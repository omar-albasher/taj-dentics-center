-- ============================================================================
-- Phase C3.3 — Trainer dues, trainer payouts, and monthly payroll
-- ============================================================================
-- Management decisions (2026-11-20):
--   * Trainer due = percentage of net collected fees (payments - refunds)
--     inside the period, per currency, no FX conversion.
--   * Percentage comes from cohort_trainer_rate_snapshots (frozen at cohort
--     creation), never re-read from the agreement at payout time.
--   * Trainer of record for a period = cohorts.trainer_id at generation time;
--     the C3 audit triggers record who generated and who was credited.
--   * Trainer payouts and payroll are registered as `expenses` rows so the C2
--     triggers move the custody ledger automatically and existing expense
--     reports keep working unchanged.
--
-- RLS is enabled here with no policies => deny-all until 20261120000005.
--
-- Rebuild-safe: idempotent DDL. staff_advances / staff_bonuses columns are
-- added at the end because payroll_lines must exist first.
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- 1. Trainer dues — one row per cohort, month and currency
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.trainer_dues (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    trainer_id uuid NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
    cohort_id uuid NOT NULL REFERENCES public.cohorts(id) ON DELETE CASCADE,
    period_start date NOT NULL,
    period_end date NOT NULL,
    currency public.currency_type NOT NULL,
    basis_amount numeric(12,2) NOT NULL DEFAULT 0 CHECK (basis_amount >= 0),
    rate_percent numeric(5,2) NOT NULL CHECK (rate_percent >= 0 AND rate_percent <= 100),
    amount numeric(12,2) NOT NULL CHECK (amount >= 0),
    status text NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'paid', 'cancelled')),
    created_by uuid REFERENCES auth.users(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT td_period_ck CHECK (period_end >= period_start),
    CONSTRAINT td_amount_ck CHECK (amount = round(basis_amount * rate_percent / 100.0, 2)),
    CONSTRAINT td_unique_period UNIQUE (cohort_id, period_start, currency)
);

COMMENT ON TABLE public.trainer_dues IS
  'C3 trainer due per cohort/month/currency. basis_amount is net collected fees; amount is fixed by td_amount_ck so a manual edit cannot drift from the formula.';

CREATE INDEX IF NOT EXISTS idx_td_trainer_status
  ON public.trainer_dues (trainer_id, status);
CREATE INDEX IF NOT EXISTS idx_td_cohort
  ON public.trainer_dues (cohort_id);

ALTER TABLE public.trainer_dues ENABLE ROW LEVEL SECURITY;

