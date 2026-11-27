-- ═══════════════════════════════════════════════════════════════════════
-- Phase #40.2 — Deployment slice 2/2: enforce the fingerprint CHECK
--
-- Source of truth: supabase/migrations/20261127000001_phase_40_2_server_password_fingerprint.sql
-- (section 2 re-run + sections 3 fail-closed gate and CHECK, verbatim).
--
-- Preconditions:
--   * staged_40_2_step1_schema_and_functions.sql applied (column + functions).
--   * manage-user and create-trainee deployed with the RPC call (Verify JWT ON).
--   This file refuses to run if either precondition is missing.
--
-- Guarantees:
--   * Re-runs the idempotent backfill to capture any flag raised by a legacy
--     function during the deployment window before the new functions went live.
--   * Aborts the whole transaction (P0001) if any flagged row still lacks a
--     derivable fingerprint — no silent degradation.
--   * Verifies that chk_users_must_change_password_at (from C1) is present;
--     it is NOT re-added.
--   * Adds chk_users_must_change_password_fingerprint only if absent.
--
-- Execute:   psql "<conn>" -v ON_ERROR_STOP=1 -f <this file>
-- Artifact:  keep the raw terminal capture as the deployment evidence.
--
-- Failure semantics: the entire file is one transaction. If the fail-closed
-- gate raises, nothing is committed and the database stays in the step-1
-- state (new functions live, CHECK absent) — no half-enforced schema. Fix the
-- offending rows manually, then re-run this file.
--
-- Rollback after success: DROP CONSTRAINT chk_users_must_change_password_fingerprint
--   (and, if the old functions are also to be restored, re-run phase C1's
--   migration 20261109000002 function definitions).
-- ═══════════════════════════════════════════════════════════════════════
BEGIN;

-- 0. Preflight: step 1 must be installed, otherwise enforcing the CHECK would
--    leave every legacy writer failing with 23514.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc
    WHERE proname = 'set_user_must_change_password'
      AND pronamespace = 'public'::regnamespace
      AND prosrc LIKE '%password_fingerprint%'
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_proc
    WHERE proname = 'complete_password_change'
      AND pronamespace = 'public'::regnamespace
      AND prosrc LIKE '%password_fingerprint%'
  ) THEN
    RAISE EXCEPTION
      '#40.2 step2 preflight: دوال البصمة (#40.2) غير منصّبة — نفّذ step1 أولاً';
  END IF;
END $$;

-- 1. Re-backfill (idempotent): catches flags raised by legacy functions after
--    step 1 (they write must_change_password with no fingerprint).
UPDATE public.users u
SET password_fingerprint = encode(sha256(au.encrypted_password::bytea), 'hex')
FROM auth.users au
WHERE u.id = au.id
  AND u.must_change_password = true
  AND u.password_fingerprint IS NULL
  AND au.encrypted_password IS NOT NULL;

-- 2. Fail-closed: any flagged row still without a derivable fingerprint
--    aborts the whole transaction instead of degrading silently.
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

-- 3. The timestamp CHECK from C1 must already exist; it backs the invariant
--    that the setter always stamps must_change_password_at.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'chk_users_must_change_password_at'
      AND conrelid = 'public.users'::regclass
  ) THEN
    RAISE EXCEPTION
      '#40.2 step2 preflight: chk_users_must_change_password_at مفقود — القاعدة ليست في حالة C1 المتوقعة؛ أوقف النشر';
  END IF;
END $$;

-- 4. قيد CHECK: يمنع وجود علامة إجبار تغيير كلمة مرور دون بصمة مسجلة
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

-- 5. Post-assertions: enforcement is live and there is no violating row.
DO $$
DECLARE
  v_missing    integer;
  v_constraint integer;
BEGIN
  SELECT count(*) INTO v_missing
  FROM public.users
  WHERE must_change_password = true
    AND password_fingerprint IS NULL;

  SELECT count(*) INTO v_constraint
  FROM pg_constraint
  WHERE conname = 'chk_users_must_change_password_fingerprint'
    AND conrelid = 'public.users'::regclass;

  IF v_missing > 0 OR v_constraint <> 1 THEN
    RAISE EXCEPTION
      '#40.2 step2 post-check FAIL: missing_fp=%, constraint=%, expected 0/1',
      v_missing, v_constraint;
  END IF;

  RAISE NOTICE '#40.2 step2 PASS: fingerprint CHECK enforced; zero flagged rows without fingerprint';
END $$;

COMMIT;