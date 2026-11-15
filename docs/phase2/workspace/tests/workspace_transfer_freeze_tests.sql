-- Batch 1 — source transfer freeze and DATABASE write barrier (Saga contract section 3).
-- Synthetic only (D-014). Run on a FRESH DB after workspace_schema_draft.sql,
-- workspace_activation_transactions.sql, workspace_governance_events_draft.sql,
-- workspace_archive_transactions.sql, workspace_inbox_projection.sql, workspace_transfer_freeze.sql and
-- workspace_roles_setup_draft.sql (-v workspace_key).
--
-- What these tests prove: that this DATABASE refuses student writes while a transfer freeze is live, that
-- the refusal binds the runtime role and the SECURITY DEFINER commands alike, that the freeze is
-- idempotent and token-bound, that unfreeze is a pre-switch-only path, and that the fence is permanent
-- after the switch.
-- What they do NOT prove: that an API, worker, importer, exporter or file surface is frozen. Those
-- surfaces do not exist in this repository, so freezing them is not implemented and is not claimed.
\set ON_ERROR_STOP on
SET app.workspace_key = :'workspace_key';
SELECT 'ws_'||current_setting('app.workspace_key')||'_runtime'      AS runtime_role \gset
SELECT 'ws_'||current_setting('app.workspace_key')||'_worker'       AS worker_role  \gset
SELECT 'ws_'||current_setting('app.workspace_key')||'_transfer_ctl' AS ctl_role     \gset
SELECT 'ws_'||current_setting('app.workspace_key')||'_synth_exec'   AS synth_role   \gset
SELECT 'ws_'||current_setting('app.workspace_key')||'_synth_inbox'  AS inbox_role   \gset
CREATE OR REPLACE FUNCTION fz_err(label text, stmt text, want text, want_msg text DEFAULT '')
RETURNS void LANGUAGE plpgsql AS $t$
BEGIN
  BEGIN
    EXECUTE stmt;
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE<>want THEN RAISE EXCEPTION 'FAIL %: got % (%), expected %',label,SQLSTATE,SQLERRM,want; END IF;
    IF want_msg<>'' AND position(want_msg IN SQLERRM)=0 THEN RAISE EXCEPTION 'FAIL %: wrong reason: %',label,SQLERRM; END IF;
    RAISE NOTICE 'PASS % (SQLSTATE %, reason verified)',label,SQLSTATE;
    RETURN;
  END;
  RAISE EXCEPTION 'FAIL %: statement unexpectedly succeeded',label;
END; $t$;
CREATE OR REPLACE FUNCTION fz_ok(label text, stmt text) RETURNS void LANGUAGE plpgsql AS $t$
BEGIN EXECUTE stmt; RAISE NOTICE 'PASS % (accepted)',label; END; $t$;

INSERT INTO workspace_profile(singleton,workspace_id,workspace_type) VALUES(true,'a9000000-0000-0000-0000-000000000001','organization');
INSERT INTO workspace_memberships(membership_id,platform_user_id,status) VALUES
 ('b9000000-0000-0000-0000-000000000001','c9000000-0000-0000-0000-000000000001','active');
INSERT INTO membership_roles(membership_id,role_key) VALUES ('b9000000-0000-0000-0000-000000000001','counselor');
INSERT INTO students(student_id,platform_student_id,display_name,grade_key,lifecycle_state) VALUES
 ('e9000000-0000-0000-0000-000000000001','f9000000-0000-0000-0000-000000000001','Freeze Subject','grade_10','active'),
 ('e9000000-0000-0000-0000-000000000002','f9000000-0000-0000-0000-000000000002','Untouched Peer','grade_10','active');
INSERT INTO enrollments(enrollment_id,student_id,ownership_generation,state) VALUES
 ('a9100000-0000-0000-0000-000000000001','e9000000-0000-0000-0000-000000000001',1,'requested'),
 ('a9100000-0000-0000-0000-000000000002','e9000000-0000-0000-0000-000000000002',1,'requested');
