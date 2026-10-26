-- ==============================================================================
-- Taj Dentics — Phase A5: referral system (2026-10-26)
--
-- Decisions (locked with product owner):
--   * The trainee's official trainee_code (T10000..T10153) doubles as the
--     referral code. There is no separate random code.
--   * Staff enter the code plus a fixed discount amount at enrollment.
--   * The referee receives that amount on the current enrollment.
--   * The referrer receives the same amount as a credit, consumed automatically
--     on their next enrollment in the same currency (FIFO, full credits only).
--   * A referee is eligible only while not occupying a seat in the same course.
--   * Discounts are folded into enrollments.discount_amount, which the financial
--     view already treats as net_due = total_due - discount_amount.
-- ==============================================================================

-- 1. The official trainee code doubles as the referral code
-- ------------------------------------------------------------------------------
-- The center numbers trainees T10000..T10153. A trainee has exactly one code:
-- trainee_code. Development dummy rows without a code are filled with the next
-- free numbers starting at T10001; real trainees keep their official codes.
--
-- trainee_code stays nullable because create-trainee inserts the trainee row
-- before staff fill in the code; a trainee without a code cannot refer anyone.

-- Defensive cleanup in case an earlier draft of this migration was applied.
ALTER TABLE public.trainees DROP COLUMN IF EXISTS referral_code;
DROP FUNCTION IF EXISTS public.generate_referral_code();

-- Normalize existing codes so lookups and the unique index agree.
UPDATE public.trainees
SET trainee_code = upper(btrim(trainee_code))
WHERE trainee_code IS NOT NULL
  AND trainee_code <> upper(btrim(trainee_code));

-- Fill missing codes with the next unused T10001..T19999 values.
WITH missing AS (
  SELECT t.id,
         row_number() OVER (ORDER BY t.created_at, t.id) AS rn
  FROM public.trainees t
  WHERE t.trainee_code IS NULL OR btrim(t.trainee_code) = ''
),
taken AS (
  SELECT upper(btrim(t.trainee_code)) AS code
  FROM public.trainees t
  WHERE t.trainee_code IS NOT NULL AND btrim(t.trainee_code) <> ''
),
free_codes AS (
  SELECT 'T' || (10000 + g)::text AS code,
         row_number() OVER (ORDER BY g) AS rn
  FROM generate_series(1, 9999) AS g
  WHERE NOT EXISTS (
    SELECT 1
    FROM taken tk
    WHERE tk.code = 'T' || (10000 + g)::text
  )
)
UPDATE public.trainees t
SET trainee_code = fc.code
FROM missing m
JOIN free_codes fc ON fc.rn = m.rn
WHERE t.id = m.id;

CREATE UNIQUE INDEX IF NOT EXISTS uq_trainees_trainee_code
  ON public.trainees (upper(btrim(trainee_code)));

-- 2. Enrollment referral columns
-- ------------------------------------------------------------------------------
ALTER TABLE public.enrollments
  ADD COLUMN IF NOT EXISTS referral_code TEXT,
  ADD COLUMN IF NOT EXISTS referral_discount_amount NUMERIC(12,2);

-- 3. Referral ledger
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.referrals (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  referrer_trainee_id UUID NOT NULL
    REFERENCES public.trainees(id) ON DELETE CASCADE,
  referee_trainee_id UUID NOT NULL
    REFERENCES public.trainees(id) ON DELETE CASCADE,
  code_used TEXT NOT NULL,  -- snapshot of trainees.trainee_code at enrollment time
  course_id UUID NOT NULL
    REFERENCES public.courses(id) ON DELETE CASCADE,
  enrollment_id UUID NOT NULL
    REFERENCES public.enrollments(id) ON DELETE CASCADE,
  discount_amount NUMERIC(12,2) NOT NULL,
  currency TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'available',
  applied_enrollment_id UUID
    REFERENCES public.enrollments(id) ON DELETE CASCADE,
  applied_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT referrals_no_self
    CHECK (referrer_trainee_id <> referee_trainee_id),
  CONSTRAINT referrals_discount_positive
    CHECK (discount_amount > 0),
  CONSTRAINT referrals_status_check
    CHECK (status IN ('available', 'applied', 'cancelled')),
  CONSTRAINT referrals_applied_fields_check
    CHECK (status <> 'applied'
           OR (applied_enrollment_id IS NOT NULL AND applied_at IS NOT NULL)),
  CONSTRAINT referrals_enrollment_unique UNIQUE (enrollment_id)
);

