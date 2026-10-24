-- ==============================================================================
-- Taj Dentics Training Center - Phase A2: Smart Responder & Grace Period Support
-- Migration: 20261024000000_phase_a2_smart_responder_and_grace_period.sql
-- ==============================================================================

-- 1. Drop accidental/dummy function if previously defined
DROP FUNCTION IF EXISTS public.close_expired_sessions(BOOLEAN);

-- 2. Add captured_at audit column to attendance table for offline timestamp tracking
ALTER TABLE public.attendance 
  ADD COLUMN IF NOT EXISTS captured_at TIMESTAMPTZ;

-- 3. Update auto_open_close_sessions (the actual cron function) to preserve qr_token on auto-close
--    This ensures offline attendee scans submitted within the 30-minute grace
--    period can resolve the session by its qr_token.
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
  -- ملاحظة: تم إبقاء qr_token كما هو دون تصفير لدعم نافذة السماح (30 دقيقة) للمتزامنين أوفلاين
  SELECT COALESCE(array_agg(id), '{}') INTO v_closed_ids
  FROM public.sessions
  WHERE status = 'open'
    AND opened_at IS NOT NULL
    AND (opened_at + (duration_minutes || ' minutes')::interval) <= now();

  v_closed_count := cardinality(v_closed_ids);

  IF NOT p_dry_run AND v_closed_count > 0 THEN
    UPDATE public.sessions
    SET status = 'closed',
        -- qr_token remains intact to allow 30-minute grace window for offline sync
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
