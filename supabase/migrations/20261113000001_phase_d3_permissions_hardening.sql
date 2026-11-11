-- ==============================================================================
-- Phase D3: Permissions Hardening & Confidentiality (Hardened v2)
-- File: supabase/migrations/20261113000001_phase_d3_permissions_hardening.sql
-- ==============================================================================

BEGIN;

-- 1) Revoke leaked public/anon grants on course_materials, preserve authenticated writes (B1)
REVOKE ALL ON public.course_materials FROM anon, public;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.course_materials TO authenticated;
GRANT ALL ON public.course_materials TO service_role;

-- 2) Performance index for storage.objects join (B3)
CREATE INDEX IF NOT EXISTS idx_course_materials_file_path
  ON public.course_materials(file_path)
  WHERE file_path IS NOT NULL;

-- 3) Consolidate course_materials table SELECT policies (B2 + B5)
DROP POLICY IF EXISTS "course_materials_read_policy" ON public.course_materials;
DROP POLICY IF EXISTS "course_materials_select_policy" ON public.course_materials;
DROP POLICY IF EXISTS "Trainees can view published materials for enrolled courses" ON public.course_materials;

CREATE POLICY "course_materials_read_policy"
ON public.course_materials
FOR SELECT
TO authenticated
USING (
  -- Staff access (admin and reception matching A6 specification)
  public.c1_staff_role() IN ('admin', 'reception')
  OR
  -- Active enrolled trainees only (immune to NULL status)
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
    )
  )
);

-- 4) Consolidate storage.objects download policies for course-materials bucket (B2 + B5)
DROP POLICY IF EXISTS "course_materials_storage_download" ON storage.objects;
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
    public.c1_staff_role() IN ('admin', 'reception')
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
    )
  )
);

COMMIT;
