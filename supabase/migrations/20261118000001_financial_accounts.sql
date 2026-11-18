-- ============================================================================
-- Phase C2.1 — Financial accounts (chart of custody accounts)
-- ============================================================================
-- One row per real custody account. No double-entry here: C2 models where the
-- money physically sits (cash box / bank / wallet), not revenue vs expense.
--
-- Approved structure (2026-11-18):
--   1. صندوق المركز        cash    SYP
--   2. صندوق المركز        cash    USD
--   3. الحساب البنكي       bank    SYP
--   4. الحساب البنكي       bank    USD
--   5. محفظة Sham Cash     wallet  SYP
--   6. محفظة هرم           wallet  SYP
--
-- Why wallets are separate: Sham Cash / Hawala balances are held by a payment
-- intermediary, not inside the cash box. Merging them would break the physical
-- cash count. Moving money out of a wallet is a transfer_between_accounts()
-- call (see 20261118000006).
--
-- Rebuild-safe: enum, table and seed are idempotent.
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- 1. Enum + table
-- ----------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'account_type' AND typnamespace = 'public'::regnamespace) THEN
    CREATE TYPE public.account_type AS ENUM ('cash', 'bank', 'wallet');
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS public.financial_accounts (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name_ar text NOT NULL,
    name_en text,
    account_type public.account_type NOT NULL,
    currency public.currency_type NOT NULL,
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    CONSTRAINT financial_accounts_name_currency_key UNIQUE (name_ar, currency)
);

COMMENT ON TABLE public.financial_accounts IS
  'C2 custody accounts: cash boxes, bank accounts and payment wallets. Balances are derived from account_transactions, never stored.';
COMMENT ON COLUMN public.financial_accounts.account_type IS
  'cash = physical box, bank = bank account, wallet = third-party payment wallet (Sham Cash / Hawala).';

ALTER TABLE public.financial_accounts ENABLE ROW LEVEL SECURITY;

-- RLS policies live in 20261118000005_account_rls.sql.
GRANT SELECT, INSERT, REFERENCES, DELETE, TRIGGER, MAINTAIN, UPDATE
  ON TABLE public.financial_accounts TO authenticated;
GRANT ALL ON TABLE public.financial_accounts TO service_role;

-- ----------------------------------------------------------------------------
-- 2. Seed — idempotent; adding a future account is one row, no migration
-- ----------------------------------------------------------------------------
INSERT INTO public.financial_accounts (name_ar, name_en, account_type, currency)
VALUES
  ('صندوق المركز',   'Main Cash Box',      'cash',   'SYP'),
  ('صندوق المركز',   'Main Cash Box',      'cash',   'USD'),
  ('الحساب البنكي',  'Bank Account',       'bank',   'SYP'),
  ('الحساب البنكي',  'Bank Account',       'bank',   'USD'),
  ('محفظة Sham Cash','Sham Cash Wallet',   'wallet', 'SYP'),
  ('محفظة هرم',      'Hawala Wallet (Haram)', 'wallet', 'SYP')
ON CONFLICT (name_ar, currency) DO NOTHING;

COMMIT;
