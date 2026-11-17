# #47 — Foundation Gap Matrix (baseline vs migrations)

**Generated:** 2026-11-17, from repository artifacts only (no live connection).
**Sources:**
- `supabase/baseline/schema_live_baseline.sql` (pg_dump, 2026-11-13, schema=public, 30 tables / 59 policies).
- `supabase/migrations/` (43 files, first is `20261019000000_core_schema_and_security.sql`).
- Post-D5 commits not present in the dump: `e83100e` (PIN), `4f50736` (sessions), `8b3885e` (users).

> The dump is a snapshot of 2026-11-13. It predates the three commits above, so a
> rebuild artifact must be regenerated from a **fresh** dump; this file is only a
> gap inventory, not a DDL source.

---

## 1. Cold-start failure (decisive evidence)

`20261019000000_core_schema_and_security.sql:14` runs
`ALTER TABLE public.survey_responses ...` and `:25` runs
`ALTER TABLE public.attendance ...`, but no earlier migration creates either
table. A fresh database fails on the first migration file.

## 2. Gap counts

| Class | Live baseline | Migrations | Missing |
|---|---|---|---|
| Tables | 30 | 18 (17 overlap + `user_pins`) | **13** |
| Enums | 8 | 0 | **8** |
| RLS ENABLE | 30 | 18 | **13** |
| Policies | 59 | 32 | **35** |
| Views | 26 | 15 | **11** |
| Functions | 81 | 82 | **5** |
| Triggers | 48 | 46 | **3** |
| Indexes | 38 | 36 | **2** |
| Sequences | 3 | 1 | **2** |

## 3. Missing tables (13)

`users`, `trainees`, `courses`, `cohorts`, `enrollments`, `payments`,
`expenses`, `sessions`, `attendance`, `audit_log`, `survey_templates`,
`survey_responses`, `survey_dispatches`.

Their columns, PK/FK/unique constraints, defaults and grants exist only in the
live dump (e.g. `users` at baseline:4605-4617; enum `user_role` at
baseline:119-124).

## 4. Missing policies (35), grouped by table

| Table | Policies |
|---|---|
| attendance | admin_all, reception_select, trainee_insert_qr, trainee_self_select |
| audit_log | admin_select_only |
| cohorts | admin_all, reception_select, trainee_enrolled |
| courses | admin_all, others_select |
| enrollments | admin_all, reception_all, trainee_self |
| expenses | admin_only (baseline:7636) |
| payments | admin_all, reception_insert, reception_select, trainee_self |
| sessions | admin_all, reception_select, trainee_select |
| survey_dispatches | admin_all, trainee_mark_read, trainee_self_select |
| survey_responses | admin_all, trainee_insert, trainee_self_select |
| survey_templates | admin_all, trainee_select |
| trainees | admin_all, reception_all, trainee_self |
| users | admin_all_users (baseline:7615), reception_select_trainees_only (7953), self_select (7984) |

## 5. Missing views (11)

`enrollment_financial_summary` (baseline:4624), `cash_vs_accrual_kpis` (4649),
`course_revenue_sql_summary` (4910), `debt_aging_report` (5165),
`discounts_report` (5233), `expenses_by_category_report` (5321),
`open_sessions_view` (5513), `profit_loss_report` (5592),
`revenue_by_method_report` (5679), `survey_statistics` (5789),
`trainee_safe_profile` (5906).

`dashboard_kpis` reads `enrollment_financial_summary`, so the base view is
required even though `_v2` variants exist.

## 6. Missing functions / triggers / indexes / sequences

**Functions (5):** `get_current_user_id()` (baseline:1598),
`get_session_attendance(uuid)` (1763), `get_trainee_id()` (1912),
`handle_trainee_code_generation()` (2002), `btrim(public.currency_type)` (351).

**Triggers (3):** `trg_generate_trainee_code` (6949), `trg_payment_status`,
`trg_survey_dispatch`.

**Indexes (2):** `idx_trainees_code`, `idx_trainees_name_ar`.

**Sequences (2):** `audit_log_id_seq` (baseline:4482),
`trainee_code_seq` (5835). `lab_invoice_number_seq` is covered.

## 7. Out-of-dump platform objects

`pg_dump --schema=public` excludes:
- `storage.buckets` / `storage.objects` policies. The repository covers only the
  `course-materials` bucket (`20261024000001_phase_a6_course_materials.sql:67-123`,
  hardened in `20261113000001_phase_d3_permissions_hardening.sql:47-74`).
- `cron.job` schedules created in `20261025000001_phase_a1_push_scheduler.sql:73-95`.
- Extensions (`pg_cron`, `pg_net`, `pgcrypto`, `pg_stat_statements`,
  `supabase_vault`, `uuid-ossp`) — live evidence in `baseline_contract.md:50-60`.
- The Auth "Custom Access Token Hook" setting (dashboard-only, manual evidence).
- `vault` secrets (names only, never values).

## 8. Stale statements to correct in `baseline_contract.md`

- `:81` says `get_user_role()` extracts the role from JWT; since `8b3885e` it
  reads `public.users` with `is_active = true`.
- `:85` mentions `pin_hash` redaction on `users`; PIN moved to `user_pins`
  (`e83100e`).
- `:77-79` lists a partial enum set; there are 8 enums (baseline:40-124).
- The dump does not contain `user_pins`, `session_status='missed'`,
  `create_session`, `close_session`, the users guard trigger, or the redefined
  `shift_cohort_sessions`.

## 9. Adopted strategy (pending E0.1)

**Squash.** A fresh `pg_dump --schema-only --schema=public --no-owner` is
committed as the canonical foundation migration; the 43 historical files move
to `supabase/migrations_archive/`. Storage policies, cron jobs and the auth hook
are separate artifacts under `supabase/`.

Blocking condition: `E0.1a` must show `supabase_migrations.schema_migrations`
absent or empty. If the live project has CLI migration history, the squash needs
a `supabase migration repair` plan instead of a blind replay.

Cold-start verification target: a second Supabase project (storage/auth/cron
included), compared against live using `live_inventory.sql` E0.2 + E0.8.
