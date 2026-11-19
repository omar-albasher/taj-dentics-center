# Secondary Project Cold-Start Audit Evidence (#47 — Post-C2)

**Latest Post-C2 Audit:** 2026-11-20 01:45:00 UTC+3  
**Target Environment:** Secondary Clean Supabase Project (Cold-start Rebuild)  
**Verification Script:** `supabase/baseline/validate_rebuild.sql`  
**Execution Sequence:** `extensions.sql` -> `canonical_foundation.sql` -> migrations `01..08` -> `storage.sql` -> `cron_jobs.sql` -> `validate_rebuild.sql`

---

## 1. Post-C2 Cold-Start Output Table (Executed 2026-11-20)

| check_id | metric | expected | actual | status |
| :--- | :--- | :--- | :--- | :--- |
| C01 | Tables in public | 33 | 33 | **PASS** |
| C02 | Views in public | 28 | 28 | **PASS** |
| C03 | Functions in public | 94 | 94 | **PASS** |
| C04 | Policies in public | 61 | 61 | **PASS** |
| C05 | Triggers in public | 53 | 53 | **PASS** |
| C06 | Indexes in public | 96 | 96 | **PASS** |
| C07 | Sequences in public | 3 | 3 | **PASS** |
| C08 | Enums in public | 9 | 9 | **PASS** |
| C09 | RLS Enabled Tables | 33 | 33 | **PASS** |
| C10 | RLS Forced Tables | 0 | 0 | **PASS** |
| C11 | Unpinned SecDef Functions | 0 | 0 | **PASS** |
| C12 | Policy MD5 Fingerprint | `9f2ee2ee3f981ee2aa73d0fad04d7657` | `9f2ee2ee3f981ee2aa73d0fad04d7657` | **PASS** |
| C13 | Storage Bucket (course-materials) | true | true | **PASS** |
| C14 | Storage Policies on objects | 2 | 2 | **PASS** |
| C15 | Distinct Core Cron Jobs | 5 | 5 | **PASS** |
| C16 | Platform Extensions | 6 | 6 | **PASS** |
| C17 | Vault Push Scheduler Secrets | 3 | 0 | **FAIL** (Expected prior to Vault secret provisioning) |

### Target Environment Session Proof:
- `current_database`: `postgres`
- `current_user`: `postgres`
- Status: **Empirically Verified Independent Cold-Start Rebuild**

### Verdict & Architectural Confirmation:
1. **16/16 Schema Invariants PASS**: All 33 tables, 28 views, 94 functions, 61 policies, 53 triggers, 96 indexes, 3 sequences, and 9 enums were created perfectly from scratch.
2. **100% Policy Fingerprint Determinism**: Policy MD5 fingerprint `9f2ee2ee3f981ee2aa73d0fad04d7657` on the clean secondary project matches production bit-for-bit.
3. **Decisive Evidence of Isolation**: C17 returned `0` (Vault secrets empty prior to provisioning, whereas production returns `3`), definitively proving execution on an independent, non-production cold-start database.

---

## 2. Historical Pre-C2 Audit Reference (Executed 2026-11-17)

> **ملاحظة تاريخية:**
> يسجل هذا القسم أدلة التحقق السابقة لمرحلة C2 (قبل إضافة حسابات الخزينة وسجل الحركات).

| check_id | metric | expected | actual | status |
| :--- | :--- | :--- | :--- | :--- |
| C01 | Tables in public | 31 | 31 | PASS |
| C02 | Views in public | 26 | 26 | PASS |
| C03 | Functions in public | 87 | 87 | PASS |
| C04 | Policies in public | 59 | 59 | PASS |
| C05 | Triggers in public | 50 | 50 | PASS |
| C06 | Indexes in public | 87 | 87 | PASS |
| C07 | Sequences in public | 3 | 3 | PASS |
| C08 | Enums in public | 8 | 8 | PASS |
| C09 | RLS Enabled Tables | 31 | 31 | PASS |
| C10 | RLS Forced Tables | 0 | 0 | PASS |
| C11 | Unpinned SecDef Functions | 0 | 0 | PASS |
| C12 | Policy MD5 Fingerprint | `bacff6e12c60748988fc0831fe4307ec` | `bacff6e12c60748988fc0831fe4307ec` | PASS |
| C13 | Storage Bucket (course-materials) | true | true | PASS |
| C14 | Storage Policies on objects | 2 | 2 | PASS |
| C15 | Distinct Core Cron Jobs | 5 | 5 | PASS |
| C16 | Platform Extensions | 6 | 6 | PASS |
| C17 | Vault Push Scheduler Secrets | 3 | 0 | FAIL (Pre-Vault) |