INSERT INTO counselor_assignments(assignment_id,enrollment_id,counselor_membership_id,is_responsible,state,accepted_at)
SELECT gen_random_uuid(),enrollment_id,'b9000000-0000-0000-0000-000000000001',true,'active',now() FROM enrollments;
-- Fixtures for the indirect-path behavioural tests FRZ-18b/18c. They must exist BEFORE any freeze,
-- because student_plans and student_guardian_links both carry student_id and are themselves barred once
-- the student is frozen. A guardian link event accompanies the link, as WS-DOM-03 requires.
INSERT INTO student_plans(plan_id, student_id)
VALUES ('a9b00000-0000-0000-0000-000000000001','e9000000-0000-0000-0000-000000000001');
-- The link and its event go in ONE transaction: the WS-DOM-03 guard is a deferred constraint trigger
-- that checks at COMMIT, and psql autocommits each statement separately.
BEGIN;
INSERT INTO student_guardian_links(link_id,student_id,guardian_platform_user_id,relationship_type,
                                   verification_state,legal_authority_ref,verified_at)
VALUES ('a9b00000-0000-0000-0000-000000000002','e9000000-0000-0000-0000-000000000001',gen_random_uuid(),
        'parent','verified','synthetic-authority-frz',clock_timestamp());
INSERT INTO guardian_link_events(event_id,link_id,event_type,actor_ref,authn_event_ref,policy_version,effective_at)
VALUES (gen_random_uuid(),'a9b00000-0000-0000-0000-000000000002','link_created','actor-frz','authn-frz',
        'policy-frz',clock_timestamp());
-- A link created already 'verified' needs its verified event too, not only link_created.
INSERT INTO guardian_link_events(event_id,link_id,event_type,actor_ref,authn_event_ref,evidence_ref,
                                 policy_version,effective_at)
VALUES (gen_random_uuid(),'a9b00000-0000-0000-0000-000000000002','verified','actor-frz','authn-frz',
        'evidence-frz','policy-frz',clock_timestamp());
COMMIT;
INSERT INTO credit_wallets(wallet_id,unit_code) VALUES('c9100000-0000-0000-0000-000000000001','CRD');
INSERT INTO credit_transactions(transaction_id,wallet_id,transaction_kind,amount,idempotency_key,reason)
VALUES(gen_random_uuid(),'c9100000-0000-0000-0000-000000000001','grant',50,'freeze-fixture-grant','synthetic opening credit');
INSERT INTO workspace_capacity_counters(dimension_key,current_value,max_value) VALUES('active_students',0,5);
SET SESSION AUTHORIZATION :"synth_role";
SELECT activate_student_enrollment_synthetic('fz-act-1','a9100000-0000-0000-0000-000000000001','c9100000-0000-0000-0000-000000000001',1,5,'b9000000-0000-0000-0000-000000000001','2099-01-01 00:00:00+00'::timestamptz);
SELECT activate_student_enrollment_synthetic('fz-act-2','a9100000-0000-0000-0000-000000000002','c9100000-0000-0000-0000-000000000001',1,5,'b9000000-0000-0000-0000-000000000001','2099-01-01 00:00:00+00'::timestamptz);
RESET SESSION AUTHORIZATION;

-- ============================ the barrier covers every student-scoped table ============================
DO $t$ DECLARE n integer; missing text; BEGIN
  SELECT count(*), string_agg(table_name,', ') INTO n, missing
    FROM student_write_barrier_coverage WHERE NOT has_barrier;
  IF n<>0 THEN RAISE EXCEPTION 'FAIL FRZ-01: % student-scoped table(s) have no write barrier: %',n,missing; END IF;
  SELECT count(*) INTO n FROM student_write_barrier_coverage;
  IF n < 15 THEN RAISE EXCEPTION 'FAIL FRZ-01: only % guarded tables, the catalog scan looks wrong',n; END IF;
  RAISE NOTICE 'PASS FRZ-01 all % student-scoped tables carry the write barrier',n;
END $t$;

