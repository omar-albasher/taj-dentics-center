-- ============================================================================
-- Acceptance Suite: 20261116000005_phase_d5_2_acceptance_proof.sql
-- Description: Independent verification of Phase D5.2 Financial Visibility Hardening
--
-- Asserts:
--   1. c1_is_admin() is SECURITY DEFINER with a pinned search_path.
--   2. dashboard_kpis and the seven _v2 report views are guarded by c1_is_admin().
--   3. Reception: dashboard_kpis returns exactly 1 row with NULL financials;
--      the seven report views return exactly 0 rows.
--   4. Reception keeps operational financials: enrollment summaries, trainee
--      statements, and overdue lists match the trusted context row-for-row.
--   5. Admin: full financials and the same report rows as the trusted context.
--   6. Trusted context (service_role / pg_cron / direct owner): full financials.
--
-- Safety: Fully transactional. Enclosed in BEGIN ... ROLLBACK.
-- ============================================================================

BEGIN;

DO $$
DECLARE
  v_admin_id uuid;
  v_reception_id uuid;
  v_kpi record;
  v_cnt bigint;
  v_view text;
  v_views text[] := ARRAY[
    'profit_loss_report_v2',
    'revenue_by_method_report_v2',
    'course_revenue_sql_summary_v2',
    'discounts_report_v2',
    'debt_aging_report_v2',
    'expenses_by_category_report_v2',
    'cash_vs_accrual_kpis_v2'
  ];
  v_admin_counts bigint[] := '{}';
  v_trusted_counts bigint[] := '{}';
  v_recep_efs bigint;
  v_recep_overdue bigint;
  v_recep_stmt bigint;
