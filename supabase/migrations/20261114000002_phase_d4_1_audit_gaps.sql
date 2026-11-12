-- ============================================================================
-- Taj Dentics - Phase D4.1.1: Audit Log Security Gaps Closure (F1, F2, F2b)
-- ============================================================================
-- Migration: 20261114000002_phase_d4_1_audit_gaps.sql
--
-- Fixes:
-- 1. F1: Secure search_path = public, pg_temp on audit_trigger_func()
-- 2. F2: Expand triggers on payment_refunds & fee_adjustments to include UPDATE
-- 3. F2b: Attach audit triggers to installment_schedule & payment_allocations
-- ============================================================================

-- 1. Fix search_path to explicitly include pg_temp
ALTER FUNCTION public.audit_trigger_func() SET search_path = public, pg_temp;

-- 2. Expand payment_refunds audit trigger to cover UPDATE
DROP TRIGGER IF EXISTS trg_z_audit_payment_refunds ON public.payment_refunds;
CREATE TRIGGER trg_z_audit_payment_refunds
  AFTER INSERT OR UPDATE OR DELETE
  ON public.payment_refunds
  FOR EACH ROW
  EXECUTE FUNCTION public.audit_trigger_func();

-- 3. Expand fee_adjustments audit trigger to cover UPDATE
DROP TRIGGER IF EXISTS trg_z_audit_fee_adjustments ON public.fee_adjustments;
CREATE TRIGGER trg_z_audit_fee_adjustments
  AFTER INSERT OR UPDATE OR DELETE
  ON public.fee_adjustments
  FOR EACH ROW
  EXECUTE FUNCTION public.audit_trigger_func();

-- 4. Attach audit triggers to installment_schedule (CRUD coverage)
DROP TRIGGER IF EXISTS trg_z_audit_installment_schedule ON public.installment_schedule;
CREATE TRIGGER trg_z_audit_installment_schedule
  AFTER INSERT OR UPDATE OR DELETE
  ON public.installment_schedule
  FOR EACH ROW
  EXECUTE FUNCTION public.audit_trigger_func();

-- 5. Attach audit triggers to payment_allocations (CRUD coverage)
DROP TRIGGER IF EXISTS trg_z_audit_payment_allocations ON public.payment_allocations;
CREATE TRIGGER trg_z_audit_payment_allocations
  AFTER INSERT OR UPDATE OR DELETE
  ON public.payment_allocations
  FOR EACH ROW
  EXECUTE FUNCTION public.audit_trigger_func();

