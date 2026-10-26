-- ==============================================================================
-- Migration: 20261025000004_phase_b4_course_waitlist.sql
-- Phase B4: Cohort Capacity + FIFO Course Waitlist (Hardened)
--
-- Design guarantees:
--   1. Capacity is enforced in PostgreSQL for every enrollment path,
--      including direct PostgREST inserts, via a row-locked BEFORE trigger.
--   2. Capacity can never be lowered below the active enrollment count.
--   3. Waitlist rows are validated on insert and follow a strict state machine.
--   4. Concurrent enrollment / waitlist / promotion operations serialize on the
--      cohort row, so the FIFO order and seat count stay consistent.
--   5. Trainees can only see their own waitlist rows; they mutate through RPCs.
--   6. Seat-available notifications are deduplicated and never block an
--      enrollment operation (exception-guarded triggers).
--
-- Existing cohorts keep capacity = NULL (unlimited). Set explicit capacities
-- manually only after checking the current enrollment count.
-- ==============================================================================

-- 1. Predicate: which enrollment statuses occupy a seat
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.enrollment_status_occupies_seat(p_status TEXT)
RETURNS BOOLEAN
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
SET search_path = public, pg_temp
AS $$
  SELECT COALESCE(NULLIF(trim(p_status), ''), 'active')
         NOT IN ('dropped', 'cancelled', 'canceled', 'withdrawn', 'refunded');
$$;

REVOKE ALL ON FUNCTION public.enrollment_status_occupies_seat(TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.enrollment_status_occupies_seat(TEXT) TO service_role;

-- 2. Capacity column (nullable = unlimited)
-- ------------------------------------------------------------------------------
ALTER TABLE public.cohorts ADD COLUMN IF NOT EXISTS capacity INTEGER;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conrelid = 'public.cohorts'::regclass
      AND conname = 'cohorts_capacity_positive'
  ) THEN
    ALTER TABLE public.cohorts
      ADD CONSTRAINT cohorts_capacity_positive
      CHECK (capacity IS NULL OR capacity > 0);
  END IF;
END $$;

-- 3. Active enrollment count helper
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.cohort_active_enrollment_count(p_cohort_id UUID)
RETURNS INTEGER
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT count(*)::INTEGER
  FROM public.enrollments e
  WHERE e.cohort_id = p_cohort_id
    AND public.enrollment_status_occupies_seat(e.status::text);
$$;

REVOKE ALL ON FUNCTION public.cohort_active_enrollment_count(UUID) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.cohort_active_enrollment_count(UUID) TO service_role;

-- 4. Hard capacity guard on enrollments (all insert/update paths)
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.trg_fn_enforce_cohort_capacity()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_capacity INTEGER;
  v_count INTEGER;
BEGIN
  IF NOT public.enrollment_status_occupies_seat(NEW.status::text) THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'UPDATE'
     AND NEW.cohort_id = OLD.cohort_id
     AND NEW.status IS NOT DISTINCT FROM OLD.status THEN
    RETURN NEW;
  END IF;

  SELECT c.capacity
  INTO v_capacity
  FROM public.cohorts c
  WHERE c.id = NEW.cohort_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'COHORT_NOT_FOUND' USING ERRCODE = 'P0001';
  END IF;

  IF v_capacity IS NULL THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'UPDATE' THEN
    SELECT count(*)
    INTO v_count
    FROM public.enrollments e
    WHERE e.cohort_id = NEW.cohort_id
      AND e.id <> OLD.id
      AND public.enrollment_status_occupies_seat(e.status::text);
  ELSE
    SELECT count(*)
    INTO v_count
    FROM public.enrollments e
    WHERE e.cohort_id = NEW.cohort_id
      AND public.enrollment_status_occupies_seat(e.status::text);
  END IF;

  IF v_count >= v_capacity THEN
    RAISE EXCEPTION 'COHORT_CAPACITY_REACHED'
      USING ERRCODE = 'P0001',
            DETAIL = format('cohort=%s active=%s capacity=%s',
                            NEW.cohort_id, v_count, v_capacity);
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_enrollments_capacity_guard ON public.enrollments;
CREATE TRIGGER trg_enrollments_capacity_guard
BEFORE INSERT OR UPDATE OF cohort_id, status
ON public.enrollments
FOR EACH ROW
EXECUTE FUNCTION public.trg_fn_enforce_cohort_capacity();

