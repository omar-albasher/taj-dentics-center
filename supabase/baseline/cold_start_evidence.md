# Secondary Project Cold-Start Audit Evidence (#47)

**Execution Timestamp:** 2026-11-17 15:20:38 UTC+3  
**Target Environment:** Secondary Clean Supabase Project (Cold-start)  
**Verification Script:** `supabase/baseline/validate_rebuild.sql`  

---

## 1. Raw Output Table (C01 - C17)

| check_id | metric | expected | actual | status |
| :--- | :--- | :--- | :--- | :--- |
| C01 | Tables in public | 31 | 31 | **PASS** |
| C02 | Views in public | 26 | 26 | **PASS** |
| C03 | Functions in public | 87 | 87 | **PASS** |
| C04 | Policies in public | 59 | 59 | **PASS** |
| C05 | Triggers in public | 50 | 50 | **PASS** |
| C06 | Indexes in public | 87 | 87 | **PASS** |
| C07 | Sequences in public | 3 | 3 | **PASS** |
| C08 | Enums in public | 8 | 8 | **PASS** |
| C09 | RLS Enabled Tables | 31 | 31 | **PASS** |
| C10 | RLS Forced Tables | 0 | 0 | **PASS** |
| C11 | Unpinned SecDef Functions | 0 | 0 | **PASS** |
| C12 | Policy MD5 Fingerprint | `bacff6e12c60748988fc0831fe4307ec` | `bacff6e12c60748988fc0831fe4307ec` | **PASS** |
| C13 | Storage Bucket (course-materials) | true | true | **PASS** |
| C14 | Storage Policies on objects | 2 | 2 | **PASS** |
| C15 | Distinct Core Cron Jobs | 5 | 5 | **PASS** |
| C16 | Platform Extensions | 6 | 6 | **PASS** |
| C17 | Vault Push Scheduler Secrets | 3 | 0 | FAIL (Expected prior to secret provisioning) |

---

## 2. Architectural Findings & Verdict
1. **16/17 Automatic Pass:** The sequential execution of `extensions.sql` -> `canonical_foundation.sql` -> `storage.sql` -> `cron_jobs.sql` created all 31 tables, 26 views, 87 functions, 50 triggers, 87 indexes, 3 sequences, and 8 enums with zero cold-start failures.
2. **Deterministic Fingerprint Match:** Policy MD5 fingerprint `bacff6e12c60748988fc0831fe4307ec` on the fresh database matches production bit-for-bit.
3. **Decisive Evidence:** C17 returned `0` because Vault secrets are empty on a blank project (unlike production where C17 returned `3`), providing independent proof that the test executed on a separate, pristine environment.
