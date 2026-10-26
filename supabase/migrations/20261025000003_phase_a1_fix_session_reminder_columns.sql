-- ==============================================================================
-- Migration: 20261025000003_phase_a1_fix_session_reminder_columns.sql
-- Description:
--   Corrects enqueue_session_reminders introduced by 20261025000002.
--   That version referenced co.title and ch.code. The application and the
--   original A1 migration use courses.name and cohorts.name. PL/pgSQL defers
--   SQL name resolution until execution, so creating the function succeeds but
--   the cron job fails silently every 5 minutes with "column does not exist".
--
--   This migration:
--     1. Restores courses.name (with sessions.title when present).
--     2. Keeps scheduled_at in the notification payload (stale-guard contract).
--     3. Restores the original dedupe key.
--     4. Adds a cross-version duplicate guard that also covers rows enqueued
--        with the temporary key from 20261025000002.
-- ==============================================================================

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
      s.scheduled_at AS session_scheduled_at,
      co.name || COALESCE(' — ' || NULLIF(s.title, ''), '') AS display_name,
      to_char(s.scheduled_at AT TIME ZONE 'Asia/Damascus', 'HH24:MI') AS start_time,
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
      AND NOT EXISTS (
        SELECT 1 FROM public.notification_outbox o
        WHERE o.user_id = t.user_id
          AND o.type = 'session_reminder'
          AND o.data->>'session_id' = s.id::text
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
$$;

REVOKE ALL ON FUNCTION public.enqueue_session_reminders() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.enqueue_session_reminders() TO service_role;
