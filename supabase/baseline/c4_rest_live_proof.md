# Phase C4 REST Invariant Live Proof (G-C4.3)

**Target Environment**: Production Supabase (`https://nmczthzqbpkvweshitvv.supabase.co`)  
**Execution Timestamp**: 2026-11-22 18:58:18 UTC+3  
**Verification Tool**: `scratch/check_c4_rest.dart`  
**Authentication Input Source**: `D:\flutter-projects\c4_rest.env` (Deleted immediately after run; no secrets logged)

---

## 1. Complete Security Matrix

| Role / Actor | RPC Function | Expected Status & Result | Actual Live Status | Live Response Body / Evidence | Gate Status |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Anonymous (Anon)** | `POST /rest/v1/rpc/get_profit_loss` | HTTP 401 Unauthorized | **HTTP 401** | `{"code":"42501","message":"permission denied for function get_profit_loss"}` | **PASS** |
| **Anonymous (Anon)** | `POST /rest/v1/rpc/get_expense_breakdown` | HTTP 401 Unauthorized | **HTTP 401** | `{"code":"42501","message":"permission denied for function get_expense_breakdown"}` | **PASS** |
| **Anonymous (Anon)** | `POST /rest/v1/rpc/get_cash_flow_statement` | HTTP 401 Unauthorized | **HTTP 401** | `{"code":"42501","message":"permission denied for function get_cash_flow_statement"}` | **PASS** |
| **Anonymous (Anon)** | `POST /rest/v1/rpc/get_financial_integrity` | HTTP 401 Unauthorized | **HTTP 401** | `{"code":"42501","message":"permission denied for function get_financial_integrity"}` | **PASS** |
| **Reception (`reception@...`)** | `POST /rest/v1/rpc/get_profit_loss` | HTTP 400 Bad Request | **HTTP 400** | `{"code":"P0001","message":"غير مصرّح: القوائم المالية متاحة لمدير المركز فقط"}` | **PASS** |
| **Reception (`reception@...`)** | `POST /rest/v1/rpc/get_expense_breakdown` | HTTP 400 Bad Request | **HTTP 400** | `{"code":"P0001","message":"غير مصرّح: القوائم المالية متاحة لمدير المركز فقط"}` | **PASS** |
| **Reception (`reception@...`)** | `POST /rest/v1/rpc/get_cash_flow_statement` | HTTP 400 Bad Request | **HTTP 400** | `{"code":"P0001","message":"غير مصرّح: القوائم المالية متاحة لمدير المركز فقط"}` | **PASS** |
| **Reception (`reception@...`)** | `POST /rest/v1/rpc/get_financial_integrity` | HTTP 400 Bad Request | **HTTP 400** | `{"code":"P0001","message":"غير مصرّح: القوائم المالية متاحة لمدير المركز فقط"}` | **PASS** |
| **Admin (`admin@tajdentics.com`)** | `POST /rest/v1/rpc/get_profit_loss` | HTTP 200 OK | **HTTP 200** | Returns P&L lines (academy net: 140,970,900 SYP; memorandum tracked) | **PASS** |
| **Admin (`admin@tajdentics.com`)** | `POST /rest/v1/rpc/get_expense_breakdown` | HTTP 200 OK | **HTTP 200** | Returns expense breakdown rows per account and category | **PASS** |
| **Admin (`admin@tajdentics.com`)** | `POST /rest/v1/rpc/get_cash_flow_statement` | HTTP 200 OK | **HTTP 200** | Returns cash flow rows per custody account with opening/closing | **PASS** |
| **Admin (`admin@tajdentics.com`)** | `POST /rest/v1/rpc/get_financial_integrity` | HTTP 200 OK | **HTTP 200** | Returns integrity audit rows (`diff: 0.00, is_balanced: true`) | **PASS** |

---

## 2. Key Verifications Proved

1. **Grant-Level Isolation for Anonymous Role**:
   Unauthenticated callers cannot execute any of the four financial reporting functions. PostgreSQL grants immediately abort with SQLSTATE `42501` and message `"permission denied for function ..."`.