-- ===================================================================================================
-- FRZ-01b  INDIRECT reachability audit. FRZ-01 above asks "does every table in the coverage view have a
--          trigger?", which cannot catch a per-student table that is MISSING FROM THE VIEW. That is how
--          this project was caught twice: counselor_assignments and friends reach a student through an
--          enrollment (Batch 1), and student_plan_versions and test_responses reach one through
--          student_plans and test_attempts (Batch 5) — none of them carries a student_id or
--          enrollment_id column, so a column scan cannot see them.
--
--          This test asks the opposite question from the catalog: which tables have a foreign key into a
--          per-student table and yet carry no barrier? Anything new fails BY NAME. The exclusion list is
--          for genuinely SHARED tables, and each entry states why sharing makes a barrier wrong there:
--          freezing one student must not block writes that other students depend on.
-- ===================================================================================================
DO $t$
DECLARE
  v_unguarded text;
  v_n integer;
  -- Reviewed exemptions. Adding a name here is a review decision, and each states its reason. There are
  -- only two valid reasons: the table is SHARED between students, so barring it would let one frozen
  -- student block writes other students depend on; or it must be writable WHILE a student is frozen,
  -- because it is part of the freeze/cutover machinery itself.
  v_shared text[] := ARRAY[
    -- shared between students
    'class_sessions',                     -- belongs to a class shared by many students
    'test_definitions',                   -- a definition is shared; attempts are per-student
    'test_definition_version_questions',  -- membership of a shared definition version
    'exam_definition_version_subjects',   -- blueprint of a shared exam definition
    'topics',                             -- curriculum, shared
    'subtopics',                          -- curriculum, shared
    'chapters',                           -- curriculum, shared
    -- already covered by FRZ-01 through a direct key column
    'class_participants',
    -- must be writable WHILE the student is frozen
    'student_transfer_freezes',           -- the freeze record itself
    'student_write_barrier_bypass',       -- the transaction-scoped exemption
    'workspace_inbox_events'              -- Saga transport: the inbox projection APPLIES the fence, so
                                          -- barring it would make the fence unable to land. It is not
                                          -- student educational data, and only the inbox roles can write it.
  ];
BEGIN
  SELECT count(*), string_agg(t.relname || ' -> ' || t.parent, ', ' ORDER BY t.relname)
    INTO v_n, v_unguarded
    FROM (
      SELECT DISTINCT c.relname, k.confrelid::regclass::text AS parent
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        JOIN pg_constraint k ON k.conrelid = c.oid AND k.contype = 'f'
       WHERE n.nspname = 'public' AND c.relkind = 'r'
         -- a parent that is itself per-student
         AND k.confrelid::regclass::text IN (
               SELECT table_name FROM public.student_scoped_tables
               UNION ALL SELECT 'students')
         AND c.relname NOT IN (SELECT table_name FROM public.student_write_barrier_coverage)
         AND NOT (c.relname = ANY (v_shared))
    ) t;

  IF v_n > 0 THEN
    RAISE EXCEPTION 'FAIL FRZ-01b % table(s) reach a student indirectly but carry NO write barrier: %. '
                    'A frozen student''s rows in these tables could still be written through cutover. '
                    'Give student_write_barrier() a resolution path for each (see the plan/attempt arms) '
                    'and list it in student_scoped_tables, or — if the table is genuinely SHARED between '
                    'students — add it to v_shared in this test with the reason.', v_n, v_unguarded;
  END IF;
  RAISE NOTICE 'PASS FRZ-01b no per-student table reaches a student indirectly without a barrier '
               '(% reviewed shared exclusion(s))', coalesce(array_length(v_shared,1),0);
END $t$;

-- FRZ-01c  The two tables found in Batch 5 are specifically guarded, so an over-broad edit to the
--          exclusion list above cannot quietly drop them again.
DO $t$
DECLARE r record; v_missing text[] := ARRAY[]::text[];
BEGIN
  FOR r IN SELECT * FROM (VALUES
      ('student_plan_versions','plan_id','plan'),
      ('test_responses','attempt_id','attempt'),
      ('guardian_permissions','guardian_link_id','guardian_link'),
      ('guardian_link_events','link_id','guardian_link'),
      ('guardian_permission_events','permission_id','guardian_permission')
    ) AS t(tbl, col, kind)
  LOOP
    IF NOT EXISTS (SELECT 1 FROM public.student_write_barrier_coverage
                    WHERE table_name = r.tbl AND key_column = r.col) THEN
      v_missing := v_missing || (r.tbl || ' (' || r.col || '/' || r.kind || ')');
    END IF;
  END LOOP;
  IF array_length(v_missing,1) IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL FRZ-01c these lost their barrier: %', array_to_string(v_missing, ', ');
  END IF;
  RAISE NOTICE 'PASS FRZ-01c the five indirectly-owned tables found in Batch 5 are guarded through their owners';
END $t$;

