-- ============================================================================
-- Platform Artifact: Vault Secrets Specification (#47)
--
-- Secrets required by push notifications scheduler (dispatch_push_batch):
-- 1. project_url: Supabase Project API URL (e.g. https://<ref>.supabase.co)
-- 2. cron_secret: Shared secret header (x-cron-secret) validated by edge function
-- 3. push_function_slug: Slug of the push edge function (e.g. push-notifications)
-- ============================================================================

-- Ensure supabase_vault extension is available
CREATE EXTENSION IF NOT EXISTS supabase_vault WITH SCHEMA vault;

-- Template for provisioning secrets in vault:
-- (Replace placeholders with actual project values on target environment)
/*
SELECT vault.create_secret('https://<project-ref>.supabase.co', 'project_url', 'Project URL for cron webhooks');
SELECT vault.create_secret('<CRON_SECRET_VALUE>', 'cron_secret', 'Shared secret for cron edge function calls');
SELECT vault.create_secret('push-notifications', 'push_function_slug', 'Edge function slug for push worker');
*/
