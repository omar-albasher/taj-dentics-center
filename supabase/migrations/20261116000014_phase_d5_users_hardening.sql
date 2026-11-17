-- ============================================================================
-- Phase D5 — Users hardening (U1 + U2)
--
-- U1a. get_user_role() becomes DB-backed (live version reads the JWT):
--        baseline:1923-1927  SELECT (auth.jwt()->'user_metadata'->>'role')::user_role
--      Consequences of the JWT version:
--        * deactivating users.is_active (baseline:4610) leaves an already issued
--          token fully privileged until exp (stateless JWT).
--        * changing users.role (baseline:4608) does not move RLS policies that
--          call this function (admin_all_users baseline:7615,
--          reception_select_trainees_only baseline:7953) until token refresh.
--      SECURITY DEFINER is mandatory here: an invoker-rights read of public.users
--      from inside a users policy re-enters RLS -> infinite recursion. The
--      function owner (postgres) bypasses RLS because users is not FORCE ROW
--      LEVEL SECURITY (baseline:8162 enables only).
--
-- U1b. custom_access_token_hook() (baseline:1159-1180) copies role but ignores
--      is_active, so a disabled account still receives a real role claim on
--      refresh. Inactive or missing users now receive 'none'.
--
-- U2. public.users has no invariant guard today: an active admin can demote or
--      deactivate themselves, and the last active admin can be removed, orphaning
--      administration. A BEFORE UPDATE OR DELETE trigger enforces:
--        * no self role change, self deactivation or self deletion;
--        * last active admin cannot be demoted, deactivated or deleted;
--      under pg_advisory_xact_lock so two concurrent admin edits cannot both
--      observe "another admin exists" and race to zero.
--
--      Trusted bypass: only sessions with an EMPTY request.jwt.claims
--      (psql/editor migrations, pg_cron) skip the guard. PostgREST requests are
--      always guarded - including service_role calls from Edge Functions - so
--      "last admin" cannot be removed by a backend bug or a leaked service key.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- U1a. DB-backed get_user_role()
-- CREATE OR REPLACE keeps the existing ACLs (anon/authenticated/service_role,
-- baseline:8470-8475).
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_user_role()
RETURNS public.user_role
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT role
  FROM public.users
  WHERE id = auth.uid()
    AND is_active = true
  LIMIT 1;
$$;

-- ----------------------------------------------------------------------------
-- U1b. Token hook ignores inactive accounts
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.custom_access_token_hook(event jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_role TEXT;
  v_claims JSONB;
  v_meta JSONB;
BEGIN
  -- الدور الموثوق من جدول المستخدمين، للحسابات النشطة فقط
  SELECT role::TEXT INTO v_role
  FROM public.users
  WHERE id = (event->>'user_id')::UUID
    AND is_active = true;

  -- بناء المسار بشكل محصن حتى لو كانت user_metadata غير مهيأة في claims
  v_claims := COALESCE(event->'claims', '{}'::jsonb);
  v_meta := COALESCE(v_claims->'user_metadata', '{}'::jsonb);
  v_meta := jsonb_set(v_meta, '{role}', to_jsonb(COALESCE(v_role, 'none')));
  v_claims := jsonb_set(v_claims, '{user_metadata}', v_meta);
  event := jsonb_set(event, '{claims}', v_claims);

  RETURN event;
END;
$$;

REVOKE ALL ON FUNCTION public.custom_access_token_hook(jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.custom_access_token_hook(jsonb) TO service_role, supabase_auth_admin;

-- ----------------------------------------------------------------------------
-- U2. Admin invariants guard
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.c1_guard_user_admin_changes()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_claims text := current_setting('request.jwt.claims', true);
  v_actor uuid := auth.uid();
  v_other_admins integer;
BEGIN
  -- Trusted silent paths only: migrations/psql and pg_cron carry no PostgREST
  -- JWT. service_role API calls DO carry claims and stay guarded.
  IF v_claims IS NULL OR v_claims = '' THEN
    IF TG_OP = 'DELETE' THEN
      RETURN OLD;
    END IF;
    RETURN NEW;
  END IF;

  -- Only role/is_active transitions and deletions are dangerous; plain profile
  -- edits (name, phone...) pass through untouched.
  IF TG_OP = 'UPDATE'
     AND NEW.role IS NOT DISTINCT FROM OLD.role
     AND NEW.is_active IS NOT DISTINCT FROM OLD.is_active THEN
    RETURN NEW;
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext('public.users.c1_admin_guard'));

  IF TG_OP = 'DELETE' THEN
    IF v_actor IS NOT NULL AND v_actor = OLD.id THEN
      RAISE EXCEPTION 'لا يمكنك حذف حسابك الخاص' USING ERRCODE = 'P0001';
    END IF;

    IF OLD.role = 'admin' AND OLD.is_active THEN
      SELECT count(*) INTO v_other_admins
      FROM public.users
      WHERE role = 'admin'
        AND is_active = true
        AND id <> OLD.id;

      IF v_other_admins = 0 THEN
        RAISE EXCEPTION 'لا يمكن حذف آخر مدير نشط في النظام' USING ERRCODE = 'P0001';
      END IF;
    END IF;

    RETURN OLD;
  END IF;

  -- UPDATE: identity guard first, then admin-count invariant
  IF v_actor IS NOT NULL AND v_actor = OLD.id THEN
    IF NEW.role IS DISTINCT FROM OLD.role THEN
      RAISE EXCEPTION 'لا يمكنك تغيير دورك بنفسك' USING ERRCODE = 'P0001';
    END IF;

    IF NEW.is_active = false THEN
      RAISE EXCEPTION 'لا يمكنك تعطيل حسابك بنفسك' USING ERRCODE = 'P0001';
    END IF;
  END IF;

  IF OLD.role = 'admin' AND OLD.is_active
     AND (NEW.role <> 'admin' OR NEW.is_active = false) THEN
    SELECT count(*) INTO v_other_admins
    FROM public.users
    WHERE role = 'admin'
      AND is_active = true
      AND id <> OLD.id;

    IF v_other_admins = 0 THEN
      RAISE EXCEPTION 'لا يمكن إزالة آخر مدير نشط في النظام' USING ERRCODE = 'P0001';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_guard_users_admin_changes ON public.users;
CREATE TRIGGER trg_guard_users_admin_changes
  BEFORE UPDATE OR DELETE ON public.users
  FOR EACH ROW
  EXECUTE FUNCTION public.c1_guard_user_admin_changes();
