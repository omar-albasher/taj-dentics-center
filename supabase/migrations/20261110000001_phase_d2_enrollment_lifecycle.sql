-- ═══════════════════════════════════════════════════════════════════════
-- Phase D2 — دورة حياة التسجيل والانسحاب بنظام Pro-rata
--
-- المشكلة:
--   enrollments.status هو payment_status (unpaid/partial/complete) وليس دورة
--   حياة. لذلك لا يوجد أي مسار حقيقي لتحرير المقعد، ولا تُشغَّل قائمة الانتظار
--   عند الانسحاب، ولا توجد تسوية مالية عادلة للجلسات المسلَّمة.
--
-- القرارات المعمارية المعتمدة (1–9):
--   1. فصل lifecycle_status عن حالة الدفع المالي.
--   2. N = الجلسات الأساسية المسلَّمة فعلياً حتى تاريخ الانسحاب، مع تجاوز
--      إداري اختياري p_sessions_override.
--   3. due = ROUND(net_due * N / total_sessions, 2).
--   4. التسوية عبر fee_adjustments + جدول تدقيق enrollment_withdrawals.
--   5. توزيع الفائض المسترد LIFO (أحدث الدفعات أولاً).
--   6. شطب الدين اختياري للمدير فقط.
--   7. تحرير المقعد يستدعي notify_next_waitlist، والترقية قرار يدوي.
--   8. الانسحاب للمدير فقط عبر c1_is_admin().
--   9. المنسحبون مستبعدون من المتأخرات والتذكيرات افتراضياً، مع بقاء الرصيد
--      ظاهراً في كشف حساب المتدرب.
--
-- قاعدة الجلسات المسلَّمة:
--   جلسة أساسية (is_extra = false) حالتها open أو closed وموعدها <= لحظة
--   الانسحاب. الجلسات scheduled/missed لا تُحتسب (لم تُسلَّم).
-- ═══════════════════════════════════════════════════════════════════════
BEGIN;

-- ==============================================================================
-- 1) أعمدة دورة الحياة
-- ==============================================================================
ALTER TABLE public.enrollments
  ADD COLUMN IF NOT EXISTS lifecycle_status TEXT NOT NULL DEFAULT 'active',
  ADD COLUMN IF NOT EXISTS withdrawn_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS withdrawal_reason TEXT;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.enrollments'::regclass
      AND conname = 'enrollments_lifecycle_status_check'
  ) THEN
    ALTER TABLE public.enrollments
      ADD CONSTRAINT enrollments_lifecycle_status_check
      CHECK (lifecycle_status IN ('active', 'completed', 'withdrawn'));
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.enrollments'::regclass
      AND conname = 'enrollments_withdrawn_fields_check'
  ) THEN
    ALTER TABLE public.enrollments
      ADD CONSTRAINT enrollments_withdrawn_fields_check
      CHECK (lifecycle_status = 'withdrawn' OR withdrawn_at IS NULL);
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_enrollments_cohort_lifecycle
  ON public.enrollments (cohort_id, lifecycle_status);

-- Legacy rows still marking departure through status (dropped/cancelled/
-- refunded...) released their seat under B4. Keep that semantics: they become
-- withdrawn before the guard trigger below exists.
DROP TRIGGER IF EXISTS trg_enrollments_withdrawal_rpc_guard ON public.enrollments;
DO $$
DECLARE
  v_migrated INTEGER;
BEGIN
  UPDATE public.enrollments e
  SET lifecycle_status = 'withdrawn',
      withdrawn_at = COALESCE(e.enrolled_at, now()),
      withdrawal_reason = 'ترحيل D2: حالة قديمة لا تشغل مقعداً'
  WHERE e.lifecycle_status = 'active'
    AND NOT public.enrollment_status_occupies_seat(e.status::text);

  GET DIAGNOSTICS v_migrated = ROW_COUNT;

  IF v_migrated > 0 THEN
    RAISE NOTICE 'D2 backfill: % legacy enrollments marked withdrawn (no settlement/audit row)',
      v_migrated;
  END IF;
END $$;

-- ==============================================================================
-- 2) Predicate: does this lifecycle occupy a seat?
--    C1 plan functions keep using enrollment_status_occupies_seat (status is
--    payment status and always occupies), so they remain untouched.
-- ==============================================================================
CREATE OR REPLACE FUNCTION public.enrollment_lifecycle_occupies_seat(p_lifecycle TEXT)
RETURNS BOOLEAN
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
SET search_path = public, pg_temp
AS $$
  SELECT COALESCE(NULLIF(trim(p_lifecycle), ''), 'active') NOT IN ('withdrawn');
$$;

REVOKE ALL ON FUNCTION public.enrollment_lifecycle_occupies_seat(TEXT)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.enrollment_lifecycle_occupies_seat(TEXT)
  TO service_role;

