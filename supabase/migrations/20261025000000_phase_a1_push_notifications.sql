-- ==============================================================================
-- Taj Dentics Training Center - Phase A1: Push Notifications Engine (Outbox)
-- 1. Tables: user_fcm_tokens, notification_outbox
-- 2. Indexes & RLS Policies
-- 3. Functions:
--    - register_fcm_token(fcm_token, device_type, device_id)
--    - enqueue_session_reminders()
--    - enqueue_payment_reminders()
--    - trg_fn_enqueue_survey_notification() [with EXCEPTION safety guard]
--    - claim_notification_batch(p_limit) [with dead-letter sweeper & limit bounds]
-- 4. Triggers on survey_dispatches
-- 5. Strict Permission Revocations
-- ==============================================================================

-- 1. Table: user_fcm_tokens
DROP TABLE IF EXISTS public.user_fcm_tokens CASCADE;
CREATE TABLE public.user_fcm_tokens (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  fcm_token TEXT NOT NULL UNIQUE,
  device_type TEXT NOT NULL DEFAULT 'android' CHECK (device_type IN ('android', 'ios', 'web')),
  device_id TEXT,
  is_active BOOLEAN NOT NULL DEFAULT true,
  last_seen_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_user_fcm_tokens_user_active 
ON public.user_fcm_tokens (user_id) 
WHERE is_active = true;

-- 2. Table: notification_outbox
CREATE TABLE IF NOT EXISTS public.notification_outbox (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  type TEXT NOT NULL CHECK (type IN ('session_reminder', 'survey_reminder', 'payment_reminder', 'custom')),
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  data JSONB NOT NULL DEFAULT '{}'::jsonb,
  dedupe_key TEXT NOT NULL UNIQUE,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'processing', 'sent', 'failed', 'skipped')),
  attempts INTEGER NOT NULL DEFAULT 0,
  max_attempts INTEGER NOT NULL DEFAULT 3,
  next_attempt_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  locked_at TIMESTAMPTZ,
  sent_at TIMESTAMPTZ,
  last_error TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_notification_outbox_pending 
ON public.notification_outbox (status, next_attempt_at) 
WHERE status IN ('pending', 'processing');

CREATE INDEX IF NOT EXISTS idx_notification_outbox_user_id 
ON public.notification_outbox (user_id);

-- 3. RLS Setup
ALTER TABLE public.user_fcm_tokens ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notification_outbox ENABLE ROW LEVEL SECURITY;

-- RLS: user_fcm_tokens (Trainee manages own tokens only)
DROP POLICY IF EXISTS "Users can select own tokens" ON public.user_fcm_tokens;
CREATE POLICY "Users can select own tokens"
ON public.user_fcm_tokens FOR SELECT
TO authenticated
USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert own tokens" ON public.user_fcm_tokens;
CREATE POLICY "Users can insert own tokens"
ON public.user_fcm_tokens FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update own tokens" ON public.user_fcm_tokens;
CREATE POLICY "Users can update own tokens"
ON public.user_fcm_tokens FOR UPDATE
TO authenticated
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can delete own tokens" ON public.user_fcm_tokens;
CREATE POLICY "Users can delete own tokens"
ON public.user_fcm_tokens FOR DELETE
TO authenticated
USING (auth.uid() = user_id);

-- RLS: notification_outbox has no public policies; access is restricted exclusively to service_role.

