-- ============================================================================
-- Migration: 20261116000006_phase_d3_residuals_cleanup.sql
-- Description: Phase D3 Residuals - Hardening helper function execution privileges
--
-- Actions:
--   1. Revoke EXECUTE on core helper functions from PUBLIC and anon.
--   2. Grant EXECUTE explicitly to authenticated and service_role only.
--   3. Ensure course_materials has zero privileges for anon.
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- 1. Revoke EXECUTE on c1_is_staff()
-- ----------------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.c1_is_staff() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.c1_is_staff() TO authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 2. Revoke EXECUTE on c1_staff_role()
-- ----------------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.c1_staff_role() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.c1_staff_role() TO authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 3. Revoke EXECUTE on c1_can_read_financials(uuid)
-- ----------------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.c1_can_read_financials(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.c1_can_read_financials(uuid) TO authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 4. Defensive hygiene: Ensure course_materials table is closed to anon & PUBLIC
--    Preserving full CRUD for authenticated and ALL for service_role
-- ----------------------------------------------------------------------------
REVOKE ALL ON public.course_materials FROM PUBLIC, anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.course_materials TO authenticated;
GRANT ALL ON public.course_materials TO service_role;

COMMIT;

