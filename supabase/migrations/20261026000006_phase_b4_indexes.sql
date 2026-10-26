-- ==============================================================================
-- Taj Dentics — Phase B4 closure patch (2026-10-26)
-- Cover the hot lookups introduced by B4:
--   * capacity guard counts active enrollments per cohort
--   * seat-status RPC lists cohorts per course
-- IF NOT EXISTS keeps the migration idempotent.
-- ==============================================================================

CREATE INDEX IF NOT EXISTS idx_enrollments_cohort_status
  ON public.enrollments (cohort_id, status);

CREATE INDEX IF NOT EXISTS idx_cohorts_course
  ON public.cohorts (course_id);