-- 5. Prevent lowering capacity below the active enrollment count
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.trg_fn_validate_cohort_capacity()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_count INTEGER;
BEGIN
  IF NEW.capacity IS NOT NULL AND NEW.capacity <= 0 THEN
    RAISE EXCEPTION 'COHORT_CAPACITY_INVALID' USING ERRCODE = 'P0001';
  END IF;

  IF TG_OP = 'UPDATE' AND NEW.capacity IS NOT DISTINCT FROM OLD.capacity THEN
    RETURN NEW;
  END IF;

  IF NEW.capacity IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT count(*)
  INTO v_count
  FROM public.enrollments e
  WHERE e.cohort_id = NEW.id
    AND public.enrollment_status_occupies_seat(e.status::text);

  IF v_count > NEW.capacity THEN
    RAISE EXCEPTION 'COHORT_CAPACITY_BELOW_ENROLLED'
      USING ERRCODE = 'P0001',
            DETAIL = format('cohort=%s active=%s requested_capacity=%s',
                            NEW.id, v_count, NEW.capacity);
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_cohorts_capacity_guard ON public.cohorts;
CREATE TRIGGER trg_cohorts_capacity_guard
BEFORE INSERT OR UPDATE OF capacity
ON public.cohorts
FOR EACH ROW
EXECUTE FUNCTION public.trg_fn_validate_cohort_capacity();

-- 6. Waitlist table
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.course_waitlist (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  cohort_id UUID NOT NULL,
  trainee_id UUID NOT NULL,
  status TEXT NOT NULL DEFAULT 'waiting',
  joined_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
  notified_at TIMESTAMPTZ,
  expires_at TIMESTAMPTZ,
  promoted_at TIMESTAMPTZ,
  promoted_by UUID,
  cancelled_at TIMESTAMPTZ,
  created_by UUID,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT course_waitlist_cohort_id_fkey
    FOREIGN KEY (cohort_id) REFERENCES public.cohorts(id) ON DELETE CASCADE,
  CONSTRAINT course_waitlist_trainee_id_fkey
    FOREIGN KEY (trainee_id) REFERENCES public.trainees(id) ON DELETE CASCADE,
  CONSTRAINT course_waitlist_created_by_fkey
    FOREIGN KEY (created_by) REFERENCES public.users(id) ON DELETE SET NULL,
  CONSTRAINT course_waitlist_promoted_by_fkey
    FOREIGN KEY (promoted_by) REFERENCES public.users(id) ON DELETE SET NULL,
  CONSTRAINT course_waitlist_status_check
    CHECK (status IN ('waiting', 'notified', 'enrolled', 'cancelled', 'expired')),
  CONSTRAINT course_waitlist_notified_fields_check
    CHECK (status <> 'notified' OR (notified_at IS NOT NULL AND expires_at IS NOT NULL)),
  CONSTRAINT course_waitlist_expiry_order_check
    CHECK (expires_at IS NULL OR notified_at IS NULL OR expires_at > notified_at),
  CONSTRAINT course_waitlist_promoted_fields_check
    CHECK (status <> 'enrolled' OR promoted_at IS NOT NULL)
);

-- Only one active waitlist row per trainee/cohort.
CREATE UNIQUE INDEX IF NOT EXISTS uq_course_waitlist_active
ON public.course_waitlist (cohort_id, trainee_id)
WHERE status IN ('waiting', 'notified');

-- FIFO selection.
CREATE INDEX IF NOT EXISTS idx_course_waitlist_fifo
ON public.course_waitlist (cohort_id, joined_at, id)
WHERE status = 'waiting';

-- Expiry sweeper.
CREATE INDEX IF NOT EXISTS idx_course_waitlist_notified_expiry
ON public.course_waitlist (expires_at)
WHERE status = 'notified';

-- Trainee status lookup and admin cohort listing.
CREATE INDEX IF NOT EXISTS idx_course_waitlist_trainee_status
ON public.course_waitlist (trainee_id, status, joined_at DESC);

CREATE INDEX IF NOT EXISTS idx_course_waitlist_cohort_status
ON public.course_waitlist (cohort_id, status, joined_at);

-- 7. Waitlist state-machine + insert invariants
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.trg_fn_validate_waitlist_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_capacity INTEGER;
  v_cohort_active BOOLEAN;
  v_course_active BOOLEAN;
  v_active_count INTEGER;
