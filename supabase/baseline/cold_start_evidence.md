# Secondary Project Cold-Start Audit Evidence (#47 — Post-C3.8)

**Latest Post-C3.8 Audit:** 2026-11-21 10:31:11 UTC+3 (07:31:11 UTC)  
**Target Environment:** Secondary Clean Supabase Project (`pjtgwaxdjtvdzvoazkxv`)  
**Verification Script:** `supabase/baseline/validate_rebuild.sql`  
**Execution Sequence:** `extensions.sql` -> `canonical_foundation.sql` -> C2 migrations `01..08` -> C3 migrations `01..09` -> `storage.sql` -> `cron_jobs.sql` -> `validate_rebuild.sql`

---

## 1. Post-C3.8 Cold-Start Output Table (Executed 2026-11-21 10:31:11 UTC+3)

| check_id | metric | expected | actual | status |
| :--- | :--- | :--- | :--- | :--- |
| C01 | Tables in public | 43 | 43 | **PASS** |
| C02 | Views in public | 33 | 33 | **PASS** |
| C03 | Functions in public | 107 | 107 | **PASS** |
| C04 | Policies in public | 71 | 71 | **PASS** |
| C05 | Triggers in public | 68 | 68 | **PASS** |
| C06 | Indexes in public | 127 | 127 | **PASS** |
| C07 | Sequences in public | 3 | 3 | **PASS** |
| C08 | Enums in public | 9 | 9 | **PASS** |
| C09 | RLS Enabled Tables | 43 | 43 | **PASS** |
| C10 | RLS Forced Tables | 0 | 0 | **PASS** |
| C11 | Unpinned SecDef Functions | 0 | 0 | **PASS** |
| C12 | Policy MD5 Fingerprint | `c8215afa7997fb5258254047a879d68a` | `c8215afa7997fb5258254047a879d68a` | **PASS** |
| C13 | Storage Bucket (course-materials) | true | true | **PASS** |
| C14 | Storage Policies on objects | 2 | 2 | **PASS** |
| C15 | Distinct Core Cron Jobs | 5 | 5 | **PASS** |
| C16 | Platform Extensions | 6 | 6 | **PASS** |
| C17 | Vault Push Scheduler Secrets | 3 | 0 | **FAIL** (Expected prior to Vault secret provisioning — confirms clean isolation) |

> **Raw Output File:** Markdown copy of query results recorded in [cold_start_raw_20261121.txt](file:///d:/flutter-projects/admin_dashboard/supabase/baseline/cold_start_raw_20261121.txt).
> **Isolation Proof (C17 = 0):** Clean secondary database has 0 vault secrets prior to secret provisioning, whereas production (`nmczthzqbpkvweshitvv`) returns 3.

### Target Environment Session Proof:
- `project_ref`: `pjtgwaxdjtvdzvoazkxv`
- `dashboard_url`: `https://supabase.com/dashboard/project/pjtgwaxdjtvdzvoazkxv`
- `current_database`: `postgres`
- `current_user`: `postgres`
- `inet_server_addr`: `2a05:d014:128e:9501:250b:1c22:5ff5:88b/128`
- `execution_timestamp`: `2026-11-21 07:31:11 UTC`
- Status: **Empirically Verified Independent Cold-Start Rebuild (Post-C3.8) — 16/17 Platform Checks (16/16 Core Schema PASS, C17 Isolated Pre-Vault)**

### Functional Acceptance Suite Proof (`phase_c3_acceptance_proof.sql`):
- **Execution Timestamp:** 2026-11-21 10:42:28 UTC+3
- **Raw Execution Result:** All 6/6 test assertions passed in clean rollback transaction (recorded in [cold_start_raw_20261121.txt](file:///d:/flutter-projects/admin_dashboard/supabase/baseline/cold_start_raw_20261121.txt))
- **Verified Invariants (6/6 PASS):**
  1. All 10 C3 tables and 5 views exist with RLS enabled.
  2. Reception role is 100% isolated (0 rows visible on tables/views, RPC calls rejected).
  3. Trainer agreement created, cohort rate snapshot (25%) frozen, and overlapping agreement rejected.
  4. Trainer dues generated (50,000 SYP) and paid via `pay_trainer_due` expense, automatically creating C2 ledger transaction.
  5. Staff payroll generated (855,000 SYP net = salary + 2.5% referral + bonus - advance), approved, and paid via C2 custody expenses.
  6. Audit trail captured all compensation and payroll mutations.

### Verdict & Architectural Confirmation:
1. **16/16 Core Schema Invariants PASS (16/17 Platform Checks)**: All 43 tables, 33 views, 107 functions, 71 policies, 68 triggers, 127 indexes, 3 sequences, and 9 enums were created perfectly from scratch. Check C17 returns 0 (FAIL) as expected prior to Vault secrets provisioning, confirming environment isolation.
2. **100% Policy Fingerprint Determinism**: Policy MD5 fingerprint `c8215afa7997fb5258254047a879d68a` on the clean secondary project matches production bit-for-bit.
3. **Custody & Advance Synchronization Verified**: C3.8 advances are tied directly to the custody ledger via automatic expense rows and isolated via `cancel_staff_advance`.

---

## 2. Historical Audit References

### أ. فحص ما بعد C3 المبدئي (نُفّذ 2026-11-20 16:47:00 UTC+3)
* الجداول: 43، العروض: 33، الدوال: 105، السياسات: 71، المشغلات: 67، الفهارس: 126، البصمة: `c8215afa7997fb5258254047a879d68a` (16/17 PASS، C17 قبل إضافة أسرار Vault).

### ب. فحص ما بعد C2 (نُفّذ 2026-11-20 01:45:00 UTC+3)
* الجداول: 33، العروض: 28، الدوال: 94، السياسات: 61، المشغلات: 53، الفهارس: 96، البصمة: `9f2ee2ee3f981ee2aa73d0fad04d7657` (16/17 PASS).

### ج. فحص ما قبل C2 / Post-D5 (نُفّذ 2026-11-17 15:20:38 UTC+3)
* الجداول: 31، العروض: 26، الدوال: 87، السياسات: 59، المشغلات: 50، الفهارس: 87، البصمة: `bacff6e12c60748988fc0831fe4307ec` (16/17 PASS).
