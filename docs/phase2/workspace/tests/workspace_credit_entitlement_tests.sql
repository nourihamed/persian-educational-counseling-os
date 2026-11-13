-- PD-2026-11-13-D — Student Credit entitlement lifecycle (archive return window, student-bound reserved
-- credit, free reactivation only inside the ORIGINAL entitlement period). Synthetic only (D-014).
-- Run on a FRESH DB after workspace_schema_draft.sql, workspace_activation_transactions.sql,
-- workspace_governance_events_draft.sql, workspace_archive_transactions.sql and workspace_roles_setup_draft.sql
-- (-v workspace_key). Commands are called as the Workspace runtime role, not as superuser.
--
-- Window semantics under test: an exact 168-hour interval from the stored activation timestamptz, boundary
-- INCLUSIVE. Boundary cases back-date the fixture by disabling the entitlement row guard as the table owner
-- for that one statement; this is a synthetic clock, not a supported runtime operation, and it is the only
-- way to exercise the real command path at the boundary without waiting seven days.
\set ON_ERROR_STOP on
SET app.workspace_key = :'workspace_key';
SELECT 'ws_'||current_setting('app.workspace_key')||'_runtime' AS runtime_role \gset
SELECT 'ws_'||current_setting('app.workspace_key')||'_synth_exec' AS synth_role \gset
CREATE OR REPLACE FUNCTION cr_err(label text, stmt text, want text, want_msg text DEFAULT '')
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
-- Synthetic fixture clock: move an entitlement's activation/period into the past.
CREATE OR REPLACE FUNCTION cr_backdate(p_student uuid, p_activated timestamptz, p_period_end timestamptz)
RETURNS void LANGUAGE plpgsql AS $t$
DECLARE v_id uuid;
BEGIN
  SELECT entitlement_id INTO v_id FROM public.student_entitlements WHERE student_id=p_student;
  IF v_id IS NULL THEN RAISE EXCEPTION 'no entitlement for student %', p_student; END IF;
  ALTER TABLE public.student_entitlements DISABLE TRIGGER student_entitlements_guard;
  UPDATE public.student_entitlements SET activated_at=p_activated, period_end=p_period_end WHERE entitlement_id=v_id;
  ALTER TABLE public.student_entitlements ENABLE TRIGGER student_entitlements_guard;
END; $t$;

INSERT INTO workspace_profile(singleton,workspace_id,workspace_type) VALUES(true,'a7500000-0000-0000-0000-000000000001','organization');
INSERT INTO workspace_memberships(membership_id,platform_user_id,status) VALUES
 ('b7500000-0000-0000-0000-000000000001','c7500000-0000-0000-0000-000000000001','active'),
 ('b7500000-0000-0000-0000-000000000002','c7500000-0000-0000-0000-000000000002','active'),     -- active, NOT a counselor
 ('b7500000-0000-0000-0000-000000000003','c7500000-0000-0000-0000-000000000003','suspended'),  -- counselor, inactive
 ('b7500000-0000-0000-0000-000000000004','c7500000-0000-0000-0000-000000000004','active');     -- a second real counselor
INSERT INTO membership_roles(membership_id,role_key) VALUES
 ('b7500000-0000-0000-0000-000000000001','counselor'),
 ('b7500000-0000-0000-0000-000000000002','assistant'),
 ('b7500000-0000-0000-0000-000000000003','counselor'),
 ('b7500000-0000-0000-0000-000000000004','counselor');
INSERT INTO students(student_id,platform_student_id,display_name,grade_key,lifecycle_state) VALUES
 ('e7500000-0000-0000-0000-00000000000a','f7500000-0000-0000-0000-00000000000a','Credit A','grade_10','active'),
 ('e7500000-0000-0000-0000-00000000000b','f7500000-0000-0000-0000-00000000000b','Credit B','grade_10','active'),
 ('e7500000-0000-0000-0000-00000000000c','f7500000-0000-0000-0000-00000000000c','Credit C','grade_10','active'),
 ('e7500000-0000-0000-0000-00000000000d','f7500000-0000-0000-0000-00000000000d','Credit D','grade_10','active');
