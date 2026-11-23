-- ============================================================================
-- Acceptance Suite: Phase C4 Financial Statements Proof
-- File: supabase/tests/20261121000002_phase_c4_acceptance_proof.sql
-- Description: Verifies the four C4 report functions against live data:
--              admin-only guard, P&L arithmetic, expense breakdown, cash flow
--              identity, transfer neutrality, lab memorandum item and
--              event-vs-ledger integrity.
-- Safety: Fully transactional. Enclosed in BEGIN ... ROLLBACK.
-- Requirements: migration 20261121000001 applied first.
-- ============================================================================

BEGIN;

DO $$
DECLARE
  v_admin_id uuid;
  v_reception_id uuid;

  v_from date := date '2000-01-01';
  v_to date := date '2100-01-01';
  v_today date := current_date;

  -- Owner-computed reference values (before any role switch)
  v_pay_syp numeric;
  v_pay_usd numeric;
  v_ref_syp numeric;
  v_ref_usd numeric;
  v_exp_syp numeric;
  v_exp_usd numeric;
  v_memo_syp numeric;
  v_memo_usd numeric;
  v_ledger_net numeric;
  v_balances_sum numeric;

  -- Values read back through the C4 functions
  v_inc numeric;
  v_ref numeric;
  v_exp numeric;
  v_net numeric;
  v_bd_sum numeric;
  v_memo numeric;
  v_cf_closing numeric;
  v_cf_opening numeric;
  v_bad int;
  v_rows int;

  -- Transfer neutrality
  v_box uuid;
  v_bank uuid;
  v_net_before numeric;
  v_net_after numeric;
  v_tr_in_before numeric;
  v_tr_out_before numeric;
  v_tr_in_after numeric;
  v_tr_out_after numeric;

  v_caught boolean;
  v_rec record;
