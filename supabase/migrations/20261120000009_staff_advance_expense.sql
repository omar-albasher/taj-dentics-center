-- ============================================================================
-- Phase C3.8 — Tie staff advances to the custody ledger
-- ============================================================================
-- Gap closed here: staff_advances.account_id is mandatory and the table
-- comment states that granting an advance is a real cash outflow at that
-- moment, but no trigger listened to staff_advances, so no expense row was
-- written and account_balances_v understated the outflow.
--
-- Design (mirrors trainer_payments.expense_id from C3.6):
--   * BEFORE INSERT writes one expense (category salary_advance) from the
--     advance's own account/currency and stamps NEW.expense_id;
--   * amount/currency/account/date are immutable afterwards, expense_id can
--     only be written by internal SECURITY DEFINER flows (GUC
--     app.c3_advance_internal), never by a direct table update;
--   * cancel_staff_advance deletes the expense so the C2 trigger removes the
--     ledger row, i.e. cancelling an advance returns the cash in the books;
--   * existing open/deducted rows are backfilled (cancelled rows never paid
--     anything and are skipped).
--
-- Rebuild-safe: IF NOT EXISTS / CREATE OR REPLACE / DROP TRIGGER IF EXISTS.
-- Depends on 20261120000008 (enum value salary_advance) being applied first:
-- a new enum value cannot be used in the transaction that adds it.
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- 1. Link column
-- ----------------------------------------------------------------------------
ALTER TABLE public.staff_advances
  ADD COLUMN IF NOT EXISTS expense_id uuid UNIQUE
    REFERENCES public.expenses(id) ON DELETE RESTRICT;

COMMENT ON COLUMN public.staff_advances.expense_id IS
  'C3.8 custody-ledger outflow created when the advance was granted. Set by trigger, cleared only by cancel_staff_advance.';

-- ----------------------------------------------------------------------------
-- 2. Insert/update guard + expense creation
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.trg_fn_c3_staff_advance_expense()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_acc public.financial_accounts%ROWTYPE;
  v_name text;
  v_actor uuid;
  v_expense uuid;
BEGIN
  IF TG_OP = 'UPDATE' THEN
    IF NEW.amount <> OLD.amount
       OR NEW.currency <> OLD.currency
       OR NEW.account_id <> OLD.account_id
       OR NEW.advanced_at <> OLD.advanced_at THEN
      RAISE EXCEPTION 'لا يمكن تعديل مبلغ السلفة أو عملتها أو حسابها أو تاريخها بعد تسجيل الصرف؛ ألغِها وسجّل سلفة جديدة';
    END IF;

    IF COALESCE(current_setting('app.c3_advance_internal', true), '') <> 'on' THEN
      IF NEW.expense_id IS DISTINCT FROM OLD.expense_id THEN
        RAISE EXCEPTION 'ربط السلفة بالمصروف يُدار تلقائياً ولا يُعدّل يدوياً';
      END IF;
      IF NEW.status = 'cancelled' AND OLD.status IS DISTINCT FROM 'cancelled' THEN
        RAISE EXCEPTION 'استخدم public.cancel_staff_advance لإلغاء السلفة وإعادة المبلغ إلى الخزينة';
      END IF;
    END IF;

    RETURN NEW;
  END IF;

  IF NEW.status <> 'open' THEN
    RAISE EXCEPTION 'تُسجَّل السلفة بحالة open فقط؛ الإلغاء يتم عبر cancel_staff_advance';
  END IF;
  IF NEW.payroll_line_id IS NOT NULL THEN
    RAISE EXCEPTION 'لا يمكن ربط سلفة جديدة ببند رواتب مسبقاً';
  END IF;
  IF NEW.expense_id IS NOT NULL THEN
    RAISE EXCEPTION 'expense_id يُولَّد تلقائياً عند تسجيل السلفة';
  END IF;
  IF NEW.amount > 99999999.99 THEN
    RAISE EXCEPTION 'مبلغ السلفة يتجاوز الحد الأعلى المسموح للمصروفات (99,999,999.99)';
  END IF;

  SELECT * INTO v_acc FROM public.financial_accounts a WHERE a.id = NEW.account_id;
  IF NOT FOUND OR NOT v_acc.is_active THEN
    RAISE EXCEPTION 'الحساب المالي غير موجود أو غير مفعّل: %', NEW.account_id;
  END IF;
  IF v_acc.currency <> NEW.currency THEN
    RAISE EXCEPTION 'عملة الحساب (%) لا تطابق عملة السلفة (%)', v_acc.currency, NEW.currency;
  END IF;

  v_actor := COALESCE(NEW.created_by, auth.uid());
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'تعذّر تحديد منشئ السلفة (created_by) لتسجيل صرف الخزينة';
  END IF;

  SELECT full_name INTO v_name FROM public.users u WHERE u.id = NEW.user_id;

  INSERT INTO public.expenses
    (category, amount, description, expense_date, performed_by, currency, account_id)
  VALUES
    ('salary_advance', NEW.amount,
     'سلفة راتب - ' || COALESCE(v_name, NEW.user_id::text),
     NEW.advanced_at, v_actor, NEW.currency, NEW.account_id)
  RETURNING id INTO v_expense;

  NEW.expense_id := v_expense;
  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.trg_fn_c3_staff_advance_expense() IS
  'C3.8 writes the salary_advance expense for a new staff advance and freezes the money fields afterwards.';

