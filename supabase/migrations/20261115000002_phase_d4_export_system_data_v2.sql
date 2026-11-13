-- ==============================================================================
-- Migration: 20261115000002_phase_d4_export_system_data_v2.sql
-- Description: Update export_system_data() to v2.0.0:
--   1. SET search_path = public, pg_temp (SECURITY DEFINER hardening)
--   2. Add p_audit_from timestamptz DEFAULT (now() - interval '90 days')
--   3. Include 7 missing tables + waitlist & referrals:
--      - payment_refunds (Phase D1)
--      - fee_adjustments (Phase D1/D2)
--      - installment_schedule (Phase D1)
--      - payment_allocations (Phase D1)
--      - enrollment_withdrawals (Phase D2)
--      - course_materials (Phase D3)
--      - audit_log (filtered by p_audit_from, Phase D4.1)
--      - course_waitlist & referrals
-- ==============================================================================

-- Drop old parameterless signature to avoid ambiguous overload
DROP FUNCTION IF EXISTS public.export_system_data();

CREATE OR REPLACE FUNCTION public.export_system_data(
    p_audit_from timestamptz DEFAULT (now() - interval '90 days')
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_user_role text;
BEGIN
    SELECT role INTO v_user_role 
    FROM public.users 
    WHERE id = auth.uid() AND is_active = true;

    IF v_user_role IS DISTINCT FROM 'admin' THEN
        RAISE EXCEPTION 'غير مصرح: تصدير بيانات النظام مخصص حصراً لمدير النظام (Admin)';
    END IF;

    RETURN jsonb_build_object(
        'metadata', jsonb_build_object(
            'system_name', 'Taj Dentics Training Center & Dental Lab',
            'export_type', 'full_system_data_snapshot',
            'version', '2.0.0',
            'exported_at', to_char(now() AT TIME ZONE 'Asia/Damascus', 'YYYY-MM-DD"T"HH24:MI:SS"+03:00"'),
            'exported_by_user_id', auth.uid(),
            'exported_by_email', (SELECT email FROM auth.users WHERE id = auth.uid()),
            'audit_filter_applied', p_audit_from,
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
                'monthly_targets', (SELECT count(*) FROM public.monthly_targets),
                'lab_clients', (SELECT count(*) FROM public.lab_clients),
                'lab_invoices', (SELECT count(*) FROM public.lab_invoices),
                'lab_invoice_items', (SELECT count(*) FROM public.lab_invoice_items),
                'lab_payments', (SELECT count(*) FROM public.lab_payments),
                'lab_expenses', (SELECT count(*) FROM public.lab_expenses),
                'course_waitlist', (SELECT count(*) FROM public.course_waitlist),
                'referrals', (SELECT count(*) FROM public.referrals),
                'course_materials', (SELECT count(*) FROM public.course_materials),
                'installment_schedule', (SELECT count(*) FROM public.installment_schedule),
                'payment_allocations', (SELECT count(*) FROM public.payment_allocations),
                'payment_refunds', (SELECT count(*) FROM public.payment_refunds),
                'fee_adjustments', (SELECT count(*) FROM public.fee_adjustments),
                'enrollment_withdrawals', (SELECT count(*) FROM public.enrollment_withdrawals),
                'audit_log', (SELECT count(*) FROM public.audit_log al WHERE p_audit_from IS NULL OR al.performed_at >= p_audit_from)
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
            'expenses', (SELECT COALESCE(jsonb_agg(to_jsonb(ex)), '[]'::jsonb) FROM public.expenses ex),
            'attendance', (SELECT COALESCE(jsonb_agg(to_jsonb(a)), '[]'::jsonb) FROM public.attendance a),
            'survey_templates', (SELECT COALESCE(jsonb_agg(to_jsonb(st)), '[]'::jsonb) FROM public.survey_templates st),
            'survey_dispatches', (SELECT COALESCE(jsonb_agg(to_jsonb(sd)), '[]'::jsonb) FROM public.survey_dispatches sd),
            'survey_responses', (SELECT COALESCE(jsonb_agg(to_jsonb(sr)), '[]'::jsonb) FROM public.survey_responses sr),
            'monthly_targets', (SELECT COALESCE(jsonb_agg(to_jsonb(mt)), '[]'::jsonb) FROM public.monthly_targets mt),
            'lab_clients', (SELECT COALESCE(jsonb_agg(to_jsonb(lc)), '[]'::jsonb) FROM public.lab_clients lc),
            'lab_invoices', (SELECT COALESCE(jsonb_agg(to_jsonb(li)), '[]'::jsonb) FROM public.lab_invoices li),
            'lab_invoice_items', (SELECT COALESCE(jsonb_agg(to_jsonb(lii)), '[]'::jsonb) FROM public.lab_invoice_items lii),
            'lab_payments', (SELECT COALESCE(jsonb_agg(to_jsonb(lp)), '[]'::jsonb) FROM public.lab_payments lp),
            'lab_expenses', (SELECT COALESCE(jsonb_agg(to_jsonb(le)), '[]'::jsonb) FROM public.lab_expenses le),
            'course_waitlist', (SELECT COALESCE(jsonb_agg(to_jsonb(cw)), '[]'::jsonb) FROM public.course_waitlist cw),
            'referrals', (SELECT COALESCE(jsonb_agg(to_jsonb(ref)), '[]'::jsonb) FROM public.referrals ref),
            'course_materials', (SELECT COALESCE(jsonb_agg(to_jsonb(cm)), '[]'::jsonb) FROM public.course_materials cm),
            'installment_schedule', (SELECT COALESCE(jsonb_agg(to_jsonb(isch)), '[]'::jsonb) FROM public.installment_schedule isch),
            'payment_allocations', (SELECT COALESCE(jsonb_agg(to_jsonb(pa)), '[]'::jsonb) FROM public.payment_allocations pa),
            'payment_refunds', (SELECT COALESCE(jsonb_agg(to_jsonb(pr)), '[]'::jsonb) FROM public.payment_refunds pr),
            'fee_adjustments', (SELECT COALESCE(jsonb_agg(to_jsonb(fa)), '[]'::jsonb) FROM public.fee_adjustments fa),
            'enrollment_withdrawals', (SELECT COALESCE(jsonb_agg(to_jsonb(ew)), '[]'::jsonb) FROM public.enrollment_withdrawals ew),
            'audit_log', (
                SELECT COALESCE(jsonb_agg(to_jsonb(al) ORDER BY al.performed_at DESC), '[]'::jsonb) 
                FROM public.audit_log al 
                WHERE p_audit_from IS NULL OR al.performed_at >= p_audit_from
            )
        )
    );
END;
$$;

REVOKE ALL ON FUNCTION public.export_system_data(timestamptz) FROM anon, public;
GRANT EXECUTE ON FUNCTION public.export_system_data(timestamptz) TO authenticated, service_role;

COMMENT ON FUNCTION public.export_system_data(timestamptz) IS 
  'Exports full system data snapshot (27 tables) as JSONB for admin backup; audit_log is filtered by p_audit_from (default last 90 days).';

