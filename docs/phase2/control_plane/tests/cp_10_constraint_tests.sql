-- CONTROL PLANE regression suite. Synthetic only. Run on a FRESH DB after cp_01, cp_05, cp_02, cp_03 and cp_04.
\set ON_ERROR_STOP on
CREATE OR REPLACE FUNCTION expect_error(label text, stmt text, want text)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE stmt;
  RAISE EXCEPTION 'FAIL %: statement unexpectedly succeeded', label;
EXCEPTION WHEN OTHERS THEN
  IF SQLSTATE <> want THEN
    RAISE EXCEPTION 'FAIL %: got SQLSTATE % (%), expected %', label, SQLSTATE, SQLERRM, want;
  END IF;
  RAISE NOTICE 'PASS % (SQLSTATE %)', label, SQLSTATE;
END; $$;

INSERT INTO workspaces(workspace_id,workspace_type,status) VALUES
 ('a0000000-0000-0000-0000-000000000001','organization','active'),
 ('a0000000-0000-0000-0000-000000000002','independent_counselor','active'),
 ('a0000000-0000-0000-0000-000000000003','organization','active');
INSERT INTO platform_students(student_id) VALUES
 ('b0000000-0000-0000-0000-000000000001'),
 ('b0000000-0000-0000-0000-000000000002'),
 ('b0000000-0000-0000-0000-000000000003');
INSERT INTO mobile_hmac_key_versions(key_version,state) VALUES (1,'active'),(2,'retiring');
INSERT INTO student_contact_index(student_id,key_version,mobile_hmac,mobile_ciphertext,cipher_key_version) VALUES
 ('b0000000-0000-0000-0000-000000000001',1,decode(repeat('11',32),'hex'),'\x01',1),
 ('b0000000-0000-0000-0000-000000000001',2,decode(repeat('12',32),'hex'),'\x02',1),
 ('b0000000-0000-0000-0000-000000000002',1,decode(repeat('22',32),'hex'),'\x03',1),
 ('b0000000-0000-0000-0000-000000000002',2,decode(repeat('23',32),'hex'),decode('03','hex'),1),
 ('b0000000-0000-0000-0000-000000000003',1,decode(repeat('33',32),'hex'),'\x04',1);
INSERT INTO student_ownership(student_id,owner_workspace_id,ownership_generation,lifecycle_state) VALUES
 ('b0000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001',1,'active'),
 ('b0000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000002',1,'active'),
 ('b0000000-0000-0000-0000-000000000003','a0000000-0000-0000-0000-000000000003',1,'active');

-- D-025: a claim has aliases for every active/retiring key version during rotation.
BEGIN;
INSERT INTO enrollment_claims(claim_id,student_id,workspace_id,grade_key,claim_state,ownership_generation)
VALUES ('c0000000-0000-0000-0000-000000000001','b0000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','grade_10','active',1);
INSERT INTO enrollment_claim_identity_aliases(claim_id,grade_key,key_version,mobile_hmac,claim_state) VALUES
 ('c0000000-0000-0000-0000-000000000001','grade_10',1,decode(repeat('11',32),'hex'),'active'),
 ('c0000000-0000-0000-0000-000000000001','grade_10',2,decode(repeat('12',32),'hex'),'active');
COMMIT;

BEGIN;
INSERT INTO enrollment_claims(claim_id,student_id,workspace_id,grade_key,claim_state,ownership_generation)
VALUES ('c0000000-0000-0000-0000-000000000002','b0000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000002','grade_10','active',1);
SELECT expect_error('CP-GU-01 duplicate mobile+grade alias across Workspace rejected','INSERT INTO enrollment_claim_identity_aliases(claim_id,grade_key,key_version,mobile_hmac,claim_state) VALUES (''c0000000-0000-0000-0000-000000000002'',''grade_10'',1,decode(repeat(''11'',32),''hex''),''active'')','23505');
-- Failed alias insertion leaves the deliberately created claim; end it before testing another grade.
UPDATE enrollment_claims SET claim_state='ended', ended_at=now() WHERE claim_id='c0000000-0000-0000-0000-000000000002';
COMMIT;
SELECT expect_error('CP-GU-02 one claim-holding enrollment per student','INSERT INTO enrollment_claims(claim_id,student_id,workspace_id,grade_key,claim_state,ownership_generation) VALUES (gen_random_uuid(),''b0000000-0000-0000-0000-000000000001'',''a0000000-0000-0000-0000-000000000001'',''grade_11'',''active'',1)','23505');
SELECT expect_error('CP-GU-03 unsupported grade rejected','INSERT INTO enrollment_claims(claim_id,student_id,workspace_id,grade_key,claim_state,ownership_generation) VALUES (gen_random_uuid(),''b0000000-0000-0000-0000-000000000003'',''a0000000-0000-0000-0000-000000000003'',''grade 10'',''active'',1)','23514');

