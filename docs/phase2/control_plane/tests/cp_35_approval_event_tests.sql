-- CONTROL PLANE approval-event tests (synthetic only, D-014). Run AFTER cp_10_constraint_tests.sql on the same DB.
-- After cp_10: student b0..01 is owned by Workspace a0..02 at generation 2; case d0..03 is open (stale source).
-- These tests leave case d0..04 frozen with three CURRENT approvals for cp_36_approval_revocation_race.sh.
\set ON_ERROR_STOP on
CREATE OR REPLACE FUNCTION ax_err(label text, stmt text, want text, want_msg text DEFAULT '')
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
CREATE OR REPLACE FUNCTION ax_approval(p_id uuid, p_case uuid, p_kind text, p_tag text,
  p_verified timestamptz DEFAULT now(), p_until timestamptz DEFAULT NULL) RETURNS void LANGUAGE sql AS $t$
  INSERT INTO transfer_approvals(approval_id,assertion_id,nonce_digest,case_id,approval_kind,evidence_ref,approver_ref,authn_event_ref,authority_snapshot,verified_at,valid_until)
  VALUES (p_id, gen_random_uuid(), sha256(convert_to('nonce-'||p_tag,'UTF8')), p_case, p_kind, 'ev-'||p_tag, 'subject-'||p_tag, 'authn-'||p_tag, '{"synthetic":true}'::jsonb, p_verified, p_until);
$t$;

-- Close the stale case and open a valid one for the same student (W2 -> W3, expected generation 2).
-- Legal pre-switch closure of the frozen stale case: recovery -> manual intervention -> cancelled with recorded unfreeze.
UPDATE transfer_cases SET state='failed_recoverable' WHERE case_id='d0000000-0000-0000-0000-000000000003';
UPDATE transfer_cases SET state='manual_intervention_pre_switch' WHERE case_id='d0000000-0000-0000-0000-000000000003';
UPDATE transfer_cases SET state='cancelled', source_unfrozen_at=now() WHERE case_id='d0000000-0000-0000-0000-000000000003';
INSERT INTO transfer_cases(case_id,student_id,source_workspace_id,destination_workspace_id,expected_generation,initiator_kind,state,idempotency_key)
VALUES ('d0000000-0000-0000-0000-0000000000a4','b0000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000003',2,'guardian','requested','approval-events');
UPDATE transfer_cases SET state='approvals_pending' WHERE case_id='d0000000-0000-0000-0000-0000000000a4';
UPDATE transfer_cases SET state='approved' WHERE case_id='d0000000-0000-0000-0000-0000000000a4';
UPDATE transfer_cases SET state='preflight_ok' WHERE case_id='d0000000-0000-0000-0000-0000000000a4';
UPDATE transfer_cases SET state='staging' WHERE case_id='d0000000-0000-0000-0000-0000000000a4';
UPDATE transfer_cases SET state='staged_verified' WHERE case_id='d0000000-0000-0000-0000-0000000000a4';
UPDATE transfer_cases SET source_freeze_token='freeze-4',source_frozen_at=now(),final_snapshot_ref='snapshot-4',final_snapshot_at=now(),snapshot_manifest_hash=decode(repeat('cc',32),'hex'),destination_validation_ref='validation-4',destination_validated_at=now() WHERE case_id='d0000000-0000-0000-0000-0000000000a4';
UPDATE transfer_cases SET state='cutover_frozen' WHERE case_id='d0000000-0000-0000-0000-0000000000a4';

SELECT ax_approval('e0000000-0000-0000-0000-000000000041','d0000000-0000-0000-0000-0000000000a4','guardian_consent','g4');
SELECT ax_approval('e0000000-0000-0000-0000-000000000042','d0000000-0000-0000-0000-0000000000a4','fee_confirmation','f4');
SELECT ax_approval('e0000000-0000-0000-0000-000000000043','d0000000-0000-0000-0000-0000000000a4','destination_acceptance','d4');

SELECT ax_err('APR-01 a second CURRENT approval of the same kind is rejected',
 $q$SELECT ax_approval(gen_random_uuid(),'d0000000-0000-0000-0000-0000000000a4','fee_confirmation','f4-dup')$q$,'23505','current fee_confirmation approval already exists');
SELECT ax_err('APR-04 an approval event cannot be deleted',
 $q$DELETE FROM transfer_approvals WHERE approval_id='e0000000-0000-0000-0000-000000000042'$q$,'23514','append-only');
SELECT ax_err('APR-05 an approval event cannot be edited',
 $q$UPDATE transfer_approvals SET valid_until=now()+interval '10 years' WHERE approval_id='e0000000-0000-0000-0000-000000000042'$q$,'23514','append-only');

-- Revocation is a separate event.
INSERT INTO transfer_approval_revocations(revocation_id,approval_id,actor_ref,authn_event_ref,reason_code)
VALUES ('e1000000-0000-0000-0000-000000000042','e0000000-0000-0000-0000-000000000042','subject-f4','authn-f4-revoke','synthetic_reason');
SELECT ax_err('APR-06 a revoked approval does not satisfy the switch (2 of 3)',
 $q$SELECT switch_student_ownership('d0000000-0000-0000-0000-0000000000a4')$q$,'23514','2 of 3');