INSERT INTO enrollments(enrollment_id,student_id,ownership_generation,state) VALUES
 ('a7600000-0000-0000-0000-00000000000a','e7500000-0000-0000-0000-00000000000a',1,'requested'),
 ('a7600000-0000-0000-0000-00000000000b','e7500000-0000-0000-0000-00000000000b',1,'requested'),
 ('a7600000-0000-0000-0000-00000000000c','e7500000-0000-0000-0000-00000000000c',1,'requested'),
 ('a7600000-0000-0000-0000-00000000000d','e7500000-0000-0000-0000-00000000000d',1,'requested');
INSERT INTO counselor_assignments(assignment_id,enrollment_id,counselor_membership_id,is_responsible,state,accepted_at)
SELECT gen_random_uuid(),enrollment_id,'b7500000-0000-0000-0000-000000000001',true,'active',now() FROM enrollments;
INSERT INTO credit_wallets(wallet_id,unit_code) VALUES('c7600000-0000-0000-0000-000000000001','CRD');
INSERT INTO credit_transactions(transaction_id,wallet_id,transaction_kind,amount,idempotency_key,reason)
VALUES(gen_random_uuid(),'c7600000-0000-0000-0000-000000000001','grant',100,'credit-fixture-grant','synthetic opening credit');
INSERT INTO workspace_capacity_counters(dimension_key,current_value,max_value) VALUES('active_students',0,3);

-- ============================ activation records one entitlement ============================
SET SESSION AUTHORIZATION :"synth_role";
SELECT activate_student_enrollment_synthetic('cr-act-a','a7600000-0000-0000-0000-00000000000a','c7600000-0000-0000-0000-000000000001',1,10,'b7500000-0000-0000-0000-000000000001',now()+interval '30 days');
-- H-04: the period is validated against the wall clock read after the locks, inside the command.
SELECT cr_err('CRD-01 activation whose entitlement period has already ended is rejected',
 $q$SELECT activate_student_enrollment_synthetic('cr-act-bad','a7600000-0000-0000-0000-00000000000b','c7600000-0000-0000-0000-000000000001',1,10,'b7500000-0000-0000-0000-000000000001',now()-interval '1 day')$q$,'23514','before this activation committed');
SELECT cr_err('CRD-01b activation without any entitlement period is rejected',
 $q$SELECT activate_student_enrollment_synthetic('cr-act-null','a7600000-0000-0000-0000-00000000000b','c7600000-0000-0000-0000-000000000001',1,10,'b7500000-0000-0000-0000-000000000001',NULL)$q$,'22023','entitlement period end');
RESET SESSION AUTHORIZATION;
DO $t$ DECLARE e public.student_entitlements%ROWTYPE; BEGIN
  SELECT * INTO e FROM student_entitlements WHERE student_id='e7500000-0000-0000-0000-00000000000a';
  IF e.state<>'consumed' OR e.credit_amount<>10 OR e.reversal_transaction_id IS NOT NULL THEN RAISE EXCEPTION 'FAIL CRD-02'; END IF;
  IF (SELECT available_balance FROM credit_wallet_balances WHERE wallet_id='c7600000-0000-0000-0000-000000000001')<>90 THEN RAISE EXCEPTION 'FAIL CRD-02 balance'; END IF;
  RAISE NOTICE 'PASS CRD-02 activation recorded one consumed entitlement and spent exactly 10 (available 90)';
END $t$;

-- ============================ archive inside the window returns the credit ============================
SET SESSION AUTHORIZATION :"runtime_role";
SELECT archive_student_enrollment('cr-arc-a','a7600000-0000-0000-0000-00000000000a',1,'b7500000-0000-0000-0000-000000000001','offboarding');
RESET SESSION AUTHORIZATION;
DO $t$ DECLARE e public.student_entitlements%ROWTYPE; b record; BEGIN
  SELECT * INTO e FROM student_entitlements WHERE student_id='e7500000-0000-0000-0000-00000000000a';
  SELECT * INTO b FROM credit_wallet_balances WHERE wallet_id='c7600000-0000-0000-0000-000000000001';
  IF e.state<>'reserved' OR e.reversal_transaction_id IS NULL OR e.reserved_at IS NULL THEN RAISE EXCEPTION 'FAIL CRD-03 state'; END IF;
  IF (SELECT count(*) FROM credit_transactions WHERE transaction_kind='reversal' AND related_transaction_id=e.debit_transaction_id)<>1 THEN RAISE EXCEPTION 'FAIL CRD-03 reversal'; END IF;
  IF (SELECT amount FROM credit_transactions WHERE transaction_id=e.reversal_transaction_id)<>10 THEN RAISE EXCEPTION 'FAIL CRD-03 amount'; END IF;
  IF b.ledger_balance<>100 OR b.reserved_credits<>10 OR b.available_balance<>90 THEN
    RAISE EXCEPTION 'FAIL CRD-03 balances: ledger %, reserved %, available %',b.ledger_balance,b.reserved_credits,b.available_balance;
  END IF;
  RAISE NOTICE 'PASS CRD-03 archive inside the window: original debit preserved, one compensating reversal, credit reserved, available still 90';
