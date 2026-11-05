-- ==============================================================================
-- Taj Dentics Training Center - Phase C1.1 Corrective Migration
-- File: 20261105000001_phase_c1_fixes.sql
-- Additive. Fixes: view leakage, refund double-count, missing automation,
-- currency lock, released-enrollment exclusion, plan/ledger reconciliation.
-- ==============================================================================

BEGIN;

-- ==============================================================================
-- 1) Authorization helpers (single source of truth for views, RLS and triggers)
-- ==============================================================================
CREATE OR REPLACE FUNCTION public.c1_staff_role()
RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
  SELECT u.role::text
  FROM public.users u
  WHERE u.id = auth.uid() AND u.is_active = true
$$;

CREATE OR REPLACE FUNCTION public.c1_is_staff()
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
  SELECT COALESCE(public.c1_staff_role() IN ('admin','reception','accountant'), false)
$$;

CREATE OR REPLACE FUNCTION public.c1_is_admin()
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
  SELECT COALESCE(public.c1_staff_role() = 'admin', false)
$$;

-- Staff see everything; a trainee sees only their own rows; trusted
-- (service_role / direct owner) connections are unrestricted.
CREATE OR REPLACE FUNCTION public.c1_can_read_financials(p_trainee_user_id uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
  SELECT auth.role() IS NULL
      OR auth.role() = 'service_role'
      OR public.c1_is_staff()
      OR (auth.uid() IS NOT NULL AND p_trainee_user_id = auth.uid())
$$;

-- ==============================================================================
-- 2) enrollment_financial_summary_v2
--     refunds aggregated separately (no fan-out double count)
--     released enrollments report zero overdue
--     row filtering by role via c1_can_read_financials
--     appended legacy-compatible columns: course_name, total_due, total_paid,
--      balance, payment_status
-- ==============================================================================
CREATE OR REPLACE VIEW public.enrollment_financial_summary_v2 AS
WITH payment_agg AS (
    SELECT p.enrollment_id, SUM(p.amount) AS gross_paid
    FROM public.payments p
    GROUP BY p.enrollment_id
),
refund_agg AS (
    SELECT p.enrollment_id, SUM(r.amount) AS total_refunded
    FROM public.payment_refunds r
    JOIN public.payments p ON p.id = r.payment_id
    GROUP BY p.enrollment_id
),
adjustment_agg AS (
    SELECT fa.enrollment_id, SUM(fa.amount) AS total_adjustments
    FROM public.fee_adjustments fa
    GROUP BY fa.enrollment_id
),
installment_agg AS (
    SELECT s.enrollment_id,
           COUNT(s.id) AS total_installments,
           MIN(CASE WHEN COALESCE(alloc.allocated, 0) < s.amount THEN s.due_date END) AS next_due_date,
           COALESCE(SUM(CASE WHEN s.due_date < (now() AT TIME ZONE 'Asia/Damascus')::date 
                             THEN GREATEST(s.amount - COALESCE(alloc.allocated, 0), 0) 
                             ELSE 0 END), 0::numeric) AS overdue_balance
    FROM public.installment_schedule s
    LEFT JOIN (
        SELECT installment_id, SUM(amount) AS allocated
        FROM public.payment_allocations
        GROUP BY installment_id
    ) alloc ON alloc.installment_id = s.id
    GROUP BY s.enrollment_id
)
SELECT
    e.id AS enrollment_id,
    e.trainee_id,
    u.full_name AS trainee_name,
    t.trainee_code,
    co.id AS cohort_id,
    co.name AS cohort_name,
    e.currency,
    e.status AS legacy_payment_status,
    e.total_due AS original_fee,
    e.discount_amount AS total_discount,
    COALESCE(adj.total_adjustments, 0::numeric) AS total_adjustments,
    (e.total_due - COALESCE(e.discount_amount, 0) + COALESCE(adj.total_adjustments, 0::numeric)) AS net_due,
    COALESCE(pa.gross_paid, 0::numeric) AS gross_paid,
    COALESCE(rf.total_refunded, 0::numeric) AS total_refunded,
    (COALESCE(pa.gross_paid, 0::numeric) - COALESCE(rf.total_refunded, 0::numeric)) AS net_paid,
    ((e.total_due - COALESCE(e.discount_amount, 0) + COALESCE(adj.total_adjustments, 0::numeric)) - (COALESCE(pa.gross_paid, 0::numeric) - COALESCE(rf.total_refunded, 0::numeric))) AS current_balance,
    COALESCE(ia.total_installments, 0) AS total_installments,
    ia.next_due_date,
    CASE
        WHEN public.enrollment_status_occupies_seat(e.status::text) THEN COALESCE(ia.overdue_balance, 0::numeric)
        ELSE 0::numeric
    END AS overdue_balance,
    -- Compatibility columns for existing admin code
    crs.name AS course_name,
    (e.total_due - COALESCE(e.discount_amount, 0) + COALESCE(adj.total_adjustments, 0::numeric)) AS total_due,
    (COALESCE(pa.gross_paid, 0::numeric) - COALESCE(rf.total_refunded, 0::numeric)) AS total_paid,
    ((e.total_due - COALESCE(e.discount_amount, 0) + COALESCE(adj.total_adjustments, 0::numeric)) - (COALESCE(pa.gross_paid, 0::numeric) - COALESCE(rf.total_refunded, 0::numeric))) AS balance,
    CASE
        WHEN (COALESCE(pa.gross_paid, 0::numeric) - COALESCE(rf.total_refunded, 0::numeric)) >= (e.total_due - COALESCE(e.discount_amount, 0) + COALESCE(adj.total_adjustments, 0::numeric)) THEN 'complete'
        WHEN (COALESCE(pa.gross_paid, 0::numeric) - COALESCE(rf.total_refunded, 0::numeric)) > 0 THEN 'partial'
        ELSE 'unpaid'
    END AS payment_status
