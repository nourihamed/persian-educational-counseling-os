-- Transfer Saga: outbox envelope, declared audience, PER-RECIPIENT delivery, leases, acknowledgement,
-- dead-letter and audited re-drive. Synthetic only (D-014).
-- Run on a FRESH DB after cp_01, cp_05, cp_07, cp_02, cp_03, cp_04, cp_06, cp_12.
--
-- C-01 regression: the previous design kept one delivery row per event, so the first recipient's
-- acknowledgement marked the whole event done and retries stopped for the other Workspace. SAGA-R01..R18
-- exercise the partial-failure boundary, not a sequential happy path.
--
-- NOT covered here, and NOT claimed anywhere: cross-database atomicity, source freeze/drain, snapshot
-- consistency, destination staging, a real process crash, network partition and chaos. Those remain
-- acceptance specifications in TRANSFER_SAGA_OUTBOX_INBOX_RECOVERY_CONTRACT.md section 10. The lease
-- expiry below is a deterministic wait on a one-second lease, not a timing race.
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
 ('a8000000-0000-0000-0000-000000000002','organization','active'),
 ('a8000000-0000-0000-0000-000000000003','organization','active');   -- never a recipient
INSERT INTO mobile_encryption_key_versions(key_version,state,key_manager_ref) VALUES (1,'active','kms://synthetic/enc-v1');
INSERT INTO mobile_hmac_key_versions(key_version,state) VALUES (1,'active');
SET SESSION AUTHORIZATION cp_identity_admission_executor;
SELECT admit_student_identity_claim('saga-admit',decode(repeat('80',32),'hex'),'b8000000-0000-0000-0000-000000000001','c8000000-0000-0000-0000-000000000001','a8000000-0000-0000-0000-000000000001','grade_10',decode('8001','hex'),1,
 '[{"key_version":1,"mobile_hmac_hex":"8080808080808080808080808080808080808080808080808080808080808080"}]'::jsonb);
RESET SESSION AUTHORIZATION;

-- ============================ the switch, its envelope and its audience are one transaction ============================
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
  PERFORM set_config('test.event_id', e.event_id::text, false);
  RAISE NOTICE 'PASS SAGA-01 the ownership switch produced one complete, self-consistent envelope at generation 2';
END $t$;
DO $t$ DECLARE n integer; BEGIN
  SELECT count(*) INTO n FROM outbox_event_recipients WHERE event_id=current_setting('test.event_id')::uuid;
  IF n<>2 THEN RAISE EXCEPTION 'FAIL SAGA-02: % declared recipients, expected 2 (source and destination)',n; END IF;
  IF NOT EXISTS (SELECT 1 FROM outbox_event_recipients WHERE event_id=current_setting('test.event_id')::uuid
                  AND workspace_id='a8000000-0000-0000-0000-000000000001' AND recipient_role='source')
     OR NOT EXISTS (SELECT 1 FROM outbox_event_recipients WHERE event_id=current_setting('test.event_id')::uuid
                  AND workspace_id='a8000000-0000-0000-0000-000000000002' AND recipient_role='destination') THEN
    RAISE EXCEPTION 'FAIL SAGA-02 wrong audience';
  END IF;
  SELECT count(*) INTO n FROM outbox_deliveries WHERE event_id=current_setting('test.event_id')::uuid AND state='pending';
  IF n<>2 THEN RAISE EXCEPTION 'FAIL SAGA-02: % pending deliveries, expected one per recipient',n; END IF;
  RAISE NOTICE 'PASS SAGA-02 both Workspaces are declared recipients and each has its own pending delivery';
END $t$;
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

-- ============================ the event and its audience are immutable ============================
SELECT sg_err('SAGA-04 an outbox event cannot be updated',
 $q$UPDATE outbox_events SET payload='{"tampered":true}'::jsonb WHERE case_id='d8000000-0000-0000-0000-000000000001'$q$,'23514','immutable');
