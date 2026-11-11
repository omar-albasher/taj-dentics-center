-- ═══════════════════════════════════════════════════════════════════════
-- Phase D2 — SQL Acceptance Tests
-- File: 20261110000001_phase_d2_acceptance.sql
--
-- HOW TO RUN (Supabase Dashboard → SQL Editor, as postgres):
--   1. Apply 20261110000001_phase_d2_enrollment_lifecycle.sql first.
--   2. Paste this whole file and run it once.
--   3. Expected: NOTICE "ALL D2 TESTS PASSED". The script ends with ROLLBACK,
--      so no fixture data survives (it is safe on production data).
--
-- The script uses existing active trainees (no fixture users) and creates its
-- own courses/cohorts/enrollments/sessions/payments. It requires at least two
-- active trainees, and the first chosen trainee must have no unspent referral
-- credits (otherwise A5 would auto-apply them on enrollment insert).
-- ═══════════════════════════════════════════════════════════════════════
BEGIN;

-- ----------------------------------------------------------------------------
-- Context + assertion helpers
-- ----------------------------------------------------------------------------
CREATE TEMP TABLE _ctx (
  k TEXT PRIMARY KEY,
  v UUID
) ON COMMIT DROP;

DO $$
DECLARE
  v_admin UUID;
  v_t1 UUID;
  v_t2 UUID;
BEGIN
  SELECT u.id INTO v_admin
  FROM public.users u
  WHERE u.role::text = 'admin' AND u.is_active = true
  ORDER BY u.id
  LIMIT 1;

  IF v_admin IS NULL THEN
    RAISE EXCEPTION 'PREFLIGHT: no active admin user found';
  END IF;

  SELECT t.id INTO v_t1
  FROM public.trainees t
  JOIN public.users u ON u.id = t.user_id
  WHERE u.is_active = true
    AND NOT EXISTS (
      SELECT 1 FROM public.referrals r
      WHERE r.referrer_trainee_id = t.id
        AND r.status = 'available'
    )
  ORDER BY t.id
  LIMIT 1;

  IF v_t1 IS NULL THEN
    RAISE EXCEPTION 'PREFLIGHT: no active trainee without available referral credits';
  END IF;

  SELECT t.id INTO v_t2
  FROM public.trainees t
  JOIN public.users u ON u.id = t.user_id
  WHERE u.is_active = true
    AND t.id <> v_t1
  ORDER BY t.id
  LIMIT 1;

  IF v_t2 IS NULL THEN
    RAISE EXCEPTION 'PREFLIGHT: need a second active trainee';
  END IF;

  INSERT INTO _ctx (k, v) VALUES
    ('admin', v_admin),
    ('t1', v_t1),
    ('t2', v_t2);

  RAISE NOTICE 'PREFLIGHT OK: admin=%, trainee1=%, trainee2=%', v_admin, v_t1, v_t2;
END $$;

CREATE FUNCTION pg_temp.assert_num(p_actual NUMERIC, p_expected NUMERIC, p_msg TEXT)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  IF p_actual IS NULL OR abs(p_actual - p_expected) > 0.005 THEN
    RAISE EXCEPTION 'ASSERT FAILED [%]: actual=% expected=%',
      p_msg, p_actual, p_expected;
  END IF;
END;
$$;

CREATE FUNCTION pg_temp.assert_true(p_cond BOOLEAN, p_msg TEXT)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  IF NOT COALESCE(p_cond, false) THEN
    RAISE EXCEPTION 'ASSERT FAILED [%]', p_msg;
  END IF;
END;
$$;

CREATE FUNCTION pg_temp.expect_error(p_sql TEXT, p_like TEXT, p_msg TEXT)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  EXECUTE p_sql;
  RAISE EXCEPTION 'ASSERT FAILED [%]: expected error matching "%" but none raised',
    p_msg, p_like;
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM LIKE '%ASSERT FAILED%' THEN
    RAISE;
  END IF;
  IF SQLERRM NOT LIKE p_like THEN
    RAISE EXCEPTION 'ASSERT FAILED [%]: wrong error: %', p_msg, SQLERRM;
  END IF;
END;
$$;

CREATE FUNCTION pg_temp.new_course(p_total INTEGER, p_price NUMERIC)
RETURNS UUID
LANGUAGE plpgsql
AS $$
DECLARE
  v_id UUID;
BEGIN
  INSERT INTO public.courses (name, total_sessions, price, description, created_by)
  VALUES (
    'D2 test ' || gen_random_uuid()::text,
    p_total,
    p_price,
    'D2 acceptance fixture',
    (SELECT v FROM _ctx WHERE k = 'admin')
  )
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

