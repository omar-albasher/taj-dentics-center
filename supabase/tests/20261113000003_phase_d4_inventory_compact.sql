-- ============================================================================
-- Phase D4.0 — جرد التقارير والتدقيق المختصر (Compact Inventory)
-- ============================================================================
-- الغرض: جلب الأقسام (04 إلى 14) المتبقية دون أي حشو مسافات (No padding).
-- آمن للقراءة فقط 100% (SELECT فقط، بلا معاملات، وبلا أي تعديل).
-- ============================================================================

WITH rels AS (
  SELECT
    n.nspname,
    c.oid,
    c.relname,
    c.relkind::text AS relkind
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public'
    AND c.relkind IN ('r', 'v', 'm')
    AND c.relname IN (
      'audit_log',
      'payments',
      'payment_refunds',
      'fee_adjustments',
      'enrollment_withdrawals',
      'installment_schedule',
      'payment_allocations',
      'enrollments',
      'expenses',
      'trainees',
      'users'
    )
),
rviews AS (
  SELECT
    n.nspname,
    c.oid,
    c.relname,
    c.relowner,
    c.relacl,
    c.reloptions
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public'
    AND c.relkind = 'v'
    AND (
      c.relname IN (
        'profit_loss_report',
        'overdue_payments',
        'course_revenue_sql_summary',
        'trainee_academic_progress',
        'revenue_by_method_report',
        'discounts_report',
        'debt_aging_report',
        'expenses_by_category_report',
        'cash_vs_accrual_kpis',
        'enrollment_financial_summary_v2',
        'overdue_installments_v',
        'trainee_statement_v',
        'dashboard_kpis'
      )
      OR c.relname ILIKE '%report%'
      OR c.relname ILIKE '%kpi%'
      OR c.relname ILIKE '%cash%'
    )
)

-- 04) محرّكات الجداول المالية وهل تمسّ audit_log
SELECT
  '04_audit_triggers'::text AS sec,
  (c.relname || '::' || t.tgname)::text AS obj,
  ('fn=' || p.proname ||
   ' | ref_audit=' || (p.prosrc ILIKE '%audit_log%')::text ||
   ' | ' || substr(replace(replace(pg_get_triggerdef(t.oid), E'\n', ' '), '  ', ' '), 1, 120))::text AS detail
FROM pg_trigger t
JOIN pg_class c ON c.oid = t.tgrelid
JOIN pg_namespace n ON n.oid = c.relnamespace
JOIN pg_proc p ON p.oid = t.tgfoid
WHERE NOT t.tgisinternal
  AND n.nspname = 'public'
  AND c.relname IN (
    'payments',
    'payment_refunds',
    'fee_adjustments',
    'enrollment_withdrawals',
    'installment_schedule',
    'payment_allocations',
    'enrollments',
    'expenses'
  )

UNION ALL

-- 05) حجم audit_log الفعلي
SELECT
  '05_audit_volume',
  (COALESCE(a.table_name, '(null)') || '/' || COALESCE(a.operation, '(null)')),
  ('total=' || count(*)::text ||
   ' | last30=' || (count(*) FILTER (WHERE a.performed_at >= now() - interval '30 days'))::text ||
   ' | null_actor=' || (count(*) FILTER (WHERE a.performed_by IS NULL))::text)
FROM public.audit_log a
GROUP BY a.table_name, a.operation

UNION ALL

-- 06) صفوف بلا فاعل في الجداول المالية
SELECT '06_actor_coverage', 'payments.performed_by',
  ('null=' || (count(*) FILTER (WHERE performed_by IS NULL))::text || ' | total=' || count(*)::text)
FROM public.payments
UNION ALL
SELECT '06_actor_coverage', 'payment_refunds.created_by',
  ('null=' || (count(*) FILTER (WHERE created_by IS NULL))::text || ' | total=' || count(*)::text)
FROM public.payment_refunds
UNION ALL
SELECT '06_actor_coverage', 'fee_adjustments.created_by',
  ('null=' || (count(*) FILTER (WHERE created_by IS NULL))::text || ' | total=' || count(*)::text)
FROM public.fee_adjustments
UNION ALL
SELECT '06_actor_coverage', 'enrollment_withdrawals.created_by',
  ('null=' || (count(*) FILTER (WHERE created_by IS NULL))::text || ' | total=' || count(*)::text)
FROM public.enrollment_withdrawals
UNION ALL
SELECT '06_actor_coverage', 'expenses.performed_by',
  ('null=' || (count(*) FILTER (WHERE performed_by IS NULL))::text || ' | total=' || count(*)::text)
FROM public.expenses
UNION ALL
SELECT '06_actor_coverage', 'installment_schedule.created_by',
  ('null=' || (count(*) FILTER (WHERE created_by IS NULL))::text || ' | total=' || count(*)::text)
