--
-- PostgreSQL database dump
--

-- \restrict rCv2pK1UjbLvqsKsd43B4uenpvplvUSrVwdVn9Y4SBLoWc3QmQHzFW0BUPxD0Rs

-- Dumped from database version 17.6
-- Dumped by pg_dump version 17.12

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: public; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA IF NOT EXISTS public;


--
-- Name: SCHEMA public; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON SCHEMA public IS 'standard public schema';


--
-- Name: attendance_method; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.attendance_method AS ENUM (
    'qr',
    'manual'
);


--
-- Name: currency_type; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.currency_type AS ENUM (
    'SYP',
    'USD'
);


--
-- Name: expense_category; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.expense_category AS ENUM (
    'rent',
    'utilities',
    'salary',
    'supplies',
    'other'
);


--
-- Name: payment_method; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.payment_method AS ENUM (
    'cash',
    'transfer',
    'other',
    'sham_cash',
    'hawala'
);


--
-- Name: payment_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.payment_status AS ENUM (
    'unpaid',
    'partial',
    'complete'
);


--
-- Name: session_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.session_status AS ENUM (
    'scheduled',
    'open',
    'closed',
    'missed'
);


--
-- Name: survey_dispatch_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.survey_dispatch_status AS ENUM (
    'pending',
    'sent',
    'answered'
);


--
-- Name: user_role; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.user_role AS ENUM (
    'admin',
    'trainer',
    'reception',
    'trainee'
);


