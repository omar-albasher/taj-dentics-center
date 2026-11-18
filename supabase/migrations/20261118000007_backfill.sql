-- ============================================================================
-- Phase C2.7 — Backfill historical payments & expenses into custody ledger
-- ============================================================================
-- Two-part migration:
--   Part 1: Dry-run audit report (read-only). Run this first in Gate G-C2.2!
--   Part 2: Idempotent transactional backfill. Run after reviewing Part 1 in Gate G-C2.3!
--
-- Derivation strategy:
--   * Uses `SET LOCAL app.account_tx_derivation = 'backfill'` so every
--     auto-created transaction carries derivation = 'backfill'.
--   * Payments: resolves account by (method, currency) rule.
--   * Expenses: defaults to cash box of the same currency (derivation = 'auto_expense_cash' / 'backfill').
--   * Refunds: links to the account of the parent payment.
--
-- Rebuild-safe and idempotent.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- PART 1: DRY-RUN AUDIT REPORT (Read-only, no data modified)
-- ----------------------------------------------------------------------------
/*
-- 1.A: Payments preview by resolved account
SELECT 
  a.name_ar AS target_account,
  a.account_type,
  p.currency,
  p.method,
  COUNT(p.id) AS payment_count,
  COALESCE(SUM(p.amount), 0) AS total_amount
FROM public.payments p
LEFT JOIN public.financial_accounts a ON a.id = COALESCE(
  p.account_id,
  public.fn_account_for_payment_method(p.method, p.currency)
)
GROUP BY a.name_ar, a.account_type, p.currency, p.method
ORDER BY p.currency, a.name_ar;

-- 1.B: Payments EXCEPTIONS (rows that cannot be resolved automatically)
SELECT 
  p.id,
  p.enrollment_id,
  p.amount,
  p.currency,
  p.method,
  p.paid_at,
  'لا يوجد حساب مطابق أو الطريقة other' AS reason
FROM public.payments p
WHERE public.fn_account_for_payment_method(p.method, p.currency) IS NULL
  AND p.account_id IS NULL;

-- 1.C: Expenses preview by resolved cash box
SELECT 
  a.name_ar AS target_account,
  x.currency,
  COUNT(x.id) AS expense_count,
  COALESCE(SUM(x.amount), 0) AS total_amount
FROM public.expenses x
LEFT JOIN public.financial_accounts a ON a.id = COALESCE(
  x.account_id,
  public.fn_default_cash_account(x.currency)
)
GROUP BY a.name_ar, x.currency
ORDER BY x.currency;

-- 1.D: Expenses EXCEPTIONS
SELECT 
  x.id,
  x.category,
  x.amount,
  x.currency,
  x.expense_date,
  'لا يوجد صندوق نقدي مطابق للعملة' AS reason
FROM public.expenses x
WHERE public.fn_default_cash_account(x.currency) IS NULL
  AND x.account_id IS NULL;

-- 1.E: Refunds preview
SELECT 
  COUNT(r.id) AS refund_count,
  COALESCE(SUM(r.amount), 0) AS total_refunded
FROM public.payment_refunds r;
*/

-- ----------------------------------------------------------------------------
-- PART 2: THE TRANSACTIONAL BACKFILL SCRIPT (Run in Gate G-C2.3)
-- ----------------------------------------------------------------------------
BEGIN;

-- Tell triggers to stamp derivation = 'backfill'
SET LOCAL app.account_tx_derivation = 'backfill';

-- 1. Backfill Payments
-- Setting account_id fires trg_c2_account_tx_payment automatically, which inserts into account_transactions
DO $$
DECLARE
  v_rec RECORD;
  v_acc uuid;
  v_count integer := 0;
BEGIN
  FOR v_rec IN 
    SELECT p.id, p.method, p.currency 
    FROM public.payments p 
    WHERE p.account_id IS NULL
  LOOP
    v_acc := public.fn_account_for_payment_method(v_rec.method, v_rec.currency);
    IF v_acc IS NOT NULL THEN
      UPDATE public.payments
         SET account_id = v_acc
       WHERE id = v_rec.id;
      v_count := v_count + 1;
    END IF;
  END LOOP;
  RAISE NOTICE 'Backfilled % payments with their custody accounts', v_count;
END $$;

-- 2. Backfill Expenses
-- Setting account_id fires trg_c2_account_tx_expense automatically
DO $$
DECLARE
  v_rec RECORD;
  v_acc uuid;
  v_count integer := 0;
BEGIN
  FOR v_rec IN 
    SELECT x.id, x.currency 
    FROM public.expenses x 
    WHERE x.account_id IS NULL
  LOOP
    v_acc := public.fn_default_cash_account(v_rec.currency);
    IF v_acc IS NOT NULL THEN
      UPDATE public.expenses
         SET account_id = v_acc
       WHERE id = v_rec.id;
      v_count := v_count + 1;
    END IF;
  END LOOP;
  RAISE NOTICE 'Backfilled % expenses with cash accounts', v_count;
END $$;

-- 3. Ensure any existing refunds have ledger entries
DO $$
DECLARE
  v_rec RECORD;
BEGIN
  FOR v_rec IN 
    SELECT r.id, r.payment_id, r.amount, r.reason, r.refunded_at, r.created_by, p.account_id
    FROM public.payment_refunds r
    JOIN public.payments p ON p.id = r.payment_id
    WHERE NOT EXISTS (
      SELECT 1 FROM public.account_transactions t
       WHERE t.source_type = 'refund' AND t.source_id = r.id
    )
  LOOP
    IF v_rec.account_id IS NOT NULL THEN
      INSERT INTO public.account_transactions (
        account_id, direction, amount, source_type, source_id,
        derivation, occurred_at, notes, created_by
      ) VALUES (
        v_rec.account_id, 'outflow', v_rec.amount, 'refund', v_rec.id,
        'backfill', v_rec.refunded_at, v_rec.reason, v_rec.created_by
      );
    END IF;
  END LOOP;
END $$;

COMMIT;
