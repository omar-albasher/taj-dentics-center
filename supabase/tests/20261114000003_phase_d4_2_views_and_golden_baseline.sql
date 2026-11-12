-- ============================================================================
-- Phase D4.2 — تعريفات العروض السبعة والأرقام الذهبية الحالية (Golden Baseline)
-- ============================================================================
-- الغرض: جلب النصوص البرمجية الكاملة للعروض السبعة + عينات وأرقام ذهبية منها
-- آمن 100% (SELECT فقط، بلا أي تعديل، ولا يعتمد على تخمين أسماء الأعمدة).
-- ============================================================================

-- 1) النصوص البرمجية للعروض السبعة وخيارات الأمان والصلاحيات
SELECT
  '01_view_def'::text AS sec,
  c.relname::text AS view_name,
  ('invoker=' || COALESCE('security_invoker=true' = ANY(c.reloptions), false)::text ||
   ' | acl=' || COALESCE(c.relacl::text, '(default)') ||
   E'\n' || pg_get_viewdef(c.oid, true))::text AS detail
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relkind = 'v'
  AND c.relname IN (
    'profit_loss_report',
    'course_revenue_sql_summary',
    'revenue_by_method_report',
    'discounts_report',
    'debt_aging_report',
    'expenses_by_category_report',
    'cash_vs_accrual_kpis'
  )

UNION ALL

-- 2) الأرقام الذهبية وعينات الصفوف عبر to_jsonb الآمن (بدون تخمين أسماء الأعمدة)
SELECT '02_golden_baseline', 'profit_loss_report',
  ('total_rows=' || count(*)::text ||
   ' | sample=' || COALESCE((SELECT jsonb_agg(to_jsonb(x)) FROM (SELECT * FROM public.profit_loss_report LIMIT 3) x)::text, '[]'))
FROM public.profit_loss_report

UNION ALL

SELECT '02_golden_baseline', 'course_revenue_sql_summary',
  ('total_rows=' || count(*)::text ||
   ' | sample=' || COALESCE((SELECT jsonb_agg(to_jsonb(x)) FROM (SELECT * FROM public.course_revenue_sql_summary LIMIT 3) x)::text, '[]'))
FROM public.course_revenue_sql_summary

UNION ALL

SELECT '02_golden_baseline', 'revenue_by_method_report',
  ('total_rows=' || count(*)::text ||
   ' | data=' || COALESCE((SELECT jsonb_agg(to_jsonb(x)) FROM public.revenue_by_method_report x)::text, '[]'))
FROM public.revenue_by_method_report

UNION ALL

SELECT '02_golden_baseline', 'discounts_report',
  ('total_rows=' || count(*)::text ||
   ' | sample=' || COALESCE((SELECT jsonb_agg(to_jsonb(x)) FROM (SELECT * FROM public.discounts_report LIMIT 3) x)::text, '[]'))
FROM public.discounts_report

UNION ALL

SELECT '02_golden_baseline', 'debt_aging_report',
  ('total_rows=' || count(*)::text ||
   ' | sample=' || COALESCE((SELECT jsonb_agg(to_jsonb(x)) FROM (SELECT * FROM public.debt_aging_report LIMIT 3) x)::text, '[]'))
FROM public.debt_aging_report

UNION ALL

SELECT '02_golden_baseline', 'expenses_by_category_report',
  ('total_rows=' || count(*)::text ||
   ' | data=' || COALESCE((SELECT jsonb_agg(to_jsonb(x)) FROM public.expenses_by_category_report x)::text, '[]'))
FROM public.expenses_by_category_report

UNION ALL

SELECT '02_golden_baseline', 'cash_vs_accrual_kpis',
  ('total_rows=' || count(*)::text ||
   ' | data=' || COALESCE((SELECT jsonb_agg(to_jsonb(x)) FROM public.cash_vs_accrual_kpis x)::text, '[]'))
FROM public.cash_vs_accrual_kpis

ORDER BY sec, view_name;
