# Taj Dentics Database Live Baseline Contract (#47)

**Extraction Date:** 2026-11-17 12:12:00 UTC+3  
**Versions:** pg_dump 17.12 (client) / PostgreSQL 17.6 (Supabase hosted, AWS eu-west-1)  
**Authoritative Dump File:** `supabase/baseline/schema_live_20261117.sql` (319,289 bytes, 9,856 lines)  
**Canonical Rebuild File:** `supabase/baseline/canonical_foundation.sql`  
**Validation Fingerprint:** `bacff6e12c60748988fc0831fe4307ec`  
**Status:** Certified Post-D5 Canonical Baseline (Cold-start verified)

---

## 1. Executive Summary & Architectural Invariants
This baseline captures the complete, authoritative live schema state of Taj Dentics database following the Phase D5 security hardening milestones (PIN storage isolation `e83100e`, sessions hardening `4f50736`, and users hardening `8b3885e`):

| Class | Count | Status | Notes |
| :--- | :--- | :--- | :--- |
| Tables | **31** | Certified | 30 foundational tables + `public.user_pins` |
| Views | **26** | Certified | Including financial reports and trainee safe profile |
| Functions | **87** | Certified | 100% of `SECURITY DEFINER` functions have pinned `search_path` |
| RLS Policies | **59** | Certified | Public policy MD5 fingerprint: `bacff6e12c60748988fc0831fe4307ec` |
| Triggers | **50** | Certified | Includes `trg_guard_users_admin_changes` & audit triggers |
| Indexes | **87** | Certified | Primary, foreign, and performance indexes |
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
  1. Commented out client-only pg_dump 17 security directives (`\restrict` and `\unrestrict`).
  2. Changed `CREATE SCHEMA public;` to `CREATE SCHEMA IF NOT EXISTS public;` to avoid collisions on pre-existing databases.

---

## 3. Platform & Out-of-Dump Components
Components outside the `public` schema are maintained in dedicated, modular files under `supabase/platform/`:
1. **Storage (`supabase/platform/storage.sql`):**
   - Bucket: `course-materials` (private).
   - Policies on `storage.objects`:
     - `admin_course_materials_storage` (ALL for active admins).
     - `course_materials_storage_download` (SELECT for staff and enrolled, non-withdrawn trainees).
2. **Cron Scheduler (`supabase/platform/cron_jobs.sql`):**
   - Registered pg_cron jobs:
     - `auto_open_close_sessions` (`*/2 * * * *`)
     - `enqueue_session_reminders` (`*/5 * * * *`)
     - `dispatch_push_batch` (`* * * * *`)
     - `expire_waitlist_notifications` (`*/15 * * * *`)
     - `enqueue_payment_reminders` (`0 7 * * 0`)
3. **Auth Hooks (`supabase/platform/auth_hooks.md`):**
   - Custom Access Token Hook points to `public.custom_access_token_hook(jsonb)` via Supabase Dashboard / Config.

---

## 4. Key Entities & Security Hardening Anchors
* **Enums (8):**
  - `public.attendance_method` (`qr`, `manual`)
  - `public.currency_type` (`SYP`, `USD`)
  - `public.enrollment_status` (`pending`, `confirmed`, `rejected`, `cancelled`)
  - `public.payment_method` (`cash`, `transfer`, `other`, `sham_cash`, `hawala`)
  - `public.payment_status` (`unpaid`, `partial`, `complete`)
  - `public.session_status` (`scheduled`, `open`, `closed`, `cancelled`, `missed`)
  - `public.survey_type` (`mid_term`, `final`, `general`)
  - `public.user_role` (`admin`, `trainer`, `reception`, `trainee`)
* **Functions:**
  - `public.get_user_role()`: Reads directly from `public.users` where `id = auth.uid() AND is_active = true` (`SECURITY DEFINER`, search_path pinned to `public, pg_temp`), eliminating stale JWT role claims.
  - `public.c1_can_read_financials(uuid)`: Authoritative financial read access control.
  - `public.verify_pin(text)`, `public.set_user_pin(text)`, `public.remove_user_pin()`: Isolated PIN management.
  - `public.create_session(...)`, `public.open_session(uuid)`, `public.close_session(uuid)`: Staff-only atomic session RPCs.
  - `public.shift_cohort_sessions(uuid, date)`: Damascus timezone-safe session rescheduling.
* **Hardened Security Triggers:**
  - `trg_guard_users_admin_changes` on `public.users`: Blocks self-demotion, self-deactivation, and demotion of the last active admin even under service_role.
  - `reception_insert` on `public.payments`: Enforces `performed_by = auth.uid()` and verified methods.
  - Exactly 12 active audit triggers across 12 tracked tables.

---

## 5. Verification Protocol
To verify any target environment (live or clean rebuild):
```sql
\i supabase/baseline/validate_rebuild.sql
```
Must yield 12/12 `PASS` with fingerprint `bacff6e12c60748988fc0831fe4307ec`.