END $t$;
SELECT cr_err('CRD-04 a second compensating reversal of the same debit is rejected (no double compensation)',
 $q$INSERT INTO credit_transactions(transaction_id,wallet_id,transaction_kind,amount,idempotency_key,related_transaction_id,student_id,reason) SELECT gen_random_uuid(),'c7600000-0000-0000-0000-000000000001','reversal',10,'cr-double-reversal',e.debit_transaction_id,e.student_id,'synthetic double compensation' FROM student_entitlements e WHERE e.student_id='e7500000-0000-0000-0000-00000000000a'$q$,'23505','already been reversed');
SELECT cr_err('CRD-05 the original activation debit cannot be edited or deleted',
 $q$DELETE FROM credit_transactions WHERE transaction_kind='activation_debit'$q$,'23514','append-only');

-- ============================ reserved credit is not spendable by anyone else ============================
SET SESSION AUTHORIZATION :"synth_role";
SELECT cr_err('CRD-06 the reserved credit cannot fund another student''s activation',
 $q$SELECT activate_student_enrollment_synthetic('cr-act-d','a7600000-0000-0000-0000-00000000000d','c7600000-0000-0000-0000-000000000001',1,95,'b7500000-0000-0000-0000-000000000001',now()+interval '30 days')$q$,'23514','reserved for named students');
SELECT activate_student_enrollment_synthetic('cr-act-d2','a7600000-0000-0000-0000-00000000000d','c7600000-0000-0000-0000-000000000001',1,90,'b7500000-0000-0000-0000-000000000001',now()+interval '30 days');
RESET SESSION AUTHORIZATION;
DO $t$ BEGIN
  IF (SELECT available_balance FROM credit_wallet_balances WHERE wallet_id='c7600000-0000-0000-0000-000000000001')<>0 THEN RAISE EXCEPTION 'FAIL CRD-07'; END IF;
  RAISE NOTICE 'PASS CRD-07 another student could spend only the 90 that were not reserved';
END $t$;

-- ============================ free reactivation inside the original period ============================
SET SESSION AUTHORIZATION :"runtime_role";
-- H-06: an active membership is not a counselor, and a suspended counselor is not available.
SELECT cr_err('CRD-07a an active member who does not hold the counselor role cannot be appointed responsible',
 $q$SELECT reactivate_student_enrollment('cr-react-noncounselor','e7500000-0000-0000-0000-00000000000a','a7600000-0000-0000-0000-0000000000a1',1,'b7500000-0000-0000-0000-000000000001','b7500000-0000-0000-0000-000000000002')$q$,'42501','does not hold the counselor role');
SELECT cr_err('CRD-07b a suspended counselor cannot be appointed responsible',
 $q$SELECT reactivate_student_enrollment('cr-react-suspended','e7500000-0000-0000-0000-00000000000a','a7600000-0000-0000-0000-0000000000a2',1,'b7500000-0000-0000-0000-000000000001','b7500000-0000-0000-0000-000000000003')$q$,'42501','not an active Workspace member');
RESET SESSION AUTHORIZATION;
DO $t$ BEGIN
  IF EXISTS (SELECT 1 FROM enrollments WHERE enrollment_id IN ('a7600000-0000-0000-0000-0000000000a1','a7600000-0000-0000-0000-0000000000a2'))
     OR EXISTS (SELECT 1 FROM reactivation_command_log WHERE idempotency_key LIKE 'cr-react-%') THEN
    RAISE EXCEPTION 'FAIL CRD-07c a refused reactivation left state behind';
  END IF;
  RAISE NOTICE 'PASS CRD-07c neither refused appointment created an enrollment or a command row';