SELECT sg_err('SAGA-05 an outbox event cannot be deleted',
 $q$DELETE FROM outbox_events WHERE case_id='d8000000-0000-0000-0000-000000000001'$q$,'23514','immutable');
SELECT sg_err('SAGA-06 an envelope whose hash does not describe its payload is refused',
 $q$INSERT INTO outbox_events(event_id,case_id,event_type,schema_version,payload,payload_hash,student_id,ownership_generation,correlation_id) VALUES (gen_random_uuid(),NULL,'forged',1,'{"a":1}'::jsonb,sha256('something else'::bytea),'b8000000-0000-0000-0000-000000000001',1,gen_random_uuid())$q$,'23514','payload_hash');
SELECT sg_err('SAGA-07 an envelope without a generation is refused',
 $q$INSERT INTO outbox_events(event_id,case_id,event_type,schema_version,payload,payload_hash,student_id,correlation_id) SELECT gen_random_uuid(),NULL,'no-generation',1,'{}'::jsonb,sha256(convert_to('{}','UTF8')),'b8000000-0000-0000-0000-000000000001',gen_random_uuid()$q$,'23502');
SELECT sg_err('SAGA-08 a delivery row cannot be deleted while its recipient exists',
 $q$DELETE FROM outbox_deliveries$q$,'23514','cannot be deleted');
SELECT sg_err('SAGA-09 a recipient cannot be removed from the declared audience',
 $q$DELETE FROM outbox_event_recipients WHERE event_id=current_setting('test.event_id')::uuid$q$,'23514','immutable');
SELECT sg_err('SAGA-10 a recipient cannot be re-pointed at another Workspace',
 $q$UPDATE outbox_event_recipients SET workspace_id='a8000000-0000-0000-0000-000000000003' WHERE event_id=current_setting('test.event_id')::uuid$q$,'23514','immutable');
-- An event with no declared audience is durable and undeliverable: refused at COMMIT.
DO $t$ DECLARE p jsonb; BEGIN
  BEGIN
    p := jsonb_build_object('synthetic',true);
    INSERT INTO outbox_events(event_id,case_id,event_type,schema_version,payload,payload_hash,student_id,ownership_generation,correlation_id)
    VALUES (gen_random_uuid(),NULL,'no-audience',1,p,sha256(convert_to(p::text,'UTF8')),'b8000000-0000-0000-0000-000000000001',1,gen_random_uuid());
    SET CONSTRAINTS public.outbox_event_requires_recipient IMMEDIATE;
  EXCEPTION WHEN check_violation THEN
    IF position('declares no recipient' IN SQLERRM)=0 THEN RAISE EXCEPTION 'FAIL SAGA-11 wrong reason: %',SQLERRM; END IF;
    SET CONSTRAINTS public.outbox_event_requires_recipient DEFERRED;
    RAISE NOTICE 'PASS SAGA-11 an event that declares no recipient is refused at the constraint check';
    RETURN;
  END;
  RAISE EXCEPTION 'FAIL SAGA-11 an event with no audience was accepted';
END $t$;

-- ============================ C-01: per-recipient delivery under partial failure ============================
-- Before anything is sent, no recipient may acknowledge, and no outsider may acknowledge at all.
SET SESSION AUTHORIZATION cp_saga_dispatcher;
SELECT sg_err('SAGA-R01 acknowledgement before a successful send is refused',
 $q$SELECT acknowledge_outbox_event(current_setting('test.event_id')::uuid,'a8000000-0000-0000-0000-000000000002','applied','too early')$q$,'23514','never sent');
SELECT sg_err('SAGA-R02 a Workspace that is not a declared recipient cannot acknowledge',
 $q$SELECT acknowledge_outbox_event(current_setting('test.event_id')::uuid,'a8000000-0000-0000-0000-000000000003','applied','not my event')$q$,'42501','not a declared recipient');
SELECT sg_err('SAGA-R03 a non-recipient cannot be reported as sent',
 $q$SELECT record_outbox_sent(current_setting('test.event_id')::uuid,'a8000000-0000-0000-0000-000000000003','dispatcher-a')$q$,'42501','not a declared recipient');