-- ==============================================================================
-- 3) fee_adjustments.kind — تمييز تسوية الانسحاب وشطب الدين
-- ==============================================================================
ALTER TABLE public.fee_adjustments
  ADD COLUMN IF NOT EXISTS kind TEXT NOT NULL DEFAULT 'manual';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.fee_adjustments'::regclass
      AND conname = 'fee_adjustments_kind_check'
  ) THEN
    ALTER TABLE public.fee_adjustments
      ADD CONSTRAINT fee_adjustments_kind_check
      CHECK (kind IN ('manual', 'withdrawal_settlement', 'debt_writeoff'));
  END IF;
END $$;

-- ==============================================================================
-- 4) جدول تدقيق الانسحاب
-- ==============================================================================
CREATE TABLE IF NOT EXISTS public.enrollment_withdrawals (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  enrollment_id UUID NOT NULL UNIQUE
    REFERENCES public.enrollments(id) ON DELETE RESTRICT,
  trainee_id UUID NOT NULL
    REFERENCES public.trainees(id) ON DELETE RESTRICT,
  currency TEXT NOT NULL,
  total_sessions INTEGER NOT NULL CHECK (total_sessions > 0),
  sessions_charged INTEGER NOT NULL CHECK (sessions_charged >= 0),
  sessions_overridden BOOLEAN NOT NULL DEFAULT false,
  session_cost NUMERIC(12,2) NOT NULL CHECK (session_cost >= 0),
  net_due_before NUMERIC(12,2) NOT NULL,
  net_due_after NUMERIC(12,2) NOT NULL CHECK (net_due_after >= 0),
  net_paid_before NUMERIC(12,2) NOT NULL,
  net_paid_after NUMERIC(12,2) NOT NULL,
  discount_revoked NUMERIC(12,2) NOT NULL DEFAULT 0,
  due_amount NUMERIC(12,2) NOT NULL CHECK (due_amount >= 0),
  settlement_delta NUMERIC(12,2) NOT NULL DEFAULT 0,
  refund_amount NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (refund_amount >= 0),
  writeoff_amount NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (writeoff_amount >= 0),
  outcome TEXT NOT NULL CHECK (outcome IN ('settled', 'refund', 'debt', 'writeoff')),
  reason TEXT NOT NULL,
  withdrawn_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by UUID REFERENCES auth.users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_enrollment_withdrawals_trainee
  ON public.enrollment_withdrawals (trainee_id, withdrawn_at DESC);

ALTER TABLE public.enrollment_withdrawals ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "enrollment_withdrawals_admin_select"
  ON public.enrollment_withdrawals;
CREATE POLICY "enrollment_withdrawals_admin_select"
ON public.enrollment_withdrawals
FOR SELECT
TO authenticated
USING (public.c1_is_admin());

REVOKE ALL ON TABLE public.enrollment_withdrawals FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.enrollment_withdrawals TO authenticated;
GRANT ALL ON TABLE public.enrollment_withdrawals TO service_role;

-- ==============================================================================
-- 5) منع تعديل دورة الحياة خارج إجراء الانسحاب
--    (المدير يملك UPDATE على enrollments عبر PostgREST؛ بدون هذا الحارس يمكن
--     تجاوز التسوية والتدقيق بتحديث عمود واحد.)
-- ==============================================================================
CREATE OR REPLACE FUNCTION public.trg_fn_enforce_withdrawal_rpc()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF current_setting('c1.withdrawal_rpc', true) = 'on' THEN
    RETURN NEW;
  END IF;

  RAISE EXCEPTION 'تغيير دورة حياة التسجيل متاح عبر إجراء الانسحاب فقط'
    USING ERRCODE = 'P0001';
END;
$$;

DROP TRIGGER IF EXISTS trg_enrollments_withdrawal_rpc_guard ON public.enrollments;
CREATE TRIGGER trg_enrollments_withdrawal_rpc_guard
BEFORE UPDATE OF lifecycle_status, withdrawn_at, withdrawal_reason
ON public.enrollments
FOR EACH ROW
EXECUTE FUNCTION public.trg_fn_enforce_withdrawal_rpc();

-- ==============================================================================
-- 6) B4: عدّ المقاعد على دورة الحياة
-- ==============================================================================
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
    AND public.enrollment_lifecycle_occupies_seat(e.lifecycle_status);
$$;

REVOKE ALL ON FUNCTION public.cohort_active_enrollment_count(UUID)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.cohort_active_enrollment_count(UUID)
  TO service_role;

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
  IF NOT public.enrollment_lifecycle_occupies_seat(NEW.lifecycle_status) THEN
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
      AND public.enrollment_lifecycle_occupies_seat(e.lifecycle_status);
  ELSE
    SELECT count(*)
    INTO v_count
    FROM public.enrollments e
    WHERE e.cohort_id = NEW.cohort_id
      AND public.enrollment_lifecycle_occupies_seat(e.lifecycle_status);
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
    AND public.enrollment_lifecycle_occupies_seat(e.lifecycle_status);

  IF v_count > NEW.capacity THEN
    RAISE EXCEPTION 'COHORT_CAPACITY_BELOW_ENROLLED'
      USING ERRCODE = 'P0001',
            DETAIL = format('cohort=%s active=%s requested_capacity=%s',
                            NEW.id, v_count, NEW.capacity);
  END IF;

  RETURN NEW;
