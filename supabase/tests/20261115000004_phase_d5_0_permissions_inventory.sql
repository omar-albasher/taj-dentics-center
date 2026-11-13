-- ==============================================================================
-- Discovery Script: 20261115000004_phase_d5_0_permissions_inventory.sql
-- Phase: D5.0 Permissions & Roles Inventory (Read-Only)
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- A. Roles & Constraints on public.users
-- ------------------------------------------------------------------------------
-- A.1 Existing roles and user active states
SELECT role, is_active, count(*) AS n
FROM public.users 
GROUP BY role, is_active 
ORDER BY role, is_active DESC;

-- A.2 Role column datatype
SELECT column_name, data_type, udt_name
FROM information_schema.columns
WHERE table_schema = 'public' 
  AND table_name = 'users' 
  AND column_name = 'role';

-- A.3 Constraints on public.users (CHECK / ENUM constraints)
SELECT conname, pg_get_constraintdef(oid) AS def
FROM pg_constraint
WHERE conrelid = 'public.users'::regclass 
  AND contype = 'c';

-- ------------------------------------------------------------------------------
-- B. Live RLS Policies & Row Security State
-- ------------------------------------------------------------------------------
-- B.1 All live policies across public and storage schemas
SELECT schemaname, tablename, policyname, cmd, roles, qual, with_check
FROM pg_policies
WHERE schemaname IN ('public', 'storage')
ORDER BY schemaname, tablename, policyname;

-- B.2 RLS enablement status on public tables
SELECT c.relname, c.relrowsecurity, c.relforcerowsecurity
FROM pg_class c 
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' 
  AND c.relkind IN ('r', 'p')
ORDER BY c.relname;

-- B.3 Tables in public schema that have NO policies
SELECT c.relname AS table_without_policies
FROM pg_class c 
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' 
  AND c.relkind = 'r'
  AND NOT EXISTS (
      SELECT 1 FROM pg_policies p
      WHERE p.schemaname = 'public' AND p.tablename = c.relname
  )
ORDER BY 1;

-- ------------------------------------------------------------------------------
-- C. Table and Column Privileges
-- ------------------------------------------------------------------------------
-- C.1 Table grants for anon, authenticated, service_role
SELECT table_name, grantee,
       string_agg(privilege_type, ', ' ORDER BY privilege_type) AS privs
FROM information_schema.role_table_grants
WHERE table_schema = 'public' 
  AND grantee IN ('anon', 'authenticated', 'service_role')
GROUP BY table_name, grantee 
ORDER BY table_name, grantee;

-- C.2 Column privileges for anon and authenticated
SELECT table_name, grantee, count(*) AS cols,
       string_agg(DISTINCT privilege_type, ', ') AS privs
FROM information_schema.column_privileges
WHERE table_schema = 'public' 
  AND grantee IN ('anon', 'authenticated')
GROUP BY table_name, grantee 
ORDER BY table_name, grantee;

-- ------------------------------------------------------------------------------
-- D. SECURITY DEFINER Functions Missing search_path
-- ------------------------------------------------------------------------------
SELECT p.proname
FROM pg_proc p 
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' 
  AND p.prosecdef
  AND NOT EXISTS (
      SELECT 1 FROM unnest(COALESCE(p.proconfig, ARRAY[]::text[])) cfg
      WHERE cfg LIKE 'search_path=%'
  )
ORDER BY 1;

-- ------------------------------------------------------------------------------
-- E. Views (security_invoker) & Triggers on public.users
-- ------------------------------------------------------------------------------
-- E.1 All views and their reloptions (security_invoker setting)
SELECT c.relname, pg_get_userbyid(c.relowner) AS owner, c.reloptions
FROM pg_class c 
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' 
  AND c.relkind IN ('v', 'm') 
ORDER BY 1;

-- E.2 Triggers on public.users
SELECT c.relname, t.tgname, t.tgenabled, pg_get_triggerdef(t.oid)
FROM pg_trigger t
JOIN pg_class c ON c.oid = t.tgrelid
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' 
  AND NOT t.tgisinternal 
  AND c.relname = 'users';