-- One claim returns BOTH recipient deliveries. The lease is one second: the expiry below is a deterministic
-- wait for that lease, not a race.
DO $t$ DECLARE n integer; BEGIN
  SELECT count(*) INTO n FROM claim_outbox_events('dispatcher-a', 10, 1);
  IF n<>2 THEN RAISE EXCEPTION 'FAIL SAGA-R04: claimed % deliveries, expected 2 (one per recipient)',n; END IF;
  RAISE NOTICE 'PASS SAGA-R04 one claim returned a separate delivery for each required recipient';
  SELECT count(*) INTO n FROM claim_outbox_events('dispatcher-b', 10, 60);
  IF n<>0 THEN RAISE EXCEPTION 'FAIL SAGA-R05: a second dispatcher claimed % live-leased deliveries',n; END IF;
  RAISE NOTICE 'PASS SAGA-R05 a second dispatcher claimed nothing while both leases were live';
END $t$;
SELECT sg_err('SAGA-R06 a dispatcher that does not hold THIS recipient''s lease cannot report it sent',
 $q$SELECT record_outbox_sent(current_setting('test.event_id')::uuid,'a8000000-0000-0000-0000-000000000002','dispatcher-b')$q$,'42501','leased by');
-- The destination is delivered and acknowledges. The source has received nothing.
DO $t$ DECLARE r text; d_src outbox_deliveries%ROWTYPE; BEGIN
  r := record_outbox_sent(current_setting('test.event_id')::uuid,'a8000000-0000-0000-0000-000000000002','dispatcher-a');
  IF r<>'sent' THEN RAISE EXCEPTION 'FAIL SAGA-R07: %',r; END IF;
  r := acknowledge_outbox_event(current_setting('test.event_id')::uuid,'a8000000-0000-0000-0000-000000000002','applied','destination projection advanced');
  IF r<>'acknowledged' THEN RAISE EXCEPTION 'FAIL SAGA-R07 ack: %',r; END IF;
  RAISE NOTICE 'PASS SAGA-R07 the destination was sent the event and acknowledged it';
END $t$;
RESET SESSION AUTHORIZATION;
DO $t$ DECLARE d_src outbox_deliveries%ROWTYPE; c record; BEGIN
  SELECT * INTO d_src FROM outbox_deliveries
   WHERE event_id=current_setting('test.event_id')::uuid AND workspace_id='a8000000-0000-0000-0000-000000000001';
  IF d_src.state='acknowledged' OR d_src.acknowledged_at IS NOT NULL OR d_src.sent_at IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL SAGA-R08: the destination acknowledgement marked the SOURCE delivery done: %', row_to_json(d_src);
  END IF;
  RAISE NOTICE 'PASS SAGA-R08 the destination acknowledgement did not touch the source delivery (this is the C-01 defect)';
  SELECT * INTO c FROM outbox_event_completion WHERE event_id=current_setting('test.event_id')::uuid;
  IF c.required_recipients<>2 OR c.acknowledged_recipients<>1 OR c.complete THEN
    RAISE EXCEPTION 'FAIL SAGA-R09: %', row_to_json(c);
  END IF;
  RAISE NOTICE 'PASS SAGA-R09 the event is NOT complete with one of two recipients acknowledged';
  IF NOT EXISTS (SELECT 1 FROM outbox_delivery_backlog
                  WHERE event_id=current_setting('test.event_id')::uuid AND workspace_id='a8000000-0000-0000-0000-000000000001') THEN
    RAISE EXCEPTION 'FAIL SAGA-R10 the source delivery left the backlog while still unacknowledged';
  END IF;
  RAISE NOTICE 'PASS SAGA-R10 the source delivery is still outstanding work in the backlog';
