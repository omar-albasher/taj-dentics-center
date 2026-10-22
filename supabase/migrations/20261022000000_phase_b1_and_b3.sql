-- ==============================================================================
-- Migration: 20261022000000_phase_b1_and_b3.sql
-- Description:
--   1. Phase B3: Monthly Financial Revenue Targets (monthly_targets table, RLS, Damascus-timezone RPCs)
--   2. Phase B1: WhatsApp Integration support (overdue_payments view updated with whatsapp_number)
-- ==============================================================================

-- 1. Phase B3: Monthly Financial Revenue Targets Table
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.monthly_targets (
    month_key text PRIMARY KEY, -- 'YYYY-MM' (e.g. '2026-10')
    target_syp numeric NOT NULL DEFAULT 0 CHECK (target_syp >= 0),
    target_usd numeric NOT NULL DEFAULT 0 CHECK (target_usd >= 0),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    updated_by uuid REFERENCES auth.users(id)
);

-- Enable Row Level Security
ALTER TABLE public.monthly_targets ENABLE ROW LEVEL SECURITY;

-- Strict Admin-only policy for monthly_targets
DROP POLICY IF EXISTS "monthly_targets_admin_only" ON public.monthly_targets;
CREATE POLICY "monthly_targets_admin_only" ON public.monthly_targets
  FOR ALL TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.users
      WHERE id = auth.uid() AND role = 'admin' AND is_active = true
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.users
      WHERE id = auth.uid() AND role = 'admin' AND is_active = true
    )
  );

-- ------------------------------------------------------------------------------
-- RPC: set_monthly_target
-- ------------------------------------------------------------------------------
-- Sets or updates the financial target for Damascus local month.
-- Restricts operation strictly to active admins and sets updated_by = auth.uid().
CREATE OR REPLACE FUNCTION public.set_monthly_target(
    p_target_syp numeric,
    p_target_usd numeric,
    p_month_key text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_month text;
    v_user_role text;
    v_res record;
BEGIN
    -- Verify caller is active admin
    SELECT role INTO v_user_role FROM public.users WHERE id = auth.uid() AND is_active = true;
    IF v_user_role IS DISTINCT FROM 'admin' THEN
        RAISE EXCEPTION 'غير مصرح: تحديد الهدف المالي مخصص لمدير النظام فقط';
    END IF;

    -- Default month_key to Damascus local month
    v_month := COALESCE(p_month_key, to_char(now() AT TIME ZONE 'Asia/Damascus', 'YYYY-MM'));

    INSERT INTO public.monthly_targets (month_key, target_syp, target_usd, updated_at, updated_by)
    VALUES (
        v_month,
        GREATEST(COALESCE(p_target_syp, 0), 0),
        GREATEST(COALESCE(p_target_usd, 0), 0),
        now(),
        auth.uid()
    )
    ON CONFLICT (month_key) DO UPDATE
    SET target_syp = EXCLUDED.target_syp,
        target_usd = EXCLUDED.target_usd,
        updated_at = now(),
        updated_by = auth.uid()
    RETURNING * INTO v_res;

    RETURN to_jsonb(v_res);
END;
$$;

-- ------------------------------------------------------------------------------
-- RPC: get_monthly_target_progress
-- ------------------------------------------------------------------------------
-- Calculates target vs collected revenue (SYP & USD) for Damascus local month boundaries.
-- Restricts execution strictly to active admins.
CREATE OR REPLACE FUNCTION public.get_monthly_target_progress(
    p_month_key text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_month text;
    v_user_role text;
    v_target_syp numeric := 0;
    v_target_usd numeric := 0;
    v_collected_syp numeric := 0;
    v_collected_usd numeric := 0;
    v_has_target boolean := false;
BEGIN
    -- Verify caller is active admin
    SELECT role INTO v_user_role FROM public.users WHERE id = auth.uid() AND is_active = true;
    IF v_user_role IS DISTINCT FROM 'admin' THEN
        RAISE EXCEPTION 'غير مصرح: الاطلاع على الأهداف المالية مخصص لمدير النظام فقط';
    END IF;

    -- Default month_key to Damascus local month (e.g. '2026-10')
    v_month := COALESCE(p_month_key, to_char(now() AT TIME ZONE 'Asia/Damascus', 'YYYY-MM'));

    -- Fetch configured targets
    SELECT target_syp, target_usd, true
    INTO v_target_syp, v_target_usd, v_has_target
    FROM public.monthly_targets
    WHERE month_key = v_month;

    IF NOT FOUND THEN
        v_target_syp := 0;
        v_target_usd := 0;
        v_has_target := false;
    END IF;

    -- Aggregate actual collections in Damascus timezone
    SELECT
        COALESCE(SUM(CASE WHEN currency = 'SYP' THEN amount ELSE 0 END), 0),
        COALESCE(SUM(CASE WHEN currency = 'USD' THEN amount ELSE 0 END), 0)
    INTO v_collected_syp, v_collected_usd
    FROM public.payments
    WHERE to_char(paid_at AT TIME ZONE 'Asia/Damascus', 'YYYY-MM') = v_month;

    RETURN jsonb_build_object(
        'month_key', v_month,
        'has_target', v_has_target,
        'target_syp', v_target_syp,
        'collected_syp', v_collected_syp,
        'progress_syp', CASE WHEN v_target_syp > 0 THEN ROUND((v_collected_syp / v_target_syp) * 100, 1) ELSE 0 END,
        'target_usd', v_target_usd,
        'collected_usd', v_collected_usd,
        'progress_usd', CASE WHEN v_target_usd > 0 THEN ROUND((v_collected_usd / v_target_usd) * 100, 1) ELSE 0 END
    );
END;
$$;

REVOKE ALL ON FUNCTION public.set_monthly_target(numeric, numeric, text) FROM anon, public;
GRANT EXECUTE ON FUNCTION public.set_monthly_target(numeric, numeric, text) TO authenticated;

REVOKE ALL ON FUNCTION public.get_monthly_target_progress(text) FROM anon, public;
GRANT EXECUTE ON FUNCTION public.get_monthly_target_progress(text) TO authenticated;


-- 2. Phase B1: Ensure overdue_payments view projects whatsapp_number
-- ------------------------------------------------------------------------------
DROP VIEW IF EXISTS public.overdue_payments CASCADE;

CREATE VIEW public.overdue_payments AS
SELECT
    efs.enrollment_id,
    efs.trainee_id,
    efs.trainee_name,
    t.trainee_code,
    efs.course_name,
    efs.cohort_name,
    efs.balance AS balance_due,
    efs.currency,
    efs.payment_status,
    u.phone,
    t.whatsapp_number
FROM public.enrollment_financial_summary efs
JOIN public.trainees t ON t.id = efs.trainee_id
LEFT JOIN public.users u ON u.id = t.user_id
WHERE efs.payment_status IN ('partial', 'unpaid')
  AND efs.balance > 0;
