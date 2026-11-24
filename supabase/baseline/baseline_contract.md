# Taj Dentics Database Live Baseline Contract (#47 — Post-C5 Certified)

**Extraction Date:** 2026-11-17 12:12:00 UTC+3  
**Versions:** pg_dump 17.12 (client) / PostgreSQL 17.6 (Supabase hosted, AWS eu-west-1)  
**Authoritative Raw Dump (Pre-C2 Base):** `supabase/baseline/schema_live_20261117.sql` (319,289 bytes, 9,856 lines; represents the Pre-C2 canonical foundation before migrations 01–08)  
**Canonical Rebuild File:** `supabase/baseline/canonical_foundation.sql` (LF-only, zero BOM, client directives stripped, safe schema creation)  
**Validation Fingerprint:** `c8215afa7997fb5258254047a879d68a`  
**Status:** Certified Post-C5 Canonical Baseline on Production (17/17 PASS verified on `nmczthzqbpkvweshitvv` at 2026-11-24 17:18:52 Damascus Time [raw proof: `production_audit_raw_20261124.txt`; server_ip: `2a05:d018:48a:c902:2d02:8d28:a30f:5129`; Post-C5 validator with C03=114, C06=131]; Fingerprint Match 100%: `c8215afa7997fb5258254047a879d68a`).
- **Phase C5 Dual-Environment Verification:** 100% schema parity across secondary testing instance `pjtgwaxdjtvdzvoazkxv` (13/13 Schema PASS + 4 platform gaps; raw proof: `staged_audit_raw_20261123.txt`; acceptance proof: `phase_c5_acceptance_raw_20261124.txt`; REST security proof: `c5_rest_live_proof.md`) and production instance `nmczthzqbpkvweshitvv` (17/17 Full Platform PASS; deep structural proof in `production_audit_raw_20261124.txt`).

---

## 1. Executive Summary & Architectural Invariants
This baseline captures the complete, authoritative live schema state of Taj Dentics database following Phase D5 hardening, Phase C2 custody ledger, Phase C3 trainer compensation & staff payroll migrations (20261120000001 through 20261120000009), Phase C4 financial statements reporting (20261121000001), and Phase C5 accrual revenue recognition & reconciliation bridge (20261123000001):

| Class | Count | Status | Notes |
| :--- | :--- | :--- | :--- |
| Tables | **43** | Certified | 30 foundational + `user_pins` + 2 C2 custody tables + 10 C3 compensation & payroll tables (`enrollments` gained `completed_at timestamptz` in C5) |
| Views | **33** | Certified | 26 foundational views + 2 C2 views + 5 C3 compensation & payroll views |
| Functions | **114** | Certified Post-C5 | 107 foundational & C2/C3 + 4 C4 reporting + 3 C5 RPCs (`complete_cohort`, `get_accrual_revenue_report`, `get_accrual_reconciliation`); 100% pinned search_path |
| RLS Policies | **71** | Certified | 61 foundational & C2 + 10 C3 `admin_all` policies |
| Triggers | **68** | Certified | 50 foundational + 3 C2 + 4 C3 triggers + 11 C3 audit triggers |
| Indexes | **131** | Certified Post-C5 | 127 foundational & C2/C3 + 3 C4 period indexes + 1 C5 partial index (`idx_sessions_cohort_status_closed`) |
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
* **Phase C4 Financial Statements (read-only reporting):**
  - Four admin-only `SECURITY DEFINER` RPCs with pinned `search_path` (`public, pg_temp`): `get_profit_loss(date, date)`, `get_expense_breakdown(date, date)`, `get_cash_flow_statement(date, date)`, `get_financial_integrity()`. `EXECUTE` is revoked from `PUBLIC` and `anon`.
  - Academy P&L is cash-basis; the lab is a separate labelled section. Uncollected lab invoices are a memorandum item only and never enter net profit.
  - Cash flow is derived exclusively from C2 `account_transactions`, so opening + inflows − outflows = closing per account.
  - No tables, views, policies, triggers, or enums are added: C01/C02/C04/C05/C08/C12 remain unchanged and C11 stays 0.
