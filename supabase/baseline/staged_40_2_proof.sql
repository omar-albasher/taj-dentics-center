-- ═══════════════════════════════════════════════════════════════════════
-- Scope #40.2 — Evidence harness (secondary: pjtgwaxdjtvdzvoazkxv)
--
-- Fully transactional: everything runs inside BEGIN ... ROLLBACK, so the
-- target database is left byte-identical. Run with:
--
--   "C:/Program Files/PostgreSQL/17/bin/psql.exe" "<secondary-conn>" \
--       -v ON_ERROR_STOP=1 -f supabase/baseline/staged_40_2_proof.sql
--
-- Any missing PASS notice or a nonzero exit code = failure. A raw capture of
-- the terminal output is the audit artifact (supabase/baseline/staged_40_2_raw_*.txt).
--
-- Tests:
--  T0   Both CHECK constraints present
--  T0b  Raising the flag without a fingerprint is rejected by the CHECK
--  T0c  No leftover 'FINGERPRINT_INITIAL_STALE' placeholders from the pre-fix run
--  T1   ACL: setter is service_role-only; complete/get_state are auth+service
--  T2   get_my_password_state() = TRUE when public.users row is missing
--       (driven by a real `request.jwt.claims.sub`, not a NULL uid)
--  T3   Setter stores sha256(encrypted_password) and timestamps the flag
--  T4   A GoTrue sign-in bump (updated_at forward, password unchanged) is rejected
--  T5   A real password change clears flag + fingerprint + timestamp
--  T6   Flag with NULL fingerprint (constraint lifted for the test) is rejected
--  T7   authenticated cannot clear its own flag via PostgREST-style RLS
-- ═══════════════════════════════════════════════════════════════════════
\set ON_ERROR_STOP on

BEGIN;

CREATE TEMP TABLE _proof40_2_ctx (uid uuid PRIMARY KEY) ON COMMIT DROP;
INSERT INTO _proof40_2_ctx VALUES ('eeeeeeee-0000-4000-8000-000000000042');

-- Defensive: remove any residue from an aborted earlier run (still inside txn)
DELETE FROM public.users WHERE id = (SELECT uid FROM _proof40_2_ctx);
DELETE FROM auth.users  WHERE id = (SELECT uid FROM _proof40_2_ctx);

\echo '--- T0: constraints ---'
DO $$
DECLARE v integer;
BEGIN
  SELECT count(*) INTO v
  FROM pg_constraint
  WHERE conrelid = 'public.users'::regclass
    AND conname IN ('chk_users_must_change_password_at',
                    'chk_users_must_change_password_fingerprint');
  IF v <> 2 THEN
    RAISE EXCEPTION 'T0 FAIL: expected 2 CHECK constraints, found %', v;
  END IF;
  RAISE NOTICE 'T0 PASS: both CHECK constraints present';
END $$;

\echo '--- T0c: no pre-fix placeholder fingerprints ---'
DO $$
DECLARE v integer;
BEGIN
  SELECT count(*) INTO v
  FROM public.users
  WHERE password_fingerprint = 'FINGERPRINT_INITIAL_STALE';
  IF v <> 0 THEN
    RAISE EXCEPTION
      'T0c FAIL: % placeholder fingerprint(s) remain; set them to NULL and re-run the migration', v;
  END IF;
  RAISE NOTICE 'T0c PASS: no placeholder fingerprints';
END $$;

