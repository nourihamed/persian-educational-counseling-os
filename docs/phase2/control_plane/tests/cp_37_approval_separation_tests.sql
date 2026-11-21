-- PD-2026-11-13-C — transfer approval separation of duties, the DISABLED source_destination_owner
-- exception, the approval-recording command and its dedicated executor identity. Synthetic only (D-014).
-- Run on a FRESH DB after cp_01, cp_05, cp_07, cp_02, cp_03, cp_04, cp_06, cp_11.
--
-- Scope: the database checks the SHAPE, SIDE, SEPARATION and freshness of recorded approval evidence, and
-- which identity may record it. It does NOT verify that an assertion is authentic, that a person truly holds
-- guardian/legal authority (Q-007), or that any fee was actually paid.
\set ON_ERROR_STOP on
CREATE OR REPLACE FUNCTION sx_err(label text, stmt text, want text, want_msg text DEFAULT '')
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
 ('a3700000-0000-0000-0000-000000000001','organization','active'),
 ('a3700000-0000-0000-0000-000000000002','organization','active'),
 ('a3700000-0000-0000-0000-000000000003','organization','active');
INSERT INTO mobile_encryption_key_versions(key_version,state,key_manager_ref) VALUES (1,'active','kms://synthetic/enc-v1');
INSERT INTO mobile_hmac_key_versions(key_version,state) VALUES (1,'active');
SET SESSION AUTHORIZATION cp_identity_admission_executor;
SELECT admit_student_identity_claim('sep-admit',decode(repeat('37',32),'hex'),'b3700000-0000-0000-0000-000000000001','c3700000-0000-0000-0000-000000000001','a3700000-0000-0000-0000-000000000001','grade_10',decode('3701','hex'),1,
 '[{"key_version":1,"mobile_hmac_hex":"3737373737373737373737373737373737373737373737373737373737373737"}]'::jsonb);
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION cp_transfer_executor;
SELECT request_transfer_case_idempotent('sep-case',decode(repeat('3c',32),'hex'),'d3700000-0000-0000-0000-000000000001','b3700000-0000-0000-0000-000000000001','a3700000-0000-0000-0000-000000000001','a3700000-0000-0000-0000-000000000002',1,'guardian');
RESET SESSION AUTHORIZATION;
UPDATE transfer_cases SET state='approvals_pending' WHERE case_id='d3700000-0000-0000-0000-000000000001';

-- ============================ only the dedicated executor may record evidence ============================
SELECT sx_err('SEP-01 superuser/table owner cannot call the approval command',
 $q$SELECT record_transfer_approval(gen_random_uuid(),gen_random_uuid(),sha256('n0'::bytea),'d3700000-0000-0000-0000-000000000001','guardian_consent','ev-0','guardian-x','authn-0','{}'::jsonb,now(),NULL)$q$,'42501','approval executor');
SET SESSION AUTHORIZATION cp_runtime;
SELECT sx_err('SEP-02 the general runtime identity cannot write approval rows directly',
 $q$INSERT INTO transfer_approvals(approval_id,assertion_id,nonce_digest,case_id,approval_kind,evidence_ref,approver_ref,authn_event_ref,authority_snapshot,verified_at) VALUES (gen_random_uuid(),gen_random_uuid(),sha256('n1'::bytea),'d3700000-0000-0000-0000-000000000001','guardian_consent','ev-r','guardian-r','authn-r','{}'::jsonb,now())$q$,'42501');
SELECT sx_err('SEP-03 the general runtime identity cannot call the approval command',
 $q$SELECT record_transfer_approval(gen_random_uuid(),gen_random_uuid(),sha256('n2'::bytea),'d3700000-0000-0000-0000-000000000001','guardian_consent','ev-r2','guardian-r','authn-r2','{}'::jsonb,now(),NULL)$q$,'42501');
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION cp_transfer_executor;
SELECT sx_err('SEP-04 the ownership-switch executor cannot record its own approvals',
 $q$SELECT record_transfer_approval(gen_random_uuid(),gen_random_uuid(),sha256('n3'::bytea),'d3700000-0000-0000-0000-000000000001','guardian_consent','ev-t','guardian-t','authn-t','{}'::jsonb,now(),NULL)$q$,'42501');
