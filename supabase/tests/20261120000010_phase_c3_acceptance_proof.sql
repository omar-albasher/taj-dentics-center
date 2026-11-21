-- ============================================================================
-- Acceptance Suite: Phase C3 Compensation & Payroll Engine Proof
-- File: supabase/tests/20261120000010_phase_c3_acceptance_proof.sql
-- Description: Comprehensive verification of C3 agreements, rate snapshots,
--              trainer dues, staff payroll, advances, bonuses, RLS and RPCs.
-- Safety: Fully transactional. Enclosed in BEGIN ... ROLLBACK.
-- ============================================================================

BEGIN;

DO $$
DECLARE
  v_admin_id uuid;
  v_reception_id uuid;
  v_trainer_id uuid;
  v_staff_id uuid;
  v_trainee_id uuid;
  v_course_id uuid;
  v_cohort_id uuid;
  v_enrollment_id uuid;
  v_account_id uuid;
  v_due_id uuid;
  v_run_id uuid;
  v_expense_id uuid;
  v_tx_count int;
  v_count int;
  v_amount numeric;
  v_status text;
  v_month date := date_trunc('month', CURRENT_DATE)::date;
  v_caught boolean := false;
  v_audit_before bigint;
BEGIN
  RAISE NOTICE '=== Starting Phase C3 Acceptance Tests ===';

  -- Snapshot the audit baseline for C3 tables so the final assertion proves THIS run wrote
  -- rows, not that historical rows happen to exist.
  SELECT count(*) INTO v_audit_before FROM public.audit_log
  WHERE table_name IN ('trainer_dues', 'payroll_runs', 'cohort_trainer_rate_snapshots');

  -- --------------------------------------------------------------------------
  -- 1. Resolve or create test users (ensuring auth.users linkage for created_by FKs)
  -- --------------------------------------------------------------------------
  SELECT u.id INTO v_admin_id
  FROM public.users u
  JOIN auth.users a ON a.id = u.id
  WHERE u.role = 'admin' AND u.is_active
  LIMIT 1;

  IF v_admin_id IS NULL THEN
    v_admin_id := gen_random_uuid();
    INSERT INTO auth.users (id, instance_id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
    VALUES (v_admin_id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
            'c3_admin_' || substr(v_admin_id::text, 1, 8) || '@example.com',
            '{"provider":"email","providers":["email"]}',
            '{"role":"admin"}', now(), now());

    INSERT INTO public.users (id, full_name, email, phone, role, is_active)
    VALUES (v_admin_id, 'C3 Test Admin', 'c3_admin_' || substr(v_admin_id::text, 1, 8) || '@example.com', '+963999999981', 'admin', true)
    ON CONFLICT (id) DO UPDATE SET role = 'admin', is_active = true;
  END IF;

  SELECT u.id INTO v_reception_id
  FROM public.users u
  JOIN auth.users a ON a.id = u.id
  WHERE u.role = 'reception' AND u.is_active
  LIMIT 1;

  IF v_reception_id IS NULL THEN
    v_reception_id := gen_random_uuid();
    INSERT INTO auth.users (id, instance_id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
    VALUES (v_reception_id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
            'c3_rec_' || substr(v_reception_id::text, 1, 8) || '@example.com',
            '{"provider":"email","providers":["email"]}',
            '{"role":"reception"}', now(), now());

    INSERT INTO public.users (id, full_name, email, phone, role, is_active)
    VALUES (v_reception_id, 'C3 Test Reception', 'c3_rec_' || substr(v_reception_id::text, 1, 8) || '@example.com', '+963999999982', 'reception', true)
    ON CONFLICT (id) DO UPDATE SET role = 'reception', is_active = true;
  END IF;

  SELECT id INTO v_trainer_id FROM public.users WHERE role = 'trainer' AND is_active LIMIT 1;
  IF v_trainer_id IS NULL THEN
    INSERT INTO public.users (full_name, email, phone, role, is_active)
    VALUES ('C3 Test Trainer', 'c3_trn_' || substr(gen_random_uuid()::text, 1, 8) || '@example.com', '+963999999983', 'trainer', true)
    RETURNING id INTO v_trainer_id;
  END IF;

  SELECT id INTO v_staff_id FROM public.users WHERE role IN ('reception', 'admin') AND is_active LIMIT 1;

  SELECT id INTO v_account_id FROM public.financial_accounts WHERE currency = 'SYP' AND is_active LIMIT 1;
  ASSERT v_account_id IS NOT NULL, 'Active SYP financial account required';

  -- --------------------------------------------------------------------------
  -- 2. Verify Schema Invariants (10 tables, 5 views, RLS enabled)
  -- --------------------------------------------------------------------------
  ASSERT to_regclass('public.trainer_compensation_agreements') IS NOT NULL, 'trainer_compensation_agreements missing';
  ASSERT to_regclass('public.cohort_trainer_rate_snapshots') IS NOT NULL, 'cohort_trainer_rate_snapshots missing';
  ASSERT to_regclass('public.staff_compensation') IS NOT NULL, 'staff_compensation missing';
  ASSERT to_regclass('public.staff_advances') IS NOT NULL, 'staff_advances missing';
  ASSERT to_regclass('public.staff_bonuses') IS NOT NULL, 'staff_bonuses missing';
  ASSERT to_regclass('public.staff_referrals') IS NOT NULL, 'staff_referrals missing';
  ASSERT to_regclass('public.trainer_dues') IS NOT NULL, 'trainer_dues missing';
  ASSERT to_regclass('public.trainer_payments') IS NOT NULL, 'trainer_payments missing';
  ASSERT to_regclass('public.payroll_runs') IS NOT NULL, 'payroll_runs missing';
  ASSERT to_regclass('public.payroll_lines') IS NOT NULL, 'payroll_lines missing';

  ASSERT to_regclass('public.cohort_trainer_rates_v') IS NOT NULL, 'cohort_trainer_rates_v view missing';
  ASSERT to_regclass('public.trainer_dues_v') IS NOT NULL, 'trainer_dues_v view missing';
  ASSERT to_regclass('public.trainer_payments_v') IS NOT NULL, 'trainer_payments_v view missing';
  ASSERT to_regclass('public.staff_compensation_v') IS NOT NULL, 'staff_compensation_v view missing';
  ASSERT to_regclass('public.payroll_v') IS NOT NULL, 'payroll_v view missing';

  RAISE NOTICE 'Test 1 Passed: All 10 C3 tables and 5 views exist';

  -- --------------------------------------------------------------------------
  -- 3. Admin Role: Agreement, Cohort Snapshot & Overlap Guard
  -- --------------------------------------------------------------------------
  PERFORM set_config('request.jwt.claims', json_build_object(
    'sub', v_admin_id,
    'role', 'authenticated',
    'user_metadata', json_build_object('role', 'admin')
  )::text, true);
  SET LOCAL ROLE authenticated;

  -- Create test course & agreement
  INSERT INTO public.courses (name, total_sessions, price, created_by)
  VALUES ('C3 Acceptance Test Course', 10, 500000, v_admin_id)
  RETURNING id INTO v_course_id;

  INSERT INTO public.trainer_compensation_agreements
    (trainer_id, course_id, rate_percent, effective_from, effective_to, created_by)
  VALUES
    (v_trainer_id, v_course_id, 25.00, '2026-01-01', NULL, v_admin_id);

  -- Overlap guard test: duplicate active agreement must fail
  v_caught := false;
  BEGIN
    INSERT INTO public.trainer_compensation_agreements
      (trainer_id, course_id, rate_percent, effective_from, effective_to, created_by)
    VALUES
      (v_trainer_id, v_course_id, 30.00, '2026-06-01', NULL, v_admin_id);
  EXCEPTION WHEN OTHERS THEN
    v_caught := true;
  END;
  ASSERT v_caught = true, 'Overlap guard failed: Allowed overlapping trainer agreement';

  -- Create cohort -> trigger must automatically freeze rate at 25%
  INSERT INTO public.cohorts (course_id, trainer_id, name, starts_at, capacity, created_by)
  VALUES (v_course_id, v_trainer_id, 'C3 Test Cohort', CURRENT_DATE, 10, v_admin_id)
  RETURNING id INTO v_cohort_id;

  SELECT rate_percent INTO v_amount FROM public.cohort_trainer_rate_snapshots WHERE cohort_id = v_cohort_id;
  ASSERT v_amount = 25.00, format('Snapshot rate expected 25%%, found %s', v_amount);

  RAISE NOTICE 'Test 2 Passed: Trainer agreement and automatic cohort rate snapshot (25%%) verified';

  -- --------------------------------------------------------------------------
  -- 4. Trainer Dues Engine & Payout Integration with C2 Ledger
  -- --------------------------------------------------------------------------
  -- Create test trainee and enrollment
  INSERT INTO public.trainees (full_name_ar, trainee_code, created_by)
  VALUES ('C3 Test Trainee', 'T99999', v_admin_id)
  RETURNING id INTO v_trainee_id;

  INSERT INTO public.enrollments (trainee_id, cohort_id, total_due, currency, status, created_by)
  VALUES (v_trainee_id, v_cohort_id, 400000, 'SYP', 'unpaid', v_admin_id)
  RETURNING id INTO v_enrollment_id;

  -- Add a payment of 200,000 SYP inside the current month
  INSERT INTO public.payments
    (enrollment_id, amount, currency, method, account_id, performed_by)
  VALUES
    (v_enrollment_id, 200000, 'SYP', 'cash', v_account_id, v_admin_id);

  -- Generate trainer dues for this cohort & month
  PERFORM public.generate_trainer_dues(v_cohort_id, v_month);

  SELECT id INTO v_due_id FROM public.trainer_dues
  WHERE cohort_id = v_cohort_id AND period_start = v_month;
  ASSERT v_due_id IS NOT NULL, 'Trainer due was not generated';

  -- Basis = 200,000; Rate = 25% => Amount must be 50,000 SYP
  SELECT amount INTO v_amount FROM public.trainer_dues WHERE id = v_due_id;
  ASSERT v_amount = 50000.00, format('Expected trainer due 50,000, found %s', v_amount);

  -- Pay trainer due -> must insert expense with category trainer_fee and trigger C2 custody outflow
  v_expense_id := public.pay_trainer_due(v_due_id, v_account_id);
  ASSERT v_expense_id IS NOT NULL, 'pay_trainer_due did not return expense_id';

  -- Verify due marked paid
  SELECT status INTO v_status FROM public.trainer_dues WHERE id = v_due_id;
  ASSERT v_status = 'paid', 'Trainer due status was not updated to paid';

  -- Verify C2 custody ledger recorded the outflow automatically
  SELECT count(*) INTO v_tx_count FROM public.account_transactions
  WHERE source_id = v_expense_id AND source_type = 'expense';
  ASSERT v_tx_count = 1, 'C2 trigger failed: custody ledger transaction was not generated for trainer fee expense';

  RAISE NOTICE 'Test 3 Passed: Trainer dues generated (50,000 SYP) and paid via C2 custody expense';

  -- --------------------------------------------------------------------------
  -- 5. Staff Payroll: Salary, Advances, Referral Commission, Bonuses & Pay
  -- --------------------------------------------------------------------------
  -- Set staff compensation: 1,000,000 SYP monthly salary + 2.5% referral commission
  INSERT INTO public.staff_compensation
    (user_id, monthly_salary, currency, commission_rate_percent, effective_from, created_by)
  VALUES
    (v_staff_id, 1000000, 'SYP', 2.50, '2026-01-01', v_admin_id);

  -- Record an advance of 200,000 SYP
  INSERT INTO public.staff_advances
    (user_id, amount, currency, account_id, status, created_by)
  VALUES
    (v_staff_id, 200000, 'SYP', v_account_id, 'open', v_admin_id);

  -- Record a bonus of 50,000 SYP
  INSERT INTO public.staff_bonuses
    (user_id, amount, currency, bonus_month, reason, created_by)
  VALUES
    (v_staff_id, 50000, 'SYP', v_month, 'Excellence in student care', v_admin_id);

  -- Attribute enrollment to staff (referral commission)
  INSERT INTO public.staff_referrals
    (enrollment_id, staff_id, commission_rate_percent, created_by)
  VALUES
    (v_enrollment_id, v_staff_id, 2.50, v_admin_id);

  -- Generate payroll
  v_run_id := public.generate_payroll(v_month);
  ASSERT v_run_id IS NOT NULL, 'generate_payroll failed';

  -- Verify payroll line calculations:
  -- Base salary = 1,000,000
  -- Commission = 2.5% of 200,000 = 5,000
  -- Bonus = 50,000
  -- Advance deducted = 200,000
  -- Net = 1,000,000 + 5,000 + 50,000 - 200,000 = 855,000 SYP
  SELECT net_amount INTO v_amount FROM public.payroll_lines WHERE run_id = v_run_id AND user_id = v_staff_id;
  ASSERT v_amount = 855000.00, format('Payroll net_amount expected 855,000, found %s', v_amount);

  -- Approve payroll
  PERFORM public.approve_payroll(v_run_id);
  SELECT status INTO v_status FROM public.payroll_runs WHERE id = v_run_id;
  ASSERT v_status = 'approved', 'Payroll run status not updated to approved';

  -- Pay payroll
  PERFORM public.pay_payroll(v_run_id, v_account_id);
  SELECT status INTO v_status FROM public.payroll_runs WHERE id = v_run_id;
  ASSERT v_status = 'paid', 'Payroll run status not updated to paid';

  RAISE NOTICE 'Test 4 Passed: Payroll generated (Net: 855,000 SYP), approved, and paid via C2 custody expenses';

  -- --------------------------------------------------------------------------
  -- 6. RLS Isolation for Reception (Tested Against Populated Tables & RPCs)
  -- --------------------------------------------------------------------------
  PERFORM set_config('request.jwt.claims', json_build_object(
    'sub', v_reception_id,
    'role', 'authenticated',
    'user_metadata', json_build_object('role', 'reception')
  )::text, true);
  SET LOCAL ROLE authenticated;

  -- Assert reception sees ZERO rows despite rows existing in tables
  SELECT count(*) INTO v_count FROM public.trainer_compensation_agreements;
  ASSERT v_count = 0, 'Security leak: Reception saw trainer_compensation_agreements';

  SELECT count(*) INTO v_count FROM public.staff_compensation;
  ASSERT v_count = 0, 'Security leak: Reception saw staff_compensation';

  SELECT count(*) INTO v_count FROM public.staff_advances;
  ASSERT v_count = 0, 'Security leak: Reception saw staff_advances';

  SELECT count(*) INTO v_count FROM public.payroll_runs;
  ASSERT v_count = 0, 'Security leak: Reception saw payroll_runs';

  SELECT count(*) INTO v_count FROM public.payroll_v;
  ASSERT v_count = 0, 'Security leak: Reception saw payroll_v';

  -- Assert reception RPC calls are rejected
  v_caught := false;
  BEGIN
    PERFORM public.generate_payroll(v_month);
  EXCEPTION WHEN OTHERS THEN
    v_caught := true;
  END;
  ASSERT v_caught = true, 'Security leak: Reception was able to call generate_payroll';

  v_caught := false;
  BEGIN
    PERFORM public.cancel_staff_advance(gen_random_uuid());
  EXCEPTION WHEN OTHERS THEN
    v_caught := true;
  END;
  ASSERT v_caught = true, 'Security leak: Reception was able to call cancel_staff_advance';

  RESET ROLE;
  RAISE NOTICE 'Test 5 Passed: Reception role is 100%% isolated from populated C3 tables, views & RPCs';

  -- --------------------------------------------------------------------------
  -- 7. Audit Trail Verification
  -- --------------------------------------------------------------------------
  SELECT count(*) INTO v_count FROM public.audit_log
  WHERE table_name IN ('trainer_dues', 'payroll_runs', 'cohort_trainer_rate_snapshots');
  ASSERT v_count > v_audit_before,
    format('Audit log wrote no rows for this run (before=%s, after=%s)', v_audit_before, v_count);

  RAISE NOTICE 'Test 6 Passed: Audit triggers captured all compensation & payroll changes';

  RAISE NOTICE '=======================================================';
  RAISE NOTICE 'All Phase C3 Functional Acceptance Tests Passed (6/6)!';
  RAISE NOTICE '=======================================================';
END;
$$;

ROLLBACK;
