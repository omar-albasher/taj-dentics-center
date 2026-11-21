-- ============================================================================
-- Phase C3.2 — Staff compensation inputs (salary, advances, bonuses, referrals)
-- ============================================================================
-- Management decisions (2026-11-20):
--   * Employee monthly salary is adjustable by the admin (effective-dated).
--   * Referral commission for staff = 2.5% of net collected fees inside the
--     month; the rate is stored per referral so a future change never
--     rewrites history.
--   * Advances are paid out of a real custody account (C2), so they move cash
--     at the moment they are granted; payroll later only deducts them from net.
--   * All employee data is entered through the Admin Dashboard UI — this
--     migration defines schema only, no seed rows.
--
-- RLS is enabled here with no policies => deny-all until 20261120000005 adds
-- the admin policies. Salary data must never be readable before that.
--
-- Rebuild-safe: idempotent DDL.
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- 1. Salary + referral rate, effective-dated per employee
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.staff_compensation (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
    monthly_salary numeric(12,2) NOT NULL DEFAULT 0 CHECK (monthly_salary >= 0),
    currency public.currency_type NOT NULL DEFAULT 'SYP',
    commission_rate_percent numeric(5,2) NOT NULL DEFAULT 0
        CHECK (commission_rate_percent >= 0 AND commission_rate_percent <= 100),
    effective_from date NOT NULL,
    effective_to date,
    notes text,
    created_by uuid REFERENCES auth.users(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT sc_dates_ck CHECK (effective_to IS NULL OR effective_to >= effective_from)
);

COMMENT ON TABLE public.staff_compensation IS
  'C3 effective-dated monthly salary and referral commission rate per employee. Payroll resolves the row covering the month end.';

CREATE INDEX IF NOT EXISTS idx_sc_user_effective
  ON public.staff_compensation (user_id, effective_from DESC);

CREATE OR REPLACE FUNCTION public.fn_c3_staff_comp_overlap_guard() RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM public.staff_compensation s
    WHERE s.id <> COALESCE(NEW.id, '00000000-0000-0000-0000-000000000000'::uuid)
      AND s.user_id = NEW.user_id
      AND daterange(s.effective_from, COALESCE(s.effective_to, 'infinity'::date), '[]')
          && daterange(NEW.effective_from, COALESCE(NEW.effective_to, 'infinity'::date), '[]')
  ) THEN
    RAISE EXCEPTION 'تداخل في فترات راتب الموظف (user=%)', NEW.user_id;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_c3_sc_overlap ON public.staff_compensation;
CREATE TRIGGER trg_c3_sc_overlap
  BEFORE INSERT OR UPDATE ON public.staff_compensation
  FOR EACH ROW EXECUTE FUNCTION public.fn_c3_staff_comp_overlap_guard();

ALTER TABLE public.staff_compensation ENABLE ROW LEVEL SECURITY;

-- ----------------------------------------------------------------------------
-- 2. Advances — cash leaves a custody account when granted
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.staff_advances (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
    amount numeric(12,2) NOT NULL CHECK (amount > 0),
    currency public.currency_type NOT NULL,
    advanced_at date NOT NULL DEFAULT CURRENT_DATE,
    account_id uuid NOT NULL REFERENCES public.financial_accounts(id) ON DELETE RESTRICT,
    reason text,
    status text NOT NULL DEFAULT 'open'
        CHECK (status IN ('open', 'deducted', 'cancelled')),
    created_by uuid REFERENCES auth.users(id),
    created_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.staff_advances IS
  'C3 salary advances. account_id is mandatory: granting an advance is a real cash outflow at that moment; payroll only deducts it from net.';

CREATE INDEX IF NOT EXISTS idx_sa_user_status
  ON public.staff_advances (user_id, status);
CREATE INDEX IF NOT EXISTS idx_sa_account
  ON public.staff_advances (account_id);

ALTER TABLE public.staff_advances ENABLE ROW LEVEL SECURITY;

-- ----------------------------------------------------------------------------
-- 3. Bonuses — one bonus_month bucket per employee
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.staff_bonuses (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
    amount numeric(12,2) NOT NULL CHECK (amount > 0),
    currency public.currency_type NOT NULL,
    bonus_month date NOT NULL,
    reason text NOT NULL,
    approved_by uuid REFERENCES auth.users(id),
    created_by uuid REFERENCES auth.users(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT sb_month_ck CHECK (bonus_month = date_trunc('month', bonus_month)::date)
);

COMMENT ON TABLE public.staff_bonuses IS
  'C3 approved bonuses, bucketed per calendar month. bonus_month is always the first day of the month so payroll picks it by range.';

CREATE INDEX IF NOT EXISTS idx_sb_user_month
  ON public.staff_bonuses (user_id, bonus_month);

ALTER TABLE public.staff_bonuses ENABLE ROW LEVEL SECURITY;

-- ----------------------------------------------------------------------------
-- 4. Staff referrals — one staff member per enrollment claim
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.staff_referrals (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    enrollment_id uuid NOT NULL UNIQUE REFERENCES public.enrollments(id) ON DELETE CASCADE,
    staff_id uuid NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
    commission_rate_percent numeric(5,2) NOT NULL
        CHECK (commission_rate_percent >= 0 AND commission_rate_percent <= 100),
    created_by uuid REFERENCES auth.users(id),
    created_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.staff_referrals IS
  'C3 attribution of an enrollment to a staff member. UNIQUE(enrollment_id): no double commission for the same enrollment.';

CREATE INDEX IF NOT EXISTS idx_sref_staff
  ON public.staff_referrals (staff_id);

ALTER TABLE public.staff_referrals ENABLE ROW LEVEL SECURITY;

-- ----------------------------------------------------------------------------
-- 5. Privileges (row visibility is controlled by 20261120000005 policies)
-- ----------------------------------------------------------------------------
GRANT SELECT, INSERT, UPDATE, DELETE ON public.staff_compensation TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.staff_advances TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.staff_bonuses TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.staff_referrals TO authenticated;
GRANT ALL ON public.staff_compensation TO service_role;
GRANT ALL ON public.staff_advances TO service_role;
GRANT ALL ON public.staff_bonuses TO service_role;
GRANT ALL ON public.staff_referrals TO service_role;

COMMIT;