2. **Strict Admin-Only Authorization via `c1_is_admin()`**:
   Even though authenticated via GoTrue (`role = 'authenticated'`), reception staff are prevented from accessing any financial statements or summaries. The functions raise SQLSTATE `P0001` with explicit message `"غير مصرّح: القوائم المالية متاحة لمدير المركز فقط"`. Zero bytes of financial figures leak to non-admins.
3. **Full Operational Functionality for Admin Role**:
   The admin token successfully queries all four endpoints and receives valid JSON records reflecting live production data.
4. **Credential Lifecycle Hygiene**:
   The transient credential file `c4_rest.env` / `c4_rest.env.txt` was permanently removed from disk immediately following script completion.

---

## 3. Raw Execution Transcript

```text
================================================================
Phase C4 REST Invariant Live Proof (G-C4.3)
Target Supabase URL: https://nmczthzqbpkvweshitvv.supabase.co
================================================================

--- 1. Anonymous Checks (No Auth Token) ---
POST /rest/v1/rpc/get_profit_loss (anon): HTTP 401 -> {"code":"42501","details":null,"hint":null,"message":"permission denied for function get_profit_loss"}
POST /rest/v1/rpc/get_expense_breakdown (anon): HTTP 401 -> {"code":"42501","details":null,"hint":null,"message":"permission denied for function get_expense_breakdown"}
POST /rest/v1/rpc/get_cash_flow_statement (anon): HTTP 401 -> {"code":"42501","details":null,"hint":null,"message":"permission denied for function get_cash_flow_statement"}
POST /rest/v1/rpc/get_financial_integrity (anon): HTTP 401 -> {"code":"42501","details":null,"hint":null,"message":"permission denied for function get_financial_integrity"}

--- 2. Reception Role Checks ---
Reception authenticated successfully (token masked).
POST /rest/v1/rpc/get_profit_loss (reception): HTTP 400 -> {"code":"P0001","details":null,"hint":null,"message":"غير مصرّح: القوائم المالية متاحة لمدير المركز فقط"}
POST /rest/v1/rpc/get_expense_breakdown (reception): HTTP 400 -> {"code":"P0001","details":null,"hint":null,"message":"غير مصرّح: القوائم المالية متاحة لمدير المركز فقط"}
POST /rest/v1/rpc/get_cash_flow_statement (reception): HTTP 400 -> {"code":"P0001","details":null,"hint":null,"message":"غير مصرّح: القوائم المالية متاحة لمدير المركز فقط"}
POST /rest/v1/rpc/get_financial_integrity (reception): HTTP 400 -> {"code":"P0001","details":null,"hint":null,"message":"غير مصرّح: القوائم المالية متاحة لمدير المركز فقط"}

--- 3. Admin Role Checks ---
Admin authenticated successfully (token masked).
POST /rest/v1/rpc/get_profit_loss (admin): HTTP 200 -> [{"currency":"SYP","section":"academy","income":140971000.00,"refunds":0.00,"expenses":100.00,"net":140970900.00,"memorandum_uncollected":0}, {"currency":"USD","section":"academy",...
POST /rest/v1/rpc/get_expense_breakdown (admin): HTTP 200 -> [{"section":"academy","currency":"SYP","account_id":"87b747e9-ab23-471f-9271-92d96c4f73bf","account_name_ar":"صندوق المركز","category":"other","amount":100.00...
POST /rest/v1/rpc/get_cash_flow_statement (admin): HTTP 200 -> [{"account_id":"87b747e9-ab23-471f-9271-92d96c4f73bf","account_name_ar":"صندوق المركز","account_type":"cash","currency":"SYP","opening_balance":576000.00,"inflows":140971000.00,"outflows":100.00,"closing_balance":141546900.00...
POST /rest/v1/rpc/get_financial_integrity (admin): HTTP 200 -> [{"source_type":"expense","currency":"SYP","events_total":100.00,"ledger_total":100.00,"diff":0.00,"is_balanced":true}, {"source_type":"payment",...

[SECURITY] D:\flutter-projects\c4_rest.env has been permanently deleted.

================================================================
Execution finished.
================================================================
```
