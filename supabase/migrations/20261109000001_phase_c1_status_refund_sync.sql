-- ═══════════════════════════════════════════════════════════════════════
-- Phase C1 — إصلاح مزامنة enrollments.status مع الاستردادات وتعديلات الرسوم
--
-- العيب المؤكد حياً (2026-11-09):
--   الدالة update_enrollment_payment_status تحسب المدفوع من payments فقط
--   (gross) دون طرح payment_refunds، وتتجاهل fee_adjustments عند حساب
--   الصافي، ولا تُشغَّل عند الاسترداد. النتيجة: بعد استرداد كامل يبقى
--   enrollments.status = 'partial' بينما payment_status في
--   enrollment_financial_summary_v2 = 'unpaid'.
--
-- الإصلاح: مصدر حساب واحد (c1_refresh_enrollment_status) + ربطه بالاستردادات
--   وتعديلات الرسوم وحذف الدفعات + backfill لكل التسجيلات.
-- ═══════════════════════════════════════════════════════════════════════
BEGIN;

-- --------------------------------------------------------------------------
-- 1) المصدر الوحيد لحساب حالة الدفع — يطابق معادلة العرض v2 حرفياً:
--    net_paid = sum(payments) - sum(refunds)
--    net_due  = total_due - discount_amount + sum(fee_adjustments)
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.c1_refresh_enrollment_status(p_enrollment_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_net_paid numeric(12,2);
  v_net_due  numeric(12,2);
  v_new      public.payment_status;
BEGIN
  IF p_enrollment_id IS NULL THEN
    RETURN;
  END IF;

  SELECT COALESCE(sum(p.amount), 0) - COALESCE((
           SELECT sum(r.amount)
           FROM public.payment_refunds r
           JOIN public.payments p2 ON p2.id = r.payment_id
           WHERE p2.enrollment_id = p_enrollment_id
         ), 0)
  INTO v_net_paid
  FROM public.payments p
  WHERE p.enrollment_id = p_enrollment_id;

  SELECT COALESCE(e.total_due, 0) - COALESCE(e.discount_amount, 0) + COALESCE((
           SELECT sum(fa.amount)
           FROM public.fee_adjustments fa
           WHERE fa.enrollment_id = p_enrollment_id
         ), 0)
  INTO v_net_due
  FROM public.enrollments e
  WHERE e.id = p_enrollment_id;

  IF v_net_due IS NULL THEN
    RETURN;
  END IF;

  v_new := CASE
             WHEN v_net_paid >= v_net_due THEN 'complete'::public.payment_status
             WHEN v_net_paid > 0 THEN 'partial'::public.payment_status
             ELSE 'unpaid'::public.payment_status
           END;

  UPDATE public.enrollments
  SET status = v_new
  WHERE id = p_enrollment_id
    AND status IS DISTINCT FROM v_new;
END;
$$;

-- --------------------------------------------------------------------------
-- 2) استبدال الدالة الحية بنفس الاسم حتى تبقى triggers payments الحالية تعمل
--    (وتدعم DELETE أيضاً، إذ كانت الدالة القديمة تفشل على NEW في DELETE)
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.update_enrollment_payment_status()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_enrollment_id uuid;
BEGIN
  IF TG_OP = 'DELETE' THEN
    v_enrollment_id := OLD.enrollment_id;
  ELSE
    v_enrollment_id := NEW.enrollment_id;
  END IF;

  PERFORM public.c1_refresh_enrollment_status(v_enrollment_id);

  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;
  RETURN NEW;
END;
$$;

-- --------------------------------------------------------------------------
-- 3) الاستردادات: تحديث الحالة عند الإضافة أو الحذف
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.trg_fn_c1_refund_status_sync()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_payment_id    uuid;
  v_enrollment_id uuid;
BEGIN
  IF TG_OP = 'DELETE' THEN
    v_payment_id := OLD.payment_id;
  ELSE
    v_payment_id := NEW.payment_id;
  END IF;

  SELECT p.enrollment_id INTO v_enrollment_id
  FROM public.payments p
  WHERE p.id = v_payment_id;

  PERFORM public.c1_refresh_enrollment_status(v_enrollment_id);

  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_c1_refund_status_sync ON public.payment_refunds;
CREATE TRIGGER trg_c1_refund_status_sync
AFTER INSERT OR DELETE ON public.payment_refunds
FOR EACH ROW EXECUTE FUNCTION public.trg_fn_c1_refund_status_sync();

-- --------------------------------------------------------------------------
-- 4) تعديلات الرسوم: الصافي يتغير دون أن تتغير total_due
--    (trg_c1_adjustment_apply يطبّق فرق الخطة أولاً لأنه أسبق أبجدياً)
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.trg_fn_c1_adjustment_status_sync()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_enrollment_id uuid;
BEGIN
  IF TG_OP = 'DELETE' THEN
    v_enrollment_id := OLD.enrollment_id;
  ELSE
    v_enrollment_id := NEW.enrollment_id;
  END IF;

  PERFORM public.c1_refresh_enrollment_status(v_enrollment_id);

  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_c1_adjustment_status_sync ON public.fee_adjustments;
CREATE TRIGGER trg_c1_adjustment_status_sync
AFTER INSERT OR DELETE ON public.fee_adjustments
FOR EACH ROW EXECUTE FUNCTION public.trg_fn_c1_adjustment_status_sync();

-- --------------------------------------------------------------------------
-- 5) حذف دفعة: غير مغطى في التريغر الحي، ويجب أن يعيد الحالة
-- --------------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_c1_payment_delete_status_sync ON public.payments;
CREATE TRIGGER trg_c1_payment_delete_status_sync
AFTER DELETE ON public.payments
FOR EACH ROW EXECUTE FUNCTION public.update_enrollment_payment_status();

-- --------------------------------------------------------------------------
-- 6) Backfill: إعادة حساب الحالة لكل التسجيلات الموجودة
-- --------------------------------------------------------------------------
DO $$
DECLARE
  r record;
BEGIN
  FOR r IN SELECT id FROM public.enrollments LOOP
    PERFORM public.c1_refresh_enrollment_status(r.id);
  END LOOP;
END $$;

-- --------------------------------------------------------------------------
-- 7) الصلاحيات: دوال triggers لا تُستدعى مباشرة
-- --------------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.c1_refresh_enrollment_status(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.update_enrollment_payment_status() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.trg_fn_c1_refund_status_sync() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.trg_fn_c1_adjustment_status_sync() FROM PUBLIC, anon, authenticated;

COMMIT;
