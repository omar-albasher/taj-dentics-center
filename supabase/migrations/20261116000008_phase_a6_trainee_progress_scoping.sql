-- ============================================================================
-- Migration: 20261116000008_phase_a6_trainee_progress_scoping.sql
-- Phase A6 residual: scope trainee_academic_progress rows to staff or owner
--
-- The view is NOT security_invoker, so it executes as its owner (postgres)
-- and bypasses table RLS. With SELECT granted to authenticated (baseline:9296)
-- and no auth filter, any signed-in user could read every trainee's name and
-- attendance through PostgREST with an arbitrary filter.
--
-- Column list and order are preserved exactly (baseline:5808-5828) so
-- CREATE OR REPLACE keeps existing PostgREST clients working.
-- ============================================================================

BEGIN;

CREATE OR REPLACE VIEW public.trainee_academic_progress AS
 SELECT e.id AS enrollment_id,
    e.trainee_id,
    u.full_name AS trainee_name,
    co.name AS course_name,
    co.total_sessions,
    count(a.id) AS sessions_attended,
    GREATEST((0)::bigint, (co.total_sessions - count(a.id))) AS sessions_remaining,
    LEAST((100)::numeric, round((((count(a.id))::numeric * 100.0) / (NULLIF(co.total_sessions, 0))::numeric))) AS attendance_percentage,
    count(a.id) FILTER (WHERE (s.is_extra IS NOT TRUE)) AS base_sessions_attended,
    count(a.id) FILTER (WHERE (s.is_extra IS TRUE)) AS extra_sessions_attended,
    count(DISTINCT s.id) FILTER (WHERE (s.is_extra IS TRUE)) AS extra_sessions_count,
    co.id AS course_id
   FROM ((((((public.enrollments e
     JOIN public.trainees t ON ((t.id = e.trainee_id)))
     JOIN public.users u ON ((u.id = t.user_id)))
     JOIN public.cohorts ch ON ((ch.id = e.cohort_id)))
     JOIN public.courses co ON ((co.id = ch.course_id)))
     LEFT JOIN public.sessions s ON ((s.cohort_id = ch.id)))
     LEFT JOIN public.attendance a ON (((a.session_id = s.id) AND (a.trainee_id = e.trainee_id))))
  WHERE (public.c1_is_staff()
      OR t.user_id = auth.uid()
      OR auth.role() IS NULL
      OR auth.role() = 'service_role')
  GROUP BY e.id, e.trainee_id, u.full_name, co.id, co.name, co.total_sessions;

-- Read-only view for API roles; anon and PUBLIC lose every privilege.
REVOKE ALL ON public.trainee_academic_progress FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.trainee_academic_progress TO authenticated, service_role;

COMMIT;
