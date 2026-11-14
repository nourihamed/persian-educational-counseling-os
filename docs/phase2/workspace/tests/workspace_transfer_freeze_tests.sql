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
 $q$INSERT INTO exams(exam_id,student_id,title,exam_at,scoring_policy_snapshot) VALUES (gen_random_uuid(),'e9000000-0000-0000-0000-000000000001','Blocked exam',now(),'{}'::jsonb)$q$,'23514','frozen for transfer case');
RESET SESSION AUTHORIZATION;
-- The barrier is a row trigger, so it binds the TABLE OWNER too, not just the least-privileged roles.
-- (The runtime has no direct UPDATE on enrollments or students by design: those go through commands.)
SELECT fz_err('FRZ-16 the table owner cannot update a frozen student''s enrollment',
 $q$UPDATE enrollments SET state='suspended' WHERE enrollment_id='a9100000-0000-0000-0000-000000000001'$q$,'23514','frozen for transfer case');
SELECT fz_err('FRZ-17 the table owner cannot update a frozen student''s own row',
 $q$UPDATE students SET display_name='Renamed while frozen' WHERE student_id='e9000000-0000-0000-0000-000000000001'$q$,'23514','frozen for transfer case');
SELECT fz_err('FRZ-18 the table owner cannot delete a frozen student''s rows',
 $q$DELETE FROM counselor_assignments WHERE enrollment_id='a9100000-0000-0000-0000-000000000001'$q$,'23514','frozen for transfer case');
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
