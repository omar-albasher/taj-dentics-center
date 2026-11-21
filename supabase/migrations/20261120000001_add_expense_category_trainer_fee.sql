-- ============================================================================
-- Phase C3.0 — Expense category for trainer fee payouts
-- ============================================================================
-- Trainer dues are paid out as expense rows (category = trainer_fee) so the
-- C2 expense trigger writes the custody ledger outflow automatically and the
-- payout appears in existing expense reports without a second entry.
--
-- PostgreSQL 17 allows ALTER TYPE ... ADD VALUE inside a transaction, but the
-- new value must not be used in the same transaction. This file is therefore
-- kept as a single statement with no BEGIN/COMMIT.
-- ============================================================================

ALTER TYPE public.expense_category ADD VALUE IF NOT EXISTS 'trainer_fee';
