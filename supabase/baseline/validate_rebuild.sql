-- ============================================================================
-- Rebuild Validation Script (#47)
--
-- Compares database and platform state against the authoritative baseline.
-- Checks both core public schema invariants and external platform dependencies.
-- Safe, read-only verification that returns a summary table of all checks.
-- ============================================================================

CREATE OR REPLACE FUNCTION pg_temp.validate_database_rebuild()
RETURNS TABLE (
  check_id text,
  metric text,
  expected text,
  actual text,
  status text
)
LANGUAGE plpgsql
AS $val$
DECLARE
  v_tables integer;
  v_views integer;
  v_functions integer;
  v_policies integer;
  v_triggers integer;
  v_indexes integer;
  v_sequences integer;
  v_enums integer;
  v_rls_enabled integer;
  v_rls_forced integer;
  v_fingerprint text;
  v_unpinned integer;
  -- Platform metrics
  v_storage_bucket boolean := false;
  v_storage_policies integer := 0;
  v_cron_jobs integer := 0;
  v_extensions integer := 0;
  v_vault_secrets integer := 0;
BEGIN
  -- 1. Gather public schema counts
  SELECT count(*) INTO v_tables FROM pg_tables WHERE schemaname = 'public';
  SELECT count(*) INTO v_views FROM pg_views WHERE schemaname = 'public';
  SELECT count(*) INTO v_functions FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'public';
  SELECT count(*) INTO v_policies FROM pg_policies WHERE schemaname = 'public';
  SELECT count(*) INTO v_triggers FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'public' AND NOT t.tgisinternal;
  SELECT count(*) INTO v_indexes FROM pg_indexes WHERE schemaname = 'public';
  SELECT count(*) INTO v_sequences FROM pg_sequences WHERE schemaname = 'public';
  SELECT count(*) INTO v_enums FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace WHERE n.nspname = 'public' AND t.typtype = 'e';
  SELECT count(*) INTO v_rls_enabled FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'public' AND c.relkind = 'r' AND c.relrowsecurity;
  SELECT count(*) INTO v_rls_forced FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'public' AND c.relkind = 'r' AND c.relforcerowsecurity;

  -- 2. Compute public policy fingerprint
  SELECT md5(string_agg(
           schemaname || '.' || tablename || ':' || policyname || ':' ||
           cmd || ':' || roles::text || ':' || COALESCE(qual, '') || ':' ||
           COALESCE(with_check, ''),
           '|' ORDER BY schemaname, tablename, policyname
         )) INTO v_fingerprint
  FROM pg_policies
  WHERE schemaname = 'public';

  -- 3. Check unpinned SECURITY DEFINER functions
  SELECT count(*) INTO v_unpinned
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.prosecdef
    AND NOT EXISTS (
      SELECT 1 FROM unnest(COALESCE(p.proconfig, '{}')) AS c
      WHERE c LIKE 'search_path=%'
    );

  -- 4. Check platform dependencies
  IF to_regclass('storage.buckets') IS NOT NULL THEN
    SELECT EXISTS (SELECT 1 FROM storage.buckets WHERE id = 'course-materials') INTO v_storage_bucket;
  END IF;

  SELECT count(*) INTO v_storage_policies
  FROM pg_policies
  WHERE schemaname = 'storage' AND tablename = 'objects';

  IF to_regclass('cron.job') IS NOT NULL THEN
    SELECT count(DISTINCT command) INTO v_cron_jobs
    FROM cron.job
    WHERE active = true
      AND command IN (
        'SELECT public.auto_open_close_sessions(false);',
        'SELECT public.enqueue_session_reminders();',
        'SELECT public.dispatch_push_batch();',
        'SELECT public.expire_waitlist_notifications();',
        'SELECT public.enqueue_payment_reminders();'
      );
  END IF;

  SELECT count(*) INTO v_extensions
  FROM pg_extension
  WHERE extname IN ('uuid-ossp', 'pgcrypto', 'pg_stat_statements', 'pg_net', 'pg_cron', 'supabase_vault');

  IF to_regclass('vault.decrypted_secrets') IS NOT NULL THEN
    SELECT count(*) INTO v_vault_secrets
    FROM vault.decrypted_secrets
    WHERE name IN ('project_url', 'cron_secret', 'push_function_slug');
  END IF;

  -- Return rows
  RETURN QUERY VALUES
    ('C01', 'Tables in public', '43', v_tables::text, CASE WHEN v_tables = 43 THEN 'PASS' ELSE 'FAIL' END),
    ('C02', 'Views in public', '33', v_views::text, CASE WHEN v_views = 33 THEN 'PASS' ELSE 'FAIL' END),
    ('C03', 'Functions in public', '107', v_functions::text, CASE WHEN v_functions = 107 THEN 'PASS' ELSE 'FAIL' END),
    ('C04', 'Policies in public', '71', v_policies::text, CASE WHEN v_policies = 71 THEN 'PASS' ELSE 'FAIL' END),
    ('C05', 'Triggers in public', '68', v_triggers::text, CASE WHEN v_triggers = 68 THEN 'PASS' ELSE 'FAIL' END),
    ('C06', 'Indexes in public', '127', v_indexes::text, CASE WHEN v_indexes = 127 THEN 'PASS' ELSE 'FAIL' END),
    ('C07', 'Sequences in public', '3', v_sequences::text, CASE WHEN v_sequences = 3 THEN 'PASS' ELSE 'FAIL' END),
    ('C08', 'Enums in public', '9', v_enums::text, CASE WHEN v_enums = 9 THEN 'PASS' ELSE 'FAIL' END),
    ('C09', 'RLS Enabled Tables', '43', v_rls_enabled::text, CASE WHEN v_rls_enabled = 43 THEN 'PASS' ELSE 'FAIL' END),
    ('C10', 'RLS Forced Tables', '0', v_rls_forced::text, CASE WHEN v_rls_forced = 0 THEN 'PASS' ELSE 'FAIL' END),
    ('C11', 'Unpinned SecDef Functions', '0', v_unpinned::text, CASE WHEN v_unpinned = 0 THEN 'PASS' ELSE 'FAIL' END),
    ('C12', 'Policy MD5 Fingerprint', 'c8215afa7997fb5258254047a879d68a', v_fingerprint, CASE WHEN v_fingerprint = 'c8215afa7997fb5258254047a879d68a' THEN 'PASS' ELSE 'FAIL' END),
    ('C13', 'Storage Bucket (course-materials)', 'true', COALESCE(v_storage_bucket, false)::text, CASE WHEN COALESCE(v_storage_bucket, false) THEN 'PASS' ELSE 'FAIL' END),
    ('C14', 'Storage Policies on objects', '2', v_storage_policies::text, CASE WHEN v_storage_policies = 2 THEN 'PASS' ELSE 'FAIL' END),
    ('C15', 'Distinct Core Cron Jobs', '5', v_cron_jobs::text, CASE WHEN v_cron_jobs = 5 THEN 'PASS' ELSE 'FAIL' END),
    ('C16', 'Platform Extensions', '6', v_extensions::text, CASE WHEN v_extensions = 6 THEN 'PASS' ELSE 'FAIL' END),
    ('C17', 'Vault Push Scheduler Secrets', '3', v_vault_secrets::text, CASE WHEN v_vault_secrets = 3 THEN 'PASS' ELSE 'FAIL' END);
END;
$val$;

SELECT * FROM pg_temp.validate_database_rebuild();
