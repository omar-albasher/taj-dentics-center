-- ============================================================================
-- Phase D3.0 — تدقيق صلاحيات القراءة والكتابة (قراءة فقط)
-- ============================================================================
-- الغرض: إخراج صورة دقيقة عن حالة RLS والسياسات ومنح الجداول/الأعمدة/الدوال
--        والعروض والتخزين في القاعدة الحية، لتحديد فجوات D3 قبل أي تعديل.
--
-- التشغيل:
--   1. الصق الملف كاملاً في Supabase SQL Editor ونفّذه مرة واحدة.
--   2. النتيجة شبكة واحدة موحّدة بعمود section يبدأ بـ 00..10.
--   3. انسخ كل الصفوف (أو Export CSV) وأرسلها للمراجعة.
--
-- أمان:
--   * الملف لا يحتوي أي أمر كتابة (INSERT/UPDATE/DELETE/DDL/GRANT/REVOKE).
--   * لا يحتوي أي أسرار أو مفاتيح؛ يقرأ كتالوجات PostgreSQL فقط.
--   * لا تُشغّله داخل معاملة؛ الاستعلام الأخير هو الذي يعرض النتيجة.
--
-- ملاحظة منفصلة (خارج SQL):
--   * تحقق من أسماء أسرار Edge Functions عبر: supabase secrets list
--     (أسماء فقط، لا تشارك القيم مطلقاً).
-- ============================================================================

WITH rels AS (
  SELECT
    n.nspname,
    c.oid,
    c.relname,
    c.relkind,
    c.relrowsecurity,
    c.relforcerowsecurity,
    c.relowner,
    c.relacl,
    c.reloptions
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE (
    n.nspname = 'public'
    AND c.relname IN (
      'enrollments',
      'payments',
      'payment_refunds',
      'fee_adjustments',
      'installment_schedule',
      'payment_allocations',
      'enrollment_withdrawals',
      'course_materials',
      'trainees',
      'users'
    )
  )
  OR (
    n.nspname = 'storage'
    AND c.relname = 'objects'
  )
),
funcs AS (
  SELECT
    n.nspname,
    p.oid,
    p.proname,
    p.prosecdef,
    p.proowner,
    p.proacl,
    p.prokind
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname IN (
      'c1_is_admin',
      'c1_is_staff',
      'c1_can_read_financials',
      'c1_allocate_payment',
      'c1_apply_plan_delta',
      'c1_refresh_enrollment_status',
      'c1_withdrawal_figures',
      'set_installment_plan',
      'withdraw_enrollment',
      'get_withdrawal_preview',
      'get_cohorts_seat_status',
      'promote_waitlist_trainee',
      'notify_next_waitlist',
      'expire_waitlist_notifications',
      'export_system_data',
      'set_monthly_target',
      'get_staff_referral_summary'
    )
)

-- 00) خصائص الأدوار
SELECT
  '00_roles'::text AS section,
  'role'::text AS object_type,
  r.rolname::text AS object_name,
  ('super=' || r.rolsuper ||
   ' | bypassrls=' || r.rolbypassrls ||
   ' | login=' || r.rolcanlogin)::text AS detail
FROM pg_roles r
WHERE r.rolname IN ('anon', 'authenticated', 'service_role', 'authenticator')

UNION ALL

-- 01) حالة RLS والملكية وACL الخام للجداول/العروض المستهدفة
SELECT
  '01_relations',
  'relation',
  (r.nspname || '.' || r.relname)::text,
  ('kind=' || r.relkind::text ||
   ' | rls_enabled=' || r.relrowsecurity ||
   ' | force_rls=' || r.relforcerowsecurity ||
   ' | owner=' || pg_get_userbyid(r.relowner) ||
   ' | acl=' || COALESCE(r.relacl::text, '(default)'))::text
FROM rels r

UNION ALL

-- 02) السياسات الحية (public + سياسات مواد الكورس في storage.objects)
SELECT
  '02_policies',
  'policy',
  (p.schemaname || '.' || p.tablename || '::' || p.policyname)::text,
  ('cmd=' || p.cmd ||
   ' | permissive=' || p.permissive ||
   ' | roles=' || COALESCE(array_to_string(p.roles, ','), '') ||
   ' | using=' || left(COALESCE(p.qual, ''), 400) ||
   ' | check=' || left(COALESCE(p.with_check, ''), 400))::text
FROM pg_policies p
WHERE (
  p.schemaname = 'public'
  AND p.tablename IN (
    'enrollments',
    'payments',
    'payment_refunds',
    'fee_adjustments',
    'installment_schedule',
    'payment_allocations',
    'enrollment_withdrawals',
    'course_materials',
    'trainees',
    'users'
  )
)
OR (
  p.schemaname = 'storage'
  AND p.tablename = 'objects'
  AND (
    p.policyname ILIKE '%course%'
    OR COALESCE(p.qual, '') ILIKE '%course-materials%'
    OR COALESCE(p.with_check, '') ILIKE '%course-materials%'
  )
)

UNION ALL