-- A cancelled referral may be re-created, an active/applied one may not.
CREATE UNIQUE INDEX IF NOT EXISTS uq_referrals_active_triplet
  ON public.referrals (referrer_trainee_id, referee_trainee_id, course_id)
  WHERE status <> 'cancelled';

CREATE INDEX IF NOT EXISTS idx_referrals_referrer_status
  ON public.referrals (referrer_trainee_id, status, created_at);

CREATE INDEX IF NOT EXISTS idx_referrals_referee
  ON public.referrals (referee_trainee_id, course_id);

CREATE OR REPLACE FUNCTION public.trg_fn_referrals_touch()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_referrals_touch ON public.referrals;
CREATE TRIGGER trg_referrals_touch
BEFORE UPDATE ON public.referrals
FOR EACH ROW
EXECUTE FUNCTION public.trg_fn_referrals_touch();

-- 4. Validate the referral code before the enrollment row exists
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.trg_fn_enrollments_referral_before()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_referrer RECORD;
  v_course_id UUID;
  v_remaining NUMERIC(12,2);
BEGIN
  -- Serialize credit consumption per trainee.
  PERFORM pg_advisory_xact_lock(
    hashtextextended('referral_credit:' || NEW.trainee_id::text, 0)
  );

  NEW.referral_code := NULLIF(upper(btrim(COALESCE(NEW.referral_code, ''))), '');
  NEW.referral_discount_amount := COALESCE(NEW.referral_discount_amount, 0);

  IF NEW.referral_code IS NULL THEN
    NEW.referral_discount_amount := 0;
    RETURN NEW;
  END IF;

  IF NEW.referral_discount_amount <= 0 THEN
    RAISE EXCEPTION 'REFERRAL_DISCOUNT_INVALID' USING ERRCODE = 'P0001';
  END IF;

  SELECT t.id, t.user_id, u.is_active
  INTO v_referrer
  FROM public.trainees t
  JOIN public.users u ON u.id = t.user_id
  WHERE upper(btrim(t.trainee_code)) = NEW.referral_code;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'REFERRAL_CODE_INVALID' USING ERRCODE = 'P0001';
  END IF;

  IF v_referrer.id = NEW.trainee_id THEN
    RAISE EXCEPTION 'REFERRAL_SELF' USING ERRCODE = 'P0001';
  END IF;

  IF NOT v_referrer.is_active THEN
    RAISE EXCEPTION 'REFERRAL_REFERRER_INACTIVE' USING ERRCODE = 'P0001';
  END IF;

  SELECT c.course_id
  INTO v_course_id
  FROM public.cohorts c
  WHERE c.id = NEW.cohort_id;

  IF v_course_id IS NULL THEN
    RAISE EXCEPTION 'COHORT_NOT_FOUND' USING ERRCODE = 'P0001';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.enrollments e
    JOIN public.cohorts c ON c.id = e.cohort_id
    WHERE e.trainee_id = NEW.trainee_id
      AND c.course_id = v_course_id
      AND public.enrollment_status_occupies_seat(e.status::text)
  ) THEN
    RAISE EXCEPTION 'REFERRAL_REFEREE_ENROLLED' USING ERRCODE = 'P0001';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.referrals r
    WHERE r.referee_trainee_id = NEW.trainee_id
      AND r.course_id = v_course_id
      AND r.status <> 'cancelled'
  ) THEN
    RAISE EXCEPTION 'REFERRAL_ALREADY_REFERRED' USING ERRCODE = 'P0001';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.referrals r
    WHERE r.referrer_trainee_id = NEW.trainee_id
      AND r.referee_trainee_id = v_referrer.id
      AND r.course_id = v_course_id
      AND r.status <> 'cancelled'
  ) THEN
    RAISE EXCEPTION 'REFERRAL_MUTUAL' USING ERRCODE = 'P0001';
  END IF;

  v_remaining := GREATEST(
    COALESCE(NEW.total_due, 0) - COALESCE(NEW.discount_amount, 0),
    0
  );

  IF v_remaining <= 0 THEN
    RAISE EXCEPTION 'REFERRAL_NOTHING_DUE' USING ERRCODE = 'P0001';
  END IF;

  IF NEW.referral_discount_amount > v_remaining THEN
    RAISE EXCEPTION 'REFERRAL_DISCOUNT_TOO_HIGH'
      USING ERRCODE = 'P0001',
            DETAIL = format('requested=%s remaining=%s',
                            NEW.referral_discount_amount, v_remaining);
  END IF;

  NEW.discount_amount := COALESCE(NEW.discount_amount, 0) + NEW.referral_discount_amount;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_enrollments_referral_before ON public.enrollments;