BEGIN
  IF NEW.status <> 'waiting' THEN
    RAISE EXCEPTION 'WAITLIST_INITIAL_STATUS_INVALID' USING ERRCODE = 'P0001';
  END IF;

  SELECT c.capacity, c.is_active, co.is_active
  INTO v_capacity, v_cohort_active, v_course_active
  FROM public.cohorts c
  JOIN public.courses co ON co.id = c.course_id
  WHERE c.id = NEW.cohort_id
  FOR UPDATE OF c;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'COHORT_NOT_FOUND' USING ERRCODE = 'P0001';
  END IF;

  IF NOT v_cohort_active OR NOT v_course_active THEN
    RAISE EXCEPTION 'COHORT_NOT_ACTIVE' USING ERRCODE = 'P0001';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.trainees t
    JOIN public.users u ON u.id = t.user_id
    WHERE t.id = NEW.trainee_id
      AND u.is_active = true
  ) THEN
    RAISE EXCEPTION 'TRAINEE_NOT_FOUND' USING ERRCODE = 'P0001';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.enrollments e
    WHERE e.cohort_id = NEW.cohort_id
      AND e.trainee_id = NEW.trainee_id
      AND public.enrollment_status_occupies_seat(e.status::text)
  ) THEN
    RAISE EXCEPTION 'ALREADY_ENROLLED' USING ERRCODE = 'P0001';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.course_waitlist w
    WHERE w.cohort_id = NEW.cohort_id
      AND w.trainee_id = NEW.trainee_id
      AND w.status IN ('waiting', 'notified')
  ) THEN
    RAISE EXCEPTION 'ALREADY_ON_WAITLIST' USING ERRCODE = 'P0001';
  END IF;

  v_active_count := public.cohort_active_enrollment_count(NEW.cohort_id);

  IF v_capacity IS NULL OR v_active_count < v_capacity THEN
    RAISE EXCEPTION 'COHORT_HAS_AVAILABLE_SEATS' USING ERRCODE = 'P0001';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_course_waitlist_insert_guard ON public.course_waitlist;
CREATE TRIGGER trg_course_waitlist_insert_guard
BEFORE INSERT ON public.course_waitlist
FOR EACH ROW
EXECUTE FUNCTION public.trg_fn_validate_waitlist_insert();

CREATE OR REPLACE FUNCTION public.trg_fn_validate_waitlist_transition()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.cohort_id <> OLD.cohort_id OR NEW.trainee_id <> OLD.trainee_id THEN
    RAISE EXCEPTION 'WAITLIST_IDENTITY_IMMUTABLE' USING ERRCODE = 'P0001';
  END IF;

  IF NEW.status = OLD.status THEN
    RETURN NEW;
  END IF;

  IF NEW.status = 'enrolled' THEN
    IF NEW.promoted_at IS NULL OR NEW.promoted_by IS NULL THEN
      RAISE EXCEPTION 'WAITLIST_PROMOTION_FIELDS_REQUIRED' USING ERRCODE = 'P0001';
    END IF;
    IF NOT EXISTS (
      SELECT 1
      FROM public.enrollments e
      WHERE e.cohort_id = NEW.cohort_id
        AND e.trainee_id = NEW.trainee_id
        AND public.enrollment_status_occupies_seat(e.status::text)
    ) THEN
      RAISE EXCEPTION 'WAITLIST_ENROLLMENT_MISSING' USING ERRCODE = 'P0001';
    END IF;
  END IF;

  IF OLD.status = 'waiting' AND NEW.status IN ('notified', 'enrolled', 'cancelled') THEN
    RETURN NEW;
  END IF;

  IF OLD.status = 'notified' AND NEW.status IN ('enrolled', 'expired', 'cancelled') THEN
    RETURN NEW;
  END IF;

  RAISE EXCEPTION 'INVALID_WAITLIST_TRANSITION'
    USING ERRCODE = 'P0001',
          DETAIL = format('from=%s to=%s', OLD.status, NEW.status);
END;
$$;

DROP TRIGGER IF EXISTS trg_course_waitlist_transition_guard ON public.course_waitlist;
CREATE TRIGGER trg_course_waitlist_transition_guard
BEFORE UPDATE OF status, cohort_id, trainee_id
ON public.course_waitlist
FOR EACH ROW
EXECUTE FUNCTION public.trg_fn_validate_waitlist_transition();

CREATE OR REPLACE FUNCTION public.trg_fn_course_waitlist_touch()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_course_waitlist_touch ON public.course_waitlist;
CREATE TRIGGER trg_course_waitlist_touch
BEFORE UPDATE ON public.course_waitlist
FOR EACH ROW
EXECUTE FUNCTION public.trg_fn_course_waitlist_touch();

