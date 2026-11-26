-- ============================================================================
-- Acceptance Suite: Phase C7 Accounting Period Closing Proof
-- File: supabase/tests/20261126000002_phase_c7_acceptance_proof.sql
-- Reference Migration: 20261126000001_phase_c7_accounting_periods.sql
--
-- Verifies the retroactive write lock over a closed Damascus calendar month:
--   Test 1:  close_accounting_period succeeds (forced), row + audit row written.
--   Test 2:  payments INSERT/UPDATE(non-financial)/DELETE in the closed month
--            => P0005 (C1 guards do not intercept these three variants).
--   Test 3:  refunds / fee adjustments / expenses / ledger / withdrawals => P0005.
--   Test 4:  enrollment INSERT and financial edits in the closed month => P0005.
--   Test 5:  trainer_dues INSERT and pending->cancelled => P0005;
--            pending->paid stays allowed (amount frozen by td_amount_ck).
--   Test 6:  payroll_lines INSERT / run DELETE / status regression => P0005;
--            draft->approved allowed.
--   Test 7:  staff advances / bonuses INSERT => P0005; cancelling an old advance
--            is blocked because its expense delete is retroactive.
--   Test 8:  lab invoice/payment/expense retro writes => P0005;
--            recalculate_lab_invoice stays allowed (same figures).
--   Test 9:  sessions closed_at retro edits => P0005.
--   Test 10: current open month stays writable (payment control).
--   Test 11: withdrawing an old enrollment still works; discount reduction on a
--            non-active enrollment allowed, increase blocked.
--   Test 12: C5 As-Of report hash is stable across blocked attempts.
--   Test 13: close argument guards (first-of-month, current/future, idempotent).
--   Test 14: reopen RBAC (reception P0001, anon 42501), short reason P0006,
--            valid reopen, retro write allowed, re-close blocks again.
--   Test 15: structural invariants (17 triggers, pinned secdef, grants, RLS)
--            and trainee_code_seq untouched.
--
-- Safety: Fully transactional (BEGIN ... ROLLBACK). Fixtures use one closed
-- month two months back and explicit trainee codes / lab invoice numbers.
-- audit_log_id_seq advances (log sequence, no business meaning) — accepted.
-- Run as the database owner/superuser (postgres) over psql, exactly like the
-- C6 suite; SET LOCAL ROLE is used only for grant-level denial assertions.
-- ============================================================================

BEGIN;

-- Session helper: runs one statement and returns 'OK' or 'SQLSTATE|message'.
CREATE FUNCTION pg_temp.c7_try(p_sql text) RETURNS text
LANGUAGE plpgsql
AS $$
BEGIN
  EXECUTE p_sql;
  RETURN 'OK';
EXCEPTION WHEN OTHERS THEN
  RETURN SQLSTATE || '|' || SQLERRM;
END;
$$;

DO $$
#variable_conflict use_column
DECLARE
  v_admin_id      uuid;
  v_reception_id  uuid;

  v_today     date := (now() AT TIME ZONE 'Asia/Damascus')::date;
  v_cur_start date := date_trunc('month', (now() AT TIME ZONE 'Asia/Damascus')::date)::date;
  v_m_start   date := (date_trunc('month', (now() AT TIME ZONE 'Asia/Damascus')::date) - interval '2 months')::date;
  v_m_end     date := (date_trunc('month', (now() AT TIME ZONE 'Asia/Damascus')::date) - interval '1 month' - interval '1 day')::date;
  v_next_start date := (date_trunc('month', (now() AT TIME ZONE 'Asia/Damascus')::date) + interval '1 month')::date;
  v_m_ts      timestamptz;
  v_m_date    date := v_m_start + 5;

  v_account   uuid;
  v_course    uuid;
  v_cohort_a  uuid;
  v_cohort_b  uuid;
  v_cohort_c  uuid;
  v_t1        uuid;
  v_t2        uuid;
  v_t3        uuid;
  v_enr_a     uuid;
  v_enr_b     uuid;
  v_payment   uuid;
  v_payment2  uuid;
  v_due1      uuid;
  v_due2      uuid;
  v_run       uuid;
  v_adv       uuid;
  v_client    uuid;
  v_invoice   uuid;
  v_session   uuid;

  v_period_id uuid;
  v_res       jsonb;
  v_txt       text;
  v_cnt       int;
  v_hash1     text;
  v_hash2     text;
  v_hash3     text;
  v_hash4     text;

  v_state     text;
  v_msg       text;
  v_caught    boolean;

  v_function  text;
  v_prosecdef boolean;
  v_pinned    boolean;

  v_seq_before bigint;
  v_seq_called_before boolean;
  v_seq_after  bigint;
  v_seq_called_after boolean;

  v_pass int := 0;
