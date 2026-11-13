-- Control Plane commands called by their REAL executor roles (not superuser). Synthetic only (D-014).
-- Run on a FRESH DB after cp_01, cp_05, cp_07, cp_02, cp_03, cp_04, cp_06.
-- Regression for a defect found on 2026-11-13: deferred alias-coverage triggers ran at COMMIT as the calling
-- executor, which has no table access, so every command failed for its own executor. Earlier suites ran as
-- superuser and could not see it.
\set ON_ERROR_STOP on
INSERT INTO workspaces(workspace_id,workspace_type,status) VALUES
 ('a4500000-0000-0000-0000-000000000001','organization','active'),
 ('a4500000-0000-0000-0000-000000000002','organization','active');
INSERT INTO mobile_encryption_key_versions(key_version,state,key_manager_ref) VALUES (1,'active','kms://synthetic/enc-v1');
INSERT INTO mobile_hmac_key_versions(key_version,state) VALUES (1,'active'),(2,'retiring');

-- EXE-01: initial admission as cp_identity_admission_executor (own transaction, real COMMIT).
SET SESSION AUTHORIZATION cp_identity_admission_executor;
SELECT admit_student_identity_claim('exe-admit',decode(repeat('0e',32),'hex'),'b4500000-0000-0000-0000-000000000001','c4500000-0000-0000-0000-000000000001','a4500000-0000-0000-0000-000000000001','grade_10',decode('ee01','hex'),1,
 '[{"key_version":1,"mobile_hmac_hex":"e1e1e1e1e1e1e1e1e1e1e1e1e1e1e1e1e1e1e1e1e1e1e1e1e1e1e1e1e1e1e1e1"},{"key_version":2,"mobile_hmac_hex":"e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2"}]'::jsonb);
RESET SESSION AUTHORIZATION;
DO $t$ BEGIN
  IF (SELECT count(*) FROM enrollment_claim_identity_aliases WHERE claim_id='c4500000-0000-0000-0000-000000000001' AND claim_state='active')<>2
     OR NOT EXISTS (SELECT 1 FROM student_ownership WHERE student_id='b4500000-0000-0000-0000-000000000001' AND ownership_generation=1) THEN
    RAISE EXCEPTION 'FAIL EXE-01';
  END IF;
  RAISE NOTICE 'PASS EXE-01 initial admission committed when called by cp_identity_admission_executor';
END $t$;

-- EXE-02: ownership switch as cp_transfer_executor. Case evidence and approvals are staged by the owner (test fixture).
SET SESSION AUTHORIZATION cp_transfer_executor;
SELECT request_transfer_case_idempotent('exe-case',decode(repeat('0c',32),'hex'),'d4500000-0000-0000-0000-000000000001','b4500000-0000-0000-0000-000000000001','a4500000-0000-0000-0000-000000000001','a4500000-0000-0000-0000-000000000002',1,'guardian');
RESET SESSION AUTHORIZATION;
UPDATE transfer_cases SET state='approvals_pending' WHERE case_id='d4500000-0000-0000-0000-000000000001';
UPDATE transfer_cases SET state='approved' WHERE case_id='d4500000-0000-0000-0000-000000000001';
UPDATE transfer_cases SET state='preflight_ok' WHERE case_id='d4500000-0000-0000-0000-000000000001';
UPDATE transfer_cases SET state='staging' WHERE case_id='d4500000-0000-0000-0000-000000000001';
UPDATE transfer_cases SET state='staged_verified' WHERE case_id='d4500000-0000-0000-0000-000000000001';
UPDATE transfer_cases SET source_freeze_token='freeze-e',source_frozen_at=now(),final_snapshot_ref='snapshot-e',final_snapshot_at=now(),snapshot_manifest_hash=decode(repeat('ee',32),'hex'),destination_validation_ref='validation-e',destination_validated_at=now() WHERE case_id='d4500000-0000-0000-0000-000000000001';
UPDATE transfer_cases SET state='cutover_frozen' WHERE case_id='d4500000-0000-0000-0000-000000000001';
INSERT INTO transfer_approvals(approval_id,assertion_id,nonce_digest,case_id,approval_kind,evidence_ref,approver_ref,authn_event_ref,authority_snapshot,verified_at)
SELECT gen_random_uuid(),gen_random_uuid(),sha256(convert_to('exe-'||k,'UTF8')),'d4500000-0000-0000-0000-000000000001',k,'ev-exe-'||k,'subject-'||k,'authn-'||k,'{"synthetic":true}'::jsonb,now()
  FROM unnest(ARRAY['guardian_consent','fee_confirmation','destination_acceptance']) k;
