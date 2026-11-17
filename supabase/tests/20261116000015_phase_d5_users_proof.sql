-- ============================================================================
-- Acceptance Suite: 20261116000015_phase_d5_users_proof.sql
-- Description: Independent verification of Phase D5 Users hardening (U1 + U2)
--
-- Safety: Fully transactional (BEGIN ... ROLLBACK). All fixtures live in
-- public.users with d5u_proof_* emails and disappear on rollback.
--
-- Visibility carrier: RAISE NOTICE is only shown by some SQL clients, so the
-- whole suite runs inside a TEMPORARY function that both emits NOTICE lines
-- and RETURNS them as a result set. The final SELECT therefore shows every
-- proof line as a grid row even when notices are hidden. The function and all
-- fixtures are created inside the transaction and vanish on ROLLBACK.
-- ============================================================================

BEGIN;

CREATE FUNCTION pg_temp.run_d5_users_proof()
RETURNS TABLE (line_no integer, message text)
LANGUAGE plpgsql
AS $proof$
DECLARE
  v_msgs text[] := '{}';
  v_admin1 uuid;
  v_admin2 uuid;
  v_reception uuid;
  v_trainee uuid;
  v_role public.user_role;
  v_hook jsonb;
  v_rejected boolean;
BEGIN
  RAISE NOTICE '=== Starting Phase D5 Users Hardening Proof ===';
  v_msgs := array_append(v_msgs, '=== Starting Phase D5 Users Hardening Proof ===');

  -- --------------------------------------------------------------------------
  -- Fixtures (transactional)
  -- --------------------------------------------------------------------------
  INSERT INTO public.users (email, full_name, role, is_active)
  VALUES ('d5u_proof_admin1@example.com', 'Proof Admin One', 'admin', true)
  RETURNING id INTO v_admin1;

  INSERT INTO public.users (email, full_name, role, is_active)
  VALUES ('d5u_proof_admin2@example.com', 'Proof Admin Two', 'admin', true)
  RETURNING id INTO v_admin2;

  INSERT INTO public.users (email, full_name, role, is_active)
  VALUES ('d5u_proof_reception@example.com', 'Proof Reception', 'reception', true)
  RETURNING id INTO v_reception;

  INSERT INTO public.users (email, full_name, role, is_active)
  VALUES ('d5u_proof_trainee@example.com', 'Proof Trainee', 'trainee', true)
  RETURNING id INTO v_trainee;

  -- --------------------------------------------------------------------------
  -- Test 1: get_user_role() is DB-backed and default-denies inactive users
  -- --------------------------------------------------------------------------
  -- The JWT deliberately claims 'reception' while the DB row says 'admin':
  -- a JWT-based implementation would return reception.
  PERFORM set_config('request.jwt.claims',
    json_build_object(
      'sub', v_admin1,
      'role', 'authenticated',
      'user_metadata', json_build_object('role', 'reception')
    )::text, true);
  SET LOCAL ROLE authenticated;

  SELECT public.get_user_role() INTO v_role;
  RESET ROLE;

  ASSERT v_role = 'admin'::public.user_role,
    format('expected DB role admin, got %s', v_role);

  -- Deactivate through the trusted psql path, then read again with the SAME
  -- stale metadata claim: access must be gone immediately.
  PERFORM set_config('request.jwt.claims', '', true);
  UPDATE public.users SET is_active = false WHERE id = v_admin1;

  PERFORM set_config('request.jwt.claims',
    json_build_object(
      'sub', v_admin1,
      'role', 'authenticated',
      'user_metadata', json_build_object('role', 'admin')
    )::text, true);
  SET LOCAL ROLE authenticated;

  SELECT public.get_user_role() INTO v_role;
  RESET ROLE;

  ASSERT v_role IS NULL, 'inactive user must resolve to NULL (default deny)';

  -- Restore, then prove non-staff roles are still covered by the function.
  PERFORM set_config('request.jwt.claims', '', true);
  UPDATE public.users SET is_active = true WHERE id = v_admin1;

  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', v_trainee, 'role', 'authenticated')::text, true);
  SET LOCAL ROLE authenticated;

  SELECT public.get_user_role() INTO v_role;
  RESET ROLE;

  ASSERT v_role = 'trainee'::public.user_role,
    format('expected trainee role, got %s', v_role);

  RAISE NOTICE 'Test 1 Passed: get_user_role reads the DB, ignores stale JWT metadata, denies inactive users and still resolves trainees.';
  v_msgs := array_append(v_msgs, 'Test 1 Passed: get_user_role reads the DB, ignores stale JWT metadata, denies inactive users and still resolves trainees.');

  -- --------------------------------------------------------------------------
  -- Test 2: custom_access_token_hook filters inactive users
  -- --------------------------------------------------------------------------
  v_hook := public.custom_access_token_hook(
    jsonb_build_object('user_id', v_admin2, 'claims', '{}'::jsonb));
  ASSERT v_hook->'claims'->'user_metadata'->>'role' = 'admin',
    'hook must copy the live role for active users';

  PERFORM set_config('request.jwt.claims', '', true);
  UPDATE public.users SET is_active = false WHERE id = v_admin2;

  v_hook := public.custom_access_token_hook(
    jsonb_build_object('user_id', v_admin2, 'claims', '{}'::jsonb));
  ASSERT v_hook->'claims'->'user_metadata'->>'role' = 'none',
    'hook must emit none for inactive users';

  UPDATE public.users SET is_active = true WHERE id = v_admin2;

  v_hook := public.custom_access_token_hook(
    jsonb_build_object('user_id', gen_random_uuid(), 'claims', '{}'::jsonb));
  ASSERT v_hook->'claims'->'user_metadata'->>'role' = 'none',
    'hook must emit none for unknown users';

  RAISE NOTICE 'Test 2 Passed: token hook emits the live role only for active users and none otherwise.';
  v_msgs := array_append(v_msgs, 'Test 2 Passed: token hook emits the live role only for active users and none otherwise.');

  -- --------------------------------------------------------------------------
  -- Test 3: guard blocks self changes and protects the last active admin
  -- --------------------------------------------------------------------------
  -- Temporarily deactivate any pre-existing active admins in this transaction so
  -- v_admin1 and v_admin2 are the only active admins during the invariant test.
  -- Everything will be rolled back cleanly at the end of the transaction.
  PERFORM set_config('request.jwt.claims', '', true);
  UPDATE public.users
  SET is_active = false
  WHERE role = 'admin'
    AND is_active = true
    AND id NOT IN (v_admin1, v_admin2);

  PERFORM set_config('request.jwt.claims',
    json_build_object(
      'sub', v_admin1,
      'role', 'authenticated',
      'user_metadata', json_build_object('role', 'admin')
    )::text, true);
  SET LOCAL ROLE authenticated;

  v_rejected := false;
  BEGIN
    UPDATE public.users SET role = 'reception' WHERE id = v_admin1;
  EXCEPTION WHEN raise_exception THEN
    v_rejected := true;
  END;
  ASSERT v_rejected, 'self role change must be blocked';

  v_rejected := false;
  BEGIN
    UPDATE public.users SET is_active = false WHERE id = v_admin1;
  EXCEPTION WHEN raise_exception THEN
    v_rejected := true;
  END;
  ASSERT v_rejected, 'self deactivation must be blocked';

  v_rejected := false;
  BEGIN
    DELETE FROM public.users WHERE id = v_admin1;
  EXCEPTION WHEN raise_exception THEN
    v_rejected := true;
  END;
  ASSERT v_rejected, 'self deletion must be blocked';

  RESET ROLE;

  -- PostgREST requests always carry claims; simulate the service_role path
  -- (no sub, non-empty claims) - the guard must still protect the last admin.
  PERFORM set_config('request.jwt.claims',
    json_build_object('role', 'service_role')::text, true);
  SET LOCAL ROLE service_role;

  -- Demoting a non-last admin must remain possible.
  UPDATE public.users SET role = 'reception' WHERE id = v_admin2;
  SELECT role INTO v_role FROM public.users WHERE id = v_admin2;
  ASSERT v_role = 'reception'::public.user_role,
    'demoting a non-last admin must be allowed';

  v_rejected := false;
  BEGIN
    UPDATE public.users SET role = 'reception' WHERE id = v_admin1;
  EXCEPTION WHEN raise_exception THEN
    v_rejected := true;
  END;
  ASSERT v_rejected, 'last active admin demotion must be blocked even for service_role HTTP calls';

  v_rejected := false;
  BEGIN
    UPDATE public.users SET is_active = false WHERE id = v_admin1;
  EXCEPTION WHEN raise_exception THEN
    v_rejected := true;
  END;
  ASSERT v_rejected, 'last active admin deactivation must be blocked even for service_role HTTP calls';

  v_rejected := false;
  BEGIN
    DELETE FROM public.users WHERE id = v_admin1;
  EXCEPTION WHEN raise_exception THEN
    v_rejected := true;
  END;
  ASSERT v_rejected, 'last active admin deletion must be blocked even for service_role HTTP calls';

  -- Profile-only edits must not be affected by the guard.
  UPDATE public.users SET full_name = 'Proof Admin One Renamed' WHERE id = v_admin1;

  RESET ROLE;

  RAISE NOTICE 'Test 3 Passed: self demotion/deactivation/deletion blocked; last active admin protected under authenticated and service_role claims; profile edits untouched.';
  v_msgs := array_append(v_msgs, 'Test 3 Passed: self demotion/deactivation/deletion blocked; last active admin protected under authenticated and service_role claims; profile edits untouched.');

  -- --------------------------------------------------------------------------
  -- Test 4: trusted silent path (empty request.jwt.claims) bypasses the guard
  -- --------------------------------------------------------------------------
  PERFORM set_config('request.jwt.claims', '', true);
  UPDATE public.users SET role = 'reception' WHERE id = v_admin1;
  SELECT role INTO v_role FROM public.users WHERE id = v_admin1;
  ASSERT v_role = 'reception'::public.user_role,
    'migration/psql path (empty claims) must bypass the guard';

  RAISE NOTICE 'Test 4 Passed: empty request.jwt.claims (migrations/psql/pg_cron) bypasses the guard.';
  v_msgs := array_append(v_msgs, 'Test 4 Passed: empty request.jwt.claims (migrations/psql/pg_cron) bypasses the guard.');

  -- --------------------------------------------------------------------------
  -- Test 5: function wiring (SECURITY DEFINER, search_path, lock, trigger)
  -- --------------------------------------------------------------------------
  ASSERT EXISTS (
    SELECT 1 FROM pg_proc
    WHERE oid = 'public.get_user_role()'::regprocedure
      AND prosecdef
      AND EXISTS (
        SELECT 1 FROM unnest(proconfig) AS c WHERE c LIKE 'search_path=%'
      )
  ), 'get_user_role must be SECURITY DEFINER with a pinned search_path';

  ASSERT EXISTS (
    SELECT 1 FROM pg_proc
    WHERE oid = 'public.custom_access_token_hook(jsonb)'::regprocedure
      AND prosecdef
      AND prosrc LIKE '%is_active%'
  ), 'token hook must be SECURITY DEFINER and filter is_active';

  ASSERT EXISTS (
    SELECT 1 FROM pg_proc
    WHERE oid = 'public.c1_guard_user_admin_changes()'::regprocedure
      AND prosecdef
      AND prosrc LIKE '%pg_advisory_xact_lock%'
  ), 'guard function must take the advisory lock';

  ASSERT EXISTS (
    SELECT 1
    FROM pg_trigger t
    JOIN pg_class c ON c.oid = t.tgrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relname = 'users'
      AND t.tgname = 'trg_guard_users_admin_changes'
      AND t.tgenabled = 'O'
      AND (t.tgtype & 27) = 27   -- BEFORE(2) + UPDATE(16) + DELETE(8) + ROW(1)
  ), 'guard trigger must be enabled BEFORE UPDATE OR DELETE FOR EACH ROW on users';

  RAISE NOTICE 'Test 5 Passed: SECURITY DEFINER + pinned search_path, advisory lock present, BEFORE UPDATE/DELETE trigger enabled.';
  v_msgs := array_append(v_msgs, 'Test 5 Passed: SECURITY DEFINER + pinned search_path, advisory lock present, BEFORE UPDATE/DELETE trigger enabled.');

  -- --------------------------------------------------------------------------
  -- Test 6: grants stay minimal
  -- --------------------------------------------------------------------------
  ASSERT has_function_privilege('authenticated', 'public.get_user_role()', 'EXECUTE'),
    'authenticated must keep EXECUTE on get_user_role (RLS policies depend on it)';
  ASSERT has_function_privilege('anon', 'public.get_user_role()', 'EXECUTE'),
    'anon grant on get_user_role must be preserved (returns NULL without a subject)';
  ASSERT NOT has_function_privilege('authenticated', 'public.custom_access_token_hook(jsonb)', 'EXECUTE'),
    'authenticated must not execute the token hook';
  ASSERT NOT has_function_privilege('anon', 'public.custom_access_token_hook(jsonb)', 'EXECUTE'),
    'anon must not execute the token hook';

  RAISE NOTICE 'Test 6 Passed: get_user_role grants retained; token hook execute denied to anon/authenticated.';
  v_msgs := array_append(v_msgs, 'Test 6 Passed: get_user_role grants retained; token hook execute denied to anon/authenticated.');

  RAISE NOTICE '=== ALL D5 USERS HARDENING PROOF CHECKS PASSED SUCCESSFULLY ===';
  v_msgs := array_append(v_msgs, '=== ALL D5 USERS HARDENING PROOF CHECKS PASSED SUCCESSFULLY ===');

  RETURN QUERY
  SELECT i::integer, v_msgs[i]
  FROM generate_subscripts(v_msgs, 1) AS i;
END;
$proof$;

SELECT * FROM pg_temp.run_d5_users_proof();

ROLLBACK;
