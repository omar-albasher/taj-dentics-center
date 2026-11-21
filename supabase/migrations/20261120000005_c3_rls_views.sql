-- ============================================================================
-- Phase C3.5 — RLS policies + admin read views
-- ============================================================================
-- Access model (salary, advances, bonuses and trainer fees are payroll data):
--   * every C3 table is admin-only (ALL), matching the C2 custody precedent;
--   * no policy for reception/trainer/trainee => zero rows, zero writes;
--   * the C3 RPCs in 20261120000006 are SECURITY DEFINER + admin-checked, so
--     they keep working for admins and refuse everyone else.
--
-- Every view is security_invoker = 'true' (lesson from the D5 audit): RLS of
-- the caller applies, so a non-admin gets an empty result even though the
-- view itself is granted.
--
-- Rebuild-safe: policies dropped and recreated; views replaced.
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- 1. Policies — one admin_all per C3 table
-- ----------------------------------------------------------------------------
DROP POLICY IF EXISTS admin_all ON public.trainer_compensation_agreements;
CREATE POLICY admin_all ON public.trainer_compensation_agreements
  FOR ALL TO authenticated
  USING (public.c1_is_admin()) WITH CHECK (public.c1_is_admin());

DROP POLICY IF EXISTS admin_all ON public.cohort_trainer_rate_snapshots;
CREATE POLICY admin_all ON public.cohort_trainer_rate_snapshots
  FOR ALL TO authenticated
  USING (public.c1_is_admin()) WITH CHECK (public.c1_is_admin());

DROP POLICY IF EXISTS admin_all ON public.staff_compensation;
CREATE POLICY admin_all ON public.staff_compensation
  FOR ALL TO authenticated
  USING (public.c1_is_admin()) WITH CHECK (public.c1_is_admin());

DROP POLICY IF EXISTS admin_all ON public.staff_advances;
CREATE POLICY admin_all ON public.staff_advances
  FOR ALL TO authenticated
  USING (public.c1_is_admin()) WITH CHECK (public.c1_is_admin());

DROP POLICY IF EXISTS admin_all ON public.staff_bonuses;
CREATE POLICY admin_all ON public.staff_bonuses
  FOR ALL TO authenticated
  USING (public.c1_is_admin()) WITH CHECK (public.c1_is_admin());

DROP POLICY IF EXISTS admin_all ON public.staff_referrals;
CREATE POLICY admin_all ON public.staff_referrals
  FOR ALL TO authenticated
  USING (public.c1_is_admin()) WITH CHECK (public.c1_is_admin());

DROP POLICY IF EXISTS admin_all ON public.trainer_dues;
CREATE POLICY admin_all ON public.trainer_dues
  FOR ALL TO authenticated
  USING (public.c1_is_admin()) WITH CHECK (public.c1_is_admin());

DROP POLICY IF EXISTS admin_all ON public.trainer_payments;
CREATE POLICY admin_all ON public.trainer_payments
  FOR ALL TO authenticated
  USING (public.c1_is_admin()) WITH CHECK (public.c1_is_admin());

DROP POLICY IF EXISTS admin_all ON public.payroll_runs;
CREATE POLICY admin_all ON public.payroll_runs
  FOR ALL TO authenticated
  USING (public.c1_is_admin()) WITH CHECK (public.c1_is_admin());

DROP POLICY IF EXISTS admin_all ON public.payroll_lines;
CREATE POLICY admin_all ON public.payroll_lines
  FOR ALL TO authenticated
  USING (public.c1_is_admin()) WITH CHECK (public.c1_is_admin());

-- ----------------------------------------------------------------------------
-- 2. Cohort rate snapshot — what the admin locks / audits
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW public.cohort_trainer_rates_v
WITH (security_invoker = 'true') AS
SELECT
  s.cohort_id,
  c.name          AS cohort_name,
  c.starts_at,
  s.trainer_id,
  u.full_name     AS trainer_name,
  s.course_id,
  co.name         AS course_name,
  s.rate_percent,
  s.locked_on,
  s.locked_at,
  s.agreement_id,
  a.effective_from AS agreement_from,
  a.effective_to   AS agreement_to
FROM public.cohort_trainer_rate_snapshots s
JOIN public.cohorts c  ON c.id = s.cohort_id
JOIN public.courses co ON co.id = s.course_id
JOIN public.users u    ON u.id = s.trainer_id
LEFT JOIN public.trainer_compensation_agreements a ON a.id = s.agreement_id;

COMMENT ON VIEW public.cohort_trainer_rates_v IS
  'C3 frozen trainer rate per cohort. rate_percent IS NULL = needs admin locking before dues generation.';