CREATE FUNCTION pg_temp.new_cohort(p_course UUID, p_capacity INTEGER)
RETURNS UUID
LANGUAGE plpgsql
AS $$
DECLARE
  v_id UUID;
BEGIN
  INSERT INTO public.cohorts (
    course_id, name, trainer_id, starts_at, capacity, created_by
  ) VALUES (
    p_course,
    'D2 cohort ' || gen_random_uuid()::text,
    (SELECT v FROM _ctx WHERE k = 'admin'),
    now() - interval '10 days',
    p_capacity,
    (SELECT v FROM _ctx WHERE k = 'admin')
  )
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

CREATE FUNCTION pg_temp.new_enrollment(
  p_trainee UUID,
  p_cohort UUID,
  p_fee NUMERIC,
  p_discount NUMERIC DEFAULT 0
)
RETURNS UUID
LANGUAGE plpgsql
AS $$
DECLARE
  v_id UUID;
BEGIN
  INSERT INTO public.enrollments (
    trainee_id, cohort_id, total_due, discount_amount, currency, created_by
  ) VALUES (
    p_trainee, p_cohort, p_fee, p_discount, 'SYP',
    (SELECT v FROM _ctx WHERE k = 'admin')
  )
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

CREATE FUNCTION pg_temp.add_delivered_sessions(p_cohort UUID, p_count INTEGER)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  INSERT INTO public.sessions (
    cohort_id, session_number, scheduled_at, duration_minutes,
    status, is_extra, opened_at, closed_at
  )
  SELECT
    p_cohort,
    g,
    now() - (p_count - g + 1) * interval '1 day',
    60,
    'closed',
    false,
    now() - (p_count - g + 1) * interval '1 day',
    now() - (p_count - g + 1) * interval '1 day' + interval '60 minutes'
  FROM generate_series(1, p_count) g;
END;
$$;

CREATE FUNCTION pg_temp.add_payment(p_enrollment UUID, p_amount NUMERIC)
RETURNS UUID
LANGUAGE plpgsql
AS $$
DECLARE
  v_id UUID;
BEGIN
  INSERT INTO public.payments (
    enrollment_id, amount, currency, method, performed_by, paid_at
  ) VALUES (
    p_enrollment, p_amount, 'SYP', 'cash',
    (SELECT v FROM _ctx WHERE k = 'admin'), now() - interval '2 days'
  )
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

CREATE FUNCTION pg_temp.plan_sum(p_enrollment UUID)
RETURNS NUMERIC
LANGUAGE sql
AS $$
  SELECT COALESCE(sum(s.amount), 0)
  FROM public.installment_schedule s
  WHERE s.enrollment_id = p_enrollment;
$$;

CREATE FUNCTION pg_temp.alloc_sum(p_enrollment UUID)
RETURNS NUMERIC
LANGUAGE sql
AS $$
  SELECT COALESCE(sum(a.amount), 0)
  FROM public.payment_allocations a
  JOIN public.payments p ON p.id = a.payment_id
  WHERE p.enrollment_id = p_enrollment;
$$;

CREATE FUNCTION pg_temp.paid_sum(p_enrollment UUID)
RETURNS NUMERIC
LANGUAGE sql
AS $$
  SELECT COALESCE(sum(p.amount), 0)
  FROM public.payments p
  WHERE p.enrollment_id = p_enrollment;
$$;

CREATE FUNCTION pg_temp.refund_sum(p_enrollment UUID)
RETURNS NUMERIC
LANGUAGE sql
AS $$
  SELECT COALESCE(sum(r.amount), 0)
  FROM public.payment_refunds r
  JOIN public.payments p ON p.id = r.payment_id
  WHERE p.enrollment_id = p_enrollment;
$$;

-- ----------------------------------------------------------------------------
-- CASE 0 — lifecycle defaults + guard against direct mutation
-- ----------------------------------------------------------------------------
DO $$
DECLARE
  v_course UUID;
  v_cohort UUID;
  v_enr UUID;
  v_lifecycle TEXT;