-- ============================ only the controller may freeze ============================
SET SESSION AUTHORIZATION :"runtime_role";
SELECT fz_err('FRZ-02 the Workspace runtime cannot freeze a student',
 $q$SELECT freeze_student_for_transfer(gen_random_uuid(),'tok-runtime','e9000000-0000-0000-0000-000000000001','d9000000-0000-0000-0000-000000000001',1,'ctl/0.1',0,now())$q$,'42501');
SELECT fz_err('FRZ-03 the Workspace runtime cannot write a freeze record directly',
 $q$INSERT INTO student_transfer_freezes(freeze_id,student_id,case_id,freeze_token,source_generation,state,controller_version,requested_at,barrier_completed_at,barrier_watermark_txid,outstanding_work_at_barrier) VALUES (gen_random_uuid(),'e9000000-0000-0000-0000-000000000001','d9000000-0000-0000-0000-000000000001','tok-forged',1,'frozen','forged',now(),now(),1,0)$q$,'42501');
SELECT fz_err('FRZ-04 the Workspace runtime cannot take a barrier exemption',
 $q$INSERT INTO student_write_barrier_bypass(student_id,txid,reason) VALUES ('e9000000-0000-0000-0000-000000000001',txid_current(),'transfer_fence_projection')$q$,'42501');
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION :"worker_role";
SELECT fz_err('FRZ-05 the background worker cannot freeze a student',
 $q$SELECT freeze_student_for_transfer(gen_random_uuid(),'tok-worker','e9000000-0000-0000-0000-000000000001','d9000000-0000-0000-0000-000000000001',1,'ctl/0.1',0,now())$q$,'42501');
RESET SESSION AUTHORIZATION;

-- ============================ the freeze itself ============================
SET SESSION AUTHORIZATION :"ctl_role";
SELECT fz_err('FRZ-06 a freeze on a stale generation is refused (fail closed)',
 $q$SELECT freeze_student_for_transfer(gen_random_uuid(),'tok-stale','e9000000-0000-0000-0000-000000000001','d9000000-0000-0000-0000-000000000001',7,'ctl/0.1',0,now())$q$,'23514','stale view');
SELECT fz_err('FRZ-07 a final barrier with outstanding work is refused',
 $q$SELECT freeze_student_for_transfer(gen_random_uuid(),'tok-busy','e9000000-0000-0000-0000-000000000001','d9000000-0000-0000-0000-000000000001',1,'ctl/0.1',3,now())$q$,'23514','zero outstanding work');
SELECT fz_err('FRZ-08 a freeze for a student this Workspace does not project is refused',
 $q$SELECT freeze_student_for_transfer(gen_random_uuid(),'tok-absent','e9000000-0000-0000-0000-0000000000ff','d9000000-0000-0000-0000-000000000001',1,'ctl/0.1',0,now())$q$,'23503');
DO $t$ DECLARE r text; BEGIN
  r := freeze_student_for_transfer('aa000000-0000-0000-0000-000000000001','tok-case-1','e9000000-0000-0000-0000-000000000001','d9000000-0000-0000-0000-000000000001',1,'ctl/0.1',0,now());
  IF r<>'frozen' THEN RAISE EXCEPTION 'FAIL FRZ-09: %',r; END IF;
  RAISE NOTICE 'PASS FRZ-09 the controller froze the student at the projected generation';
  r := freeze_student_for_transfer('aa000000-0000-0000-0000-000000000001','tok-case-1','e9000000-0000-0000-0000-000000000001','d9000000-0000-0000-0000-000000000001',1,'ctl/0.1',0,now());
  IF r<>'replayed' THEN RAISE EXCEPTION 'FAIL FRZ-10: %',r; END IF;
  RAISE NOTICE 'PASS FRZ-10 replaying the same freeze token is idempotent';
END $t$;
SELECT fz_err('FRZ-11 a DIFFERENT token for the same case, student and generation is refused',
 $q$SELECT freeze_student_for_transfer(gen_random_uuid(),'tok-case-1-again','e9000000-0000-0000-0000-000000000001','d9000000-0000-0000-0000-000000000001',1,'ctl/0.1',0,now())$q$,'23505','different token');
SELECT fz_err('FRZ-12 a second live freeze on the same student is refused',
 $q$SELECT freeze_student_for_transfer(gen_random_uuid(),'tok-case-2','e9000000-0000-0000-0000-000000000001','d9000000-0000-0000-0000-000000000002',1,'ctl/0.1',0,now())$q$,'23505');
