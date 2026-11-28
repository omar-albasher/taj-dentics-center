-- ═══════════════════════════════════════════════════════════════════════
-- Production Phase #40.2 — Step P1: Pre-flight Read-Only Inspection
-- Target: nmczthzqbpkvweshitvv (PRODUCTION)
-- Mode: STRICTLY READ-ONLY (Zero writes, Zero DDL, PII Masked)
-- ═══════════════════════════════════════════════════════════════════════
\set ON_ERROR_STOP on
SET default_transaction_read_only = on;

\echo '=== 1. Production Identity ==='
SELECT current_database() AS db,
       current_user       AS usr,
       inet_server_addr() AS addr,
       now()              AS ts;

\echo '=== 2. Pre-existing Schema & Invariants ==='
SELECT
  -- C1 baseline constraint
  EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'chk_users_must_change_password_at'
      AND conrelid = 'public.users'::regclass
  ) AS c1_timestamp_check_present,
  -- #40.2 column status
  EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'users'
      AND column_name = 'password_fingerprint'
  ) AS password_fingerprint_column_present,
  -- #40.2 constraint status
  EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'chk_users_must_change_password_fingerprint'
      AND conrelid = 'public.users'::regclass
  ) AS fingerprint_check_present,
  -- #40.2 RPC status
  EXISTS (
    SELECT 1 FROM pg_proc
    WHERE proname = 'set_user_must_change_password'
      AND pronamespace = 'public'::regnamespace
  ) AS setter_rpc_present;

\echo '=== 3. User Counts & Flagged Password State ==='
SELECT
  count(*) AS total_public_users,
  count(*) FILTER (WHERE u.must_change_password = true) AS flagged_users_count,
  count(*) FILTER (WHERE u.must_change_password = false OR u.must_change_password IS NULL) AS unflagged_users_count
FROM public.users u;

\echo '=== 4. Fingerprint Feasibility & Unbackfillable Anomaly Audit ==='
SELECT
  count(*) FILTER (WHERE u.must_change_password = true) AS total_flagged,
  count(*) FILTER (WHERE u.must_change_password = true AND (to_jsonb(u)->>'password_fingerprint') IS NOT NULL) AS already_has_fingerprint,
  count(*) FILTER (WHERE u.must_change_password = true AND au.id IS NOT NULL AND au.encrypted_password IS NOT NULL) AS derivable_from_auth,
  count(*) FILTER (WHERE u.must_change_password = true AND (au.id IS NULL OR au.encrypted_password IS NULL)) AS unbackfillable_anomalies
FROM public.users u
LEFT JOIN auth.users au ON au.id = u.id;

\echo '=== 5. Flagged Users Detail (Audit Record — PII Masked) ==='
SELECT
  u.id,
  regexp_replace(u.email, '(^.).*(@.*$)', '\1***\2') AS masked_email,
  u.role,
  u.is_active,
  u.must_change_password_at,
  (au.encrypted_password IS NOT NULL) AS has_encrypted_password
FROM public.users u
LEFT JOIN auth.users au ON au.id = u.id
WHERE u.must_change_password = true
ORDER BY u.must_change_password_at ASC NULLS LAST;