FROM public.enrollments e
LEFT JOIN public.trainees t ON t.id = e.trainee_id
LEFT JOIN public.users u ON u.id = t.user_id
LEFT JOIN public.cohorts co ON co.id = e.cohort_id
LEFT JOIN public.courses crs ON crs.id = co.course_id
LEFT JOIN payment_agg pa ON pa.enrollment_id = e.id
LEFT JOIN refund_agg rf ON rf.enrollment_id = e.id
LEFT JOIN adjustment_agg adj ON adj.enrollment_id = e.id
LEFT JOIN installment_agg ia ON ia.enrollment_id = e.id
WHERE public.c1_can_read_financials(t.user_id);

-- ==============================================================================
-- 3) overdue_installments_v — released enrollments excluded, Damascus date
-- ==============================================================================
CREATE OR REPLACE VIEW public.overdue_installments_v AS
SELECT
    s.id AS installment_id,
    s.enrollment_id,
    e.trainee_id,
    t.trainee_code,
    u.full_name AS trainee_name,
    u.phone AS trainee_phone,
    co.id AS cohort_id,
    co.name AS cohort_name,
    s.installment_number,
    s.due_date,
    s.amount AS installment_amount,
    COALESCE(alloc.allocated, 0::numeric) AS paid_amount,
    (s.amount - COALESCE(alloc.allocated, 0::numeric)) AS overdue_amount,
    s.currency,
    ((now() AT TIME ZONE 'Asia/Damascus')::date - s.due_date) AS days_overdue,
    e.status::text AS enrollment_status
FROM public.installment_schedule s
JOIN public.enrollments e ON e.id = s.enrollment_id
JOIN public.trainees t ON t.id = e.trainee_id
JOIN public.users u ON u.id = t.user_id
JOIN public.cohorts co ON co.id = e.cohort_id
LEFT JOIN (
    SELECT installment_id, SUM(amount) AS allocated
    FROM public.payment_allocations
    GROUP BY installment_id
) alloc ON alloc.installment_id = s.id
WHERE s.due_date < (now() AT TIME ZONE 'Asia/Damascus')::date
  AND (s.amount - COALESCE(alloc.allocated, 0::numeric)) > 0
  AND public.enrollment_status_occupies_seat(e.status::text)
  AND public.c1_can_read_financials(t.user_id);

-- ==============================================================================
-- 4) trainee_statement_v — ownership filter without current_user bypass
-- ==============================================================================
CREATE OR REPLACE VIEW public.trainee_statement_v AS
WITH ledger_entries AS (
    SELECT
        e.id AS enrollment_id,
        e.trainee_id,
        e.id::text AS entry_id,
        COALESCE(co.starts_at, co.created_at, now()) AS entry_date,
        'initial_fee' AS entry_type,
        'رسوم التسجيل الأساسية - ' || co.name AS description,
        e.total_due AS debit,
        0::numeric AS credit,
        e.currency
    FROM public.enrollments e
    JOIN public.cohorts co ON co.id = e.cohort_id

    UNION ALL

    SELECT
        e.id,
        e.trainee_id,
        e.id::text || '_disc',
        COALESCE(co.starts_at, co.created_at, now()),
        'discount',
        'خصم تسجيل معتمد',
        0::numeric,
        e.discount_amount,
        e.currency
    FROM public.enrollments e
    JOIN public.cohorts co ON co.id = e.cohort_id
    WHERE COALESCE(e.discount_amount, 0) > 0

    UNION ALL

    SELECT
        fa.enrollment_id,
        e.trainee_id,
        fa.id::text,
        fa.adjusted_at,
        'fee_adjustment',
        'تعديل رسوم: ' || fa.reason,
        CASE WHEN fa.amount > 0 THEN fa.amount ELSE 0::numeric END,
        CASE WHEN fa.amount < 0 THEN ABS(fa.amount) ELSE 0::numeric END,
        e.currency
    FROM public.fee_adjustments fa
    JOIN public.enrollments e ON e.id = fa.enrollment_id

    UNION ALL

    SELECT
        p.enrollment_id,
        e.trainee_id,
        p.id::text,
        p.paid_at,
        'payment',
        'دفعة نقدية/تحويل - إيصال #' || COALESCE(p.receipt_number, substring(p.id::text, 1, 8)),
        0::numeric,
        p.amount,
        p.currency
    FROM public.payments p
    JOIN public.enrollments e ON e.id = p.enrollment_id

    UNION ALL

    SELECT
        p.enrollment_id,
        e.trainee_id,
        r.id::text,
        r.refunded_at,
        'refund',
        'استرداد دفعة: ' || r.reason,
        r.amount,
        0::numeric,
        p.currency
    FROM public.payment_refunds r
    JOIN public.payments p ON p.id = r.payment_id
    JOIN public.enrollments e ON e.id = p.enrollment_id
)
SELECT
    le.enrollment_id,
    le.trainee_id,
    t.trainee_code,
    u.full_name AS trainee_name,
    le.entry_id,
    le.entry_date,
    le.entry_type,
    le.description,
    le.debit,
    le.credit,
    le.currency,
    SUM(le.debit - le.credit) OVER (
        PARTITION BY le.enrollment_id
        ORDER BY le.entry_date ASC,
                 CASE le.entry_type
                     WHEN 'initial_fee'    THEN 1
                     WHEN 'discount'       THEN 2
                     WHEN 'fee_adjustment' THEN 3
                     WHEN 'payment'        THEN 4
                     WHEN 'refund'         THEN 5
                     ELSE 6
                 END,
                 le.entry_id ASC
    ) AS running_balance