-- ----------------------------------------------------------------------------
-- 2. Trainer payments — actual payout tied to a due and an expense
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.trainer_payments (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    due_id uuid NOT NULL REFERENCES public.trainer_dues(id) ON DELETE RESTRICT,
    amount numeric(12,2) NOT NULL CHECK (amount > 0),
    currency public.currency_type NOT NULL,
    account_id uuid NOT NULL REFERENCES public.financial_accounts(id) ON DELETE RESTRICT,
    paid_at timestamptz NOT NULL DEFAULT now(),
    expense_id uuid UNIQUE REFERENCES public.expenses(id) ON DELETE RESTRICT,
    performed_by uuid REFERENCES auth.users(id),
    created_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.trainer_payments IS
  'C3 trainer payout. expense_id links the custody-ledger outflow; account_id mirrors the expense account so account balances stay reconcilable.';

CREATE INDEX IF NOT EXISTS idx_tp_due
  ON public.trainer_payments (due_id);
CREATE INDEX IF NOT EXISTS idx_tp_account
  ON public.trainer_payments (account_id);

ALTER TABLE public.trainer_payments ENABLE ROW LEVEL SECURITY;

-- ----------------------------------------------------------------------------
-- 3. Payroll runs — one run per calendar month
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.payroll_runs (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    month date NOT NULL UNIQUE,
    status text NOT NULL DEFAULT 'draft'
        CHECK (status IN ('draft', 'approved', 'paid')),
    notes text,
    created_by uuid REFERENCES auth.users(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    approved_by uuid REFERENCES auth.users(id),
    approved_at timestamptz,
    CONSTRAINT pr_month_ck CHECK (month = date_trunc('month', month)::date),
    CONSTRAINT pr_approved_ck CHECK (status = 'draft' OR approved_by IS NOT NULL)
);

COMMENT ON TABLE public.payroll_runs IS
  'C3 monthly payroll run. status draft -> approved -> paid; approved_by is mandatory once it leaves draft.';

ALTER TABLE public.payroll_runs ENABLE ROW LEVEL SECURITY;

-- ----------------------------------------------------------------------------
-- 4. Payroll lines — one per employee and currency inside a run
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.payroll_lines (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    run_id uuid NOT NULL REFERENCES public.payroll_runs(id) ON DELETE CASCADE,
    user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
    currency public.currency_type NOT NULL,
    base_salary numeric(12,2) NOT NULL DEFAULT 0 CHECK (base_salary >= 0),
    commission_amount numeric(12,2) NOT NULL DEFAULT 0 CHECK (commission_amount >= 0),
    bonus_amount numeric(12,2) NOT NULL DEFAULT 0 CHECK (bonus_amount >= 0),
    advances_deducted numeric(12,2) NOT NULL DEFAULT 0 CHECK (advances_deducted >= 0),
    net_amount numeric(12,2) NOT NULL,
    expense_id uuid UNIQUE REFERENCES public.expenses(id) ON DELETE SET NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pl_unique_employee UNIQUE (run_id, user_id, currency),
    CONSTRAINT pl_net_ck CHECK (net_amount = base_salary + commission_amount + bonus_amount - advances_deducted),
    CONSTRAINT pl_net_nonnegative_ck CHECK (net_amount >= 0)
);

COMMENT ON TABLE public.payroll_lines IS
  'C3 payroll line. net_amount is enforced by pl_net_ck; each line becomes one salary expense when the run is paid.';

CREATE INDEX IF NOT EXISTS idx_pl_user
  ON public.payroll_lines (user_id);

ALTER TABLE public.payroll_lines ENABLE ROW LEVEL SECURITY;

-- ----------------------------------------------------------------------------
-- 5. Back-reference from the payroll inputs to the line that consumed them
--    (added last: payroll_lines must exist first)
-- ----------------------------------------------------------------------------
ALTER TABLE public.staff_advances
  ADD COLUMN IF NOT EXISTS payroll_line_id uuid
  REFERENCES public.payroll_lines(id) ON DELETE SET NULL;

ALTER TABLE public.staff_bonuses
  ADD COLUMN IF NOT EXISTS payroll_line_id uuid
  REFERENCES public.payroll_lines(id) ON DELETE SET NULL;

COMMENT ON COLUMN public.staff_advances.payroll_line_id IS
  'C3 payroll line that deducted this advance. NULL while the advance is still open.';
COMMENT ON COLUMN public.staff_bonuses.payroll_line_id IS
  'C3 payroll line that paid this bonus. NULL while the bonus has not been paid yet.';

CREATE INDEX IF NOT EXISTS idx_sa_payroll_line
  ON public.staff_advances (payroll_line_id)
  WHERE payroll_line_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_sb_payroll_line
  ON public.staff_bonuses (payroll_line_id)
  WHERE payroll_line_id IS NOT NULL;

-- ----------------------------------------------------------------------------
-- 6. Privileges (row visibility is controlled by 20261120000005 policies)
-- ----------------------------------------------------------------------------
GRANT SELECT, INSERT, UPDATE, DELETE ON public.trainer_dues TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.trainer_payments TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.payroll_runs TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.payroll_lines TO authenticated;
GRANT ALL ON public.trainer_dues TO service_role;
GRANT ALL ON public.trainer_payments TO service_role;
GRANT ALL ON public.payroll_runs TO service_role;
GRANT ALL ON public.payroll_lines TO service_role;

COMMIT;
