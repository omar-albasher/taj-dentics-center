-- ============================================================================
-- Phase D4.0 — جرد التقارير وسجل التدقيق (قراءة فقط)
-- ============================================================================
-- الغرض: صورة دقيقة عن كائنات التقارير الحية، تغطية audit_log، أعمدة الفاعل،
--        الصلاحيات، الفهارس، ونظافة البيانات قبل تصميم D4.
--
-- التشغيل:
--   1. الصق الملف كاملاً في Supabase SQL Editor ونفّذه مرة واحدة.
--   2. النتيجة شبكة واحدة بعمود section من 00 إلى 14.
--   3. انسخ كل الصفوف أو Export CSV وأرسلها للمراجعة.
--
-- أمان:
--   * SELECT فقط — لا كتابة ولا DDL ولا GRANT/REVOKE.
--   * لا أسرار أو مفاتيح؛ يقرأ الكتالوج والجداول المالية فقط.
--   * بلا معاملة؛ الاستعلام الأخير هو الذي يعرض النتيجة.
-- ============================================================================

WITH rels AS (
  SELECT
    n.nspname,
    c.oid,
    c.relname,
    c.relkind::text AS relkind,
    c.relrowsecurity,
    c.relforcerowsecurity,
    c.relowner,
    c.relacl,
    c.reloptions
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
SELECT
  '00_audit_objects'::text AS section,
  'relation'::text AS object_type,
  (r.nspname || '.' || r.relname)::text AS object_name,
  ('kind=' || r.relkind ||
   ' | rls_enabled=' || r.relrowsecurity ||
   ' | force_rls=' || r.relforcerowsecurity ||
   ' | owner=' || pg_get_userbyid(r.relowner) ||
   ' | acl=' || COALESCE(r.relacl::text, '(default)'))::text AS detail
FROM rels r

UNION ALL

-- 01) أعمدة audit_log الحية
SELECT
  '01_audit_columns',
  'column',
  (c.table_schema || '.' || c.table_name || '.' || c.column_name)::text,
  ('type=' || c.data_type ||
   ' | nullable=' || c.is_nullable ||
   ' | default=' || COALESCE(c.column_default, '-') ||
   ' | ordinal=' || c.ordinal_position::text)::text
FROM information_schema.columns c
WHERE c.table_schema = 'public'
  AND c.table_name = 'audit_log'

UNION ALL

-- 02) سياسات audit_log
SELECT
  '02_audit_policies',
  'policy',
  (p.schemaname || '.' || p.tablename || '::' || p.policyname)::text,
  ('cmd=' || p.cmd::text ||
   ' | permissive=' || p.permissive ||
   ' | roles=' || COALESCE(array_to_string(p.roles, ','), '') ||
   ' | using=' || left(COALESCE(p.qual, ''), 500) ||
   ' | check=' || left(COALESCE(p.with_check, ''), 500))::text
FROM pg_policies p
WHERE p.schemaname = 'public'
  AND p.tablename = 'audit_log'

UNION ALL

-- 03) منح audit_log الفعلية + has_table_privilege
SELECT
  '03_audit_grants',
  'grant',
  ('public.audit_log :: ' ||
   CASE WHEN a.grantee = 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END)::text,
  a.privilege_type::text
FROM rels r
CROSS JOIN LATERAL aclexplode(COALESCE(r.relacl, acldefault('r', r.relowner))) a
WHERE r.relname = 'audit_log'
  AND (
    a.grantee = 0
    OR a.grantee IN (
      SELECT pr.oid FROM pg_roles pr
      WHERE pr.rolname IN ('anon', 'authenticated', 'service_role')
    )
  )

UNION ALL

SELECT
  '03_audit_grants',
  'privilege',
  ('public.audit_log :: ' || rl.role_name)::text,
  ('SELECT=' || has_table_privilege(rl.role_name, 'public.audit_log', 'SELECT')::text ||
   ' | INSERT=' || has_table_privilege(rl.role_name, 'public.audit_log', 'INSERT')::text ||
   ' | UPDATE=' || has_table_privilege(rl.role_name, 'public.audit_log', 'UPDATE')::text ||
   ' | DELETE=' || has_table_privilege(rl.role_name, 'public.audit_log', 'DELETE')::text)::text