SELECT sx_err('SEP-05 the ownership-switch executor cannot write approval rows directly',
 $q$INSERT INTO transfer_approvals(approval_id,assertion_id,nonce_digest,case_id,approval_kind,evidence_ref,approver_ref,authn_event_ref,authority_snapshot,verified_at) VALUES (gen_random_uuid(),gen_random_uuid(),sha256('n4'::bytea),'d3700000-0000-0000-0000-000000000001','guardian_consent','ev-t2','guardian-t','authn-t2','{}'::jsonb,now())$q$,'42501');
RESET SESSION AUTHORIZATION;

-- ============================ recording, replay and side binding ============================
SET SESSION AUTHORIZATION cp_transfer_approval_executor;
DO $t$ DECLARE r text; BEGIN
  r := record_transfer_approval('e3700000-0000-0000-0000-000000000001','f3700000-0000-0000-0000-000000000001',sha256('sep-g'::bytea),
       'd3700000-0000-0000-0000-000000000001','guardian_consent','ev-g','guardian-subject','authn-g','{"relationship":"verified"}'::jsonb,now(),NULL);
  IF r<>'recorded' THEN RAISE EXCEPTION 'FAIL SEP-06: %',r; END IF;
  RAISE NOTICE 'PASS SEP-06 the approval executor recorded guardian consent';
  r := record_transfer_approval('e3700000-0000-0000-0000-000000000001','f3700000-0000-0000-0000-000000000001',sha256('sep-g'::bytea),
       'd3700000-0000-0000-0000-000000000001','guardian_consent','ev-g','guardian-subject','authn-g','{"relationship":"verified"}'::jsonb,now(),NULL);
  IF r<>'replayed' THEN RAISE EXCEPTION 'FAIL SEP-07: %',r; END IF;
  RAISE NOTICE 'PASS SEP-07 the same assertion replayed unchanged is idempotent';
END $t$;
SELECT sx_err('SEP-08 the same assertion with different content is rejected',
 $q$SELECT record_transfer_approval('e3700000-0000-0000-0000-0000000000ff','f3700000-0000-0000-0000-000000000001',sha256('sep-g'::bytea),'d3700000-0000-0000-0000-000000000001','guardian_consent','ev-g','OTHER-subject','authn-g','{"relationship":"verified"}'::jsonb,now(),NULL)$q$,'23505','different content');
SELECT sx_err('SEP-09 fee confirmation recorded for the destination Workspace is rejected',
 $q$SELECT record_transfer_approval(gen_random_uuid(),gen_random_uuid(),sha256('sep-f-bad'::bytea),'d3700000-0000-0000-0000-000000000001','fee_confirmation','ev-f-bad','counselor-subject','authn-f-bad','{"workspace_id":"a3700000-0000-0000-0000-000000000002"}'::jsonb,now(),NULL)$q$,'23514','SOURCE Workspace');
SELECT sx_err('SEP-10 destination acceptance recorded for a third Workspace is rejected',
 $q$SELECT record_transfer_approval(gen_random_uuid(),gen_random_uuid(),sha256('sep-d-bad'::bytea),'d3700000-0000-0000-0000-000000000001','destination_acceptance','ev-d-bad','dest-subject','authn-d-bad','{"workspace_id":"a3700000-0000-0000-0000-000000000003"}'::jsonb,now(),NULL)$q$,'23514','DESTINATION Workspace');
SELECT sx_err('SEP-11 evidence that is already expired at recording time is rejected',
 $q$SELECT record_transfer_approval(gen_random_uuid(),gen_random_uuid(),sha256('sep-exp'::bytea),'d3700000-0000-0000-0000-000000000001','fee_confirmation','ev-exp','counselor-subject','authn-exp','{"workspace_id":"a3700000-0000-0000-0000-000000000001"}'::jsonb,now()-interval '2 hours',now()-interval '1 hour')$q$,'23514','already expired');
SELECT sx_err('SEP-12 evidence verified in the future is rejected',
 $q$SELECT record_transfer_approval(gen_random_uuid(),gen_random_uuid(),sha256('sep-fut'::bytea),'d3700000-0000-0000-0000-000000000001','fee_confirmation','ev-fut','counselor-subject','authn-fut','{"workspace_id":"a3700000-0000-0000-0000-000000000001"}'::jsonb,now()+interval '1 hour',NULL)$q$,'23514','in the future');
