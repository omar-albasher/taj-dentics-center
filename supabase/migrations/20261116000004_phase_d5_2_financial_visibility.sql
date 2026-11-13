-- ============================================================================
-- Phase D5.2 — Financial visibility hardening
-- ============================================================================
-- Scope:
--   1. public.c1_is_admin(): active admin by public.users (immediate revocation,
--      independent of user_metadata.role injected into the JWT).
--   2. dashboard_kpis keeps exactly ONE row for every staff member, but all
--      financial columns are redacted (NULL) unless the caller is an admin or a
--      trusted backend context (service_role / direct owner / pg_cron).
--   3. The seven _v2 financial report views are restricted to admin + trusted
--      contexts. Definitions are copied verbatim from the live schema
--      (supabase/baseline/schema_live_baseline.sql) with only the staff guard
--      replaced by c1_is_admin().
--   4. Operational financials required by reception remain untouched:
--      enrollment_financial_summary_v2, trainee_statement_v,
--      overdue_installments_v, overdue_payments (c1_can_read_financials).
--
-- Why view-level guards: these views are NOT security_invoker, so they run with
-- owner privileges and bypass table RLS. The WHERE clause is the only boundary.
--
-- Rebuild-safe: every object below is declared in the repository.
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- 1. Helper: c1_is_admin()
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.c1_is_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.users
    WHERE id = auth.uid()
      AND role = 'admin'
      AND is_active = true
  );
$$;

COMMENT ON FUNCTION public.c1_is_admin() IS
  'True only for an active admin row in public.users; used by financial views.';

REVOKE EXECUTE ON FUNCTION public.c1_is_admin() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.c1_is_admin() TO authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 2. dashboard_kpis — 18 columns preserved, financials redacted for reception
--    (same 18 columns and order as the live view; CREATE OR REPLACE keeps ACLs)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW public.dashboard_kpis AS
WITH fin AS (
    SELECT * FROM public.enrollment_financial_summary_v2
),
kpi AS (
    SELECT
        (SELECT count(*) FROM public.trainees) AS total_trainees,
        (SELECT count(*) FROM public.trainees t
          JOIN public.users u ON u.id = t.user_id
          WHERE u.is_active = true) AS active_trainees,
        (SELECT count(*) FROM fin
          WHERE payment_status = 'partial'
            AND lifecycle_status <> 'withdrawn') AS partial_count,
        (SELECT count(*) FROM fin
          WHERE payment_status = 'unpaid'
            AND lifecycle_status <> 'withdrawn') AS unpaid_count,
        COALESCE((SELECT sum(p.amount) FROM public.payments p
                   WHERE p.currency = 'SYP'), 0) AS total_paid_syp,
        COALESCE((SELECT sum(p.amount) FROM public.payments p
                   WHERE p.currency = 'USD'), 0) AS total_paid_usd,
        COALESCE((SELECT sum(r.amount) FROM public.payment_refunds r
                   JOIN public.payments p ON p.id = r.payment_id
                   WHERE p.currency = 'SYP'), 0) AS total_refunded_syp,
        COALESCE((SELECT sum(r.amount) FROM public.payment_refunds r
                   JOIN public.payments p ON p.id = r.payment_id
                   WHERE p.currency = 'USD'), 0) AS total_refunded_usd,
        COALESCE((SELECT sum(x.amount) FROM public.expenses x
                   WHERE x.currency = 'SYP'), 0) AS total_exp_syp,
        COALESCE((SELECT sum(x.amount) FROM public.expenses x
                   WHERE x.currency = 'USD'), 0) AS total_exp_usd,
        COALESCE((SELECT sum(GREATEST(f.current_balance, 0)) FROM fin f
                   WHERE f.currency = 'SYP'
                     AND f.lifecycle_status <> 'withdrawn'), 0) AS total_balance_syp,
        COALESCE((SELECT sum(GREATEST(f.current_balance, 0)) FROM fin f
                   WHERE f.currency = 'USD'
                     AND f.lifecycle_status <> 'withdrawn'), 0) AS total_balance_usd,
        COALESCE((SELECT sum(GREATEST(f.net_paid - f.net_due, 0)) FROM fin f
                   WHERE f.currency = 'SYP'), 0) AS total_overpaid_syp,
        COALESCE((SELECT sum(GREATEST(f.net_paid - f.net_due, 0)) FROM fin f
                   WHERE f.currency = 'USD'), 0) AS total_overpaid_usd,
        COALESCE((SELECT sum(p.amount) FROM public.payments p
                   WHERE p.currency = 'SYP'), 0)
          - COALESCE((SELECT sum(r.amount) FROM public.payment_refunds r
                       JOIN public.payments p ON p.id = r.payment_id
                       WHERE p.currency = 'SYP'), 0) AS net_paid_syp,
        COALESCE((SELECT sum(p.amount) FROM public.payments p
                   WHERE p.currency = 'USD'), 0)
          - COALESCE((SELECT sum(r.amount) FROM public.payment_refunds r
                       JOIN public.payments p ON p.id = r.payment_id
                       WHERE p.currency = 'USD'), 0) AS net_paid_usd
),
authz AS (
    SELECT (
        auth.role() IS NULL
        OR auth.role() = 'service_role'
        OR public.c1_is_admin()
    ) AS allow_financials
)
SELECT
    k.total_trainees,
    k.active_trainees,
    CASE WHEN a.allow_financials THEN k.partial_count END AS partial_count,
    CASE WHEN a.allow_financials THEN k.unpaid_count END AS unpaid_count,
    CASE WHEN a.allow_financials THEN k.total_paid_syp END AS total_paid_syp,
    CASE WHEN a.allow_financials THEN k.total_paid_usd END AS total_paid_usd,
    CASE WHEN a.allow_financials THEN k.total_refunded_syp END AS total_refunded_syp,
    CASE WHEN a.allow_financials THEN k.total_refunded_usd END AS total_refunded_usd,
    CASE WHEN a.allow_financials THEN k.total_exp_syp END AS total_exp_syp,
    CASE WHEN a.allow_financials THEN k.total_exp_usd END AS total_exp_usd,
    CASE WHEN a.allow_financials THEN k.total_balance_syp END AS total_balance_syp,
    CASE WHEN a.allow_financials THEN k.total_balance_usd END AS total_balance_usd,
    CASE WHEN a.allow_financials THEN k.total_overpaid_syp END AS total_overpaid_syp,
    CASE WHEN a.allow_financials THEN k.total_overpaid_usd END AS total_overpaid_usd,
    CASE WHEN a.allow_financials THEN k.net_paid_syp END AS net_paid_syp,
    CASE WHEN a.allow_financials THEN k.net_paid_usd END AS net_paid_usd,
    CASE WHEN a.allow_financials
         THEN (k.net_paid_syp - k.total_exp_syp) END AS net_profit_syp,
    CASE WHEN a.allow_financials
         THEN (k.net_paid_usd - k.total_exp_usd) END AS net_profit_usd
