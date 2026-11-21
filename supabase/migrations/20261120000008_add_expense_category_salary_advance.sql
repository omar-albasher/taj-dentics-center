-- ============================================================================
-- Phase C3.8 — Expense category for staff salary advances
-- ============================================================================
-- Granting an advance is a cash outflow at that moment (staff_advances comment),
-- so it must be written as an expense row for the C2 trigger to move the
-- custody ledger. A dedicated category keeps advances distinguishable from the
-- end-of-month salary payout in expense reports.
--
-- PostgreSQL 17 allows ALTER TYPE ... ADD VALUE inside a transaction, but the
-- new value must not be used in the same transaction. This file is therefore
-- kept as a single statement with no BEGIN/COMMIT.
-- ============================================================================

ALTER TYPE public.expense_category ADD VALUE IF NOT EXISTS 'salary_advance';