BEGIN
  RAISE NOTICE '=== Starting Phase C7 Accounting Period Closing Acceptance Proof ===';
  RAISE NOTICE 'Context: Database=%, User=%, DamascusDate=%, ClosedMonth=%',
    current_database(), current_user, v_today, to_char(v_m_start, 'YYYY-MM');
  RAISE NOTICE 'Operational Rule: do not run within 60s of Damascus midnight';

  v_m_ts := ((v_m_start + 5)::timestamp + interval '10 hours') AT TIME ZONE 'Asia/Damascus';

  -- --------------------------------------------------------------------------
  -- 0. Actors + sequence baseline
  -- --------------------------------------------------------------------------
  SELECT u.id INTO v_admin_id
  FROM public.users u JOIN auth.users a ON a.id = u.id
  WHERE u.role = 'admin' AND u.is_active
  LIMIT 1;

  IF v_admin_id IS NULL THEN
    v_admin_id := gen_random_uuid();
    INSERT INTO auth.users (id, instance_id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
    VALUES (v_admin_id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
            'c7_admin_' || substr(v_admin_id::text, 1, 8) || '@example.com',
            '{"provider":"email","providers":["email"]}', '{"role":"admin"}', now(), now());
    INSERT INTO public.users (id, full_name, email, role, is_active)
    VALUES (v_admin_id, 'C7 Admin Test', 'c7_admin_' || substr(v_admin_id::text, 1, 8) || '@example.com', 'admin', true);
  END IF;

  SELECT u.id INTO v_reception_id
  FROM public.users u JOIN auth.users a ON a.id = u.id
  WHERE u.role = 'reception' AND u.is_active
  LIMIT 1;

  IF v_reception_id IS NULL THEN
    v_reception_id := gen_random_uuid();
    INSERT INTO auth.users (id, instance_id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
    VALUES (v_reception_id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
            'c7_rec_' || substr(v_reception_id::text, 1, 8) || '@example.com',
            '{"provider":"email","providers":["email"]}', '{"role":"reception"}', now(), now());
    INSERT INTO public.users (id, full_name, email, role, is_active)
    VALUES (v_reception_id, 'C7 Reception Test', 'c7_rec_' || substr(v_reception_id::text, 1, 8) || '@example.com', 'reception', true);
  END IF;

  PERFORM set_config('request.jwt.claim.sub', v_admin_id::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object(
    'sub', v_admin_id, 'role', 'authenticated',
    'user_metadata', json_build_object('role', 'admin'))::text, true);

  SELECT last_value, is_called INTO v_seq_before, v_seq_called_before
  FROM public.trainee_code_seq;

  -- --------------------------------------------------------------------------
  -- 1. Fixtures (all inside v_m_start .. v_m_end unless noted)
  -- --------------------------------------------------------------------------
  SELECT id INTO v_account
  FROM public.financial_accounts
  WHERE is_active AND currency = 'SYP'
  ORDER BY created_at
  LIMIT 1;

  IF v_account IS NULL THEN
    INSERT INTO public.financial_accounts (name_ar, name_en, account_type, currency, is_active)
    VALUES ('صندوق C7 اختبار', 'C7 Test Cash', 'cash', 'SYP', true)
    RETURNING id INTO v_account;
  END IF;

  v_course := gen_random_uuid();
  INSERT INTO public.courses (id, name, total_sessions, price, created_by, is_active)
  VALUES (v_course, 'C7 Period Lock Course', 10, 100000.00, v_admin_id, true);

  v_cohort_a := gen_random_uuid();
  INSERT INTO public.cohorts (id, course_id, trainer_id, name, starts_at, created_by, is_active)
  VALUES (v_cohort_a, v_course, v_admin_id, 'C7 Closed-Month Cohort', v_m_start - 7, v_admin_id, true);

  v_cohort_b := gen_random_uuid();
  INSERT INTO public.cohorts (id, course_id, trainer_id, name, starts_at, created_by, is_active)
  VALUES (v_cohort_b, v_course, v_admin_id, 'C7 Dues Cancel Cohort', v_m_start - 7, v_admin_id, true);

  v_cohort_c := gen_random_uuid();
  INSERT INTO public.cohorts (id, course_id, trainer_id, name, starts_at, created_by, is_active)
  VALUES (v_cohort_c, v_course, v_admin_id, 'C7 Late Dues Cohort', v_m_start - 7, v_admin_id, true);

  v_t1 := gen_random_uuid();
  INSERT INTO public.trainees (id, trainee_code, full_name_ar, created_by)
  VALUES (v_t1, 'C7T' || upper(substr(v_t1::text, 1, 8)), 'متدرب C7 منسحب', v_admin_id);

  v_t2 := gen_random_uuid();
  INSERT INTO public.trainees (id, trainee_code, full_name_ar, created_by)
  VALUES (v_t2, 'C7T' || upper(substr(v_t2::text, 1, 8)), 'متدرب C7 نشط', v_admin_id);

  v_t3 := gen_random_uuid();
  INSERT INTO public.trainees (id, trainee_code, full_name_ar, created_by)
  VALUES (v_t3, 'C7T' || upper(substr(v_t3::text, 1, 8)), 'متدرب C7 إضافي', v_admin_id);

  v_enr_a := gen_random_uuid();
  INSERT INTO public.enrollments (id, cohort_id, trainee_id, enrolled_at, created_by, status, lifecycle_status, total_due, discount_amount, currency)
  VALUES (v_enr_a, v_cohort_a, v_t1, v_m_ts, v_admin_id, 'unpaid', 'active', 100000.00, 5000.00, 'SYP');

  v_enr_b := gen_random_uuid();
  INSERT INTO public.enrollments (id, cohort_id, trainee_id, enrolled_at, created_by, status, lifecycle_status, total_due, discount_amount, currency)
  VALUES (v_enr_b, v_cohort_a, v_t2, v_m_ts, v_admin_id, 'partial', 'active', 100000.00, 0.00, 'SYP');

  INSERT INTO public.sessions (id, cohort_id, session_number, scheduled_at, status, closed_at, is_extra)
  VALUES (gen_random_uuid(), v_cohort_a, 1, v_m_ts, 'closed', v_m_ts, false)
  RETURNING id INTO v_session;

  INSERT INTO public.payments (enrollment_id, amount, method, paid_at, performed_by, currency)
  VALUES (v_enr_b, 1000.00, 'cash', v_m_ts, v_admin_id, 'SYP')
  RETURNING id INTO v_payment;

  -- Refund-free payment: proves the C7 DELETE guard, not the C1 guard.
  INSERT INTO public.payments (enrollment_id, amount, method, paid_at, performed_by, currency)
  VALUES (v_enr_b, 300.00, 'cash', v_m_ts, v_admin_id, 'SYP')
  RETURNING id INTO v_payment2;

  INSERT INTO public.payment_refunds (payment_id, amount, reason, refunded_at, created_by)
  VALUES (v_payment, 100.00, 'استرداد C7 اختباري', v_m_ts + interval '1 day', v_admin_id);

  INSERT INTO public.fee_adjustments (enrollment_id, amount, reason, adjusted_at, created_by, kind)
  VALUES (v_enr_b, 50.00, 'تعديل رسوم C7 اختباري', v_m_ts, v_admin_id, 'manual');

  INSERT INTO public.expenses (category, amount, description, expense_date, performed_by, currency)
  VALUES ('other', 200.00, 'مصروف C7 اختباري', v_m_date, v_admin_id, 'SYP');

  INSERT INTO public.trainer_dues (trainer_id, cohort_id, period_start, period_end, currency, basis_amount, rate_percent, amount, status)
  VALUES (v_admin_id, v_cohort_a, v_m_start, v_m_end, 'SYP', 10000.00, 10.00, 1000.00, 'pending')
  RETURNING id INTO v_due1;

  INSERT INTO public.trainer_dues (trainer_id, cohort_id, period_start, period_end, currency, basis_amount, rate_percent, amount, status)
  VALUES (v_admin_id, v_cohort_b, v_m_start, v_m_end, 'SYP', 10000.00, 10.00, 1000.00, 'pending')
  RETURNING id INTO v_due2;

  INSERT INTO public.payroll_runs (month, status, created_by)
  VALUES (v_m_start, 'draft', v_admin_id)
  RETURNING id INTO v_run;

  INSERT INTO public.payroll_lines (run_id, user_id, currency, base_salary, net_amount)
  VALUES (v_run, v_admin_id, 'SYP', 1000.00, 1000.00);

  INSERT INTO public.staff_advances (user_id, amount, currency, advanced_at, account_id, reason, status, created_by)
  VALUES (v_admin_id, 500.00, 'SYP', v_m_start + 2, v_account, 'سلفة C7 اختبارية', 'open', v_admin_id)
  RETURNING id INTO v_adv;

  INSERT INTO public.staff_bonuses (user_id, amount, currency, bonus_month, reason, approved_by, created_by)
  VALUES (v_admin_id, 100.00, 'SYP', v_m_start, 'مكافأة C7 اختبارية', v_admin_id, v_admin_id);

  INSERT INTO public.lab_clients (name)
  VALUES ('C7 Lab Client')
  RETURNING id INTO v_client;

  INSERT INTO public.lab_invoices (invoice_number, client_id, patient_name, status, currency, subtotal, discount, total_amount, issue_date, created_by)
  VALUES (99001, v_client, 'C7 Patient', 'unpaid', 'SYP', 1000.00, 0.00, 1000.00, v_m_start, v_admin_id)
  RETURNING id INTO v_invoice;

  -- Keep the invoice internally consistent so recalculate_lab_invoice is a
  -- genuine no-op after closing (otherwise it would legitimately change figures).
  INSERT INTO public.lab_invoice_items (invoice_id, service_name, quantity, unit_price)
  VALUES (v_invoice, 'C7 Crown', 1, 1000.00);

  INSERT INTO public.lab_payments (invoice_id, amount, currency, paid_at, method)
  VALUES (v_invoice, 200.00, 'SYP', v_m_ts, 'cash');

  INSERT INTO public.lab_expenses (title, amount, currency, expense_date, payment_method, performed_by)
  VALUES ('C7 Lab Materials', 50.00, 'SYP', v_m_start + 1, 'cash', v_admin_id);

  RAISE NOTICE 'Fixtures ready: closed month=%, account=%, invoice=%', to_char(v_m_start, 'YYYY-MM'), v_account, v_invoice;

  -- --------------------------------------------------------------------------
  -- Test 1: close succeeds (forced) and is audited
  -- --------------------------------------------------------------------------
  v_res := public.close_accounting_period(v_m_start, true);
  ASSERT (v_res ->> 'status') = 'closed',
    format('Test 1 Failed: expected closed, got %s', v_res::text);

  SELECT id INTO v_period_id
  FROM public.accounting_periods
  WHERE period_month = v_m_start AND status = 'closed' AND closed_by = v_admin_id;

  ASSERT v_period_id IS NOT NULL,
    'Test 1 Failed: accounting_periods row missing or not closed by admin';

  SELECT count(*) INTO v_cnt
  FROM public.audit_log
  WHERE table_name = 'accounting_periods' AND operation = 'CLOSE' AND record_id = v_period_id;

  ASSERT v_cnt = 1,
    format('Test 1 Failed: expected exactly one CLOSE audit row, got %s', v_cnt);

  v_pass := v_pass + 1;
  RAISE NOTICE '[Test 1] PASS - close % (forced) written, closed_by=admin, CLOSE audit row present', to_char(v_m_start, 'YYYY-MM');

  -- --------------------------------------------------------------------------
  -- Test 2: payments are frozen in the closed month
  -- --------------------------------------------------------------------------
  v_txt := pg_temp.c7_try(format(
    'INSERT INTO public.payments (enrollment_id, amount, method, paid_at, performed_by, currency)
     VALUES (%L, 100.00, %L, %L, %L, %L)',
    v_enr_b, 'cash', v_m_ts, v_admin_id, 'SYP'));
  ASSERT v_txt LIKE 'P0005|%', format('Test 2a Failed: retro payment insert must be P0005, got %s', v_txt);

  v_txt := pg_temp.c7_try(format(
    'UPDATE public.payments SET notes = %L WHERE id = %L', 'C7 retro note', v_payment));
  ASSERT v_txt LIKE 'P0005|%', format('Test 2b Failed: retro payment update must be P0005, got %s', v_txt);

  v_txt := pg_temp.c7_try(format(
    'DELETE FROM public.payments WHERE id = %L', v_payment2));
  ASSERT v_txt LIKE 'P0005|%', format('Test 2c Failed: retro payment delete must be P0005, got %s', v_txt);

  ASSERT v_txt LIKE '%مغلقة%',
    format('Test 2d Failed: P0005 message must mention a closed period, got %s', v_txt);

  v_pass := v_pass + 1;
  RAISE NOTICE '[Test 2] PASS - payments INSERT/UPDATE/DELETE blocked with P0005 (message=%)', split_part(v_txt, '|', 2);

  -- --------------------------------------------------------------------------
  -- Test 3: other cash surfaces are frozen
  -- --------------------------------------------------------------------------
  v_txt := pg_temp.c7_try(format(
    'INSERT INTO public.payment_refunds (payment_id, amount, reason, refunded_at, created_by)
     VALUES (%L, 10.00, %L, %L, %L)',
    v_payment, 'استرداد C7 إضافي', v_m_ts, v_admin_id));
  ASSERT v_txt LIKE 'P0005|%', format('Test 3a Failed: retro refund must be P0005, got %s', v_txt);

  v_txt := pg_temp.c7_try(format(
    'INSERT INTO public.fee_adjustments (enrollment_id, amount, reason, adjusted_at, created_by)
     VALUES (%L, 10.00, %L, %L, %L)',
    v_enr_b, 'تعديل C7 إضافي', v_m_ts, v_admin_id));
  ASSERT v_txt LIKE 'P0005|%', format('Test 3b Failed: retro fee adjustment must be P0005, got %s', v_txt);

  v_txt := pg_temp.c7_try(format(
    'INSERT INTO public.expenses (category, amount, description, expense_date, performed_by, currency)
     VALUES (%L, 10.00, %L, %L, %L, %L)',
    'other', 'مصروف C7 إضافي', v_m_date, v_admin_id, 'SYP'));
  ASSERT v_txt LIKE 'P0005|%', format('Test 3c Failed: retro expense must be P0005, got %s', v_txt);

  v_txt := pg_temp.c7_try(format(
    'INSERT INTO public.account_transactions (account_id, direction, amount, source_type, occurred_at)
     VALUES (%L, %L, 10.00, %L, %L)',
    v_account, 'inflow', 'adjustment', v_m_ts));
  ASSERT v_txt LIKE 'P0005|%', format('Test 3d Failed: retro ledger row must be P0005, got %s', v_txt);

  v_txt := pg_temp.c7_try(format(
    'INSERT INTO public.enrollment_withdrawals
       (enrollment_id, trainee_id, currency, total_sessions, sessions_charged, session_cost,
        net_due_before, net_due_after, net_paid_before, net_paid_after, discount_revoked,
        due_amount, outcome, reason, withdrawn_at)
     VALUES (%L, %L, %L, 10, 1, 1000.00, 95000.00, 9500.00, 0.00, 0.00, 5000.00,
             9500.00, %L, %L, %L)',
    v_enr_a, v_t1, 'SYP', 'debt', 'انسحاب C7 إضافي', v_m_ts));
  ASSERT v_txt LIKE 'P0005|%', format('Test 3e Failed: retro withdrawal row must be P0005, got %s', v_txt);

  v_pass := v_pass + 1;
  RAISE NOTICE '[Test 3] PASS - refunds, fee adjustments, expenses, ledger rows and withdrawal rows blocked';

  -- --------------------------------------------------------------------------
  -- Test 4: enrollment financial columns are frozen
  -- --------------------------------------------------------------------------
  v_txt := pg_temp.c7_try(format(
    'INSERT INTO public.enrollments (cohort_id, trainee_id, enrolled_at, created_by, status, lifecycle_status, total_due, discount_amount, currency)
     VALUES (%L, %L, %L, %L, %L, %L, 100000.00, 0.00, %L)',
    v_cohort_a, v_t3, v_m_ts, v_admin_id, 'unpaid', 'active', 'SYP'));
  ASSERT v_txt LIKE 'P0005|%', format('Test 4a Failed: retro enrollment insert must be P0005, got %s', v_txt);

  v_txt := pg_temp.c7_try(format(
    'UPDATE public.enrollments SET total_due = 90000.00 WHERE id = %L', v_enr_a));
  ASSERT v_txt LIKE 'P0005|%', format('Test 4b Failed: retro total_due edit must be P0005, got %s', v_txt);

  v_txt := pg_temp.c7_try(format(
    'UPDATE public.enrollments SET discount_amount = 9000.00 WHERE id = %L', v_enr_a));
  ASSERT v_txt LIKE 'P0005|%', format('Test 4c Failed: discount increase on active old enrollment must be P0005, got %s', v_txt);

  v_pass := v_pass + 1;
  RAISE NOTICE '[Test 4] PASS - enrollment insert / total_due / discount increase blocked';

  -- --------------------------------------------------------------------------
  -- Test 5: trainer dues policy
  -- --------------------------------------------------------------------------
  v_txt := pg_temp.c7_try(format(
    'INSERT INTO public.trainer_dues (trainer_id, cohort_id, period_start, period_end, currency, basis_amount, rate_percent, amount, status)
     VALUES (%L, %L, %L, %L, %L, 10000.00, 10.00, 1000.00, %L)',
    v_admin_id, v_cohort_c, v_m_start, v_m_end, 'SYP', 'pending'));
  ASSERT v_txt LIKE 'P0005|%', format('Test 5a Failed: retro due insert must be P0005, got %s', v_txt);

  v_txt := pg_temp.c7_try(format(
    'UPDATE public.trainer_dues SET status = %L WHERE id = %L', 'cancelled', v_due2));
  ASSERT v_txt LIKE 'P0005|%', format('Test 5b Failed: retro due cancel must be P0005, got %s', v_txt);

  v_txt := pg_temp.c7_try(format(
    'UPDATE public.trainer_dues SET status = %L WHERE id = %L', 'paid', v_due1));
  ASSERT v_txt = 'OK',
    format('Test 5c Failed: pending->paid inside a closed month must stay allowed, got %s', v_txt);

  v_pass := v_pass + 1;
  RAISE NOTICE '[Test 5] PASS - dues insert/cancel blocked; pending->paid allowed';

  -- --------------------------------------------------------------------------
  -- Test 6: payroll policy
  -- --------------------------------------------------------------------------
  v_txt := pg_temp.c7_try(format(
    'INSERT INTO public.payroll_lines (run_id, user_id, currency, base_salary, net_amount)
     VALUES (%L, %L, %L, 500.00, 500.00)',
    v_run, v_admin_id, 'SYP'));
  ASSERT v_txt LIKE 'P0005|%', format('Test 6a Failed: retro payroll line insert must be P0005, got %s', v_txt);

  v_txt := pg_temp.c7_try(format(
    'DELETE FROM public.payroll_runs WHERE id = %L', v_run));
  ASSERT v_txt LIKE 'P0005|%', format('Test 6b Failed: retro payroll run delete must be P0005, got %s', v_txt);

  v_txt := pg_temp.c7_try(format(
    'UPDATE public.payroll_runs SET status = %L, approved_by = %L, approved_at = now() WHERE id = %L',
    'approved', v_admin_id, v_run));
  ASSERT v_txt = 'OK',
    format('Test 6c Failed: draft->approved inside a closed month must stay allowed, got %s', v_txt);

  v_txt := pg_temp.c7_try(format(
    'UPDATE public.payroll_runs SET status = %L WHERE id = %L', 'draft', v_run));
  ASSERT v_txt LIKE 'P0005|%',
    format('Test 6d Failed: payroll status regression must be P0005, got %s', v_txt);

  v_pass := v_pass + 1;
  RAISE NOTICE '[Test 6] PASS - payroll lines/delete/regression blocked; forward approval allowed';

  -- --------------------------------------------------------------------------
  -- Test 7: staff advances and bonuses
  -- --------------------------------------------------------------------------
  v_txt := pg_temp.c7_try(format(
    'INSERT INTO public.staff_advances (user_id, amount, currency, advanced_at, account_id, reason, status, created_by)
     VALUES (%L, 100.00, %L, %L, %L, %L, %L, %L)',
    v_admin_id, 'SYP', v_m_start + 1, v_account, 'سلفة C7 إضافية', 'open', v_admin_id));
  ASSERT v_txt LIKE 'P0005|%', format('Test 7a Failed: retro advance insert must be P0005, got %s', v_txt);

  v_txt := pg_temp.c7_try(format(
    'INSERT INTO public.staff_bonuses (user_id, amount, currency, bonus_month, reason, approved_by, created_by)
     VALUES (%L, 100.00, %L, %L, %L, %L, %L)',
    v_admin_id, 'SYP', v_m_start, 'مكافأة C7 إضافية', v_admin_id, v_admin_id));
  ASSERT v_txt LIKE 'P0005|%', format('Test 7b Failed: retro bonus insert must be P0005, got %s', v_txt);

  v_txt := pg_temp.c7_try(format(
    'SELECT public.cancel_staff_advance(%L)', v_adv));
  ASSERT v_txt LIKE 'P0005|%',
    format('Test 7c Failed: cancelling an advance from a closed month must be P0005, got %s', v_txt);

  v_pass := v_pass + 1;
  RAISE NOTICE '[Test 7] PASS - advances/bonuses inserts blocked; old advance cancellation blocked';

  -- --------------------------------------------------------------------------
  -- Test 8: lab operations
  -- --------------------------------------------------------------------------
  v_txt := pg_temp.c7_try(format(
    'INSERT INTO public.lab_payments (invoice_id, amount, currency, paid_at, method)
     VALUES (%L, 10.00, %L, %L, %L)',
    v_invoice, 'SYP', v_m_ts, 'cash'));
  ASSERT v_txt LIKE 'P0005|%', format('Test 8a Failed: retro lab payment must be P0005, got %s', v_txt);

  v_txt := pg_temp.c7_try(format(
    'INSERT INTO public.lab_expenses (title, amount, currency, expense_date, payment_method, performed_by)
     VALUES (%L, 10.00, %L, %L, %L, %L)',
    'C7 Lab Extra', 'SYP', v_m_start + 2, 'cash', v_admin_id));
  ASSERT v_txt LIKE 'P0005|%', format('Test 8b Failed: retro lab expense must be P0005, got %s', v_txt);

  v_txt := pg_temp.c7_try(format(
    'INSERT INTO public.lab_invoices (invoice_number, client_id, patient_name, status, currency, subtotal, discount, total_amount, issue_date, created_by)
     VALUES (99002, %L, %L, %L, %L, 100.00, 0.00, 100.00, %L, %L)',
    v_client, 'C7 Extra Patient', 'unpaid', 'SYP', v_m_start, v_admin_id));
  ASSERT v_txt LIKE 'P0005|%', format('Test 8c Failed: retro lab invoice must be P0005, got %s', v_txt);

  v_txt := pg_temp.c7_try(format(
    'UPDATE public.lab_invoices SET total_amount = total_amount + 100 WHERE id = %L', v_invoice));
  ASSERT v_txt LIKE 'P0005|%', format('Test 8d Failed: retro lab invoice amount edit must be P0005, got %s', v_txt);

  v_txt := pg_temp.c7_try(format(
    'SELECT public.recalculate_lab_invoice(%L)', v_invoice));
  ASSERT v_txt = 'OK',
    format('Test 8e Failed: unchanged lab invoice recalculation must stay allowed, got %s', v_txt);

  v_pass := v_pass + 1;
  RAISE NOTICE '[Test 8] PASS - lab invoice/payment/expense retro writes blocked; same-figure recalc allowed';

  -- --------------------------------------------------------------------------
  -- Test 9: sessions
  -- --------------------------------------------------------------------------
  v_txt := pg_temp.c7_try(format(
    'UPDATE public.sessions SET closed_at = NULL WHERE id = %L', v_session));
  ASSERT v_txt LIKE 'P0005|%', format('Test 9a Failed: retro session reopen must be P0005, got %s', v_txt);

  v_txt := pg_temp.c7_try(format(
    'INSERT INTO public.sessions (cohort_id, session_number, scheduled_at, status, closed_at, is_extra)
     VALUES (%L, 2, %L, %L, %L, false)',
    v_cohort_a, v_m_ts, 'closed', v_m_ts));
  ASSERT v_txt LIKE 'P0005|%', format('Test 9b Failed: retro session insert must be P0005, got %s', v_txt);

  v_pass := v_pass + 1;
  RAISE NOTICE '[Test 9] PASS - session closed_at edits and retro session inserts blocked';

  -- --------------------------------------------------------------------------
  -- Test 10: current open month stays writable
  -- --------------------------------------------------------------------------
  v_txt := pg_temp.c7_try(format(
    'INSERT INTO public.payments (enrollment_id, amount, method, paid_at, performed_by, currency)
     VALUES (%L, 25.00, %L, now(), %L, %L)',
    v_enr_b, 'cash', v_admin_id, 'SYP'));
  ASSERT v_txt = 'OK',
    format('Test 10 Failed: current-month payment must stay writable, got %s', v_txt);

  v_pass := v_pass + 1;
  RAISE NOTICE '[Test 10] PASS - current open month remains writable';

  -- --------------------------------------------------------------------------
  -- Test 11: old-enrollment withdrawal still works; discount changes narrowed
  -- --------------------------------------------------------------------------
  v_txt := pg_temp.c7_try(format(
    'SELECT public.withdraw_enrollment(%L, %L, true)',
    v_enr_a, 'انسحاب C7 اختباري من فوج قديم'));
  ASSERT v_txt = 'OK',
    format('Test 11a Failed: withdrawing an old enrollment must stay allowed, got %s', v_txt);

  SELECT count(*) INTO v_cnt
  FROM public.enrollments
  WHERE id = v_enr_a AND lifecycle_status = 'withdrawn';
  ASSERT v_cnt = 1, 'Test 11a Failed: enrollment was not marked withdrawn';

  v_txt := pg_temp.c7_try(format(
    'UPDATE public.enrollments SET discount_amount = 2000.00 WHERE id = %L', v_enr_a));
  ASSERT v_txt = 'OK',
    format('Test 11b Failed: discount reduction on a withdrawn old enrollment must be allowed, got %s', v_txt);

  v_txt := pg_temp.c7_try(format(
    'UPDATE public.enrollments SET discount_amount = 9000.00 WHERE id = %L', v_enr_a));
  ASSERT v_txt LIKE 'P0005|%',
    format('Test 11c Failed: discount increase on a withdrawn old enrollment must be P0005, got %s', v_txt);

  v_pass := v_pass + 1;
  RAISE NOTICE '[Test 11] PASS - old withdrawal allowed; discount reduction allowed; increase blocked';

  -- --------------------------------------------------------------------------
  -- Test 12: C5 As-Of hash stable across blocked attempts
  -- --------------------------------------------------------------------------
  SELECT md5(COALESCE(jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text)::text, '[]'))
  INTO v_hash1
  FROM public.get_accrual_revenue_report(v_m_end) x;

  v_txt := pg_temp.c7_try(format(
    'INSERT INTO public.payments (enrollment_id, amount, method, paid_at, performed_by, currency)
     VALUES (%L, 30.00, %L, %L, %L, %L)',
    v_enr_b, 'cash', v_m_ts, v_admin_id, 'SYP'));
  ASSERT v_txt LIKE 'P0005|%', format('Test 12a Failed: blocked payment expected, got %s', v_txt);

  SELECT md5(COALESCE(jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text)::text, '[]'))
  INTO v_hash2
  FROM public.get_accrual_revenue_report(v_m_end) x;

  ASSERT v_hash1 = v_hash2,
    format('Test 12 Failed: C5 As-Of hash changed after blocked attempts (%s -> %s)', v_hash1, v_hash2);

  v_pass := v_pass + 1;
  RAISE NOTICE '[Test 12] PASS - C5 As-Of report for % unchanged after blocked retro write (hash=%)', to_char(v_m_end, 'YYYY-MM-DD'), v_hash2;

  -- --------------------------------------------------------------------------
  -- Test 13: close argument guards
  -- --------------------------------------------------------------------------
  v_txt := pg_temp.c7_try(format(
    'SELECT public.close_accounting_period(%L, true)', v_m_start + 5));
  ASSERT v_txt LIKE 'P0006|%', format('Test 13a Failed: non first-of-month must be P0006, got %s', v_txt);

  v_txt := pg_temp.c7_try(format(
    'SELECT public.close_accounting_period(%L, false)', v_cur_start));
  ASSERT v_txt LIKE 'P0006|%', format('Test 13b Failed: current month without force must be P0006, got %s', v_txt);

  v_txt := pg_temp.c7_try(format(
    'SELECT public.close_accounting_period(%L, false)', v_next_start));
  ASSERT v_txt LIKE 'P0006|%', format('Test 13c Failed: future month without force must be P0006, got %s', v_txt);

  v_res := public.close_accounting_period(v_m_start, true);
  ASSERT (v_res ->> 'status') = 'already_closed',
    format('Test 13d Failed: second close must be idempotent, got %s', v_res::text);

  v_pass := v_pass + 1;
  RAISE NOTICE '[Test 13] PASS - close guards: first-of-month/current/future rejected (P0006), re-close idempotent';

  -- --------------------------------------------------------------------------
  -- Test 14: reopen RBAC, reason, effect, and re-close
  -- --------------------------------------------------------------------------
  PERFORM set_config('request.jwt.claim.sub', v_reception_id::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object(
    'sub', v_reception_id, 'role', 'authenticated',
    'user_metadata', json_build_object('role', 'reception'))::text, true);

  v_caught := false;
  BEGIN
    PERFORM public.reopen_accounting_period(v_m_start, 'مسوّغ اختبار الاستقبال');
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    v_caught := true;
  END;
  ASSERT v_caught AND v_state = 'P0001' AND v_msg LIKE '%غير مصرّح%',
    format('Test 14a Failed: reception reopen must be P0001, got state=%s msg=%s', v_state, v_msg);

  RESET ROLE;
  SET LOCAL ROLE anon;
  v_caught := false;
  BEGIN
    PERFORM public.reopen_accounting_period(v_m_start, 'مسوّغ اختبار المجهول');
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    v_caught := true;
  END;
  ASSERT v_caught AND v_state = '42501',
    format('Test 14b Failed: anon reopen must be 42501, got state=%s msg=%s', v_state, v_msg);
  RESET ROLE;

  PERFORM set_config('request.jwt.claim.sub', v_admin_id::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object(
    'sub', v_admin_id, 'role', 'authenticated',
    'user_metadata', json_build_object('role', 'admin'))::text, true);

  v_txt := pg_temp.c7_try(format(
    'SELECT public.reopen_accounting_period(%L, %L)', v_m_start, 'قصير'));
  ASSERT v_txt LIKE 'P0006|%', format('Test 14c Failed: short reopen reason must be P0006, got %s', v_txt);

  v_res := public.reopen_accounting_period(v_m_start, 'مراجعة قيود موردين متأخرة لشهر اختبار C7');
  ASSERT (v_res ->> 'status') = 'reopened' AND (v_res ->> 'reopen_count')::int = 1,
    format('Test 14d Failed: valid reopen must succeed with reopen_count=1, got %s', v_res::text);

  SELECT count(*) INTO v_cnt
  FROM public.audit_log
  WHERE table_name = 'accounting_periods' AND operation = 'REOPEN' AND record_id = v_period_id;
  ASSERT v_cnt = 1, format('Test 14e Failed: expected one REOPEN audit row, got %s', v_cnt);

  v_txt := pg_temp.c7_try(format(
    'INSERT INTO public.payments (enrollment_id, amount, method, paid_at, performed_by, currency)
     VALUES (%L, 40.00, %L, %L, %L, %L)',
    v_enr_b, 'cash', v_m_ts, v_admin_id, 'SYP'));
  ASSERT v_txt = 'OK', format('Test 14f Failed: write after reopen must succeed, got %s', v_txt);

  SELECT md5(COALESCE(jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text)::text, '[]'))
  INTO v_hash3
  FROM public.get_accrual_revenue_report(v_m_end) x;

  ASSERT v_hash3 <> v_hash2,
    'Test 14g Failed: allowed write after reopen must change the C5 As-Of report';

  v_res := public.close_accounting_period(v_m_start, true);
  ASSERT (v_res ->> 'status') = 'reclosed',
    format('Test 14h Failed: re-close must report reclosed, got %s', v_res::text);

  v_txt := pg_temp.c7_try(format(
    'INSERT INTO public.payments (enrollment_id, amount, method, paid_at, performed_by, currency)
     VALUES (%L, 50.00, %L, %L, %L, %L)',
    v_enr_b, 'cash', v_m_ts, v_admin_id, 'SYP'));
  ASSERT v_txt LIKE 'P0005|%', format('Test 14i Failed: retro write after re-close must be P0005, got %s', v_txt);

  SELECT md5(COALESCE(jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text)::text, '[]'))
  INTO v_hash4
  FROM public.get_accrual_revenue_report(v_m_end) x;

  ASSERT v_hash4 = v_hash3,
    format('Test 14j Failed: C5 hash changed after blocked write on re-closed month (%s -> %s)', v_hash3, v_hash4);

  v_pass := v_pass + 1;
  RAISE NOTICE '[Test 14] PASS - reopen RBAC (P0001/42501), short reason P0006, audited reopen, write allowed then blocked after re-close';

  -- --------------------------------------------------------------------------
  -- Test 15: structural invariants
  -- --------------------------------------------------------------------------
  SELECT count(*) INTO v_cnt
  FROM pg_trigger t
  JOIN pg_class c ON c.oid = t.tgrelid
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public'
    AND t.tgname LIKE 'trg_c7_guard_%'
    AND NOT t.tgisinternal;
  ASSERT v_cnt = 17, format('Test 15a Failed: expected 17 C7 guard triggers, got %s', v_cnt);

  FOR v_function IN
    SELECT unnest(ARRAY[
      'public.c7_period_guard()',
      'public.close_accounting_period(date, boolean)',
      'public.reopen_accounting_period(date, text)'
    ])
  LOOP
    SELECT p.prosecdef,
           EXISTS (SELECT 1 FROM unnest(COALESCE(p.proconfig, '{}')) AS c WHERE c LIKE 'search_path=%')
      INTO v_prosecdef, v_pinned
    FROM pg_proc p
    WHERE p.oid = v_function::regprocedure;

    ASSERT v_prosecdef, format('Test 15b Failed: %s must be SECURITY DEFINER', v_function);
    ASSERT v_pinned, format('Test 15c Failed: %s must pin search_path', v_function);
  END LOOP;

  ASSERT has_function_privilege('anon', 'public.close_accounting_period(date, boolean)', 'EXECUTE') = false,
    'Test 15d Failed: anon must not execute close_accounting_period';
  ASSERT has_function_privilege('anon', 'public.reopen_accounting_period(date, text)', 'EXECUTE') = false,
    'Test 15d Failed: anon must not execute reopen_accounting_period';
  ASSERT has_function_privilege('authenticated', 'public.close_accounting_period(date, boolean)', 'EXECUTE') = true,
    'Test 15e Failed: authenticated must execute close_accounting_period (guard then enforces admin)';
  ASSERT has_function_privilege('authenticated', 'public.reopen_accounting_period(date, text)', 'EXECUTE') = true,
    'Test 15e Failed: authenticated must execute reopen_accounting_period';
  ASSERT has_function_privilege('authenticated', 'public.c7_period_guard()', 'EXECUTE') = false,
    'Test 15f Failed: guard function must not be callable by authenticated';

  SELECT c.relrowsecurity INTO v_caught
  FROM pg_class c
  WHERE c.oid = 'public.accounting_periods'::regclass;
  ASSERT v_caught = true, 'Test 15g Failed: accounting_periods must have RLS enabled';

  SELECT count(*) INTO v_cnt
  FROM pg_policies
  WHERE schemaname = 'public' AND tablename = 'accounting_periods' AND policyname = 'c7_admin_select';
  ASSERT v_cnt = 1, 'Test 15g Failed: c7_admin_select policy missing';

  SELECT last_value, is_called INTO v_seq_after, v_seq_called_after
  FROM public.trainee_code_seq;
  ASSERT v_seq_after IS NOT DISTINCT FROM v_seq_before,
    format('Test 15h Failed: trainee_code_seq advanced (%s -> %s)', v_seq_before, v_seq_after);
  ASSERT v_seq_called_after IS NOT DISTINCT FROM v_seq_called_before,
    format('Test 15h Failed: trainee_code_seq is_called changed (%s -> %s)', v_seq_called_before, v_seq_called_after);

  v_pass := v_pass + 1;
  RAISE NOTICE '[Test 15] PASS - 17 triggers, 3 pinned SECURITY DEFINER functions, grants, RLS, trainee_code_seq untouched';

  -- --------------------------------------------------------------------------
  RAISE NOTICE '============================================================';
  RAISE NOTICE '=== ALL % PHASE C7 ACCEPTANCE TESTS PASSED (%)', v_pass, v_pass || '/15';
  RAISE NOTICE 'Safety: enclosed in BEGIN ... ROLLBACK; no fixtures, periods, audit rows or sequence values persist (audit_log_id_seq advances only).';
  RAISE NOTICE '============================================================';
END $$;

ROLLBACK;
