-- Transfer Saga: outbox envelope, delivery leases, acknowledgement, dead-letter and audited re-drive.
-- Synthetic only (D-014). Run on a FRESH DB after cp_01, cp_05, cp_07, cp_02, cp_03, cp_04, cp_06, cp_12.
--
-- NOT covered by these tests, and NOT claimed anywhere: cross-database atomicity, source freeze/drain,
-- snapshot consistency, destination staging, real dispatcher crash/restart, network partition and chaos.
-- Those remain acceptance specifications in TRANSFER_SAGA_OUTBOX_INBOX_RECOVERY_CONTRACT.md section 10.
\set ON_ERROR_STOP on
CREATE OR REPLACE FUNCTION sg_err(label text, stmt text, want text, want_msg text DEFAULT '')
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

INSERT INTO workspaces(workspace_id,workspace_type,status) VALUES
 ('a8000000-0000-0000-0000-000000000001','organization','active'),
 ('a8000000-0000-0000-0000-000000000002','organization','active');
INSERT INTO mobile_encryption_key_versions(key_version,state,key_manager_ref) VALUES (1,'active','kms://synthetic/enc-v1');
INSERT INTO mobile_hmac_key_versions(key_version,state) VALUES (1,'active');
SET SESSION AUTHORIZATION cp_identity_admission_executor;
SELECT admit_student_identity_claim('saga-admit',decode(repeat('80',32),'hex'),'b8000000-0000-0000-0000-000000000001','c8000000-0000-0000-0000-000000000001','a8000000-0000-0000-0000-000000000001','grade_10',decode('8001','hex'),1,
 '[{"key_version":1,"mobile_hmac_hex":"8080808080808080808080808080808080808080808080808080808080808080"}]'::jsonb);
RESET SESSION AUTHORIZATION;

-- ============================ the switch and its event are one transaction ============================
SET SESSION AUTHORIZATION cp_transfer_executor;
SELECT request_transfer_case_idempotent('saga-case',decode(repeat('8c',32),'hex'),'d8000000-0000-0000-0000-000000000001','b8000000-0000-0000-0000-000000000001','a8000000-0000-0000-0000-000000000001','a8000000-0000-0000-0000-000000000002',1,'guardian');
RESET SESSION AUTHORIZATION;
UPDATE transfer_cases SET state='approvals_pending' WHERE case_id='d8000000-0000-0000-0000-000000000001';
UPDATE transfer_cases SET state='approved' WHERE case_id='d8000000-0000-0000-0000-000000000001';
UPDATE transfer_cases SET state='preflight_ok' WHERE case_id='d8000000-0000-0000-0000-000000000001';
UPDATE transfer_cases SET state='staging' WHERE case_id='d8000000-0000-0000-0000-000000000001';
UPDATE transfer_cases SET state='staged_verified' WHERE case_id='d8000000-0000-0000-0000-000000000001';
UPDATE transfer_cases SET source_freeze_token='freeze-saga',source_frozen_at=now(),final_snapshot_ref='snapshot-saga',final_snapshot_at=now(),snapshot_manifest_hash=decode(repeat('80',32),'hex'),destination_validation_ref='validation-saga',destination_validated_at=now() WHERE case_id='d8000000-0000-0000-0000-000000000001';
UPDATE transfer_cases SET state='cutover_frozen' WHERE case_id='d8000000-0000-0000-0000-000000000001';
INSERT INTO transfer_approvals(approval_id,assertion_id,nonce_digest,case_id,approval_kind,evidence_ref,approver_ref,authn_event_ref,authority_snapshot,verified_at)
SELECT gen_random_uuid(),gen_random_uuid(),sha256(convert_to('saga-'||k,'UTF8')),c.case_id,k,'ev-saga-'||k,'subject-saga-'||k,'authn-saga-'||k,
       jsonb_build_object('synthetic',true,'workspace_id',
         CASE k WHEN 'fee_confirmation' THEN c.source_workspace_id WHEN 'destination_acceptance' THEN c.destination_workspace_id END),now()
  FROM unnest(ARRAY['guardian_consent','fee_confirmation','destination_acceptance']) k,
       transfer_cases c WHERE c.case_id='d8000000-0000-0000-0000-000000000001';
