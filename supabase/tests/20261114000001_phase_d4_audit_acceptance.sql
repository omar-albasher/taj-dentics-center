-- ============================================================================
-- Phase D4.1 — Acceptance Test Suite: Audit Log & Actor Hardening
-- ============================================================================
-- Safe & Idempotent: Runs inside a strict TRANSACTION with explicit ROLLBACK.
-- No permanent test data will be written to the database.
-- ============================================================================

BEGIN;

DO $$
DECLARE
  v_admin_id uuid;
  v_second_user_id uuid;
  v_second_user_role text;
  v_course_id uuid;
  v_mat_id uuid := gen_random_uuid();
  v_audit_row record;
BEGIN
  RAISE NOTICE '=== Starting Phase D4.1 Audit Log Hardening Acceptance Suite ===';

  -- --------------------------------------------------------------------------
  -- STEP 1: Verify Schema Columns & Data Types on audit_log
  -- --------------------------------------------------------------------------
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'audit_log' AND column_name = 'actor_source'
  ) THEN
    RAISE EXCEPTION 'TEST 1 FAILED: Column actor_source missing from public.audit_log';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'audit_log' AND column_name = 'actor_role'
  ) THEN
    RAISE EXCEPTION 'TEST 1 FAILED: Column actor_role missing from public.audit_log';
  END IF;

  RAISE NOTICE 'Test 1 Passed: audit_log schema columns verified.';

  -- --------------------------------------------------------------------------
  -- STEP 2: Verify High-Performance Indexes
  -- --------------------------------------------------------------------------
  IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND tablename = 'audit_log' AND indexname = 'idx_audit_log_performed_at') THEN
    RAISE EXCEPTION 'TEST 2 FAILED: Index idx_audit_log_performed_at missing';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND tablename = 'audit_log' AND indexname = 'idx_audit_log_table_name') THEN
    RAISE EXCEPTION 'TEST 2 FAILED: Index idx_audit_log_table_name missing';
  END IF;

  RAISE NOTICE 'Test 2 Passed: Audit log performance indexes verified.';

  -- --------------------------------------------------------------------------
  -- STEP 3: Verify Function Security & Privileges
  -- --------------------------------------------------------------------------
  IF has_function_privilege('anon', 'public.audit_trigger_func()', 'EXECUTE') THEN
    RAISE EXCEPTION 'TEST 3 FAILED: anon role still has EXECUTE on audit_trigger_func';
  END IF;

  IF NOT has_function_privilege('authenticated', 'public.audit_trigger_func()', 'EXECUTE') THEN
    RAISE EXCEPTION 'TEST 3 FAILED: authenticated role lacks EXECUTE on audit_trigger_func';
  END IF;

  RAISE NOTICE 'Test 3 Passed: audit_trigger_func execution privileges verified.';

  -- --------------------------------------------------------------------------
  -- STEP 4: Verify Trigger Existence on Financial & Material Tables
  -- --------------------------------------------------------------------------
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_z_audit_payment_refunds' AND NOT tgisinternal) THEN
    RAISE EXCEPTION 'TEST 4 FAILED: Trigger trg_z_audit_payment_refunds missing';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_z_audit_fee_adjustments' AND NOT tgisinternal) THEN
    RAISE EXCEPTION 'TEST 4 FAILED: Trigger trg_z_audit_fee_adjustments missing';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_z_audit_enrollment_withdrawals' AND NOT tgisinternal) THEN
    RAISE EXCEPTION 'TEST 4 FAILED: Trigger trg_z_audit_enrollment_withdrawals missing';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_z_audit_course_materials' AND NOT tgisinternal) THEN
    RAISE EXCEPTION 'TEST 4 FAILED: Trigger trg_z_audit_course_materials missing';
  END IF;

  RAISE NOTICE 'Test 4 Passed: All 4 new audit triggers verified.';

  -- --------------------------------------------------------------------------
  -- STEP 5: Behavioral Provenance Testing
  -- --------------------------------------------------------------------------
  SELECT id INTO v_admin_id FROM public.users WHERE role = 'admin' AND is_active = true LIMIT 1;
  SELECT id INTO v_course_id FROM public.courses LIMIT 1;

  IF v_admin_id IS NULL OR v_course_id IS NULL THEN
    RAISE EXCEPTION 'TEST 5 PREREQUISITE FAILED: active admin or course not found';
  END IF;

  -- Select a second active user if available, otherwise reuse admin
  SELECT id, role::text INTO v_second_user_id, v_second_user_role
  FROM public.users
  WHERE id <> v_admin_id AND is_active = true
  LIMIT 1;

  IF v_second_user_id IS NULL THEN
    v_second_user_id := v_admin_id;
    v_second_user_role := 'admin';
  END IF;

  -- 5.1 Test Priority A (JWT Simulation)
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_admin_id::text,
      'role', 'authenticated',
      'user_metadata', json_build_object('role', 'admin')
    )::text,
    true
  );
  PERFORM set_config('request.jwt.claim.sub', v_admin_id::text, true);
  PERFORM set_config('app.actor_id', '', true);

  INSERT INTO public.course_materials (
    id, course_id, title, material_type, file_path, file_size_bytes, is_published, created_by
  ) VALUES (
    v_mat_id, v_course_id, 'Audit D4 Test Mat A', 'file', 'materials/audit_test_a.pdf', 1024, true, v_admin_id
  );

  SELECT * INTO v_audit_row
  FROM public.audit_log
  WHERE table_name = 'course_materials' AND record_id = v_mat_id AND operation = 'INSERT'
  ORDER BY id DESC LIMIT 1;

  IF v_audit_row.id IS NULL THEN
    RAISE EXCEPTION 'TEST 5.1 FAILED: No audit_log row inserted for course_materials';
  END IF;

  IF v_audit_row.performed_by <> v_admin_id OR v_audit_row.actor_source <> 'jwt' OR v_audit_row.actor_role <> 'admin' THEN
    RAISE EXCEPTION 'TEST 5.1 FAILED: JWT Provenance mismatch: actor=%, source=%, role=%, expected actor=%, source=jwt, role=admin',
      v_audit_row.performed_by, v_audit_row.actor_source, v_audit_row.actor_role, v_admin_id;
  END IF;
  RAISE NOTICE 'Test 5.1 Passed: JWT Authenticated provenance successfully captured.';

  -- 5.2 Test Priority B (RPC Context Simulation via app.actor_id with JWT cleared)
  PERFORM set_config('request.jwt.claims', '', true);
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('app.actor_id', v_second_user_id::text, true);

  UPDATE public.course_materials
  SET title = 'Audit D4 Test Mat B'
  WHERE id = v_mat_id;

  SELECT * INTO v_audit_row
  FROM public.audit_log
  WHERE table_name = 'course_materials' AND record_id = v_mat_id AND operation = 'UPDATE'
  ORDER BY id DESC LIMIT 1;

  IF v_audit_row.performed_by <> v_second_user_id OR v_audit_row.actor_source <> 'rpc_context' OR v_audit_row.actor_role <> v_second_user_role THEN
    RAISE EXCEPTION 'TEST 5.2 FAILED: RPC Context Provenance mismatch: actor=%, source=%, role=%, expected actor=%, source=rpc_context, role=%',
      v_audit_row.performed_by, v_audit_row.actor_source, v_audit_row.actor_role, v_second_user_id, v_second_user_role;
  END IF;
  RAISE NOTICE 'Test 5.2 Passed: RPC Context (app.actor_id) provenance successfully captured.';

  -- 5.3 Test Priority C (Fallback when all contexts are empty)
  PERFORM set_config('request.jwt.claims', '', true);
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('app.actor_id', '', true);

  DELETE FROM public.course_materials WHERE id = v_mat_id;

  SELECT * INTO v_audit_row
  FROM public.audit_log
  WHERE table_name = 'course_materials' AND record_id = v_mat_id AND operation = 'DELETE'
  ORDER BY id DESC LIMIT 1;

  IF v_audit_row.actor_source <> 'system' THEN
    RAISE EXCEPTION 'TEST 5.3 FAILED: Expected system provenance for uncontextualized DELETE, got %', v_audit_row.actor_source;
  END IF;
  RAISE NOTICE 'Test 5.3 Passed: Fallback system provenance verified for uncontextualized operations.';

  RAISE NOTICE '====================================================================';
  RAISE NOTICE 'SUCCESS: ALL PHASE D4.1 AUDIT LOG & ACTOR HARDENING TESTS PASSED!';
  RAISE NOTICE '====================================================================';

END $$;

ROLLBACK;
