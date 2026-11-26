-- ============================================================================
-- Phase C6 — Cohort Contribution Margin (read-only analytics)
-- File: supabase/migrations/20261125000001_phase_c6_cohort_contribution.sql
--
-- Managerial unit-economics view per (cohort, currency), as of a Damascus
-- business-day cutoff:
--   earned_revenue      = SUM(C5 earned_revenue) grouped by (cohort, currency)
--   trainer_cost        = SUM(trainer_dues.amount) where status <> 'cancelled'
--                         and period_end <= p_as_of (months ended by as-of)
--   contribution_margin = earned_revenue - trainer_cost
--   margin_ratio        = margin / earned, NULL when earned = 0 (unbounded)
--   trainees_count      = COUNT(DISTINCT trainee_id) over as-of enrollments
--   has_trainer_cost    = EXISTS a non-cancelled due row with period_end <= p_as_of
--
-- This is NOT net profit per cohort: shared/administrative expenses are not
-- attributable to a cohort in the current schema (expenses has no cohort_id),
-- and C3 trainer dues are computed on monthly cash collections after close.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.get_cohort_contribution_report(
  p_as_of date
) RETURNS TABLE (
  cohort_id uuid,
  cohort_name text,
  course_name text,
  currency text,
  earned_revenue numeric,
  trainer_cost numeric,
  contribution_margin numeric,
  margin_ratio numeric,
  trainees_count int,
  has_trainer_cost boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
#variable_conflict use_column
BEGIN
  -- 1. Security guard: Admin only
  IF NOT public.c1_is_admin() THEN
    RAISE EXCEPTION 'غير مصرّح: تقرير هامش مساهمة الأفواج متاح لمدير المركز فقط'
      USING ERRCODE = 'P0001';
  END IF;

  IF p_as_of IS NULL THEN
    RAISE EXCEPTION 'تاريخ التقرير مطلوب'
      USING ERRCODE = 'P0002';
  END IF;

  RETURN QUERY
  WITH revenue AS (
    SELECT
      r.cohort_id,
      max(r.cohort_name) AS cohort_name,
      max(r.course_name) AS course_name,
      r.currency,
      sum(r.earned_revenue)::numeric AS earned_revenue,
      count(DISTINCT r.trainee_id)::int AS trainees_count
    FROM public.get_accrual_revenue_report(p_as_of) AS r
    GROUP BY r.cohort_id, r.currency
  ),
  trainer AS (
    SELECT
      d.cohort_id,
      co.name AS cohort_name,
      c.name AS course_name,
      d.currency::text AS currency,
      sum(d.amount)::numeric AS trainer_cost
    FROM public.trainer_dues AS d
    JOIN public.cohorts AS co ON co.id = d.cohort_id
    JOIN public.courses AS c ON c.id = co.course_id
    WHERE d.status <> 'cancelled'
      AND d.period_end <= p_as_of
    GROUP BY d.cohort_id, co.name, c.name, d.currency
  ),
  merged AS (
    SELECT
      coalesce(rv.cohort_id, tr.cohort_id) AS cohort_id,
      coalesce(rv.cohort_name, tr.cohort_name) AS cohort_name,
      coalesce(rv.course_name, tr.course_name) AS course_name,
      coalesce(rv.currency, tr.currency) AS currency,
      coalesce(rv.earned_revenue, 0.00) AS earned_revenue,
      coalesce(tr.trainer_cost, 0.00) AS trainer_cost,
      coalesce(rv.trainees_count, 0) AS trainees_count,
      (tr.cohort_id IS NOT NULL) AS has_trainer_cost
    FROM revenue AS rv
    FULL OUTER JOIN trainer AS tr
      ON tr.cohort_id = rv.cohort_id
     AND tr.currency = rv.currency
  )
  SELECT
    m.cohort_id,
    m.cohort_name,
    m.course_name,
    m.currency,
    m.earned_revenue,
    m.trainer_cost,
    (m.earned_revenue - m.trainer_cost) AS contribution_margin,
    CASE
      WHEN m.earned_revenue > 0
        THEN (m.earned_revenue - m.trainer_cost) / m.earned_revenue
      ELSE NULL::numeric
    END AS margin_ratio,
    m.trainees_count,
    m.has_trainer_cost
  FROM merged AS m
  ORDER BY m.currency, m.cohort_name;
END;
$$;

COMMENT ON FUNCTION public.get_cohort_contribution_report(date) IS
  'C6 read-only cohort contribution margin: C5 accrual earned revenue minus C3 trainer dues for months ended by the as-of date. Managerial margin before shared expenses; trainer dues are cash-collection based and monthly.';

REVOKE ALL ON FUNCTION public.get_cohort_contribution_report(date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_cohort_contribution_report(date) TO authenticated, service_role;
