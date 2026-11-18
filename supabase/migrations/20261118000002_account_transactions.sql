-- ============================================================================
-- Phase C2.2 — Account transactions (custody ledger)
-- ============================================================================
-- Append-only movement log per account. Written by:
--   * triggers on payments / expenses / payment_refunds (20261118000004)
--   * transfer_between_accounts() RPC (20261118000006)
--   * backfill (20261118000007, pending G-C2.2/G-C2.3)
--
-- Balance is always SUM(inflow) - SUM(outflow). No stored balance column, so a
-- balance can never drift from its transactions.
--
-- derivation records HOW the account was chosen, so nothing is silently
-- assigned:
--   manual            -> account_id was supplied by the caller
--   auto_method       -> resolved from (payment_method, currency) rule
--   auto_expense_cash -> expense had no account; defaulted to cash box of its
--                        currency (historical expenses carry no method)
--   backfill          -> generated during the C2 backfill run
--   admin_attested    -> assigned after explicit admin confirmation
--
-- Rebuild-safe.
-- ============================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS public.account_transactions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    account_id uuid NOT NULL REFERENCES public.financial_accounts(id) ON DELETE RESTRICT,
    direction text NOT NULL CHECK (direction IN ('inflow', 'outflow')),
    amount numeric(12,2) NOT NULL CHECK (amount > 0),
    source_type text NOT NULL CHECK (source_type IN ('payment', 'expense', 'refund', 'transfer', 'adjustment')),
    source_id uuid,
    transfer_group uuid,
    derivation text NOT NULL DEFAULT 'manual'
      CHECK (derivation IN ('manual', 'auto_method', 'auto_expense_cash', 'backfill', 'admin_attested')),
    occurred_at timestamp with time zone NOT NULL DEFAULT now(),
    notes text,
    created_by uuid,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    CONSTRAINT account_transactions_source_ck CHECK (
      (source_type IN ('payment', 'expense', 'refund') AND source_id IS NOT NULL)
      OR (source_type = 'transfer' AND transfer_group IS NOT NULL AND source_id IS NULL)
      OR (source_type = 'adjustment' AND source_id IS NULL)
    )
);

COMMENT ON TABLE public.account_transactions IS
  'C2 custody ledger. One row per money movement per account; balance = sum(inflow) - sum(outflow).';
COMMENT ON COLUMN public.account_transactions.transfer_group IS
  'Links the outflow/inflow pair of a single internal transfer.';
COMMENT ON COLUMN public.account_transactions.derivation IS
  'How account_id was chosen (manual/auto_method/auto_expense_cash/backfill/admin_attested).';

-- Idempotency: a payment/expense/refund can own at most one ledger row.
CREATE UNIQUE INDEX IF NOT EXISTS account_transactions_source_uidx
  ON public.account_transactions (source_type, source_id)
  WHERE source_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS account_transactions_account_time_idx
  ON public.account_transactions (account_id, occurred_at DESC);

CREATE INDEX IF NOT EXISTS account_transactions_time_idx
  ON public.account_transactions (occurred_at DESC);

CREATE INDEX IF NOT EXISTS account_transactions_transfer_group_idx
  ON public.account_transactions (transfer_group)
  WHERE transfer_group IS NOT NULL;

ALTER TABLE public.account_transactions ENABLE ROW LEVEL SECURITY;

-- RLS policies live in 20261118000005_account_rls.sql.
-- Write access for staff is intentionally NOT granted: ledger rows are created
-- only by the SECURITY DEFINER triggers (04) and the transfer RPC (06), so no
-- API caller can forge a one-sided movement. service_role retains full access
-- for maintenance and the auditable adjustment entry.
GRANT SELECT ON TABLE public.account_transactions TO authenticated;
GRANT ALL ON TABLE public.account_transactions TO service_role;

COMMIT;
