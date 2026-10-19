-- ==============================================================================
-- Taj Dentics Training Center - Core Database Functions, Views & Security Hooks
-- Generated: 2026-10-19
-- ==============================================================================

-- 1. Unique Constraints (Data Integrity)
-- ------------------------------------------------------------------------------
-- Prevent duplicate survey responses for the same dispatch
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'unique_dispatch_response'
  ) THEN
    ALTER TABLE public.survey_responses 
      ADD CONSTRAINT unique_dispatch_response UNIQUE (dispatch_id);
  END IF;
END $$;

-- Prevent duplicate attendance records for the same trainee in the same session
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'unique_attendance_session_trainee'
  ) THEN
    ALTER TABLE public.attendance 
      ADD CONSTRAINT unique_attendance_session_trainee UNIQUE (session_id, trainee_id);
  END IF;
END $$;


-- 2. Financial & Operational Dashboard KPIs View
-- ------------------------------------------------------------------------------
-- High-performance aggregated view computed on PostgreSQL server.
-- Avoids client-side row limits (PostgREST db-max-rows) and calculates accurate totals.
DROP VIEW IF EXISTS public.dashboard_kpis CASCADE;

CREATE VIEW public.dashboard_kpis AS
SELECT
    (SELECT count(*) FROM public.trainees) AS total_trainees,
    (SELECT count(*) FROM public.trainees t JOIN public.users u ON t.user_id = u.id WHERE u.is_active = true) AS active_trainees,
    (SELECT count(*) FROM public.enrollment_financial_summary WHERE payment_status = 'partial') AS partial_count,
    (SELECT count(*) FROM public.enrollment_financial_summary WHERE payment_status = 'unpaid') AS unpaid_count,
    COALESCE((SELECT sum(amount) FROM public.payments WHERE currency = 'SYP'), 0) AS total_paid_syp,
    COALESCE((SELECT sum(amount) FROM public.payments WHERE currency = 'USD'), 0) AS total_paid_usd,
    COALESCE((SELECT sum(amount) FROM public.expenses WHERE currency = 'SYP'), 0) AS total_exp_syp,
    COALESCE((SELECT sum(amount) FROM public.expenses WHERE currency = 'USD'), 0) AS total_exp_usd,
    COALESCE((SELECT sum(amount) FROM public.payments WHERE currency = 'SYP'), 0) - COALESCE((SELECT sum(amount) FROM public.expenses WHERE currency = 'SYP'), 0) AS net_profit_syp,
    COALESCE((SELECT sum(amount) FROM public.payments WHERE currency = 'USD'), 0) - COALESCE((SELECT sum(amount) FROM public.expenses WHERE currency = 'USD'), 0) AS net_profit_usd,
    COALESCE((SELECT sum(balance) FROM public.enrollment_financial_summary WHERE currency = 'SYP'), 0) AS total_balance_syp,
    COALESCE((SELECT sum(balance) FROM public.enrollment_financial_summary WHERE currency = 'USD'), 0) AS total_balance_usd;


-- 3. Security: Custom Access Token Hook
-- ------------------------------------------------------------------------------
-- Overwrites claims.user_metadata.role with authoritative value from public.users.
-- Prevents role forgery via client-side auth.updateUser().
CREATE OR REPLACE FUNCTION public.custom_access_token_hook(event jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_role TEXT;
BEGIN
  -- Lookup true role from users table
  SELECT role::TEXT INTO v_role
  FROM public.users
  WHERE id = (event->>'user_id')::UUID;

  -- Force real role into JWT claims, fallback to 'none'
  event := jsonb_set(
    event, 
    '{claims,user_metadata,role}', 
    to_jsonb(COALESCE(v_role, 'none'))
  );

  RETURN event;
END;
$$;


-- 4. Atomic Survey Submission RPC
-- ------------------------------------------------------------------------------
-- Inserts answers and marks dispatch as answered in a single atomic transaction.
-- Hardened with strict ownership check to prevent IDOR / answer tampering.
CREATE OR REPLACE FUNCTION public.submit_survey_response(p_dispatch_id UUID, p_answers JSONB)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Strict ownership check: ensure dispatch belongs to an enrollment of the current trainee
  IF NOT EXISTS (
    SELECT 1 FROM public.survey_dispatches d
    JOIN public.enrollments e ON e.id = d.enrollment_id
    JOIN public.trainees t ON t.id = e.trainee_id
    WHERE d.id = p_dispatch_id AND t.user_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'غير مصرح: هذا الاستبيان غير مخصص لك أو انتهت صلاحيته';
  END IF;

  -- Insert or update answers on conflict
  INSERT INTO public.survey_responses (dispatch_id, answers)
  VALUES (p_dispatch_id, p_answers)
  ON CONFLICT (dispatch_id) DO UPDATE
    SET answers = EXCLUDED.answers;

  -- Mark dispatch as answered
  UPDATE public.survey_dispatches
  SET status = 'answered',
      answered_at = NOW()
  WHERE id = p_dispatch_id;
END;
$$;


-- 5. Atomic Survey Dispatch to All Enrollments (S15)
-- ------------------------------------------------------------------------------
-- Resolves the 1000-row PostgREST client limit, eliminates heavy client payloads,
-- and inserts dispatches atomically on the server.
CREATE OR REPLACE FUNCTION public.dispatch_survey_to_all(p_template_id UUID)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_inserted_count integer;
BEGIN
  -- Insert survey dispatches for all enrollments where a dispatch at session 0 doesn't exist
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


