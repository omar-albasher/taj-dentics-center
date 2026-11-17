-- ============================================================================
-- Platform Artifact: Vault Secrets Provisioning (#47)
--
-- Secrets required by push notifications scheduler (dispatch_push_batch):
-- 1. project_url: Supabase Project API URL (e.g. https://<ref>.supabase.co)
-- 2. cron_secret: Shared secret header (x-cron-secret) validated by edge function
-- 3. push_function_slug: Slug of the push edge function (e.g. send-fcm-notification)
-- ============================================================================

-- Ensure supabase_vault extension is available
CREATE EXTENSION IF NOT EXISTS supabase_vault WITH SCHEMA vault;

-- Idempotent provisioning block (uses placeholders for template replay):
DO $$
DECLARE v_id uuid;
BEGIN
  -- 1. project_url
  SELECT id INTO v_id FROM vault.secrets WHERE name = 'project_url';
  IF v_id IS NULL THEN
    PERFORM vault.create_secret('https://<project-ref>.supabase.co', 'project_url', 'Project URL for cron webhooks');
  END IF;

  -- 2. cron_secret
  SELECT id INTO v_id FROM vault.secrets WHERE name = 'cron_secret';
  IF v_id IS NULL THEN
    PERFORM vault.create_secret('<CRON_SECRET_VALUE>', 'cron_secret', 'Shared secret for cron edge function calls');
  END IF;

  -- 3. push_function_slug
  SELECT id INTO v_id FROM vault.secrets WHERE name = 'push_function_slug';
  IF v_id IS NULL THEN
    PERFORM vault.create_secret('send-fcm-notification', 'push_function_slug', 'Edge function slug for push worker');
  END IF;
END $$;
