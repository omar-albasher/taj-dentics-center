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

-- Idempotent provisioning block with safety guard against template execution:
DO $$
DECLARE
  v_url text := 'https://<project-ref>.supabase.co';
  v_cron_secret text := '<CRON_SECRET_VALUE>';
  v_slug text := 'send-fcm-notification';
  v_id uuid;
BEGIN
  -- Safety guard: reject template placeholders
  IF v_url LIKE '%<project-ref>%' OR v_cron_secret LIKE '%<CRON_SECRET_VALUE>%' THEN
    RAISE EXCEPTION 'vault_secrets.sql contains placeholders; replace v_url and v_cron_secret with real environment values before running.';
  END IF;

  -- 1. project_url
  SELECT id INTO v_id FROM vault.secrets WHERE name = 'project_url';
  IF v_id IS NULL THEN
    PERFORM vault.create_secret(v_url, 'project_url', 'Project URL for cron webhooks');
  ELSE
    PERFORM vault.update_secret(v_id, v_url);
  END IF;

  -- 2. cron_secret
  SELECT id INTO v_id FROM vault.secrets WHERE name = 'cron_secret';
  IF v_id IS NULL THEN
    PERFORM vault.create_secret(v_cron_secret, 'cron_secret', 'Shared secret for cron edge function calls');
  ELSE
    PERFORM vault.update_secret(v_id, v_cron_secret);
  END IF;

  -- 3. push_function_slug (only create if missing; preserves customized or existing live slug)
  SELECT id INTO v_id FROM vault.secrets WHERE name = 'push_function_slug';
  IF v_id IS NULL THEN
    PERFORM vault.create_secret(v_slug, 'push_function_slug', 'Edge function slug for push worker');
  END IF;
END $$;