FROM ledger_entries le
JOIN public.trainees t ON t.id = le.trainee_id
JOIN public.users u ON u.id = t.user_id
WHERE public.c1_can_read_financials(t.user_id);

-- ==============================================================================
-- 5) Constraint Trigger: sum(installments) = net_due at COMMIT
-- ==============================================================================
CREATE OR REPLACE FUNCTION public.trg_fn_c1_plan_total()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_enrollment_id uuid;
    v_net           numeric(12,2);
    v_sum           numeric(12,2);
    v_status        text;
BEGIN
    IF current_setting('c1.replanning', true) = 'on' THEN
        RETURN NULL;
    END IF;

    IF TG_OP = 'DELETE' THEN
        v_enrollment_id := OLD.enrollment_id;
    ELSE
        v_enrollment_id := NEW.enrollment_id;
    END IF;

    SELECT e.status::text,
           COALESCE(e.total_due, 0) - COALESCE(e.discount_amount, 0) +
           COALESCE((SELECT sum(fa.amount) FROM public.fee_adjustments fa
                     WHERE fa.enrollment_id = e.id), 0)
    INTO v_status, v_net
    FROM public.enrollments e
    WHERE e.id = v_enrollment_id;

    IF v_status IS NULL OR NOT public.enrollment_status_occupies_seat(v_status) THEN
        RETURN NULL;
    END IF;

    SELECT COALESCE(sum(s.amount), 0)
    INTO v_sum
    FROM public.installment_schedule s
    WHERE s.enrollment_id = v_enrollment_id;

    IF v_net > 0 AND v_sum <> v_net THEN
        RAISE EXCEPTION 'خطة الأقساط لا تطابق صافي الرسوم: الأقساط=%, الرسوم=%', v_sum, v_net;
    END IF;

    IF v_net <= 0 AND v_sum > 0 THEN
        RAISE EXCEPTION 'يوجد أقساط لتسجيل صافي رسومه صفر أو سالب (%)', v_net;
    END IF;

    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_c1_plan_total ON public.installment_schedule;
CREATE CONSTRAINT TRIGGER trg_c1_plan_total
AFTER INSERT OR UPDATE OR DELETE ON public.installment_schedule
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW
EXECUTE FUNCTION public.trg_fn_c1_plan_total();

-- ==============================================================================
-- 6) Backfill any missing default plan (COALESCE + released-status filter)
-- ==============================================================================
INSERT INTO public.installment_schedule
  (enrollment_id, installment_number, due_date, amount, currency, notes)
SELECT e.id,
       1,
       GREATEST(
         COALESCE(c.starts_at::date, (now() AT TIME ZONE 'Asia/Damascus')::date),
         (now() AT TIME ZONE 'Asia/Damascus')::date
       ),
       v.net,
       e.currency,
       'قسط افتراضي آلي (Phase C1)'
FROM public.enrollments e
LEFT JOIN public.cohorts c ON c.id = e.cohort_id
CROSS JOIN LATERAL (
  SELECT COALESCE(e.total_due, 0) - COALESCE(e.discount_amount, 0) +
         COALESCE((SELECT sum(fa.amount) FROM public.fee_adjustments fa
                   WHERE fa.enrollment_id = e.id), 0) AS net
) v
WHERE v.net > 0
  AND public.enrollment_status_occupies_seat(e.status::text)
  AND NOT EXISTS (
    SELECT 1 FROM public.installment_schedule s WHERE s.enrollment_id = e.id
  );

-- ==============================================================================
-- 7) Correct retroactive due dates of the C1.1 backfilled installment
-- ==============================================================================
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'enrollments'
      AND column_name = 'created_at'
  ) THEN
    EXECUTE $q$
      UPDATE public.installment_schedule s
      SET due_date = GREATEST(
        COALESCE(c.starts_at::date, (now() AT TIME ZONE 'Asia/Damascus')::date),
        (e.created_at AT TIME ZONE 'Asia/Damascus')::date
      )
      FROM public.enrollments e
      LEFT JOIN public.cohorts c ON c.id = e.cohort_id
      WHERE s.enrollment_id = e.id
        AND s.installment_number = 1
        AND s.notes = 'القسط الافتراضي الأساسي (تسوية تلقائية Phase C1)'
        AND NOT EXISTS (
          SELECT 1 FROM public.payment_allocations a WHERE a.installment_id = s.id
        )
    $q$;
  ELSE
    RAISE NOTICE 'enrollments.created_at غير موجود: لم تُصحَّح تواريخ الاستحقاق التاريخية.';
  END IF;
END $$;