END $t$;
SET SESSION AUTHORIZATION :"runtime_role";
SELECT reactivate_student_enrollment('cr-react-a','e7500000-0000-0000-0000-00000000000a','a7600000-0000-0000-0000-0000000000aa',1,'b7500000-0000-0000-0000-000000000001','b7500000-0000-0000-0000-000000000001');
RESET SESSION AUTHORIZATION;
DO $t$ DECLARE e public.student_entitlements%ROWTYPE; b record; BEGIN
  SELECT * INTO e FROM student_entitlements WHERE student_id='e7500000-0000-0000-0000-00000000000a';
  SELECT * INTO b FROM credit_wallet_balances WHERE wallet_id='c7600000-0000-0000-0000-000000000001';
  IF e.state<>'consumed' OR e.reconsumed_at IS NULL THEN RAISE EXCEPTION 'FAIL CRD-08 entitlement'; END IF;
  IF (SELECT count(*) FROM credit_transactions WHERE student_id='e7500000-0000-0000-0000-00000000000a')<>2 THEN RAISE EXCEPTION 'FAIL CRD-08 no new debit expected'; END IF;
  IF (SELECT lifecycle_state FROM students WHERE student_id='e7500000-0000-0000-0000-00000000000a')<>'active'
     OR (SELECT archived_at FROM students WHERE student_id='e7500000-0000-0000-0000-00000000000a') IS NOT NULL
     OR (SELECT state FROM enrollments WHERE enrollment_id='a7600000-0000-0000-0000-0000000000aa')<>'active' THEN RAISE EXCEPTION 'FAIL CRD-08 state'; END IF;
  IF (SELECT state FROM enrollments WHERE enrollment_id='a7600000-0000-0000-0000-00000000000a')<>'archived' THEN RAISE EXCEPTION 'FAIL CRD-08 history'; END IF;
  IF b.available_balance<>0 OR b.reserved_credits<>0 OR b.recommitted_credits<>10 THEN
    RAISE EXCEPTION 'FAIL CRD-08 balances: reserved %, recommitted %, available %',b.reserved_credits,b.recommitted_credits,b.available_balance;
  END IF;
  RAISE NOTICE 'PASS CRD-08 reactivation consumed the SAME returned credit with no new debit; the historical enrollment is kept';
END $t$;
DO $t$ DECLARE p timestamptz; BEGIN
  SELECT period_end INTO p FROM student_entitlements WHERE student_id='e7500000-0000-0000-0000-00000000000a';
  IF p > now()+interval '30 days' THEN RAISE EXCEPTION 'FAIL CRD-09: entitlement period was extended to %',p; END IF;
  RAISE NOTICE 'PASS CRD-09 archive and reactivation did not restart or extend the original entitlement period';
END $t$;
SET SESSION AUTHORIZATION :"runtime_role";
DO $t$ DECLARE r uuid; BEGIN
  r := reactivate_student_enrollment('cr-react-a','e7500000-0000-0000-0000-00000000000a','a7600000-0000-0000-0000-0000000000aa',1,'b7500000-0000-0000-0000-000000000001','b7500000-0000-0000-0000-000000000001');
  IF r<>'a7600000-0000-0000-0000-0000000000aa' THEN RAISE EXCEPTION 'FAIL CRD-10: %',r; END IF;
  RAISE NOTICE 'PASS CRD-10 exact reactivation replay returned the same enrollment without a second effect';
END $t$;
SELECT cr_err('CRD-11 reactivation key reused with a different intent rejected',
 $q$SELECT reactivate_student_enrollment('cr-react-a','e7500000-0000-0000-0000-00000000000a','a7600000-0000-0000-0000-0000000000ab',1,'b7500000-0000-0000-0000-000000000001','b7500000-0000-0000-0000-000000000001')$q$,'23505','different intent');
