-- ============================================================================
-- Phase C2.4 — Ledger triggers (payments / expenses / refunds)
-- ============================================================================
-- Every write to payments, expenses or payment_refunds keeps
-- account_transactions in sync. Functions are SECURITY DEFINER because:
--   * reception can INSERT payments but has no grant/policy on
--     account_transactions (admin-only), and
--   * the rule lookup must read financial_accounts regardless of caller RLS.
-- search_path is pinned on every function, matching the existing trigger
-- pattern (update_enrollment_payment_status, baseline:4435-4455).
--
-- Account resolution rules (no silent fallback):
--   cash       -> cash box of the same currency
--   transfer   -> bank account of the same currency
--   sham_cash  -> محفظة Sham Cash (SYP only)
--   hawala     -> محفظة هرم (SYP only)
--   other/NULL -> RAISE EXCEPTION: caller must supply account_id explicitly
--   expense    -> cash box of the expense currency, marked auto_expense_cash
--
-- `app.account_tx_derivation` is an optional per-transaction GUC used by the
-- backfill (07) to stamp derivation = 'backfill'; normal app writes never set
-- it and fall back to manual/auto_*.
--
-- Rebuild-safe.
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- 1. Resolution helpers (read-only, owner-rights)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_account_for_payment_method(
  p_method public.payment_method,
  p_currency public.currency_type
) RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT a.id
  FROM public.financial_accounts a
  WHERE a.is_active
    AND a.currency = p_currency
    AND (
      (p_method = 'cash'      AND a.account_type = 'cash') OR
      (p_method = 'transfer'  AND a.account_type = 'bank') OR
      (p_method = 'sham_cash' AND a.account_type = 'wallet' AND a.name_ar = 'محفظة Sham Cash') OR
      (p_method = 'hawala'    AND a.account_type = 'wallet' AND a.name_ar = 'محفظة هرم')
    )
  LIMIT 1;
$$;

COMMENT ON FUNCTION public.fn_account_for_payment_method(public.payment_method, public.currency_type) IS
  'Maps a payment method + currency to its custody account. Returns NULL for other/unsupported so callers fail loudly instead of guessing.';

CREATE OR REPLACE FUNCTION public.fn_default_cash_account(
  p_currency public.currency_type
) RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT a.id
  FROM public.financial_accounts a
  WHERE a.is_active
    AND a.account_type = 'cash'
    AND a.currency = p_currency
  LIMIT 1;
$$;

COMMENT ON FUNCTION public.fn_default_cash_account(public.currency_type) IS
  'Cash box of the given currency. Used as the attested default for expenses, which carry no payment method.';

-- ----------------------------------------------------------------------------
-- 2. Derivation helper
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_account_tx_derivation(p_has_manual_account boolean, p_default text)
RETURNS text
LANGUAGE plpgsql
STABLE
SET search_path = public, pg_temp
AS $$
DECLARE
  v_override text := NULLIF(current_setting('app.account_tx_derivation', true), '');
BEGIN
  IF v_override IN ('backfill', 'admin_attested') THEN
    RETURN v_override;
  END IF;
  IF p_has_manual_account THEN
    RETURN 'manual';
  END IF;
  RETURN p_default;
END;
$$;

-- ----------------------------------------------------------------------------
-- 3. Payments -> ledger
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.trg_fn_account_tx_payment()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_account uuid;
  v_derivation text;
BEGIN
  IF TG_OP = 'DELETE' THEN
    DELETE FROM public.account_transactions
     WHERE source_type = 'payment' AND source_id = OLD.id;
    RETURN OLD;
  END IF;

  v_account := COALESCE(
    NEW.account_id,
    public.fn_account_for_payment_method(NEW.method, NEW.currency)
  );

  IF v_account IS NULL THEN
    RAISE EXCEPTION
      'لا يوجد حساب مالي مطابق لطريقة الدفع % بعملة %؛ حدّد account_id صراحةً أو أضف الحساب أولاً',
      NEW.method, NEW.currency;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.financial_accounts a
     WHERE a.id = v_account AND a.currency = NEW.currency
  ) THEN
    RAISE EXCEPTION 'عملة الحساب المالي (%) لا تطابق عملة الدفعة (%)',
      (SELECT a.currency FROM public.financial_accounts a WHERE a.id = v_account),
      NEW.currency;
  END IF;

  v_derivation := public.fn_account_tx_derivation(NEW.account_id IS NOT NULL, 'auto_method');

  DELETE FROM public.account_transactions
   WHERE source_type = 'payment' AND source_id = NEW.id;

  INSERT INTO public.account_transactions (
    account_id, direction, amount, source_type, source_id,
    derivation, occurred_at, notes, created_by
  ) VALUES (
    v_account, 'inflow', NEW.amount, 'payment', NEW.id,
    v_derivation, NEW.paid_at, NEW.notes, COALESCE(NEW.performed_by, auth.uid())
  );

  -- A refund follows the account that received its payment.
  UPDATE public.account_transactions t
     SET account_id = v_account
   WHERE t.source_type = 'refund'
     AND t.source_id IN (
       SELECT r.id FROM public.payment_refunds r WHERE r.payment_id = NEW.id
     );

  RETURN NEW;