-- 8. RLS: admin full, trainee reads own rows only
-- ------------------------------------------------------------------------------
ALTER TABLE public.course_waitlist ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "course_waitlist_admin_all" ON public.course_waitlist;
CREATE POLICY "course_waitlist_admin_all"
ON public.course_waitlist
FOR ALL
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.users
    WHERE id = auth.uid() AND role = 'admin' AND is_active = true
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1 FROM public.users
    WHERE id = auth.uid() AND role = 'admin' AND is_active = true
  )
);

DROP POLICY IF EXISTS "course_waitlist_trainee_select_own" ON public.course_waitlist;
CREATE POLICY "course_waitlist_trainee_select_own"
ON public.course_waitlist
FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.trainees t
    WHERE t.id = course_waitlist.trainee_id
      AND t.user_id = auth.uid()
  )
);

REVOKE ALL ON TABLE public.course_waitlist FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.course_waitlist TO authenticated;
GRANT ALL ON TABLE public.course_waitlist TO service_role;

-- 9. Outbox: allow waitlist_available type
-- ------------------------------------------------------------------------------
DO $$
DECLARE
  v_conname TEXT;
BEGIN
  FOR v_conname IN
    SELECT conname
    FROM pg_constraint
    WHERE conrelid = 'public.notification_outbox'::regclass
      AND contype = 'c'
      AND pg_get_constraintdef(oid) ILIKE '%session_reminder%'
  LOOP
    EXECUTE format(
      'ALTER TABLE public.notification_outbox DROP CONSTRAINT %I',
      v_conname
    );
  END LOOP;
END $$;

ALTER TABLE public.notification_outbox
  ADD CONSTRAINT notification_outbox_type_check
  CHECK (type IN (
    'session_reminder',
    'survey_reminder',
    'payment_reminder',
    'custom',
    'waitlist_available'
  ));

-- 10. Notify the first eligible waiting trainee when a seat is available
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.notify_next_waitlist(p_cohort_id UUID)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_capacity INTEGER;
  v_active_count INTEGER;
  v_waitlist RECORD;
  v_course_name TEXT;
  v_cohort_name TEXT;
  v_now TIMESTAMPTZ := now();
  v_expires_at TIMESTAMPTZ := now() + interval '24 hours';
  v_dedupe_key TEXT;
BEGIN
  SELECT c.capacity, co.name, c.name
  INTO v_capacity, v_course_name, v_cohort_name
  FROM public.cohorts c
  JOIN public.courses co ON co.id = c.course_id
  WHERE c.id = p_cohort_id
    AND c.is_active = true
    AND co.is_active = true
  FOR UPDATE OF c;

  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  UPDATE public.course_waitlist
  SET status = 'expired',
      updated_at = v_now
  WHERE cohort_id = p_cohort_id
    AND status = 'notified'
    AND expires_at IS NOT NULL
    AND expires_at <= v_now;

  v_active_count := public.cohort_active_enrollment_count(p_cohort_id);

  IF v_capacity IS NOT NULL AND v_active_count >= v_capacity THEN
    RETURN NULL;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.course_waitlist w
    WHERE w.cohort_id = p_cohort_id
      AND w.status = 'notified'
      AND (w.expires_at IS NULL OR w.expires_at > v_now)
  ) THEN
    RETURN NULL;
  END IF;

  SELECT w.*
  INTO v_waitlist
  FROM public.course_waitlist w
  JOIN public.trainees t ON t.id = w.trainee_id
  JOIN public.users u ON u.id = t.user_id AND u.is_active = true
  WHERE w.cohort_id = p_cohort_id
    AND w.status = 'waiting'
  ORDER BY w.joined_at ASC, w.id ASC
  LIMIT 1
  FOR UPDATE OF w;

  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  UPDATE public.course_waitlist
  SET status = 'notified',
      notified_at = v_now,
      expires_at = v_expires_at,
      updated_at = v_now
  WHERE id = v_waitlist.id;

  v_dedupe_key := 'waitlist_available:' || v_waitlist.id::text || ':' ||
                  to_char(v_now AT TIME ZONE 'UTC', 'YYYYMMDDHH24MISSUS');

  INSERT INTO public.notification_outbox (
    user_id,
    type,
    title,
    body,
    data,
    dedupe_key
  )
  SELECT
    t.user_id,
    'waitlist_available',
    'مقعد متاح في دورة تدريبية',
    'أصبح هناك مقعد متاح في ' || v_course_name || ' — ' || v_cohort_name ||
      '. يرجى التواصل مع الإدارة لتثبيت التسجيل.',
    jsonb_build_object(
      'type', 'waitlist_available',
      'cohort_id', p_cohort_id,
      'waitlist_id', v_waitlist.id,
      'route', '/courses'
    ),
    v_dedupe_key
  FROM public.trainees t
  WHERE t.id = v_waitlist.trainee_id;

  RETURN v_waitlist.id;
