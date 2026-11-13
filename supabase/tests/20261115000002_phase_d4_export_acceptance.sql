-- ==============================================================================
-- Test Suite: 20261115000002_phase_d4_export_acceptance.sql
-- Phase: D4.3 Full System Export RPC Update (export_system_data v2.0.0)
-- Safety: Enclosed in BEGIN ... ROLLBACK transaction block
-- ==============================================================================

BEGIN;

DO $$
DECLARE
    v_admin_id uuid;
    v_non_admin_id uuid;
    v_result jsonb;
    v_result_filtered jsonb;
    v_result_all jsonb;
    v_expected_tables text[] := ARRAY[
        'users', 'trainees', 'courses', 'cohorts', 'sessions',
        'enrollments', 'payments', 'expenses', 'attendance',
        'survey_templates', 'survey_dispatches', 'survey_responses',
        'monthly_targets', 'lab_clients', 'lab_invoices', 'lab_invoice_items',
        'lab_payments', 'lab_expenses', 'course_waitlist', 'referrals',
        'course_materials', 'installment_schedule', 'payment_allocations',
        'payment_refunds', 'fee_adjustments', 'enrollment_withdrawals', 'audit_log'
    ];
    v_tbl text;
    v_error_caught boolean := false;
    v_audit_id_old bigint;
    v_audit_id_new bigint;
    v_found_old boolean := false;
    v_found_new boolean := false;
    v_elem jsonb;
    v_search_path text;
    v_is_secdef boolean;