-- Same mobile alias in a different grade is permitted by D-025.
BEGIN;
INSERT INTO enrollment_claims(claim_id,student_id,workspace_id,grade_key,claim_state,ownership_generation)
VALUES ('c0000000-0000-0000-0000-000000000003','b0000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000002','grade_11','active',1);
INSERT INTO enrollment_claim_identity_aliases(claim_id,grade_key,key_version,mobile_hmac,claim_state)
VALUES ('c0000000-0000-0000-0000-000000000003','grade_11',1,decode(repeat('11',32),'hex'),'active');
INSERT INTO enrollment_claim_identity_aliases(claim_id,grade_key,key_version,mobile_hmac,claim_state)
VALUES ('c0000000-0000-0000-0000-000000000003','grade_11',2,decode(repeat('23',32),'hex'),'active');
COMMIT;

-- Rotation maintenance gate blocks new claim admission until all active/retiring aliases are verified.
SELECT begin_identity_hmac_rotation();
SELECT expect_error('CP-ROT-01 claim mutation denied during HMAC rotation','INSERT INTO enrollment_claims(claim_id,student_id,workspace_id,grade_key,claim_state,ownership_generation) VALUES (gen_random_uuid(),''b0000000-0000-0000-0000-000000000003'',''a0000000-0000-0000-0000-000000000003'',''grade_12'',''active'',1)','55000');
SELECT complete_identity_hmac_rotation(2);
DO $rotation$ BEGIN
 IF (SELECT maintenance_mode FROM identity_write_gate WHERE singleton=true) THEN RAISE EXCEPTION 'FAIL CP-ROT-02 rotation gate remained enabled'; END IF;
 IF (SELECT count(*) FROM mobile_hmac_key_versions WHERE state IN ('active','retiring'))<>2 THEN RAISE EXCEPTION 'FAIL CP-ROT-03 expected two overlap key versions'; END IF;
 RAISE NOTICE 'PASS CP-ROT-02/03 rotation completion verified and gate reopened';
END $rotation$;
SELECT begin_identity_hmac_rotation();
SELECT retire_identity_hmac_version(1);
DO $retire$ BEGIN
 IF (SELECT state FROM mobile_hmac_key_versions WHERE key_version=1)<>'retired' THEN RAISE EXCEPTION 'FAIL CP-ROT-04 old key version not retired'; END IF;
 IF EXISTS (SELECT 1 FROM enrollment_claim_identity_aliases WHERE key_version=1) THEN RAISE EXCEPTION 'FAIL CP-ROT-05 retired aliases remain'; END IF;
 IF EXISTS (SELECT 1 FROM student_contact_index WHERE key_version=1) THEN RAISE EXCEPTION 'FAIL CP-ROT-06 retired contact HMAC rows remain'; END IF;
 IF (SELECT maintenance_mode FROM identity_write_gate WHERE singleton=true) THEN RAISE EXCEPTION 'FAIL CP-ROT-07 gate remained enabled after retirement'; END IF;
 RAISE NOTICE 'PASS CP-ROT-04..07 old HMAC aliases/index rows purged and gate reopened';
END $retire$;

-- Platform Admin cannot initiate a transfer.
SELECT expect_error('CP-INIT-01 Platform Admin is not an eligible initiator','INSERT INTO transfer_cases(case_id,student_id,source_workspace_id,destination_workspace_id,expected_generation,initiator_kind,state,idempotency_key) VALUES (gen_random_uuid(),''b0000000-0000-0000-0000-000000000002'',''a0000000-0000-0000-0000-000000000002'',''a0000000-0000-0000-0000-000000000001'',1,''platform_admin'',''requested'',''admin-key'')','23514');

-- Idempotency: same key/same hash returns same case; payload mismatch rejects.
DO $$ DECLARE a uuid; b uuid; BEGIN
 a := request_transfer_case_idempotent('idem-1',decode(repeat('aa',32),'hex'),'d0000000-0000-0000-0000-000000000001','b0000000-0000-0000-0000-000000000003','a0000000-0000-0000-0000-000000000003','a0000000-0000-0000-0000-000000000001',1,'guardian');
 b := request_transfer_case_idempotent('idem-1',decode(repeat('aa',32),'hex'),'d0000000-0000-0000-0000-000000000099','b0000000-0000-0000-0000-000000000003','a0000000-0000-0000-0000-000000000003','a0000000-0000-0000-0000-000000000001',1,'guardian');
 IF a<>b THEN RAISE EXCEPTION 'FAIL CP-IDEM-01 same payload did not replay original result'; END IF;
 RAISE NOTICE 'PASS CP-IDEM-01 same key/same payload replayed case %',a;
