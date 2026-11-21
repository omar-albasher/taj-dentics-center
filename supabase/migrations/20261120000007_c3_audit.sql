-- ============================================================================
-- Phase C3.7 — Audit triggers for the compensation ledger
-- ============================================================================
-- Compensation is payroll data: every insert/update/delete on the C3 tables
-- and on the custody ledger must leave an audit_log trail (who changed what,
-- before/after). This is the compensation for the management decision to waive
-- strict append-only on C3 (2026-11-20): updates stay possible, but never
-- silent.
--
-- Ten tables reuse the canonical public.audit_trigger_func() (baseline:132).
-- cohort_trainer_rate_snapshots has no `id` column (PK is cohort_id), which
-- audit_trigger_func requires, so it gets a dedicated trigger that records the
-- cohort_id as the audited record.
--
-- Rebuild-safe: triggers dropped and recreated.
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- 1. Dedicated audit function for the snapshot table (PK = cohort_id)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_c3_audit_cohort_rate_snapshot() RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_role text;
  v_old jsonb := NULL;
  v_new jsonb := NULL;
  v_record uuid;
BEGIN
  IF TG_OP = 'DELETE' THEN
    v_old := to_jsonb(OLD);
    v_record := OLD.cohort_id;
  ELSIF TG_OP = 'INSERT' THEN
    v_new := to_jsonb(NEW);
    v_record := NEW.cohort_id;
  ELSE
    v_old := to_jsonb(OLD);
    v_new := to_jsonb(NEW);
    v_record := NEW.cohort_id;
  END IF;

  IF v_actor IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.users WHERE id = v_actor) THEN
    v_actor := NULL;
  END IF;
  IF v_actor IS NOT NULL THEN
    SELECT role::text INTO v_role FROM public.users WHERE id = v_actor;
  END IF;

  INSERT INTO public.audit_log
    (table_name, operation, record_id, old_data, new_data,
     performed_by, performed_at, actor_source, actor_role)
  VALUES
    (TG_TABLE_NAME, TG_OP, v_record, v_old, v_new,
     v_actor, now(),
     CASE WHEN v_actor IS NULL THEN 'system' ELSE 'jwt' END, v_role);

  RETURN NULL;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_c3_audit_cohort_rate_snapshot() FROM PUBLIC, anon;

DROP TRIGGER IF EXISTS trg_z_audit_cohort_trainer_rate_snapshots
  ON public.cohort_trainer_rate_snapshots;
CREATE TRIGGER trg_z_audit_cohort_trainer_rate_snapshots
  AFTER INSERT OR UPDATE OR DELETE ON public.cohort_trainer_rate_snapshots
  FOR EACH ROW EXECUTE FUNCTION public.fn_c3_audit_cohort_rate_snapshot();

-- ----------------------------------------------------------------------------
-- 2. Canonical audit triggers — compensation inputs
-- ----------------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_z_audit_trainer_compensation_agreements
  ON public.trainer_compensation_agreements;
CREATE TRIGGER trg_z_audit_trainer_compensation_agreements
  AFTER INSERT OR UPDATE OR DELETE ON public.trainer_compensation_agreements
  FOR EACH ROW EXECUTE FUNCTION public.audit_trigger_func();

DROP TRIGGER IF EXISTS trg_z_audit_staff_compensation
  ON public.staff_compensation;
CREATE TRIGGER trg_z_audit_staff_compensation
  AFTER INSERT OR UPDATE OR DELETE ON public.staff_compensation
  FOR EACH ROW EXECUTE FUNCTION public.audit_trigger_func();

DROP TRIGGER IF EXISTS trg_z_audit_staff_advances
  ON public.staff_advances;
CREATE TRIGGER trg_z_audit_staff_advances
  AFTER INSERT OR UPDATE OR DELETE ON public.staff_advances
  FOR EACH ROW EXECUTE FUNCTION public.audit_trigger_func();

DROP TRIGGER IF EXISTS trg_z_audit_staff_bonuses
  ON public.staff_bonuses;
CREATE TRIGGER trg_z_audit_staff_bonuses
  AFTER INSERT OR UPDATE OR DELETE ON public.staff_bonuses
  FOR EACH ROW EXECUTE FUNCTION public.audit_trigger_func();

DROP TRIGGER IF EXISTS trg_z_audit_staff_referrals
  ON public.staff_referrals;
CREATE TRIGGER trg_z_audit_staff_referrals
  AFTER INSERT OR UPDATE OR DELETE ON public.staff_referrals
  FOR EACH ROW EXECUTE FUNCTION public.audit_trigger_func();

-- ----------------------------------------------------------------------------
-- 3. Canonical audit triggers — dues, payouts, payroll
-- ----------------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_z_audit_trainer_dues
  ON public.trainer_dues;
CREATE TRIGGER trg_z_audit_trainer_dues
  AFTER INSERT OR UPDATE OR DELETE ON public.trainer_dues
  FOR EACH ROW EXECUTE FUNCTION public.audit_trigger_func();

DROP TRIGGER IF EXISTS trg_z_audit_trainer_payments
  ON public.trainer_payments;
CREATE TRIGGER trg_z_audit_trainer_payments
  AFTER INSERT OR UPDATE OR DELETE ON public.trainer_payments
  FOR EACH ROW EXECUTE FUNCTION public.audit_trigger_func();

DROP TRIGGER IF EXISTS trg_z_audit_payroll_runs
  ON public.payroll_runs;
CREATE TRIGGER trg_z_audit_payroll_runs
  AFTER INSERT OR UPDATE OR DELETE ON public.payroll_runs
  FOR EACH ROW EXECUTE FUNCTION public.audit_trigger_func();

DROP TRIGGER IF EXISTS trg_z_audit_payroll_lines
  ON public.payroll_lines;
CREATE TRIGGER trg_z_audit_payroll_lines
  AFTER INSERT OR UPDATE OR DELETE ON public.payroll_lines
  FOR EACH ROW EXECUTE FUNCTION public.audit_trigger_func();

-- ----------------------------------------------------------------------------
-- 4. Custody ledger audit (deferred in C2, closed here)
-- ----------------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_z_audit_account_transactions
  ON public.account_transactions;
CREATE TRIGGER trg_z_audit_account_transactions
  AFTER INSERT OR UPDATE OR DELETE ON public.account_transactions
  FOR EACH ROW EXECUTE FUNCTION public.audit_trigger_func();

COMMIT;