-- M-01: the same key with the SAME everything except the counselor is a different request.
SELECT cr_err('CRD-11b reactivation replay naming a different counselor is rejected',
 $q$SELECT reactivate_student_enrollment('cr-react-a','e7500000-0000-0000-0000-00000000000a','a7600000-0000-0000-0000-0000000000aa',1,'b7500000-0000-0000-0000-000000000001','b7500000-0000-0000-0000-000000000004')$q$,'23505','different intent');
RESET SESSION AUTHORIZATION;
DO $t$ BEGIN
  IF (SELECT current_value FROM workspace_capacity_counters WHERE dimension_key='active_students')<>2
     OR (SELECT count(*) FROM capacity_events WHERE idempotency_key='reactivation:cr-react-a')<>1 THEN RAISE EXCEPTION 'FAIL CRD-12'; END IF;
  IF (SELECT counselor_membership_id FROM reactivation_command_log WHERE idempotency_key='cr-react-a')<>'b7500000-0000-0000-0000-000000000001' THEN
    RAISE EXCEPTION 'FAIL CRD-12b the command log did not bind the responsible counselor';
  END IF;
  RAISE NOTICE 'PASS CRD-12 reactivation reserved exactly one capacity slot, replay reserved nothing more';
END $t$;

-- ============================ second archive does not compensate twice ============================
SET SESSION AUTHORIZATION :"runtime_role";
SELECT archive_student_enrollment('cr-arc-a2','a7600000-0000-0000-0000-0000000000aa',1,'b7500000-0000-0000-0000-000000000001','offboarding again');
RESET SESSION AUTHORIZATION;
DO $t$ DECLARE e public.student_entitlements%ROWTYPE; BEGIN
  SELECT * INTO e FROM student_entitlements WHERE student_id='e7500000-0000-0000-0000-00000000000a';
  IF e.state<>'reserved' THEN RAISE EXCEPTION 'FAIL CRD-13 state'; END IF;
  IF (SELECT count(*) FROM credit_transactions WHERE student_id='e7500000-0000-0000-0000-00000000000a')<>2 THEN RAISE EXCEPTION 'FAIL CRD-13 ledger grew'; END IF;
  IF (SELECT credit_returned FROM archive_command_log WHERE idempotency_key='cr-arc-a2')<>false THEN RAISE EXCEPTION 'FAIL CRD-13 log'; END IF;
  RAISE NOTICE 'PASS CRD-13 archiving a reactivated student reserved the same credit again without a second compensation';
END $t$;

-- ============================ exact boundary and past the boundary ============================
-- More credit and capacity for the remaining scenarios.
INSERT INTO credit_transactions(transaction_id,wallet_id,transaction_kind,amount,idempotency_key,reason)
VALUES(gen_random_uuid(),'c7600000-0000-0000-0000-000000000001','grant',50,'credit-fixture-grant-2','synthetic top-up');
UPDATE workspace_capacity_counters SET max_value=10 WHERE dimension_key='active_students';
INSERT INTO students(student_id,platform_student_id,display_name,grade_key,lifecycle_state)
VALUES ('e7500000-0000-0000-0000-00000000000e','f7500000-0000-0000-0000-00000000000e','Credit E','grade_10','active');
INSERT INTO enrollments(enrollment_id,student_id,ownership_generation,state)
VALUES ('a7600000-0000-0000-0000-00000000000e','e7500000-0000-0000-0000-00000000000e',1,'requested');
INSERT INTO counselor_assignments(assignment_id,enrollment_id,counselor_membership_id,is_responsible,state,accepted_at)
VALUES (gen_random_uuid(),'a7600000-0000-0000-0000-00000000000e','b7500000-0000-0000-0000-000000000001',true,'active',now());