RESET SESSION AUTHORIZATION;
DO $t$ DECLARE f student_transfer_freezes%ROWTYPE; BEGIN
  SELECT * INTO f FROM student_transfer_freezes WHERE freeze_token='tok-case-1';
  IF f.state<>'frozen' OR f.barrier_watermark_txid IS NULL OR f.barrier_completed_at IS NULL
     OR f.outstanding_work_at_barrier<>0 THEN RAISE EXCEPTION 'FAIL FRZ-13: %',row_to_json(f); END IF;
  IF (SELECT count(*) FROM audit_events WHERE event_type='transfer.source_freeze' AND correlation_id='tok-case-1')<>1 THEN
    RAISE EXCEPTION 'FAIL FRZ-13 the freeze was not audited';
  END IF;
  IF (SELECT metadata->>'signed_receipt' FROM audit_events WHERE correlation_id='tok-case-1')<>'false' THEN
    RAISE EXCEPTION 'FAIL FRZ-13 the audit record must state that the receipt is unsigned';
  END IF;
  RAISE NOTICE 'PASS FRZ-13 the freeze is durable, carries a barrier watermark, and is audited as an UNSIGNED receipt';
END $t$;

-- ============================ the write barrier actually refuses writes ============================
SET SESSION AUTHORIZATION :"runtime_role";
SELECT fz_err('FRZ-14 a frozen student cannot have a study session written',
 $q$INSERT INTO study_sessions(study_session_id,student_id,started_at,actual_minutes) VALUES (gen_random_uuid(),'e9000000-0000-0000-0000-000000000001',now(),30)$q$,'23514','frozen for transfer case');
SELECT fz_err('FRZ-15 a frozen student cannot have an exam written',
 $q$INSERT INTO exams(exam_id,student_id,title,exam_at,scoring_policy_snapshot) VALUES (gen_random_uuid(),'e9000000-0000-0000-0000-000000000001','Blocked exam',now(),'{"algorithm":"standard_negative","algorithm_version":1,"negative_marking":true}'::jsonb)$q$,'23514','frozen for transfer case');
RESET SESSION AUTHORIZATION;
-- The barrier is a row trigger, so it binds the TABLE OWNER too, not just the least-privileged roles.
-- (The runtime has no direct UPDATE on enrollments or students by design: those go through commands.)
SELECT fz_err('FRZ-16 the table owner cannot update a frozen student''s enrollment',
 $q$UPDATE enrollments SET state='suspended' WHERE enrollment_id='a9100000-0000-0000-0000-000000000001'$q$,'23514','frozen for transfer case');
SELECT fz_err('FRZ-17 the table owner cannot update a frozen student''s own row',
 $q$UPDATE students SET display_name='Renamed while frozen' WHERE student_id='e9000000-0000-0000-0000-000000000001'$q$,'23514','frozen for transfer case');
SELECT fz_err('FRZ-18 the table owner cannot delete a frozen student''s rows',
 $q$DELETE FROM counselor_assignments WHERE enrollment_id='a9100000-0000-0000-0000-000000000001'$q$,'23514','frozen for transfer case');

-- FRZ-18b/18c  THE INDIRECT PATHS, TESTED BEHAVIOURALLY. FRZ-01b/01c prove the triggers are installed;
--              these prove the resolution actually reaches the student. A two-hop lookup that silently
--              returned NULL would leave the barrier open while still looking "covered", because
--              assert_student_not_frozen() returns early for a NULL student.
SELECT fz_err('FRZ-18b a frozen student''s plan version is refused (resolved plan_id -> student_plans)',
 $q$INSERT INTO student_plan_versions(plan_version_id,plan_id,version_no,input_snapshot,rule_version,plan_content,status)
    VALUES (gen_random_uuid(),'a9b00000-0000-0000-0000-000000000001',1,'{}'::jsonb,'r1','{}'::jsonb,'draft')$q$,
 '23514','frozen for transfer case');

SELECT fz_err('FRZ-18c a frozen student''s guardian permission is refused (resolved through the link)',
 $q$INSERT INTO guardian_permissions(permission_id,guardian_link_id,scope_key,authority_ref,valid_from)
    VALUES (gen_random_uuid(),'a9b00000-0000-0000-0000-000000000002','progress_summary',
            'synthetic-authority-frz',clock_timestamp())$q$,
 '23514','frozen for transfer case');
