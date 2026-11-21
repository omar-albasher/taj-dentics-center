# Taj Dentics Database Live Baseline Contract (#47 — Post-C3.8)

**Extraction Date:** 2026-11-17 12:12:00 UTC+3  
**Versions:** pg_dump 17.12 (client) / PostgreSQL 17.6 (Supabase hosted, AWS eu-west-1)  
**Authoritative Raw Dump (Pre-C2 Base):** `supabase/baseline/schema_live_20261117.sql` (319,289 bytes, 9,856 lines; represents the Pre-C2 canonical foundation before migrations 01–08)  
**Canonical Rebuild File:** `supabase/baseline/canonical_foundation.sql` (LF-only, zero BOM, client directives stripped, safe schema creation)  
**Validation Fingerprint:** `c8215afa7997fb5258254047a879d68a`  
**Status:** Certified Post-C3.8 Canonical Baseline (Rebuild Invariants Verified 16/17 pre-Vault on secondary project [C17=0 isolation proof]; 17/17 expected upon Vault provisioning; Fingerprint Match 100%: c8215afa7997fb5258254047a879d68a; Live DB 17/17 certified historically)

---

## 1. Executive Summary & Architectural Invariants
This baseline captures the complete, authoritative live schema state of Taj Dentics database following Phase D5 hardening, Phase C2 custody ledger, and Phase C3 trainer compensation & staff payroll migrations (20261120000001 through 20261120000009):

| Class | Count | Status | Notes |
| :--- | :--- | :--- | :--- |
| Tables | **43** | Certified | 30 foundational + `user_pins` + 2 C2 custody tables + 10 C3 compensation & payroll tables |
| Views | **33** | Certified | 26 foundational views + 2 C2 views + 5 C3 compensation & payroll views |
| Functions | **107** | Certified | 100% of `SECURITY DEFINER` functions have pinned `search_path` |
| RLS Policies | **71** | Certified | 61 foundational & C2 + 10 C3 `admin_all` policies |
| Triggers | **68** | Certified | 50 foundational + 3 C2 + 4 C3 triggers + 11 C3 audit triggers |
| Indexes | **127** | Certified | Foundation + C2 ledger + 31 C3 indexes |
| Sequences | **3** | Certified | `audit_log_id_seq`, `trainee_code_seq`, `lab_invoice_number_seq` |
| Enums | **9** | Certified | 9 enum types (8 foundational + `public.account_type`); `expense_category` gained values `trainer_fee` and `salary_advance` (values not counted by C08) |
| RLS Enabled | **43** | Certified | 100% of tables have row-level security enabled |
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
* **Enums (9):** `account_type`, `attendance_method`, `currency_type`, `enrollment_status`, `payment_method`, `payment_status`, `session_status` (including `'missed'`), `survey_type`, `user_role`.
* **Functions:**
  - `public.get_user_role()`: Live DB read with `is_active = true` (`SECURITY DEFINER`, search_path pinned to `public, pg_temp`), completely independent of JWT claims.
  - `public.verify_pin(text)`, `public.set_user_pin(text)`, `public.remove_user_pin()`: Isolated PIN management.
  - `public.create_session(...)`, `public.open_session(uuid)`, `public.close_session(uuid)`: Atomic staff-only RPCs.
  - `public.shift_cohort_sessions(uuid, date)`: Damascus timezone-safe rescheduling preserving wall clock.
* **Phase C2 Custody Ledger & Backfill Invariants:**
  - Single-entry custody ledger per account where balance = Σ(inflow) − Σ(outflow). Internal transfers record two reciprocal rows.
  - Written exclusively via triggers and RPC (`SECURITY DEFINER`, search_path pinned to `public, pg_temp`, admin-only). No direct staff write path exists via REST API (enforced by revoked grants and read-only RLS). Triggers synchronize corresponding ledger rows upon source payment/expense update or deletion.
  - Historical backfill executed on live DB (verified on 2026-11-20: `payments` unassigned = 0, `expenses` unassigned = 0).
* **Phase C3 Trainer Compensation & Staff Payroll Invariants:**
  - 10 tables protected by strict `admin_all` RLS; zero visibility for reception and trainees.
  - Rate percentages frozen per cohort via `cohort_trainer_rate_snapshots`; historical cohorts never modified by future agreement rate changes.
  - Payouts (trainer dues & monthly payroll) registered as `expenses` rows under `trainer_fee` and `salary` categories, naturally triggering C2 custody ledger movements without duplicate bookkeeping.
  - Complete auditability: 11 audit triggers capture before/after states on all C3 tables and `account_transactions`.
* **Hardened Security Triggers:**
  - `trg_guard_users_admin_changes` on `public.users`: Protects against self-demotion, self-deactivation, and demotion of the last active admin even under service_role.
  - `reception_insert` on `public.payments`: Enforces `performed_by = auth.uid()`.
  - 23 active audit triggers across 23 tracked tables.

---

## 5. Cold-Start Rebuild Sequence & Verification Protocol
### Sequential Execution Order:
1. `supabase/platform/extensions.sql` (Enable 6 platform extensions)
2. `supabase/baseline/canonical_foundation.sql` (Create canonical public schema)
3. Apply Phase C2 Migrations: `supabase/migrations/20261118000001_financial_accounts.sql` through `20261118000008_account_ledger_v.sql` (Authoritative source for Phase C2 schema, triggers, RLS, and views)
4. Apply Phase C3 Migrations: `supabase/migrations/20261120000001_add_expense_category_trainer_fee.sql` through `20261120000009_staff_advance_expense.sql` (Trainer compensation, staff payroll, advances, and audit triggers)
5. `supabase/platform/storage.sql` (Create bucket & storage policies)
6. `supabase/platform/cron_jobs.sql` (Register 5 core cron jobs)
7. Deploy Edge Functions (`manage-user`, `send-fcm-notification`, `create-trainee`, `smart-responder`)
8. Configure Edge Function Secrets (`CRON_SECRET`, `FIREBASE_SERVICE_ACCOUNT`)
9. `supabase/platform/vault_secrets.sql` (Provide real project URL, cron secret, and push slug)
10. Configure Auth Hook in Dashboard (`supabase/platform/auth_hooks.md`)
11. Run Verification Script:
   ```sql
   \i supabase/baseline/validate_rebuild.sql
   ```
* **Expected Outcome:**
  - All 17 checks evaluated: **17/17 PASS**.
  - Verified policy fingerprint: `c8215afa7997fb5258254047a879d68a`.