END;
$$;

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
      AND public.enrollment_lifecycle_occupies_seat(e.lifecycle_status)
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
        AND public.enrollment_lifecycle_occupies_seat(e.lifecycle_status)
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
       public.enrollment_lifecycle_occupies_seat(OLD.lifecycle_status)
       AND NOT public.enrollment_lifecycle_occupies_seat(NEW.lifecycle_status)
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
AFTER UPDATE OF lifecycle_status, cohort_id
ON public.enrollments
FOR EACH ROW
EXECUTE FUNCTION public.trg_fn_enrollment_waitlist_on_release();

CREATE OR REPLACE FUNCTION public.trg_fn_autoclose_waitlist_on_enrollment()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_promoted_by UUID;
BEGIN
  IF NOT public.enrollment_lifecycle_occupies_seat(NEW.lifecycle_status) THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'UPDATE'
     AND OLD.cohort_id = NEW.cohort_id
     AND public.enrollment_lifecycle_occupies_seat(OLD.lifecycle_status) THEN
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
        AND public.enrollment_lifecycle_occupies_seat(e.lifecycle_status)
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
        AND public.enrollment_lifecycle_occupies_seat(e.lifecycle_status)
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
      AND public.enrollment_lifecycle_occupies_seat(e.lifecycle_status)
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
      AND public.enrollment_lifecycle_occupies_seat(e.lifecycle_status)
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
      AND public.enrollment_lifecycle_occupies_seat(e.lifecycle_status)
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

-- ==============================================================================
-- 7) A5: الإحالات تُقاس بدورة الحياة
-- ==============================================================================
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
      AND public.enrollment_lifecycle_occupies_seat(e.lifecycle_status)
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

  IF public.enrollment_lifecycle_occupies_seat(OLD.lifecycle_status)
     AND NOT public.enrollment_lifecycle_occupies_seat(NEW.lifecycle_status) THEN
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
AFTER UPDATE OF lifecycle_status ON public.enrollments
FOR EACH ROW
EXECUTE FUNCTION public.trg_fn_referral_on_enrollment_release();

-- ==============================================================================
-- 8) c1_allocate_payment: لا يُنشئ قسطاً افتراضياً لتسجيل منسحب
--    (الاستردادات تحدث بعد الانسحاب، وقد تترك الخطة صفراً؛ إنشاء قسط عندها
--     يكسر قيد trg_c1_plan_total المؤجل.)
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
           e.lifecycle_status,
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
    ) AND v_enr.net > 0
      AND v_enr.lifecycle_status <> 'withdrawn' THEN
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

-- ==============================================================================
-- 9) العرض المالي: دورة الحياة بدل حالة الدفع في احتساب التأخر
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
        WHEN public.enrollment_lifecycle_occupies_seat(e.lifecycle_status) THEN COALESCE(ia.overdue_balance, 0::numeric)
        ELSE 0::numeric
    END AS overdue_balance,
    crs.name AS course_name,
    (e.total_due - COALESCE(e.discount_amount, 0) + COALESCE(adj.total_adjustments, 0::numeric)) AS total_due,
    (COALESCE(pa.gross_paid, 0::numeric) - COALESCE(rf.total_refunded, 0::numeric)) AS total_paid,
    ((e.total_due - COALESCE(e.discount_amount, 0) + COALESCE(adj.total_adjustments, 0::numeric)) - (COALESCE(pa.gross_paid, 0::numeric) - COALESCE(rf.total_refunded, 0::numeric))) AS balance,
    CASE
        WHEN (COALESCE(pa.gross_paid, 0::numeric) - COALESCE(rf.total_refunded, 0::numeric)) >= (e.total_due - COALESCE(e.discount_amount, 0) + COALESCE(adj.total_adjustments, 0::numeric)) THEN 'complete'
        WHEN (COALESCE(pa.gross_paid, 0::numeric) - COALESCE(rf.total_refunded, 0::numeric)) > 0 THEN 'partial'
        ELSE 'unpaid'
    END AS payment_status,
    e.lifecycle_status
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
    e.status::text AS enrollment_status,
    e.lifecycle_status
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
  AND public.enrollment_lifecycle_occupies_seat(e.lifecycle_status)
  AND public.c1_can_read_financials(t.user_id);

CREATE OR REPLACE VIEW public.overdue_payments AS
SELECT
    v.enrollment_id,
    v.trainee_id,
    v.trainee_name,
    v.trainee_code,
    v.course_name,
    v.current_balance AS balance_due,
    v.currency,
    v.payment_status,
    u.phone,
    t.whatsapp_number,
    v.lifecycle_status
FROM public.enrollment_financial_summary_v2 v
JOIN public.trainees t ON t.id = v.trainee_id
LEFT JOIN public.users u ON u.id = t.user_id
WHERE v.payment_status IN ('partial', 'unpaid')
  AND v.current_balance > 0
  AND v.lifecycle_status <> 'withdrawn';

DROP VIEW IF EXISTS public.dashboard_kpis CASCADE;

