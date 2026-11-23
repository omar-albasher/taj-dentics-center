# Secondary Project Cold-Start Audit Evidence (#48 — Post-C4)

**Latest Post-C4 Audit:** 2026-11-22 18:00:10 UTC+3  
**Target Environment:** Secondary Clean Supabase Project (`pjtgwaxdjtvdzvoazkxv`)  
**Verification Script:** `supabase/baseline/validate_rebuild.sql`  
**Execution Sequence:** `extensions.sql` -> `canonical_foundation.sql` -> C2 migrations `01..08` -> C3 migrations `01..09` -> C4 migration `20261121000001` -> `storage.sql` -> `cron_jobs.sql` -> `validate_rebuild.sql`

---

## 1. Post-C4 Cold-Start Output Table (Executed 2026-11-22 18:00:10 UTC+3)

| check_id | metric | expected | actual | status |
| :--- | :--- | :--- | :--- | :--- |
| C01 | Tables in public | 43 | 43 | **PASS** |
| C02 | Views in public | 33 | 33 | **PASS** |
| C03 | Functions in public | 111 | 111 | **PASS** |
| C04 | Policies in public | 71 | 71 | **PASS** |
| C05 | Triggers in public | 68 | 68 | **PASS** |
| C06 | Indexes in public | 130 | 130 | **PASS** |
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

> **Raw Output File:** Markdown copy of query results recorded in [cold_start_raw_20261122.txt](file:///d:/flutter-projects/admin_dashboard/supabase/baseline/cold_start_raw_20261122.txt).
> **Isolation Proof (C17 = 0):** Clean secondary database has 0 vault secrets prior to secret provisioning, whereas production (`nmczthzqbpkvweshitvv`) returns 3.

### Target Environment Session Proof:
- `project_ref`: `pjtgwaxdjtvdzvoazkxv`
- `dashboard_url`: `https://supabase.com/dashboard/project/pjtgwaxdjtvdzvoazkxv`
- `current_database`: `postgres`
- `current_user`: `postgres`
- `inet_server_addr`: `2a05:d014:128e:9501:250b:1c22:5ff5:88b`
- `execution_timestamp`: `2026-11-22 15:14:41 UTC` (18:14:41 Damascus / UTC+3)
- Status: **Empirically Verified Independent Cold-Start Rebuild (Post-C4) — 16/17 Platform Checks (16/16 Core Schema Invariants PASS, C17 Isolated Pre-Vault)**

### Functional Acceptance Suite Proof (`phase_c4_acceptance_proof.sql`):
- **Script:** `supabase/tests/20261121000002_phase_c4_acceptance_proof.sql`
- **Safety:** Transactional execution enclosed in `BEGIN ... ROLLBACK`
- **Result:** All 9/9 acceptance tests passed without error (`Success. No rows returned`)
- **Verified Invariants (9/9 PASS):**
  1. **Test 1**: P&L arithmetic matches payments/refunds/expenses per currency (`income - refunds - expenses = net`).
  2. **Test 2**: Expense breakdown reconciles with P&L category totals.
  3. **Test 3**: Cash flow per account reconciles with the C2 ledger (`account_transactions`) and `account_balances_v`.
  4. **Test 4**: Internal transfers between accounts are strictly P&L-neutral and reflected only in cash flow.
  5. **Test 5**: Lab section is isolated from Academy and `memorandum_uncollected` accurately tracks uncollected lab invoices.
  6. **Test 6**: Financial integrity function confirms every operational event matches the custody ledger.
  7. **Test 7**: Guard against invalid date periods (`p_to < p_from`) properly throws exception.
  8. **Test 8**: Reception role is denied execution across all four C4 functions (`c1_is_admin()` check).
  9. **Test 9**: Anonymous role is denied at the PostgreSQL grant level.

### Verdict & Architectural Confirmation:
1. **16/16 Core Schema Invariants PASS (16/17 Platform Checks)**: All 43 tables, 33 views, 111 functions (including 4 C4 reporting RPCs), 71 policies, 68 triggers, 130 indexes (including 3 C4 indexes), 3 sequences, and 9 enums were created perfectly from scratch. Check C17 returns 0 (FAIL) as expected prior to Vault secrets provisioning, confirming environment isolation.
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