SELECT ax_err('APR-07 an approval can be revoked only once',
 $q$INSERT INTO transfer_approval_revocations(revocation_id,approval_id,actor_ref,authn_event_ref,reason_code) VALUES (gen_random_uuid(),'e0000000-0000-0000-0000-000000000042','x','y','z')$q$,'23505');
SELECT ax_err('APR-08 a revocation event cannot be deleted (un-revoke)',
 $q$DELETE FROM transfer_approval_revocations WHERE revocation_id='e1000000-0000-0000-0000-000000000042'$q$,'23514','append-only');
SELECT ax_err('APR-09 a revocation event cannot be edited',
 $q$UPDATE transfer_approval_revocations SET reason_code='changed' WHERE revocation_id='e1000000-0000-0000-0000-000000000042'$q$,'23514','append-only');
SELECT ax_err('APR-10 a revocation requires actor, authentication event and reason',
 $q$INSERT INTO transfer_approval_revocations(revocation_id,approval_id,actor_ref,authn_event_ref,reason_code) VALUES (gen_random_uuid(),'e0000000-0000-0000-0000-000000000041','',' ','r')$q$,'23514');

-- Replay guards, exercised while the fee confirmation is revoked (so the one-current rule is not what rejects them).
SELECT ax_err('APR-02 an assertion id cannot be used for two approvals',
 $q$INSERT INTO transfer_approvals(approval_id,assertion_id,nonce_digest,case_id,approval_kind,evidence_ref,approver_ref,authn_event_ref,authority_snapshot,verified_at)
    SELECT gen_random_uuid(), assertion_id, sha256('other'::bytea), 'd0000000-0000-0000-0000-0000000000a4', approval_kind, 'ev-reuse', approver_ref, authn_event_ref, authority_snapshot, now()
      FROM transfer_approvals WHERE approval_id='e0000000-0000-0000-0000-000000000042'$q$,'23505','assertion_id');
SELECT ax_err('APR-03 a nonce cannot be replayed for another approval',
 $q$INSERT INTO transfer_approvals(approval_id,assertion_id,nonce_digest,case_id,approval_kind,evidence_ref,approver_ref,authn_event_ref,authority_snapshot,verified_at)
    SELECT gen_random_uuid(), gen_random_uuid(), nonce_digest, 'd0000000-0000-0000-0000-0000000000a4', approval_kind, 'ev-replay', approver_ref, authn_event_ref, authority_snapshot, now()
      FROM transfer_approvals WHERE approval_id='e0000000-0000-0000-0000-000000000042'$q$,'23505','nonce_digest');

-- Replacement approval after revocation: a NEW event; the revoked one stays in history.
SELECT ax_approval('e0000000-0000-0000-0000-000000000044','d0000000-0000-0000-0000-0000000000a4','fee_confirmation','f4-replacement');
DO $t$ BEGIN
  IF (SELECT count(*) FROM transfer_approvals WHERE case_id='d0000000-0000-0000-0000-0000000000a4' AND approval_kind='fee_confirmation')<>2
     OR (SELECT count(*) FROM transfer_approvals_current WHERE case_id='d0000000-0000-0000-0000-0000000000a4' AND approval_kind='fee_confirmation')<>1
     OR (SELECT approval_id FROM transfer_approvals_current WHERE case_id='d0000000-0000-0000-0000-0000000000a4' AND approval_kind='fee_confirmation')<>'e0000000-0000-0000-0000-000000000044' THEN
    RAISE EXCEPTION 'FAIL APR-11';
  END IF;
  RAISE NOTICE 'PASS APR-11 replacement recorded as a new event; revoked approval preserved; exactly one current';
END $t$;

-- Expiry: an expired approval is not current and does not block a replacement (no revocation needed).
INSERT INTO transfer_approval_revocations(revocation_id,approval_id,actor_ref,authn_event_ref,reason_code)
VALUES (gen_random_uuid(),'e0000000-0000-0000-0000-000000000043','subject-d4','authn-d4-revoke','synthetic_reason');
SELECT ax_approval('e0000000-0000-0000-0000-000000000045','d0000000-0000-0000-0000-0000000000a4','destination_acceptance','d4-expired', now()-interval '2 hours', now()-interval '1 hour');
SELECT ax_err('APR-12 an expired approval does not satisfy the switch (2 of 3)',
 $q$SELECT switch_student_ownership('d0000000-0000-0000-0000-0000000000a4')$q$,'23514','2 of 3');
SELECT ax_approval('e0000000-0000-0000-0000-000000000046','d0000000-0000-0000-0000-0000000000a4','destination_acceptance','d4-replacement');
DO $t$ BEGIN
  IF (SELECT count(DISTINCT approval_kind) FROM transfer_approvals_current WHERE case_id='d0000000-0000-0000-0000-0000000000a4')<>3 THEN RAISE EXCEPTION 'FAIL APR-13'; END IF;
  IF (SELECT owner_workspace_id FROM student_ownership WHERE student_id='b0000000-0000-0000-0000-000000000001')<>'a0000000-0000-0000-0000-000000000002' THEN RAISE EXCEPTION 'FAIL APR-13 owner changed'; END IF;
  RAISE NOTICE 'PASS APR-13 three current approvals after replacements; ownership unchanged by rejected switches';
END $t$;
DO $t$ BEGIN RAISE NOTICE '=== CONTROL PLANE APPROVAL EVENT TESTS COMPLETED (synthetic) ==='; END $t$;