END $t$;
SET SESSION AUTHORIZATION cp_saga_dispatcher;
DO $t$ DECLARE r text; BEGIN
  r := acknowledge_outbox_event(current_setting('test.event_id')::uuid,'a8000000-0000-0000-0000-000000000002','applied','destination projection advanced');
  IF r<>'replayed' THEN RAISE EXCEPTION 'FAIL SAGA-R11: %',r; END IF;
  RAISE NOTICE 'PASS SAGA-R11 a duplicate acknowledgement from the same recipient is idempotent';
END $t$;
SELECT sg_err('SAGA-R12 a conflicting acknowledgement from the same recipient is refused',
 $q$SELECT acknowledge_outbox_event(current_setting('test.event_id')::uuid,'a8000000-0000-0000-0000-000000000002','ignored_stale','changed its mind')$q$,'23505','already acknowledged');

-- Dispatcher "crash": dispatcher-a never reports the source. Its one-second lease expires and a restarted
-- dispatcher picks up exactly the outstanding recipient.
SELECT pg_sleep(1.2);
DO $t$ DECLARE n integer; w uuid; BEGIN
  SELECT count(*), max(workspace_id::text)::uuid INTO n, w FROM claim_outbox_events('dispatcher-c', 10, 60);
  IF n<>1 THEN RAISE EXCEPTION 'FAIL SAGA-R13: the restarted dispatcher claimed % deliveries, expected only the source',n; END IF;
  IF w<>'a8000000-0000-0000-0000-000000000001' THEN RAISE EXCEPTION 'FAIL SAGA-R13 wrong recipient claimed: %',w; END IF;
  RAISE NOTICE 'PASS SAGA-R13 after the lease expired, a restarted dispatcher claimed ONLY the unacknowledged recipient';
END $t$;
SELECT sg_err('SAGA-R14 the stale dispatcher cannot report the delivery it abandoned',
 $q$SELECT record_outbox_sent(current_setting('test.event_id')::uuid,'a8000000-0000-0000-0000-000000000001','dispatcher-a')$q$,'42501','leased by');
DO $t$ DECLARE r text; c record; BEGIN
  r := record_outbox_sent(current_setting('test.event_id')::uuid,'a8000000-0000-0000-0000-000000000001','dispatcher-c');
  IF r<>'sent' THEN RAISE EXCEPTION 'FAIL SAGA-R15: %',r; END IF;
  r := acknowledge_outbox_event(current_setting('test.event_id')::uuid,'a8000000-0000-0000-0000-000000000001','applied','source projection fenced');
  IF r<>'acknowledged' THEN RAISE EXCEPTION 'FAIL SAGA-R15 ack: %',r; END IF;
  RAISE NOTICE 'PASS SAGA-R15 the remaining recipient was delivered and acknowledged after the restart';
END $t$;
RESET SESSION AUTHORIZATION;
DO $t$ DECLARE c record; BEGIN
  SELECT * INTO c FROM outbox_event_completion WHERE event_id=current_setting('test.event_id')::uuid;
  IF c.required_recipients<>2 OR c.acknowledged_recipients<>2 OR NOT c.complete THEN
    RAISE EXCEPTION 'FAIL SAGA-R16: %', row_to_json(c);
  END IF;
  IF EXISTS (SELECT 1 FROM outbox_delivery_backlog WHERE event_id=current_setting('test.event_id')::uuid) THEN
    RAISE EXCEPTION 'FAIL SAGA-R16 backlog not empty';
  END IF;
  IF (SELECT count(*) FROM inbox_events WHERE event_id=current_setting('test.event_id')::uuid)<>2 THEN
    RAISE EXCEPTION 'FAIL SAGA-R16 expected one acknowledgement row per recipient';
  END IF;
  RAISE NOTICE 'PASS SAGA-R16 the event became complete only after BOTH required recipients acknowledged';
END $t$;
SELECT sg_err('SAGA-R17 an acknowledged delivery is terminal',
 $q$UPDATE outbox_deliveries SET state='pending', acknowledged_at=NULL WHERE event_id=current_setting('test.event_id')::uuid$q$,'23514');
