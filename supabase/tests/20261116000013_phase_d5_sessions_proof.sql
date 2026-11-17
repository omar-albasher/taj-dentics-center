-- ============================================================================
-- Acceptance Suite: 20261116000013_phase_d5_sessions_proof.sql
-- Description: Independent verification of the sessions hardening package
--              (20261116000012_phase_d5_sessions_hardening.sql)
--
-- Safety: Fully transactional. Enclosed in BEGIN ... ROLLBACK.
-- ============================================================================

BEGIN;

CREATE FUNCTION pg_temp.run_d5_sessions_proof()
RETURNS TABLE (line_no integer, message text)
LANGUAGE plpgsql
AS $proof$
DECLARE
  v_msgs text[] := '{}';
  v_suffix text := substr(gen_random_uuid()::text, 1, 6);
  v_admin uuid;
  v_reception uuid;
  v_trainee uuid;
  v_course uuid;
  v_cohort uuid;
  v_cohort_shift uuid;
  v_missed_labels int;
  v_sess_extra uuid;
  v_sess_regular uuid;
  v_t1 uuid;
  v_t2 uuid;
  v_t3 uuid;
  v_res json;
  v_json jsonb;
  v_qr_before uuid;
  v_qr_after uuid;
  v_status public.session_status;
  v_closed_at timestamptz;
  v_title text;
  v_description text;
  v_is_extra boolean;
  v_duration int;
  v_count int;
  v_starts_at date;
  v_rejected boolean;
  v_denied boolean;
