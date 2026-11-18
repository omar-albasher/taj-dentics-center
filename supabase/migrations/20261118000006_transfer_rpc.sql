-- ============================================================================
-- Phase C2.6 — Internal transfer RPC
-- ============================================================================
-- The only way to move money between custody accounts (e.g. withdrawing a
-- Sham Cash balance into the cash box). Same-currency only: C2 has no FX rate
-- policy, so a cross-currency call fails loudly instead of inventing a rate.
--
-- Writes exactly two ledger rows sharing one transfer_group, inside the
-- caller's transaction: either both exist or neither does.
--
-- Admin-only, enforced inside the function AND backed by the admin-only RLS on
-- account_transactions.
--
-- Rebuild-safe.
-- ============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.transfer_between_accounts(
  p_from_account_id uuid,
  p_to_account_id uuid,
  p_amount numeric,
  p_notes text DEFAULT NULL
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_from public.financial_accounts%ROWTYPE;
  v_to public.financial_accounts%ROWTYPE;
  v_group uuid := gen_random_uuid();
BEGIN
  IF NOT public.c1_is_admin() THEN
    RAISE EXCEPTION 'التحويل الداخلي متاح لمدير المركز فقط';
  END IF;

  IF p_from_account_id = p_to_account_id THEN
    RAISE EXCEPTION 'لا يمكن التحويل من الحساب إلى نفسه';
  END IF;

  IF p_amount IS NULL OR p_amount <= 0 THEN
    RAISE EXCEPTION 'مبلغ التحويل يجب أن يكون أكبر من صفر';
  END IF;

  SELECT * INTO v_from FROM public.financial_accounts a
   WHERE a.id = p_from_account_id AND a.is_active;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'حساب المصدر غير موجود أو غير مفعّل: %', p_from_account_id;
  END IF;

  SELECT * INTO v_to FROM public.financial_accounts a
   WHERE a.id = p_to_account_id AND a.is_active;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'حساب الوجهة غير موجود أو غير مفعّل: %', p_to_account_id;
  END IF;

  IF v_from.currency <> v_to.currency THEN
    RAISE EXCEPTION 'التحويل بين عملتين مختلفتين (%) و (%) غير مدعوم في المرحلة C2',
      v_from.currency, v_to.currency;
  END IF;

  INSERT INTO public.account_transactions (
    account_id, direction, amount, source_type, transfer_group,
    derivation, occurred_at, notes, created_by
  ) VALUES
    (v_from.id, 'outflow', p_amount, 'transfer', v_group,
     'manual', now(), p_notes, auth.uid()),
    (v_to.id, 'inflow', p_amount, 'transfer', v_group,
     'manual', now(), p_notes, auth.uid());

  RETURN v_group;
END;
$$;

COMMENT ON FUNCTION public.transfer_between_accounts(uuid, uuid, numeric, text) IS
  'C2 internal transfer between custody accounts (same currency only). Admin-only; returns the transfer_group uuid.';

REVOKE ALL ON FUNCTION public.transfer_between_accounts(uuid, uuid, numeric, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.transfer_between_accounts(uuid, uuid, numeric, text) TO authenticated, service_role;

COMMIT;