DO $t$ DECLARE a integer; b integer; BEGIN
  SELECT attempts INTO a FROM outbox_deliveries WHERE event_id=current_setting('test.event_id')::uuid AND workspace_id='a8000000-0000-0000-0000-000000000001';
  SELECT attempts INTO b FROM outbox_deliveries WHERE event_id=current_setting('test.event_id')::uuid AND workspace_id='a8000000-0000-0000-0000-000000000002';
  IF a<1 OR b<1 THEN RAISE EXCEPTION 'FAIL SAGA-R18: attempts %, %',a,b; END IF;
  RAISE NOTICE 'PASS SAGA-R18 each recipient carries its own independent attempt count (source %, destination %)',a,b;
END $t$;

-- ============================ dead-letter and re-drive are per recipient ============================
-- The event and its audience must be declared in ONE transaction: the deferred audience check runs at
-- commit, so an event committed without recipients is refused (see SAGA-11).
BEGIN;
INSERT INTO outbox_events(event_id,case_id,event_type,schema_version,payload,payload_hash,student_id,
                          source_workspace_id,destination_workspace_id,ownership_generation,correlation_id)
SELECT 'e8000000-0000-0000-0000-00000000000d',NULL,'ownership_switched',1,p,
       sha256(convert_to(p::text,'UTF8')),'b8000000-0000-0000-0000-000000000001',
       'a8000000-0000-0000-0000-000000000002','a8000000-0000-0000-0000-000000000001',3,gen_random_uuid()
  FROM (SELECT jsonb_build_object('student_id','b8000000-0000-0000-0000-000000000001','generation',3) AS p) x;
INSERT INTO outbox_event_recipients(event_id,workspace_id,recipient_role) VALUES
 ('e8000000-0000-0000-0000-00000000000d','a8000000-0000-0000-0000-000000000002','source'),
 ('e8000000-0000-0000-0000-00000000000d','a8000000-0000-0000-0000-000000000001','destination');
COMMIT;
SET SESSION AUTHORIZATION cp_saga_dispatcher;
SELECT sg_err('SAGA-R19 the dispatcher cannot dead-letter a delivery by itself',
 $q$SELECT dead_letter_outbox_event('e8000000-0000-0000-0000-00000000000d','a8000000-0000-0000-0000-000000000001','dispatcher-a','gave up')$q$,'42501');
RESET SESSION AUTHORIZATION;
SELECT sg_err('SAGA-R20 a non-recipient delivery cannot be dead-lettered',
 $q$SELECT dead_letter_outbox_event('e8000000-0000-0000-0000-00000000000d','a8000000-0000-0000-0000-000000000003','operator-1','not a recipient')$q$,'42501','not a declared recipient');
DO $t$ DECLARE r text; BEGIN
  r := dead_letter_outbox_event('e8000000-0000-0000-0000-00000000000d','a8000000-0000-0000-0000-000000000001','operator-1','undeliverable-after-review');
  IF r<>'dead_lettered' THEN RAISE EXCEPTION 'FAIL SAGA-R21: %',r; END IF;
  r := dead_letter_outbox_event('e8000000-0000-0000-0000-00000000000d','a8000000-0000-0000-0000-000000000001','operator-1','undeliverable-after-review');
  IF r<>'replayed' THEN RAISE EXCEPTION 'FAIL SAGA-R21 replay: %',r; END IF;
  RAISE NOTICE 'PASS SAGA-R21 dead-letter applies to one recipient and is idempotent';
END $t$;
DO $t$ BEGIN
  IF (SELECT state FROM outbox_deliveries WHERE event_id='e8000000-0000-0000-0000-00000000000d' AND workspace_id='a8000000-0000-0000-0000-000000000002')<>'pending' THEN
    RAISE EXCEPTION 'FAIL SAGA-R22 dead-lettering one recipient changed the other';
  END IF;
  RAISE NOTICE 'PASS SAGA-R22 the other recipient is untouched and still deliverable';