-- The guardian who already consented cannot also confirm the source fee.
SELECT sx_err('SEP-12b the guardian approver cannot also record the fee confirmation',
 $q$SELECT record_transfer_approval(gen_random_uuid(),gen_random_uuid(),sha256('sep-f-same'::bytea),'d3700000-0000-0000-0000-000000000001','fee_confirmation','ev-f-same','guardian-subject','authn-f-same','{"workspace_id":"a3700000-0000-0000-0000-000000000001"}'::jsonb,now(),NULL)$q$,'23514','cannot satisfy incompatible approval kinds');
DO $t$ BEGIN
  PERFORM record_transfer_approval('e3700000-0000-0000-0000-000000000002','f3700000-0000-0000-0000-000000000002',sha256('sep-f'::bytea),
    'd3700000-0000-0000-0000-000000000001','fee_confirmation','ev-f','counselor-subject','authn-f','{"workspace_id":"a3700000-0000-0000-0000-000000000001"}'::jsonb,now(),NULL);
  RAISE NOTICE 'PASS SEP-13 fee confirmation recorded for the source Workspace of the case';
END $t$;

-- ============================ separation of duties ============================
SELECT sx_err('SEP-14 the same person cannot also give destination acceptance (default separation)',
 $q$SELECT record_transfer_approval(gen_random_uuid(),gen_random_uuid(),sha256('sep-d-same'::bytea),'d3700000-0000-0000-0000-000000000001','destination_acceptance','ev-d-same','counselor-subject','authn-d-same','{"workspace_id":"a3700000-0000-0000-0000-000000000002"}'::jsonb,now(),NULL)$q$,'23514','cannot satisfy incompatible approval kinds');
DO $t$ BEGIN
  PERFORM record_transfer_approval('e3700000-0000-0000-0000-000000000003','f3700000-0000-0000-0000-000000000003',sha256('sep-d'::bytea),
    'd3700000-0000-0000-0000-000000000001','destination_acceptance','ev-d','destination-subject','authn-d','{"workspace_id":"a3700000-0000-0000-0000-000000000002"}'::jsonb,now(),NULL);
  RAISE NOTICE 'PASS SEP-16 a DIFFERENT person completed the third approval kind';
END $t$;
RESET SESSION AUTHORIZATION;
DO $t$ BEGIN
  IF (SELECT count(DISTINCT approval_kind) FROM transfer_approvals_current WHERE case_id='d3700000-0000-0000-0000-000000000001')<>3
     OR (SELECT count(DISTINCT approver_ref) FROM transfer_approvals_current WHERE case_id='d3700000-0000-0000-0000-000000000001')<>3 THEN
    RAISE EXCEPTION 'FAIL SEP-17';
  END IF;
  RAISE NOTICE 'PASS SEP-17 the three cumulative approvals are held by three distinct approvers';
END $t$;

-- ============================ the deferred exception stays disabled ============================
DO $t$ BEGIN
  IF (SELECT enabled FROM transfer_approval_conflict_exceptions WHERE exception_case='source_destination_owner')<>false THEN
    RAISE EXCEPTION 'FAIL SEP-18 the deferred exception is enabled';
  END IF;
  RAISE NOTICE 'PASS SEP-18 the source_destination_owner exception is present and disabled';
END $t$;
SELECT sx_err('SEP-19 the deferred exception cannot be enabled by any DML, even by the table owner',
 $q$UPDATE transfer_approval_conflict_exceptions SET enabled=true WHERE exception_case='source_destination_owner'$q$,'23514');
SELECT sx_err('SEP-20 an enabled exception row cannot be inserted',
 $q$INSERT INTO transfer_approval_conflict_exceptions(exception_case,enabled) VALUES ('source_destination_owner',true)$q$,'23514');
SELECT sx_err('SEP-21 no other exception case can be introduced by DML',
 $q$INSERT INTO transfer_approval_conflict_exceptions(exception_case) VALUES ('platform_admin_override')$q$,'23514');
SET SESSION AUTHORIZATION cp_transfer_approval_executor;
SELECT sx_err('SEP-22 the approval executor cannot read or change the exception policy',
 $q$UPDATE transfer_approval_conflict_exceptions SET enabled=true$q$,'42501');
RESET SESSION AUTHORIZATION;

