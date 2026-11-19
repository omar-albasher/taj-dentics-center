# Taj Dentics Database Live Baseline Contract (#47 — Post-C2)

**Extraction Date:** 2026-11-17 12:12:00 UTC+3  
**Versions:** pg_dump 17.12 (client) / PostgreSQL 17.6 (Supabase hosted, AWS eu-west-1)  
**Authoritative Raw Dump (Pre-C2 Base):** `supabase/baseline/schema_live_20261117.sql` (319,289 bytes, 9,856 lines; represents the Pre-C2 canonical foundation before migrations 01–08)  
**Canonical Rebuild File:** `supabase/baseline/canonical_foundation.sql` (LF-only, zero BOM, client directives stripped, safe schema creation)  
**Validation Fingerprint:** `9f2ee2ee3f981ee2aa73d0fad04d7657`  
**Status:** Certified Post-C2 Canonical Baseline (Cold-start Verified 16/17 on secondary project; Fingerprint Match 100%; Live DB 17/17 PASS)

---

## 1. Executive Summary & Architectural Invariants
This baseline captures the complete, authoritative live schema state of Taj Dentics database following Phase D5 hardening and Phase C2 custody ledger migrations (20261118000001 through 20261118000008):

| Class | Count | Status | Notes |
| :--- | :--- | :--- | :--- |
| Tables | **33** | Certified | 30 foundational tables + `user_pins` + `financial_accounts` + `account_transactions` |
| Views | **28** | Certified | 26 foundational views + `account_balances_v` + `account_ledger_v` |
| Functions | **94** | Certified | 100% of `SECURITY DEFINER` functions have pinned `search_path` |
| RLS Policies | **61** | Certified | 59 foundational + `admin_all` on `financial_accounts` + `admin_select` on `account_transactions` |
| Triggers | **53** | Certified | 50 foundational + 3 C2 triggers (`trg_c2_account_tx_payment`, `expense`, `refund`) |
| Indexes | **96** | Certified | Foundation + C2 ledger unique source and time indexes |
| Sequences | **3** | Certified | `audit_log_id_seq`, `trainee_code_seq`, `lab_invoice_number_seq` |
| Enums | **9** | Certified | 8 foundational enums + `public.account_type` (`cash`, `bank`, `wallet`) |
| RLS Enabled | **33** | Certified | 100% of tables have row-level security enabled |
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
* **Hardened Security Triggers:**
  - `trg_guard_users_admin_changes` on `public.users`: Protects against self-demotion, self-deactivation, and demotion of the last active admin even under service_role.
  - `reception_insert` on `public.payments`: Enforces `performed_by = auth.uid()`.
  - 12 active audit triggers across 12 tracked tables.

---

## 5. Cold-Start Rebuild Sequence & Verification Protocol
### Sequential Execution Order:
1. `supabase/platform/extensions.sql` (Enable 6 platform extensions)
2. `supabase/baseline/canonical_foundation.sql` (Create canonical public schema)
3. Apply Phase C2 Migrations: `supabase/migrations/20261118000001_financial_accounts.sql` through `20261118000008_account_ledger_v.sql` (Authoritative source for Phase C2 schema, triggers, RLS, and views)
4. `supabase/platform/storage.sql` (Create bucket & storage policies)
5. `supabase/platform/cron_jobs.sql` (Register 5 core cron jobs)
6. Deploy Edge Functions (`manage-user`, `send-fcm-notification`, `create-trainee`, `smart-responder`)
7. Configure Edge Function Secrets (`CRON_SECRET`, `FIREBASE_SERVICE_ACCOUNT`)
8. `supabase/platform/vault_secrets.sql` (Provide real project URL, cron secret, and push slug)
9. Configure Auth Hook in Dashboard (`supabase/platform/auth_hooks.md`)
10. Run Verification Script:
   ```sql
   \i supabase/baseline/validate_rebuild.sql
   ```
* **Expected Outcome:**
  - All 17 checks evaluated: **17/17 PASS**.
  - Verified policy fingerprint: `9f2ee2ee3f981ee2aa73d0fad04d7657`.