FROM (VALUES ('anon'), ('authenticated'), ('service_role')) AS rl(role_name)

UNION ALL

-- 04) محرّكات الجداول المالية وهل تمسّ audit_log
SELECT
  '04_audit_triggers',
  'trigger',
  (n.nspname || '.' || c.relname || '::' || t.tgname)::text,
  ('fn=' || p.proname ||
   ' | references_audit_log=' || (p.prosrc ILIKE '%audit_log%')::text ||
   ' | def=' || left(pg_get_triggerdef(t.oid), 700))::text
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

-- 05) حجم audit_log حسب الجدول والعملية
SELECT
  '05_audit_volume',
  'audit',
  ('audit_log/' || COALESCE(a.table_name, '(null)') || '/' || COALESCE(a.operation, '(null)'))::text,
  ('total=' || count(*)::text ||
   ' | last30=' || (count(*) FILTER (WHERE a.performed_at >= now() - interval '30 days'))::text ||
   ' | min=' || COALESCE(min(a.performed_at)::text, '-') ||
   ' | max=' || COALESCE(max(a.performed_at)::text, '-') ||
   ' | null_actor=' || (count(*) FILTER (WHERE a.performed_by IS NULL))::text)::text
FROM public.audit_log a
GROUP BY a.table_name, a.operation

UNION ALL

-- 06) أعمدة الفاعل في الجداول المالية
SELECT
  '06_actor_coverage',
  'actor_column',
  (r.relname || '.' || att.attname)::text,
  ('type=' || format_type(att.atttypid, att.atttypmod) ||
   ' | nullable=' || (NOT att.attnotnull)::text)::text
FROM rels r
JOIN pg_attribute att
  ON att.attrelid = r.oid
 AND att.attnum > 0
 AND NOT att.attisdropped
WHERE r.relkind = 'r'
  AND r.relname IN (
    'payments',
    'payment_refunds',
    'fee_adjustments',
    'enrollment_withdrawals',
    'expenses',
    'installment_schedule',
    'payment_allocations'
  )
  AND att.attname IN ('created_by', 'performed_by')

UNION ALL

-- 06) صفوف بلا فاعل
SELECT '06_actor_coverage', 'null_actors', 'public.payments.performed_by',
  ('null=' || (count(*) FILTER (WHERE performed_by IS NULL))::text ||
   ' | total=' || count(*)::text)
FROM public.payments
UNION ALL
SELECT '06_actor_coverage', 'null_actors', 'public.payment_refunds.created_by',
  ('null=' || (count(*) FILTER (WHERE created_by IS NULL))::text ||
   ' | total=' || count(*)::text)
FROM public.payment_refunds
UNION ALL
SELECT '06_actor_coverage', 'null_actors', 'public.fee_adjustments.created_by',
  ('null=' || (count(*) FILTER (WHERE created_by IS NULL))::text ||
   ' | total=' || count(*)::text)
FROM public.fee_adjustments
UNION ALL
SELECT '06_actor_coverage', 'null_actors', 'public.enrollment_withdrawals.created_by',
  ('null=' || (count(*) FILTER (WHERE created_by IS NULL))::text ||
   ' | total=' || count(*)::text)
FROM public.enrollment_withdrawals
UNION ALL
SELECT '06_actor_coverage', 'null_actors', 'public.expenses.performed_by',
  ('null=' || (count(*) FILTER (WHERE performed_by IS NULL))::text ||
   ' | total=' || count(*)::text)
FROM public.expenses
UNION ALL
SELECT '06_actor_coverage', 'null_actors', 'public.installment_schedule.created_by',
  ('null=' || (count(*) FILTER (WHERE created_by IS NULL))::text ||
   ' | total=' || count(*)::text)
FROM public.installment_schedule
UNION ALL
SELECT '06_actor_coverage', 'null_actors', 'public.payment_allocations.created_by',
  ('null=' || (count(*) FILTER (WHERE created_by IS NULL))::text ||
   ' | total=' || count(*)::text)