-- ==============================================================================
-- 8) FIFO allocation engine (single source of truth for allocations)
-- ==============================================================================
CREATE OR REPLACE FUNCTION public.c1_allocate_payment(p_payment_id uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_payment   record;
    v_enr       record;
    v_refunded  numeric(12,2);
    v_amount    numeric(12,2);
    v_remaining numeric(12,2);
    v_alloc     numeric(12,2);
    r           record;
BEGIN
    SELECT p.id, p.enrollment_id, p.amount, p.currency
    INTO v_payment
    FROM public.payments p
    WHERE p.id = p_payment_id;

    IF v_payment.id IS NULL OR v_payment.enrollment_id IS NULL THEN
        RETURN;
    END IF;

    PERFORM pg_advisory_xact_lock(
        hashtextextended('c1_alloc:' || v_payment.enrollment_id::text, 0)
    );

    SELECT e.id, e.currency::text AS currency, e.status::text AS status,
           COALESCE(e.total_due, 0) - COALESCE(e.discount_amount, 0) AS net
    INTO v_enr
    FROM public.enrollments e
    WHERE e.id = v_payment.enrollment_id;

    IF v_enr.id IS NULL THEN
        RETURN;
    END IF;

    IF v_payment.currency::text IS DISTINCT FROM v_enr.currency THEN
        RAISE EXCEPTION 'عملة الدفعة (%) لا تطابق عملة التسجيل (%)',
            v_payment.currency, v_enr.currency;
    END IF;

    SELECT COALESCE(sum(rf.amount), 0) INTO v_refunded
    FROM public.payment_refunds rf
    WHERE rf.payment_id = p_payment_id;

    v_amount := COALESCE(v_payment.amount, 0) - v_refunded;

    IF v_amount <= 0 THEN
        DELETE FROM public.payment_allocations WHERE payment_id = p_payment_id;
        RETURN;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM public.installment_schedule s WHERE s.enrollment_id = v_enr.id
    ) AND v_enr.net > 0 THEN
        INSERT INTO public.installment_schedule
          (enrollment_id, installment_number, due_date, amount, currency, notes, created_by)
        VALUES
          (v_enr.id, 1, (now() AT TIME ZONE 'Asia/Damascus')::date,
           v_enr.net, v_payment.currency, 'قسط افتراضي آلي (Phase C1)', auth.uid())
        ON CONFLICT (enrollment_id, installment_number) DO NOTHING;
    END IF;

    DELETE FROM public.payment_allocations WHERE payment_id = p_payment_id;

    v_remaining := v_amount;

    FOR r IN
        SELECT s.id, s.amount, COALESCE(a.alloc, 0) AS allocated
        FROM public.installment_schedule s
        LEFT JOIN (
            SELECT pa.installment_id, sum(pa.amount) AS alloc
            FROM public.payment_allocations pa
            GROUP BY pa.installment_id
        ) a ON a.installment_id = s.id
        WHERE s.enrollment_id = v_enr.id
          AND s.amount > COALESCE(a.alloc, 0)
        ORDER BY s.due_date, s.installment_number
    LOOP
        EXIT WHEN v_remaining <= 0;
        v_alloc := LEAST(v_remaining, r.amount - r.allocated);
        IF v_alloc > 0 THEN
            INSERT INTO public.payment_allocations
              (payment_id, installment_id, amount, created_by)
            VALUES
              (p_payment_id, r.id, v_alloc, auth.uid());
            v_remaining := v_remaining - v_alloc;
        END IF;
    END LOOP;
END;
$$;

-- Re-normalise every existing payment
DO $$
DECLARE
  r record;
  v_bad integer;
BEGIN
  SELECT count(*) INTO v_bad
  FROM public.payments p
  JOIN public.enrollments e ON e.id = p.enrollment_id
  WHERE p.currency::text IS DISTINCT FROM e.currency::text;

  IF v_bad > 0 THEN
    RAISE NOTICE 'يوجد % دفعة بعملة مخالفة لعملة التسجيل: لم تُعد تسويتها وتحتاج مراجعة يدوية.', v_bad;
  END IF;

  FOR r IN
    SELECT p.id
    FROM public.payments p
    JOIN public.enrollments e ON e.id = p.enrollment_id
    WHERE p.currency::text = e.currency::text
    ORDER BY p.paid_at NULLS LAST, p.id
  LOOP
    PERFORM public.c1_allocate_payment(r.id);
  END LOOP;
END $$;

-- ==============================================================================
-- 9) Plan delta application helper
-- ==============================================================================
CREATE OR REPLACE FUNCTION public.c1_apply_plan_delta(
    p_enrollment_id uuid,
    p_delta         numeric(12,2)
)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_last_id   uuid;
    v_remaining numeric(12,2);
    v_take      numeric(12,2);
    v_free      numeric(12,2);
    v_net       numeric(12,2);
    v_currency  public.currency_type;
    r           record;