-- 4. RPC: register_fcm_token (Reassigns token safely on shared devices)
CREATE OR REPLACE FUNCTION public.register_fcm_token(
  p_fcm_token TEXT,
  p_device_type TEXT DEFAULT 'android',
  p_device_id TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid UUID := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  IF p_fcm_token IS NULL OR trim(p_fcm_token) = '' THEN
    RAISE EXCEPTION 'FCM token cannot be empty';
  END IF;

  INSERT INTO public.user_fcm_tokens (
    user_id,
    fcm_token,
    device_type,
    device_id,
    is_active,
    last_seen_at,
    updated_at
  ) VALUES (
    v_uid,
    trim(p_fcm_token),
    COALESCE(p_device_type, 'android'),
    p_device_id,
    true,
    now(),
    now()
  )
  ON CONFLICT (fcm_token) DO UPDATE SET
    user_id = EXCLUDED.user_id,
    device_type = EXCLUDED.device_type,
    device_id = COALESCE(EXCLUDED.device_id, public.user_fcm_tokens.device_id),
    is_active = true,
    last_seen_at = now(),
    updated_at = now();
END;
$$;

-- 5. Outbox Enqueue: Session Reminders (Window: 55-65 mins, HH24:MI, Course name always present)
CREATE OR REPLACE FUNCTION public.enqueue_session_reminders()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_inserted_count INTEGER;
BEGIN
  WITH target_enrollments AS (
    SELECT DISTINCT 
      t.user_id,
      s.id AS session_id,
      co.name || COALESCE(' — ' || NULLIF(s.title, ''), '') AS display_name,
      to_char(s.scheduled_at at time zone 'Asia/Damascus', 'HH24:MI') AS start_time,
      'session:' || s.id || ':user:' || t.user_id || ':60' AS dedupe_key
    FROM public.sessions s
    JOIN public.cohorts ch ON ch.id = s.cohort_id
    JOIN public.courses co ON co.id = ch.course_id
    JOIN public.enrollments e ON e.cohort_id = ch.id
    JOIN public.trainees t ON t.id = e.trainee_id
    JOIN public.users u ON u.id = t.user_id
    WHERE s.status IN ('scheduled', 'open')
      AND s.scheduled_at BETWEEN (now() + interval '55 minutes')
                             AND (now() + interval '65 minutes')
      AND u.is_active = true
      AND e.status::text <> 'dropped'
      AND NOT EXISTS (
        SELECT 1 FROM public.attendance a
        WHERE a.session_id = s.id AND a.trainee_id = e.trainee_id
      )
  ),
  inserted AS (
    INSERT INTO public.notification_outbox (
      user_id,
      type,
      title,
      body,
      data,
      dedupe_key
    )
    SELECT 
      te.user_id,
      'session_reminder',
      'تذكير بجلسة بعد ساعة',
      te.display_name || ' — الساعة ' || te.start_time,
      jsonb_build_object(
        'type', 'session_reminder',
        'session_id', te.session_id,
        'route', '/home'
      ),
      te.dedupe_key
    FROM target_enrollments te
    ON CONFLICT (dedupe_key) DO NOTHING
    RETURNING 1
  )
  SELECT count(*) INTO v_inserted_count FROM inserted;

  RETURN v_inserted_count;
END;
$$;

-- 6. Outbox Enqueue: Due Payment Reminders (Weekly max per debtor, privacy-safe text)
CREATE OR REPLACE FUNCTION public.enqueue_payment_reminders()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_inserted_count INTEGER;
  v_week_code TEXT := to_char(now() at time zone 'Asia/Damascus', 'IYYY-IW');
BEGIN
  WITH debtors AS (
    SELECT DISTINCT
      t.user_id,
      'payment_due:user:' || t.user_id || ':' || v_week_code AS dedupe_key
    FROM public.enrollment_financial_summary efs
    JOIN public.trainees t ON t.id = efs.trainee_id
    JOIN public.users u ON u.id = t.user_id
    JOIN public.enrollments e ON e.id = efs.enrollment_id
    WHERE efs.payment_status IN ('unpaid', 'partial')
      AND efs.balance > 0
      AND u.is_active = true
      AND e.status::text <> 'dropped'
  ),
  inserted AS (
    INSERT INTO public.notification_outbox (
      user_id,
      type,
      title,
      body,
      data,
      dedupe_key
    )
    SELECT 
      d.user_id,
      'payment_reminder',
      'تذكير بمستحقات الدفع',
      'لديك دفعة مستحقة — يرجى مراجعة التفاصيل داخل التطبيق',
      jsonb_build_object(
        'type', 'payment_reminder',
        'route', '/payments'
      ),
      d.dedupe_key
    FROM debtors d
    ON CONFLICT (dedupe_key) DO NOTHING
    RETURNING 1
  )
  SELECT count(*) INTO v_inserted_count FROM inserted;

  RETURN v_inserted_count;
END;
$$;

-- 7. Trigger on survey_dispatches: In-transaction outbox enqueue with EXCEPTION safety guard
CREATE OR REPLACE FUNCTION public.trg_fn_enqueue_survey_notification()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user_id UUID;
  v_title TEXT;
BEGIN
  SELECT t.user_id, st.title
  INTO v_user_id, v_title
  FROM public.enrollments e
  JOIN public.trainees t ON t.id = e.trainee_id
  JOIN public.users u ON u.id = t.user_id
  JOIN public.survey_templates st ON st.id = NEW.template_id
  WHERE e.id = NEW.enrollment_id
    AND u.is_active = true
    AND e.status::text <> 'dropped';

  IF v_user_id IS NOT NULL THEN
    INSERT INTO public.notification_outbox (
      user_id,
      type,
      title,
      body,
      data,
      dedupe_key
    ) VALUES (
      v_user_id,
      'survey_reminder',
      'استبيان جديد بانتظارك',
      'يرجى تعبئة استبيان: ' || COALESCE(v_title, 'استبيان تقييم'),
      jsonb_build_object(
        'type', 'survey_reminder',
        'dispatch_id', NEW.id,
        'route', '/surveys'
      ),
      'survey:' || NEW.id
    )
    ON CONFLICT (dedupe_key) DO NOTHING;
  END IF;

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'survey outbox enqueue failed for dispatch %: %', NEW.id, SQLERRM;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_survey_dispatch_outbox ON public.survey_dispatches;
CREATE TRIGGER trg_survey_dispatch_outbox
AFTER INSERT ON public.survey_dispatches
FOR EACH ROW
EXECUTE FUNCTION public.trg_fn_enqueue_survey_notification();

-- 8. Claim Function: Batch claiming with FOR UPDATE SKIP LOCKED & Dead-letter Sweeper
CREATE OR REPLACE FUNCTION public.claim_notification_batch(p_limit INTEGER DEFAULT 50)
RETURNS TABLE (
  outbox_id UUID,
  recipient_user_id UUID,
  notification_type TEXT,
  notification_title TEXT,
  notification_body TEXT,
  notification_data JSONB,
  attempt_number INTEGER,
  max_attempts INTEGER,
  fcm_tokens TEXT[]
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_limit INTEGER := GREATEST(1, LEAST(COALESCE(p_limit, 50), 100));
BEGIN
  -- 1. استعادة الصفوف العالقة في processing لأكثر من 10 دقائق
  UPDATE public.notification_outbox
  SET status = 'pending',
      locked_at = NULL
  WHERE status = 'processing'
    AND locked_at < now() - interval '10 minutes';

  -- 2. Sweeper: تحويل الصفوف المستنفدة للمحاولات إلى failed حتى لا تبقى pending للأبد
  UPDATE public.notification_outbox
  SET status = 'failed',
      last_error = COALESCE(last_error, 'max_attempts_reached'),
      locked_at = NULL
  WHERE status = 'pending'
    AND attempts >= notification_outbox.max_attempts;

  -- 3. حجز الدفعة التالية وتجميع التوكنات النشطة لكل مستخدم نشط
  RETURN QUERY
  WITH locked_rows AS (
    SELECT o.id
    FROM public.notification_outbox o
    WHERE o.status = 'pending'
      AND o.next_attempt_at <= now()
      AND o.attempts < o.max_attempts
    ORDER BY o.created_at ASC
    LIMIT v_limit
    FOR UPDATE SKIP LOCKED
  ),
  marked AS (
    UPDATE public.notification_outbox o
    SET status = 'processing',
        attempts = o.attempts + 1,
        locked_at = now()
    FROM locked_rows lr
    WHERE o.id = lr.id
    RETURNING o.id, o.user_id, o.type, o.title, o.body, o.data, o.attempts, o.max_attempts
  )
  SELECT 
    m.id AS outbox_id,
    m.user_id AS recipient_user_id,
    m.type AS notification_type,
    m.title AS notification_title,
    m.body AS notification_body,
    m.data AS notification_data,
    m.attempts AS attempt_number,
    m.max_attempts AS max_attempts,
    COALESCE(
      (
        SELECT array_agg(t.fcm_token)
        FROM public.user_fcm_tokens t
        JOIN public.users u ON u.id = t.user_id AND u.is_active = true
        WHERE t.user_id = m.user_id
          AND t.is_active = true
      ),
      ARRAY[]::TEXT[]
    ) AS fcm_tokens
  FROM marked m;
END;
$$;

-- 9. الصلاحيات: عزل دوال السيرفر عن العامة وحصرها في service_role
REVOKE ALL ON FUNCTION public.enqueue_session_reminders() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.enqueue_session_reminders() TO service_role;

REVOKE ALL ON FUNCTION public.enqueue_payment_reminders() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.enqueue_payment_reminders() TO service_role;

REVOKE ALL ON FUNCTION public.trg_fn_enqueue_survey_notification() FROM PUBLIC, anon, authenticated;

REVOKE ALL ON FUNCTION public.claim_notification_batch(INTEGER) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_notification_batch(INTEGER) TO service_role;

REVOKE ALL ON FUNCTION public.register_fcm_token(TEXT, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.register_fcm_token(TEXT, TEXT, TEXT) TO authenticated, service_role;

GRANT SELECT, INSERT, UPDATE, DELETE ON public.user_fcm_tokens TO authenticated, service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.notification_outbox TO service_role;