END;
$$;

-- ----------------------------------------------------------------------------
-- 4. Expenses -> ledger
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.trg_fn_account_tx_expense()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_account uuid;
  v_derivation text;
BEGIN
  IF TG_OP = 'DELETE' THEN
    DELETE FROM public.account_transactions
     WHERE source_type = 'expense' AND source_id = OLD.id;
    RETURN OLD;
  END IF;

  v_account := COALESCE(NEW.account_id, public.fn_default_cash_account(NEW.currency));

  IF v_account IS NULL THEN
    RAISE EXCEPTION 'لا يوجد صندوق نقدي بعملة %؛ أنشئ الحساب أو حدّد account_id صراحةً', NEW.currency;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.financial_accounts a
     WHERE a.id = v_account AND a.currency = NEW.currency
  ) THEN
    RAISE EXCEPTION 'عملة الحساب المالي لا تطابق عملة المصروف';
  END IF;

  v_derivation := public.fn_account_tx_derivation(NEW.account_id IS NOT NULL, 'auto_expense_cash');

  DELETE FROM public.account_transactions
   WHERE source_type = 'expense' AND source_id = NEW.id;

  INSERT INTO public.account_transactions (
    account_id, direction, amount, source_type, source_id,
    derivation, occurred_at, notes, created_by
  ) VALUES (
    v_account, 'outflow', NEW.amount, 'expense', NEW.id,
    v_derivation,
    (NEW.expense_date::timestamp AT TIME ZONE 'Asia/Damascus'),
    NEW.description, COALESCE(NEW.performed_by, auth.uid())
  );

  RETURN NEW;
END;
$$;

-- ----------------------------------------------------------------------------
-- 5. Refunds -> ledger (outflow from the account that received the payment)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.trg_fn_account_tx_refund()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_payment public.payments%ROWTYPE;
  v_account uuid;
  v_derivation text;
BEGIN
  IF TG_OP = 'DELETE' THEN
    DELETE FROM public.account_transactions
     WHERE source_type = 'refund' AND source_id = OLD.id;
    RETURN OLD;
  END IF;

  SELECT * INTO v_payment FROM public.payments p WHERE p.id = NEW.payment_id;

  v_account := COALESCE(
    v_payment.account_id,
    public.fn_account_for_payment_method(v_payment.method, v_payment.currency)
  );

  IF v_account IS NULL THEN
    RAISE EXCEPTION
      'لا يمكن تسجيل استرداد: الدفعة الأصلية % بلا حساب مالي محدد (طريقة %)',
      NEW.payment_id, v_payment.method;
  END IF;

  v_derivation := public.fn_account_tx_derivation(v_payment.account_id IS NOT NULL, 'auto_method');

  DELETE FROM public.account_transactions
   WHERE source_type = 'refund' AND source_id = NEW.id;

  INSERT INTO public.account_transactions (
    account_id, direction, amount, source_type, source_id,
    derivation, occurred_at, notes, created_by
  ) VALUES (
    v_account, 'outflow', NEW.amount, 'refund', NEW.id,
    v_derivation, NEW.refunded_at, NEW.reason, COALESCE(NEW.created_by, auth.uid())
  );

  RETURN NEW;
END;
$$;

-- ----------------------------------------------------------------------------
-- 6. Triggers
-- ----------------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_c2_account_tx_payment ON public.payments;
CREATE TRIGGER trg_c2_account_tx_payment
  AFTER INSERT OR UPDATE OR DELETE ON public.payments
  FOR EACH ROW EXECUTE FUNCTION public.trg_fn_account_tx_payment();

DROP TRIGGER IF EXISTS trg_c2_account_tx_expense ON public.expenses;
CREATE TRIGGER trg_c2_account_tx_expense
  AFTER INSERT OR UPDATE OR DELETE ON public.expenses
  FOR EACH ROW EXECUTE FUNCTION public.trg_fn_account_tx_expense();

DROP TRIGGER IF EXISTS trg_c2_account_tx_refund ON public.payment_refunds;
CREATE TRIGGER trg_c2_account_tx_refund
  AFTER INSERT OR UPDATE OR DELETE ON public.payment_refunds
  FOR EACH ROW EXECUTE FUNCTION public.trg_fn_account_tx_refund();

-- ----------------------------------------------------------------------------
-- 7. ACL — never executable by anon; trigger functions cannot be called
--    directly, and the helpers are only used inside owner-rights triggers.
-- ----------------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.fn_account_for_payment_method(public.payment_method, public.currency_type) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.fn_default_cash_account(public.currency_type) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.fn_account_tx_derivation(boolean, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.trg_fn_account_tx_payment() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.trg_fn_account_tx_expense() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.trg_fn_account_tx_refund() FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.fn_account_for_payment_method(public.payment_method, public.currency_type) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_default_cash_account(public.currency_type) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_account_tx_derivation(boolean, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.trg_fn_account_tx_payment() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.trg_fn_account_tx_expense() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.trg_fn_account_tx_refund() TO authenticated, service_role;

COMMIT;