-- ============================ revocation, idempotency and post-switch immutability ============================
SET SESSION AUTHORIZATION cp_transfer_approval_executor;
DO $t$ DECLARE r text; BEGIN
  r := revoke_transfer_approval('a3800000-0000-0000-0000-000000000001','e3700000-0000-0000-0000-000000000003','revoker-subject','authn-rev','withdrawn');
  IF r<>'revoked' THEN RAISE EXCEPTION 'FAIL SEP-23: %',r; END IF;
  r := revoke_transfer_approval('a3800000-0000-0000-0000-000000000001','e3700000-0000-0000-0000-000000000003','revoker-subject','authn-rev','withdrawn');
  IF r<>'replayed' THEN RAISE EXCEPTION 'FAIL SEP-24: %',r; END IF;
  RAISE NOTICE 'PASS SEP-23/24 revocation is recorded once and replays idempotently';
END $t$;
SELECT sx_err('SEP-25 a second, different revocation of the same approval is rejected',
 $q$SELECT revoke_transfer_approval(gen_random_uuid(),'e3700000-0000-0000-0000-000000000003','other-subject','authn-rev2','other')$q$,'23505');
RESET SESSION AUTHORIZATION;
DO $t$ BEGIN
  IF (SELECT count(DISTINCT approval_kind) FROM transfer_approvals_current WHERE case_id='d3700000-0000-0000-0000-000000000001')<>2 THEN
    RAISE EXCEPTION 'FAIL SEP-26';
  END IF;
  RAISE NOTICE 'PASS SEP-26 the revoked approval left history intact but is no longer current';
END $t$;
-- With one approval revoked the cutover must fail closed.
UPDATE transfer_cases SET state='approved' WHERE case_id='d3700000-0000-0000-0000-000000000001';
UPDATE transfer_cases SET state='preflight_ok' WHERE case_id='d3700000-0000-0000-0000-000000000001';
UPDATE transfer_cases SET state='staging' WHERE case_id='d3700000-0000-0000-0000-000000000001';
UPDATE transfer_cases SET state='staged_verified' WHERE case_id='d3700000-0000-0000-0000-000000000001';
UPDATE transfer_cases SET source_freeze_token='freeze-sep',source_frozen_at=now(),final_snapshot_ref='snapshot-sep',final_snapshot_at=now(),snapshot_manifest_hash=decode(repeat('37',32),'hex'),destination_validation_ref='validation-sep',destination_validated_at=now() WHERE case_id='d3700000-0000-0000-0000-000000000001';
UPDATE transfer_cases SET state='cutover_frozen' WHERE case_id='d3700000-0000-0000-0000-000000000001';
SET SESSION AUTHORIZATION cp_transfer_executor;
SELECT sx_err('SEP-27 the ownership switch fails closed while one approval is revoked',
 $q$SELECT switch_student_ownership('d3700000-0000-0000-0000-000000000001')$q$,'23514','of 3 required approvals');
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION cp_transfer_approval_executor;
SELECT sx_err('SEP-28 a cutover-frozen case no longer accepts new approval evidence',
 $q$SELECT record_transfer_approval(gen_random_uuid(),gen_random_uuid(),sha256('sep-late'::bytea),'d3700000-0000-0000-0000-000000000001','destination_acceptance','ev-late','late-subject','authn-late','{"workspace_id":"a3700000-0000-0000-0000-000000000002"}'::jsonb,now(),NULL)$q$,'23514','no longer accepts approval evidence');
RESET SESSION AUTHORIZATION;
DO $t$ BEGIN
  IF (SELECT ownership_generation FROM student_ownership WHERE student_id='b3700000-0000-0000-0000-000000000001')<>1
     OR (SELECT owner_workspace_id FROM student_ownership WHERE student_id='b3700000-0000-0000-0000-000000000001')<>'a3700000-0000-0000-0000-000000000001' THEN
    RAISE EXCEPTION 'FAIL SEP-29 ownership moved without three current approvals';
  END IF;
  RAISE NOTICE 'PASS SEP-29 ownership and generation are unchanged after every refused path';
END $t$;
SELECT 'TRANSFER APPROVAL SEPARATION TESTS COMPLETED (SEP-01..SEP-29 (SEP-15 merged into SEP-12b))' AS result;
