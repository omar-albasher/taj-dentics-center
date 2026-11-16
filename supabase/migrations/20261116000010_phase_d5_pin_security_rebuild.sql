-- ============================================================================
-- Migration: 20261116000010_phase_d5_pin_security_rebuild.sql
-- Description: Phase D5 / #46 - Rebuild the PIN lock backend.
--
-- Context (verified 2026-11-16):
--   * phase9_pin_security (20261021000002) defined users.pin_hash + 3 RPCs but
--     was never applied live (to_regprocedure returned NULL for all three).
--   * D5.1's unconditional ALTER FUNCTION statements (20261116000001:203-204)
--     therefore failed while the rest of that migration committed statement by
--     statement (baseline proves the remaining sections are live).
--   * users.pin_hash is NOT used: authenticated holds table-level SELECT on
--     public.users (baseline:8942) and UsersRepository does `select()` without
--     a column list (users_repository.dart:8), so the bcrypt hash would leak to
--     every admin/reception client. Storage is isolated in public.user_pins.
--
-- Actions:
--   1. Create public.user_pins (RLS on, zero policies, zero client grants).
--   2. Create set_user_pin / verify_user_pin / has_user_pin (SECURITY DEFINER).
--   3. EXECUTE only for authenticated + service_role; nothing for PUBLIC/anon.
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;

CREATE TABLE IF NOT EXISTS public.user_pins (
  user_id    uuid PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
  pin_hash   text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.user_pins ENABLE ROW LEVEL SECURITY;

-- No policies by design: only the SECURITY DEFINER RPCs touch this table.
-- FORCE ROW LEVEL SECURITY is intentionally NOT set - it would also filter the
-- table owner (postgres) and break the SECURITY DEFINER functions.
ALTER TABLE public.user_pins NO FORCE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.user_pins FROM PUBLIC, anon, authenticated;
GRANT ALL ON TABLE public.user_pins TO service_role;

-- ----------------------------------------------------------------------------
-- 1. set_user_pin: upsert a bcrypt hash for the calling user
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.set_user_pin(p_pin text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'غير مصرح: يجب تسجيل الدخول لتعيين رمز PIN';
  END IF;

  IF p_pin IS NULL
     OR length(p_pin) NOT BETWEEN 4 AND 6
     OR p_pin !~ '^[0-9]+$' THEN
    RAISE EXCEPTION 'رمز الـ PIN يجب أن يتكون من 4 إلى 6 أرقام فقط';
  END IF;

  INSERT INTO public.user_pins (user_id, pin_hash)
  VALUES (auth.uid(), crypt(p_pin, gen_salt('bf', 8)))
  ON CONFLICT (user_id) DO UPDATE
    SET pin_hash  = EXCLUDED.pin_hash,
        updated_at = now();

  RETURN jsonb_build_object('success', true, 'message', 'تم حفظ رمز PIN بنجاح');
END;
$$;

REVOKE ALL ON FUNCTION public.set_user_pin(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_user_pin(text) TO authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 2. verify_user_pin: compare the submitted PIN against the caller's hash
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.verify_user_pin(p_pin text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  v_hash text;
BEGIN
  IF auth.uid() IS NULL OR p_pin IS NULL THEN
    RETURN false;
  END IF;

  SELECT up.pin_hash INTO v_hash
  FROM public.user_pins up
  JOIN public.users u ON u.id = up.user_id
  WHERE up.user_id = auth.uid()
    AND u.is_active = true;

  IF v_hash IS NULL THEN
    RETURN false;
  END IF;

  RETURN (v_hash = crypt(p_pin, v_hash));
END;
$$;

REVOKE ALL ON FUNCTION public.verify_user_pin(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.verify_user_pin(text) TO authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 3. has_user_pin: does the caller have a PIN (active account only)?
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.has_user_pin()
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN false;
  END IF;

  RETURN EXISTS (
    SELECT 1
    FROM public.user_pins up
    JOIN public.users u ON u.id = up.user_id
    WHERE up.user_id = auth.uid()
      AND u.is_active = true
  );
END;
$$;

REVOKE ALL ON FUNCTION public.has_user_pin() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.has_user_pin() TO authenticated, service_role;
