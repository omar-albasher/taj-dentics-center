-- ==============================================================================
-- Taj Dentics Training Center - Phase 10: Dental Lab Management System (المخبر)
-- Migration: 20261022000004_phase10_dental_lab.sql
-- ==============================================================================

-- 1. Dental Lab Clients (عيادات وأطباء الأسنان)
CREATE TABLE IF NOT EXISTS public.lab_clients (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    phone TEXT,
    clinic_address TEXT,
    notes TEXT,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

-- 2. Dental Lab Invoices (فواتير المخبر)
CREATE SEQUENCE IF NOT EXISTS public.lab_invoice_number_seq START WITH 1001;

CREATE TABLE IF NOT EXISTS public.lab_invoices (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    invoice_number INT NOT NULL UNIQUE,
    client_id UUID NOT NULL REFERENCES public.lab_clients(id) ON DELETE RESTRICT,
    patient_name TEXT,
    status TEXT NOT NULL DEFAULT 'unpaid' CHECK (status IN ('unpaid', 'partial', 'paid', 'cancelled')),
    currency TEXT NOT NULL DEFAULT 'SYP' CHECK (currency IN ('SYP', 'USD')),
    subtotal NUMERIC(12, 2) NOT NULL DEFAULT 0.00 CHECK (subtotal >= 0),
    discount NUMERIC(12, 2) NOT NULL DEFAULT 0.00 CHECK (discount >= 0),
    total_amount NUMERIC(12, 2) NOT NULL DEFAULT 0.00 CHECK (total_amount >= 0),
    paid_amount NUMERIC(12, 2) NOT NULL DEFAULT 0.00 CHECK (paid_amount >= 0),
    issue_date DATE NOT NULL DEFAULT CURRENT_DATE,
    due_date DATE,
    notes TEXT,
    created_by UUID REFERENCES public.users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

-- 3. Dental Lab Invoice Items (بنود/خدمات الفاتورة)
CREATE TABLE IF NOT EXISTS public.lab_invoice_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    invoice_id UUID NOT NULL REFERENCES public.lab_invoices(id) ON DELETE CASCADE,
    service_name TEXT NOT NULL,
    tooth_number TEXT,
    shade TEXT,
    quantity INT NOT NULL DEFAULT 1 CHECK (quantity > 0),
    unit_price NUMERIC(12, 2) NOT NULL DEFAULT 0.00 CHECK (unit_price >= 0),
    total_price NUMERIC(12, 2) NOT NULL DEFAULT 0.00 CHECK (total_price >= 0),
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

-- 4. Dental Lab Payments (سجل تسديد دفعات فواتير المخبر)
CREATE TABLE IF NOT EXISTS public.lab_payments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    invoice_id UUID NOT NULL REFERENCES public.lab_invoices(id) ON DELETE RESTRICT,
    amount NUMERIC(12, 2) NOT NULL CHECK (amount > 0),
    currency TEXT NOT NULL DEFAULT 'SYP' CHECK (currency IN ('SYP', 'USD')),
    paid_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    method TEXT NOT NULL CHECK (method IN ('cash', 'sham_cash', 'hawala', 'bank_transfer')),
    receipt_number TEXT,
    external_reference TEXT,
    notes TEXT,
    performed_by UUID REFERENCES public.users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

-- 5. Dental Lab Expenses (مصاريف خاصة بالمخبر فقط)
CREATE TABLE IF NOT EXISTS public.lab_expenses (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title TEXT NOT NULL,
    category TEXT NOT NULL DEFAULT 'materials' CHECK (category IN ('materials', 'equipment_maintenance', 'utilities', 'salaries', 'other')),
    amount NUMERIC(12, 2) NOT NULL CHECK (amount > 0),
    currency TEXT NOT NULL DEFAULT 'SYP' CHECK (currency IN ('SYP', 'USD')),
    expense_date DATE NOT NULL DEFAULT CURRENT_DATE,
    payment_method TEXT NOT NULL DEFAULT 'cash' CHECK (payment_method IN ('cash', 'sham_cash', 'hawala', 'bank_transfer')),
    notes TEXT,
    performed_by UUID REFERENCES public.users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

-- ------------------------------------------------------------------------------
-- Indexes for Performance
-- ------------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_lab_invoices_client_id ON public.lab_invoices(client_id);
CREATE INDEX IF NOT EXISTS idx_lab_invoices_status ON public.lab_invoices(status);
CREATE INDEX IF NOT EXISTS idx_lab_invoices_created_at ON public.lab_invoices(created_at);
CREATE INDEX IF NOT EXISTS idx_lab_invoice_items_invoice_id ON public.lab_invoice_items(invoice_id);
CREATE INDEX IF NOT EXISTS idx_lab_payments_invoice_id ON public.lab_payments(invoice_id);
CREATE INDEX IF NOT EXISTS idx_lab_expenses_expense_date ON public.lab_expenses(expense_date);
CREATE INDEX IF NOT EXISTS idx_lab_expenses_category ON public.lab_expenses(category);

-- ------------------------------------------------------------------------------
-- Trigger 1: Auto-generate Invoice Number
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.lab_invoice_set_number()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.invoice_number IS NULL OR NEW.invoice_number <= 0 THEN
        NEW.invoice_number := nextval('public.lab_invoice_number_seq');
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_lab_invoice_set_number ON public.lab_invoices;
CREATE TRIGGER trg_lab_invoice_set_number
BEFORE INSERT ON public.lab_invoices
FOR EACH ROW
EXECUTE FUNCTION public.lab_invoice_set_number();

-- ------------------------------------------------------------------------------
-- Trigger 2: Calculate Item Total Price
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.lab_invoice_item_calc_total()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.total_price := ROUND((NEW.quantity * NEW.unit_price)::numeric, 2);
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_lab_invoice_item_calc_total ON public.lab_invoice_items;
CREATE TRIGGER trg_lab_invoice_item_calc_total
BEFORE INSERT OR UPDATE ON public.lab_invoice_items
FOR EACH ROW
EXECUTE FUNCTION public.lab_invoice_item_calc_total();

-- ------------------------------------------------------------------------------
-- Function & Triggers: Recalculate Invoice Subtotal, Total, Paid Amount, and Status
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.recalculate_lab_invoice(p_invoice_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_subtotal NUMERIC(12, 2);
    v_discount NUMERIC(12, 2);
    v_total NUMERIC(12, 2);
    v_paid NUMERIC(12, 2);
    v_status TEXT;
    v_current_status TEXT;
BEGIN
    SELECT COALESCE(SUM(total_price), 0.00)
    INTO v_subtotal
    FROM public.lab_invoice_items
    WHERE invoice_id = p_invoice_id;

    SELECT COALESCE(discount, 0.00), status
    INTO v_discount, v_current_status
    FROM public.lab_invoices
    WHERE id = p_invoice_id;

    IF v_current_status = 'cancelled' THEN
        v_status := 'cancelled';
    ELSE
        v_total := GREATEST(ROUND((v_subtotal - v_discount)::numeric, 2), 0.00);

        SELECT COALESCE(SUM(amount), 0.00)
        INTO v_paid
        FROM public.lab_payments
        WHERE invoice_id = p_invoice_id;

        IF v_total > 0 AND v_paid >= v_total THEN
            v_status := 'paid';
        ELSIF v_paid > 0 THEN
            v_status := 'partial';
        ELSE
            v_status := 'unpaid';
        END IF;
    END IF;

    UPDATE public.lab_invoices
    SET
        subtotal = v_subtotal,
        total_amount = GREATEST(ROUND((v_subtotal - v_discount)::numeric, 2), 0.00),
        paid_amount = (SELECT COALESCE(SUM(amount), 0.00) FROM public.lab_payments WHERE invoice_id = p_invoice_id),
        status = v_status,
        updated_at = timezone('utc'::text, now())
    WHERE id = p_invoice_id;
END;
$$;


-- Hardening: Prevent direct RPC execution of recalculate_lab_invoice by trainees / reception
REVOKE ALL ON FUNCTION public.recalculate_lab_invoice(UUID) FROM PUBLIC, anon, authenticated;

-- Trigger on items changes
CREATE OR REPLACE FUNCTION public.trg_lab_invoice_items_sync()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        PERFORM public.recalculate_lab_invoice(OLD.invoice_id);
    ELSE
        PERFORM public.recalculate_lab_invoice(NEW.invoice_id);
    END IF;
    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_lab_items_sync ON public.lab_invoice_items;
CREATE TRIGGER trg_lab_items_sync
AFTER INSERT OR UPDATE OR DELETE ON public.lab_invoice_items
FOR EACH ROW
EXECUTE FUNCTION public.trg_lab_invoice_items_sync();

-- Trigger on payments changes
CREATE OR REPLACE FUNCTION public.trg_lab_payments_sync()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        PERFORM public.recalculate_lab_invoice(OLD.invoice_id);
    ELSE
        PERFORM public.recalculate_lab_invoice(NEW.invoice_id);
    END IF;
    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_lab_payments_sync ON public.lab_payments;
CREATE TRIGGER trg_lab_payments_sync
AFTER INSERT OR UPDATE OR DELETE ON public.lab_payments
FOR EACH ROW
EXECUTE FUNCTION public.trg_lab_payments_sync();

-- Trigger on invoice discount change
CREATE OR REPLACE FUNCTION public.trg_lab_invoice_discount_sync()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.discount IS DISTINCT FROM OLD.discount THEN
        NEW.total_amount := GREATEST(ROUND((NEW.subtotal - COALESCE(NEW.discount, 0.00))::numeric, 2), 0.00);
        IF NEW.status != 'cancelled' THEN
            IF NEW.total_amount > 0 AND NEW.paid_amount >= NEW.total_amount THEN
                NEW.status := 'paid';
            ELSIF NEW.paid_amount > 0 THEN
                NEW.status := 'partial';
            ELSE
                NEW.status := 'unpaid';
            END IF;
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_lab_invoice_discount_sync ON public.lab_invoices;
CREATE TRIGGER trg_lab_invoice_discount_sync
BEFORE UPDATE OF discount ON public.lab_invoices
FOR EACH ROW
EXECUTE FUNCTION public.trg_lab_invoice_discount_sync();

-- ------------------------------------------------------------------------------
-- RLS Policies: Strictly Admin Only (Matching expenses and monthly_targets pattern)
-- ------------------------------------------------------------------------------
ALTER TABLE public.lab_clients ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lab_invoices ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lab_invoice_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lab_payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lab_expenses ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "lab_clients_admin_only" ON public.lab_clients;
CREATE POLICY "lab_clients_admin_only" ON public.lab_clients
  FOR ALL TO authenticated
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

DROP POLICY IF EXISTS "lab_invoices_admin_only" ON public.lab_invoices;
CREATE POLICY "lab_invoices_admin_only" ON public.lab_invoices
  FOR ALL TO authenticated
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

DROP POLICY IF EXISTS "lab_invoice_items_admin_only" ON public.lab_invoice_items;
CREATE POLICY "lab_invoice_items_admin_only" ON public.lab_invoice_items
  FOR ALL TO authenticated
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

DROP POLICY IF EXISTS "lab_payments_admin_only" ON public.lab_payments;
CREATE POLICY "lab_payments_admin_only" ON public.lab_payments
  FOR ALL TO authenticated
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

DROP POLICY IF EXISTS "lab_expenses_admin_only" ON public.lab_expenses;
CREATE POLICY "lab_expenses_admin_only" ON public.lab_expenses
  FOR ALL TO authenticated
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

-- ------------------------------------------------------------------------------
-- Update export_system_data to Include Dental Lab System Tables
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.export_system_data()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_role text;
BEGIN
    SELECT role INTO v_user_role 
    FROM public.users 
    WHERE id = auth.uid() AND is_active = true;

    IF v_user_role IS DISTINCT FROM 'admin' THEN
        RAISE EXCEPTION 'غير مصرح: تصدير بيانات النظام مخصص حصراً لمدير النظام (Admin)';
    END IF;

    RETURN jsonb_build_object(
        'metadata', jsonb_build_object(
            'system_name', 'Taj Dentics Training Center & Dental Lab',
            'export_type', 'full_system_data_snapshot',
            'version', '1.1.0',
            'exported_at', to_char(now() AT TIME ZONE 'Asia/Damascus', 'YYYY-MM-DD"T"HH24:MI:SS"+03:00"'),
            'exported_by_user_id', auth.uid(),
            'exported_by_email', (SELECT email FROM auth.users WHERE id = auth.uid()),
            'counts', jsonb_build_object(
                'users', (SELECT count(*) FROM public.users),
                'trainees', (SELECT count(*) FROM public.trainees),
                'courses', (SELECT count(*) FROM public.courses),
                'cohorts', (SELECT count(*) FROM public.cohorts),
                'sessions', (SELECT count(*) FROM public.sessions),
                'enrollments', (SELECT count(*) FROM public.enrollments),
                'payments', (SELECT count(*) FROM public.payments),
                'expenses', (SELECT count(*) FROM public.expenses),
                'attendance', (SELECT count(*) FROM public.attendance),
                'survey_templates', (SELECT count(*) FROM public.survey_templates),
                'survey_dispatches', (SELECT count(*) FROM public.survey_dispatches),
                'survey_responses', (SELECT count(*) FROM public.survey_responses),
                'monthly_targets', (SELECT count(*) FROM public.monthly_targets),
                'lab_clients', (SELECT count(*) FROM public.lab_clients),
                'lab_invoices', (SELECT count(*) FROM public.lab_invoices),
                'lab_invoice_items', (SELECT count(*) FROM public.lab_invoice_items),
                'lab_payments', (SELECT count(*) FROM public.lab_payments),
                'lab_expenses', (SELECT count(*) FROM public.lab_expenses)
            )
        ),
        'data', jsonb_build_object(
            'users', (SELECT COALESCE(jsonb_agg(to_jsonb(u)), '[]'::jsonb) FROM public.users u),
            'trainees', (SELECT COALESCE(jsonb_agg(to_jsonb(t)), '[]'::jsonb) FROM public.trainees t),
            'courses', (SELECT COALESCE(jsonb_agg(to_jsonb(c)), '[]'::jsonb) FROM public.courses c),
            'cohorts', (SELECT COALESCE(jsonb_agg(to_jsonb(ch)), '[]'::jsonb) FROM public.cohorts ch),
            'sessions', (SELECT COALESCE(jsonb_agg(to_jsonb(s)), '[]'::jsonb) FROM public.sessions s),
            'enrollments', (SELECT COALESCE(jsonb_agg(to_jsonb(e)), '[]'::jsonb) FROM public.enrollments e),
            'payments', (SELECT COALESCE(jsonb_agg(to_jsonb(p)), '[]'::jsonb) FROM public.payments p),
            'expenses', (SELECT COALESCE(jsonb_agg(to_jsonb(ex)), '[]'::jsonb) FROM public.expenses ex),
            'attendance', (SELECT COALESCE(jsonb_agg(to_jsonb(a)), '[]'::jsonb) FROM public.attendance a),
            'survey_templates', (SELECT COALESCE(jsonb_agg(to_jsonb(st)), '[]'::jsonb) FROM public.survey_templates st),
            'survey_dispatches', (SELECT COALESCE(jsonb_agg(to_jsonb(sd)), '[]'::jsonb) FROM public.survey_dispatches sd),
            'survey_responses', (SELECT COALESCE(jsonb_agg(to_jsonb(sr)), '[]'::jsonb) FROM public.survey_responses sr),
            'monthly_targets', (SELECT COALESCE(jsonb_agg(to_jsonb(mt)), '[]'::jsonb) FROM public.monthly_targets mt),
            'lab_clients', (SELECT COALESCE(jsonb_agg(to_jsonb(lc)), '[]'::jsonb) FROM public.lab_clients lc),
            'lab_invoices', (SELECT COALESCE(jsonb_agg(to_jsonb(li)), '[]'::jsonb) FROM public.lab_invoices li),
            'lab_invoice_items', (SELECT COALESCE(jsonb_agg(to_jsonb(lii)), '[]'::jsonb) FROM public.lab_invoice_items lii),
            'lab_payments', (SELECT COALESCE(jsonb_agg(to_jsonb(lp)), '[]'::jsonb) FROM public.lab_payments lp),
            'lab_expenses', (SELECT COALESCE(jsonb_agg(to_jsonb(le)), '[]'::jsonb) FROM public.lab_expenses le)
        )
    );
END;
$$;