SET SESSION AUTHORIZATION cp_transfer_executor;
SELECT switch_student_ownership('d8000000-0000-0000-0000-000000000001');
RESET SESSION AUTHORIZATION;
DO $t$ DECLARE e outbox_events%ROWTYPE; BEGIN
  SELECT * INTO e FROM outbox_events WHERE case_id='d8000000-0000-0000-0000-000000000001';
  IF NOT FOUND THEN RAISE EXCEPTION 'FAIL SAGA-01 no event for a completed switch'; END IF;
  IF e.event_type<>'ownership_switched' OR e.schema_version<>1 OR e.student_id<>'b8000000-0000-0000-0000-000000000001'
     OR e.ownership_generation<>2 OR e.source_workspace_id<>'a8000000-0000-0000-0000-000000000001'
     OR e.destination_workspace_id<>'a8000000-0000-0000-0000-000000000002' OR e.correlation_id IS NULL THEN
    RAISE EXCEPTION 'FAIL SAGA-01 incomplete envelope: %', row_to_json(e);
  END IF;
  IF e.payload_hash <> sha256(convert_to(e.payload::text,'UTF8')) THEN RAISE EXCEPTION 'FAIL SAGA-01 hash'; END IF;
  IF (SELECT ownership_generation FROM student_ownership WHERE student_id='b8000000-0000-0000-0000-000000000001')<>e.ownership_generation THEN
    RAISE EXCEPTION 'FAIL SAGA-01 the switch and the event disagree about the generation';
  END IF;
  RAISE NOTICE 'PASS SAGA-01 the ownership switch produced one complete, self-consistent envelope at generation 2';
  IF (SELECT state FROM outbox_deliveries WHERE event_id=e.event_id)<>'pending' THEN RAISE EXCEPTION 'FAIL SAGA-02'; END IF;
  RAISE NOTICE 'PASS SAGA-02 delivery state was created automatically and starts pending';
END $t$;
-- Failure injection: a switch that raises inside its transaction leaves neither ownership nor event behind.
DO $t$ DECLARE n_before integer; n_after integer; g_before bigint; BEGIN
  SELECT count(*) INTO n_before FROM outbox_events;
  SELECT ownership_generation INTO g_before FROM student_ownership WHERE student_id='b8000000-0000-0000-0000-000000000001';
  BEGIN
    PERFORM switch_student_ownership('d8000000-0000-0000-0000-000000000001');   -- already switched: must fail
  EXCEPTION WHEN OTHERS THEN NULL;
  END;
  SELECT count(*) INTO n_after FROM outbox_events;
  IF n_after<>n_before
     OR (SELECT ownership_generation FROM student_ownership WHERE student_id='b8000000-0000-0000-0000-000000000001')<>g_before THEN
    RAISE EXCEPTION 'FAIL SAGA-03 a refused switch left ownership or an event behind';
  END IF;
  RAISE NOTICE 'PASS SAGA-03 a refused switch produced neither an ownership change nor an event';
END $t$;

-- ============================ the event is immutable, the delivery is not ============================
SELECT sg_err('SAGA-04 an outbox event cannot be updated',
 $q$UPDATE outbox_events SET payload='{"tampered":true}'::jsonb WHERE case_id='d8000000-0000-0000-0000-000000000001'$q$,'23514','immutable');
SELECT sg_err('SAGA-05 an outbox event cannot be deleted',
 $q$DELETE FROM outbox_events WHERE case_id='d8000000-0000-0000-0000-000000000001'$q$,'23514','immutable');
SELECT sg_err('SAGA-06 an envelope whose hash does not describe its payload is refused',
 $q$INSERT INTO outbox_events(event_id,case_id,event_type,schema_version,payload,payload_hash,student_id,ownership_generation,correlation_id) VALUES (gen_random_uuid(),NULL,'forged',1,'{"a":1}'::jsonb,sha256('something else'::bytea),'b8000000-0000-0000-0000-000000000001',1,gen_random_uuid())$q$,'23514','payload_hash');
