-- ═══════════════════════════════════════════════════════════════════════
-- Phase #40.2 — Positive-path probe (secondary ONLY; fully transactional)
--
-- Closes the two behavioral gaps left by the idempotent slices dry-run
-- (staged_40_2_slices_dryrun_20261127.txt), where flagged=0 meant neither the
-- backfill UPDATE nor the fail-closed gate ever touched a row:
--
--   PA1  The backfill statement (verbatim from step1/step2) derives and stores
--        sha256(auth.users.encrypted_password) for a flagged row.
--   PA2  The fail-closed gate (verbatim body from step2) aborts with P0001
--        while any flagged row still has no fingerprint.
--
-- The fingerprint CHECK is dropped *inside this transaction* to recreate the
-- pre-#40.2 write state; ROLLBACK restores it. Residue checks run afterwards
-- in a fresh transaction and must show 0/0 and constraint=1.
--
-- Execute:   psql "<secondary-conn>" -v ON_ERROR_STOP=1 -f <this file>
-- Artifact:  keep the raw terminal capture as the evidence.
-- ═══════════════════════════════════════════════════════════════════════
\set ON_ERROR_STOP on

\echo '--- Identity ---'
SELECT current_database() AS db,
       current_user      AS usr,
       inet_server_addr() AS addr,
       now()             AS ts;

BEGIN;

CREATE TEMP TABLE _probe40_ctx (uid uuid PRIMARY KEY) ON COMMIT DROP;
INSERT INTO _probe40_ctx VALUES
  ('dddddddd-0000-4000-8000-0000000000a1'),  -- PA1: backfill
  ('dddddddd-0000-4000-8000-0000000000b1');  -- PA2: fail-closed gate

-- Defensive: remove any residue from an aborted earlier run (still inside txn).
DELETE FROM public.users WHERE id IN (SELECT uid FROM _probe40_ctx);
DELETE FROM auth.users  WHERE id IN (SELECT uid FROM _probe40_ctx);

\echo '--- Precondition: fingerprint CHECK exists; drop it in-txn to emulate pre-#40.2 ---'
DO $$
DECLARE v integer;
BEGIN
  SELECT count(*) INTO v
  FROM pg_constraint
  WHERE conname = 'chk_users_must_change_password_fingerprint'
    AND conrelid = 'public.users'::regclass;
  IF v <> 1 THEN
    RAISE EXCEPTION 'Probe precondition FAIL: fingerprint CHECK absent (is this the secondary at post-#40.2?)';
  END IF;
  RAISE NOTICE 'Precondition PASS: fingerprint CHECK present';
END $$;

ALTER TABLE public.users DROP CONSTRAINT chk_users_must_change_password_fingerprint;

\echo '--- Setup: PA1 auth + flagged row (no fingerprint) ---'
INSERT INTO auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at
) VALUES (
  '00000000-0000-0000-0000-000000000000',
  'dddddddd-0000-4000-8000-0000000000a1',
  'authenticated', 'authenticated',
  'probe40_a1@example.test',
  '$2a$10$proofsaltproofsaltpr00J9Xk1Q3hV8mZ2sW5tR7uY4iP6aD8fG1hK3lN5oQ',
  now(), now(), now()
);

INSERT INTO public.users (id, email, full_name, role, is_active, must_change_password, must_change_password_at)
VALUES (
  'dddddddd-0000-4000-8000-0000000000a1',
  'probe40_a1@example.test', 'Probe A1', 'trainee', true, true, now()
);

\echo '--- PA1: backfill derives sha256(encrypted_password) ---'
DO $$
DECLARE
  v_uid      uuid := 'dddddddd-0000-4000-8000-0000000000a1';
  v_expected text;
  v_fp       text;