* **Phase C5 Accrual Revenue Recognition & Reconciliation Bridge:**
  - Three admin-only `SECURITY DEFINER` RPCs with pinned `search_path` (`public, pg_temp`): `complete_cohort(uuid, boolean)`, `get_accrual_revenue_report(date)`, `get_accrual_reconciliation(date, date)`. `EXECUTE` is revoked from `PUBLIC` and `anon`.
  - True temporal As-Of isolation anchored to Damascus timezone (`Asia/Damascus`). Payments, refunds (`payment_refunds.created_at`), fee adjustments (`fee_adjustments.adjusted_at`), and cohort completions (`enrollments.completed_at`) are strictly bounded by `p_as_of` day end.
  - Delivery counting uses `FILTER` over sessions table, avoiding Cartesian inflation on multiple enrollments. Extra sessions (`is_extra = true`) are strictly excluded from delivery pro-rata.
  - Withdrawal handling preserves historical snapshots (`enrollment_withdrawals.net_due_before` prior to withdrawal date, and settled `due_amount` on/after withdrawal) without double pro-rata reduction.
  - Referral discounts (already embedded in `discount_amount` upon creation per A5) are not double-deducted. Net due is bounded by `GREATEST(0.00, ...)`.
  - Cohort completion enforces an unclosed session guard (`P0004`) requiring `p_force = true` for overrides, while safely allowing idempotent retries (`already_completed`) on previously closed cohorts with zero active enrollments.
  - One partial index added: `CREATE INDEX idx_sessions_cohort_status_closed ON public.sessions (cohort_id, status, closed_at) WHERE is_extra = false;`.
  - Invariant metrics updated: C03 = 114 functions, C06 = 131 indexes. Fingerprint C12 remains identical (`c8215afa7997fb5258254047a879d68a`).
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
5. Apply Phase C4 Migration: `supabase/migrations/20261121000001_phase_c4_financial_statements.sql` (Read-only financial statements: 4 RPCs + 3 indexes)
6. Apply Phase C5 Migration: `supabase/migrations/20261123000001_phase_c5_accrual_revenue.sql` (Accrual revenue reporting, cohort completion, and partial index)
7. `supabase/platform/storage.sql` (Create bucket & storage policies)
8. `supabase/platform/cron_jobs.sql` (Register 5 core cron jobs)
9. Deploy Edge Functions (`manage-user`, `send-fcm-notification`, `create-trainee`, `smart-responder`)
10. Configure Edge Function Secrets (`CRON_SECRET`, `FIREBASE_SERVICE_ACCOUNT`)
11. `supabase/platform/vault_secrets.sql` (Provide real project URL, cron secret, and push slug)
12. Configure Auth Hook in Dashboard (`supabase/platform/auth_hooks.md`)
13. Run Verification Script:
   ```sql
   \i supabase/baseline/validate_rebuild.sql
   ```
* **Expected Outcome:**
  - **Certified Live Production Baseline (Post-C5 on `nmczthzqbpkvweshitvv` at 2026-11-24 17:18:52 Damascus Time):** **17/17 PASS** verified live (documented in `production_audit_raw_20261124.txt` with Post-C5 validator: C03 = 114 functions, C06 = 131 indexes, C17 = 3 Vault secrets, C12 = `c8215afa7997fb5258254047a879d68a`, server_ip = `2a05:d018:48a:c902:2d02:8d28:a30f:5129`).
  - **Historical Post-C4 Baseline (under commit `a163fae`):** 17/17 PASS verified on `nmczthzqbpkvweshitvv` at 2026-11-22 18:40:20 UTC+3 (documented in `production_audit_raw_20261122.txt` with Post-C4 validator: C03 = 111 functions, C06 = 130 indexes).
  - **Staged Post-C5 Secondary Validation (`validate_rebuild.sql` on `pjtgwaxdjtvdzvoazkxv` at 2026-11-24 01:37:10 Damascus Time):** **13/17 PASS** (documented in `staged_audit_raw_20261123.txt`):
    - **13/13 Schema Integrity PASS:** C01–C13 all PASS (Tables=43, Views=33, Functions=114, Policies=71, Triggers=68, Indexes=131, Sequences=3, Enums=9, RLS Enabled=43, RLS Forced=0, SecDef Unpinned=0, Fingerprint C12=`c8215afa7997fb5258254047a879d68a`, Storage Bucket C13=true).
    - **4/4 Expected Secondary Platform Isolation Gaps (C14–C17):** Storage Policies C14=0 (expected 2), Scheduled Cron C15=0 (expected 5), Loaded Extensions C16=4 (expected 6), Vault Secrets C17=0 (expected 3). These 4 platform assets reside outside canonical DDL and are deliberately not initialized on the isolated secondary testing instance.
  - **Phase C4 Acceptance Suite:** `supabase/tests/20261121000002_phase_c4_acceptance_proof.sql` → 9/9 assertions, ends in `ROLLBACK`.
  - **Phase C5 Acceptance Suite:** `supabase/tests/20261123000002_phase_c5_acceptance_proof.sql` → 41 assertions across 12 tests, fully transactional, ends in `ROLLBACK`.
    - **Verified Live Execution (Secondary `pjtgwaxdjtvdzvoazkxv` via psql on 2026-11-24 15:34:37 Damascus Time):** **12/12 PASS** (documented in `supabase/tests/phase_c5_acceptance_raw_20261124.txt`; Migration MD5 = `20e5bca96abbc0cf5112284147e12a3a`, Test Script MD5 = `69f2efccf8783f74977444701fec5e85`, Zero Residuals verified via `ROLLBACK`).
    - **Verified Live Production Execution (`nmczthzqbpkvweshitvv` via psql on 2026-11-25 00:04:48 Damascus Time):** **12/12 PASS** (documented in `supabase/tests/phase_c5_acceptance_production_raw_20261125.txt`; executed following `trainee_code_seq` resync documented in `supabase/baseline/trainee_code_seq_resync_20261125.txt`; 100% assertions satisfied including universal bounds & balance identity on real production data; Zero Residuals verified via `ROLLBACK`).
    - **Phase C5 REST Security Invariant Matrix (G-C5.3 on Secondary `pjtgwaxdjtvdzvoazkxv` at 2026-11-24 16:22:20 UTC+3):** **PASS** across all roles (Anon HTTP 401 / 42501, Reception HTTP 400 / P0001, Admin: HTTP 200 للتقريرين و P0002 لإقفال فوج غير موجود [تجاوز الحارس الأمني]; zero leaked data; documented in `supabase/baseline/c5_rest_live_proof.md`).
