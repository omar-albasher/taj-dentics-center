-- ==============================================================================
-- Taj Dentics Training Center - Phase A3: Trainee Payment Receipts View
-- Migration: 20261022000003_phase_a3_trainee_payment_receipts.sql
-- ==============================================================================

-- Secure view for trainees to query their own individual payments/receipts.
-- Pre-joins course, cohort, trainee name, and trainee code.
-- Strictly filters by authenticated trainee user_id.

DROP VIEW IF EXISTS public.trainee_payment_receipts CASCADE;

CREATE VIEW public.trainee_payment_receipts AS
SELECT
    p.id AS payment_id,
    p.enrollment_id,
    p.amount,
    p.currency,
    p.paid_at,
    p.method AS payment_method,
    p.receipt_number,
    p.external_reference,
    p.notes,
    c.id AS course_id,
    c.name AS course_name,
    ch.id AS cohort_id,
    ch.name AS cohort_name,
    t.id AS trainee_id,
    t.trainee_code,
    u.full_name AS trainee_name
FROM public.payments p
JOIN public.enrollments e ON e.id = p.enrollment_id
JOIN public.cohorts ch ON ch.id = e.cohort_id
JOIN public.courses c ON c.id = ch.course_id
JOIN public.trainees t ON t.id = e.trainee_id
JOIN public.users u ON u.id = t.user_id
WHERE (
    t.user_id = auth.uid()
    OR auth.role() = 'service_role'
    OR (auth.jwt() ->> 'role') = 'service_role'
    OR current_user = 'postgres'
);

GRANT SELECT ON public.trainee_payment_receipts TO authenticated;
