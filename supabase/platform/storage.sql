-- ============================================================================
-- Platform Artifact: Storage Buckets & Policies (#47)
-- ============================================================================

-- 1. Buckets
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'course-materials',
  'course-materials',
  false,
  NULL,
  NULL
)
ON CONFLICT (id) DO NOTHING;

-- 2. Storage Policies on storage.objects

-- Admin full access
DROP POLICY IF EXISTS "admin_course_materials_storage" ON storage.objects;
CREATE POLICY "admin_course_materials_storage" ON storage.objects
  FOR ALL
  TO authenticated
  USING (
    bucket_id = 'course-materials'
    AND (
      SELECT u.role
      FROM public.users u
      WHERE u.id = auth.uid()
        AND u.is_active = true
    ) = 'admin'::public.user_role
  )
  WITH CHECK (
    bucket_id = 'course-materials'
    AND (
      SELECT u.role
      FROM public.users u
      WHERE u.id = auth.uid()
        AND u.is_active = true
    ) = 'admin'::public.user_role
  );

-- Staff and enrolled trainees download access
DROP POLICY IF EXISTS "course_materials_storage_download" ON storage.objects;
CREATE POLICY "course_materials_storage_download" ON storage.objects
  FOR SELECT
  TO authenticated
  USING (
    bucket_id = 'course-materials'
    AND (
      public.c1_staff_role() = ANY (ARRAY['admin'::text, 'reception'::text])
      OR EXISTS (
        SELECT 1
        FROM public.course_materials cm
        JOIN public.cohorts c ON c.course_id = cm.course_id
        JOIN public.enrollments e ON e.cohort_id = c.id
        JOIN public.trainees t ON t.id = e.trainee_id
        WHERE cm.file_path = storage.objects.name
          AND cm.is_published = true
          AND t.user_id = auth.uid()
          AND COALESCE(e.lifecycle_status, 'active'::text) <> 'withdrawn'::text
      )
    )
  );