BEGIN
  v_course := pg_temp.new_course(4, 400);
  v_cohort := pg_temp.new_cohort(v_course, NULL);
  v_enr := pg_temp.new_enrollment((SELECT v FROM _ctx WHERE k = 't1'), v_cohort, 400, 0);

  SELECT e.lifecycle_status INTO v_lifecycle
  FROM public.enrollments e WHERE e.id = v_enr;

  PERFORM pg_temp.assert_true(v_lifecycle = 'active', 'new enrollment lifecycle active');
  PERFORM pg_temp.assert_num(pg_temp.plan_sum(v_enr), 400, 'default plan equals net due');

  PERFORM set_config('c1.withdrawal_rpc', 'off', true);
  PERFORM pg_temp.expect_error(
    format('UPDATE public.enrollments SET lifecycle_status = %L WHERE id = %L',
           'withdrawn', v_enr),
    '%إجراء الانسحاب%',
    'direct lifecycle mutation blocked'
  );

  SELECT e.lifecycle_status INTO v_lifecycle
  FROM public.enrollments e WHERE e.id = v_enr;
  PERFORM pg_temp.assert_true(v_lifecycle = 'active', 'lifecycle stayed active after blocked update');

  -- Allow the guard so the CHECK constraint itself is exercised.
  PERFORM set_config('c1.withdrawal_rpc', 'on', true);
  PERFORM pg_temp.expect_error(
    format('UPDATE public.enrollments SET lifecycle_status = %L WHERE id = %L', 'bogus', v_enr),
    '%enrollments_lifecycle_status_check%',
    'invalid lifecycle value rejected'
  );
  PERFORM set_config('c1.withdrawal_rpc', 'off', true);

  RAISE NOTICE 'CASE 0 PASSED: lifecycle defaults and guard';
END $$;

-- ----------------------------------------------------------------------------
-- CASE 1 — surplus refund + seat release + overdue exclusion
-- ----------------------------------------------------------------------------
DO $$
DECLARE
  v_course UUID;
  v_cohort UUID;
  v_enr UUID;
  v_prev JSONB;
  v_res JSONB;
  v_paid NUMERIC;
  v_balance NUMERIC;
BEGIN
  v_course := pg_temp.new_course(4, 400);
  v_cohort := pg_temp.new_cohort(v_course, NULL);
  v_enr := pg_temp.new_enrollment((SELECT v FROM _ctx WHERE k = 't1'), v_cohort, 400, 0);

  PERFORM pg_temp.add_delivered_sessions(v_cohort, 2);
  PERFORM pg_temp.add_payment(v_enr, 400);

  INSERT INTO _ctx (k, v) VALUES ('case1', v_enr);

  v_prev := public.get_withdrawal_preview(v_enr, NULL);
  PERFORM pg_temp.assert_true((v_prev->>'can_withdraw')::boolean, 'case1 can withdraw');
  PERFORM pg_temp.assert_num((v_prev->>'sessions_charged')::numeric, 2, 'case1 delivered sessions');
  PERFORM pg_temp.assert_num((v_prev->>'due_amount')::numeric, 200, 'case1 pro-rata due');
  PERFORM pg_temp.assert_num((v_prev->>'refundable')::numeric, 200, 'case1 refundable preview');
  PERFORM pg_temp.assert_num((v_prev->>'settlement_amount')::numeric, -200, 'case1 settlement preview');

  v_res := public.withdraw_enrollment(v_enr, 'انسحاب اختباري — حالة الفائض');

  PERFORM pg_temp.assert_true(v_res->>'outcome' = 'refund', 'case1 outcome refund');
  PERFORM pg_temp.assert_num((v_res->>'refund_amount')::numeric, 200, 'case1 refund amount');
  PERFORM pg_temp.assert_num((v_res->>'due_amount')::numeric, 200, 'case1 due amount');

  PERFORM pg_temp.assert_num(pg_temp.plan_sum(v_enr), 200, 'case1 plan settled to due');
  PERFORM pg_temp.assert_num(pg_temp.alloc_sum(v_enr), 200, 'case1 allocations settled');
  PERFORM pg_temp.assert_num(pg_temp.refund_sum(v_enr), 200, 'case1 refund rows total');

  SELECT v.current_balance INTO v_balance
  FROM public.enrollment_financial_summary_v2 v
  WHERE v.enrollment_id = v_enr;

  PERFORM pg_temp.assert_num(v_balance, 0, 'case1 balance zero');

  PERFORM pg_temp.assert_num(
    (SELECT count(*)::numeric FROM public.overdue_payments WHERE enrollment_id = v_enr),
    0, 'case1 excluded from overdue_payments'
  );
  PERFORM pg_temp.assert_num(
    (SELECT count(*)::numeric FROM public.overdue_installments_v WHERE enrollment_id = v_enr),
    0, 'case1 excluded from overdue_installments_v'
  );
  PERFORM pg_temp.assert_num(
    public.cohort_active_enrollment_count(v_cohort)::numeric,
    0, 'case1 seat released'
  );

  PERFORM pg_temp.assert_true(
    EXISTS (
      SELECT 1 FROM public.enrollment_withdrawals w
      WHERE w.enrollment_id = v_enr
        AND w.outcome = 'refund'
        AND w.sessions_charged = 2
        AND w.total_sessions = 4
        AND w.refund_amount = 200
        AND w.settlement_delta = -200
    ),
    'case1 audit row'
  );

  PERFORM pg_temp.expect_error(
    format('SELECT public.withdraw_enrollment(%L, %L)', v_enr, 'محاولة ثانية'),
    '%ENROLLMENT_NOT_ACTIVE%',
    'case1 double withdrawal rejected'
  );

  RAISE NOTICE 'CASE 1 PASSED: refund, plan reconciliation, seat release, views';
