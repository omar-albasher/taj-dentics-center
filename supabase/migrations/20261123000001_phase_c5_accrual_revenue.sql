-- ============================================================================
-- Phase C5 — Accrual Revenue Recognition & Reconciliation
-- Migration: supabase/migrations/20261123000001_phase_c5_accrual_revenue.sql
-- Description:
--   0. Add completed_at timestamp column to enrollments for true temporal as-of tracking.
--   1. Partial index on regular closed sessions for performant delivery counting.
--   2. Administrative cohort completion RPC with future session guard & p_force override.
--   3. True temporal As-Of Accrual revenue recognition report (get_accrual_revenue_report).
--   4. Period movement reconciliation bridge with independent cash refunds (get_accrual_reconciliation).
-- Security:
--   Security definer, search_path pinned to public, pg_temp.
--   Restricted to admin role via c1_is_admin().
--   EXECUTE revoked from PUBLIC and anon; granted to authenticated and service_role.
-- Rebuild-safe: CREATE OR REPLACE + IF NOT EXISTS only.
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- 0. Schema enhancement: completed_at on enrollments
-- ----------------------------------------------------------------------------
ALTER TABLE public.enrollments
  ADD COLUMN IF NOT EXISTS completed_at timestamp with time zone;

-- ----------------------------------------------------------------------------
-- 1. Performance index on regular closed sessions
-- ----------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_sessions_cohort_status_closed
  ON public.sessions (cohort_id, status, closed_at)
  WHERE is_extra = false;

