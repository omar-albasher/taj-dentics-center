-- ============================================================================
-- Phase D1-B (#47) — Live inventory (READ-ONLY)
--
-- Purpose: capture the evidence needed to close the Squash/Bootstrap decision
-- and to define the cold-start fingerprint. No writes, no DDL, no temp objects.
-- Run each numbered block in the Supabase SQL Editor (as postgres).
-- ============================================================================

-- E0.1a Migration tracking: does the project use CLI migration history?
SELECT to_regclass('supabase_migrations.schema_migrations') AS migrations_table;

-- E0.1b Run only if E0.1a returned a non-null value.
-- If it errors with "relation does not exist", the project was provisioned by
-- manual SQL (no CLI history) and the squash can be applied without repair.
SELECT version, name, inserted_at
FROM supabase_migrations.schema_migrations
ORDER BY version;

-- E0.2 Public schema object counts (must match the rebuild fingerprint)
SELECT
  (SELECT count(*) FROM pg_tables
    WHERE schemaname = 'public')                                   AS tables,
  (SELECT count(*) FROM pg_views
    WHERE schemaname = 'public')                                   AS views,
  (SELECT count(*) FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public')                                    AS functions,
  (SELECT count(*) FROM pg_policies
    WHERE schemaname = 'public')                                   AS policies,
  (SELECT count(*) FROM pg_trigger t
    JOIN pg_class c ON c.oid = t.tgrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND NOT t.tgisinternal)             AS triggers,
  (SELECT count(*) FROM pg_indexes
    WHERE schemaname = 'public')                                   AS indexes,
  (SELECT count(*) FROM pg_sequences
    WHERE schemaname = 'public')                                   AS sequences,
  (SELECT count(*) FROM pg_type t
    JOIN pg_namespace n ON n.oid = t.typnamespace
    WHERE n.nspname = 'public' AND t.typtype = 'e')                AS enums,
  (SELECT count(*) FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relkind = 'r'
      AND c.relrowsecurity)                                        AS rls_enabled,
  (SELECT count(*) FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relkind = 'r'
      AND c.relforcerowsecurity)                                   AS rls_forced;

-- E0.3 RLS state per table (FORCE must be false everywhere; D5 relies on the
-- owner bypass inside SECURITY DEFINER functions)
SELECT c.relname,
       c.relrowsecurity  AS rls_enabled,
       c.relforcerowsecurity AS rls_forced
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' AND c.relkind = 'r'
ORDER BY c.relname;

-- E0.4 Storage buckets and storage.objects policies (absent from schema=public)
SELECT id, name, public, file_size_limit, allowed_mime_types
FROM storage.buckets
ORDER BY id;

SELECT schemaname, tablename, policyname, cmd, roles, qual, with_check
FROM pg_policies
WHERE schemaname = 'storage'
ORDER BY tablename, policyname;

-- E0.5 pg_cron jobs (must be recreated explicitly on a cold start)
SELECT jobid, schedule, command, database, username, active
FROM cron.job
ORDER BY jobid;

-- E0.6 Installed extensions and their schemas
SELECT e.extname, e.extversion, n.nspname AS schema
FROM pg_extension e
JOIN pg_namespace n ON n.oid = e.extnamespace
ORDER BY e.extname;

-- E0.7 Security-definer functions whose search_path is not pinned (rebuild must
-- preserve the hardened state; expected: empty after D5)
SELECT p.oid::regprocedure AS function,
       p.prosecdef,
       p.proconfig
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.prosecdef
  AND NOT EXISTS (
    SELECT 1 FROM unnest(COALESCE(p.proconfig, '{}')) AS c
    WHERE c LIKE 'search_path=%'
  )
ORDER BY 1;

-- E0.8 Policy fingerprint (used later by validate_rebuild.sql to compare a
-- cold-start database against live)
SELECT md5(string_agg(
         schemaname || '.' || tablename || ':' || policyname || ':' ||
         cmd || ':' || roles::text || ':' || COALESCE(qual, '') || ':' ||
         COALESCE(with_check, ''),
         '|' ORDER BY schemaname, tablename, policyname
       )) AS public_policy_fingerprint
FROM pg_policies
WHERE schemaname = 'public';
