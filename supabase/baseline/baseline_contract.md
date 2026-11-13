# Taj Dentics Database Live Baseline Contract (#47)

**Extraction Date:** 2026-11-13 15:11:46 UTC+3  
**Versions:** pg_dump 17.12 (client) / PostgreSQL 17.6 (Supabase hosted, AWS eu-west-1)  
**Schema Dump File:** `supabase/baseline/schema_live_baseline.sql` (305,999 bytes, 9,418 lines)  
**Status:** Canonical Reference Only (Do NOT execute directly over incremental migrations)

---

## 1. Executive Summary & Architectural Discovery
Prior to this baseline extraction, the repository migrations (`supabase/migrations/`) only declared 17 incremental tables. The core architectural schema comprising **13 foundational tables** and their base RLS policies were never declared in the repository migrations:
1. `users`
2. `trainees`
3. `courses`
4. `cohorts`
5. `enrollments`
6. `payments`
7. `expenses`
8. `sessions`
9. `attendance`
10. `audit_log`
11. `survey_templates`
12. `survey_responses`
13. `survey_dispatches`

This baseline captures the complete, authoritative live schema state (30 tables total, 59 RLS policy definitions — **35 of them live-only and absent from `supabase/migrations`** — custom enums, and functions).

---

## 2. Extraction Command & Flags
The schema was extracted without sensitive data using the standard `pg_dump` tool:
```bash
# Use the Session pooler (port 5432) or direct connection — NOT the transaction pooler (6543).
pg_dump "$SUPABASE_DB_URL" \
  --schema-only \
  --schema=public \
  --no-owner \
  --file="supabase/baseline/schema_live_baseline.sql"
```
* The connection string was supplied via the `SUPABASE_DB_URL` environment variable and was never written to the repository.
* **Flags:**
  * `--schema-only`: Strict zero-data guarantee.
  * `--schema=public`: Excludes Supabase-managed internal schemas (`auth`, `storage`, `vault`).
  * `--no-owner`: Eliminates environment-specific role bindings.

---

## 3. Supplementary Live Evidence

### E1: Installed Extensions
Captured live from `pg_extension`:
| Extension | Version | Schema |
| :--- | :--- | :--- |
| `pg_cron` | 1.6.4 | `pg_catalog` |
| `pg_net` | 0.20.0 | `public` |
| `pg_stat_statements` | 1.11 | `extensions` |
| `pgcrypto` | 1.3 | `extensions` |
| `plpgsql` | 1.0 | `pg_catalog` |
| `supabase_vault` | 0.3.1 | `vault` |
| `uuid-ossp` | 1.1 | `extensions` |

### E2: Storage RLS Policies (`storage.objects`)
Captured live from `pg_policies`:
* **`admin_course_materials_storage` (ALL):**
  * Target: `bucket_id = 'course-materials'`
  * Roles: `authenticated`
  * Condition: `users.role = 'admin'::user_role AND users.is_active = true`
* **`course_materials_storage_download` (SELECT):**
  * Target: `bucket_id = 'course-materials'`
  * Roles: `authenticated`
  * Condition: Staff (`admin`, `reception`) OR enrolled, non-withdrawn trainees.

---

## 4. Key Entities Captured & Validated
* **Enums:**
  * `public.user_role` (`admin`, `trainer`, `reception`, `trainee`)
  * `public.payment_method` (`cash`, `transfer`, `other`, `sham_cash`, `hawala`)
  * `public.payment_status` (`unpaid`, `partial`, `complete`)
* **Functions:**
  * `public.get_user_role()` (Extracts role from JWT claims)
  * `public.c1_can_read_financials(uuid)` (Includes `service_role` and `auth.role() IS NULL` trust anchors)
* **Hardened Security Policies (D5.1):**
  * `reception_insert` on `public.payments` enforcing `performed_by = auth.uid()` and verified methods.
  * `trg_z_audit_users` active on `public.users` with `pin_hash` redaction.
  * Exactly 12 active audit triggers across 12 tracked tables.

---

## 5. Usage & Replay Warning
> [!CAUTION]
> **Reference-Only Artifact:**
> Do NOT execute `schema_live_baseline.sql` directly on an existing database that has already applied migrations. It contains raw DDL declarations (e.g. `CREATE SCHEMA public;`, pg_dump 17 `\restrict` directives).
> Cold-start environment provisioning must be handled via a dedicated foundation squash in a separate future milestone.