BEGIN
    IF p_delta IS NULL OR p_delta = 0 THEN
        RETURN;
    END IF;

    PERFORM pg_advisory_xact_lock(
        hashtextextended('c1_plan:' || p_enrollment_id::text, 0)
    );

    SELECT e.currency,
           COALESCE(e.total_due, 0) - COALESCE(e.discount_amount, 0) +
           COALESCE((SELECT sum(fa.amount) FROM public.fee_adjustments fa
                     WHERE fa.enrollment_id = e.id), 0)
    INTO v_currency, v_net
    FROM public.enrollments e
    WHERE e.id = p_enrollment_id;

    IF v_currency IS NULL THEN
        RETURN;
    END IF;

    IF p_delta > 0 THEN
        SELECT s.id INTO v_last_id
        FROM public.installment_schedule s
        WHERE s.enrollment_id = p_enrollment_id
        ORDER BY s.installment_number DESC LIMIT 1;

        IF v_last_id IS NULL THEN
            INSERT INTO public.installment_schedule
              (enrollment_id, installment_number, due_date, amount, currency, notes)
            VALUES
              (p_enrollment_id, 1, (now() AT TIME ZONE 'Asia/Damascus')::date,
               v_net, v_currency, 'قسط افتراضي آلي (Phase C1)');
        ELSE
            UPDATE public.installment_schedule
            SET amount = amount + p_delta WHERE id = v_last_id;
        END IF;
    ELSE
        v_remaining := -p_delta;

        FOR r IN
            SELECT s.id, s.amount, COALESCE(a.alloc, 0) AS allocated
            FROM public.installment_schedule s
            LEFT JOIN (
                SELECT pa.installment_id, sum(pa.amount) AS alloc
                FROM public.payment_allocations pa GROUP BY pa.installment_id
            ) a ON a.installment_id = s.id
            WHERE s.enrollment_id = p_enrollment_id
            ORDER BY s.installment_number DESC
        LOOP
            EXIT WHEN v_remaining <= 0;
            v_free := r.amount - r.allocated;
            v_take := LEAST(v_remaining, v_free);
            IF v_take > 0 THEN
                IF v_take = r.amount THEN
                    DELETE FROM public.installment_schedule WHERE id = r.id;
                ELSE
                    UPDATE public.installment_schedule
                    SET amount = amount - v_take WHERE id = r.id;
                END IF;
                v_remaining := v_remaining - v_take;
            END IF;
        END LOOP;

        IF v_remaining > 0 THEN
            RAISE EXCEPTION 'تعذر تطبيق التخفيض بالكامل؛ المتبقي %', v_remaining;
        END IF;
    END IF;
END;
$$;

-- ==============================================================================
-- 10) Default installment trigger on new enrollments
-- ==============================================================================
CREATE OR REPLACE FUNCTION public.trg_fn_c1_default_installment()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_net   numeric(12,2);
    v_due   date;
    v_start date;
BEGIN
    v_net := COALESCE(NEW.total_due, 0) - COALESCE(NEW.discount_amount, 0);
    IF v_net <= 0 THEN RETURN NEW; END IF;

    IF NEW.currency IS NULL THEN
        RAISE EXCEPTION 'لا يمكن إنشاء خطة أقساط لتسجيل بلا عملة';
    END IF;

    SELECT c.starts_at::date INTO v_start
    FROM public.cohorts c WHERE c.id = NEW.cohort_id;

    v_due := GREATEST(
        COALESCE(v_start, (now() AT TIME ZONE 'Asia/Damascus')::date),
        (now() AT TIME ZONE 'Asia/Damascus')::date
    );

    INSERT INTO public.installment_schedule
      (enrollment_id, installment_number, due_date, amount, currency, notes, created_by)
    VALUES
      (NEW.id, 1, v_due, v_net, NEW.currency,
       'قسط افتراضي آلي (Phase C1)', auth.uid())
    ON CONFLICT (enrollment_id, installment_number) DO NOTHING;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_c1_default_installment ON public.enrollments;
CREATE TRIGGER trg_c1_default_installment
AFTER INSERT ON public.enrollments
FOR EACH ROW EXECUTE FUNCTION public.trg_fn_c1_default_installment();

-- ==============================================================================
-- 11) Enrollment fee changes trigger
-- ==============================================================================
CREATE OR REPLACE FUNCTION public.trg_fn_c1_enrollment_fee_changed()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_old_net numeric(12,2);
    v_new_net numeric(12,2);
BEGIN
    IF NEW.total_due IS NOT DISTINCT FROM OLD.total_due
       AND NEW.discount_amount IS NOT DISTINCT FROM OLD.discount_amount THEN
        RETURN NEW;
    END IF;

    IF NOT public.enrollment_status_occupies_seat(NEW.status::text) THEN
        RETURN NEW;
    END IF;

    v_old_net := COALESCE(OLD.total_due, 0) - COALESCE(OLD.discount_amount, 0);
    v_new_net := COALESCE(NEW.total_due, 0) - COALESCE(NEW.discount_amount, 0);

    IF v_new_net IS DISTINCT FROM v_old_net THEN
        PERFORM public.c1_apply_plan_delta(NEW.id, v_new_net - v_old_net);
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_c1_enrollment_fee_changed ON public.enrollments;
CREATE TRIGGER trg_c1_enrollment_fee_changed
AFTER UPDATE OF total_due, discount_amount, status ON public.enrollments
FOR EACH ROW EXECUTE FUNCTION public.trg_fn_c1_enrollment_fee_changed();

