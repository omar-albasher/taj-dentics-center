-- ==============================================================================
-- Taj Dentics Training Center - Phase C1: Installments & Trainee Statement (Report 5)
-- Migration: 20261105000000_phase_c1_installments.sql
-- ==============================================================================

BEGIN;

-- 1. Installment Schedule Table (جدول أقساط التسجيل)
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.installment_schedule (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    enrollment_id uuid NOT NULL REFERENCES public.enrollments(id) ON DELETE CASCADE,
    installment_number integer NOT NULL CHECK (installment_number > 0),
    due_date date NOT NULL,
    amount numeric(12,2) NOT NULL CHECK (amount > 0),
    currency public.currency_type NOT NULL,
    notes text,
    created_at timestamptz NOT NULL DEFAULT now(),
    created_by uuid REFERENCES auth.users(id),
    CONSTRAINT uq_enrollment_installment UNIQUE (enrollment_id, installment_number)
);

CREATE INDEX IF NOT EXISTS idx_installment_schedule_enrollment ON public.installment_schedule(enrollment_id);
CREATE INDEX IF NOT EXISTS idx_installment_schedule_due_date ON public.installment_schedule(due_date);

-- 2. Payment Allocations Table (جدول تخصيص الدفعات على الأقساط)
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.payment_allocations (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    payment_id uuid NOT NULL REFERENCES public.payments(id) ON DELETE CASCADE,
    installment_id uuid NOT NULL REFERENCES public.installment_schedule(id) ON DELETE CASCADE,
    amount numeric(12,2) NOT NULL CHECK (amount > 0),
    created_at timestamptz NOT NULL DEFAULT now(),
    created_by uuid REFERENCES auth.users(id),
    CONSTRAINT uq_payment_installment_allocation UNIQUE (payment_id, installment_id)
);

CREATE INDEX IF NOT EXISTS idx_payment_allocations_payment ON public.payment_allocations(payment_id);
CREATE INDEX IF NOT EXISTS idx_payment_allocations_installment ON public.payment_allocations(installment_id);

-- 3. Payment Refunds Table (جدول استرداد الدفعات - محصور بالإدارة)
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.payment_refunds (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    payment_id uuid NOT NULL REFERENCES public.payments(id) ON DELETE RESTRICT,
    amount numeric(12,2) NOT NULL CHECK (amount > 0),
    reason text NOT NULL,
    refunded_at timestamptz NOT NULL DEFAULT now(),
    created_at timestamptz NOT NULL DEFAULT now(),
    created_by uuid REFERENCES auth.users(id)
);

CREATE INDEX IF NOT EXISTS idx_payment_refunds_payment ON public.payment_refunds(payment_id);

-- 4. Fee Adjustments Table (جدول تعديل الرسوم - محصور بالإدارة)
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.fee_adjustments (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    enrollment_id uuid NOT NULL REFERENCES public.enrollments(id) ON DELETE CASCADE,
    amount numeric(12,2) NOT NULL CHECK (amount <> 0),
    reason text NOT NULL,
    adjusted_at timestamptz NOT NULL DEFAULT now(),
    created_at timestamptz NOT NULL DEFAULT now(),
    created_by uuid REFERENCES auth.users(id)
);

CREATE INDEX IF NOT EXISTS idx_fee_adjustments_enrollment ON public.fee_adjustments(enrollment_id);

-- 5. Backfill Existing Data: Default 1 installment for current enrollments
-- ------------------------------------------------------------------------------
INSERT INTO public.installment_schedule (enrollment_id, installment_number, due_date, amount, currency, notes)
SELECT 
    e.id,
    1,
    COALESCE(c.starts_at::date, c.created_at::date, CURRENT_DATE),
    GREATEST(e.total_due - e.discount_amount, 1),
    e.currency,
    'القسط الافتراضي الأساسي (تسوية تلقائية Phase C1)'
FROM public.enrollments e
LEFT JOIN public.cohorts c ON c.id = e.cohort_id
WHERE NOT EXISTS (
    SELECT 1 FROM public.installment_schedule s WHERE s.enrollment_id = e.id
)
AND (e.total_due - e.discount_amount) > 0;

-- 6. Backfill Existing Payments Allocation: Allocate existing payments to installment #1
-- ------------------------------------------------------------------------------
INSERT INTO public.payment_allocations (payment_id, installment_id, amount)
SELECT 
    p.id,
    s.id,
    p.amount
FROM public.payments p
JOIN public.installment_schedule s ON s.enrollment_id = p.enrollment_id AND s.installment_number = 1
WHERE NOT EXISTS (
    SELECT 1 FROM public.payment_allocations a WHERE a.payment_id = p.id
);