SET SESSION AUTHORIZATION :"synth_role";
SELECT activate_student_enrollment_synthetic('cr-act-b','a7600000-0000-0000-0000-00000000000b','c7600000-0000-0000-0000-000000000001',1,5,'b7500000-0000-0000-0000-000000000001',now()+interval '30 days');
SELECT activate_student_enrollment_synthetic('cr-act-c','a7600000-0000-0000-0000-00000000000c','c7600000-0000-0000-0000-000000000001',1,5,'b7500000-0000-0000-0000-000000000001',now()+interval '30 days');
SELECT activate_student_enrollment_synthetic('cr-act-e','a7600000-0000-0000-0000-00000000000e','c7600000-0000-0000-0000-000000000001',1,5,'b7500000-0000-0000-0000-000000000001',now()+interval '30 days');
RESET SESSION AUTHORIZATION;
-- The boundary is bracketed to one second: B has one second of window left, C passed it one second ago.
-- An exactly-equal instant cannot be observed against a wall clock; the comparison operator in the command
-- is <= (inclusive), which these two cases bracket and the file header documents.
SELECT cr_backdate('e7500000-0000-0000-0000-00000000000b', now()-interval '168 hours'+interval '1 second', now()+interval '30 days');
SELECT cr_backdate('e7500000-0000-0000-0000-00000000000c', now()-interval '168 hours 1 second', now()+interval '30 days');
SET SESSION AUTHORIZATION :"runtime_role";
SELECT archive_student_enrollment('cr-arc-b','a7600000-0000-0000-0000-00000000000b',1,'b7500000-0000-0000-0000-000000000001','boundary');
SELECT archive_student_enrollment('cr-arc-c','a7600000-0000-0000-0000-00000000000c',1,'b7500000-0000-0000-0000-000000000001','past boundary');
RESET SESSION AUTHORIZATION;
DO $t$ DECLARE b public.student_entitlements%ROWTYPE; c public.student_entitlements%ROWTYPE; BEGIN
  SELECT * INTO b FROM student_entitlements WHERE student_id='e7500000-0000-0000-0000-00000000000b';
  SELECT * INTO c FROM student_entitlements WHERE student_id='e7500000-0000-0000-0000-00000000000c';
  IF b.state<>'reserved' OR b.reversal_transaction_id IS NULL THEN RAISE EXCEPTION 'FAIL CRD-14: archive inside the window did not return the credit'; END IF;
  IF (SELECT credit_returned FROM archive_command_log WHERE idempotency_key='cr-arc-b')<>true THEN RAISE EXCEPTION 'FAIL CRD-14 log'; END IF;
  RAISE NOTICE 'PASS CRD-14 archive with one second of the 168-hour window left still returns the credit';
  IF c.state<>'consumed' OR c.reversal_transaction_id IS NOT NULL THEN RAISE EXCEPTION 'FAIL CRD-15: credit returned past the window'; END IF;
  IF (SELECT count(*) FROM credit_transactions WHERE student_id='e7500000-0000-0000-0000-00000000000c')<>1 THEN RAISE EXCEPTION 'FAIL CRD-15 ledger'; END IF;
  IF (SELECT credit_returned FROM archive_command_log WHERE idempotency_key='cr-arc-c')<>false THEN RAISE EXCEPTION 'FAIL CRD-15 log'; END IF;
  RAISE NOTICE 'PASS CRD-15 archive one second past the 168-hour window returns nothing (no automatic return)';
END $t$;

-- ============================ reactivation outside the entitlement ============================
SET SESSION AUTHORIZATION :"runtime_role";
SELECT cr_err('CRD-16 reactivation without a reserved entitlement requires a new credit debit',
 $q$SELECT reactivate_student_enrollment('cr-react-c','e7500000-0000-0000-0000-00000000000c','a7600000-0000-0000-0000-0000000000cc',1,'b7500000-0000-0000-0000-000000000001','b7500000-0000-0000-0000-000000000001')$q$,'23514','requires a new credit debit');
RESET SESSION AUTHORIZATION;
-- B's reserved credit outlives its own period.
SELECT cr_backdate('e7500000-0000-0000-0000-00000000000b', now()-interval '200 hours', now()-interval '1 hour');
SET SESSION AUTHORIZATION :"runtime_role";
SELECT cr_err('CRD-17 reactivation after the original entitlement period ended is refused',
 $q$SELECT reactivate_student_enrollment('cr-react-b','e7500000-0000-0000-0000-00000000000b','a7600000-0000-0000-0000-0000000000bb',1,'b7500000-0000-0000-0000-000000000001','b7500000-0000-0000-0000-000000000001')$q$,'23514','entitlement period ended');
