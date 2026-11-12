-- ============================================================================
-- Phase D4.2 — عروض التقارير المالية v2
-- ============================================================================
-- المبادئ المحاسبية المعتمدة:
-- 1) كل صف يحمل عملة واحدة؛ يمنع جمع SYP مع USD بنيوياً.
-- 2) النقدي (cash): مدفوعات جميع التسجيلات ناقص الاستردادات، ويشمل المنسحبين
--    لأن النقد تحرّك فعلاً.
-- 3) الاستحقاقي (accrual): التسجيلات الفعّالة فقط (lifecycle_status <> 'withdrawn').
-- 4) تخصيصات الدفعات تعكس الاستردادات مسبقاً عبر c1_allocate_payment
--    (20261110000001...sql:1197-1205)، لذا لا نطرح الاسترداد مرتين.
-- 5) كل تجميع زمني بتوقيت دمشق.
-- 6) العروض القديمة تبقى دون تغيير وظيفي؛ تُشدّد صلاحياتها فقط.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) الربح والخسارة (نقدي): صف لكل (شهر, عملة)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW public.profit_loss_report_v2 AS
WITH events AS (
    SELECT
        p.currency::text AS currency,
        date_trunc('month', p.paid_at AT TIME ZONE 'Asia/Damascus')::date AS month,
        p.amount AS income_amount,
        0::numeric AS refund_amount,
        0::numeric AS expense_amount
    FROM public.payments p

    UNION ALL

    SELECT
        p.currency::text,
        date_trunc('month', r.refunded_at AT TIME ZONE 'Asia/Damascus')::date,
        0::numeric,
        r.amount,
        0::numeric
    FROM public.payment_refunds r
    JOIN public.payments p ON p.id = r.payment_id

    UNION ALL

    SELECT
        x.currency::text,
        date_trunc('month', x.expense_date)::date,
        0::numeric,
        0::numeric,
        x.amount
    FROM public.expenses x
)
SELECT
    month,
    currency,
    SUM(income_amount) AS cash_income,
    SUM(refund_amount) AS refunds,
    SUM(income_amount) - SUM(refund_amount) AS net_income,
    SUM(expense_amount) AS expenses,
    SUM(income_amount) - SUM(refund_amount) - SUM(expense_amount) AS net_profit
FROM events
WHERE public.c1_is_staff()
   OR auth.role() IS NULL
   OR auth.role() = 'service_role'
GROUP BY month, currency;

-- ----------------------------------------------------------------------------
-- 2) الإيراد حسب طريقة الدفع: صف لكل (طريقة, عملة)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW public.revenue_by_method_report_v2 AS
WITH gross AS (
    SELECT
        p.method,
        p.currency::text AS currency,
        SUM(p.amount) AS gross_collected,
        COUNT(*) AS payment_count
    FROM public.payments p
    GROUP BY p.method, p.currency::text
),
refunds AS (
    SELECT
        p.method,
        p.currency::text AS currency,
        SUM(r.amount) AS refunded
    FROM public.payment_refunds r
    JOIN public.payments p ON p.id = r.payment_id
    GROUP BY p.method, p.currency::text
)
SELECT
    COALESCE(g.method, r.method) AS method,
    COALESCE(g.currency, r.currency) AS currency,
    COALESCE(g.gross_collected, 0) AS gross_collected,
    COALESCE(r.refunded, 0) AS refunds,
    COALESCE(g.gross_collected, 0) - COALESCE(r.refunded, 0) AS net_collected,
    COALESCE(g.payment_count, 0) AS payment_count
FROM gross g
FULL JOIN refunds r
  ON r.method IS NOT DISTINCT FROM g.method
 AND r.currency = g.currency
WHERE public.c1_is_staff()
   OR auth.role() IS NULL
   OR auth.role() = 'service_role';