FROM public.installment_schedule
UNION ALL
SELECT '06_actor_coverage', 'payment_allocations.created_by',
  ('null=' || (count(*) FILTER (WHERE created_by IS NULL))::text || ' | total=' || count(*)::text)
FROM public.payment_allocations

UNION ALL

-- 07) خريطة عروض التقارير الموجودة ومؤشرات منطقها
SELECT
  '07_report_views',
  v.relname::text,
  ('owner=' || pg_get_userbyid(v.relowner) ||
   ' | invoker=' || COALESCE('security_invoker=true' = ANY(v.reloptions), false)::text ||
   ' | has_withdrawn=' || (position('withdrawn' IN pg_get_viewdef(v.oid)) > 0)::text ||
   ' | has_refunds=' || (position('payment_refunds' IN pg_get_viewdef(v.oid)) > 0)::text ||
   ' | has_kind=' || (position('kind' IN pg_get_viewdef(v.oid)) > 0)::text ||
   ' | damascus_tz=' || (position('Asia/Damascus' IN pg_get_viewdef(v.oid)) > 0)::text ||
   ' | def_len=' || length(pg_get_viewdef(v.oid))::text)
FROM rviews v

UNION ALL

-- 12) نظافة البيانات المالية
SELECT
  '12_data_hygiene',
  ('enrollments: ' || e.lifecycle_status || '/' || COALESCE(e.status::text, 'NULL')),
  ('count=' || count(*)::text ||
   ' | due_syp=' || COALESCE(sum(e.total_due) FILTER (WHERE e.currency::text = 'SYP'), 0)::text ||
   ' | due_usd=' || COALESCE(sum(e.total_due) FILTER (WHERE e.currency::text = 'USD'), 0)::text)
FROM public.enrollments e
GROUP BY e.lifecycle_status, e.status

UNION ALL

SELECT
  '12_data_hygiene',
  ('payments: ' || p.currency::text),
  ('count=' || count(*)::text || ' | sum=' || COALESCE(sum(p.amount), 0)::text)
FROM public.payments p
GROUP BY p.currency

UNION ALL

SELECT
  '12_data_hygiene',
  ('refunds: ' || p.currency::text),
  ('count=' || count(*)::text || ' | sum=' || COALESCE(sum(r.amount), 0)::text)
FROM public.payment_refunds r
JOIN public.payments p ON p.id = r.payment_id
GROUP BY p.currency

UNION ALL

SELECT
  '12_data_hygiene',
  'overdue_installments_nonwithdrawn',
  ('count=' || count(*)::text ||
   ' | due=' || COALESCE(sum(s.amount - COALESCE(alloc.allocated, 0)), 0)::text)
FROM public.installment_schedule s
JOIN public.enrollments e ON e.id = s.enrollment_id
LEFT JOIN (
  SELECT pa.installment_id, SUM(pa.amount) AS allocated
  FROM public.payment_allocations pa
  GROUP BY pa.installment_id
) alloc ON alloc.installment_id = s.id
WHERE s.due_date < (now() AT TIME ZONE 'Asia/Damascus')::date
  AND e.lifecycle_status <> 'withdrawn'
  AND (s.amount - COALESCE(alloc.allocated, 0)) > 0

UNION ALL

-- 13) دوال النظام الحالية
SELECT
  '13_functions',
  p.proname::text,
  ('secdef=' || p.prosecdef::text ||
   ' | owner=' || pg_get_userbyid(p.proowner) ||
   ' | auth_uid=' || (p.prosrc ILIKE '%auth.uid()%')::text ||
   ' | admin_guard=' || (p.prosrc ILIKE '%admin%')::text)
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN (
    'export_system_data',
    'get_staff_referral_summary',
    'set_monthly_target',
    'c1_withdrawal_figures',
    'withdraw_enrollment'
  )

UNION ALL

-- 14) فحص وجود كائنات شاشة التقارير والداشبورد
SELECT
  '14_missing_objects',
  obj.name::text,
  (CASE
     WHEN to_regclass('public.' || obj.name) IS NULL THEN 'MISSING'
     ELSE 'present (' ||
       (SELECT c.relkind::text FROM pg_class c WHERE c.oid = to_regclass('public.' || obj.name)) ||
       ')'
   END)
FROM unnest(ARRAY[
  'audit_log',
  'profit_loss_report',
  'overdue_payments',
  'course_revenue_sql_summary',
  'trainee_academic_progress',
  'revenue_by_method_report',
  'discounts_report',
  'debt_aging_report',
  'expenses_by_category_report',
  'cash_vs_accrual_kpis',
  'enrollment_financial_summary_v2',
  'overdue_installments_v',
  'trainee_statement_v',
  'dashboard_kpis'
]) AS obj(name)

ORDER BY sec, obj;

