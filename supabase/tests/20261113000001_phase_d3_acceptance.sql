-- ==============================================================================
-- Phase D3 Acceptance Tests: Hardened Behavioral Verification (B4 - Bulletproof)
-- File: supabase/tests/20261113000001_phase_d3_acceptance.sql
-- ==============================================================================

BEGIN;

DO $$
DECLARE
    v_has_anon_select boolean;
    v_has_auth_select boolean;
    v_has_auth_insert boolean;
    v_has_auth_update boolean;
    v_has_auth_delete boolean;
    v_has_staff_exec  boolean;
    v_cm_select_count integer;
    v_storage_count   integer;
    v_index_exists    boolean;

    v_admin_uid       uuid;
    v_rec_uid         uuid;
    v_trainee_uid     uuid;
    v_trainee_id      uuid;
    
    v_course_id       uuid;
    v_cohort_id       uuid;
    v_enr_id          uuid := gen_random_uuid();
    v_mat_pub_id      uuid := gen_random_uuid();
    v_mat_unpub_id    uuid := gen_random_uuid();
    v_count           integer;
BEGIN
    RAISE NOTICE '=== 1. Static Permissions & Catalog Verification ===';

    -- 1) Verify anon has NO SELECT on course_materials
    SELECT has_table_privilege('anon', 'public.course_materials', 'SELECT') INTO v_has_anon_select;
    IF v_has_anon_select THEN
        RAISE EXCEPTION 'TEST FAILED: anon still has SELECT on public.course_materials';
    END IF;

    -- 2) Verify authenticated has SELECT, INSERT, UPDATE, DELETE (B1)
    SELECT has_table_privilege('authenticated', 'public.course_materials', 'SELECT') INTO v_has_auth_select;
    SELECT has_table_privilege('authenticated', 'public.course_materials', 'INSERT') INTO v_has_auth_insert;
    SELECT has_table_privilege('authenticated', 'public.course_materials', 'UPDATE') INTO v_has_auth_update;
    SELECT has_table_privilege('authenticated', 'public.course_materials', 'DELETE') INTO v_has_auth_delete;

    IF NOT (v_has_auth_select AND v_has_auth_insert AND v_has_auth_update AND v_has_auth_delete) THEN
        RAISE EXCEPTION 'TEST FAILED: authenticated is missing table-level CRUD on course_materials (sel=%, ins=%, upd=%, del=%)',
            v_has_auth_select, v_has_auth_insert, v_has_auth_update, v_has_auth_delete;
    END IF;

    -- 3) Verify authenticated can execute c1_is_staff()
    SELECT has_function_privilege('authenticated', 'public.c1_is_staff()', 'EXECUTE') INTO v_has_staff_exec;
    IF NOT v_has_staff_exec THEN
        RAISE EXCEPTION 'TEST FAILED: authenticated lacks EXECUTE on public.c1_is_staff()';
    END IF;

    -- 4) Verify file_path index exists (B3)
    SELECT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'public'
          AND tablename = 'course_materials'
          AND indexname = 'idx_course_materials_file_path'
    ) INTO v_index_exists;

    IF NOT v_index_exists THEN
        RAISE EXCEPTION 'TEST FAILED: idx_course_materials_file_path index is missing';
    END IF;

    -- 5) Verify exact policy counts (no orphan / extra policies)
    SELECT count(*) INTO v_cm_select_count
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'course_materials'
      AND (cmd = 'SELECT' OR cmd = 'ALL');

    IF v_cm_select_count <> 2 THEN
        RAISE EXCEPTION 'TEST FAILED: Expected exactly 2 read/all policies on course_materials, found %', v_cm_select_count;
    END IF;

    SELECT count(*) INTO v_storage_count
    FROM pg_policies
    WHERE schemaname = 'storage'
      AND tablename = 'objects'
      AND (qual ILIKE '%course-materials%' OR with_check ILIKE '%course-materials%');

    IF v_storage_count <> 2 THEN
        RAISE EXCEPTION 'TEST FAILED: Expected exactly 2 course-materials storage policies, found %', v_storage_count;
    END IF;

    RAISE NOTICE '=== 2. Behavioral Simulation with Temporary Test Data ===';

    -- Pick existing admin
    SELECT u.id INTO v_admin_uid
    FROM public.users u
    WHERE u.role::text = 'admin' AND u.is_active = true
    LIMIT 1;

    -- Pick existing reception
    SELECT u.id INTO v_rec_uid
    FROM public.users u
    WHERE u.role::text = 'reception' AND u.is_active = true
    LIMIT 1;

    -- Pick existing trainee
    SELECT t.id, t.user_id INTO v_trainee_id, v_trainee_uid
    FROM public.trainees t
    JOIN public.users u ON u.id = t.user_id
    WHERE u.is_active = true
    LIMIT 1;

    IF v_admin_uid IS NULL OR v_trainee_uid IS NULL THEN
        RAISE EXCEPTION 'TEST FAILED: Missing active admin or trainee in database';
    END IF;

    -- Pick an existing cohort and course where this trainee is not yet enrolled
    SELECT c.id, c.course_id INTO v_cohort_id, v_course_id
    FROM public.cohorts c
    WHERE NOT EXISTS (
        SELECT 1 FROM public.enrollments e
        WHERE e.cohort_id = c.id AND e.trainee_id = v_trainee_id
    )
    LIMIT 1;

    IF v_cohort_id IS NULL THEN
        SELECT c.id, c.course_id INTO v_cohort_id, v_course_id
        FROM public.cohorts c
        LIMIT 1;
    END IF;

    -- Insert 1 published and 1 unpublished material with unique IDs
    INSERT INTO public.course_materials (id, course_id, title, material_type, file_path, is_published, created_by)
    VALUES
        (v_mat_pub_id, v_course_id, 'Published Mat D3', 'file', 'materials/test_pub.pdf', true, v_admin_uid),
        (v_mat_unpub_id, v_course_id, 'Draft Mat D3', 'file', 'materials/test_draft.pdf', false, v_admin_uid);

    -- Setup ACTIVE enrollment for trainee with created_by populated
    INSERT INTO public.enrollments (id, cohort_id, trainee_id, status, lifecycle_status, total_due, discount_amount, enrolled_at, created_by)
    VALUES (v_enr_id, v_cohort_id, v_trainee_id, 'unpaid'::payment_status, 'active', 1000, 0, now(), v_admin_uid);

    -- SIMULATION 1: Active Trainee sees only published material (1 out of the 2 test materials)
    PERFORM set_config(
        'request.jwt.claims',
        json_build_object(
            'sub', v_trainee_uid::text,
            'role', 'authenticated',
            'user_metadata', json_build_object(
                'role', 'trainee',
                'trainee_id', v_trainee_id::text
            )
        )::text,
        true
    );
    PERFORM set_config('request.jwt.claim.sub', v_trainee_uid::text, true);
    PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
    SET LOCAL ROLE authenticated;

    SELECT count(*) INTO v_count
    FROM public.course_materials
    WHERE id IN (v_mat_pub_id, v_mat_unpub_id);

    IF v_count <> 1 THEN
        RAISE EXCEPTION 'BEHAVIORAL FAILED: Active trainee saw %, expected 1 (published only)', v_count;
    END IF;

    -- SIMULATION 2: Update enrollment to WITHDRAWN (using D2 trigger bypass flag) -> Trainee sees 0 materials
    RESET ROLE;
    PERFORM set_config('c1.withdrawal_rpc', 'on', true);
    UPDATE public.enrollments
    SET lifecycle_status = 'withdrawn'
    WHERE id = v_enr_id;
    PERFORM set_config('c1.withdrawal_rpc', 'off', true);

    PERFORM set_config(
        'request.jwt.claims',
        json_build_object(
            'sub', v_trainee_uid::text,
            'role', 'authenticated',
            'user_metadata', json_build_object(
                'role', 'trainee',
                'trainee_id', v_trainee_id::text
            )
        )::text,
        true
    );
    PERFORM set_config('request.jwt.claim.sub', v_trainee_uid::text, true);
    PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
    SET LOCAL ROLE authenticated;

    SELECT count(*) INTO v_count
    FROM public.course_materials
    WHERE id IN (v_mat_pub_id, v_mat_unpub_id);

    IF v_count <> 0 THEN
        RAISE EXCEPTION 'BEHAVIORAL FAILED: Withdrawn trainee saw %, expected 0', v_count;
    END IF;

    -- SIMULATION 3: Reception staff sees BOTH published and draft (2)
    IF v_rec_uid IS NOT NULL THEN
        RESET ROLE;
        PERFORM set_config(
            'request.jwt.claims',
            json_build_object(
                'sub', v_rec_uid::text,
                'role', 'authenticated',
                'user_metadata', json_build_object(
                    'role', 'reception'
                )
            )::text,
            true
        );
        PERFORM set_config('request.jwt.claim.sub', v_rec_uid::text, true);
        PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
        SET LOCAL ROLE authenticated;

        SELECT count(*) INTO v_count
        FROM public.course_materials
        WHERE id IN (v_mat_pub_id, v_mat_unpub_id);

        IF v_count <> 2 THEN
            RAISE EXCEPTION 'BEHAVIORAL FAILED: Reception saw %, expected 2', v_count;
        END IF;
    END IF;

    RESET ROLE;
    RAISE NOTICE 'SUCCESS: ALL PHASE D3 BEHAVIORAL AND PERMISSION TESTS PASSED!';
END $$;

ROLLBACK;