CREATE TRIGGER trg_enrollments_referral_before
BEFORE INSERT ON public.enrollments
FOR EACH ROW
EXECUTE FUNCTION public.trg_fn_enrollments_referral_before();

-- 5. Consume referrer credits and record the referral
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.trg_fn_enrollments_referral_after()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_budget NUMERIC(12,2);
  v_applied NUMERIC(12,2) := 0;
  v_row RECORD;
  v_referrer_id UUID;
  v_referrer_user_id UUID;
  v_course_id UUID;
  v_referral_id UUID;
BEGIN
  PERFORM pg_advisory_xact_lock(
    hashtextextended('referral_credit:' || NEW.trainee_id::text, 0)
  );

  v_budget := GREATEST(
    COALESCE(NEW.total_due, 0) - COALESCE(NEW.discount_amount, 0),
    0
  );

  IF v_budget > 0 THEN
    FOR v_row IN
      SELECT r.id, r.discount_amount
      FROM public.referrals r
      WHERE r.referrer_trainee_id = NEW.trainee_id
        AND r.status = 'available'
        AND upper(btrim(r.currency)) = upper(btrim(NEW.currency::text))
        AND r.enrollment_id <> NEW.id
      ORDER BY r.created_at, r.id
      FOR UPDATE
    LOOP
      CONTINUE WHEN v_row.discount_amount > (v_budget - v_applied);

      UPDATE public.referrals
      SET status = 'applied',
          applied_enrollment_id = NEW.id,
          applied_at = now(),
          updated_at = now()
      WHERE id = v_row.id;

      v_applied := v_applied + v_row.discount_amount;

      EXIT WHEN v_applied >= v_budget;
    END LOOP;

    IF v_applied > 0 THEN
      UPDATE public.enrollments
      SET discount_amount = COALESCE(discount_amount, 0) + v_applied
      WHERE id = NEW.id;
    END IF;
  END IF;

  IF NEW.referral_code IS NOT NULL
     AND COALESCE(NEW.referral_discount_amount, 0) > 0 THEN
    SELECT t.id, t.user_id, c.course_id
    INTO v_referrer_id, v_referrer_user_id, v_course_id
    FROM public.trainees t
    JOIN public.cohorts c ON c.id = NEW.cohort_id
    WHERE upper(btrim(t.trainee_code)) = NEW.referral_code;

    IF v_referrer_id IS NOT NULL THEN
      INSERT INTO public.referrals (
        referrer_trainee_id,
        referee_trainee_id,
        code_used,
        course_id,
        enrollment_id,
        discount_amount,
        currency
      ) VALUES (
        v_referrer_id,
        NEW.trainee_id,
        NEW.referral_code,
        v_course_id,
        NEW.id,
        NEW.referral_discount_amount,
        upper(btrim(NEW.currency::text))
      )
      RETURNING id INTO v_referral_id;

      INSERT INTO public.notification_outbox (
        user_id,
        type,
        title,
        body,
        data,
        dedupe_key
      ) VALUES (
        v_referrer_user_id,
        'referral_qualified',
        'إحالة ناجحة',
        'تم تسجيل صديقك بكود الإحالة الخاص بك. أصبح لديك رصيد خصم بقيمة ' ||
          to_char(NEW.referral_discount_amount, 'FM999999990.##') || ' ' ||
          NEW.currency,
        jsonb_build_object(
          'type', 'referral_qualified',
          'referral_id', v_referral_id,
          'route', '/home'
        ),
        'referral_qualified:' || v_referral_id::text
      );
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_enrollments_referral_after ON public.enrollments;
CREATE TRIGGER trg_enrollments_referral_after
AFTER INSERT ON public.enrollments
FOR EACH ROW
EXECUTE FUNCTION public.trg_fn_enrollments_referral_after();

