-- ============================================================================
-- Phase C2.6 — Account Ledger View
-- ============================================================================
-- Unified view for the custody transaction ledger. Joins account_transactions
-- with financial_accounts (name, type, currency) and users (performed_by_name)
-- to avoid round-tripping or client-side joins.
--
-- Security: security_invoker = 'true' ensures RLS from underlying tables
-- (admin_select on account_transactions and financial_accounts) is respected.
-- Non-admin callers see zero rows.
-- ============================================================================

BEGIN;

CREATE OR REPLACE VIEW public.account_ledger_v
WITH (security_invoker = 'true') AS
SELECT
  t.id,
  t.account_id,
  a.name_ar AS account_name_ar,
  a.name_en AS account_name_en,
  a.account_type,
  a.currency,
  t.direction,
  t.amount,
  t.source_type,
  t.source_id,
  t.transfer_group,
  t.derivation,
  t.occurred_at,
  t.notes,
  t.created_by,
  u.full_name AS performed_by_name,
  t.created_at
FROM public.account_transactions t
JOIN public.financial_accounts a ON a.id = t.account_id
LEFT JOIN public.users u ON u.id = t.created_by;

COMMENT ON VIEW public.account_ledger_v IS
  'C2 custody ledger display view with account metadata and creator names. security_invoker applies admin-only RLS.';

GRANT SELECT ON public.account_ledger_v TO authenticated;
GRANT ALL ON public.account_ledger_v TO service_role;

COMMIT;