SET SESSION AUTHORIZATION :"runtime_role";
-- The barrier binds the SECURITY DEFINER commands too, not only direct table access.
SELECT fz_err('FRZ-19 the archive command is refused for a frozen student',
 $q$SELECT archive_student_enrollment('fz-arc','a9100000-0000-0000-0000-000000000001',1,'b9000000-0000-0000-0000-000000000001','blocked by freeze')$q$,'23514','frozen for transfer case');
-- A different student is completely unaffected: the barrier is per student, not a global stop.
SELECT fz_ok('FRZ-20 an unfrozen student is unaffected',
 $q$INSERT INTO study_sessions(study_session_id,student_id,started_at,actual_minutes) VALUES ('ab000000-0000-0000-0000-000000000001','e9000000-0000-0000-0000-000000000002',now(),30)$q$);
DO $t$ DECLARE n integer; BEGIN
  SELECT count(*) INTO n FROM students WHERE student_id='e9000000-0000-0000-0000-000000000001';
  IF n<>1 THEN RAISE EXCEPTION 'FAIL FRZ-21'; END IF;
  SELECT count(*) INTO n FROM enrollments WHERE student_id='e9000000-0000-0000-0000-000000000001';
  IF n<>1 THEN RAISE EXCEPTION 'FAIL FRZ-21'; END IF;
  RAISE NOTICE 'PASS FRZ-21 reads of a frozen student still work: the barrier stops writes, not visibility';
END $t$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION :"synth_role";
SELECT fz_err('FRZ-22 activation of a frozen student''s enrollment is refused',
 $q$SELECT activate_student_enrollment_synthetic('fz-act-blocked','a9100000-0000-0000-0000-000000000001','c9100000-0000-0000-0000-000000000001',1,5,'b9000000-0000-0000-0000-000000000001','2099-01-01 00:00:00+00'::timestamptz)$q$,'23514');
RESET SESSION AUTHORIZATION;

-- ============================ unfreeze is a pre-switch abort path ============================
SET SESSION AUTHORIZATION :"ctl_role";
SELECT fz_err('FRZ-23 unfreeze with an unknown token is refused',
 $q$SELECT unfreeze_student_after_abort('tok-nonexistent','d9000000-0000-0000-0000-000000000001','abort')$q$,'P0002');
SELECT fz_err('FRZ-24 unfreeze bound to another case is refused',
 $q$SELECT unfreeze_student_after_abort('tok-case-1','d9000000-0000-0000-0000-0000000000ff','abort')$q$,'42501','another transfer case');
SELECT fz_err('FRZ-25 unfreeze without a reason code is refused',
 $q$SELECT unfreeze_student_after_abort('tok-case-1','d9000000-0000-0000-0000-000000000001','  ')$q$,'22023');
DO $t$ DECLARE r text; BEGIN
  r := unfreeze_student_after_abort('tok-case-1','d9000000-0000-0000-0000-000000000001','transfer_aborted_before_switch');
  IF r<>'unfrozen' THEN RAISE EXCEPTION 'FAIL FRZ-26: %',r; END IF;
  r := unfreeze_student_after_abort('tok-case-1','d9000000-0000-0000-0000-000000000001','transfer_aborted_before_switch');
  IF r<>'replayed' THEN RAISE EXCEPTION 'FAIL FRZ-27: %',r; END IF;
  RAISE NOTICE 'PASS FRZ-26/27 pre-switch unfreeze succeeds and replays idempotently';
END $t$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION :"runtime_role";
SELECT fz_ok('FRZ-28 writes resume after the abort',
 $q$INSERT INTO study_sessions(study_session_id,student_id,started_at,actual_minutes) VALUES ('ab000000-0000-0000-0000-000000000002','e9000000-0000-0000-0000-000000000001',now(),45)$q$);
RESET SESSION AUTHORIZATION;
SELECT fz_err('FRZ-29 an unfrozen freeze record cannot be reactivated',
 $q$UPDATE student_transfer_freezes SET state='frozen' WHERE freeze_token='tok-case-1'$q$,'23514','cannot be reactivated');
SELECT fz_err('FRZ-30 freeze identity and barrier evidence are immutable',
 $q$UPDATE student_transfer_freezes SET barrier_watermark_txid=1 WHERE freeze_token='tok-case-1'$q$,'23514','immutable');
