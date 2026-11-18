-- ============================================================================
-- Phase C2.5 — RLS + balances view
-- ============================================================================
-- Access model (matches the plan's security rule and the existing expenses
-- precedent, baseline:8005):
--   * financial_accounts  -> admin only (ALL)
--   * account_transactions -> admin only (ALL)
--   * reception/trainer/trainee get no policy => no rows, and no write path.
-- Triggers and the transfer RPC write as SECURITY DEFINER, so reception can
-- still register a payment without ever seeing a custody account.
--
-- account_balances_v is security_invoker: RLS applies to the caller, so a
-- non-admin gets an empty result even though the view itself is readable.
--
-- Rebuild-safe.
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- 1. Policies
-- ----------------------------------------------------------------------------
DROP POLICY IF EXISTS admin_all ON public.financial_accounts;
CREATE POLICY admin_all ON public.financial_accounts
  FOR ALL TO authenticated
  USING (public.c1_is_admin())
  WITH CHECK (public.c1_is_admin());

DROP POLICY IF EXISTS admin_select ON public.account_transactions;
CREATE POLICY admin_select ON public.account_transactions
  FOR SELECT TO authenticated
  USING (public.c1_is_admin());
-- No INSERT/UPDATE/DELETE policy: staff never write the ledger directly.
-- Writes go through the SECURITY DEFINER triggers (04) and transfer RPC (06).

-- ----------------------------------------------------------------------------
-- 2. Balances view — derived, never stored
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW public.account_balances_v
WITH (security_invoker = 'true') AS
SELECT
  a.id AS account_id,
  a.name_ar,
  a.name_en,
  a.account_type,
  a.currency,
  a.is_active,
  COALESCE(SUM(CASE WHEN t.direction = 'inflow' THEN t.amount ELSE -t.amount END), 0)::numeric(12,2) AS balance,
  COALESCE(SUM(CASE WHEN t.direction = 'inflow' THEN t.amount ELSE 0 END), 0)::numeric(12,2) AS total_inflow,
  COALESCE(SUM(CASE WHEN t.direction = 'outflow' THEN t.amount ELSE 0 END), 0)::numeric(12,2) AS total_outflow,
  COUNT(t.id) AS transaction_count,
  MAX(t.occurred_at) AS last_transaction_at
FROM public.financial_accounts a
LEFT JOIN public.account_transactions t ON t.account_id = a.id
GROUP BY a.id, a.name_ar, a.name_en, a.account_type, a.currency, a.is_active;

COMMENT ON VIEW public.account_balances_v IS
  'C2 derived balances per custody account. security_invoker: non-admin callers see nothing because of table RLS.';

GRANT SELECT ON public.account_balances_v TO authenticated;
GRANT ALL ON public.account_balances_v TO service_role;

COMMIT;