-- ==============================================================================
-- 12) Payments guard and allocation triggers
-- ==============================================================================
CREATE OR REPLACE FUNCTION public.trg_fn_c1_payments_guard()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_enr record;
BEGIN
    IF NEW.amount IS NULL OR NEW.amount <= 0 THEN
        RAISE EXCEPTION 'مبلغ الدفعة يجب أن يكون أكبر من صفر';
    END IF;

    SELECT e.id, e.currency::text AS currency, e.status::text AS status
    INTO v_enr
    FROM public.enrollments e WHERE e.id = NEW.enrollment_id;

    IF v_enr.id IS NULL THEN
        RAISE EXCEPTION 'الدفعة يجب أن ترتبط بتسجيل صالح';
    END IF;

    IF NEW.currency::text IS DISTINCT FROM v_enr.currency THEN
        RAISE EXCEPTION 'عملة الدفعة (%) لا تطابق عملة التسجيل (%): الدفع بعملة مختلفة ممنوع',
            NEW.currency, v_enr.currency;
    END IF;

    IF TG_OP = 'INSERT' THEN
        RETURN NEW;
    END IF;

    IF (NEW.amount IS DISTINCT FROM OLD.amount
        OR NEW.currency IS DISTINCT FROM OLD.currency)
       AND EXISTS (SELECT 1 FROM public.payment_refunds rf WHERE rf.payment_id = OLD.id) THEN
        RAISE EXCEPTION 'لا يمكن تعديل مبلغ أو عملة دفعة صدر عنها استرداد';
    END IF;

    IF NEW.enrollment_id IS DISTINCT FROM OLD.enrollment_id THEN
        IF EXISTS (SELECT 1 FROM public.payment_allocations pa WHERE pa.payment_id = OLD.id) THEN
            RAISE EXCEPTION 'لا يمكن نقل دفعة مخصصة إلى تسجيل آخر';
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.trg_fn_c1_payments_after()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
BEGIN
    PERFORM public.c1_allocate_payment(NEW.id);
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_c1_payments_guard ON public.payments;
CREATE TRIGGER trg_c1_payments_guard
BEFORE INSERT OR UPDATE ON public.payments
FOR EACH ROW EXECUTE FUNCTION public.trg_fn_c1_payments_guard();

DROP TRIGGER IF EXISTS trg_c1_payments_after ON public.payments;
CREATE TRIGGER trg_c1_payments_after
AFTER INSERT OR UPDATE OF amount, currency, enrollment_id ON public.payments
FOR EACH ROW EXECUTE FUNCTION public.trg_fn_c1_payments_after();

-- ==============================================================================
-- 13) Refunds guard and triggers
-- ==============================================================================
CREATE OR REPLACE FUNCTION public.trg_fn_c1_refund_guard()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_paid  numeric(12,2);
    v_total numeric(12,2);
BEGIN
    IF auth.uid() IS NOT NULL AND NOT public.c1_is_admin() THEN
        RAISE EXCEPTION 'الاسترداد المالي متاح لمدير المركز فقط';
    END IF;

    IF TG_OP = 'UPDATE' THEN
        IF NEW.amount IS DISTINCT FROM OLD.amount
           OR NEW.payment_id IS DISTINCT FROM OLD.payment_id THEN
            RAISE EXCEPTION 'لا يمكن تعديل استرداد صادر: احذفه وأنشئ استرداداً جديداً';
        END IF;
        RETURN NEW;
    END IF;

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;

    SELECT p.amount INTO v_paid
    FROM public.payments p WHERE p.id = NEW.payment_id;

    IF v_paid IS NULL THEN
        RAISE EXCEPTION 'الدفعة غير موجودة';
    END IF;

    SELECT COALESCE(sum(rf.amount), 0) INTO v_total
    FROM public.payment_refunds rf
    WHERE rf.payment_id = NEW.payment_id;

    IF v_total + NEW.amount > v_paid THEN
        RAISE EXCEPTION 'مجموع الاستردادات (%) يتجاوز مبلغ الدفعة (%)',
            v_total + NEW.amount, v_paid;
    END IF;

    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.trg_fn_c1_refund_after()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_payment_id uuid;
BEGIN
    IF TG_OP = 'DELETE' THEN
        v_payment_id := OLD.payment_id;
    ELSE
        v_payment_id := NEW.payment_id;
    END IF;

    PERFORM public.c1_allocate_payment(v_payment_id);

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_c1_refund_guard ON public.payment_refunds;
CREATE TRIGGER trg_c1_refund_guard
BEFORE INSERT OR UPDATE OR DELETE ON public.payment_refunds
FOR EACH ROW EXECUTE FUNCTION public.trg_fn_c1_refund_guard();

DROP TRIGGER IF EXISTS trg_c1_refund_after ON public.payment_refunds;
CREATE TRIGGER trg_c1_refund_after
AFTER INSERT OR DELETE ON public.payment_refunds
FOR EACH ROW EXECUTE FUNCTION public.trg_fn_c1_refund_after();

-- ==============================================================================
-- 14) Fee adjustments guard and triggers
-- ==============================================================================
CREATE OR REPLACE FUNCTION public.trg_fn_c1_adjustment_apply()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_enrollment_id uuid;
    v_delta         numeric(12,2);
BEGIN
    IF auth.uid() IS NOT NULL AND NOT public.c1_is_admin() THEN
        RAISE EXCEPTION 'تعديل الرسوم متاح لمدير المركز فقط';
    END IF;

    IF TG_OP = 'UPDATE' THEN
        RAISE EXCEPTION 'لا يمكن تعديل قيد رسوم صادر: احذفه وأنشئ قيداً معاكساً';
    END IF;

    IF TG_OP = 'DELETE' THEN
        v_enrollment_id := OLD.enrollment_id;
        v_delta := -OLD.amount;
    ELSE
        v_enrollment_id := NEW.enrollment_id;
        v_delta := NEW.amount;
    END IF;

    PERFORM public.c1_apply_plan_delta(v_enrollment_id, v_delta);

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_c1_adjustment_apply ON public.fee_adjustments;
CREATE TRIGGER trg_c1_adjustment_apply
AFTER INSERT OR DELETE ON public.fee_adjustments
FOR EACH ROW EXECUTE FUNCTION public.trg_fn_c1_adjustment_apply();