END $$;

-- ----------------------------------------------------------------------------
-- CASE 2 — outstanding debt without write-off
-- ----------------------------------------------------------------------------
DO $$
DECLARE
  v_course UUID;
  v_cohort UUID;
  v_enr UUID;
  v_prev JSONB;
  v_res JSONB;
BEGIN
  v_course := pg_temp.new_course(4, 400);
  v_cohort := pg_temp.new_cohort(v_course, NULL);
  v_enr := pg_temp.new_enrollment((SELECT v FROM _ctx WHERE k = 't1'), v_cohort, 400, 0);

  PERFORM pg_temp.add_delivered_sessions(v_cohort, 1);
  PERFORM pg_temp.add_payment(v_enr, 50);

  INSERT INTO _ctx (k, v) VALUES ('case2', v_enr);

  v_prev := public.get_withdrawal_preview(v_enr, NULL);
  PERFORM pg_temp.assert_num((v_prev->>'due_amount')::numeric, 100, 'case2 due');
  PERFORM pg_temp.assert_num((v_prev->>'debt_amount')::numeric, 50, 'case2 debt preview');
  PERFORM pg_temp.assert_num((v_prev->>'refundable')::numeric, 0, 'case2 no refund');

  v_res := public.withdraw_enrollment(v_enr, 'انسحاب اختباري — حالة الدين', false);

  PERFORM pg_temp.assert_true(v_res->>'outcome' = 'debt', 'case2 outcome debt');
  PERFORM pg_temp.assert_num((v_res->>'writeoff_amount')::numeric, 0, 'case2 no writeoff');

  PERFORM pg_temp.assert_num(pg_temp.plan_sum(v_enr), 100, 'case2 plan equals due');
  PERFORM pg_temp.assert_num(pg_temp.alloc_sum(v_enr), 50, 'case2 allocations unchanged');
  PERFORM pg_temp.assert_num(pg_temp.refund_sum(v_enr), 0, 'case2 no refunds');

  PERFORM pg_temp.assert_num(
    (SELECT v.current_balance FROM public.enrollment_financial_summary_v2 v
     WHERE v.enrollment_id = v_enr),
    50, 'case2 balance remains 50'
  );

  PERFORM pg_temp.assert_num(
    (SELECT count(*)::numeric FROM public.overdue_payments WHERE enrollment_id = v_enr),
    0, 'case2 withdrawn excluded from overdue_payments despite balance'
  );

  PERFORM pg_temp.assert_true(
    EXISTS (
      SELECT 1 FROM public.fee_adjustments fa
      WHERE fa.enrollment_id = v_enr
        AND fa.kind = 'withdrawal_settlement'
        AND fa.amount = -300
    ),
    'case2 settlement adjustment kind/amount'
  );

  RAISE NOTICE 'CASE 2 PASSED: debt preserved, excluded from operational overdue';
END $$;

-- ----------------------------------------------------------------------------
-- CASE 3 — outstanding debt with admin write-off
-- ----------------------------------------------------------------------------
DO $$
DECLARE
  v_course UUID;
  v_cohort UUID;
  v_enr UUID;
  v_res JSONB;
