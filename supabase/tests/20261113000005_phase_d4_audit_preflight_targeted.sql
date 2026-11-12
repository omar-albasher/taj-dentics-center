-- ============================================================================
-- Phase D4.1 — Preflight الموجه لسجل التدقيق (Targeted Preflight)
-- ============================================================================
-- الغرض: جلب الأقسام الحرجة (04 إلى 09) المتبقية دون أي حشو ودون قيود المفاتيح الداخلية
-- حجم النتيجة: أقل من 8 كيلوبايت — آمن 100% ولن يُقتطع إطلاقاً.
-- ============================================================================

-- 04) التعريف الحي الكامل لدالة التدقيق وأي دالة تمس audit_log
SELECT
  '04_function_defs'::text AS sec,
  (n.nspname || '.' || p.proname)::text AS obj,
  ('secdef=' || p.prosecdef::text ||
   ' | owner=' || pg_get_userbyid(p.proowner) ||
   ' | proconfig=' || COALESCE(array_to_string(p.proconfig, ','), '-') ||
   E'\n' || pg_get_functiondef(p.oid))::text AS detail
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND (p.proname ILIKE '%audit%' OR p.prosrc ILIKE '%audit_log%')

UNION ALL

-- 05) صلاحيات تنفيذ دوال التدقيق
SELECT
  '05_function_acl',
  (n.nspname || '.' || p.proname),
  ('anon=' || has_function_privilege('anon', p.oid, 'EXECUTE')::text ||
   ' | authenticated=' || has_function_privilege('authenticated', p.oid, 'EXECUTE')::text ||
   ' | service_role=' || has_function_privilege('service_role', p.oid, 'EXECUTE')::text ||
   ' | acl=' || COALESCE(p.proacl::text, '(default)'))
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND (p.proname ILIKE '%audit%' OR p.prosrc ILIKE '%audit_log%')

UNION ALL

-- 06) صلاحيات الأعمدة على audit_log
SELECT
  '06_audit_column_acl',
  att.attname::text,
  att.attacl::text
FROM pg_attribute att
JOIN pg_class c ON c.oid = att.attrelid
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relname = 'audit_log'
  AND att.attnum > 0
  AND NOT att.attisdropped
  AND att.attacl IS NOT NULL

UNION ALL

-- 07) قيم table_name الفعلية في audit_log
SELECT
  '07_audit_distinct_tables',
  COALESCE(a.table_name, '(null)')::text,
  ('rows=' || count(*)::text ||
   ' | ops=' || COALESCE(string_agg(DISTINCT a.operation::text, ','), '-'))
FROM public.audit_log a
GROUP BY a.table_name

UNION ALL

-- 08) ترتيب تنفيذ المحرّكات التشغيلية (غير الداخلية) لكل جدول
SELECT
  '08_trigger_order',
  c.relname::text,
  string_agg(t.tgname || '(' ||
    CASE WHEN (t.tgtype & 2) = 2 THEN 'BEFORE' ELSE 'AFTER' END || ' ' ||
    CASE
      WHEN (t.tgtype & 4) = 4 AND (t.tgtype & 8) = 8 AND (t.tgtype & 16) = 16 THEN 'INSERT/DELETE/UPDATE'
      WHEN (t.tgtype & 4) = 4 AND (t.tgtype & 16) = 16 THEN 'INSERT/UPDATE'
      WHEN (t.tgtype & 4) = 4 THEN 'INSERT'
      WHEN (t.tgtype & 16) = 16 THEN 'UPDATE'
      WHEN (t.tgtype & 8) = 8 THEN 'DELETE'
      ELSE 'OTHER'
    END || ')', ' -> ' ORDER BY t.tgname)
FROM pg_trigger t
JOIN pg_class c ON c.oid = t.tgrelid
JOIN pg_namespace n ON n.oid = c.relnamespace
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
    'expenses',
    'audit_log'
  )
GROUP BY c.relname

UNION ALL

-- 09) تسلسل/هوية id في audit_log
SELECT
  '09_audit_identity',
  COALESCE(pg_get_serial_sequence('public.audit_log', 'id'), '-')::text,
  ('default=' ||
   COALESCE((
     SELECT pg_get_expr(ad.adbin, ad.adrelid)
     FROM pg_attrdef ad
     JOIN pg_attribute att ON att.attrelid = ad.adrelid AND att.attnum = ad.adnum
     JOIN pg_class c ON c.oid = ad.adrelid
     WHERE c.relname = 'audit_log' AND att.attname = 'id'
   ), '-'))

ORDER BY sec, obj;

