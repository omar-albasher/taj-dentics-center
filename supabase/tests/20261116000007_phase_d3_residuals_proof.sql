-- ============================================================================
-- Acceptance Suite: 20261116000007_phase_d3_residuals_proof.sql
-- Description: Independent verification of Phase D3 Residuals & Storage RLS
--
-- Safety: Fully transactional. Enclosed in BEGIN ... ROLLBACK.
-- ============================================================================

BEGIN;

DO $$
DECLARE
  v_anon_exec boolean;
  v_course_id uuid;
  v_cohort_id uuid;
  v_active_trainee_uid uuid;
  v_withdrawn_trainee_uid uuid;
  v_reception_uid uuid;
  v_active_trainee_id uuid;
  v_withdrawn_trainee_id uuid;
  v_active_enrollment_id uuid;
  v_withdrawn_enrollment_id uuid;
  v_uuid_suffix text := substr(gen_random_uuid()::text, 1, 6);
  v_material_file_path text;
  v_storage_visible_count int;
  v_anon_col_count int;
BEGIN
  v_material_file_path := 'materials/test_doc_d3_' || v_uuid_suffix || '.pdf';
  RAISE NOTICE '=== Starting Phase D3 Residuals Acceptance Tests ===';

  -- --------------------------------------------------------------------------
  -- Test 1: Verify Revoked Privileges on Helper Functions for anon
  -- --------------------------------------------------------------------------
  SELECT has_function_privilege('anon', 'public.c1_is_staff()', 'EXECUTE') INTO v_anon_exec;
  ASSERT v_anon_exec = false, 'SECURITY LEAK: anon can execute c1_is_staff()!';

  SELECT has_function_privilege('anon', 'public.c1_staff_role()', 'EXECUTE') INTO v_anon_exec;
  ASSERT v_anon_exec = false, 'SECURITY LEAK: anon can execute c1_staff_role()!';

  SELECT has_function_privilege('anon', 'public.c1_can_read_financials(uuid)', 'EXECUTE') INTO v_anon_exec;
  ASSERT v_anon_exec = false, 'SECURITY LEAK: anon can execute c1_can_read_financials(uuid)!';

  ASSERT has_function_privilege('authenticated', 'public.c1_is_staff()', 'EXECUTE') = true, 
    'authenticated must have EXECUTE on c1_is_staff()';
  ASSERT has_function_privilege('authenticated', 'public.c1_can_read_financials(uuid)', 'EXECUTE') = true, 
    'authenticated must have EXECUTE on c1_can_read_financials(uuid)';

  RAISE NOTICE 'Test 1 Passed: anon has ZERO execute privileges on c1_ helper functions, while authenticated retains access.';

  -- --------------------------------------------------------------------------
  -- Test 2: Verify zero column ACLs and preserved CRUD privileges on course_materials
  -- --------------------------------------------------------------------------
  SELECT count(*) INTO v_anon_col_count 
  FROM pg_attribute
  WHERE attrelid = 'public.course_materials'::regclass
    AND attnum > 0 AND NOT attisdropped AND attacl IS NOT NULL;

  ASSERT v_anon_col_count = 0, 'Column-level ACLs exist on course_materials';

  ASSERT has_table_privilege('authenticated', 'public.course_materials', 'INSERT')
     AND has_table_privilege('authenticated', 'public.course_materials', 'UPDATE')
     AND has_table_privilege('authenticated', 'public.course_materials', 'DELETE')
     AND has_table_privilege('authenticated', 'public.course_materials', 'SELECT'),
    'REGRESSION: authenticated lost CRUD on course_materials';

  ASSERT has_table_privilege('service_role', 'public.course_materials', 'INSERT')
     AND has_table_privilege('service_role', 'public.course_materials', 'SELECT'),
    'REGRESSION: service_role lost write on course_materials';

  ASSERT has_table_privilege('anon', 'public.course_materials', 'SELECT') = false,
    'SECURITY LEAK: anon has SELECT on course_materials';

  RAISE NOTICE 'Test 2 Passed: Zero column ACLs on course_materials, authenticated retains CRUD, service_role retains write, anon has NO access.';

  -- --------------------------------------------------------------------------
  -- Setup Fixtures for Storage RLS Behavioral Verification
  -- --------------------------------------------------------------------------
  -- Reception Staff (Created first to serve as created_by)
  INSERT INTO public.users (full_name, email, phone, role, is_active)
  VALUES ('D3 Reception', 'd3_rec_' || v_uuid_suffix || '@example.com', '+96399' || (floor(random() * 8999999 + 1000000)::bigint)::text, 'reception', true)
  RETURNING id INTO v_reception_uid;

  -- Active Trainee
  INSERT INTO public.users (full_name, email, phone, role, is_active)
  VALUES ('D3 Active Trainee', 'd3_act_' || v_uuid_suffix || '@example.com', '+96399' || (floor(random() * 8999999 + 1000000)::bigint)::text, 'trainee', true)
  RETURNING id INTO v_active_trainee_uid;

  INSERT INTO public.trainees (user_id, created_by, trainee_code) 
  VALUES (v_active_trainee_uid, v_reception_uid, 'TD3A' || v_uuid_suffix)
  RETURNING id INTO v_active_trainee_id;

  -- Withdrawn Trainee
  INSERT INTO public.users (full_name, email, phone, role, is_active)
  VALUES ('D3 Withdrawn Trainee', 'd3_wth_' || v_uuid_suffix || '@example.com', '+96399' || (floor(random() * 8999999 + 1000000)::bigint)::text, 'trainee', true)
  RETURNING id INTO v_withdrawn_trainee_uid;

  INSERT INTO public.trainees (user_id, created_by, trainee_code) 
  VALUES (v_withdrawn_trainee_uid, v_reception_uid, 'TD3W' || v_uuid_suffix)
  RETURNING id INTO v_withdrawn_trainee_id;

  -- Course & Cohort
  INSERT INTO public.courses (name, total_sessions, price, is_active, created_by)
  VALUES ('D3 Storage Test Course ' || v_uuid_suffix, 10, 500000, true, v_reception_uid)
  RETURNING id INTO v_course_id;

  INSERT INTO public.cohorts (course_id, trainer_id, name, capacity, is_active, created_by)
  VALUES (v_course_id, v_reception_uid, 'D3 Cohort ' || v_uuid_suffix, 30, true, v_reception_uid)
  RETURNING id INTO v_cohort_id;

  -- Enrollments: 1 Active, 1 Withdrawn
  INSERT INTO public.enrollments (cohort_id, trainee_id, total_due, lifecycle_status, created_by)
  VALUES (v_cohort_id, v_active_trainee_id, 500000, 'active', v_reception_uid)
  RETURNING id INTO v_active_enrollment_id;

  INSERT INTO public.enrollments (cohort_id, trainee_id, total_due, lifecycle_status, created_by)
  VALUES (v_cohort_id, v_withdrawn_trainee_id, 500000, 'withdrawn', v_reception_uid)
  RETURNING id INTO v_withdrawn_enrollment_id;

  -- Published Course Material
  INSERT INTO public.course_materials (course_id, title, material_type, file_path, is_published, created_by)
  VALUES (v_course_id, 'D3 PDF Material', 'file', v_material_file_path, true, v_reception_uid);

  -- Storage Objects Fixture (Ensure bucket exists or insert test object)
  INSERT INTO storage.buckets (id, name, public)
  VALUES ('course-materials', 'course-materials', false)
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO storage.objects (bucket_id, name, owner)
  VALUES ('course-materials', v_material_file_path, v_reception_uid)
  ON CONFLICT DO NOTHING;

  -- --------------------------------------------------------------------------
  -- Test 3: Storage RLS for Active Trainee (Must See Material)
  -- --------------------------------------------------------------------------
  PERFORM set_config('request.jwt.claims',
    json_build_object(
      'sub', v_active_trainee_uid,
      'role', 'authenticated',
      'user_metadata', json_build_object('role', 'trainee')
    )::text, true);
  SET LOCAL ROLE authenticated;

  SELECT count(*) INTO v_storage_visible_count
  FROM storage.objects
  WHERE bucket_id = 'course-materials' AND name = v_material_file_path;

  ASSERT v_storage_visible_count = 1, 'Active trainee failed to see published course material in storage.objects!';
  RAISE NOTICE 'Test 3 Passed: Active enrolled trainee can successfully view storage course material.';

  -- --------------------------------------------------------------------------
  -- Test 4: Storage RLS for Withdrawn Trainee (Must NOT See Material)
  -- --------------------------------------------------------------------------
  PERFORM set_config('request.jwt.claims',
    json_build_object(
      'sub', v_withdrawn_trainee_uid,
      'role', 'authenticated',
      'user_metadata', json_build_object('role', 'trainee')
    )::text, true);
  SET LOCAL ROLE authenticated;

  SELECT count(*) INTO v_storage_visible_count
  FROM storage.objects
  WHERE bucket_id = 'course-materials' AND name = v_material_file_path;

  ASSERT v_storage_visible_count = 0, 'SECURITY LEAK: Withdrawn trainee was able to view storage course material!';
  RAISE NOTICE 'Test 4 Passed: Withdrawn trainee is correctly blocked from storage course material.';

  -- --------------------------------------------------------------------------
  -- Test 5: Storage RLS for Reception Staff (Must See Material)
  -- --------------------------------------------------------------------------
  PERFORM set_config('request.jwt.claims',
    json_build_object(
      'sub', v_reception_uid,
      'role', 'authenticated',
      'user_metadata', json_build_object('role', 'reception')
    )::text, true);
  SET LOCAL ROLE authenticated;

  SELECT count(*) INTO v_storage_visible_count
  FROM storage.objects
  WHERE bucket_id = 'course-materials' AND name = v_material_file_path;

  ASSERT v_storage_visible_count = 1, 'Reception staff failed to see course material in storage.objects!';
  RAISE NOTICE 'Test 5 Passed: Reception staff has full access to course materials in storage.';

  -- --------------------------------------------------------------------------
  -- Test 6: Storage RLS for Anon (Must NOT See Material)
  -- --------------------------------------------------------------------------
  RESET ROLE;
  PERFORM set_config('request.jwt.claims', '', true);
  SET LOCAL ROLE anon;

  SELECT count(*) INTO v_storage_visible_count
  FROM storage.objects
  WHERE bucket_id = 'course-materials' AND name = v_material_file_path;

  ASSERT v_storage_visible_count = 0, 'SECURITY LEAK: Anon role was able to view storage course material!';
  RAISE NOTICE 'Test 6 Passed: Anon role is completely blocked from storage course materials.';

  RESET ROLE;
  RAISE NOTICE '=== ALL PHASE D3 RESIDUALS ACCEPTANCE TESTS PASSED SUCCESSFULLY ===';
END;
$$;

ROLLBACK;

