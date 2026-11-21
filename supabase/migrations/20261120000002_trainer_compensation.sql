-- ============================================================================
-- Phase C3.1 — Trainer compensation agreements + cohort rate snapshots
-- ============================================================================
-- Management decisions (2026-11-20):
--   * Trainer fee = percentage of collected fees (payments - refunds), per
--     currency, no FX conversion.
--   * The percentage is frozen when a cohort is created, so later agreement
--     changes never retroact on an existing cohort.
--   * Trainer of record for a period = cohorts.trainer_id at generation time
--     (audited by the C3 audit triggers).
--
-- cohorts.trainer_id / course_id already exist (baseline:4783-4793), so no
-- join table is needed.
--
-- RLS is enabled here with no policies => deny-all until 20261120000005 adds
-- the admin policies. Never ship a window where these tables are readable.
--
-- Rebuild-safe: idempotent DDL.
-- ============================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS public.trainer_compensation_agreements (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    trainer_id uuid NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
    course_id uuid NOT NULL REFERENCES public.courses(id) ON DELETE CASCADE,
    rate_percent numeric(5,2) NOT NULL CHECK (rate_percent > 0 AND rate_percent <= 100),
    effective_from date NOT NULL,
    effective_to date,
    notes text,
    created_by uuid REFERENCES auth.users(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT tca_dates_ck CHECK (effective_to IS NULL OR effective_to >= effective_from)
);

COMMENT ON TABLE public.trainer_compensation_agreements IS
  'C3 effective-dated trainer percentages per course. Frozen into cohort_trainer_rate_snapshots when a cohort is created.';

CREATE INDEX IF NOT EXISTS idx_tca_trainer_course
  ON public.trainer_compensation_agreements (trainer_id, course_id, effective_from DESC);

-- Overlap guard: a trainer/course pair cannot have two overlapping periods.
CREATE OR REPLACE FUNCTION public.fn_c3_tca_overlap_guard() RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM public.trainer_compensation_agreements a
    WHERE a.id <> COALESCE(NEW.id, '00000000-0000-0000-0000-000000000000'::uuid)
      AND a.trainer_id = NEW.trainer_id
      AND a.course_id = NEW.course_id
      AND daterange(a.effective_from, COALESCE(a.effective_to, 'infinity'::date), '[]')
          && daterange(NEW.effective_from, COALESCE(NEW.effective_to, 'infinity'::date), '[]')
  ) THEN
    RAISE EXCEPTION 'تداخل في فترات نسبة المدرّب لنفس الدورة (trainer=%, course=%)',
      NEW.trainer_id, NEW.course_id;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_c3_tca_overlap ON public.trainer_compensation_agreements;
CREATE TRIGGER trg_c3_tca_overlap
  BEFORE INSERT OR UPDATE ON public.trainer_compensation_agreements
  FOR EACH ROW EXECUTE FUNCTION public.fn_c3_tca_overlap_guard();

ALTER TABLE public.trainer_compensation_agreements ENABLE ROW LEVEL SECURITY;

-- ----------------------------------------------------------------------------
-- Frozen rate per cohort (management decision: lock at cohort creation)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.cohort_trainer_rate_snapshots (
    cohort_id uuid PRIMARY KEY REFERENCES public.cohorts(id) ON DELETE CASCADE,
    trainer_id uuid NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
    course_id uuid NOT NULL REFERENCES public.courses(id) ON DELETE CASCADE,
    rate_percent numeric(5,2) CHECK (rate_percent > 0 AND rate_percent <= 100),
    agreement_id uuid REFERENCES public.trainer_compensation_agreements(id) ON DELETE SET NULL,
    locked_on date NOT NULL,
    locked_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.cohort_trainer_rate_snapshots IS
  'C3 frozen trainer percentage per cohort. rate_percent NULL = no agreement was resolvable; dues generation must refuse instead of guessing.';

CREATE INDEX IF NOT EXISTS idx_ctrs_agreement
  ON public.cohort_trainer_rate_snapshots (agreement_id);

CREATE OR REPLACE FUNCTION public.fn_c3_snapshot_cohort_trainer_rate() RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_on date := COALESCE(NEW.starts_at, CURRENT_DATE);
  v_rate numeric(5,2);
  v_agreement uuid;
BEGIN
  SELECT a.rate_percent, a.id
    INTO v_rate, v_agreement
    FROM public.trainer_compensation_agreements a
   WHERE a.trainer_id = NEW.trainer_id
     AND a.course_id = NEW.course_id
     AND a.effective_from <= v_on
     AND (a.effective_to IS NULL OR a.effective_to >= v_on)
   ORDER BY a.effective_from DESC
   LIMIT 1;

  INSERT INTO public.cohort_trainer_rate_snapshots
    (cohort_id, trainer_id, course_id, rate_percent, agreement_id, locked_on)
  VALUES
    (NEW.id, NEW.trainer_id, NEW.course_id, v_rate, v_agreement, v_on)
  ON CONFLICT (cohort_id) DO NOTHING;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_c3_snapshot_cohort_rate ON public.cohorts;
CREATE TRIGGER trg_c3_snapshot_cohort_rate
  AFTER INSERT ON public.cohorts
  FOR EACH ROW EXECUTE FUNCTION public.fn_c3_snapshot_cohort_trainer_rate();

ALTER TABLE public.cohort_trainer_rate_snapshots ENABLE ROW LEVEL SECURITY;

-- ----------------------------------------------------------------------------
-- Backfill: lock rates for existing cohorts where an agreement already
-- resolves. Cohorts without a resolvable agreement stay unlocked on purpose;
-- the admin locks them after entering the historical agreement (C3 RPCs),
-- instead of freezing a silent NULL now.
-- ----------------------------------------------------------------------------
INSERT INTO public.cohort_trainer_rate_snapshots
  (cohort_id, trainer_id, course_id, rate_percent, agreement_id, locked_on)
SELECT
  c.id,
  c.trainer_id,
  c.course_id,
  r.rate_percent,
  r.id,
  COALESCE(c.starts_at, CURRENT_DATE)
FROM public.cohorts c
JOIN LATERAL (
  SELECT a.rate_percent, a.id
    FROM public.trainer_compensation_agreements a
   WHERE a.trainer_id = c.trainer_id
     AND a.course_id = c.course_id
     AND a.effective_from <= COALESCE(c.starts_at, CURRENT_DATE)
     AND (a.effective_to IS NULL OR a.effective_to >= COALESCE(c.starts_at, CURRENT_DATE))
   ORDER BY a.effective_from DESC
   LIMIT 1
) r ON TRUE
WHERE NOT EXISTS (
  SELECT 1 FROM public.cohort_trainer_rate_snapshots s WHERE s.cohort_id = c.id
);

COMMIT;
