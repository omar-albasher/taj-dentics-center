-- ==============================================================================
-- Taj Dentics Training Center - Phase B5: Full System Data Export (JSON)
-- Migration: 20261022000002_phase_b5_export_system_data.sql
-- ==============================================================================

-- Security & Logic:
-- 1. Strictly restricted to active admin role (verified server-side).
-- 2. Returns single unified JSONB payload containing metadata, summary counts,
--    and raw data objects for all operational center tables.
-- 3. Phase 10 dental lab tables will be appended once created.

CREATE OR REPLACE FUNCTION public.export_system_data()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_role text;
    v_export jsonb;
BEGIN
    -- 1. Verify caller is active admin
    SELECT role INTO v_user_role 
    FROM public.users 
    WHERE id = auth.uid() AND is_active = true;

    IF v_user_role IS DISTINCT FROM 'admin' THEN
        RAISE EXCEPTION 'غير مصرح: تصدير بيانات النظام مخصص حصراً لمدير النظام (Admin)';
    END IF;

    -- 2. Construct unified JSON snapshot
    SELECT jsonb_build_object(
        'metadata', jsonb_build_object(
            'system_name', 'Taj Dentics Training Center',
            'export_type', 'full_system_data_snapshot',
            'version', '1.0.0',
            'exported_at', to_char(now() AT TIME ZONE 'Asia/Damascus', 'YYYY-MM-DD"T"HH24:MI:SSOF'),
            'exported_by_user_id', auth.uid(),
            'exported_by_email', (SELECT email FROM auth.users WHERE id = auth.uid()),
            'counts', jsonb_build_object(
                'users', (SELECT count(*) FROM public.users),
                'trainees', (SELECT count(*) FROM public.trainees),
                'courses', (SELECT count(*) FROM public.courses),
                'cohorts', (SELECT count(*) FROM public.cohorts),
                'sessions', (SELECT count(*) FROM public.sessions),
                'enrollments', (SELECT count(*) FROM public.enrollments),
                'payments', (SELECT count(*) FROM public.payments),
                'expenses', (SELECT count(*) FROM public.expenses),
                'attendance', (SELECT count(*) FROM public.attendance),
                'survey_templates', (SELECT count(*) FROM public.survey_templates),
                'survey_dispatches', (SELECT count(*) FROM public.survey_dispatches),
                'survey_responses', (SELECT count(*) FROM public.survey_responses),
                'monthly_targets', (SELECT count(*) FROM public.monthly_targets)
            )
        ),
        'data', jsonb_build_object(
            'users', (SELECT COALESCE(jsonb_agg(to_jsonb(u)), '[]'::jsonb) FROM public.users u),
            'trainees', (SELECT COALESCE(jsonb_agg(to_jsonb(t)), '[]'::jsonb) FROM public.trainees t),
            'courses', (SELECT COALESCE(jsonb_agg(to_jsonb(c)), '[]'::jsonb) FROM public.courses c),
            'cohorts', (SELECT COALESCE(jsonb_agg(to_jsonb(ch)), '[]'::jsonb) FROM public.cohorts ch),
            'sessions', (SELECT COALESCE(jsonb_agg(to_jsonb(s)), '[]'::jsonb) FROM public.sessions s),
            'enrollments', (SELECT COALESCE(jsonb_agg(to_jsonb(e)), '[]'::jsonb) FROM public.enrollments e),
            'payments', (SELECT COALESCE(jsonb_agg(to_jsonb(p)), '[]'::jsonb) FROM public.payments p),
            'expenses', (SELECT COALESCE(jsonb_agg(to_jsonb(x)), '[]'::jsonb) FROM public.expenses x),
            'attendance', (SELECT COALESCE(jsonb_agg(to_jsonb(a)), '[]'::jsonb) FROM public.attendance a),
            'survey_templates', (SELECT COALESCE(jsonb_agg(to_jsonb(st)), '[]'::jsonb) FROM public.survey_templates st),
            'survey_dispatches', (SELECT COALESCE(jsonb_agg(to_jsonb(sd)), '[]'::jsonb) FROM public.survey_dispatches sd),
            'survey_responses', (SELECT COALESCE(jsonb_agg(to_jsonb(sr)), '[]'::jsonb) FROM public.survey_responses sr),
            'monthly_targets', (SELECT COALESCE(jsonb_agg(to_jsonb(mt)), '[]'::jsonb) FROM public.monthly_targets mt)
        )
    ) INTO v_export;

    RETURN v_export;
END;
$$;

-- Permissions
REVOKE ALL ON FUNCTION public.export_system_data() FROM anon, public;
GRANT EXECUTE ON FUNCTION public.export_system_data() TO authenticated;