-- ----------------------------------------------------------------------------
-- 3) إيراد الكورسات: نقدي شامل + ذمم الفعّالين، صف لكل (كورس, عملة)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW public.course_revenue_sql_summary_v2 AS
WITH cash AS (
    SELECT
        co.course_id,
        p.currency::text AS currency,
        SUM(p.amount) AS gross_collected,
        COUNT(p.id) AS payment_count
    FROM public.payments p
    JOIN public.enrollments e ON e.id = p.enrollment_id
    JOIN public.cohorts co ON co.id = e.cohort_id
    GROUP BY co.course_id, p.currency::text
),
refunds AS (
    SELECT
        co.course_id,
        p.currency::text AS currency,
        SUM(r.amount) AS refunded
    FROM public.payment_refunds r
    JOIN public.payments p ON p.id = r.payment_id
    JOIN public.enrollments e ON e.id = p.enrollment_id
    JOIN public.cohorts co ON co.id = e.cohort_id
    GROUP BY co.course_id, p.currency::text
),
accrual AS (
    SELECT
        co.course_id,
        v.currency::text AS currency,
        SUM(v.net_due) FILTER (WHERE v.lifecycle_status <> 'withdrawn') AS active_expected_net_due,
        SUM(v.net_paid) FILTER (WHERE v.lifecycle_status <> 'withdrawn') AS active_net_paid,
        SUM(GREATEST(v.current_balance, 0)) FILTER (WHERE v.lifecycle_status <> 'withdrawn') AS active_outstanding,
        COUNT(*) FILTER (WHERE v.lifecycle_status <> 'withdrawn') AS active_enrollments,
        COUNT(*) FILTER (WHERE v.lifecycle_status = 'withdrawn') AS withdrawn_enrollments
    FROM public.enrollment_financial_summary_v2 v
    JOIN public.cohorts co ON co.id = v.cohort_id
    GROUP BY co.course_id, v.currency::text
),
keys AS (
    SELECT
        co.course_id,
        e.currency::text AS currency
    FROM public.enrollments e
    JOIN public.cohorts co ON co.id = e.cohort_id
    GROUP BY co.course_id, e.currency::text
)
SELECT
    k.course_id,
    crs.name AS course_name,
    k.currency,
    COALESCE(c.gross_collected, 0) AS gross_collected,
    COALESCE(r.refunded, 0) AS refunds,
    COALESCE(c.gross_collected, 0) - COALESCE(r.refunded, 0) AS net_collected,
    COALESCE(c.gross_collected, 0) - COALESCE(r.refunded, 0) AS total_paid,
    COALESCE(a.active_expected_net_due, 0) AS active_expected_net_due,
    COALESCE(a.active_net_paid, 0) AS active_net_paid,
    COALESCE(a.active_outstanding, 0) AS active_outstanding,
    COALESCE(a.active_enrollments, 0) AS active_enrollments,
    COALESCE(a.withdrawn_enrollments, 0) AS withdrawn_enrollments,
    COALESCE(c.payment_count, 0) AS payment_count
FROM keys k
JOIN public.courses crs ON crs.id = k.course_id
LEFT JOIN cash c
       ON c.course_id = k.course_id AND c.currency = k.currency
LEFT JOIN refunds r
       ON r.course_id = k.course_id AND r.currency = k.currency
LEFT JOIN accrual a
       ON a.course_id = k.course_id AND a.currency = k.currency
WHERE public.c1_is_staff()
   OR auth.role() IS NULL
   OR auth.role() = 'service_role';

-- ----------------------------------------------------------------------------
-- 4) الخصومات: الأصلية + التعديلات اليدوية السالبة، للفعّالين فقط
--    withdrawal_settlement و debt_writeoff تُستبعد (ليست خصومات تسويقية).
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW public.discounts_report_v2 AS
WITH manual AS (
    SELECT
        fa.enrollment_id,
        SUM(CASE WHEN fa.kind = 'manual' AND fa.amount < 0 THEN -fa.amount ELSE 0 END) AS manual_discounts,
        COUNT(*) FILTER (WHERE fa.kind = 'manual' AND fa.amount < 0) AS manual_count
    FROM public.fee_adjustments fa
    GROUP BY fa.enrollment_id
)
SELECT
    e.id AS enrollment_id,
    t.trainee_code,
    u.full_name AS trainee_name,
    crs.name AS course_name,
    e.currency::text AS currency,
    COALESCE(e.discount_amount, 0) AS original_discount,
    COALESCE(m.manual_discounts, 0) AS manual_discounts,
    COALESCE(e.discount_amount, 0) + COALESCE(m.manual_discounts, 0) AS total_discounts,
    COALESCE(m.manual_count, 0) AS manual_count
