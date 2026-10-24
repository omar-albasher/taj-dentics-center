-- ==============================================================================
-- Taj Dentics Training Center - Phase A6: Course Materials & Attachments
-- Migration: 20261024000001_phase_a6_course_materials.sql
-- ==============================================================================

-- 1. جدول مواد الكورس
CREATE TABLE IF NOT EXISTS public.course_materials (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  course_id UUID NOT NULL REFERENCES public.courses(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  description TEXT,
  material_type TEXT NOT NULL CHECK (material_type IN ('file', 'link')),
  file_path TEXT,          -- مسار الملف داخل باكت course-materials (null إذا كان رابطاً)
  file_size_bytes BIGINT,  -- حجم الملف بالبايت
  mime_type TEXT,          -- نوع الملف (application/pdf, image/png...)
  external_url TEXT,       -- رابط يوتيوب/درايف الخارجي (null إذا كان ملفاً)
  is_published BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by UUID REFERENCES public.users(id) ON DELETE SET NULL
);

-- 2. فهارس الأداء
CREATE INDEX IF NOT EXISTS idx_course_materials_course_id ON public.course_materials(course_id);
CREATE INDEX IF NOT EXISTS idx_course_materials_published ON public.course_materials(course_id, is_published);

-- 3. تفعيل الـ RLS
ALTER TABLE public.course_materials ENABLE ROW LEVEL SECURITY;

-- 4. سياسة القراءة (SELECT):
-- الأدمن والاستقبال يقرؤون كل المواد
-- المتدرب يقرأ فقط المواد المنشورة للكورسات المسجل بها
DROP POLICY IF EXISTS "course_materials_select_policy" ON public.course_materials;
CREATE POLICY "course_materials_select_policy"
ON public.course_materials
FOR SELECT
TO authenticated
USING (
  (SELECT role FROM public.users WHERE id = auth.uid() AND is_active = true) IN ('admin', 'reception')
  OR
  (
    is_published = true
    AND EXISTS (
      SELECT 1 
      FROM public.enrollments e
      JOIN public.cohorts c ON c.id = e.cohort_id
      JOIN public.trainees t ON t.id = e.trainee_id
      WHERE c.course_id = course_materials.course_id
        AND t.user_id = auth.uid()
    )
  )
);

-- 5. سياسة الإدارة الكاملة (INSERT, UPDATE, DELETE): للأدمن فقط
DROP POLICY IF EXISTS "course_materials_admin_manage_policy" ON public.course_materials;
CREATE POLICY "course_materials_admin_manage_policy"
ON public.course_materials
FOR ALL
TO authenticated
USING (
  (SELECT role FROM public.users WHERE id = auth.uid() AND is_active = true) = 'admin'
)
WITH CHECK (
  (SELECT role FROM public.users WHERE id = auth.uid() AND is_active = true) = 'admin'
);

-- 6. إنشاء باكت التخزين الخاص (Private Bucket) بحد أقصى 20 ميغابايت للملف
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'course-materials',
  'course-materials',
  false,
  20971520, -- 20 MB
  ARRAY[
    'application/pdf',
    'application/vnd.ms-powerpoint',
    'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    'image/png',
    'image/jpeg',
    'image/webp'
  ]
)
ON CONFLICT (id) DO UPDATE SET
  public = false,
  file_size_limit = 20971520;

-- 7. سياسات أمان الـ Storage للباكت:
-- الأدمن يرفع ويحذف
DROP POLICY IF EXISTS "admin_course_materials_storage" ON storage.objects;
CREATE POLICY "admin_course_materials_storage"
ON storage.objects
FOR ALL
TO authenticated
USING (
  bucket_id = 'course-materials'
  AND (SELECT role FROM public.users WHERE id = auth.uid() AND is_active = true) = 'admin'
)
WITH CHECK (
  bucket_id = 'course-materials'
  AND (SELECT role FROM public.users WHERE id = auth.uid() AND is_active = true) = 'admin'
);

-- الأدمن والاستقبال والمتدربون المسجلون يحملون الملفات عبر Signed URLs
DROP POLICY IF EXISTS "authenticated_course_materials_download" ON storage.objects;
CREATE POLICY "authenticated_course_materials_download"
ON storage.objects
FOR SELECT
TO authenticated
USING (
  bucket_id = 'course-materials'
  AND (
    (SELECT role FROM public.users WHERE id = auth.uid() AND is_active = true) IN ('admin', 'reception')
    OR
    EXISTS (
      SELECT 1
      FROM public.course_materials cm
      JOIN public.enrollments e ON e.cohort_id IN (SELECT id FROM public.cohorts WHERE course_id = cm.course_id)
      JOIN public.trainees t ON t.id = e.trainee_id
      WHERE cm.file_path = storage.objects.name
        AND cm.is_published = true
        AND t.user_id = auth.uid()
    )
  )
);