DROP TRIGGER IF EXISTS trg_c1_adjustment_guard ON public.fee_adjustments;
CREATE TRIGGER trg_c1_adjustment_guard
BEFORE UPDATE ON public.fee_adjustments
FOR EACH ROW EXECUTE FUNCTION public.trg_fn_c1_adjustment_apply();

-- ==============================================================================
-- 15) Installment schedule guard
-- ==============================================================================
CREATE OR REPLACE FUNCTION public.trg_fn_c1_installment_guard()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_currency  text;
    v_status    text;
    v_allocated numeric(12,2);
BEGIN
    IF current_setting('c1.replanning', true) = 'on' THEN
        IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
        RETURN NEW;
    END IF;

    IF TG_OP = 'INSERT' THEN
        SELECT e.currency::text, e.status::text INTO v_currency, v_status
        FROM public.enrollments e WHERE e.id = NEW.enrollment_id;

        IF v_currency IS NULL THEN
            RAISE EXCEPTION 'التسجيل غير موجود';
        END IF;
        IF NEW.currency::text IS DISTINCT FROM v_currency THEN
            RAISE EXCEPTION 'عملة القسط (%) لا تطابق عملة التسجيل (%)',
                NEW.currency, v_currency;
        END IF;
        IF NOT public.enrollment_status_occupies_seat(v_status) THEN
            RAISE EXCEPTION 'لا يمكن إنشاء أقساط لتسجيل بحالة (%)', v_status;
        END IF;
        RETURN NEW;
    END IF;

    IF TG_OP = 'UPDATE' THEN
        IF NEW.enrollment_id IS DISTINCT FROM OLD.enrollment_id THEN
            RAISE EXCEPTION 'لا يمكن نقل القسط إلى تسجيل آخر';
        END IF;
        IF NEW.currency IS DISTINCT FROM OLD.currency THEN
            RAISE EXCEPTION 'لا يمكن تغيير عملة القسط';
        END IF;

        SELECT COALESCE(sum(a.amount), 0) INTO v_allocated
        FROM public.payment_allocations a
        WHERE a.installment_id = NEW.id;

        IF NEW.amount < v_allocated THEN
            RAISE EXCEPTION 'لا يمكن إنقاص القسط إلى ما دون المبلغ المخصص له (%)', v_allocated;
        END IF;
        RETURN NEW;
    END IF;

    IF TG_OP = 'DELETE' THEN
        IF EXISTS (SELECT 1 FROM public.payment_allocations a WHERE a.installment_id = OLD.id) THEN
            RAISE EXCEPTION 'لا يمكن حذف قسط مخصص له دفعات';
        END IF;
        RETURN OLD;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_c1_installment_guard ON public.installment_schedule;
CREATE TRIGGER trg_c1_installment_guard
BEFORE INSERT OR UPDATE OR DELETE ON public.installment_schedule
FOR EACH ROW EXECUTE FUNCTION public.trg_fn_c1_installment_guard();

-- ==============================================================================
-- 16) RPC: set_installment_plan (إعادة هيكلة أقساط تسجيل)
-- ==============================================================================
CREATE OR REPLACE FUNCTION public.set_installment_plan(
    p_enrollment_id uuid,
    p_installments  jsonb,
    p_notes         text DEFAULT NULL
)
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_enr       record;
    v_paid      numeric(12,2);
    v_net       numeric(12,2);
    v_count     integer;
    v_sum       numeric(12,2) := 0;
    v_amount    numeric(12,2);
    v_due       date;
    v_i         integer;
    v_payment   record;