END $$;
SELECT expect_error('CP-IDEM-02 same key with different payload rejected','SELECT request_transfer_case_idempotent(''idem-1'',decode(repeat(''bb'',32),''hex''),gen_random_uuid(),''b0000000-0000-0000-0000-000000000003'',''a0000000-0000-0000-0000-000000000003'',''a0000000-0000-0000-0000-000000000001'',1,''guardian'')','23505');
SELECT expect_error('CP-IDEM-03 command payload hash is immutable','UPDATE command_log SET payload_hash=decode(repeat(''cc'',32),''hex'') WHERE idempotency_key=''idem-1''','23514');


-- A transfer cannot enter cutover_frozen without freeze/snapshot/destination evidence.
INSERT INTO transfer_cases(case_id,student_id,source_workspace_id,destination_workspace_id,expected_generation,initiator_kind,state,idempotency_key)
VALUES ('d0000000-0000-0000-0000-000000000004','b0000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000001',1,'current_counselor','requested','missing-freeze-evidence');
UPDATE transfer_cases SET state='approvals_pending' WHERE case_id='d0000000-0000-0000-0000-000000000004';
UPDATE transfer_cases SET state='approved' WHERE case_id='d0000000-0000-0000-0000-000000000004';
UPDATE transfer_cases SET state='preflight_ok' WHERE case_id='d0000000-0000-0000-0000-000000000004';
UPDATE transfer_cases SET state='staging' WHERE case_id='d0000000-0000-0000-0000-000000000004';
UPDATE transfer_cases SET state='staged_verified' WHERE case_id='d0000000-0000-0000-0000-000000000004';
SELECT expect_error('CP-CUTOVER-01 cutover_frozen requires source freeze + final snapshot + destination validation','UPDATE transfer_cases SET state=''cutover_frozen'' WHERE case_id=''d0000000-0000-0000-0000-000000000004''','23514');

-- Transfer test for student 1.
INSERT INTO transfer_cases(case_id,student_id,source_workspace_id,destination_workspace_id,expected_generation,initiator_kind,state,idempotency_key)
VALUES ('d0000000-0000-0000-0000-000000000002','b0000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000002',1,'guardian','requested','transfer-1');
UPDATE transfer_cases SET state='approvals_pending' WHERE case_id='d0000000-0000-0000-0000-000000000002';
UPDATE transfer_cases SET state='approved' WHERE case_id='d0000000-0000-0000-0000-000000000002';
UPDATE transfer_cases SET state='preflight_ok' WHERE case_id='d0000000-0000-0000-0000-000000000002';
UPDATE transfer_cases SET state='staging' WHERE case_id='d0000000-0000-0000-0000-000000000002';
UPDATE transfer_cases SET state='staged_verified' WHERE case_id='d0000000-0000-0000-0000-000000000002';
UPDATE transfer_cases SET source_freeze_token='freeze-1',source_frozen_at=now(),final_snapshot_ref='snapshot-1',snapshot_manifest_hash=decode(repeat('aa',32),'hex'),destination_validation_ref='validation-1',destination_validated_at=now() WHERE case_id='d0000000-0000-0000-0000-000000000002';
UPDATE transfer_cases SET state='cutover_frozen' WHERE case_id='d0000000-0000-0000-0000-000000000002';
INSERT INTO transfer_approvals(approval_id,case_id,approval_kind,evidence_ref,approver_ref,authn_event_ref,authority_snapshot,verified_at)
VALUES
 (gen_random_uuid(),'d0000000-0000-0000-0000-000000000002','guardian_consent','ev-g1','guardian-subject','authn-g1','{"relationship":"verified","legal_authority":"verified","scope":"transfer"}',now()),
 (gen_random_uuid(),'d0000000-0000-0000-0000-000000000002','destination_acceptance','ev-d1','destination-subject','authn-d1','{"workspace":"destination","permission":"transfer_accept"}',now());
SELECT expect_error('CP-APP-01 missing prior counselor fee confirmation blocks switch','SELECT switch_student_ownership(''d0000000-0000-0000-0000-000000000002'')','23514');
INSERT INTO transfer_approvals(approval_id,case_id,approval_kind,evidence_ref,approver_ref,authn_event_ref,authority_snapshot,verified_at)
VALUES (gen_random_uuid(),'d0000000-0000-0000-0000-000000000002','fee_confirmation','ev-f1','prior-counselor-subject','authn-f1','{"source_assignment":"verified","fee_confirmation":true}',now());
SELECT expect_error('CP-APP-02 approval evidence cannot be rewritten','UPDATE transfer_approvals SET approver_ref=''forged-subject'' WHERE case_id=''d0000000-0000-0000-0000-000000000002'' AND approval_kind=''guardian_consent''','23514');

