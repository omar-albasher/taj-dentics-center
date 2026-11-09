-- ═══════════════════════════════════════════════════════════════════════
-- Phase C1 — إجبار المتدرب على تغيير كلمة المرور المؤقتة عند أول دخول
--
-- بعد استيراد 205 حساباً بكلمة مرور مؤقتة قابلة للتخمين (Taj@[code]):
--   - يُعلَّم الحساب بـmust_change_password = true مع توقيت التعيين.
--   - trainee_app يعرض شاشة التغيير ولا يسمح بالوصول للرئيسية قبلها.
--   - complete_password_change() ترفض إسقاط العلامة إن لم يتغيّر
--     auth.users.updated_at بعد لحظة التعيين (أي لم يُستدعَ updateUser(password)).
--
-- ملاحظة أمنية: هذا ضابط تشغيلي (يمنع بقاء الطالب على كلمة المرور المؤقتة)،
-- وليس حداً أمنياً صارماً؛ الحساب نفسه محمي بكلمة مروره الحالية.
-- ═══════════════════════════════════════════════════════════════════════
BEGIN;

ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS must_change_password boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS must_change_password_at timestamptz;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'chk_users_must_change_password_at'
      AND conrelid = 'public.users'::regclass
  ) THEN
    ALTER TABLE public.users
      ADD CONSTRAINT chk_users_must_change_password_at
      CHECK (must_change_password = false OR must_change_password_at IS NOT NULL);
  END IF;
END $$;

-- --------------------------------------------------------------------------
-- قراءة حالة الحساب الحالي (للتطبيق)
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_my_password_state()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT COALESCE((
    SELECT u.must_change_password
    FROM public.users u
    WHERE u.id = auth.uid()
  ), false)
$$;

-- --------------------------------------------------------------------------
-- إسقاط العلامة بعد تغيير كلمة المرور فعلياً عبر GoTrue
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.complete_password_change()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid        uuid := auth.uid();
  v_flag       boolean;
  v_flagged_at timestamptz;
  v_auth_upd   timestamptz;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'غير مصرح';
  END IF;

  SELECT u.must_change_password, u.must_change_password_at
  INTO v_flag, v_flagged_at
  FROM public.users u
  WHERE u.id = v_uid;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'المستخدم غير موجود';
  END IF;

  IF NOT v_flag THEN
    RETURN;
  END IF;

  SELECT au.updated_at INTO v_auth_upd
  FROM auth.users au
  WHERE au.id = v_uid;

  IF v_flagged_at IS NULL
     OR v_auth_upd IS NULL
     OR v_auth_upd <= v_flagged_at THEN
    RAISE EXCEPTION 'لم يتم تغيير كلمة المرور بعد';
  END IF;

  UPDATE public.users
  SET must_change_password = false,
      must_change_password_at = NULL
  WHERE id = v_uid;
END;
$$;

-- --------------------------------------------------------------------------
-- Backfill: كل حسابات المتدربين المستوردة
-- --------------------------------------------------------------------------
UPDATE public.users
SET must_change_password = true,
    must_change_password_at = now()
WHERE role = 'trainee'
  AND email ILIKE '%@tajdentics.com'
  AND must_change_password = false;

-- --------------------------------------------------------------------------
-- الصلاحيات
-- --------------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.get_my_password_state() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.complete_password_change() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_password_state() TO authenticated;
GRANT EXECUTE ON FUNCTION public.complete_password_change() TO authenticated;

COMMIT;
