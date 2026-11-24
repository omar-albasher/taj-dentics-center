# Phase C5 REST Invariant Live Proof (G-C5.3)

**Target Environment**: Secondary Testing Supabase (`https://pjtgwaxdjtvdzvoazkxv.supabase.co`)  
**Execution Timestamp**: 2026-11-24 16:22:20 UTC+3  
**Verification Tool**: `scratch/check_c5_rest.dart`  
**Authentication Input Source**: `D:\flutter-projects\c5_rest.env` (Deleted immediately after run; no secrets logged; zero residuals in database)

---

## 1. Complete Security Matrix

| Role / Actor | RPC Function | Expected Status & Result | Actual Live Status | Live Response Body / Evidence | Gate Status |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Anonymous (Anon)** | `POST /rest/v1/rpc/complete_cohort` | HTTP 401 Unauthorized | **HTTP 401** | `{"code":"42501","message":"permission denied for function complete_cohort"}` | **PASS** |
| **Anonymous (Anon)** | `POST /rest/v1/rpc/get_accrual_revenue_report` | HTTP 401 Unauthorized | **HTTP 401** | `{"code":"42501","message":"permission denied for function get_accrual_revenue_report"}` | **PASS** |
| **Anonymous (Anon)** | `POST /rest/v1/rpc/get_accrual_reconciliation` | HTTP 401 Unauthorized | **HTTP 401** | `{"code":"42501","message":"permission denied for function get_accrual_reconciliation"}` | **PASS** |
| **Reception (`reception@test.com`)** | `POST /rest/v1/rpc/complete_cohort` | HTTP 400 Bad Request | **HTTP 400** | `{"code":"P0001","message":"غير مصرّح: إقفال الفوج متاح لمدير المركز فقط"}` | **PASS** |
| **Reception (`reception@test.com`)** | `POST /rest/v1/rpc/get_accrual_revenue_report` | HTTP 400 Bad Request | **HTTP 400** | `{"code":"P0001","message":"غير مصرّح: تقارير الاستحقاق متاحة لمدير المركز فقط"}` | **PASS** |
| **Reception (`reception@test.com`)** | `POST /rest/v1/rpc/get_accrual_reconciliation` | HTTP 400 Bad Request | **HTTP 400** | `{"code":"P0001","message":"غير مصرّح: تقارير تسوية الاستحقاق متاحة لمدير المركز فقط"}` | **PASS** |
| **Admin (`admin@test.com`)** | `POST /rest/v1/rpc/complete_cohort` | Bypassed Auth Guard (Code P0002) | **HTTP 500 / P0002** | `{"code":"P0002","message":"الفوج غير موجود"}` (Auth passed, reached business validation) | **PASS** |
| **Admin (`admin@test.com`)** | `POST /rest/v1/rpc/get_accrual_revenue_report` | HTTP 200 OK | **HTTP 200** | Returns accrual report array (`[]` on clean secondary instance) | **PASS** |
| **Admin (`admin@test.com`)** | `POST /rest/v1/rpc/get_accrual_reconciliation` | HTTP 200 OK | **HTTP 200** | Returns reconciliation records per currency (`[{"currency":"SYP", ...}]`) | **PASS** |

---

## 2. Key Verifications Proved

1. **Grant-Level Isolation for Anonymous Role**:
   Unauthenticated callers cannot execute any of the three Phase C5 functions. PostgreSQL grants immediately abort with SQLSTATE `42501` and message `"permission denied for function ..."`.
2. **Strict Admin-Only Authorization via `c1_is_admin()`**:
   Even though authenticated via GoTrue (`role = 'authenticated'`), reception staff are prevented from closing cohorts or accessing accrual revenue reports and reconciliations. The functions raise SQLSTATE `P0001` with explicit Arabic messages (`"غير مصرّح: ..."`) via PostgREST. Zero financial or cohort data leaks to non-admins.