FROM public.payment_allocations

UNION ALL

-- 07) خريطة عروض التقارير ومؤشرات المحتوى
SELECT
  '07_report_views',
  'view',
  (v.nspname || '.' || v.relname)::text,
  ('owner=' || pg_get_userbyid(v.relowner) ||
   ' | security_invoker=' ||
     COALESCE('security_invoker=true' = ANY(v.reloptions), false)::text ||
   ' | has_withdrawn=' ||
     (position('withdrawn' IN pg_get_viewdef(v.oid)) > 0)::text ||
   ' | has_lifecycle=' ||
     (position('lifecycle_status' IN pg_get_viewdef(v.oid)) > 0)::text ||
   ' | has_dropped=' ||
     (position('dropped' IN pg_get_viewdef(v.oid)) > 0)::text ||
   ' | has_refunds=' ||
     (position('payment_refunds' IN pg_get_viewdef(v.oid)) > 0)::text ||
   ' | has_kind=' ||
     (position('kind' IN pg_get_viewdef(v.oid)) > 0)::text ||
   ' | damascus_tz=' ||
     (position('Asia/Damascus' IN pg_get_viewdef(v.oid)) > 0)::text ||
   ' | def_len=' || length(pg_get_viewdef(v.oid))::text ||
   ' | acl=' || COALESCE(v.relacl::text, '(default)'))::text
FROM rviews v

UNION ALL

-- 08) تعريفات عروض التقارير كاملة
SELECT
  '08_report_view_defs',
  'view_def',
  (v.nspname || '.' || v.relname)::text,
  left(pg_get_viewdef(v.oid, true), 12000)::text
FROM rviews v

UNION ALL

-- 09) منح عروض التقارير
SELECT
  '09_report_grants',
  'grant',
  (v.nspname || '.' || v.relname || ' :: ' ||
   CASE WHEN a.grantee = 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END)::text,
  a.privilege_type::text
FROM rviews v
CROSS JOIN LATERAL aclexplode(COALESCE(v.relacl, acldefault('r', v.relowner))) a
WHERE a.grantee = 0
   OR a.grantee IN (
     SELECT pr.oid FROM pg_roles pr
     WHERE pr.rolname IN ('anon', 'authenticated', 'service_role')
   )

UNION ALL

SELECT
  '09_report_grants',
  'privilege',
  (v.nspname || '.' || v.relname || ' :: ' || rl.role_name)::text,
  ('SELECT=' ||
   has_table_privilege(rl.role_name, 'public.' || v.relname, 'SELECT')::text)::text
FROM rviews v
CROSS JOIN (VALUES ('anon'), ('authenticated'), ('service_role')) AS rl(role_name)

UNION ALL

-- 10) أعمدة عروض التقارير
SELECT
  '10_report_columns',
  'column',
  (c.table_schema || '.' || c.table_name || '.' || c.column_name)::text,
  ('type=' || c.data_type ||
   ' | nullable=' || c.is_nullable ||
   ' | ordinal=' || c.ordinal_position::text)::text
FROM information_schema.columns c
WHERE c.table_schema = 'public'
  AND c.table_name IN (SELECT rv.relname FROM rviews rv)

UNION ALL

-- 11) فهارس الجداول الداعمة للتقارير
SELECT
  '11_report_indexes',
  'index',
  (n.nspname || '.' || c.relname || '::' || i.relname)::text,
  pg_get_indexdef(x.indexrelid)::text
FROM pg_index x
JOIN pg_class c ON c.oid = x.indrelid
JOIN pg_namespace n ON n.oid = c.relnamespace
JOIN pg_class i ON i.oid = x.indexrelid
WHERE n.nspname = 'public'
  AND c.relname IN (
    'payments',
    'payment_refunds',
    'fee_adjustments',
    'enrollment_withdrawals',
    'installment_schedule',
    'payment_allocations',
    'enrollments',
    'expenses',
    'audit_log'
  )

UNION ALL

