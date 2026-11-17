-- ============================================================================
-- Rebuild Validation Script (#47)
--
-- Compares public schema state against the authoritative baseline fingerprint.
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
BEGIN
  -- 1. Gather live counts
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

  -- 2. Compute policy fingerprint
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

  -- Return rows
  RETURN QUERY VALUES
    ('C01', 'Tables in public', '31', v_tables::text, CASE WHEN v_tables = 31 THEN 'PASS' ELSE 'FAIL' END),
    ('C02', 'Views in public', '26', v_views::text, CASE WHEN v_views = 26 THEN 'PASS' ELSE 'FAIL' END),
    ('C03', 'Functions in public', '87', v_functions::text, CASE WHEN v_functions = 87 THEN 'PASS' ELSE 'FAIL' END),
    ('C04', 'Policies in public', '59', v_policies::text, CASE WHEN v_policies = 59 THEN 'PASS' ELSE 'FAIL' END),
    ('C05', 'Triggers in public', '50', v_triggers::text, CASE WHEN v_triggers = 50 THEN 'PASS' ELSE 'FAIL' END),
    ('C06', 'Indexes in public', '87', v_indexes::text, CASE WHEN v_indexes = 87 THEN 'PASS' ELSE 'FAIL' END),
    ('C07', 'Sequences in public', '3', v_sequences::text, CASE WHEN v_sequences = 3 THEN 'PASS' ELSE 'FAIL' END),
    ('C08', 'Enums in public', '8', v_enums::text, CASE WHEN v_enums = 8 THEN 'PASS' ELSE 'FAIL' END),
    ('C09', 'RLS Enabled Tables', '31', v_rls_enabled::text, CASE WHEN v_rls_enabled = 31 THEN 'PASS' ELSE 'FAIL' END),
    ('C10', 'RLS Forced Tables', '0', v_rls_forced::text, CASE WHEN v_rls_forced = 0 THEN 'PASS' ELSE 'FAIL' END),
    ('C11', 'Unpinned SecDef Functions', '0', v_unpinned::text, CASE WHEN v_unpinned = 0 THEN 'PASS' ELSE 'FAIL' END),
    ('C12', 'Policy MD5 Fingerprint', 'bacff6e12c60748988fc0831fe4307ec', v_fingerprint, CASE WHEN v_fingerprint = 'bacff6e12c60748988fc0831fe4307ec' THEN 'PASS' ELSE 'FAIL' END);
END;
$val$;

SELECT * FROM pg_temp.validate_database_rebuild();
