-- Workspace activation + credit + capacity regression tests. Synthetic only.
-- Run on a fresh DB after workspace_schema_draft.sql and workspace_activation_transactions.sql.
\set ON_ERROR_STOP on

CREATE OR REPLACE FUNCTION ws_activation_expect_error(label text, stmt text, want text)
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

INSERT INTO workspace_profile(singleton,workspace_id,workspace_type)
VALUES(true,'a8100000-0000-0000-0000-000000000001','organization');
INSERT INTO workspace_memberships(membership_id,platform_user_id,role_key,status) VALUES
 ('b8100000-0000-0000-0000-000000000001','c8100000-0000-0000-0000-000000000001','counselor','active'),
 ('b8100000-0000-0000-0000-000000000002','c8100000-0000-0000-0000-000000000002','counselor','suspended');
INSERT INTO membership_roles(membership_id,role_key) VALUES
 ('b8100000-0000-0000-0000-000000000001','counselor'),
 ('b8100000-0000-0000-0000-000000000002','counselor');

INSERT INTO students(student_id,platform_student_id,display_name,grade_key,lifecycle_state) VALUES
 ('e8100000-0000-0000-0000-000000000001','f8100000-0000-0000-0000-000000000001','Activation One','grade_10','active'),
 ('e8100000-0000-0000-0000-000000000002','f8100000-0000-0000-0000-000000000002','Activation Two','grade_10','active'),
 ('e8100000-0000-0000-0000-000000000003','f8100000-0000-0000-0000-000000000003','Activation Three','grade_10','active'),
 ('e8100000-0000-0000-0000-000000000004','f8100000-0000-0000-0000-000000000004','Activation Four','grade_10','active');

INSERT INTO enrollments(enrollment_id,student_id,ownership_generation,state) VALUES
 ('a8200000-0000-0000-0000-000000000001','e8100000-0000-0000-0000-000000000001',1,'requested'),
 ('a8200000-0000-0000-0000-000000000002','e8100000-0000-0000-0000-000000000002',1,'requested'),
 ('a8200000-0000-0000-0000-000000000003','e8100000-0000-0000-0000-000000000003',1,'awaiting_consent'),
 ('a8200000-0000-0000-0000-000000000004','e8100000-0000-0000-0000-000000000004',1,'requested');

INSERT INTO counselor_assignments(assignment_id,enrollment_id,counselor_membership_id,is_responsible,state,accepted_at) VALUES
 ('b8200000-0000-0000-0000-000000000001','a8200000-0000-0000-0000-000000000001','b8100000-0000-0000-0000-000000000001',true,'active',now()),
 ('b8200000-0000-0000-0000-000000000002','a8200000-0000-0000-0000-000000000002','b8100000-0000-0000-0000-000000000001',true,'active',now()),
 ('b8200000-0000-0000-0000-000000000003','a8200000-0000-0000-0000-000000000003','b8100000-0000-0000-0000-000000000001',true,'active',now());

INSERT INTO credit_wallets(wallet_id,unit_code)
VALUES('c8200000-0000-0000-0000-000000000001','CRD');
INSERT INTO credit_transactions(transaction_id,wallet_id,transaction_kind,amount,idempotency_key,reason)
VALUES('d8200000-0000-0000-0000-000000000001','c8200000-0000-0000-0000-000000000001','grant',100,'activation-fixture-grant','synthetic opening credit');
INSERT INTO workspace_capacity_counters(dimension_key,current_value,max_value)
VALUES('active_students',0,1);

-- Successful activation debits credit, reserves capacity and activates enrollment in one transaction.
DO $assert$
DECLARE result_id uuid;
BEGIN
  result_id:=activate_student_enrollment(
    'activate-one','a8200000-0000-0000-0000-000000000001',
    'c8200000-0000-0000-0000-000000000001',1,40,
    'b8100000-0000-0000-0000-000000000001');
  IF result_id<>'a8200000-0000-0000-0000-000000000001' THEN
    RAISE EXCEPTION 'FAIL WS-ACT-01 returned wrong enrollment';
  END IF;
  IF (SELECT state FROM enrollments WHERE enrollment_id=result_id)<>'active'
     OR (SELECT started_at FROM enrollments WHERE enrollment_id=result_id) IS NULL THEN
    RAISE EXCEPTION 'FAIL WS-ACT-02 enrollment not activated';
  END IF;
  IF (SELECT current_value FROM workspace_capacity_counters WHERE dimension_key='active_students')<>1 THEN
    RAISE EXCEPTION 'FAIL WS-ACT-03 capacity not reserved exactly once';
  END IF;
  IF (SELECT sum(amount) FROM credit_transactions WHERE wallet_id='c8200000-0000-0000-0000-000000000001')<>60 THEN
    RAISE EXCEPTION 'FAIL WS-ACT-04 credit balance is not 60';
  END IF;
  IF (SELECT count(*) FROM credit_transactions WHERE idempotency_key='activation:activate-one')<>1
     OR (SELECT count(*) FROM capacity_events WHERE idempotency_key='activation:activate-one')<>1
     OR (SELECT count(*) FROM activation_command_log WHERE idempotency_key='activate-one')<>1 THEN
    RAISE EXCEPTION 'FAIL WS-ACT-05 activation evidence count mismatch';
  END IF;
  RAISE NOTICE 'PASS WS-ACT-01..05 atomic activation, debit and capacity reservation';
END $assert$;

-- Exact replay returns the same result and causes no additional debit/capacity event.
SELECT activate_student_enrollment(
  'activate-one','a8200000-0000-0000-0000-000000000001',
  'c8200000-0000-0000-0000-000000000001',1,40,
  'b8100000-0000-0000-0000-000000000001');