SET SESSION AUTHORIZATION cp_transfer_executor;
SELECT switch_student_ownership('d4500000-0000-0000-0000-000000000001');
RESET SESSION AUTHORIZATION;
DO $t$ BEGIN
  IF (SELECT owner_workspace_id::text||'/'||ownership_generation FROM student_ownership WHERE student_id='b4500000-0000-0000-0000-000000000001')<>'a4500000-0000-0000-0000-000000000002/2' THEN
    RAISE EXCEPTION 'FAIL EXE-02';
  END IF;
  RAISE NOTICE 'PASS EXE-02 ownership switch committed when called by cp_transfer_executor (generation 2)';
END $t$;

-- EXE-03 / EXE-04: rotation completion and retirement as cp_rotation_executor.
SET SESSION AUTHORIZATION cp_rotation_executor;
SELECT begin_identity_hmac_rotation();
SELECT complete_identity_hmac_rotation(2);
RESET SESSION AUTHORIZATION;
DO $t$ BEGIN
  IF (SELECT state FROM mobile_hmac_key_versions WHERE key_version=2)<>'active' OR (SELECT maintenance_mode FROM identity_write_gate WHERE singleton) THEN RAISE EXCEPTION 'FAIL EXE-03'; END IF;
  RAISE NOTICE 'PASS EXE-03 HMAC rotation completion committed when called by cp_rotation_executor';
END $t$;
SET SESSION AUTHORIZATION cp_rotation_executor;
SELECT begin_identity_hmac_rotation();
SELECT retire_identity_hmac_version(1);
RESET SESSION AUTHORIZATION;
DO $t$ BEGIN
  IF (SELECT state FROM mobile_hmac_key_versions WHERE key_version=1)<>'retired'
     OR EXISTS (SELECT 1 FROM enrollment_claim_identity_aliases WHERE key_version=1)
     OR (SELECT maintenance_mode FROM identity_write_gate WHERE singleton) THEN RAISE EXCEPTION 'FAIL EXE-04'; END IF;
  RAISE NOTICE 'PASS EXE-04 HMAC version retirement committed when called by cp_rotation_executor';
END $t$;
-- A broken coverage state must still be rejected inside the command (the check was moved, not removed).
DO $t$ BEGIN
  BEGIN
    SET SESSION AUTHORIZATION cp_identity_admission_executor;
    PERFORM admit_student_identity_claim('exe-bad',decode(repeat('0b',32),'hex'),'b4500000-0000-0000-0000-000000000002','c4500000-0000-0000-0000-000000000002','a4500000-0000-0000-0000-000000000001','grade_10',decode('ee02','hex'),1,
      '[{"key_version":2,"mobile_hmac_hex":"e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2"}]'::jsonb);
    RESET SESSION AUTHORIZATION;
  EXCEPTION WHEN unique_violation THEN
    RESET SESSION AUTHORIZATION;
    RAISE NOTICE 'PASS EXE-05 duplicate mobile+grade still rejected for the executor (global identity index)';
    RETURN;
  END;
  RAISE EXCEPTION 'FAIL EXE-05 duplicate identity admitted';
END $t$;
DO $t$ BEGIN RAISE NOTICE '=== CONTROL PLANE EXECUTOR-IDENTITY TESTS COMPLETED (synthetic) ==='; END $t$;