-- ----------------------------------------------------------------------------
-- 3. Trainer dues — with paid total and remaining
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW public.trainer_dues_v
WITH (security_invoker = 'true') AS
SELECT
  d.id,
  d.trainer_id,
  u.full_name AS trainer_name,
  d.cohort_id,
  c.name      AS cohort_name,
  d.period_start,
  d.period_end,
  d.currency,
  d.basis_amount,
  d.rate_percent,
  d.amount,
  d.status,
  COALESCE(paid.paid_total, 0)::numeric(12,2) AS paid_total,
  (d.amount - COALESCE(paid.paid_total, 0))::numeric(12,2) AS remaining,
  d.created_by,
  d.created_at
FROM public.trainer_dues d
JOIN public.users u   ON u.id = d.trainer_id
JOIN public.cohorts c ON c.id = d.cohort_id
LEFT JOIN (
  SELECT due_id, SUM(amount) AS paid_total
  FROM public.trainer_payments
  GROUP BY due_id
) paid ON paid.due_id = d.id;

COMMENT ON VIEW public.trainer_dues_v IS
  'C3 trainer dues with derived paid/remaining. remaining is never stored.';

-- ----------------------------------------------------------------------------
-- 4. Trainer payments — payout trail back to the custody expense
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW public.trainer_payments_v
WITH (security_invoker = 'true') AS
SELECT
  p.id,
  p.due_id,
  d.trainer_id,
  u.full_name AS trainer_name,
  d.cohort_id,
  c.name      AS cohort_name,
  d.period_start,
  d.period_end,
  p.amount,
  p.currency,
  p.account_id,
  fa.name_ar  AS account_name,
  p.expense_id,
  p.paid_at,
  p.performed_by
FROM public.trainer_payments p
JOIN public.trainer_dues d ON d.id = p.due_id
JOIN public.users u        ON u.id = d.trainer_id
JOIN public.cohorts c      ON c.id = d.cohort_id
JOIN public.financial_accounts fa ON fa.id = p.account_id;

COMMENT ON VIEW public.trainer_payments_v IS
  'C3 trainer payouts. expense_id is the custody-ledger outflow that actually paid it.';

-- ----------------------------------------------------------------------------
-- 5. Staff compensation — effective-dated salary rows
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW public.staff_compensation_v
WITH (security_invoker = 'true') AS
SELECT
  s.id,
  s.user_id,
  u.full_name,
  u.role,
  u.is_active,
  s.monthly_salary,
  s.currency,
  s.commission_rate_percent,
  s.effective_from,
  s.effective_to,
  s.notes,
  s.created_at
FROM public.staff_compensation s
JOIN public.users u ON u.id = s.user_id;

COMMENT ON VIEW public.staff_compensation_v IS
  'C3 staff salary/commission history for the admin UI.';

-- ----------------------------------------------------------------------------
-- 6. Payroll — lines with their run and expense
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW public.payroll_v
WITH (security_invoker = 'true') AS
SELECT
  l.id            AS line_id,
  r.id            AS run_id,
  r.month,
  r.status        AS run_status,
  l.user_id,
  u.full_name,
  l.currency,
  l.base_salary,
  l.commission_amount,
  l.bonus_amount,
  l.advances_deducted,
  l.net_amount,
  l.expense_id,
  r.created_at    AS run_created_at,
  r.approved_by,
  r.approved_at
FROM public.payroll_lines l
JOIN public.payroll_runs r ON r.id = l.run_id
JOIN public.users u        ON u.id = l.user_id;

COMMENT ON VIEW public.payroll_v IS
  'C3 payroll lines joined with run status; net_amount is the enforced formula result.';

-- ----------------------------------------------------------------------------
-- 7. Privileges (views are safe to grant: security_invoker + table RLS)
-- ----------------------------------------------------------------------------
GRANT SELECT ON public.cohort_trainer_rates_v TO authenticated;
GRANT SELECT ON public.trainer_dues_v TO authenticated;
GRANT SELECT ON public.trainer_payments_v TO authenticated;
GRANT SELECT ON public.staff_compensation_v TO authenticated;
GRANT SELECT ON public.payroll_v TO authenticated;
GRANT ALL ON public.cohort_trainer_rates_v TO service_role;
GRANT ALL ON public.trainer_dues_v TO service_role;
GRANT ALL ON public.trainer_payments_v TO service_role;
GRANT ALL ON public.staff_compensation_v TO service_role;
GRANT ALL ON public.payroll_v TO service_role;

COMMIT;