CREATE VIEW public.dashboard_kpis AS
WITH fin AS (
    SELECT * FROM public.enrollment_financial_summary_v2
),
kpi AS (
    SELECT
        (SELECT count(*) FROM public.trainees) AS total_trainees,
        (SELECT count(*) FROM public.trainees t
          JOIN public.users u ON u.id = t.user_id
          WHERE u.is_active = true) AS active_trainees,
        (SELECT count(*) FROM fin
          WHERE payment_status = 'partial'
            AND lifecycle_status <> 'withdrawn') AS partial_count,
        (SELECT count(*) FROM fin
          WHERE payment_status = 'unpaid'
            AND lifecycle_status <> 'withdrawn') AS unpaid_count,

        COALESCE((SELECT sum(p.amount) FROM public.payments p
                   WHERE p.currency = 'SYP'), 0) AS total_paid_syp,
        COALESCE((SELECT sum(p.amount) FROM public.payments p
                   WHERE p.currency = 'USD'), 0) AS total_paid_usd,

        COALESCE((SELECT sum(r.amount) FROM public.payment_refunds r
                   JOIN public.payments p ON p.id = r.payment_id
                   WHERE p.currency = 'SYP'), 0) AS total_refunded_syp,
        COALESCE((SELECT sum(r.amount) FROM public.payment_refunds r
                   JOIN public.payments p ON p.id = r.payment_id
                   WHERE p.currency = 'USD'), 0) AS total_refunded_usd,

        COALESCE((SELECT sum(x.amount) FROM public.expenses x
                   WHERE x.currency = 'SYP'), 0) AS total_exp_syp,
        COALESCE((SELECT sum(x.amount) FROM public.expenses x
                   WHERE x.currency = 'USD'), 0) AS total_exp_usd,

        COALESCE((SELECT sum(GREATEST(f.current_balance, 0)) FROM fin f
                   WHERE f.currency = 'SYP'
                     AND f.lifecycle_status <> 'withdrawn'), 0) AS total_balance_syp,
        COALESCE((SELECT sum(GREATEST(f.current_balance, 0)) FROM fin f
                   WHERE f.currency = 'USD'
                     AND f.lifecycle_status <> 'withdrawn'), 0) AS total_balance_usd,

        COALESCE((SELECT sum(GREATEST(f.net_paid - f.net_due, 0)) FROM fin f
                   WHERE f.currency = 'SYP'), 0) AS total_overpaid_syp,
        COALESCE((SELECT sum(GREATEST(f.net_paid - f.net_due, 0)) FROM fin f
                   WHERE f.currency = 'USD'), 0) AS total_overpaid_usd,

        COALESCE((SELECT sum(p.amount) FROM public.payments p
                   WHERE p.currency = 'SYP'), 0)
          - COALESCE((SELECT sum(r.amount) FROM public.payment_refunds r
                       JOIN public.payments p ON p.id = r.payment_id
                       WHERE p.currency = 'SYP'), 0) AS net_paid_syp,
        COALESCE((SELECT sum(p.amount) FROM public.payments p
                   WHERE p.currency = 'USD'), 0)
          - COALESCE((SELECT sum(r.amount) FROM public.payment_refunds r
                       JOIN public.payments p ON p.id = r.payment_id
                       WHERE p.currency = 'USD'), 0) AS net_paid_usd
)
SELECT
    k.*,
    (k.net_paid_syp - k.total_exp_syp) AS net_profit_syp,
    (k.net_paid_usd - k.total_exp_usd) AS net_profit_usd
FROM kpi k
WHERE public.c1_can_read_financials(NULL);

COMMENT ON VIEW public.dashboard_kpis IS
    'KPIs مبنية على enrollment_financial_summary_v2: صافي المقبوض بعد الاستردادات، والربح بعد المصاريف، والأرصدة الموجبة فقط. التسجيلات المنسحبة مستبعدة من أعداد غير المكتمل والأرصدة.';

COMMENT ON VIEW public.overdue_payments IS
    'الأرصدة المستحقة الصافية وفق v2. التسجيلات المنسحبة مستبعدة افتراضياً (تبقى أرصدتها في v2 وكشف الحساب).';

REVOKE ALL ON public.dashboard_kpis FROM anon;
REVOKE ALL ON public.overdue_payments FROM anon;
GRANT SELECT ON public.dashboard_kpis TO authenticated, service_role;
GRANT SELECT ON public.overdue_payments TO authenticated, service_role;