END;
$$;

REVOKE ALL ON FUNCTION public.notify_next_waitlist(UUID) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.notify_next_waitlist(UUID) TO service_role;

-- 11. Trigger: seat released by status change or cohort transfer
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.trg_fn_enrollment_waitlist_on_release()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    BEGIN
      PERFORM public.notify_next_waitlist(OLD.cohort_id);
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'waitlist notify skipped for cohort %: %', OLD.cohort_id, SQLERRM;
    END;
    RETURN OLD;
  END IF;

  IF (OLD.cohort_id IS DISTINCT FROM NEW.cohort_id)
     OR (
       public.enrollment_status_occupies_seat(OLD.status::text)
       AND NOT public.enrollment_status_occupies_seat(NEW.status::text)
     ) THEN
    BEGIN
      PERFORM public.notify_next_waitlist(OLD.cohort_id);
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'waitlist notify skipped for cohort %: %', OLD.cohort_id, SQLERRM;
    END;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_enrollments_waitlist_release ON public.enrollments;
CREATE TRIGGER trg_enrollments_waitlist_release
AFTER UPDATE OF status, cohort_id
ON public.enrollments
FOR EACH ROW
EXECUTE FUNCTION public.trg_fn_enrollment_waitlist_on_release();

DROP TRIGGER IF EXISTS trg_enrollments_waitlist_release_delete ON public.enrollments;
CREATE TRIGGER trg_enrollments_waitlist_release_delete
AFTER DELETE
ON public.enrollments
FOR EACH ROW
EXECUTE FUNCTION public.trg_fn_enrollment_waitlist_on_release();

-- 12. Trigger: capacity increased or removed (unlimited)
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.trg_fn_waitlist_on_capacity_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF (OLD.capacity IS NOT NULL AND NEW.capacity IS NULL)
     OR (
       OLD.capacity IS NOT NULL
       AND NEW.capacity IS NOT NULL
       AND NEW.capacity > OLD.capacity
     ) THEN
    BEGIN
      PERFORM public.notify_next_waitlist(NEW.id);
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'waitlist notify skipped for cohort %: %', NEW.id, SQLERRM;
    END;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_cohorts_waitlist_on_capacity_change ON public.cohorts;
CREATE TRIGGER trg_cohorts_waitlist_on_capacity_change
AFTER UPDATE OF capacity
ON public.cohorts
FOR EACH ROW
EXECUTE FUNCTION public.trg_fn_waitlist_on_capacity_change();