BEGIN
    RAISE NOTICE '=== Starting Phase D4.3 export_system_data Acceptance Suite ===';

    -- --------------------------------------------------------------------------
    -- 1. Verify Function Definition & Search Path Security
    -- --------------------------------------------------------------------------
    SELECT prosecdef, array_to_string(proconfig, ', ')
    INTO v_is_secdef, v_search_path
    FROM pg_proc
    WHERE proname = 'export_system_data'
      AND pronamespace = 'public'::regnamespace;

    IF v_is_secdef IS NOT TRUE THEN
        RAISE EXCEPTION 'TEST 1 FAILED: export_system_data must be SECURITY DEFINER';
    END IF;

    IF v_search_path IS NULL OR v_search_path NOT LIKE '%search_path=public, pg_temp%' THEN
        RAISE EXCEPTION 'TEST 1 FAILED: export_system_data search_path must be public, pg_temp. Got: %', v_search_path;
    END IF;

    RAISE NOTICE 'TEST 1 PASSED: Function signature and search_path (public, pg_temp) verified.';

    -- --------------------------------------------------------------------------
    -- 2. Setup Identities
    -- --------------------------------------------------------------------------
    SELECT id INTO v_admin_id
    FROM public.users
    WHERE role = 'admin' AND is_active = true
    LIMIT 1;

    IF v_admin_id IS NULL THEN
        RAISE EXCEPTION 'Prerequisite missing: Active admin user not found in public.users';
    END IF;

    SELECT id INTO v_non_admin_id
    FROM public.users
    WHERE role <> 'admin' AND is_active = true
    LIMIT 1;

    IF v_non_admin_id IS NULL THEN
        INSERT INTO public.users (id, full_name, email, role, is_active)
        VALUES (gen_random_uuid(), 'D4.3 Test Receptionist', 'd43_reception@test.local', 'reception', true)
        RETURNING id INTO v_non_admin_id;
    END IF;

    -- --------------------------------------------------------------------------
    -- 3. Test Security Guard: Non-Admin Rejection
    -- --------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claim.sub', v_non_admin_id::text, true);
    PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_non_admin_id, 'role', 'authenticated')::text, true);

    BEGIN
        PERFORM public.export_system_data();
        v_error_caught := false;
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%غير مصرح%' THEN
            v_error_caught := true;
        ELSE
            RAISE EXCEPTION 'Unexpected error when calling as non-admin: %', SQLERRM;
        END IF;
    END;

    IF NOT v_error_caught THEN
        RAISE EXCEPTION 'TEST 2 FAILED: Non-admin was NOT rejected by export_system_data!';
    END IF;

    RAISE NOTICE 'TEST 2 PASSED: Non-admin access correctly rejected with authorization error.';

    -- --------------------------------------------------------------------------
    -- 4. Test Admin Invocation (Default 90-day filter, 0 arguments)
    -- --------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claim.sub', v_admin_id::text, true);
    PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_admin_id, 'role', 'authenticated')::text, true);

    v_result := public.export_system_data();

    IF NOT (v_result ? 'metadata') OR NOT (v_result ? 'data') THEN
        RAISE EXCEPTION 'TEST 3 FAILED: Export JSON missing top-level metadata or data keys';
    END IF;

    IF (v_result->'metadata'->>'version') <> '2.0.0' THEN
        RAISE EXCEPTION 'TEST 3 FAILED: Expected metadata.version 2.0.0, got: %', v_result->'metadata'->>'version';
    END IF;

    IF (v_result->'metadata'->>'exported_by_user_id') <> v_admin_id::text THEN
        RAISE EXCEPTION 'TEST 3 FAILED: exported_by_user_id mismatch';
    END IF;

    FOREACH v_tbl IN ARRAY v_expected_tables
    LOOP
        IF NOT (v_result->'metadata'->'counts' ? v_tbl) THEN
            RAISE EXCEPTION 'TEST 3 FAILED: Table % missing from metadata.counts', v_tbl;
        END IF;
        IF NOT (v_result->'data' ? v_tbl) THEN
            RAISE EXCEPTION 'TEST 3 FAILED: Table % missing from data payload', v_tbl;
        END IF;
    END LOOP;

    RAISE NOTICE 'TEST 3 PASSED: Admin export returned valid JSON with all 27 tables present.';

    -- --------------------------------------------------------------------------
    -- 5. Test Audit Log Date Range Filtering
    -- --------------------------------------------------------------------------
    INSERT INTO public.audit_log (table_name, operation, record_id, performed_by, performed_at, actor_source, actor_role)
    VALUES ('test_export_old', 'INSERT', gen_random_uuid(), v_admin_id, now() - interval '120 days', 'jwt', 'admin')
    RETURNING id INTO v_audit_id_old;

    INSERT INTO public.audit_log (table_name, operation, record_id, performed_by, performed_at, actor_source, actor_role)
    VALUES ('test_export_new', 'INSERT', gen_random_uuid(), v_admin_id, now() - interval '5 days', 'jwt', 'admin')
    RETURNING id INTO v_audit_id_new;

    v_result_filtered := public.export_system_data(p_audit_from => now() - interval '30 days');

    v_found_old := false;
    v_found_new := false;
    FOR v_elem IN SELECT * FROM jsonb_array_elements(v_result_filtered->'data'->'audit_log')
    LOOP
        IF (v_elem->>'id')::bigint = v_audit_id_old THEN
            v_found_old := true;
        END IF;
        IF (v_elem->>'id')::bigint = v_audit_id_new THEN
            v_found_new := true;
        END IF;
    END LOOP;

    IF v_found_old THEN
        RAISE EXCEPTION 'TEST 4 FAILED: 120-day-old audit record was included in 30-day filtered export!';
    END IF;
    IF NOT v_found_new THEN
        RAISE EXCEPTION 'TEST 4 FAILED: 5-day-old audit record was NOT included in 30-day filtered export!';
    END IF;

    v_result_all := public.export_system_data(p_audit_from => NULL);

    v_found_old := false;
    v_found_new := false;
    FOR v_elem IN SELECT * FROM jsonb_array_elements(v_result_all->'data'->'audit_log')
    LOOP
        IF (v_elem->>'id')::bigint = v_audit_id_old THEN
            v_found_old := true;
        END IF;
        IF (v_elem->>'id')::bigint = v_audit_id_new THEN
            v_found_new := true;
        END IF;
    END LOOP;

    IF NOT v_found_old OR NOT v_found_new THEN
        RAISE EXCEPTION 'TEST 4 FAILED: Full export with p_audit_from=NULL did not contain both audit records!';
    END IF;

    RAISE NOTICE 'TEST 4 PASSED: Audit log date filtering and full override work perfectly.';

    RAISE NOTICE '=== ALL PHASE D4.3 ACCEPTANCE TESTS COMPLETED SUCCESSFULLY ===';
END $$;

ROLLBACK;
