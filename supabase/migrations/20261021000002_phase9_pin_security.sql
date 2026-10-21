-- ==============================================================================
-- Taj Dentics - Phase 9: PIN Screen Lock & Inactivity Security
-- Migration: 20261021000002_phase9_pin_security.sql
-- ==============================================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- 1. Add pin_hash to public.users
ALTER TABLE public.users 
  ADD COLUMN IF NOT EXISTS pin_hash TEXT;

-- 2. RPC to set/update user PIN securely
CREATE OR REPLACE FUNCTION public.set_user_pin(p_pin TEXT)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'غير مصرح: يجب تسجيل الدخول لتعيين رمز PIN';
  END IF;

  IF length(p_pin) < 4 OR length(p_pin) > 6 OR p_pin !~ '^[0-9]+$' THEN
    RAISE EXCEPTION 'رمز الـ PIN يجب أن يتكون من 4 إلى 6 أرقام فقط';
  END IF;

  UPDATE public.users
  SET pin_hash = crypt(p_pin, gen_salt('bf', 8))
  WHERE id = auth.uid();

  RETURN jsonb_build_object('success', true, 'message', 'تم حفظ رمز PIN بنجاح');
END;
$$;

REVOKE EXECUTE ON FUNCTION public.set_user_pin FROM public, anon;
GRANT EXECUTE ON FUNCTION public.set_user_pin TO authenticated;

-- 3. RPC to verify user PIN
CREATE OR REPLACE FUNCTION public.verify_user_pin(p_pin TEXT)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_hash TEXT;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN false;
  END IF;

  SELECT pin_hash INTO v_hash
  FROM public.users
  WHERE id = auth.uid() AND is_active = true;

  IF v_hash IS NULL THEN
    RETURN false;
  END IF;

  RETURN (v_hash = crypt(p_pin, v_hash));
END;
$$;

REVOKE EXECUTE ON FUNCTION public.verify_user_pin FROM public, anon;
GRANT EXECUTE ON FUNCTION public.verify_user_pin TO authenticated;

-- 4. RPC to check if current user has a PIN configured
CREATE OR REPLACE FUNCTION public.has_user_pin()
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN false;
  END IF;

  RETURN EXISTS (
    SELECT 1 FROM public.users 
    WHERE id = auth.uid() AND pin_hash IS NOT NULL AND is_active = true
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.has_user_pin FROM public, anon;
GRANT EXECUTE ON FUNCTION public.has_user_pin TO authenticated;