-- 13. RPC: join waitlist (trainee self, or admin on behalf of a trainee)
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.join_course_waitlist(
  p_cohort_id UUID,
  p_trainee_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_role TEXT;
  v_trainee_id UUID := p_trainee_id;
  v_capacity INTEGER;
  v_cohort_active BOOLEAN;
  v_course_active BOOLEAN;
  v_active_count INTEGER;
  v_existing_id UUID;
  v_existing_status TEXT;
  v_waitlist_id UUID;
  v_queue_position INTEGER;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'AUTH_REQUIRED' USING ERRCODE = 'P0001';
  END IF;

  SELECT u.role::TEXT
  INTO v_role
  FROM public.users u
  WHERE u.id = v_uid AND u.is_active = true;

  IF v_trainee_id IS NULL THEN
    SELECT t.id
    INTO v_trainee_id
    FROM public.trainees t
    WHERE t.user_id = v_uid;
  ELSIF v_role IS DISTINCT FROM 'admin' THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED' USING ERRCODE = 'P0001';
  END IF;

  IF v_trainee_id IS NULL
     OR NOT EXISTS (
       SELECT 1
       FROM public.trainees t
       JOIN public.users u ON u.id = t.user_id
       WHERE t.id = v_trainee_id
         AND u.is_active = true
     ) THEN
    RAISE EXCEPTION 'TRAINEE_NOT_FOUND' USING ERRCODE = 'P0001';
  END IF;

  SELECT c.capacity, c.is_active, co.is_active
  INTO v_capacity, v_cohort_active, v_course_active
  FROM public.cohorts c
  JOIN public.courses co ON co.id = c.course_id
  WHERE c.id = p_cohort_id
  FOR UPDATE OF c;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'COHORT_NOT_FOUND' USING ERRCODE = 'P0001';
  END IF;

  IF NOT v_cohort_active OR NOT v_course_active THEN
    RAISE EXCEPTION 'COHORT_NOT_ACTIVE' USING ERRCODE = 'P0001';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.enrollments e
    WHERE e.cohort_id = p_cohort_id
      AND e.trainee_id = v_trainee_id
      AND public.enrollment_status_occupies_seat(e.status::text)
  ) THEN
    RAISE EXCEPTION 'ALREADY_ENROLLED' USING ERRCODE = 'P0001';
  END IF;

  SELECT w.id, w.status
  INTO v_existing_id, v_existing_status
  FROM public.course_waitlist w
  WHERE w.cohort_id = p_cohort_id
    AND w.trainee_id = v_trainee_id
    AND w.status IN ('waiting', 'notified')
  LIMIT 1;

  IF FOUND THEN
    RETURN jsonb_build_object(
      'waitlist_id', v_existing_id,
      'status', v_existing_status,
      'already_joined', true
    );
  END IF;

  v_active_count := public.cohort_active_enrollment_count(p_cohort_id);

  IF v_capacity IS NULL OR v_active_count < v_capacity THEN
    RAISE EXCEPTION 'COHORT_HAS_AVAILABLE_SEATS' USING ERRCODE = 'P0001';
  END IF;

  INSERT INTO public.course_waitlist (
    cohort_id,
    trainee_id,
    status,
    created_by
  ) VALUES (
    p_cohort_id,
    v_trainee_id,
    'waiting',
    v_uid
  )
  RETURNING id INTO v_waitlist_id;

  SELECT count(*) + 1
  INTO v_queue_position
  FROM public.course_waitlist w
  WHERE w.cohort_id = p_cohort_id
    AND w.status IN ('waiting', 'notified')
    AND w.id <> v_waitlist_id;

  RETURN jsonb_build_object(
    'waitlist_id', v_waitlist_id,
    'status', 'waiting',
    'already_joined', false,
    'queue_position', v_queue_position
  );
END;
$$;

REVOKE ALL ON FUNCTION public.join_course_waitlist(UUID, UUID) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.join_course_waitlist(UUID, UUID) TO authenticated;

