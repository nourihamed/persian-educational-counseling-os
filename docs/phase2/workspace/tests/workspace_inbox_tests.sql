-- Saga inbox: duplicate, out-of-order, stale and future events; atomic inbox + projection; generation
-- fencing of later local commands. Synthetic only (D-014).
-- Run on a FRESH DB after workspace_schema_draft.sql, workspace_activation_transactions.sql,
-- workspace_governance_events_draft.sql, workspace_archive_transactions.sql, workspace_inbox_projection.sql
-- and workspace_roles_setup_draft.sql (-v workspace_key). The command is called as the WORKER role.
--
-- NOT covered: real delivery, dispatcher crash, network partition, staging/import of a student who has not
-- been projected yet, and resolution of a quarantined event. Those are open or belong to later phases.
\set ON_ERROR_STOP on
SET app.workspace_key = :'workspace_key';
SELECT 'ws_'||current_setting('app.workspace_key')||'_runtime' AS runtime_role \gset
SELECT 'ws_'||current_setting('app.workspace_key')||'_worker'  AS worker_role \gset
SELECT 'ws_'||current_setting('app.workspace_key')||'_synth_exec' AS synth_role \gset
CREATE OR REPLACE FUNCTION ib_err(label text, stmt text, want text, want_msg text DEFAULT '')
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
-- Builds a well-formed envelope exactly as the Control Plane would, and applies it.
CREATE OR REPLACE FUNCTION ib_apply(p_event uuid, p_student uuid, p_src uuid, p_dst uuid, p_gen bigint,
                                    p_type text DEFAULT 'ownership_switched', p_schema integer DEFAULT 1)
RETURNS text LANGUAGE plpgsql AS $t$
DECLARE p jsonb;
BEGIN
  p := jsonb_build_object('student_id',p_student::text,'from_workspace_id',p_src::text,
                          'to_workspace_id',p_dst::text,'generation',p_gen);
  RETURN public.apply_inbox_event(p_event,p_schema,p_type,p,sha256(convert_to(p::text,'UTF8')),
                                  p_student,p_src,p_dst,p_gen,'c0000000-0000-0000-0000-000000000001');
END; $t$;

INSERT INTO workspace_profile(singleton,workspace_id,workspace_type) VALUES(true,'a1b00000-0000-0000-0000-000000000001','organization');
INSERT INTO workspace_memberships(membership_id,platform_user_id,status) VALUES
 ('b1b00000-0000-0000-0000-000000000001','c1b00000-0000-0000-0000-000000000001','active');
INSERT INTO membership_roles(membership_id,role_key) VALUES ('b1b00000-0000-0000-0000-000000000001','counselor');
INSERT INTO students(student_id,platform_student_id,display_name,grade_key,lifecycle_state) VALUES
 ('e1b00000-0000-0000-0000-000000000001','f1b00000-0000-0000-0000-000000000001','Inbox Student','grade_10','active');
INSERT INTO enrollments(enrollment_id,student_id,ownership_generation,state) VALUES
 ('a1c00000-0000-0000-0000-000000000001','e1b00000-0000-0000-0000-000000000001',1,'requested');
INSERT INTO counselor_assignments(assignment_id,enrollment_id,counselor_membership_id,is_responsible,state,accepted_at)
VALUES (gen_random_uuid(),'a1c00000-0000-0000-0000-000000000001','b1b00000-0000-0000-0000-000000000001',true,'active',now());
INSERT INTO credit_wallets(wallet_id,unit_code) VALUES('c1c00000-0000-0000-0000-000000000001','CRD');
INSERT INTO credit_transactions(transaction_id,wallet_id,transaction_kind,amount,idempotency_key,reason)
VALUES(gen_random_uuid(),'c1c00000-0000-0000-0000-000000000001','grant',50,'inbox-fixture-grant','synthetic opening credit');
INSERT INTO workspace_capacity_counters(dimension_key,current_value,max_value) VALUES('active_students',0,5);
SET SESSION AUTHORIZATION :"synth_role";
SELECT activate_student_enrollment_synthetic('ib-act','a1c00000-0000-0000-0000-000000000001','c1c00000-0000-0000-0000-000000000001',1,5,'b1b00000-0000-0000-0000-000000000001','2099-01-01 00:00:00+00'::timestamptz);
RESET SESSION AUTHORIZATION;

