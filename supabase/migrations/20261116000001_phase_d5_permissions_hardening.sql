-- ============================================================================
-- Migration: 20261116000001_phase_d5_permissions_hardening.sql
-- Description: Phase D5.1 - Role-Based Administration & Granular Permissions Hardening
--
-- Contents:
--   1. Harden audit_trigger_func() to redact sensitive fields ('pin_hash') on 'users'
--   2. Attach trg_z_audit_users trigger on public.users
--   3. Declare missing repository audit triggers (payments, enrollments, expenses, attendance, sessions)
--   4. Harden search_path on 13 SECURITY DEFINER functions (adding pg_temp and setting defaults)
--   5. Expand reception payment methods via ALTER POLICY on payments table
--   6. Remove phantom 'accountant' role references from database security helpers
--   7. Revoke broad anon privileges on internal tables (Defense-in-depth)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Update audit_trigger_func() to redact pin_hash on 'users'
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.audit_trigger_func()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
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
  -- استخراج معرف السجل وبيانات JSON
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

  -- [D5 Security Hardening] تجريد حقول الأمان الحساسة مثل pin_hash لجدول المستخدمين
  IF TG_TABLE_NAME = 'users' THEN
    IF v_old_data IS NOT NULL THEN
      v_old_data := v_old_data - 'pin_hash';
    END IF;
    IF v_new_data IS NOT NULL THEN
      v_new_data := v_new_data - 'pin_hash';
    END IF;
  END IF;

  -- تحديد الفاعل بتسلسل هرمي موثوق
  -- أولوية 1: سياق JWT النشط للمستخدم المسجل
  v_actor_id := auth.uid();
  IF v_actor_id IS NOT NULL THEN
    v_actor_source := 'jwt';
  ELSE
    -- أولوية 2: المتغير الموثوق من دوال الـ RPC المعرفة
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

  -- أولوية 3: الرجوع الاحتياطي لحقول الجدول عند انعدام السياق
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

  -- التحقق من وجود المستخدم لاحترام قيد المفتاح الأجنبي
  IF v_actor_id IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM public.users WHERE id = v_actor_id) THEN
      v_actor_id := NULL;
      v_actor_source := 'system';
    END IF;
  ELSE
    v_actor_source := 'system';
  END IF;

  -- جلب دور الفاعل
  IF v_actor_id IS NOT NULL THEN
    SELECT role::text INTO v_actor_role
    FROM public.users
    WHERE id = v_actor_id;
  END IF;

  -- إدراج سجل التدقيق غير القابل للتعديل
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

-- ----------------------------------------------------------------------------
-- 2. Attach audit trigger on public.users
-- ----------------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_z_audit_users ON public.users;
CREATE TRIGGER trg_z_audit_users
AFTER INSERT OR UPDATE OR DELETE ON public.users
FOR EACH ROW EXECUTE FUNCTION public.audit_trigger_func();

-- ----------------------------------------------------------------------------
-- 3. Declarative definition of 5 repository-missing audit triggers
-- ----------------------------------------------------------------------------
DROP TRIGGER IF EXISTS audit_payments ON public.payments;
CREATE TRIGGER audit_payments
AFTER INSERT OR UPDATE OR DELETE ON public.payments
FOR EACH ROW EXECUTE FUNCTION public.audit_trigger_func();

DROP TRIGGER IF EXISTS audit_enrollments ON public.enrollments;
CREATE TRIGGER audit_enrollments
AFTER INSERT OR UPDATE OR DELETE ON public.enrollments
FOR EACH ROW EXECUTE FUNCTION public.audit_trigger_func();

DROP TRIGGER IF EXISTS audit_expenses ON public.expenses;
CREATE TRIGGER audit_expenses
AFTER INSERT OR UPDATE OR DELETE ON public.expenses
FOR EACH ROW EXECUTE FUNCTION public.audit_trigger_func();

DROP TRIGGER IF EXISTS audit_attendance ON public.attendance;
CREATE TRIGGER audit_attendance
AFTER INSERT OR UPDATE OR DELETE ON public.attendance
FOR EACH ROW EXECUTE FUNCTION public.audit_trigger_func();