-- 14. RPC: cancel a waitlist entry (owner or admin)
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.cancel_course_waitlist(p_waitlist_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_role TEXT;
  v_trainee_id UUID;
  v_cohort_id UUID;
  v_row RECORD;
  v_was_notified BOOLEAN;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'AUTH_REQUIRED' USING ERRCODE = 'P0001';
  END IF;

  SELECT u.role::TEXT
  INTO v_role
  FROM public.users u
  WHERE u.id = v_uid AND u.is_active = true;

  SELECT w.cohort_id
  INTO v_cohort_id
  FROM public.course_waitlist w
  WHERE w.id = p_waitlist_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'WAITLIST_NOT_FOUND' USING ERRCODE = 'P0001';
  END IF;

  PERFORM 1
  FROM public.cohorts c
  WHERE c.id = v_cohort_id
  FOR UPDATE;

  SELECT w.*
  INTO v_row
  FROM public.course_waitlist w
  WHERE w.id = p_waitlist_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'WAITLIST_NOT_FOUND' USING ERRCODE = 'P0001';
  END IF;

  IF v_role IS DISTINCT FROM 'admin' THEN
    SELECT t.id
    INTO v_trainee_id
    FROM public.trainees t
    WHERE t.user_id = v_uid;

    IF v_trainee_id IS NULL OR v_trainee_id <> v_row.trainee_id THEN
      RAISE EXCEPTION 'NOT_AUTHORIZED' USING ERRCODE = 'P0001';
    END IF;
  END IF;

  IF v_row.status NOT IN ('waiting', 'notified') THEN
    RAISE EXCEPTION 'WAITLIST_NOT_ACTIVE' USING ERRCODE = 'P0001';
  END IF;

  v_was_notified := (v_row.status = 'notified');

  UPDATE public.course_waitlist
  SET status = 'cancelled',
      cancelled_at = now(),
      updated_at = now()
  WHERE id = p_waitlist_id;

  IF v_was_notified THEN
    BEGIN
      PERFORM public.notify_next_waitlist(v_cohort_id);
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'waitlist notify skipped after cancel for cohort %: %',
                    v_cohort_id, SQLERRM;
    END;
  END IF;

  RETURN jsonb_build_object(
    'waitlist_id', p_waitlist_id,
    'status', 'cancelled'
  );
END;
$$;

REVOKE ALL ON FUNCTION public.cancel_course_waitlist(UUID) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.cancel_course_waitlist(UUID) TO authenticated;

-- 15. RPC: promote a waitlist entry into a real enrollment (admin only)
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.promote_waitlist_trainee(
  p_waitlist_id UUID,
  p_total_due NUMERIC,
  p_discount_amount NUMERIC DEFAULT 0,
  p_currency TEXT DEFAULT 'SYP'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_role TEXT;
  v_cohort_id UUID;
  v_row RECORD;
  v_capacity INTEGER;
  v_active_count INTEGER;
  v_enrollment_id UUID;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'AUTH_REQUIRED' USING ERRCODE = 'P0001';
  END IF;

  SELECT u.role::TEXT
  INTO v_role
  FROM public.users u
  WHERE u.id = v_uid AND u.is_active = true;

  IF v_role IS DISTINCT FROM 'admin' THEN
    RAISE EXCEPTION 'ADMIN_ONLY' USING ERRCODE = 'P0001';
  END IF;

  IF p_total_due IS NULL OR p_total_due < 0 THEN
    RAISE EXCEPTION 'INVALID_TOTAL_DUE' USING ERRCODE = 'P0001';
  END IF;

  IF p_discount_amount IS NULL OR p_discount_amount < 0 THEN
    RAISE EXCEPTION 'INVALID_DISCOUNT' USING ERRCODE = 'P0001';
  END IF;

  IF p_currency IS NULL OR length(trim(p_currency)) = 0 THEN
    RAISE EXCEPTION 'INVALID_CURRENCY' USING ERRCODE = 'P0001';
  END IF;

  SELECT w.cohort_id
  INTO v_cohort_id
  FROM public.course_waitlist w
  WHERE w.id = p_waitlist_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'WAITLIST_NOT_FOUND' USING ERRCODE = 'P0001';
  END IF;

  PERFORM 1
  FROM public.cohorts c
  WHERE c.id = v_cohort_id
  FOR UPDATE;

  SELECT w.*
  INTO v_row
  FROM public.course_waitlist w
  WHERE w.id = p_waitlist_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'WAITLIST_NOT_FOUND' USING ERRCODE = 'P0001';
  END IF;

  IF v_row.status NOT IN ('waiting', 'notified') THEN
    RAISE EXCEPTION 'WAITLIST_NOT_ACTIVE' USING ERRCODE = 'P0001';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.trainees t
    JOIN public.users u ON u.id = t.user_id
    WHERE t.id = v_row.trainee_id
      AND u.is_active = true
  ) THEN
    RAISE EXCEPTION 'TRAINEE_NOT_FOUND' USING ERRCODE = 'P0001';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.enrollments e
    WHERE e.cohort_id = v_cohort_id
      AND e.trainee_id = v_row.trainee_id
      AND public.enrollment_status_occupies_seat(e.status::text)
  ) THEN
    RAISE EXCEPTION 'ALREADY_ENROLLED' USING ERRCODE = 'P0001';
  END IF;

  SELECT c.capacity
  INTO v_capacity
  FROM public.cohorts c
  WHERE c.id = v_cohort_id;

  v_active_count := public.cohort_active_enrollment_count(v_cohort_id);

  IF v_capacity IS NOT NULL AND v_active_count >= v_capacity THEN
    RAISE EXCEPTION 'COHORT_CAPACITY_REACHED'
      USING ERRCODE = 'P0001',
            DETAIL = format('cohort=%s active=%s capacity=%s',
                            v_cohort_id, v_active_count, v_capacity);
  END IF;

  INSERT INTO public.enrollments (
    trainee_id,
    cohort_id,
    total_due,
    discount_amount,
    currency,
    created_by
  ) VALUES (
    v_row.trainee_id,
    v_cohort_id,
    p_total_due,
    p_discount_amount,
    trim(p_currency),
    v_uid
  )
  RETURNING id INTO v_enrollment_id;

  UPDATE public.course_waitlist
  SET status = 'enrolled',
      promoted_at = now(),
      promoted_by = v_uid,
      updated_at = now()
  WHERE id = p_waitlist_id;

  BEGIN
    PERFORM public.notify_next_waitlist(v_cohort_id);
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'waitlist notify skipped after promotion for cohort %: %',
                  v_cohort_id, SQLERRM;
  END;

  RETURN jsonb_build_object(
    'enrollment_id', v_enrollment_id,
    'waitlist_id', p_waitlist_id,
    'status', 'enrolled'
  );
