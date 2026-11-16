-- ============================================================================
-- Migration: 20261116000012_phase_d5_sessions_hardening.sql
-- Description: Phase D5 / #46 - Sessions hardening (S1 + S2 + S3)
--
-- Fixes (all verified against the live baseline on 2026-11-16):
--   S1. session_status enum lacks 'missed' while auto_open_close_sessions
--       writes it (baseline:97-101 vs :307) -> the cron aborts and never
--       auto-opens/closes sessions once any stale scheduled row exists.
--       Also fixes qr_token uuid type mismatch in auto_open_close_sessions:273.
--   S2. Reception reaches /sessions (app_router.dart:88, app_shell.dart:97)
--       but holds SELECT-only on sessions (baseline:7946) while the UI writes
--       directly (admin_sessions_repository.dart:22-40,62-72). Replaced by
--       atomic SECURITY DEFINER RPCs (create_session, close_session, open_session);
--       no broad UPDATE policy is added. Also fixes qr_token uuid type mismatch
--       in baseline open_session:2331-2335.
--   S3. shift_cohort_sessions reads/writes a nonexistent `session_date`
--       column (baseline:2847-2881) while sessions has scheduled_at
--       (baseline:5728) -> rescheduling always fails at runtime. Rewritten
--       with Damascus local-date math that preserves wall-clock time.
--
-- Roll-forward history note: if v_day_delta arithmetic changes across DST,
-- timestamptz -> local timestamp -> add days -> timestamptz is required.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- S1. Add the missing enum value (must not be used in this transaction)
-- ----------------------------------------------------------------------------
ALTER TYPE public.session_status ADD VALUE IF NOT EXISTS 'missed';

-- ----------------------------------------------------------------------------
-- S1b. auto_open_close_sessions: fix qr_token text cast (UUID type mismatch)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.auto_open_close_sessions(p_dry_run boolean DEFAULT false)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_opened_count INT := 0;
  v_closed_count INT := 0;
  v_missed_count INT := 0;
  v_opened_ids UUID[] := '{}';
  v_closed_ids UUID[] := '{}';
  v_missed_ids UUID[] := '{}';
BEGIN
  -- A. الفتح التلقائي
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

  -- B. الإغلاق التلقائي (حفظ qr_token لدعم نافذة الـ 30 دقيقة)
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

  -- C. معالجة الجلسات المهجورة (Scheduled -> Missed بعد ساعتين)
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

  -- D. تسجيل نبض التشغيل
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

REVOKE ALL ON FUNCTION public.auto_open_close_sessions(boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.auto_open_close_sessions(boolean) TO authenticated, service_role;

-- ----------------------------------------------------------------------------
-- S2a. create_session: staff-only atomic insert
--      Parity with bulk_schedule_sessions, which already lets reception
--      schedule regular sessions (baseline:373-379).
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.create_session(
  p_cohort_id uuid,
  p_session_number integer,
  p_scheduled_at timestamptz,
  p_duration_minutes integer DEFAULT 120,
  p_is_extra boolean DEFAULT false,
  p_title text DEFAULT NULL,
  p_description text DEFAULT NULL
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
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

REVOKE ALL ON FUNCTION public.create_session(uuid, integer, timestamptz, integer, boolean, text, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_session(uuid, integer, timestamptz, integer, boolean, text, text)
  TO authenticated, service_role;

-- ----------------------------------------------------------------------------
-- S2b. open_session: staff-only atomic open with fixed UUID qr_token
--      Fixes baseline:2331-2335 where v_qr TEXT caused error 42804.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.open_session(p_session_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
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

REVOKE ALL ON FUNCTION public.open_session(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.open_session(uuid) TO authenticated, service_role;

-- ----------------------------------------------------------------------------
-- S2c. close_session: staff-only atomic close of an open session
--      qr_token is preserved on purpose (30-minute offline grace window).
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.close_session(p_session_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
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

REVOKE ALL ON FUNCTION public.close_session(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.close_session(uuid) TO authenticated, service_role;

-- ----------------------------------------------------------------------------
-- S3. shift_cohort_sessions: replace phantom session_date with scheduled_at
--     Local-date basis is Asia/Damascus; the shift preserves wall-clock time.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.shift_cohort_sessions(p_cohort_id uuid, p_new_start_date date)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
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
  -- 1. التحقق من الصلاحيات
  SELECT role, is_active INTO v_role, v_is_active
  FROM public.users
  WHERE id = auth.uid();

  IF v_role IS NULL OR v_is_active IS NOT TRUE OR v_role NOT IN ('admin', 'reception') THEN
    RAISE EXCEPTION 'غير مصرح لك بترحيل مواعيد الجلسات';
  END IF;

  -- 2. التحقق من وجود جلسات منفذة (مفتوحة أو مغلقة)
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

  -- 3. جلب تاريخ أول جلسة مجدولة (بتوقيت دمشق)
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

  -- 4. إزاحة الجلسات المجدولة فقط (حفظ ساعة الجدار بتوقيت دمشق)
  UPDATE public.sessions
  SET scheduled_at = (
        (scheduled_at AT TIME ZONE 'Asia/Damascus') + make_interval(days => v_day_delta)
      ) AT TIME ZONE 'Asia/Damascus'
  WHERE cohort_id = p_cohort_id
    AND status = 'scheduled';

  GET DIAGNOSTICS v_shifted_count = ROW_COUNT;

  -- 5. تحديث تاريخ بداية الدفعة فقط إذا لم تبدأ أي جلسة بعد
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

-- CREATE OR REPLACE preserves the existing ACLs (REVOKE PUBLIC / GRANT authenticated,
-- service_role) recorded in baseline:8597-8599.