SELECT sg_err('SAGA-07 an envelope without a generation is refused',
 $q$INSERT INTO outbox_events(event_id,case_id,event_type,schema_version,payload,payload_hash,student_id,correlation_id) SELECT gen_random_uuid(),NULL,'no-generation',1,'{}'::jsonb,sha256(convert_to('{}','UTF8')),'b8000000-0000-0000-0000-000000000001',gen_random_uuid()$q$,'23502');
SELECT sg_err('SAGA-08 a delivery row cannot be deleted while its event exists',
 $q$DELETE FROM outbox_deliveries$q$,'23514','cannot be deleted');

-- ============================ dispatcher leases ============================
SELECT 'e8000000-0000-0000-0000-000000000001'::uuid AS unused \gset
DO $t$ DECLARE v_id uuid; n integer; BEGIN
  SELECT event_id INTO v_id FROM outbox_events LIMIT 1;
  PERFORM set_config('test.event_id', v_id::text, false);
END $t$;
SET SESSION AUTHORIZATION cp_saga_dispatcher;
DO $t$ DECLARE n integer; v_id uuid; BEGIN
  SELECT count(*) INTO n FROM claim_outbox_events('dispatcher-a', 10, 60);
  IF n<>1 THEN RAISE EXCEPTION 'FAIL SAGA-09: claimed % events, expected 1',n; END IF;
  RAISE NOTICE 'PASS SAGA-09 the dispatcher claimed the pending event under a lease';
  SELECT count(*) INTO n FROM claim_outbox_events('dispatcher-b', 10, 60);
  IF n<>0 THEN RAISE EXCEPTION 'FAIL SAGA-10: a second dispatcher claimed % leased events',n; END IF;
  RAISE NOTICE 'PASS SAGA-10 a second dispatcher claimed nothing while the lease is live';
END $t$;
SELECT sg_err('SAGA-11 a dispatcher that does not hold the lease cannot report the event as sent',
 $q$SELECT record_outbox_sent(current_setting('test.event_id')::uuid,'dispatcher-b')$q$,'42501','leased by');
SELECT sg_err('SAGA-12 the lease duration must be stated explicitly',
 $q$SELECT count(*) FROM claim_outbox_events('dispatcher-a',10,NULL)$q$,'22023','lease_seconds');
DO $t$ DECLARE r text; BEGIN
  r := record_outbox_sent(current_setting('test.event_id')::uuid,'dispatcher-a');
  IF r<>'sent' THEN RAISE EXCEPTION 'FAIL SAGA-13: %',r; END IF;
  r := release_outbox_lease(current_setting('test.event_id')::uuid,'dispatcher-a','synthetic-timeout');
  IF r<>'released' THEN RAISE EXCEPTION 'FAIL SAGA-14: %',r; END IF;
  RAISE NOTICE 'PASS SAGA-13/14 the lease holder reported the send and then returned the event to the queue';
END $t$;
RESET SESSION AUTHORIZATION;
DO $t$ DECLARE d outbox_deliveries%ROWTYPE; BEGIN
  SELECT * INTO d FROM outbox_deliveries WHERE event_id=current_setting('test.event_id')::uuid;
  IF d.state<>'pending' OR d.attempts<>2 OR d.lease_owner IS NOT NULL OR d.last_error_code<>'synthetic-timeout' THEN
    RAISE EXCEPTION 'FAIL SAGA-15: %', row_to_json(d);
  END IF;
  RAISE NOTICE 'PASS SAGA-15 the same event id is retried with its attempt count preserved (2 attempts)';
END $t$;
SELECT sg_err('SAGA-16 the attempt count cannot be rewritten downwards',
 $q$UPDATE outbox_deliveries SET attempts=0 WHERE event_id=current_setting('test.event_id')::uuid$q$,'23514','cannot decrease');