BEGIN
  RAISE NOTICE '=== Starting Phase C4 Acceptance Tests ===';

  -- 1. Resolve or create actors (all rolled back at the end)
  SELECT id INTO v_admin_id FROM public.users WHERE role = 'admin' AND is_active LIMIT 1;
  IF v_admin_id IS NULL THEN
    INSERT INTO public.users (full_name, email, phone, role, is_active)
    VALUES ('C4 Test Admin', 'c4_admin_' || substr(gen_random_uuid()::text, 1, 8) || '@example.com', '+963999999993', 'admin', true)
    RETURNING id INTO v_admin_id;
  END IF;

  SELECT id INTO v_reception_id FROM public.users WHERE role = 'reception' AND is_active LIMIT 1;
  IF v_reception_id IS NULL THEN
    INSERT INTO public.users (full_name, email, phone, role, is_active)
    VALUES ('C4 Test Reception', 'c4_reception_' || substr(gen_random_uuid()::text, 1, 8) || '@example.com', '+963999999994', 'reception', true)
    RETURNING id INTO v_reception_id;
  END IF;

  -- 2. Reference totals as owner (unfiltered by RLS)
  SELECT COALESCE(SUM(amount), 0) INTO v_pay_syp FROM public.payments WHERE currency = 'SYP';
  SELECT COALESCE(SUM(amount), 0) INTO v_pay_usd FROM public.payments WHERE currency = 'USD';

  SELECT COALESCE(SUM(rfnd.amount), 0) INTO v_ref_syp
    FROM public.payment_refunds rfnd JOIN public.payments p ON p.id = rfnd.payment_id
   WHERE p.currency = 'SYP';
  SELECT COALESCE(SUM(rfnd.amount), 0) INTO v_ref_usd
    FROM public.payment_refunds rfnd JOIN public.payments p ON p.id = rfnd.payment_id
   WHERE p.currency = 'USD';

  SELECT COALESCE(SUM(amount), 0) INTO v_exp_syp FROM public.expenses WHERE currency = 'SYP';
  SELECT COALESCE(SUM(amount), 0) INTO v_exp_usd FROM public.expenses WHERE currency = 'USD';

  SELECT COALESCE(SUM(GREATEST(total_amount - paid_amount, 0)), 0) INTO v_memo_syp
    FROM public.lab_invoices WHERE status <> 'cancelled' AND currency = 'SYP';
  SELECT COALESCE(SUM(GREATEST(total_amount - paid_amount, 0)), 0) INTO v_memo_usd
    FROM public.lab_invoices WHERE status <> 'cancelled' AND currency = 'USD';

  SELECT COALESCE(SUM(CASE WHEN direction = 'inflow' THEN amount ELSE -amount END), 0) INTO v_ledger_net
    FROM public.account_transactions;

  SELECT COALESCE(SUM(balance), 0) INTO v_balances_sum FROM public.account_balances_v;

  -- 3. Switch to an authenticated admin and exercise the report functions
  PERFORM set_config('request.jwt.claims', json_build_object(
    'sub', v_admin_id,
    'role', 'authenticated',
    'user_metadata', json_build_object('role', 'admin')
  )::text, true);
  SET LOCAL ROLE authenticated;

  -- --------------------------------------------------------------------------
  -- Test 1: P&L per currency equals payments - refunds - expenses
  -- --------------------------------------------------------------------------
  SELECT COALESCE(SUM(income), 0), COALESCE(SUM(refunds), 0),
         COALESCE(SUM(expenses), 0), COALESCE(SUM(net), 0)
    INTO v_inc, v_ref, v_exp, v_net
    FROM public.get_profit_loss(v_from, v_to)
   WHERE section = 'academy' AND currency = 'SYP';

  ASSERT v_inc = ROUND(v_pay_syp, 2),
    format('SYP income mismatch: report=%s ledger_ref=%s', v_inc, ROUND(v_pay_syp, 2));
  ASSERT v_ref = ROUND(v_ref_syp, 2),
    format('SYP refunds mismatch: report=%s ledger_ref=%s', v_ref, ROUND(v_ref_syp, 2));
  ASSERT v_exp = ROUND(v_exp_syp, 2),
    format('SYP expenses mismatch: report=%s ledger_ref=%s', v_exp, ROUND(v_exp_syp, 2));
  ASSERT v_net = ROUND(v_pay_syp - v_ref_syp - v_exp_syp, 2),
    format('SYP net mismatch: report=%s expected=%s', v_net, ROUND(v_pay_syp - v_ref_syp - v_exp_syp, 2));

  SELECT COALESCE(SUM(income), 0), COALESCE(SUM(refunds), 0),
         COALESCE(SUM(expenses), 0), COALESCE(SUM(net), 0)
    INTO v_inc, v_ref, v_exp, v_net
    FROM public.get_profit_loss(v_from, v_to)
   WHERE section = 'academy' AND currency = 'USD';

  ASSERT v_inc = ROUND(v_pay_usd, 2), 'USD income mismatch';
  ASSERT v_ref = ROUND(v_ref_usd, 2), 'USD refunds mismatch';
  ASSERT v_exp = ROUND(v_exp_usd, 2), 'USD expenses mismatch';
  ASSERT v_net = ROUND(v_pay_usd - v_ref_usd - v_exp_usd, 2), 'USD net mismatch';

  RAISE NOTICE 'Test 1 Passed: P&L arithmetic matches payments/refunds/expenses per currency';

  -- --------------------------------------------------------------------------
  -- Test 2: Expense breakdown sums to P&L expenses
  -- --------------------------------------------------------------------------
  SELECT COALESCE(SUM(amount), 0) INTO v_bd_sum
    FROM public.get_expense_breakdown(v_from, v_to)
   WHERE section = 'academy' AND currency = 'SYP';
  ASSERT v_bd_sum = ROUND(v_exp_syp, 2),
    format('SYP expense breakdown mismatch: breakdown=%s pnl=%s', v_bd_sum, ROUND(v_exp_syp, 2));

  SELECT COALESCE(SUM(amount), 0) INTO v_bd_sum
    FROM public.get_expense_breakdown(v_from, v_to)
   WHERE section = 'academy' AND currency = 'USD';
  ASSERT v_bd_sum = ROUND(v_exp_usd, 2), 'USD expense breakdown mismatch';

  RAISE NOTICE 'Test 2 Passed: Expense breakdown reconciles with P&L totals';

  -- --------------------------------------------------------------------------
  -- Test 3: Cash flow identity and ledger reconciliation
  -- --------------------------------------------------------------------------
  SELECT COUNT(*) INTO v_bad
    FROM public.get_cash_flow_statement(v_from, v_to)
   WHERE closing_balance <> opening_balance + inflows - outflows;
  ASSERT v_bad = 0, format('%s cash-flow rows violate opening + in - out = closing', v_bad);

  SELECT COALESCE(SUM(opening_balance), 0), COALESCE(SUM(closing_balance), 0)
    INTO v_cf_opening, v_cf_closing
    FROM public.get_cash_flow_statement(v_from, v_to);
  ASSERT v_cf_opening = 0, format('Opening balance before 2000-01-01 must be zero, got %s', v_cf_opening);
  ASSERT v_cf_closing = ROUND(v_ledger_net, 2),
    format('Cash-flow closing sum mismatch: report=%s ledger=%s', v_cf_closing, ROUND(v_ledger_net, 2));
  ASSERT v_cf_closing = ROUND(v_balances_sum, 2),
    format('Cash-flow closing sum mismatch with account_balances_v: %s vs %s', v_cf_closing, ROUND(v_balances_sum, 2));

  RAISE NOTICE 'Test 3 Passed: Cash flow per account reconciles with the C2 ledger and balances view';

  -- --------------------------------------------------------------------------
  -- Test 4: Internal transfer is neutral for P&L and visible in cash flow
  -- --------------------------------------------------------------------------
  SELECT id INTO v_box FROM public.financial_accounts
   WHERE name_ar = 'صندوق المركز' AND currency = 'SYP' AND is_active;
  SELECT id INTO v_bank FROM public.financial_accounts
   WHERE name_ar = 'الحساب البنكي' AND currency = 'SYP' AND is_active;
  ASSERT v_box IS NOT NULL AND v_bank IS NOT NULL, 'Required SYP accounts are missing';

  SELECT COALESCE(MAX(net), 0) INTO v_net_before FROM public.get_profit_loss(v_today, v_today)
   WHERE section = 'academy' AND currency = 'SYP';

  SELECT COALESCE(SUM(transfer_in), 0) INTO v_tr_in_before
    FROM public.get_cash_flow_statement(v_today, v_today) WHERE account_id = v_bank;
  SELECT COALESCE(SUM(transfer_out), 0) INTO v_tr_out_before
    FROM public.get_cash_flow_statement(v_today, v_today) WHERE account_id = v_box;

  PERFORM public.transfer_between_accounts(v_box, v_bank, 1000, 'C4 acceptance transfer');

  SELECT COALESCE(MAX(net), 0) INTO v_net_after FROM public.get_profit_loss(v_today, v_today)
   WHERE section = 'academy' AND currency = 'SYP';

  SELECT COALESCE(SUM(transfer_in), 0) INTO v_tr_in_after
    FROM public.get_cash_flow_statement(v_today, v_today) WHERE account_id = v_bank;
  SELECT COALESCE(SUM(transfer_out), 0) INTO v_tr_out_after
    FROM public.get_cash_flow_statement(v_today, v_today) WHERE account_id = v_box;

  ASSERT v_net_after = v_net_before, 'Internal transfer must not change P&L net profit';
  ASSERT v_tr_in_after - v_tr_in_before = 1000,
    format('Transfer inflow delta expected 1000, got %s', v_tr_in_after - v_tr_in_before);
  ASSERT v_tr_out_after - v_tr_out_before = 1000,
    format('Transfer outflow delta expected 1000, got %s', v_tr_out_after - v_tr_out_before);

  RAISE NOTICE 'Test 4 Passed: Internal transfer is P&L-neutral and appears only in cash flow';

  -- --------------------------------------------------------------------------
  -- Test 5: Lab section is separate; memorandum equals uncollected invoices
  -- --------------------------------------------------------------------------
  v_memo := 0;
  SELECT memorandum_uncollected INTO v_memo FROM public.get_profit_loss(v_from, v_to)
   WHERE section = 'lab' AND currency = 'SYP';
  ASSERT COALESCE(v_memo, 0) = ROUND(v_memo_syp, 2),
    format('SYP lab memorandum mismatch: report=%s invoices=%s', v_memo, ROUND(v_memo_syp, 2));

  v_memo := 0;
  SELECT memorandum_uncollected INTO v_memo FROM public.get_profit_loss(v_from, v_to)
   WHERE section = 'lab' AND currency = 'USD';
  ASSERT COALESCE(v_memo, 0) = ROUND(v_memo_usd, 2), 'USD lab memorandum mismatch';

  SELECT COUNT(*) INTO v_rows FROM public.get_profit_loss(v_from, v_to) WHERE section = 'lab';
  IF v_memo_syp > 0 OR v_memo_usd > 0 THEN
    ASSERT v_rows > 0, 'Lab section must appear when lab receivables exist';
  END IF;

  RAISE NOTICE 'Test 5 Passed: Lab section isolated and memorandum matches uncollected invoices';

  -- --------------------------------------------------------------------------
  -- Test 6: Event-vs-ledger integrity
  -- --------------------------------------------------------------------------
  FOR v_rec IN SELECT * FROM public.get_financial_integrity() LOOP
    IF NOT v_rec.is_balanced THEN
      RAISE NOTICE 'Unbalanced integrity row: source_type=% currency=% events=% ledger=% diff=%',
        v_rec.source_type, v_rec.currency, v_rec.events_total, v_rec.ledger_total, v_rec.diff;
    END IF;
  END LOOP;

  SELECT COUNT(*) INTO v_bad FROM public.get_financial_integrity() WHERE NOT is_balanced;
  ASSERT v_bad = 0, format('%s event/ledger integrity rows are unbalanced', v_bad);

  RAISE NOTICE 'Test 6 Passed: Every payment/refund/expense total matches the C2 ledger';

  -- --------------------------------------------------------------------------
  -- Test 7: Invalid period is rejected
  -- --------------------------------------------------------------------------
  v_caught := false;
  BEGIN
    PERFORM public.get_profit_loss(v_to, v_from);
  EXCEPTION WHEN OTHERS THEN
    v_caught := true;
  END;
  ASSERT v_caught = true, 'Reversed date range must be rejected';

  RAISE NOTICE 'Test 7 Passed: Invalid period rejected';

  -- --------------------------------------------------------------------------
  -- Test 8: Reception is denied on all four functions
  -- --------------------------------------------------------------------------
  PERFORM set_config('request.jwt.claims', json_build_object(
    'sub', v_reception_id,
    'role', 'authenticated',
    'user_metadata', json_build_object('role', 'reception')
  )::text, true);

  v_caught := false;
  BEGIN PERFORM public.get_profit_loss(v_from, v_to); EXCEPTION WHEN OTHERS THEN v_caught := true; END;
  ASSERT v_caught = true, 'Security leak: reception executed get_profit_loss';

  v_caught := false;
  BEGIN PERFORM public.get_expense_breakdown(v_from, v_to); EXCEPTION WHEN OTHERS THEN v_caught := true; END;
  ASSERT v_caught = true, 'Security leak: reception executed get_expense_breakdown';

  v_caught := false;
  BEGIN PERFORM public.get_cash_flow_statement(v_from, v_to); EXCEPTION WHEN OTHERS THEN v_caught := true; END;
  ASSERT v_caught = true, 'Security leak: reception executed get_cash_flow_statement';

  v_caught := false;
  BEGIN PERFORM public.get_financial_integrity(); EXCEPTION WHEN OTHERS THEN v_caught := true; END;
  ASSERT v_caught = true, 'Security leak: reception executed get_financial_integrity';

  RESET ROLE;
  RAISE NOTICE 'Test 8 Passed: Reception is denied on all four C4 functions';

  -- --------------------------------------------------------------------------
  -- Test 9: Anonymous role has no EXECUTE at all
  -- --------------------------------------------------------------------------
  SET LOCAL ROLE anon;

  v_caught := false;
  BEGIN PERFORM public.get_profit_loss(v_from, v_to); EXCEPTION WHEN OTHERS THEN v_caught := true; END;
  ASSERT v_caught = true, 'Security leak: anon executed get_profit_loss';

  v_caught := false;
  BEGIN PERFORM public.get_cash_flow_statement(v_from, v_to); EXCEPTION WHEN OTHERS THEN v_caught := true; END;
  ASSERT v_caught = true, 'Security leak: anon executed get_cash_flow_statement';

  RESET ROLE;
  RAISE NOTICE 'Test 9 Passed: Anonymous role is denied at the grant level';

  RAISE NOTICE '=== ALL PHASE C4 ACCEPTANCE TESTS PASSED (9/9) ===';
END $$;

ROLLBACK;
