-- ============================================================================
-- Migration: 20261116000003_phase_d5_1_remediation.sql
-- Description: Remediation for Phase D5.1 Permissions Hardening
--
-- Fixes:
--   1. Harden reception_insert policy to bind performed_by = auth.uid()
--   2. Drop unintended zero-arg overload of c1_can_read_financials()
--   3. Retain and align canonical c1_can_read_financials(uuid) with strict is_active = true
--   4. Align c1_is_staff() and c1_staff_role() with strict is_active = true
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Bind performed_by = auth.uid() in reception_insert policy
-- ----------------------------------------------------------------------------
-- NOTE: reception_insert, get_user_role() and the user_role/payment_method enums
-- are part of the live-only baseline (see #47), not created by this repository.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_policy
    WHERE polrelid = 'public.payments'::regclass AND polname = 'reception_insert'
  ) THEN
    ALTER POLICY reception_insert ON public.payments
    WITH CHECK (
      (get_user_role() = 'reception'::user_role) AND
      (performed_by = auth.uid()) AND
      (method IN ('cash'::payment_method, 'sham_cash'::payment_method, 'hawala'::payment_method, 'transfer'::payment_method))
    );
  END IF;
END $$;

-- ----------------------------------------------------------------------------
-- 2. Drop unintended zero-arg overload of c1_can_read_financials()
-- ----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.c1_can_read_financials();

-- ----------------------------------------------------------------------------
-- 3. Restore and harden canonical c1_can_read_financials(uuid)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.c1_can_read_financials(p_trainee_user_id uuid DEFAULT NULL)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT
    -- Trusted contexts: direct DB owner, pg_cron and service_role must never be row-filtered
    auth.role() IS NULL
    OR auth.role() = 'service_role'
    OR public.c1_is_staff()
    OR
    -- Trainees can only read their own financial records
    (
      p_trainee_user_id IS NOT NULL
      AND auth.uid() = p_trainee_user_id
      AND EXISTS (
        SELECT 1 FROM public.users u
        WHERE u.id = auth.uid()
          AND u.role = 'trainee'
          AND u.is_active = true
      )
    );
$$;

-- ----------------------------------------------------------------------------
-- 4. Align c1_is_staff() with strict is_active = true (no accountant)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.c1_is_staff()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.users
    WHERE id = auth.uid()
      AND role IN ('admin', 'reception')
      AND is_active = true
  );
$$;

-- ----------------------------------------------------------------------------
-- 5. Restore original contract of c1_staff_role()
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.c1_staff_role()
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT role::text FROM public.users
  WHERE id = auth.uid()
    AND is_active = true
  LIMIT 1;
$$;