BEGIN
  v_course := pg_temp.new_course(4, 400);
  v_cohort := pg_temp.new_cohort(v_course, NULL);
  v_enr := pg_temp.new_enrollment((SELECT v FROM _ctx WHERE k = 't1'), v_cohort, 400, 0);

  PERFORM pg_temp.add_delivered_sessions(v_cohort, 1);
  PERFORM pg_temp.add_payment(v_enr, 50);

  INSERT INTO _ctx (k, v) VALUES ('case3', v_enr);

  v_res := public.withdraw_enrollment(v_enr, 'انسحاب اختباري — شطب الدين', true);

  PERFORM pg_temp.assert_true(v_res->>'outcome' = 'writeoff', 'case3 outcome writeoff');
  PERFORM pg_temp.assert_num((v_res->>'writeoff_amount')::numeric, 50, 'case3 writeoff amount');

  PERFORM pg_temp.assert_num(pg_temp.plan_sum(v_enr), 50, 'case3 plan equals paid after writeoff');
  PERFORM pg_temp.assert_num(
    (SELECT v.current_balance FROM public.enrollment_financial_summary_v2 v
     WHERE v.enrollment_id = v_enr),
    0, 'case3 balance zero after writeoff'
  );
  PERFORM pg_temp.assert_true(
    (SELECT v.payment_status = 'complete' FROM public.enrollment_financial_summary_v2 v
     WHERE v.enrollment_id = v_enr),
    'case3 status complete after writeoff'
  );
  PERFORM pg_temp.assert_true(
    EXISTS (
      SELECT 1 FROM public.fee_adjustments fa
      WHERE fa.enrollment_id = v_enr
        AND fa.kind = 'debt_writeoff'
        AND fa.amount = -50
    ),
    'case3 writeoff adjustment'
  );

  RAISE NOTICE 'CASE 3 PASSED: write-off';
END $$;

-- ----------------------------------------------------------------------------
-- CASE 4 — referral revocation before pro-rata
--   fee 400, discount 100 (50 manual + 50 applied credit), paid 350, N=2/T=4
--   net_before 300 → revocation +50 → net_after 350 → due 175 → refund 175
-- ----------------------------------------------------------------------------
DO $$
DECLARE
  v_course UUID;
  v_cohort UUID;
  v_enr UUID;
  v_prev JSONB;
  v_res JSONB;
  v_referral UUID;
BEGIN
  v_course := pg_temp.new_course(4, 400);
  v_cohort := pg_temp.new_cohort(v_course, NULL);
  v_enr := pg_temp.new_enrollment((SELECT v FROM _ctx WHERE k = 't1'), v_cohort, 400, 100);
  PERFORM pg_temp.add_delivered_sessions(v_cohort, 2);
  PERFORM pg_temp.add_payment(v_enr, 350);

  INSERT INTO public.referrals (
    referrer_trainee_id, referee_trainee_id, code_used, course_id,
    enrollment_id, discount_amount, currency, status,
    applied_enrollment_id, applied_at
  ) VALUES (
    (SELECT v FROM _ctx WHERE k = 't2'),
    (SELECT v FROM _ctx WHERE k = 't1'),
    'D2-SIM',
    v_course,
    v_enr,
    50,
    'SYP',
    'applied',
    v_enr,
    now()
  )
  RETURNING id INTO v_referral;

  INSERT INTO _ctx (k, v) VALUES ('case4', v_enr);

  v_prev := public.get_withdrawal_preview(v_enr, NULL);
  PERFORM pg_temp.assert_num((v_prev->>'discount_revoked')::numeric, 50, 'case4 revoked preview');
  PERFORM pg_temp.assert_num((v_prev->>'net_due_before')::numeric, 300, 'case4 net before');
  PERFORM pg_temp.assert_num((v_prev->>'net_due_after')::numeric, 350, 'case4 net after revocation');
  PERFORM pg_temp.assert_num((v_prev->>'due_amount')::numeric, 175, 'case4 due');
  PERFORM pg_temp.assert_num((v_prev->>'refundable')::numeric, 175, 'case4 refundable');

  v_res := public.withdraw_enrollment(v_enr, 'انسحاب اختباري — إحالة');

  PERFORM pg_temp.assert_num((v_res->>'discount_revoked')::numeric, 50, 'case4 revoked result');
  PERFORM pg_temp.assert_num((v_res->>'refund_amount')::numeric, 175, 'case4 refund');
  PERFORM pg_temp.assert_num((v_res->>'settlement_amount')::numeric, -175, 'case4 settlement');
  PERFORM pg_temp.assert_num(pg_temp.plan_sum(v_enr), 175, 'case4 plan settled');

  PERFORM pg_temp.assert_true(
    (SELECT e.discount_amount = 50 FROM public.enrollments e WHERE e.id = v_enr),
    'case4 manual discount kept, referral discount revoked'
  );
  PERFORM pg_temp.assert_true(
    (SELECT r.status = 'available' AND r.applied_enrollment_id IS NULL
     FROM public.referrals r WHERE r.id = v_referral),
    'case4 credit restored to referrer'
  );
  PERFORM pg_temp.assert_num(
    (SELECT v.current_balance FROM public.enrollment_financial_summary_v2 v
     WHERE v.enrollment_id = v_enr),
    0, 'case4 balance zero'
  );

  RAISE NOTICE 'CASE 4 PASSED: referral revocation + refund';
END $$;

