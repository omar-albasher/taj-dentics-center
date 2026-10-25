-- ==============================================================================
-- Taj Dentics Training Center - Phase A1: Push Notifications Scheduler
-- 1. dispatch_push_batch function via pg_net & vault
-- 2. pg_cron schedules for:
--    - Session reminders: every 5 minutes
--    - Due payment reminders: daily at 07:00 UTC (10:00 Damascus)
--    - Batch push dispatcher: every minute
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.dispatch_push_batch()
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_url TEXT;
  v_secret TEXT;
BEGIN
  SELECT decrypted_secret INTO v_url
  FROM vault.decrypted_secrets WHERE name = 'project_url';
  SELECT decrypted_secret INTO v_secret
  FROM vault.decrypted_secrets WHERE name = 'cron_secret';

  IF v_url IS NULL OR v_secret IS NULL THEN
    RAISE EXCEPTION 'push scheduler secrets missing in vault (project_url or cron_secret)';
  END IF;

  RETURN net.http_post(
    url := rtrim(v_url, '/') || '/functions/v1/bright-endpoint',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-cron-secret', v_secret
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 30000
  );
END;
$$;

REVOKE ALL ON FUNCTION public.dispatch_push_batch() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.dispatch_push_batch() TO service_role;

-- Unschedule any previous jobs with these names if they exist
DO $$
BEGIN
  PERFORM cron.unschedule('taj_push_session_reminders');
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

DO $$
BEGIN
  PERFORM cron.unschedule('taj_push_payment_reminders');
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

DO $$
BEGIN
  PERFORM cron.unschedule('taj_push_send_batch');
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

-- 1. Enqueue Session reminders: every 5 minutes
SELECT cron.schedule(
  'taj_push_session_reminders',
  '*/5 * * * *',
  $$SELECT public.enqueue_session_reminders();$$
);

-- 2. Enqueue Due Payment reminders: daily at 07:00 UTC (10:00 Damascus)
SELECT cron.schedule(
  'taj_push_payment_reminders',
  '0 7 * * *',
  $$SELECT public.enqueue_payment_reminders();$$
);

-- 3. Batch dispatcher: every minute
SELECT cron.schedule(
  'taj_push_send_batch',
  '* * * * *',
  $$SELECT public.dispatch_push_batch();$$
);
