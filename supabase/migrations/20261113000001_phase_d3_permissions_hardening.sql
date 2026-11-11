-- ==============================================================================
-- Phase D3: Permissions Hardening & Confidentiality
-- File: supabase/migrations/20261113000001_phase_d3_permissions_hardening.sql
-- ==============================================================================

BEGIN;

-- 1) Revoke leaked public/anon grants on course_materials table
REVOKE ALL ON public.course_materials FROM anon, public;
GRANT SELECT ON public.course_materials TO authenticated;
GRANT ALL ON public.course_materials TO service_role;

-- 2) Consolidate course_materials table SELECT policies to exclude withdrawn trainees
DROP POLICY IF EXISTS "course_materials_select_policy" ON public.course_materials;
DROP POLICY IF EXISTS "Trainees can view published materials for enrolled courses" ON public.course_materials;

CREATE POLICY "course_materials_read_policy"
ON public.course_materials
FOR SELECT
TO authenticated
USING (
  -- Staff access (Admin, Reception, Accountant)
  public.c1_is_staff()
  OR
  -- Active enrolled trainees only
  (
    is_published = true
    AND EXISTS (
      SELECT 1
      FROM public.enrollments e
      JOIN public.cohorts c ON c.id = e.cohort_id
      JOIN public.trainees t ON t.id = e.trainee_id
      WHERE c.course_id = course_materials.course_id
        AND t.user_id = auth.uid()
        AND COALESCE(e.lifecycle_status, 'active') <> 'withdrawn'
        AND (e.status)::text NOT IN ('dropped', 'cancelled', 'canceled')
    )
  )
);

-- 3) Consolidate storage.objects download policies for course-materials bucket
DROP POLICY IF EXISTS "authenticated_course_materials_download" ON storage.objects;
DROP POLICY IF EXISTS "Trainees can download course materials for enrolled courses" ON storage.objects;

CREATE POLICY "course_materials_storage_download"
ON storage.objects
FOR SELECT
TO authenticated
USING (
  bucket_id = 'course-materials'
  AND (
    -- Staff access
    public.c1_is_staff()
    OR
    -- Active enrolled trainees for the specific course material file
    EXISTS (
      SELECT 1
      FROM public.course_materials cm
      JOIN public.cohorts c ON c.course_id = cm.course_id
      JOIN public.enrollments e ON e.cohort_id = c.id
      JOIN public.trainees t ON t.id = e.trainee_id
      WHERE cm.file_path = storage.objects.name
        AND cm.is_published = true
        AND t.user_id = auth.uid()
        AND COALESCE(e.lifecycle_status, 'active') <> 'withdrawn'
        AND (e.status)::text NOT IN ('dropped', 'cancelled', 'canceled')
    )
  )
);

COMMIT;

