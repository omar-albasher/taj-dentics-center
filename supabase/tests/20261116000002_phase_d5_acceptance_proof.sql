-- ============================================================================
-- Acceptance Suite: 20261116000002_phase_d5_acceptance_proof.sql
-- Description: Independent verification of Phase D5.1 Permissions Hardening
--
-- Safety: Fully transactional. Enclosed in BEGIN ... ROLLBACK.
-- ============================================================================

BEGIN;

DO $$
DECLARE
  v_test_user_id uuid;
  v_test_pin_hash text := '$2a$10$abcdefghijklmnopqrstuvwxyz1234567890ABCDEFGHIJK';
  v_audit_record record;
  v_null_proconfig_count int;
  v_public_only_count int;
  v_missing_pg_temp_count int;
  v_pin_missing_extensions int;
  v_tracked_triggers_count int;
  v_total_triggers_count int;
  v_zero_arg_count int;
  v_reception_id uuid;
  v_impostor_id uuid := '00000000-0000-0000-0000-000000000001';
  v_course_id uuid;
  v_cohort_id uuid;
  v_trainee_id uuid;
  v_enrollment_id uuid;
  v_payment_id uuid;
  v_reception_insert_check text;
BEGIN
  RAISE NOTICE '=== Starting Phase D5.1 Acceptance Tests ===';

  -- --------------------------------------------------------------------------
  -- Test 1: Verify all 12 audited tables have active triggers (and NO duplicates)
  -- --------------------------------------------------------------------------
  SELECT COUNT(*), COUNT(DISTINCT c.relname) 
  INTO v_total_triggers_count, v_tracked_triggers_count
  FROM pg_trigger t
  JOIN pg_class c ON c.oid = t.tgrelid
  JOIN pg_proc p ON p.oid = t.tgfoid
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public'
    AND p.proname = 'audit_trigger_func'
    AND t.tgenabled = 'O'
    AND NOT t.tgisinternal
    AND c.relname IN (
      'attendance',
      'course_materials',
      'enrollment_withdrawals',
      'enrollments',
      'expenses',
      'fee_adjustments',
      'installment_schedule',
      'payment_allocations',
      'payment_refunds',
      'payments',
      'sessions',
      'users'
    );

  ASSERT v_tracked_triggers_count = 12, 
    format('Expected 12 tracked tables with active audit triggers, found %s', v_tracked_triggers_count);
  ASSERT v_total_triggers_count = 12,
    format('Duplicate audit triggers detected! Expected exactly 12 triggers total, found %s', v_total_triggers_count);
  RAISE NOTICE 'Test 1 Passed: Exactly 12 tables have exactly 1 active audit trigger each (Zero duplicates).';

  -- --------------------------------------------------------------------------
  -- Test 2: Verify users audit logging and sensitive field protection
  -- --------------------------------------------------------------------------
  -- 2.1 Insert test user
  INSERT INTO public.users (
    full_name,
    email,
    phone,
    role,
    is_active
  ) VALUES (
    'D5 Test Trainee',
    'd5_test_user@example.com',
    '+963999999991',
    'trainee',
    true
  ) RETURNING id INTO v_test_user_id;

  -- 2.2 Verify INSERT audit entry captured and pin_hash is not present
  SELECT * INTO v_audit_record
  FROM public.audit_log
  WHERE table_name = 'users' AND record_id = v_test_user_id AND operation = 'INSERT'
  ORDER BY id DESC LIMIT 1;

  ASSERT v_audit_record.id IS NOT NULL, 'Failed to capture INSERT audit entry for users';
  ASSERT NOT (v_audit_record.new_data ? 'pin_hash'), 'CRITICAL LEAK: pin_hash found in audit_log new_data!';
  ASSERT v_audit_record.new_data->>'phone' = '+963999999991', 'Expected phone in new_data';

  -- 2.3 Update test user
  UPDATE public.users
  SET phone = '+963999999999'
  WHERE id = v_test_user_id;

  -- 2.4 Verify UPDATE audit entry captured and pin_hash is not present
  SELECT * INTO v_audit_record
  FROM public.audit_log
  WHERE table_name = 'users' AND record_id = v_test_user_id AND operation = 'UPDATE'
  ORDER BY id DESC LIMIT 1;

  ASSERT v_audit_record.id IS NOT NULL, 'Failed to capture UPDATE audit entry for users';
  ASSERT NOT (v_audit_record.old_data ? 'pin_hash'), 'CRITICAL LEAK: pin_hash found in audit_log old_data!';
  ASSERT NOT (v_audit_record.new_data ? 'pin_hash'), 'CRITICAL LEAK: pin_hash found in audit_log new_data!';
  ASSERT v_audit_record.new_data->>'phone' = '+963999999999', 'Expected updated phone in new_data';
  RAISE NOTICE 'Test 2 Passed: Users table changes are fully audited with sensitive fields protected.';

  -- --------------------------------------------------------------------------
  -- Test 3: Verify search_path on all SECURITY DEFINER functions
  -- --------------------------------------------------------------------------
  SELECT COUNT(*) INTO v_null_proconfig_count
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' 
    AND p.prosecdef = true
    AND p.proconfig IS NULL;

  ASSERT v_null_proconfig_count = 0, 
    format('Found %s SECURITY DEFINER functions with null proconfig (missing search_path)!', v_null_proconfig_count);

  SELECT COUNT(*) INTO v_public_only_count
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' 
    AND p.prosecdef = true
    AND p.proconfig = ARRAY['search_path=public'];

  ASSERT v_public_only_count = 0, 
    format('Found %s SECURITY DEFINER functions with search_path=public only (missing pg_temp)!', v_public_only_count);

  SELECT COUNT(*) INTO v_missing_pg_temp_count
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.prosecdef = true
    AND NOT EXISTS (
      SELECT 1 FROM unnest(p.proconfig) c WHERE c LIKE 'search_path=%pg_temp%'
    );

  ASSERT v_missing_pg_temp_count = 0,
    format('Found %s SECURITY DEFINER functions whose search_path lacks pg_temp!', v_missing_pg_temp_count);

  SELECT COUNT(*) INTO v_pin_missing_extensions
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname IN ('set_user_pin', 'verify_user_pin')
    AND NOT EXISTS (
      SELECT 1 FROM unnest(p.proconfig) c WHERE c LIKE '%extensions%'
    );

  ASSERT v_pin_missing_extensions = 0,
    format('Found %s PIN functions whose search_path lost the extensions schema (pgcrypto breakage)!', v_pin_missing_extensions);

  -- Trusted contexts (owner / pg_cron / service_role) must never be row-filtered
  ASSERT public.c1_can_read_financials(NULL) IS TRUE,
    'c1_can_read_financials(NULL) must be TRUE for auth.role() IS NULL (owner/pg_cron)';
  ASSERT pg_get_functiondef('public.c1_can_read_financials(uuid)'::regprocedure) LIKE '%service_role%',
    'c1_can_read_financials(uuid) lost the service_role bypass clause';
  RAISE NOTICE 'Test 3 Passed: search_path allowlist, extensions retention and trusted-context bypass verified.';

  -- --------------------------------------------------------------------------
  -- Test 4: Verify reception_insert policy check expression and NO zero-arg overload
  -- --------------------------------------------------------------------------
  SELECT pg_get_expr(polwithcheck, polrelid) INTO v_reception_insert_check
  FROM pg_policy 
  WHERE polrelid = 'public.payments'::regclass AND polname = 'reception_insert';

  ASSERT v_reception_insert_check LIKE '%sham_cash%' 
     AND v_reception_insert_check LIKE '%hawala%' 
     AND v_reception_insert_check LIKE '%transfer%',
    format('Policy reception_insert does not contain expanded payment methods. Actual: %s', v_reception_insert_check);

  ASSERT v_reception_insert_check LIKE '%performed_by = auth.uid()%',
    format('Policy reception_insert MISSING performed_by = auth.uid() check! Actual: %s', v_reception_insert_check);

  SELECT COUNT(*) INTO v_zero_arg_count
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' 
    AND p.proname = 'c1_can_read_financials'
    AND pg_get_function_identity_arguments(p.oid) = '';

  ASSERT v_zero_arg_count = 0, 'Unintended zero-arg overload of c1_can_read_financials() still exists!';
  RAISE NOTICE 'Test 4 Passed: reception_insert enforces methods & performed_by binding, and zero-arg overload is removed.';

  -- --------------------------------------------------------------------------
  -- Test 5: Verify RLS impersonation: reception can insert sham_cash
  -- --------------------------------------------------------------------------
  -- 5.1 Create test reception staff and enrollment fixtures
  INSERT INTO public.users (full_name, email, phone, role, is_active)
  VALUES ('D5 Test Reception', 'd5_reception_user@example.com', '+963999999992', 'reception', true)
  RETURNING id INTO v_reception_id;

  -- 5.1 Use existing enrollment fixture or fallback
  SELECT id INTO v_enrollment_id FROM public.enrollments LIMIT 1;

  IF v_enrollment_id IS NULL THEN
    INSERT INTO public.courses (name, is_active)
    VALUES ('D5 Test Course', true)
    RETURNING id INTO v_course_id;

    INSERT INTO public.cohorts (course_id, name, capacity, is_active)
    VALUES (v_course_id, 'D5 Cohort A', 20, true)
    RETURNING id INTO v_cohort_id;

    INSERT INTO public.trainees (user_id)
    VALUES (v_test_user_id)
    RETURNING id INTO v_trainee_id;

    INSERT INTO public.enrollments (cohort_id, trainee_id, status, total_fee, payment_type)
    VALUES (v_cohort_id, v_trainee_id, 'confirmed', 500000, 'cash')
    RETURNING id INTO v_enrollment_id;
  END IF;

  -- 5.2 Set local role and context to test reception user with accurate JWT claims
  PERFORM set_config('request.jwt.claims',
    json_build_object(
      'sub', v_reception_id,
      'role', 'authenticated',
      'user_metadata', json_build_object('role', 'reception')
    )::text, true);
  SET LOCAL ROLE authenticated;

  -- 5.3 Attempt to insert sham_cash payment as reception with CORRECT performed_by -> MUST SUCCEED
  INSERT INTO public.payments (
    enrollment_id,
    amount,
    currency,
    method,
    performed_by
  ) VALUES (
    v_enrollment_id,
    150000,
    'SYP',
    'sham_cash',
    v_reception_id
  ) RETURNING id INTO v_payment_id;

  ASSERT v_payment_id IS NOT NULL, 'Reception user failed to insert sham_cash payment!';
  RAISE NOTICE 'Test 5.1 Passed: Reception user successfully inserted sham_cash payment bound to self.';

  -- 5.4 Attempt to insert payment with IMPOSTOR performed_by -> MUST FAIL under RLS
  BEGIN
    INSERT INTO public.payments (
      enrollment_id,
      amount,
      currency,
      method,
      performed_by
    ) VALUES (
      v_enrollment_id,
      50000,
      'SYP',
      'cash',
      v_impostor_id
    );
    RAISE EXCEPTION 'CRITICAL RLS VIOLATION: Reception user was able to log payment under someone else!';
  EXCEPTION WHEN insufficient_privilege OR SQLSTATE '42501' THEN
    RAISE NOTICE 'Test 5.2 Passed: Impostor performed_by was correctly BLOCKED by RLS.';
  END;

  -- 5.4 Attempt to update payment as reception -> MUST FAIL under RLS (reception has only SELECT & INSERT)
  BEGIN
    UPDATE public.payments
    SET amount = 999999
    WHERE id = v_payment_id;

    -- If RLS silently filters out rows or raises 42501, verify amount did NOT change
    IF EXISTS (SELECT 1 FROM public.payments WHERE id = v_payment_id AND amount = 999999) THEN
      RAISE EXCEPTION 'CRITICAL RLS VIOLATION: Reception user was able to modify payment amount!';
    END IF;

    RAISE NOTICE 'Test 6 Passed: Reception user was correctly BLOCKED from updating payments.';
  EXCEPTION WHEN insufficient_privilege OR SQLSTATE '42501' THEN
    RAISE NOTICE 'Test 6 Passed: Reception user was correctly BLOCKED from updating payments.';
  END;

  RESET ROLE;
  RAISE NOTICE '=== ALL PHASE D5.1 ACCEPTANCE TESTS PASSED SUCCESSFULLY ===';
END;
$$;

ROLLBACK;