BEGIN
  SELECT encode(sha256(encrypted_password::bytea), 'hex') INTO v_expected
  FROM auth.users WHERE id = v_uid;

  -- Verbatim backfill statement from staged_40_2_step1/step2.
  UPDATE public.users u
  SET password_fingerprint = encode(sha256(au.encrypted_password::bytea), 'hex')
  FROM auth.users au
  WHERE u.id = au.id
    AND u.must_change_password = true
    AND u.password_fingerprint IS NULL
    AND au.encrypted_password IS NOT NULL;

  SELECT password_fingerprint INTO v_fp
  FROM public.users WHERE id = v_uid;

  IF v_fp IS NULL OR v_fp <> v_expected THEN
    RAISE EXCEPTION 'PA1 FAIL: fp=% expected=%', v_fp, v_expected;
  END IF;
  RAISE NOTICE 'PA1 PASS: backfill stored sha256 fingerprint (%)', v_fp;
END $$;

\echo '--- Setup: PA2 flagged row (auth row present, but backfill NOT run on it) ---'
INSERT INTO auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at
) VALUES (
  '00000000-0000-0000-0000-000000000000',
  'dddddddd-0000-4000-8000-0000000000b1',
  'authenticated', 'authenticated',
  'probe40_b1@example.test',
  '$2a$10$newsaltnewsaltnewsalt0B7cE9gJ2kM4nP6rT8vX1zA3dF5hL7oQ9sU2wY4i',
  now(), now(), now()
);

INSERT INTO public.users (id, email, full_name, role, is_active, must_change_password, must_change_password_at)
VALUES (
  'dddddddd-0000-4000-8000-0000000000b1',
  'probe40_b1@example.test', 'Probe B1', 'trainee', true, true, now()
);

\echo '--- PA2: fail-closed gate aborts on a flagged row without fingerprint ---'
-- Gate body copied verbatim from staged_40_2_step2 (DO wrapper -> temp function
-- so the exception can be asserted instead of aborting the script).
CREATE FUNCTION pg_temp._gate40_2() RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  v_unresolved integer;
BEGIN
  SELECT count(*) INTO v_unresolved
  FROM public.users u
  WHERE u.must_change_password = true
    AND u.password_fingerprint IS NULL;

  IF v_unresolved > 0 THEN
    RAISE EXCEPTION
      'Phase 40.2 fail-closed: % صف/صفوف معلّمة بـmust_change_password بلا بصمة قابلة للاشتقاق من auth.users؛ عالجها يدوياً قبل الترحيل',
      v_unresolved
      USING ERRCODE = 'P0001';
  END IF;
END;
$$;

DO $$
BEGIN
  BEGIN
    PERFORM pg_temp._gate40_2();
    RAISE EXCEPTION 'PA2 FAIL: gate accepted a flagged row without fingerprint';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM NOT LIKE 'Phase 40.2 fail-closed%' THEN
      RAISE;
    END IF;
    RAISE NOTICE 'PA2 PASS: gate aborted (%)', SQLERRM;
  END;
END $$;

\echo '--- Cleanup (inside txn; claims cleared for the c1 guard) ---'
SELECT set_config('request.jwt.claims', '', true);
DELETE FROM public.audit_log
 WHERE performed_by IN (SELECT uid FROM _probe40_ctx)
    OR record_id    IN (SELECT uid FROM _probe40_ctx);
DELETE FROM public.users WHERE id IN (SELECT uid FROM _probe40_ctx);
DELETE FROM auth.users  WHERE id IN (SELECT uid FROM _probe40_ctx);

SELECT count(*) AS residue_public_users FROM public.users WHERE id IN (SELECT uid FROM _probe40_ctx);
SELECT count(*) AS residue_auth_users   FROM auth.users  WHERE id IN (SELECT uid FROM _probe40_ctx);

ROLLBACK;

\echo '--- Post-rollback state (fresh transaction) ---'
SELECT count(*) AS residue_public_users FROM public.users
 WHERE id IN ('dddddddd-0000-4000-8000-0000000000a1','dddddddd-0000-4000-8000-0000000000b1');
SELECT count(*) AS residue_auth_users FROM auth.users
 WHERE id IN ('dddddddd-0000-4000-8000-0000000000a1','dddddddd-0000-4000-8000-0000000000b1');
SELECT count(*) AS fingerprint_constraint_present
FROM pg_constraint
WHERE conname = 'chk_users_must_change_password_fingerprint'
  AND conrelid = 'public.users'::regclass;