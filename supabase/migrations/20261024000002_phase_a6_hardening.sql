-- ==============================================================================
-- Taj Dentics Training Center - Phase A6 Hardening Migration
-- 1. Exclude dropped enrollments from Course Materials RLS (table & storage)
-- 2. Add course_id to trainee_academic_progress view
-- 3. Add data integrity CHECK constraint to course_materials
-- ==============================================================================

-- 1. Update trainee_academic_progress view to include course_id
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
    count(DISTINCT s.id) FILTER (WHERE s.is_extra IS TRUE) AS extra_sessions_count,
    co.id AS course_id
FROM public.enrollments e
  JOIN public.trainees t ON t.id = e.trainee_id
  JOIN public.users u ON u.id = t.user_id
  JOIN public.cohorts ch ON ch.id = e.cohort_id
  JOIN public.courses co ON co.id = ch.course_id
  LEFT JOIN public.sessions s ON s.cohort_id = ch.id
  LEFT JOIN public.attendance a ON a.session_id = s.id AND a.trainee_id = e.trainee_id
GROUP BY e.id, e.trainee_id, u.full_name, co.id, co.name, co.total_sessions;

-- 2. Hardened Table RLS: Exclude dropped trainees
DROP POLICY IF EXISTS "Trainees can view published materials for enrolled courses" ON public.course_materials;

CREATE POLICY "Trainees can view published materials for enrolled courses"
ON public.course_materials
FOR SELECT
TO authenticated
USING (
  is_published = true
  AND EXISTS (
    SELECT 1
    FROM public.enrollments e
    JOIN public.cohorts c ON c.id = e.cohort_id
    JOIN public.trainees t ON t.id = e.trainee_id
    WHERE c.course_id = course_materials.course_id
      AND t.user_id = auth.uid()
      AND e.status::text <> 'dropped'
  )
);

-- 3. Hardened Storage RLS: Exclude dropped trainees from downloading
DROP POLICY IF EXISTS "Trainees can download course materials for enrolled courses" ON storage.objects;

CREATE POLICY "Trainees can download course materials for enrolled courses"
ON storage.objects
FOR SELECT
TO authenticated
USING (
  bucket_id = 'course-materials'
  AND EXISTS (
    SELECT 1
    FROM public.course_materials cm
    JOIN public.enrollments e ON true
    JOIN public.cohorts c ON c.id = e.cohort_id AND c.course_id = cm.course_id
    JOIN public.trainees t ON t.id = e.trainee_id
    WHERE cm.file_path = storage.objects.name
      AND cm.is_published = true
      AND t.user_id = auth.uid()
      AND e.status::text <> 'dropped'
  )
);

-- 4. Data integrity CHECK constraint
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'chk_course_materials_type_integrity'
  ) THEN
    ALTER TABLE public.course_materials
    ADD CONSTRAINT chk_course_materials_type_integrity
    CHECK (
      (material_type = 'file' AND file_path IS NOT NULL) OR
      (material_type = 'link' AND external_url IS NOT NULL)
    );
  END IF;
END $$;