-- 6. Cancel an unspent credit when the referee's enrollment is released
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.trg_fn_referral_on_enrollment_release()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  PERFORM pg_advisory_xact_lock(
    hashtextextended('referral_credit:' || NEW.trainee_id::text, 0)
  );

  IF public.enrollment_status_occupies_seat(OLD.status::text)
     AND NOT public.enrollment_status_occupies_seat(NEW.status::text) THEN
    -- Credits this enrollment consumed go back to the referrer, and their
    -- discount is removed from the released enrollment so neither can be reused.
    WITH restored AS (
      UPDATE public.referrals
      SET status = 'available',
          applied_enrollment_id = NULL,
          applied_at = NULL,
          updated_at = now()
      WHERE applied_enrollment_id = NEW.id
        AND status = 'applied'
      RETURNING discount_amount
    ),
    cancelled AS (
      UPDATE public.referrals
      SET status = 'cancelled',
          updated_at = now()
      WHERE enrollment_id = NEW.id
        AND status = 'available'
      RETURNING discount_amount
    )
    UPDATE public.enrollments e
    SET discount_amount = GREATEST(
          COALESCE(e.discount_amount, 0)
          - COALESCE((SELECT sum(discount_amount) FROM restored), 0)
          - COALESCE(e.referral_discount_amount, 0),
          0
        ),
        referral_code = NULL,
        referral_discount_amount = 0
    WHERE e.id = NEW.id;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_enrollments_referral_release ON public.enrollments;
CREATE TRIGGER trg_enrollments_referral_release
AFTER UPDATE OF status ON public.enrollments
FOR EACH ROW
EXECUTE FUNCTION public.trg_fn_referral_on_enrollment_release();

-- 7. Staff preview of a referral code
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.preview_referral_code(p_code TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_code TEXT := NULLIF(upper(btrim(COALESCE(p_code, ''))), '');
  v_row RECORD;
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM public.users u
    WHERE u.id = auth.uid()
      AND u.is_active = true
      AND u.role::text IN ('admin', 'reception')
  ) THEN
    RAISE EXCEPTION 'AUTH_REQUIRED' USING ERRCODE = 'P0001';
  END IF;

  IF v_code IS NULL THEN
    RETURN jsonb_build_object('valid', false, 'error', 'REFERRAL_CODE_INVALID');
  END IF;

  SELECT t.id, u.full_name, u.is_active
  INTO v_row
  FROM public.trainees t
  JOIN public.users u ON u.id = t.user_id
  WHERE upper(btrim(t.trainee_code)) = v_code;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('valid', false, 'error', 'REFERRAL_CODE_INVALID');
  END IF;

  IF NOT v_row.is_active THEN
    RETURN jsonb_build_object('valid', false, 'error', 'REFERRAL_REFERRER_INACTIVE');
  END IF;

  RETURN jsonb_build_object(
    'valid', true,
    'referrer_trainee_id', v_row.id,
    'referrer_name', v_row.full_name
  );