SELECT ws_activation_expect_error('WS-ACT-06 same key with different debit is rejected',
  $q$SELECT activate_student_enrollment('activate-one','a8200000-0000-0000-0000-000000000001','c8200000-0000-0000-0000-000000000001',1,41,'b8100000-0000-0000-0000-000000000001')$q$,
  '23505');
SELECT ws_activation_expect_error('WS-ACT-07 second key cannot double-activate the same enrollment',
  $q$SELECT activate_student_enrollment('activate-one-again','a8200000-0000-0000-0000-000000000001','c8200000-0000-0000-0000-000000000001',1,10,'b8100000-0000-0000-0000-000000000001')$q$,
  '23514');

-- Insufficient credit must roll back the command log and leave enrollment/capacity untouched.
SELECT ws_activation_expect_error('WS-ACT-08 insufficient credit rejects activation',
  $q$SELECT activate_student_enrollment('activate-insufficient','a8200000-0000-0000-0000-000000000002','c8200000-0000-0000-0000-000000000001',1,70,'b8100000-0000-0000-0000-000000000001')$q$,
  '23514');
DO $assert$
BEGIN
  IF (SELECT state FROM enrollments WHERE enrollment_id='a8200000-0000-0000-0000-000000000002')<>'requested'
     OR (SELECT current_value FROM workspace_capacity_counters WHERE dimension_key='active_students')<>1
     OR (SELECT sum(amount) FROM credit_transactions WHERE wallet_id='c8200000-0000-0000-0000-000000000001')<>60
     OR EXISTS(SELECT 1 FROM activation_command_log WHERE idempotency_key='activate-insufficient') THEN
    RAISE EXCEPTION 'FAIL WS-ACT-09 insufficient-credit attempt left partial state';
  END IF;
  RAISE NOTICE 'PASS WS-ACT-09 insufficient-credit rollback leaves no partial state';
END $assert$;

-- Capacity failure after a provisional debit must roll back the debit and command record too.
SELECT ws_activation_expect_error('WS-ACT-10 full capacity rejects activation',
  $q$SELECT activate_student_enrollment('activate-capacity','a8200000-0000-0000-0000-000000000003','c8200000-0000-0000-0000-000000000001',1,10,'b8100000-0000-0000-0000-000000000001')$q$,
  '23514');
DO $assert$
BEGIN
  IF (SELECT state FROM enrollments WHERE enrollment_id='a8200000-0000-0000-0000-000000000003')<>'awaiting_consent'
     OR (SELECT current_value FROM workspace_capacity_counters WHERE dimension_key='active_students')<>1
     OR (SELECT sum(amount) FROM credit_transactions WHERE wallet_id='c8200000-0000-0000-0000-000000000001')<>60
     OR EXISTS(SELECT 1 FROM activation_command_log WHERE idempotency_key='activate-capacity')
     OR EXISTS(SELECT 1 FROM credit_transactions WHERE idempotency_key='activation:activate-capacity')
     OR EXISTS(SELECT 1 FROM capacity_events WHERE idempotency_key='activation:activate-capacity') THEN
    RAISE EXCEPTION 'FAIL WS-ACT-11 capacity failure left partial debit/reservation';
  END IF;
  RAISE NOTICE 'PASS WS-ACT-11 capacity failure rolls back debit, event and command';
END $assert$;

SELECT ws_activation_expect_error('WS-ACT-12 stale generation rejects activation',
  $q$SELECT activate_student_enrollment('activate-stale','a8200000-0000-0000-0000-000000000004','c8200000-0000-0000-0000-000000000001',2,10,'b8100000-0000-0000-0000-000000000001')$q$,
  '23514');
SELECT ws_activation_expect_error('WS-ACT-13 no accepted responsible counselor rejects activation',
  $q$SELECT activate_student_enrollment('activate-no-counselor','a8200000-0000-0000-0000-000000000004','c8200000-0000-0000-0000-000000000001',1,10,'b8100000-0000-0000-0000-000000000001')$q$,
  '23514');
SELECT ws_activation_expect_error('WS-ACT-14 suspended Workspace member cannot activate',
  $q$SELECT activate_student_enrollment('activate-suspended-actor','a8200000-0000-0000-0000-000000000004','c8200000-0000-0000-0000-000000000001',1,10,'b8100000-0000-0000-0000-000000000002')$q$,
  '42501');

-- Direct ledger inserts cannot make the wallet balance negative.
SELECT ws_activation_expect_error('WS-CREDIT-BAL-01 negative balance is rejected',
  $q$INSERT INTO credit_transactions(transaction_id,wallet_id,transaction_kind,amount,idempotency_key,reason) VALUES (gen_random_uuid(),'c8200000-0000-0000-0000-000000000001','adjustment',-1000,'negative-balance-attempt','synthetic overdraw')$q$,
  '23514');


SELECT ws_activation_expect_error('WS-ACT-16 direct active enrollment insert is rejected',
  $q$INSERT INTO enrollments(enrollment_id,student_id,ownership_generation,state,started_at) VALUES ('a8200000-0000-0000-0000-000000000099','e8100000-0000-0000-0000-000000000004',1,'active',now())$q$,
  '23514');

SELECT ws_activation_expect_error('WS-ACT-15 activation command log is append-only',
  $q$UPDATE activation_command_log SET debit_amount=1 WHERE idempotency_key='activate-one'$q$,
  '23514');

DO $test$ BEGIN RAISE NOTICE '=== WORKSPACE ACTIVATION/CREDIT/CAPACITY TESTS COMPLETED (synthetic) ==='; END $test$;
