-- ═══════════════════════════════════════════════════════════════════════
-- Phase #40.2 — Deployment slice 1/2: schema + functions (NO enforcement)
--
-- Source of truth: supabase/migrations/20261127000001_phase_40_2_server_password_fingerprint.sql
-- This file contains sections 1, 2, 4, 5, 6, 7 of that migration verbatim,
-- reordered so the fingerprint functions are live before any CHECK exists.
--
-- Runbook (production: only after the separate explicit approval):
--   1. THIS FILE                          column + backfill + new functions
--   2. deploy manage-user + create-trainee (Verify JWT ON)
--   3. staged_40_2_step2_enforce_checks.sql
--
-- Why split: legacy Edge Functions write must_change_password directly with no
-- fingerprint. If the CHECK existed first, every legacy reset/create would
-- fail with 23514 during the deployment window. With this order the legacy
-- functions keep working; the new functions take over; the CHECK is enforced
-- last, once every writer produces a fingerprint.
--
-- Transitional property (intentional, fail-closed): between step 1 and step 2,
-- a flag raised by a LEGACY function has no fingerprint, so
-- complete_password_change() rejects the completion ("بصمة ... مفقودة")
-- until step 2's re-backfill fills it. There is no bypass; worst case is a
-- brief retry delay for that user.
--
-- Execute:   psql "<conn>" -v ON_ERROR_STOP=1 -f <this file>
-- Artifact:  keep the raw terminal capture as the deployment evidence.
-- Rollback:  re-run phase C1's function definitions (migration
--            20261109000002) to restore the old complete_password_change and
--            get_my_password_state; the added column/backfill are harmless.
-- ═══════════════════════════════════════════════════════════════════════
BEGIN;

-- 0. Preflight: C1 must be applied (its CHECK backs the timestamp invariant).
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'chk_users_must_change_password_at'
      AND conrelid = 'public.users'::regclass
  ) THEN
    RAISE EXCEPTION
      '#40.2 step1 preflight: chk_users_must_change_password_at مفقود — طُبّق C1 على هذه القاعدة أولاً';
  END IF;
END $$;

-- 1. إضافة عمود بصمة كلمة المرور
ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS password_fingerprint text;

-- 2. Backfill (idempotent): fills ONLY flagged rows that still lack a
--    fingerprint, so already-running forced-change users keep working with
--    the new complete_password_change() during the deployment window.
UPDATE public.users u
SET password_fingerprint = encode(sha256(au.encrypted_password::bytea), 'hex')
FROM auth.users au
WHERE u.id = au.id
  AND u.must_change_password = true
  AND u.password_fingerprint IS NULL
  AND au.encrypted_password IS NOT NULL;

-- Visibility (non-blocking): what step 2's fail-closed gate will see.
DO $$
DECLARE
  v_flagged    integer;
  v_with_fp    integer;
  v_without_fp integer;
  v_unresolved integer;
BEGIN
  SELECT count(*) FILTER (WHERE u.must_change_password),
         count(*) FILTER (WHERE u.must_change_password AND u.password_fingerprint IS NOT NULL),
         count(*) FILTER (WHERE u.must_change_password AND u.password_fingerprint IS NULL),
         count(*) FILTER (WHERE u.must_change_password
                            AND u.password_fingerprint IS NULL
                            AND (au.id IS NULL OR au.encrypted_password IS NULL))
  INTO v_flagged, v_with_fp, v_without_fp, v_unresolved
  FROM public.users u
  LEFT JOIN auth.users au ON au.id = u.id;

  RAISE NOTICE '#40.2 step1: flagged=%, with_fp=%, without_fp=%, unbackfillable=%',
    v_flagged, v_with_fp, v_without_fp, v_unresolved;

  IF v_unresolved > 0 THEN
    RAISE WARNING
      '#40.2 step1: % صف/صفوف معلّمة بلا بصمة قابلة للاشتقاق (لا صف auth.users أو كلمة مرور NULL) — ستُجهِض step2؛ عالجها قبل المتابعة',
      v_unresolved;
  END IF;
END $$;

-- 3. دالة رفع علامة إجبار التغيير وحساب البصمة (مقصورة على service_role)
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

-- 4. تحديث complete_password_change() للتحقق عبر البصمة (سد علة GoTrue نهائياً)
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

-- 5. تحديث get_my_password_state() لدعم Fail-closed عند غياب الصف
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

-- 6. الصلاحيات
REVOKE ALL ON FUNCTION public.get_my_password_state() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.complete_password_change() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_password_state() TO authenticated;
GRANT EXECUTE ON FUNCTION public.complete_password_change() TO authenticated;

-- Post-state (non-blocking): step 1 must NOT enforce the fingerprint CHECK.
DO $$
DECLARE v_enforced integer;
BEGIN
  SELECT count(*) INTO v_enforced
  FROM pg_constraint
  WHERE conname = 'chk_users_must_change_password_fingerprint'
    AND conrelid = 'public.users'::regclass;
  IF v_enforced > 0 THEN
    RAISE NOTICE '#40.2 step1: fingerprint CHECK already present — step 2 already applied?';
  ELSE
    RAISE NOTICE '#40.2 step1: fingerprint CHECK correctly absent (step 2 will enforce it)';
  END IF;
END $$;

COMMIT;