-- ----------------------------------------------------------------------------
-- 2. Complete Cohort RPC
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.complete_cohort(
  p_cohort_id uuid,
  p_force boolean DEFAULT false
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_cohort record;
  v_open_sessions_count int := 0;
  v_closed_count int := 0;
BEGIN
  -- 1. Security guard: Admin only
  IF NOT public.c1_is_admin() THEN
    RAISE EXCEPTION 'غير مصرّح: إقفال الفوج متاح لمدير المركز فقط'
      USING ERRCODE = 'P0001';
  END IF;

  -- 2. Verify cohort exists
  SELECT id, name, is_active
  INTO v_cohort
  FROM public.cohorts
  WHERE id = p_cohort_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'الفوج غير موجود'
      USING ERRCODE = 'P0002';
  END IF;

  -- 3. Check remaining active enrollments
  SELECT count(*)
  INTO v_closed_count
  FROM public.enrollments
  WHERE cohort_id = p_cohort_id
    AND lifecycle_status = 'active';

  -- 4. Safe idempotent early return if cohort is already deactivated and no active enrollments remain
  IF NOT v_cohort.is_active AND v_closed_count = 0 THEN
    RETURN jsonb_build_object(
      'cohort_id', p_cohort_id,
      'cohort_name', v_cohort.name,
      'status', 'already_completed',
      'is_active', false,
      'closed_enrollments', 0,
      'message', 'الفوج مقفل مسبقاً'
    );
  END IF;

  -- 5. Guard against unclosed/future sessions unless p_force is true (evaluated before any actual closure)
  IF NOT p_force THEN
    SELECT count(*)
    INTO v_open_sessions_count
    FROM public.sessions
    WHERE cohort_id = p_cohort_id
      AND is_extra = false
      AND status IN ('scheduled', 'open');

    IF v_open_sessions_count > 0 THEN
      RAISE EXCEPTION 'لا يمكن إقفال الفوج: توجد % جلسة مجدولة أو جارية لم تُغلق بعد. استخدم خيار التجاوز الإداري (p_force)', v_open_sessions_count
        USING ERRCODE = 'P0004';
    END IF;
  END IF;

  -- 6. Deactivate cohort
  UPDATE public.cohorts
  SET is_active = false
  WHERE id = p_cohort_id;

  -- 7. Set session config to satisfy trg_fn_enforce_withdrawal_rpc
  PERFORM set_config('c1.withdrawal_rpc', 'on', true);

  -- 8. Mark active enrollments as completed with timestamp
  WITH updated AS (
    UPDATE public.enrollments
    SET lifecycle_status = 'completed',
        completed_at = now()
    WHERE cohort_id = p_cohort_id
      AND lifecycle_status = 'active'
    RETURNING id
  )
  SELECT count(*) INTO v_closed_count FROM updated;

  -- 9. Restore session config
  PERFORM set_config('c1.withdrawal_rpc', 'off', true);

  RETURN jsonb_build_object(
    'cohort_id', p_cohort_id,
    'cohort_name', v_cohort.name,
    'status', 'completed',
    'is_active', false,
    'closed_enrollments', v_closed_count,
    'message', 'تم إقفال الفوج والتسجيلات بنجاح'
  );
END;
$$;

-- ----------------------------------------------------------------------------
-- 3. As-Of Accrual Revenue Report (True Temporal Calculation)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_accrual_revenue_report(
  p_as_of date
) RETURNS TABLE (
  cohort_id uuid,
  cohort_name text,
  course_name text,
  total_course_sessions int,
  enrollment_id uuid,
  trainee_id uuid,
  trainee_name text,
  currency text,
  lifecycle_status text,
  enrolled_at timestamptz,
  net_due numeric,
  net_paid numeric,
  sessions_prior int,
  planned_remaining int,
  delivered_since_enrolled int,
  completion_ratio numeric,
  earned_revenue numeric,
  unearned_revenue numeric,
  accrued_receivables numeric
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
#variable_conflict use_column
DECLARE
  v_cutoff timestamptz;
BEGIN
  -- 1. Security guard: Admin only
  IF NOT public.c1_is_admin() THEN
    RAISE EXCEPTION 'غير مصرّح: تقارير الاستحقاق متاحة لمدير المركز فقط'
      USING ERRCODE = 'P0001';
  END IF;

  IF p_as_of IS NULL THEN
    RAISE EXCEPTION 'تاريخ الاستحقاق مطلوب'
      USING ERRCODE = 'P0002';
  END IF;

  -- Cutoff: end of business day in Damascus timezone
  -- Note: Assumes payments.currency = enrollments.currency (system enforces single-currency per enrollment).
  v_cutoff := ((p_as_of + 1)::text || ' 00:00:00 Asia/Damascus')::timestamptz;

  RETURN QUERY
  WITH enrollments_base AS (
    SELECT
      e.id AS enr_id,
      e.cohort_id AS enr_cohort_id,
      e.trainee_id AS enr_trainee_id,
      coalesce(t.full_name_ar, t.full_name_en, u.full_name, 'متدرب')::text AS tr_name,
      e.currency::text AS enr_currency,
      e.enrolled_at AS enr_date,
      e.lifecycle_status::text AS raw_lifecycle,
      e.completed_at AS raw_completed_at,
      e.total_due AS raw_total_due,
      -- discount_amount already includes referral_discount_amount (A5 design)
      e.discount_amount AS raw_discount,
      c.id AS crs_id,
      c.name::text AS crs_name,
      co.name::text AS coh_name,
      c.total_sessions AS crs_total_sessions
    FROM public.enrollments e
    JOIN public.cohorts co ON co.id = e.cohort_id
    JOIN public.courses c ON c.id = co.course_id
    JOIN public.trainees t ON t.id = e.trainee_id
    LEFT JOIN public.users u ON u.id = t.user_id
    WHERE e.enrolled_at < v_cutoff
  ),
  -- Temporal payments as of cutoff
  payments_asof AS (
    SELECT
      p.enrollment_id,
      coalesce(sum(p.amount), 0.00) AS sum_payments
    FROM public.payments p
    WHERE p.paid_at < v_cutoff
    GROUP BY p.enrollment_id
  ),
  -- Temporal refunds as of cutoff
  refunds_asof AS (
    SELECT
      p.enrollment_id,
      coalesce(sum(rfnd.amount), 0.00) AS sum_refunds
    FROM public.payment_refunds rfnd
    JOIN public.payments p ON p.id = rfnd.payment_id
    WHERE rfnd.created_at < v_cutoff
    GROUP BY p.enrollment_id
  ),
  -- Temporal fee adjustments as of cutoff
  adjustments_asof AS (
    SELECT
      fa.enrollment_id,
      coalesce(sum(fa.amount), 0.00) AS sum_adjustments
    FROM public.fee_adjustments fa
    WHERE fa.adjusted_at < v_cutoff
    GROUP BY fa.enrollment_id
  ),
  -- All withdrawals
  withdrawals_all AS (
    SELECT
      ew.enrollment_id,
      ew.due_amount,
      ew.net_due_before,
      ew.withdrawn_at
    FROM public.enrollment_withdrawals ew
  ),
  -- Temporal withdrawal snapshot: withdrawn prior to cutoff
  withdrawal_asof AS (
    SELECT DISTINCT ON (wa.enrollment_id)
      wa.enrollment_id, wa.due_amount, wa.net_due_before, wa.withdrawn_at
    FROM withdrawals_all wa
    WHERE wa.withdrawn_at < v_cutoff
    ORDER BY wa.enrollment_id, wa.withdrawn_at DESC
  ),
  -- Future withdrawal snapshot: withdrawn at or after cutoff (for net_due_before recovery)
  withdrawal_future AS (
    SELECT DISTINCT ON (wf.enrollment_id)
      wf.enrollment_id, wf.due_amount, wf.net_due_before, wf.withdrawn_at
    FROM withdrawals_all wf
    WHERE wf.withdrawn_at >= v_cutoff
    ORDER BY wf.enrollment_id, wf.withdrawn_at ASC
  ),
  -- Filtered regular sessions (eliminates Cartesian product completely)
  session_metrics AS (
    SELECT
      eb.enr_id,
      count(*) FILTER (
        WHERE s.closed_at < eb.enr_date
      )::int AS cnt_prior,
      count(*) FILTER (
        WHERE s.closed_at >= eb.enr_date
          AND s.closed_at < v_cutoff
          AND (w.withdrawn_at IS NULL OR s.closed_at <= w.withdrawn_at)
      )::int AS cnt_delivered
    FROM enrollments_base eb
    LEFT JOIN withdrawal_asof w ON w.enrollment_id = eb.enr_id
    LEFT JOIN public.sessions s
      ON s.cohort_id = eb.enr_cohort_id
     AND s.is_extra = false
     AND s.status = 'closed'
     AND s.closed_at < v_cutoff
    GROUP BY eb.enr_id
  ),
  calculated AS (
    SELECT
      eb.enr_cohort_id AS c_id,
      eb.coh_name AS c_name,
      eb.crs_name AS cr_name,
      eb.crs_total_sessions AS t_sessions,
      eb.enr_id AS e_id,
      eb.enr_trainee_id AS t_id,
      eb.tr_name AS tr_n,
      eb.enr_currency AS curr,
      eb.enr_date AS e_date,
      -- Temporal lifecycle status as of cutoff
      CASE
        WHEN w.withdrawn_at IS NOT NULL THEN 'withdrawn'
        WHEN eb.raw_completed_at IS NOT NULL AND eb.raw_completed_at < v_cutoff THEN 'completed'
        ELSE 'active'
      END AS l_status,
      -- Temporal net_due as of cutoff
      CASE
        WHEN w.withdrawn_at IS NOT NULL THEN GREATEST(0.00, w.due_amount)
        WHEN wf.withdrawn_at IS NOT NULL THEN GREATEST(0.00, wf.net_due_before)
        ELSE GREATEST(0.00, eb.raw_total_due - eb.raw_discount + coalesce(fa.sum_adjustments, 0.00))
      END AS n_due,
      -- Temporal net_paid as of cutoff
      (coalesce(pa.sum_payments, 0.00) - coalesce(ra.sum_refunds, 0.00)) AS n_paid,
      sm.cnt_prior AS s_prior,
      GREATEST(1, eb.crs_total_sessions - sm.cnt_prior)::int AS p_remaining,
      sm.cnt_delivered AS s_delivered,
      -- Ratio calculation
      CASE
        WHEN w.withdrawn_at IS NOT NULL THEN 1.0000
        WHEN eb.raw_completed_at IS NOT NULL AND eb.raw_completed_at < v_cutoff THEN 1.0000
        ELSE LEAST(1.0000, round(sm.cnt_delivered::numeric / GREATEST(1, eb.crs_total_sessions - sm.cnt_prior)::numeric, 4))
      END AS comp_ratio
    FROM enrollments_base eb
    JOIN session_metrics sm ON sm.enr_id = eb.enr_id
    LEFT JOIN payments_asof pa ON pa.enrollment_id = eb.enr_id
    LEFT JOIN refunds_asof ra ON ra.enrollment_id = eb.enr_id
    LEFT JOIN adjustments_asof fa ON fa.enrollment_id = eb.enr_id
    LEFT JOIN withdrawal_asof w ON w.enrollment_id = eb.enr_id
    LEFT JOIN withdrawal_future wf ON wf.enrollment_id = eb.enr_id
  )
  SELECT
    c_id AS cohort_id,
    c_name AS cohort_name,
    cr_name AS course_name,
    t_sessions AS total_course_sessions,
    e_id AS enrollment_id,
    t_id AS trainee_id,
    tr_n AS trainee_name,
    curr AS currency,
    l_status AS lifecycle_status,
    e_date AS enrolled_at,
    n_due AS net_due,
    n_paid AS net_paid,
    s_prior AS sessions_prior,
    p_remaining AS planned_remaining,
    s_delivered AS delivered_since_enrolled,
    comp_ratio AS completion_ratio,
    -- Earned Revenue
    round(n_due * comp_ratio, 2) AS earned_revenue,
    -- General rule: unearned = max(0, net_paid - earned)
    GREATEST(0.00, round(n_paid - round(n_due * comp_ratio, 2), 2)) AS unearned_revenue,
    -- General rule: accrued = max(0, earned - net_paid)
    GREATEST(0.00, round(round(n_due * comp_ratio, 2) - n_paid, 2)) AS accrued_receivables
  FROM calculated
  ORDER BY curr, c_name, tr_n;
END;
$$;

-- ----------------------------------------------------------------------------
-- 4. Accrual Reconciliation Bridge (Movement between p_from and p_to)
-- Note: The reconciliation bridge (earned + unearned - accrued = net_paid) is
-- a structural accounting identity verifying temporal window consistency and
-- refund linkages, rather than an independent economic proof.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_accrual_reconciliation(
  p_from date,
  p_to date
) RETURNS TABLE (
  currency text,
  opening_unearned numeric,
  opening_accrued numeric,
  opening_earned_cumulative numeric,
  closing_unearned numeric,
  closing_accrued numeric,
  closing_earned_cumulative numeric,
  delta_unearned numeric,
  delta_accrued numeric,
  period_earned_revenue numeric,
  period_cash_payments numeric,
  period_cash_refunds numeric,
  period_cash_net numeric,
  reconciliation_diff numeric,
  is_reconciled boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
#variable_conflict use_column
DECLARE
  v_start timestamptz;
  v_end timestamptz;
  v_prior_date date;
BEGIN
  -- 1. Security guard: Admin only
  IF NOT public.c1_is_admin() THEN
    RAISE EXCEPTION 'غير مصرّح: تقارير تسوية الاستحقاق متاحة لمدير المركز فقط'
      USING ERRCODE = 'P0001';
  END IF;

  IF p_from IS NULL OR p_to IS NULL THEN
    RAISE EXCEPTION 'تاريخ البداية والنهاية مطلوبان'
      USING ERRCODE = 'P0002';
  END IF;

  IF p_to < p_from THEN
    RAISE EXCEPTION 'تاريخ النهاية يجب أن يكون بعد تاريخ البداية'
      USING ERRCODE = 'P0003';
  END IF;

  -- Period bounds anchored to Damascus timezone (matching C4 exactly)
  v_start := (p_from::text || ' 00:00:00 Asia/Damascus')::timestamptz;
  v_end := ((p_to + 1)::text || ' 00:00:00 Asia/Damascus')::timestamptz;
  v_prior_date := p_from - 1;

  RETURN QUERY
  WITH currencies AS (
    SELECT 'SYP'::text AS cur
    UNION ALL
    SELECT 'USD'::text AS cur
  ),
  opening_as_of AS (
    SELECT
      r.currency AS cur,
      coalesce(sum(r.unearned_revenue), 0.00) AS op_unearned,
      coalesce(sum(r.accrued_receivables), 0.00) AS op_accrued,
      coalesce(sum(r.earned_revenue), 0.00) AS op_earned
    FROM public.get_accrual_revenue_report(v_prior_date) r
    GROUP BY r.currency
  ),
  closing_as_of AS (
    SELECT
      r.currency AS cur,
      coalesce(sum(r.unearned_revenue), 0.00) AS cl_unearned,
      coalesce(sum(r.accrued_receivables), 0.00) AS cl_accrued,
      coalesce(sum(r.earned_revenue), 0.00) AS cl_earned
    FROM public.get_accrual_revenue_report(p_to) r
    GROUP BY r.currency
  ),
  -- Cash in: payments occurring strictly within period
  cash_in AS (
    SELECT
      p.currency::text AS cur,
      coalesce(sum(p.amount), 0.00) AS gross_in
    FROM public.payments p
    WHERE p.paid_at >= v_start
      AND p.paid_at < v_end
    GROUP BY p.currency::text
  ),
  -- Cash out: refunds occurring strictly within period (independent of payment date)
  cash_out AS (
    SELECT
      p.currency::text AS cur,
      coalesce(sum(rfnd.amount), 0.00) AS refunds_out
    FROM public.payment_refunds rfnd
    JOIN public.payments p ON p.id = rfnd.payment_id
    WHERE rfnd.created_at >= v_start
      AND rfnd.created_at < v_end
    GROUP BY p.currency::text
  ),
  assembled AS (
    SELECT
      c.cur,
      coalesce(o.op_unearned, 0.00) AS op_unearned,
      coalesce(o.op_accrued, 0.00) AS op_accrued,
      coalesce(o.op_earned, 0.00) AS op_earned,
      coalesce(cl.cl_unearned, 0.00) AS cl_unearned,
      coalesce(cl.cl_accrued, 0.00) AS cl_accrued,
      coalesce(cl.cl_earned, 0.00) AS cl_earned,
      (coalesce(cl.cl_unearned, 0.00) - coalesce(o.op_unearned, 0.00)) AS d_unearned,
      (coalesce(cl.cl_accrued, 0.00) - coalesce(o.op_accrued, 0.00)) AS d_accrued,
      (coalesce(cl.cl_earned, 0.00) - coalesce(o.op_earned, 0.00)) AS p_earned,
      coalesce(cin.gross_in, 0.00) AS p_cash_in,
      coalesce(cout.refunds_out, 0.00) AS p_cash_out,
      (coalesce(cin.gross_in, 0.00) - coalesce(cout.refunds_out, 0.00)) AS p_cash_net
    FROM currencies c
    LEFT JOIN opening_as_of o ON o.cur = c.cur
    LEFT JOIN closing_as_of cl ON cl.cur = c.cur
    LEFT JOIN cash_in cin ON cin.cur = c.cur
    LEFT JOIN cash_out cout ON cout.cur = c.cur
  )
  SELECT
    cur AS currency,
    op_unearned AS opening_unearned,
    op_accrued AS opening_accrued,
    op_earned AS opening_earned_cumulative,
    cl_unearned AS closing_unearned,
    cl_accrued AS closing_accrued,
    cl_earned AS closing_earned_cumulative,
    d_unearned AS delta_unearned,
    d_accrued AS delta_accrued,
    p_earned AS period_earned_revenue,
    p_cash_in AS period_cash_payments,
    p_cash_out AS period_cash_refunds,
    p_cash_net AS period_cash_net,
    -- Golden Bridge Reconcile Diff: (Period Cash Net - Delta Unearned + Delta Accrued) - Period Earned
    round((p_cash_net - d_unearned + d_accrued) - p_earned, 2) AS reconciliation_diff,
    -- Is Reconciled: diff is 0.00
    (abs((p_cash_net - d_unearned + d_accrued) - p_earned) < 0.01) AS is_reconciled
  FROM assembled
  ORDER BY cur;
END;
$$;

-- ----------------------------------------------------------------------------
-- 5. Grants and Security
-- ----------------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.complete_cohort(uuid, boolean) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_accrual_revenue_report(date) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_accrual_reconciliation(date, date) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.complete_cohort(uuid, boolean) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_accrual_revenue_report(date) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_accrual_reconciliation(date, date) TO authenticated, service_role;

COMMIT;
