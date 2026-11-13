-- ==============================================================================
-- Test / Inspection Suite: 20261115000003_phase_d4_5_final_proof.sql
-- Phase: D4.5 Final Proof & Live Audit Trail Verification
-- ==============================================================================

-- 1. Distinct table names currently recorded in public.audit_log
SELECT DISTINCT table_name 
FROM public.audit_log 
ORDER BY 1;

-- 2. Authoritative check of active triggers and enabled status across all 11 audited tables
SELECT 
    c.relname AS table_name,
    t.tgname  AS trigger_name,
    t.tgenabled AS enabled_status,
    pg_get_triggerdef(t.oid) AS definition
FROM pg_trigger t
JOIN pg_class c ON c.oid = t.tgrelid
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND NOT t.tgisinternal
  AND c.relname IN (
      'payments',
      'enrollments',
      'expenses',
      'attendance',
      'sessions',
      'payment_refunds',
      'fee_adjustments',
      'enrollment_withdrawals',
      'course_materials',
      'installment_schedule',
      'payment_allocations'
  )
  AND (t.tgname ILIKE '%audit%' OR pg_get_triggerdef(t.oid) ILIKE '%audit%')
ORDER BY c.relname, t.tgname;