-- ============================ only the consumer identity may apply events ============================
SET SESSION AUTHORIZATION :"runtime_role";
SELECT ib_err('INB-01 the general runtime identity cannot apply an inbox event',
 $q$SELECT apply_inbox_event(gen_random_uuid(),1,'ownership_switched','{}'::jsonb,sha256(convert_to('{}','UTF8')),'f1b00000-0000-0000-0000-000000000001',NULL,NULL,2,gen_random_uuid())$q$,'42501');
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION :"worker_role";
SELECT ib_err('INB-02 the consumer identity may not write an inbox row directly',
 $q$INSERT INTO workspace_inbox_events(event_id,schema_version,event_type,payload,payload_hash,platform_student_id,ownership_generation,correlation_id,outcome) VALUES (gen_random_uuid(),1,'forged','{}'::jsonb,sha256(convert_to('{}','UTF8')),'f1b00000-0000-0000-0000-000000000001',9,gen_random_uuid(),'applied')$q$,'42501');
RESET SESSION AUTHORIZATION;

-- ============================ rejected envelopes ============================
SET SESSION AUTHORIZATION :"worker_role";
DO $t$ DECLARE r text; p jsonb; BEGIN
  p := jsonb_build_object('generation',2);
  r := apply_inbox_event('d1b00000-0000-0000-0000-00000000000a',1,'ownership_switched',p,sha256('a different payload'::bytea),
       'f1b00000-0000-0000-0000-000000000001','a1b00000-0000-0000-0000-000000000009','a1b00000-0000-0000-0000-000000000001',2,'c0000000-0000-0000-0000-000000000001');
  IF r<>'rejected_payload' THEN RAISE EXCEPTION 'FAIL INB-03: %',r; END IF;
  RAISE NOTICE 'PASS INB-03 an envelope whose hash does not describe its payload is rejected, not applied';
  r := ib_apply('d1b00000-0000-0000-0000-00000000000b','f1b00000-0000-0000-0000-000000000001','a1b00000-0000-0000-0000-000000000009','a1b00000-0000-0000-0000-000000000001',2,'ownership_switched',7);
  IF r<>'rejected_schema' THEN RAISE EXCEPTION 'FAIL INB-04: %',r; END IF;
  RAISE NOTICE 'PASS INB-04 an unsupported envelope schema version is rejected, not guessed at';
  r := ib_apply('d1b00000-0000-0000-0000-00000000000c','f1b00000-0000-0000-0000-000000000001','a1b00000-0000-0000-0000-000000000007','a1b00000-0000-0000-0000-000000000008',2);
  IF r<>'rejected_not_addressed' THEN RAISE EXCEPTION 'FAIL INB-05: %',r; END IF;
  RAISE NOTICE 'PASS INB-05 an event for two other Workspaces has no effect here (no context substitution)';
END $t$;
RESET SESSION AUTHORIZATION;
DO $t$ BEGIN
  IF (SELECT ownership_generation FROM enrollments WHERE enrollment_id='a1c00000-0000-0000-0000-000000000001')<>1 THEN
    RAISE EXCEPTION 'FAIL INB-06 a rejected event moved the local fence';
  END IF;
  IF (SELECT count(*) FROM workspace_inbox_events WHERE outcome LIKE 'rejected%')<>3 THEN RAISE EXCEPTION 'FAIL INB-06 record'; END IF;
  RAISE NOTICE 'PASS INB-06 every rejected event is recorded with its reason and changed no projection';
END $t$;

