-- ============================================================================
-- Phase D4.1.1 — Acceptance Test Suite: Audit Security Gaps Closure (F1, F2, F2b, F3)
-- ============================================================================
-- Safe & Idempotent: Runs inside a strict TRANSACTION with explicit ROLLBACK.
-- ============================================================================

BEGIN;

DO $$
DECLARE
  v_admin_id uuid;
  v_fake_user_id uuid;
  v_course_id uuid;
  v_cohort_id uuid;
  v_enr_id uuid := gen_random_uuid();
  v_adj_id uuid := gen_random_uuid();
  v_audit_row record;
  v_proconfig text[];
BEGIN
  RAISE NOTICE '=== Starting Phase D4.1.1 Audit Gaps Closure Acceptance Suite ===';

  -- --------------------------------------------------------------------------
  -- STEP 1: Verify search_path includes public, pg_temp (F1)
  -- --------------------------------------------------------------------------
  SELECT p.proconfig INTO v_proconfig
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname = 'audit_trigger_func';

  IF v_proconfig IS NULL OR NOT ('search_path=public, pg_temp' = ANY(v_proconfig)) THEN
    RAISE EXCEPTION 'TEST 1 FAILED: audit_trigger_func search_path is not public, pg_temp. Got: %', v_proconfig;
  END IF;
  RAISE NOTICE 'Test 1 Passed: search_path = public, pg_temp verified on audit_trigger_func.';

  -- --------------------------------------------------------------------------
  -- STEP 2: Verify All 4 Indexes on audit_log
  -- --------------------------------------------------------------------------
  IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND tablename = 'audit_log' AND indexname = 'idx_audit_log_performed_at') THEN
    RAISE EXCEPTION 'TEST 2 FAILED: idx_audit_log_performed_at missing';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND tablename = 'audit_log' AND indexname = 'idx_audit_log_table_name') THEN
    RAISE EXCEPTION 'TEST 2 FAILED: idx_audit_log_table_name missing';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND tablename = 'audit_log' AND indexname = 'idx_audit_log_record_id') THEN
    RAISE EXCEPTION 'TEST 2 FAILED: idx_audit_log_record_id missing';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND tablename = 'audit_log' AND indexname = 'idx_audit_log_performed_by') THEN
    RAISE EXCEPTION 'TEST 2 FAILED: idx_audit_log_performed_by missing';
  END IF;
  RAISE NOTICE 'Test 2 Passed: All 4 audit_log performance indexes verified.';

  -- --------------------------------------------------------------------------
  -- STEP 3: Verify Triggers Cover UPDATE (F2, F2b)
  -- --------------------------------------------------------------------------
  -- payment_refunds (UPDATE event mask & 16)
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger t
    JOIN pg_class c ON c.oid = t.tgrelid
    WHERE c.relname = 'payment_refunds' AND t.tgname = 'trg_z_audit_payment_refunds' AND (t.tgtype & 16) = 16
  ) THEN
    RAISE EXCEPTION 'TEST 3 FAILED: trg_z_audit_payment_refunds does not cover UPDATE';
  END IF;

  -- fee_adjustments (UPDATE event mask & 16)
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger t
    JOIN pg_class c ON c.oid = t.tgrelid
    WHERE c.relname = 'fee_adjustments' AND t.tgname = 'trg_z_audit_fee_adjustments' AND (t.tgtype & 16) = 16
  ) THEN
    RAISE EXCEPTION 'TEST 3 FAILED: trg_z_audit_fee_adjustments does not cover UPDATE';
  END IF;

  -- installment_schedule
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger t
    JOIN pg_class c ON c.oid = t.tgrelid
    WHERE c.relname = 'installment_schedule' AND t.tgname = 'trg_z_audit_installment_schedule'
  ) THEN
    RAISE EXCEPTION 'TEST 3 FAILED: trg_z_audit_installment_schedule missing';
  END IF;

  -- payment_allocations
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger t
    JOIN pg_class c ON c.oid = t.tgrelid
    WHERE c.relname = 'payment_allocations' AND t.tgname = 'trg_z_audit_payment_allocations'
  ) THEN
    RAISE EXCEPTION 'TEST 3 FAILED: trg_z_audit_payment_allocations missing';
  END IF;
  RAISE NOTICE 'Test 3 Passed: UPDATE coverage and triggers on installment_schedule / payment_allocations verified.';

  -- --------------------------------------------------------------------------
  -- STEP 4: Anti-Spoofing Behavioral Test (F3)
  -- --------------------------------------------------------------------------
  SELECT id INTO v_admin_id FROM public.users WHERE role = 'admin' AND is_active = true LIMIT 1;
  SELECT id INTO v_fake_user_id FROM public.users WHERE id <> v_admin_id LIMIT 1;
  SELECT id, course_id INTO v_cohort_id, v_course_id FROM public.cohorts LIMIT 1;

  IF v_fake_user_id IS NULL THEN
    v_fake_user_id := gen_random_uuid();
  END IF;

  -- Simulate Admin JWT
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

  -- Insert course material passing a FORGED created_by column
  INSERT INTO public.course_materials (
    id, course_id, title, material_type, file_path, file_size_bytes, is_published, created_by
  ) VALUES (
    v_enr_id, v_course_id, 'Anti-Spoofing Material Test', 'file', 'materials/spoof.pdf', 1024, true, v_fake_user_id
  );

  SELECT * INTO v_audit_row
  FROM public.audit_log
  WHERE table_name = 'course_materials' AND record_id = v_enr_id AND operation = 'INSERT'
  ORDER BY id DESC LIMIT 1;

  -- Must record authentic JWT admin, completely immune to the forged created_by column
  IF v_audit_row.performed_by <> v_admin_id OR v_audit_row.actor_source <> 'jwt' THEN
    RAISE EXCEPTION 'TEST 4 FAILED: Anti-spoofing breach! performed_by=%, source=%, expected admin=%',
      v_audit_row.performed_by, v_audit_row.actor_source, v_admin_id;
  END IF;
  RAISE NOTICE 'Test 4 Passed: Anti-spoofing verified. JWT authoritatively supersedes forged column data.';

  RAISE NOTICE '====================================================================';
  RAISE NOTICE 'SUCCESS: ALL PHASE D4.1.1 AUDIT GAPS (F1, F2, F2b, F3) VERIFIED!';
  RAISE NOTICE '====================================================================';

END $$;

ROLLBACK;

