-- ==============================================================================
-- Phase D3 Acceptance Tests: Permissions & Storage Hardening Verification
-- File: supabase/tests/20261113000001_phase_d3_acceptance.sql
-- ==============================================================================

DO $$
DECLARE
    v_anon_grants_count integer;
    v_old_policies_count integer;
    v_new_table_policy_count integer;
    v_new_storage_policy_count integer;
BEGIN
    -- 1) Verify no privileges for anon on course_materials
    SELECT count(*) INTO v_anon_grants_count
    FROM information_schema.role_table_grants
    WHERE grantee = 'anon'
      AND table_schema = 'public'
      AND table_name = 'course_materials';

    IF v_anon_grants_count > 0 THEN
        RAISE EXCEPTION 'TEST FAILED: anon still has % grants on course_materials', v_anon_grants_count;
    END IF;

    -- 2) Verify old redundant policies were dropped
    SELECT count(*) INTO v_old_policies_count
    FROM pg_policies
    WHERE (schemaname = 'public' AND tablename = 'course_materials' AND policyname IN ('course_materials_select_policy', 'Trainees can view published materials for enrolled courses'))
       OR (schemaname = 'storage' AND tablename = 'objects' AND policyname IN ('authenticated_course_materials_download', 'Trainees can download course materials for enrolled courses'));

    IF v_old_policies_count > 0 THEN
        RAISE EXCEPTION 'TEST FAILED: % old redundant policies still exist', v_old_policies_count;
    END IF;

    -- 3) Verify new table policy exists and checks lifecycle_status
    SELECT count(*) INTO v_new_table_policy_count
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'course_materials'
      AND policyname = 'course_materials_read_policy'
      AND qual ILIKE '%lifecycle_status%';

    IF v_new_table_policy_count = 0 THEN
        RAISE EXCEPTION 'TEST FAILED: course_materials_read_policy missing or does not inspect lifecycle_status';
    END IF;

    -- 4) Verify new storage policy exists and checks lifecycle_status
    SELECT count(*) INTO v_new_storage_policy_count
    FROM pg_policies
    WHERE schemaname = 'storage'
      AND tablename = 'objects'
      AND policyname = 'course_materials_storage_download'
      AND qual ILIKE '%lifecycle_status%';

    IF v_new_storage_policy_count = 0 THEN
        RAISE EXCEPTION 'TEST FAILED: course_materials_storage_download missing or does not inspect lifecycle_status';
    END IF;

    RAISE NOTICE 'SUCCESS: ALL PHASE D3 PERMISSIONS TESTS PASSED!';
END $$;