-- Stale generation is rejected before any partial write.
UPDATE student_ownership SET ownership_generation=2 WHERE student_id='b0000000-0000-0000-0000-000000000001';
SELECT expect_error('CP-FENCE-01 stale generation rejected','SELECT switch_student_ownership(''d0000000-0000-0000-0000-000000000002'')','23514');
UPDATE student_ownership SET ownership_generation=1 WHERE student_id='b0000000-0000-0000-0000-000000000001';

DO $$ DECLARE g bigint; BEGIN
 g:=switch_student_ownership('d0000000-0000-0000-0000-000000000002');
 IF g<>2 THEN RAISE EXCEPTION 'FAIL CP-SWITCH-01 expected generation 2, got %',g; END IF;
 IF (SELECT owner_workspace_id FROM student_ownership WHERE student_id='b0000000-0000-0000-0000-000000000001')<>'a0000000-0000-0000-0000-000000000002' THEN RAISE EXCEPTION 'FAIL CP-SWITCH-02 owner mismatch'; END IF;
 IF (SELECT count(*) FROM ownership_history WHERE case_id='d0000000-0000-0000-0000-000000000002' AND ownership_generation=2)<>1 THEN RAISE EXCEPTION 'FAIL CP-SWITCH-03 history missing'; END IF;
 IF (SELECT count(*) FROM outbox_events WHERE case_id='d0000000-0000-0000-0000-000000000002' AND event_type='ownership_switched')<>1 THEN RAISE EXCEPTION 'FAIL CP-SWITCH-04 outbox missing'; END IF;
 RAISE NOTICE 'PASS CP-SWITCH-01 atomic owner/generation/claim/history/outbox switch';
END $$;
SELECT expect_error('CP-OUTBOX-01 outbox payload cannot be rewritten','UPDATE outbox_events SET payload=''{"tampered":true}''::jsonb WHERE case_id=''d0000000-0000-0000-0000-000000000002''','23514');
SELECT expect_error('CP-STATE-01 cancellation after ownership switch forbidden','UPDATE transfer_cases SET state=''cancelled'' WHERE case_id=''d0000000-0000-0000-0000-000000000002''','23514');
UPDATE transfer_cases SET state='projections_finalizing' WHERE case_id='d0000000-0000-0000-0000-000000000002';
UPDATE transfer_cases SET state='completed' WHERE case_id='d0000000-0000-0000-0000-000000000002';

-- Stale source Workspace must not switch a student whose owner has changed.
INSERT INTO transfer_cases(case_id,student_id,source_workspace_id,destination_workspace_id,expected_generation,initiator_kind,state,idempotency_key)
VALUES ('d0000000-0000-0000-0000-000000000003','b0000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000003',2,'destination_workspace','requested','stale-source');
UPDATE transfer_cases SET state='approvals_pending' WHERE case_id='d0000000-0000-0000-0000-000000000003';
UPDATE transfer_cases SET state='approved' WHERE case_id='d0000000-0000-0000-0000-000000000003';
UPDATE transfer_cases SET state='preflight_ok' WHERE case_id='d0000000-0000-0000-0000-000000000003';
UPDATE transfer_cases SET state='staging' WHERE case_id='d0000000-0000-0000-0000-000000000003';
UPDATE transfer_cases SET state='staged_verified' WHERE case_id='d0000000-0000-0000-0000-000000000003';
UPDATE transfer_cases SET source_freeze_token='freeze-3',source_frozen_at=now(),final_snapshot_ref='snapshot-3',snapshot_manifest_hash=decode(repeat('bb',32),'hex'),destination_validation_ref='validation-3',destination_validated_at=now() WHERE case_id='d0000000-0000-0000-0000-000000000003';
UPDATE transfer_cases SET state='cutover_frozen' WHERE case_id='d0000000-0000-0000-0000-000000000003';
INSERT INTO transfer_approvals(approval_id,case_id,approval_kind,evidence_ref,approver_ref,authn_event_ref,authority_snapshot,verified_at)
VALUES
 (gen_random_uuid(),'d0000000-0000-0000-0000-000000000003','guardian_consent','ev-g3','guardian3','authn-g3','{"relationship":"verified"}',now()),
 (gen_random_uuid(),'d0000000-0000-0000-0000-000000000003','fee_confirmation','ev-f3','counselor3','authn-f3','{"source_assignment":"verified"}',now()),
 (gen_random_uuid(),'d0000000-0000-0000-0000-000000000003','destination_acceptance','ev-d3','dest3','authn-d3','{"permission":"verified"}',now());
SELECT expect_error('CP-FENCE-02 stale source Workspace rejected','SELECT switch_student_ownership(''d0000000-0000-0000-0000-000000000003'')','23514');

DO $$ BEGIN RAISE NOTICE '=== CONTROL PLANE REGRESSION SUITE COMPLETED (synthetic) ==='; END $$;