--
-- Name: audit_trigger_func(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.audit_trigger_func() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
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
$$;


--
-- Name: auto_open_close_sessions(boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.auto_open_close_sessions(p_dry_run boolean DEFAULT false) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_opened_count INT := 0;
  v_closed_count INT := 0;
  v_missed_count INT := 0;
  v_opened_ids UUID[] := '{}';
  v_closed_ids UUID[] := '{}';
  v_missed_ids UUID[] := '{}';
BEGIN
  SELECT COALESCE(array_agg(id), '{}') INTO v_opened_ids
  FROM public.sessions
  WHERE status = 'scheduled'
    AND scheduled_at <= now()
    AND scheduled_at > now() - interval '60 minutes';

  v_opened_count := cardinality(v_opened_ids);

  IF NOT p_dry_run AND v_opened_count > 0 THEN
    UPDATE public.sessions
    SET status = 'open',
        qr_token = gen_random_uuid(),
        opened_at = now(),
        opened_by = NULL
    WHERE id = ANY(v_opened_ids)
      AND status = 'scheduled';
  END IF;

  SELECT COALESCE(array_agg(id), '{}') INTO v_closed_ids
  FROM public.sessions
  WHERE status = 'open'
    AND opened_at IS NOT NULL
    AND (opened_at + (duration_minutes || ' minutes')::interval) <= now();

  v_closed_count := cardinality(v_closed_ids);

  IF NOT p_dry_run AND v_closed_count > 0 THEN
    UPDATE public.sessions
    SET status = 'closed',
        closed_at = now()
    WHERE id = ANY(v_closed_ids)
      AND status = 'open';
  END IF;

  SELECT COALESCE(array_agg(id), '{}') INTO v_missed_ids
  FROM public.sessions
  WHERE status = 'scheduled'
    AND scheduled_at <= now() - interval '120 minutes';

  v_missed_count := cardinality(v_missed_ids);

  IF NOT p_dry_run AND v_missed_count > 0 THEN
    UPDATE public.sessions
    SET status = 'missed'
    WHERE id = ANY(v_missed_ids)
      AND status = 'scheduled';
  END IF;

  INSERT INTO public.cron_job_log (
    job_name,
    opened_sessions_count,
    closed_sessions_count,
    missed_sessions_count,
    details,
    status
  ) VALUES (
    CASE WHEN p_dry_run THEN 'auto_sessions_dry_run' ELSE 'auto_sessions_live' END,
    v_opened_count,
    v_closed_count,
    v_missed_count,
    jsonb_build_object(
      'dry_run', p_dry_run,
      'opened_ids', v_opened_ids,
      'closed_ids', v_closed_ids,
      'missed_ids', v_missed_ids
    ),
    'success'
  );

  RETURN jsonb_build_object(
    'success', true,
    'opened_count', v_opened_count,
    'closed_count', v_closed_count,
    'missed_count', v_missed_count
  );
END;
$$;


--
-- Name: btrim(public.currency_type); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.btrim(public.currency_type) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $_$ 
  SELECT btrim($1::text); 
$_$;


--
-- Name: bulk_schedule_sessions(uuid, date, time without time zone, integer[], integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.bulk_schedule_sessions(p_cohort_id uuid, p_start_date date, p_start_time time without time zone, p_days_of_week integer[], p_session_count integer, p_duration_minutes integer DEFAULT 120) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_role TEXT;
  v_max_session_num INT := 0;
  v_has_executed BOOLEAN := false;
  v_min_date TIMESTAMPTZ;
  v_inserted_count INT := 0;
BEGIN
  SELECT role INTO v_role 
  FROM public.users 
  WHERE id = auth.uid() AND is_active = true;

  IF v_role IS NULL OR v_role NOT IN ('admin', 'reception') THEN
    RAISE EXCEPTION 'غير مصرح: جدولة الجلسات مخصصة للإدارة والاستقبال فقط';
  END IF;

  IF p_session_count <= 0 THEN
    RAISE EXCEPTION 'عدد الجلسات المطلوب جدولتها يجب أن يكون أكبر من الصفر';
  END IF;

  IF p_days_of_week IS NULL OR cardinality(p_days_of_week) = 0 THEN
    RAISE EXCEPTION 'يرجى تحديد يوم واحد على الأقل لجدولة الجلسات';
  END IF;

  SELECT COALESCE(MAX(session_number), 0) INTO v_max_session_num
  FROM public.sessions
  WHERE cohort_id = p_cohort_id;

  SELECT EXISTS (
    SELECT 1 FROM public.sessions 
    WHERE cohort_id = p_cohort_id AND status IN ('open', 'closed')
  ) INTO v_has_executed;

  WITH candidate_dates AS (
    SELECT (d::date + p_start_time) AT TIME ZONE 'Asia/Damascus' AS session_timestamptz
    FROM generate_series(p_start_date, p_start_date + interval '1 year', interval '1 day') d
    WHERE EXTRACT(DOW FROM d)::int = ANY(p_days_of_week)
    LIMIT p_session_count
  ),
  inserted_rows AS (
    INSERT INTO public.sessions (
      cohort_id,
      session_number,
      scheduled_at,
      duration_minutes,
      status,
      is_extra
    )
    SELECT 
      p_cohort_id,
      ROW_NUMBER() OVER (ORDER BY session_timestamptz ASC) + v_max_session_num,
      session_timestamptz,
      p_duration_minutes,
      'scheduled',
      false
    FROM candidate_dates
    RETURNING id, scheduled_at
  )
  SELECT count(*), MIN(scheduled_at) 
  INTO v_inserted_count, v_min_date
  FROM inserted_rows;

  IF NOT v_has_executed AND v_min_date IS NOT NULL THEN
    UPDATE public.cohorts 
    SET starts_at = v_min_date 
    WHERE id = p_cohort_id;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'created_count', v_inserted_count,
    'first_session_date', v_min_date,
    'message', format('تمت جدولة %s جلسة بنجاح', v_inserted_count)
  );
END;
$$;


--
-- Name: c1_allocate_payment(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.c1_allocate_payment(p_payment_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
    v_payment   record;
    v_enr       record;
    v_refunded  numeric(12,2);
    v_amount    numeric(12,2);
    v_remaining numeric(12,2);
    v_alloc     numeric(12,2);
    r           record;
BEGIN
    SELECT p.id, p.enrollment_id, p.amount, p.currency
    INTO v_payment
    FROM public.payments p
    WHERE p.id = p_payment_id;

    IF v_payment.id IS NULL OR v_payment.enrollment_id IS NULL THEN
        RETURN;
    END IF;

    PERFORM pg_advisory_xact_lock(
        hashtextextended('c1_alloc:' || v_payment.enrollment_id::text, 0)
    );

    SELECT e.id, e.currency::text AS currency, e.status::text AS status,
           e.lifecycle_status,
           COALESCE(e.total_due, 0) - COALESCE(e.discount_amount, 0) AS net
    INTO v_enr
    FROM public.enrollments e
    WHERE e.id = v_payment.enrollment_id;

    IF v_enr.id IS NULL THEN
        RETURN;
    END IF;

    IF v_payment.currency::text IS DISTINCT FROM v_enr.currency THEN
        RAISE EXCEPTION 'عملة الدفعة (%) لا تطابق عملة التسجيل (%)',
            v_payment.currency, v_enr.currency;
    END IF;

    SELECT COALESCE(sum(rf.amount), 0) INTO v_refunded
    FROM public.payment_refunds rf
    WHERE rf.payment_id = p_payment_id;

    v_amount := COALESCE(v_payment.amount, 0) - v_refunded;

    IF v_amount <= 0 THEN
        DELETE FROM public.payment_allocations WHERE payment_id = p_payment_id;
        RETURN;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM public.installment_schedule s WHERE s.enrollment_id = v_enr.id
    ) AND v_enr.net > 0
      AND v_enr.lifecycle_status <> 'withdrawn' THEN
        INSERT INTO public.installment_schedule
          (enrollment_id, installment_number, due_date, amount, currency, notes, created_by)
        VALUES
          (v_enr.id, 1, (now() AT TIME ZONE 'Asia/Damascus')::date,
           v_enr.net, v_payment.currency, 'قسط افتراضي آلي (Phase C1)', auth.uid())
        ON CONFLICT (enrollment_id, installment_number) DO NOTHING;
    END IF;

    DELETE FROM public.payment_allocations WHERE payment_id = p_payment_id;

    v_remaining := v_amount;

    FOR r IN
        SELECT s.id, s.amount, COALESCE(a.alloc, 0) AS allocated
        FROM public.installment_schedule s
        LEFT JOIN (
            SELECT pa.installment_id, sum(pa.amount) AS alloc
            FROM public.payment_allocations pa
            GROUP BY pa.installment_id
        ) a ON a.installment_id = s.id
        WHERE s.enrollment_id = v_enr.id
          AND s.amount > COALESCE(a.alloc, 0)
        ORDER BY s.due_date, s.installment_number
    LOOP
        EXIT WHEN v_remaining <= 0;
        v_alloc := LEAST(v_remaining, r.amount - r.allocated);
        IF v_alloc > 0 THEN
            INSERT INTO public.payment_allocations
              (payment_id, installment_id, amount, created_by)
            VALUES
              (p_payment_id, r.id, v_alloc, auth.uid());
            v_remaining := v_remaining - v_alloc;
        END IF;
    END LOOP;
END;
$$;


--
-- Name: c1_apply_plan_delta(uuid, numeric); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.c1_apply_plan_delta(p_enrollment_id uuid, p_delta numeric) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
    v_last_id   uuid;
    v_remaining numeric(12,2);
    v_take      numeric(12,2);
    v_free      numeric(12,2);
    v_net       numeric(12,2);
    v_currency  public.currency_type;
    r           record;
BEGIN
    IF p_delta IS NULL OR p_delta = 0 THEN
        RETURN;
    END IF;

    PERFORM pg_advisory_xact_lock(
        hashtextextended('c1_plan:' || p_enrollment_id::text, 0)
    );

    SELECT e.currency,
           COALESCE(e.total_due, 0) - COALESCE(e.discount_amount, 0) +
           COALESCE((SELECT sum(fa.amount) FROM public.fee_adjustments fa
                     WHERE fa.enrollment_id = e.id), 0)
    INTO v_currency, v_net
    FROM public.enrollments e
    WHERE e.id = p_enrollment_id;

    IF v_currency IS NULL THEN
        RETURN;
    END IF;

    IF p_delta > 0 THEN
        SELECT s.id INTO v_last_id
        FROM public.installment_schedule s
        WHERE s.enrollment_id = p_enrollment_id
        ORDER BY s.installment_number DESC LIMIT 1;

        IF v_last_id IS NULL THEN
            INSERT INTO public.installment_schedule
              (enrollment_id, installment_number, due_date, amount, currency, notes)
            VALUES
              (p_enrollment_id, 1, (now() AT TIME ZONE 'Asia/Damascus')::date,
               v_net, v_currency, 'قسط افتراضي آلي (Phase C1)');
        ELSE
            UPDATE public.installment_schedule
            SET amount = amount + p_delta WHERE id = v_last_id;
        END IF;
    ELSE
        v_remaining := -p_delta;

        FOR r IN
            SELECT s.id, s.amount, COALESCE(a.alloc, 0) AS allocated
            FROM public.installment_schedule s
            LEFT JOIN (
                SELECT pa.installment_id, sum(pa.amount) AS alloc
                FROM public.payment_allocations pa GROUP BY pa.installment_id
            ) a ON a.installment_id = s.id
            WHERE s.enrollment_id = p_enrollment_id
            ORDER BY s.installment_number DESC
        LOOP
            EXIT WHEN v_remaining <= 0;
            v_free := r.amount - r.allocated;
            v_take := LEAST(v_remaining, v_free);
            IF v_take > 0 THEN
                IF v_take = r.amount THEN
                    DELETE FROM public.installment_schedule WHERE id = r.id;
                ELSE
                    UPDATE public.installment_schedule
                    SET amount = amount - v_take WHERE id = r.id;
                END IF;
                v_remaining := v_remaining - v_take;
            END IF;
        END LOOP;

        IF v_remaining > 0 THEN
            RAISE EXCEPTION 'تعذر تطبيق التخفيض بالكامل؛ المتبقي %', v_remaining;
        END IF;
    END IF;
END;
$$;


--
-- Name: c1_can_read_financials(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.c1_can_read_financials(p_trainee_user_id uuid DEFAULT NULL::uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
  SELECT
    -- Trusted contexts: direct DB owner, pg_cron and service_role must never be row-filtered
    auth.role() IS NULL
    OR auth.role() = 'service_role'
    OR public.c1_is_staff()
    OR
    -- Trainees can only read their own financial records
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


--
-- Name: c1_guard_user_admin_changes(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.c1_guard_user_admin_changes() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_claims text := current_setting('request.jwt.claims', true);
  v_actor uuid := auth.uid();
  v_other_admins integer;
BEGIN
  -- Trusted silent paths only: migrations/psql and pg_cron carry no PostgREST
  -- JWT. service_role API calls DO carry claims and stay guarded.
  IF v_claims IS NULL OR v_claims = '' THEN
    IF TG_OP = 'DELETE' THEN
      RETURN OLD;
    END IF;
    RETURN NEW;
  END IF;

  -- Only role/is_active transitions and deletions are dangerous; plain profile
  -- edits (name, phone...) pass through untouched.
  IF TG_OP = 'UPDATE'
     AND NEW.role IS NOT DISTINCT FROM OLD.role
     AND NEW.is_active IS NOT DISTINCT FROM OLD.is_active THEN
    RETURN NEW;
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext('public.users.c1_admin_guard'));

  IF TG_OP = 'DELETE' THEN
    IF v_actor IS NOT NULL AND v_actor = OLD.id THEN
      RAISE EXCEPTION 'لا يمكنك حذف حسابك الخاص' USING ERRCODE = 'P0001';
    END IF;

    IF OLD.role = 'admin' AND OLD.is_active THEN
      SELECT count(*) INTO v_other_admins
      FROM public.users
      WHERE role = 'admin'
        AND is_active = true
        AND id <> OLD.id;

      IF v_other_admins = 0 THEN
        RAISE EXCEPTION 'لا يمكن حذف آخر مدير نشط في النظام' USING ERRCODE = 'P0001';
      END IF;
    END IF;

    RETURN OLD;
  END IF;

  -- UPDATE: identity guard first, then admin-count invariant
  IF v_actor IS NOT NULL AND v_actor = OLD.id THEN
    IF NEW.role IS DISTINCT FROM OLD.role THEN
      RAISE EXCEPTION 'لا يمكنك تغيير دورك بنفسك' USING ERRCODE = 'P0001';
    END IF;

    IF NEW.is_active = false THEN
      RAISE EXCEPTION 'لا يمكنك تعطيل حسابك بنفسك' USING ERRCODE = 'P0001';
    END IF;
  END IF;

  IF OLD.role = 'admin' AND OLD.is_active
     AND (NEW.role <> 'admin' OR NEW.is_active = false) THEN
    SELECT count(*) INTO v_other_admins
    FROM public.users
    WHERE role = 'admin'
      AND is_active = true
      AND id <> OLD.id;

    IF v_other_admins = 0 THEN
      RAISE EXCEPTION 'لا يمكن إزالة آخر مدير نشط في النظام' USING ERRCODE = 'P0001';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;


--
-- Name: c1_is_admin(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.c1_is_admin() RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.users
    WHERE id = auth.uid()
      AND role = 'admin'
      AND is_active = true
  );
$$;


--
-- Name: FUNCTION c1_is_admin(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.c1_is_admin() IS 'True only for an active admin row in public.users; used by financial views.';


--
-- Name: c1_is_staff(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.c1_is_staff() RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.users
    WHERE id = auth.uid()
      AND role IN ('admin', 'reception')
      AND is_active = true
  );
$$;


--
-- Name: c1_refresh_enrollment_status(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.c1_refresh_enrollment_status(p_enrollment_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_net_paid numeric(12,2);
  v_net_due  numeric(12,2);
  v_new      public.payment_status;
BEGIN
  IF p_enrollment_id IS NULL THEN
    RETURN;
  END IF;

  SELECT COALESCE(sum(p.amount), 0) - COALESCE((
           SELECT sum(r.amount)
           FROM public.payment_refunds r
           JOIN public.payments p2 ON p2.id = r.payment_id
           WHERE p2.enrollment_id = p_enrollment_id
         ), 0)
  INTO v_net_paid
  FROM public.payments p
  WHERE p.enrollment_id = p_enrollment_id;

  SELECT COALESCE(e.total_due, 0) - COALESCE(e.discount_amount, 0) + COALESCE((
           SELECT sum(fa.amount)
           FROM public.fee_adjustments fa
           WHERE fa.enrollment_id = p_enrollment_id
         ), 0)
  INTO v_net_due
  FROM public.enrollments e
  WHERE e.id = p_enrollment_id;

  IF v_net_due IS NULL THEN
    RETURN;
  END IF;

  v_new := CASE
             WHEN v_net_paid >= v_net_due THEN 'complete'::public.payment_status
             WHEN v_net_paid > 0 THEN 'partial'::public.payment_status
             ELSE 'unpaid'::public.payment_status
           END;

  UPDATE public.enrollments
  SET status = v_new
  WHERE id = p_enrollment_id
    AND status IS DISTINCT FROM v_new;
END;
$$;


--
-- Name: c1_staff_role(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.c1_staff_role() RETURNS text
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
  SELECT role::text FROM public.users
  WHERE id = auth.uid()
    AND is_active = true
  LIMIT 1;
$$;


--
-- Name: c1_withdrawal_figures(uuid, integer, timestamp with time zone); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.c1_withdrawal_figures(p_enrollment_id uuid, p_sessions_override integer DEFAULT NULL::integer, p_at timestamp with time zone DEFAULT now()) RETURNS TABLE(trainee_id uuid, currency text, course_name text, cohort_name text, lifecycle_status text, total_sessions integer, delivered_sessions integer, sessions_overridden boolean, net_due_before numeric, net_due_after numeric, net_paid numeric, discount_revoked numeric, due_amount numeric, settlement_delta numeric, refundable numeric, debt_amount numeric)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_trainee_id UUID;
  v_currency TEXT;
  v_cohort_id UUID;
  v_lifecycle TEXT;
  v_total_due NUMERIC(12,2);
  v_discount NUMERIC(12,2);
  v_referral_discount NUMERIC(12,2);
  v_course_name TEXT;
  v_cohort_name TEXT;
  v_total INTEGER;
  v_delivered INTEGER;
  v_overridden BOOLEAN := false;
  v_adj NUMERIC(12,2);
  v_gross NUMERIC(12,2);
  v_refunded NUMERIC(12,2);
  v_paid NUMERIC(12,2);
  v_applied NUMERIC(12,2);
  v_revoked NUMERIC(12,2);
  v_net_before NUMERIC(12,2);
  v_net_after_raw NUMERIC(12,2);
  v_net_after NUMERIC(12,2);
  v_due NUMERIC(12,2);
  v_settlement NUMERIC(12,2);
BEGIN
  SELECT e.trainee_id, e.currency::text, e.cohort_id, e.lifecycle_status,
         e.total_due, COALESCE(e.discount_amount, 0),
         COALESCE(e.referral_discount_amount, 0)
  INTO v_trainee_id, v_currency, v_cohort_id, v_lifecycle,
       v_total_due, v_discount, v_referral_discount
  FROM public.enrollments e
  WHERE e.id = p_enrollment_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'ENROLLMENT_NOT_FOUND' USING ERRCODE = 'P0001';
  END IF;

  SELECT co.name, c.name, co.total_sessions::INTEGER
  INTO v_course_name, v_cohort_name, v_total
  FROM public.cohorts c
  JOIN public.courses co ON co.id = c.course_id
  WHERE c.id = v_cohort_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'COHORT_NOT_FOUND' USING ERRCODE = 'P0001';
  END IF;

  IF v_total IS NULL OR v_total <= 0 THEN
    RAISE EXCEPTION 'لا يمكن احتساب تسوية الانسحاب: يجب تحديد إجمالي جلسات الكورس أولاً'
      USING ERRCODE = 'P0001';
  END IF;

  SELECT count(*)::INTEGER
  INTO v_delivered
  FROM public.sessions s
  WHERE s.cohort_id = v_cohort_id
    AND COALESCE(s.is_extra, false) = false
    AND s.status IN ('open', 'closed')
    AND s.scheduled_at <= p_at;

  v_delivered := LEAST(GREATEST(v_delivered, 0), v_total);

  IF p_sessions_override IS NOT NULL THEN
    IF p_sessions_override < 0 OR p_sessions_override > v_total THEN
      RAISE EXCEPTION 'SESSIONS_OVERRIDE_OUT_OF_RANGE'
        USING ERRCODE = 'P0001',
              DETAIL = format('override=%s total=%s', p_sessions_override, v_total);
    END IF;
    v_delivered := p_sessions_override;
    v_overridden := true;
  END IF;

  SELECT COALESCE(sum(fa.amount), 0)
  INTO v_adj
  FROM public.fee_adjustments fa
  WHERE fa.enrollment_id = p_enrollment_id;

  SELECT COALESCE(sum(p.amount), 0)
  INTO v_gross
  FROM public.payments p
  WHERE p.enrollment_id = p_enrollment_id;

  SELECT COALESCE(sum(r.amount), 0)
  INTO v_refunded
  FROM public.payment_refunds r
  JOIN public.payments p ON p.id = r.payment_id
  WHERE p.enrollment_id = p_enrollment_id;

  v_paid := v_gross - v_refunded;

  SELECT COALESCE(sum(r.discount_amount), 0)
  INTO v_applied
  FROM public.referrals r
  WHERE r.applied_enrollment_id = p_enrollment_id
    AND r.status = 'applied';

  v_revoked := LEAST(v_discount, v_applied + v_referral_discount);

  v_net_before := v_total_due - v_discount + v_adj;
  v_net_after_raw := v_total_due - (v_discount - v_revoked) + v_adj;
  v_net_after := GREATEST(v_net_after_raw, 0);

  v_due := GREATEST(ROUND(v_net_after * v_delivered / v_total, 2), 0);
  v_settlement := v_due - v_net_after;

  RETURN QUERY SELECT
    v_trainee_id,
    v_currency,
    v_course_name,
    v_cohort_name,
    v_lifecycle,
    v_total,
    v_delivered,
    v_overridden,
    v_net_before,
    v_net_after,
    v_paid,
    v_revoked,
    v_due,
    v_settlement,
    GREATEST(v_paid - v_due, 0),
    GREATEST(v_due - v_paid, 0);
END;
$$;


--
-- Name: cancel_course_waitlist(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.cancel_course_waitlist(p_waitlist_id uuid) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_role TEXT;
  v_trainee_id UUID;
  v_cohort_id UUID;
  v_row RECORD;
  v_was_notified BOOLEAN;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'AUTH_REQUIRED' USING ERRCODE = 'P0001';
  END IF;

  SELECT u.role::TEXT
  INTO v_role
  FROM public.users u
  WHERE u.id = v_uid AND u.is_active = true;

  SELECT w.cohort_id
  INTO v_cohort_id
  FROM public.course_waitlist w
  WHERE w.id = p_waitlist_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'WAITLIST_NOT_FOUND' USING ERRCODE = 'P0001';
  END IF;

  PERFORM 1
  FROM public.cohorts c
  WHERE c.id = v_cohort_id
  FOR UPDATE;

  SELECT w.*
  INTO v_row
  FROM public.course_waitlist w
  WHERE w.id = p_waitlist_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'WAITLIST_NOT_FOUND' USING ERRCODE = 'P0001';
  END IF;

  IF v_role IS DISTINCT FROM 'admin' THEN
    SELECT t.id
    INTO v_trainee_id
    FROM public.trainees t
    WHERE t.user_id = v_uid;

    IF v_trainee_id IS NULL OR v_trainee_id <> v_row.trainee_id THEN
      RAISE EXCEPTION 'NOT_AUTHORIZED' USING ERRCODE = 'P0001';
    END IF;
  END IF;

  IF v_row.status NOT IN ('waiting', 'notified') THEN
    RAISE EXCEPTION 'WAITLIST_NOT_ACTIVE' USING ERRCODE = 'P0001';
  END IF;

  v_was_notified := (v_row.status = 'notified');

  UPDATE public.course_waitlist
  SET status = 'cancelled',
      cancelled_at = now(),
      updated_at = now()
  WHERE id = p_waitlist_id;

  IF v_was_notified THEN
    BEGIN
      PERFORM public.notify_next_waitlist(v_cohort_id);
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'waitlist notify skipped after cancel for cohort %: %',
                    v_cohort_id, SQLERRM;
    END;
  END IF;

  RETURN jsonb_build_object(
    'waitlist_id', p_waitlist_id,
    'status', 'cancelled'
  );
END;
$$;


--
-- Name: check_survey_dispatch(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.check_survey_dispatch() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  v_enrollment_id  UUID;
  v_attended_count INT;
  v_template_id    UUID;
  v_trigger_count  INT;
  v_is_extra       BOOLEAN;
BEGIN
  -- التحقق مما إذا كانت الجلسة الحالية إضافية
  SELECT s.is_extra, e.id 
  INTO v_is_extra, v_enrollment_id
  FROM enrollments e
  JOIN cohorts c  ON c.id = e.cohort_id
  JOIN sessions s ON s.cohort_id = c.id
  WHERE s.id = NEW.session_id AND e.trainee_id = NEW.trainee_id;

  -- إذا لم يوجد تسجيل أو كانت الجلسة إضافية، لا نرسل استبياناً مرحلياً
  IF v_enrollment_id IS NULL OR v_is_extra IS TRUE THEN 
    RETURN NEW; 
  END IF;

  -- حساب عدد الجلسات الأساسية التي حضرها المتدرب فقط
  SELECT COUNT(*) INTO v_attended_count
  FROM attendance a
  JOIN sessions s ON s.id = a.session_id
  JOIN cohorts c  ON c.id = s.cohort_id
  JOIN enrollments e ON e.cohort_id = c.id AND e.trainee_id = a.trainee_id
  WHERE e.id = v_enrollment_id
    AND s.is_extra IS NOT TRUE;

  -- جلب القالب النشط
  SELECT id, trigger_after_sessions INTO v_template_id, v_trigger_count
  FROM survey_templates WHERE is_active = TRUE
  ORDER BY created_at DESC LIMIT 1;

  IF v_template_id IS NULL OR v_trigger_count IS NULL OR v_trigger_count <= 0 THEN 
    RETURN NEW; 
  END IF;

  -- التحقق من بلوغ العتبة
  IF v_attended_count > 0 AND (v_attended_count % v_trigger_count = 0) THEN
    INSERT INTO survey_dispatches (enrollment_id, template_id, at_session_count)
    VALUES (v_enrollment_id, v_template_id, v_attended_count)
    ON CONFLICT (enrollment_id, at_session_count) DO NOTHING;
  END IF;

  RETURN NEW;
END;
$$;


--
-- Name: claim_notification_batch(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.claim_notification_batch(p_limit integer DEFAULT 50) RETURNS TABLE(outbox_id uuid, recipient_user_id uuid, notification_type text, notification_title text, notification_body text, notification_data jsonb, attempt_number integer, max_attempts integer, created_at timestamp with time zone, fcm_tokens text[])
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_limit INTEGER := GREATEST(1, LEAST(COALESCE(p_limit, 50), 100));
BEGIN
  UPDATE public.notification_outbox
  SET status = 'pending', locked_at = NULL
  WHERE status = 'processing' AND locked_at < now() - interval '10 minutes';

  UPDATE public.notification_outbox
  SET status = 'failed', last_error = COALESCE(last_error, 'max_attempts_reached'), locked_at = NULL
  WHERE status = 'pending' AND attempts >= notification_outbox.max_attempts;

  RETURN QUERY
  WITH locked_rows AS (
    SELECT o.id FROM public.notification_outbox o
    WHERE o.status = 'pending' AND o.next_attempt_at <= now() AND o.attempts < o.max_attempts
    ORDER BY o.created_at ASC LIMIT v_limit FOR UPDATE SKIP LOCKED
  ),
  marked AS (
    UPDATE public.notification_outbox o
    SET status = 'processing', attempts = o.attempts + 1, locked_at = now()
    FROM locked_rows lr WHERE o.id = lr.id
    RETURNING o.id, o.user_id, o.type, o.title, o.body, o.data, o.attempts, o.max_attempts, o.created_at
  )
  SELECT 
    m.id AS outbox_id,
    m.user_id AS recipient_user_id,
    m.type AS notification_type,
    m.title AS notification_title,
    m.body AS notification_body,
    m.data AS notification_data,
    m.attempts AS attempt_number,
    m.max_attempts AS max_attempts,
    m.created_at AS created_at,
    COALESCE(
      (
        SELECT array_agg(t.fcm_token)
        FROM public.user_fcm_tokens t
        JOIN public.users u ON u.id = t.user_id AND u.is_active = true
        WHERE t.user_id = m.user_id AND t.is_active = true
      ),
      ARRAY[]::TEXT[]
    ) AS fcm_tokens
  FROM marked m;
END;
$$;


--
-- Name: close_session(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.close_session(p_session_id uuid) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_updated integer;
BEGIN
  IF public.c1_is_staff() IS NOT TRUE THEN
    RAISE EXCEPTION 'غير مصرح: إغلاق الجلسات مخصص للإدارة والاستقبال فقط';
  END IF;

  IF p_session_id IS NULL THEN
    RAISE EXCEPTION 'معرف الجلسة مطلوب';
  END IF;

  UPDATE public.sessions
  SET status = 'closed',
      closed_at = now()
  WHERE id = p_session_id
    AND status = 'open';

  GET DIAGNOSTICS v_updated = ROW_COUNT;

  IF v_updated = 0 THEN
    RAISE EXCEPTION 'الجلسة غير موجودة أو ليست مفتوحة';
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'session_id', p_session_id,
    'status', 'closed'
  );
END;
$$;


--
-- Name: cohort_active_enrollment_count(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.cohort_active_enrollment_count(p_cohort_id uuid) RETURNS integer
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
  SELECT count(*)::INTEGER
  FROM public.enrollments e
  WHERE e.cohort_id = p_cohort_id
    AND public.enrollment_lifecycle_occupies_seat(e.lifecycle_status);
$$;


--
-- Name: complete_password_change(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.complete_password_change() RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_uid        uuid := auth.uid();
  v_flag       boolean;
  v_flagged_at timestamptz;
  v_auth_upd   timestamptz;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'غير مصرح';
  END IF;

  SELECT u.must_change_password, u.must_change_password_at
  INTO v_flag, v_flagged_at
  FROM public.users u
  WHERE u.id = v_uid;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'المستخدم غير موجود';
  END IF;

  IF NOT v_flag THEN
    RETURN;
  END IF;

  SELECT au.updated_at INTO v_auth_upd
  FROM auth.users au
  WHERE au.id = v_uid;

  IF v_flagged_at IS NULL
     OR v_auth_upd IS NULL
     OR v_auth_upd <= v_flagged_at THEN
    RAISE EXCEPTION 'لم يتم تغيير كلمة المرور بعد';
  END IF;

  UPDATE public.users
  SET must_change_password = false,
      must_change_password_at = NULL
  WHERE id = v_uid;
END;
$$;


--
-- Name: create_session(uuid, integer, timestamp with time zone, integer, boolean, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_session(p_cohort_id uuid, p_session_number integer, p_scheduled_at timestamp with time zone, p_duration_minutes integer DEFAULT 120, p_is_extra boolean DEFAULT false, p_title text DEFAULT NULL::text, p_description text DEFAULT NULL::text) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_role text;
  v_id uuid;
BEGIN
  v_role := public.c1_staff_role();

  IF v_role IS NULL OR v_role NOT IN ('admin', 'reception') THEN
    RAISE EXCEPTION 'غير مصرح: إنشاء الجلسات مخصص للإدارة والاستقبال فقط';
  END IF;

  IF p_cohort_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.cohorts WHERE id = p_cohort_id
  ) THEN
    RAISE EXCEPTION 'الدفعة غير موجودة';
  END IF;

  IF p_session_number IS NULL OR p_session_number <= 0 THEN
    RAISE EXCEPTION 'رقم الجلسة يجب أن يكون أكبر من صفر';
  END IF;

  IF p_scheduled_at IS NULL THEN
    RAISE EXCEPTION 'موعد الجلسة مطلوب';
  END IF;

  IF p_duration_minutes IS NULL OR p_duration_minutes < 10 OR p_duration_minutes > 600 THEN
    RAISE EXCEPTION 'مدة الجلسة يجب أن تكون بين 10 و600 دقيقة';
  END IF;

  INSERT INTO public.sessions (
    cohort_id,
    session_number,
    scheduled_at,
    status,
    is_extra,
    title,
    description,
    duration_minutes
  ) VALUES (
    p_cohort_id,
    p_session_number,
    p_scheduled_at,
    'scheduled',
    COALESCE(p_is_extra, false),
    NULLIF(btrim(p_title), ''),
    NULLIF(btrim(p_description), ''),
    p_duration_minutes
  )
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;


--
-- Name: custom_access_token_hook(jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.custom_access_token_hook(event jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_role TEXT;
  v_claims JSONB;
  v_meta JSONB;
BEGIN
  -- الدور الموثوق من جدول المستخدمين، للحسابات النشطة فقط
  SELECT role::TEXT INTO v_role
  FROM public.users
  WHERE id = (event->>'user_id')::UUID
    AND is_active = true;

  -- بناء المسار بشكل محصن حتى لو كانت user_metadata غير مهيأة في claims
  v_claims := COALESCE(event->'claims', '{}'::jsonb);
  v_meta := COALESCE(v_claims->'user_metadata', '{}'::jsonb);
  v_meta := jsonb_set(v_meta, '{role}', to_jsonb(COALESCE(v_role, 'none')));
  v_claims := jsonb_set(v_claims, '{user_metadata}', v_meta);
  event := jsonb_set(event, '{claims}', v_claims);

  RETURN event;
END;
$$;


--
-- Name: dispatch_push_batch(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.dispatch_push_batch() RETURNS bigint
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_url TEXT;
  v_secret TEXT;
  v_slug TEXT;
BEGIN
  SELECT decrypted_secret INTO v_url FROM vault.decrypted_secrets WHERE name = 'project_url';
  SELECT decrypted_secret INTO v_secret FROM vault.decrypted_secrets WHERE name = 'cron_secret';
  SELECT decrypted_secret INTO v_slug FROM vault.decrypted_secrets WHERE name = 'push_function_slug';

  IF v_url IS NULL OR v_secret IS NULL OR v_slug IS NULL OR length(trim(v_slug)) = 0 THEN
    RAISE EXCEPTION 'push scheduler secrets missing in vault (project_url, cron_secret, or push_function_slug)';
  END IF;

  RETURN net.http_post(
    url := rtrim(v_url, '/') || '/functions/v1/' || trim(v_slug),
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-cron-secret', trim(v_secret)
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 30000
  );
END;
$$;


--
-- Name: dispatch_survey_to_all(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.dispatch_survey_to_all(p_template_id uuid) RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_inserted_count integer;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.users 
    WHERE id = auth.uid() AND role = 'admin' AND is_active = true
  ) THEN
    RAISE EXCEPTION 'غير مصرح: عملية إرسال الاستبيانات بالجملة مخصصة لمدير النظام فقط';
  END IF;

  WITH inserted AS (
    INSERT INTO public.survey_dispatches (enrollment_id, template_id, at_session_count)
    SELECT id, p_template_id, 0
    FROM public.enrollments
    ON CONFLICT (enrollment_id, at_session_count) DO NOTHING
    RETURNING 1
  )
  SELECT count(*) INTO v_inserted_count FROM inserted;

  RETURN v_inserted_count;
END;
$$;


--
-- Name: enqueue_payment_reminders(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.enqueue_payment_reminders() RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_inserted_count INTEGER;
  v_week_code TEXT := to_char(now() AT TIME ZONE 'Asia/Damascus', 'IYYY-IW');
BEGIN
  WITH debtors AS (
    SELECT DISTINCT t.user_id
    FROM public.overdue_installments_v oi
    JOIN public.trainees t ON t.id = oi.trainee_id
    JOIN public.users u ON u.id = t.user_id
    WHERE u.is_active = true
  ),
  inserted AS (
    INSERT INTO public.notification_outbox (
      user_id,
      type,
      title,
      body,
      data,
      dedupe_key
    )
    SELECT
      d.user_id,
      'payment_reminder',
      'تذكير بموعد القسط',
      'لديك قسط متأخر — يرجى مراجعة التفاصيل داخل التطبيق',
      jsonb_build_object(
        'type', 'payment_reminder',
        'route', '/payments'
      ),
      'payment_due:user:' || d.user_id || ':' || v_week_code
    FROM debtors d
    ON CONFLICT (dedupe_key) DO NOTHING
    RETURNING 1
  )
  SELECT count(*) INTO v_inserted_count FROM inserted;

  RETURN v_inserted_count;
END;
$$;


--
-- Name: enqueue_session_reminders(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.enqueue_session_reminders() RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_inserted_count INTEGER;
BEGIN
  WITH target_enrollments AS (
    SELECT DISTINCT
      t.user_id,
      s.id AS session_id,
      s.scheduled_at AS session_scheduled_at,
      co.name || COALESCE(' — ' || NULLIF(s.title, ''), '') AS display_name,
      to_char(s.scheduled_at AT TIME ZONE 'Asia/Damascus', 'HH24:MI') AS start_time,
      'session:' || s.id || ':user:' || t.user_id || ':60' AS dedupe_key
    FROM public.sessions s
    JOIN public.cohorts ch ON ch.id = s.cohort_id
    JOIN public.courses co ON co.id = ch.course_id
    JOIN public.enrollments e ON e.cohort_id = ch.id
    JOIN public.trainees t ON t.id = e.trainee_id
    JOIN public.users u ON u.id = t.user_id
    WHERE s.status IN ('scheduled', 'open')
      AND s.scheduled_at BETWEEN (now() + interval '55 minutes')
                             AND (now() + interval '65 minutes')
      AND u.is_active = true
      AND e.lifecycle_status <> 'withdrawn'
      AND NOT EXISTS (
        SELECT 1 FROM public.attendance a
        WHERE a.session_id = s.id AND a.trainee_id = e.trainee_id
      )
      AND NOT EXISTS (
        SELECT 1 FROM public.notification_outbox o
        WHERE o.user_id = t.user_id
          AND o.type = 'session_reminder'
          AND o.data->>'session_id' = s.id::text
      )
  ),
  inserted AS (
    INSERT INTO public.notification_outbox (
      user_id,
      type,
      title,
      body,
      data,
      dedupe_key
    )
    SELECT
      te.user_id,
      'session_reminder',
      'تذكير بجلسة بعد ساعة',
      te.display_name || ' — الساعة ' || te.start_time,
      jsonb_build_object(
        'type', 'session_reminder',
        'session_id', te.session_id,
        'scheduled_at', te.session_scheduled_at,
        'route', '/home'
      ),
      te.dedupe_key
    FROM target_enrollments te
    ON CONFLICT (dedupe_key) DO NOTHING
    RETURNING 1
  )
  SELECT count(*) INTO v_inserted_count FROM inserted;

  RETURN v_inserted_count;
END;
$$;


--
-- Name: enrollment_lifecycle_occupies_seat(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.enrollment_lifecycle_occupies_seat(p_lifecycle text) RETURNS boolean
    LANGUAGE sql IMMUTABLE PARALLEL SAFE
    SET search_path TO 'public', 'pg_temp'
    AS $$
  SELECT COALESCE(NULLIF(trim(p_lifecycle), ''), 'active') NOT IN ('withdrawn');
$$;


--
-- Name: enrollment_status_occupies_seat(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.enrollment_status_occupies_seat(p_status text) RETURNS boolean
    LANGUAGE sql IMMUTABLE PARALLEL SAFE
    SET search_path TO 'public', 'pg_temp'
    AS $$
  SELECT COALESCE(NULLIF(trim(p_status), ''), 'active')
         NOT IN ('dropped', 'cancelled', 'canceled', 'withdrawn', 'refunded');
$$;


--
-- Name: expire_waitlist_notifications(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.expire_waitlist_notifications() RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_cohort_ids UUID[];
  v_cohort_id UUID;
  v_expired_count INTEGER := 0;
BEGIN
  -- Read-only pass: collect cohorts with stale offers without locking rows.
  SELECT array_agg(DISTINCT w.cohort_id ORDER BY w.cohort_id)
  INTO v_cohort_ids
  FROM public.course_waitlist w
  WHERE w.status = 'notified'
    AND w.expires_at IS NOT NULL
    AND w.expires_at <= now();

  -- notify_next_waitlist locks the cohort first, then expires and promotes.
  FOREACH v_cohort_id IN ARRAY COALESCE(v_cohort_ids, ARRAY[]::UUID[])
  LOOP
    BEGIN
      PERFORM public.notify_next_waitlist(v_cohort_id);
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'waitlist expiry notify skipped for cohort %: %',
                    v_cohort_id, SQLERRM;
    END;
  END LOOP;

  -- Inactive cohorts (or failed notify calls) still need the stale rows expired.
  -- This UPDATE takes only waitlist row locks and never waits for a cohort afterwards.
  UPDATE public.course_waitlist
  SET status = 'expired',
      updated_at = now()
  WHERE status = 'notified'
    AND expires_at IS NOT NULL
    AND expires_at <= now();
  GET DIAGNOSTICS v_expired_count = ROW_COUNT;

  RETURN v_expired_count;
END;
$$;


--
-- Name: export_system_data(timestamp with time zone); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.export_system_data(p_audit_from timestamp with time zone DEFAULT (now() - '90 days'::interval)) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
    v_user_role text;
BEGIN
    SELECT role INTO v_user_role 
    FROM public.users 
    WHERE id = auth.uid() AND is_active = true;

    IF v_user_role IS DISTINCT FROM 'admin' THEN
        RAISE EXCEPTION 'غير مصرح: تصدير بيانات النظام مخصص حصراً لمدير النظام (Admin)';
    END IF;

    RETURN jsonb_build_object(
        'metadata', jsonb_build_object(
            'system_name', 'Taj Dentics Training Center & Dental Lab',
            'export_type', 'full_system_data_snapshot',
            'version', '2.0.0',
            'exported_at', to_char(now() AT TIME ZONE 'Asia/Damascus', 'YYYY-MM-DD"T"HH24:MI:SS"+03:00"'),
            'exported_by_user_id', auth.uid(),
            'exported_by_email', (SELECT email FROM auth.users WHERE id = auth.uid()),
            'audit_filter_applied', p_audit_from,
            'counts', jsonb_build_object(
                'users', (SELECT count(*) FROM public.users),
                'trainees', (SELECT count(*) FROM public.trainees),
                'courses', (SELECT count(*) FROM public.courses),
                'cohorts', (SELECT count(*) FROM public.cohorts),
                'sessions', (SELECT count(*) FROM public.sessions),
                'enrollments', (SELECT count(*) FROM public.enrollments),
                'payments', (SELECT count(*) FROM public.payments),
                'expenses', (SELECT count(*) FROM public.expenses),
                'attendance', (SELECT count(*) FROM public.attendance),
                'survey_templates', (SELECT count(*) FROM public.survey_templates),
                'survey_dispatches', (SELECT count(*) FROM public.survey_dispatches),
                'survey_responses', (SELECT count(*) FROM public.survey_responses),
                'monthly_targets', (SELECT count(*) FROM public.monthly_targets),
                'lab_clients', (SELECT count(*) FROM public.lab_clients),
                'lab_invoices', (SELECT count(*) FROM public.lab_invoices),
                'lab_invoice_items', (SELECT count(*) FROM public.lab_invoice_items),
                'lab_payments', (SELECT count(*) FROM public.lab_payments),
                'lab_expenses', (SELECT count(*) FROM public.lab_expenses),
                'course_waitlist', (SELECT count(*) FROM public.course_waitlist),
                'referrals', (SELECT count(*) FROM public.referrals),
                'course_materials', (SELECT count(*) FROM public.course_materials),
                'installment_schedule', (SELECT count(*) FROM public.installment_schedule),
                'payment_allocations', (SELECT count(*) FROM public.payment_allocations),
                'payment_refunds', (SELECT count(*) FROM public.payment_refunds),
                'fee_adjustments', (SELECT count(*) FROM public.fee_adjustments),
                'enrollment_withdrawals', (SELECT count(*) FROM public.enrollment_withdrawals),
                'audit_log', (SELECT count(*) FROM public.audit_log al WHERE p_audit_from IS NULL OR al.performed_at >= p_audit_from)
            )
        ),
        'data', jsonb_build_object(
            'users', (SELECT COALESCE(jsonb_agg(to_jsonb(u)), '[]'::jsonb) FROM public.users u),
            'trainees', (SELECT COALESCE(jsonb_agg(to_jsonb(t)), '[]'::jsonb) FROM public.trainees t),
            'courses', (SELECT COALESCE(jsonb_agg(to_jsonb(c)), '[]'::jsonb) FROM public.courses c),
            'cohorts', (SELECT COALESCE(jsonb_agg(to_jsonb(ch)), '[]'::jsonb) FROM public.cohorts ch),
            'sessions', (SELECT COALESCE(jsonb_agg(to_jsonb(s)), '[]'::jsonb) FROM public.sessions s),
            'enrollments', (SELECT COALESCE(jsonb_agg(to_jsonb(e)), '[]'::jsonb) FROM public.enrollments e),
            'payments', (SELECT COALESCE(jsonb_agg(to_jsonb(p)), '[]'::jsonb) FROM public.payments p),
            'expenses', (SELECT COALESCE(jsonb_agg(to_jsonb(ex)), '[]'::jsonb) FROM public.expenses ex),
            'attendance', (SELECT COALESCE(jsonb_agg(to_jsonb(a)), '[]'::jsonb) FROM public.attendance a),
            'survey_templates', (SELECT COALESCE(jsonb_agg(to_jsonb(st)), '[]'::jsonb) FROM public.survey_templates st),
            'survey_dispatches', (SELECT COALESCE(jsonb_agg(to_jsonb(sd)), '[]'::jsonb) FROM public.survey_dispatches sd),
            'survey_responses', (SELECT COALESCE(jsonb_agg(to_jsonb(sr)), '[]'::jsonb) FROM public.survey_responses sr),
            'monthly_targets', (SELECT COALESCE(jsonb_agg(to_jsonb(mt)), '[]'::jsonb) FROM public.monthly_targets mt),
            'lab_clients', (SELECT COALESCE(jsonb_agg(to_jsonb(lc)), '[]'::jsonb) FROM public.lab_clients lc),
            'lab_invoices', (SELECT COALESCE(jsonb_agg(to_jsonb(li)), '[]'::jsonb) FROM public.lab_invoices li),
            'lab_invoice_items', (SELECT COALESCE(jsonb_agg(to_jsonb(lii)), '[]'::jsonb) FROM public.lab_invoice_items lii),
            'lab_payments', (SELECT COALESCE(jsonb_agg(to_jsonb(lp)), '[]'::jsonb) FROM public.lab_payments lp),
            'lab_expenses', (SELECT COALESCE(jsonb_agg(to_jsonb(le)), '[]'::jsonb) FROM public.lab_expenses le),
            'course_waitlist', (SELECT COALESCE(jsonb_agg(to_jsonb(cw)), '[]'::jsonb) FROM public.course_waitlist cw),
            'referrals', (SELECT COALESCE(jsonb_agg(to_jsonb(ref)), '[]'::jsonb) FROM public.referrals ref),
            'course_materials', (SELECT COALESCE(jsonb_agg(to_jsonb(cm)), '[]'::jsonb) FROM public.course_materials cm),
            'installment_schedule', (SELECT COALESCE(jsonb_agg(to_jsonb(isch)), '[]'::jsonb) FROM public.installment_schedule isch),
            'payment_allocations', (SELECT COALESCE(jsonb_agg(to_jsonb(pa)), '[]'::jsonb) FROM public.payment_allocations pa),
            'payment_refunds', (SELECT COALESCE(jsonb_agg(to_jsonb(pr)), '[]'::jsonb) FROM public.payment_refunds pr),
            'fee_adjustments', (SELECT COALESCE(jsonb_agg(to_jsonb(fa)), '[]'::jsonb) FROM public.fee_adjustments fa),
            'enrollment_withdrawals', (SELECT COALESCE(jsonb_agg(to_jsonb(ew)), '[]'::jsonb) FROM public.enrollment_withdrawals ew),
            'audit_log', (
                SELECT COALESCE(jsonb_agg(to_jsonb(al) ORDER BY al.performed_at DESC), '[]'::jsonb) 
                FROM public.audit_log al 
                WHERE p_audit_from IS NULL OR al.performed_at >= p_audit_from
            )
        )
    );
END;
$$;


--
-- Name: FUNCTION export_system_data(p_audit_from timestamp with time zone); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.export_system_data(p_audit_from timestamp with time zone) IS 'Exports full system data snapshot (27 tables) as JSONB for admin backup; audit_log is filtered by p_audit_from (default last 90 days).';


--
-- Name: get_cohorts_seat_status(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_cohorts_seat_status(p_course_id uuid DEFAULT NULL::uuid) RETURNS TABLE(cohort_id uuid, course_id uuid, cohort_name text, course_name text, cohort_starts_at timestamp with time zone, course_price numeric, course_total_sessions integer, capacity integer, enrolled_count integer, waitlist_count integer, available_seats integer, is_full boolean)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
  SELECT
    c.id,
    c.course_id,
    c.name,
    co.name,
    c.starts_at,
    co.price::NUMERIC,
    co.total_sessions::INTEGER,
    c.capacity,
    ec.enrolled_count,
    wc.waitlist_count,
    CASE
      WHEN c.capacity IS NULL THEN NULL
      ELSE GREATEST(c.capacity - ec.enrolled_count, 0)::INTEGER
    END,
    CASE
      WHEN c.capacity IS NULL THEN false
      ELSE ec.enrolled_count >= c.capacity
    END
  FROM public.cohorts c
  JOIN public.courses co ON co.id = c.course_id
  CROSS JOIN LATERAL (
    SELECT count(*)::INTEGER AS enrolled_count
    FROM public.enrollments e
    WHERE e.cohort_id = c.id
      AND public.enrollment_lifecycle_occupies_seat(e.lifecycle_status)
  ) ec
  CROSS JOIN LATERAL (
    SELECT count(*)::INTEGER AS waitlist_count
    FROM public.course_waitlist w
    WHERE w.cohort_id = c.id
      AND w.status IN ('waiting', 'notified')
  ) wc
  WHERE c.is_active = true
    AND co.is_active = true
    AND (p_course_id IS NULL OR c.course_id = p_course_id)
  ORDER BY co.name ASC, c.name ASC;
$$;


--
-- Name: get_current_user_id(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_current_user_id() RETURNS uuid
    LANGUAGE sql STABLE
    AS $$
  SELECT auth.uid();
$$;


--
-- Name: get_monthly_target_progress(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_monthly_target_progress(p_month_key text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
    v_month text;
    v_user_role text;
    v_target_syp numeric := 0;
    v_target_usd numeric := 0;
    v_collected_syp numeric := 0;
    v_collected_usd numeric := 0;
    v_has_target boolean := false;
BEGIN
    SELECT role INTO v_user_role FROM public.users WHERE id = auth.uid() AND is_active = true;
    IF v_user_role IS DISTINCT FROM 'admin' THEN
        RAISE EXCEPTION 'غير مصرح: الاطلاع على الأهداف المالية مخصص لمدير النظام فقط';
    END IF;

    v_month := COALESCE(p_month_key, to_char(now() AT TIME ZONE 'Asia/Damascus', 'YYYY-MM'));

    SELECT target_syp, target_usd, true
    INTO v_target_syp, v_target_usd, v_has_target
    FROM public.monthly_targets
    WHERE month_key = v_month;

    IF NOT FOUND THEN
        v_target_syp := 0;
        v_target_usd := 0;
        v_has_target := false;
    END IF;

    SELECT
        COALESCE(SUM(CASE WHEN currency = 'SYP' THEN amount ELSE 0 END), 0),
        COALESCE(SUM(CASE WHEN currency = 'USD' THEN amount ELSE 0 END), 0)
    INTO v_collected_syp, v_collected_usd
    FROM public.payments
    WHERE to_char(paid_at AT TIME ZONE 'Asia/Damascus', 'YYYY-MM') = v_month;

    RETURN jsonb_build_object(
        'month_key', v_month,
        'has_target', v_has_target,
        'target_syp', v_target_syp,
        'collected_syp', v_collected_syp,
        'progress_syp', CASE WHEN v_target_syp > 0 THEN ROUND((v_collected_syp / v_target_syp) * 100, 1) ELSE 0 END,
        'target_usd', v_target_usd,
        'collected_usd', v_collected_usd,
        'progress_usd', CASE WHEN v_target_usd > 0 THEN ROUND((v_collected_usd / v_target_usd) * 100, 1) ELSE 0 END
    );
END;
$$;


--
-- Name: get_my_password_state(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_my_password_state() RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
  SELECT COALESCE((
    SELECT u.must_change_password
    FROM public.users u
    WHERE u.id = auth.uid()
  ), false)
$$;


--
-- Name: get_my_referral_summary(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_my_referral_summary() RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_trainee_id UUID;
  v_code TEXT;
  v_available JSONB;
  v_referrals JSONB;
BEGIN
  SELECT t.id
  INTO v_trainee_id
  FROM public.trainees t
  WHERE t.user_id = auth.uid();

  IF v_trainee_id IS NULL THEN
    RAISE EXCEPTION 'AUTH_REQUIRED' USING ERRCODE = 'P0001';
  END IF;

  SELECT t.trainee_code
  INTO v_code
  FROM public.trainees t
  WHERE t.id = v_trainee_id;

  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'currency', x.currency,
        'amount', x.total,
        'count', x.cnt
      )
      ORDER BY x.currency
    ),
    '[]'::jsonb
  )
  INTO v_available
  FROM (
    SELECT upper(btrim(r.currency)) AS currency,
           sum(r.discount_amount) AS total,
           count(*) AS cnt
    FROM public.referrals r
    WHERE r.referrer_trainee_id = v_trainee_id
      AND r.status = 'available'
    GROUP BY upper(btrim(r.currency))
  ) x;

  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'id', r.id,
        'referee_name', u.full_name,
        'course_name', co.name,
        'amount', r.discount_amount,
        'currency', r.currency,
        'status', r.status,
        'created_at', r.created_at,
        'applied_at', r.applied_at
      )
      ORDER BY r.created_at DESC
    ),
    '[]'::jsonb
  )
  INTO v_referrals
  FROM public.referrals r
  JOIN public.trainees t ON t.id = r.referee_trainee_id
  JOIN public.users u ON u.id = t.user_id
  JOIN public.courses co ON co.id = r.course_id
  WHERE r.referrer_trainee_id = v_trainee_id;

  RETURN jsonb_build_object(
    'referral_code', v_code,
    'available_credits', v_available,
    'referrals', v_referrals
  );
END;
$$;


--
-- Name: get_session_attendance(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_session_attendance(p_session_id uuid) RETURNS TABLE(id uuid, session_id uuid, trainee_id uuid, recorded_at timestamp with time zone, full_name text)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_caller_role  user_role;
  v_caller_id    UUID := auth.uid();
BEGIN
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: authentication required'
      USING ERRCODE = '28000';
  END IF;

  v_caller_role := (auth.jwt() -> 'user_metadata' ->> 'role')::user_role;

  IF v_caller_role IN ('admin', 'reception') THEN
    RETURN QUERY
      SELECT a.id, a.session_id, a.trainee_id, a.recorded_at, u.full_name
      FROM attendance a
      JOIN trainees t ON t.id = a.trainee_id
      JOIN users u    ON u.id = t.user_id
      WHERE a.session_id = p_session_id
      ORDER BY a.recorded_at DESC;
    RETURN;
  END IF;

  IF v_caller_role = 'trainee' THEN
    IF NOT EXISTS (
      SELECT 1
      FROM sessions s
      JOIN enrollments e ON e.cohort_id = s.cohort_id
      JOIN trainees t2   ON t2.id = e.trainee_id
      WHERE s.id = p_session_id
        AND t2.user_id = v_caller_id
    ) THEN
      RAISE EXCEPTION 'Forbidden: not enrolled in this session''s cohort'
        USING ERRCODE = '42501';
    END IF;

    RETURN QUERY
      SELECT a.id, a.session_id, a.trainee_id, a.recorded_at, u.full_name
      FROM attendance a
      JOIN trainees t ON t.id = a.trainee_id
      JOIN users u    ON u.id = t.user_id
      WHERE a.session_id = p_session_id
      ORDER BY a.recorded_at DESC;
    RETURN;
  END IF;

  RAISE EXCEPTION 'Forbidden: role not authorized for this operation'
    USING ERRCODE = '42501';
END;
$$;


--
-- Name: get_staff_referral_summary(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_staff_referral_summary(p_trainee_id uuid) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_code TEXT;
  v_name TEXT;
  v_available JSONB;
  v_referrals JSONB;
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM public.users u
    WHERE u.id = auth.uid()
      AND u.is_active = true
      AND u.role::text IN ('admin', 'reception')
  ) THEN
    RAISE EXCEPTION 'AUTH_REQUIRED' USING ERRCODE = 'P0001';
  END IF;

  SELECT t.trainee_code, u.full_name
  INTO v_code, v_name
  FROM public.trainees t
  JOIN public.users u ON u.id = t.user_id
  WHERE t.id = p_trainee_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'TRAINEE_NOT_FOUND' USING ERRCODE = 'P0001';
  END IF;

  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'currency', x.currency,
        'amount', x.total,
        'count', x.cnt
      )
      ORDER BY x.currency
    ),
    '[]'::jsonb
  )
  INTO v_available
  FROM (
    SELECT upper(btrim(r.currency)) AS currency,
           sum(r.discount_amount) AS total,
           count(*) AS cnt
    FROM public.referrals r
    WHERE r.referrer_trainee_id = p_trainee_id
      AND r.status = 'available'
    GROUP BY upper(btrim(r.currency))
  ) x;

  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'id', r.id,
        'referee_name', u.full_name,
        'course_name', co.name,
        'amount', r.discount_amount,
        'currency', r.currency,
        'status', r.status,
        'created_at', r.created_at,
        'applied_at', r.applied_at
      )
      ORDER BY r.created_at DESC
    ),
    '[]'::jsonb
  )
  INTO v_referrals
  FROM public.referrals r
  JOIN public.trainees t ON t.id = r.referee_trainee_id
  JOIN public.users u ON u.id = t.user_id
  JOIN public.courses co ON co.id = r.course_id
  WHERE r.referrer_trainee_id = p_trainee_id;

  RETURN jsonb_build_object(
    'trainee_id', p_trainee_id,
    'trainee_name', v_name,
    'referral_code', v_code,
    'available_credits', v_available,
    'referrals', v_referrals
  );
END;
$$;


--
-- Name: get_trainee_id(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_trainee_id() RETURNS uuid
    LANGUAGE sql STABLE
    AS $$
  SELECT id FROM trainees WHERE user_id = auth.uid();
$$;


--
-- Name: get_user_role(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_user_role() RETURNS public.user_role
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
  SELECT role
  FROM public.users
  WHERE id = auth.uid()
    AND is_active = true
  LIMIT 1;
$$;


--
-- Name: get_withdrawal_preview(uuid, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_withdrawal_preview(p_enrollment_id uuid, p_sessions_override integer DEFAULT NULL::integer) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_enr RECORD;
  v_fig RECORD;
  v_outcome TEXT;
BEGIN
  IF auth.uid() IS NOT NULL AND NOT public.c1_is_admin() THEN
    RAISE EXCEPTION 'ADMIN_ONLY' USING ERRCODE = 'P0001';
  END IF;

  SELECT e.id, e.trainee_id, e.lifecycle_status
  INTO v_enr
  FROM public.enrollments e
  WHERE e.id = p_enrollment_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'ENROLLMENT_NOT_FOUND' USING ERRCODE = 'P0001';
  END IF;

  IF v_enr.lifecycle_status <> 'active' THEN
    RETURN jsonb_build_object(
      'can_withdraw', false,
      'reason', 'ENROLLMENT_NOT_ACTIVE',
      'lifecycle_status', v_enr.lifecycle_status
    );
  END IF;

  SELECT * INTO v_fig
  FROM public.c1_withdrawal_figures(p_enrollment_id, p_sessions_override);

  v_outcome := CASE
                 WHEN v_fig.debt_amount > 0 THEN 'debt'
                 WHEN v_fig.refundable > 0 THEN 'refund'
                 ELSE 'settled'
               END;

  RETURN jsonb_build_object(
    'can_withdraw', true,
    'enrollment_id', p_enrollment_id,
    'trainee_id', v_fig.trainee_id,
    'currency', v_fig.currency,
    'course_name', v_fig.course_name,
    'cohort_name', v_fig.cohort_name,
    'lifecycle_status', v_fig.lifecycle_status,
    'total_sessions', v_fig.total_sessions,
    'sessions_charged', v_fig.delivered_sessions,
    'sessions_overridden', v_fig.sessions_overridden,
    'net_due_before', v_fig.net_due_before,
    'net_due_after', v_fig.net_due_after,
    'net_paid', v_fig.net_paid,
    'discount_revoked', v_fig.discount_revoked,
    'due_amount', v_fig.due_amount,
    'settlement_amount', v_fig.settlement_delta,
    'refundable', v_fig.refundable,
    'debt_amount', v_fig.debt_amount,
    'outcome', v_outcome
  );
END;
$$;


--
-- Name: handle_trainee_code_generation(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.handle_trainee_code_generation() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  -- إذا تم إدخال كود يدوي (مثل T10001) يتم حفظه كأحرف كبيرة
  IF NEW.trainee_code IS NOT NULL AND TRIM(NEW.trainee_code) <> '' THEN
    NEW.trainee_code := UPPER(TRIM(NEW.trainee_code));
  ELSE
    -- توليد تلقائي للجدد
    NEW.trainee_code := 'T' || nextval('public.trainee_code_seq')::TEXT;
  END IF;
  
  -- مزامنة الاسم العربي تلقائياً من users لو لم يُحدد
  IF NEW.full_name_ar IS NULL OR TRIM(NEW.full_name_ar) = '' THEN
    SELECT full_name INTO NEW.full_name_ar FROM public.users WHERE id = NEW.user_id;
  END IF;

  RETURN NEW;
END;
$$;


--
-- Name: has_user_pin(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.has_user_pin() RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN false;
  END IF;

  RETURN EXISTS (
    SELECT 1
    FROM public.user_pins up
    JOIN public.users u ON u.id = up.user_id
    WHERE up.user_id = auth.uid()
      AND u.is_active = true
  );
END;
$$;


--
-- Name: join_course_waitlist(uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.join_course_waitlist(p_cohort_id uuid, p_trainee_id uuid DEFAULT NULL::uuid) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_role TEXT;
  v_trainee_id UUID := p_trainee_id;
  v_capacity INTEGER;
  v_cohort_active BOOLEAN;
  v_course_active BOOLEAN;
  v_active_count INTEGER;
  v_existing_id UUID;
  v_existing_status TEXT;
  v_waitlist_id UUID;
  v_queue_position INTEGER;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'AUTH_REQUIRED' USING ERRCODE = 'P0001';
  END IF;

  SELECT u.role::TEXT
  INTO v_role
  FROM public.users u
  WHERE u.id = v_uid AND u.is_active = true;

  IF v_trainee_id IS NULL THEN
    SELECT t.id
    INTO v_trainee_id
    FROM public.trainees t
    WHERE t.user_id = v_uid;
  ELSIF v_role IS DISTINCT FROM 'admin' THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED' USING ERRCODE = 'P0001';
  END IF;

  IF v_trainee_id IS NULL
     OR NOT EXISTS (
       SELECT 1
       FROM public.trainees t
       JOIN public.users u ON u.id = t.user_id
       WHERE t.id = v_trainee_id
         AND u.is_active = true
     ) THEN
    RAISE EXCEPTION 'TRAINEE_NOT_FOUND' USING ERRCODE = 'P0001';
  END IF;

  SELECT c.capacity, c.is_active, co.is_active
  INTO v_capacity, v_cohort_active, v_course_active
  FROM public.cohorts c
  JOIN public.courses co ON co.id = c.course_id
  WHERE c.id = p_cohort_id
  FOR UPDATE OF c;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'COHORT_NOT_FOUND' USING ERRCODE = 'P0001';
  END IF;

  IF NOT v_cohort_active OR NOT v_course_active THEN
    RAISE EXCEPTION 'COHORT_NOT_ACTIVE' USING ERRCODE = 'P0001';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.enrollments e
    WHERE e.cohort_id = p_cohort_id
      AND e.trainee_id = v_trainee_id
      AND public.enrollment_lifecycle_occupies_seat(e.lifecycle_status)
  ) THEN
    RAISE EXCEPTION 'ALREADY_ENROLLED' USING ERRCODE = 'P0001';
  END IF;

  SELECT w.id, w.status
  INTO v_existing_id, v_existing_status
  FROM public.course_waitlist w
  WHERE w.cohort_id = p_cohort_id
    AND w.trainee_id = v_trainee_id
    AND w.status IN ('waiting', 'notified')
  LIMIT 1;

  IF FOUND THEN
    RETURN jsonb_build_object(
      'waitlist_id', v_existing_id,
      'status', v_existing_status,
      'already_joined', true
    );
  END IF;

  v_active_count := public.cohort_active_enrollment_count(p_cohort_id);

  IF v_capacity IS NULL OR v_active_count < v_capacity THEN
    RAISE EXCEPTION 'COHORT_HAS_AVAILABLE_SEATS' USING ERRCODE = 'P0001';
  END IF;

  INSERT INTO public.course_waitlist (
    cohort_id,
    trainee_id,
    status,
    created_by
  ) VALUES (
    p_cohort_id,
    v_trainee_id,
    'waiting',
    v_uid
  )
  RETURNING id INTO v_waitlist_id;

  SELECT count(*) + 1
  INTO v_queue_position
  FROM public.course_waitlist w
  WHERE w.cohort_id = p_cohort_id
    AND w.status IN ('waiting', 'notified')
    AND w.id <> v_waitlist_id;

  RETURN jsonb_build_object(
    'waitlist_id', v_waitlist_id,
    'status', 'waiting',
    'already_joined', false,
    'queue_position', v_queue_position
  );
END;
$$;


--
-- Name: lab_invoice_item_calc_total(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.lab_invoice_item_calc_total() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.total_price := ROUND((NEW.quantity * NEW.unit_price)::numeric, 2);
    RETURN NEW;
END;
$$;


--
-- Name: lab_invoice_set_number(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.lab_invoice_set_number() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF NEW.invoice_number IS NULL OR NEW.invoice_number <= 0 THEN
        NEW.invoice_number := nextval('public.lab_invoice_number_seq');
    END IF;
    RETURN NEW;
END;
$$;


--
-- Name: notify_next_waitlist(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.notify_next_waitlist(p_cohort_id uuid) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_capacity INTEGER;
  v_active_count INTEGER;
  v_waitlist RECORD;
  v_course_name TEXT;
  v_cohort_name TEXT;
  v_now TIMESTAMPTZ := now();
  v_expires_at TIMESTAMPTZ := now() + interval '24 hours';
  v_dedupe_key TEXT;
BEGIN
  SELECT c.capacity, co.name, c.name
  INTO v_capacity, v_course_name, v_cohort_name
  FROM public.cohorts c
  JOIN public.courses co ON co.id = c.course_id
  WHERE c.id = p_cohort_id
    AND c.is_active = true
    AND co.is_active = true
  FOR UPDATE OF c;

  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  UPDATE public.course_waitlist w
  SET status = 'cancelled',
      cancelled_at = v_now,
      updated_at = v_now
  WHERE w.cohort_id = p_cohort_id
    AND w.status IN ('waiting', 'notified')
    AND EXISTS (
      SELECT 1
      FROM public.enrollments e
      WHERE e.cohort_id = w.cohort_id
        AND e.trainee_id = w.trainee_id
        AND public.enrollment_lifecycle_occupies_seat(e.lifecycle_status)
    );

  UPDATE public.course_waitlist
  SET status = 'expired',
      updated_at = v_now
  WHERE cohort_id = p_cohort_id
    AND status = 'notified'
    AND expires_at IS NOT NULL
    AND expires_at <= v_now;

  v_active_count := public.cohort_active_enrollment_count(p_cohort_id);

  IF v_capacity IS NOT NULL AND v_active_count >= v_capacity THEN
    RETURN NULL;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.course_waitlist w
    WHERE w.cohort_id = p_cohort_id
      AND w.status = 'notified'
      AND (w.expires_at IS NULL OR w.expires_at > v_now)
  ) THEN
    RETURN NULL;
  END IF;

  SELECT w.*
  INTO v_waitlist
  FROM public.course_waitlist w
  JOIN public.trainees t ON t.id = w.trainee_id
  JOIN public.users u ON u.id = t.user_id AND u.is_active = true
  WHERE w.cohort_id = p_cohort_id
    AND w.status = 'waiting'
    AND NOT EXISTS (
      SELECT 1
      FROM public.enrollments e
      WHERE e.cohort_id = w.cohort_id
        AND e.trainee_id = w.trainee_id
        AND public.enrollment_lifecycle_occupies_seat(e.lifecycle_status)
    )
  ORDER BY w.joined_at ASC, w.id ASC
  LIMIT 1
  FOR UPDATE OF w;

  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  UPDATE public.course_waitlist
  SET status = 'notified',
      notified_at = v_now,
      expires_at = v_expires_at,
      updated_at = v_now
  WHERE id = v_waitlist.id;

  v_dedupe_key := 'waitlist_available:' || v_waitlist.id::text || ':' ||
                  to_char(v_now AT TIME ZONE 'UTC', 'YYYYMMDDHH24MISSUS');

  INSERT INTO public.notification_outbox (
    user_id,
    type,
    title,
    body,
    data,
    dedupe_key
  )
  SELECT
    t.user_id,
    'waitlist_available',
    'مقعد متاح في دورة تدريبية',
    'أصبح هناك مقعد متاح في ' || v_course_name || ' — ' || v_cohort_name ||
      '. يرجى التواصل مع الإدارة لتثبيت التسجيل.',
    jsonb_build_object(
      'type', 'waitlist_available',
      'cohort_id', p_cohort_id,
      'waitlist_id', v_waitlist.id,
      'route', '/courses'
    ),
    v_dedupe_key
  FROM public.trainees t
  WHERE t.id = v_waitlist.trainee_id;

  RETURN v_waitlist.id;
END;
$$;


--
-- Name: open_session(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.open_session(p_session_id uuid) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_role text;
  v_qr uuid;
BEGIN
  v_role := public.c1_staff_role();

  IF v_role IS NULL OR v_role NOT IN ('admin', 'reception') THEN
    RAISE EXCEPTION 'غير مصرح: فتح الجلسة مخصص للإدارة والاستقبال فقط';
  END IF;

  IF p_session_id IS NULL THEN
    RAISE EXCEPTION 'معرف الجلسة مطلوب';
  END IF;

  v_qr := gen_random_uuid();

  UPDATE public.sessions
  SET status = 'open',
      qr_token = v_qr,
      opened_at = now(),
      opened_by = auth.uid()
  WHERE id = p_session_id AND status = 'scheduled';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'الجلسة غير موجودة أو ليست بحالة مجدولة';
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'session_id', p_session_id,
    'qr_token', v_qr,
    'opened_at', now()
  );
END;
$$;


--
-- Name: preview_referral_code(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.preview_referral_code(p_code text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_code TEXT := NULLIF(upper(btrim(COALESCE(p_code, ''))), '');
  v_row RECORD;
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM public.users u
    WHERE u.id = auth.uid()
      AND u.is_active = true
      AND u.role::text IN ('admin', 'reception')
  ) THEN
    RAISE EXCEPTION 'AUTH_REQUIRED' USING ERRCODE = 'P0001';
  END IF;

  IF v_code IS NULL THEN
    RETURN jsonb_build_object('valid', false, 'error', 'REFERRAL_CODE_INVALID');
  END IF;

  SELECT t.id, u.full_name, u.is_active
  INTO v_row
  FROM public.trainees t
  JOIN public.users u ON u.id = t.user_id
  WHERE upper(btrim(t.trainee_code)) = v_code;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('valid', false, 'error', 'REFERRAL_CODE_INVALID');
  END IF;

  IF NOT v_row.is_active THEN
    RETURN jsonb_build_object('valid', false, 'error', 'REFERRAL_REFERRER_INACTIVE');
  END IF;

  RETURN jsonb_build_object(
    'valid', true,
    'referrer_trainee_id', v_row.id,
    'referrer_name', v_row.full_name
  );
END;
$$;


--
-- Name: promote_waitlist_trainee(uuid, numeric, numeric, text, text, numeric); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.promote_waitlist_trainee(p_waitlist_id uuid, p_total_due numeric, p_discount_amount numeric DEFAULT 0, p_currency text DEFAULT 'SYP'::text, p_referral_code text DEFAULT NULL::text, p_referral_discount_amount numeric DEFAULT NULL::numeric) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_role TEXT;
  v_cohort_id UUID;
  v_row RECORD;
  v_capacity INTEGER;
  v_active_count INTEGER;
  v_enrollment_id UUID;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'AUTH_REQUIRED' USING ERRCODE = 'P0001';
  END IF;

  SELECT u.role::TEXT
  INTO v_role
  FROM public.users u
  WHERE u.id = v_uid AND u.is_active = true;

  IF v_role IS DISTINCT FROM 'admin' THEN
    RAISE EXCEPTION 'ADMIN_ONLY' USING ERRCODE = 'P0001';
  END IF;

  IF p_total_due IS NULL OR p_total_due < 0 THEN
    RAISE EXCEPTION 'INVALID_TOTAL_DUE' USING ERRCODE = 'P0001';
  END IF;

  IF p_discount_amount IS NULL OR p_discount_amount < 0 THEN
    RAISE EXCEPTION 'INVALID_DISCOUNT' USING ERRCODE = 'P0001';
  END IF;

  IF p_currency IS NULL OR length(trim(p_currency)) = 0 THEN
    RAISE EXCEPTION 'INVALID_CURRENCY' USING ERRCODE = 'P0001';
  END IF;

  IF p_referral_discount_amount IS NOT NULL AND p_referral_discount_amount < 0 THEN
    RAISE EXCEPTION 'INVALID_DISCOUNT' USING ERRCODE = 'P0001';
  END IF;

  SELECT w.cohort_id
  INTO v_cohort_id
  FROM public.course_waitlist w
  WHERE w.id = p_waitlist_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'WAITLIST_NOT_FOUND' USING ERRCODE = 'P0001';
  END IF;

  PERFORM 1
  FROM public.cohorts c
  WHERE c.id = v_cohort_id
  FOR UPDATE;

  SELECT w.*
  INTO v_row
  FROM public.course_waitlist w
  WHERE w.id = p_waitlist_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'WAITLIST_NOT_FOUND' USING ERRCODE = 'P0001';
  END IF;

  IF v_row.status NOT IN ('waiting', 'notified') THEN
    RAISE EXCEPTION 'WAITLIST_NOT_ACTIVE' USING ERRCODE = 'P0001';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.trainees t
    JOIN public.users u ON u.id = t.user_id
    WHERE t.id = v_row.trainee_id
      AND u.is_active = true
  ) THEN
    RAISE EXCEPTION 'TRAINEE_NOT_FOUND' USING ERRCODE = 'P0001';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.enrollments e
    WHERE e.cohort_id = v_cohort_id
      AND e.trainee_id = v_row.trainee_id
      AND public.enrollment_lifecycle_occupies_seat(e.lifecycle_status)
  ) THEN
    RAISE EXCEPTION 'ALREADY_ENROLLED' USING ERRCODE = 'P0001';
  END IF;

  SELECT c.capacity
  INTO v_capacity
  FROM public.cohorts c
  WHERE c.id = v_cohort_id;

  v_active_count := public.cohort_active_enrollment_count(v_cohort_id);

  IF v_capacity IS NOT NULL AND v_active_count >= v_capacity THEN
    RAISE EXCEPTION 'COHORT_CAPACITY_REACHED'
      USING ERRCODE = 'P0001',
            DETAIL = format('cohort=%s active=%s capacity=%s',
                            v_cohort_id, v_active_count, v_capacity);
  END IF;

  INSERT INTO public.enrollments (
    trainee_id,
    cohort_id,
    total_due,
    discount_amount,
    currency,
    created_by,
    referral_code,
    referral_discount_amount
  ) VALUES (
    v_row.trainee_id,
    v_cohort_id,
    p_total_due,
    p_discount_amount,
    trim(p_currency),
    v_uid,
    NULLIF(upper(btrim(COALESCE(p_referral_code, ''))), ''),
    COALESCE(p_referral_discount_amount, 0)
  )
  RETURNING id INTO v_enrollment_id;

  UPDATE public.course_waitlist
  SET status = 'enrolled',
      promoted_at = now(),
      promoted_by = v_uid,
      updated_at = now()
  WHERE id = p_waitlist_id;

  BEGIN
    PERFORM public.notify_next_waitlist(v_cohort_id);
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'waitlist notify skipped after promotion for cohort %: %',
                  v_cohort_id, SQLERRM;
  END;

  RETURN jsonb_build_object(
    'enrollment_id', v_enrollment_id,
    'waitlist_id', p_waitlist_id,
    'status', 'enrolled'
  );
END;
$$;


--
-- Name: recalculate_lab_invoice(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.recalculate_lab_invoice(p_invoice_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
    v_subtotal NUMERIC(12, 2);
    v_discount NUMERIC(12, 2);
    v_total NUMERIC(12, 2);
    v_paid NUMERIC(12, 2);
    v_status TEXT;
    v_current_status TEXT;
BEGIN
    SELECT COALESCE(SUM(total_price), 0.00)
    INTO v_subtotal
    FROM public.lab_invoice_items
    WHERE invoice_id = p_invoice_id;

    SELECT COALESCE(discount, 0.00), status
    INTO v_discount, v_current_status
    FROM public.lab_invoices
    WHERE id = p_invoice_id;

    IF v_current_status = 'cancelled' THEN
        v_status := 'cancelled';
    ELSE
        v_total := GREATEST(ROUND((v_subtotal - v_discount)::numeric, 2), 0.00);

        SELECT COALESCE(SUM(amount), 0.00)
        INTO v_paid
        FROM public.lab_payments
        WHERE invoice_id = p_invoice_id;

        IF v_total > 0 AND v_paid >= v_total THEN
            v_status := 'paid';
        ELSIF v_paid > 0 THEN
            v_status := 'partial';
        ELSE
            v_status := 'unpaid';
        END IF;
    END IF;

    UPDATE public.lab_invoices
    SET
        subtotal = v_subtotal,
        total_amount = GREATEST(ROUND((v_subtotal - v_discount)::numeric, 2), 0.00),
        paid_amount = (SELECT COALESCE(SUM(amount), 0.00) FROM public.lab_payments WHERE invoice_id = p_invoice_id),
        status = v_status,
        updated_at = timezone('utc'::text, now())
    WHERE id = p_invoice_id;
END;
$$;


--
-- Name: register_fcm_token(text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.register_fcm_token(p_fcm_token text, p_device_type text DEFAULT 'android'::text, p_device_id text DEFAULT NULL::text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_uid UUID := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  IF p_fcm_token IS NULL OR trim(p_fcm_token) = '' THEN
    RAISE EXCEPTION 'FCM token cannot be empty';
  END IF;

  INSERT INTO public.user_fcm_tokens (
    user_id,
    fcm_token,
    device_type,
    device_id,
    is_active,
    last_seen_at,
    updated_at
  ) VALUES (
    v_uid,
    trim(p_fcm_token),
    COALESCE(p_device_type, 'android'),
    p_device_id,
    true,
    now(),
    now()
  )
  ON CONFLICT (fcm_token) DO UPDATE SET
    user_id = EXCLUDED.user_id,
    device_type = EXCLUDED.device_type,
    device_id = COALESCE(EXCLUDED.device_id, public.user_fcm_tokens.device_id),
    is_active = true,
    last_seen_at = now(),
    updated_at = now();
END;
$$;


--
-- Name: set_installment_plan(uuid, jsonb, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.set_installment_plan(p_enrollment_id uuid, p_installments jsonb, p_notes text DEFAULT NULL::text) RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
    v_enr       record;
    v_paid      numeric(12,2);
    v_net       numeric(12,2);
    v_count     integer;
    v_sum       numeric(12,2) := 0;
    v_amount    numeric(12,2);
    v_due       date;
    v_i         integer;
    v_payment   record;
BEGIN
    IF NOT public.c1_is_staff() THEN
        RAISE EXCEPTION 'إعادة تخطيط الأقساط متاح لموظفي المركز فقط';
    END IF;

    PERFORM pg_advisory_xact_lock(
        hashtextextended('c1_plan:' || p_enrollment_id::text, 0)
    );

    SELECT e.id, e.currency, e.status::text AS status,
           COALESCE(e.total_due, 0) - COALESCE(e.discount_amount, 0) +
           COALESCE((SELECT sum(fa.amount) FROM public.fee_adjustments fa
                     WHERE fa.enrollment_id = e.id), 0) AS net
    INTO v_enr
    FROM public.enrollments e
    WHERE e.id = p_enrollment_id;

    IF v_enr.id IS NULL THEN
        RAISE EXCEPTION 'التسجيل غير موجود';
    END IF;

    IF NOT public.enrollment_status_occupies_seat(v_enr.status) THEN
        RAISE EXCEPTION 'لا يمكن إعادة تخطيط أقساط تسجيل بحالة (%)', v_enr.status;
    END IF;

    v_net := v_enr.net;
    IF v_net <= 0 THEN
        RAISE EXCEPTION 'صافي الرسوم (%) لا يسمح بإنشاء خطة أقساط', v_net;
    END IF;

    SELECT COALESCE(sum(p.amount), 0) - COALESCE((
        SELECT sum(rf.amount) FROM public.payment_refunds rf
        JOIN public.payments p2 ON p2.id = rf.payment_id
        WHERE p2.enrollment_id = p_enrollment_id
    ), 0)
    INTO v_paid
    FROM public.payments p
    WHERE p.enrollment_id = p_enrollment_id;

    IF jsonb_typeof(p_installments) <> 'array' THEN
        RAISE EXCEPTION 'خطة الأقساط يجب أن تكون مصفوفة JSON';
    END IF;

    v_count := jsonb_array_length(p_installments);
    IF v_count <= 0 THEN
        RAISE EXCEPTION 'يجب تحديد قسط واحد على الأقل';
    END IF;

    FOR v_i IN 0 .. v_count - 1 LOOP
        v_amount := NULLIF(p_installments -> v_i ->> 'amount', '')::numeric;
        v_due    := NULLIF(p_installments -> v_i ->> 'due_date', '')::date;

        IF v_amount IS NULL OR v_amount <= 0 THEN
            RAISE EXCEPTION 'مبلغ القسط % غير صالح', v_i + 1;
        END IF;
        IF v_due IS NULL THEN
            RAISE EXCEPTION 'تاريخ استحقاق القسط % غير صالح', v_i + 1;
        END IF;

        v_sum := v_sum + v_amount;
    END LOOP;

    IF round(v_sum, 2) <> round(v_net, 2) THEN
        RAISE EXCEPTION 'مجموع الأقساط (%) لا يطابق صافي الرسوم (%)', v_sum, v_net;
    END IF;

    PERFORM set_config('c1.replanning', 'on', true);
    DELETE FROM public.installment_schedule s WHERE s.enrollment_id = p_enrollment_id;

    FOR v_i IN 0 .. v_count - 1 LOOP
        INSERT INTO public.installment_schedule
          (enrollment_id, installment_number, due_date, amount, currency, notes, created_by)
        VALUES
          (p_enrollment_id,
           v_i + 1,
           (p_installments -> v_i ->> 'due_date')::date,
           (p_installments -> v_i ->> 'amount')::numeric,
           v_enr.currency,
           COALESCE(p_notes, 'خطة أقساط معدّلة يدوياً'),
           auth.uid());
    END LOOP;
    PERFORM set_config('c1.replanning', '', true);

    FOR v_payment IN
        SELECT p.id FROM public.payments p
        WHERE p.enrollment_id = p_enrollment_id
          AND p.currency::text = v_enr.currency::text
        ORDER BY p.paid_at NULLS LAST, p.id
    LOOP
        PERFORM public.c1_allocate_payment(v_payment.id);
    END LOOP;

    RETURN v_count;
END;
$$;


--
-- Name: set_monthly_target(numeric, numeric, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.set_monthly_target(p_target_syp numeric, p_target_usd numeric, p_month_key text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
    v_month text;
    v_user_role text;
    v_res record;
BEGIN
    SELECT role INTO v_user_role FROM public.users WHERE id = auth.uid() AND is_active = true;
    IF v_user_role IS DISTINCT FROM 'admin' THEN
        RAISE EXCEPTION 'غير مصرح: تحديد الهدف المالي مخصص لمدير النظام فقط';
    END IF;

    v_month := COALESCE(p_month_key, to_char(now() AT TIME ZONE 'Asia/Damascus', 'YYYY-MM'));

    INSERT INTO public.monthly_targets (month_key, target_syp, target_usd, updated_at, updated_by)
    VALUES (
        v_month,
        GREATEST(COALESCE(p_target_syp, 0), 0),
        GREATEST(COALESCE(p_target_usd, 0), 0),
        now(),
        auth.uid()
    )
    ON CONFLICT (month_key) DO UPDATE
    SET target_syp = EXCLUDED.target_syp,
        target_usd = EXCLUDED.target_usd,
        updated_at = now(),
        updated_by = auth.uid()
    RETURNING * INTO v_res;

    RETURN to_jsonb(v_res);
END;
$$;


--
-- Name: set_user_pin(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.set_user_pin(p_pin text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $_$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'غير مصرح: يجب تسجيل الدخول لتعيين رمز PIN';
  END IF;

  IF p_pin IS NULL
     OR length(p_pin) NOT BETWEEN 4 AND 6
     OR p_pin !~ '^[0-9]+$' THEN
    RAISE EXCEPTION 'رمز الـ PIN يجب أن يتكون من 4 إلى 6 أرقام فقط';
  END IF;

  INSERT INTO public.user_pins (user_id, pin_hash)
  VALUES (auth.uid(), crypt(p_pin, gen_salt('bf', 8)))
  ON CONFLICT (user_id) DO UPDATE
    SET pin_hash  = EXCLUDED.pin_hash,
        updated_at = now();

  RETURN jsonb_build_object('success', true, 'message', 'تم حفظ رمز PIN بنجاح');
END;
$_$;


--
-- Name: shift_cohort_sessions(uuid, date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.shift_cohort_sessions(p_cohort_id uuid, p_new_start_date date) RETURNS json
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_role text;
  v_is_active boolean;
  v_first_scheduled_date date;
  v_day_delta integer;
  v_has_executed_sessions boolean;
  v_last_executed_date date;
  v_shifted_count integer;
BEGIN
  SELECT role, is_active INTO v_role, v_is_active
  FROM public.users
  WHERE id = auth.uid();

  IF v_role IS NULL OR v_is_active IS NOT TRUE OR v_role NOT IN ('admin', 'reception') THEN
    RAISE EXCEPTION 'غير مصرح لك بترحيل مواعيد الجلسات';
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM public.sessions
    WHERE cohort_id = p_cohort_id
      AND status IN ('open', 'closed')
  ) INTO v_has_executed_sessions;

  IF v_has_executed_sessions THEN
    SELECT max((scheduled_at AT TIME ZONE 'Asia/Damascus')::date) INTO v_last_executed_date
    FROM public.sessions
    WHERE cohort_id = p_cohort_id
      AND status IN ('open', 'closed');

    IF p_new_start_date <= v_last_executed_date THEN
      RAISE EXCEPTION 'تاريخ البدء الجديد (%) يجب أن يكون بعد تاريخ آخر جلسة منفذة (%)',
        p_new_start_date, v_last_executed_date;
    END IF;
  END IF;

  SELECT min((scheduled_at AT TIME ZONE 'Asia/Damascus')::date) INTO v_first_scheduled_date
  FROM public.sessions
  WHERE cohort_id = p_cohort_id
    AND status = 'scheduled';

  IF v_first_scheduled_date IS NULL THEN
    RAISE EXCEPTION 'لا توجد جلسات مجدولة متبقية لترحيلها في هذه الدفعة';
  END IF;

  v_day_delta := p_new_start_date - v_first_scheduled_date;

  IF v_day_delta = 0 THEN
    RETURN json_build_object(
      'success', true,
      'shifted_sessions_count', 0,
      'day_delta', 0,
      'message', 'التاريخ المختار هو نفس تاريخ أول جلسة مجدولة حالياً، لم يتم ترحيل أي جلسة.'
    );
  END IF;

  UPDATE public.sessions
  SET scheduled_at = (
        (scheduled_at AT TIME ZONE 'Asia/Damascus') + make_interval(days => v_day_delta)
      ) AT TIME ZONE 'Asia/Damascus'
  WHERE cohort_id = p_cohort_id
    AND status = 'scheduled';

  GET DIAGNOSTICS v_shifted_count = ROW_COUNT;

  IF NOT v_has_executed_sessions THEN
    UPDATE public.cohorts
    SET starts_at = p_new_start_date
    WHERE id = p_cohort_id;
  END IF;

  RETURN json_build_object(
    'success', true,
    'shifted_sessions_count', v_shifted_count,
    'day_delta', v_day_delta,
    'message', format('تم ترحيل %s جلسة مجدولة بنجاح بفارق %s يوم.', v_shifted_count, v_day_delta)
  );
END;
$$;


--
-- Name: submit_survey_response(uuid, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.submit_survey_response(p_dispatch_id uuid, p_answers jsonb) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_dispatch UUID;
BEGIN
  SELECT sd.id INTO v_dispatch
  FROM public.survey_dispatches sd
  JOIN public.enrollments e ON e.id = sd.enrollment_id
  JOIN public.trainees t ON t.id = e.trainee_id
  WHERE sd.id = p_dispatch_id 
    AND t.user_id = auth.uid();

  IF v_dispatch IS NULL THEN
    RAISE EXCEPTION 'غير مصرح: هذا الاستبيان غير مخصص لك أو انتهت صلاحيته';
  END IF;

  INSERT INTO public.survey_responses (dispatch_id, answers)
  VALUES (p_dispatch_id, p_answers)
  ON CONFLICT (dispatch_id) DO UPDATE
    SET answers = EXCLUDED.answers;

  UPDATE public.survey_dispatches
  SET status = 'answered',
      answered_at = NOW()
  WHERE id = p_dispatch_id;
END;
$$;


--
-- Name: trg_fn_autoclose_waitlist_on_enrollment(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trg_fn_autoclose_waitlist_on_enrollment() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_promoted_by UUID;
BEGIN
  IF NOT public.enrollment_lifecycle_occupies_seat(NEW.lifecycle_status) THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'UPDATE'
     AND OLD.cohort_id = NEW.cohort_id
     AND public.enrollment_lifecycle_occupies_seat(OLD.lifecycle_status) THEN
    RETURN NEW;
  END IF;

  v_promoted_by := COALESCE(auth.uid(), NEW.created_by);

  IF v_promoted_by IS NOT NULL THEN
    UPDATE public.course_waitlist
    SET status = 'enrolled',
        promoted_at = now(),
        promoted_by = v_promoted_by,
        cancelled_at = NULL,
        updated_at = now()
    WHERE cohort_id = NEW.cohort_id
      AND trainee_id = NEW.trainee_id
      AND status IN ('waiting', 'notified');
  ELSE
    UPDATE public.course_waitlist
    SET status = 'cancelled',
        cancelled_at = now(),
        updated_at = now()
    WHERE cohort_id = NEW.cohort_id
      AND trainee_id = NEW.trainee_id
      AND status IN ('waiting', 'notified');
  END IF;

  RETURN NEW;
END;
$$;


--
-- Name: trg_fn_c1_adjustment_apply(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trg_fn_c1_adjustment_apply() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
    v_enrollment_id uuid;
    v_delta         numeric(12,2);
BEGIN
    IF auth.uid() IS NOT NULL AND NOT public.c1_is_admin() THEN
        RAISE EXCEPTION 'تعديل الرسوم متاح لمدير المركز فقط';
    END IF;

    IF TG_OP = 'UPDATE' THEN
        RAISE EXCEPTION 'لا يمكن تعديل قيد رسوم صادر: احذفه وأنشئ قيداً معاكساً';
    END IF;

    IF TG_OP = 'DELETE' THEN
        v_enrollment_id := OLD.enrollment_id;
        v_delta := -OLD.amount;
    ELSE
        v_enrollment_id := NEW.enrollment_id;
        v_delta := NEW.amount;
    END IF;

    PERFORM public.c1_apply_plan_delta(v_enrollment_id, v_delta);

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$$;


--
-- Name: trg_fn_c1_adjustment_status_sync(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trg_fn_c1_adjustment_status_sync() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_enrollment_id uuid;
BEGIN
  IF TG_OP = 'DELETE' THEN
    v_enrollment_id := OLD.enrollment_id;
  ELSE
    v_enrollment_id := NEW.enrollment_id;
  END IF;

  PERFORM public.c1_refresh_enrollment_status(v_enrollment_id);

  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: trg_fn_c1_default_installment(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trg_fn_c1_default_installment() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
    v_net   numeric(12,2);
    v_due   date;
    v_start date;
BEGIN
    v_net := COALESCE(NEW.total_due, 0) - COALESCE(NEW.discount_amount, 0);
    IF v_net <= 0 THEN RETURN NEW; END IF;

    IF NEW.currency IS NULL THEN
        RAISE EXCEPTION 'لا يمكن إنشاء خطة أقساط لتسجيل بلا عملة';
    END IF;

    SELECT c.starts_at::date INTO v_start
    FROM public.cohorts c WHERE c.id = NEW.cohort_id;

    v_due := GREATEST(
        COALESCE(v_start, (now() AT TIME ZONE 'Asia/Damascus')::date),
        (now() AT TIME ZONE 'Asia/Damascus')::date
    );

    INSERT INTO public.installment_schedule
      (enrollment_id, installment_number, due_date, amount, currency, notes, created_by)
    VALUES
      (NEW.id, 1, v_due, v_net, NEW.currency,
       'قسط افتراضي آلي (Phase C1)', auth.uid())
    ON CONFLICT (enrollment_id, installment_number) DO NOTHING;

    RETURN NEW;
END;
$$;


--
-- Name: trg_fn_c1_enrollment_fee_changed(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trg_fn_c1_enrollment_fee_changed() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
    v_old_net numeric(12,2);
    v_new_net numeric(12,2);
BEGIN
    IF NEW.total_due IS NOT DISTINCT FROM OLD.total_due
       AND NEW.discount_amount IS NOT DISTINCT FROM OLD.discount_amount THEN
        RETURN NEW;
    END IF;

    IF NOT public.enrollment_status_occupies_seat(NEW.status::text) THEN
        RETURN NEW;
    END IF;

    v_old_net := COALESCE(OLD.total_due, 0) - COALESCE(OLD.discount_amount, 0);
    v_new_net := COALESCE(NEW.total_due, 0) - COALESCE(NEW.discount_amount, 0);

    IF v_new_net IS DISTINCT FROM v_old_net THEN
        PERFORM public.c1_apply_plan_delta(NEW.id, v_new_net - v_old_net);
    END IF;

    RETURN NEW;
END;
$$;


--
-- Name: trg_fn_c1_installment_guard(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trg_fn_c1_installment_guard() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
    v_currency  text;
    v_status    text;
    v_allocated numeric(12,2);
BEGIN
    IF current_setting('c1.replanning', true) = 'on' THEN
        IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
        RETURN NEW;
    END IF;

    IF TG_OP = 'INSERT' THEN
        SELECT e.currency::text, e.status::text INTO v_currency, v_status
        FROM public.enrollments e WHERE e.id = NEW.enrollment_id;

        IF v_currency IS NULL THEN
            RAISE EXCEPTION 'التسجيل غير موجود';
        END IF;
        IF NEW.currency::text IS DISTINCT FROM v_currency THEN
            RAISE EXCEPTION 'عملة القسط (%) لا تطابق عملة التسجيل (%)',
                NEW.currency, v_currency;
        END IF;
        IF NOT public.enrollment_status_occupies_seat(v_status) THEN
            RAISE EXCEPTION 'لا يمكن إنشاء أقساط لتسجيل بحالة (%)', v_status;
        END IF;
        RETURN NEW;
    END IF;

    IF TG_OP = 'UPDATE' THEN
        IF NEW.enrollment_id IS DISTINCT FROM OLD.enrollment_id THEN
            RAISE EXCEPTION 'لا يمكن نقل القسط إلى تسجيل آخر';
        END IF;
        IF NEW.currency IS DISTINCT FROM OLD.currency THEN
            RAISE EXCEPTION 'لا يمكن تغيير عملة القسط';
        END IF;

        SELECT COALESCE(sum(a.amount), 0) INTO v_allocated
        FROM public.payment_allocations a
        WHERE a.installment_id = NEW.id;

        IF NEW.amount < v_allocated THEN
            RAISE EXCEPTION 'لا يمكن إنقاص القسط إلى ما دون المبلغ المخصص له (%)', v_allocated;
        END IF;
        RETURN NEW;
    END IF;

    IF TG_OP = 'DELETE' THEN
        IF EXISTS (SELECT 1 FROM public.payment_allocations a WHERE a.installment_id = OLD.id) THEN
            RAISE EXCEPTION 'لا يمكن حذف قسط مخصص له دفعات';
        END IF;
        RETURN OLD;
    END IF;

    RETURN NEW;
END;
$$;


--
-- Name: trg_fn_c1_payment_write_guard(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trg_fn_c1_payment_write_guard() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
BEGIN
  IF auth.uid() IS NOT NULL AND NOT public.c1_is_admin() THEN
    IF TG_OP = 'DELETE' THEN
      RAISE EXCEPTION 'حذف الدفعة متاح لمدير المركز فقط';
    END IF;
  END IF;

  IF TG_OP = 'DELETE' THEN
    IF EXISTS (
      SELECT 1 FROM public.payment_refunds r WHERE r.payment_id = OLD.id
    ) THEN
      RAISE EXCEPTION 'لا يمكن حذف دفعة عليها استردادات: احذف الاستردادات أولاً';
    END IF;
    RETURN OLD;
  END IF;

  IF NEW.amount IS DISTINCT FROM OLD.amount
     OR NEW.currency IS DISTINCT FROM OLD.currency
     OR NEW.enrollment_id IS DISTINCT FROM OLD.enrollment_id THEN
    RAISE EXCEPTION 'لا يمكن تعديل مبلغ أو عملة أو تسجيل دفعة صادرة: احذفها وأعد تسجيلها';
  END IF;

  RETURN NEW;
END;
$$;


--
-- Name: trg_fn_c1_payments_after(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trg_fn_c1_payments_after() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
BEGIN
    PERFORM public.c1_allocate_payment(NEW.id);
    RETURN NEW;
END;
$$;


--
-- Name: trg_fn_c1_payments_guard(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trg_fn_c1_payments_guard() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
    v_enr record;
BEGIN
    IF NEW.amount IS NULL OR NEW.amount <= 0 THEN
        RAISE EXCEPTION 'مبلغ الدفعة يجب أن يكون أكبر من صفر';
    END IF;

    SELECT e.id, e.currency::text AS currency, e.status::text AS status
    INTO v_enr
    FROM public.enrollments e WHERE e.id = NEW.enrollment_id;

    IF v_enr.id IS NULL THEN
        RAISE EXCEPTION 'الدفعة يجب أن ترتبط بتسجيل صالح';
    END IF;

    IF NEW.currency::text IS DISTINCT FROM v_enr.currency THEN
        RAISE EXCEPTION 'عملة الدفعة (%) لا تطابق عملة التسجيل (%): الدفع بعملة مختلفة ممنوع',
            NEW.currency, v_enr.currency;
    END IF;

    IF TG_OP = 'INSERT' THEN
        RETURN NEW;
    END IF;

    IF (NEW.amount IS DISTINCT FROM OLD.amount
        OR NEW.currency IS DISTINCT FROM OLD.currency)
       AND EXISTS (SELECT 1 FROM public.payment_refunds rf WHERE rf.payment_id = OLD.id) THEN
        RAISE EXCEPTION 'لا يمكن تعديل مبلغ أو عملة دفعة صدر عنها استرداد';
    END IF;

    IF NEW.enrollment_id IS DISTINCT FROM OLD.enrollment_id THEN
        IF EXISTS (SELECT 1 FROM public.payment_allocations pa WHERE pa.payment_id = OLD.id) THEN
            RAISE EXCEPTION 'لا يمكن نقل دفعة مخصصة إلى تسجيل آخر';
        END IF;
    END IF;

    RETURN NEW;
END;
$$;


--
-- Name: trg_fn_c1_plan_total(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trg_fn_c1_plan_total() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
    v_enrollment_id uuid;
    v_net           numeric(12,2);
    v_sum           numeric(12,2);
    v_status        text;
BEGIN
    IF current_setting('c1.replanning', true) = 'on' THEN
        RETURN NULL;
    END IF;

    IF TG_OP = 'DELETE' THEN
        v_enrollment_id := OLD.enrollment_id;
    ELSE
        v_enrollment_id := NEW.enrollment_id;
    END IF;

    SELECT e.status::text,
           COALESCE(e.total_due, 0) - COALESCE(e.discount_amount, 0) +
           COALESCE((SELECT sum(fa.amount) FROM public.fee_adjustments fa
                     WHERE fa.enrollment_id = e.id), 0)
    INTO v_status, v_net
    FROM public.enrollments e
    WHERE e.id = v_enrollment_id;

    IF v_status IS NULL OR NOT public.enrollment_status_occupies_seat(v_status) THEN
        RETURN NULL;
    END IF;

    SELECT COALESCE(sum(s.amount), 0)
    INTO v_sum
    FROM public.installment_schedule s
    WHERE s.enrollment_id = v_enrollment_id;

    IF v_net > 0 AND v_sum <> v_net THEN
        RAISE EXCEPTION 'خطة الأقساط لا تطابق صافي الرسوم: الأقساط=%, الرسوم=%', v_sum, v_net;
    END IF;

    IF v_net <= 0 AND v_sum > 0 THEN
        RAISE EXCEPTION 'يوجد أقساط لتسجيل صافي رسومه صفر أو سالب (%)', v_net;
    END IF;

    RETURN NULL;
END;
$$;


--
-- Name: trg_fn_c1_refund_after(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trg_fn_c1_refund_after() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
    v_payment_id uuid;
BEGIN
    IF TG_OP = 'DELETE' THEN
        v_payment_id := OLD.payment_id;
    ELSE
        v_payment_id := NEW.payment_id;
    END IF;

    PERFORM public.c1_allocate_payment(v_payment_id);

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$$;


--
-- Name: trg_fn_c1_refund_guard(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trg_fn_c1_refund_guard() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
    v_paid  numeric(12,2);
    v_total numeric(12,2);
BEGIN
    IF auth.uid() IS NOT NULL AND NOT public.c1_is_admin() THEN
        RAISE EXCEPTION 'الاسترداد المالي متاح لمدير المركز فقط';
    END IF;

    IF TG_OP = 'UPDATE' THEN
        IF NEW.amount IS DISTINCT FROM OLD.amount
           OR NEW.payment_id IS DISTINCT FROM OLD.payment_id THEN
            RAISE EXCEPTION 'لا يمكن تعديل استرداد صادر: احذفه وأنشئ استرداداً جديداً';
        END IF;
        RETURN NEW;
    END IF;

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;

    SELECT p.amount INTO v_paid
    FROM public.payments p WHERE p.id = NEW.payment_id;

    IF v_paid IS NULL THEN
        RAISE EXCEPTION 'الدفعة غير موجودة';
    END IF;

    SELECT COALESCE(sum(rf.amount), 0) INTO v_total
    FROM public.payment_refunds rf
    WHERE rf.payment_id = NEW.payment_id;

    IF v_total + NEW.amount > v_paid THEN
        RAISE EXCEPTION 'مجموع الاستردادات (%) يتجاوز مبلغ الدفعة (%)',
            v_total + NEW.amount, v_paid;
    END IF;

    RETURN NEW;
END;
$$;


--
-- Name: trg_fn_c1_refund_status_sync(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trg_fn_c1_refund_status_sync() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_payment_id    uuid;
  v_enrollment_id uuid;
BEGIN
  IF TG_OP = 'DELETE' THEN
    v_payment_id := OLD.payment_id;
  ELSE
    v_payment_id := NEW.payment_id;
  END IF;

  SELECT p.enrollment_id INTO v_enrollment_id
  FROM public.payments p
  WHERE p.id = v_payment_id;

  PERFORM public.c1_refresh_enrollment_status(v_enrollment_id);

  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: trg_fn_course_waitlist_touch(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trg_fn_course_waitlist_touch() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public', 'pg_temp'
    AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;


--
-- Name: trg_fn_enforce_cohort_capacity(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trg_fn_enforce_cohort_capacity() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_capacity INTEGER;
  v_count INTEGER;
BEGIN
  IF NOT public.enrollment_lifecycle_occupies_seat(NEW.lifecycle_status) THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'UPDATE'
     AND NEW.cohort_id = OLD.cohort_id
     AND NEW.status IS NOT DISTINCT FROM OLD.status THEN
    RETURN NEW;
  END IF;

  SELECT c.capacity
  INTO v_capacity
  FROM public.cohorts c
  WHERE c.id = NEW.cohort_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'COHORT_NOT_FOUND' USING ERRCODE = 'P0001';
  END IF;

  IF v_capacity IS NULL THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'UPDATE' THEN
    SELECT count(*)
    INTO v_count
    FROM public.enrollments e
    WHERE e.cohort_id = NEW.cohort_id
      AND e.id <> OLD.id
      AND public.enrollment_lifecycle_occupies_seat(e.lifecycle_status);
  ELSE
    SELECT count(*)
    INTO v_count
    FROM public.enrollments e
    WHERE e.cohort_id = NEW.cohort_id
      AND public.enrollment_lifecycle_occupies_seat(e.lifecycle_status);
  END IF;

  IF v_count >= v_capacity THEN
    RAISE EXCEPTION 'COHORT_CAPACITY_REACHED'
      USING ERRCODE = 'P0001',
            DETAIL = format('cohort=%s active=%s capacity=%s',
                            NEW.cohort_id, v_count, v_capacity);
  END IF;

  RETURN NEW;
END;
$$;


--
-- Name: trg_fn_enforce_withdrawal_rpc(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trg_fn_enforce_withdrawal_rpc() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
BEGIN
  IF current_setting('c1.withdrawal_rpc', true) = 'on' THEN
    RETURN NEW;
  END IF;

  RAISE EXCEPTION 'تغيير دورة حياة التسجيل متاح عبر إجراء الانسحاب فقط'
    USING ERRCODE = 'P0001';
END;
$$;


--
-- Name: trg_fn_enqueue_survey_notification(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trg_fn_enqueue_survey_notification() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_user_id UUID;
  v_title TEXT;
BEGIN
  SELECT t.user_id, st.title
  INTO v_user_id, v_title
  FROM public.enrollments e
  JOIN public.trainees t ON t.id = e.trainee_id
  JOIN public.users u ON u.id = t.user_id
  JOIN public.survey_templates st ON st.id = NEW.template_id
  WHERE e.id = NEW.enrollment_id
    AND u.is_active = true
    AND e.status::text <> 'dropped';

  IF v_user_id IS NOT NULL THEN
    INSERT INTO public.notification_outbox (
      user_id,
      type,
      title,
      body,
      data,
      dedupe_key
    ) VALUES (
      v_user_id,
      'survey_reminder',
      'استبيان جديد بانتظارك',
      'يرجى تعبئة استبيان: ' || COALESCE(v_title, 'استبيان تقييم'),
      jsonb_build_object(
        'type', 'survey_reminder',
        'dispatch_id', NEW.id,
        'route', '/surveys'
      ),
      'survey:' || NEW.id
    )
    ON CONFLICT (dedupe_key) DO NOTHING;
  END IF;

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'survey outbox enqueue failed for dispatch %: %', NEW.id, SQLERRM;
  RETURN NEW;
END;
$$;


--
-- Name: trg_fn_enrollment_waitlist_on_release(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trg_fn_enrollment_waitlist_on_release() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    BEGIN
      PERFORM public.notify_next_waitlist(OLD.cohort_id);
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'waitlist notify skipped for cohort %: %', OLD.cohort_id, SQLERRM;
    END;
    RETURN OLD;
  END IF;

  IF (OLD.cohort_id IS DISTINCT FROM NEW.cohort_id)
     OR (
       public.enrollment_lifecycle_occupies_seat(OLD.lifecycle_status)
       AND NOT public.enrollment_lifecycle_occupies_seat(NEW.lifecycle_status)
     ) THEN
    BEGIN
      PERFORM public.notify_next_waitlist(OLD.cohort_id);
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'waitlist notify skipped for cohort %: %', OLD.cohort_id, SQLERRM;
    END;
  END IF;

  RETURN NEW;
END;
$$;


--
-- Name: trg_fn_enrollments_referral_after(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trg_fn_enrollments_referral_after() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_budget NUMERIC(12,2);
  v_applied NUMERIC(12,2) := 0;
  v_row RECORD;
  v_referrer_id UUID;
  v_referrer_user_id UUID;
  v_course_id UUID;
  v_referral_id UUID;
BEGIN
  PERFORM pg_advisory_xact_lock(
    hashtextextended('referral_credit:' || NEW.trainee_id::text, 0)
  );

  v_budget := GREATEST(
    COALESCE(NEW.total_due, 0) - COALESCE(NEW.discount_amount, 0),
    0
  );

  IF v_budget > 0 THEN
    FOR v_row IN
      SELECT r.id, r.discount_amount
      FROM public.referrals r
      WHERE r.referrer_trainee_id = NEW.trainee_id
        AND r.status = 'available'
        AND upper(btrim(r.currency)) = upper(btrim(NEW.currency))
        AND r.enrollment_id <> NEW.id
      ORDER BY r.created_at, r.id
      FOR UPDATE
    LOOP
      CONTINUE WHEN v_row.discount_amount > (v_budget - v_applied);

      UPDATE public.referrals
      SET status = 'applied',
          applied_enrollment_id = NEW.id,
          applied_at = now(),
          updated_at = now()
      WHERE id = v_row.id;

      v_applied := v_applied + v_row.discount_amount;

      EXIT WHEN v_applied >= v_budget;
    END LOOP;

    IF v_applied > 0 THEN
      UPDATE public.enrollments
      SET discount_amount = COALESCE(discount_amount, 0) + v_applied
      WHERE id = NEW.id;
    END IF;
  END IF;

  IF NEW.referral_code IS NOT NULL
     AND COALESCE(NEW.referral_discount_amount, 0) > 0 THEN
    SELECT t.id, t.user_id, c.course_id
    INTO v_referrer_id, v_referrer_user_id, v_course_id
    FROM public.trainees t
    JOIN public.cohorts c ON c.id = NEW.cohort_id
    WHERE upper(btrim(t.trainee_code)) = NEW.referral_code;

    IF v_referrer_id IS NOT NULL THEN
      INSERT INTO public.referrals (
        referrer_trainee_id,
        referee_trainee_id,
        code_used,
        course_id,
        enrollment_id,
        discount_amount,
        currency
      ) VALUES (
        v_referrer_id,
        NEW.trainee_id,
        NEW.referral_code,
        v_course_id,
        NEW.id,
        NEW.referral_discount_amount,
        upper(btrim(NEW.currency))
      )
      RETURNING id INTO v_referral_id;

      INSERT INTO public.notification_outbox (
        user_id,
        type,
        title,
        body,
        data,
        dedupe_key
      ) VALUES (
        v_referrer_user_id,
        'referral_qualified',
        'إحالة ناجحة',
        'تم تسجيل صديقك بكود الإحالة الخاص بك. أصبح لديك رصيد خصم بقيمة ' ||
          to_char(NEW.referral_discount_amount, 'FM999999990.##') || ' ' ||
          NEW.currency,
        jsonb_build_object(
          'type', 'referral_qualified',
          'referral_id', v_referral_id,
          'route', '/home'
        ),
        'referral_qualified:' || v_referral_id::text
      );
    END IF;
  END IF;

  RETURN NEW;
END;
$$;


--
-- Name: trg_fn_enrollments_referral_before(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trg_fn_enrollments_referral_before() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_referrer RECORD;
  v_course_id UUID;
  v_remaining NUMERIC(12,2);
BEGIN
  PERFORM pg_advisory_xact_lock(
    hashtextextended('referral_credit:' || NEW.trainee_id::text, 0)
  );

  NEW.referral_code := NULLIF(upper(btrim(COALESCE(NEW.referral_code, ''))), '');
  NEW.referral_discount_amount := COALESCE(NEW.referral_discount_amount, 0);

  IF NEW.referral_code IS NULL THEN
    NEW.referral_discount_amount := 0;
    RETURN NEW;
  END IF;

  IF NEW.referral_discount_amount <= 0 THEN
    RAISE EXCEPTION 'REFERRAL_DISCOUNT_INVALID' USING ERRCODE = 'P0001';
  END IF;

  SELECT t.id, t.user_id, u.is_active
  INTO v_referrer
  FROM public.trainees t
  JOIN public.users u ON u.id = t.user_id
  WHERE upper(btrim(t.trainee_code)) = NEW.referral_code;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'REFERRAL_CODE_INVALID' USING ERRCODE = 'P0001';
  END IF;

  IF v_referrer.id = NEW.trainee_id THEN
    RAISE EXCEPTION 'REFERRAL_SELF' USING ERRCODE = 'P0001';
  END IF;

  IF NOT v_referrer.is_active THEN
    RAISE EXCEPTION 'REFERRAL_REFERRER_INACTIVE' USING ERRCODE = 'P0001';
  END IF;

  SELECT c.course_id
  INTO v_course_id
  FROM public.cohorts c
  WHERE c.id = NEW.cohort_id;

  IF v_course_id IS NULL THEN
    RAISE EXCEPTION 'COHORT_NOT_FOUND' USING ERRCODE = 'P0001';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.enrollments e
    JOIN public.cohorts c ON c.id = e.cohort_id
    WHERE e.trainee_id = NEW.trainee_id
      AND c.course_id = v_course_id
      AND public.enrollment_lifecycle_occupies_seat(e.lifecycle_status)
  ) THEN
    RAISE EXCEPTION 'REFERRAL_REFEREE_ENROLLED' USING ERRCODE = 'P0001';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.referrals r
    WHERE r.referee_trainee_id = NEW.trainee_id
      AND r.course_id = v_course_id
      AND r.status <> 'cancelled'
  ) THEN
    RAISE EXCEPTION 'REFERRAL_ALREADY_REFERRED' USING ERRCODE = 'P0001';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.referrals r
    WHERE r.referrer_trainee_id = NEW.trainee_id
      AND r.referee_trainee_id = v_referrer.id
      AND r.course_id = v_course_id
      AND r.status <> 'cancelled'
  ) THEN
    RAISE EXCEPTION 'REFERRAL_MUTUAL' USING ERRCODE = 'P0001';
  END IF;

  v_remaining := GREATEST(
    COALESCE(NEW.total_due, 0) - COALESCE(NEW.discount_amount, 0),
    0
  );

  IF v_remaining <= 0 THEN
    RAISE EXCEPTION 'REFERRAL_NOTHING_DUE' USING ERRCODE = 'P0001';
  END IF;

  IF NEW.referral_discount_amount > v_remaining THEN
    RAISE EXCEPTION 'REFERRAL_DISCOUNT_TOO_HIGH'
      USING ERRCODE = 'P0001',
            DETAIL = format('requested=%s remaining=%s',
                            NEW.referral_discount_amount, v_remaining);
  END IF;

  NEW.discount_amount := COALESCE(NEW.discount_amount, 0) + NEW.referral_discount_amount;

  RETURN NEW;
END;
$$;


--
-- Name: trg_fn_referral_on_enrollment_release(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trg_fn_referral_on_enrollment_release() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
BEGIN
  PERFORM pg_advisory_xact_lock(
    hashtextextended('referral_credit:' || NEW.trainee_id::text, 0)
  );

  IF public.enrollment_lifecycle_occupies_seat(OLD.lifecycle_status)
     AND NOT public.enrollment_lifecycle_occupies_seat(NEW.lifecycle_status) THEN
    WITH restored AS (
      UPDATE public.referrals
      SET status = 'available',
          applied_enrollment_id = NULL,
          applied_at = NULL,
          updated_at = now()
      WHERE applied_enrollment_id = NEW.id
        AND status = 'applied'
      RETURNING discount_amount
    ),
    cancelled AS (
      UPDATE public.referrals
      SET status = 'cancelled',
          updated_at = now()
      WHERE enrollment_id = NEW.id
        AND status = 'available'
      RETURNING discount_amount
    )
    UPDATE public.enrollments e
    SET discount_amount = GREATEST(
          COALESCE(e.discount_amount, 0)
          - COALESCE((SELECT sum(discount_amount) FROM restored), 0)
          - COALESCE(e.referral_discount_amount, 0),
          0
        ),
        referral_code = NULL,
        referral_discount_amount = 0
    WHERE e.id = NEW.id;
  END IF;

  RETURN NEW;
END;
$$;


--
-- Name: trg_fn_referrals_touch(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trg_fn_referrals_touch() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public', 'pg_temp'
    AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;


--
-- Name: trg_fn_validate_cohort_capacity(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trg_fn_validate_cohort_capacity() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_count INTEGER;
BEGIN
  IF NEW.capacity IS NOT NULL AND NEW.capacity <= 0 THEN
    RAISE EXCEPTION 'COHORT_CAPACITY_INVALID' USING ERRCODE = 'P0001';
  END IF;

  IF TG_OP = 'UPDATE' AND NEW.capacity IS NOT DISTINCT FROM OLD.capacity THEN
    RETURN NEW;
  END IF;

  IF NEW.capacity IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT count(*)
  INTO v_count
  FROM public.enrollments e
  WHERE e.cohort_id = NEW.id
    AND public.enrollment_lifecycle_occupies_seat(e.lifecycle_status);

  IF v_count > NEW.capacity THEN
    RAISE EXCEPTION 'COHORT_CAPACITY_BELOW_ENROLLED'
      USING ERRCODE = 'P0001',
            DETAIL = format('cohort=%s active=%s requested_capacity=%s',
                            NEW.id, v_count, NEW.capacity);
  END IF;

  RETURN NEW;
END;
$$;


--
-- Name: trg_fn_validate_waitlist_insert(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trg_fn_validate_waitlist_insert() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_capacity INTEGER;
  v_cohort_active BOOLEAN;
  v_course_active BOOLEAN;
  v_active_count INTEGER;
BEGIN
  IF NEW.status <> 'waiting' THEN
    RAISE EXCEPTION 'WAITLIST_INITIAL_STATUS_INVALID' USING ERRCODE = 'P0001';
  END IF;

  SELECT c.capacity, c.is_active, co.is_active
  INTO v_capacity, v_cohort_active, v_course_active
  FROM public.cohorts c
  JOIN public.courses co ON co.id = c.course_id
  WHERE c.id = NEW.cohort_id
  FOR UPDATE OF c;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'COHORT_NOT_FOUND' USING ERRCODE = 'P0001';
  END IF;

  IF NOT v_cohort_active OR NOT v_course_active THEN
    RAISE EXCEPTION 'COHORT_NOT_ACTIVE' USING ERRCODE = 'P0001';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.trainees t
    JOIN public.users u ON u.id = t.user_id
    WHERE t.id = NEW.trainee_id
      AND u.is_active = true
  ) THEN
    RAISE EXCEPTION 'TRAINEE_NOT_FOUND' USING ERRCODE = 'P0001';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.enrollments e
    WHERE e.cohort_id = NEW.cohort_id
      AND e.trainee_id = NEW.trainee_id
      AND public.enrollment_lifecycle_occupies_seat(e.lifecycle_status)
  ) THEN
    RAISE EXCEPTION 'ALREADY_ENROLLED' USING ERRCODE = 'P0001';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.course_waitlist w
    WHERE w.cohort_id = NEW.cohort_id
      AND w.trainee_id = NEW.trainee_id
      AND w.status IN ('waiting', 'notified')
  ) THEN
    RAISE EXCEPTION 'ALREADY_ON_WAITLIST' USING ERRCODE = 'P0001';
  END IF;

  v_active_count := public.cohort_active_enrollment_count(NEW.cohort_id);

  IF v_capacity IS NULL OR v_active_count < v_capacity THEN
    RAISE EXCEPTION 'COHORT_HAS_AVAILABLE_SEATS' USING ERRCODE = 'P0001';
  END IF;

  RETURN NEW;
END;
$$;


--
-- Name: trg_fn_validate_waitlist_transition(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trg_fn_validate_waitlist_transition() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
BEGIN
  IF NEW.cohort_id <> OLD.cohort_id OR NEW.trainee_id <> OLD.trainee_id THEN
    RAISE EXCEPTION 'WAITLIST_IDENTITY_IMMUTABLE' USING ERRCODE = 'P0001';
  END IF;

  IF NEW.status = OLD.status THEN
    RETURN NEW;
  END IF;

  IF NEW.status = 'enrolled' THEN
    IF NEW.promoted_at IS NULL OR NEW.promoted_by IS NULL THEN
      RAISE EXCEPTION 'WAITLIST_PROMOTION_FIELDS_REQUIRED' USING ERRCODE = 'P0001';
    END IF;
    IF NOT EXISTS (
      SELECT 1
      FROM public.enrollments e
      WHERE e.cohort_id = NEW.cohort_id
        AND e.trainee_id = NEW.trainee_id
        AND public.enrollment_lifecycle_occupies_seat(e.lifecycle_status)
    ) THEN
      RAISE EXCEPTION 'WAITLIST_ENROLLMENT_MISSING' USING ERRCODE = 'P0001';
    END IF;
  END IF;

  IF OLD.status = 'waiting' AND NEW.status IN ('notified', 'enrolled', 'cancelled') THEN
    RETURN NEW;
  END IF;

  IF OLD.status = 'notified' AND NEW.status IN ('enrolled', 'expired', 'cancelled') THEN
    RETURN NEW;
  END IF;

  RAISE EXCEPTION 'INVALID_WAITLIST_TRANSITION'
    USING ERRCODE = 'P0001',
          DETAIL = format('from=%s to=%s', OLD.status, NEW.status);
END;
$$;


--
-- Name: trg_fn_waitlist_on_capacity_change(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trg_fn_waitlist_on_capacity_change() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
BEGIN
  IF (OLD.capacity IS NOT NULL AND NEW.capacity IS NULL)
     OR (
       OLD.capacity IS NOT NULL
       AND NEW.capacity IS NOT NULL
       AND NEW.capacity > OLD.capacity
     ) THEN
    BEGIN
      PERFORM public.notify_next_waitlist(NEW.id);
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'waitlist notify skipped for cohort %: %', NEW.id, SQLERRM;
    END;
  END IF;

  RETURN NEW;
END;
$$;


--
-- Name: trg_lab_invoice_discount_sync(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trg_lab_invoice_discount_sync() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF NEW.discount IS DISTINCT FROM OLD.discount THEN
        NEW.total_amount := GREATEST(ROUND((NEW.subtotal - COALESCE(NEW.discount, 0.00))::numeric, 2), 0.00);
        IF NEW.status != 'cancelled' THEN
            IF NEW.total_amount > 0 AND NEW.paid_amount >= NEW.total_amount THEN
                NEW.status := 'paid';
            ELSIF NEW.paid_amount > 0 THEN
                NEW.status := 'partial';
            ELSE
                NEW.status := 'unpaid';
            END IF;
        END IF;
    END IF;
    RETURN NEW;
END;
$$;


--
-- Name: trg_lab_invoice_items_sync(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trg_lab_invoice_items_sync() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        PERFORM public.recalculate_lab_invoice(OLD.invoice_id);
    ELSE
        PERFORM public.recalculate_lab_invoice(NEW.invoice_id);
    END IF;
    RETURN NULL;
END;
$$;


--
-- Name: trg_lab_payments_sync(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trg_lab_payments_sync() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        PERFORM public.recalculate_lab_invoice(OLD.invoice_id);
    ELSE
        PERFORM public.recalculate_lab_invoice(NEW.invoice_id);
    END IF;
    RETURN NULL;
END;
$$;


--
-- Name: update_enrollment_payment_status(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_enrollment_payment_status() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_enrollment_id uuid;
BEGIN
  IF TG_OP = 'DELETE' THEN
    v_enrollment_id := OLD.enrollment_id;
  ELSE
    v_enrollment_id := NEW.enrollment_id;
  END IF;

  PERFORM public.c1_refresh_enrollment_status(v_enrollment_id);

  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: verify_user_pin(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.verify_user_pin(p_pin text) RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
DECLARE
  v_hash text;
BEGIN
  IF auth.uid() IS NULL OR p_pin IS NULL THEN
    RETURN false;
  END IF;

  SELECT up.pin_hash INTO v_hash
  FROM public.user_pins up
  JOIN public.users u ON u.id = up.user_id
  WHERE up.user_id = auth.uid()
    AND u.is_active = true;

  IF v_hash IS NULL THEN
    RETURN false;
  END IF;

  RETURN (v_hash = crypt(p_pin, v_hash));
END;
$$;


--
-- Name: withdraw_enrollment(uuid, text, boolean, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.withdraw_enrollment(p_enrollment_id uuid, p_reason text, p_write_off_debt boolean DEFAULT false, p_sessions_override integer DEFAULT NULL::integer) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_at TIMESTAMPTZ := now();
  v_enr RECORD;
  v_pre RECORD;
  v_post RECORD;
  v_reason TEXT := NULLIF(btrim(COALESCE(p_reason, '')), '');
  v_payment RECORD;
  v_remaining NUMERIC(12,2);
  v_take NUMERIC(12,2);
  v_free NUMERIC(12,2);
  v_refund_total NUMERIC(12,2) := 0;
  v_writeoff NUMERIC(12,2) := 0;
  v_settlement NUMERIC(12,2);
  v_outcome TEXT;
BEGIN
  IF v_uid IS NOT NULL AND NOT public.c1_is_admin() THEN
    RAISE EXCEPTION 'ADMIN_ONLY' USING ERRCODE = 'P0001';
  END IF;

  IF v_reason IS NULL THEN
    RAISE EXCEPTION 'سبب الانسحاب مطلوب' USING ERRCODE = 'P0001';
  END IF;

  SELECT e.id, e.trainee_id, e.lifecycle_status
  INTO v_enr
  FROM public.enrollments e
  WHERE e.id = p_enrollment_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'ENROLLMENT_NOT_FOUND' USING ERRCODE = 'P0001';
  END IF;

  IF v_enr.lifecycle_status <> 'active' THEN
    RAISE EXCEPTION 'ENROLLMENT_NOT_ACTIVE' USING ERRCODE = 'P0001',
      DETAIL = format('lifecycle_status=%s', v_enr.lifecycle_status);
  END IF;

  PERFORM pg_advisory_xact_lock(
    hashtextextended('referral_credit:' || v_enr.trainee_id::text, 0)
  );

  SELECT * INTO v_pre
  FROM public.c1_withdrawal_figures(p_enrollment_id, p_sessions_override, v_at);

  -- Guard trigger allows this only under the RPC flag.
  PERFORM set_config('c1.withdrawal_rpc', 'on', true);

  UPDATE public.enrollments
  SET lifecycle_status = 'withdrawn',
      withdrawn_at = v_at,
      withdrawal_reason = v_reason
  WHERE id = p_enrollment_id;

  -- Recompute from actual post-trigger state (referral discount revocation applied).
  SELECT * INTO v_post
  FROM public.c1_withdrawal_figures(p_enrollment_id, p_sessions_override, v_at);

  -- 4) LIFO surplus refund: newest payments first.
  v_remaining := v_post.refundable;

  FOR v_payment IN
    SELECT p.id,
           p.amount - COALESCE((
             SELECT sum(rf.amount)
             FROM public.payment_refunds rf
             WHERE rf.payment_id = p.id
           ), 0) AS free_amount
    FROM public.payments p
    WHERE p.enrollment_id = p_enrollment_id
    ORDER BY p.paid_at DESC NULLS LAST,
             p.id DESC
  LOOP
    EXIT WHEN v_remaining <= 0;

    v_free := COALESCE(v_payment.free_amount, 0);
    CONTINUE WHEN v_free <= 0;

    v_take := LEAST(v_remaining, v_free);

    INSERT INTO public.payment_refunds (
      payment_id,
      amount,
      reason,
      created_by
    ) VALUES (
      v_payment.id,
      v_take,
      'استرداد فائض انسحاب pro-rata',
      v_uid
    );

    v_remaining := v_remaining - v_take;
    v_refund_total := v_refund_total + v_take;
  END LOOP;

  IF v_remaining > 0 THEN
    RAISE EXCEPTION 'REFUND_ALLOCATION_FAILED'
      USING ERRCODE = 'P0001',
            DETAIL = format('remaining=%s', v_remaining);
  END IF;

  -- 5) Settle the obligation to the pro-rata due amount.
  v_settlement := v_post.settlement_delta;

  IF v_settlement <> 0 THEN
    INSERT INTO public.fee_adjustments (
      enrollment_id,
      amount,
      reason,
      kind,
      created_by
    ) VALUES (
      p_enrollment_id,
      v_settlement,
      'تسوية انسحاب pro-rata: ' || v_post.delivered_sessions || ' من ' ||
        v_post.total_sessions || ' جلسة',
      'withdrawal_settlement',
      v_uid
    );
  END IF;

  -- 6) Optional debt write-off (admin decision).
  IF p_write_off_debt AND v_post.debt_amount > 0 THEN
    v_writeoff := v_post.debt_amount;

    INSERT INTO public.fee_adjustments (
      enrollment_id,
      amount,
      reason,
      kind,
      created_by
    ) VALUES (
      p_enrollment_id,
      -v_writeoff,
      'شطب دين انسحاب بقرار الإدارة',
      'debt_writeoff',
      v_uid
    );
  END IF;

  v_outcome := CASE
                 WHEN v_writeoff > 0 THEN 'writeoff'
                 WHEN v_post.debt_amount > 0 THEN 'debt'
                 WHEN v_refund_total > 0 THEN 'refund'
                 ELSE 'settled'
               END;

  -- Ensure enrollments.status reflects the settled obligation even when no
  -- refund/adjustment was written (paid == due exactly).
  PERFORM public.c1_refresh_enrollment_status(p_enrollment_id);

  -- 7) Audit.
  INSERT INTO public.enrollment_withdrawals (
    enrollment_id,
    trainee_id,
    currency,
    total_sessions,
    sessions_charged,
    sessions_overridden,
    session_cost,
    net_due_before,
    net_due_after,
    net_paid_before,
    net_paid_after,
    discount_revoked,
    due_amount,
    settlement_delta,
    refund_amount,
    writeoff_amount,
    outcome,
    reason,
    withdrawn_at,
    created_by
  ) VALUES (
    p_enrollment_id,
    v_enr.trainee_id,
    v_post.currency,
    v_post.total_sessions,
    v_post.delivered_sessions,
    v_post.sessions_overridden,
    CASE
      WHEN v_post.total_sessions > 0
      THEN ROUND(v_post.net_due_after / v_post.total_sessions, 2)
      ELSE 0
    END,
    v_pre.net_due_before,
    v_post.net_due_after,
    v_pre.net_paid,
    v_pre.net_paid - v_refund_total,
    v_pre.discount_revoked,
    v_post.due_amount,
    v_settlement,
    v_refund_total,
    v_writeoff,
    v_outcome,
    v_reason,
    v_at,
    v_uid
  );

  PERFORM set_config('c1.withdrawal_rpc', 'off', true);

  RETURN jsonb_build_object(
    'enrollment_id', p_enrollment_id,
    'lifecycle_status', 'withdrawn',
    'currency', v_post.currency,
    'total_sessions', v_post.total_sessions,
    'sessions_charged', v_post.delivered_sessions,
    'sessions_overridden', v_post.sessions_overridden,
    'net_due_before', v_pre.net_due_before,
    'net_due_after', v_post.net_due_after,
    'net_paid_before', v_pre.net_paid,
    'net_paid_after', v_pre.net_paid - v_refund_total,
    'discount_revoked', v_pre.discount_revoked,
    'due_amount', v_post.due_amount,
    'settlement_amount', v_settlement,
    'refund_amount', v_refund_total,
    'debt_amount', v_post.debt_amount,
    'writeoff_amount', v_writeoff,
    'outcome', v_outcome
  );
END;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: attendance; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.attendance (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    session_id uuid NOT NULL,
    trainee_id uuid NOT NULL,
    method public.attendance_method DEFAULT 'qr'::public.attendance_method NOT NULL,
    recorded_at timestamp with time zone DEFAULT now() NOT NULL,
    performed_by uuid NOT NULL,
    captured_at timestamp with time zone
);


--
-- Name: audit_log; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.audit_log (
    id bigint NOT NULL,
    table_name text NOT NULL,
    operation text NOT NULL,
    record_id uuid,
    old_data jsonb,
    new_data jsonb,
    performed_by uuid,
    performed_at timestamp with time zone DEFAULT now() NOT NULL,
    actor_source text,
    actor_role text
);


--
-- Name: audit_log_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.audit_log_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: audit_log_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.audit_log_id_seq OWNED BY public.audit_log.id;


--
-- Name: cohorts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.cohorts (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    course_id uuid NOT NULL,
    trainer_id uuid NOT NULL,
    name text NOT NULL,
    starts_at date,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid NOT NULL,
    capacity integer,
    CONSTRAINT cohorts_capacity_positive CHECK (((capacity IS NULL) OR (capacity > 0)))
);


--
-- Name: courses; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.courses (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text NOT NULL,
    total_sessions integer NOT NULL,
    price numeric(10,2) NOT NULL,
    description text,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid NOT NULL,
    CONSTRAINT courses_price_check CHECK ((price >= (0)::numeric)),
    CONSTRAINT courses_total_sessions_check CHECK ((total_sessions > 0))
);


--
-- Name: enrollments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.enrollments (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    trainee_id uuid NOT NULL,
    cohort_id uuid NOT NULL,
    total_due numeric(10,2) NOT NULL,
    status public.payment_status DEFAULT 'unpaid'::public.payment_status NOT NULL,
    enrolled_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid NOT NULL,
    discount_amount numeric(10,2) DEFAULT 0 NOT NULL,
    currency public.currency_type DEFAULT 'SYP'::public.currency_type NOT NULL,
    referral_code text,
    referral_discount_amount numeric(12,2),
    lifecycle_status text DEFAULT 'active'::text NOT NULL,
    withdrawn_at timestamp with time zone,
    withdrawal_reason text,
    CONSTRAINT enrollments_lifecycle_status_check CHECK ((lifecycle_status = ANY (ARRAY['active'::text, 'completed'::text, 'withdrawn'::text]))),
    CONSTRAINT enrollments_withdrawn_fields_check CHECK (((lifecycle_status = 'withdrawn'::text) OR (withdrawn_at IS NULL)))
);


--
-- Name: payments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.payments (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    enrollment_id uuid NOT NULL,
    amount numeric(10,2) NOT NULL,
    method public.payment_method DEFAULT 'cash'::public.payment_method NOT NULL,
    paid_at timestamp with time zone DEFAULT now() NOT NULL,
    notes text,
    performed_by uuid NOT NULL,
    currency public.currency_type DEFAULT 'SYP'::public.currency_type NOT NULL,
    receipt_number text,
    external_reference text,
    CONSTRAINT payments_amount_check CHECK ((amount > (0)::numeric))
);


--
-- Name: trainees; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.trainees (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid,
    notes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid NOT NULL,
    academic_year text,
    full_name_en text,
    university text,
    trainee_code text,
    full_name_ar text,
    whatsapp_number text,
    university_name text,
    province text,
    address text,
    behavioral_notes text,
    academic_notes text,
    batch_date date
);


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    email text NOT NULL,
    role public.user_role DEFAULT 'trainee'::public.user_role NOT NULL,
    full_name text NOT NULL,
    phone text,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    must_change_password boolean DEFAULT false NOT NULL,
    must_change_password_at timestamp with time zone,
    CONSTRAINT chk_users_must_change_password_at CHECK (((must_change_password = false) OR (must_change_password_at IS NOT NULL)))
);


--
-- Name: enrollment_financial_summary; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.enrollment_financial_summary WITH (security_invoker='true') AS
 SELECT e.id AS enrollment_id,
    t.id AS trainee_id,
    u.full_name AS trainee_name,
    co.name AS course_name,
    e.total_due,
    e.discount_amount,
    e.currency,
    (e.total_due - e.discount_amount) AS net_due,
    COALESCE(sum(p.amount), (0)::numeric) AS total_paid,
    ((e.total_due - e.discount_amount) - COALESCE(sum(p.amount), (0)::numeric)) AS balance,
    e.status AS payment_status
   FROM (((((public.enrollments e
     JOIN public.trainees t ON ((t.id = e.trainee_id)))
     JOIN public.users u ON ((u.id = t.user_id)))
     JOIN public.cohorts c ON ((c.id = e.cohort_id)))
     JOIN public.courses co ON ((co.id = c.course_id)))
     LEFT JOIN public.payments p ON ((p.enrollment_id = e.id)))
  GROUP BY e.id, t.id, u.full_name, co.name, e.total_due, e.discount_amount, e.currency, e.status;


--
-- Name: cash_vs_accrual_kpis; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.cash_vs_accrual_kpis WITH (security_invoker='true') AS
 SELECT currency,
    COALESCE(sum(total_paid), (0)::numeric) AS collected_cash,
    COALESCE(sum(balance), (0)::numeric) AS pending_accrual,
    COALESCE(sum(total_due), (0)::numeric) AS total_expected
   FROM public.enrollment_financial_summary e
  GROUP BY currency;


--
-- Name: fee_adjustments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.fee_adjustments (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    enrollment_id uuid NOT NULL,
    amount numeric(12,2) NOT NULL,
    reason text NOT NULL,
    adjusted_at timestamp with time zone DEFAULT now() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    kind text DEFAULT 'manual'::text NOT NULL,
    CONSTRAINT fee_adjustments_amount_check CHECK ((amount <> (0)::numeric)),
    CONSTRAINT fee_adjustments_kind_check CHECK ((kind = ANY (ARRAY['manual'::text, 'withdrawal_settlement'::text, 'debt_writeoff'::text])))
);


--
-- Name: installment_schedule; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.installment_schedule (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    enrollment_id uuid NOT NULL,
    installment_number integer NOT NULL,
    due_date date NOT NULL,
    amount numeric(12,2) NOT NULL,
    currency public.currency_type NOT NULL,
    notes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    CONSTRAINT installment_schedule_amount_check CHECK ((amount > (0)::numeric)),
    CONSTRAINT installment_schedule_installment_number_check CHECK ((installment_number > 0))
);


--
-- Name: payment_allocations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.payment_allocations (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    payment_id uuid NOT NULL,
    installment_id uuid NOT NULL,
    amount numeric(12,2) NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    CONSTRAINT payment_allocations_amount_check CHECK ((amount > (0)::numeric))
);


--
-- Name: payment_refunds; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.payment_refunds (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    payment_id uuid NOT NULL,
    amount numeric(12,2) NOT NULL,
    reason text NOT NULL,
    refunded_at timestamp with time zone DEFAULT now() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    CONSTRAINT payment_refunds_amount_check CHECK ((amount > (0)::numeric))
);


--
-- Name: enrollment_financial_summary_v2; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.enrollment_financial_summary_v2 AS
 WITH payment_agg AS (
         SELECT p.enrollment_id,
            sum(p.amount) AS gross_paid
           FROM public.payments p
          GROUP BY p.enrollment_id
        ), refund_agg AS (
         SELECT p.enrollment_id,
            sum(r.amount) AS total_refunded
           FROM (public.payment_refunds r
             JOIN public.payments p ON ((p.id = r.payment_id)))
          GROUP BY p.enrollment_id
        ), adjustment_agg AS (
         SELECT fa.enrollment_id,
            sum(fa.amount) AS total_adjustments
           FROM public.fee_adjustments fa
          GROUP BY fa.enrollment_id
        ), installment_agg AS (
         SELECT s.enrollment_id,
            count(s.id) AS total_installments,
            min(
                CASE
                    WHEN (COALESCE(alloc.allocated, (0)::numeric) < s.amount) THEN s.due_date
                    ELSE NULL::date
                END) AS next_due_date,
            COALESCE(sum(
                CASE
                    WHEN (s.due_date < ((now() AT TIME ZONE 'Asia/Damascus'::text))::date) THEN GREATEST((s.amount - COALESCE(alloc.allocated, (0)::numeric)), (0)::numeric)
                    ELSE (0)::numeric
                END), (0)::numeric) AS overdue_balance
           FROM (public.installment_schedule s
             LEFT JOIN ( SELECT payment_allocations.installment_id,
                    sum(payment_allocations.amount) AS allocated
                   FROM public.payment_allocations
                  GROUP BY payment_allocations.installment_id) alloc ON ((alloc.installment_id = s.id)))
          GROUP BY s.enrollment_id
        )
 SELECT e.id AS enrollment_id,
    e.trainee_id,
    u.full_name AS trainee_name,
    t.trainee_code,
    co.id AS cohort_id,
    co.name AS cohort_name,
    e.currency,
    e.status AS legacy_payment_status,
    e.total_due AS original_fee,
    e.discount_amount AS total_discount,
    COALESCE(adj.total_adjustments, (0)::numeric) AS total_adjustments,
    ((e.total_due - COALESCE(e.discount_amount, (0)::numeric)) + COALESCE(adj.total_adjustments, (0)::numeric)) AS net_due,
    COALESCE(pa.gross_paid, (0)::numeric) AS gross_paid,
    COALESCE(rf.total_refunded, (0)::numeric) AS total_refunded,
    (COALESCE(pa.gross_paid, (0)::numeric) - COALESCE(rf.total_refunded, (0)::numeric)) AS net_paid,
    (((e.total_due - COALESCE(e.discount_amount, (0)::numeric)) + COALESCE(adj.total_adjustments, (0)::numeric)) - (COALESCE(pa.gross_paid, (0)::numeric) - COALESCE(rf.total_refunded, (0)::numeric))) AS current_balance,
    COALESCE(ia.total_installments, (0)::bigint) AS total_installments,
    ia.next_due_date,
        CASE
            WHEN public.enrollment_lifecycle_occupies_seat(e.lifecycle_status) THEN COALESCE(ia.overdue_balance, (0)::numeric)
            ELSE (0)::numeric
        END AS overdue_balance,
    crs.name AS course_name,
    ((e.total_due - COALESCE(e.discount_amount, (0)::numeric)) + COALESCE(adj.total_adjustments, (0)::numeric)) AS total_due,
    (COALESCE(pa.gross_paid, (0)::numeric) - COALESCE(rf.total_refunded, (0)::numeric)) AS total_paid,
    (((e.total_due - COALESCE(e.discount_amount, (0)::numeric)) + COALESCE(adj.total_adjustments, (0)::numeric)) - (COALESCE(pa.gross_paid, (0)::numeric) - COALESCE(rf.total_refunded, (0)::numeric))) AS balance,
        CASE
            WHEN ((COALESCE(pa.gross_paid, (0)::numeric) - COALESCE(rf.total_refunded, (0)::numeric)) >= ((e.total_due - COALESCE(e.discount_amount, (0)::numeric)) + COALESCE(adj.total_adjustments, (0)::numeric))) THEN 'complete'::text
            WHEN ((COALESCE(pa.gross_paid, (0)::numeric) - COALESCE(rf.total_refunded, (0)::numeric)) > (0)::numeric) THEN 'partial'::text
            ELSE 'unpaid'::text
        END AS payment_status,
    e.lifecycle_status
   FROM ((((((((public.enrollments e
     LEFT JOIN public.trainees t ON ((t.id = e.trainee_id)))
     LEFT JOIN public.users u ON ((u.id = t.user_id)))
     LEFT JOIN public.cohorts co ON ((co.id = e.cohort_id)))
     LEFT JOIN public.courses crs ON ((crs.id = co.course_id)))
     LEFT JOIN payment_agg pa ON ((pa.enrollment_id = e.id)))
     LEFT JOIN refund_agg rf ON ((rf.enrollment_id = e.id)))
     LEFT JOIN adjustment_agg adj ON ((adj.enrollment_id = e.id)))
     LEFT JOIN installment_agg ia ON ((ia.enrollment_id = e.id)))
  WHERE public.c1_can_read_financials(t.user_id);


--
-- Name: cash_vs_accrual_kpis_v2; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.cash_vs_accrual_kpis_v2 AS
 WITH gross AS (
         SELECT (p.currency)::text AS currency,
            sum(p.amount) AS gross_paid,
            count(*) AS payment_count
           FROM public.payments p
          GROUP BY (p.currency)::text
        ), refunds AS (
         SELECT (p.currency)::text AS currency,
            sum(r_1.amount) AS refunds
           FROM (public.payment_refunds r_1
             JOIN public.payments p ON ((p.id = r_1.payment_id)))
          GROUP BY (p.currency)::text
        ), active AS (
         SELECT (v.currency)::text AS currency,
            sum(v.net_due) AS active_expected_net_due,
            sum(v.net_paid) AS active_net_paid,
            sum(GREATEST(v.current_balance, (0)::numeric)) AS active_outstanding,
            count(*) AS active_enrollments
           FROM public.enrollment_financial_summary_v2 v
          WHERE (v.lifecycle_status <> 'withdrawn'::text)
          GROUP BY (v.currency)::text
        ), withdrawn AS (
         SELECT (v.currency)::text AS currency,
            sum(v.net_paid) AS withdrawn_net_paid,
            sum(GREATEST(v.current_balance, (0)::numeric)) AS withdrawn_outstanding,
            count(*) AS withdrawn_enrollments
           FROM public.enrollment_financial_summary_v2 v
          WHERE (v.lifecycle_status = 'withdrawn'::text)
          GROUP BY (v.currency)::text
        ), all_enrollments AS (
         SELECT (v.currency)::text AS currency,
            sum(v.net_due) AS all_expected_net_due,
            sum(v.current_balance) AS all_outstanding
           FROM public.enrollment_financial_summary_v2 v
          GROUP BY (v.currency)::text
        ), currencies AS (
         SELECT gross.currency
           FROM gross
        UNION
         SELECT refunds.currency
           FROM refunds
        UNION
         SELECT all_enrollments.currency
           FROM all_enrollments
        )
 SELECT c.currency,
    COALESCE(g.gross_paid, (0)::numeric) AS gross_paid,
    COALESCE(r.refunds, (0)::numeric) AS refunds,
    (COALESCE(g.gross_paid, (0)::numeric) - COALESCE(r.refunds, (0)::numeric)) AS cash_collected,
    COALESCE(a.active_expected_net_due, (0)::numeric) AS active_expected_net_due,
    COALESCE(a.active_net_paid, (0)::numeric) AS active_net_paid,
    COALESCE(a.active_outstanding, (0)::numeric) AS active_outstanding,
    COALESCE(a.active_enrollments, (0)::bigint) AS active_enrollments,
    COALESCE(w.withdrawn_net_paid, (0)::numeric) AS withdrawn_net_paid,
    COALESCE(w.withdrawn_outstanding, (0)::numeric) AS withdrawn_outstanding,
    COALESCE(w.withdrawn_enrollments, (0)::bigint) AS withdrawn_enrollments,
    COALESCE(av.all_expected_net_due, (0)::numeric) AS all_expected_net_due,
    COALESCE(av.all_outstanding, (0)::numeric) AS all_outstanding,
    COALESCE(g.payment_count, (0)::bigint) AS payment_count
   FROM (((((currencies c
     LEFT JOIN gross g ON ((g.currency = c.currency)))
     LEFT JOIN refunds r ON ((r.currency = c.currency)))
     LEFT JOIN active a ON ((a.currency = c.currency)))
     LEFT JOIN withdrawn w ON ((w.currency = c.currency)))
     LEFT JOIN all_enrollments av ON ((av.currency = c.currency)))
  WHERE (public.c1_is_admin() OR (auth.role() IS NULL) OR (auth.role() = 'service_role'::text));


--
-- Name: course_materials; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.course_materials (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    course_id uuid NOT NULL,
    title text NOT NULL,
    description text,
    material_type text NOT NULL,
    file_path text,
    file_size_bytes bigint,
    mime_type text,
    external_url text,
    is_published boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    CONSTRAINT chk_course_materials_type_integrity CHECK ((((material_type = 'file'::text) AND (file_path IS NOT NULL)) OR ((material_type = 'link'::text) AND (external_url IS NOT NULL)))),
    CONSTRAINT course_materials_material_type_check CHECK ((material_type = ANY (ARRAY['file'::text, 'link'::text])))
);


--
-- Name: course_revenue_sql_summary; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.course_revenue_sql_summary WITH (security_invoker='true') AS
 SELECT course_name,
    currency,
    count(enrollment_id) AS trainees_count,
    COALESCE(sum(total_due), (0)::numeric) AS total_due,
    COALESCE(sum(total_paid), (0)::numeric) AS total_paid,
    COALESCE(sum(balance), (0)::numeric) AS total_balance
   FROM public.enrollment_financial_summary
  GROUP BY course_name, currency
  ORDER BY COALESCE(sum(total_paid), (0)::numeric) DESC;


--
-- Name: course_revenue_sql_summary_v2; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.course_revenue_sql_summary_v2 AS
 WITH cash AS (
         SELECT co.course_id,
            (p.currency)::text AS currency,
            sum(p.amount) AS gross_collected,
            count(p.id) AS payment_count
           FROM ((public.payments p
             JOIN public.enrollments e ON ((e.id = p.enrollment_id)))
             JOIN public.cohorts co ON ((co.id = e.cohort_id)))
          GROUP BY co.course_id, (p.currency)::text
        ), refunds AS (
         SELECT co.course_id,
            (p.currency)::text AS currency,
            sum(r_1.amount) AS refunded
           FROM (((public.payment_refunds r_1
             JOIN public.payments p ON ((p.id = r_1.payment_id)))
             JOIN public.enrollments e ON ((e.id = p.enrollment_id)))
             JOIN public.cohorts co ON ((co.id = e.cohort_id)))
          GROUP BY co.course_id, (p.currency)::text
        ), accrual AS (
         SELECT co.course_id,
            (v.currency)::text AS currency,
            sum(v.net_due) FILTER (WHERE (v.lifecycle_status <> 'withdrawn'::text)) AS active_expected_net_due,
            sum(v.net_paid) FILTER (WHERE (v.lifecycle_status <> 'withdrawn'::text)) AS active_net_paid,
            sum(GREATEST(v.current_balance, (0)::numeric)) FILTER (WHERE (v.lifecycle_status <> 'withdrawn'::text)) AS active_outstanding,
            count(*) FILTER (WHERE (v.lifecycle_status <> 'withdrawn'::text)) AS active_enrollments,
            count(*) FILTER (WHERE (v.lifecycle_status = 'withdrawn'::text)) AS withdrawn_enrollments
           FROM (public.enrollment_financial_summary_v2 v
             JOIN public.cohorts co ON ((co.id = v.cohort_id)))
          GROUP BY co.course_id, (v.currency)::text
        ), keys AS (
         SELECT co.course_id,
            (e.currency)::text AS currency
           FROM (public.enrollments e
             JOIN public.cohorts co ON ((co.id = e.cohort_id)))
          GROUP BY co.course_id, (e.currency)::text
        )
 SELECT k.course_id,
    crs.name AS course_name,
    k.currency,
    COALESCE(c.gross_collected, (0)::numeric) AS gross_collected,
    COALESCE(r.refunded, (0)::numeric) AS refunds,
    (COALESCE(c.gross_collected, (0)::numeric) - COALESCE(r.refunded, (0)::numeric)) AS net_collected,
    (COALESCE(c.gross_collected, (0)::numeric) - COALESCE(r.refunded, (0)::numeric)) AS total_paid,
    COALESCE(a.active_expected_net_due, (0)::numeric) AS active_expected_net_due,
    COALESCE(a.active_net_paid, (0)::numeric) AS active_net_paid,
    COALESCE(a.active_outstanding, (0)::numeric) AS active_outstanding,
    COALESCE(a.active_enrollments, (0)::bigint) AS active_enrollments,
    COALESCE(a.withdrawn_enrollments, (0)::bigint) AS withdrawn_enrollments,
    COALESCE(c.payment_count, (0)::bigint) AS payment_count
   FROM ((((keys k
     JOIN public.courses crs ON ((crs.id = k.course_id)))
     LEFT JOIN cash c ON (((c.course_id = k.course_id) AND (c.currency = k.currency))))
     LEFT JOIN refunds r ON (((r.course_id = k.course_id) AND (r.currency = k.currency))))
     LEFT JOIN accrual a ON (((a.course_id = k.course_id) AND (a.currency = k.currency))))
  WHERE (public.c1_is_admin() OR (auth.role() IS NULL) OR (auth.role() = 'service_role'::text));


--
-- Name: course_waitlist; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.course_waitlist (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    cohort_id uuid NOT NULL,
    trainee_id uuid NOT NULL,
    status text DEFAULT 'waiting'::text NOT NULL,
    joined_at timestamp with time zone DEFAULT clock_timestamp() NOT NULL,
    notified_at timestamp with time zone,
    expires_at timestamp with time zone,
    promoted_at timestamp with time zone,
    promoted_by uuid,
    cancelled_at timestamp with time zone,
    created_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT course_waitlist_expiry_order_check CHECK (((expires_at IS NULL) OR (notified_at IS NULL) OR (expires_at > notified_at))),
    CONSTRAINT course_waitlist_notified_fields_check CHECK (((status <> 'notified'::text) OR ((notified_at IS NOT NULL) AND (expires_at IS NOT NULL)))),
    CONSTRAINT course_waitlist_promoted_fields_check CHECK (((status <> 'enrolled'::text) OR (promoted_at IS NOT NULL))),
    CONSTRAINT course_waitlist_status_check CHECK ((status = ANY (ARRAY['waiting'::text, 'notified'::text, 'enrolled'::text, 'cancelled'::text, 'expired'::text])))
);


--
-- Name: cron_job_log; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.cron_job_log (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    job_name text NOT NULL,
    executed_at timestamp with time zone DEFAULT now() NOT NULL,
    opened_sessions_count integer DEFAULT 0 NOT NULL,
    closed_sessions_count integer DEFAULT 0 NOT NULL,
    missed_sessions_count integer DEFAULT 0 NOT NULL,
    details jsonb,
    status text DEFAULT 'success'::text NOT NULL
);


--
-- Name: expenses; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.expenses (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    category public.expense_category NOT NULL,
    amount numeric(10,2) NOT NULL,
    description text,
    expense_date date DEFAULT CURRENT_DATE NOT NULL,
    performed_by uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    currency public.currency_type DEFAULT 'SYP'::public.currency_type NOT NULL,
    CONSTRAINT expenses_amount_check CHECK ((amount > (0)::numeric))
);


--
-- Name: dashboard_kpis; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.dashboard_kpis AS
 WITH fin AS (
         SELECT enrollment_financial_summary_v2.enrollment_id,
            enrollment_financial_summary_v2.trainee_id,
            enrollment_financial_summary_v2.trainee_name,
            enrollment_financial_summary_v2.trainee_code,
            enrollment_financial_summary_v2.cohort_id,
            enrollment_financial_summary_v2.cohort_name,
            enrollment_financial_summary_v2.currency,
            enrollment_financial_summary_v2.legacy_payment_status,
            enrollment_financial_summary_v2.original_fee,
            enrollment_financial_summary_v2.total_discount,
            enrollment_financial_summary_v2.total_adjustments,
            enrollment_financial_summary_v2.net_due,
            enrollment_financial_summary_v2.gross_paid,
            enrollment_financial_summary_v2.total_refunded,
            enrollment_financial_summary_v2.net_paid,
            enrollment_financial_summary_v2.current_balance,
            enrollment_financial_summary_v2.total_installments,
            enrollment_financial_summary_v2.next_due_date,
            enrollment_financial_summary_v2.overdue_balance,
            enrollment_financial_summary_v2.course_name,
            enrollment_financial_summary_v2.total_due,
            enrollment_financial_summary_v2.total_paid,
            enrollment_financial_summary_v2.balance,
            enrollment_financial_summary_v2.payment_status,
            enrollment_financial_summary_v2.lifecycle_status
           FROM public.enrollment_financial_summary_v2
        ), kpi AS (
         SELECT ( SELECT count(*) AS count
                   FROM public.trainees) AS total_trainees,
            ( SELECT count(*) AS count
                   FROM (public.trainees t
                     JOIN public.users u ON ((u.id = t.user_id)))
                  WHERE (u.is_active = true)) AS active_trainees,
            ( SELECT count(*) AS count
                   FROM fin
                  WHERE ((fin.payment_status = 'partial'::text) AND (fin.lifecycle_status <> 'withdrawn'::text))) AS partial_count,
            ( SELECT count(*) AS count
                   FROM fin
                  WHERE ((fin.payment_status = 'unpaid'::text) AND (fin.lifecycle_status <> 'withdrawn'::text))) AS unpaid_count,
            COALESCE(( SELECT sum(p.amount) AS sum
                   FROM public.payments p
                  WHERE (p.currency = 'SYP'::public.currency_type)), (0)::numeric) AS total_paid_syp,
            COALESCE(( SELECT sum(p.amount) AS sum
                   FROM public.payments p
                  WHERE (p.currency = 'USD'::public.currency_type)), (0)::numeric) AS total_paid_usd,
            COALESCE(( SELECT sum(r.amount) AS sum
                   FROM (public.payment_refunds r
                     JOIN public.payments p ON ((p.id = r.payment_id)))
                  WHERE (p.currency = 'SYP'::public.currency_type)), (0)::numeric) AS total_refunded_syp,
            COALESCE(( SELECT sum(r.amount) AS sum
                   FROM (public.payment_refunds r
                     JOIN public.payments p ON ((p.id = r.payment_id)))
                  WHERE (p.currency = 'USD'::public.currency_type)), (0)::numeric) AS total_refunded_usd,
            COALESCE(( SELECT sum(x.amount) AS sum
                   FROM public.expenses x
                  WHERE (x.currency = 'SYP'::public.currency_type)), (0)::numeric) AS total_exp_syp,
            COALESCE(( SELECT sum(x.amount) AS sum
                   FROM public.expenses x
                  WHERE (x.currency = 'USD'::public.currency_type)), (0)::numeric) AS total_exp_usd,
            COALESCE(( SELECT sum(GREATEST(f.current_balance, (0)::numeric)) AS sum
                   FROM fin f
                  WHERE ((f.currency = 'SYP'::public.currency_type) AND (f.lifecycle_status <> 'withdrawn'::text))), (0)::numeric) AS total_balance_syp,
            COALESCE(( SELECT sum(GREATEST(f.current_balance, (0)::numeric)) AS sum
                   FROM fin f
                  WHERE ((f.currency = 'USD'::public.currency_type) AND (f.lifecycle_status <> 'withdrawn'::text))), (0)::numeric) AS total_balance_usd,
            COALESCE(( SELECT sum(GREATEST((f.net_paid - f.net_due), (0)::numeric)) AS sum
                   FROM fin f
                  WHERE (f.currency = 'SYP'::public.currency_type)), (0)::numeric) AS total_overpaid_syp,
            COALESCE(( SELECT sum(GREATEST((f.net_paid - f.net_due), (0)::numeric)) AS sum
                   FROM fin f
                  WHERE (f.currency = 'USD'::public.currency_type)), (0)::numeric) AS total_overpaid_usd,
            (COALESCE(( SELECT sum(p.amount) AS sum
                   FROM public.payments p
                  WHERE (p.currency = 'SYP'::public.currency_type)), (0)::numeric) - COALESCE(( SELECT sum(r.amount) AS sum
                   FROM (public.payment_refunds r
                     JOIN public.payments p ON ((p.id = r.payment_id)))
                  WHERE (p.currency = 'SYP'::public.currency_type)), (0)::numeric)) AS net_paid_syp,
            (COALESCE(( SELECT sum(p.amount) AS sum
                   FROM public.payments p
                  WHERE (p.currency = 'USD'::public.currency_type)), (0)::numeric) - COALESCE(( SELECT sum(r.amount) AS sum
                   FROM (public.payment_refunds r
                     JOIN public.payments p ON ((p.id = r.payment_id)))
                  WHERE (p.currency = 'USD'::public.currency_type)), (0)::numeric)) AS net_paid_usd
        ), authz AS (
         SELECT ((auth.role() IS NULL) OR (auth.role() = 'service_role'::text) OR public.c1_is_admin()) AS allow_financials
        )
 SELECT k.total_trainees,
    k.active_trainees,
        CASE
            WHEN a.allow_financials THEN k.partial_count
            ELSE NULL::bigint
        END AS partial_count,
        CASE
            WHEN a.allow_financials THEN k.unpaid_count
            ELSE NULL::bigint
        END AS unpaid_count,
        CASE
            WHEN a.allow_financials THEN k.total_paid_syp
            ELSE NULL::numeric
        END AS total_paid_syp,
        CASE
            WHEN a.allow_financials THEN k.total_paid_usd
            ELSE NULL::numeric
        END AS total_paid_usd,
        CASE
            WHEN a.allow_financials THEN k.total_refunded_syp
            ELSE NULL::numeric
        END AS total_refunded_syp,
        CASE
            WHEN a.allow_financials THEN k.total_refunded_usd
            ELSE NULL::numeric
        END AS total_refunded_usd,
        CASE
            WHEN a.allow_financials THEN k.total_exp_syp
            ELSE NULL::numeric
        END AS total_exp_syp,
        CASE
            WHEN a.allow_financials THEN k.total_exp_usd
            ELSE NULL::numeric
        END AS total_exp_usd,
        CASE
            WHEN a.allow_financials THEN k.total_balance_syp
            ELSE NULL::numeric
        END AS total_balance_syp,
        CASE
            WHEN a.allow_financials THEN k.total_balance_usd
            ELSE NULL::numeric
        END AS total_balance_usd,
        CASE
            WHEN a.allow_financials THEN k.total_overpaid_syp
            ELSE NULL::numeric
        END AS total_overpaid_syp,
        CASE
            WHEN a.allow_financials THEN k.total_overpaid_usd
            ELSE NULL::numeric
        END AS total_overpaid_usd,
        CASE
            WHEN a.allow_financials THEN k.net_paid_syp
            ELSE NULL::numeric
        END AS net_paid_syp,
        CASE
            WHEN a.allow_financials THEN k.net_paid_usd
            ELSE NULL::numeric
        END AS net_paid_usd,
        CASE
            WHEN a.allow_financials THEN (k.net_paid_syp - k.total_exp_syp)
            ELSE NULL::numeric
        END AS net_profit_syp,
        CASE
            WHEN a.allow_financials THEN (k.net_paid_usd - k.total_exp_usd)
            ELSE NULL::numeric
        END AS net_profit_usd
   FROM (kpi k
     CROSS JOIN authz a)
  WHERE public.c1_can_read_financials(NULL::uuid);


--
-- Name: VIEW dashboard_kpis; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.dashboard_kpis IS 'KPIs: one row for every staff member. total_trainees/active_trainees always visible; all financial columns are NULL unless admin or trusted backend context.';


--
-- Name: debt_aging_report; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.debt_aging_report WITH (security_invoker='true') AS
 SELECT
        CASE
            WHEN ((CURRENT_DATE - (en.enrolled_at)::date) < 30) THEN 'less_than_30'::text
            WHEN (((CURRENT_DATE - (en.enrolled_at)::date) >= 30) AND ((CURRENT_DATE - (en.enrolled_at)::date) <= 90)) THEN 'between_30_and_90'::text
            ELSE 'more_than_90'::text
        END AS aging_bracket,
    efs.currency,
    count(efs.enrollment_id) AS enrollments_count,
    COALESCE(sum(efs.balance), (0)::numeric) AS total_overdue_balance
   FROM (public.enrollment_financial_summary efs
     JOIN public.enrollments en ON ((en.id = efs.enrollment_id)))
  WHERE (efs.balance > (0)::numeric)
  GROUP BY
        CASE
            WHEN ((CURRENT_DATE - (en.enrolled_at)::date) < 30) THEN 'less_than_30'::text
            WHEN (((CURRENT_DATE - (en.enrolled_at)::date) >= 30) AND ((CURRENT_DATE - (en.enrolled_at)::date) <= 90)) THEN 'between_30_and_90'::text
            ELSE 'more_than_90'::text
        END, efs.currency;


--
-- Name: debt_aging_report_v2; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.debt_aging_report_v2 AS
 WITH alloc AS (
         SELECT pa.installment_id,
            sum(pa.amount) AS allocated
           FROM public.payment_allocations pa
          GROUP BY pa.installment_id
        ), open_installments AS (
         SELECT s.id,
            s.enrollment_id,
            s.due_date,
            (s.currency)::text AS currency,
            e.trainee_id,
            GREATEST((s.amount - COALESCE(a.allocated, (0)::numeric)), (0)::numeric) AS remaining,
            (((now() AT TIME ZONE 'Asia/Damascus'::text))::date - s.due_date) AS days_overdue
           FROM ((public.installment_schedule s
             JOIN public.enrollments e ON ((e.id = s.enrollment_id)))
             LEFT JOIN alloc a ON ((a.installment_id = s.id)))
          WHERE ((e.lifecycle_status <> 'withdrawn'::text) AND (s.due_date < ((now() AT TIME ZONE 'Asia/Damascus'::text))::date))
        )
 SELECT currency,
        CASE
            WHEN (days_overdue <= 30) THEN '1-30'::text
            WHEN (days_overdue <= 90) THEN '31-90'::text
            ELSE '>90'::text
        END AS aging_bucket,
    sum(remaining) AS total_overdue_balance,
    count(*) AS installments_count,
    count(DISTINCT trainee_id) AS trainees_count,
    min(due_date) AS oldest_due_date
   FROM open_installments
  WHERE ((remaining > (0)::numeric) AND (public.c1_is_admin() OR (auth.role() IS NULL) OR (auth.role() = 'service_role'::text)))
  GROUP BY currency,
        CASE
            WHEN (days_overdue <= 30) THEN '1-30'::text
            WHEN (days_overdue <= 90) THEN '31-90'::text
            ELSE '>90'::text
        END;


--
-- Name: discounts_report; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.discounts_report WITH (security_invoker='true') AS
 SELECT efs.course_name,
    efs.currency,
    count(efs.enrollment_id) AS discounted_trainees_count,
    COALESCE(sum(en.discount_amount), (0)::numeric) AS total_discounts
   FROM (public.enrollment_financial_summary efs
     JOIN public.enrollments en ON ((en.id = efs.enrollment_id)))
  WHERE (en.discount_amount > (0)::numeric)
  GROUP BY efs.course_name, efs.currency
  ORDER BY COALESCE(sum(en.discount_amount), (0)::numeric) DESC;


--
-- Name: discounts_report_v2; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.discounts_report_v2 AS
 WITH manual AS (
         SELECT fa.enrollment_id,
            sum(
                CASE
                    WHEN ((fa.kind = 'manual'::text) AND (fa.amount < (0)::numeric)) THEN (- fa.amount)
                    ELSE (0)::numeric
                END) AS manual_discounts,
            count(*) FILTER (WHERE ((fa.kind = 'manual'::text) AND (fa.amount < (0)::numeric))) AS manual_count
           FROM public.fee_adjustments fa
          GROUP BY fa.enrollment_id
        )
 SELECT e.id AS enrollment_id,
    t.trainee_code,
    u.full_name AS trainee_name,
    crs.name AS course_name,
    (e.currency)::text AS currency,
    COALESCE(e.discount_amount, (0)::numeric) AS original_discount,
    COALESCE(m.manual_discounts, (0)::numeric) AS manual_discounts,
    (COALESCE(e.discount_amount, (0)::numeric) + COALESCE(m.manual_discounts, (0)::numeric)) AS total_discounts,
    COALESCE(m.manual_count, (0)::bigint) AS manual_count
   FROM (((((public.enrollments e
     JOIN public.trainees t ON ((t.id = e.trainee_id)))
     LEFT JOIN public.users u ON ((u.id = t.user_id)))
     LEFT JOIN public.cohorts co ON ((co.id = e.cohort_id)))
     LEFT JOIN public.courses crs ON ((crs.id = co.course_id)))
     LEFT JOIN manual m ON ((m.enrollment_id = e.id)))
  WHERE ((e.lifecycle_status <> 'withdrawn'::text) AND ((COALESCE(e.discount_amount, (0)::numeric) + COALESCE(m.manual_discounts, (0)::numeric)) > (0)::numeric) AND (public.c1_is_admin() OR (auth.role() IS NULL) OR (auth.role() = 'service_role'::text)));


--
-- Name: enrollment_withdrawals; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.enrollment_withdrawals (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    enrollment_id uuid NOT NULL,
    trainee_id uuid NOT NULL,
    currency text NOT NULL,
    total_sessions integer NOT NULL,
    sessions_charged integer NOT NULL,
    sessions_overridden boolean DEFAULT false NOT NULL,
    session_cost numeric(12,2) NOT NULL,
    net_due_before numeric(12,2) NOT NULL,
    net_due_after numeric(12,2) NOT NULL,
    net_paid_before numeric(12,2) NOT NULL,
    net_paid_after numeric(12,2) NOT NULL,
    discount_revoked numeric(12,2) DEFAULT 0 NOT NULL,
    due_amount numeric(12,2) NOT NULL,
    settlement_delta numeric(12,2) DEFAULT 0 NOT NULL,
    refund_amount numeric(12,2) DEFAULT 0 NOT NULL,
    writeoff_amount numeric(12,2) DEFAULT 0 NOT NULL,
    outcome text NOT NULL,
    reason text NOT NULL,
    withdrawn_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT enrollment_withdrawals_due_amount_check CHECK ((due_amount >= (0)::numeric)),
    CONSTRAINT enrollment_withdrawals_net_due_after_check CHECK ((net_due_after >= (0)::numeric)),
    CONSTRAINT enrollment_withdrawals_outcome_check CHECK ((outcome = ANY (ARRAY['settled'::text, 'refund'::text, 'debt'::text, 'writeoff'::text]))),
    CONSTRAINT enrollment_withdrawals_refund_amount_check CHECK ((refund_amount >= (0)::numeric)),
    CONSTRAINT enrollment_withdrawals_session_cost_check CHECK ((session_cost >= (0)::numeric)),
    CONSTRAINT enrollment_withdrawals_sessions_charged_check CHECK ((sessions_charged >= 0)),
    CONSTRAINT enrollment_withdrawals_total_sessions_check CHECK ((total_sessions > 0)),
    CONSTRAINT enrollment_withdrawals_writeoff_amount_check CHECK ((writeoff_amount >= (0)::numeric))
);


--
-- Name: expenses_by_category_report; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.expenses_by_category_report WITH (security_invoker='true') AS
 SELECT category,
    currency,
    count(id) AS expense_count,
    COALESCE(sum(amount), (0)::numeric) AS total_spent
   FROM public.expenses
  GROUP BY category, currency
  ORDER BY COALESCE(sum(amount), (0)::numeric) DESC;


--
-- Name: expenses_by_category_report_v2; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.expenses_by_category_report_v2 AS
 SELECT category,
    (currency)::text AS currency,
    sum(amount) AS total_spent,
    count(*) AS expense_count
   FROM public.expenses x
  WHERE (public.c1_is_admin() OR (auth.role() IS NULL) OR (auth.role() = 'service_role'::text))
  GROUP BY category, (currency)::text;


--
-- Name: lab_clients; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.lab_clients (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text NOT NULL,
    phone text,
    clinic_address text,
    notes text,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    updated_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL
);


--
-- Name: lab_expenses; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.lab_expenses (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    title text NOT NULL,
    category text DEFAULT 'materials'::text NOT NULL,
    amount numeric(12,2) NOT NULL,
    currency text DEFAULT 'SYP'::text NOT NULL,
    expense_date date DEFAULT CURRENT_DATE NOT NULL,
    payment_method text DEFAULT 'cash'::text NOT NULL,
    notes text,
    performed_by uuid,
    created_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    CONSTRAINT lab_expenses_amount_check CHECK ((amount > (0)::numeric)),
    CONSTRAINT lab_expenses_category_check CHECK ((category = ANY (ARRAY['materials'::text, 'equipment_maintenance'::text, 'utilities'::text, 'salaries'::text, 'other'::text]))),
    CONSTRAINT lab_expenses_currency_check CHECK ((currency = ANY (ARRAY['SYP'::text, 'USD'::text]))),
    CONSTRAINT lab_expenses_payment_method_check CHECK ((payment_method = ANY (ARRAY['cash'::text, 'sham_cash'::text, 'hawala'::text, 'bank_transfer'::text])))
);


--
-- Name: lab_invoice_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.lab_invoice_items (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    invoice_id uuid NOT NULL,
    service_name text NOT NULL,
    tooth_number text,
    shade text,
    quantity integer DEFAULT 1 NOT NULL,
    unit_price numeric(12,2) DEFAULT 0.00 NOT NULL,
    total_price numeric(12,2) DEFAULT 0.00 NOT NULL,
    notes text,
    created_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    CONSTRAINT lab_invoice_items_quantity_check CHECK ((quantity > 0)),
    CONSTRAINT lab_invoice_items_total_price_check CHECK ((total_price >= (0)::numeric)),
    CONSTRAINT lab_invoice_items_unit_price_check CHECK ((unit_price >= (0)::numeric))
);


--
-- Name: lab_invoice_number_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.lab_invoice_number_seq
    START WITH 1001
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: lab_invoices; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.lab_invoices (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    invoice_number integer NOT NULL,
    client_id uuid NOT NULL,
    patient_name text,
    status text DEFAULT 'unpaid'::text NOT NULL,
    currency text DEFAULT 'SYP'::text NOT NULL,
    subtotal numeric(12,2) DEFAULT 0.00 NOT NULL,
    discount numeric(12,2) DEFAULT 0.00 NOT NULL,
    total_amount numeric(12,2) DEFAULT 0.00 NOT NULL,
    paid_amount numeric(12,2) DEFAULT 0.00 NOT NULL,
    issue_date date DEFAULT CURRENT_DATE NOT NULL,
    due_date date,
    notes text,
    created_by uuid,
    created_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    updated_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    CONSTRAINT lab_invoices_currency_check CHECK ((currency = ANY (ARRAY['SYP'::text, 'USD'::text]))),
    CONSTRAINT lab_invoices_discount_check CHECK ((discount >= (0)::numeric)),
    CONSTRAINT lab_invoices_paid_amount_check CHECK ((paid_amount >= (0)::numeric)),
    CONSTRAINT lab_invoices_status_check CHECK ((status = ANY (ARRAY['unpaid'::text, 'partial'::text, 'paid'::text, 'cancelled'::text]))),
    CONSTRAINT lab_invoices_subtotal_check CHECK ((subtotal >= (0)::numeric)),
    CONSTRAINT lab_invoices_total_amount_check CHECK ((total_amount >= (0)::numeric))
);


--
-- Name: lab_payments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.lab_payments (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    invoice_id uuid NOT NULL,
    amount numeric(12,2) NOT NULL,
    currency text DEFAULT 'SYP'::text NOT NULL,
    paid_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    method text NOT NULL,
    receipt_number text,
    external_reference text,
    notes text,
    performed_by uuid,
    created_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    CONSTRAINT lab_payments_amount_check CHECK ((amount > (0)::numeric)),
    CONSTRAINT lab_payments_currency_check CHECK ((currency = ANY (ARRAY['SYP'::text, 'USD'::text]))),
    CONSTRAINT lab_payments_method_check CHECK ((method = ANY (ARRAY['cash'::text, 'sham_cash'::text, 'hawala'::text, 'bank_transfer'::text])))
);


--
-- Name: monthly_targets; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.monthly_targets (
    month_key text NOT NULL,
    target_syp numeric DEFAULT 0 NOT NULL,
    target_usd numeric DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by uuid,
    CONSTRAINT monthly_targets_target_syp_check CHECK ((target_syp >= (0)::numeric)),
    CONSTRAINT monthly_targets_target_usd_check CHECK ((target_usd >= (0)::numeric))
);


--
-- Name: notification_outbox; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.notification_outbox (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    type text NOT NULL,
    title text NOT NULL,
    body text NOT NULL,
    data jsonb DEFAULT '{}'::jsonb NOT NULL,
    dedupe_key text NOT NULL,
    status text DEFAULT 'pending'::text NOT NULL,
    attempts integer DEFAULT 0 NOT NULL,
    max_attempts integer DEFAULT 3 NOT NULL,
    next_attempt_at timestamp with time zone DEFAULT now() NOT NULL,
    locked_at timestamp with time zone,
    sent_at timestamp with time zone,
    last_error text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT notification_outbox_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'processing'::text, 'sent'::text, 'failed'::text, 'skipped'::text]))),
    CONSTRAINT notification_outbox_type_check CHECK ((type = ANY (ARRAY['session_reminder'::text, 'survey_reminder'::text, 'payment_reminder'::text, 'custom'::text, 'waitlist_available'::text, 'referral_qualified'::text])))
);


--
-- Name: open_sessions_view; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.open_sessions_view AS
SELECT
    NULL::uuid AS id,
    NULL::uuid AS cohort_id,
    NULL::integer AS session_number,
    NULL::uuid AS qr_token,
    NULL::timestamp with time zone AS opened_at,
    NULL::text AS cohort_name,
    NULL::text AS course_name,
    NULL::bigint AS attendees_count;


--
-- Name: overdue_installments_v; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.overdue_installments_v AS
 SELECT s.id AS installment_id,
    s.enrollment_id,
    e.trainee_id,
    t.trainee_code,
    u.full_name AS trainee_name,
    u.phone AS trainee_phone,
    co.id AS cohort_id,
    co.name AS cohort_name,
    s.installment_number,
    s.due_date,
    s.amount AS installment_amount,
    COALESCE(alloc.allocated, (0)::numeric) AS paid_amount,
    (s.amount - COALESCE(alloc.allocated, (0)::numeric)) AS overdue_amount,
    s.currency,
    (((now() AT TIME ZONE 'Asia/Damascus'::text))::date - s.due_date) AS days_overdue,
    (e.status)::text AS enrollment_status,
    e.lifecycle_status
   FROM (((((public.installment_schedule s
     JOIN public.enrollments e ON ((e.id = s.enrollment_id)))
     JOIN public.trainees t ON ((t.id = e.trainee_id)))
     JOIN public.users u ON ((u.id = t.user_id)))
     JOIN public.cohorts co ON ((co.id = e.cohort_id)))
     LEFT JOIN ( SELECT payment_allocations.installment_id,
            sum(payment_allocations.amount) AS allocated
           FROM public.payment_allocations
          GROUP BY payment_allocations.installment_id) alloc ON ((alloc.installment_id = s.id)))
  WHERE ((s.due_date < ((now() AT TIME ZONE 'Asia/Damascus'::text))::date) AND ((s.amount - COALESCE(alloc.allocated, (0)::numeric)) > (0)::numeric) AND public.enrollment_lifecycle_occupies_seat(e.lifecycle_status) AND public.c1_can_read_financials(t.user_id));


--
-- Name: overdue_payments; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.overdue_payments AS
 SELECT v.enrollment_id,
    v.trainee_id,
    v.trainee_name,
    v.trainee_code,
    v.course_name,
    v.current_balance AS balance_due,
    v.currency,
    v.payment_status,
    u.phone,
    t.whatsapp_number,
    v.lifecycle_status
   FROM ((public.enrollment_financial_summary_v2 v
     JOIN public.trainees t ON ((t.id = v.trainee_id)))
     LEFT JOIN public.users u ON ((u.id = t.user_id)))
  WHERE ((v.payment_status = ANY (ARRAY['partial'::text, 'unpaid'::text])) AND (v.current_balance > (0)::numeric) AND (v.lifecycle_status <> 'withdrawn'::text));


--
-- Name: VIEW overdue_payments; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.overdue_payments IS 'الأرصدة المستحقة الصافية وفق v2. التسجيلات المنسحبة مستبعدة افتراضياً (تبقى أرصدتها في v2 وكشف الحساب).';


--
-- Name: profit_loss_report; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.profit_loss_report WITH (security_invoker='true') AS
 SELECT date_trunc('month'::text, period_date) AS month,
    sum(income) AS total_income,
    sum(expense) AS total_expenses,
    (sum(income) - sum(expense)) AS net_profit
   FROM ( SELECT payments.paid_at AS period_date,
            payments.amount AS income,
            0 AS expense
           FROM public.payments
        UNION ALL
         SELECT (expenses.expense_date)::timestamp with time zone AS expense_date,
            0,
            expenses.amount
           FROM public.expenses) combined
  GROUP BY (date_trunc('month'::text, period_date))
  ORDER BY (date_trunc('month'::text, period_date));


--
-- Name: profit_loss_report_v2; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.profit_loss_report_v2 AS
 WITH events AS (
         SELECT (p.currency)::text AS currency,
            (date_trunc('month'::text, (p.paid_at AT TIME ZONE 'Asia/Damascus'::text)))::date AS month,
            p.amount AS income_amount,
            (0)::numeric AS refund_amount,
            (0)::numeric AS expense_amount
           FROM public.payments p
        UNION ALL
         SELECT (p.currency)::text AS currency,
            (date_trunc('month'::text, (r.refunded_at AT TIME ZONE 'Asia/Damascus'::text)))::date AS date_trunc,
            (0)::numeric AS "numeric",
            r.amount,
            (0)::numeric AS "numeric"
           FROM (public.payment_refunds r
             JOIN public.payments p ON ((p.id = r.payment_id)))
        UNION ALL
         SELECT (x.currency)::text AS currency,
            (date_trunc('month'::text, (x.expense_date)::timestamp with time zone))::date AS date_trunc,
            (0)::numeric AS "numeric",
            (0)::numeric AS "numeric",
            x.amount
           FROM public.expenses x
        )
 SELECT month,
    currency,
    sum(income_amount) AS cash_income,
    sum(refund_amount) AS refunds,
    (sum(income_amount) - sum(refund_amount)) AS net_income,
    sum(expense_amount) AS expenses,
    ((sum(income_amount) - sum(refund_amount)) - sum(expense_amount)) AS net_profit
   FROM events
  WHERE (public.c1_is_admin() OR (auth.role() IS NULL) OR (auth.role() = 'service_role'::text))
  GROUP BY month, currency;


--
-- Name: referrals; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.referrals (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    referrer_trainee_id uuid NOT NULL,
    referee_trainee_id uuid NOT NULL,
    code_used text NOT NULL,
    course_id uuid NOT NULL,
    enrollment_id uuid NOT NULL,
    discount_amount numeric(12,2) NOT NULL,
    currency text NOT NULL,
    status text DEFAULT 'available'::text NOT NULL,
    applied_enrollment_id uuid,
    applied_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT referrals_applied_fields_check CHECK (((status <> 'applied'::text) OR ((applied_enrollment_id IS NOT NULL) AND (applied_at IS NOT NULL)))),
    CONSTRAINT referrals_discount_positive CHECK ((discount_amount > (0)::numeric)),
    CONSTRAINT referrals_no_self CHECK ((referrer_trainee_id <> referee_trainee_id)),
    CONSTRAINT referrals_status_check CHECK ((status = ANY (ARRAY['available'::text, 'applied'::text, 'cancelled'::text])))
);


--
-- Name: revenue_by_method_report; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.revenue_by_method_report WITH (security_invoker='true') AS
 SELECT method,
    currency,
    count(id) AS payments_count,
    COALESCE(sum(amount), (0)::numeric) AS total_amount
   FROM public.payments
  GROUP BY method, currency
  ORDER BY COALESCE(sum(amount), (0)::numeric) DESC;


--
-- Name: revenue_by_method_report_v2; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.revenue_by_method_report_v2 AS
 WITH gross AS (
         SELECT p.method,
            (p.currency)::text AS currency,
            sum(p.amount) AS gross_collected,
            count(*) AS payment_count
           FROM public.payments p
          GROUP BY p.method, (p.currency)::text
        ), refunds AS (
         SELECT p.method,
            (p.currency)::text AS currency,
            sum(r_1.amount) AS refunded
           FROM (public.payment_refunds r_1
             JOIN public.payments p ON ((p.id = r_1.payment_id)))
          GROUP BY p.method, (p.currency)::text
        )
 SELECT COALESCE(g.method, r.method) AS method,
    COALESCE(g.currency, r.currency) AS currency,
    COALESCE(g.gross_collected, (0)::numeric) AS gross_collected,
    COALESCE(r.refunded, (0)::numeric) AS refunds,
    (COALESCE(g.gross_collected, (0)::numeric) - COALESCE(r.refunded, (0)::numeric)) AS net_collected,
    COALESCE(g.payment_count, (0)::bigint) AS payment_count
   FROM (gross g
     FULL JOIN refunds r ON (((NOT (r.method IS DISTINCT FROM g.method)) AND (r.currency = g.currency))))
  WHERE (public.c1_is_admin() OR (auth.role() IS NULL) OR (auth.role() = 'service_role'::text));


--
-- Name: sessions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sessions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    cohort_id uuid NOT NULL,
    session_number integer NOT NULL,
    scheduled_at timestamp with time zone NOT NULL,
    status public.session_status DEFAULT 'scheduled'::public.session_status NOT NULL,
    qr_token uuid,
    notes text,
    opened_at timestamp with time zone,
    closed_at timestamp with time zone,
    opened_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    is_extra boolean DEFAULT false NOT NULL,
    title text,
    description text,
    duration_minutes integer DEFAULT 120 NOT NULL
);


--
-- Name: survey_dispatches; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.survey_dispatches (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    enrollment_id uuid NOT NULL,
    template_id uuid NOT NULL,
    at_session_count integer NOT NULL,
    status public.survey_dispatch_status DEFAULT 'pending'::public.survey_dispatch_status NOT NULL,
    dispatched_at timestamp with time zone DEFAULT now() NOT NULL,
    read_at timestamp with time zone
);


--
-- Name: survey_responses; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.survey_responses (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    dispatch_id uuid NOT NULL,
    answers jsonb NOT NULL,
    submitted_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: survey_templates; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.survey_templates (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    title text NOT NULL,
    questions jsonb NOT NULL,
    trigger_after_sessions integer DEFAULT 3 NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid NOT NULL
);


--
-- Name: survey_statistics; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.survey_statistics WITH (security_invoker='true') AS
 SELECT st.title AS survey_title,
    count(sr.id) AS total_responses,
    round(avg(((sr.answers ->> 'q1'::text))::numeric), 2) AS avg_rating,
    round((((count(
        CASE
            WHEN (((sr.answers ->> 'q1'::text))::integer >= 4) THEN 1
            ELSE NULL::integer
        END))::numeric * 100.0) / (NULLIF(count(sr.id), 0))::numeric)) AS satisfaction_rate
   FROM ((public.survey_templates st
     LEFT JOIN public.survey_dispatches sd ON ((sd.template_id = st.id)))
     LEFT JOIN public.survey_responses sr ON ((sr.dispatch_id = sd.id)))
  GROUP BY st.id, st.title;


--
-- Name: trainee_academic_progress; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.trainee_academic_progress AS
 SELECT e.id AS enrollment_id,
    e.trainee_id,
    u.full_name AS trainee_name,
    co.name AS course_name,
    co.total_sessions,
    count(a.id) AS sessions_attended,
    GREATEST((0)::bigint, (co.total_sessions - count(a.id))) AS sessions_remaining,
    LEAST((100)::numeric, round((((count(a.id))::numeric * 100.0) / (NULLIF(co.total_sessions, 0))::numeric))) AS attendance_percentage,
    count(a.id) FILTER (WHERE (s.is_extra IS NOT TRUE)) AS base_sessions_attended,
    count(a.id) FILTER (WHERE (s.is_extra IS TRUE)) AS extra_sessions_attended,
    count(DISTINCT s.id) FILTER (WHERE (s.is_extra IS TRUE)) AS extra_sessions_count,
    co.id AS course_id
   FROM ((((((public.enrollments e
     JOIN public.trainees t ON ((t.id = e.trainee_id)))
     JOIN public.users u ON ((u.id = t.user_id)))
     JOIN public.cohorts ch ON ((ch.id = e.cohort_id)))
     JOIN public.courses co ON ((co.id = ch.course_id)))
     LEFT JOIN public.sessions s ON ((s.cohort_id = ch.id)))
     LEFT JOIN public.attendance a ON (((a.session_id = s.id) AND (a.trainee_id = e.trainee_id))))
  WHERE (public.c1_is_staff() OR (t.user_id = auth.uid()) OR (auth.role() IS NULL) OR (auth.role() = 'service_role'::text))
  GROUP BY e.id, e.trainee_id, u.full_name, co.id, co.name, co.total_sessions;


--
-- Name: trainee_code_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.trainee_code_seq
    START WITH 10155
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: trainee_next_sessions; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.trainee_next_sessions AS
 SELECT s.id AS session_id,
    s.cohort_id,
    s.session_number,
    s.title,
    s.description,
    s.scheduled_at,
    s.duration_minutes,
    s.status,
    s.is_extra,
    c.name AS cohort_name,
    cr.id AS course_id,
    cr.name AS course_name,
    t.id AS trainee_id,
    t.user_id,
    (a.id IS NOT NULL) AS is_attended
   FROM (((((public.sessions s
     JOIN public.cohorts c ON ((c.id = s.cohort_id)))
     JOIN public.courses cr ON ((cr.id = c.course_id)))
     JOIN public.enrollments e ON ((e.cohort_id = c.id)))
     JOIN public.trainees t ON ((t.id = e.trainee_id)))
     LEFT JOIN public.attendance a ON (((a.session_id = s.id) AND (a.trainee_id = t.id))))
  WHERE ((s.status = ANY (ARRAY['scheduled'::public.session_status, 'open'::public.session_status])) AND ((s.scheduled_at >= (now() - '04:00:00'::interval)) OR (s.status = 'open'::public.session_status)) AND (e.lifecycle_status <> 'withdrawn'::text) AND ((t.user_id = auth.uid()) OR (auth.role() = 'service_role'::text) OR ((auth.jwt() ->> 'role'::text) = 'service_role'::text) OR (CURRENT_USER = 'postgres'::name)));


--
-- Name: trainee_payment_receipts; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.trainee_payment_receipts AS
 SELECT p.id AS payment_id,
    p.enrollment_id,
    p.amount,
    p.currency,
    p.paid_at,
    p.method AS payment_method,
    p.receipt_number,
    p.external_reference,
    p.notes,
    c.id AS course_id,
    c.name AS course_name,
    ch.id AS cohort_id,
    ch.name AS cohort_name,
    t.id AS trainee_id,
    t.trainee_code,
    u.full_name AS trainee_name
   FROM (((((public.payments p
     JOIN public.enrollments e ON ((e.id = p.enrollment_id)))
     JOIN public.cohorts ch ON ((ch.id = e.cohort_id)))
     JOIN public.courses c ON ((c.id = ch.course_id)))
     JOIN public.trainees t ON ((t.id = e.trainee_id)))
     JOIN public.users u ON ((u.id = t.user_id)))
  WHERE ((t.user_id = auth.uid()) OR (auth.role() = 'service_role'::text) OR ((auth.jwt() ->> 'role'::text) = 'service_role'::text) OR (CURRENT_USER = 'postgres'::name));


--
-- Name: trainee_safe_profile; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.trainee_safe_profile WITH (security_invoker='true') AS
 SELECT t.id,
    t.user_id,
    t.trainee_code,
    COALESCE(t.full_name_ar, u.full_name) AS full_name,
    t.full_name_ar,
    t.full_name_en,
    u.email,
    u.phone,
    t.whatsapp_number,
    t.university_name,
    t.academic_year,
    t.province,
    t.address,
    t.created_at
   FROM (public.trainees t
     JOIN public.users u ON ((u.id = t.user_id)));


--
-- Name: trainee_statement_v; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.trainee_statement_v AS
 WITH ledger_entries AS (
         SELECT e.id AS enrollment_id,
            e.trainee_id,
            (e.id)::text AS entry_id,
            COALESCE((co.starts_at)::timestamp with time zone, co.created_at, now()) AS entry_date,
            'initial_fee'::text AS entry_type,
            ('رسوم التسجيل الأساسية - '::text || co.name) AS description,
            e.total_due AS debit,
            (0)::numeric AS credit,
            e.currency
           FROM (public.enrollments e
             JOIN public.cohorts co ON ((co.id = e.cohort_id)))
        UNION ALL
         SELECT e.id,
            e.trainee_id,
            ((e.id)::text || '_disc'::text),
            COALESCE((co.starts_at)::timestamp with time zone, co.created_at, now()) AS "coalesce",
            'discount'::text,
            'خصم تسجيل معتمد'::text,
            (0)::numeric AS "numeric",
            e.discount_amount,
            e.currency
           FROM (public.enrollments e
             JOIN public.cohorts co ON ((co.id = e.cohort_id)))
          WHERE (COALESCE(e.discount_amount, (0)::numeric) > (0)::numeric)
        UNION ALL
         SELECT fa.enrollment_id,
            e.trainee_id,
            (fa.id)::text AS id,
            fa.adjusted_at,
            'fee_adjustment'::text,
            ('تعديل رسوم: '::text || fa.reason),
                CASE
                    WHEN (fa.amount > (0)::numeric) THEN fa.amount
                    ELSE (0)::numeric
                END AS "case",
                CASE
                    WHEN (fa.amount < (0)::numeric) THEN abs(fa.amount)
                    ELSE (0)::numeric
                END AS "case",
            e.currency
           FROM (public.fee_adjustments fa
             JOIN public.enrollments e ON ((e.id = fa.enrollment_id)))
        UNION ALL
         SELECT p.enrollment_id,
            e.trainee_id,
            (p.id)::text AS id,
            p.paid_at,
            'payment'::text,
            ('دفعة نقدية/تحويل - إيصال #'::text || COALESCE(p.receipt_number, "substring"((p.id)::text, 1, 8))),
            (0)::numeric AS "numeric",
            p.amount,
            p.currency
           FROM (public.payments p
             JOIN public.enrollments e ON ((e.id = p.enrollment_id)))
        UNION ALL
         SELECT p.enrollment_id,
            e.trainee_id,
            (r.id)::text AS id,
            r.refunded_at,
            'refund'::text,
            ('استرداد دفعة: '::text || r.reason),
            r.amount,
            (0)::numeric AS "numeric",
            p.currency
           FROM ((public.payment_refunds r
             JOIN public.payments p ON ((p.id = r.payment_id)))
             JOIN public.enrollments e ON ((e.id = p.enrollment_id)))
        )
 SELECT le.enrollment_id,
    le.trainee_id,
    t.trainee_code,
    u.full_name AS trainee_name,
    le.entry_id,
    le.entry_date,
    le.entry_type,
    le.description,
    le.debit,
    le.credit,
    le.currency,
    sum((le.debit - le.credit)) OVER (PARTITION BY le.enrollment_id ORDER BY le.entry_date,
        CASE le.entry_type
            WHEN 'initial_fee'::text THEN 1
            WHEN 'discount'::text THEN 2
            WHEN 'fee_adjustment'::text THEN 3
            WHEN 'payment'::text THEN 4
            WHEN 'refund'::text THEN 5
            ELSE 6
        END, le.entry_id) AS running_balance
   FROM ((ledger_entries le
     JOIN public.trainees t ON ((t.id = le.trainee_id)))
     JOIN public.users u ON ((u.id = t.user_id)))
  WHERE public.c1_can_read_financials(t.user_id);


--
-- Name: user_fcm_tokens; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_fcm_tokens (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    fcm_token text NOT NULL,
    device_type text DEFAULT 'android'::text NOT NULL,
    device_id text,
    is_active boolean DEFAULT true NOT NULL,
    last_seen_at timestamp with time zone DEFAULT now() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT user_fcm_tokens_device_type_check CHECK ((device_type = ANY (ARRAY['android'::text, 'ios'::text, 'web'::text])))
);


--
-- Name: user_pins; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_pins (
    user_id uuid NOT NULL,
    pin_hash text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: audit_log id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_log ALTER COLUMN id SET DEFAULT nextval('public.audit_log_id_seq'::regclass);


--
-- Name: attendance attendance_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendance
    ADD CONSTRAINT attendance_pkey PRIMARY KEY (id);


--
-- Name: attendance attendance_session_id_trainee_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendance
    ADD CONSTRAINT attendance_session_id_trainee_id_key UNIQUE (session_id, trainee_id);


--
-- Name: audit_log audit_log_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_log
    ADD CONSTRAINT audit_log_pkey PRIMARY KEY (id);


--
-- Name: cohorts cohorts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cohorts
    ADD CONSTRAINT cohorts_pkey PRIMARY KEY (id);


--
-- Name: course_materials course_materials_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.course_materials
    ADD CONSTRAINT course_materials_pkey PRIMARY KEY (id);


--
-- Name: course_waitlist course_waitlist_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.course_waitlist
    ADD CONSTRAINT course_waitlist_pkey PRIMARY KEY (id);


--
-- Name: courses courses_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.courses
    ADD CONSTRAINT courses_pkey PRIMARY KEY (id);


--
-- Name: cron_job_log cron_job_log_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cron_job_log
    ADD CONSTRAINT cron_job_log_pkey PRIMARY KEY (id);


--
-- Name: enrollment_withdrawals enrollment_withdrawals_enrollment_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.enrollment_withdrawals
    ADD CONSTRAINT enrollment_withdrawals_enrollment_id_key UNIQUE (enrollment_id);


--
-- Name: enrollment_withdrawals enrollment_withdrawals_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.enrollment_withdrawals
    ADD CONSTRAINT enrollment_withdrawals_pkey PRIMARY KEY (id);


--
-- Name: enrollments enrollments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.enrollments
    ADD CONSTRAINT enrollments_pkey PRIMARY KEY (id);


--
-- Name: enrollments enrollments_trainee_id_cohort_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.enrollments
    ADD CONSTRAINT enrollments_trainee_id_cohort_id_key UNIQUE (trainee_id, cohort_id);


--
-- Name: expenses expenses_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.expenses
    ADD CONSTRAINT expenses_pkey PRIMARY KEY (id);


--
-- Name: fee_adjustments fee_adjustments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fee_adjustments
    ADD CONSTRAINT fee_adjustments_pkey PRIMARY KEY (id);


--
-- Name: installment_schedule installment_schedule_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.installment_schedule
    ADD CONSTRAINT installment_schedule_pkey PRIMARY KEY (id);


--
-- Name: lab_clients lab_clients_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lab_clients
    ADD CONSTRAINT lab_clients_pkey PRIMARY KEY (id);


--
-- Name: lab_expenses lab_expenses_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lab_expenses
    ADD CONSTRAINT lab_expenses_pkey PRIMARY KEY (id);


--
-- Name: lab_invoice_items lab_invoice_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lab_invoice_items
    ADD CONSTRAINT lab_invoice_items_pkey PRIMARY KEY (id);


--
-- Name: lab_invoices lab_invoices_invoice_number_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lab_invoices
    ADD CONSTRAINT lab_invoices_invoice_number_key UNIQUE (invoice_number);


--
-- Name: lab_invoices lab_invoices_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lab_invoices
    ADD CONSTRAINT lab_invoices_pkey PRIMARY KEY (id);


--
-- Name: lab_payments lab_payments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lab_payments
    ADD CONSTRAINT lab_payments_pkey PRIMARY KEY (id);


--
-- Name: monthly_targets monthly_targets_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.monthly_targets
    ADD CONSTRAINT monthly_targets_pkey PRIMARY KEY (month_key);


--
-- Name: notification_outbox notification_outbox_dedupe_key_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notification_outbox
    ADD CONSTRAINT notification_outbox_dedupe_key_key UNIQUE (dedupe_key);


--
-- Name: notification_outbox notification_outbox_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notification_outbox
    ADD CONSTRAINT notification_outbox_pkey PRIMARY KEY (id);


--
-- Name: payment_allocations payment_allocations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payment_allocations
    ADD CONSTRAINT payment_allocations_pkey PRIMARY KEY (id);


--
-- Name: payment_refunds payment_refunds_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payment_refunds
    ADD CONSTRAINT payment_refunds_pkey PRIMARY KEY (id);


--
-- Name: payments payments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_pkey PRIMARY KEY (id);


--
-- Name: referrals referrals_enrollment_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.referrals
    ADD CONSTRAINT referrals_enrollment_unique UNIQUE (enrollment_id);


--
-- Name: referrals referrals_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.referrals
    ADD CONSTRAINT referrals_pkey PRIMARY KEY (id);


--
-- Name: sessions sessions_cohort_id_session_number_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sessions
    ADD CONSTRAINT sessions_cohort_id_session_number_key UNIQUE (cohort_id, session_number);


--
-- Name: sessions sessions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sessions
    ADD CONSTRAINT sessions_pkey PRIMARY KEY (id);


--
-- Name: sessions sessions_qr_token_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sessions
    ADD CONSTRAINT sessions_qr_token_key UNIQUE (qr_token);


--
-- Name: survey_dispatches survey_dispatches_enrollment_id_at_session_count_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.survey_dispatches
    ADD CONSTRAINT survey_dispatches_enrollment_id_at_session_count_key UNIQUE (enrollment_id, at_session_count);


--
-- Name: survey_dispatches survey_dispatches_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.survey_dispatches
    ADD CONSTRAINT survey_dispatches_pkey PRIMARY KEY (id);


--
-- Name: survey_responses survey_responses_dispatch_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.survey_responses
    ADD CONSTRAINT survey_responses_dispatch_id_key UNIQUE (dispatch_id);


--
-- Name: survey_responses survey_responses_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.survey_responses
    ADD CONSTRAINT survey_responses_pkey PRIMARY KEY (id);


--
-- Name: survey_templates survey_templates_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.survey_templates
    ADD CONSTRAINT survey_templates_pkey PRIMARY KEY (id);


--
-- Name: trainees trainees_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trainees
    ADD CONSTRAINT trainees_pkey PRIMARY KEY (id);


--
-- Name: trainees trainees_trainee_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trainees
    ADD CONSTRAINT trainees_trainee_code_key UNIQUE (trainee_code);


--
-- Name: trainees trainees_user_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trainees
    ADD CONSTRAINT trainees_user_id_key UNIQUE (user_id);


--
-- Name: attendance unique_attendance_session_trainee; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendance
    ADD CONSTRAINT unique_attendance_session_trainee UNIQUE (session_id, trainee_id);


--
-- Name: survey_responses unique_dispatch_response; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.survey_responses
    ADD CONSTRAINT unique_dispatch_response UNIQUE (dispatch_id);


--
-- Name: installment_schedule uq_enrollment_installment; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.installment_schedule
    ADD CONSTRAINT uq_enrollment_installment UNIQUE (enrollment_id, installment_number);


--
-- Name: payment_allocations uq_payment_installment_allocation; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payment_allocations
    ADD CONSTRAINT uq_payment_installment_allocation UNIQUE (payment_id, installment_id);


--
-- Name: user_fcm_tokens user_fcm_tokens_fcm_token_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_fcm_tokens
    ADD CONSTRAINT user_fcm_tokens_fcm_token_key UNIQUE (fcm_token);


--
-- Name: user_fcm_tokens user_fcm_tokens_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_fcm_tokens
    ADD CONSTRAINT user_fcm_tokens_pkey PRIMARY KEY (id);


--
-- Name: user_pins user_pins_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_pins
    ADD CONSTRAINT user_pins_pkey PRIMARY KEY (user_id);


--
-- Name: users users_email_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_email_key UNIQUE (email);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: idx_audit_log_performed_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_audit_log_performed_at ON public.audit_log USING btree (performed_at DESC);


--
-- Name: idx_audit_log_performed_by; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_audit_log_performed_by ON public.audit_log USING btree (performed_by) WHERE (performed_by IS NOT NULL);


--
-- Name: idx_audit_log_record_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_audit_log_record_id ON public.audit_log USING btree (record_id);


--
-- Name: idx_audit_log_table_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_audit_log_table_name ON public.audit_log USING btree (table_name);


--
-- Name: idx_cohorts_course; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_cohorts_course ON public.cohorts USING btree (course_id);


--
-- Name: idx_course_materials_course_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_course_materials_course_id ON public.course_materials USING btree (course_id);


--
-- Name: idx_course_materials_file_path; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_course_materials_file_path ON public.course_materials USING btree (file_path) WHERE (file_path IS NOT NULL);


--
-- Name: idx_course_materials_published; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_course_materials_published ON public.course_materials USING btree (course_id, is_published);


--
-- Name: idx_course_waitlist_cohort_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_course_waitlist_cohort_status ON public.course_waitlist USING btree (cohort_id, status, joined_at);


--
-- Name: idx_course_waitlist_fifo; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_course_waitlist_fifo ON public.course_waitlist USING btree (cohort_id, joined_at, id) WHERE (status = 'waiting'::text);


--
-- Name: idx_course_waitlist_notified_expiry; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_course_waitlist_notified_expiry ON public.course_waitlist USING btree (expires_at) WHERE (status = 'notified'::text);


--
-- Name: idx_course_waitlist_trainee_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_course_waitlist_trainee_status ON public.course_waitlist USING btree (trainee_id, status, joined_at DESC);


--
-- Name: idx_enrollment_withdrawals_trainee; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_enrollment_withdrawals_trainee ON public.enrollment_withdrawals USING btree (trainee_id, withdrawn_at DESC);


--
-- Name: idx_enrollments_cohort_lifecycle; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_enrollments_cohort_lifecycle ON public.enrollments USING btree (cohort_id, lifecycle_status);


--
-- Name: idx_enrollments_cohort_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_enrollments_cohort_status ON public.enrollments USING btree (cohort_id, status);


--
-- Name: idx_fee_adjustments_enrollment; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_fee_adjustments_enrollment ON public.fee_adjustments USING btree (enrollment_id);


--
-- Name: idx_installment_schedule_due_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_installment_schedule_due_date ON public.installment_schedule USING btree (due_date);


--
-- Name: idx_installment_schedule_enrollment; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_installment_schedule_enrollment ON public.installment_schedule USING btree (enrollment_id);


--
-- Name: idx_lab_expenses_category; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_lab_expenses_category ON public.lab_expenses USING btree (category);


--
-- Name: idx_lab_expenses_expense_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_lab_expenses_expense_date ON public.lab_expenses USING btree (expense_date);


--
-- Name: idx_lab_invoice_items_invoice_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_lab_invoice_items_invoice_id ON public.lab_invoice_items USING btree (invoice_id);


--
-- Name: idx_lab_invoices_client_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_lab_invoices_client_id ON public.lab_invoices USING btree (client_id);


--
-- Name: idx_lab_invoices_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_lab_invoices_created_at ON public.lab_invoices USING btree (created_at);


--
-- Name: idx_lab_invoices_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_lab_invoices_status ON public.lab_invoices USING btree (status);


--
-- Name: idx_lab_payments_invoice_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_lab_payments_invoice_id ON public.lab_payments USING btree (invoice_id);


--
-- Name: idx_notification_outbox_pending; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_notification_outbox_pending ON public.notification_outbox USING btree (status, next_attempt_at) WHERE (status = ANY (ARRAY['pending'::text, 'processing'::text]));


--
-- Name: idx_notification_outbox_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_notification_outbox_user_id ON public.notification_outbox USING btree (user_id);


--
-- Name: idx_payment_allocations_installment; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_payment_allocations_installment ON public.payment_allocations USING btree (installment_id);


--
-- Name: idx_payment_allocations_payment; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_payment_allocations_payment ON public.payment_allocations USING btree (payment_id);


--
-- Name: idx_payment_refunds_payment; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_payment_refunds_payment ON public.payment_refunds USING btree (payment_id);


--
-- Name: idx_referrals_referee; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_referrals_referee ON public.referrals USING btree (referee_trainee_id, course_id);


--
-- Name: idx_referrals_referrer_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_referrals_referrer_status ON public.referrals USING btree (referrer_trainee_id, status, created_at);


--
-- Name: idx_trainees_code; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_trainees_code ON public.trainees USING btree (trainee_code);


--
-- Name: idx_trainees_name_ar; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_trainees_name_ar ON public.trainees USING btree (full_name_ar);


--
-- Name: idx_user_fcm_tokens_user_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_user_fcm_tokens_user_active ON public.user_fcm_tokens USING btree (user_id) WHERE (is_active = true);


--
-- Name: uq_course_waitlist_active; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_course_waitlist_active ON public.course_waitlist USING btree (cohort_id, trainee_id) WHERE (status = ANY (ARRAY['waiting'::text, 'notified'::text]));


--
-- Name: uq_referrals_active_triplet; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_referrals_active_triplet ON public.referrals USING btree (referrer_trainee_id, referee_trainee_id, course_id) WHERE (status <> 'cancelled'::text);


--
-- Name: uq_trainees_trainee_code; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_trainees_trainee_code ON public.trainees USING btree (upper(btrim(trainee_code)));


--
-- Name: open_sessions_view _RETURN; Type: RULE; Schema: public; Owner: -
--

CREATE OR REPLACE VIEW public.open_sessions_view WITH (security_invoker='true') AS
 SELECT s.id,
    s.cohort_id,
    s.session_number,
    s.qr_token,
    s.opened_at,
    c.name AS cohort_name,
    co.name AS course_name,
    count(a.id) AS attendees_count
   FROM (((public.sessions s
     JOIN public.cohorts c ON ((c.id = s.cohort_id)))
     JOIN public.courses co ON ((co.id = c.course_id)))
     LEFT JOIN public.attendance a ON ((a.session_id = s.id)))
  WHERE (s.status = 'open'::public.session_status)
  GROUP BY s.id, c.name, co.name;


--
-- Name: attendance audit_attendance; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER audit_attendance AFTER INSERT OR DELETE OR UPDATE ON public.attendance FOR EACH ROW EXECUTE FUNCTION public.audit_trigger_func();


--
-- Name: enrollments audit_enrollments; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER audit_enrollments AFTER INSERT OR DELETE OR UPDATE ON public.enrollments FOR EACH ROW EXECUTE FUNCTION public.audit_trigger_func();


--
-- Name: expenses audit_expenses; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER audit_expenses AFTER INSERT OR DELETE OR UPDATE ON public.expenses FOR EACH ROW EXECUTE FUNCTION public.audit_trigger_func();


--
-- Name: payments audit_payments; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER audit_payments AFTER INSERT OR DELETE OR UPDATE ON public.payments FOR EACH ROW EXECUTE FUNCTION public.audit_trigger_func();


--
-- Name: sessions audit_sessions; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER audit_sessions AFTER INSERT OR DELETE OR UPDATE ON public.sessions FOR EACH ROW EXECUTE FUNCTION public.audit_trigger_func();


--
-- Name: fee_adjustments trg_c1_adjustment_apply; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_c1_adjustment_apply AFTER INSERT OR DELETE ON public.fee_adjustments FOR EACH ROW EXECUTE FUNCTION public.trg_fn_c1_adjustment_apply();


--
-- Name: fee_adjustments trg_c1_adjustment_guard; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_c1_adjustment_guard BEFORE UPDATE ON public.fee_adjustments FOR EACH ROW EXECUTE FUNCTION public.trg_fn_c1_adjustment_apply();


--
-- Name: fee_adjustments trg_c1_adjustment_status_sync; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_c1_adjustment_status_sync AFTER INSERT OR DELETE ON public.fee_adjustments FOR EACH ROW EXECUTE FUNCTION public.trg_fn_c1_adjustment_status_sync();


--
-- Name: enrollments trg_c1_default_installment; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_c1_default_installment AFTER INSERT ON public.enrollments FOR EACH ROW EXECUTE FUNCTION public.trg_fn_c1_default_installment();


--
-- Name: enrollments trg_c1_enrollment_fee_changed; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_c1_enrollment_fee_changed AFTER UPDATE OF total_due, discount_amount, status ON public.enrollments FOR EACH ROW EXECUTE FUNCTION public.trg_fn_c1_enrollment_fee_changed();


--
-- Name: installment_schedule trg_c1_installment_guard; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_c1_installment_guard BEFORE INSERT OR DELETE OR UPDATE ON public.installment_schedule FOR EACH ROW EXECUTE FUNCTION public.trg_fn_c1_installment_guard();


--
-- Name: payments trg_c1_payment_delete_status_sync; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_c1_payment_delete_status_sync AFTER DELETE ON public.payments FOR EACH ROW EXECUTE FUNCTION public.update_enrollment_payment_status();


--
-- Name: payments trg_c1_payment_write_guard; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_c1_payment_write_guard BEFORE DELETE OR UPDATE ON public.payments FOR EACH ROW EXECUTE FUNCTION public.trg_fn_c1_payment_write_guard();


--
-- Name: payments trg_c1_payments_after; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_c1_payments_after AFTER INSERT OR UPDATE OF amount, currency, enrollment_id ON public.payments FOR EACH ROW EXECUTE FUNCTION public.trg_fn_c1_payments_after();


--
-- Name: payments trg_c1_payments_guard; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_c1_payments_guard BEFORE INSERT OR UPDATE ON public.payments FOR EACH ROW EXECUTE FUNCTION public.trg_fn_c1_payments_guard();


--
-- Name: installment_schedule trg_c1_plan_total; Type: TRIGGER; Schema: public; Owner: -
--

CREATE CONSTRAINT TRIGGER trg_c1_plan_total AFTER INSERT OR DELETE OR UPDATE ON public.installment_schedule DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.trg_fn_c1_plan_total();


--
-- Name: payment_refunds trg_c1_refund_after; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_c1_refund_after AFTER INSERT OR DELETE ON public.payment_refunds FOR EACH ROW EXECUTE FUNCTION public.trg_fn_c1_refund_after();


--
-- Name: payment_refunds trg_c1_refund_guard; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_c1_refund_guard BEFORE INSERT OR DELETE OR UPDATE ON public.payment_refunds FOR EACH ROW EXECUTE FUNCTION public.trg_fn_c1_refund_guard();


--
-- Name: payment_refunds trg_c1_refund_status_sync; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_c1_refund_status_sync AFTER INSERT OR DELETE ON public.payment_refunds FOR EACH ROW EXECUTE FUNCTION public.trg_fn_c1_refund_status_sync();


--
-- Name: cohorts trg_cohorts_capacity_guard; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_cohorts_capacity_guard BEFORE INSERT OR UPDATE OF capacity ON public.cohorts FOR EACH ROW EXECUTE FUNCTION public.trg_fn_validate_cohort_capacity();


--
-- Name: cohorts trg_cohorts_waitlist_on_capacity_change; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_cohorts_waitlist_on_capacity_change AFTER UPDATE OF capacity ON public.cohorts FOR EACH ROW EXECUTE FUNCTION public.trg_fn_waitlist_on_capacity_change();


--
-- Name: course_waitlist trg_course_waitlist_insert_guard; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_course_waitlist_insert_guard BEFORE INSERT ON public.course_waitlist FOR EACH ROW EXECUTE FUNCTION public.trg_fn_validate_waitlist_insert();


--
-- Name: course_waitlist trg_course_waitlist_touch; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_course_waitlist_touch BEFORE UPDATE ON public.course_waitlist FOR EACH ROW EXECUTE FUNCTION public.trg_fn_course_waitlist_touch();


--
-- Name: course_waitlist trg_course_waitlist_transition_guard; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_course_waitlist_transition_guard BEFORE UPDATE OF status, cohort_id, trainee_id ON public.course_waitlist FOR EACH ROW EXECUTE FUNCTION public.trg_fn_validate_waitlist_transition();


--
-- Name: enrollments trg_enrollments_autoclose_waitlist; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_enrollments_autoclose_waitlist AFTER INSERT OR UPDATE OF status, cohort_id ON public.enrollments FOR EACH ROW EXECUTE FUNCTION public.trg_fn_autoclose_waitlist_on_enrollment();


--
-- Name: enrollments trg_enrollments_capacity_guard; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_enrollments_capacity_guard BEFORE INSERT OR UPDATE OF cohort_id, status ON public.enrollments FOR EACH ROW EXECUTE FUNCTION public.trg_fn_enforce_cohort_capacity();


--
-- Name: enrollments trg_enrollments_referral_after; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_enrollments_referral_after AFTER INSERT ON public.enrollments FOR EACH ROW EXECUTE FUNCTION public.trg_fn_enrollments_referral_after();


--
-- Name: enrollments trg_enrollments_referral_before; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_enrollments_referral_before BEFORE INSERT ON public.enrollments FOR EACH ROW EXECUTE FUNCTION public.trg_fn_enrollments_referral_before();


--
-- Name: enrollments trg_enrollments_referral_release; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_enrollments_referral_release AFTER UPDATE OF lifecycle_status ON public.enrollments FOR EACH ROW EXECUTE FUNCTION public.trg_fn_referral_on_enrollment_release();


--
-- Name: enrollments trg_enrollments_waitlist_release; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_enrollments_waitlist_release AFTER UPDATE OF lifecycle_status, cohort_id ON public.enrollments FOR EACH ROW EXECUTE FUNCTION public.trg_fn_enrollment_waitlist_on_release();


--
-- Name: enrollments trg_enrollments_waitlist_release_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_enrollments_waitlist_release_delete AFTER DELETE ON public.enrollments FOR EACH ROW EXECUTE FUNCTION public.trg_fn_enrollment_waitlist_on_release();


--
-- Name: enrollments trg_enrollments_withdrawal_rpc_guard; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_enrollments_withdrawal_rpc_guard BEFORE UPDATE OF lifecycle_status, withdrawn_at, withdrawal_reason ON public.enrollments FOR EACH ROW EXECUTE FUNCTION public.trg_fn_enforce_withdrawal_rpc();


--
-- Name: trainees trg_generate_trainee_code; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_generate_trainee_code BEFORE INSERT ON public.trainees FOR EACH ROW EXECUTE FUNCTION public.handle_trainee_code_generation();


--
-- Name: users trg_guard_users_admin_changes; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_guard_users_admin_changes BEFORE DELETE OR UPDATE ON public.users FOR EACH ROW EXECUTE FUNCTION public.c1_guard_user_admin_changes();


--
-- Name: lab_invoices trg_lab_invoice_discount_sync; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_lab_invoice_discount_sync BEFORE UPDATE OF discount ON public.lab_invoices FOR EACH ROW EXECUTE FUNCTION public.trg_lab_invoice_discount_sync();


--
-- Name: lab_invoice_items trg_lab_invoice_item_calc_total; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_lab_invoice_item_calc_total BEFORE INSERT OR UPDATE ON public.lab_invoice_items FOR EACH ROW EXECUTE FUNCTION public.lab_invoice_item_calc_total();


--
-- Name: lab_invoices trg_lab_invoice_set_number; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_lab_invoice_set_number BEFORE INSERT ON public.lab_invoices FOR EACH ROW EXECUTE FUNCTION public.lab_invoice_set_number();


--
-- Name: lab_invoice_items trg_lab_items_sync; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_lab_items_sync AFTER INSERT OR DELETE OR UPDATE ON public.lab_invoice_items FOR EACH ROW EXECUTE FUNCTION public.trg_lab_invoice_items_sync();


--
-- Name: lab_payments trg_lab_payments_sync; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_lab_payments_sync AFTER INSERT OR DELETE OR UPDATE ON public.lab_payments FOR EACH ROW EXECUTE FUNCTION public.trg_lab_payments_sync();


--
-- Name: payments trg_payment_status; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_payment_status AFTER INSERT OR DELETE OR UPDATE ON public.payments FOR EACH ROW EXECUTE FUNCTION public.update_enrollment_payment_status();


--
-- Name: referrals trg_referrals_touch; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_referrals_touch BEFORE UPDATE ON public.referrals FOR EACH ROW EXECUTE FUNCTION public.trg_fn_referrals_touch();


--
-- Name: attendance trg_survey_dispatch; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_survey_dispatch AFTER INSERT ON public.attendance FOR EACH ROW EXECUTE FUNCTION public.check_survey_dispatch();


--
-- Name: survey_dispatches trg_survey_dispatch_outbox; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_survey_dispatch_outbox AFTER INSERT ON public.survey_dispatches FOR EACH ROW EXECUTE FUNCTION public.trg_fn_enqueue_survey_notification();


--
-- Name: course_materials trg_z_audit_course_materials; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_z_audit_course_materials AFTER INSERT OR DELETE OR UPDATE ON public.course_materials FOR EACH ROW EXECUTE FUNCTION public.audit_trigger_func();


--
-- Name: enrollment_withdrawals trg_z_audit_enrollment_withdrawals; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_z_audit_enrollment_withdrawals AFTER INSERT ON public.enrollment_withdrawals FOR EACH ROW EXECUTE FUNCTION public.audit_trigger_func();


--
-- Name: fee_adjustments trg_z_audit_fee_adjustments; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_z_audit_fee_adjustments AFTER INSERT OR DELETE OR UPDATE ON public.fee_adjustments FOR EACH ROW EXECUTE FUNCTION public.audit_trigger_func();


--
-- Name: installment_schedule trg_z_audit_installment_schedule; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_z_audit_installment_schedule AFTER INSERT OR DELETE OR UPDATE ON public.installment_schedule FOR EACH ROW EXECUTE FUNCTION public.audit_trigger_func();


--
-- Name: payment_allocations trg_z_audit_payment_allocations; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_z_audit_payment_allocations AFTER INSERT OR DELETE OR UPDATE ON public.payment_allocations FOR EACH ROW EXECUTE FUNCTION public.audit_trigger_func();


--
-- Name: payment_refunds trg_z_audit_payment_refunds; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_z_audit_payment_refunds AFTER INSERT OR DELETE OR UPDATE ON public.payment_refunds FOR EACH ROW EXECUTE FUNCTION public.audit_trigger_func();


--
-- Name: users trg_z_audit_users; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_z_audit_users AFTER INSERT OR DELETE OR UPDATE ON public.users FOR EACH ROW EXECUTE FUNCTION public.audit_trigger_func();


--
-- Name: attendance attendance_performed_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendance
    ADD CONSTRAINT attendance_performed_by_fkey FOREIGN KEY (performed_by) REFERENCES public.users(id);


--
-- Name: attendance attendance_session_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendance
    ADD CONSTRAINT attendance_session_id_fkey FOREIGN KEY (session_id) REFERENCES public.sessions(id);


--
-- Name: attendance attendance_trainee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendance
    ADD CONSTRAINT attendance_trainee_id_fkey FOREIGN KEY (trainee_id) REFERENCES public.trainees(id);


--
-- Name: audit_log audit_log_performed_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_log
    ADD CONSTRAINT audit_log_performed_by_fkey FOREIGN KEY (performed_by) REFERENCES public.users(id);


--
-- Name: cohorts cohorts_course_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cohorts
    ADD CONSTRAINT cohorts_course_id_fkey FOREIGN KEY (course_id) REFERENCES public.courses(id);


--
-- Name: cohorts cohorts_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cohorts
    ADD CONSTRAINT cohorts_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- Name: cohorts cohorts_trainer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cohorts
    ADD CONSTRAINT cohorts_trainer_id_fkey FOREIGN KEY (trainer_id) REFERENCES public.users(id);


--
-- Name: course_materials course_materials_course_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.course_materials
    ADD CONSTRAINT course_materials_course_id_fkey FOREIGN KEY (course_id) REFERENCES public.courses(id) ON DELETE CASCADE;


--
-- Name: course_materials course_materials_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.course_materials
    ADD CONSTRAINT course_materials_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: course_waitlist course_waitlist_cohort_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.course_waitlist
    ADD CONSTRAINT course_waitlist_cohort_id_fkey FOREIGN KEY (cohort_id) REFERENCES public.cohorts(id) ON DELETE CASCADE;


--
-- Name: course_waitlist course_waitlist_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.course_waitlist
    ADD CONSTRAINT course_waitlist_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: course_waitlist course_waitlist_promoted_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.course_waitlist
    ADD CONSTRAINT course_waitlist_promoted_by_fkey FOREIGN KEY (promoted_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: course_waitlist course_waitlist_trainee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.course_waitlist
    ADD CONSTRAINT course_waitlist_trainee_id_fkey FOREIGN KEY (trainee_id) REFERENCES public.trainees(id) ON DELETE CASCADE;


--
-- Name: courses courses_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.courses
    ADD CONSTRAINT courses_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- Name: enrollment_withdrawals enrollment_withdrawals_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.enrollment_withdrawals
    ADD CONSTRAINT enrollment_withdrawals_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id);


--
-- Name: enrollment_withdrawals enrollment_withdrawals_enrollment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.enrollment_withdrawals
    ADD CONSTRAINT enrollment_withdrawals_enrollment_id_fkey FOREIGN KEY (enrollment_id) REFERENCES public.enrollments(id) ON DELETE RESTRICT;


--
-- Name: enrollment_withdrawals enrollment_withdrawals_trainee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.enrollment_withdrawals
    ADD CONSTRAINT enrollment_withdrawals_trainee_id_fkey FOREIGN KEY (trainee_id) REFERENCES public.trainees(id) ON DELETE RESTRICT;


--
-- Name: enrollments enrollments_cohort_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.enrollments
    ADD CONSTRAINT enrollments_cohort_id_fkey FOREIGN KEY (cohort_id) REFERENCES public.cohorts(id);


--
-- Name: enrollments enrollments_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.enrollments
    ADD CONSTRAINT enrollments_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- Name: enrollments enrollments_trainee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.enrollments
    ADD CONSTRAINT enrollments_trainee_id_fkey FOREIGN KEY (trainee_id) REFERENCES public.trainees(id);


--
-- Name: expenses expenses_performed_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.expenses
    ADD CONSTRAINT expenses_performed_by_fkey FOREIGN KEY (performed_by) REFERENCES public.users(id);


--
-- Name: fee_adjustments fee_adjustments_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fee_adjustments
    ADD CONSTRAINT fee_adjustments_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id);


--
-- Name: fee_adjustments fee_adjustments_enrollment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fee_adjustments
    ADD CONSTRAINT fee_adjustments_enrollment_id_fkey FOREIGN KEY (enrollment_id) REFERENCES public.enrollments(id) ON DELETE CASCADE;


--
-- Name: installment_schedule installment_schedule_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.installment_schedule
    ADD CONSTRAINT installment_schedule_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id);


--
-- Name: installment_schedule installment_schedule_enrollment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.installment_schedule
    ADD CONSTRAINT installment_schedule_enrollment_id_fkey FOREIGN KEY (enrollment_id) REFERENCES public.enrollments(id) ON DELETE CASCADE;


--
-- Name: lab_expenses lab_expenses_performed_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lab_expenses
    ADD CONSTRAINT lab_expenses_performed_by_fkey FOREIGN KEY (performed_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: lab_invoice_items lab_invoice_items_invoice_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lab_invoice_items
    ADD CONSTRAINT lab_invoice_items_invoice_id_fkey FOREIGN KEY (invoice_id) REFERENCES public.lab_invoices(id) ON DELETE CASCADE;


--
-- Name: lab_invoices lab_invoices_client_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lab_invoices
    ADD CONSTRAINT lab_invoices_client_id_fkey FOREIGN KEY (client_id) REFERENCES public.lab_clients(id) ON DELETE RESTRICT;


--
-- Name: lab_invoices lab_invoices_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lab_invoices
    ADD CONSTRAINT lab_invoices_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: lab_payments lab_payments_invoice_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lab_payments
    ADD CONSTRAINT lab_payments_invoice_id_fkey FOREIGN KEY (invoice_id) REFERENCES public.lab_invoices(id) ON DELETE RESTRICT;


--
-- Name: lab_payments lab_payments_performed_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lab_payments
    ADD CONSTRAINT lab_payments_performed_by_fkey FOREIGN KEY (performed_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: monthly_targets monthly_targets_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.monthly_targets
    ADD CONSTRAINT monthly_targets_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES auth.users(id);


--
-- Name: notification_outbox notification_outbox_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notification_outbox
    ADD CONSTRAINT notification_outbox_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: payment_allocations payment_allocations_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payment_allocations
    ADD CONSTRAINT payment_allocations_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id);


--
-- Name: payment_allocations payment_allocations_installment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payment_allocations
    ADD CONSTRAINT payment_allocations_installment_id_fkey FOREIGN KEY (installment_id) REFERENCES public.installment_schedule(id) ON DELETE CASCADE;


--
-- Name: payment_allocations payment_allocations_payment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payment_allocations
    ADD CONSTRAINT payment_allocations_payment_id_fkey FOREIGN KEY (payment_id) REFERENCES public.payments(id) ON DELETE CASCADE;


--
-- Name: payment_refunds payment_refunds_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payment_refunds
    ADD CONSTRAINT payment_refunds_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id);


--
-- Name: payment_refunds payment_refunds_payment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payment_refunds
    ADD CONSTRAINT payment_refunds_payment_id_fkey FOREIGN KEY (payment_id) REFERENCES public.payments(id) ON DELETE RESTRICT;


--
-- Name: payments payments_enrollment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_enrollment_id_fkey FOREIGN KEY (enrollment_id) REFERENCES public.enrollments(id);


--
-- Name: payments payments_performed_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_performed_by_fkey FOREIGN KEY (performed_by) REFERENCES public.users(id);


--
-- Name: referrals referrals_applied_enrollment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.referrals
    ADD CONSTRAINT referrals_applied_enrollment_id_fkey FOREIGN KEY (applied_enrollment_id) REFERENCES public.enrollments(id) ON DELETE CASCADE;


--
-- Name: referrals referrals_course_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.referrals
    ADD CONSTRAINT referrals_course_id_fkey FOREIGN KEY (course_id) REFERENCES public.courses(id) ON DELETE CASCADE;


--
-- Name: referrals referrals_enrollment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.referrals
    ADD CONSTRAINT referrals_enrollment_id_fkey FOREIGN KEY (enrollment_id) REFERENCES public.enrollments(id) ON DELETE CASCADE;


--
-- Name: referrals referrals_referee_trainee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.referrals
    ADD CONSTRAINT referrals_referee_trainee_id_fkey FOREIGN KEY (referee_trainee_id) REFERENCES public.trainees(id) ON DELETE CASCADE;


--
-- Name: referrals referrals_referrer_trainee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.referrals
    ADD CONSTRAINT referrals_referrer_trainee_id_fkey FOREIGN KEY (referrer_trainee_id) REFERENCES public.trainees(id) ON DELETE CASCADE;


--
-- Name: sessions sessions_cohort_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sessions
    ADD CONSTRAINT sessions_cohort_id_fkey FOREIGN KEY (cohort_id) REFERENCES public.cohorts(id);


--
-- Name: sessions sessions_opened_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sessions
    ADD CONSTRAINT sessions_opened_by_fkey FOREIGN KEY (opened_by) REFERENCES public.users(id);


--
-- Name: survey_dispatches survey_dispatches_enrollment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.survey_dispatches
    ADD CONSTRAINT survey_dispatches_enrollment_id_fkey FOREIGN KEY (enrollment_id) REFERENCES public.enrollments(id);


--
-- Name: survey_dispatches survey_dispatches_template_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.survey_dispatches
    ADD CONSTRAINT survey_dispatches_template_id_fkey FOREIGN KEY (template_id) REFERENCES public.survey_templates(id);


--
-- Name: survey_responses survey_responses_dispatch_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.survey_responses
    ADD CONSTRAINT survey_responses_dispatch_id_fkey FOREIGN KEY (dispatch_id) REFERENCES public.survey_dispatches(id);


--
-- Name: survey_templates survey_templates_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.survey_templates
    ADD CONSTRAINT survey_templates_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- Name: trainees trainees_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trainees
    ADD CONSTRAINT trainees_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- Name: trainees trainees_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trainees
    ADD CONSTRAINT trainees_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: user_fcm_tokens user_fcm_tokens_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_fcm_tokens
    ADD CONSTRAINT user_fcm_tokens_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: user_pins user_pins_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_pins
    ADD CONSTRAINT user_pins_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: users users_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- Name: cron_job_log Allow staff to read cron logs; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Allow staff to read cron logs" ON public.cron_job_log FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.users
  WHERE ((users.id = auth.uid()) AND (users.role = ANY (ARRAY['admin'::public.user_role, 'reception'::public.user_role])) AND (users.is_active = true)))));


--
-- Name: user_fcm_tokens Users can delete own tokens; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can delete own tokens" ON public.user_fcm_tokens FOR DELETE TO authenticated USING ((auth.uid() = user_id));


--
-- Name: user_fcm_tokens Users can insert own tokens; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can insert own tokens" ON public.user_fcm_tokens FOR INSERT TO authenticated WITH CHECK ((auth.uid() = user_id));


--
-- Name: user_fcm_tokens Users can select own tokens; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can select own tokens" ON public.user_fcm_tokens FOR SELECT TO authenticated USING ((auth.uid() = user_id));


--
-- Name: user_fcm_tokens Users can update own tokens; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can update own tokens" ON public.user_fcm_tokens FOR UPDATE TO authenticated USING ((auth.uid() = user_id)) WITH CHECK ((auth.uid() = user_id));


--
-- Name: attendance admin_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY admin_all ON public.attendance USING ((public.get_user_role() = 'admin'::public.user_role));


--
-- Name: cohorts admin_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY admin_all ON public.cohorts USING ((public.get_user_role() = 'admin'::public.user_role));


--
-- Name: courses admin_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY admin_all ON public.courses USING ((public.get_user_role() = 'admin'::public.user_role));


--
-- Name: enrollments admin_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY admin_all ON public.enrollments USING ((public.get_user_role() = 'admin'::public.user_role));


--
-- Name: payments admin_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY admin_all ON public.payments USING ((public.get_user_role() = 'admin'::public.user_role));


--
-- Name: sessions admin_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY admin_all ON public.sessions USING ((public.get_user_role() = 'admin'::public.user_role));


--
-- Name: survey_dispatches admin_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY admin_all ON public.survey_dispatches USING ((public.get_user_role() = 'admin'::public.user_role));


--
-- Name: survey_responses admin_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY admin_all ON public.survey_responses USING ((public.get_user_role() = 'admin'::public.user_role));


--
-- Name: survey_templates admin_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY admin_all ON public.survey_templates USING ((public.get_user_role() = 'admin'::public.user_role));


--
-- Name: trainees admin_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY admin_all ON public.trainees USING ((public.get_user_role() = 'admin'::public.user_role));


--
-- Name: users admin_all_users; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY admin_all_users ON public.users USING ((public.get_user_role() = 'admin'::public.user_role));


--
-- Name: fee_adjustments admin_manage_fee_adjustments; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY admin_manage_fee_adjustments ON public.fee_adjustments TO authenticated USING (public.c1_is_admin()) WITH CHECK (public.c1_is_admin());


--
-- Name: payment_refunds admin_manage_payment_refunds; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY admin_manage_payment_refunds ON public.payment_refunds TO authenticated USING (public.c1_is_admin()) WITH CHECK (public.c1_is_admin());


--
-- Name: expenses admin_only; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY admin_only ON public.expenses USING ((public.get_user_role() = 'admin'::public.user_role));


--
-- Name: audit_log admin_select_only; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY admin_select_only ON public.audit_log FOR SELECT USING ((public.get_user_role() = 'admin'::public.user_role));


--
-- Name: attendance; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.attendance ENABLE ROW LEVEL SECURITY;

--
-- Name: audit_log; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;

--
-- Name: cohorts; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.cohorts ENABLE ROW LEVEL SECURITY;

--
-- Name: course_materials; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.course_materials ENABLE ROW LEVEL SECURITY;

--
-- Name: course_materials course_materials_admin_manage_policy; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY course_materials_admin_manage_policy ON public.course_materials TO authenticated USING ((( SELECT users.role
   FROM public.users
  WHERE ((users.id = auth.uid()) AND (users.is_active = true))) = 'admin'::public.user_role)) WITH CHECK ((( SELECT users.role
   FROM public.users
  WHERE ((users.id = auth.uid()) AND (users.is_active = true))) = 'admin'::public.user_role));


--
-- Name: course_materials course_materials_read_policy; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY course_materials_read_policy ON public.course_materials FOR SELECT TO authenticated USING (((public.c1_staff_role() = ANY (ARRAY['admin'::text, 'reception'::text])) OR ((is_published = true) AND (EXISTS ( SELECT 1
   FROM ((public.enrollments e
     JOIN public.cohorts c ON ((c.id = e.cohort_id)))
     JOIN public.trainees t ON ((t.id = e.trainee_id)))
  WHERE ((c.course_id = course_materials.course_id) AND (t.user_id = auth.uid()) AND (COALESCE(e.lifecycle_status, 'active'::text) <> 'withdrawn'::text)))))));


--
-- Name: course_waitlist; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.course_waitlist ENABLE ROW LEVEL SECURITY;

--
-- Name: course_waitlist course_waitlist_admin_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY course_waitlist_admin_all ON public.course_waitlist TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.users
  WHERE ((users.id = auth.uid()) AND (users.role = 'admin'::public.user_role) AND (users.is_active = true))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM public.users
  WHERE ((users.id = auth.uid()) AND (users.role = 'admin'::public.user_role) AND (users.is_active = true)))));


--
-- Name: course_waitlist course_waitlist_trainee_select_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY course_waitlist_trainee_select_own ON public.course_waitlist FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.trainees t
  WHERE ((t.id = course_waitlist.trainee_id) AND (t.user_id = auth.uid())))));


--
-- Name: courses; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.courses ENABLE ROW LEVEL SECURITY;

--
-- Name: cron_job_log; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.cron_job_log ENABLE ROW LEVEL SECURITY;

--
-- Name: enrollment_withdrawals; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.enrollment_withdrawals ENABLE ROW LEVEL SECURITY;

--
-- Name: enrollment_withdrawals enrollment_withdrawals_admin_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY enrollment_withdrawals_admin_select ON public.enrollment_withdrawals FOR SELECT TO authenticated USING (public.c1_is_admin());


--
-- Name: enrollments; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.enrollments ENABLE ROW LEVEL SECURITY;

--
-- Name: expenses; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.expenses ENABLE ROW LEVEL SECURITY;

--
-- Name: fee_adjustments; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.fee_adjustments ENABLE ROW LEVEL SECURITY;

--
-- Name: installment_schedule; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.installment_schedule ENABLE ROW LEVEL SECURITY;

--
-- Name: lab_clients; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.lab_clients ENABLE ROW LEVEL SECURITY;

--
-- Name: lab_clients lab_clients_admin_only; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY lab_clients_admin_only ON public.lab_clients TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.users
  WHERE ((users.id = auth.uid()) AND (users.role = 'admin'::public.user_role) AND (users.is_active = true))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM public.users
  WHERE ((users.id = auth.uid()) AND (users.role = 'admin'::public.user_role) AND (users.is_active = true)))));


--
-- Name: lab_expenses; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.lab_expenses ENABLE ROW LEVEL SECURITY;

--
-- Name: lab_expenses lab_expenses_admin_only; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY lab_expenses_admin_only ON public.lab_expenses TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.users
  WHERE ((users.id = auth.uid()) AND (users.role = 'admin'::public.user_role) AND (users.is_active = true))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM public.users
  WHERE ((users.id = auth.uid()) AND (users.role = 'admin'::public.user_role) AND (users.is_active = true)))));


--
-- Name: lab_invoice_items; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.lab_invoice_items ENABLE ROW LEVEL SECURITY;

--
-- Name: lab_invoice_items lab_invoice_items_admin_only; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY lab_invoice_items_admin_only ON public.lab_invoice_items TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.users
  WHERE ((users.id = auth.uid()) AND (users.role = 'admin'::public.user_role) AND (users.is_active = true))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM public.users
  WHERE ((users.id = auth.uid()) AND (users.role = 'admin'::public.user_role) AND (users.is_active = true)))));


--
-- Name: lab_invoices; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.lab_invoices ENABLE ROW LEVEL SECURITY;

--
-- Name: lab_invoices lab_invoices_admin_only; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY lab_invoices_admin_only ON public.lab_invoices TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.users
  WHERE ((users.id = auth.uid()) AND (users.role = 'admin'::public.user_role) AND (users.is_active = true))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM public.users
  WHERE ((users.id = auth.uid()) AND (users.role = 'admin'::public.user_role) AND (users.is_active = true)))));


--
-- Name: lab_payments; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.lab_payments ENABLE ROW LEVEL SECURITY;

--
-- Name: lab_payments lab_payments_admin_only; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY lab_payments_admin_only ON public.lab_payments TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.users
  WHERE ((users.id = auth.uid()) AND (users.role = 'admin'::public.user_role) AND (users.is_active = true))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM public.users
  WHERE ((users.id = auth.uid()) AND (users.role = 'admin'::public.user_role) AND (users.is_active = true)))));


--
-- Name: monthly_targets; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.monthly_targets ENABLE ROW LEVEL SECURITY;

--
-- Name: monthly_targets monthly_targets_admin_only; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY monthly_targets_admin_only ON public.monthly_targets TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.users
  WHERE ((users.id = auth.uid()) AND (users.role = 'admin'::public.user_role) AND (users.is_active = true))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM public.users
  WHERE ((users.id = auth.uid()) AND (users.role = 'admin'::public.user_role) AND (users.is_active = true)))));


--
-- Name: notification_outbox; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.notification_outbox ENABLE ROW LEVEL SECURITY;

--
-- Name: courses others_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY others_select ON public.courses FOR SELECT USING ((public.get_user_role() = ANY (ARRAY['reception'::public.user_role, 'trainee'::public.user_role])));


--
-- Name: payment_allocations; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.payment_allocations ENABLE ROW LEVEL SECURITY;

--
-- Name: payment_refunds; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.payment_refunds ENABLE ROW LEVEL SECURITY;

--
-- Name: payments; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.payments ENABLE ROW LEVEL SECURITY;

--
-- Name: enrollments reception_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY reception_all ON public.enrollments USING ((public.get_user_role() = 'reception'::public.user_role));


--
-- Name: trainees reception_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY reception_all ON public.trainees USING ((public.get_user_role() = 'reception'::public.user_role));


--
-- Name: payments reception_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY reception_insert ON public.payments FOR INSERT WITH CHECK (((public.get_user_role() = 'reception'::public.user_role) AND (performed_by = auth.uid()) AND (method = ANY (ARRAY['cash'::public.payment_method, 'sham_cash'::public.payment_method, 'hawala'::public.payment_method, 'transfer'::public.payment_method]))));


--
-- Name: attendance reception_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY reception_select ON public.attendance FOR SELECT USING ((public.get_user_role() = 'reception'::public.user_role));


--
-- Name: cohorts reception_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY reception_select ON public.cohorts FOR SELECT USING ((public.get_user_role() = 'reception'::public.user_role));


--
-- Name: payments reception_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY reception_select ON public.payments FOR SELECT USING ((public.get_user_role() = 'reception'::public.user_role));


--
-- Name: sessions reception_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY reception_select ON public.sessions FOR SELECT USING ((public.get_user_role() = 'reception'::public.user_role));


--
-- Name: users reception_select_trainees_only; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY reception_select_trainees_only ON public.users FOR SELECT USING (((public.get_user_role() = 'reception'::public.user_role) AND (role = 'trainee'::public.user_role)));


--
-- Name: referrals; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.referrals ENABLE ROW LEVEL SECURITY;

--
-- Name: referrals referrals_staff_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY referrals_staff_select ON public.referrals FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.users u
  WHERE ((u.id = auth.uid()) AND (u.is_active = true) AND ((u.role)::text = ANY (ARRAY['admin'::text, 'reception'::text]))))));


--
-- Name: referrals referrals_trainee_select_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY referrals_trainee_select_own ON public.referrals FOR SELECT TO authenticated USING ((referrer_trainee_id IN ( SELECT t.id
   FROM public.trainees t
  WHERE (t.user_id = auth.uid()))));


--
-- Name: users self_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY self_select ON public.users FOR SELECT USING ((id = public.get_current_user_id()));


--
-- Name: sessions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.sessions ENABLE ROW LEVEL SECURITY;

--
-- Name: installment_schedule staff_read_installment_schedule; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY staff_read_installment_schedule ON public.installment_schedule FOR SELECT TO authenticated USING (public.c1_is_staff());


--
-- Name: payment_allocations staff_read_payment_allocations; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY staff_read_payment_allocations ON public.payment_allocations FOR SELECT TO authenticated USING (public.c1_is_staff());


--
-- Name: survey_dispatches; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.survey_dispatches ENABLE ROW LEVEL SECURITY;

--
-- Name: survey_responses; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.survey_responses ENABLE ROW LEVEL SECURITY;

--
-- Name: survey_templates; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.survey_templates ENABLE ROW LEVEL SECURITY;

--
-- Name: cohorts trainee_enrolled; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY trainee_enrolled ON public.cohorts FOR SELECT USING (((public.get_user_role() = 'trainee'::public.user_role) AND (id IN ( SELECT enrollments.cohort_id
   FROM public.enrollments
  WHERE (enrollments.trainee_id = public.get_trainee_id())))));


--
-- Name: survey_responses trainee_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY trainee_insert ON public.survey_responses FOR INSERT WITH CHECK (((public.get_user_role() = 'trainee'::public.user_role) AND (dispatch_id IN ( SELECT sd.id
   FROM (public.survey_dispatches sd
     JOIN public.enrollments e ON ((e.id = sd.enrollment_id)))
  WHERE (e.trainee_id = public.get_trainee_id())))));


--
-- Name: attendance trainee_insert_qr; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY trainee_insert_qr ON public.attendance FOR INSERT WITH CHECK (((public.get_user_role() = 'trainee'::public.user_role) AND (method = 'qr'::public.attendance_method) AND (trainee_id = public.get_trainee_id())));


--
-- Name: survey_dispatches trainee_mark_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY trainee_mark_read ON public.survey_dispatches FOR UPDATE USING (((public.get_user_role() = 'trainee'::public.user_role) AND (enrollment_id IN ( SELECT enrollments.id
   FROM public.enrollments
  WHERE (enrollments.trainee_id = public.get_trainee_id())))));


--
-- Name: installment_schedule trainee_read_installment_schedule; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY trainee_read_installment_schedule ON public.installment_schedule FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM (public.enrollments e
     JOIN public.trainees t ON ((t.id = e.trainee_id)))
  WHERE ((e.id = installment_schedule.enrollment_id) AND (t.user_id = auth.uid())))));


--
-- Name: payment_allocations trainee_read_payment_allocations; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY trainee_read_payment_allocations ON public.payment_allocations FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM ((public.payments p
     JOIN public.enrollments e ON ((e.id = p.enrollment_id)))
     JOIN public.trainees t ON ((t.id = e.trainee_id)))
  WHERE ((p.id = payment_allocations.payment_id) AND (t.user_id = auth.uid())))));


--
-- Name: sessions trainee_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY trainee_select ON public.sessions FOR SELECT USING (((public.get_user_role() = 'trainee'::public.user_role) AND (cohort_id IN ( SELECT enrollments.cohort_id
   FROM public.enrollments
  WHERE (enrollments.trainee_id = public.get_trainee_id())))));


--
-- Name: survey_templates trainee_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY trainee_select ON public.survey_templates FOR SELECT USING ((public.get_user_role() = 'trainee'::public.user_role));


--
-- Name: enrollments trainee_self; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY trainee_self ON public.enrollments FOR SELECT USING (((public.get_user_role() = 'trainee'::public.user_role) AND (trainee_id = public.get_trainee_id())));


--
-- Name: payments trainee_self; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY trainee_self ON public.payments FOR SELECT USING (((public.get_user_role() = 'trainee'::public.user_role) AND (enrollment_id IN ( SELECT enrollments.id
   FROM public.enrollments
  WHERE (enrollments.trainee_id = public.get_trainee_id())))));


--
-- Name: trainees trainee_self; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY trainee_self ON public.trainees FOR SELECT USING ((user_id = public.get_current_user_id()));


--
-- Name: attendance trainee_self_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY trainee_self_select ON public.attendance FOR SELECT USING (((public.get_user_role() = 'trainee'::public.user_role) AND (trainee_id = public.get_trainee_id())));


--
-- Name: survey_dispatches trainee_self_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY trainee_self_select ON public.survey_dispatches FOR SELECT USING (((public.get_user_role() = 'trainee'::public.user_role) AND (enrollment_id IN ( SELECT enrollments.id
   FROM public.enrollments
  WHERE (enrollments.trainee_id = public.get_trainee_id())))));


--
-- Name: survey_responses trainee_self_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY trainee_self_select ON public.survey_responses FOR SELECT USING (((public.get_user_role() = 'trainee'::public.user_role) AND (dispatch_id IN ( SELECT sd.id
   FROM (public.survey_dispatches sd
     JOIN public.enrollments e ON ((e.id = sd.enrollment_id)))
  WHERE (e.trainee_id = public.get_trainee_id())))));


--
-- Name: trainees; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.trainees ENABLE ROW LEVEL SECURITY;

--
-- Name: user_fcm_tokens; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.user_fcm_tokens ENABLE ROW LEVEL SECURITY;

--
-- Name: user_pins; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.user_pins ENABLE ROW LEVEL SECURITY;

--
-- Name: users; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;

--
-- Name: SCHEMA public; Type: ACL; Schema: -; Owner: -
--

GRANT USAGE ON SCHEMA public TO postgres;
GRANT USAGE ON SCHEMA public TO anon;
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT USAGE ON SCHEMA public TO service_role;
GRANT USAGE ON SCHEMA public TO supabase_auth_admin;


--
-- Name: FUNCTION audit_trigger_func(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.audit_trigger_func() FROM PUBLIC;
GRANT ALL ON FUNCTION public.audit_trigger_func() TO authenticated;
GRANT ALL ON FUNCTION public.audit_trigger_func() TO service_role;


--
-- Name: FUNCTION auto_open_close_sessions(p_dry_run boolean); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.auto_open_close_sessions(p_dry_run boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION public.auto_open_close_sessions(p_dry_run boolean) TO service_role;
GRANT ALL ON FUNCTION public.auto_open_close_sessions(p_dry_run boolean) TO authenticated;


--
-- Name: FUNCTION btrim(public.currency_type); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.btrim(public.currency_type) TO anon;
GRANT ALL ON FUNCTION public.btrim(public.currency_type) TO authenticated;
GRANT ALL ON FUNCTION public.btrim(public.currency_type) TO service_role;


--
-- Name: FUNCTION bulk_schedule_sessions(p_cohort_id uuid, p_start_date date, p_start_time time without time zone, p_days_of_week integer[], p_session_count integer, p_duration_minutes integer); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.bulk_schedule_sessions(p_cohort_id uuid, p_start_date date, p_start_time time without time zone, p_days_of_week integer[], p_session_count integer, p_duration_minutes integer) FROM PUBLIC;
GRANT ALL ON FUNCTION public.bulk_schedule_sessions(p_cohort_id uuid, p_start_date date, p_start_time time without time zone, p_days_of_week integer[], p_session_count integer, p_duration_minutes integer) TO authenticated;
GRANT ALL ON FUNCTION public.bulk_schedule_sessions(p_cohort_id uuid, p_start_date date, p_start_time time without time zone, p_days_of_week integer[], p_session_count integer, p_duration_minutes integer) TO service_role;


--
-- Name: FUNCTION c1_allocate_payment(p_payment_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.c1_allocate_payment(p_payment_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.c1_allocate_payment(p_payment_id uuid) TO service_role;


--
-- Name: FUNCTION c1_apply_plan_delta(p_enrollment_id uuid, p_delta numeric); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.c1_apply_plan_delta(p_enrollment_id uuid, p_delta numeric) FROM PUBLIC;
GRANT ALL ON FUNCTION public.c1_apply_plan_delta(p_enrollment_id uuid, p_delta numeric) TO service_role;


--
-- Name: FUNCTION c1_can_read_financials(p_trainee_user_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.c1_can_read_financials(p_trainee_user_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.c1_can_read_financials(p_trainee_user_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.c1_can_read_financials(p_trainee_user_id uuid) TO service_role;


--
-- Name: FUNCTION c1_guard_user_admin_changes(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.c1_guard_user_admin_changes() TO anon;
GRANT ALL ON FUNCTION public.c1_guard_user_admin_changes() TO authenticated;
GRANT ALL ON FUNCTION public.c1_guard_user_admin_changes() TO service_role;


--
-- Name: FUNCTION c1_is_admin(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.c1_is_admin() FROM PUBLIC;
GRANT ALL ON FUNCTION public.c1_is_admin() TO authenticated;
GRANT ALL ON FUNCTION public.c1_is_admin() TO service_role;


--
-- Name: FUNCTION c1_is_staff(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.c1_is_staff() FROM PUBLIC;
GRANT ALL ON FUNCTION public.c1_is_staff() TO authenticated;
GRANT ALL ON FUNCTION public.c1_is_staff() TO service_role;


--
-- Name: FUNCTION c1_refresh_enrollment_status(p_enrollment_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.c1_refresh_enrollment_status(p_enrollment_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.c1_refresh_enrollment_status(p_enrollment_id uuid) TO service_role;


--
-- Name: FUNCTION c1_staff_role(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.c1_staff_role() FROM PUBLIC;
GRANT ALL ON FUNCTION public.c1_staff_role() TO authenticated;
GRANT ALL ON FUNCTION public.c1_staff_role() TO service_role;


--
-- Name: FUNCTION c1_withdrawal_figures(p_enrollment_id uuid, p_sessions_override integer, p_at timestamp with time zone); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.c1_withdrawal_figures(p_enrollment_id uuid, p_sessions_override integer, p_at timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION public.c1_withdrawal_figures(p_enrollment_id uuid, p_sessions_override integer, p_at timestamp with time zone) TO service_role;


--
-- Name: FUNCTION cancel_course_waitlist(p_waitlist_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.cancel_course_waitlist(p_waitlist_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.cancel_course_waitlist(p_waitlist_id uuid) TO service_role;
GRANT ALL ON FUNCTION public.cancel_course_waitlist(p_waitlist_id uuid) TO authenticated;


--
-- Name: FUNCTION check_survey_dispatch(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.check_survey_dispatch() TO anon;
GRANT ALL ON FUNCTION public.check_survey_dispatch() TO authenticated;
GRANT ALL ON FUNCTION public.check_survey_dispatch() TO service_role;


--
-- Name: FUNCTION claim_notification_batch(p_limit integer); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.claim_notification_batch(p_limit integer) TO anon;
GRANT ALL ON FUNCTION public.claim_notification_batch(p_limit integer) TO authenticated;
GRANT ALL ON FUNCTION public.claim_notification_batch(p_limit integer) TO service_role;


--
-- Name: FUNCTION close_session(p_session_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.close_session(p_session_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.close_session(p_session_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.close_session(p_session_id uuid) TO service_role;


--
-- Name: FUNCTION cohort_active_enrollment_count(p_cohort_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.cohort_active_enrollment_count(p_cohort_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.cohort_active_enrollment_count(p_cohort_id uuid) TO service_role;


--
-- Name: FUNCTION complete_password_change(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.complete_password_change() FROM PUBLIC;
GRANT ALL ON FUNCTION public.complete_password_change() TO authenticated;
GRANT ALL ON FUNCTION public.complete_password_change() TO service_role;


--
-- Name: FUNCTION create_session(p_cohort_id uuid, p_session_number integer, p_scheduled_at timestamp with time zone, p_duration_minutes integer, p_is_extra boolean, p_title text, p_description text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.create_session(p_cohort_id uuid, p_session_number integer, p_scheduled_at timestamp with time zone, p_duration_minutes integer, p_is_extra boolean, p_title text, p_description text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.create_session(p_cohort_id uuid, p_session_number integer, p_scheduled_at timestamp with time zone, p_duration_minutes integer, p_is_extra boolean, p_title text, p_description text) TO authenticated;
GRANT ALL ON FUNCTION public.create_session(p_cohort_id uuid, p_session_number integer, p_scheduled_at timestamp with time zone, p_duration_minutes integer, p_is_extra boolean, p_title text, p_description text) TO service_role;


--
-- Name: FUNCTION custom_access_token_hook(event jsonb); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.custom_access_token_hook(event jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.custom_access_token_hook(event jsonb) TO service_role;
GRANT ALL ON FUNCTION public.custom_access_token_hook(event jsonb) TO supabase_auth_admin;


--
-- Name: FUNCTION dispatch_push_batch(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.dispatch_push_batch() FROM PUBLIC;
GRANT ALL ON FUNCTION public.dispatch_push_batch() TO service_role;


--
-- Name: FUNCTION dispatch_survey_to_all(p_template_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.dispatch_survey_to_all(p_template_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.dispatch_survey_to_all(p_template_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.dispatch_survey_to_all(p_template_id uuid) TO service_role;


--
-- Name: FUNCTION enqueue_payment_reminders(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.enqueue_payment_reminders() FROM PUBLIC;
GRANT ALL ON FUNCTION public.enqueue_payment_reminders() TO service_role;


--
-- Name: FUNCTION enqueue_session_reminders(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.enqueue_session_reminders() FROM PUBLIC;
GRANT ALL ON FUNCTION public.enqueue_session_reminders() TO service_role;


--
-- Name: FUNCTION enrollment_lifecycle_occupies_seat(p_lifecycle text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.enrollment_lifecycle_occupies_seat(p_lifecycle text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.enrollment_lifecycle_occupies_seat(p_lifecycle text) TO service_role;
GRANT ALL ON FUNCTION public.enrollment_lifecycle_occupies_seat(p_lifecycle text) TO authenticated;


--
-- Name: FUNCTION enrollment_status_occupies_seat(p_status text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.enrollment_status_occupies_seat(p_status text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.enrollment_status_occupies_seat(p_status text) TO service_role;
GRANT ALL ON FUNCTION public.enrollment_status_occupies_seat(p_status text) TO authenticated;


--
-- Name: FUNCTION expire_waitlist_notifications(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.expire_waitlist_notifications() FROM PUBLIC;
GRANT ALL ON FUNCTION public.expire_waitlist_notifications() TO service_role;


--
-- Name: FUNCTION export_system_data(p_audit_from timestamp with time zone); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.export_system_data(p_audit_from timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION public.export_system_data(p_audit_from timestamp with time zone) TO authenticated;
GRANT ALL ON FUNCTION public.export_system_data(p_audit_from timestamp with time zone) TO service_role;


--
-- Name: FUNCTION get_cohorts_seat_status(p_course_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.get_cohorts_seat_status(p_course_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.get_cohorts_seat_status(p_course_id uuid) TO service_role;
GRANT ALL ON FUNCTION public.get_cohorts_seat_status(p_course_id uuid) TO authenticated;


--
-- Name: FUNCTION get_current_user_id(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.get_current_user_id() TO anon;
GRANT ALL ON FUNCTION public.get_current_user_id() TO authenticated;
GRANT ALL ON FUNCTION public.get_current_user_id() TO service_role;


--
-- Name: FUNCTION get_monthly_target_progress(p_month_key text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.get_monthly_target_progress(p_month_key text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.get_monthly_target_progress(p_month_key text) TO authenticated;
GRANT ALL ON FUNCTION public.get_monthly_target_progress(p_month_key text) TO service_role;


--
-- Name: FUNCTION get_my_password_state(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.get_my_password_state() FROM PUBLIC;
GRANT ALL ON FUNCTION public.get_my_password_state() TO authenticated;
GRANT ALL ON FUNCTION public.get_my_password_state() TO service_role;


--
-- Name: FUNCTION get_my_referral_summary(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.get_my_referral_summary() FROM PUBLIC;
GRANT ALL ON FUNCTION public.get_my_referral_summary() TO authenticated;
GRANT ALL ON FUNCTION public.get_my_referral_summary() TO service_role;


--
-- Name: FUNCTION get_session_attendance(p_session_id uuid); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.get_session_attendance(p_session_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.get_session_attendance(p_session_id uuid) TO service_role;


--
-- Name: FUNCTION get_staff_referral_summary(p_trainee_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.get_staff_referral_summary(p_trainee_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.get_staff_referral_summary(p_trainee_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.get_staff_referral_summary(p_trainee_id uuid) TO service_role;


--
-- Name: FUNCTION get_trainee_id(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.get_trainee_id() TO anon;
GRANT ALL ON FUNCTION public.get_trainee_id() TO authenticated;
GRANT ALL ON FUNCTION public.get_trainee_id() TO service_role;


--
-- Name: FUNCTION get_user_role(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.get_user_role() TO anon;
GRANT ALL ON FUNCTION public.get_user_role() TO authenticated;
GRANT ALL ON FUNCTION public.get_user_role() TO service_role;


--
-- Name: FUNCTION get_withdrawal_preview(p_enrollment_id uuid, p_sessions_override integer); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.get_withdrawal_preview(p_enrollment_id uuid, p_sessions_override integer) FROM PUBLIC;
GRANT ALL ON FUNCTION public.get_withdrawal_preview(p_enrollment_id uuid, p_sessions_override integer) TO service_role;
GRANT ALL ON FUNCTION public.get_withdrawal_preview(p_enrollment_id uuid, p_sessions_override integer) TO authenticated;


--
-- Name: FUNCTION handle_trainee_code_generation(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.handle_trainee_code_generation() TO anon;
GRANT ALL ON FUNCTION public.handle_trainee_code_generation() TO authenticated;
GRANT ALL ON FUNCTION public.handle_trainee_code_generation() TO service_role;


--
-- Name: FUNCTION has_user_pin(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.has_user_pin() FROM PUBLIC;
GRANT ALL ON FUNCTION public.has_user_pin() TO authenticated;
GRANT ALL ON FUNCTION public.has_user_pin() TO service_role;


--
-- Name: FUNCTION join_course_waitlist(p_cohort_id uuid, p_trainee_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.join_course_waitlist(p_cohort_id uuid, p_trainee_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.join_course_waitlist(p_cohort_id uuid, p_trainee_id uuid) TO service_role;
GRANT ALL ON FUNCTION public.join_course_waitlist(p_cohort_id uuid, p_trainee_id uuid) TO authenticated;


--
-- Name: FUNCTION lab_invoice_item_calc_total(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.lab_invoice_item_calc_total() TO anon;
GRANT ALL ON FUNCTION public.lab_invoice_item_calc_total() TO authenticated;
GRANT ALL ON FUNCTION public.lab_invoice_item_calc_total() TO service_role;


--
-- Name: FUNCTION lab_invoice_set_number(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.lab_invoice_set_number() TO anon;
GRANT ALL ON FUNCTION public.lab_invoice_set_number() TO authenticated;
GRANT ALL ON FUNCTION public.lab_invoice_set_number() TO service_role;


--
-- Name: FUNCTION notify_next_waitlist(p_cohort_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.notify_next_waitlist(p_cohort_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.notify_next_waitlist(p_cohort_id uuid) TO service_role;


--
-- Name: FUNCTION open_session(p_session_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.open_session(p_session_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.open_session(p_session_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.open_session(p_session_id uuid) TO service_role;


--
-- Name: FUNCTION preview_referral_code(p_code text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.preview_referral_code(p_code text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.preview_referral_code(p_code text) TO authenticated;
GRANT ALL ON FUNCTION public.preview_referral_code(p_code text) TO service_role;


--
-- Name: FUNCTION promote_waitlist_trainee(p_waitlist_id uuid, p_total_due numeric, p_discount_amount numeric, p_currency text, p_referral_code text, p_referral_discount_amount numeric); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.promote_waitlist_trainee(p_waitlist_id uuid, p_total_due numeric, p_discount_amount numeric, p_currency text, p_referral_code text, p_referral_discount_amount numeric) FROM PUBLIC;
GRANT ALL ON FUNCTION public.promote_waitlist_trainee(p_waitlist_id uuid, p_total_due numeric, p_discount_amount numeric, p_currency text, p_referral_code text, p_referral_discount_amount numeric) TO service_role;
GRANT ALL ON FUNCTION public.promote_waitlist_trainee(p_waitlist_id uuid, p_total_due numeric, p_discount_amount numeric, p_currency text, p_referral_code text, p_referral_discount_amount numeric) TO authenticated;


--
-- Name: FUNCTION recalculate_lab_invoice(p_invoice_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.recalculate_lab_invoice(p_invoice_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.recalculate_lab_invoice(p_invoice_id uuid) TO service_role;


--
-- Name: FUNCTION register_fcm_token(p_fcm_token text, p_device_type text, p_device_id text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.register_fcm_token(p_fcm_token text, p_device_type text, p_device_id text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.register_fcm_token(p_fcm_token text, p_device_type text, p_device_id text) TO authenticated;
GRANT ALL ON FUNCTION public.register_fcm_token(p_fcm_token text, p_device_type text, p_device_id text) TO service_role;


--
-- Name: FUNCTION set_installment_plan(p_enrollment_id uuid, p_installments jsonb, p_notes text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.set_installment_plan(p_enrollment_id uuid, p_installments jsonb, p_notes text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.set_installment_plan(p_enrollment_id uuid, p_installments jsonb, p_notes text) TO authenticated;
GRANT ALL ON FUNCTION public.set_installment_plan(p_enrollment_id uuid, p_installments jsonb, p_notes text) TO service_role;


--
-- Name: FUNCTION set_monthly_target(p_target_syp numeric, p_target_usd numeric, p_month_key text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.set_monthly_target(p_target_syp numeric, p_target_usd numeric, p_month_key text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.set_monthly_target(p_target_syp numeric, p_target_usd numeric, p_month_key text) TO authenticated;
GRANT ALL ON FUNCTION public.set_monthly_target(p_target_syp numeric, p_target_usd numeric, p_month_key text) TO service_role;


--
-- Name: FUNCTION set_user_pin(p_pin text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.set_user_pin(p_pin text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.set_user_pin(p_pin text) TO authenticated;
GRANT ALL ON FUNCTION public.set_user_pin(p_pin text) TO service_role;


--
-- Name: FUNCTION shift_cohort_sessions(p_cohort_id uuid, p_new_start_date date); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.shift_cohort_sessions(p_cohort_id uuid, p_new_start_date date) FROM PUBLIC;
GRANT ALL ON FUNCTION public.shift_cohort_sessions(p_cohort_id uuid, p_new_start_date date) TO authenticated;
GRANT ALL ON FUNCTION public.shift_cohort_sessions(p_cohort_id uuid, p_new_start_date date) TO service_role;


--
-- Name: FUNCTION submit_survey_response(p_dispatch_id uuid, p_answers jsonb); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.submit_survey_response(p_dispatch_id uuid, p_answers jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.submit_survey_response(p_dispatch_id uuid, p_answers jsonb) TO authenticated;
GRANT ALL ON FUNCTION public.submit_survey_response(p_dispatch_id uuid, p_answers jsonb) TO service_role;


--
-- Name: FUNCTION trg_fn_autoclose_waitlist_on_enrollment(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.trg_fn_autoclose_waitlist_on_enrollment() FROM PUBLIC;
GRANT ALL ON FUNCTION public.trg_fn_autoclose_waitlist_on_enrollment() TO service_role;


--
-- Name: FUNCTION trg_fn_c1_adjustment_apply(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.trg_fn_c1_adjustment_apply() TO anon;
GRANT ALL ON FUNCTION public.trg_fn_c1_adjustment_apply() TO authenticated;
GRANT ALL ON FUNCTION public.trg_fn_c1_adjustment_apply() TO service_role;


--
-- Name: FUNCTION trg_fn_c1_adjustment_status_sync(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.trg_fn_c1_adjustment_status_sync() FROM PUBLIC;
GRANT ALL ON FUNCTION public.trg_fn_c1_adjustment_status_sync() TO service_role;


--
-- Name: FUNCTION trg_fn_c1_default_installment(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.trg_fn_c1_default_installment() TO anon;
GRANT ALL ON FUNCTION public.trg_fn_c1_default_installment() TO authenticated;
GRANT ALL ON FUNCTION public.trg_fn_c1_default_installment() TO service_role;


--
-- Name: FUNCTION trg_fn_c1_enrollment_fee_changed(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.trg_fn_c1_enrollment_fee_changed() TO anon;
GRANT ALL ON FUNCTION public.trg_fn_c1_enrollment_fee_changed() TO authenticated;
GRANT ALL ON FUNCTION public.trg_fn_c1_enrollment_fee_changed() TO service_role;


--
-- Name: FUNCTION trg_fn_c1_installment_guard(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.trg_fn_c1_installment_guard() TO anon;
GRANT ALL ON FUNCTION public.trg_fn_c1_installment_guard() TO authenticated;
GRANT ALL ON FUNCTION public.trg_fn_c1_installment_guard() TO service_role;


--
-- Name: FUNCTION trg_fn_c1_payment_write_guard(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.trg_fn_c1_payment_write_guard() TO anon;
GRANT ALL ON FUNCTION public.trg_fn_c1_payment_write_guard() TO authenticated;
GRANT ALL ON FUNCTION public.trg_fn_c1_payment_write_guard() TO service_role;


--
-- Name: FUNCTION trg_fn_c1_payments_after(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.trg_fn_c1_payments_after() TO anon;
GRANT ALL ON FUNCTION public.trg_fn_c1_payments_after() TO authenticated;
GRANT ALL ON FUNCTION public.trg_fn_c1_payments_after() TO service_role;


--
-- Name: FUNCTION trg_fn_c1_payments_guard(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.trg_fn_c1_payments_guard() TO anon;
GRANT ALL ON FUNCTION public.trg_fn_c1_payments_guard() TO authenticated;
GRANT ALL ON FUNCTION public.trg_fn_c1_payments_guard() TO service_role;


--
-- Name: FUNCTION trg_fn_c1_plan_total(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.trg_fn_c1_plan_total() TO anon;
GRANT ALL ON FUNCTION public.trg_fn_c1_plan_total() TO authenticated;
GRANT ALL ON FUNCTION public.trg_fn_c1_plan_total() TO service_role;


--
-- Name: FUNCTION trg_fn_c1_refund_after(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.trg_fn_c1_refund_after() TO anon;
GRANT ALL ON FUNCTION public.trg_fn_c1_refund_after() TO authenticated;
GRANT ALL ON FUNCTION public.trg_fn_c1_refund_after() TO service_role;


--
-- Name: FUNCTION trg_fn_c1_refund_guard(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.trg_fn_c1_refund_guard() TO anon;
GRANT ALL ON FUNCTION public.trg_fn_c1_refund_guard() TO authenticated;
GRANT ALL ON FUNCTION public.trg_fn_c1_refund_guard() TO service_role;


--
-- Name: FUNCTION trg_fn_c1_refund_status_sync(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.trg_fn_c1_refund_status_sync() FROM PUBLIC;
GRANT ALL ON FUNCTION public.trg_fn_c1_refund_status_sync() TO service_role;


--
-- Name: FUNCTION trg_fn_course_waitlist_touch(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.trg_fn_course_waitlist_touch() FROM PUBLIC;
GRANT ALL ON FUNCTION public.trg_fn_course_waitlist_touch() TO service_role;


--
-- Name: FUNCTION trg_fn_enforce_cohort_capacity(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.trg_fn_enforce_cohort_capacity() FROM PUBLIC;
GRANT ALL ON FUNCTION public.trg_fn_enforce_cohort_capacity() TO service_role;


--
-- Name: FUNCTION trg_fn_enforce_withdrawal_rpc(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.trg_fn_enforce_withdrawal_rpc() FROM PUBLIC;
GRANT ALL ON FUNCTION public.trg_fn_enforce_withdrawal_rpc() TO service_role;


--
-- Name: FUNCTION trg_fn_enqueue_survey_notification(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.trg_fn_enqueue_survey_notification() FROM PUBLIC;
GRANT ALL ON FUNCTION public.trg_fn_enqueue_survey_notification() TO service_role;


--
-- Name: FUNCTION trg_fn_enrollment_waitlist_on_release(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.trg_fn_enrollment_waitlist_on_release() FROM PUBLIC;
GRANT ALL ON FUNCTION public.trg_fn_enrollment_waitlist_on_release() TO service_role;


--
-- Name: FUNCTION trg_fn_enrollments_referral_after(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.trg_fn_enrollments_referral_after() FROM PUBLIC;
GRANT ALL ON FUNCTION public.trg_fn_enrollments_referral_after() TO service_role;


--
-- Name: FUNCTION trg_fn_enrollments_referral_before(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.trg_fn_enrollments_referral_before() FROM PUBLIC;
GRANT ALL ON FUNCTION public.trg_fn_enrollments_referral_before() TO service_role;


--
-- Name: FUNCTION trg_fn_referral_on_enrollment_release(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.trg_fn_referral_on_enrollment_release() FROM PUBLIC;
GRANT ALL ON FUNCTION public.trg_fn_referral_on_enrollment_release() TO service_role;


--
-- Name: FUNCTION trg_fn_referrals_touch(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.trg_fn_referrals_touch() FROM PUBLIC;
GRANT ALL ON FUNCTION public.trg_fn_referrals_touch() TO service_role;


--
-- Name: FUNCTION trg_fn_validate_cohort_capacity(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.trg_fn_validate_cohort_capacity() FROM PUBLIC;
GRANT ALL ON FUNCTION public.trg_fn_validate_cohort_capacity() TO service_role;


--
-- Name: FUNCTION trg_fn_validate_waitlist_insert(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.trg_fn_validate_waitlist_insert() FROM PUBLIC;
GRANT ALL ON FUNCTION public.trg_fn_validate_waitlist_insert() TO service_role;


--
-- Name: FUNCTION trg_fn_validate_waitlist_transition(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.trg_fn_validate_waitlist_transition() FROM PUBLIC;
GRANT ALL ON FUNCTION public.trg_fn_validate_waitlist_transition() TO service_role;


--
-- Name: FUNCTION trg_fn_waitlist_on_capacity_change(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.trg_fn_waitlist_on_capacity_change() FROM PUBLIC;
GRANT ALL ON FUNCTION public.trg_fn_waitlist_on_capacity_change() TO service_role;


--
-- Name: FUNCTION trg_lab_invoice_discount_sync(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.trg_lab_invoice_discount_sync() TO anon;
GRANT ALL ON FUNCTION public.trg_lab_invoice_discount_sync() TO authenticated;
GRANT ALL ON FUNCTION public.trg_lab_invoice_discount_sync() TO service_role;


--
-- Name: FUNCTION trg_lab_invoice_items_sync(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.trg_lab_invoice_items_sync() TO anon;
GRANT ALL ON FUNCTION public.trg_lab_invoice_items_sync() TO authenticated;
GRANT ALL ON FUNCTION public.trg_lab_invoice_items_sync() TO service_role;


--
-- Name: FUNCTION trg_lab_payments_sync(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.trg_lab_payments_sync() TO anon;
GRANT ALL ON FUNCTION public.trg_lab_payments_sync() TO authenticated;
GRANT ALL ON FUNCTION public.trg_lab_payments_sync() TO service_role;


--
-- Name: FUNCTION update_enrollment_payment_status(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.update_enrollment_payment_status() FROM PUBLIC;
GRANT ALL ON FUNCTION public.update_enrollment_payment_status() TO service_role;


--
-- Name: FUNCTION verify_user_pin(p_pin text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.verify_user_pin(p_pin text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.verify_user_pin(p_pin text) TO authenticated;
GRANT ALL ON FUNCTION public.verify_user_pin(p_pin text) TO service_role;


--
-- Name: FUNCTION withdraw_enrollment(p_enrollment_id uuid, p_reason text, p_write_off_debt boolean, p_sessions_override integer); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.withdraw_enrollment(p_enrollment_id uuid, p_reason text, p_write_off_debt boolean, p_sessions_override integer) FROM PUBLIC;
GRANT ALL ON FUNCTION public.withdraw_enrollment(p_enrollment_id uuid, p_reason text, p_write_off_debt boolean, p_sessions_override integer) TO service_role;
GRANT ALL ON FUNCTION public.withdraw_enrollment(p_enrollment_id uuid, p_reason text, p_write_off_debt boolean, p_sessions_override integer) TO authenticated;


--
-- Name: TABLE attendance; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,MAINTAIN,UPDATE ON TABLE public.attendance TO authenticated;
GRANT ALL ON TABLE public.attendance TO service_role;


--
-- Name: TABLE audit_log; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,MAINTAIN,UPDATE ON TABLE public.audit_log TO authenticated;
GRANT ALL ON TABLE public.audit_log TO service_role;


--
-- Name: SEQUENCE audit_log_id_seq; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON SEQUENCE public.audit_log_id_seq TO anon;
GRANT ALL ON SEQUENCE public.audit_log_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.audit_log_id_seq TO service_role;


--
-- Name: TABLE cohorts; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,MAINTAIN,UPDATE ON TABLE public.cohorts TO authenticated;
GRANT ALL ON TABLE public.cohorts TO service_role;


--
-- Name: TABLE courses; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,MAINTAIN,UPDATE ON TABLE public.courses TO authenticated;
GRANT ALL ON TABLE public.courses TO service_role;


--
-- Name: TABLE enrollments; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,MAINTAIN,UPDATE ON TABLE public.enrollments TO authenticated;
GRANT ALL ON TABLE public.enrollments TO service_role;


--
-- Name: TABLE payments; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,MAINTAIN,UPDATE ON TABLE public.payments TO authenticated;
GRANT ALL ON TABLE public.payments TO service_role;


--
-- Name: TABLE trainees; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,MAINTAIN,UPDATE ON TABLE public.trainees TO authenticated;
GRANT ALL ON TABLE public.trainees TO service_role;


--
-- Name: TABLE users; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,MAINTAIN,UPDATE ON TABLE public.users TO authenticated;
GRANT ALL ON TABLE public.users TO service_role;


--
-- Name: TABLE enrollment_financial_summary; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,MAINTAIN,UPDATE ON TABLE public.enrollment_financial_summary TO authenticated;
GRANT ALL ON TABLE public.enrollment_financial_summary TO service_role;


--
-- Name: TABLE cash_vs_accrual_kpis; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,MAINTAIN,UPDATE ON TABLE public.cash_vs_accrual_kpis TO authenticated;
GRANT ALL ON TABLE public.cash_vs_accrual_kpis TO service_role;


--
-- Name: TABLE fee_adjustments; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.fee_adjustments TO authenticated;
GRANT ALL ON TABLE public.fee_adjustments TO service_role;


--
-- Name: TABLE installment_schedule; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE public.installment_schedule TO authenticated;
GRANT ALL ON TABLE public.installment_schedule TO service_role;


--
-- Name: TABLE payment_allocations; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE public.payment_allocations TO authenticated;
GRANT ALL ON TABLE public.payment_allocations TO service_role;


--
-- Name: TABLE payment_refunds; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.payment_refunds TO authenticated;
GRANT ALL ON TABLE public.payment_refunds TO service_role;


--
-- Name: TABLE enrollment_financial_summary_v2; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.enrollment_financial_summary_v2 TO authenticated;
GRANT ALL ON TABLE public.enrollment_financial_summary_v2 TO service_role;


--
-- Name: TABLE cash_vs_accrual_kpis_v2; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.cash_vs_accrual_kpis_v2 TO authenticated;
GRANT ALL ON TABLE public.cash_vs_accrual_kpis_v2 TO service_role;


--
-- Name: TABLE course_materials; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.course_materials TO authenticated;
GRANT ALL ON TABLE public.course_materials TO service_role;


--
-- Name: TABLE course_revenue_sql_summary; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,MAINTAIN,UPDATE ON TABLE public.course_revenue_sql_summary TO authenticated;
GRANT ALL ON TABLE public.course_revenue_sql_summary TO service_role;


--
-- Name: TABLE course_revenue_sql_summary_v2; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.course_revenue_sql_summary_v2 TO authenticated;
GRANT ALL ON TABLE public.course_revenue_sql_summary_v2 TO service_role;


--
-- Name: TABLE course_waitlist; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.course_waitlist TO service_role;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.course_waitlist TO authenticated;


--
-- Name: TABLE cron_job_log; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.cron_job_log TO authenticated;
GRANT ALL ON TABLE public.cron_job_log TO service_role;


--
-- Name: TABLE expenses; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,MAINTAIN,UPDATE ON TABLE public.expenses TO authenticated;
GRANT ALL ON TABLE public.expenses TO service_role;


--
-- Name: TABLE dashboard_kpis; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.dashboard_kpis TO authenticated;
GRANT ALL ON TABLE public.dashboard_kpis TO service_role;


--
-- Name: TABLE debt_aging_report; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,MAINTAIN,UPDATE ON TABLE public.debt_aging_report TO authenticated;
GRANT ALL ON TABLE public.debt_aging_report TO service_role;


--
-- Name: TABLE debt_aging_report_v2; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.debt_aging_report_v2 TO authenticated;
GRANT ALL ON TABLE public.debt_aging_report_v2 TO service_role;


--
-- Name: TABLE discounts_report; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,MAINTAIN,UPDATE ON TABLE public.discounts_report TO authenticated;
GRANT ALL ON TABLE public.discounts_report TO service_role;


--
-- Name: TABLE discounts_report_v2; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.discounts_report_v2 TO authenticated;
GRANT ALL ON TABLE public.discounts_report_v2 TO service_role;


--
-- Name: TABLE enrollment_withdrawals; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.enrollment_withdrawals TO service_role;
GRANT SELECT ON TABLE public.enrollment_withdrawals TO authenticated;


--
-- Name: TABLE expenses_by_category_report; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,MAINTAIN,UPDATE ON TABLE public.expenses_by_category_report TO authenticated;
GRANT ALL ON TABLE public.expenses_by_category_report TO service_role;


--
-- Name: TABLE expenses_by_category_report_v2; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.expenses_by_category_report_v2 TO authenticated;
GRANT ALL ON TABLE public.expenses_by_category_report_v2 TO service_role;


--
-- Name: TABLE lab_clients; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.lab_clients TO authenticated;
GRANT ALL ON TABLE public.lab_clients TO service_role;


--
-- Name: TABLE lab_expenses; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.lab_expenses TO authenticated;
GRANT ALL ON TABLE public.lab_expenses TO service_role;


--
-- Name: TABLE lab_invoice_items; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.lab_invoice_items TO authenticated;
GRANT ALL ON TABLE public.lab_invoice_items TO service_role;


--
-- Name: SEQUENCE lab_invoice_number_seq; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON SEQUENCE public.lab_invoice_number_seq TO anon;
GRANT ALL ON SEQUENCE public.lab_invoice_number_seq TO authenticated;
GRANT ALL ON SEQUENCE public.lab_invoice_number_seq TO service_role;


--
-- Name: TABLE lab_invoices; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.lab_invoices TO authenticated;
GRANT ALL ON TABLE public.lab_invoices TO service_role;


--
-- Name: TABLE lab_payments; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.lab_payments TO authenticated;
GRANT ALL ON TABLE public.lab_payments TO service_role;


--
-- Name: TABLE monthly_targets; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.monthly_targets TO authenticated;
GRANT ALL ON TABLE public.monthly_targets TO service_role;


--
-- Name: TABLE notification_outbox; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.notification_outbox TO anon;
GRANT ALL ON TABLE public.notification_outbox TO authenticated;
GRANT ALL ON TABLE public.notification_outbox TO service_role;


--
-- Name: TABLE open_sessions_view; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,MAINTAIN,UPDATE ON TABLE public.open_sessions_view TO authenticated;
GRANT ALL ON TABLE public.open_sessions_view TO service_role;


--
-- Name: TABLE overdue_installments_v; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.overdue_installments_v TO authenticated;
GRANT ALL ON TABLE public.overdue_installments_v TO service_role;


--
-- Name: TABLE overdue_payments; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.overdue_payments TO authenticated;
GRANT ALL ON TABLE public.overdue_payments TO service_role;


--
-- Name: TABLE profit_loss_report; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,MAINTAIN,UPDATE ON TABLE public.profit_loss_report TO authenticated;
GRANT ALL ON TABLE public.profit_loss_report TO service_role;


--
-- Name: TABLE profit_loss_report_v2; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.profit_loss_report_v2 TO authenticated;
GRANT ALL ON TABLE public.profit_loss_report_v2 TO service_role;


--
-- Name: TABLE referrals; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.referrals TO service_role;
GRANT SELECT ON TABLE public.referrals TO authenticated;


--
-- Name: TABLE revenue_by_method_report; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,MAINTAIN,UPDATE ON TABLE public.revenue_by_method_report TO authenticated;
GRANT ALL ON TABLE public.revenue_by_method_report TO service_role;


--
-- Name: TABLE revenue_by_method_report_v2; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.revenue_by_method_report_v2 TO authenticated;
GRANT ALL ON TABLE public.revenue_by_method_report_v2 TO service_role;


--
-- Name: TABLE sessions; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,MAINTAIN,UPDATE ON TABLE public.sessions TO authenticated;
GRANT ALL ON TABLE public.sessions TO service_role;


--
-- Name: TABLE survey_dispatches; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,MAINTAIN,UPDATE ON TABLE public.survey_dispatches TO authenticated;
GRANT ALL ON TABLE public.survey_dispatches TO service_role;


--
-- Name: TABLE survey_responses; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,MAINTAIN,UPDATE ON TABLE public.survey_responses TO authenticated;
GRANT ALL ON TABLE public.survey_responses TO service_role;


--
-- Name: TABLE survey_templates; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,MAINTAIN,UPDATE ON TABLE public.survey_templates TO authenticated;
GRANT ALL ON TABLE public.survey_templates TO service_role;


--
-- Name: TABLE survey_statistics; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,MAINTAIN,UPDATE ON TABLE public.survey_statistics TO authenticated;
GRANT ALL ON TABLE public.survey_statistics TO service_role;


--
-- Name: TABLE trainee_academic_progress; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.trainee_academic_progress TO service_role;
GRANT SELECT ON TABLE public.trainee_academic_progress TO authenticated;


--
-- Name: SEQUENCE trainee_code_seq; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON SEQUENCE public.trainee_code_seq TO anon;
GRANT ALL ON SEQUENCE public.trainee_code_seq TO authenticated;
GRANT ALL ON SEQUENCE public.trainee_code_seq TO service_role;


--
-- Name: TABLE trainee_next_sessions; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.trainee_next_sessions TO anon;
GRANT ALL ON TABLE public.trainee_next_sessions TO authenticated;
GRANT ALL ON TABLE public.trainee_next_sessions TO service_role;


--
-- Name: TABLE trainee_payment_receipts; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.trainee_payment_receipts TO anon;
GRANT ALL ON TABLE public.trainee_payment_receipts TO authenticated;
GRANT ALL ON TABLE public.trainee_payment_receipts TO service_role;


--
-- Name: TABLE trainee_safe_profile; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.trainee_safe_profile TO anon;
GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,MAINTAIN,UPDATE ON TABLE public.trainee_safe_profile TO authenticated;
GRANT ALL ON TABLE public.trainee_safe_profile TO service_role;


--
-- Name: TABLE trainee_statement_v; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.trainee_statement_v TO authenticated;
GRANT ALL ON TABLE public.trainee_statement_v TO service_role;


--
-- Name: TABLE user_fcm_tokens; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.user_fcm_tokens TO anon;
GRANT ALL ON TABLE public.user_fcm_tokens TO authenticated;
GRANT ALL ON TABLE public.user_fcm_tokens TO service_role;


--
-- Name: TABLE user_pins; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.user_pins TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR SEQUENCES; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR SEQUENCES; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON SEQUENCES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON SEQUENCES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON SEQUENCES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON SEQUENCES TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR FUNCTIONS; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR FUNCTIONS; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON FUNCTIONS TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON FUNCTIONS TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON FUNCTIONS TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON FUNCTIONS TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON TABLES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON TABLES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON TABLES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON TABLES TO service_role;


--
-- PostgreSQL database dump complete
--

-- \unrestrict rCv2pK1UjbLvqsKsd43B4uenpvplvUSrVwdVn9Y4SBLoWc3QmQHzFW0BUPxD0Rs