-- ============================ stale and future generations ============================
SET SESSION AUTHORIZATION :"worker_role";
DO $t$ DECLARE r text; BEGIN
  r := ib_apply('d1b00000-0000-0000-0000-000000000011','f1b00000-0000-0000-0000-000000000001','a1b00000-0000-0000-0000-000000000009','a1b00000-0000-0000-0000-000000000001',1);
  IF r<>'ignored_stale' THEN RAISE EXCEPTION 'FAIL INB-07: %',r; END IF;
  RAISE NOTICE 'PASS INB-07 an event at the generation already held is ignored as stale';
  r := ib_apply('d1b00000-0000-0000-0000-000000000012','f1b00000-0000-0000-0000-000000000001','a1b00000-0000-0000-0000-000000000009','a1b00000-0000-0000-0000-000000000001',5);
  IF r<>'quarantined_future' THEN RAISE EXCEPTION 'FAIL INB-08: %',r; END IF;
  RAISE NOTICE 'PASS INB-08 an event ahead of the local generation is quarantined, not applied';
END $t$;
RESET SESSION AUTHORIZATION;
DO $t$ BEGIN
  IF (SELECT ownership_generation FROM enrollments WHERE enrollment_id='a1c00000-0000-0000-0000-000000000001')<>1 THEN
    RAISE EXCEPTION 'FAIL INB-09 a stale or future event moved the local fence';
  END IF;
  IF (SELECT count(*) FROM quarantined_inbox_events)<>1 THEN RAISE EXCEPTION 'FAIL INB-09 quarantine view'; END IF;
  RAISE NOTICE 'PASS INB-09 the fence is unchanged and the future event is visible in the quarantine view';
END $t$;

-- ============================ the destination advances to exactly N+1 ============================
SET SESSION AUTHORIZATION :"worker_role";
DO $t$ DECLARE r text; BEGIN
  r := ib_apply('d1b00000-0000-0000-0000-000000000021','f1b00000-0000-0000-0000-000000000001','a1b00000-0000-0000-0000-000000000009','a1b00000-0000-0000-0000-000000000001',2);
  IF r<>'applied' THEN RAISE EXCEPTION 'FAIL INB-10: %',r; END IF;
  RAISE NOTICE 'PASS INB-10 the destination applied exactly generation N+1';
  r := ib_apply('d1b00000-0000-0000-0000-000000000021','f1b00000-0000-0000-0000-000000000001','a1b00000-0000-0000-0000-000000000009','a1b00000-0000-0000-0000-000000000001',2);
  IF r<>'applied' THEN RAISE EXCEPTION 'FAIL INB-11: %',r; END IF;
  RAISE NOTICE 'PASS INB-11 a duplicate delivery returned the recorded outcome';
END $t$;
RESET SESSION AUTHORIZATION;
DO $t$ BEGIN
  IF (SELECT ownership_generation FROM enrollments WHERE enrollment_id='a1c00000-0000-0000-0000-000000000001')<>2
     OR (SELECT state FROM enrollments WHERE enrollment_id='a1c00000-0000-0000-0000-000000000001')<>'active' THEN
    RAISE EXCEPTION 'FAIL INB-12 projection';
  END IF;
  IF (SELECT count(*) FROM workspace_inbox_events WHERE event_id='d1b00000-0000-0000-0000-000000000021')<>1 THEN
    RAISE EXCEPTION 'FAIL INB-12 the duplicate delivery created a second inbox row';
  END IF;
  IF (SELECT applied_at FROM workspace_inbox_events WHERE event_id='d1b00000-0000-0000-0000-000000000021') IS NULL THEN
    RAISE EXCEPTION 'FAIL INB-12 applied row has no applied_at';
  END IF;
  RAISE NOTICE 'PASS INB-12 inbox row and projection moved together exactly once (at-least-once delivery, once-only effect)';
END $t$;
SET SESSION AUTHORIZATION :"worker_role";
SELECT ib_err('INB-13 the same event id with different content is refused',
 $q$SELECT ib_apply('d1b00000-0000-0000-0000-000000000021','f1b00000-0000-0000-0000-000000000001','a1b00000-0000-0000-0000-000000000009','a1b00000-0000-0000-0000-000000000001',3)$q$,'23505','different content');
DO $t$ DECLARE r text; BEGIN
  -- Out of order: the earlier event arrives after the later one and must not move the fence back.
  r := ib_apply('d1b00000-0000-0000-0000-000000000022','f1b00000-0000-0000-0000-000000000001','a1b00000-0000-0000-0000-000000000009','a1b00000-0000-0000-0000-000000000001',1);
  IF r<>'ignored_stale' THEN RAISE EXCEPTION 'FAIL INB-14: %',r; END IF;
  RAISE NOTICE 'PASS INB-14 an out-of-order earlier event is ignored and never rewinds the fence';