-- 12) نظافة البيانات: التسجيلات حسب الدورة والحالة
SELECT
  '12_data_hygiene',
  'enrollments',
  ('lifecycle=' || e.lifecycle_status || ' status=' || COALESCE(e.status::text, 'NULL'))::text,
  ('count=' || count(*)::text ||
   ' | due_syp=' || COALESCE(sum(e.total_due) FILTER (WHERE e.currency::text = 'SYP'), 0)::text ||
   ' | due_usd=' || COALESCE(sum(e.total_due) FILTER (WHERE e.currency::text = 'USD'), 0)::text)::text
FROM public.enrollments e
GROUP BY e.lifecycle_status, e.status

UNION ALL

-- 12) تعديلات الرسوم حسب النوع
SELECT
  '12_data_hygiene',
  'fee_adjustments',
  ('kind=' || fa.kind)::text,
  ('count=' || count(*)::text ||
   ' | sum=' || COALESCE(sum(fa.amount), 0)::text)::text
FROM public.fee_adjustments fa
GROUP BY fa.kind

UNION ALL

-- 12) المدفوعات حسب العملة
SELECT
  '12_data_hygiene',
  'payments',
  ('currency=' || p.currency::text)::text,
  ('count=' || count(*)::text ||
   ' | sum=' || COALESCE(sum(p.amount), 0)::text ||
   ' | first=' || COALESCE(min(p.paid_at)::text, '-') ||
   ' | last=' || COALESCE(max(p.paid_at)::text, '-'))::text
FROM public.payments p
GROUP BY p.currency

UNION ALL

-- 12) الاستردادات حسب العملة
SELECT
  '12_data_hygiene',
  'payment_refunds',
  ('currency=' || p.currency::text)::text,
  ('count=' || count(*)::text ||
   ' | sum=' || COALESCE(sum(r.amount), 0)::text)::text
FROM public.payment_refunds r
JOIN public.payments p ON p.id = r.payment_id
GROUP BY p.currency

UNION ALL

-- 12) المصاريف حسب العملة
SELECT
  '12_data_hygiene',
  'expenses',
  ('currency=' || x.currency::text)::text,
  ('count=' || count(*)::text ||
   ' | sum=' || COALESCE(sum(x.amount), 0)::text)::text
FROM public.expenses x
GROUP BY x.currency

UNION ALL

-- 12) المتأخرات الفعلية (استثناء المنسحبين)
SELECT
  '12_data_hygiene',
  'installments',
  'overdue_nonwithdrawn'::text,
  ('count=' || count(*)::text ||
   ' | due=' || COALESCE(sum(s.amount - COALESCE(alloc.allocated, 0)), 0)::text)::text
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

-- 13) دوال التقارير والتدقيق: الحماية والصلاحيات
SELECT
  '13_report_functions',
  'function',
  (n.nspname || '.' || p.proname || '(' ||
   pg_get_function_identity_arguments(p.oid) || ')')::text,
  ('secdef=' || p.prosecdef::text ||
   ' | owner=' || pg_get_userbyid(p.proowner) ||
   ' | acl=' || COALESCE(p.proacl::text, '(default)') ||
   ' | has_auth_uid=' || (p.prosrc ILIKE '%auth.uid()%')::text ||
   ' | has_admin_guard=' || (p.prosrc ILIKE '%admin%')::text)::text
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN (
    'export_system_data',
    'get_staff_referral_summary',
    'set_monthly_target',
    'c1_withdrawal_figures',
    'c1_refresh_enrollment_status',
    'get_withdrawal_preview',
    'withdraw_enrollment'
  )

UNION ALL

-- 14) حضور الكائنات التي يعتمد عليها كود الأدمن
SELECT
  '14_missing_objects',
  'object',
  obj.name::text,
  (CASE
     WHEN to_regclass('public.' || obj.name) IS NULL THEN 'MISSING'
     ELSE 'present (' ||
       (SELECT c.relkind::text FROM pg_class c WHERE c.oid = to_regclass('public.' || obj.name)) ||
       ')'
   END)::text
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

ORDER BY section, object_name, detail;
