# Taj Dentics Database Live Baseline Contract (#47)

**Extraction Date:** 2026-11-17 12:12:00 UTC+3  
**Versions:** pg_dump 17.12 (client) / PostgreSQL 17.6 (Supabase hosted, AWS eu-west-1)  
**Authoritative Raw Dump:** `supabase/baseline/schema_live_20261117.sql` (319,289 bytes, 9,856 lines)  
**Canonical Rebuild File:** `supabase/baseline/canonical_foundation.sql` (LF-only, zero BOM, client directives stripped, safe schema creation)  
**Validation Fingerprint:** `bacff6e12c60748988fc0831fe4307ec`  
**Status:** Certified Post-D5 Canonical Baseline (Cold-start Verified 16/17 on secondary project; Fingerprint Match 100%)

---

## 1. Executive Summary & Architectural Invariants
This baseline captures the complete, authoritative live schema state of Taj Dentics database following the Phase D5 security hardening milestones (PIN storage isolation `e83100e`, sessions hardening `4f50736`, and users hardening `8b3885e`):

| Class | Count | Status | Notes |
| :--- | :--- | :--- | :--- |
| Tables | **31** | Certified | 30 foundational tables + `public.user_pins` |
| Views | **26** | Certified | Including financial reports and trainee safe profile |
| Functions | **87** | Certified | 100% of `SECURITY DEFINER` functions have pinned `search_path` |
| RLS Policies | **59** | Certified | Public policy MD5 fingerprint: `bacff6e12c60748988fc0831fe4307ec` |
| Triggers | **50** | Certified | 49 standard triggers + 1 constraint trigger (`trg_guard_users_admin_changes`) |
| Indexes | **87** | Certified | 31 PK + 18 UNIQUE constraints + 35 CREATE INDEX + 3 UNIQUE INDEX |
| Sequences | **3** | Certified | `audit_log_id_seq`, `trainee_code_seq`, `lab_invoice_number_seq` |
| Enums | **8** | Certified | All 8 custom PostgreSQL enums defined |
| RLS Enabled | **31** | Certified | 100% of tables have row-level security enabled |
| RLS Forced | **0** | Certified | Zero forced tables (avoids breaking owner bypass in SecDef RPCs) |

---

## 2. Extraction & Clean-up Specification
The schema was extracted without sensitive data using the standard `pg_dump` tool:
```bash
pg_dump "$SUPABASE_DB_URL" \
  --schema-only \
  --schema=public \
  --no-owner \
  --file="supabase/baseline/schema_live_20261117.sql"
```

* **Clean-up applied to generate `canonical_foundation.sql`:**
  1. **Zero BOM & LF Line Endings:** Encoded strictly as UTF-8 without byte-order marks (`2D 2D`) and Unix line feeds (`\n`).
  2. **Directives Stripped:** Entirely removed PostgreSQL 17 client slash commands (`\restrict` and `\unrestrict`).
  3. **Idempotent Schema:** Replaced `CREATE SCHEMA public;` with `CREATE SCHEMA IF NOT EXISTS public;`.
  4. **Permission Guard:** Wrapped `ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin` in a PL/pgSQL `DO $$` block catching `insufficient_privilege` to prevent cold-start failures where `postgres` lacks administrative membership in `supabase_admin`.

---

## 3. Platform Prerequisites & External Dependencies
Components outside the `public` schema are maintained in modular files under `supabase/platform/`:
1. **Extensions (`supabase/platform/extensions.sql`):**
   - `uuid-ossp` (schema `extensions`)
   - `pgcrypto` (schema `extensions`)
   - `pg_stat_statements` (schema `extensions`)
   - `pg_net` (schema `public`)
   - `pg_cron` (schema `pg_catalog`)
   - `supabase_vault` (schema `vault`)
