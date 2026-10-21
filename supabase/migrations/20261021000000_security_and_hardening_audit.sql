-- ==============================================================================
-- Taj Dentics Training Center - Security, Hardening & Timezone Standardization Audit
-- Migration: 20261021000000_security_and_hardening_audit.sql
-- ==============================================================================

-- 1. Ensure all timestamp columns are TIMESTAMPTZ (Safe Conversion)
-- ------------------------------------------------------------------------------
DO $$
BEGIN
  -- sessions.scheduled_at
  IF EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema = 'public' AND table_name = 'sessions' 
      AND column_name = 'scheduled_at' AND data_type = 'timestamp without time zone'
  ) THEN
    ALTER TABLE public.sessions ALTER COLUMN scheduled_at TYPE timestamptz;
  END IF;

  -- sessions.opened_at
  IF EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema = 'public' AND table_name = 'sessions' 
      AND column_name = 'opened_at' AND data_type = 'timestamp without time zone'
  ) THEN
    ALTER TABLE public.sessions ALTER COLUMN opened_at TYPE timestamptz;
  END IF;

  -- sessions.closed_at
  IF EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema = 'public' AND table_name = 'sessions' 
      AND column_name = 'closed_at' AND data_type = 'timestamp without time zone'
  ) THEN
    ALTER TABLE public.sessions ALTER COLUMN closed_at TYPE timestamptz;
  END IF;

  -- cohorts.starts_at
  IF EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema = 'public' AND table_name = 'cohorts' 
      AND column_name = 'starts_at' AND data_type = 'timestamp without time zone'
  ) THEN
    ALTER TABLE public.cohorts ALTER COLUMN starts_at TYPE timestamptz;
  END IF;

  -- payments.paid_at
  IF EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema = 'public' AND table_name = 'payments' 
      AND column_name = 'paid_at' AND data_type = 'timestamp without time zone'
  ) THEN
    ALTER TABLE public.payments ALTER COLUMN paid_at TYPE timestamptz;
  END IF;
END $$;


-- 2. Hardening: dispatch_survey_to_all
-- ------------------------------------------------------------------------------
-- Ensure only active administrators can trigger bulk survey dispatching.
CREATE OR REPLACE FUNCTION public.dispatch_survey_to_all(p_template_id UUID)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_inserted_count integer;
BEGIN
  -- فحص الدور الصارم: مدير نشط فقط
  IF NOT EXISTS (
    SELECT 1 FROM public.users 
    WHERE id = auth.uid() AND role = 'admin' AND is_active = true
  ) THEN
    RAISE EXCEPTION 'غير مصرح: عملية إرسال الاستبيانات بالجملة مخصصة لمدير النظام فقط';
  END IF;

  WITH inserted AS (
    INSERT INTO public.survey_dispatches (enrollment_id, template_id, at_session_count)
    SELECT id, p_template_id, 0
    FROM public.enrollments
    ON CONFLICT (enrollment_id, at_session_count) DO NOTHING
    RETURNING 1
  )
  SELECT count(*) INTO v_inserted_count FROM inserted;

  RETURN v_inserted_count;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.dispatch_survey_to_all FROM public, anon;
GRANT EXECUTE ON FUNCTION public.dispatch_survey_to_all TO authenticated;


-- 3. Hardening: submit_survey_response
-- ------------------------------------------------------------------------------
REVOKE EXECUTE ON FUNCTION public.submit_survey_response FROM public, anon;
GRANT EXECUTE ON FUNCTION public.submit_survey_response TO authenticated;


-- 4. Hardening: shift_cohort_sessions
-- ------------------------------------------------------------------------------
REVOKE EXECUTE ON FUNCTION public.shift_cohort_sessions FROM public, anon;
GRANT EXECUTE ON FUNCTION public.shift_cohort_sessions TO authenticated;
