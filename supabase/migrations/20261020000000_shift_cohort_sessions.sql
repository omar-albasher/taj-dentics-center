-- ==============================================================================
-- Taj Dentics Training Center - Shift Cohort Sessions RPC (Phase 7)
-- Date: 2026-10-20
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.shift_cohort_sessions(
  p_cohort_id UUID,
  p_new_start_date TIMESTAMPTZ
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_old_date TIMESTAMPTZ;
  v_delta INTERVAL;
  v_count INT;
  v_has_executed_sessions BOOLEAN;
  v_last_executed_date TIMESTAMPTZ;
BEGIN
  -- 1. فحص الصلاحيات الصارم (Admin / Reception فقط)
  IF NOT EXISTS (
    SELECT 1 FROM public.users
    WHERE id = auth.uid() 
      AND role IN ('admin', 'reception') 
      AND is_active = true
  ) THEN
    RAISE EXCEPTION 'غير مصرح: هذه العملية مخصصة للإدارة فقط';
  END IF;

  -- 2. إيجاد تاريخ أقرب جلسة مجدولة
  SELECT MIN(scheduled_at) INTO v_old_date
  FROM public.sessions
  WHERE cohort_id = p_cohort_id AND status = 'scheduled';

  IF v_old_date IS NULL THEN
    RETURN jsonb_build_object(
      'success', false, 
      'message', 'لا توجد جلسات مجدولة لتحريكها في هذه الدفعة'
    );
  END IF;

  -- 3. فحص وجود جلسات منفذة مسبقاً وتاريخ آخر واحدة منها
  SELECT 
    EXISTS(SELECT 1 FROM public.sessions WHERE cohort_id = p_cohort_id AND status IN ('open', 'closed')),
    MAX(scheduled_at)
  INTO v_has_executed_sessions, v_last_executed_date
  FROM public.sessions
  WHERE cohort_id = p_cohort_id AND status IN ('open', 'closed');

  -- منع وضع الجلسات المجدولة قبل آخر جلسة منفذة
  IF v_has_executed_sessions AND p_new_start_date <= v_last_executed_date THEN
    RETURN jsonb_build_object(
      'success', false, 
      'message', 'لا يمكن إزاحة الجلسات لتاريخ يسبق الجلسات المنفذة بالفعل'
    );
  END IF;

  -- 4. حساب الفارق الزمني وتطبيقه على الجلسات المجدولة حصراً
  v_delta := p_new_start_date - v_old_date;

  UPDATE public.sessions
  SET scheduled_at = scheduled_at + v_delta
  WHERE cohort_id = p_cohort_id AND status = 'scheduled';

  GET DIAGNOSTICS v_count = ROW_COUNT;

  -- 5. تحديث تاريخ بداية الدفعة فقط إذا لم تكن قد بدأت أصلاً
  IF NOT v_has_executed_sessions THEN
    UPDATE public.cohorts
    SET starts_at = p_new_start_date
    WHERE id = p_cohort_id;
  END IF;

  RETURN jsonb_build_object(
    'success', true, 
    'count', v_count, 
    'message', 'تمت إزاحة ' || v_count || ' جلسة مجدولة بنجاح'
  );
END;
$$;

-- إلغاء صلاحية الوصول العام للمجهولين
REVOKE EXECUTE ON FUNCTION public.shift_cohort_sessions FROM anon;
