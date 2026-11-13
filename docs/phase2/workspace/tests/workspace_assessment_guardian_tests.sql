-- WS-DOM-01 (assessment integrity) and WS-DOM-03 (guardian history) regression tests. Synthetic only (D-014).
-- Run AFTER workspace_schema_tests.sql on the same database (reuses its Workspace, student, subject, test
-- definition d4..01, published version d41..01, analysed attempt e4..01, verified guardian link c2..01).
\set ON_ERROR_STOP on
CREATE OR REPLACE FUNCTION wx_err(label text, stmt text, want text, want_msg text DEFAULT '')
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
CREATE OR REPLACE FUNCTION wx_ok(label text, stmt text) RETURNS void LANGUAGE plpgsql AS $t$
BEGIN EXECUTE stmt; RAISE NOTICE 'PASS % (accepted)',label; END; $t$;
-- Statement that must fail at COMMIT (deferred constraint trigger): run it with constraints made immediate.
CREATE OR REPLACE FUNCTION wx_err_at_commit(label text, stmt text, want_msg text) RETURNS void LANGUAGE plpgsql AS $t$
BEGIN
  BEGIN
    EXECUTE stmt;
    SET CONSTRAINTS ALL IMMEDIATE;
  EXCEPTION WHEN check_violation THEN
    IF position(want_msg IN SQLERRM)=0 THEN RAISE EXCEPTION 'FAIL %: wrong reason: %',label,SQLERRM; END IF;
    SET CONSTRAINTS ALL DEFERRED;
    RAISE NOTICE 'PASS % (rejected at constraint check, reason verified)',label;
    RETURN;
  END;
  RAISE EXCEPTION 'FAIL %: accepted without the required event',label;
END; $t$;

-- ========================= WS-DOM-01 =========================
-- Definition versions
SELECT wx_err('ASM-01 definition version cannot be inserted already published',
 $q$INSERT INTO test_definition_versions(version_id,test_id,version_no,status,question_count,scoring_policy_snapshot,published_at) VALUES (gen_random_uuid(),'d4000000-0000-0000-0000-000000000001',9,'published',5,'{}'::jsonb,now())$q$,'23514','created as draft');
SELECT wx_err('ASM-02 published version content is immutable',
 $q$UPDATE test_definition_versions SET question_count=11 WHERE version_id='d4100000-0000-0000-0000-000000000001'$q$,'23514','immutable');
SELECT wx_err('ASM-03 published version cannot be deleted',
 $q$DELETE FROM test_definition_versions WHERE version_id='d4100000-0000-0000-0000-000000000001'$q$,'23514','immutable');
INSERT INTO test_definition_versions(version_id,test_id,version_no,question_count,scoring_policy_snapshot)
VALUES ('d4100000-0000-0000-0000-000000000002','d4000000-0000-0000-0000-000000000001',2,3,'{"negative_marking":false,"version":"v2"}'::jsonb);
SELECT wx_err('ASM-04 attempt on a draft version rejected',
 $q$INSERT INTO test_attempts(attempt_id,test_id,definition_version_id,student_id,started_at,question_count,scoring_policy_snapshot) VALUES (gen_random_uuid(),'d4000000-0000-0000-0000-000000000001','d4100000-0000-0000-0000-000000000002','e1000000-0000-0000-0000-000000000001',now(),3,'{}'::jsonb)$q$,'23514','published definition version');
UPDATE test_definition_versions SET status='published', published_at=now() WHERE version_id='d4100000-0000-0000-0000-000000000002';
DO $t$ BEGIN
  IF (SELECT question_count FROM test_attempts WHERE attempt_id='e4000000-0000-0000-0000-000000000001')<>10 THEN RAISE EXCEPTION 'FAIL ASM-05'; END IF;
  RAISE NOTICE 'PASS ASM-05 publishing version 2 did not change the existing attempt denominator (10)';
END $t$;
-- Attempt creation
SELECT wx_err('ASM-06 attempt cannot be created already submitted',
 $q$INSERT INTO test_attempts(attempt_id,test_id,definition_version_id,student_id,state,started_at,submitted_at,question_count,correct_count,wrong_count,blank_count,score,scoring_policy_snapshot,submission_idempotency_key,submission_payload_hash) VALUES (gen_random_uuid(),'d4000000-0000-0000-0000-000000000001','d4100000-0000-0000-0000-000000000002','e1000000-0000-0000-0000-000000000001','submitted',now(),now(),3,3,0,0,100,'{}'::jsonb,'k-direct',sha256('x'::bytea))$q$,'23514','state started');
