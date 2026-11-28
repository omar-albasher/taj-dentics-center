-- ═══════════════════════════════════════════════════════════════════════
-- Production #40.2 — Post-deploy verification (STRICTLY READ-ONLY)
-- Target: nmczthzqbpkvweshitvv (PRODUCTION)
-- Mode: single READ ONLY transaction, zero writes, zero DDL, PII-free
--
-- Execute:
--   psql "<conn>" -v ON_ERROR_STOP=1 -f production_post_40_2_verify_readonly.sql
--   (capture the full terminal transcript verbatim as the raw evidence)
--
-- Acceptance (see expected values below):
--   S0  identity: inet_server_addr = 2a05:d018:48a:c902:2d02:8d28:a30f:5129
--       (or pooled address + documented state cross-check) and read_only = on
--   S1  both constraints present, convalidated = true, defs match step2
--   S2  password_fingerprint column type = text
--   S3  function prosrc_md5 matches expected LF hashes (below);
--       anon/auth EXECUTE = false on setter, svc EXECUTE = true
--   S4  flagged_without_fp = 0, flagged_bad_length = 0,
--       flagged_fp_mismatch = 0 (fingerprint == sha256(encrypted_password))
--   S5  role split + trainees/auth/public counts (reconcile with Phase 2)
--   S6  NOT from SQL: Edge versions/verify_jwt + backup path/sha256/timestamp
--
-- Expected prosrc md5 (LF, body between AS $$ ... $$, leading/trailing NL):
--   set_user_must_change_password 007eedefac00c8e8308e68b66507c539
--   complete_password_change      9b2562dda67d9ddfe84227ecdc010bfc
--   get_my_password_state         a06a316cdfd41317d343c760cd928a19
-- ═══════════════════════════════════════════════════════════════════════
\set ON_ERROR_STOP on
\pset pager off
\pset footer off

BEGIN TRANSACTION READ ONLY;
SET LOCAL search_path = public, extensions, auth, pg_temp;

\echo '=== S0. Session & Identity ==='
SELECT current_database()          AS db,
       current_user                AS usr,
       inet_server_addr()          AS addr,
       inet_server_port()          AS port,
       current_setting('transaction_read_only') AS read_only,
       now()                       AS ts,
       version()                   AS pg_version;

\echo '=== S1. Constraint definitions ==='
SELECT c.conname,
       c.convalidated,
       c.condeferrable,
       pg_get_constraintdef(c.oid) AS definition
FROM pg_constraint c
WHERE c.conrelid = 'public.users'::regclass
  AND c.conname IN ('chk_users_must_change_password_at',
                    'chk_users_must_change_password_fingerprint')
ORDER BY c.conname;

\echo '=== S2. Fingerprint column ==='
SELECT column_name,
       data_type,
       is_nullable,
       column_default
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'users'
  AND column_name = 'password_fingerprint';

\echo '=== S3. Functions: security, ACL, body hashes, guard probes ==='
SELECT p.proname,
       p.prosecdef                                   AS security_definer,
       pg_get_userbyid(p.proowner)                   AS owner,
       p.proconfig                                   AS proconfig,
       p.proacl::text                                AS acl,
       has_function_privilege('anon', p.oid, 'EXECUTE')          AS anon_exec,
       has_function_privilege('authenticated', p.oid, 'EXECUTE') AS auth_exec,
       has_function_privilege('service_role', p.oid, 'EXECUTE')  AS svc_exec,
       md5(p.prosrc)                                 AS prosrc_md5,
       md5(replace(p.prosrc, E'\r', ''))             AS prosrc_md5_nocr,
       array_length(string_to_array(p.prosrc, E'\n'), 1) AS prosrc_lines,
       length(p.prosrc)                              AS prosrc_len,
       (position('password_fingerprint' in p.prosrc) > 0)            AS mentions_fingerprint,
       (position('v_current_fp = v_stored_fp' in p.prosrc) > 0)      AS has_failclosed_compare,
       (position('بصمة كلمة المرور مفقودة' in p.prosrc) > 0)          AS has_missing_fp_guard,
       (position('RETURN true' in p.prosrc) > 0)                     AS has_failclosed_return
FROM pg_proc p
WHERE p.pronamespace = 'public'::regnamespace
  AND p.proname IN ('set_user_must_change_password',
                    'complete_password_change',
                    'get_my_password_state')
ORDER BY p.proname;

\echo '=== S3b. Source-match against repository bodies ==='
WITH expected(proname, expected_md5) AS (
  VALUES
    ('set_user_must_change_password', '007eedefac00c8e8308e68b66507c539'),
    ('complete_password_change',      '9b2562dda67d9ddfe84227ecdc010bfc'),
    ('get_my_password_state',         'a06a316cdfd41317d343c760cd928a19')
)
SELECT p.proname,
       md5(p.prosrc) AS live_md5,
       e.expected_md5,
       (md5(p.prosrc) = e.expected_md5) AS matches_repo_source
FROM pg_proc p
JOIN expected e USING (proname)
WHERE p.pronamespace = 'public'::regnamespace
ORDER BY p.proname;

\echo '=== S4. Fingerprint integrity (0 required on every violation counter) ==='
SELECT count(*) AS total_users,
       count(*) FILTER (WHERE u.must_change_password) AS flagged,
       count(*) FILTER (WHERE u.must_change_password
                          AND u.password_fingerprint IS NOT NULL) AS flagged_with_fp,
       count(*) FILTER (WHERE u.must_change_password
                          AND u.password_fingerprint IS NULL) AS flagged_without_fp,
       count(*) FILTER (WHERE u.must_change_password
                          AND u.password_fingerprint IS NOT NULL
                          AND length(u.password_fingerprint) <> 64) AS flagged_bad_length,
       count(*) FILTER (WHERE u.must_change_password
                          AND u.password_fingerprint IS NOT NULL
                          AND au.id IS NULL) AS flagged_missing_auth_row,
       count(*) FILTER (WHERE u.must_change_password
                          AND u.password_fingerprint IS NOT NULL
                          AND au.encrypted_password IS NULL) AS flagged_null_enc,
       count(*) FILTER (WHERE u.must_change_password
                          AND u.password_fingerprint IS NOT NULL
                          AND au.encrypted_password IS NOT NULL
                          AND u.password_fingerprint
                              <> encode(sha256(au.encrypted_password::bytea), 'hex')) AS flagged_fp_mismatch
FROM public.users u
LEFT JOIN auth.users au ON au.id = u.id;

\echo '=== S5. Role split and row counts ==='
SELECT u.role,
       count(*) AS n,
       count(*) FILTER (WHERE u.must_change_password) AS flagged,
       count(*) FILTER (WHERE NOT coalesce(u.must_change_password, false)) AS unflagged
FROM public.users u
GROUP BY u.role
ORDER BY u.role;

SELECT (SELECT count(*) FROM public.trainees) AS trainees_rows,
       (SELECT count(*) FROM auth.users)       AS auth_users,
       (SELECT count(*) FROM public.users)     AS public_users;

\echo '=== S6. Non-SQL evidence still required separately ==='
\echo 'EDGE   : supabase functions list / Dashboard -> versions, updated_at, Verify JWT'
\echo 'BACKUP : path + bytes + sha256 + timestamp'

ROLLBACK;
\echo '=== verification finished (read-only transaction rolled back) ==='