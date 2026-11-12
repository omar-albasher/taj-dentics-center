-- ============================================================================
-- Phase D4.2 — Acceptance Suite: Financial Reports v2
-- ============================================================================
-- BEGIN … ROLLBACK. No permanent data is written.
-- Covers: currency separation, cash vs accrual, withdrawn exclusion,
--         refund subtraction, discount sources, debt aging, Damascus month
--         boundary, and trainee denial.
-- ============================================================================

BEGIN;

DO $$
DECLARE
  v_admin uuid;
  v_trainee uuid;
  v_trainee_user uuid;
  v_course uuid;
  v_cohort uuid;
  v_cohort_b uuid;
  v_enr_a uuid;
  v_enr_b uuid;
  v_pay_a uuid;
  v_pay_b uuid;
  v_today date := (now() AT TIME ZONE 'Asia/Damascus')::date;
  v_n numeric;
  v_n2 numeric;
  v_name text;
  v_views text[] := ARRAY[
    'profit_loss_report_v2',
    'revenue_by_method_report_v2',
    'course_revenue_sql_summary_v2',
    'discounts_report_v2',
    'debt_aging_report_v2',
    'expenses_by_category_report_v2',
    'cash_vs_accrual_kpis_v2'
  ];
BEGIN
  RAISE NOTICE '=== Phase D4.2 Financial Reports v2 Acceptance ===';

  -- 1) Static: views exist, anon denied, authenticated allowed
  FOREACH v_name IN ARRAY v_views LOOP
    IF to_regclass('public.' || v_name) IS NULL THEN
      RAISE EXCEPTION 'TEST 1 FAILED: view % missing', v_name;
    END IF;
    IF has_table_privilege('anon', 'public.' || v_name, 'SELECT') THEN
      RAISE EXCEPTION 'TEST 1 FAILED: anon can SELECT %', v_name;
    END IF;
    IF NOT has_table_privilege('authenticated', 'public.' || v_name, 'SELECT') THEN
      RAISE EXCEPTION 'TEST 1 FAILED: authenticated cannot SELECT %', v_name;
    END IF;
  END LOOP;

  IF to_regclass('public.profit_loss_report') IS NOT NULL
     AND has_table_privilege('anon', 'public.profit_loss_report', 'SELECT') THEN
    RAISE EXCEPTION 'TEST 1 FAILED: legacy profit_loss_report still readable by anon';
  END IF;
  RAISE NOTICE 'Test 1 passed: views exist and anon is denied.';

  -- 2) Context
  SELECT id INTO v_admin FROM public.users
  WHERE role = 'admin' AND is_active = true LIMIT 1;
  IF v_admin IS NULL THEN
    RAISE EXCEPTION 'TEST 2 FAILED: no active admin';
  END IF;

  SELECT t.id, t.user_id INTO v_trainee, v_trainee_user
  FROM public.trainees t
  WHERE t.user_id IS NOT NULL
  LIMIT 1;
  IF v_trainee IS NULL THEN
    RAISE EXCEPTION 'TEST 2 FAILED: no trainee with user_id';
  END IF;

  SELECT course_id INTO v_course FROM public.cohorts LIMIT 1;
  IF v_course IS NULL THEN
    RAISE EXCEPTION 'TEST 2 FAILED: no cohort/course';
  END IF;

  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', v_admin::text, 'role', 'authenticated')::text, true);
  PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);

  -- Baseline snapshots for delta assertions
  DROP TABLE IF EXISTS pg_temp.kpi_before;
  CREATE TEMP TABLE kpi_before AS SELECT * FROM public.cash_vs_accrual_kpis_v2;
  DROP TABLE IF EXISTS pg_temp.course_before;
  CREATE TEMP TABLE course_before AS SELECT * FROM public.course_revenue_sql_summary_v2;
  DROP TABLE IF EXISTS pg_temp.aging_before;
  CREATE TEMP TABLE aging_before AS SELECT * FROM public.debt_aging_report_v2;
  DROP TABLE IF EXISTS pg_temp.method_before;
  CREATE TEMP TABLE method_before AS SELECT * FROM public.revenue_by_method_report_v2;
  DROP TABLE IF EXISTS pg_temp.expenses_before;
  CREATE TEMP TABLE expenses_before AS SELECT * FROM public.expenses_by_category_report_v2;

  INSERT INTO public.cohorts (course_id, name, trainer_id, starts_at, capacity, created_by)
  VALUES (v_course, 'D4.2 fixture ' || gen_random_uuid()::text, v_admin, now(), 999, v_admin)
  RETURNING id INTO v_cohort;

  -- --------------------------------------------------------------------------
  -- Fixture A: active, SYP, total 1000, discount 100, manual discount 50
  --            plan 400 (due -40) / 300 (due -10) / 150 (future)
  -- --------------------------------------------------------------------------
  INSERT INTO public.enrollments (trainee_id, cohort_id, total_due, discount_amount, currency, created_by)
  VALUES (v_trainee, v_cohort, 1000, 100, 'SYP', v_admin)
  RETURNING id INTO v_enr_a;

  INSERT INTO public.fee_adjustments (enrollment_id, amount, reason, kind, created_by)
  VALUES (v_enr_a, -50, 'D4.2 manual discount', 'manual', v_admin);

  DELETE FROM public.installment_schedule WHERE enrollment_id = v_enr_a;

  INSERT INTO public.installment_schedule
    (enrollment_id, installment_number, due_date, amount, currency, created_by)
  VALUES
    (v_enr_a, 1, v_today - 40, 400, 'SYP', v_admin),
    (v_enr_a, 2, v_today - 10, 300, 'SYP', v_admin),
    (v_enr_a, 3, v_today + 30, 150, 'SYP', v_admin);

  -- --------------------------------------------------------------------------
  -- Fixture B: withdrawn, SYP, total 500, writeoff 100, payment 500, refund 200
  --            overdue remainder 100 must NOT appear in aging.
  -- --------------------------------------------------------------------------
  INSERT INTO public.cohorts (course_id, name, trainer_id, starts_at, capacity, created_by)
  VALUES (v_course, 'D4.2 fixture B ' || gen_random_uuid()::text, v_admin, now(), 999, v_admin)
  RETURNING id INTO v_cohort_b;

  INSERT INTO public.enrollments (trainee_id, cohort_id, total_due, discount_amount, currency, created_by)
  VALUES (v_trainee, v_cohort_b, 500, 0, 'SYP', v_admin)
  RETURNING id INTO v_enr_b;

  INSERT INTO public.fee_adjustments (enrollment_id, amount, reason, kind, created_by)
  VALUES (v_enr_b, -100, 'D4.2 writeoff', 'debt_writeoff', v_admin);

  UPDATE public.installment_schedule
  SET due_date = v_today - 20
  WHERE enrollment_id = v_enr_b;

  -- --------------------------------------------------------------------------
  -- Cash movements: A payment at 22:30 UTC on 2027-02-28 = 2027-03-01 Damascus
  -- --------------------------------------------------------------------------
  INSERT INTO public.payments
    (enrollment_id, amount, currency, method, performed_by, paid_at)
  VALUES
    (v_enr_a, 400, 'SYP', 'cash', v_admin, '2027-02-28 22:30:00+00')
  RETURNING id INTO v_pay_a;

  INSERT INTO public.payments
    (enrollment_id, amount, currency, method, performed_by, paid_at)
  VALUES
    (v_enr_b, 500, 'SYP', 'cash', v_admin, '2027-03-10 10:00:00+00')
  RETURNING id INTO v_pay_b;

  INSERT INTO public.payment_refunds (payment_id, amount, reason, refunded_at, created_by)
  VALUES (v_pay_a, 100, 'D4.2 refund A', '2027-03-12 10:00:00+00', v_admin);

  INSERT INTO public.payment_refunds (payment_id, amount, reason, refunded_at, created_by)
  VALUES (v_pay_b, 200, 'D4.2 refund B', '2027-03-13 10:00:00+00', v_admin);

  PERFORM set_config('c1.withdrawal_rpc', 'on', true);
  UPDATE public.enrollments SET lifecycle_status = 'withdrawn' WHERE id = v_enr_b;
  PERFORM set_config('c1.withdrawal_rpc', 'off', true);

  INSERT INTO public.expenses (category, amount, currency, expense_date, description, performed_by)
  VALUES ('other', 100, 'SYP', DATE '2027-03-15', 'D4.2 fixture', v_admin);

  -- --------------------------------------------------------------------------
  -- 3) Profit & Loss: Damascus month boundary + refunds + expenses
  -- --------------------------------------------------------------------------
  SELECT net_profit INTO v_n
  FROM public.profit_loss_report_v2
  WHERE month = DATE '2027-03-01' AND currency = 'SYP';

  IF v_n IS DISTINCT FROM 500 THEN
    RAISE EXCEPTION 'TEST 3 FAILED: March net_profit expected 500, got %', v_n;
  END IF;

  SELECT net_income INTO v_n
  FROM public.profit_loss_report_v2
  WHERE month = DATE '2027-03-01' AND currency = 'SYP';
  IF v_n IS DISTINCT FROM 600 THEN
    RAISE EXCEPTION 'TEST 3 FAILED: March net_income expected 600, got %', v_n;
  END IF;
  RAISE NOTICE 'Test 3 passed: Damascus month boundary, refunds, and expenses.';

  -- --------------------------------------------------------------------------
  -- 4) Discounts: original + manual only; withdrawn and writeoff excluded
  -- --------------------------------------------------------------------------
  SELECT total_discounts INTO v_n
  FROM public.discounts_report_v2 WHERE enrollment_id = v_enr_a;
  IF v_n IS DISTINCT FROM 150 THEN
    RAISE EXCEPTION 'TEST 4 FAILED: A total_discounts expected 150, got %', v_n;
  END IF;

  IF EXISTS (SELECT 1 FROM public.discounts_report_v2 WHERE enrollment_id = v_enr_b) THEN
    RAISE EXCEPTION 'TEST 4 FAILED: withdrawn enrollment appears in discounts';
  END IF;
  RAISE NOTICE 'Test 4 passed: discount sources and withdrawn exclusion.';

  -- --------------------------------------------------------------------------
  -- 5) Debt aging: active remaining only; refunds already netted in allocations
  --    1-30 = A installment 2 (300); 31-90 = A installment 1 (100)
  -- --------------------------------------------------------------------------
  SELECT COALESCE(k.total_overdue_balance, 0) - COALESCE(b.total_overdue_balance, 0)
  INTO v_n
  FROM public.debt_aging_report_v2 k
  LEFT JOIN aging_before b
    ON b.currency = k.currency AND b.aging_bucket = k.aging_bucket
  WHERE k.currency = 'SYP' AND k.aging_bucket = '1-30';

  IF v_n IS DISTINCT FROM 300 THEN
    RAISE EXCEPTION 'TEST 5 FAILED: 1-30 delta expected 300, got %', v_n;
  END IF;

  SELECT COALESCE(k.total_overdue_balance, 0) - COALESCE(b.total_overdue_balance, 0)
  INTO v_n
  FROM public.debt_aging_report_v2 k
  LEFT JOIN aging_before b
    ON b.currency = k.currency AND b.aging_bucket = k.aging_bucket
  WHERE k.currency = 'SYP' AND k.aging_bucket = '31-90';

  IF v_n IS DISTINCT FROM 100 THEN
    RAISE EXCEPTION 'TEST 5 FAILED: 31-90 delta expected 100, got %', v_n;
  END IF;
  RAISE NOTICE 'Test 5 passed: aging excludes withdrawn and nets refunds.';

  -- --------------------------------------------------------------------------
  -- 6) Course revenue: cash includes withdrawn; accrual only active
  -- --------------------------------------------------------------------------
  SELECT COALESCE(k.gross_collected,0)-COALESCE(b.gross_collected,0) INTO v_n
  FROM public.course_revenue_sql_summary_v2 k LEFT JOIN course_before b
    ON b.course_id=k.course_id AND b.currency=k.currency
  WHERE k.course_id=v_course AND k.currency='SYP';
  IF v_n IS DISTINCT FROM 900 THEN RAISE EXCEPTION 'TEST 6 FAILED: course gross expected 900, got %', v_n; END IF;

  SELECT COALESCE(k.refunds,0)-COALESCE(b.refunds,0) INTO v_n
  FROM public.course_revenue_sql_summary_v2 k LEFT JOIN course_before b
    ON b.course_id=k.course_id AND b.currency=k.currency
  WHERE k.course_id=v_course AND k.currency='SYP';
  IF v_n IS DISTINCT FROM 300 THEN RAISE EXCEPTION 'TEST 6 FAILED: course refunds expected 300, got %', v_n; END IF;

  SELECT COALESCE(k.net_collected,0)-COALESCE(b.net_collected,0) INTO v_n
  FROM public.course_revenue_sql_summary_v2 k LEFT JOIN course_before b
    ON b.course_id=k.course_id AND b.currency=k.currency
  WHERE k.course_id=v_course AND k.currency='SYP';
  IF v_n IS DISTINCT FROM 600 THEN RAISE EXCEPTION 'TEST 6 FAILED: course net expected 600, got %', v_n; END IF;

  SELECT COALESCE(k.active_expected_net_due,0)-COALESCE(b.active_expected_net_due,0) INTO v_n
  FROM public.course_revenue_sql_summary_v2 k LEFT JOIN course_before b
    ON b.course_id=k.course_id AND b.currency=k.currency
  WHERE k.course_id=v_course AND k.currency='SYP';
  IF v_n IS DISTINCT FROM 850 THEN RAISE EXCEPTION 'TEST 6 FAILED: course expected due 850, got %', v_n; END IF;

  SELECT COALESCE(k.active_outstanding,0)-COALESCE(b.active_outstanding,0) INTO v_n
  FROM public.course_revenue_sql_summary_v2 k LEFT JOIN course_before b
    ON b.course_id=k.course_id AND b.currency=k.currency
  WHERE k.course_id=v_course AND k.currency='SYP';
  IF v_n IS DISTINCT FROM 550 THEN RAISE EXCEPTION 'TEST 6 FAILED: course outstanding 550, got %', v_n; END IF;

  SELECT COALESCE(k.active_enrollments,0)-COALESCE(b.active_enrollments,0) INTO v_n
  FROM public.course_revenue_sql_summary_v2 k LEFT JOIN course_before b
    ON b.course_id=k.course_id AND b.currency=k.currency
  WHERE k.course_id=v_course AND k.currency='SYP';
  IF v_n IS DISTINCT FROM 1 THEN RAISE EXCEPTION 'TEST 6 FAILED: active count 1, got %', v_n; END IF;

  SELECT COALESCE(k.withdrawn_enrollments,0)-COALESCE(b.withdrawn_enrollments,0) INTO v_n
  FROM public.course_revenue_sql_summary_v2 k LEFT JOIN course_before b
    ON b.course_id=k.course_id AND b.currency=k.currency
  WHERE k.course_id=v_course AND k.currency='SYP';
  IF v_n IS DISTINCT FROM 1 THEN RAISE EXCEPTION 'TEST 6 FAILED: withdrawn count 1, got %', v_n; END IF;
  RAISE NOTICE 'Test 6 passed: course cash includes withdrawn, accrual excludes it.';

  -- --------------------------------------------------------------------------
  -- 7) Method report: refunds subtracted per method
  -- --------------------------------------------------------------------------
  SELECT COALESCE(k.net_collected,0)-COALESCE(b.net_collected,0) INTO v_n
  FROM public.revenue_by_method_report_v2 k LEFT JOIN method_before b
    ON b.method = k.method AND b.currency = k.currency
  WHERE k.method = 'cash' AND k.currency = 'SYP';
  IF v_n IS DISTINCT FROM 600 THEN
    RAISE EXCEPTION 'TEST 7 FAILED: cash/SYP net expected 600, got %', v_n;
  END IF;
  RAISE NOTICE 'Test 7 passed: refunds deducted per method.';

  -- --------------------------------------------------------------------------
  -- 8) KPIs: cash all, accrual active, withdrawn separated
  -- --------------------------------------------------------------------------
  SELECT COALESCE(k.cash_collected,0)-COALESCE(b.cash_collected,0) INTO v_n
  FROM public.cash_vs_accrual_kpis_v2 k LEFT JOIN kpi_before b USING (currency)
  WHERE k.currency='SYP';
  IF v_n IS DISTINCT FROM 600 THEN RAISE EXCEPTION 'TEST 8 FAILED: cash_collected 600, got %', v_n; END IF;

  SELECT COALESCE(k.active_expected_net_due,0)-COALESCE(b.active_expected_net_due,0) INTO v_n
  FROM public.cash_vs_accrual_kpis_v2 k LEFT JOIN kpi_before b USING (currency)
  WHERE k.currency='SYP';
  IF v_n IS DISTINCT FROM 850 THEN RAISE EXCEPTION 'TEST 8 FAILED: active expected 850, got %', v_n; END IF;

  SELECT COALESCE(k.active_outstanding,0)-COALESCE(b.active_outstanding,0) INTO v_n
  FROM public.cash_vs_accrual_kpis_v2 k LEFT JOIN kpi_before b USING (currency)
  WHERE k.currency='SYP';
  IF v_n IS DISTINCT FROM 550 THEN RAISE EXCEPTION 'TEST 8 FAILED: active outstanding 550, got %', v_n; END IF;

  SELECT COALESCE(k.withdrawn_net_paid,0)-COALESCE(b.withdrawn_net_paid,0) INTO v_n
  FROM public.cash_vs_accrual_kpis_v2 k LEFT JOIN kpi_before b USING (currency)
  WHERE k.currency='SYP';
  IF v_n IS DISTINCT FROM 300 THEN RAISE EXCEPTION 'TEST 8 FAILED: withdrawn net paid 300, got %', v_n; END IF;

  SELECT COALESCE(k.all_outstanding,0)-COALESCE(b.all_outstanding,0) INTO v_n
  FROM public.cash_vs_accrual_kpis_v2 k LEFT JOIN kpi_before b USING (currency)
  WHERE k.currency='SYP';
  IF v_n IS DISTINCT FROM 650 THEN RAISE EXCEPTION 'TEST 8 FAILED: all outstanding 650, got %', v_n; END IF;
  RAISE NOTICE 'Test 8 passed: KPI cash/accrual separation and withdrawn isolation.';

  -- --------------------------------------------------------------------------
  -- 9) Expenses category v2
  -- --------------------------------------------------------------------------
  SELECT COALESCE(k.total_spent, 0) - COALESCE(b.total_spent, 0) INTO v_n
  FROM public.expenses_by_category_report_v2 k
  LEFT JOIN expenses_before b
    ON b.category = k.category AND b.currency = k.currency
  WHERE k.category = 'other' AND k.currency = 'SYP';

  IF v_n IS DISTINCT FROM 100 THEN
    RAISE EXCEPTION 'TEST 9 FAILED: expense delta expected 100, got %', v_n;
  END IF;
  RAISE NOTICE 'Test 9 passed: expenses by category.';

  -- --------------------------------------------------------------------------
  -- 10) Trainee denial across all v2 views
  -- --------------------------------------------------------------------------
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', v_trainee_user::text, 'role', 'authenticated')::text, true);
  PERFORM set_config('request.jwt.claim.sub', v_trainee_user::text, true);

  FOREACH v_name IN ARRAY v_views LOOP
    EXECUTE format('SELECT count(*) FROM public.%I', v_name) INTO v_n;
    IF v_n <> 0 THEN
      RAISE EXCEPTION 'TEST 10 FAILED: trainee sees % rows in %', v_n, v_name;
    END IF;
  END LOOP;
  RAISE NOTICE 'Test 10 passed: trainee denied on all v2 reports.';

  RAISE NOTICE '=== SUCCESS: ALL D4.2 REPORT TESTS PASSED ===';
END $$;

ROLLBACK;
