-- ============================================================================
-- Phase D4.1 — Preflight لسجل التدقيق (قراءة فقط)
-- ============================================================================
-- الغرض: قبل أي CREATE OR REPLACE على audit_trigger_func أو إضافة محرّكات جديدة،
--        نحتاج التعريف الحيّ الكامل للدالة، وبنية audit_log الفعلية (قيود/فهارس/
--        هوية)، وتعريفات كل المحرّكات القائمة وترتيب تنفيذها، وصلاحيات الدوال.
--
--   ملاحظة: audit_log و audit_trigger_func غير موجودين في مايغريشنات المستودع؛
--           هما كائنان حيّان فقط، لذا لا يجوز تخمين تعريفهما.
--
-- التشغيل: لصق الملف كاملاً في Supabase SQL Editor مرة واحدة، ثم إرسال الناتج.
-- أمان: SELECT فقط — بلا DDL ولا كتابة ولا GRANT/REVOKE. لا أسرار.
-- ============================================================================

WITH fin AS (
  SELECT c.oid
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public'
    AND c.relkind = 'r'
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
),
audit_rel AS (
  SELECT c.oid
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public'
    AND c.relname = 'audit_log'
)

-- 00) أعمدة audit_log: NOT NULL / identity / generated / default الكامل
SELECT
  '00_audit_columns'::text AS section,
  'column'::text AS object_type,
  att.attname::text AS object_name,
  ('type=' || format_type(att.atttypid, att.atttypmod) ||
   ' | notnull=' || att.attnotnull::text ||
   ' | identity=' || COALESCE(NULLIF(att.attidentity::text, ''), '-') ||
   ' | generated=' || COALESCE(NULLIF(att.attgenerated::text, ''), '-') ||
   ' | default=' || COALESCE(pg_get_expr(ad.adbin, ad.adrelid), '-'))::text AS detail
FROM pg_attribute att
JOIN audit_rel r ON r.oid = att.attrelid
LEFT JOIN pg_attrdef ad
  ON ad.adrelid = att.attrelid
 AND ad.adnum = att.attnum
WHERE att.attnum > 0
  AND NOT att.attisdropped

UNION ALL

-- 01) قيود audit_log (PK/FK/CHECK) + القيود التي تشير إليه
SELECT
  '01_audit_constraints',
  'constraint',
  con.conname::text,
  ('type=' || con.contype::text ||
   ' | on=' || con.conrelid::regclass::text ||
   ' | ' || pg_get_constraintdef(con.oid))::text
FROM pg_constraint con
JOIN audit_rel r ON con.conrelid = r.oid OR con.confrelid = r.oid

UNION ALL

-- 02) فهارس audit_log
SELECT
  '02_audit_indexes',
  'index',
  indexname::text,
  indexdef::text
FROM pg_indexes
WHERE schemaname = 'public'
  AND tablename = 'audit_log'

UNION ALL

-- 03) كل المحرّكات القائمة على audit_log والجداول المالية (تعريف كامل)
SELECT
  '03_audit_triggers',
  'trigger',
  (c.relname || '::' || t.tgname)::text,
  ('enabled=' || t.tgenabled::text ||
   ' | internal=' || t.tgisinternal::text ||
   ' | ' || pg_get_triggerdef(t.oid))::text
FROM pg_trigger t
JOIN pg_class c ON c.oid = t.tgrelid
WHERE c.oid IN (SELECT oid FROM fin UNION SELECT oid FROM audit_rel)

UNION ALL

-- 04) تعريفات الدوال الكاملة: دوال المحرّكات + أي دالة تمسّ audit_log
SELECT
  '04_function_defs',
  'function',
  (n.nspname || '.' || p.proname || '(' ||
   pg_get_function_identity_arguments(p.oid) || ')')::text,
  ('secdef=' || p.prosecdef::text ||
   ' | owner=' || pg_get_userbyid(p.proowner) ||
   ' | proconfig=' || COALESCE(array_to_string(p.proconfig, ','), '-') ||
   E'\n' || pg_get_functiondef(p.oid))::text
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.prokind = 'f'
  AND (
    p.oid IN (
      SELECT t.tgfoid
      FROM pg_trigger t
      WHERE t.tgrelid IN (SELECT oid FROM fin)
    )
    OR p.proname ILIKE '%audit%'
    OR p.prosrc ILIKE '%audit_log%'
  )

UNION ALL

-- 05) صلاحيات تنفيذ دوال التدقيق
SELECT
  '05_function_acl',
  'function',
  (n.nspname || '.' || p.proname || '(' ||
   pg_get_function_identity_arguments(p.oid) || ')')::text,
  ('anon=' || has_function_privilege('anon', p.oid, 'EXECUTE')::text ||
   ' | authenticated=' || has_function_privilege('authenticated', p.oid, 'EXECUTE')::text ||
   ' | service_role=' || has_function_privilege('service_role', p.oid, 'EXECUTE')::text ||
   ' | acl=' || COALESCE(p.proacl::text, '(default)'))::text
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.prokind = 'f'
  AND (p.proname ILIKE '%audit%' OR p.prosrc ILIKE '%audit_log%')

UNION ALL

-- 06) صلاحيات على مستوى أعمدة audit_log (إن وُجدت)
SELECT
  '06_audit_column_acl',
  'column',
  att.attname::text,
  att.attacl::text
FROM pg_attribute att
JOIN audit_rel r ON r.oid = att.attrelid
WHERE att.attnum > 0
  AND NOT att.attisdropped
  AND att.attacl IS NOT NULL

UNION ALL

-- 07) قيم table_name الفعلية في السجل (لمقارنتها بفلاتر الواجهة)
SELECT
  '07_audit_distinct_tables',
  'table_name',
  COALESCE(a.table_name, '(null)')::text,
  ('rows=' || count(*)::text ||
   ' | ops=' || COALESCE(string_agg(DISTINCT a.operation::text, ','), '-'))::text
FROM public.audit_log a
GROUP BY a.table_name

UNION ALL

-- 08) ترتيب تنفيذ المحرّكات لكل جدول (الأبجدية تحكم نفس الحدث)
SELECT
  '08_trigger_order',
  'table',
  c.relname::text,
  string_agg(t.tgname || '(' || t.tgenabled::text || ')', ' -> ' ORDER BY t.tgname)::text
FROM pg_trigger t
JOIN pg_class c ON c.oid = t.tgrelid
WHERE c.oid IN (SELECT oid FROM fin UNION SELECT oid FROM audit_rel)
GROUP BY c.relname

UNION ALL

-- 09) تسلسل/هوية المعرّف الافتراضي لـ audit_log
SELECT
  '09_audit_identity',
  'sequence',
  COALESCE(pg_get_serial_sequence('public.audit_log', 'id'), '-')::text,
  ('id_column_default=' ||
   COALESCE((
     SELECT pg_get_expr(ad.adbin, ad.adrelid)
     FROM pg_attrdef ad
     JOIN pg_attribute att
       ON att.attrelid = ad.adrelid
      AND att.attnum = ad.adnum
     WHERE ad.adrelid = (SELECT oid FROM audit_rel)
       AND att.attname = 'id'
   ), '-'))::text

ORDER BY section, object_name;