RESET SESSION AUTHORIZATION;
DO $t$ BEGIN
  IF (SELECT count(*) FROM enrollments WHERE enrollment_id='a7600000-0000-0000-0000-0000000000bb')<>0
     OR (SELECT count(*) FROM reactivation_command_log WHERE idempotency_key='cr-react-b')<>0
     OR (SELECT state FROM student_entitlements WHERE student_id='e7500000-0000-0000-0000-00000000000b')<>'reserved' THEN RAISE EXCEPTION 'FAIL CRD-18'; END IF;
  IF (SELECT count(*) FROM expired_reserved_entitlements WHERE student_id='e7500000-0000-0000-0000-00000000000b')<>1 THEN RAISE EXCEPTION 'FAIL CRD-18 view'; END IF;
  RAISE NOTICE 'PASS CRD-18 the refused reactivation left no enrollment, no log row and the credit still reserved (disposition is an OPEN decision)';
END $t$;

-- ============================ rollback on partial failure ============================
SET SESSION AUTHORIZATION :"runtime_role";
SELECT archive_student_enrollment('cr-arc-e','a7600000-0000-0000-0000-00000000000e',1,'b7500000-0000-0000-0000-000000000001','rollback fixture');
RESET SESSION AUTHORIZATION;
UPDATE workspace_capacity_counters SET max_value=current_value WHERE dimension_key='active_students';
SET SESSION AUTHORIZATION :"runtime_role";
SELECT cr_err('CRD-19 reactivation that cannot reserve capacity fails',
 $q$SELECT reactivate_student_enrollment('cr-react-e','e7500000-0000-0000-0000-00000000000e','a7600000-0000-0000-0000-0000000000ee',1,'b7500000-0000-0000-0000-000000000001','b7500000-0000-0000-0000-000000000001')$q$,'23514');
RESET SESSION AUTHORIZATION;
DO $t$ DECLARE e public.student_entitlements%ROWTYPE; BEGIN
  SELECT * INTO e FROM student_entitlements WHERE student_id='e7500000-0000-0000-0000-00000000000e';
  IF (SELECT count(*) FROM enrollments WHERE enrollment_id='a7600000-0000-0000-0000-0000000000ee')<>0
     OR (SELECT count(*) FROM reactivation_command_log WHERE idempotency_key='cr-react-e')<>0
     OR (SELECT count(*) FROM capacity_events WHERE idempotency_key='reactivation:cr-react-e')<>0
     OR e.state<>'reserved' OR e.reconsumed_at IS NOT NULL
     OR (SELECT lifecycle_state FROM students WHERE student_id='e7500000-0000-0000-0000-00000000000e')<>'archived' THEN RAISE EXCEPTION 'FAIL CRD-20'; END IF;
  RAISE NOTICE 'PASS CRD-20 the failed reactivation rolled back enrollment, assignment, capacity, entitlement and log together';
END $t$;
UPDATE workspace_capacity_counters SET max_value=10 WHERE dimension_key='active_students';

-- ============================ entitlement row integrity ============================
SELECT cr_err('CRD-21 an entitlement cannot be deleted',
 $q$DELETE FROM student_entitlements WHERE student_id='e7500000-0000-0000-0000-00000000000c'$q$,'23514','not deletable');
SELECT cr_err('CRD-22 the entitlement period cannot be extended',
 $q$UPDATE student_entitlements SET period_end=now()+interval '999 days' WHERE student_id='e7500000-0000-0000-0000-00000000000c'$q$,'23514','immutable');
SELECT cr_err('CRD-23 an entitlement cannot be moved to another student',
 $q$UPDATE student_entitlements SET student_id='e7500000-0000-0000-0000-00000000000d' WHERE student_id='e7500000-0000-0000-0000-00000000000c'$q$,'23514','immutable');
SELECT cr_err('CRD-24 an entitlement cannot be reserved without its compensating reversal',
 $q$UPDATE student_entitlements SET state='reserved', reserved_at=now() WHERE student_id='e7500000-0000-0000-0000-00000000000c'$q$,'23514');
SELECT cr_err('CRD-25 an entitlement cannot be created already reserved',
 $q$INSERT INTO student_entitlements(entitlement_id,student_id,debit_transaction_id,credit_amount,activated_at,period_end,state,reserved_at) SELECT gen_random_uuid(),'e7500000-0000-0000-0000-00000000000d',t.transaction_id,1,now(),now()+interval '1 day','reserved',now() FROM credit_transactions t WHERE t.transaction_kind='grant' LIMIT 1$q$,'23514');
