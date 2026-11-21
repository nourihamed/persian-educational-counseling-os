-- Control Plane initial identity-claim admission regression tests. Synthetic only (D-014).
-- Run on a fresh DB after cp_01, cp_05, cp_07 and cp_06.
\set ON_ERROR_STOP on

CREATE OR REPLACE FUNCTION cp_admit_expect_error(label text, stmt text, want text)
RETURNS void LANGUAGE plpgsql AS $test$
BEGIN
  EXECUTE stmt;
  RAISE EXCEPTION 'FAIL %: statement unexpectedly succeeded',label;
EXCEPTION WHEN OTHERS THEN
  IF SQLSTATE<>want THEN
    RAISE EXCEPTION 'FAIL %: got SQLSTATE % (%), expected %',label,SQLSTATE,SQLERRM,want;
  END IF;
  RAISE NOTICE 'PASS % (SQLSTATE %)',label,SQLSTATE;
END; $test$;

INSERT INTO workspaces(workspace_id,workspace_type,status) VALUES
 ('a7100000-0000-0000-0000-000000000001','organization','active'),
 ('a7100000-0000-0000-0000-000000000002','independent_counselor','active'),
 ('a7100000-0000-0000-0000-000000000003','organization','active'),
 ('a7100000-0000-0000-0000-000000000004','organization','suspended');
INSERT INTO mobile_encryption_key_versions(key_version,state,key_manager_ref)
VALUES(1,'active','kms://synthetic/mobile-encryption-v1');
INSERT INTO mobile_hmac_key_versions(key_version,state) VALUES
 (1,'active'),(2,'retiring');

-- Initial admission writes the global student, owner, claim and every live-key alias atomically.
SELECT admit_student_identity_claim(
 'admit-one',decode(repeat('aa',32),'hex'),
 'b7100000-0000-0000-0000-000000000001','c7100000-0000-0000-0000-000000000001',
 'a7100000-0000-0000-0000-000000000001','grade_10',
 decode('aabbccdd','hex'),1,
 '[{"key_version":1,"mobile_hmac_hex":"1111111111111111111111111111111111111111111111111111111111111111"},{"key_version":2,"mobile_hmac_hex":"2222222222222222222222222222222222222222222222222222222222222222"}]'::jsonb);

DO $assert$
BEGIN
  IF NOT EXISTS(SELECT 1 FROM platform_students WHERE student_id='b7100000-0000-0000-0000-000000000001')
     OR NOT EXISTS(SELECT 1 FROM student_ownership WHERE student_id='b7100000-0000-0000-0000-000000000001' AND owner_workspace_id='a7100000-0000-0000-0000-000000000001' AND ownership_generation=1)
     OR NOT EXISTS(SELECT 1 FROM enrollment_claims WHERE claim_id='c7100000-0000-0000-0000-000000000001' AND claim_state='active')
     OR (SELECT count(*) FROM student_contact_index WHERE student_id='b7100000-0000-0000-0000-000000000001')<>2
     OR (SELECT count(*) FROM enrollment_claim_identity_aliases WHERE claim_id='c7100000-0000-0000-0000-000000000001' AND claim_state='active')<>2
     OR (SELECT count(*) FROM identity_admission_commands WHERE idempotency_key='admit-one')<>1 THEN
    RAISE EXCEPTION 'FAIL CP-ADMIT-01 incomplete initial claim admission';
  END IF;
  RAISE NOTICE 'PASS CP-ADMIT-01 atomic initial claim, ownership, ciphertext and two HMAC aliases';
END $assert$;

-- Exact replay returns the same claim; a changed payload under the same key is rejected.
SELECT admit_student_identity_claim(
 'admit-one',decode(repeat('aa',32),'hex'),
 'b7100000-0000-0000-0000-000000000001','c7100000-0000-0000-0000-000000000001',
 'a7100000-0000-0000-0000-000000000001','grade_10',
 decode('aabbccdd','hex'),1,
 '[{"key_version":1,"mobile_hmac_hex":"1111111111111111111111111111111111111111111111111111111111111111"},{"key_version":2,"mobile_hmac_hex":"2222222222222222222222222222222222222222222222222222222222222222"}]'::jsonb);
SELECT cp_admit_expect_error('CP-ADMIT-02 same idempotency key with different payload is rejected',
  $q$SELECT admit_student_identity_claim('admit-one',decode(repeat('bb',32),'hex'),'b7100000-0000-0000-0000-000000000001','c7100000-0000-0000-0000-000000000001','a7100000-0000-0000-0000-000000000001','grade_10',decode('aabbccdd','hex'),1,'[{"key_version":1,"mobile_hmac_hex":"1111111111111111111111111111111111111111111111111111111111111111"},{"key_version":2,"mobile_hmac_hex":"2222222222222222222222222222222222222222222222222222222222222222"}]'::jsonb)$q$,
  '23505');