SELECT wx_err('ASM-07 fixed-delivery attempt with a different question_count rejected',
 $q$INSERT INTO test_attempts(attempt_id,test_id,definition_version_id,student_id,started_at,question_count,scoring_policy_snapshot) VALUES (gen_random_uuid(),'d4000000-0000-0000-0000-000000000001','d4100000-0000-0000-0000-000000000002','e1000000-0000-0000-0000-000000000001',now(),4,'{}'::jsonb)$q$,'23514','differs from fixed definition');
INSERT INTO test_definitions(test_id,title,subject_id,test_kind,scoring_policy_snapshot)
SELECT 'd4000000-0000-0000-0000-000000000002','Other quiz',subject_id,'educational','{}'::jsonb FROM test_definitions WHERE test_id='d4000000-0000-0000-0000-000000000001';
SELECT wx_err('ASM-08 attempt/version/test linkage must agree (version of another test)',
 $q$INSERT INTO test_attempts(attempt_id,test_id,definition_version_id,student_id,started_at,question_count,scoring_policy_snapshot) VALUES (gen_random_uuid(),'d4000000-0000-0000-0000-000000000002','d4100000-0000-0000-0000-000000000002','e1000000-0000-0000-0000-000000000001',now(),3,'{}'::jsonb)$q$,'23503');
INSERT INTO test_attempts(attempt_id,test_id,definition_version_id,student_id,started_at,question_count,scoring_policy_snapshot)
VALUES ('e4000000-0000-0000-0000-000000000002','d4000000-0000-0000-0000-000000000001','d4100000-0000-0000-0000-000000000002','e1000000-0000-0000-0000-000000000001',now(),3,'{"negative_marking":false,"version":"v2"}'::jsonb);
-- Responses while started
INSERT INTO test_responses(response_id,attempt_id,question_no,response_state) VALUES
 ('f4000000-0000-0000-0000-000000000011','e4000000-0000-0000-0000-000000000002',1,'correct'),
 ('f4000000-0000-0000-0000-000000000012','e4000000-0000-0000-0000-000000000002',2,'wrong');
SELECT wx_err('ASM-09 duplicate response for the same question rejected',
 $q$INSERT INTO test_responses(response_id,attempt_id,question_no,response_state) VALUES (gen_random_uuid(),'e4000000-0000-0000-0000-000000000002',2,'blank')$q$,'23505');
SELECT wx_err('ASM-10 question_no outside the delivered set rejected',
 $q$INSERT INTO test_responses(response_id,attempt_id,question_no,response_state) VALUES (gen_random_uuid(),'e4000000-0000-0000-0000-000000000002',4,'blank')$q$,'23514','outside');
SELECT wx_err('ASM-11 custom error reason requires a description',
 $q$UPDATE test_responses SET error_reason='custom' WHERE response_id='f4000000-0000-0000-0000-000000000012'$q$,'23514');
SELECT wx_err('ASM-12 a description without the custom reason is rejected',
 $q$UPDATE test_responses SET error_reason='concept', custom_error_reason='x' WHERE response_id='f4000000-0000-0000-0000-000000000012'$q$,'23514');
SELECT wx_ok('ASM-13 custom error reason with a description accepted',
 $q$UPDATE test_responses SET error_reason='custom', custom_error_reason='synthetic: misread the unit' WHERE response_id='f4000000-0000-0000-0000-000000000012'$q$);
SELECT wx_err('ASM-14 counters cannot be written while the attempt is started',
 $q$UPDATE test_attempts SET correct_count=1 WHERE attempt_id='e4000000-0000-0000-0000-000000000002'$q$,'23514');
-- Submission
SELECT wx_err('ASM-15 submission with a missing response (2 of 3) rejected',
 $q$SELECT submit_test_attempt('e4000000-0000-0000-0000-000000000002',1,1,0,50,'k-2',sha256('p2'::bytea))$q$,'23514','2 responses for 3');
DO $t$ BEGIN
  IF (SELECT state FROM test_attempts WHERE attempt_id='e4000000-0000-0000-0000-000000000002')<>'started' THEN RAISE EXCEPTION 'FAIL ASM-16'; END IF;
  RAISE NOTICE 'PASS ASM-16 rejected submission left the attempt started (no partial finalization)';
END $t$;
INSERT INTO test_responses(response_id,attempt_id,question_no,response_state) VALUES ('f4000000-0000-0000-0000-000000000013','e4000000-0000-0000-0000-000000000002',3,'blank');
SELECT wx_err('ASM-17 counters that differ from the responses rejected (2,1,0 vs 1,1,1)',
 $q$SELECT submit_test_attempt('e4000000-0000-0000-0000-000000000002',2,1,0,66,'k-2',sha256('p2'::bytea))$q$,'23514','differ from responses');
SELECT wx_err('ASM-18 counters that do not sum to the denominator rejected by any writer (direct UPDATE)',
 $q$UPDATE test_attempts SET state='submitted', submitted_at=now(), correct_count=1, wrong_count=1, blank_count=0, score=50, submission_idempotency_key='k-x', submission_payload_hash=sha256('x'::bytea) WHERE attempt_id='e4000000-0000-0000-0000-000000000002'$q$,'23514');
