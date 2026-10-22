-- ==============================================================================
-- Taj Dentics Training Center - Phase A4: Next Session View for Trainees
-- Migration: 20261022000001_phase_a4_trainee_next_session.sql
-- ==============================================================================

-- Create or update the trainee_next_sessions view.
-- Strictly filters sessions by the authenticated trainee's active enrollments.
-- Excludes past/completed sessions and includes currently open or upcoming scheduled sessions.
-- Provides fallback columns (course_name, cohort_name, is_attended).

DROP VIEW IF EXISTS public.trainee_next_sessions CASCADE;

CREATE VIEW public.trainee_next_sessions AS
SELECT
    s.id AS session_id,
    s.cohort_id,
    s.session_number,
    s.title,
    s.description,
    s.scheduled_at,
    s.duration_minutes,
    s.status,
    s.is_extra,
    c.name AS cohort_name,
    cr.id AS course_id,
    cr.name AS course_name,
    t.id AS trainee_id,
    t.user_id,
    (a.id IS NOT NULL) AS is_attended
FROM public.sessions s
JOIN public.cohorts c ON c.id = s.cohort_id
JOIN public.courses cr ON cr.id = c.course_id
JOIN public.enrollments e ON e.cohort_id = c.id
JOIN public.trainees t ON t.id = e.trainee_id
LEFT JOIN public.attendance a ON a.session_id = s.id AND a.trainee_id = t.id
WHERE s.status IN ('scheduled', 'open')
  AND (s.scheduled_at >= (now() - interval '4 hours') OR s.status = 'open')
  AND e.status = 'active'
  AND (
    t.user_id = auth.uid()
    OR auth.role() = 'service_role'
    OR (auth.jwt() ->> 'role') = 'service_role'
    OR current_user = 'postgres'
  );

-- Grant select permission to authenticated trainees
GRANT SELECT ON public.trainee_next_sessions TO authenticated;