-- ==============================================================================
-- 10) تذكيرات الجلسات: استبعاد المنسحب بدل حالة الدفع
-- ==============================================================================
CREATE OR REPLACE FUNCTION public.enqueue_session_reminders()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_inserted_count INTEGER;
BEGIN
  WITH target_enrollments AS (
    SELECT DISTINCT
      t.user_id,
      s.id AS session_id,
      s.scheduled_at AS session_scheduled_at,
      co.name || COALESCE(' — ' || NULLIF(s.title, ''), '') AS display_name,
      to_char(s.scheduled_at AT TIME ZONE 'Asia/Damascus', 'HH24:MI') AS start_time,
      'session:' || s.id || ':user:' || t.user_id || ':60' AS dedupe_key
    FROM public.sessions s
    JOIN public.cohorts ch ON ch.id = s.cohort_id
    JOIN public.courses co ON co.id = ch.course_id
    JOIN public.enrollments e ON e.cohort_id = ch.id
    JOIN public.trainees t ON t.id = e.trainee_id
    JOIN public.users u ON u.id = t.user_id
    WHERE s.status IN ('scheduled', 'open')
      AND s.scheduled_at BETWEEN (now() + interval '55 minutes')
                             AND (now() + interval '65 minutes')
      AND u.is_active = true
      AND e.lifecycle_status <> 'withdrawn'
      AND NOT EXISTS (
        SELECT 1 FROM public.attendance a
        WHERE a.session_id = s.id AND a.trainee_id = e.trainee_id
      )
      AND NOT EXISTS (
        SELECT 1 FROM public.notification_outbox o
        WHERE o.user_id = t.user_id
          AND o.type = 'session_reminder'
          AND o.data->>'session_id' = s.id::text
      )
  ),
  inserted AS (
    INSERT INTO public.notification_outbox (
      user_id,
      type,
      title,
      body,
      data,
      dedupe_key
    )
    SELECT
      te.user_id,
      'session_reminder',
      'تذكير بجلسة بعد ساعة',
      te.display_name || ' — الساعة ' || te.start_time,
      jsonb_build_object(
        'type', 'session_reminder',
        'session_id', te.session_id,
        'scheduled_at', te.session_scheduled_at,
        'route', '/home'
      ),
      te.dedupe_key
    FROM target_enrollments te
    ON CONFLICT (dedupe_key) DO NOTHING
    RETURNING 1
  )
  SELECT count(*) INTO v_inserted_count FROM inserted;

  RETURN v_inserted_count;
END;
$$;

REVOKE ALL ON FUNCTION public.enqueue_session_reminders() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.enqueue_session_reminders() TO service_role;