FROM public.enrollments e
JOIN public.trainees t ON t.id = e.trainee_id
LEFT JOIN public.users u ON u.id = t.user_id
LEFT JOIN public.cohorts co ON co.id = e.cohort_id
LEFT JOIN public.courses crs ON crs.id = co.course_id
LEFT JOIN manual m ON m.enrollment_id = e.id
WHERE e.lifecycle_status <> 'withdrawn'
  AND (COALESCE(e.discount_amount, 0) + COALESCE(m.manual_discounts, 0)) > 0
  AND (public.c1_is_staff() OR auth.role() IS NULL OR auth.role() = 'service_role');

-- ----------------------------------------------------------------------------
-- 5) أعمار الديون: أقساط الفعّالين المتأخرة، صف لكل (عملة, شريحة)
--    التخصيصات صافية من الاستردادات بفعل c1_allocate_payment.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW public.debt_aging_report_v2 AS
WITH alloc AS (
    SELECT
        pa.installment_id,
        SUM(pa.amount) AS allocated
    FROM public.payment_allocations pa
    GROUP BY pa.installment_id
),
open_installments AS (
    SELECT
        s.id,
        s.enrollment_id,
        s.due_date,
        s.currency::text AS currency,
        e.trainee_id,
        GREATEST(s.amount - COALESCE(a.allocated, 0), 0) AS remaining,
        (now() AT TIME ZONE 'Asia/Damascus')::date - s.due_date AS days_overdue
    FROM public.installment_schedule s
    JOIN public.enrollments e ON e.id = s.enrollment_id
    LEFT JOIN alloc a ON a.installment_id = s.id
    WHERE e.lifecycle_status <> 'withdrawn'
      AND s.due_date < (now() AT TIME ZONE 'Asia/Damascus')::date
)
SELECT
    currency,
    CASE
        WHEN days_overdue <= 30 THEN '1-30'
        WHEN days_overdue <= 90 THEN '31-90'
        ELSE '>90'
    END AS aging_bucket,
    SUM(remaining) AS total_overdue_balance,
    COUNT(*) AS installments_count,
    COUNT(DISTINCT trainee_id) AS trainees_count,
    MIN(due_date) AS oldest_due_date
FROM open_installments
WHERE remaining > 0
  AND (public.c1_is_staff() OR auth.role() IS NULL OR auth.role() = 'service_role')
GROUP BY currency, aging_bucket;

-- ----------------------------------------------------------------------------
-- 6) المصاريف حسب التصنيف: صف لكل (تصنيف, عملة)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW public.expenses_by_category_report_v2 AS
SELECT
    x.category,
    x.currency::text AS currency,
    SUM(x.amount) AS total_spent,
    COUNT(*) AS expense_count
FROM public.expenses x
WHERE public.c1_is_staff()
   OR auth.role() IS NULL
   OR auth.role() = 'service_role'
GROUP BY x.category, x.currency::text;