-- The same canonical mobile+grade cannot be claimed by another Workspace, even with two key aliases.
SELECT cp_admit_expect_error('CP-ADMIT-03 global mobile+grade duplicate across Workspaces is rejected',
  $q$SELECT admit_student_identity_claim('admit-duplicate',decode(repeat('cc',32),'hex'),'b7100000-0000-0000-0000-000000000002','c7100000-0000-0000-0000-000000000002','a7100000-0000-0000-0000-000000000002','grade_10',decode('aabbccdd','hex'),1,'[{"key_version":1,"mobile_hmac_hex":"1111111111111111111111111111111111111111111111111111111111111111"},{"key_version":2,"mobile_hmac_hex":"2222222222222222222222222222222222222222222222222222222222222222"}]'::jsonb)$q$,
  '23505');
DO $assert$
BEGIN
  IF EXISTS(SELECT 1 FROM platform_students WHERE student_id='b7100000-0000-0000-0000-000000000002')
     OR EXISTS(SELECT 1 FROM student_ownership WHERE student_id='b7100000-0000-0000-0000-000000000002')
     OR EXISTS(SELECT 1 FROM identity_admission_commands WHERE idempotency_key='admit-duplicate') THEN
    RAISE EXCEPTION 'FAIL CP-ADMIT-04 rejected duplicate left partial rows';
  END IF;
  RAISE NOTICE 'PASS CP-ADMIT-04 global-identity conflict rolls back all admission rows';
END $assert$;

-- Same mobile with a different grade is allowed by the approved D-025 rule.
SELECT admit_student_identity_claim(
 'admit-different-grade',decode(repeat('dd',32),'hex'),
 'b7100000-0000-0000-0000-000000000003','c7100000-0000-0000-0000-000000000003',
 'a7100000-0000-0000-0000-000000000003','grade_11',
 decode('aabbccdd','hex'),1,
 '[{"key_version":1,"mobile_hmac_hex":"1111111111111111111111111111111111111111111111111111111111111111"},{"key_version":2,"mobile_hmac_hex":"2222222222222222222222222222222222222222222222222222222222222222"}]'::jsonb);
DO $assert$
BEGIN
  IF NOT EXISTS(SELECT 1 FROM enrollment_claims WHERE claim_id='c7100000-0000-0000-0000-000000000003' AND grade_key='grade_11') THEN
    RAISE EXCEPTION 'FAIL CP-ADMIT-05 different grade claim was not admitted';
  END IF;
  RAISE NOTICE 'PASS CP-ADMIT-05 same mobile with different grade is allowed';
END $assert$;

SELECT cp_admit_expect_error('CP-ADMIT-06 missing retiring-key alias is rejected',
  $q$SELECT admit_student_identity_claim('admit-missing-key',decode(repeat('ee',32),'hex'),'b7100000-0000-0000-0000-000000000004','c7100000-0000-0000-0000-000000000004','a7100000-0000-0000-0000-000000000001','grade_10',decode('aabbccdd','hex'),1,'[{"key_version":1,"mobile_hmac_hex":"3333333333333333333333333333333333333333333333333333333333333333"}]'::jsonb)$q$,
  '23514');
SELECT cp_admit_expect_error('CP-ADMIT-07 duplicate HMAC key version is rejected',
  $q$SELECT admit_student_identity_claim('admit-duplicate-version',decode(repeat('ee',32),'hex'),'b7100000-0000-0000-0000-000000000004','c7100000-0000-0000-0000-000000000004','a7100000-0000-0000-0000-000000000001','grade_10',decode('aabbccdd','hex'),1,'[{"key_version":1,"mobile_hmac_hex":"3333333333333333333333333333333333333333333333333333333333333333"},{"key_version":1,"mobile_hmac_hex":"4444444444444444444444444444444444444444444444444444444444444444"}]'::jsonb)$q$,
  '23514');
SELECT cp_admit_expect_error('CP-ADMIT-08 malformed HMAC hex is rejected',
  $q$SELECT admit_student_identity_claim('admit-bad-hmac',decode(repeat('ee',32),'hex'),'b7100000-0000-0000-0000-000000000004','c7100000-0000-0000-0000-000000000004','a7100000-0000-0000-0000-000000000001','grade_10',decode('aabbccdd','hex'),1,'[{"key_version":1,"mobile_hmac_hex":"bad"},{"key_version":2,"mobile_hmac_hex":"2222222222222222222222222222222222222222222222222222222222222222"}]'::jsonb)$q$,
  '23514');