-- ==============================================================================
-- 11) محرّك الحساب المشترك: معاينة وتسوية
-- ==============================================================================
CREATE OR REPLACE FUNCTION public.c1_withdrawal_figures(
  p_enrollment_id UUID,
  p_sessions_override INTEGER DEFAULT NULL,
  p_at TIMESTAMPTZ DEFAULT now()
)
RETURNS TABLE (
  trainee_id UUID,
  currency TEXT,
  course_name TEXT,
  cohort_name TEXT,
  lifecycle_status TEXT,
  total_sessions INTEGER,
  delivered_sessions INTEGER,
  sessions_overridden BOOLEAN,
  net_due_before NUMERIC,
  net_due_after NUMERIC,
  net_paid NUMERIC,
  discount_revoked NUMERIC,
  due_amount NUMERIC,
  settlement_delta NUMERIC,
  refundable NUMERIC,
  debt_amount NUMERIC
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_trainee_id UUID;
  v_currency TEXT;
  v_cohort_id UUID;
  v_lifecycle TEXT;
  v_total_due NUMERIC(12,2);
  v_discount NUMERIC(12,2);
  v_referral_discount NUMERIC(12,2);
  v_course_name TEXT;
  v_cohort_name TEXT;
  v_total INTEGER;
  v_delivered INTEGER;
  v_overridden BOOLEAN := false;
  v_adj NUMERIC(12,2);
  v_gross NUMERIC(12,2);
  v_refunded NUMERIC(12,2);
  v_paid NUMERIC(12,2);
  v_applied NUMERIC(12,2);
  v_revoked NUMERIC(12,2);
  v_net_before NUMERIC(12,2);
  v_net_after_raw NUMERIC(12,2);
  v_net_after NUMERIC(12,2);
  v_due NUMERIC(12,2);
  v_settlement NUMERIC(12,2);
BEGIN
  SELECT e.trainee_id, e.currency::text, e.cohort_id, e.lifecycle_status,
         e.total_due, COALESCE(e.discount_amount, 0),
         COALESCE(e.referral_discount_amount, 0)
  INTO v_trainee_id, v_currency, v_cohort_id, v_lifecycle,
       v_total_due, v_discount, v_referral_discount
  FROM public.enrollments e
  WHERE e.id = p_enrollment_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'ENROLLMENT_NOT_FOUND' USING ERRCODE = 'P0001';
  END IF;

  SELECT co.name, c.name, co.total_sessions::INTEGER
  INTO v_course_name, v_cohort_name, v_total
  FROM public.cohorts c
  JOIN public.courses co ON co.id = c.course_id
  WHERE c.id = v_cohort_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'COHORT_NOT_FOUND' USING ERRCODE = 'P0001';
  END IF;

  IF v_total IS NULL OR v_total <= 0 THEN
    RAISE EXCEPTION 'لا يمكن احتساب تسوية الانسحاب: يجب تحديد إجمالي جلسات الكورس أولاً'
      USING ERRCODE = 'P0001';
  END IF;

  SELECT count(*)::INTEGER
  INTO v_delivered
  FROM public.sessions s
  WHERE s.cohort_id = v_cohort_id
    AND COALESCE(s.is_extra, false) = false
    AND s.status IN ('open', 'closed')
    AND s.scheduled_at <= p_at;

  v_delivered := LEAST(GREATEST(v_delivered, 0), v_total);

  IF p_sessions_override IS NOT NULL THEN
    IF p_sessions_override < 0 OR p_sessions_override > v_total THEN
      RAISE EXCEPTION 'SESSIONS_OVERRIDE_OUT_OF_RANGE'
        USING ERRCODE = 'P0001',
              DETAIL = format('override=%s total=%s', p_sessions_override, v_total);
    END IF;
    v_delivered := p_sessions_override;
    v_overridden := true;
  END IF;

  SELECT COALESCE(sum(fa.amount), 0)
  INTO v_adj
  FROM public.fee_adjustments fa
  WHERE fa.enrollment_id = p_enrollment_id;

  SELECT COALESCE(sum(p.amount), 0)
  INTO v_gross
  FROM public.payments p
  WHERE p.enrollment_id = p_enrollment_id;

  SELECT COALESCE(sum(r.amount), 0)
  INTO v_refunded
  FROM public.payment_refunds r
  JOIN public.payments p ON p.id = r.payment_id
  WHERE p.enrollment_id = p_enrollment_id;

  v_paid := v_gross - v_refunded;

  SELECT COALESCE(sum(r.discount_amount), 0)
  INTO v_applied
  FROM public.referrals r
  WHERE r.applied_enrollment_id = p_enrollment_id
    AND r.status = 'applied';

  v_revoked := LEAST(v_discount, v_applied + v_referral_discount);

  v_net_before := v_total_due - v_discount + v_adj;
  v_net_after_raw := v_total_due - (v_discount - v_revoked) + v_adj;
  v_net_after := GREATEST(v_net_after_raw, 0);

  v_due := GREATEST(ROUND(v_net_after * v_delivered / v_total, 2), 0);
  v_settlement := v_due - v_net_after;

  RETURN QUERY SELECT
    v_trainee_id,
    v_currency,
    v_course_name,
    v_cohort_name,
    v_lifecycle,
    v_total,
    v_delivered,
    v_overridden,
    v_net_before,
    v_net_after,
    v_paid,
    v_revoked,
    v_due,
    v_settlement,
    GREATEST(v_paid - v_due, 0),
    GREATEST(v_due - v_paid, 0);
END;
$$;

REVOKE ALL ON FUNCTION public.c1_withdrawal_figures(UUID, INTEGER, TIMESTAMPTZ)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.c1_withdrawal_figures(UUID, INTEGER, TIMESTAMPTZ)
  TO service_role;

-- ==============================================================================
-- 12) RPC: معاينة الانسحاب
-- ==============================================================================
CREATE OR REPLACE FUNCTION public.get_withdrawal_preview(
  p_enrollment_id UUID,
  p_sessions_override INTEGER DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_enr RECORD;
  v_fig RECORD;
  v_outcome TEXT;
BEGIN
  IF auth.uid() IS NOT NULL AND NOT public.c1_is_admin() THEN
    RAISE EXCEPTION 'ADMIN_ONLY' USING ERRCODE = 'P0001';
  END IF;

  SELECT e.id, e.trainee_id, e.lifecycle_status
  INTO v_enr
  FROM public.enrollments e
  WHERE e.id = p_enrollment_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'ENROLLMENT_NOT_FOUND' USING ERRCODE = 'P0001';
  END IF;

  IF v_enr.lifecycle_status <> 'active' THEN
    RETURN jsonb_build_object(
      'can_withdraw', false,
      'reason', 'ENROLLMENT_NOT_ACTIVE',
      'lifecycle_status', v_enr.lifecycle_status
    );
  END IF;

  SELECT * INTO v_fig
  FROM public.c1_withdrawal_figures(p_enrollment_id, p_sessions_override);

  v_outcome := CASE
                 WHEN v_fig.debt_amount > 0 THEN 'debt'
                 WHEN v_fig.refundable > 0 THEN 'refund'
                 ELSE 'settled'
               END;

  RETURN jsonb_build_object(
    'can_withdraw', true,
    'enrollment_id', p_enrollment_id,
    'trainee_id', v_fig.trainee_id,
    'currency', v_fig.currency,
    'course_name', v_fig.course_name,
    'cohort_name', v_fig.cohort_name,
    'lifecycle_status', v_fig.lifecycle_status,
    'total_sessions', v_fig.total_sessions,
    'sessions_charged', v_fig.delivered_sessions,
    'sessions_overridden', v_fig.sessions_overridden,
    'net_due_before', v_fig.net_due_before,
    'net_due_after', v_fig.net_due_after,
    'net_paid', v_fig.net_paid,
    'discount_revoked', v_fig.discount_revoked,
    'due_amount', v_fig.due_amount,
    'settlement_amount', v_fig.settlement_delta,
    'refundable', v_fig.refundable,
    'debt_amount', v_fig.debt_amount,
    'outcome', v_outcome
  );
END;
$$;

REVOKE ALL ON FUNCTION public.get_withdrawal_preview(UUID, INTEGER)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_withdrawal_preview(UUID, INTEGER)
  TO authenticated;

-- ==============================================================================
-- 13) RPC: تنفيذ الانسحاب (مدير فقط)
--
-- الترتيب مقصود:
--   1. قفل التسجيل ومفتاح الإحالات، وحساب الأرقام قبل التغيير.
--   2. تحديث lifecycle_status → يُشغّل تحرير الإحالات (A5) وتحرير المقعد (B4).
--      تحرير الإحالة يخفّض discount_amount، فيطبّق C1 فرق الخطة تلقائياً.
--   3. إعادة الحساب من الحالة الفعلية بعد التحديث.
--   4. استرداد الفائض LIFO (كل استرداد يعيد توزيع الأقساط FIFO).
--   5. تسوية الالتزام عبر fee_adjustments (deferred constraint يتحقق عند COMMIT).
--   6. شطب الدين اختيارياً.
--   7. تدقيق في enrollment_withdrawals.
-- ==============================================================================
CREATE OR REPLACE FUNCTION public.withdraw_enrollment(
  p_enrollment_id UUID,
  p_reason TEXT,
  p_write_off_debt BOOLEAN DEFAULT false,
  p_sessions_override INTEGER DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_at TIMESTAMPTZ := now();
  v_enr RECORD;
  v_pre RECORD;
  v_post RECORD;
  v_reason TEXT := NULLIF(btrim(COALESCE(p_reason, '')), '');
  v_payment RECORD;
  v_remaining NUMERIC(12,2);
  v_take NUMERIC(12,2);
  v_free NUMERIC(12,2);
  v_refund_total NUMERIC(12,2) := 0;
  v_writeoff NUMERIC(12,2) := 0;
  v_settlement NUMERIC(12,2);
  v_outcome TEXT;
BEGIN
  IF v_uid IS NOT NULL AND NOT public.c1_is_admin() THEN
    RAISE EXCEPTION 'ADMIN_ONLY' USING ERRCODE = 'P0001';
  END IF;

  IF v_reason IS NULL THEN
    RAISE EXCEPTION 'سبب الانسحاب مطلوب' USING ERRCODE = 'P0001';
  END IF;

  SELECT e.id, e.trainee_id, e.lifecycle_status
  INTO v_enr
  FROM public.enrollments e
  WHERE e.id = p_enrollment_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'ENROLLMENT_NOT_FOUND' USING ERRCODE = 'P0001';
  END IF;

  IF v_enr.lifecycle_status <> 'active' THEN
    RAISE EXCEPTION 'ENROLLMENT_NOT_ACTIVE' USING ERRCODE = 'P0001',
      DETAIL = format('lifecycle_status=%s', v_enr.lifecycle_status);
  END IF;

  PERFORM pg_advisory_xact_lock(
    hashtextextended('referral_credit:' || v_enr.trainee_id::text, 0)
  );

  SELECT * INTO v_pre
  FROM public.c1_withdrawal_figures(p_enrollment_id, p_sessions_override, v_at);

  -- Guard trigger allows this only under the RPC flag.
  PERFORM set_config('c1.withdrawal_rpc', 'on', true);

  UPDATE public.enrollments
  SET lifecycle_status = 'withdrawn',
      withdrawn_at = v_at,
      withdrawal_reason = v_reason
  WHERE id = p_enrollment_id;

  -- Recompute from actual post-trigger state (referral discount revocation applied).
  SELECT * INTO v_post
  FROM public.c1_withdrawal_figures(p_enrollment_id, p_sessions_override, v_at);

  -- 4) LIFO surplus refund: newest payments first.
  v_remaining := v_post.refundable;

  FOR v_payment IN
    SELECT p.id,
           p.amount - COALESCE((
             SELECT sum(rf.amount)
             FROM public.payment_refunds rf
             WHERE rf.payment_id = p.id
           ), 0) AS free_amount
    FROM public.payments p
    WHERE p.enrollment_id = p_enrollment_id
    ORDER BY p.paid_at DESC NULLS LAST,
             p.id DESC
  LOOP
    EXIT WHEN v_remaining <= 0;

    v_free := COALESCE(v_payment.free_amount, 0);
    CONTINUE WHEN v_free <= 0;

    v_take := LEAST(v_remaining, v_free);

    INSERT INTO public.payment_refunds (
      payment_id,
      amount,
      reason,
      created_by
    ) VALUES (
      v_payment.id,
      v_take,
      'استرداد فائض انسحاب pro-rata',
      v_uid
    );

    v_remaining := v_remaining - v_take;
    v_refund_total := v_refund_total + v_take;
  END LOOP;

  IF v_remaining > 0 THEN
    RAISE EXCEPTION 'REFUND_ALLOCATION_FAILED'
      USING ERRCODE = 'P0001',
            DETAIL = format('remaining=%s', v_remaining);
  END IF;

  -- 5) Settle the obligation to the pro-rata due amount.
  v_settlement := v_post.settlement_delta;

  IF v_settlement <> 0 THEN
    INSERT INTO public.fee_adjustments (
      enrollment_id,
      amount,
      reason,
      kind,
      created_by
    ) VALUES (
      p_enrollment_id,
      v_settlement,
      'تسوية انسحاب pro-rata: ' || v_post.delivered_sessions || ' من ' ||
        v_post.total_sessions || ' جلسة',
      'withdrawal_settlement',
      v_uid
    );
  END IF;

  -- 6) Optional debt write-off (admin decision).
  IF p_write_off_debt AND v_post.debt_amount > 0 THEN
    v_writeoff := v_post.debt_amount;

    INSERT INTO public.fee_adjustments (
      enrollment_id,
      amount,
      reason,
      kind,
      created_by
    ) VALUES (
      p_enrollment_id,
      -v_writeoff,
      'شطب دين انسحاب بقرار الإدارة',
      'debt_writeoff',
      v_uid
    );
  END IF;

  v_outcome := CASE
                 WHEN v_writeoff > 0 THEN 'writeoff'
                 WHEN v_post.debt_amount > 0 THEN 'debt'
                 WHEN v_refund_total > 0 THEN 'refund'
                 ELSE 'settled'
               END;

  -- Ensure enrollments.status reflects the settled obligation even when no
  -- refund/adjustment was written (paid == due exactly).
  PERFORM public.c1_refresh_enrollment_status(p_enrollment_id);

  -- 7) Audit.
  INSERT INTO public.enrollment_withdrawals (
    enrollment_id,
    trainee_id,
    currency,
    total_sessions,
    sessions_charged,
    sessions_overridden,
    session_cost,
    net_due_before,
    net_due_after,
    net_paid_before,
    net_paid_after,
    discount_revoked,
    due_amount,
    settlement_delta,
    refund_amount,
    writeoff_amount,
    outcome,
    reason,
    withdrawn_at,
    created_by
  ) VALUES (
    p_enrollment_id,
    v_enr.trainee_id,
    v_post.currency,
    v_post.total_sessions,
    v_post.delivered_sessions,
    v_post.sessions_overridden,
    CASE
      WHEN v_post.total_sessions > 0
      THEN ROUND(v_post.net_due_after / v_post.total_sessions, 2)
      ELSE 0
    END,
    v_pre.net_due_before,
    v_post.net_due_after,
    v_pre.net_paid,
    v_pre.net_paid - v_refund_total,
    v_pre.discount_revoked,
    v_post.due_amount,
    v_settlement,
    v_refund_total,
    v_writeoff,
    v_outcome,
    v_reason,
    v_at,
    v_uid
  );

  PERFORM set_config('c1.withdrawal_rpc', 'off', true);

  RETURN jsonb_build_object(
    'enrollment_id', p_enrollment_id,
    'lifecycle_status', 'withdrawn',
    'currency', v_post.currency,
    'total_sessions', v_post.total_sessions,
    'sessions_charged', v_post.delivered_sessions,
    'sessions_overridden', v_post.sessions_overridden,
    'net_due_before', v_pre.net_due_before,
    'net_due_after', v_post.net_due_after,
    'net_paid_before', v_pre.net_paid,
    'net_paid_after', v_pre.net_paid - v_refund_total,
    'discount_revoked', v_pre.discount_revoked,
    'due_amount', v_post.due_amount,
    'settlement_amount', v_settlement,
    'refund_amount', v_refund_total,
    'debt_amount', v_post.debt_amount,
    'writeoff_amount', v_writeoff,
    'outcome', v_outcome
  );
