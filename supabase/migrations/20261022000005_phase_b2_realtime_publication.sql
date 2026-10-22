-- ==============================================================================
-- Taj Dentics Training Center - Phase B2: Live Activity Feed Realtime Publication
-- Migration: 20261022000005_phase_b2_realtime_publication.sql
-- ==============================================================================

-- Enable Supabase Realtime replication for the 3 live event tables:
-- 1. payments (Trainee course installment payments)
-- 2. attendance (Trainee session attendance records)
-- 3. lab_payments (Dental lab invoice payments)

DO $$
BEGIN
  -- Add payments to publication if not already present
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables 
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'payments'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.payments;
  END IF;

  -- Add attendance to publication if not already present
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables 
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'attendance'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.attendance;
  END IF;

  -- Add lab_payments to publication if not already present
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables 
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'lab_payments'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.lab_payments;
  END IF;
END $$;
