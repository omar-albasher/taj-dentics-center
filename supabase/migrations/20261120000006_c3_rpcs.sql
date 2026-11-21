-- ============================================================================
-- Phase C3.6 — Calculation and payout engine
-- ============================================================================
-- Six admin-only RPCs over the C3.1-C3.4 tables. All money movement goes
-- through public.expenses, so the C2 triggers write the custody ledger and the
-- existing expense reports stay single-sourced. Nothing here writes
-- account_transactions directly.
--
-- Period convention (management decision 2026-11-20):
--   * One calendar month, evaluated in Asia/Damascus wall clock.
--   * Trainer basis  = payments collected in the month - refunds issued in the
--     month, per currency inside one cohort. No FX, no cross-currency netting.
--   * Trainer rate   = cohort_trainer_rate_snapshots (frozen at cohort
--     creation). Generation refuses when the rate is still NULL.
--   * Trainer of record = cohorts.trainer_id at generation time; the audit
--     triggers record who was credited.
--   * Salary          = staff_compensation row covering the month's last day.
--     Mid-month changes take effect the next month (no proration).
--   * Referral commission = per-referral rate x max(net collected in month, 0).
--   * Advances        = open advances of the same employee and currency,
--     oldest first, deducted only from positive net; no partial deductions.
--   * Bonuses         = staff_bonuses of the same month/currency not yet paid.
--
-- Rebuild-safe: CREATE OR REPLACE only.
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- 0. Shared guard
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_c3_require_admin() RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT public.c1_is_admin() THEN
    RAISE EXCEPTION 'غير مصرّح: هذه العملية للمدير فقط';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_c3_require_admin() FROM PUBLIC, anon;