BEGIN
  RAISE NOTICE '=== Starting D5 Sessions Hardening Acceptance Tests ===';
  v_msgs := array_append(v_msgs, '=== Starting D5 Sessions Hardening Acceptance Tests ===');

  -- --------------------------------------------------------------------------
  -- Test 1: Static contract (enum, functions, search_path, grants)
  -- --------------------------------------------------------------------------
  SELECT count(*) INTO v_missed_labels
  FROM pg_enum e
  JOIN pg_type t ON t.oid = e.enumtypid
  WHERE t.typname = 'session_status' AND e.enumlabel = 'missed';
  ASSERT v_missed_labels = 1, 'session_status is missing the ''missed'' label';

  -- Casting proves the label is usable, not just present in pg_enum
  PERFORM 'missed'::public.session_status;

  ASSERT to_regprocedure('public.create_session(uuid,integer,timestamptz,integer,boolean,text,text)') IS NOT NULL,
    'public.create_session(...) is missing';
  ASSERT to_regprocedure('public.open_session(uuid)') IS NOT NULL,
    'public.open_session(uuid) is missing';
  ASSERT to_regprocedure('public.close_session(uuid)') IS NOT NULL,
    'public.close_session(uuid) is missing';
  ASSERT to_regprocedure('public.shift_cohort_sessions(uuid,date)') IS NOT NULL,
    'public.shift_cohort_sessions(uuid,date) is missing';

  ASSERT (SELECT prosecdef FROM pg_proc WHERE oid =
          'public.create_session(uuid,integer,timestamptz,integer,boolean,text,text)'::regprocedure),
    'create_session must be SECURITY DEFINER';
  ASSERT (SELECT prosecdef FROM pg_proc WHERE oid = 'public.open_session(uuid)'::regprocedure),
    'open_session must be SECURITY DEFINER';
  ASSERT (SELECT prosecdef FROM pg_proc WHERE oid = 'public.close_session(uuid)'::regprocedure),
    'close_session must be SECURITY DEFINER';
  ASSERT (SELECT prosecdef FROM pg_proc WHERE oid =
          'public.shift_cohort_sessions(uuid,date)'::regprocedure),
    'shift_cohort_sessions must be SECURITY DEFINER';

  ASSERT EXISTS (
    SELECT 1 FROM pg_proc p,
         unnest(p.proconfig) c
    WHERE p.oid = 'public.create_session(uuid,integer,timestamptz,integer,boolean,text,text)'::regprocedure
      AND c LIKE '%pg_temp%'
  ), 'create_session search_path must include pg_temp';
  ASSERT EXISTS (
    SELECT 1 FROM pg_proc p,
         unnest(p.proconfig) c
    WHERE p.oid = 'public.open_session(uuid)'::regprocedure
      AND c LIKE '%pg_temp%'
  ), 'open_session search_path must include pg_temp';
  ASSERT EXISTS (
    SELECT 1 FROM pg_proc p,
         unnest(p.proconfig) c
    WHERE p.oid = 'public.close_session(uuid)'::regprocedure
      AND c LIKE '%pg_temp%'
  ), 'close_session search_path must include pg_temp';
  ASSERT EXISTS (
    SELECT 1 FROM pg_proc p,
         unnest(p.proconfig) c
    WHERE p.oid = 'public.shift_cohort_sessions(uuid,date)'::regprocedure
      AND c LIKE '%pg_temp%'
  ), 'shift_cohort_sessions search_path must include pg_temp';

  ASSERT has_function_privilege('anon',
      'public.create_session(uuid,integer,timestamptz,integer,boolean,text,text)', 'EXECUTE') = false
    AND has_function_privilege('anon', 'public.open_session(uuid)', 'EXECUTE') = false
    AND has_function_privilege('anon', 'public.close_session(uuid)', 'EXECUTE') = false
    AND has_function_privilege('anon', 'public.shift_cohort_sessions(uuid,date)', 'EXECUTE') = false,
    'SECURITY LEAK: anon can execute sessions RPCs';
  ASSERT has_function_privilege('authenticated',
      'public.create_session(uuid,integer,timestamptz,integer,boolean,text,text)', 'EXECUTE') = true
    AND has_function_privilege('authenticated', 'public.open_session(uuid)', 'EXECUTE') = true
    AND has_function_privilege('authenticated', 'public.close_session(uuid)', 'EXECUTE') = true
    AND has_function_privilege('authenticated', 'public.shift_cohort_sessions(uuid,date)', 'EXECUTE') = true,
    'REGRESSION: authenticated lost EXECUTE on sessions RPCs';

  RAISE NOTICE 'Test 1 Passed: missed label usable; 4 RPCs SECURITY DEFINER with pg_temp; anon denied, authenticated allowed.';
  v_msgs := array_append(v_msgs, 'Test 1 Passed: missed label usable; 4 RPCs SECURITY DEFINER with pg_temp; anon denied, authenticated allowed.');

  -- --------------------------------------------------------------------------
  -- Setup fixtures
  -- --------------------------------------------------------------------------
  INSERT INTO public.users (full_name, email, phone, role, is_active)
  VALUES ('Sessions Admin', 'd5s_admin_' || v_suffix || '@example.com',
          '+96399' || (floor(random() * 8999999 + 1000000)::bigint)::text, 'admin', true)
  RETURNING id INTO v_admin;

  INSERT INTO public.users (full_name, email, phone, role, is_active)
  VALUES ('Sessions Reception', 'd5s_rec_' || v_suffix || '@example.com',
          '+96399' || (floor(random() * 8999999 + 1000000)::bigint)::text, 'reception', true)
  RETURNING id INTO v_reception;

  INSERT INTO public.users (full_name, email, phone, role, is_active)
  VALUES ('Sessions Trainee', 'd5s_trn_' || v_suffix || '@example.com',
          '+96399' || (floor(random() * 8999999 + 1000000)::bigint)::text, 'trainee', true)
  RETURNING id INTO v_trainee;

  INSERT INTO public.courses (name, total_sessions, price, is_active, created_by)
  VALUES ('D5 Sessions Course ' || v_suffix, 10, 500000, true, v_admin)
  RETURNING id INTO v_course;

  INSERT INTO public.cohorts (course_id, trainer_id, name, capacity, is_active, created_by)
  VALUES (v_course, v_admin, 'D5 Sessions Cohort ' || v_suffix, 30, true, v_admin)
  RETURNING id INTO v_cohort;

  -- Dedicated cohort for shift tests: Test 3 closes a session on v_cohort,
  -- which would otherwise freeze cohorts.starts_at before any shift runs.
  INSERT INTO public.cohorts (course_id, trainer_id, name, capacity, is_active, created_by)
  VALUES (v_course, v_admin, 'D5 Shift Cohort ' || v_suffix, 30, true, v_admin)
  RETURNING id INTO v_cohort_shift;

  -- --------------------------------------------------------------------------
  -- Test 2: Reception can create sessions atomically (regular + extra)
  -- --------------------------------------------------------------------------
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', v_reception, 'role', 'authenticated',
                      'user_metadata', json_build_object('role', 'reception'))::text, true);
  SET LOCAL ROLE authenticated;

  v_sess_extra := public.create_session(
    v_cohort, 9001,
    ((date '2027-06-01' + time '10:00') AT TIME ZONE 'Asia/Damascus'),
    90, true, '  جلسة تعويضية  ', '   '
  );
  ASSERT v_sess_extra IS NOT NULL, 'create_session did not return an id';

  SELECT status, is_extra, title, description, duration_minutes
    INTO v_status, v_is_extra, v_title, v_description, v_duration
  FROM public.sessions WHERE id = v_sess_extra;
  ASSERT v_status = 'scheduled', 'new session must start as scheduled';
  ASSERT v_is_extra = true, 'is_extra flag was not persisted';
  ASSERT v_title = 'جلسة تعويضية', 'title was not trimmed/persisted';
  ASSERT v_description IS NULL, 'blank description should be stored as NULL';
  ASSERT v_duration = 90, 'duration_minutes was not persisted';

  v_sess_regular := public.create_session(
    v_cohort, 9002,
    ((date '2027-06-02' + time '10:00') AT TIME ZONE 'Asia/Damascus'),
    120, false, NULL, NULL
  );
  ASSERT v_sess_regular IS NOT NULL, 'create_session failed for a regular session';

  v_rejected := false;
  BEGIN
    PERFORM public.create_session(v_cohort, 9003,
      ((date '2027-06-03' + time '10:00') AT TIME ZONE 'Asia/Damascus'), 5, false, NULL, NULL);
  EXCEPTION WHEN raise_exception THEN
    v_rejected := true;
  END;
  ASSERT v_rejected, 'create_session accepted an invalid duration';

  v_rejected := false;
  BEGIN
    PERFORM public.create_session(v_cohort, 0,
      ((date '2027-06-03' + time '10:00') AT TIME ZONE 'Asia/Damascus'), 120, false, NULL, NULL);
  EXCEPTION WHEN raise_exception THEN
    v_rejected := true;
  END;
  ASSERT v_rejected, 'create_session accepted session_number = 0';

  v_rejected := false;
  BEGIN
    PERFORM public.create_session(gen_random_uuid(), 9004,
      ((date '2027-06-03' + time '10:00') AT TIME ZONE 'Asia/Damascus'), 120, false, NULL, NULL);
  EXCEPTION WHEN raise_exception THEN
    v_rejected := true;
  END;
  ASSERT v_rejected, 'create_session accepted a nonexistent cohort';

  RAISE NOTICE 'Test 2 Passed: reception created regular/extra sessions atomically; invalid input and unknown cohort rejected.';
  v_msgs := array_append(v_msgs, 'Test 2 Passed: reception created regular/extra sessions atomically; invalid input and unknown cohort rejected.');

  -- --------------------------------------------------------------------------
  -- Test 3: close_session is atomic and status-guarded
  -- --------------------------------------------------------------------------
  v_rejected := false;
  BEGIN
    PERFORM public.close_session(v_sess_extra);
  EXCEPTION WHEN raise_exception THEN
    v_rejected := true;
  END;
  ASSERT v_rejected, 'close_session closed a session that was not open';

  v_json := public.open_session(v_sess_extra);
  ASSERT v_json->>'success' = 'true', 'open_session failed for reception';

  SELECT qr_token INTO v_qr_before FROM public.sessions WHERE id = v_sess_extra;
  ASSERT v_qr_before IS NOT NULL, 'open_session did not set a qr_token';

  v_json := public.close_session(v_sess_extra);
  ASSERT v_json->>'success' = 'true', 'close_session failed for reception';

  SELECT status, closed_at, qr_token INTO v_status, v_closed_at, v_qr_after
  FROM public.sessions WHERE id = v_sess_extra;
  ASSERT v_status = 'closed', 'session status was not set to closed';
  ASSERT v_closed_at IS NOT NULL, 'closed_at was not set';
  ASSERT v_qr_after = v_qr_before, 'qr_token must be preserved for the grace window';

  v_rejected := false;
  BEGIN
    PERFORM public.close_session(v_sess_extra);
  EXCEPTION WHEN raise_exception THEN
    v_rejected := true;
  END;
  ASSERT v_rejected, 'close_session accepted an already-closed session';

  RAISE NOTICE 'Test 3 Passed: close_session refuses non-open sessions and preserves qr_token.';
  v_msgs := array_append(v_msgs, 'Test 3 Passed: close_session refuses non-open sessions and preserves qr_token.');

  -- --------------------------------------------------------------------------
  -- Test 4: shift_cohort_sessions math (Damascus local dates, wall clock)
  -- --------------------------------------------------------------------------
  v_t1 := public.create_session(v_cohort_shift, 9101,
    ((date '2027-06-01' + time '09:00') AT TIME ZONE 'Asia/Damascus'), 120, false, NULL, NULL);
  v_t2 := public.create_session(v_cohort_shift, 9102,
    ((date '2027-06-03' + time '09:00') AT TIME ZONE 'Asia/Damascus'), 120, false, NULL, NULL);
  v_t3 := public.create_session(v_cohort_shift, 9103,
    ((date '2027-06-08' + time '09:00') AT TIME ZONE 'Asia/Damascus'), 120, false, NULL, NULL);

  v_res := public.shift_cohort_sessions(v_cohort_shift, date '2027-06-08');
  ASSERT v_res->>'success' = 'true', 'shift_cohort_sessions did not report success';
  ASSERT v_res->>'day_delta' = '7', format('expected day_delta 7, got %s', v_res->>'day_delta');
  ASSERT v_res->>'shifted_sessions_count' = '3',
    format('expected 3 shifted sessions, got %s', v_res->>'shifted_sessions_count');

  SELECT count(*) INTO v_count
  FROM public.sessions
  WHERE id IN (v_t1, v_t2, v_t3)
    AND (scheduled_at AT TIME ZONE 'Asia/Damascus')::time = time '09:00';
  ASSERT v_count = 3, 'shift changed the local wall-clock time of sessions';

  SELECT count(*) INTO v_count
  FROM public.sessions
  WHERE id IN (v_t1, v_t2, v_t3)
    AND (scheduled_at AT TIME ZONE 'Asia/Damascus')::date IN
        (date '2027-06-08', date '2027-06-10', date '2027-06-15');
  ASSERT v_count = 3, 'shifted local dates are wrong';

  SELECT starts_at INTO v_starts_at FROM public.cohorts WHERE id = v_cohort_shift;
  ASSERT v_starts_at = date '2027-06-08', 'cohorts.starts_at was not updated';

  RAISE NOTICE 'Test 4 Passed: shift uses scheduled_at, keeps 09:00 wall clock, and updates cohorts.starts_at.';
  v_msgs := array_append(v_msgs, 'Test 4 Passed: shift uses scheduled_at, keeps 09:00 wall clock, and updates cohorts.starts_at.');

  -- --------------------------------------------------------------------------
  -- Test 5: executed sessions guard and start-date freeze
  -- --------------------------------------------------------------------------
  v_json := public.open_session(v_t1);
  ASSERT v_json->>'success' = 'true', 'open_session failed before shift guard test';

  -- After Test 4 the remaining scheduled dates are 06-10 and 06-15; 06-11 is
  -- one day after the first remaining session and after the executed 06-08.
  v_res := public.shift_cohort_sessions(v_cohort_shift, date '2027-06-11');
  ASSERT v_res->>'day_delta' = '1', 'shift after an executed session must shift only the remainder';
  ASSERT v_res->>'shifted_sessions_count' = '2',
    format('expected 2 remaining sessions, got %s', v_res->>'shifted_sessions_count');

  SELECT starts_at INTO v_starts_at FROM public.cohorts WHERE id = v_cohort_shift;
  ASSERT v_starts_at = date '2027-06-08',
    'cohorts.starts_at must stay frozen once a session has executed';

  v_rejected := false;
  BEGIN
    PERFORM public.shift_cohort_sessions(v_cohort_shift, date '2027-06-08');
  EXCEPTION WHEN raise_exception THEN
    v_rejected := true;
  END;
  ASSERT v_rejected, 'shift accepted a start date not after the last executed session';

  RAISE NOTICE 'Test 5 Passed: executed-session guard works and starts_at stays frozen.';
  v_msgs := array_append(v_msgs, 'Test 5 Passed: executed-session guard works and starts_at stays frozen.');

  -- --------------------------------------------------------------------------
  -- Test 6: trainee and anon are denied
  -- --------------------------------------------------------------------------
  RESET ROLE;
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', v_trainee, 'role', 'authenticated',
                      'user_metadata', json_build_object('role', 'trainee'))::text, true);
  SET LOCAL ROLE authenticated;

  v_rejected := false;
  BEGIN
    PERFORM public.create_session(v_cohort, 9901,
      ((date '2027-07-01' + time '10:00') AT TIME ZONE 'Asia/Damascus'), 120, false, NULL, NULL);
  EXCEPTION WHEN raise_exception THEN
    v_rejected := true;
  END;
  ASSERT v_rejected, 'SECURITY LEAK: trainee created a session';

  RESET ROLE;
  PERFORM set_config('request.jwt.claims', '', true);
  SET LOCAL ROLE anon;

  v_denied := false;
  BEGIN
    PERFORM public.create_session(v_cohort, 9902,
      ((date '2027-07-02' + time '10:00') AT TIME ZONE 'Asia/Damascus'), 120, false, NULL, NULL);
  EXCEPTION WHEN insufficient_privilege THEN
    v_denied := true;
  END;
  ASSERT v_denied, 'SECURITY LEAK: anon executed create_session';

  RESET ROLE;
  RAISE NOTICE 'Test 6 Passed: trainees are rejected by the role guard and anon is denied at the grant level.';
  v_msgs := array_append(v_msgs, 'Test 6 Passed: trainees are rejected by the role guard and anon is denied at the grant level.');

  RAISE NOTICE '=== ALL D5 SESSIONS HARDENING ACCEPTANCE TESTS PASSED SUCCESSFULLY ===';
  v_msgs := array_append(v_msgs, '=== ALL D5 SESSIONS HARDENING ACCEPTANCE TESTS PASSED SUCCESSFULLY ===');

  RETURN QUERY
  SELECT i::integer, v_msgs[i]
  FROM generate_subscripts(v_msgs, 1) AS i;
END;
$proof$;

SELECT * FROM pg_temp.run_d5_sessions_proof();

ROLLBACK;