SELECT wx_err('ASM-19 submission without a score rejected',
 $q$SELECT submit_test_attempt('e4000000-0000-0000-0000-000000000002',1,1,1,NULL,'k-2',sha256('p2'::bytea))$q$,'23514');
DO $t$ DECLARE r text; BEGIN
  r := submit_test_attempt('e4000000-0000-0000-0000-000000000002',1,1,1,33.333,'k-2',sha256('p2'::bytea));
  IF r<>'submitted' THEN RAISE EXCEPTION 'FAIL ASM-20: %', r; END IF;
  RAISE NOTICE 'PASS ASM-20 complete, reconciled submission accepted (explicit blank counted)';
  r := submit_test_attempt('e4000000-0000-0000-0000-000000000002',1,1,1,33.333,'k-2',sha256('p2'::bytea));
  IF r<>'replayed' THEN RAISE EXCEPTION 'FAIL ASM-21: %', r; END IF;
  RAISE NOTICE 'PASS ASM-21 identical submit replay is idempotent';
END $t$;
SELECT wx_err('ASM-22 same idempotency key with a different payload rejected',
 $q$SELECT submit_test_attempt('e4000000-0000-0000-0000-000000000002',1,1,1,33.333,'k-2',sha256('OTHER'::bytea))$q$,'23505');
SELECT wx_err('ASM-23 submitted response cannot be changed',
 $q$UPDATE test_responses SET response_state='correct' WHERE response_id='f4000000-0000-0000-0000-000000000012'$q$,'23514','immutable once');
SELECT wx_err('ASM-24 submitted response cannot be deleted',
 $q$DELETE FROM test_responses WHERE response_id='f4000000-0000-0000-0000-000000000013'$q$,'23514','immutable once');
SELECT wx_err('ASM-25 response cannot be added after submission',
 $q$INSERT INTO test_responses(response_id,attempt_id,question_no,response_state) VALUES (gen_random_uuid(),'e4000000-0000-0000-0000-000000000001',3,'blank')$q$,'23514','immutable once');
SELECT wx_err('ASM-26 submitted counters and score cannot be rewritten',
 $q$UPDATE test_attempts SET score=100 WHERE attempt_id='e4000000-0000-0000-0000-000000000002'$q$,'23514');
SELECT wx_err('ASM-27 scoring snapshot of an attempt is immutable',
 $q$UPDATE test_attempts SET scoring_policy_snapshot='{"negative_marking":true}'::jsonb WHERE attempt_id='e4000000-0000-0000-0000-000000000002'$q$,'23514','immutable');
SELECT wx_err('ASM-28 analysis must not rewrite the submitted attempt',
 $q$UPDATE test_attempts SET state='analysed', score=90 WHERE attempt_id='e4000000-0000-0000-0000-000000000002'$q$,'23514','must not rewrite');
SELECT wx_err('ASM-29 submitted attempt cannot be cancelled',
 $q$UPDATE test_attempts SET state='cancelled' WHERE attempt_id='e4000000-0000-0000-0000-000000000002'$q$,'23514');
SELECT wx_err('ASM-30 submitted attempt cannot be deleted',
 $q$DELETE FROM test_attempts WHERE attempt_id='e4000000-0000-0000-0000-000000000002'$q$,'23514','cannot be deleted');

-- ========================= WS-DOM-03 =========================
SELECT wx_err('GDN-01 guardian link events are append-only (UPDATE)',
 $q$UPDATE guardian_link_events SET actor_ref='tampered'$q$,'23514','append-only');
SELECT wx_err('GDN-02 guardian permission events are append-only (DELETE)',
 $q$DELETE FROM guardian_permission_events$q$,'23514','append-only');
SELECT wx_err('GDN-03 a verified event requires an evidence reference',
 $q$INSERT INTO guardian_link_events(event_id,link_id,event_type,actor_ref,authn_event_ref,policy_version,effective_at) VALUES (gen_random_uuid(),'c2000000-0000-0000-0000-000000000001','verified','a','b','p',now())$q$,'23514');
SELECT wx_err('GDN-04 an event cannot claim another transaction',
 $q$INSERT INTO guardian_link_events(event_id,link_id,event_type,actor_ref,authn_event_ref,policy_version,effective_at,txid) VALUES (gen_random_uuid(),'c2000000-0000-0000-0000-000000000001','link_created','a','b','p',now(),1)$q$,'23514','current transaction');