-- ----------------------------------------------------------------------------
-- 7) النقدي مقابل الاستحقاقي: صف لكل عملة مع فصل صريح للمنسحبين
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW public.cash_vs_accrual_kpis_v2 AS
WITH gross AS (
    SELECT
        p.currency::text AS currency,
        SUM(p.amount) AS gross_paid,
        COUNT(*) AS payment_count
    FROM public.payments p
    GROUP BY p.currency::text
),
refunds AS (
    SELECT
        p.currency::text AS currency,
        SUM(r.amount) AS refunds
    FROM public.payment_refunds r
    JOIN public.payments p ON p.id = r.payment_id
    GROUP BY p.currency::text
),
active AS (
    SELECT
        v.currency::text AS currency,
        SUM(v.net_due) AS active_expected_net_due,
        SUM(v.net_paid) AS active_net_paid,
        SUM(GREATEST(v.current_balance, 0)) AS active_outstanding,
        COUNT(*) AS active_enrollments
    FROM public.enrollment_financial_summary_v2 v
    WHERE v.lifecycle_status <> 'withdrawn'
    GROUP BY v.currency::text
),
withdrawn AS (
    SELECT
        v.currency::text AS currency,
        SUM(v.net_paid) AS withdrawn_net_paid,
        SUM(GREATEST(v.current_balance, 0)) AS withdrawn_outstanding,
        COUNT(*) AS withdrawn_enrollments
    FROM public.enrollment_financial_summary_v2 v
    WHERE v.lifecycle_status = 'withdrawn'
    GROUP BY v.currency::text
),
all_enrollments AS (
    SELECT
        v.currency::text AS currency,
        SUM(v.net_due) AS all_expected_net_due,
        SUM(v.current_balance) AS all_outstanding
    FROM public.enrollment_financial_summary_v2 v
    GROUP BY v.currency::text
),
currencies AS (
    SELECT currency FROM gross
    UNION
    SELECT currency FROM refunds
    UNION
    SELECT currency FROM all_enrollments
)
SELECT
    c.currency,
    COALESCE(g.gross_paid, 0) AS gross_paid,
    COALESCE(r.refunds, 0) AS refunds,
    COALESCE(g.gross_paid, 0) - COALESCE(r.refunds, 0) AS cash_collected,
    COALESCE(a.active_expected_net_due, 0) AS active_expected_net_due,
    COALESCE(a.active_net_paid, 0) AS active_net_paid,
    COALESCE(a.active_outstanding, 0) AS active_outstanding,
    COALESCE(a.active_enrollments, 0) AS active_enrollments,
    COALESCE(w.withdrawn_net_paid, 0) AS withdrawn_net_paid,
    COALESCE(w.withdrawn_outstanding, 0) AS withdrawn_outstanding,
    COALESCE(w.withdrawn_enrollments, 0) AS withdrawn_enrollments,
    COALESCE(av.all_expected_net_due, 0) AS all_expected_net_due,
    COALESCE(av.all_outstanding, 0) AS all_outstanding,
    COALESCE(g.payment_count, 0) AS payment_count
FROM currencies c
LEFT JOIN gross g ON g.currency = c.currency
LEFT JOIN refunds r ON r.currency = c.currency
LEFT JOIN active a ON a.currency = c.currency
LEFT JOIN withdrawn w ON w.currency = c.currency
LEFT JOIN all_enrollments av ON av.currency = c.currency
WHERE public.c1_is_staff()
   OR auth.role() IS NULL
   OR auth.role() = 'service_role';

-- ----------------------------------------------------------------------------
-- 8) الصلاحيات: سحب anon/PUBLIC عن العروض الجديدة والقديمة، قراءة للمصادقين
-- ----------------------------------------------------------------------------
DO $$
DECLARE
    v_name text;
    v_new text[] := ARRAY[
        'profit_loss_report_v2',
        'revenue_by_method_report_v2',
        'course_revenue_sql_summary_v2',
        'discounts_report_v2',
        'debt_aging_report_v2',
        'expenses_by_category_report_v2',
        'cash_vs_accrual_kpis_v2'
    ];
    v_legacy text[] := ARRAY[
        'profit_loss_report',
        'course_revenue_sql_summary',
        'revenue_by_method_report',
        'discounts_report',
        'debt_aging_report',
        'expenses_by_category_report',
        'cash_vs_accrual_kpis'
    ];
BEGIN
    FOREACH v_name IN ARRAY v_new LOOP
        EXECUTE format('REVOKE ALL ON public.%I FROM PUBLIC, anon', v_name);
        EXECUTE format('GRANT SELECT ON public.%I TO authenticated, service_role', v_name);
    END LOOP;

    FOREACH v_name IN ARRAY v_legacy LOOP
        IF to_regclass('public.' || v_name) IS NOT NULL THEN
            EXECUTE format('REVOKE ALL ON public.%I FROM PUBLIC, anon', v_name);
            EXECUTE format('GRANT SELECT ON public.%I TO authenticated, service_role', v_name);
        END IF;
    END LOOP;
END $$;
