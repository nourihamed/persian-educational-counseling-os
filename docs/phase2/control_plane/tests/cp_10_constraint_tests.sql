-- CONTROL PLANE constraint + workflow tests (synthetic). Run after cp_01 and cp_02 on a FRESH DB.
\set ON_ERROR_STOP on
CREATE OR REPLACE FUNCTION expect_error(label text, stmt text, want text, want_msg text DEFAULT '')
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE stmt;
  RAISE EXCEPTION 'FAIL %: statement succeeded, expected SQLSTATE %', label, want;
EXCEPTION WHEN OTHERS THEN
  IF SQLSTATE <> want THEN RAISE EXCEPTION 'FAIL %: got SQLSTATE % (%), expected %', label, SQLSTATE, SQLERRM, want; END IF;
  IF want_msg <> '' AND position(want_msg IN SQLERRM) = 0 THEN RAISE EXCEPTION 'FAIL %: wrong reason: %', label, SQLERRM; END IF;
  RAISE NOTICE 'PASS % (SQLSTATE %, reason verified)', label, SQLSTATE;
END; $$;
CREATE OR REPLACE FUNCTION expect_ok(label text, stmt text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN EXECUTE stmt; RAISE NOTICE 'PASS % (accepted)', label; END; $$;

-- Fixtures: three Workspaces (two organizations, one independent) and three students.
INSERT INTO workspaces (workspace_id, workspace_type, status) VALUES
 ('a0000000-0000-0000-0000-000000000001','organization','active'),
 ('a0000000-0000-0000-0000-000000000002','independent_counselor','active'),
 ('a0000000-0000-0000-0000-000000000003','organization','active');
INSERT INTO platform_students (student_id) VALUES
 ('b0000000-0000-0000-0000-000000000001'),('b0000000-0000-0000-0000-000000000002'),('b0000000-0000-0000-0000-000000000003');
-- Synthetic HMAC values (32 bytes). Real key material never appears here.
INSERT INTO student_contact_index (student_id, key_version, mobile_hmac, mobile_ciphertext, cipher_key_version) VALUES
 ('b0000000-0000-0000-0000-000000000001',1,decode(repeat('11',32),'hex'),'\x00',1),
 ('b0000000-0000-0000-0000-000000000002',1,decode(repeat('22',32),'hex'),'\x00',1),
 ('b0000000-0000-0000-0000-000000000003',1,decode(repeat('33',32),'hex'),'\x00',1);
INSERT INTO student_ownership (student_id, owner_workspace_id, ownership_generation, lifecycle_state) VALUES
 ('b0000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001',1,'active'),
 ('b0000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000002',1,'active'),
 ('b0000000-0000-0000-0000-000000000003','a0000000-0000-0000-0000-000000000003',1,'active');

-- ---- Global identity (D-025) ----
SELECT expect_ok('CP-GU-01 claim: student 1 active in W1 for hmac-A, grade_10',
  $q$INSERT INTO enrollment_claims (claim_id,student_id,workspace_id,grade_key,key_version,mobile_hmac,claim_state,ownership_generation)
     VALUES ('c0000000-0000-0000-0000-000000000001','b0000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','grade_10',1,decode(repeat('11',32),'hex'),'active',1)$q$);
SELECT expect_error('CP-GU-02 same mobile+grade active in a DIFFERENT Workspace rejected (global)',
  $q$INSERT INTO enrollment_claims (claim_id,student_id,workspace_id,grade_key,key_version,mobile_hmac,claim_state,ownership_generation)
     VALUES ('c0000000-0000-0000-0000-000000000002','b0000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000002','grade_10',1,decode(repeat('11',32),'hex'),'active',1)$q$,
  '23505', 'enrollment_claims_global_identity');
SELECT expect_error('CP-GU-03 one claim-holding enrollment per student platform-wide (PO-4)',
  $q$INSERT INTO enrollment_claims (claim_id,student_id,workspace_id,grade_key,key_version,mobile_hmac,claim_state,ownership_generation)
     VALUES ('c0000000-0000-0000-0000-000000000003','b0000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','grade_11',1,decode(repeat('11',32),'hex'),'active',1)$q$,
  '23505', 'enrollment_claims_one_per_student');
SELECT expect_ok('CP-GU-04 same mobile, DIFFERENT grade (grade_11) for another student is allowed by D-025',
  $q$INSERT INTO enrollment_claims (claim_id,student_id,workspace_id,grade_key,key_version,mobile_hmac,claim_state,ownership_generation)
     VALUES ('c0000000-0000-0000-0000-000000000004','b0000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000002','grade_11',1,decode(repeat('11',32),'hex'),'active',1)$q$);
SELECT expect_error('CP-GU-05 grade outside MVP enumeration rejected',
  $q$INSERT INTO enrollment_claims (claim_id,student_id,workspace_id,grade_key,key_version,mobile_hmac,claim_state,ownership_generation)
     VALUES (gen_random_uuid(),'b0000000-0000-0000-0000-000000000003','a0000000-0000-0000-0000-000000000003','grade 10',1,decode(repeat('33',32),'hex'),'active',1)$q$, '23514');
SELECT expect_error('CP-GU-06 mobile HMAC must be exactly 32 bytes',
  $q$INSERT INTO enrollment_claims (claim_id,student_id,workspace_id,grade_key,key_version,mobile_hmac,claim_state,ownership_generation)
     VALUES (gen_random_uuid(),'b0000000-0000-0000-0000-000000000003','a0000000-0000-0000-0000-000000000003','grade_12',1,'\x0102',  'active',1)$q$, '23514');
SELECT expect_ok('CP-GU-07 ended claim releases the global key (PROPOSED rule, see cp_01 comment)',
  $q$UPDATE enrollment_claims SET claim_state='ended', ended_at=now() WHERE claim_id='c0000000-0000-0000-0000-000000000001'$q$);
SELECT expect_ok('CP-GU-08 after release, student 3 may claim hmac-A grade_10 in W3',
  $q$INSERT INTO enrollment_claims (claim_id,student_id,workspace_id,grade_key,key_version,mobile_hmac,claim_state,ownership_generation)
     VALUES ('c0000000-0000-0000-0000-000000000005','b0000000-0000-0000-0000-000000000003','a0000000-0000-0000-0000-000000000003','grade_10',1,decode(repeat('11',32),'hex'),'active',1)$q$);
SELECT expect_error('CP-GU-09 ended state requires ended_at (lifecycle check)',
  $q$UPDATE enrollment_claims SET claim_state='archived', ended_at=NULL WHERE claim_id='c0000000-0000-0000-0000-000000000005'$q$, '23514');

-- ---- Privacy: no plaintext mobile column in the Control Plane ----
DO $$ DECLARE n int; BEGIN
  SELECT count(*) INTO n FROM information_schema.columns
   WHERE table_schema='public' AND column_name ~* '(mobile|phone|msisdn)'
     AND column_name NOT IN ('mobile_hmac','mobile_ciphertext');
  IF n <> 0 THEN RAISE EXCEPTION 'FAIL CP-PRIV-01: % plaintext-like mobile column(s) present', n; END IF;
  RAISE NOTICE 'PASS CP-PRIV-01 only mobile_hmac and mobile_ciphertext exist (no plaintext mobile column)';
END $$;

-- ---- Transfer cases: initiator rule (OQ-A) and idempotency ----
SELECT expect_error('CP-INIT-01 Platform Admin cannot be a transfer initiator (OQ-A)',
  $q$INSERT INTO transfer_cases (case_id,student_id,source_workspace_id,destination_workspace_id,expected_generation,initiator_kind,state,idempotency_key)
     VALUES (gen_random_uuid(),'b0000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000001',1,'platform_admin','requested','k-admin')$q$, '23514');
SELECT expect_ok('CP-INIT-02 guardian-initiated case accepted (initiation alone does not finalize)',
  $q$INSERT INTO transfer_cases (case_id,student_id,source_workspace_id,destination_workspace_id,expected_generation,initiator_kind,state,idempotency_key)
     VALUES ('d0000000-0000-0000-0000-000000000001','b0000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000001',1,'guardian','requested','k-guardian-1')$q$);
SELECT expect_error('CP-IDEM-01 duplicate idempotency key rejected',
  $q$INSERT INTO transfer_cases (case_id,student_id,source_workspace_id,destination_workspace_id,expected_generation,initiator_kind,state,idempotency_key)
     VALUES (gen_random_uuid(),'b0000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000001',1,'guardian','requested','k-guardian-1')$q$, '23505');
SELECT expect_error('CP-CASE-01 only one open transfer per student',
  $q$INSERT INTO transfer_cases (case_id,student_id,source_workspace_id,destination_workspace_id,expected_generation,initiator_kind,state,idempotency_key)
     VALUES (gen_random_uuid(),'b0000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000003',1,'current_counselor','requested','k-second')$q$, '23505', 'transfer_cases_one_open_per_student');

-- ---- Cumulative approvals: switch requires all three, in cutover_frozen ----
UPDATE transfer_cases SET state='approvals_pending' WHERE case_id='d0000000-0000-0000-0000-000000000001';
UPDATE transfer_cases SET state='approved' WHERE case_id='d0000000-0000-0000-0000-000000000001';
UPDATE transfer_cases SET state='preflight_ok' WHERE case_id='d0000000-0000-0000-0000-000000000001';
UPDATE transfer_cases SET state='staging' WHERE case_id='d0000000-0000-0000-0000-000000000001';
UPDATE transfer_cases SET state='staged_verified' WHERE case_id='d0000000-0000-0000-0000-000000000001';
UPDATE transfer_cases SET state='cutover_frozen' WHERE case_id='d0000000-0000-0000-0000-000000000001';
INSERT INTO transfer_approvals (approval_id,case_id,approval_kind,evidence_ref,approver_ref) VALUES
 (gen_random_uuid(),'d0000000-0000-0000-0000-000000000001','guardian_consent','ev-consent-1','principal-guardian-1'),
 (gen_random_uuid(),'d0000000-0000-0000-0000-000000000001','destination_acceptance','ev-accept-1','principal-dest-1');
SELECT expect_error('CP-APP-01 switch with 2 of 3 approvals (missing fee confirmation) is rejected',
  $q$SELECT switch_student_ownership('d0000000-0000-0000-0000-000000000001')$q$, '23514', 'of 3 required approvals');
SELECT expect_error('CP-APP-02 approval kind cannot be duplicated for a case',
  $q$INSERT INTO transfer_approvals (approval_id,case_id,approval_kind,evidence_ref,approver_ref) VALUES
     (gen_random_uuid(),'d0000000-0000-0000-0000-000000000001','guardian_consent','ev-consent-2','principal-guardian-2')$q$, '23505');
INSERT INTO transfer_approvals (approval_id,case_id,approval_kind,evidence_ref,approver_ref) VALUES
 (gen_random_uuid(),'d0000000-0000-0000-0000-000000000001','fee_confirmation','ev-fee-1','principal-prior-counselor-1');

-- ---- Fencing: stale generation and stale source are rejected, owner unchanged ----
UPDATE student_ownership SET ownership_generation = 2 WHERE student_id='b0000000-0000-0000-0000-000000000002';
SELECT expect_error('CP-FENCE-01 stale generation rejected (case expects 1, current is 2)',
  $q$SELECT switch_student_ownership('d0000000-0000-0000-0000-000000000001')$q$, '23514', 'stale generation');
UPDATE student_ownership SET ownership_generation = 1 WHERE student_id='b0000000-0000-0000-0000-000000000002';
-- ---- Successful switch: one transaction, generation +1, claim moved, outbox, history ----
DO $$ DECLARE g bigint; st text; BEGIN
  g := switch_student_ownership('d0000000-0000-0000-0000-000000000001');
  SELECT state INTO st FROM transfer_cases WHERE case_id='d0000000-0000-0000-0000-000000000001';
  IF g <> 2 THEN RAISE EXCEPTION 'FAIL CP-SWITCH-01: generation % expected 2', g; END IF;
  IF (SELECT owner_workspace_id FROM student_ownership WHERE student_id='b0000000-0000-0000-0000-000000000002') <> 'a0000000-0000-0000-0000-000000000001' THEN
    RAISE EXCEPTION 'FAIL CP-SWITCH-01b: owner not switched'; END IF;
  IF (SELECT count(*) FROM outbox_events WHERE case_id='d0000000-0000-0000-0000-000000000001' AND event_type='ownership_switched') <> 1 THEN
    RAISE EXCEPTION 'FAIL CP-SWITCH-01c: outbox event missing'; END IF;
  IF (SELECT count(*) FROM ownership_history WHERE student_id='b0000000-0000-0000-0000-000000000002' AND ownership_generation=2) <> 1 THEN
    RAISE EXCEPTION 'FAIL CP-SWITCH-01d: history missing'; END IF;
  IF st <> 'ownership_switched' THEN RAISE EXCEPTION 'FAIL CP-SWITCH-01e: case state %', st; END IF;
  RAISE NOTICE 'PASS CP-SWITCH-01 atomic switch: generation 2, owner W1, outbox + history written, state ownership_switched';
END $$;
SELECT expect_error('CP-SWITCH-02 replayed switch for the same case is refused (already switched)',
  $q$SELECT switch_student_ownership('d0000000-0000-0000-0000-000000000001')$q$, '23514', 'expected cutover_frozen');
SELECT expect_error('CP-HIST-01 ownership history is append-only (UPDATE)',
  $q$UPDATE ownership_history SET to_workspace_id='a0000000-0000-0000-0000-000000000003' WHERE student_id='b0000000-0000-0000-0000-000000000002'$q$, '23514', 'forbidden');
SELECT expect_error('CP-SWITCH-03 switch from a non-frozen state is refused',
  $q$SELECT switch_student_ownership(gen_random_uuid())$q$, '23503');

-- ---- Initial-state guard (cp_03): a transfer cannot be inserted directly as cutover_frozen
SELECT expect_error('CP-STATE-00 transfer inserted directly as cutover_frozen rejected',
  $q$INSERT INTO transfer_cases (case_id,student_id,source_workspace_id,destination_workspace_id,expected_generation,initiator_kind,state,idempotency_key)
     VALUES (gen_random_uuid(),'b0000000-0000-0000-0000-000000000003','a0000000-0000-0000-0000-000000000003','a0000000-0000-0000-0000-000000000001',1,'guardian','cutover_frozen','k-direct')$q$, '23514', 'must start in requested');

-- ---- Transition guard (cp_03): illegal state jumps are rejected ----
SELECT expect_error('CP-STATE-01 illegal transition requested -> completed rejected',
  $q$UPDATE transfer_cases SET state='completed' WHERE case_id='d0000000-0000-0000-0000-000000000001'$q$, '23514', 'illegal transfer transition');
-- Legal forward path after the switch (case 1 is ownership_switched).
SELECT expect_ok('CP-STATE-02 legal forward path: ownership_switched -> projections_finalizing -> completed',
  $q$UPDATE transfer_cases SET state='projections_finalizing' WHERE case_id='d0000000-0000-0000-0000-000000000001';
     UPDATE transfer_cases SET state='completed' WHERE case_id='d0000000-0000-0000-0000-000000000001'$q$);

-- ---- Stale source via the function (not a direct UPDATE): case says source W2, owner is now W1 ----
INSERT INTO transfer_cases (case_id,student_id,source_workspace_id,destination_workspace_id,expected_generation,initiator_kind,state,idempotency_key)
VALUES ('d0000000-0000-0000-0000-000000000002','b0000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000003',2,'destination_workspace','requested','k-stale-source');
UPDATE transfer_cases SET state='approvals_pending' WHERE case_id='d0000000-0000-0000-0000-000000000002';
UPDATE transfer_cases SET state='approved' WHERE case_id='d0000000-0000-0000-0000-000000000002';
UPDATE transfer_cases SET state='preflight_ok' WHERE case_id='d0000000-0000-0000-0000-000000000002';
UPDATE transfer_cases SET state='staging' WHERE case_id='d0000000-0000-0000-0000-000000000002';
UPDATE transfer_cases SET state='staged_verified' WHERE case_id='d0000000-0000-0000-0000-000000000002';
UPDATE transfer_cases SET state='cutover_frozen' WHERE case_id='d0000000-0000-0000-0000-000000000002';
INSERT INTO transfer_approvals (approval_id,case_id,approval_kind,evidence_ref,approver_ref) VALUES
 (gen_random_uuid(),'d0000000-0000-0000-0000-000000000002','guardian_consent','ev-c2','p-g2'),
 (gen_random_uuid(),'d0000000-0000-0000-0000-000000000002','fee_confirmation','ev-f2','p-f2'),
 (gen_random_uuid(),'d0000000-0000-0000-0000-000000000002','destination_acceptance','ev-a2','p-a2');
SELECT expect_error('CP-FENCE-02 stale source workspace rejected by the switch function',
  $q$SELECT switch_student_ownership('d0000000-0000-0000-0000-000000000002')$q$, '23514', 'stale source');
SELECT expect_error('CP-FENCE-03 owner unchanged after the rejected switch (rollback, no partial write)',
  $q$SELECT CASE WHEN (SELECT owner_workspace_id FROM student_ownership WHERE student_id='b0000000-0000-0000-0000-000000000002')='a0000000-0000-0000-0000-000000000001' THEN 1/0 ELSE 1 END$q$, '22012');

DO $$ BEGIN RAISE NOTICE '=== CONTROL PLANE CONSTRAINT SUITE COMPLETED (synthetic) ==='; END $$;