END $t$;
DO $t$ DECLARE r text; BEGIN
  r := redrive_outbox_event('e8000000-0000-0000-0000-00000000000d','a8000000-0000-0000-0000-000000000001','operator-2','root-cause-fixed');
  IF r<>'redriven' THEN RAISE EXCEPTION 'FAIL SAGA-R23: %',r; END IF;
  RAISE NOTICE 'PASS SAGA-R23 re-drive returned the SAME event id to the queue for that recipient';
END $t$;
SELECT sg_err('SAGA-R24 re-driving a delivery that is not dead-lettered is refused',
 $q$SELECT redrive_outbox_event('e8000000-0000-0000-0000-00000000000d','a8000000-0000-0000-0000-000000000001','operator-2','again')$q$,'23514','only a dead-lettered');
SELECT sg_err('SAGA-R25 dead-letter without a reason code is refused',
 $q$SELECT dead_letter_outbox_event('e8000000-0000-0000-0000-00000000000d','a8000000-0000-0000-0000-000000000001','operator-1','   ')$q$,'22023','reason code');
DO $t$ BEGIN
  IF (SELECT count(*) FROM outbox_delivery_audit WHERE event_id='e8000000-0000-0000-0000-00000000000d' AND workspace_id='a8000000-0000-0000-0000-000000000001')<>2
     OR (SELECT count(*) FROM outbox_delivery_audit WHERE event_id='e8000000-0000-0000-0000-00000000000d' AND workspace_id='a8000000-0000-0000-0000-000000000002')<>0 THEN
    RAISE EXCEPTION 'FAIL SAGA-R26 the audit trail is not per recipient';
  END IF;
  IF (SELECT count(*) FROM outbox_events WHERE event_id='e8000000-0000-0000-0000-00000000000d')<>1 THEN
    RAISE EXCEPTION 'FAIL SAGA-R26 re-drive minted a new event';
  END IF;
  RAISE NOTICE 'PASS SAGA-R26 every dead-letter and re-drive is attributed to one recipient, and no new event was minted';
END $t$;
SELECT sg_err('SAGA-R27 the delivery audit trail is append-only',
 $q$DELETE FROM outbox_delivery_audit$q$,'23514','append-only');

-- ============================ the dispatcher cannot touch ownership or the audience ============================
SET SESSION AUTHORIZATION cp_saga_dispatcher;
SELECT sg_err('SAGA-R28 the dispatcher cannot change Control Plane ownership',
 $q$UPDATE student_ownership SET ownership_generation=99 WHERE student_id='b8000000-0000-0000-0000-000000000001'$q$,'42501');
SELECT sg_err('SAGA-R29 the dispatcher cannot write an outbox event',
 $q$INSERT INTO outbox_events(event_id,case_id,event_type,schema_version,payload,payload_hash,student_id,ownership_generation,correlation_id) VALUES (gen_random_uuid(),NULL,'forged',1,'{}'::jsonb,sha256(convert_to('{}','UTF8')),'b8000000-0000-0000-0000-000000000001',1,gen_random_uuid())$q$,'42501');
SELECT sg_err('SAGA-R30 the dispatcher cannot declare or change an audience',
 $q$INSERT INTO outbox_event_recipients(event_id,workspace_id,recipient_role) VALUES ('e8000000-0000-0000-0000-00000000000d','a8000000-0000-0000-0000-000000000003','owner')$q$,'42501');
SELECT sg_err('SAGA-R31 the dispatcher cannot change delivery rows directly',
 $q$UPDATE outbox_deliveries SET state='acknowledged'$q$,'42501');
SELECT sg_err('SAGA-R32 the dispatcher cannot switch ownership',
 $q$SELECT switch_student_ownership('d8000000-0000-0000-0000-000000000001')$q$,'42501');
RESET SESSION AUTHORIZATION;
SELECT 'SAGA PER-RECIPIENT DELIVERY TESTS COMPLETED (SAGA-01..11, SAGA-R01..R32)' AS result;