END;
$$;

-- 8. Trainee summary
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_my_referral_summary()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_trainee_id UUID;
  v_code TEXT;
  v_available JSONB;
  v_referrals JSONB;
BEGIN
  SELECT t.id
  INTO v_trainee_id
  FROM public.trainees t
  WHERE t.user_id = auth.uid();

  IF v_trainee_id IS NULL THEN
    RAISE EXCEPTION 'AUTH_REQUIRED' USING ERRCODE = 'P0001';
  END IF;

  SELECT t.trainee_code
  INTO v_code
  FROM public.trainees t
  WHERE t.id = v_trainee_id;

  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'currency', x.currency,
        'amount', x.total,
        'count', x.cnt
      )
      ORDER BY x.currency
    ),
    '[]'::jsonb
  )
  INTO v_available
  FROM (
    SELECT upper(btrim(r.currency)) AS currency,
           sum(r.discount_amount) AS total,
           count(*) AS cnt
    FROM public.referrals r
    WHERE r.referrer_trainee_id = v_trainee_id
      AND r.status = 'available'
    GROUP BY upper(btrim(r.currency))
  ) x;

  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'id', r.id,
        'referee_name', u.full_name,
        'course_name', co.name,
        'amount', r.discount_amount,
        'currency', r.currency,
        'status', r.status,
        'created_at', r.created_at,
        'applied_at', r.applied_at
      )
      ORDER BY r.created_at DESC
    ),
    '[]'::jsonb
  )
  INTO v_referrals
  FROM public.referrals r
  JOIN public.trainees t ON t.id = r.referee_trainee_id
  JOIN public.users u ON u.id = t.user_id
  JOIN public.courses co ON co.id = r.course_id
  WHERE r.referrer_trainee_id = v_trainee_id;

  RETURN jsonb_build_object(
    'referral_code', v_code,
    'available_credits', v_available,
    'referrals', v_referrals
  );
END;
$$;

-- 9. Staff summary for a trainee profile
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_staff_referral_summary(p_trainee_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_code TEXT;
  v_name TEXT;
  v_available JSONB;
  v_referrals JSONB;
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM public.users u
    WHERE u.id = auth.uid()
      AND u.is_active = true
      AND u.role::text IN ('admin', 'reception')
  ) THEN
    RAISE EXCEPTION 'AUTH_REQUIRED' USING ERRCODE = 'P0001';
  END IF;

  SELECT t.trainee_code, u.full_name
  INTO v_code, v_name
  FROM public.trainees t
  JOIN public.users u ON u.id = t.user_id
  WHERE t.id = p_trainee_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'TRAINEE_NOT_FOUND' USING ERRCODE = 'P0001';
  END IF;

  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'currency', x.currency,
        'amount', x.total,
        'count', x.cnt
      )
      ORDER BY x.currency
    ),
    '[]'::jsonb
  )
  INTO v_available
  FROM (
    SELECT upper(btrim(r.currency)) AS currency,
           sum(r.discount_amount) AS total,
           count(*) AS cnt
    FROM public.referrals r
    WHERE r.referrer_trainee_id = p_trainee_id
      AND r.status = 'available'
    GROUP BY upper(btrim(r.currency))
  ) x;

  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'id', r.id,
        'referee_name', u.full_name,
        'course_name', co.name,
        'amount', r.discount_amount,
        'currency', r.currency,
        'status', r.status,
        'created_at', r.created_at,
        'applied_at', r.applied_at
      )
      ORDER BY r.created_at DESC
    ),
    '[]'::jsonb
  )
  INTO v_referrals
  FROM public.referrals r
  JOIN public.trainees t ON t.id = r.referee_trainee_id
  JOIN public.users u ON u.id = t.user_id
  JOIN public.courses co ON co.id = r.course_id
  WHERE r.referrer_trainee_id = p_trainee_id;

  RETURN jsonb_build_object(
    'trainee_id', p_trainee_id,
    'trainee_name', v_name,
    'referral_code', v_code,
    'available_credits', v_available,
    'referrals', v_referrals
  );
