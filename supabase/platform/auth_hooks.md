# Platform Configuration: Auth Hooks & External Services (#47)

This document records platform configurations that reside outside `public` schema DDL and must be configured via the Supabase Dashboard or CLI.

---

## 1. Custom Access Token (JWT) Hook

Supabase Auth uses a Postgres function hook to inject custom claims (such as the active user role) into issued JWT tokens.

### Configuration Steps
1. In the Supabase Dashboard, navigate to:
   **Authentication** > **Hooks** (or **Advanced Settings** depending on Supabase UI version).
2. Locate **Custom Access Token (JWT)** hook.
3. Select **Postgres function**.
4. Configure:
   - **Schema:** `public`
   - **Function name:** `custom_access_token_hook(event jsonb)`
5. Save changes.

### Security Invariants Enforced by the Hook
- Defined as `SECURITY DEFINER` with search_path pinned to `public, pg_temp`.
- Grants: `EXECUTE` is strictly revoked from `public`, `anon`, and `authenticated`. Granted exclusively to `supabase_auth_admin` (and `service_role`).
- Behavior: Inspects `public.users` where `is_active = true`. If inactive or missing, sets `role = 'none'`.

---

## 2. Edge Functions

### `manage-user`
- **Location:** `supabase/functions/manage-user/index.ts`
- **Secrets Required:** `SERVICE_ROLE_KEY`
- **Deployment Command:**
  ```bash
  supabase functions deploy manage-user
  ```
- **Purpose:** Synchronous user deactivation / reactivation and role management using GoTrue Admin API (`updateUserById` with `ban_duration`).