SELECT cp_admit_expect_error('CP-ADMIT-09 non-active encryption key is rejected',
  $q$SELECT admit_student_identity_claim('admit-bad-cipher-key',decode(repeat('ee',32),'hex'),'b7100000-0000-0000-0000-000000000004','c7100000-0000-0000-0000-000000000004','a7100000-0000-0000-0000-000000000001','grade_10',decode('aabbccdd','hex'),99,'[{"key_version":1,"mobile_hmac_hex":"3333333333333333333333333333333333333333333333333333333333333333"},{"key_version":2,"mobile_hmac_hex":"2222222222222222222222222222222222222222222222222222222222222222"}]'::jsonb)$q$,
  '23514');
SELECT cp_admit_expect_error('CP-ADMIT-10 inactive Workspace is rejected',
  $q$SELECT admit_student_identity_claim('admit-inactive-workspace',decode(repeat('ee',32),'hex'),'b7100000-0000-0000-0000-000000000004','c7100000-0000-0000-0000-000000000004','a7100000-0000-0000-0000-000000000004','grade_10',decode('aabbccdd','hex'),1,'[{"key_version":1,"mobile_hmac_hex":"3333333333333333333333333333333333333333333333333333333333333333"},{"key_version":2,"mobile_hmac_hex":"2222222222222222222222222222222222222222222222222222222222222222"}]'::jsonb)$q$,
  '23503');

-- A retiring-only key set must not accept new claims; exactly one active HMAC key is required.
UPDATE mobile_hmac_key_versions SET state='retiring' WHERE key_version=1;
SELECT cp_admit_expect_error('CP-ADMIT-11 exactly one active HMAC key is required',
  $q$SELECT admit_student_identity_claim('admit-no-active-key',decode(repeat('ff',32),'hex'),'b7100000-0000-0000-0000-000000000004','c7100000-0000-0000-0000-000000000004','a7100000-0000-0000-0000-000000000001','grade_10',decode('aabbccdd','hex'),1,'[{"key_version":1,"mobile_hmac_hex":"3333333333333333333333333333333333333333333333333333333333333333"},{"key_version":2,"mobile_hmac_hex":"2222222222222222222222222222222222222222222222222222222222222222"}]'::jsonb)$q$,
  '23514');
UPDATE mobile_hmac_key_versions SET state='active' WHERE key_version=1;

-- During key rotation, new admissions fail closed; exact replay remains idempotent.
UPDATE identity_write_gate SET maintenance_mode=true WHERE singleton=true;
SELECT cp_admit_expect_error('CP-ADMIT-12 new admission is blocked during HMAC rotation maintenance',
  $q$SELECT admit_student_identity_claim('admit-maintenance',decode(repeat('ff',32),'hex'),'b7100000-0000-0000-0000-000000000004','c7100000-0000-0000-0000-000000000004','a7100000-0000-0000-0000-000000000001','grade_10',decode('aabbccdd','hex'),1,'[{"key_version":1,"mobile_hmac_hex":"3333333333333333333333333333333333333333333333333333333333333333"},{"key_version":2,"mobile_hmac_hex":"2222222222222222222222222222222222222222222222222222222222222222"}]'::jsonb)$q$,
  '55000');
SELECT admit_student_identity_claim(
 'admit-one',decode(repeat('aa',32),'hex'),
 'b7100000-0000-0000-0000-000000000001','c7100000-0000-0000-0000-000000000001',
 'a7100000-0000-0000-0000-000000000001','grade_10',
 decode('aabbccdd','hex'),1,
 '[{"key_version":1,"mobile_hmac_hex":"1111111111111111111111111111111111111111111111111111111111111111"},{"key_version":2,"mobile_hmac_hex":"2222222222222222222222222222222222222222222222222222222222222222"}]'::jsonb);
UPDATE identity_write_gate SET maintenance_mode=false WHERE singleton=true;

SELECT cp_admit_expect_error('CP-ADMIT-13 identity admission command log is append-only',
  $q$UPDATE identity_admission_commands SET grade_key='grade_12' WHERE idempotency_key='admit-one'$q$,
  '23514');

DO $done$ BEGIN RAISE NOTICE '=== CONTROL PLANE IDENTITY ADMISSION TESTS COMPLETED (synthetic) ==='; END $done$;
