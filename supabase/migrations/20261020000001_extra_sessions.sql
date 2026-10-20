-- ====================================================================
-- Phase 6: Extra Sessions (الجلسات الإضافية)
-- 1. Add is_extra column to public.sessions
-- 2. Update check_survey_dispatch() to ignore extra sessions
-- 3. Update trainee_academic_progress view with safe bounds (0 to 100)
-- ====================================================================

-- 1. إضافة عمود is_extra
ALTER TABLE public.sessions 
ADD COLUMN IF NOT EXISTS is_extra boolean NOT NULL DEFAULT false;

-- 2. تحديث دالة التريغر check_survey_dispatch لعدم احتساب الجلسات الإضافية في عتبات الاستبيانات
CREATE OR REPLACE FUNCTION public.check_survey_dispatch()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
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
$function$;

-- 3. تحديث trainee_academic_progress view
CREATE OR REPLACE VIEW public.trainee_academic_progress AS
SELECT 
    e.id AS enrollment_id,
    e.trainee_id,
    u.full_name AS trainee_name,
    co.name AS course_name,
    co.total_sessions,
    count(a.id) AS sessions_attended,
    -- حماية القاع: المتبقي لا يمكن أن يقل عن صفر أبداً
    GREATEST(0::bigint, co.total_sessions - count(a.id)) AS sessions_remaining,
    -- حماية السقف: النسبة لا يمكن أن تتجاوز 100% أبداً
    LEAST(100, round(count(a.id)::numeric * 100.0 / NULLIF(co.total_sessions, 0)::numeric)) AS attendance_percentage,
    -- أعمدة تفصيلية داعمة للميزات المتقدمة دون كسر التوافق
    count(a.id) FILTER (WHERE s.is_extra IS NOT TRUE) AS base_sessions_attended,
    count(a.id) FILTER (WHERE s.is_extra IS TRUE) AS extra_sessions_attended,
    count(DISTINCT s.id) FILTER (WHERE s.is_extra IS TRUE) AS extra_sessions_count
FROM enrollments e
  JOIN trainees t ON t.id = e.trainee_id
  JOIN users u ON u.id = t.user_id
  JOIN cohorts ch ON ch.id = e.cohort_id
  JOIN courses co ON co.id = ch.course_id
  LEFT JOIN sessions s ON s.cohort_id = ch.id
  LEFT JOIN attendance a ON a.session_id = s.id AND a.trainee_id = e.trainee_id
GROUP BY e.id, e.trainee_id, u.full_name, co.name, co.total_sessions;
