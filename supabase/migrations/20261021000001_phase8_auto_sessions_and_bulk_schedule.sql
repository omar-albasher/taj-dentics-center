-- ==============================================================================
-- Taj Dentics Training Center - Phase 8: Auto Sessions, Bulk Schedule & Details
-- Migration: 20261021000001_phase8_auto_sessions_and_bulk_schedule.sql
-- ==============================================================================

-- 1. Schema Expansion for public.sessions
-- ------------------------------------------------------------------------------
ALTER TABLE public.sessions 
  ADD COLUMN IF NOT EXISTS title TEXT,
  ADD COLUMN IF NOT EXISTS description TEXT,
  ADD COLUMN IF NOT EXISTS duration_minutes INT NOT NULL DEFAULT 120;

-- 2. Audit & Heartbeat Log Table for Cron Automation
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.cron_job_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  job_name TEXT NOT NULL,
  executed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  opened_sessions_count INT NOT NULL DEFAULT 0,
  closed_sessions_count INT NOT NULL DEFAULT 0,
  missed_sessions_count INT NOT NULL DEFAULT 0,
  details JSONB,
  status TEXT NOT NULL DEFAULT 'success'
);

ALTER TABLE public.cron_job_log ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Allow staff to read cron logs" ON public.cron_job_log;
CREATE POLICY "Allow staff to read cron logs"
ON public.cron_job_log FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.users 
    WHERE id = auth.uid() AND role IN ('admin', 'reception') AND is_active = true
  )
);

-- 3. Atomic Server-Side Session Open RPC with Secure QR Generation
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.open_session(p_session_id UUID)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role TEXT;
  v_qr TEXT;
BEGIN
  -- التحقق من صلاحية المستخدم
  SELECT role INTO v_role 
  FROM public.users 
  WHERE id = auth.uid() AND is_active = true;

  IF v_role IS NULL OR v_role NOT IN ('admin', 'reception') THEN
    RAISE EXCEPTION 'غير مصرح: فتح الجلسة مخصص للإدارة والاستقبال فقط';
  END IF;

  v_qr := gen_random_uuid()::text;

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
    'qr_token', v_qr, 
    'opened_at', now()
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.open_session FROM public, anon;
GRANT EXECUTE ON FUNCTION public.open_session TO authenticated;


-- 4. Idempotent Auto Open/Close/Missed Automation with Dry-Run Mode
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.auto_open_close_sessions(p_dry_run BOOLEAN DEFAULT false)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_opened_count INT := 0;
  v_closed_count INT := 0;
  v_missed_count INT := 0;
  v_opened_ids UUID[] := '{}';
  v_closed_ids UUID[] := '{}';
  v_missed_ids UUID[] := '{}';
BEGIN
  -- A. الفتح التلقائي: مجدولة، حان وقتها، ولم يمضِ أكثر من 60 دقيقة
  SELECT COALESCE(array_agg(id), '{}') INTO v_opened_ids
  FROM public.sessions
  WHERE status = 'scheduled'
    AND scheduled_at <= now()
    AND scheduled_at > now() - interval '60 minutes';

  v_opened_count := cardinality(v_opened_ids);

  IF NOT p_dry_run AND v_opened_count > 0 THEN
    UPDATE public.sessions
    SET status = 'open',
        qr_token = gen_random_uuid()::text,
        opened_at = now(),
        opened_by = NULL -- علامة على الفتح التلقائي بالسيرفر
    WHERE id = ANY(v_opened_ids)
      AND status = 'scheduled';
  END IF;

  -- B. الإغلاق التلقائي: مفتوحة ومضت المدة المحددة (opened_at + duration_minutes)
  SELECT COALESCE(array_agg(id), '{}') INTO v_closed_ids
  FROM public.sessions
  WHERE status = 'open'
    AND opened_at IS NOT NULL
    AND (opened_at + (duration_minutes || ' minutes')::interval) <= now();

  v_closed_count := cardinality(v_closed_ids);

  IF NOT p_dry_run AND v_closed_count > 0 THEN
    UPDATE public.sessions
    SET status = 'closed',
        qr_token = NULL,
        closed_at = now()
    WHERE id = ANY(v_closed_ids)
      AND status = 'open';
  END IF;

  -- C. معالجة الجلسات المهجورة (Abandoned Sessions -> Missed)
  -- تأخرت أكثر من ساعتين عن موعدها ولم تُفتح أبداً
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

  -- D. تسجيل نبض التشغيل في جدول السجلات (Heartbeat)
  INSERT INTO public.cron_job_log (
    job_name,
    opened_sessions_count,
    closed_sessions_count,
    missed_sessions_count,
    details,
    status
  )
  VALUES (
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
    'dry_run', p_dry_run,
    'opened_count', v_opened_count,
    'closed_count', v_closed_count,
    'missed_count', v_missed_count,
    'timestamp', now()
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.auto_open_close_sessions FROM public, anon;
GRANT EXECUTE ON FUNCTION public.auto_open_close_sessions TO authenticated, service_role;


-- 5. Bulk Schedule Sessions RPC (Atomic single INSERT with generate_series)
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.bulk_schedule_sessions(
  p_cohort_id UUID,
  p_start_date DATE,
  p_start_time TIME,
  p_days_of_week INT[], -- 0=Sunday, 1=Monday ... 6=Saturday
  p_session_count INT,
  p_duration_minutes INT DEFAULT 120
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role TEXT;
  v_max_session_num INT := 0;
  v_has_executed BOOLEAN := false;
  v_min_date TIMESTAMPTZ;
  v_inserted_count INT := 0;
BEGIN
  -- 1. التحقق من صلاحيات الإدارة والاستقبال
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

  -- 2. معرفة أعلى رقم جلسة حالية في هذه الدفعة
  SELECT COALESCE(MAX(session_number), 0) INTO v_max_session_num
  FROM public.sessions
  WHERE cohort_id = p_cohort_id;

  -- فحص ما إذا كانت الدفعة قد بدأت
  SELECT EXISTS (
    SELECT 1 FROM public.sessions 
    WHERE cohort_id = p_cohort_id AND status IN ('open', 'closed')
  ) INTO v_has_executed;

  -- 3. توليد وإدراج الجلسات بدقة ذرية عبر generate_series وحساب التوقيت بدمشق
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

  -- 4. تحديث موعد انطلاق الدفعة إذا كانت لم تبدأ بعد
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

REVOKE EXECUTE ON FUNCTION public.bulk_schedule_sessions FROM public, anon;
GRANT EXECUTE ON FUNCTION public.bulk_schedule_sessions TO authenticated;
