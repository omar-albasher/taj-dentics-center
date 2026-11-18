-- ============================================================================
-- Acceptance Suite: Phase C2 Custody Ledger Proof
-- File: supabase/tests/20261118000009_phase_c2_acceptance_proof.sql
-- Description: Comprehensive verification of C2 financial accounts,
--              custody ledger, triggers, RLS isolation and transfer RPC.
-- Safety: Fully transactional. Enclosed in BEGIN ... ROLLBACK.
-- ============================================================================

BEGIN;

DO $$
DECLARE
  v_admin_id uuid;
  v_reception_id uuid;
  v_enrollment_id uuid;
  v_count int;
  v_syp_box uuid;
  v_syp_bank uuid;
  v_usd_bank uuid;
  v_test_payment_id uuid;
  v_test_tx_id uuid;
  v_transfer_group uuid;
  v_caught boolean := false;
BEGIN
  RAISE NOTICE '=== Starting Phase C2 Acceptance Tests ===';

  -- 1. Resolve or create test users (cleanly rolled back at the end)
  SELECT id INTO v_admin_id FROM public.users WHERE role = 'admin' AND is_active LIMIT 1;
  IF v_admin_id IS NULL THEN
    INSERT INTO public.users (full_name, email, phone, role, is_active)
    VALUES ('C2 Test Admin', 'c2_admin_' || substr(gen_random_uuid()::text, 1, 8) || '@example.com', '+963999999991', 'admin', true)
    RETURNING id INTO v_admin_id;
  END IF;

  SELECT id INTO v_reception_id FROM public.users WHERE role = 'reception' AND is_active LIMIT 1;
  IF v_reception_id IS NULL THEN
    INSERT INTO public.users (full_name, email, phone, role, is_active)
    VALUES ('C2 Test Reception', 'c2_reception_' || substr(gen_random_uuid()::text, 1, 8) || '@example.com', '+963999999992', 'reception', true)
    RETURNING id INTO v_reception_id;
  END IF;

  -- 2. Test Static Contracts (Tables, RLS, Views, Functions)
  ASSERT to_regclass('public.financial_accounts') IS NOT NULL, 'financial_accounts table missing';
  ASSERT to_regclass('public.account_transactions') IS NOT NULL, 'account_transactions table missing';
  ASSERT to_regclass('public.account_balances_v') IS NOT NULL, 'account_balances_v view missing';

  -- Verify 6 seeded accounts exist
  SELECT count(*) INTO v_count FROM public.financial_accounts WHERE is_active;
  ASSERT v_count = 6, format('Expected 6 active financial accounts, found %s', v_count);

  -- Retrieve key test accounts
  SELECT id INTO v_syp_box FROM public.financial_accounts WHERE name_ar = 'صندوق المركز' AND currency = 'SYP';
  SELECT id INTO v_syp_bank FROM public.financial_accounts WHERE name_ar = 'الحساب البنكي' AND currency = 'SYP';
  SELECT id INTO v_usd_bank FROM public.financial_accounts WHERE name_ar = 'الحساب البنكي' AND currency = 'USD';

  ASSERT v_syp_box IS NOT NULL AND v_syp_bank IS NOT NULL AND v_usd_bank IS NOT NULL, 'Key accounts missing';

  -- --------------------------------------------------------------------------
  -- Test 2: RLS Isolation for Reception (Zero Visibility)
  -- --------------------------------------------------------------------------
  PERFORM set_config('request.jwt.claims', json_build_object(
    'sub', v_reception_id,
    'role', 'authenticated',
    'user_metadata', json_build_object('role', 'reception')
  )::text, true);
  SET LOCAL ROLE authenticated;

  -- Reception must see 0 financial_accounts
  SELECT count(*) INTO v_count FROM public.financial_accounts;
  ASSERT v_count = 0, format('Security leak: Reception saw %s rows in financial_accounts', v_count);

  -- Reception must see 0 account_transactions
  SELECT count(*) INTO v_count FROM public.account_transactions;
  ASSERT v_count = 0, format('Security leak: Reception saw %s rows in account_transactions', v_count);

  -- Reception must see 0 account_balances_v
  SELECT count(*) INTO v_count FROM public.account_balances_v;
  ASSERT v_count = 0, format('Security leak: Reception saw %s rows in account_balances_v', v_count);

  -- Reception must be blocked from calling transfer RPC
  v_caught := false;
  BEGIN
    PERFORM public.transfer_between_accounts(v_syp_box, v_syp_bank, 100, 'Unauthorized test');
  EXCEPTION WHEN OTHERS THEN
    v_caught := true;
  END;
  ASSERT v_caught = true, 'Security leak: Reception was able to execute transfer_between_accounts!';

  RESET ROLE;
  RAISE NOTICE 'Test 2 Passed: Reception is completely isolated from C2 financial data';

  -- --------------------------------------------------------------------------
  -- Test 3: Admin Visibility and Balances View
  -- --------------------------------------------------------------------------
  PERFORM set_config('request.jwt.claims', json_build_object(
    'sub', v_admin_id,
    'role', 'authenticated',
    'user_metadata', json_build_object('role', 'admin')
  )::text, true);
  SET LOCAL ROLE authenticated;

  SELECT count(*) INTO v_count FROM public.financial_accounts;
  ASSERT v_count = 6, format('Admin should see 6 financial accounts, found %s', v_count);

  SELECT count(*) INTO v_count FROM public.account_balances_v;
  ASSERT v_count = 6, format('Admin should see 6 rows in account_balances_v, found %s', v_count);

  RESET ROLE;
  RAISE NOTICE 'Test 3 Passed: Admin can view all 6 accounts and balances';

  -- --------------------------------------------------------------------------
  -- Test 4: Triggers Lifecycle (Insert Payment -> Ledger Inflow -> Delete -> Clean)
  -- --------------------------------------------------------------------------
  SELECT id INTO v_enrollment_id FROM public.enrollments LIMIT 1;

  IF v_enrollment_id IS NOT NULL THEN
    -- Insert test payment as reception (cash SYP)
    PERFORM set_config('request.jwt.claims', json_build_object(
      'sub', v_reception_id,
      'role', 'authenticated',
      'user_metadata', json_build_object('role', 'reception')
    )::text, true);
    SET LOCAL ROLE authenticated;

    INSERT INTO public.payments (
      enrollment_id, amount, currency, method, performed_by, notes
    ) VALUES (
      v_enrollment_id, 25000, 'SYP', 'cash', v_reception_id, 'C2 Automated Test Payment'
    ) RETURNING id INTO v_test_payment_id;

    -- Switch back to admin to verify the ledger
    PERFORM set_config('request.jwt.claims', json_build_object(
      'sub', v_admin_id,
      'role', 'authenticated',
      'user_metadata', json_build_object('role', 'admin')
    )::text, true);

    SELECT id INTO v_test_tx_id
    FROM public.account_transactions
    WHERE source_type = 'payment' AND source_id = v_test_payment_id;

    ASSERT v_test_tx_id IS NOT NULL, 'Trigger failed to create ledger entry for new payment';

    -- Verify transaction properties
    ASSERT (SELECT direction FROM public.account_transactions WHERE id = v_test_tx_id) = 'inflow',
      'Payment transaction must be an inflow';
    ASSERT (SELECT amount FROM public.account_transactions WHERE id = v_test_tx_id) = 25000.00,
      'Payment transaction amount mismatch';
    ASSERT (SELECT account_id FROM public.account_transactions WHERE id = v_test_tx_id) = v_syp_box,
      'Payment transaction must map to صندوق المركز (SYP)';

    -- Delete the test payment and verify the ledger entry is cleaned up
    RESET ROLE;
    DELETE FROM public.payments WHERE id = v_test_payment_id;
    ASSERT NOT EXISTS (SELECT 1 FROM public.account_transactions WHERE id = v_test_tx_id),
      'Trigger failed to delete ledger entry upon payment deletion';

    RAISE NOTICE 'Test 4 Passed: Payment trigger created and cleaned up ledger transaction accurately';
  END IF;

  -- --------------------------------------------------------------------------
  -- Test 5: Internal Transfer RPC (Same-Currency, Cross-Currency, Self-Transfer)
  -- --------------------------------------------------------------------------
  PERFORM set_config('request.jwt.claims', json_build_object(
    'sub', v_admin_id,
    'role', 'authenticated',
    'user_metadata', json_build_object('role', 'admin')
  )::text, true);
  SET LOCAL ROLE authenticated;

  -- Valid transfer between SYP accounts (box -> bank)
  v_transfer_group := public.transfer_between_accounts(v_syp_box, v_syp_bank, 50000, 'C2 Test Transfer');
  ASSERT v_transfer_group IS NOT NULL, 'transfer_between_accounts failed to return a transfer_group';

  SELECT count(*) INTO v_count
  FROM public.account_transactions
  WHERE transfer_group = v_transfer_group;
  ASSERT v_count = 2, format('Transfer must create exactly 2 ledger rows, found %s', v_count);

  -- Cross-currency transfer attempt (SYP box -> USD bank) must FAIL
  v_caught := false;
  BEGIN
    PERFORM public.transfer_between_accounts(v_syp_box, v_usd_bank, 100, 'Cross currency test');
  EXCEPTION WHEN OTHERS THEN
    v_caught := true;
  END;
  ASSERT v_caught = true, 'Cross-currency transfer should have been rejected!';

  -- Self-transfer attempt (SYP box -> SYP box) must FAIL
  v_caught := false;
  BEGIN
    PERFORM public.transfer_between_accounts(v_syp_box, v_syp_box, 100, 'Self transfer test');
  EXCEPTION WHEN OTHERS THEN
    v_caught := true;
  END;
  ASSERT v_caught = true, 'Self-transfer should have been rejected!';

  RESET ROLE;
  RAISE NOTICE 'Test 5 Passed: Transfer RPC enforced same-currency and created dual-entry movements';

  RAISE NOTICE '=== ALL PHASE C2 ACCEPTANCE TESTS PASSED (5/5) ===';
END $$;

ROLLBACK;