SELECT wx_err_at_commit('GDN-05 a new guardian link without a link_created event is rejected',
 $q$INSERT INTO student_guardian_links(link_id,student_id,guardian_platform_user_id,relationship_type,verification_state) VALUES ('c2000000-0000-0000-0000-000000000002','e1000000-0000-0000-0000-000000000001','c1000000-0000-0000-0000-000000000002','parent','unverified')$q$,'no link_created event');
SELECT wx_err('GDN-06 revoked state requires revoked_at (and the reverse)',
 $q$UPDATE student_guardian_links SET verification_state='revoked' WHERE link_id='c2000000-0000-0000-0000-000000000001'$q$,'23514');
SELECT wx_err_at_commit('GDN-07 a new permission without a granted event is rejected',
 $q$INSERT INTO guardian_permissions(permission_id,guardian_link_id,scope_key,authority_ref,valid_from) VALUES (gen_random_uuid(),'c2000000-0000-0000-0000-000000000001','plan.read','synthetic-authority-ref',now())$q$,'no granted event');
SELECT wx_err('GDN-08 a permission cannot be edited (scope change)',
 $q$UPDATE guardian_permissions SET scope_key='finance.read' WHERE permission_id='d2000000-0000-0000-0000-000000000001'$q$,'23514','immutable except');
SELECT wx_err('GDN-09 a permission cannot be deleted',
 $q$DELETE FROM guardian_permissions WHERE permission_id='d2000000-0000-0000-0000-000000000001'$q$,'23514','never deleted');
SELECT wx_err('GDN-10 a guardian link cannot be deleted',
 $q$DELETE FROM student_guardian_links WHERE link_id='c2000000-0000-0000-0000-000000000001'$q$,'23514','never deleted');
SELECT wx_err('GDN-11 guardian link identity (student) is immutable',
 $q$UPDATE student_guardian_links SET guardian_platform_user_id=gen_random_uuid() WHERE link_id='c2000000-0000-0000-0000-000000000001'$q$,'23514','identity is immutable');
DO $t$ BEGIN
  IF (SELECT count(*) FROM guardian_permissions_effective WHERE permission_id='d2000000-0000-0000-0000-000000000001')<>1 THEN RAISE EXCEPTION 'FAIL GDN-12'; END IF;
  RAISE NOTICE 'PASS GDN-12 permission is effective while the link is verified';
END $t$;
SELECT wx_err_at_commit('GDN-13 permission revocation without a revoked event is rejected',
 $q$UPDATE guardian_permissions SET revoked_at=now() WHERE permission_id='d2000000-0000-0000-0000-000000000001'$q$,'no revoked event');
SELECT wx_err_at_commit('GDN-14 link revocation without a revoked event is rejected',
 $q$UPDATE student_guardian_links SET verification_state='revoked', revoked_at=now() WHERE link_id='c2000000-0000-0000-0000-000000000001'$q$,'without a revoked event');
-- Legitimate link revocation with its event, one transaction.
BEGIN;
UPDATE student_guardian_links SET verification_state='revoked', revoked_at=now() WHERE link_id='c2000000-0000-0000-0000-000000000001';
INSERT INTO guardian_link_events(event_id,link_id,event_type,actor_ref,authn_event_ref,policy_version,effective_at)
VALUES (gen_random_uuid(),'c2000000-0000-0000-0000-000000000001','revoked','synthetic-actor','synthetic-authn-2','synthetic-policy-v1',now());
COMMIT;
DO $t$ BEGIN
  IF (SELECT count(*) FROM guardian_permissions_effective WHERE guardian_link_id='c2000000-0000-0000-0000-000000000001')<>0 THEN RAISE EXCEPTION 'FAIL GDN-15'; END IF;
  RAISE NOTICE 'PASS GDN-15 revoking the link makes its stored permissions ineffective immediately';
  IF (SELECT count(*) FROM guardian_link_events WHERE link_id='c2000000-0000-0000-0000-000000000001')<>3 THEN RAISE EXCEPTION 'FAIL GDN-16'; END IF;
  RAISE NOTICE 'PASS GDN-16 history preserved: link_created, verified and revoked events all remain';
END $t$;
SELECT wx_err('GDN-17 a revoked link is terminal (cannot be re-verified in place)',
 $q$UPDATE student_guardian_links SET verification_state='verified', revoked_at=NULL WHERE link_id='c2000000-0000-0000-0000-000000000001'$q$,'23514','terminal');
SELECT wx_err('GDN-18 a permission cannot be granted on a link that is not verified',
 $q$INSERT INTO guardian_permissions(permission_id,guardian_link_id,scope_key,authority_ref,valid_from) VALUES (gen_random_uuid(),'c2000000-0000-0000-0000-000000000001','plan.read','synthetic-authority-ref',now())$q$,'23514','currently verified');
DO $t$ BEGIN RAISE NOTICE '=== WS-DOM-01 / WS-DOM-03 TESTS COMPLETED (synthetic) ==='; END $t$;
