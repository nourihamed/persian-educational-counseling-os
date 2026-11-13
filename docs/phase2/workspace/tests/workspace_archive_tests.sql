-- Workspace archive + capacity release tests. Synthetic only (D-014).
-- Run on a FRESH DB after workspace_schema_draft.sql, workspace_activation_transactions.sql,
-- workspace_governance_events_draft.sql, workspace_archive_transactions.sql and workspace_roles_setup_draft.sql
-- (-v workspace_key). Commands are called as the Workspace runtime role, not as superuser.
\set ON_ERROR_STOP on
SET app.workspace_key = :'workspace_key';
SELECT 'ws_'||current_setting('app.workspace_key')||'_runtime' AS runtime_role \gset
SELECT 'ws_'||current_setting('app.workspace_key')||'_worker' AS worker_role \gset
CREATE OR REPLACE FUNCTION ar_err(label text, stmt text, want text, want_msg text DEFAULT '')
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

INSERT INTO workspace_profile(singleton,workspace_id,workspace_type) VALUES(true,'a9500000-0000-0000-0000-000000000001','organization');
INSERT INTO workspace_memberships(membership_id,platform_user_id,status) VALUES
 ('b9500000-0000-0000-0000-000000000001','c9500000-0000-0000-0000-000000000001','active'),
 ('b9500000-0000-0000-0000-000000000002','c9500000-0000-0000-0000-000000000002','suspended');
INSERT INTO membership_roles(membership_id,role_key) VALUES ('b9500000-0000-0000-0000-000000000001','counselor');
INSERT INTO students(student_id,platform_student_id,display_name,grade_key,lifecycle_state) VALUES
 ('e9500000-0000-0000-0000-000000000001','f9500000-0000-0000-0000-000000000001','Archive One','grade_10','active'),
 ('e9500000-0000-0000-0000-000000000002','f9500000-0000-0000-0000-000000000002','Archive Two','grade_10','active'),
 ('e9500000-0000-0000-0000-000000000003','f9500000-0000-0000-0000-000000000003','Archive Three','grade_10','active');
INSERT INTO enrollments(enrollment_id,student_id,ownership_generation,state) VALUES
 ('a9600000-0000-0000-0000-000000000001','e9500000-0000-0000-0000-000000000001',1,'requested'),
 ('a9600000-0000-0000-0000-000000000002','e9500000-0000-0000-0000-000000000002',1,'requested'),
 ('a9600000-0000-0000-0000-000000000003','e9500000-0000-0000-0000-000000000003',1,'requested');
INSERT INTO counselor_assignments(assignment_id,enrollment_id,counselor_membership_id,is_responsible,state,accepted_at) VALUES
 (gen_random_uuid(),'a9600000-0000-0000-0000-000000000001','b9500000-0000-0000-0000-000000000001',true,'active',now()),
 (gen_random_uuid(),'a9600000-0000-0000-0000-000000000002','b9500000-0000-0000-0000-000000000001',true,'active',now()),
 (gen_random_uuid(),'a9600000-0000-0000-0000-000000000003','b9500000-0000-0000-0000-000000000001',true,'active',now());
INSERT INTO credit_wallets(wallet_id,unit_code) VALUES('c9600000-0000-0000-0000-000000000001','CRD');
INSERT INTO credit_transactions(transaction_id,wallet_id,transaction_kind,amount,idempotency_key,reason)
VALUES(gen_random_uuid(),'c9600000-0000-0000-0000-000000000001','grant',100,'archive-fixture-grant','synthetic opening credit');
INSERT INTO workspace_capacity_counters(dimension_key,current_value,max_value) VALUES('active_students',0,2);

SET SESSION AUTHORIZATION :"runtime_role";
SELECT activate_student_enrollment('ar-act-1','a9600000-0000-0000-0000-000000000001','c9600000-0000-0000-0000-000000000001',1,10,'b9500000-0000-0000-0000-000000000001');
SELECT activate_student_enrollment('ar-act-2','a9600000-0000-0000-0000-000000000002','c9600000-0000-0000-0000-000000000001',1,10,'b9500000-0000-0000-0000-000000000001');
SELECT ar_err('ARC-01 capacity is full before any archive (third activation rejected)',
 $q$SELECT activate_student_enrollment('ar-act-3','a9600000-0000-0000-0000-000000000003','c9600000-0000-0000-0000-000000000001',1,10,'b9500000-0000-0000-0000-000000000001')$q$,'23514','capacity unavailable');
SELECT ar_err('ARC-02 stale ownership generation rejected',
 $q$SELECT archive_student_enrollment('ar-1','a9600000-0000-0000-0000-000000000001',2,'b9500000-0000-0000-0000-000000000001','offboarding')$q$,'23514','stale local ownership');
SELECT ar_err('ARC-03 an inactive member cannot archive',
 $q$SELECT archive_student_enrollment('ar-1','a9600000-0000-0000-0000-000000000001',1,'b9500000-0000-0000-0000-000000000002','offboarding')$q$,'42501','not an active Workspace member');
SELECT ar_err('ARC-04 an enrollment that is not active cannot be archived',
 $q$SELECT archive_student_enrollment('ar-3','a9600000-0000-0000-0000-000000000003',1,'b9500000-0000-0000-0000-000000000001','offboarding')$q$,'23514','only active');
SELECT ar_err('ARC-05 a reason code is required',
 $q$SELECT archive_student_enrollment('ar-1','a9600000-0000-0000-0000-000000000001',1,'b9500000-0000-0000-0000-000000000001',' ')$q$,'22023');