-- ----------------------------------------------------------------------------
-- 1. Lock a cohort rate manually (cohorts with no resolvable agreement)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.lock_cohort_trainer_rate(
  p_cohort_id uuid,
  p_rate_percent numeric
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_cohort public.cohorts%ROWTYPE;
  v_agreement uuid;
BEGIN
  PERFORM public.fn_c3_require_admin();

  IF p_rate_percent IS NULL OR p_rate_percent <= 0 OR p_rate_percent > 100 THEN
    RAISE EXCEPTION 'نسبة غير صالحة: يجب أن تكون أكبر من 0 وحتى 100';
  END IF;

  SELECT * INTO v_cohort FROM public.cohorts WHERE id = p_cohort_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'الدفعة غير موجودة: %', p_cohort_id;
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.cohort_trainer_rate_snapshots s
    WHERE s.cohort_id = p_cohort_id AND s.rate_percent IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'نسبة هذه الدفعة مقفلة مسبقاً ولا تُعدّل: %', p_cohort_id;
  END IF;

  SELECT a.id INTO v_agreement
  FROM public.trainer_compensation_agreements a
  WHERE a.trainer_id = v_cohort.trainer_id
    AND a.course_id = v_cohort.course_id
    AND a.effective_from <= COALESCE(v_cohort.starts_at, CURRENT_DATE)
    AND (a.effective_to IS NULL OR a.effective_to >= COALESCE(v_cohort.starts_at, CURRENT_DATE))
  ORDER BY a.effective_from DESC
  LIMIT 1;

  INSERT INTO public.cohort_trainer_rate_snapshots
    (cohort_id, trainer_id, course_id, rate_percent, agreement_id, locked_on)
  VALUES
    (p_cohort_id, v_cohort.trainer_id, v_cohort.course_id, p_rate_percent, v_agreement, CURRENT_DATE)
  ON CONFLICT (cohort_id) DO UPDATE
    SET rate_percent = EXCLUDED.rate_percent,
        agreement_id = EXCLUDED.agreement_id,
        locked_on    = EXCLUDED.locked_on,
        locked_at    = now()
    WHERE public.cohort_trainer_rate_snapshots.rate_percent IS NULL;
END;
$$;

COMMENT ON FUNCTION public.lock_cohort_trainer_rate(uuid, numeric) IS
  'C3 admin lock of a cohort trainer rate when no agreement was resolvable at creation. Refuses to overwrite an already locked rate.';

-- ----------------------------------------------------------------------------
-- 2. Generate trainer dues for one cohort and month
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.generate_trainer_dues(
  p_cohort_id uuid,
  p_month date
) RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_start date;
  v_end date;
  v_trainer uuid;
  v_rate numeric(5,2);
  v_status text;
  v_amount numeric(12,2);
  v_count integer := 0;
  r record;
BEGIN
  PERFORM public.fn_c3_require_admin();

  IF p_month IS NULL THEN
    RAISE EXCEPTION 'الشهر مطلوب';
  END IF;
  v_start := date_trunc('month', p_month)::date;
  v_end   := (date_trunc('month', p_month) + interval '1 month - 1 day')::date;

  SELECT c.trainer_id INTO v_trainer FROM public.cohorts c WHERE c.id = p_cohort_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'الدفعة غير موجودة: %', p_cohort_id;
  END IF;

  SELECT s.rate_percent INTO v_rate
  FROM public.cohort_trainer_rate_snapshots s
  WHERE s.cohort_id = p_cohort_id;
  IF v_rate IS NULL THEN
    RAISE EXCEPTION 'نسبة المدرّب غير مقفلة لهذه الدفعة؛ استخدم lock_cohort_trainer_rate أولاً: %', p_cohort_id;
  END IF;

  FOR r IN
    WITH pay AS (
      SELECT p.currency, SUM(p.amount) AS total
      FROM public.payments p
      JOIN public.enrollments e ON e.id = p.enrollment_id
      WHERE e.cohort_id = p_cohort_id
        AND (p.paid_at AT TIME ZONE 'Asia/Damascus')::date BETWEEN v_start AND v_end
      GROUP BY p.currency
    ), ref AS (
      SELECT rp.currency, SUM(rf.amount) AS total
      FROM public.payment_refunds rf
      JOIN public.payments rp ON rp.id = rf.payment_id
      JOIN public.enrollments re ON re.id = rp.enrollment_id
      WHERE re.cohort_id = p_cohort_id
        AND (rf.refunded_at AT TIME ZONE 'Asia/Damascus')::date BETWEEN v_start AND v_end
      GROUP BY rp.currency
    )
    SELECT COALESCE(pay.currency, ref.currency) AS currency,
           COALESCE(pay.total, 0) - COALESCE(ref.total, 0) AS basis
    FROM pay
    FULL OUTER JOIN ref ON ref.currency = pay.currency
  LOOP
    IF r.basis <= 0 THEN
      -- Regeneration after more refunds must not leave a stale pending due.
      DELETE FROM public.trainer_dues d
      WHERE d.cohort_id = p_cohort_id
        AND d.period_start = v_start
        AND d.currency = r.currency
        AND d.status = 'pending';
      CONTINUE;
    END IF;

    SELECT d.status INTO v_status
    FROM public.trainer_dues d
    WHERE d.cohort_id = p_cohort_id
      AND d.period_start = v_start
      AND d.currency = r.currency;
    IF v_status = 'paid' THEN
      RAISE EXCEPTION 'مستحق هذه الفترة مدفوع مسبقاً (%، %)! لا يمكن إعادة توليده', v_start, r.currency;
    END IF;

    v_amount := round(r.basis * v_rate / 100.0, 2);

    INSERT INTO public.trainer_dues
      (trainer_id, cohort_id, period_start, period_end, currency,
       basis_amount, rate_percent, amount, status, created_by)
    VALUES
      (v_trainer, p_cohort_id, v_start, v_end, r.currency,
       r.basis, v_rate, v_amount, 'pending', auth.uid())
    ON CONFLICT (cohort_id, period_start, currency) DO UPDATE
      SET trainer_id   = EXCLUDED.trainer_id,
          period_end   = EXCLUDED.period_end,
          basis_amount = EXCLUDED.basis_amount,
          rate_percent = EXCLUDED.rate_percent,
          amount       = EXCLUDED.amount
      WHERE public.trainer_dues.status = 'pending';

    v_count := v_count + 1;
  END LOOP;

  RETURN v_count;
END;
$$;

COMMENT ON FUNCTION public.generate_trainer_dues(uuid, date) IS
  'C3 idempotent dues generation for one cohort/month: net collected per currency x frozen rate. Refuses when the rate is not locked or the due is already paid.';

-- ----------------------------------------------------------------------------
-- 3. Pay a trainer due from one custody account
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.pay_trainer_due(
  p_due_id uuid,
  p_account_id uuid
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_due public.trainer_dues%ROWTYPE;
  v_acc public.financial_accounts%ROWTYPE;
  v_paid numeric(12,2);
  v_remaining numeric(12,2);
  v_cohort text;
  v_expense uuid;
BEGIN
  PERFORM public.fn_c3_require_admin();

  SELECT * INTO v_due FROM public.trainer_dues WHERE id = p_due_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'المستحق غير موجود: %', p_due_id;
  END IF;
  IF v_due.status <> 'pending' THEN
    RAISE EXCEPTION 'حالة المستحق (%) لا تسمح بالدفع', v_due.status;
  END IF;

  SELECT COALESCE(SUM(tp.amount), 0) INTO v_paid
  FROM public.trainer_payments tp
  WHERE tp.due_id = p_due_id;
  v_remaining := v_due.amount - v_paid;
  IF v_remaining <= 0 THEN
    RAISE EXCEPTION 'لا يوجد مبلغ متبقٍ لدفعه على هذا المستحق';
  END IF;

  SELECT * INTO v_acc FROM public.financial_accounts
  WHERE id = p_account_id AND is_active = true;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'الحساب المالي غير موجود أو غير مفعّل: %', p_account_id;
  END IF;
  IF v_acc.currency <> v_due.currency THEN
    RAISE EXCEPTION 'عملة الحساب (%) لا تطابق عملة المستحق (%)', v_acc.currency, v_due.currency;
  END IF;

  SELECT c.name INTO v_cohort FROM public.cohorts c WHERE c.id = v_due.cohort_id;

  INSERT INTO public.expenses
    (category, amount, description, expense_date, performed_by, currency, account_id)
  VALUES
    ('trainer_fee', v_remaining,
     'أتعاب مدرّب - ' || COALESCE(v_cohort, 'دفعة') || ' - ' || to_char(v_due.period_start, 'YYYY-MM'),
     CURRENT_DATE, auth.uid(), v_due.currency, p_account_id)
  RETURNING id INTO v_expense;

  INSERT INTO public.trainer_payments
    (due_id, amount, currency, account_id, expense_id, performed_by)
  VALUES
    (p_due_id, v_remaining, v_due.currency, p_account_id, v_expense, auth.uid());

  UPDATE public.trainer_dues SET status = 'paid' WHERE id = p_due_id;

  RETURN v_expense;
END;
$$;

COMMENT ON FUNCTION public.pay_trainer_due(uuid, uuid) IS
  'C3 pays the remaining balance of a trainer due via one trainer_fee expense (C2 trigger moves the ledger). Returns the expense id.';

-- ----------------------------------------------------------------------------
-- 4. Generate (or regenerate) the payroll draft for a month
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.generate_payroll(
  p_month date
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_month date;
  v_end date;
  v_run public.payroll_runs%ROWTYPE;
  v_row record;
  v_adv record;
  v_base numeric(12,2);
  v_comm numeric(12,2);
  v_bonus numeric(12,2);
  v_gross numeric(12,2);
  v_deduct numeric(12,2);
  v_line uuid;
BEGIN
  PERFORM public.fn_c3_require_admin();

  IF p_month IS NULL THEN
    RAISE EXCEPTION 'الشهر مطلوب';
  END IF;
  v_month := date_trunc('month', p_month)::date;
  v_end   := (date_trunc('month', p_month) + interval '1 month - 1 day')::date;

  INSERT INTO public.payroll_runs (month, created_by)
  VALUES (v_month, auth.uid())
  ON CONFLICT (month) DO NOTHING;

  SELECT * INTO v_run FROM public.payroll_runs WHERE month = v_month FOR UPDATE;
  IF v_run.status <> 'draft' THEN
    RAISE EXCEPTION 'مسير الرواتب ليس مسودة (الحالة: %)؛ لا يمكن إعادة التوليد', v_run.status;
  END IF;

  -- Draft regeneration: unlinks advances/bonuses through ON DELETE SET NULL.
  DELETE FROM public.payroll_lines WHERE run_id = v_run.id;

  FOR v_row IN
    SELECT DISTINCT ON (s.user_id, s.currency)
           s.user_id, s.currency, s.monthly_salary
    FROM public.staff_compensation s
    WHERE s.effective_from <= v_end
      AND (s.effective_to IS NULL OR s.effective_to >= v_end)
    ORDER BY s.user_id, s.currency, s.effective_from DESC
  LOOP
    v_base := v_row.monthly_salary;

    SELECT COALESCE(SUM(
             round(
               GREATEST(
                 COALESCE((
                   SELECT SUM(p.amount) FROM public.payments p
                   WHERE p.enrollment_id = sr.enrollment_id
                     AND p.currency = v_row.currency
                     AND (p.paid_at AT TIME ZONE 'Asia/Damascus')::date BETWEEN v_month AND v_end
                 ), 0)
                 - COALESCE((
                   SELECT SUM(rf.amount) FROM public.payment_refunds rf
                   JOIN public.payments rp ON rp.id = rf.payment_id
                   WHERE rp.enrollment_id = sr.enrollment_id
                     AND rp.currency = v_row.currency
                     AND (rf.refunded_at AT TIME ZONE 'Asia/Damascus')::date BETWEEN v_month AND v_end
                 ), 0),
                 0
               ) * sr.commission_rate_percent / 100.0, 2)
           ), 0)
      INTO v_comm
    FROM public.staff_referrals sr
    WHERE sr.staff_id = v_row.user_id;

    SELECT COALESCE(SUM(b.amount), 0) INTO v_bonus
    FROM public.staff_bonuses b
    WHERE b.user_id = v_row.user_id
      AND b.currency = v_row.currency
      AND b.bonus_month = v_month
      AND b.payroll_line_id IS NULL;

    v_gross := v_base + v_comm + v_bonus;
    CONTINUE WHEN v_gross <= 0;

    INSERT INTO public.payroll_lines
      (run_id, user_id, currency, base_salary, commission_amount,
       bonus_amount, advances_deducted, net_amount)
    VALUES
      (v_run.id, v_row.user_id, v_row.currency, v_base, v_comm, v_bonus, 0, v_gross)
    RETURNING id INTO v_line;

    v_deduct := 0;
    FOR v_adv IN
      SELECT a.id, a.amount
      FROM public.staff_advances a
      WHERE a.user_id = v_row.user_id
        AND a.currency = v_row.currency
        AND a.status = 'open'
        AND a.payroll_line_id IS NULL
        AND a.advanced_at <= v_end
      ORDER BY a.advanced_at, a.id
    LOOP
      EXIT WHEN v_deduct + v_adv.amount > v_gross;
      v_deduct := v_deduct + v_adv.amount;
      UPDATE public.staff_advances SET payroll_line_id = v_line WHERE id = v_adv.id;
    END LOOP;

    UPDATE public.payroll_lines
    SET advances_deducted = v_deduct,
        net_amount = v_gross - v_deduct
    WHERE id = v_line;

    UPDATE public.staff_bonuses
    SET payroll_line_id = v_line
    WHERE user_id = v_row.user_id
      AND currency = v_row.currency
      AND bonus_month = v_month
      AND payroll_line_id IS NULL;
  END LOOP;

  RETURN v_run.id;
END;
$$;

COMMENT ON FUNCTION public.generate_payroll(date) IS
  'C3 builds/refreshes the draft payroll for a month from salary rows, referral commissions, bonuses and open advances.';

-- ----------------------------------------------------------------------------
-- 5. Approve a payroll run
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.approve_payroll(
  p_run_id uuid
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_run public.payroll_runs%ROWTYPE;
BEGIN
  PERFORM public.fn_c3_require_admin();

  SELECT * INTO v_run FROM public.payroll_runs WHERE id = p_run_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'مسير الرواتب غير موجود: %', p_run_id;
  END IF;
  IF v_run.status <> 'draft' THEN
    RAISE EXCEPTION 'المسير ليس مسودة (الحالة: %)', v_run.status;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.payroll_lines WHERE run_id = p_run_id) THEN
    RAISE EXCEPTION 'المسير لا يحتوي أي بند؛ ولّد الرواتب أولاً';
  END IF;

  UPDATE public.payroll_runs
  SET status = 'approved', approved_by = auth.uid(), approved_at = now()
  WHERE id = p_run_id;
END;
$$;

COMMENT ON FUNCTION public.approve_payroll(uuid) IS
  'C3 draft -> approved. Once approved, lines are frozen and cannot be regenerated.';

-- ----------------------------------------------------------------------------
-- 6. Pay one currency of an approved run
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.pay_payroll(
  p_run_id uuid,
  p_account_id uuid
) RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_run public.payroll_runs%ROWTYPE;
  v_acc public.financial_accounts%ROWTYPE;
  v_line record;
  v_name text;
  v_expense uuid;
  v_count integer := 0;
  v_remaining integer;
BEGIN
  PERFORM public.fn_c3_require_admin();

  SELECT * INTO v_run FROM public.payroll_runs WHERE id = p_run_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'مسير الرواتب غير موجود: %', p_run_id;
  END IF;
  IF v_run.status <> 'approved' THEN
    RAISE EXCEPTION 'المسير يجب أن يكون معتمداً قبل الدفع (الحالة: %)', v_run.status;
  END IF;

  SELECT * INTO v_acc FROM public.financial_accounts
  WHERE id = p_account_id AND is_active = true;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'الحساب المالي غير موجود أو غير مفعّل: %', p_account_id;
  END IF;

  FOR v_line IN
    SELECT l.id, l.user_id, l.net_amount, l.currency
    FROM public.payroll_lines l
    WHERE l.run_id = p_run_id
      AND l.expense_id IS NULL
      AND l.currency = v_acc.currency
    ORDER BY l.user_id
  LOOP
    IF v_line.net_amount = 0 THEN
      UPDATE public.staff_advances SET status = 'deducted' WHERE payroll_line_id = v_line.id;
      CONTINUE;
    END IF;

    SELECT full_name INTO v_name FROM public.users WHERE id = v_line.user_id;

    INSERT INTO public.expenses
      (category, amount, description, expense_date, performed_by, currency, account_id)
    VALUES
      ('salary', v_line.net_amount,
       'راتب ' || to_char(v_run.month, 'YYYY-MM') || ' - ' || COALESCE(v_name, v_line.user_id::text),
       CURRENT_DATE, auth.uid(), v_line.currency, p_account_id)
    RETURNING id INTO v_expense;

    UPDATE public.payroll_lines SET expense_id = v_expense WHERE id = v_line.id;
    UPDATE public.staff_advances SET status = 'deducted' WHERE payroll_line_id = v_line.id;
    v_count := v_count + 1;
  END LOOP;

  SELECT count(*) INTO v_remaining
  FROM public.payroll_lines
  WHERE run_id = p_run_id AND expense_id IS NULL AND net_amount > 0;

  IF v_remaining = 0 THEN
    UPDATE public.payroll_runs SET status = 'paid' WHERE id = p_run_id;
  END IF;

  RETURN v_count;
END;
$$;

COMMENT ON FUNCTION public.pay_payroll(uuid, uuid) IS
  'C3 pays every unpaid positive line of the run in the account currency via salary expenses; marks the run paid when all currencies are settled.';

-- ----------------------------------------------------------------------------
-- 7. Grants — admin check is inside each function
-- ----------------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.lock_cohort_trainer_rate(uuid, numeric) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.generate_trainer_dues(uuid, date) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.pay_trainer_due(uuid, uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.generate_payroll(date) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.approve_payroll(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.pay_payroll(uuid, uuid) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.lock_cohort_trainer_rate(uuid, numeric) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.generate_trainer_dues(uuid, date) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.pay_trainer_due(uuid, uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.generate_payroll(date) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.approve_payroll(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.pay_payroll(uuid, uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_c3_require_admin() TO service_role;

COMMIT;
