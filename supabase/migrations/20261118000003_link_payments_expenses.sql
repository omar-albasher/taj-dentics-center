-- ============================================================================
-- Phase C2.3 — Link payments and expenses to custody accounts
-- ============================================================================
-- Nullable on purpose:
--   * existing rows are backfilled in a separate, reviewable step (07);
--   * older app builds keep inserting without account_id until the C2 screens
--     ship — the trigger resolves the account by rule and records the
--     derivation, so nothing breaks and nothing is silently mislabelled.
--
-- payments.currency exists (baseline:4851) and expenses.currency exists
-- (baseline:5319); the trigger enforces account.currency = row.currency.
--
-- Rebuild-safe.
-- ============================================================================

BEGIN;

ALTER TABLE public.payments
  ADD COLUMN IF NOT EXISTS account_id uuid
  REFERENCES public.financial_accounts(id) ON DELETE RESTRICT;

ALTER TABLE public.expenses
  ADD COLUMN IF NOT EXISTS account_id uuid
  REFERENCES public.financial_accounts(id) ON DELETE RESTRICT;

COMMENT ON COLUMN public.payments.account_id IS
  'C2 custody account receiving this payment. NULL = resolve by (method, currency) rule and record derivation.';
COMMENT ON COLUMN public.expenses.account_id IS
  'C2 custody account paying this expense. NULL = default to cash box of the expense currency.';

CREATE INDEX IF NOT EXISTS payments_account_id_idx
  ON public.payments (account_id)
  WHERE account_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS expenses_account_id_idx
  ON public.expenses (account_id)
  WHERE account_id IS NOT NULL;

COMMIT;
