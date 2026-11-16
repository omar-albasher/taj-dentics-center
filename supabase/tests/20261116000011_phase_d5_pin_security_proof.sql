-- ============================================================================
-- Acceptance Suite: 20261116000011_phase_d5_pin_security_proof.sql
-- Description: Independent verification of the D5 PIN rebuild
--              (20261116000010_phase_d5_pin_security_rebuild.sql)
--
-- Safety: Fully transactional. Enclosed in BEGIN ... ROLLBACK.
-- ============================================================================

BEGIN;

DO $$
DECLARE
  v_suffix text := substr(gen_random_uuid()::text, 1, 6);
  v_a uuid;
  v_b uuid;
  v_cols int;
  v_pk int;
  v_fk int;
  v_rls boolean;
  v_force_rls boolean;
  v_pols int;
  v_user_pin_cols int;
  v_cfg text[];
  v_json jsonb;
  v_rejected boolean;
  v_denied boolean;
  v_leak boolean;
BEGIN
  RAISE NOTICE '=== Starting D5 PIN Rebuild Acceptance Tests ===';

  -- --------------------------------------------------------------------------
  -- Test 1: Static contract - table, columns, RLS, keys, zero policies
  -- --------------------------------------------------------------------------
  ASSERT to_regclass('public.user_pins') IS NOT NULL,
    'public.user_pins does not exist';

  SELECT count(*) INTO v_cols
  FROM pg_attribute
  WHERE attrelid = 'public.user_pins'::regclass
    AND attnum > 0 AND NOT attisdropped;
  ASSERT v_cols = 4, format('user_pins must have exactly 4 columns, found %s', v_cols);

  ASSERT (SELECT attnotnull FROM pg_attribute
          WHERE attrelid = 'public.user_pins'::regclass AND attname = 'pin_hash'),
    'user_pins.pin_hash must be NOT NULL';

  SELECT count(*) INTO v_pk FROM pg_constraint
  WHERE conrelid = 'public.user_pins'::regclass AND contype = 'p';
  ASSERT v_pk = 1, 'user_pins must have exactly one primary key';

  SELECT count(*) INTO v_fk FROM pg_constraint
  WHERE conrelid = 'public.user_pins'::regclass
    AND contype = 'f'
    AND confrelid = 'public.users'::regclass
    AND confdeltype = 'c';
  ASSERT v_fk = 1, 'user_pins must cascade-delete from public.users';

  SELECT relrowsecurity, relforcerowsecurity INTO v_rls, v_force_rls
  FROM pg_class WHERE oid = 'public.user_pins'::regclass;
  ASSERT v_rls = true, 'RLS must be enabled on user_pins';
  ASSERT v_force_rls = false,
    'FORCE RLS must stay off or SECURITY DEFINER (owner) access breaks';

  SELECT count(*) INTO v_pols FROM pg_policies
  WHERE schemaname = 'public' AND tablename = 'user_pins';
  ASSERT v_pols = 0, format('user_pins must have zero policies, found %s', v_pols);

  SELECT count(*) INTO v_user_pin_cols FROM information_schema.columns
  WHERE table_schema = 'public' AND table_name = 'users' AND column_name = 'pin_hash';
  ASSERT v_user_pin_cols = 0,
    'SECURITY LEAK: users.pin_hash exists and would reach clients via select()';

  RAISE NOTICE 'Test 1 Passed: user_pins exists with 4 columns, PK, cascade FK, RLS on (not forced), zero policies, and users has no pin_hash.';

  -- --------------------------------------------------------------------------
  -- Test 2: Static contract - functions, SECURITY DEFINER, search_path
  -- --------------------------------------------------------------------------
  ASSERT to_regprocedure('public.set_user_pin(text)') IS NOT NULL,
    'public.set_user_pin(text) is missing';
  ASSERT to_regprocedure('public.verify_user_pin(text)') IS NOT NULL,
    'public.verify_user_pin(text) is missing';
  ASSERT to_regprocedure('public.has_user_pin()') IS NOT NULL,
    'public.has_user_pin() is missing';

  ASSERT (SELECT prosecdef FROM pg_proc WHERE oid = 'public.set_user_pin(text)'::regprocedure),
    'set_user_pin must be SECURITY DEFINER';
  ASSERT (SELECT prosecdef FROM pg_proc WHERE oid = 'public.verify_user_pin(text)'::regprocedure),
    'verify_user_pin must be SECURITY DEFINER';
  ASSERT (SELECT prosecdef FROM pg_proc WHERE oid = 'public.has_user_pin()'::regprocedure),
    'has_user_pin must be SECURITY DEFINER';

  SELECT proconfig INTO v_cfg FROM pg_proc WHERE oid = 'public.set_user_pin(text)'::regprocedure;
  ASSERT v_cfg IS NOT NULL AND EXISTS (SELECT 1 FROM unnest(v_cfg) c WHERE c LIKE '%pg_temp%'),
    'set_user_pin search_path must include pg_temp';
  ASSERT EXISTS (SELECT 1 FROM unnest(v_cfg) c WHERE c LIKE '%extensions%'),
    'set_user_pin search_path must include extensions (pgcrypto)';

  SELECT proconfig INTO v_cfg FROM pg_proc WHERE oid = 'public.verify_user_pin(text)'::regprocedure;
  ASSERT v_cfg IS NOT NULL AND EXISTS (SELECT 1 FROM unnest(v_cfg) c WHERE c LIKE '%pg_temp%'),
    'verify_user_pin search_path must include pg_temp';
  ASSERT EXISTS (SELECT 1 FROM unnest(v_cfg) c WHERE c LIKE '%extensions%'),
    'verify_user_pin search_path must include extensions (pgcrypto)';

  SELECT proconfig INTO v_cfg FROM pg_proc WHERE oid = 'public.has_user_pin()'::regprocedure;
  ASSERT v_cfg IS NOT NULL AND EXISTS (SELECT 1 FROM unnest(v_cfg) c WHERE c LIKE '%pg_temp%'),
    'has_user_pin search_path must include pg_temp';

  RAISE NOTICE 'Test 2 Passed: all 3 RPCs exist, are SECURITY DEFINER, and pin their search_path.';

  -- --------------------------------------------------------------------------
  -- Test 3: Static contract - grants (table + functions)
  -- --------------------------------------------------------------------------
  ASSERT has_function_privilege('anon', 'public.set_user_pin(text)', 'EXECUTE') = false
     AND has_function_privilege('anon', 'public.verify_user_pin(text)', 'EXECUTE') = false
     AND has_function_privilege('anon', 'public.has_user_pin()', 'EXECUTE') = false,
    'SECURITY LEAK: anon can execute PIN RPCs';
  ASSERT has_function_privilege('authenticated', 'public.set_user_pin(text)', 'EXECUTE') = true
     AND has_function_privilege('authenticated', 'public.verify_user_pin(text)', 'EXECUTE') = true
     AND has_function_privilege('authenticated', 'public.has_user_pin()', 'EXECUTE') = true,
    'REGRESSION: authenticated lost EXECUTE on PIN RPCs';
  ASSERT has_function_privilege('service_role', 'public.set_user_pin(text)', 'EXECUTE') = true
     AND has_function_privilege('service_role', 'public.verify_user_pin(text)', 'EXECUTE') = true
     AND has_function_privilege('service_role', 'public.has_user_pin()', 'EXECUTE') = true,
    'service_role must retain EXECUTE on PIN RPCs';

  ASSERT has_table_privilege('authenticated', 'public.user_pins', 'SELECT') = false
     AND has_table_privilege('authenticated', 'public.user_pins', 'INSERT') = false
     AND has_table_privilege('authenticated', 'public.user_pins', 'UPDATE') = false
     AND has_table_privilege('authenticated', 'public.user_pins', 'DELETE') = false,
    'SECURITY LEAK: authenticated has direct table privileges on user_pins';
  ASSERT has_table_privilege('anon', 'public.user_pins', 'SELECT') = false,
    'SECURITY LEAK: anon can read user_pins';
  ASSERT has_table_privilege('service_role', 'public.user_pins', 'SELECT') = true,
    'service_role must retain access to user_pins';

  RAISE NOTICE 'Test 3 Passed: PIN RPCs are executable by authenticated only; user_pins has zero client grants.';

  -- --------------------------------------------------------------------------
  -- Setup fixtures
  -- --------------------------------------------------------------------------
  INSERT INTO public.users (full_name, email, phone, role, is_active)
  VALUES ('D5 PIN User A', 'd5pin_a_' || v_suffix || '@example.com',
          '+96399' || (floor(random() * 8999999 + 1000000)::bigint)::text, 'admin', true)
  RETURNING id INTO v_a;

  INSERT INTO public.users (full_name, email, phone, role, is_active)
  VALUES ('D5 PIN User B', 'd5pin_b_' || v_suffix || '@example.com',
          '+96399' || (floor(random() * 8999999 + 1000000)::bigint)::text, 'reception', true)
  RETURNING id INTO v_b;

  -- --------------------------------------------------------------------------
  -- Test 4: User A with no PIN yet
  -- --------------------------------------------------------------------------
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', v_a, 'role', 'authenticated',
                      'user_metadata', json_build_object('role', 'admin'))::text, true);
  SET LOCAL ROLE authenticated;

  ASSERT public.has_user_pin() = false, 'has_user_pin must be false before any PIN is set';
  ASSERT public.verify_user_pin('1234') = false, 'verify_user_pin must be false before any PIN is set';

  -- Direct table read must be denied (grant-level defense in depth)
  v_leak := true;
  BEGIN
    PERFORM count(*) FROM public.user_pins;
  EXCEPTION WHEN insufficient_privilege THEN
    v_leak := false;
  END;
  ASSERT v_leak = false, 'SECURITY LEAK: authenticated can SELECT from user_pins!';

  RAISE NOTICE 'Test 4 Passed: user without PIN gets false/false, and authenticated cannot read user_pins.';

  -- --------------------------------------------------------------------------
  -- Test 5: Invalid PIN formats are rejected
  -- --------------------------------------------------------------------------
  v_rejected := false;
  BEGIN
    PERFORM public.set_user_pin('12a4');
  EXCEPTION WHEN raise_exception THEN
    v_rejected := true;
  END;
  ASSERT v_rejected, 'set_user_pin accepted a non-numeric PIN';

  v_rejected := false;
  BEGIN
    PERFORM public.set_user_pin('123');
  EXCEPTION WHEN raise_exception THEN
    v_rejected := true;
  END;
  ASSERT v_rejected, 'set_user_pin accepted a PIN shorter than 4 digits';

  v_rejected := false;
  BEGIN
    PERFORM public.set_user_pin('1234567');
  EXCEPTION WHEN raise_exception THEN
    v_rejected := true;
  END;
  ASSERT v_rejected, 'set_user_pin accepted a PIN longer than 6 digits';

  v_rejected := false;
  BEGIN
    PERFORM public.set_user_pin(NULL);
  EXCEPTION WHEN raise_exception THEN
    v_rejected := true;
  END;
  ASSERT v_rejected, 'set_user_pin accepted a NULL PIN';

  RAISE NOTICE 'Test 5 Passed: invalid, short, long and NULL PINs are all rejected.';

  -- --------------------------------------------------------------------------
  -- Test 6: Set then verify (correct and wrong PIN)
  -- --------------------------------------------------------------------------
  v_json := public.set_user_pin('1234');
  ASSERT v_json->>'success' = 'true', 'set_user_pin did not return success=true';
  ASSERT public.has_user_pin() = true, 'has_user_pin must be true after setting a PIN';
  ASSERT public.verify_user_pin('1234') = true, 'verify_user_pin rejected the correct PIN';
  ASSERT public.verify_user_pin('0000') = false, 'verify_user_pin accepted a wrong PIN';

  RAISE NOTICE 'Test 6 Passed: set/verify round-trip works and wrong PINs fail.';

  -- --------------------------------------------------------------------------
  -- Test 7: User isolation (tenant isolation)
  -- --------------------------------------------------------------------------
  RESET ROLE;
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', v_b, 'role', 'authenticated',
                      'user_metadata', json_build_object('role', 'reception'))::text, true);
  SET LOCAL ROLE authenticated;

  ASSERT public.has_user_pin() = false, 'User B must not inherit User A''s PIN';
  ASSERT public.verify_user_pin('1234') = false, 'User B verified against User A''s PIN!';

  v_json := public.set_user_pin('5678');
  ASSERT v_json->>'success' = 'true', 'User B could not set its own PIN';

  RESET ROLE;
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', v_a, 'role', 'authenticated',
                      'user_metadata', json_build_object('role', 'admin'))::text, true);
  SET LOCAL ROLE authenticated;

  ASSERT public.verify_user_pin('5678') = false, 'User A verified against User B''s PIN!';
  ASSERT public.verify_user_pin('1234') = true, 'User A lost its own PIN after B set one';

  RAISE NOTICE 'Test 7 Passed: PINs are strictly per-user; no cross-user read or verify.';

  -- --------------------------------------------------------------------------
  -- Test 8: anon cannot execute; service_role with no jwt subject gets false
  -- --------------------------------------------------------------------------
  RESET ROLE;
  PERFORM set_config('request.jwt.claims', '', true);
  SET LOCAL ROLE anon;

  v_denied := false;
  BEGIN
    PERFORM public.has_user_pin();
  EXCEPTION WHEN insufficient_privilege THEN
    v_denied := true;
  END;
  ASSERT v_denied, 'SECURITY LEAK: anon executed has_user_pin()';

  v_denied := false;
  BEGIN
    PERFORM public.set_user_pin('1234');
  EXCEPTION WHEN insufficient_privilege THEN
    v_denied := true;
  END;
  ASSERT v_denied, 'SECURITY LEAK: anon executed set_user_pin()';

  RESET ROLE;
  SET LOCAL ROLE service_role;
  ASSERT public.has_user_pin() = false,
    'has_user_pin must return false when auth.uid() is NULL (no subject claim)';

  RAISE NOTICE 'Test 8 Passed: anon is fully denied on the RPCs and NULL-subject contexts return false.';

  -- --------------------------------------------------------------------------
  -- Test 9: Deactivated user cannot use the PIN
  -- --------------------------------------------------------------------------
  RESET ROLE;
  UPDATE public.users SET is_active = false WHERE id = v_a;

  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', v_a, 'role', 'authenticated',
                      'user_metadata', json_build_object('role', 'admin'))::text, true);
  SET LOCAL ROLE authenticated;

  ASSERT public.has_user_pin() = false, 'Inactive user still reports a configured PIN';
  ASSERT public.verify_user_pin('1234') = false, 'Inactive user verified a PIN';

  RESET ROLE;
  RAISE NOTICE 'Test 9 Passed: deactivated accounts are locked out of the PIN path.';

  RAISE NOTICE '=== ALL D5 PIN REBUILD ACCEPTANCE TESTS PASSED SUCCESSFULLY ===';
END;
$$;

ROLLBACK;
