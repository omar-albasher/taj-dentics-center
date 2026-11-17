-- ============================================================================
-- Platform Artifact: Scheduled Jobs (pg_cron) (#47)
-- ============================================================================

-- Ensure pg_cron extension is available
CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog;

-- Clear any existing named schedules before re-registering
SELECT cron.unschedule('auto_open_close_sessions') WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'auto_open_close_sessions');
SELECT cron.unschedule('enqueue_session_reminders') WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'enqueue_session_reminders');
SELECT cron.unschedule('dispatch_push_batch') WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'dispatch_push_batch');
SELECT cron.unschedule('expire_waitlist_notifications') WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'expire_waitlist_notifications');
SELECT cron.unschedule('enqueue_payment_reminders') WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'enqueue_payment_reminders');

-- 1. Auto open and close sessions (runs every 2 minutes)
SELECT cron.schedule(
  'auto_open_close_sessions',
  '*/2 * * * *',
  'SELECT public.auto_open_close_sessions(false);'
);

-- 2. Enqueue session reminders (runs every 5 minutes)
SELECT cron.schedule(
  'enqueue_session_reminders',
  '*/5 * * * *',
  'SELECT public.enqueue_session_reminders();'
);

-- 3. Dispatch push batch (runs every minute)
SELECT cron.schedule(
  'dispatch_push_batch',
  '* * * * *',
  'SELECT public.dispatch_push_batch();'
);

-- 4. Expire waitlist notifications (runs every 15 minutes)
SELECT cron.schedule(
  'expire_waitlist_notifications',
  '*/15 * * * *',
  'SELECT public.expire_waitlist_notifications();'
);

-- 5. Enqueue payment reminders (runs every Sunday at 07:00 UTC)
SELECT cron.schedule(
  'enqueue_payment_reminders',
  '0 7 * * 0',
  'SELECT public.enqueue_payment_reminders();'
);