BEGIN
    IF NOT public.c1_is_staff() THEN
        RAISE EXCEPTION 'إعادة تخطيط الأقساط متاح لموظفي المركز فقط';
    END IF;

    PERFORM pg_advisory_xact_lock(
        hashtextextended('c1_plan:' || p_enrollment_id::text, 0)
    );

    SELECT e.id, e.currency, e.status::text AS status,
           COALESCE(e.total_due, 0) - COALESCE(e.discount_amount, 0) +
           COALESCE((SELECT sum(fa.amount) FROM public.fee_adjustments fa
                     WHERE fa.enrollment_id = e.id), 0) AS net
    INTO v_enr
    FROM public.enrollments e
    WHERE e.id = p_enrollment_id;

    IF v_enr.id IS NULL THEN
        RAISE EXCEPTION 'التسجيل غير موجود';
    END IF;

    IF NOT public.enrollment_status_occupies_seat(v_enr.status) THEN
        RAISE EXCEPTION 'لا يمكن إعادة تخطيط أقساط تسجيل بحالة (%)', v_enr.status;
    END IF;

    v_net := v_enr.net;
    IF v_net <= 0 THEN
        RAISE EXCEPTION 'صافي الرسوم (%) لا يسمح بإنشاء خطة أقساط', v_net;
    END IF;

    SELECT COALESCE(sum(p.amount), 0) - COALESCE((
        SELECT sum(rf.amount) FROM public.payment_refunds rf
        JOIN public.payments p2 ON p2.id = rf.payment_id
        WHERE p2.enrollment_id = p_enrollment_id
    ), 0)
    INTO v_paid
    FROM public.payments p
    WHERE p.enrollment_id = p_enrollment_id;

    IF jsonb_typeof(p_installments) <> 'array' THEN
        RAISE EXCEPTION 'خطة الأقساط يجب أن تكون مصفوفة JSON';
    END IF;

    v_count := jsonb_array_length(p_installments);
    IF v_count <= 0 THEN
        RAISE EXCEPTION 'يجب تحديد قسط واحد على الأقل';
    END IF;

    FOR v_i IN 0 .. v_count - 1 LOOP
        v_amount := NULLIF(p_installments -> v_i ->> 'amount', '')::numeric;
        v_due    := NULLIF(p_installments -> v_i ->> 'due_date', '')::date;

        IF v_amount IS NULL OR v_amount <= 0 THEN
            RAISE EXCEPTION 'مبلغ القسط % غير صالح', v_i + 1;
        END IF;
        IF v_due IS NULL THEN
            RAISE EXCEPTION 'تاريخ استحقاق القسط % غير صالح', v_i + 1;
        END IF;

        v_sum := v_sum + v_amount;
    END LOOP;

    IF round(v_sum, 2) <> round(v_net, 2) THEN
        RAISE EXCEPTION 'مجموع الأقساط (%) لا يطابق صافي الرسوم (%)', v_sum, v_net;
    END IF;

    PERFORM set_config('c1.replanning', 'on', true);
    DELETE FROM public.installment_schedule s WHERE s.enrollment_id = p_enrollment_id;

    FOR v_i IN 0 .. v_count - 1 LOOP
        INSERT INTO public.installment_schedule
          (enrollment_id, installment_number, due_date, amount, currency, notes, created_by)
        VALUES
          (p_enrollment_id,
           v_i + 1,
           (p_installments -> v_i ->> 'due_date')::date,
           (p_installments -> v_i ->> 'amount')::numeric,
           v_enr.currency,
           COALESCE(p_notes, 'خطة أقساط معدّلة يدوياً'),
           auth.uid());
    END LOOP;
    PERFORM set_config('c1.replanning', '', true);

    FOR v_payment IN
        SELECT p.id FROM public.payments p
        WHERE p.enrollment_id = p_enrollment_id
          AND p.currency::text = v_enr.currency::text
        ORDER BY p.paid_at NULLS LAST, p.id
    LOOP
        PERFORM public.c1_allocate_payment(v_payment.id);
    END LOOP;

    RETURN v_count;
END;
$$;

-- ==============================================================================
-- 17) Security Policies & Grants
-- ==============================================================================
DROP POLICY IF EXISTS "staff_manage_installment_schedule" ON public.installment_schedule;
DROP POLICY IF EXISTS "staff_manage_payment_allocations" ON public.payment_allocations;
DROP POLICY IF EXISTS "admin_manage_payment_refunds" ON public.payment_refunds;
DROP POLICY IF EXISTS "admin_manage_fee_adjustments" ON public.fee_adjustments;
DROP POLICY IF EXISTS "staff_read_installment_schedule" ON public.installment_schedule;
DROP POLICY IF EXISTS "staff_read_payment_allocations" ON public.payment_allocations;

CREATE POLICY "staff_read_installment_schedule" ON public.installment_schedule
    FOR SELECT TO authenticated USING (public.c1_is_staff());

CREATE POLICY "staff_read_payment_allocations" ON public.payment_allocations
    FOR SELECT TO authenticated USING (public.c1_is_staff());

CREATE POLICY "admin_manage_payment_refunds" ON public.payment_refunds
    FOR ALL TO authenticated
    USING (public.c1_is_admin()) WITH CHECK (public.c1_is_admin());

CREATE POLICY "admin_manage_fee_adjustments" ON public.fee_adjustments
    FOR ALL TO authenticated
    USING (public.c1_is_admin()) WITH CHECK (public.c1_is_admin());

-- Permissions
REVOKE ALL ON public.installment_schedule FROM anon;
REVOKE ALL ON public.payment_allocations FROM anon;
REVOKE ALL ON public.payment_refunds FROM anon;
REVOKE ALL ON public.fee_adjustments FROM anon;

REVOKE INSERT, UPDATE, DELETE ON public.installment_schedule FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.payment_allocations FROM authenticated;

GRANT SELECT ON public.installment_schedule TO authenticated;
GRANT SELECT ON public.payment_allocations TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.payment_refunds TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.fee_adjustments TO authenticated;

GRANT SELECT ON public.enrollment_financial_summary_v2 TO authenticated;
GRANT SELECT ON public.trainee_statement_v TO authenticated;
GRANT SELECT ON public.overdue_installments_v TO authenticated;

REVOKE ALL ON public.enrollment_financial_summary_v2 FROM anon;
REVOKE ALL ON public.trainee_statement_v FROM anon;
REVOKE ALL ON public.overdue_installments_v FROM anon;

GRANT EXECUTE ON FUNCTION public.c1_staff_role() TO authenticated;
GRANT EXECUTE ON FUNCTION public.c1_is_staff() TO authenticated;
GRANT EXECUTE ON FUNCTION public.c1_is_admin() TO authenticated;
GRANT EXECUTE ON FUNCTION public.c1_can_read_financials(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.enrollment_status_occupies_seat(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_installment_plan(uuid, jsonb, text) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.set_installment_plan(uuid, jsonb, text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.c1_allocate_payment(uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.c1_apply_plan_delta(uuid, numeric) FROM PUBLIC, anon, authenticated;

COMMIT;

