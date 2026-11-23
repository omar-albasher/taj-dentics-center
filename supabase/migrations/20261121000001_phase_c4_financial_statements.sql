-- ============================================================================
-- Phase C4 — Financial statements (v3)
-- ============================================================================
-- Read-only reporting layer over the money already recorded by C1/C2/C3.
-- Nothing here writes; no table, trigger, policy or ledger rule is modified.
--
-- Design decisions (approved 2026-11-21):
--   * Academy P&L is CASH basis: income = payments received, refunds reduce
--     income, expenses = expenses rows. Accrual figures stay in
--     enrollment_financial_summary_v2 / cash_vs_accrual_kpis_v2 (D4).
--   * Lab is a separate, labelled section: income = lab_payments actually
--     received, costs = lab_expenses. Uncollected invoice balances are a
--     memorandum item only and never touch net profit.
--   * Cash flow comes exclusively from account_transactions (C2 ledger), so
--     opening + inflows - outflows always equals closing per account.
--   * Period boundaries are Damascus business dates, matching
--     profit_loss_report_v2 (paid_at AT TIME ZONE 'Asia/Damascus').
--
-- Access: admin only. Every function is SECURITY DEFINER with a pinned
-- search_path and an explicit c1_is_admin() guard, and EXECUTE is revoked
-- from PUBLIC/anon (same pattern as transfer_between_accounts, C2.6).
--
-- Rebuild-safe: CREATE OR REPLACE + IF NOT EXISTS only.
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- 1. Profit & loss, per currency and section
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_profit_loss(
  p_from date,
  p_to date
) RETURNS TABLE (
  currency text,
  section text,
  income numeric,
  refunds numeric,
  expenses numeric,
  net numeric,
  memorandum_uncollected numeric
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_start timestamptz;
  v_end timestamptz;
BEGIN
  IF NOT public.c1_is_admin() THEN
    RAISE EXCEPTION 'غير مصرّح: القوائم المالية متاحة لمدير المركز فقط';
  END IF;

  IF p_from IS NULL OR p_to IS NULL OR p_from > p_to THEN
    RAISE EXCEPTION 'مدى الفترة غير صالح: من % إلى %', p_from, p_to;
  END IF;

  v_start := (p_from::timestamp AT TIME ZONE 'Asia/Damascus');
  v_end := ((p_to + 1)::timestamp AT TIME ZONE 'Asia/Damascus');

  RETURN QUERY
  WITH acad AS (
    SELECT p.currency::text AS curr,
           SUM(p.amount) AS inc,
           0::numeric AS rfnd,
           0::numeric AS spend
      FROM public.payments p
     WHERE p.paid_at >= v_start
       AND p.paid_at < v_end
     GROUP BY p.currency
    UNION ALL
    SELECT p.currency::text,
           0::numeric,
           SUM(r.amount),
           0::numeric
      FROM public.payment_refunds r
      JOIN public.payments p ON p.id = r.payment_id
     WHERE r.refunded_at >= v_start
       AND r.refunded_at < v_end
     GROUP BY p.currency
    UNION ALL
    SELECT x.currency::text,
           0::numeric,
           0::numeric,
           SUM(x.amount)
      FROM public.expenses x
     WHERE x.expense_date BETWEEN p_from AND p_to
     GROUP BY x.currency
  ),
  acad_agg AS (
    SELECT curr, SUM(inc) AS inc, SUM(rfnd) AS rfnd, SUM(spend) AS spend
      FROM acad
     GROUP BY curr
  ),
  lab_ev AS (
    SELECT lp.currency::text AS curr,
           SUM(lp.amount) AS inc,
           0::numeric AS spend
      FROM public.lab_payments lp
     WHERE lp.paid_at >= v_start
       AND lp.paid_at < v_end
     GROUP BY lp.currency
    UNION ALL
    SELECT le.currency::text,
           0::numeric,
           SUM(le.amount)
      FROM public.lab_expenses le
     WHERE le.expense_date BETWEEN p_from AND p_to
     GROUP BY le.currency
  ),
  lab_agg AS (
    SELECT curr, SUM(inc) AS inc, SUM(spend) AS spend
      FROM lab_ev
     GROUP BY curr
  ),
  recv AS (
    SELECT li.currency::text AS curr,
           SUM(GREATEST(li.total_amount - li.paid_amount, 0)) AS outstanding
      FROM public.lab_invoices li
     WHERE li.status <> 'cancelled'
       AND li.issue_date <= p_to
     GROUP BY li.currency
  ),
  lab_cur AS (
    SELECT curr FROM lab_agg
    UNION
    SELECT curr FROM recv
  )
  SELECT a.curr,
         'academy'::text,
         ROUND(a.inc, 2),
         ROUND(a.rfnd, 2),
         ROUND(a.spend, 2),
         ROUND(a.inc - a.rfnd - a.spend, 2),
         0::numeric
    FROM acad_agg a
  UNION ALL
  SELECT lc.curr,
         'lab'::text,
         ROUND(COALESCE(la.inc, 0), 2),
         0::numeric,
         ROUND(COALESCE(la.spend, 0), 2),
         ROUND(COALESCE(la.inc, 0) - COALESCE(la.spend, 0), 2),
         ROUND(COALESCE(r.outstanding, 0), 2)
    FROM lab_cur lc
    LEFT JOIN lab_agg la ON la.curr = lc.curr
    LEFT JOIN recv r ON r.curr = lc.curr
   ORDER BY 1, 2;
END;
$$;

COMMENT ON FUNCTION public.get_profit_loss(date, date) IS
  'C4 cash-basis profit & loss per currency. Academy and lab are separate sections; lab memorandum_uncollected is informational only. Admin-only.';

-- ----------------------------------------------------------------------------
-- 2. Expense breakdown (feeds the P&L detail)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_expense_breakdown(
  p_from date,
  p_to date
) RETURNS TABLE (
  section text,
  currency text,
  account_id uuid,
  account_name_ar text,
  category text,
  amount numeric,
  expense_count bigint
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT public.c1_is_admin() THEN
    RAISE EXCEPTION 'غير مصرّح: القوائم المالية متاحة لمدير المركز فقط';
  END IF;

  IF p_from IS NULL OR p_to IS NULL OR p_from > p_to THEN
    RAISE EXCEPTION 'مدى الفترة غير صالح: من % إلى %', p_from, p_to;
  END IF;

  RETURN QUERY
  SELECT 'academy'::text,
         x.currency::text,
         x.account_id,
         a.name_ar,
         x.category::text,
         ROUND(SUM(x.amount), 2),
         COUNT(*)::bigint
    FROM public.expenses x
    LEFT JOIN public.financial_accounts a ON a.id = x.account_id
   WHERE x.expense_date BETWEEN p_from AND p_to
   GROUP BY x.currency, x.account_id, a.name_ar, x.category
  UNION ALL
  SELECT 'lab'::text,
         le.currency,
         NULL::uuid,
         NULL::text,
         le.category,
         ROUND(SUM(le.amount), 2),
         COUNT(*)::bigint
    FROM public.lab_expenses le
   WHERE le.expense_date BETWEEN p_from AND p_to
   GROUP BY le.currency, le.category
   ORDER BY 1, 2, 6 DESC;
END;
$$;

COMMENT ON FUNCTION public.get_expense_breakdown(date, date) IS
  'C4 expense breakdown per section/currency/account/category for the given Damascus-date period. Admin-only.';

-- ----------------------------------------------------------------------------
-- 3. Cash flow statement, per custody account
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_cash_flow_statement(
  p_from date,
  p_to date
) RETURNS TABLE (
  account_id uuid,
  account_name_ar text,
  account_type text,
  currency text,
  opening_balance numeric,
  inflows numeric,
  outflows numeric,
  closing_balance numeric,
  payment_in numeric,
  expense_out numeric,
  refund_out numeric,
  transfer_in numeric,
  transfer_out numeric,
  adjustment_in numeric,
  adjustment_out numeric,
  tx_count bigint
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_start timestamptz;
  v_end timestamptz;
BEGIN
  IF NOT public.c1_is_admin() THEN
    RAISE EXCEPTION 'غير مصرّح: القوائم المالية متاحة لمدير المركز فقط';
  END IF;

  IF p_from IS NULL OR p_to IS NULL OR p_from > p_to THEN
    RAISE EXCEPTION 'مدى الفترة غير صالح: من % إلى %', p_from, p_to;
  END IF;

  v_start := (p_from::timestamp AT TIME ZONE 'Asia/Damascus');
  v_end := ((p_to + 1)::timestamp AT TIME ZONE 'Asia/Damascus');

  RETURN QUERY
  WITH opening AS (
    SELECT t.account_id,
           SUM(CASE WHEN t.direction = 'inflow' THEN t.amount ELSE -t.amount END) AS bal
      FROM public.account_transactions t
     WHERE t.occurred_at < v_start
     GROUP BY t.account_id
  ),
  period AS (
    SELECT t.account_id,
           SUM(CASE WHEN t.direction = 'inflow' THEN t.amount ELSE 0 END) AS inf,
           SUM(CASE WHEN t.direction = 'outflow' THEN t.amount ELSE 0 END) AS outf,
           SUM(CASE WHEN t.direction = 'inflow' AND t.source_type = 'payment' THEN t.amount ELSE 0 END) AS pay_in,
           SUM(CASE WHEN t.direction = 'outflow' AND t.source_type = 'expense' THEN t.amount ELSE 0 END) AS exp_out,
           SUM(CASE WHEN t.direction = 'outflow' AND t.source_type = 'refund' THEN t.amount ELSE 0 END) AS ref_out,
           SUM(CASE WHEN t.direction = 'inflow' AND t.source_type = 'transfer' THEN t.amount ELSE 0 END) AS tr_in,
           SUM(CASE WHEN t.direction = 'outflow' AND t.source_type = 'transfer' THEN t.amount ELSE 0 END) AS tr_out,
           SUM(CASE WHEN t.direction = 'inflow' AND t.source_type = 'adjustment' THEN t.amount ELSE 0 END) AS adj_in,
           SUM(CASE WHEN t.direction = 'outflow' AND t.source_type = 'adjustment' THEN t.amount ELSE 0 END) AS adj_out,
           COUNT(*) AS cnt
      FROM public.account_transactions t
     WHERE t.occurred_at >= v_start
       AND t.occurred_at < v_end
     GROUP BY t.account_id
  )
  SELECT a.id,
         a.name_ar,
         a.account_type::text,
         a.currency::text,
         ROUND(COALESCE(o.bal, 0), 2),
         ROUND(COALESCE(pr.inf, 0), 2),
         ROUND(COALESCE(pr.outf, 0), 2),
         ROUND(COALESCE(o.bal, 0) + COALESCE(pr.inf, 0) - COALESCE(pr.outf, 0), 2),
         ROUND(COALESCE(pr.pay_in, 0), 2),
         ROUND(COALESCE(pr.exp_out, 0), 2),
         ROUND(COALESCE(pr.ref_out, 0), 2),
         ROUND(COALESCE(pr.tr_in, 0), 2),
         ROUND(COALESCE(pr.tr_out, 0), 2),
         ROUND(COALESCE(pr.adj_in, 0), 2),
         ROUND(COALESCE(pr.adj_out, 0), 2),
         COALESCE(pr.cnt, 0)::bigint
    FROM public.financial_accounts a
    LEFT JOIN opening o ON o.account_id = a.id
    LEFT JOIN period pr ON pr.account_id = a.id
   ORDER BY a.currency, a.account_type, a.name_ar;
END;
$$;

COMMENT ON FUNCTION public.get_cash_flow_statement(date, date) IS
  'C4 cash flow per custody account from the C2 ledger: opening, movement by source type, and closing. Admin-only.';

-- ----------------------------------------------------------------------------
-- 4. Integrity check: business events vs ledger (all time)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_financial_integrity()
RETURNS TABLE (
  source_type text,
  currency text,
  events_total numeric,
  ledger_total numeric,
  diff numeric,
  is_balanced boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT public.c1_is_admin() THEN
    RAISE EXCEPTION 'غير مصرّح: القوائم المالية متاحة لمدير المركز فقط';
  END IF;

  RETURN QUERY
  WITH ev AS (
    SELECT 'payment'::text AS st, p.currency::text AS curr, SUM(p.amount) AS amt
      FROM public.payments p
     GROUP BY p.currency
    UNION ALL
    SELECT 'refund'::text, p.currency::text, SUM(r.amount)
      FROM public.payment_refunds r
      JOIN public.payments p ON p.id = r.payment_id
     GROUP BY p.currency
    UNION ALL
    SELECT 'expense'::text, x.currency::text, SUM(x.amount)
      FROM public.expenses x
     GROUP BY x.currency
  ),
  led AS (
    SELECT t.source_type AS st, a.currency::text AS curr, SUM(t.amount) AS amt
      FROM public.account_transactions t
      JOIN public.financial_accounts a ON a.id = t.account_id
     WHERE t.source_type IN ('payment', 'refund', 'expense')
     GROUP BY t.source_type, a.currency
  )
  SELECT COALESCE(e.st, l.st),
         COALESCE(e.curr, l.curr),
         ROUND(COALESCE(e.amt, 0), 2),
         ROUND(COALESCE(l.amt, 0), 2),
         ROUND(COALESCE(e.amt, 0) - COALESCE(l.amt, 0), 2),
         COALESCE(e.amt, 0) = COALESCE(l.amt, 0)
    FROM ev e
    FULL JOIN led l ON l.st = e.st AND l.curr = e.curr
   ORDER BY 1, 2;
END;
$$;

COMMENT ON FUNCTION public.get_financial_integrity() IS
  'C4 all-time cross-check: payments/refunds/expenses totals vs C2 ledger totals per source type and currency. Transfers and adjustments are intentionally excluded. Admin-only.';

-- ----------------------------------------------------------------------------
-- 5. Supporting indexes for period filtering
-- ----------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_payments_paid_at
  ON public.payments (paid_at);

CREATE INDEX IF NOT EXISTS idx_expenses_expense_date
  ON public.expenses (expense_date);

CREATE INDEX IF NOT EXISTS idx_lab_payments_paid_at
  ON public.lab_payments (paid_at);

-- ----------------------------------------------------------------------------
-- 6. Grants
-- ----------------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.get_profit_loss(date, date) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_expense_breakdown(date, date) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_cash_flow_statement(date, date) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_financial_integrity() FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.get_profit_loss(date, date) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_expense_breakdown(date, date) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_cash_flow_statement(date, date) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_financial_integrity() TO authenticated, service_role;

COMMIT;