-- ----------------------------------------------------------------------------
-- CASE 5 — rounding 1000 / 3 and override
-- ----------------------------------------------------------------------------
DO $$
DECLARE
  v_course UUID;
  v_cohort UUID;
  v_enr UUID;
  v_p1 JSONB;
  v_p2 JSONB;
  v_p3 JSONB;
  v_res JSONB;
BEGIN
  v_course := pg_temp.new_course(3, 1000);
  v_cohort := pg_temp.new_cohort(v_course, NULL);
  v_enr := pg_temp.new_enrollment((SELECT v FROM _ctx WHERE k = 't1'), v_cohort, 1000, 0);

  INSERT INTO _ctx (k, v) VALUES ('case5', v_enr);

  v_p1 := public.get_withdrawal_preview(v_enr, 1);
  v_p2 := public.get_withdrawal_preview(v_enr, 2);
  v_p3 := public.get_withdrawal_preview(v_enr, 3);

  PERFORM pg_temp.assert_num((v_p1->>'due_amount')::numeric, 333.33, 'case5 N=1 rounds to 333.33');
  PERFORM pg_temp.assert_num((v_p2->>'due_amount')::numeric, 666.67, 'case5 N=2 rounds to 666.67');
  PERFORM pg_temp.assert_num((v_p3->>'due_amount')::numeric, 1000.00, 'case5 N=3 full fee');

  v_res := public.withdraw_enrollment(v_enr, 'انسحاب اختباري — تدقيق التقريب', false, 2);

  PERFORM pg_temp.assert_true((v_res->>'sessions_overridden')::boolean, 'case5 override flagged');
  PERFORM pg_temp.assert_num((v_res->>'due_amount')::numeric, 666.67, 'case5 due 666.67');
  PERFORM pg_temp.assert_num((v_res->>'settlement_amount')::numeric, -333.33, 'case5 settlement');
  PERFORM pg_temp.assert_num(pg_temp.plan_sum(v_enr), 666.67, 'case5 plan settled to 666.67');

  PERFORM pg_temp.assert_true(
    EXISTS (
      SELECT 1 FROM public.enrollment_withdrawals w
      WHERE w.enrollment_id = v_enr
        AND w.sessions_overridden = true
        AND w.sessions_charged = 2
    ),
    'case5 audit override'
  );

  RAISE NOTICE 'CASE 5 PASSED: rounding and override';
END $$;

-- ----------------------------------------------------------------------------
-- CASE 6 — total_sessions guard
-- ----------------------------------------------------------------------------
DO $$
DECLARE
  v_course UUID;
  v_cohort UUID;
  v_enr UUID;
BEGIN
  v_course := pg_temp.new_course(4, 400);
  v_cohort := pg_temp.new_cohort(v_course, NULL);
  v_enr := pg_temp.new_enrollment((SELECT v FROM _ctx WHERE k = 't1'), v_cohort, 400, 0);

  BEGIN
    UPDATE public.courses SET total_sessions = 0 WHERE id = v_course;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'CASE 6 SKIPPED: live schema forbids total_sessions = 0 (%)', SQLERRM;
    RETURN;
  END;

  PERFORM pg_temp.expect_error(
    format('SELECT public.get_withdrawal_preview(%L, NULL)', v_enr),
    '%لا يمكن احتساب تسوية الانسحاب: يجب تحديد إجمالي جلسات الكورس أولاً%',
    'case6 preview blocks missing total_sessions'
  );

  PERFORM pg_temp.expect_error(
    format('SELECT public.withdraw_enrollment(%L, %L)', v_enr, 'انسحاب'),
    '%لا يمكن احتساب تسوية الانسحاب: يجب تحديد إجمالي جلسات الكورس أولاً%',
    'case6 withdraw blocks missing total_sessions'
  );

  PERFORM pg_temp.assert_true(
    (SELECT lifecycle_status = 'active' FROM public.enrollments WHERE id = v_enr),
    'case6 enrollment untouched after rejection'
  );

  RAISE NOTICE 'CASE 6 PASSED: strict total_sessions guard';
END $$;

-- ----------------------------------------------------------------------------
-- CASE 7 — admin-only gate (authenticated non-admin)
-- ----------------------------------------------------------------------------
DO $$
DECLARE
  v_course UUID;
  v_cohort UUID;
  v_enr UUID;
  v_claims_before TEXT;
  v_sub_before TEXT;
  v_role_before TEXT;