\echo '--- T1: function ACL matrix ---'
DO $$
BEGIN
  IF has_function_privilege('anon', 'public.set_user_must_change_password(uuid)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.set_user_must_change_password(uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'T1 FAIL: setter executable by anon/authenticated';
  END IF;
  IF NOT has_function_privilege('service_role', 'public.set_user_must_change_password(uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'T1 FAIL: setter not executable by service_role';
  END IF;
  IF has_function_privilege('anon', 'public.complete_password_change()', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.complete_password_change()', 'EXECUTE') THEN
    RAISE EXCEPTION 'T1 FAIL: complete_password_change ACL is wrong';
  END IF;
  IF has_function_privilege('anon', 'public.get_my_password_state()', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.get_my_password_state()', 'EXECUTE') THEN
    RAISE EXCEPTION 'T1 FAIL: get_my_password_state ACL is wrong';
  END IF;
  RAISE NOTICE 'T1 PASS: setter=service_role only; complete/get_state=authenticated+service';
END $$;

\echo '--- Setup: test auth user + jwt sub ---'
-- The functions only hash the stored value; the literal need not be a real
-- bcrypt digest (GoTrue is never invoked by this harness and everything rolls back).
INSERT INTO auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at
)
SELECT '00000000-0000-0000-0000-000000000000', uid, 'authenticated', 'authenticated',
       'proof40_2_' || uid || '@example.test',
       '$2a$10$proofsaltproofsaltpr00J9Xk1Q3hV8mZ2sW5tR7uY4iP6aD8fG1hK3lN5oQ',
       now(), now(), now()
FROM _proof40_2_ctx;

\echo '--- T2: fail-closed state while public.users row is missing ---'
DO $$
DECLARE v_uid uuid := (SELECT uid FROM _proof40_2_ctx);
BEGIN
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', v_uid::text, 'role', 'authenticated')::text, true);
  IF public.get_my_password_state() IS NOT TRUE THEN
    RAISE EXCEPTION 'T2 FAIL: expected TRUE for missing public.users row';
  END IF;
  RAISE NOTICE 'T2 PASS: TRUE with real jwt sub and missing users row';
END $$;

INSERT INTO public.users (id, email, full_name, role, is_active)
SELECT uid, 'proof40_2_' || uid || '@example.test', 'Proof User', 'trainee', true
FROM _proof40_2_ctx;

\echo '--- T0b: CHECK blocks flag without fingerprint ---'
DO $$
BEGIN
  BEGIN
    UPDATE public.users
       SET must_change_password = true,
           must_change_password_at = now(),
           password_fingerprint = NULL
     WHERE id = (SELECT uid FROM _proof40_2_ctx);
    RAISE EXCEPTION 'T0b FAIL: flag raised without fingerprint';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE '%chk_users_must_change_password_fingerprint%' THEN
      RAISE EXCEPTION 'T0b FAIL: expected fingerprint constraint violation, got: %', SQLERRM;
    END IF;
    RAISE NOTICE 'T0b PASS: rejected by fingerprint constraint (%)', SQLERRM;
  END;
END $$;

\echo '--- T3: setter stores the fingerprint ---'
DO $$
DECLARE
  v_uid      uuid := (SELECT uid FROM _proof40_2_ctx);
  v_expected text;
  v_flag     boolean;
  v_fp       text;
  v_at       timestamptz;
BEGIN
  SELECT encode(sha256(encrypted_password::bytea), 'hex') INTO v_expected
  FROM auth.users WHERE id = v_uid;

  PERFORM public.set_user_must_change_password(v_uid);

  SELECT must_change_password, password_fingerprint, must_change_password_at
  INTO v_flag, v_fp, v_at
  FROM public.users WHERE id = v_uid;

  IF v_flag IS NOT TRUE OR v_fp IS DISTINCT FROM v_expected OR v_at IS NULL THEN
    RAISE EXCEPTION 'T3 FAIL: flag=%, fp_match=%, at_null=%',
      v_flag, v_fp IS NOT DISTINCT FROM v_expected, v_at IS NULL;
  END IF;
  RAISE NOTICE 'T3 PASS: fingerprint %', v_fp;
END $$;

\echo '--- T4: GoTrue sign-in bump must not clear the flag ---'
DO $$
DECLARE v_uid uuid := (SELECT uid FROM _proof40_2_ctx);
BEGIN
  -- Simulate a successful sign-in: GoTrue moves updated_at forward, password untouched
  UPDATE auth.users SET updated_at = now() + interval '1 minute' WHERE id = v_uid;

  BEGIN
    PERFORM public.complete_password_change();
    RAISE EXCEPTION 'T4 FAIL: sign-in bump accepted';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'لم يتم تغيير كلمة المرور بعد' THEN RAISE; END IF;
    RAISE NOTICE 'T4 PASS: rejected (%)', SQLERRM;
  END;
END $$;

\echo '--- T5: real password change clears everything ---'
DO $$
DECLARE
  v_uid  uuid := (SELECT uid FROM _proof40_2_ctx);
  v_flag boolean;
  v_fp   text;
  v_at   timestamptz;
BEGIN
  -- Simulate the real password change: auth.users.encrypted_password becomes a new value
  UPDATE auth.users
     SET encrypted_password = '$2a$10$newsaltnewsaltnewsalt0B7cE9gJ2kM4nP6rT8vX1zA3dF5hL7oQ9sU2wY4i',
         updated_at = now()
   WHERE id = v_uid;

  PERFORM public.complete_password_change();

  SELECT must_change_password, password_fingerprint, must_change_password_at
  INTO v_flag, v_fp, v_at
  FROM public.users WHERE id = v_uid;

  IF v_flag IS DISTINCT FROM false OR v_fp IS NOT NULL OR v_at IS NOT NULL THEN
    RAISE EXCEPTION 'T5 FAIL: flag=%, fp=%, at=%', v_flag, v_fp, v_at;
  END IF;
  RAISE NOTICE 'T5 PASS: flag, fingerprint and timestamp cleared';
END $$;

\echo '--- T6: missing fingerprint is fail-closed ---'
ALTER TABLE public.users DROP CONSTRAINT chk_users_must_change_password_fingerprint;

DO $$
DECLARE v_uid uuid := (SELECT uid FROM _proof40_2_ctx);
BEGIN
  UPDATE public.users
     SET must_change_password = true,
         password_fingerprint = NULL,
         must_change_password_at = now()
   WHERE id = v_uid;

  BEGIN
    PERFORM public.complete_password_change();
    RAISE EXCEPTION 'T6 FAIL: missing fingerprint accepted';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'بصمة كلمة المرور مفقودة؛ يرجى مراجعة الإدارة' THEN RAISE; END IF;
    RAISE NOTICE 'T6 PASS: rejected (%)', SQLERRM;
  END;

  -- Restore a constraint-valid state before re-adding the CHECK
  UPDATE public.users
     SET must_change_password = false, must_change_password_at = NULL
   WHERE id = v_uid;
END $$;

ALTER TABLE public.users ADD CONSTRAINT chk_users_must_change_password_fingerprint
  CHECK (must_change_password = false OR password_fingerprint IS NOT NULL);

\echo '--- T7: authenticated cannot clear its own flag ---'
DO $$
DECLARE
  v_uid  uuid := (SELECT uid FROM _proof40_2_ctx);
  v_rows integer;
  v_flag boolean;
BEGIN
  PERFORM public.set_user_must_change_password(v_uid);

  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', v_uid::text, 'role', 'authenticated')::text, true);

  UPDATE public.users
     SET must_change_password = false, password_fingerprint = NULL
   WHERE id = v_uid;
  GET DIAGNOSTICS v_rows = ROW_COUNT;

  EXECUTE 'RESET ROLE';

  IF v_rows <> 0 THEN
    RAISE EXCEPTION 'T7 FAIL: authenticated cleared its own flag (% rows)', v_rows;
  END IF;

  SELECT must_change_password INTO v_flag FROM public.users WHERE id = v_uid;
  IF v_flag IS NOT TRUE THEN
    RAISE EXCEPTION 'T7 FAIL: flag was cleared';
  END IF;
  RAISE NOTICE 'T7 PASS: RLS denied the self-update; flag intact';
END $$;

\echo '--- Cleanup + residue check ---'
-- Clear the JWT claims first: the c1 guard raises if a claimed actor deletes its
-- own users row ("لا يمكنك حذف حسابك الخاص").
SELECT set_config('request.jwt.claims', '', true);
DELETE FROM public.audit_log WHERE performed_by = (SELECT uid FROM _proof40_2_ctx) OR record_id = (SELECT uid FROM _proof40_2_ctx);
DELETE FROM public.users WHERE id = (SELECT uid FROM _proof40_2_ctx);
DELETE FROM auth.users  WHERE id = (SELECT uid FROM _proof40_2_ctx);

SELECT count(*) AS residue_public_users
FROM public.users WHERE id = 'eeeeeeee-0000-4000-8000-000000000042';
SELECT count(*) AS residue_auth_users
FROM auth.users WHERE id = 'eeeeeeee-0000-4000-8000-000000000042';

ROLLBACK;
