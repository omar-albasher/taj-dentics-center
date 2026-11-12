-- ============================================================================
-- Taj Dentics - Phase D4.1: Audit Log & Actor Hardening Migration
-- ============================================================================
-- Migration: 20261114000001_phase_d4_audit_actor_hardening.sql
--
-- Goals:
-- 1. Add provenance columns (actor_source, actor_role) to public.audit_log.
-- 2. Mark historical null-actor records as 'legacy'.
-- 3. Create high-performance indexes on public.audit_log for audit_screen.
-- 4. Replace public.audit_trigger_func() with secure, search_path protected,
--    provenance-aware logic (jwt -> rpc_context -> table_column -> system).
-- 5. Revoke execute privileges on audit_trigger_func from anon/public.
-- 6. Attach audit triggers (trg_z_audit_*) to financial tables missing audit coverage:
--    - payment_refunds
--    - fee_adjustments
--    - enrollment_withdrawals
--    - course_materials
-- ============================================================================

-- 1. Extend audit_log with provenance tracking
ALTER TABLE public.audit_log 
  ADD COLUMN IF NOT EXISTS actor_source text,
  ADD COLUMN IF NOT EXISTS actor_role text;

-- Mark historical unassigned records as legacy
UPDATE public.audit_log
SET actor_source = 'legacy'
WHERE actor_source IS NULL AND performed_by IS NULL;

-- 2. Performance Indexes for Audit Log UI
CREATE INDEX IF NOT EXISTS idx_audit_log_performed_at 
  ON public.audit_log (performed_at DESC);

CREATE INDEX IF NOT EXISTS idx_audit_log_table_name 
  ON public.audit_log (table_name);

CREATE INDEX IF NOT EXISTS idx_audit_log_record_id 
  ON public.audit_log (record_id);

CREATE INDEX IF NOT EXISTS idx_audit_log_performed_by 
  ON public.audit_log (performed_by) 
  WHERE performed_by IS NOT NULL;

-- 3. Hardened, Search-Path Safe, Provenance-Aware Audit Trigger Function
CREATE OR REPLACE FUNCTION public.audit_trigger_func()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_actor_id uuid;
  v_actor_source text;
  v_actor_role text;
  v_record_id uuid;
  v_old_data jsonb := NULL;
  v_new_data jsonb := NULL;
  v_app_actor text;
BEGIN
  -- 3.1 Extract Record ID and serialized JSON payloads
  IF TG_OP = 'DELETE' THEN
    v_record_id := OLD.id;
    v_old_data := to_jsonb(OLD);
  ELSIF TG_OP = 'INSERT' THEN
    v_record_id := NEW.id;
    v_new_data := to_jsonb(NEW);
  ELSIF TG_OP = 'UPDATE' THEN
    v_record_id := NEW.id;
    v_old_data := to_jsonb(OLD);
    v_new_data := to_jsonb(NEW);
  END IF;

  -- 3.2 Determine Actor Identity with Strict Provenance Hierarchy
  -- Priority A: Direct Authenticated JWT Context
  v_actor_id := auth.uid();
  IF v_actor_id IS NOT NULL THEN
    v_actor_source := 'jwt';
  ELSE
    -- Priority B: Trusted Session Setting from SECURITY DEFINER RPC
    v_app_actor := current_setting('app.actor_id', true);
    IF v_app_actor IS NOT NULL AND v_app_actor <> '' THEN
      BEGIN
        v_actor_id := v_app_actor::uuid;
        v_actor_source := 'rpc_context';
      EXCEPTION WHEN OTHERS THEN
        v_actor_id := NULL;
      END;
    END IF;
  END IF;

  -- Priority C: Table-level actor column fallback (Client/RPC payload)
  IF v_actor_id IS NULL AND TG_OP <> 'DELETE' THEN
    IF TG_TABLE_NAME IN ('payments', 'expenses') THEN
      v_actor_id := NEW.performed_by;
      IF v_actor_id IS NOT NULL THEN
        v_actor_source := 'table_column';
      END IF;
    ELSIF TG_TABLE_NAME IN ('payment_refunds', 'fee_adjustments', 'enrollment_withdrawals', 'enrollments') THEN
      v_actor_id := NEW.created_by;
      IF v_actor_id IS NOT NULL THEN
        v_actor_source := 'table_column';
      END IF;
    END IF;
  END IF;

  -- Verify actor exists in public.users to respect FK constraint audit_log_performed_by_fkey
  IF v_actor_id IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM public.users WHERE id = v_actor_id) THEN
      v_actor_id := NULL;
      v_actor_source := 'system';
    END IF;
  ELSE
    v_actor_source := 'system';
  END IF;

  -- 3.3 Fetch Actor Role if actor is resolved
  IF v_actor_id IS NOT NULL THEN
    SELECT role::text INTO v_actor_role
    FROM public.users
    WHERE id = v_actor_id;
  END IF;

  -- 3.4 Insert Immutable Audit Record
  INSERT INTO public.audit_log (
    table_name,
    operation,
    record_id,
    old_data,
    new_data,
    performed_by,
    performed_at,
    actor_source,
    actor_role
  ) VALUES (
    TG_TABLE_NAME,
    TG_OP,
    v_record_id,
    v_old_data,
    v_new_data,
    v_actor_id,
    now(),
    v_actor_source,
    v_actor_role
  );

  RETURN COALESCE(NEW, OLD);
END;
$function$;

-- 4. Permissions Hardening on Audit Trigger Function
REVOKE ALL ON FUNCTION public.audit_trigger_func() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.audit_trigger_func() TO authenticated, service_role;

-- 5. Attach Audit Triggers to Financial & Operational Tables
-- Naming with 'trg_z_audit_' ensures execution AFTER c1 guards and validation triggers

-- 5.1 Payment Refunds
DROP TRIGGER IF EXISTS trg_z_audit_payment_refunds ON public.payment_refunds;
CREATE TRIGGER trg_z_audit_payment_refunds
  AFTER INSERT OR DELETE
  ON public.payment_refunds
  FOR EACH ROW
  EXECUTE FUNCTION public.audit_trigger_func();

-- 5.2 Fee Adjustments
DROP TRIGGER IF EXISTS trg_z_audit_fee_adjustments ON public.fee_adjustments;
CREATE TRIGGER trg_z_audit_fee_adjustments
  AFTER INSERT OR DELETE
  ON public.fee_adjustments
  FOR EACH ROW
  EXECUTE FUNCTION public.audit_trigger_func();

-- 5.3 Enrollment Withdrawals
DROP TRIGGER IF EXISTS trg_z_audit_enrollment_withdrawals ON public.enrollment_withdrawals;
CREATE TRIGGER trg_z_audit_enrollment_withdrawals
  AFTER INSERT
  ON public.enrollment_withdrawals
  FOR EACH ROW
  EXECUTE FUNCTION public.audit_trigger_func();

-- 5.4 Course Materials
DROP TRIGGER IF EXISTS trg_z_audit_course_materials ON public.course_materials;
CREATE TRIGGER trg_z_audit_course_materials
  AFTER INSERT OR UPDATE OR DELETE
  ON public.course_materials
  FOR EACH ROW
  EXECUTE FUNCTION public.audit_trigger_func();