END $t$;
RESET SESSION AUTHORIZATION;
DO $t$ BEGIN
  IF (SELECT ownership_generation FROM enrollments WHERE enrollment_id='a1c00000-0000-0000-0000-000000000001')<>2 THEN
    RAISE EXCEPTION 'FAIL INB-15 the fence moved backwards';
  END IF;
  RAISE NOTICE 'PASS INB-15 the local generation only ever moves forward';
END $t$;

-- ============================ the fence actually blocks later local commands ============================
SET SESSION AUTHORIZATION :"runtime_role";
SELECT ib_err('INB-16 a command using the pre-transfer generation is now refused',
 $q$SELECT archive_student_enrollment('ib-arc-stale','a1c00000-0000-0000-0000-000000000001',1,'b1b00000-0000-0000-0000-000000000001','stale generation')$q$,'23514','stale local ownership generation');
RESET SESSION AUTHORIZATION;

-- ============================ the source side is fenced and ended ============================
SET SESSION AUTHORIZATION :"worker_role";
DO $t$ DECLARE r text; BEGIN
  r := ib_apply('d1b00000-0000-0000-0000-000000000031','f1b00000-0000-0000-0000-000000000001','a1b00000-0000-0000-0000-000000000001','a1b00000-0000-0000-0000-000000000009',3);
  IF r<>'applied' THEN RAISE EXCEPTION 'FAIL INB-17: %',r; END IF;
  RAISE NOTICE 'PASS INB-17 the source Workspace applied the event that takes the student away';
END $t$;
RESET SESSION AUTHORIZATION;
DO $t$ BEGIN
  IF (SELECT state FROM enrollments WHERE enrollment_id='a1c00000-0000-0000-0000-000000000001')<>'ended'
     OR (SELECT ownership_generation FROM enrollments WHERE enrollment_id='a1c00000-0000-0000-0000-000000000001')<>3
     OR (SELECT ended_at FROM enrollments WHERE enrollment_id='a1c00000-0000-0000-0000-000000000001') IS NULL THEN
    RAISE EXCEPTION 'FAIL INB-18 the source projection was not fenced';
  END IF;
  IF EXISTS (SELECT 1 FROM counselor_assignments WHERE enrollment_id='a1c00000-0000-0000-0000-000000000001' AND state='active') THEN
    RAISE EXCEPTION 'FAIL INB-18 an active counselor assignment survived the transfer out';
  END IF;
  RAISE NOTICE 'PASS INB-18 the source projection is fenced at the new generation and its assignments are ended';
END $t$;
SET SESSION AUTHORIZATION :"runtime_role";
SELECT ib_err('INB-19 no local command can act on a student who has left',
 $q$SELECT archive_student_enrollment('ib-arc-gone','a1c00000-0000-0000-0000-000000000001',3,'b1b00000-0000-0000-0000-000000000001','after transfer out')$q$,'23514','only active');
RESET SESSION AUTHORIZATION;

-- ============================ the inbox is append-only and holds no global ownership ============================
SELECT ib_err('INB-20 an inbox row cannot be rewritten',
 $q$UPDATE workspace_inbox_events SET outcome='applied' WHERE outcome='ignored_stale'$q$,'23514','append-only');
SELECT ib_err('INB-21 an inbox row cannot be deleted',
 $q$DELETE FROM workspace_inbox_events$q$,'23514','append-only');
DO $t$ DECLARE n integer; BEGIN
  SELECT count(*) INTO n FROM information_schema.tables
   WHERE table_schema='public' AND table_name IN ('student_ownership','platform_students','transfer_cases');
  IF n<>0 THEN RAISE EXCEPTION 'FAIL INB-22: the Workspace database holds % Control Plane ownership table(s)',n; END IF;
  RAISE NOTICE 'PASS INB-22 the Workspace database has no global ownership table: a consumer cannot change Control Plane ownership';
END $t$;
SELECT 'WORKSPACE INBOX TESTS COMPLETED (INB-01..INB-22)' AS result;
