-- ============================================================================== 
-- Migration: 20261025000002_phase_a1_sync_claim_batch.sql 
-- Description: 
--   Synchronizes claim_notification_batch with created_at return type to 
--   eliminate drift between database runtime and repository migrations. 
--   Also ensures session reminders payload includes scheduled_at. 
-- ============================================================================== 

-- 1. Ensure enqueue_session_reminders puts scheduled_at into notification_data 
CREATE OR REPLACE FUNCTION public.enqueue_session_reminders() 
RETURNS INTEGER 
LANGUAGE plpgsql 
SECURITY DEFINER 
SET search_path = public, pg_temp 
AS  
DECLARE 
  v_inserted_count INTEGER; 
BEGIN 
  WITH target_enrollments AS ( 
    SELECT DISTINCT 
      t.user_id, 
      s.id AS session_id, 
      s.scheduled_at AS session_scheduled_at, 
      co.title AS course_title, 
      ch.code AS cohort_code, 
      co.title || ' (' || ch.code || ')' AS display_name, 
      to_char(s.scheduled_at AT TIME ZONE 'Asia/Damascus', 'HH24:MI') AS start_time, 
      'session_reminder:' || s.id || ':' || t.user_id AS dedupe_key 
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
        'scheduled_at', te.session_scheduled_at, 
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
; 

REVOKE ALL ON FUNCTION public.enqueue_session_reminders() FROM PUBLIC, anon, authenticated; 
GRANT EXECUTE ON FUNCTION public.enqueue_session_reminders() TO service_role; 

-- 2. Drop old signature to allow return type change 
DROP FUNCTION IF EXISTS public.claim_notification_batch(INTEGER); 

-- 3. Recreate claim_notification_batch with created_at TIMESTAMPTZ 
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
  created_at TIMESTAMPTZ, 
  fcm_tokens TEXT[] 
) 
LANGUAGE plpgsql 
SECURITY DEFINER 
SET search_path = public, pg_temp 
AS  
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
    RETURNING o.id, o.user_id, o.type, o.title, o.body, o.data, o.attempts, o.max_attempts, o.created_at 
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
    m.created_at AS created_at, 
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
; 

-- 4. Reapply strict security permissions 
REVOKE ALL ON FUNCTION public.claim_notification_batch(INTEGER) FROM PUBLIC, anon, authenticated; 
GRANT EXECUTE ON FUNCTION public.claim_notification_batch(INTEGER) TO service_role; 