END;
$$;

REVOKE ALL ON FUNCTION public.withdraw_enrollment(UUID, TEXT, BOOLEAN, INTEGER)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.withdraw_enrollment(UUID, TEXT, BOOLEAN, INTEGER)
  TO authenticated;

-- ==============================================================================
-- 14) الصلاحيات على دوال التريغر المعدَّلة
-- ==============================================================================
REVOKE ALL ON FUNCTION public.trg_fn_enforce_withdrawal_rpc()
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.trg_fn_enforce_cohort_capacity()
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.trg_fn_validate_cohort_capacity()
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.trg_fn_validate_waitlist_insert()
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.trg_fn_validate_waitlist_transition()
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.trg_fn_enrollment_waitlist_on_release()
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.trg_fn_autoclose_waitlist_on_enrollment()
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.trg_fn_enrollments_referral_before()
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.trg_fn_referral_on_enrollment_release()
  FROM PUBLIC, anon, authenticated;

REVOKE ALL ON FUNCTION public.notify_next_waitlist(UUID)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.notify_next_waitlist(UUID) TO service_role;

REVOKE ALL ON FUNCTION public.join_course_waitlist(UUID, UUID)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.join_course_waitlist(UUID, UUID) TO authenticated;

REVOKE ALL ON FUNCTION public.promote_waitlist_trainee(UUID, NUMERIC, NUMERIC, TEXT, TEXT, NUMERIC)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.promote_waitlist_trainee(UUID, NUMERIC, NUMERIC, TEXT, TEXT, NUMERIC)
  TO authenticated;

REVOKE ALL ON FUNCTION public.get_cohorts_seat_status(UUID)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_cohorts_seat_status(UUID) TO authenticated;

COMMIT;