SELECT ar_err('ARC-06 runtime cannot write the archive command log directly',
 $q$INSERT INTO archive_command_log(idempotency_key,enrollment_id,expected_generation,actor_membership_id,reason_code) VALUES ('x','a9600000-0000-0000-0000-000000000001',1,'b9500000-0000-0000-0000-000000000001','r')$q$,'42501');
SELECT ar_err('ARC-07 runtime cannot release capacity directly',
 $q$SELECT adjust_workspace_capacity('active_students',-1,'direct','e9500000-0000-0000-0000-000000000001','b9500000-0000-0000-0000-000000000001','x')$q$,'42501');
SELECT archive_student_enrollment('ar-1','a9600000-0000-0000-0000-000000000001',1,'b9500000-0000-0000-0000-000000000001','offboarding');
SELECT archive_student_enrollment('ar-1','a9600000-0000-0000-0000-000000000001',1,'b9500000-0000-0000-0000-000000000001','offboarding');  -- exact replay
SELECT ar_err('ARC-08 same idempotency key with a different intent rejected',
 $q$SELECT archive_student_enrollment('ar-1','a9600000-0000-0000-0000-000000000002',1,'b9500000-0000-0000-0000-000000000001','offboarding')$q$,'23505','different intent');
SELECT ar_err('ARC-09 a second archive of the same enrollment under a new key rejected (no underflow)',
 $q$SELECT archive_student_enrollment('ar-1-again','a9600000-0000-0000-0000-000000000001',1,'b9500000-0000-0000-0000-000000000001','offboarding')$q$,'23514','only active');
RESET SESSION AUTHORIZATION;
DO $t$ BEGIN
  IF (SELECT state FROM enrollments WHERE enrollment_id='a9600000-0000-0000-0000-000000000001')<>'archived'
     OR (SELECT ended_at FROM enrollments WHERE enrollment_id='a9600000-0000-0000-0000-000000000001') IS NULL
     OR (SELECT lifecycle_state FROM students WHERE student_id='e9500000-0000-0000-0000-000000000001')<>'archived' THEN RAISE EXCEPTION 'FAIL ARC-10 state'; END IF;
  IF (SELECT current_value FROM workspace_capacity_counters WHERE dimension_key='active_students')<>1 THEN RAISE EXCEPTION 'FAIL ARC-10 counter'; END IF;
  IF (SELECT count(*) FROM capacity_events WHERE idempotency_key='archive:ar-1' AND delta=-1)<>1 THEN RAISE EXCEPTION 'FAIL ARC-10 event'; END IF;
  RAISE NOTICE 'PASS ARC-10 archive released exactly one slot with the archive state; replay released nothing more';
  IF (SELECT count(*) FROM enrollments WHERE enrollment_id='a9600000-0000-0000-0000-000000000001')<>1
     OR (SELECT count(*) FROM counselor_assignments WHERE enrollment_id='a9600000-0000-0000-0000-000000000001' AND state='ended' AND ended_at IS NOT NULL)<>1
     OR EXISTS (SELECT 1 FROM counselor_assignments WHERE enrollment_id='a9600000-0000-0000-0000-000000000001' AND state='active') THEN RAISE EXCEPTION 'FAIL ARC-11'; END IF;
  RAISE NOTICE 'PASS ARC-11 historical enrollment and assignment rows preserved (ended, not deleted)';
  IF (SELECT count(*) FROM credit_transactions WHERE student_id='e9500000-0000-0000-0000-000000000001')<>1 THEN RAISE EXCEPTION 'FAIL ARC-12'; END IF;
  RAISE NOTICE 'PASS ARC-12 archive made no credit movement (only the original activation debit exists)';
  IF (SELECT count(*) FROM audit_events WHERE event_type='student.archive' AND correlation_id='ar-1')<>1 THEN RAISE EXCEPTION 'FAIL ARC-13'; END IF;
  RAISE NOTICE 'PASS ARC-13 exactly one archive audit event';
  IF EXISTS (SELECT 1 FROM capacity_counter_reconciliation WHERE NOT consistent) THEN RAISE EXCEPTION 'FAIL ARC-14'; END IF;
  RAISE NOTICE 'PASS ARC-14 capacity counter equals the sum of its event ledger';
END $t$;
SET SESSION AUTHORIZATION :"runtime_role";
SELECT activate_student_enrollment('ar-act-3','a9600000-0000-0000-0000-000000000003','c9600000-0000-0000-0000-000000000001',1,10,'b9500000-0000-0000-0000-000000000001');
RESET SESSION AUTHORIZATION;
DO $t$ BEGIN
  IF (SELECT state FROM enrollments WHERE enrollment_id='a9600000-0000-0000-0000-000000000003')<>'active'
     OR (SELECT current_value FROM workspace_capacity_counters WHERE dimension_key='active_students')<>2 THEN RAISE EXCEPTION 'FAIL ARC-15'; END IF;
  RAISE NOTICE 'PASS ARC-15 the released slot is usable by another student (archived students consume no capacity)';
END $t$;
SET SESSION AUTHORIZATION :"worker_role";
SELECT ar_err('ARC-16 worker role cannot call the archive command',
 $q$SELECT archive_student_enrollment('ar-w','a9600000-0000-0000-0000-000000000002',1,'b9500000-0000-0000-0000-000000000001','offboarding')$q$,'42501');
RESET SESSION AUTHORIZATION;
SELECT ar_err('ARC-17 archive command log is append-only',$q$DELETE FROM archive_command_log$q$,'23514','append-only');
DO $t$ BEGIN RAISE NOTICE '=== WORKSPACE ARCHIVE TESTS COMPLETED (synthetic) ==='; END $t$;