DROP TRIGGER IF EXISTS trg_c3_staff_advance_expense ON public.staff_advances;
CREATE TRIGGER trg_c3_staff_advance_expense
  BEFORE INSERT OR UPDATE ON public.staff_advances
  FOR EACH ROW EXECUTE FUNCTION public.trg_fn_c3_staff_advance_expense();

-- ----------------------------------------------------------------------------
-- 3. Cancel RPC — reverses the outflow in the same transaction
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.cancel_staff_advance(
  p_advance_id uuid
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_adv public.staff_advances%ROWTYPE;
  v_expense uuid;
BEGIN
  PERFORM public.fn_c3_require_admin();

  SELECT * INTO v_adv FROM public.staff_advances
  WHERE id = p_advance_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'السلفة غير موجودة: %', p_advance_id;
  END IF;
  IF v_adv.status <> 'open' THEN
    RAISE EXCEPTION 'لا يمكن إلغاء سلفة حالتها % (المسموح: open فقط)', v_adv.status;
  END IF;
  IF v_adv.payroll_line_id IS NOT NULL THEN
    RAISE EXCEPTION 'السلفة مرتبطة بمسودة مسير رواتب؛ أعد توليد المسير لتحرير الارتباط ثم أعد المحاولة';
  END IF;

  v_expense := v_adv.expense_id;
  PERFORM set_config('app.c3_advance_internal', 'on', true);

  UPDATE public.staff_advances
  SET status = 'cancelled', expense_id = NULL
  WHERE id = p_advance_id;

  IF v_expense IS NOT NULL THEN
    DELETE FROM public.expenses WHERE id = v_expense;
  END IF;
END;
$$;

COMMENT ON FUNCTION public.cancel_staff_advance(uuid) IS
  'C3.8 cancels an open advance and deletes its expense, so the C2 trigger removes the custody outflow.';

-- ----------------------------------------------------------------------------
-- 4. Backfill open/deducted advances that never produced an expense
-- ----------------------------------------------------------------------------
DO $$
DECLARE
  v_bad   bigint;
  v_count integer := 0;
  v_expense uuid;
  r record;
BEGIN
  SELECT count(*) INTO v_bad
  FROM public.staff_advances a
  WHERE a.expense_id IS NULL
    AND a.status IN ('open', 'deducted')
    AND (
      a.created_by IS NULL
      OR a.amount > 99999999.99
      OR NOT EXISTS (
        SELECT 1 FROM public.financial_accounts fa
        WHERE fa.id = a.account_id
          AND fa.is_active
          AND fa.currency = a.currency
      )
    );
  IF v_bad > 0 THEN
    RAISE EXCEPTION
      'ترحيل C3.8 متوقف: % سلفة بلا created_by أو بحساب/عملة غير صالحة أو مبلغ يتجاوز حد المصروفات؛ صحّحها ثم أعد التنفيذ',
      v_bad;
  END IF;

  PERFORM set_config('app.c3_advance_internal', 'on', true);

  FOR r IN
    SELECT a.id, a.user_id, a.amount, a.currency, a.advanced_at,
           a.account_id, a.created_by, u.full_name
    FROM public.staff_advances a
    JOIN public.users u ON u.id = a.user_id
    WHERE a.expense_id IS NULL
      AND a.status IN ('open', 'deducted')
    ORDER BY a.advanced_at, a.id
  LOOP
    INSERT INTO public.expenses
      (category, amount, description, expense_date, performed_by, currency, account_id)
    VALUES
      ('salary_advance', r.amount,
       'سلفة راتب (ترحيل C3.8) - ' || r.full_name,
       r.advanced_at, r.created_by, r.currency, r.account_id)
    RETURNING id INTO v_expense;

    UPDATE public.staff_advances
    SET expense_id = v_expense
    WHERE id = r.id;

    v_count := v_count + 1;
  END LOOP;

  PERFORM set_config('app.c3_advance_internal', 'off', true);
  RAISE NOTICE 'C3.8 backfill: % advance(s) linked to a custody expense', v_count;
END;
$$;

-- ----------------------------------------------------------------------------
-- 5. ACL
-- ----------------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.trg_fn_c3_staff_advance_expense() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.cancel_staff_advance(uuid) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.trg_fn_c3_staff_advance_expense() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.cancel_staff_advance(uuid) TO authenticated, service_role;

COMMIT;
