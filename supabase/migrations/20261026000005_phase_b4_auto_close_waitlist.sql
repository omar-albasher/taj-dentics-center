-- ==============================================================================
-- Taj Dentics — Phase B4 hardening (2026-10-26)
-- 1. Repair active waitlist rows that already have an occupying enrollment
-- 2. Auto-close the matching active waitlist row on direct enrollment
-- 3. Make notify_next_waitlist skip already-enrolled trainees
-- 4. Use a cohort-first lock order in the expiry sweeper to avoid deadlocks
-- ==============================================================================

-- 1. Repair pre-existing orphans (rows created before this hardening)
-- ------------------------------------------------------------------------------
DO $$
DECLARE
  v_row RECORD;
  v_promoted_by UUID;
BEGIN
  FOR v_row IN
    SELECT w.id, w.cohort_id, w.trainee_id
    FROM public.course_waitlist w
    WHERE w.status IN ('waiting', 'notified')
      AND EXISTS (
        SELECT 1
        FROM public.enrollments e
        WHERE e.cohort_id = w.cohort_id
          AND e.trainee_id = w.trainee_id
          AND public.enrollment_status_occupies_seat(e.status::text)
      )
  LOOP
    SELECT e.created_by
    INTO v_promoted_by
    FROM public.enrollments e
    WHERE e.cohort_id = v_row.cohort_id
      AND e.trainee_id = v_row.trainee_id
      AND public.enrollment_status_occupies_seat(e.status::text)
      AND e.created_by IS NOT NULL
    ORDER BY e.created_at DESC NULLS LAST
    LIMIT 1;

    IF v_promoted_by IS NOT NULL THEN
      UPDATE public.course_waitlist
      SET status = 'enrolled',
          promoted_at = now(),
          promoted_by = v_promoted_by,
          updated_at = now()
      WHERE id = v_row.id;
    ELSE
      UPDATE public.course_waitlist
      SET status = 'cancelled',
          cancelled_at = now(),
          updated_at = now()
      WHERE id = v_row.id;
    END IF;
  END LOOP;
END $$;

-- 2. Auto-close on every direct enrollment path
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.trg_fn_autoclose_waitlist_on_enrollment()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_promoted_by UUID;
BEGIN
  IF NOT public.enrollment_status_occupies_seat(NEW.status::text) THEN
    RETURN NEW;
  END IF;

  -- A status change that already occupied a seat in the same cohort took no new seat.
  IF TG_OP = 'UPDATE'
     AND OLD.cohort_id = NEW.cohort_id
     AND public.enrollment_status_occupies_seat(OLD.status::text) THEN
    RETURN NEW;
  END IF;

  v_promoted_by := COALESCE(auth.uid(), NEW.created_by);

  IF v_promoted_by IS NOT NULL THEN
    UPDATE public.course_waitlist
    SET status = 'enrolled',
        promoted_at = now(),
        promoted_by = v_promoted_by,
        cancelled_at = NULL,
        updated_at = now()
    WHERE cohort_id = NEW.cohort_id
      AND trainee_id = NEW.trainee_id
      AND status IN ('waiting', 'notified');
  ELSE
    -- No auditable actor is available (e.g. a trusted direct SQL insert).
    UPDATE public.course_waitlist
    SET status = 'cancelled',
        cancelled_at = now(),
        updated_at = now()
    WHERE cohort_id = NEW.cohort_id
      AND trainee_id = NEW.trainee_id
      AND status IN ('waiting', 'notified');
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_enrollments_autoclose_waitlist ON public.enrollments;
CREATE TRIGGER trg_enrollments_autoclose_waitlist
AFTER INSERT OR UPDATE OF status, cohort_id
ON public.enrollments
FOR EACH ROW
EXECUTE FUNCTION public.trg_fn_autoclose_waitlist_on_enrollment();

-- 3. notify_next_waitlist: never notify an already-enrolled trainee
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

  -- Defense in depth: close active rows whose trainee is already enrolled.
  UPDATE public.course_waitlist w
  SET status = 'cancelled',
      cancelled_at = v_now,
      updated_at = v_now
  WHERE w.cohort_id = p_cohort_id
    AND w.status IN ('waiting', 'notified')
    AND EXISTS (
      SELECT 1
      FROM public.enrollments e
      WHERE e.cohort_id = w.cohort_id
        AND e.trainee_id = w.trainee_id
        AND public.enrollment_status_occupies_seat(e.status::text)
    );

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
    AND NOT EXISTS (
      SELECT 1
      FROM public.enrollments e
      WHERE e.cohort_id = w.cohort_id
        AND e.trainee_id = w.trainee_id
        AND public.enrollment_status_occupies_seat(e.status::text)
    )
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

-- 4. Expiry sweeper: cohort-first lock order (matches promote/cancel/release)
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.expire_waitlist_notifications()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_cohort_ids UUID[];
  v_cohort_id UUID;
  v_expired_count INTEGER := 0;
BEGIN
  -- Read-only pass: collect cohorts with stale offers without locking rows.
  SELECT array_agg(DISTINCT w.cohort_id ORDER BY w.cohort_id)
  INTO v_cohort_ids
  FROM public.course_waitlist w
  WHERE w.status = 'notified'
    AND w.expires_at IS NOT NULL
    AND w.expires_at <= now();

  -- notify_next_waitlist locks the cohort first, then expires and promotes.
  FOREACH v_cohort_id IN ARRAY COALESCE(v_cohort_ids, ARRAY[]::UUID[])
  LOOP
    BEGIN
      PERFORM public.notify_next_waitlist(v_cohort_id);
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'waitlist expiry notify skipped for cohort %: %',
                    v_cohort_id, SQLERRM;
    END;
  END LOOP;

  -- Inactive cohorts (or failed notify calls) still need the stale rows expired.
  -- This UPDATE takes only waitlist row locks and never waits for a cohort afterwards.
  UPDATE public.course_waitlist
  SET status = 'expired',
      updated_at = now()
  WHERE status = 'notified'
    AND expires_at IS NOT NULL
    AND expires_at <= now();
  GET DIAGNOSTICS v_expired_count = ROW_COUNT;

  RETURN v_expired_count;
END;
$$;

-- 5. Permissions
-- ------------------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.trg_fn_autoclose_waitlist_on_enrollment()
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.notify_next_waitlist(UUID)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.notify_next_waitlist(UUID) TO service_role;
REVOKE ALL ON FUNCTION public.expire_waitlist_notifications()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.expire_waitlist_notifications() TO service_role;
