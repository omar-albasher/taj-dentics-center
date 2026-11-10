-- ═══════════════════════════════════════════════════════════════════════
-- Phase D1 — توحيد مصادر الحقيقة المالية وتشغيل الأتمتة
--
-- المشكلة: dashboard_kpis وoverdue_payments وتذكيرات الأقساط كانت تعتمد
-- على enrollment_financial_summary (v1) الذي لا يعكس الاستردادات ولا
-- تعديلات الرسوم، ما يجعل أرقام اللوحة والمتأخرات والتذكيرات تنحرف عن
-- نموذج C1 المعتمد في enrollment_financial_summary_v2.
--
-- القرارات المنفذة:
--   1. KPIs على v2: صافي المقبوض بعد الاستردادات، ربح صافٍ بعد المصاريف.
--   2. المتأخرات على v2 (current_balance > 0).
--   3. تذكيرات الأقساط أسبوعياً للمتأخرين فقط (overdue_installments_v).
--   4. حارس كتابة الدفعات: منع تعديل المبلغ/العملة/التسجيل ومنع حذف
--      دفعة عليها استردادات؛ الحذف لمدير المركز فقط.
--   5. تثبيت جدولة pg_cron: فتح/إغلاق الجلسات + التذكيرات الأسبوعية.
--
-- ملاحظة: الأعمدة القديمة محفوظة بالاسم، مع إضافة أعمدة صافية صريحة
-- (net_paid_*, total_refunded_*, total_overpaid_*) لتفادي أي تغيير صامت
-- في معنى الأعمدة القائمة.
-- ═══════════════════════════════════════════════════════════════════════
BEGIN;

-- ==============================================================================
-- 1) dashboard_kpis — v2 net model
-- ==============================================================================
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
        (SELECT count(*) FROM fin WHERE payment_status = 'partial') AS partial_count,
        (SELECT count(*) FROM fin WHERE payment_status = 'unpaid') AS unpaid_count,

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
                   WHERE f.currency = 'SYP'), 0) AS total_balance_syp,
        COALESCE((SELECT sum(GREATEST(f.current_balance, 0)) FROM fin f
                   WHERE f.currency = 'USD'), 0) AS total_balance_usd,

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
    'KPIs مبنية على enrollment_financial_summary_v2: صافي المقبوض بعد الاستردادات، والربح بعد المصاريف، والأرصدة الموجبة فقط. متاحة للطاقم فقط (c1_can_read_financials).';

-- ==============================================================================
-- 2) overdue_payments — v2 current balance
-- ==============================================================================
DROP VIEW IF EXISTS public.overdue_payments CASCADE;

CREATE VIEW public.overdue_payments AS
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
    t.whatsapp_number
FROM public.enrollment_financial_summary_v2 v
JOIN public.trainees t ON t.id = v.trainee_id
LEFT JOIN public.users u ON u.id = t.user_id
WHERE v.payment_status IN ('partial', 'unpaid')
  AND v.current_balance > 0;

COMMENT ON VIEW public.overdue_payments IS
    'الأرصدة المستحقة الصافية وفق v2 (بعد الاستردادات وتعديلات الرسوم).';

-- ==============================================================================
-- 3) تذكيرات الأقساط: أسبوعية ولمن تأخر قسطه فعلاً فقط
-- ==============================================================================
CREATE OR REPLACE FUNCTION public.enqueue_payment_reminders()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_inserted_count INTEGER;
  v_week_code TEXT := to_char(now() AT TIME ZONE 'Asia/Damascus', 'IYYY-IW');
BEGIN
  WITH debtors AS (
    SELECT DISTINCT t.user_id
    FROM public.overdue_installments_v oi
    JOIN public.trainees t ON t.id = oi.trainee_id
    JOIN public.users u ON u.id = t.user_id
    WHERE u.is_active = true
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
      d.user_id,
      'payment_reminder',
      'تذكير بموعد القسط',
      'لديك قسط متأخر — يرجى مراجعة التفاصيل داخل التطبيق',
      jsonb_build_object(
        'type', 'payment_reminder',
        'route', '/payments'
      ),
      'payment_due:user:' || d.user_id || ':' || v_week_code
    FROM debtors d
    ON CONFLICT (dedupe_key) DO NOTHING
    RETURNING 1
  )
  SELECT count(*) INTO v_inserted_count FROM inserted;

  RETURN v_inserted_count;
END;
$$;

REVOKE ALL ON FUNCTION public.enqueue_payment_reminders() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.enqueue_payment_reminders() TO service_role;

-- ==============================================================================
-- 4) حارس كتابة الدفعات (تعديل/حذف)
-- ==============================================================================
CREATE OR REPLACE FUNCTION public.trg_fn_c1_payment_write_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF auth.uid() IS NOT NULL AND NOT public.c1_is_admin() THEN
    IF TG_OP = 'DELETE' THEN
      RAISE EXCEPTION 'حذف الدفعة متاح لمدير المركز فقط';
    END IF;
  END IF;

  IF TG_OP = 'DELETE' THEN
    IF EXISTS (
      SELECT 1 FROM public.payment_refunds r WHERE r.payment_id = OLD.id
    ) THEN
      RAISE EXCEPTION 'لا يمكن حذف دفعة عليها استردادات: احذف الاستردادات أولاً';
    END IF;
    RETURN OLD;
  END IF;

  IF NEW.amount IS DISTINCT FROM OLD.amount
     OR NEW.currency IS DISTINCT FROM OLD.currency
     OR NEW.enrollment_id IS DISTINCT FROM OLD.enrollment_id THEN
    RAISE EXCEPTION 'لا يمكن تعديل مبلغ أو عملة أو تسجيل دفعة صادرة: احذفها وأعد تسجيلها';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_c1_payment_write_guard ON public.payments;
CREATE TRIGGER trg_c1_payment_write_guard
BEFORE UPDATE OR DELETE ON public.payments
FOR EACH ROW EXECUTE FUNCTION public.trg_fn_c1_payment_write_guard();

-- ==============================================================================
-- 5) pg_cron: تثبيت الحالة المطلوبة في المستودع
-- ==============================================================================

-- 5.1 تذكيرات الأقساط: أسبوعياً كل يوم أحد 07:00 UTC (10:00 دمشق)
DO $$
BEGIN
  PERFORM cron.unschedule('taj_push_payment_reminders');
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

SELECT cron.schedule(
  'taj_push_payment_reminders',
  '0 7 * * 0',
  $$SELECT public.enqueue_payment_reminders();$$
);

-- 5.2 الفتح/الإغلاق التلقائي للجلسات: كل 5 دقائق (نبض cron_job_log)
DO $$
BEGIN
  PERFORM cron.unschedule('taj_auto_open_close_sessions');
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

SELECT cron.schedule(
  'taj_auto_open_close_sessions',
  '*/5 * * * *',
  $$SELECT public.auto_open_close_sessions(false);$$
);

-- ==============================================================================
-- 6) الصلاحيات
-- ==============================================================================
REVOKE ALL ON public.dashboard_kpis FROM anon;
REVOKE ALL ON public.overdue_payments FROM anon;
GRANT SELECT ON public.dashboard_kpis TO authenticated, service_role;
GRANT SELECT ON public.overdue_payments TO authenticated, service_role;

COMMIT;