SELECT cr_err('CRD-26 two entitlements cannot share one activation debit',
 $q$INSERT INTO student_entitlements(entitlement_id,student_id,debit_transaction_id,credit_amount,activated_at,period_end,state) SELECT gen_random_uuid(),'e7500000-0000-0000-0000-00000000000d',e.debit_transaction_id,1,now(),now()+interval '1 day','consumed' FROM student_entitlements e WHERE e.student_id='e7500000-0000-0000-0000-00000000000c'$q$,'23505');

DO $t$ DECLARE b record; BEGIN
  SELECT * INTO b FROM credit_wallet_balances WHERE wallet_id='c7600000-0000-0000-0000-000000000001';
  IF b.ledger_balance <> (SELECT sum(amount) FROM credit_transactions WHERE wallet_id='c7600000-0000-0000-0000-000000000001') THEN RAISE EXCEPTION 'FAIL CRD-27'; END IF;
  IF b.available_balance <> b.ledger_balance - b.reserved_credits - b.recommitted_credits THEN RAISE EXCEPTION 'FAIL CRD-27 identity'; END IF;
  RAISE NOTICE 'PASS CRD-27 wallet view identity holds: available = ledger - reserved - recommitted (ledger %, reserved %, recommitted %, available %)',
    b.ledger_balance,b.reserved_credits,b.recommitted_credits,b.available_balance;
END $t$;
-- ============================ H-02: the production-intended activation path fails closed ============================
INSERT INTO students(student_id,platform_student_id,display_name,grade_key,lifecycle_state)
VALUES ('e7500000-0000-0000-0000-00000000000f','f7500000-0000-0000-0000-00000000000f','Credit F','grade_10','active');
INSERT INTO enrollments(enrollment_id,student_id,ownership_generation,state)
VALUES ('a7600000-0000-0000-0000-00000000000f','e7500000-0000-0000-0000-00000000000f',1,'requested');
INSERT INTO counselor_assignments(assignment_id,enrollment_id,counselor_membership_id,is_responsible,state,accepted_at)
VALUES (gen_random_uuid(),'a7600000-0000-0000-0000-00000000000f','b7500000-0000-0000-0000-000000000001',true,'active',now());
SET SESSION AUTHORIZATION :"runtime_role";
SELECT cr_err('CRD-28 the production-intended activation path fails closed: no approved entitlement period source',
 $q$SELECT activate_student_enrollment('cr-act-f','a7600000-0000-0000-0000-00000000000f','c7600000-0000-0000-0000-000000000001',1,1,'b7500000-0000-0000-0000-000000000001')$q$,'0A000','OQ-CRD-3');
SELECT cr_err('CRD-29 the Runtime cannot reach the synthetic caller-supplied-period command',
 $q$SELECT activate_student_enrollment_synthetic('cr-act-f2','a7600000-0000-0000-0000-00000000000f','c7600000-0000-0000-0000-000000000001',1,1,'b7500000-0000-0000-0000-000000000001',now()+interval '30 days')$q$,'42501');
SELECT cr_err('CRD-30 the Runtime cannot reach the entitlement period resolver directly',
 $q$SELECT resolve_student_entitlement_period('e7500000-0000-0000-0000-00000000000f',1,now())$q$,'42501');
RESET SESSION AUTHORIZATION;
DO $t$ BEGIN
  IF (SELECT state FROM enrollments WHERE enrollment_id='a7600000-0000-0000-0000-00000000000f')<>'requested'
     OR EXISTS (SELECT 1 FROM student_entitlements WHERE student_id='e7500000-0000-0000-0000-00000000000f')
     OR EXISTS (SELECT 1 FROM activation_command_log WHERE idempotency_key IN ('cr-act-f','cr-act-f2')) THEN
    RAISE EXCEPTION 'FAIL CRD-31 the refused activation left partial state';
  END IF;
  RAISE NOTICE 'PASS CRD-31 the fail-closed activation created no enrollment state, entitlement or command row';
END $t$;
SELECT 'STUDENT CREDIT ENTITLEMENT TESTS COMPLETED (CRD-01..CRD-31, including H-06/M-01)' AS result;