END;
$$;

REVOKE ALL ON FUNCTION public.promote_waitlist_trainee(UUID, NUMERIC, NUMERIC, TEXT)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.promote_waitlist_trainee(UUID, NUMERIC, NUMERIC, TEXT)
  TO authenticated;

-- 16. RPC: expiry sweeper (cron safety net)
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.expire_waitlist_notifications()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_expired_count INTEGER;
  v_cohort_ids UUID[];
  v_cohort_id UUID;
BEGIN
  WITH expired AS (
    UPDATE public.course_waitlist
    SET status = 'expired',
        updated_at = now()
    WHERE status = 'notified'
      AND expires_at IS NOT NULL
      AND expires_at <= now()
    RETURNING cohort_id
  )
  SELECT count(*), array_agg(DISTINCT cohort_id)
  INTO v_expired_count, v_cohort_ids
  FROM expired;

  FOREACH v_cohort_id IN ARRAY COALESCE(v_cohort_ids, ARRAY[]::UUID[])
  LOOP
    BEGIN
      PERFORM public.notify_next_waitlist(v_cohort_id);
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'waitlist expiry notify skipped for cohort %: %',
                    v_cohort_id, SQLERRM;
    END;
  END LOOP;

  RETURN v_expired_count;
END;
$$;

REVOKE ALL ON FUNCTION public.expire_waitlist_notifications() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.expire_waitlist_notifications() TO service_role;

-- 17. Read RPC: seat status for admin and trainee UIs
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_cohorts_seat_status(p_course_id UUID DEFAULT NULL)
RETURNS TABLE (
  cohort_id UUID,
  course_id UUID,
  cohort_name TEXT,
  course_name TEXT,
  cohort_starts_at TIMESTAMPTZ,
  course_price NUMERIC,
  course_total_sessions INTEGER,
  capacity INTEGER,
  enrolled_count INTEGER,
  waitlist_count INTEGER,
  available_seats INTEGER,
  is_full BOOLEAN
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT
    c.id,
    c.course_id,
    c.name,
    co.name,
    c.starts_at,
    co.price::NUMERIC,
    co.total_sessions::INTEGER,
    c.capacity,
    ec.enrolled_count,
    wc.waitlist_count,
    CASE
      WHEN c.capacity IS NULL THEN NULL
      ELSE GREATEST(c.capacity - ec.enrolled_count, 0)::INTEGER
    END,
    CASE
      WHEN c.capacity IS NULL THEN false
      ELSE ec.enrolled_count >= c.capacity
    END
  FROM public.cohorts c
  JOIN public.courses co ON co.id = c.course_id
  CROSS JOIN LATERAL (
    SELECT count(*)::INTEGER AS enrolled_count
    FROM public.enrollments e
    WHERE e.cohort_id = c.id
      AND public.enrollment_status_occupies_seat(e.status::text)
  ) ec
  CROSS JOIN LATERAL (
    SELECT count(*)::INTEGER AS waitlist_count
    FROM public.course_waitlist w
    WHERE w.cohort_id = c.id
      AND w.status IN ('waiting', 'notified')
  ) wc
  WHERE c.is_active = true
    AND co.is_active = true
    AND (p_course_id IS NULL OR c.course_id = p_course_id)
  ORDER BY co.name ASC, c.name ASC;
$$;

REVOKE ALL ON FUNCTION public.get_cohorts_seat_status(UUID) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_cohorts_seat_status(UUID) TO authenticated;

-- 18. Trigger function permissions
-- ------------------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.trg_fn_enforce_cohort_capacity() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.trg_fn_validate_cohort_capacity() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.trg_fn_validate_waitlist_insert() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.trg_fn_validate_waitlist_transition() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.trg_fn_course_waitlist_touch() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.trg_fn_enrollment_waitlist_on_release() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.trg_fn_waitlist_on_capacity_change() FROM PUBLIC, anon, authenticated;

-- 19. Cron: expire stale seat notifications every 15 minutes
-- ------------------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS pg_cron;

DO $$
BEGIN
  PERFORM cron.unschedule('taj_waitlist_expiry');
EXCEPTION WHEN OTHERS THEN
  NULL;
END $$;

SELECT cron.schedule(
  'taj_waitlist_expiry',
  '*/15 * * * *',
  $$SELECT public.expire_waitlist_notifications();$$
);