BEGIN
  v_course := pg_temp.new_course(4, 400);
  v_cohort := pg_temp.new_cohort(v_course, NULL);
  v_enr := pg_temp.new_enrollment((SELECT v FROM _ctx WHERE k = 't1'), v_cohort, 400, 0);

  -- Remember the editor's identity so later cases keep running as a trusted
  -- (no-JWT) connection instead of the fake authenticated user.
  v_claims_before := current_setting('request.jwt.claims', true);
  v_sub_before := current_setting('request.jwt.claim.sub', true);
  v_role_before := current_setting('request.jwt.claim.role', true);

  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', gen_random_uuid()::text, 'role', 'authenticated')::text,
    true
  );
  -- Older auth.uid() implementations read the singular claim key.
  PERFORM set_config('request.jwt.claim.sub', (current_setting('request.jwt.claims')::jsonb ->> 'sub'), true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
  EXECUTE 'SET LOCAL ROLE authenticated';

  BEGIN
    PERFORM public.get_withdrawal_preview(v_enr, NULL);
    RAISE EXCEPTION 'ASSERT FAILED [case7]: non-admin preview allowed';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE '%ASSERT FAILED%' THEN
      EXECUTE 'RESET ROLE';
      RAISE;
    END IF;
    IF SQLERRM NOT LIKE '%ADMIN_ONLY%' THEN
      EXECUTE 'RESET ROLE';
      RAISE EXCEPTION 'ASSERT FAILED [case7 preview]: unexpected error %', SQLERRM;
    END IF;
  END;

  BEGIN
    PERFORM public.withdraw_enrollment(v_enr, 'محاولة غير مصرح بها');
    RAISE EXCEPTION 'ASSERT FAILED [case7]: non-admin withdrawal allowed';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE '%ASSERT FAILED%' THEN
      EXECUTE 'RESET ROLE';
      RAISE;
    END IF;
    IF SQLERRM NOT LIKE '%ADMIN_ONLY%' THEN
      EXECUTE 'RESET ROLE';
      RAISE EXCEPTION 'ASSERT FAILED [case7 withdraw]: unexpected error %', SQLERRM;
    END IF;
  END;

  EXECUTE 'RESET ROLE';

  -- Restore the original (unset) JWT so CASE 8-10 keep trusted access.
  PERFORM set_config('request.jwt.claims', COALESCE(v_claims_before, ''), true);
  PERFORM set_config('request.jwt.claim.sub', COALESCE(v_sub_before, ''), true);
  PERFORM set_config('request.jwt.claim.role', COALESCE(v_role_before, ''), true);

  PERFORM pg_temp.assert_true(
    (SELECT lifecycle_status = 'active' FROM public.enrollments WHERE id = v_enr),
    'case7 enrollment untouched'
  );

  RAISE NOTICE 'CASE 7 PASSED: admin-only enforcement';
END $$;

-- ----------------------------------------------------------------------------
-- CASE 8 — session reminders skip withdrawn, still reach active
-- ----------------------------------------------------------------------------
DO $$
DECLARE
  v_case1_cohort UUID;
  v_sess_off UUID;
  v_course UUID;
  v_cohort UUID;
  v_enr UUID;
  v_sess_on UUID;
  v_t2_user UUID;
BEGIN
  SELECT c.id INTO v_case1_cohort
  FROM public.enrollments e
  JOIN public.cohorts c ON c.id = e.cohort_id
  WHERE e.id = (SELECT v FROM _ctx WHERE k = 'case1');

  INSERT INTO public.sessions (
    cohort_id, session_number, scheduled_at, duration_minutes, status, is_extra
  ) VALUES (
    v_case1_cohort, 3, now() + interval '60 minutes', 60, 'scheduled', false
  )
  RETURNING id INTO v_sess_off;

  PERFORM public.enqueue_session_reminders();

  PERFORM pg_temp.assert_num(
    (SELECT count(*)::numeric FROM public.notification_outbox o
     WHERE o.type = 'session_reminder'
       AND o.data->>'session_id' = v_sess_off::text),
    0, 'case8 withdrawn trainee gets no session reminder'
  );

  v_course := pg_temp.new_course(2, 200);
  v_cohort := pg_temp.new_cohort(v_course, NULL);
  v_enr := pg_temp.new_enrollment((SELECT v FROM _ctx WHERE k = 't2'), v_cohort, 200, 0);

  INSERT INTO public.sessions (
    cohort_id, session_number, scheduled_at, duration_minutes, status, is_extra
  ) VALUES (
    v_cohort, 1, now() + interval '60 minutes', 60, 'scheduled', false
  )
  RETURNING id INTO v_sess_on;

  SELECT t.user_id INTO v_t2_user
  FROM public.trainees t
  WHERE t.id = (SELECT v FROM _ctx WHERE k = 't2');

  PERFORM public.enqueue_session_reminders();

  PERFORM pg_temp.assert_num(
    (SELECT count(*)::numeric FROM public.notification_outbox o
     WHERE o.type = 'session_reminder'
       AND o.user_id = v_t2_user
       AND o.data->>'session_id' = v_sess_on::text),
    1, 'case8 active trainee still receives reminder'
  );

  RAISE NOTICE 'CASE 8 PASSED: reminder filter by lifecycle';
END $$;

-- ----------------------------------------------------------------------------
-- CASE 9 — capacity 1 + waitlist notification on withdrawal
-- ----------------------------------------------------------------------------
DO $$
DECLARE
  v_course UUID;
  v_cohort UUID;
  v_enr UUID;
  v_t2 UUID;
  v_waitlist UUID;
  v_status TEXT;
  v_res JSONB;
BEGIN
  v_t2 := (SELECT v FROM _ctx WHERE k = 't2');
  v_course := pg_temp.new_course(2, 100);
  v_cohort := pg_temp.new_cohort(v_course, 1);
  v_enr := pg_temp.new_enrollment((SELECT v FROM _ctx WHERE k = 't1'), v_cohort, 100, 0);

  PERFORM pg_temp.assert_num(
    public.cohort_active_enrollment_count(v_cohort)::numeric, 1, 'case9 seat occupied'
  );

  INSERT INTO public.course_waitlist (cohort_id, trainee_id, status, created_by)
  VALUES (v_cohort, v_t2, 'waiting', (SELECT v FROM _ctx WHERE k = 'admin'))
  RETURNING id INTO v_waitlist;

  v_res := public.withdraw_enrollment(v_enr, 'انسحاب اختباري — تحرير مقعد', false, 0);

  PERFORM pg_temp.assert_true(v_res->>'outcome' = 'settled', 'case9 no due at zero sessions');
  PERFORM pg_temp.assert_num(
    public.cohort_active_enrollment_count(v_cohort)::numeric, 0, 'case9 seat released'
  );

  SELECT w.status INTO v_status
  FROM public.course_waitlist w WHERE w.id = v_waitlist;

  PERFORM pg_temp.assert_true(v_status = 'notified', 'case9 next waitlist notified');

  PERFORM pg_temp.assert_true(
    EXISTS (
      SELECT 1 FROM public.notification_outbox o
      WHERE o.type = 'waitlist_available'
        AND o.data->>'waitlist_id' = v_waitlist::text
    ),
    'case9 waitlist outbox row'
  );

  -- Promotion remains a manual admin decision: no enrollment was created for t2.
  PERFORM pg_temp.assert_num(
    (SELECT count(*)::numeric FROM public.enrollments e
     WHERE e.cohort_id = v_cohort AND e.trainee_id = v_t2),
    0, 'case9 no automatic promotion'
  );

  PERFORM pg_temp.assert_num(
    (SELECT g.available_seats::numeric
     FROM public.get_cohorts_seat_status(v_course) g
     WHERE g.cohort_id = v_cohort),
    1, 'case9 seat status reflects free seat'
  );

  RAISE NOTICE 'CASE 9 PASSED: seat release + waitlist notification, manual promotion';
END $$;

-- ----------------------------------------------------------------------------
-- CASE 10 — dashboard KPI and view consistency
-- ----------------------------------------------------------------------------
DO $$
DECLARE
  v_kpi RECORD;
  v_expected INTEGER;
BEGIN
  SELECT * INTO v_kpi FROM public.dashboard_kpis;

  SELECT count(*) INTO v_expected
  FROM public.enrollment_financial_summary_v2 v
  WHERE v.payment_status IN ('partial', 'unpaid')
    AND v.lifecycle_status <> 'withdrawn';

  PERFORM pg_temp.assert_num(
    (v_kpi.partial_count + v_kpi.unpaid_count)::numeric,
    v_expected::numeric,
    'case10 KPI excludes withdrawn from partial/unpaid counts'
  );

  PERFORM pg_temp.assert_num(
    (SELECT count(*)::numeric
     FROM public.enrollment_financial_summary_v2 v
     WHERE v.enrollment_id IN (SELECT v FROM _ctx WHERE k LIKE 'case%')
       AND v.lifecycle_status <> 'withdrawn'),
    0, 'case10 all fixtures withdrawn'
  );

  RAISE NOTICE 'CASE 10 PASSED: KPI/view lifecycle consistency';
END $$;

-- ----------------------------------------------------------------------------
-- DONE
-- ----------------------------------------------------------------------------
DO $$
BEGIN
  RAISE NOTICE 'ALL D2 TESTS PASSED';
END $$;

ROLLBACK;