DROP TRIGGER IF EXISTS audit_sessions ON public.sessions;
CREATE TRIGGER audit_sessions
AFTER INSERT OR UPDATE OR DELETE ON public.sessions
FOR EACH ROW EXECUTE FUNCTION public.audit_trigger_func();

-- ----------------------------------------------------------------------------
-- 4. Harden search_path on all SECURITY DEFINER functions dynamically
-- ----------------------------------------------------------------------------
DO $$
DECLARE
  r RECORD;
  v_sql text;
BEGIN
  FOR r IN (
    SELECT p.proname,
           pg_get_function_identity_arguments(p.oid) AS args
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.prosecdef = true
      AND (
        p.proconfig IS NULL
        OR p.proconfig = ARRAY['search_path=public']
        OR (
          NOT ('search_path=public, pg_temp' = ANY(p.proconfig))
          AND NOT EXISTS (
            SELECT 1 FROM unnest(p.proconfig) c WHERE c LIKE '%extensions%'
          )
        )
      )
  ) LOOP
    v_sql := format('ALTER FUNCTION public.%I(%s) SET search_path = public, pg_temp;', r.proname, r.args);
    EXECUTE v_sql;
    RAISE NOTICE 'Hardened search_path on function: %(%)', r.proname, r.args;
  END LOOP;
END;
$$;

-- pgcrypto lives in the extensions schema; PIN helpers must resolve crypt/gen_salt
ALTER FUNCTION public.set_user_pin(text) SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.verify_user_pin(text) SET search_path = public, extensions, pg_temp;

-- ----------------------------------------------------------------------------
-- 5. Expand reception payment methods & enforce performed_by = auth.uid()
-- ----------------------------------------------------------------------------
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_policy WHERE polrelid = 'public.payments'::regclass AND polname = 'reception_insert') THEN
    ALTER POLICY reception_insert ON public.payments
    WITH CHECK (
      (get_user_role() = 'reception'::user_role) AND
      (performed_by = auth.uid()) AND
      (method IN ('cash'::payment_method, 'sham_cash'::payment_method, 'hawala'::payment_method, 'transfer'::payment_method))
    );
  END IF;
END $$;

-- ----------------------------------------------------------------------------
-- 6. Clean phantom 'accountant' references from database security helpers
-- ----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.c1_can_read_financials();

CREATE OR REPLACE FUNCTION public.c1_is_staff()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.users
    WHERE id = auth.uid()
      AND role IN ('admin', 'reception')
      AND is_active = true
  );
$$;

CREATE OR REPLACE FUNCTION public.c1_staff_role()
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT role::text FROM public.users
  WHERE id = auth.uid()
    AND is_active = true
  LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.c1_can_read_financials(p_trainee_user_id uuid DEFAULT NULL)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT
    -- Trusted contexts: direct DB owner, pg_cron and service_role must never be row-filtered
    auth.role() IS NULL
    OR auth.role() = 'service_role'
    OR public.c1_is_staff()
    OR
    (
      p_trainee_user_id IS NOT NULL
      AND auth.uid() = p_trainee_user_id
      AND EXISTS (
        SELECT 1 FROM public.users u
        WHERE u.id = auth.uid()
          AND u.role = 'trainee'
          AND u.is_active = true
      )
    );
$$;

-- ----------------------------------------------------------------------------
-- 7. Revoke broad anon privileges on internal tables (Defense-in-depth)
-- ----------------------------------------------------------------------------
REVOKE ALL ON public.cron_job_log FROM anon;
REVOKE ALL ON public.monthly_targets FROM anon;
REVOKE ALL ON public.lab_clients FROM anon;
REVOKE ALL ON public.lab_expenses FROM anon;
REVOKE ALL ON public.lab_invoice_items FROM anon;
REVOKE ALL ON public.lab_invoices FROM anon;
REVOKE ALL ON public.lab_payments FROM anon;