END;
$$;

-- 10. Promotion path must accept referral input
-- ------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.promote_waitlist_trainee(UUID, NUMERIC, NUMERIC, TEXT);

CREATE OR REPLACE FUNCTION public.promote_waitlist_trainee(
  p_waitlist_id UUID,
  p_total_due NUMERIC,
  p_discount_amount NUMERIC DEFAULT 0,
  p_currency TEXT DEFAULT 'SYP',
  p_referral_code TEXT DEFAULT NULL,
  p_referral_discount_amount NUMERIC DEFAULT NULL
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

  IF p_referral_discount_amount IS NOT NULL AND p_referral_discount_amount < 0 THEN
    RAISE EXCEPTION 'INVALID_DISCOUNT' USING ERRCODE = 'P0001';
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
    created_by,
    referral_code,
    referral_discount_amount
  ) VALUES (
    v_row.trainee_id,
    v_cohort_id,
    p_total_due,
    p_discount_amount,
    trim(p_currency),
    v_uid,
    NULLIF(upper(btrim(COALESCE(p_referral_code, ''))), ''),
    COALESCE(p_referral_discount_amount, 0)
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

-- 11. Outbox: allow referral_qualified
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
      AND pg_get_constraintdef(oid) ILIKE '%waitlist_available%'
  LOOP
    EXECUTE format(
      'ALTER TABLE public.notification_outbox DROP CONSTRAINT %I',
      v_conname
    );
  END LOOP;
END $$;

ALTER TABLE public.notification_outbox
  DROP CONSTRAINT IF EXISTS notification_outbox_type_check;

ALTER TABLE public.notification_outbox
  ADD CONSTRAINT notification_outbox_type_check
  CHECK (type IN (
    'session_reminder',
    'survey_reminder',
    'payment_reminder',
    'custom',
    'waitlist_available',
    'referral_qualified'
  ));

-- 12. RLS and grants
-- ------------------------------------------------------------------------------
ALTER TABLE public.referrals ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "referrals_staff_select" ON public.referrals;
CREATE POLICY "referrals_staff_select"
ON public.referrals
FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM public.users u
    WHERE u.id = auth.uid()
      AND u.is_active = true
      AND u.role::text IN ('admin', 'reception')
  )
);

DROP POLICY IF EXISTS "referrals_trainee_select_own" ON public.referrals;
CREATE POLICY "referrals_trainee_select_own"
ON public.referrals
FOR SELECT
TO authenticated
USING (
  referrer_trainee_id IN (
    SELECT t.id
    FROM public.trainees t
    WHERE t.user_id = auth.uid()
  )
);

REVOKE ALL ON TABLE public.referrals FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.referrals TO authenticated;
GRANT ALL ON TABLE public.referrals TO service_role;

-- 13. Function permissions
-- ------------------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.trg_fn_enrollments_referral_before()
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.trg_fn_enrollments_referral_after()
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.trg_fn_referral_on_enrollment_release()
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.trg_fn_referrals_touch()
  FROM PUBLIC, anon, authenticated;

REVOKE ALL ON FUNCTION public.preview_referral_code(TEXT)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.preview_referral_code(TEXT)
  TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.get_my_referral_summary()
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_referral_summary()
  TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.get_staff_referral_summary(UUID)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_staff_referral_summary(UUID)
  TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.promote_waitlist_trainee(
  UUID, NUMERIC, NUMERIC, TEXT, TEXT, NUMERIC
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.promote_waitlist_trainee(
  UUID, NUMERIC, NUMERIC, TEXT, TEXT, NUMERIC
) TO authenticated;