-- ============================ acknowledgement is the consumer's recorded outcome ============================
SET SESSION AUTHORIZATION cp_saga_dispatcher;
DO $t$ DECLARE r text; BEGIN
  PERFORM count(*) FROM claim_outbox_events('dispatcher-a',10,60);
  PERFORM record_outbox_sent(current_setting('test.event_id')::uuid,'dispatcher-a');
  r := acknowledge_outbox_event(current_setting('test.event_id')::uuid,'a8000000-0000-0000-0000-000000000002','applied','destination projection advanced');
  IF r<>'acknowledged' THEN RAISE EXCEPTION 'FAIL SAGA-17: %',r; END IF;
  r := acknowledge_outbox_event(current_setting('test.event_id')::uuid,'a8000000-0000-0000-0000-000000000002','applied','destination projection advanced');
  IF r<>'replayed' THEN RAISE EXCEPTION 'FAIL SAGA-18: %',r; END IF;
  RAISE NOTICE 'PASS SAGA-17/18 acknowledgement is recorded once and a duplicate acknowledgement changes nothing';
  r := acknowledge_outbox_event(current_setting('test.event_id')::uuid,'a8000000-0000-0000-0000-000000000001','applied','source projection fenced');
  IF r<>'acknowledged' THEN RAISE EXCEPTION 'FAIL SAGA-19: %',r; END IF;
  RAISE NOTICE 'PASS SAGA-19 the other side of the transfer acknowledged the same event independently';
END $t$;
SELECT sg_err('SAGA-20 a second acknowledgement with a different outcome is refused',
 $q$SELECT acknowledge_outbox_event(current_setting('test.event_id')::uuid,'a8000000-0000-0000-0000-000000000002','ignored_stale','changed its mind')$q$,'23505','already acknowledged');
RESET SESSION AUTHORIZATION;
DO $t$ BEGIN
  IF (SELECT count(*) FROM inbox_events WHERE event_id=current_setting('test.event_id')::uuid)<>2 THEN RAISE EXCEPTION 'FAIL SAGA-21'; END IF;
  IF (SELECT state FROM outbox_deliveries WHERE event_id=current_setting('test.event_id')::uuid)<>'acknowledged' THEN RAISE EXCEPTION 'FAIL SAGA-21 state'; END IF;
  IF EXISTS (SELECT 1 FROM outbox_delivery_backlog WHERE event_id=current_setting('test.event_id')::uuid) THEN RAISE EXCEPTION 'FAIL SAGA-21 backlog'; END IF;
  RAISE NOTICE 'PASS SAGA-21 both acknowledgements are recorded and the event left the backlog';
END $t$;
SELECT sg_err('SAGA-22 an acknowledged delivery is terminal',
 $q$UPDATE outbox_deliveries SET state='pending', acknowledged_at=NULL WHERE event_id=current_setting('test.event_id')::uuid$q$,'23514');

-- ============================ dead-letter and audited re-drive ============================
-- A second, undeliverable event for the same student. It needs no transfer case of its own.
INSERT INTO outbox_events(event_id,case_id,event_type,schema_version,payload,payload_hash,student_id,
                          source_workspace_id,destination_workspace_id,ownership_generation,correlation_id)
SELECT 'e8000000-0000-0000-0000-00000000000d',NULL,'ownership_switched',1,p,
       sha256(convert_to(p::text,'UTF8')),'b8000000-0000-0000-0000-000000000001',
       'a8000000-0000-0000-0000-000000000002','a8000000-0000-0000-0000-000000000001',3,gen_random_uuid()
  FROM (SELECT jsonb_build_object('student_id','b8000000-0000-0000-0000-000000000001','generation',3) AS p) x;
SET SESSION AUTHORIZATION cp_saga_dispatcher;
SELECT sg_err('SAGA-23 the dispatcher cannot dead-letter an event by itself',
 $q$SELECT dead_letter_outbox_event('e8000000-0000-0000-0000-00000000000d','dispatcher-a','gave up')$q$,'42501');