FROM kpi k
CROSS JOIN authz a
WHERE public.c1_can_read_financials(NULL::uuid);

COMMENT ON VIEW public.dashboard_kpis IS
  'KPIs: one row for every staff member. total_trainees/active_trainees always visible; all financial columns are NULL unless admin or trusted backend context.';

-- ----------------------------------------------------------------------------
-- 3. The seven _v2 financial report views — admin + trusted contexts only
--    (bodies copied from the live schema; only the staff guard changed)
-- ----------------------------------------------------------------------------

-- 3.1 profit_loss_report_v2
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
WHERE public.c1_is_admin()
   OR auth.role() IS NULL
   OR auth.role() = 'service_role'
GROUP BY month, currency;

-- 3.2 revenue_by_method_report_v2
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
WHERE public.c1_is_admin()
   OR auth.role() IS NULL
   OR auth.role() = 'service_role';

-- 3.3 course_revenue_sql_summary_v2
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
WHERE public.c1_is_admin()
   OR auth.role() IS NULL
   OR auth.role() = 'service_role';

-- 3.4 discounts_report_v2
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
  AND (public.c1_is_admin() OR auth.role() IS NULL OR auth.role() = 'service_role');

-- 3.5 debt_aging_report_v2
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
  AND (public.c1_is_admin() OR auth.role() IS NULL OR auth.role() = 'service_role')
GROUP BY currency, aging_bucket;

-- 3.6 expenses_by_category_report_v2
CREATE OR REPLACE VIEW public.expenses_by_category_report_v2 AS
SELECT
    x.category,
    x.currency::text AS currency,
    SUM(x.amount) AS total_spent,
    COUNT(*) AS expense_count
FROM public.expenses x
WHERE public.c1_is_admin()
   OR auth.role() IS NULL
   OR auth.role() = 'service_role'
GROUP BY x.category, x.currency::text;

-- 3.7 cash_vs_accrual_kpis_v2
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
WHERE public.c1_is_admin()
   OR auth.role() IS NULL
   OR auth.role() = 'service_role';

-- ----------------------------------------------------------------------------
-- 4. Grants (idempotent; CREATE OR REPLACE already preserves existing ACLs)
-- ----------------------------------------------------------------------------
DO $$
DECLARE
    v_name text;
    v_views text[] := ARRAY[
        'dashboard_kpis',
        'profit_loss_report_v2',
        'revenue_by_method_report_v2',
        'course_revenue_sql_summary_v2',
        'discounts_report_v2',
        'debt_aging_report_v2',
        'expenses_by_category_report_v2',
        'cash_vs_accrual_kpis_v2'
    ];
BEGIN
    FOREACH v_name IN ARRAY v_views LOOP
        EXECUTE format('REVOKE ALL ON public.%I FROM PUBLIC, anon', v_name);
        EXECUTE format('GRANT SELECT ON public.%I TO authenticated, service_role', v_name);
    END LOOP;

    -- Grant missing execute privilege on helper function to authenticated
    GRANT EXECUTE ON FUNCTION public.enrollment_lifecycle_occupies_seat(text) TO authenticated;
END $$;

COMMIT;