SELECT fz_err('FRZ-31 a freeze record cannot be deleted',
 $q$DELETE FROM student_transfer_freezes WHERE freeze_token='tok-case-1'$q$,'23514','cannot be deleted');

-- ============================ after the switch the fence is permanent ============================
SET SESSION AUTHORIZATION :"ctl_role";
SELECT freeze_student_for_transfer('aa000000-0000-0000-0000-000000000002','tok-case-3','e9000000-0000-0000-0000-000000000001','d9000000-0000-0000-0000-000000000003',1,'ctl/0.1',0,now());
RESET SESSION AUTHORIZATION;
-- The source applies the ownership-switch event: it fences its own projection and closes the freeze.
SET SESSION AUTHORIZATION :"inbox_role";
DO $t$ DECLARE r text; p jsonb; BEGIN
  p := jsonb_build_object('student_id','f9000000-0000-0000-0000-000000000001','from_workspace_id','a9000000-0000-0000-0000-000000000001',
                          'to_workspace_id','a9000000-0000-0000-0000-000000000099','generation',2);
  r := apply_inbox_event_synthetic('ad000000-0000-0000-0000-000000000001',1,'ownership_switched',p,sha256(convert_to(p::text,'UTF8')),
       'f9000000-0000-0000-0000-000000000001','a9000000-0000-0000-0000-000000000001','a9000000-0000-0000-0000-000000000099',2,
       'ae000000-0000-0000-0000-000000000001');
  IF r<>'applied' THEN RAISE EXCEPTION 'FAIL FRZ-32: %',r; END IF;
  RAISE NOTICE 'PASS FRZ-32 the source applied the switch event while the student was frozen';
END $t$;
RESET SESSION AUTHORIZATION;
DO $t$ DECLARE f student_transfer_freezes%ROWTYPE; BEGIN
  SELECT * INTO f FROM student_transfer_freezes WHERE freeze_token='tok-case-3';
  IF f.state<>'fenced' OR f.fenced_at IS NULL OR f.fenced_generation<>2 THEN
    RAISE EXCEPTION 'FAIL FRZ-33: %',row_to_json(f);
  END IF;
  IF (SELECT state FROM enrollments WHERE enrollment_id='a9100000-0000-0000-0000-000000000001')<>'ended' THEN
    RAISE EXCEPTION 'FAIL FRZ-33 the source projection was not fenced';
  END IF;
  IF (SELECT count(*) FROM student_write_barrier_bypass)<>0 THEN
    RAISE EXCEPTION 'FAIL FRZ-33 the barrier exemption outlived its transaction';
  END IF;
  RAISE NOTICE 'PASS FRZ-33 the freeze became a permanent fence, the projection ended, and the exemption did not leak';
END $t$;
SET SESSION AUTHORIZATION :"ctl_role";
SELECT fz_err('FRZ-34 unfreeze after the ownership switch is prohibited',
 $q$SELECT unfreeze_student_after_abort('tok-case-3','d9000000-0000-0000-0000-000000000003','too late')$q$,'23514','prohibited after the switch');
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION :"runtime_role";
SELECT fz_err('FRZ-35 a fenced student can never be written again',
 $q$INSERT INTO study_sessions(study_session_id,student_id,started_at,actual_minutes) VALUES (gen_random_uuid(),'e9000000-0000-0000-0000-000000000001',now(),30)$q$,'23514','permanently fenced');
RESET SESSION AUTHORIZATION;
SELECT fz_err('FRZ-36 a fenced freeze record cannot be reopened even by the table owner',
 $q$UPDATE student_transfer_freezes SET state='unfrozen', unfrozen_at=now() WHERE freeze_token='tok-case-3'$q$,'23514','permanently fenced');
DO $t$ BEGIN
  IF (SELECT count(*) FROM student_transfer_freezes WHERE student_id='e9000000-0000-0000-0000-000000000001')<>2 THEN
    RAISE EXCEPTION 'FAIL FRZ-37';
  END IF;
  RAISE NOTICE 'PASS FRZ-37 the full freeze history is retained: one aborted freeze and one permanent fence';
END $t$;
SELECT 'TRANSFER FREEZE AND WRITE BARRIER TESTS COMPLETED (FRZ-01..FRZ-37)' AS result;
