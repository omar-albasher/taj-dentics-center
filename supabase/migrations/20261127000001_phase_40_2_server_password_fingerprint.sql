-- ═══════════════════════════════════════════════════════════════════════
-- Phase 40.2 — Server-Side Password Fingerprint Hardening
--
-- الغرض: تحويل ضابط إجبار تغيير كلمة المرور إلى حد أمني صلب على مستوى DB:
-- 1. إضافة عمود password_fingerprint وقيد CHECK يمنع رفع العلامة بلا بصمة.
-- 2. دالة SECURITY DEFINER (set_user_must_change_password) مقصورة على service_role
--    تقوم بحساب بصمة sha256 لكلمة المرور المشفرة الحالية وتخزينها ورفع العلامة.
-- 3. تحديث complete_password_change() لتقارن بصمة كلمة المرور الحالية بالبصمة المسجلة؛
--    ترفض (fail-closed) إذا كانت البصمة مفقودة أو مطابقة (لم تتغير فعلياً)،
--    وتسقط العلامة وتمحو البصمة فقط عند حدوث تغيير حقيقي في كلمة المرور.
-- 4. تحديث get_my_password_state() لتعيد true (fail-closed) عند غياب صف المستخدم.
-- ═══════════════════════════════════════════════════════════════════════
BEGIN;

-- 1. إضافة عمود بصمة كلمة المرور
ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS password_fingerprint text;

-- 2. Backfill لحسابات المتدربين أو المستخدمين المعلّمين حالياً من auth.users
UPDATE public.users u
SET password_fingerprint = encode(sha256(au.encrypted_password::bytea), 'hex')
FROM auth.users au
WHERE u.id = au.id
  AND u.must_change_password = true
  AND u.password_fingerprint IS NULL
  AND au.encrypted_password IS NOT NULL;

-- Fail-closed: أي صف معلّم بلا بصمة قابلة للاشتقاق (غياب auth.users أو كلمة مرور)
-- يُجهِض المهاجرة بالكامل بدل التدهور الصامت إلى قيمة بديلة قابلة للتجاوز.
DO $$
DECLARE
  v_unresolved integer;
BEGIN
  SELECT count(*) INTO v_unresolved
  FROM public.users u
  WHERE u.must_change_password = true
    AND u.password_fingerprint IS NULL;

  IF v_unresolved > 0 THEN
    RAISE EXCEPTION
      'Phase 40.2 fail-closed: % صف/صفوف معلّمة بـmust_change_password بلا بصمة قابلة للاشتقاق من auth.users؛ عالجها يدوياً قبل الترحيل',
      v_unresolved
      USING ERRCODE = 'P0001';
  END IF;
END $$;

-- 3. قيد CHECK: يمنع وجود علامة إجبار تغيير كلمة مرور دون بصمة مسجلة
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'chk_users_must_change_password_fingerprint'
      AND conrelid = 'public.users'::regclass
  ) THEN
    ALTER TABLE public.users
      ADD CONSTRAINT chk_users_must_change_password_fingerprint
      CHECK (must_change_password = false OR password_fingerprint IS NOT NULL);
  END IF;
END $$;

-- 4. دالة رفع علامة إجبار التغيير وحساب البصمة (مقصورة على service_role)
CREATE OR REPLACE FUNCTION public.set_user_must_change_password(p_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE
  v_enc_pass text;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'معرّف المستخدم مطلوب';
  END IF;

  SELECT encrypted_password INTO v_enc_pass
  FROM auth.users
  WHERE id = p_user_id;

  IF NOT FOUND OR v_enc_pass IS NULL THEN
    RAISE EXCEPTION 'حساب المستخدم غير موجود في auth.users أو لا يملك كلمة مرور';
  END IF;

  UPDATE public.users
  SET must_change_password = true,
      password_fingerprint = encode(sha256(v_enc_pass::bytea), 'hex'),
      must_change_password_at = now()
  WHERE id = p_user_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'المستخدم غير موجود في public.users';
  END IF;
END;
$$;

-- قصر صلاحية الاستدعاء على service_role فقط
REVOKE ALL ON FUNCTION public.set_user_must_change_password(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.set_user_must_change_password(uuid) TO service_role;

-- 5. تحديث complete_password_change() للتحقق عبر البصمة (سد علة GoTrue نهائياً)
CREATE OR REPLACE FUNCTION public.complete_password_change()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE
  v_uid         uuid := auth.uid();
  v_flag        boolean;
  v_stored_fp   text;
  v_current_enc text;
  v_current_fp  text;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'غير مصرح';
  END IF;

  SELECT u.must_change_password, u.password_fingerprint
  INTO v_flag, v_stored_fp
  FROM public.users u
  WHERE u.id = v_uid;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'المستخدم غير موجود';
  END IF;

  -- إذا لم تكن هناك علامة إجبار، العملية مكتملة بالفعل
  IF NOT v_flag THEN
    RETURN;
  END IF;

  -- Fail-closed: رفض فوري إذا رُفعت العلامة بدون بصمة
  IF v_stored_fp IS NULL THEN
    RAISE EXCEPTION 'بصمة كلمة المرور مفقودة؛ يرجى مراجعة الإدارة';
  END IF;

  -- جلب كلمة المرور المشفرة الحالية من auth.users
  SELECT au.encrypted_password
  INTO v_current_enc
  FROM auth.users au
  WHERE au.id = v_uid;

  IF NOT FOUND OR v_current_enc IS NULL THEN
    RAISE EXCEPTION 'تعذر التحقق من حالة الحساب';
  END IF;

  v_current_fp := encode(sha256(v_current_enc::bytea), 'hex');

  -- إذا كانت البصمة الحالية مطابقة للبصمة المسجلة وقت رفع العلامة، فكلمة المرور لم تتغير فعلياً
  IF v_current_fp = v_stored_fp THEN
    RAISE EXCEPTION 'لم يتم تغيير كلمة المرور بعد';
  END IF;

  -- التغيير تم فعلياً: إسقاط العلامة وتفريغ البصمة والطابع
  UPDATE public.users
  SET must_change_password = false,
      password_fingerprint = NULL,
      must_change_password_at = NULL
  WHERE id = v_uid;
END;
$$;

-- 6. تحديث get_my_password_state() لدعم Fail-closed عند غياب الصف
CREATE OR REPLACE FUNCTION public.get_my_password_state()
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_flag boolean;
BEGIN
  IF v_uid IS NULL THEN
    RETURN true; -- Fail-closed
  END IF;

  SELECT u.must_change_password
  INTO v_flag
  FROM public.users u
  WHERE u.id = v_uid;

  IF NOT FOUND THEN
    RETURN true; -- Fail-closed: صف المستخدم مفقود في public.users
  END IF;

  RETURN coalesce(v_flag, false);
END;
$$;

-- 7. الصلاحيات
REVOKE ALL ON FUNCTION public.get_my_password_state() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.complete_password_change() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_password_state() TO authenticated;
GRANT EXECUTE ON FUNCTION public.complete_password_change() TO authenticated;

COMMIT;