RESET SESSION AUTHORIZATION;
DO $t$ DECLARE r text; BEGIN
  r := dead_letter_outbox_event('e8000000-0000-0000-0000-00000000000d','operator-1','undeliverable-after-review');
  IF r<>'dead_lettered' THEN RAISE EXCEPTION 'FAIL SAGA-24: %',r; END IF;
  r := dead_letter_outbox_event('e8000000-0000-0000-0000-00000000000d','operator-1','undeliverable-after-review');
  IF r<>'replayed' THEN RAISE EXCEPTION 'FAIL SAGA-25: %',r; END IF;
  r := redrive_outbox_event('e8000000-0000-0000-0000-00000000000d','operator-2','root-cause-fixed');
  IF r<>'redriven' THEN RAISE EXCEPTION 'FAIL SAGA-26: %',r; END IF;
  RAISE NOTICE 'PASS SAGA-24/25/26 dead-letter is idempotent and re-drive returns the SAME event id to the queue';
END $t$;
SELECT sg_err('SAGA-27 re-driving an event that is not dead-lettered is refused',
 $q$SELECT redrive_outbox_event('e8000000-0000-0000-0000-00000000000d','operator-2','again')$q$,'23514','only a dead-lettered');
SELECT sg_err('SAGA-28 dead-letter without a reason code is refused',
 $q$SELECT dead_letter_outbox_event('e8000000-0000-0000-0000-00000000000d','operator-1','   ')$q$,'22023','reason code');
DO $t$ BEGIN
  IF (SELECT count(*) FROM outbox_delivery_audit WHERE event_id='e8000000-0000-0000-0000-00000000000d')<>2
     OR (SELECT count(*) FROM outbox_delivery_audit WHERE action='dead_letter' AND actor_ref='operator-1')<>1
     OR (SELECT count(*) FROM outbox_delivery_audit WHERE action='redrive' AND actor_ref='operator-2')<>1 THEN
    RAISE EXCEPTION 'FAIL SAGA-29 the dead-letter/re-drive trail is incomplete';
  END IF;
  IF (SELECT count(*) FROM outbox_events WHERE event_id='e8000000-0000-0000-0000-00000000000d')<>1 THEN
    RAISE EXCEPTION 'FAIL SAGA-29 re-drive minted a new event';
  END IF;
  RAISE NOTICE 'PASS SAGA-29 every dead-letter and re-drive is attributed, and no new event was minted';
END $t$;
SELECT sg_err('SAGA-30 the delivery audit trail is append-only',
 $q$DELETE FROM outbox_delivery_audit$q$,'23514','append-only');

-- ============================ the dispatcher cannot touch ownership ============================
SET SESSION AUTHORIZATION cp_saga_dispatcher;
SELECT sg_err('SAGA-31 the dispatcher cannot change Control Plane ownership',
 $q$UPDATE student_ownership SET ownership_generation=99 WHERE student_id='b8000000-0000-0000-0000-000000000001'$q$,'42501');
SELECT sg_err('SAGA-32 the dispatcher cannot write an outbox event',
 $q$INSERT INTO outbox_events(event_id,case_id,event_type,schema_version,payload,payload_hash,student_id,ownership_generation,correlation_id) VALUES (gen_random_uuid(),NULL,'forged',1,'{}'::jsonb,sha256(convert_to('{}','UTF8')),'b8000000-0000-0000-0000-000000000001',1,gen_random_uuid())$q$,'42501');
SELECT sg_err('SAGA-33 the dispatcher cannot change delivery rows directly',
 $q$UPDATE outbox_deliveries SET state='acknowledged'$q$,'42501');
SELECT sg_err('SAGA-34 the dispatcher cannot switch ownership',
 $q$SELECT switch_student_ownership('d8000000-0000-0000-0000-000000000001')$q$,'42501');
RESET SESSION AUTHORIZATION;
SELECT 'SAGA OUTBOX DELIVERY TESTS COMPLETED (SAGA-01..SAGA-34)' AS result;
