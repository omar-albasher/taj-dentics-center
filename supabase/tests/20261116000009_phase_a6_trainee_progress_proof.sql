-- ============================================================================
-- Acceptance Suite: 20261116000009_phase_a6_trainee_progress_proof.sql
-- Description: Independent verification of Phase A6 trainee progress scoping
--
-- Safety: Fully transactional. Enclosed in BEGIN ... ROLLBACK.
-- ============================================================================

BEGIN;

DO $$
DECLARE
  v_viewdef        text;
  v_col_count      int;
  v_admin_uid      uuid;
  v_reception_uid  uuid;
  v_trainee_a_uid  uuid;
  v_trainee_b_uid  uuid;
  v_trainee_a_id   uuid;
  v_trainee_b_id   uuid;
  v_course_id      uuid;
  v_cohort_id      uuid;
  v_enr_a          uuid;
  v_enr_b          uuid;
  v_suffix         text := substr(gen_random_uuid()::text, 1, 6);
  v_count          int;
BEGIN
  RAISE NOTICE '=== Starting Phase A6 trainee_academic_progress Scoping Tests ===';

  -- --------------------------------------------------------------------------
  -- Test 1: Static definition, shape and grants
  -- --------------------------------------------------------------------------
  SELECT pg_get_viewdef('public.trainee_academic_progress'::regclass, true)
  INTO v_viewdef;

  ASSERT position('auth.uid()' IN v_viewdef) > 0,
    'View definition is missing the auth.uid() guard';
  ASSERT position('c1_is_staff' IN v_viewdef) > 0,
    'View definition is missing the c1_is_staff() staff guard';
  ASSERT position('service_role' IN v_viewdef) > 0,
    'View definition lost the service_role trust anchor';

  SELECT count(*) INTO v_col_count
  FROM pg_attribute
  WHERE attrelid = 'public.trainee_academic_progress'::regclass
    AND attnum > 0
    AND NOT attisdropped;

  ASSERT v_col_count = 12,
    format('Expected 12 columns, found %s (client contract drift)', v_col_count);

  ASSERT NOT has_table_privilege('anon', 'public.trainee_academic_progress', 'SELECT'),
    'SECURITY LEAK: anon still has SELECT on the view';
  ASSERT has_table_privilege('authenticated', 'public.trainee_academic_progress', 'SELECT'),
    'authenticated lost SELECT on the view';
  ASSERT NOT has_table_privilege('authenticated', 'public.trainee_academic_progress', 'INSERT')
     AND NOT has_table_privilege('authenticated', 'public.trainee_academic_progress', 'UPDATE')
     AND NOT has_table_privilege('authenticated', 'public.trainee_academic_progress', 'DELETE'),
    'authenticated retains write privileges on a read-only view';
  ASSERT has_table_privilege('service_role', 'public.trainee_academic_progress', 'SELECT'),
    'service_role lost SELECT on the view';

  RAISE NOTICE 'Test 1 Passed: guard present, 12 columns preserved, grants tightened.';

  -- --------------------------------------------------------------------------
  -- Fixtures
  -- --------------------------------------------------------------------------
  INSERT INTO public.users (full_name, email, phone, role, is_active)
  VALUES ('A6 Admin', 'a6_admin_' || v_suffix || '@example.com',
          '+96399' || (floor(random() * 8999999 + 1000000)::bigint)::text, 'admin', true)
  RETURNING id INTO v_admin_uid;

  INSERT INTO public.users (full_name, email, phone, role, is_active)
  VALUES ('A6 Reception', 'a6_rec_' || v_suffix || '@example.com',
          '+96399' || (floor(random() * 8999999 + 1000000)::bigint)::text, 'reception', true)
  RETURNING id INTO v_reception_uid;

  INSERT INTO public.users (full_name, email, phone, role, is_active)
  VALUES ('A6 Trainee A', 'a6_ta_' || v_suffix || '@example.com',
          '+96399' || (floor(random() * 8999999 + 1000000)::bigint)::text, 'trainee', true)
  RETURNING id INTO v_trainee_a_uid;

  INSERT INTO public.trainees (user_id, created_by, trainee_code)
  VALUES (v_trainee_a_uid, v_reception_uid, 'TA6A' || v_suffix)
  RETURNING id INTO v_trainee_a_id;

  INSERT INTO public.users (full_name, email, phone, role, is_active)
  VALUES ('A6 Trainee B', 'a6_tb_' || v_suffix || '@example.com',
          '+96399' || (floor(random() * 8999999 + 1000000)::bigint)::text, 'trainee', true)
  RETURNING id INTO v_trainee_b_uid;

  INSERT INTO public.trainees (user_id, created_by, trainee_code)
  VALUES (v_trainee_b_uid, v_reception_uid, 'TA6B' || v_suffix)
  RETURNING id INTO v_trainee_b_id;

  INSERT INTO public.courses (name, total_sessions, price, is_active, created_by)
  VALUES ('A6 Scoping Course ' || v_suffix, 10, 500000, true, v_admin_uid)
  RETURNING id INTO v_course_id;

  INSERT INTO public.cohorts (course_id, trainer_id, name, capacity, is_active, created_by)
  VALUES (v_course_id, v_admin_uid, 'A6 Cohort ' || v_suffix, 30, true, v_admin_uid)
  RETURNING id INTO v_cohort_id;

  INSERT INTO public.enrollments (cohort_id, trainee_id, total_due, lifecycle_status, created_by)
  VALUES (v_cohort_id, v_trainee_a_id, 500000, 'active', v_admin_uid)
  RETURNING id INTO v_enr_a;

  INSERT INTO public.enrollments (cohort_id, trainee_id, total_due, lifecycle_status, created_by)
  VALUES (v_cohort_id, v_trainee_b_id, 500000, 'active', v_admin_uid)
  RETURNING id INTO v_enr_b;

  -- --------------------------------------------------------------------------
  -- Test 2: Trainee A sees exactly one row, and cannot probe trainee B
  -- --------------------------------------------------------------------------
  PERFORM set_config('request.jwt.claims',
    json_build_object(
      'sub', v_trainee_a_uid,
      'role', 'authenticated',
      'user_metadata', json_build_object('role', 'trainee')
    )::text, true);
  SET LOCAL ROLE authenticated;

  SELECT count(*) INTO v_count FROM public.trainee_academic_progress;
  ASSERT v_count = 1,
    format('Trainee A should see exactly 1 row, got %s', v_count);

  SELECT count(*) INTO v_count
  FROM public.trainee_academic_progress
  WHERE trainee_id = v_trainee_b_id;
  ASSERT v_count = 0,
    'SECURITY LEAK: trainee A can read trainee B rows through an explicit filter';

  RAISE NOTICE 'Test 2 Passed: trainee sees only own row and cannot probe other trainees.';

  -- --------------------------------------------------------------------------
  -- Test 3: Reception staff sees both rows
  -- --------------------------------------------------------------------------
  PERFORM set_config('request.jwt.claims',
    json_build_object(
      'sub', v_reception_uid,
      'role', 'authenticated',
      'user_metadata', json_build_object('role', 'reception')
    )::text, true);
  SET LOCAL ROLE authenticated;

  SELECT count(*) INTO v_count
  FROM public.trainee_academic_progress
  WHERE enrollment_id IN (v_enr_a, v_enr_b);
  ASSERT v_count = 2,
    format('Reception should see both fixture rows, got %s', v_count);

  RAISE NOTICE 'Test 3 Passed: reception keeps full attendance visibility.';

  -- --------------------------------------------------------------------------
  -- Test 4: Admin sees both rows
  -- --------------------------------------------------------------------------
  PERFORM set_config('request.jwt.claims',
    json_build_object(
      'sub', v_admin_uid,
      'role', 'authenticated',
      'user_metadata', json_build_object('role', 'admin')
    )::text, true);
  SET LOCAL ROLE authenticated;

  SELECT count(*) INTO v_count
  FROM public.trainee_academic_progress
  WHERE enrollment_id IN (v_enr_a, v_enr_b);
  ASSERT v_count = 2,
    format('Admin should see both fixture rows, got %s', v_count);

  RAISE NOTICE 'Test 4 Passed: admin reports keep full visibility.';

  -- --------------------------------------------------------------------------
  -- Test 5: Trusted backend context (owner / service_role / pg_cron) sees both
  -- --------------------------------------------------------------------------
  RESET ROLE;
  PERFORM set_config('request.jwt.claims', '', true);

  SELECT count(*) INTO v_count
  FROM public.trainee_academic_progress
  WHERE enrollment_id IN (v_enr_a, v_enr_b);
  ASSERT v_count = 2,
    format('Trusted context should see both fixture rows, got %s', v_count);

  RAISE NOTICE 'Test 5 Passed: trusted backend context retains full access.';

  RAISE NOTICE '=== ALL PHASE A6 TRACKING PROGRESS TESTS PASSED SUCCESSFULLY ===';
END;
$$;

ROLLBACK;
