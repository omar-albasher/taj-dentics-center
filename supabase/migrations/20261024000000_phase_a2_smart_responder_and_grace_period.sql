-- ==============================================================================
-- Taj Dentics Training Center - Phase A2: Smart Responder & Grace Period Support
-- Migration: 20261024000000_phase_a2_smart_responder_and_grace_period.sql
-- ==============================================================================

-- 1. Add captured_at audit column to attendance table for offline timestamp tracking
ALTER TABLE public.attendance 
  ADD COLUMN IF NOT EXISTS captured_at TIMESTAMPTZ;

-- 2. Update close_expired_sessions function to preserve qr_token on auto-close
--    This allows offline attendee scans submitted within the 30-minute grace
--    period to resolve the session by its token.
CREATE OR REPLACE FUNCTION public.close_expired_sessions(p_dry_run BOOLEAN DEFAULT false)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role TEXT;
  v_closed_ids UUID[];
  v_missed_ids UUID[];
  v_closed_count INT := 0;
  v_missed_count INT := 0;
BEGIN
  -- التحقق من الصلاحية (يمكن استدعاؤها عبر كرون بمفتاح الخدمة service_role أو بواسطة admin)
  IF auth.uid() IS NOT NULL THEN
    SELECT role INTO v_role 
    FROM public.users 
    WHERE id = auth.uid() AND is_active = true;

    IF v_role IS NULL OR v_role NOT IN ('admin') THEN
      RAISE EXCEPTION 'غير مصرح: إدارة الجلسات من صلاحيات الأدمن فقط';
    END IF;
  END IF;

  -- B. معالجة الجلسات المنتهية (Expired Sessions -> Closed)
  -- الجلسات المفتوحة التي تجاوزت مدتها المقررة
  SELECT COALESCE(array_agg(id), '{}') INTO v_closed_ids
  FROM public.sessions
  WHERE status = 'open'
    AND opened_at IS NOT NULL
    AND (opened_at + (duration_minutes || ' minutes')::interval) <= now();

  v_closed_count := cardinality(v_closed_ids);

  IF NOT p_dry_run AND v_closed_count > 0 THEN
    UPDATE public.sessions
    SET status = 'closed',
        -- qr_token remains intact to support 30-minute grace window for offline sync
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

  RETURN jsonb_build_object(
    'success', true,
    'dry_run', p_dry_run,
    'closed_count', v_closed_count,
    'closed_session_ids', v_closed_ids,
    'missed_count', v_missed_count,
    'missed_session_ids', v_missed_ids,
    'executed_at', now()
  );
END;
$$;