3. **Operational Functionality & Guard Bypass for Admin Role**:
   The admin token successfully executes both reporting RPCs (`get_accrual_revenue_report` and `get_accrual_reconciliation`), receiving HTTP 200 with structured JSON. For `complete_cohort`, passing a non-existent cohort UUID returns HTTP 500 with SQLSTATE `P0002` (`الفوج غير موجود`), proving that the caller successfully bypassed the `c1_is_admin()` authorization guard (`P0001`) and reached the domain validation logic (the full transactional completion lifecycle is separately verified in acceptance suite Test 8).
4. **Credential & Database Hygiene**:
   The transient credential file `c5_rest.env` was permanently deleted immediately following script completion, and all temporary authentication and public user rows were purged from the secondary database (`public_users_count = 0` and `auth_users_count = 0` verified via psql).

---

## 3. Raw Execution Transcript

```text
================================================================
Phase C5 REST Invariant Live Proof (G-C5.3)
Target Supabase URL: https://pjtgwaxdjtvdzvoazkxv.supabase.co
================================================================

--- 1. Anonymous Checks (No Auth Token) ---
POST /rest/v1/rpc/complete_cohort (anon): HTTP 401 -> {"code":"42501","details":null,"hint":null,"message":"permission denied for function complete_cohort"}
POST /rest/v1/rpc/get_accrual_revenue_report (anon): HTTP 401 -> {"code":"42501","details":null,"hint":null,"message":"permission denied for function get_accrual_revenue_report"}
POST /rest/v1/rpc/get_accrual_reconciliation (anon): HTTP 401 -> {"code":"42501","details":null,"hint":null,"message":"permission denied for function get_accrual_reconciliation"}

--- 2. Reception Role Checks ---
Reception authenticated successfully (token masked).
POST /rest/v1/rpc/complete_cohort (reception): HTTP 400 -> {"code":"P0001","details":null,"hint":null,"message":"غير مصرّح: إقفال الفوج متاح لمدير المركز فقط"}
POST /rest/v1/rpc/get_accrual_revenue_report (reception): HTTP 400 -> {"code":"P0001","details":null,"hint":null,"message":"غير مصرّح: تقارير الاستحقاق متاحة لمدير المركز فقط"}
POST /rest/v1/rpc/get_accrual_reconciliation (reception): HTTP 400 -> {"code":"P0001","details":null,"hint":null,"message":"غير مصرّح: تقارير تسوية الاستحقاق متاحة لمدير المركز فقط"}

--- 3. Admin Role Checks ---
Admin authenticated successfully (token masked).
POST /rest/v1/rpc/complete_cohort (admin): HTTP 500 -> {"code":"P0002","details":null,"hint":null,"message":"الفوج غير موجود"}
POST /rest/v1/rpc/get_accrual_revenue_report (admin): HTTP 200 -> []
POST /rest/v1/rpc/get_accrual_reconciliation (admin): HTTP 200 -> [{"currency":"SYP","opening_unearned":0.00,"opening_accrued":0.00,"opening_earned_cumulative":0.00,"closing_unearned":0.00,"closing_accrued":0.00,"clo...

[SECURITY] D:\flutter-projects\c5_rest.env has been permanently deleted.

--- 4. Cleanup & Zero Residuals Verification (psql) ---
DELETE FROM public.users WHERE email IN ('admin@test.com', 'reception@test.com');
DELETE FROM auth.identities WHERE user_id IN ('b0b7363f-2f1f-4d6a-bda3-37a5fde5fc42'::uuid, '5c91ea10-d131-431e-9662-4bf0f21eff97'::uuid);
DELETE FROM auth.users WHERE email IN ('admin@test.com', 'reception@test.com');
SELECT count(*) AS public_users_count FROM public.users;
SELECT count(*) AS auth_users_count FROM auth.users;

DELETE 2
DELETE 2
DELETE 2
 public_users_count 
--------------------
                  0
(1 row)

 auth_users_count 
------------------
                0
(1 row)

================================================================
Execution finished.
================================================================
```