-- 03) منح الجداول/العروض بشكل مفصّل (PUBLIC/anon/authenticated/service_role)
SELECT
  '03_relation_grants',
  'grant',
  (r.nspname || '.' || r.relname)::text,
  ((CASE
      WHEN a.grantee = 0 THEN 'PUBLIC'
      ELSE pg_get_userbyid(a.grantee)
    END) || ' : ' || a.privilege_type ||
   CASE WHEN a.is_grantable THEN ' (WITH GRANT OPTION)' ELSE '' END)::text
FROM rels r
CROSS JOIN LATERAL aclexplode(
  COALESCE(r.relacl, acldefault('r', r.relowner))
) a
WHERE a.grantee = 0
   OR a.grantee IN (
     SELECT pr.oid FROM pg_roles pr
     WHERE pr.rolname IN ('anon', 'authenticated', 'service_role')
   )

UNION ALL

-- 04) منح على مستوى الأعمدة (إن وجدت)
SELECT
  '04_column_grants',
  'column_grant',
  (r.nspname || '.' || r.relname || '.' || att.attname)::text,
  ((CASE
      WHEN a.grantee = 0 THEN 'PUBLIC'
      ELSE pg_get_userbyid(a.grantee)
    END) || ' : ' || a.privilege_type)::text
FROM rels r
JOIN pg_attribute att
  ON att.attrelid = r.oid
 AND att.attnum > 0
 AND NOT att.attisdropped
CROSS JOIN LATERAL aclexplode(att.attacl) a
WHERE att.attacl IS NOT NULL
  AND (
    a.grantee = 0
    OR a.grantee IN (
      SELECT pr.oid FROM pg_roles pr
      WHERE pr.rolname IN ('anon', 'authenticated', 'service_role')
    )
  )

UNION ALL

-- 05) العروض: المالك، security_invoker، وجود حارس c1_can_read_financials
SELECT
  '05_views',
  'view',
  (r.nspname || '.' || r.relname)::text,
  ('owner=' || pg_get_userbyid(r.relowner) ||
   ' | security_invoker=' ||
     COALESCE('security_invoker=true' = ANY(r.reloptions), false) ||
   ' | has_financial_guard=' ||
     (position('c1_can_read_financials' IN pg_get_viewdef(r.oid)) > 0) ||
   ' | acl=' || COALESCE(r.relacl::text, '(default)'))::text
FROM rels r
WHERE r.relkind = 'v'

UNION ALL

-- 06) الدوال: SECURITY DEFINER، المالك، ACL الخام
SELECT
  '06_functions',
  'function',
  (f.nspname || '.' || f.proname || '(' ||
   pg_get_function_identity_arguments(f.oid) || ')')::text,
  ('secdef=' || f.prosecdef ||
   ' | kind=' || f.prokind::text ||
   ' | owner=' || pg_get_userbyid(f.proowner) ||
   ' | acl=' || COALESCE(f.proacl::text, '(default)'))::text
FROM funcs f

UNION ALL

-- 07) منح EXECUTE للدوال حسب الدور
SELECT
  '07_function_grants',
  'grant',
  (f.nspname || '.' || f.proname || '(' ||
   pg_get_function_identity_arguments(f.oid) || ')')::text,
  ((CASE
      WHEN a.grantee = 0 THEN 'PUBLIC'
      ELSE pg_get_userbyid(a.grantee)
    END) || ' : ' || a.privilege_type)::text
FROM funcs f
CROSS JOIN LATERAL aclexplode(
  COALESCE(f.proacl, acldefault('f', f.proowner))
) a
WHERE a.grantee = 0
   OR a.grantee IN (
     SELECT pr.oid FROM pg_roles pr
     WHERE pr.rolname IN ('anon', 'authenticated', 'service_role')
   )

UNION ALL

-- 08) الصلاحيات الافتراضية في المخطط (ALTER DEFAULT PRIVILEGES)
SELECT
  '08_default_acl',
  'default_acl',
  (CASE
     WHEN d.defaclnamespace = 0 THEN '(global)'
     ELSE d.defaclnamespace::regnamespace::text
   END)::text,
  ('role=' || pg_get_userbyid(d.defaclrole) ||
   ' | objtype=' || d.defaclobjtype::text ||
   ' | acl=' || d.defaclacl::text)::text
FROM pg_default_acl d

UNION ALL

-- 09) إعداد حاوية مواد الكورس
SELECT
  '09_buckets',
  'bucket',
  b.id::text,
  ('name=' || b.name ||
   ' | public=' || b."public" ||
   ' | limit=' || COALESCE(b.file_size_limit::text, 'unlimited') ||
   ' | mime=' || COALESCE(b.allowed_mime_types::text, 'any'))::text
FROM storage.buckets b
WHERE b.id = 'course-materials'

UNION ALL

-- 10) فجوات صريحة: جداول مستهدفة بلا RLS
SELECT
  '10_rls_gaps',
  'table',
  (r.nspname || '.' || r.relname)::text,
  'RLS DISABLED — يجب تفعيله في D3'::text
FROM rels r
WHERE r.relkind = 'r'
  AND r.relrowsecurity = false

ORDER BY section, object_name, detail;