-- 7. View: enrollment_financial_summary_v2 (العرض المالي الشامل المطور)
-- ------------------------------------------------------------------------------
CREATE OR REPLACE VIEW public.enrollment_financial_summary_v2 AS
WITH payment_agg AS (
    SELECT 
        p.enrollment_id,
        COALESCE(SUM(p.amount), 0::numeric) AS gross_paid,
        COALESCE(SUM(r.amount), 0::numeric) AS total_refunded,
        COALESCE(SUM(p.amount), 0::numeric) - COALESCE(SUM(r.amount), 0::numeric) AS net_paid
    FROM public.payments p
    LEFT JOIN public.payment_refunds r ON r.payment_id = p.id
    GROUP BY p.enrollment_id
),
adjustment_agg AS (
    SELECT 
        fa.enrollment_id,
        COALESCE(SUM(fa.amount), 0::numeric) AS total_adjustments
    FROM public.fee_adjustments fa
    GROUP BY fa.enrollment_id
),
installment_agg AS (
    SELECT 
        s.enrollment_id,
        COUNT(s.id) AS total_installments,
        MIN(CASE WHEN COALESCE(alloc.allocated, 0) < s.amount THEN s.due_date END) AS next_due_date,
        COALESCE(SUM(CASE WHEN s.due_date < CURRENT_DATE THEN GREATEST(s.amount - COALESCE(alloc.allocated, 0), 0) ELSE 0 END), 0::numeric) AS overdue_balance
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
    (e.total_due - e.discount_amount + COALESCE(adj.total_adjustments, 0::numeric)) AS net_due,
    COALESCE(pa.gross_paid, 0::numeric) AS gross_paid,
    COALESCE(pa.total_refunded, 0::numeric) AS total_refunded,
    COALESCE(pa.net_paid, 0::numeric) AS net_paid,
    ((e.total_due - e.discount_amount + COALESCE(adj.total_adjustments, 0::numeric)) - COALESCE(pa.net_paid, 0::numeric)) AS current_balance,
    COALESCE(ia.total_installments, 0) AS total_installments,
    ia.next_due_date,
    COALESCE(ia.overdue_balance, 0::numeric) AS overdue_balance
FROM public.enrollments e
JOIN public.trainees t ON t.id = e.trainee_id
JOIN public.users u ON u.id = t.user_id
JOIN public.cohorts co ON co.id = e.cohort_id
LEFT JOIN payment_agg pa ON pa.enrollment_id = e.id
LEFT JOIN adjustment_agg adj ON adj.enrollment_id = e.id
LEFT JOIN installment_agg ia ON ia.enrollment_id = e.id;

-- 8. View: trainee_statement_v (تقرير 5: كشف حساب المتدرب التفصيلي)
-- ------------------------------------------------------------------------------
CREATE OR REPLACE VIEW public.trainee_statement_v AS
WITH ledger_entries AS (
    -- 1. Initial Course Fee (Debit)
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

    -- 2. Initial Discount (Credit)
    SELECT 
        e.id AS enrollment_id,
        e.trainee_id,
        e.id::text || '_disc' AS entry_id,
        COALESCE(co.starts_at, co.created_at, now()) AS entry_date,
        'discount' AS entry_type,
        'خصم تسجيل معتمد' AS description,
        0::numeric AS debit,
        e.discount_amount AS credit,
        e.currency
    FROM public.enrollments e
    JOIN public.cohorts co ON co.id = e.cohort_id
    WHERE e.discount_amount > 0

    UNION ALL

    -- 3. Fee Adjustments (Debit if positive, Credit if negative)
    SELECT 
        fa.enrollment_id,
        e.trainee_id,
        fa.id::text AS entry_id,
        fa.adjusted_at AS entry_date,
        'fee_adjustment' AS entry_type,
        'تعديل رسوم: ' || fa.reason AS description,
        CASE WHEN fa.amount > 0 THEN fa.amount ELSE 0::numeric END AS debit,
        CASE WHEN fa.amount < 0 THEN ABS(fa.amount) ELSE 0::numeric END AS credit,
        e.currency
    FROM public.fee_adjustments fa
    JOIN public.enrollments e ON e.id = fa.enrollment_id

    UNION ALL

    -- 4. Payments (Credit)
    SELECT 
        p.enrollment_id,
        e.trainee_id,
        p.id::text AS entry_id,
        p.paid_at AS entry_date,
        'payment' AS entry_type,
        'دفعة نقدية/تحويل - إيصال #' || COALESCE(p.receipt_number, substring(p.id::text, 1, 8)) AS description,
        0::numeric AS debit,
        p.amount AS credit,
        p.currency
    FROM public.payments p
    JOIN public.enrollments e ON e.id = p.enrollment_id

    UNION ALL

    -- 5. Refunds (Debit)
    SELECT 
        p.enrollment_id,
        e.trainee_id,
        r.id::text AS entry_id,
        r.refunded_at AS entry_date,
        'refund' AS entry_type,
        'استرداد دفعة: ' || r.reason AS description,
        r.amount AS debit,
        0::numeric AS credit,
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
                     WHEN 'initial_fee' THEN 1 
                     WHEN 'discount' THEN 2 
                     WHEN 'fee_adjustment' THEN 3 
                     WHEN 'payment' THEN 4 
                     WHEN 'refund' THEN 5 
                     ELSE 6 
                 END,
                 le.entry_id ASC
    ) AS running_balance
FROM ledger_entries le
JOIN public.trainees t ON t.id = le.trainee_id
JOIN public.users u ON u.id = t.user_id
WHERE (
    t.user_id = auth.uid()
    OR auth.role() = 'service_role'
    OR (auth.jwt() ->> 'role') = 'service_role'
    OR current_user = 'postgres'
    OR EXISTS (
        SELECT 1 FROM public.users u2 
        WHERE u2.id = auth.uid() 
          AND u2.is_active = true 
          AND u2.role::text IN ('admin', 'reception', 'accountant')
    )
);

-- 9. View: overdue_installments_v (الأقساط المستحقة المتأخرة)
-- ------------------------------------------------------------------------------
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
    (CURRENT_DATE - s.due_date) AS days_overdue
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
WHERE s.due_date < CURRENT_DATE
  AND (s.amount - COALESCE(alloc.allocated, 0::numeric)) > 0;

-- 10. Row Level Security & Policies
-- ------------------------------------------------------------------------------
ALTER TABLE public.installment_schedule ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payment_allocations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payment_refunds ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.fee_adjustments ENABLE ROW LEVEL SECURITY;

-- installment_schedule: Staff can view and manage
DROP POLICY IF EXISTS "staff_manage_installment_schedule" ON public.installment_schedule;
CREATE POLICY "staff_manage_installment_schedule" ON public.installment_schedule
    FOR ALL TO authenticated
    USING (EXISTS (
        SELECT 1 FROM public.users u 
        WHERE u.id = auth.uid() 
          AND u.is_active = true 
          AND u.role::text IN ('admin', 'reception', 'accountant')
    ));

-- installment_schedule: Trainees can read their own
DROP POLICY IF EXISTS "trainee_read_installment_schedule" ON public.installment_schedule;
CREATE POLICY "trainee_read_installment_schedule" ON public.installment_schedule
    FOR SELECT TO authenticated
    USING (EXISTS (
        SELECT 1 FROM public.enrollments e
        JOIN public.trainees t ON t.id = e.trainee_id
        WHERE e.id = installment_schedule.enrollment_id AND t.user_id = auth.uid()
    ));

-- payment_allocations: Staff can view and manage
DROP POLICY IF EXISTS "staff_manage_payment_allocations" ON public.payment_allocations;
CREATE POLICY "staff_manage_payment_allocations" ON public.payment_allocations
    FOR ALL TO authenticated
    USING (EXISTS (
        SELECT 1 FROM public.users u 
        WHERE u.id = auth.uid() 
          AND u.is_active = true 
          AND u.role::text IN ('admin', 'reception', 'accountant')
    ));

-- payment_allocations: Trainees can read their own
DROP POLICY IF EXISTS "trainee_read_payment_allocations" ON public.payment_allocations;
CREATE POLICY "trainee_read_payment_allocations" ON public.payment_allocations
    FOR SELECT TO authenticated
    USING (EXISTS (
        SELECT 1 FROM public.payments p
        JOIN public.enrollments e ON e.id = p.enrollment_id
        JOIN public.trainees t ON t.id = e.trainee_id
        WHERE p.id = payment_allocations.payment_id AND t.user_id = auth.uid()
    ));

-- payment_refunds: Strict Admin-Only
DROP POLICY IF EXISTS "admin_manage_payment_refunds" ON public.payment_refunds;
CREATE POLICY "admin_manage_payment_refunds" ON public.payment_refunds
    FOR ALL TO authenticated
    USING (EXISTS (
        SELECT 1 FROM public.users u 
        WHERE u.id = auth.uid() 
          AND u.is_active = true 
          AND u.role::text = 'admin'
    ));

-- fee_adjustments: Strict Admin-Only
DROP POLICY IF EXISTS "admin_manage_fee_adjustments" ON public.fee_adjustments;
CREATE POLICY "admin_manage_fee_adjustments" ON public.fee_adjustments
    FOR ALL TO authenticated
    USING (EXISTS (
        SELECT 1 FROM public.users u 
        WHERE u.id = auth.uid() 
          AND u.is_active = true 
          AND u.role::text = 'admin'
    ));

-- 11. Permissions Grants
-- ------------------------------------------------------------------------------
GRANT SELECT, INSERT, UPDATE, DELETE ON public.installment_schedule TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.payment_allocations TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.payment_refunds TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.fee_adjustments TO authenticated;

GRANT SELECT ON public.enrollment_financial_summary_v2 TO authenticated;
GRANT SELECT ON public.trainee_statement_v TO authenticated;
GRANT SELECT ON public.overdue_installments_v TO authenticated;

COMMIT;