2. **Vault Secrets (`supabase/platform/vault_secrets.sql`):**
   - Required by push worker `dispatch_push_batch`:
     - `project_url`
     - `cron_secret`
     - `push_function_slug`: Canonical default is `send-fcm-notification`. Replay scripts only create this secret if missing and strictly preserve any existing custom or historical live slug (such as production's `bright-endpoint`).
   - Guarded against executing raw unconfigured placeholders.
3. **Storage (`supabase/platform/storage.sql`):**
   - Bucket: `course-materials` (private).
   - Policies on `storage.objects`:
     - `admin_course_materials_storage` (ALL for active admins).
     - `course_materials_storage_download` (SELECT for staff and enrolled, non-withdrawn trainees).
4. **Cron Scheduler (`supabase/platform/cron_jobs.sql`):**
   - 5 core registered pg_cron jobs:
     - `auto_open_close_sessions` (`*/2 * * * *`)
     - `enqueue_session_reminders` (`*/5 * * * *`)
     - `dispatch_push_batch` (`* * * * *`)
     - `expire_waitlist_notifications` (`*/15 * * * *`)
     - `enqueue_payment_reminders` (`0 7 * * 0`)
5. **Auth Hooks (`supabase/platform/auth_hooks.md`):**
   - Custom Access Token Hook points to `public.custom_access_token_hook(jsonb)`.
6. **Edge Functions & Environment Secrets:**
   - Functions: `manage-user`, `send-fcm-notification`, `create-trainee`, `smart-responder`.
   - Function Secrets: `CRON_SECRET`, `FIREBASE_SERVICE_ACCOUNT`, `SERVICE_ROLE_KEY` (or `SUPABASE_SERVICE_ROLE_KEY`).

---

## 4. Key Security Invariants & Defenses
* **Enums (8):** `attendance_method`, `currency_type`, `enrollment_status`, `payment_method`, `payment_status`, `session_status` (including `'missed'`), `survey_type`, `user_role`.
* **Functions:**
  - `public.get_user_role()`: Live DB read with `is_active = true` (`SECURITY DEFINER`, search_path pinned to `public, pg_temp`), completely independent of JWT claims.
  - `public.verify_pin(text)`, `public.set_user_pin(text)`, `public.remove_user_pin()`: Isolated PIN management.
  - `public.create_session(...)`, `public.open_session(uuid)`, `public.close_session(uuid)`: Atomic staff-only RPCs.
  - `public.shift_cohort_sessions(uuid, date)`: Damascus timezone-safe rescheduling preserving wall clock.
* **Hardened Security Triggers:**
  - `trg_guard_users_admin_changes` on `public.users`: Protects against self-demotion, self-deactivation, and demotion of the last active admin even under service_role.
  - `reception_insert` on `public.payments`: Enforces `performed_by = auth.uid()`.
  - 12 active audit triggers across 12 tracked tables.

---

## 5. Cold-Start Rebuild Sequence & Verification Protocol
### Sequential Execution Order:
1. `supabase/platform/extensions.sql` (Enable 6 platform extensions)
2. `supabase/baseline/canonical_foundation.sql` (Create canonical public schema)
3. `supabase/platform/storage.sql` (Create bucket & storage policies)
4. `supabase/platform/cron_jobs.sql` (Register 5 core cron jobs)
5. Deploy Edge Functions (`manage-user`, `send-fcm-notification`, `create-trainee`, `smart-responder`)
6. Configure Edge Function Secrets (`CRON_SECRET`, `FIREBASE_SERVICE_ACCOUNT`)
7. `supabase/platform/vault_secrets.sql` (Provide real project URL, cron secret, and push slug)
8. Configure Auth Hook in Dashboard (`supabase/platform/auth_hooks.md`)
9. Run Verification Script:
   ```sql
   \i supabase/baseline/validate_rebuild.sql
   ```
* **Expected Outcome:**
  - All 17 checks evaluated: **17/17 PASS**.
  - Verified policy fingerprint: `bacff6e12c60748988fc0831fe4307ec`.