BEGIN
  RAISE NOTICE '=== Starting Phase D5.2 Acceptance Tests ===';

  -- --------------------------------------------------------------------------
  -- Test 0: Helper shape and view definitions
  -- --------------------------------------------------------------------------
  ASSERT (
    SELECT p.prosecdef FROM pg_proc p
    WHERE p.oid = 'public.c1_is_admin()'::regprocedure
  ), 'c1_is_admin() must be SECURITY DEFINER';

  ASSERT (
    SELECT p.proconfig FROM pg_proc p
    WHERE p.oid = 'public.c1_is_admin()'::regprocedure
  ) @> ARRAY['search_path=public, pg_temp'],
    'c1_is_admin() must pin search_path = public, pg_temp';

  SELECT count(*) INTO v_cnt
  FROM unnest(ARRAY['dashboard_kpis'] || v_views) AS x(name)
  WHERE pg_get_viewdef(('public.' || x.name)::regclass, true) NOT LIKE '%c1_is_admin%';
  ASSERT v_cnt = 0,
    format('%s financial object(s) are not guarded by c1_is_admin()', v_cnt);

  SELECT count(*) INTO v_cnt
  FROM unnest(v_views) AS x(name)
  WHERE pg_get_viewdef(('public.' || x.name)::regclass, true) LIKE '%c1_is_staff%';
  ASSERT v_cnt = 0,
    format('%s report view(s) still allow the staff-wide guard', v_cnt);

  SELECT count(*) INTO v_cnt
  FROM unnest(ARRAY['dashboard_kpis'] || v_views) AS x(name)
  WHERE pg_get_viewdef(('public.' || x.name)::regclass, true) NOT LIKE '%service_role%';
  ASSERT v_cnt = 0,
    format('%s financial object(s) lost the service_role trust anchor', v_cnt);

  ASSERT has_table_privilege('authenticated', 'public.dashboard_kpis', 'SELECT'),
    'authenticated lost SELECT on dashboard_kpis';
  ASSERT has_table_privilege('authenticated', 'public.profit_loss_report_v2', 'SELECT'),
    'authenticated lost SELECT on profit_loss_report_v2';

  RAISE NOTICE 'Test 0 Passed: helper shape, admin guards, and trust anchors verified.';

  -- --------------------------------------------------------------------------
  -- Fixtures (inside the transaction, rolled back at the end)
  -- --------------------------------------------------------------------------
  INSERT INTO public.users (full_name, email, phone, role, is_active)
  VALUES ('D5.2 Admin', 'd5_2_admin@example.com', '+963999999981', 'admin', true)
  RETURNING id INTO v_admin_id;

  INSERT INTO public.users (full_name, email, phone, role, is_active)
  VALUES ('D5.2 Reception', 'd5_2_reception@example.com', '+963999999982', 'reception', true)
  RETURNING id INTO v_reception_id;

  -- --------------------------------------------------------------------------
  -- Test 1: Reception context
  -- --------------------------------------------------------------------------
  PERFORM set_config('request.jwt.claims',
    json_build_object(
      'sub', v_reception_id,
      'role', 'authenticated',
      'user_metadata', json_build_object('role', 'reception')
    )::text, true);
  SET LOCAL ROLE authenticated;

  ASSERT public.c1_is_admin() IS FALSE,
    'SECURITY LEAK: c1_is_admin() is true for reception';

  SELECT count(*) INTO v_cnt FROM public.dashboard_kpis;
  ASSERT v_cnt = 1, format('dashboard_kpis must return 1 row for reception, got %s', v_cnt);

  SELECT * INTO v_kpi FROM public.dashboard_kpis;
  ASSERT v_kpi.total_trainees IS NOT NULL, 'total_trainees must stay visible for reception';
  ASSERT v_kpi.partial_count IS NULL, 'SECURITY LEAK: partial_count visible to reception';
  ASSERT v_kpi.unpaid_count IS NULL, 'SECURITY LEAK: unpaid_count visible to reception';
  ASSERT v_kpi.net_paid_syp IS NULL, 'SECURITY LEAK: net_paid_syp visible to reception';
  ASSERT v_kpi.total_paid_syp IS NULL, 'SECURITY LEAK: total_paid_syp visible to reception';
  ASSERT v_kpi.total_exp_syp IS NULL, 'SECURITY LEAK: total_exp_syp visible to reception';
  ASSERT v_kpi.total_balance_syp IS NULL, 'SECURITY LEAK: total_balance_syp visible to reception';
  ASSERT v_kpi.net_profit_syp IS NULL, 'SECURITY LEAK: net_profit_syp visible to reception';

  FOREACH v_view IN ARRAY v_views LOOP
    EXECUTE format('SELECT count(*) FROM public.%I', v_view) INTO v_cnt;
    ASSERT v_cnt = 0,
      format('SECURITY LEAK: %s returned %s rows for reception', v_view, v_cnt);
  END LOOP;
  RAISE NOTICE 'Test 1 Passed: reception sees 1 redacted KPI row and 0 rows from all 7 report views.';

  -- Retention: operational financials must still match the trusted context.
  SELECT count(*) INTO v_recep_efs FROM public.enrollment_financial_summary_v2;
  SELECT count(*) INTO v_recep_overdue FROM public.overdue_payments;
  SELECT count(*) INTO v_recep_stmt FROM public.trainee_statement_v;

  -- --------------------------------------------------------------------------
  -- Test 2: Admin context
  -- --------------------------------------------------------------------------
  PERFORM set_config('request.jwt.claims',
    json_build_object(
      'sub', v_admin_id,
      'role', 'authenticated',
      'user_metadata', json_build_object('role', 'admin')
    )::text, true);

  ASSERT public.c1_is_admin() IS TRUE, 'c1_is_admin() must be true for admin';

  SELECT count(*) INTO v_cnt FROM public.dashboard_kpis;
  ASSERT v_cnt = 1, format('dashboard_kpis must return 1 row for admin, got %s', v_cnt);

  SELECT * INTO v_kpi FROM public.dashboard_kpis;
  ASSERT v_kpi.total_trainees IS NOT NULL, 'total_trainees must be visible for admin';
  ASSERT v_kpi.partial_count IS NOT NULL, 'partial_count must be visible for admin';
  ASSERT v_kpi.total_paid_syp IS NOT NULL, 'total_paid_syp must be visible for admin';
  ASSERT v_kpi.net_profit_syp IS NOT NULL, 'net_profit_syp must be visible for admin';

  FOREACH v_view IN ARRAY v_views LOOP
    EXECUTE format('SELECT count(*) FROM public.%I', v_view) INTO v_cnt;
    v_admin_counts := v_admin_counts || v_cnt;
  END LOOP;
  RAISE NOTICE 'Test 2 Passed: admin sees full KPI financials and can read all 7 report views.';

  -- --------------------------------------------------------------------------
  -- Test 3: Trusted backend context (service_role / pg_cron / direct owner)
  -- --------------------------------------------------------------------------
  RESET ROLE;
  PERFORM set_config('request.jwt.claims', '{}', true);

  ASSERT public.c1_is_admin() IS FALSE, 'c1_is_admin() must be false without end-user claims';

  SELECT count(*) INTO v_cnt FROM public.dashboard_kpis;
  ASSERT v_cnt = 1, format('dashboard_kpis must return 1 row for trusted context, got %s', v_cnt);

  SELECT * INTO v_kpi FROM public.dashboard_kpis;
  ASSERT v_kpi.net_profit_syp IS NOT NULL,
    'Trusted context lost full financial visibility (cron/service_role regression)';

  FOREACH v_view IN ARRAY v_views LOOP
    EXECUTE format('SELECT count(*) FROM public.%I', v_view) INTO v_cnt;
    v_trusted_counts := v_trusted_counts || v_cnt;
  END LOOP;

  ASSERT v_admin_counts = v_trusted_counts,
    format('Admin and trusted contexts disagree on report rows: %s vs %s',
           v_admin_counts, v_trusted_counts);

  SELECT count(*) INTO v_cnt FROM public.enrollment_financial_summary_v2;
  ASSERT v_cnt = v_recep_efs,
    'Reception lost enrollment financial rows (operational visibility regression)';

  SELECT count(*) INTO v_cnt FROM public.overdue_payments;
  ASSERT v_cnt = v_recep_overdue,
    'Reception lost overdue payment rows (operational visibility regression)';

  SELECT count(*) INTO v_cnt FROM public.trainee_statement_v;
  ASSERT v_cnt = v_recep_stmt,
    'Reception lost trainee statement rows (operational visibility regression)';

  RAISE NOTICE 'Test 3 Passed: trusted context retains full access; reception retains operational financials.';
  RAISE NOTICE '=== ALL PHASE D5.2 ACCEPTANCE TESTS PASSED SUCCESSFULLY ===';
END;
$$;

ROLLBACK;
