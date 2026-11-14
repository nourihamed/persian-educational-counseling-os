-- PD-2026-11-13-A — fixed immutable question membership and order per published TestDefinitionVersion.
-- Synthetic only (D-014). Run AFTER workspace_schema_tests.sql and workspace_assessment_guardian_tests.sql
-- on the same database (reuses workspace/student/subject fixtures and published version d41..02).
-- These tests prove the database boundary. They do NOT prove service authorization or any scoring formula.
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

-- ============================ fixture: a third test and its draft version ============================
INSERT INTO test_definitions(test_id,title,subject_id,test_kind,scoring_policy_snapshot)
SELECT 'd4000000-0000-0000-0000-000000000003','Version integrity quiz',subject_id,'educational','{"negative_marking":true,"version":"v3"}'::jsonb
  FROM test_definitions WHERE test_id='d4000000-0000-0000-0000-000000000001';
INSERT INTO test_definition_versions(version_id,test_id,version_no,question_count,scoring_policy_snapshot)
VALUES ('d4100000-0000-0000-0000-000000000003','d4000000-0000-0000-0000-000000000003',1,3,'{"negative_marking":true,"version":"v3"}'::jsonb);
INSERT INTO test_definition_version_questions(version_question_id,version_id,question_no,item_ref) VALUES
 ('d4230000-0000-0000-0000-000000000001','d4100000-0000-0000-0000-000000000003',1,'synthetic-item-v3-1'),
 ('d4230000-0000-0000-0000-000000000002','d4100000-0000-0000-0000-000000000003',2,'synthetic-item-v3-2');

-- ============================ membership and order uniqueness ============================
SELECT wx_err('AVQ-01 duplicate question order within a version rejected',
 $q$INSERT INTO test_definition_version_questions(version_question_id,version_id,question_no,item_ref) VALUES (gen_random_uuid(),'d4100000-0000-0000-0000-000000000003',2,'synthetic-item-v3-other')$q$,'23505');
SELECT wx_err('AVQ-02 duplicate question membership within a version rejected',
 $q$INSERT INTO test_definition_version_questions(version_question_id,version_id,question_no,item_ref) VALUES (gen_random_uuid(),'d4100000-0000-0000-0000-000000000003',3,'synthetic-item-v3-2')$q$,'23505');
-- The membership guard runs before the foreign key and refuses an unknown parent outright.
SELECT wx_err('AVQ-03 question of a non-existent version rejected',
 $q$INSERT INTO test_definition_version_questions(version_question_id,version_id,question_no,item_ref) VALUES (gen_random_uuid(),'d4100000-0000-0000-0000-0000000000ff',1,'synthetic-item-orphan')$q$,'23514','missing');
SELECT wx_err('AVQ-04 empty item_ref rejected',
 $q$INSERT INTO test_definition_version_questions(version_question_id,version_id,question_no,item_ref) VALUES (gen_random_uuid(),'d4100000-0000-0000-0000-000000000003',3,'   ')$q$,'23514');

-- ============================ publication gates: question_count is not proof ============================
SELECT wx_err('AVQ-05 publishing a version whose membership count differs from question_count rejected',
 $q$UPDATE test_definition_versions SET status='published', published_at=now() WHERE version_id='d4100000-0000-0000-0000-000000000003'$q$,'23514','question rows');
INSERT INTO test_definition_version_questions(version_question_id,version_id,question_no,item_ref)
VALUES ('d4230000-0000-0000-0000-000000000004','d4100000-0000-0000-0000-000000000003',4,'synthetic-item-v3-4');
SELECT wx_err('AVQ-06 publishing a version with a gap in the question order rejected (1,2,4)',
 $q$UPDATE test_definition_versions SET status='published', published_at=now() WHERE version_id='d4100000-0000-0000-0000-000000000003'$q$,'23514','exactly 1..');
DELETE FROM test_definition_version_questions WHERE version_question_id='d4230000-0000-0000-0000-000000000004';
INSERT INTO test_definition_version_questions(version_question_id,version_id,question_no,item_ref)
VALUES ('d4230000-0000-0000-0000-000000000003','d4100000-0000-0000-0000-000000000003',3,'synthetic-item-v3-3');
UPDATE test_definition_versions SET delivery_mode='per_attempt' WHERE version_id='d4100000-0000-0000-0000-000000000003';
SELECT wx_err('AVQ-07 per-attempt (adaptive) delivery cannot be published in MVP — fail closed',
 $q$UPDATE test_definition_versions SET status='published', published_at=now() WHERE version_id='d4100000-0000-0000-0000-000000000003'$q$,'23514','separate Product Owner decision');
UPDATE test_definition_versions SET delivery_mode='fixed' WHERE version_id='d4100000-0000-0000-0000-000000000003';
SELECT wx_ok('AVQ-08 version with complete, contiguous, fixed membership publishes',
 $q$UPDATE test_definition_versions SET status='published', published_at=now() WHERE version_id='d4100000-0000-0000-0000-000000000003'$q$);

-- ============================ published membership is immutable ============================
SELECT wx_err('AVQ-09 question cannot be added to a published version',
 $q$INSERT INTO test_definition_version_questions(version_question_id,version_id,question_no,item_ref) VALUES (gen_random_uuid(),'d4100000-0000-0000-0000-000000000003',4,'synthetic-item-v3-late')$q$,'23514','immutable');
SELECT wx_err('AVQ-10 question of a published version cannot be changed',
 $q$UPDATE test_definition_version_questions SET item_ref='synthetic-item-swapped' WHERE version_question_id='d4230000-0000-0000-0000-000000000002'$q$,'23514','immutable');
SELECT wx_err('AVQ-11 question order of a published version cannot be reordered',
 $q$UPDATE test_definition_version_questions SET question_no=9 WHERE version_question_id='d4230000-0000-0000-0000-000000000003'$q$,'23514','immutable');
SELECT wx_err('AVQ-12 question of a published version cannot be removed',
 $q$DELETE FROM test_definition_version_questions WHERE version_question_id='d4230000-0000-0000-0000-000000000003'$q$,'23514','immutable');
-- A draft row cannot be re-parented into another version (membership laundering).
INSERT INTO test_definition_versions(version_id,test_id,version_no,question_count,scoring_policy_snapshot)
VALUES ('d4100000-0000-0000-0000-000000000004','d4000000-0000-0000-0000-000000000003',2,1,'{"negative_marking":true,"version":"v4"}'::jsonb);
INSERT INTO test_definition_version_questions(version_question_id,version_id,question_no,item_ref)
VALUES ('d4240000-0000-0000-0000-000000000001','d4100000-0000-0000-0000-000000000004',1,'synthetic-item-v4-1');
SELECT wx_err('AVQ-13 a question cannot be moved to another version',
 $q$UPDATE test_definition_version_questions SET version_id='d4100000-0000-0000-0000-000000000003' WHERE version_question_id='d4240000-0000-0000-0000-000000000001'$q$,'23514','moved to another version');

-- ============================ attempt binds to the published version policy ============================
SELECT wx_err('AVQ-14 attempt whose scoring policy differs from the published version rejected',
 $q$INSERT INTO test_attempts(attempt_id,test_id,definition_version_id,student_id,started_at,question_count,scoring_policy_snapshot) VALUES (gen_random_uuid(),'d4000000-0000-0000-0000-000000000003','d4100000-0000-0000-0000-000000000003','e1000000-0000-0000-0000-000000000001',now(),3,'{"negative_marking":false}'::jsonb)$q$,'23514','differs from the published version policy');
INSERT INTO test_attempts(attempt_id,test_id,definition_version_id,student_id,started_at,question_count,scoring_policy_snapshot)
VALUES ('e4000000-0000-0000-0000-000000000003','d4000000-0000-0000-0000-000000000003','d4100000-0000-0000-0000-000000000003','e1000000-0000-0000-0000-000000000001',now(),3,'{"negative_marking":true,"version":"v3"}'::jsonb);

-- ============================ responses cannot leave their version ============================
SELECT wx_err('AVQ-15 response citing a question of ANOTHER version rejected (cross-version substitution)',
 $q$INSERT INTO test_responses(response_id,attempt_id,definition_version_id,version_question_id,question_no,response_state) VALUES (gen_random_uuid(),'e4000000-0000-0000-0000-000000000003','d4100000-0000-0000-0000-000000000003','d4210000-0000-0000-0000-000000000001',1,'correct')$q$,'23503');
SELECT wx_err('AVQ-16 response whose definition_version_id is not the attempt version rejected',
 $q$INSERT INTO test_responses(response_id,attempt_id,definition_version_id,version_question_id,question_no,response_state) VALUES (gen_random_uuid(),'e4000000-0000-0000-0000-000000000003','d4100000-0000-0000-0000-000000000002','d4210000-0000-0000-0000-000000000001',1,'correct')$q$,'23503');
SELECT wx_err('AVQ-17 response citing the right question at the wrong order rejected',
 $q$INSERT INTO test_responses(response_id,attempt_id,definition_version_id,version_question_id,question_no,response_state) VALUES (gen_random_uuid(),'e4000000-0000-0000-0000-000000000003','d4100000-0000-0000-0000-000000000003','d4230000-0000-0000-0000-000000000001',2,'correct')$q$,'23503');
INSERT INTO test_responses(response_id,attempt_id,definition_version_id,version_question_id,question_no,response_state) VALUES
 ('f4300000-0000-0000-0000-000000000001','e4000000-0000-0000-0000-000000000003','d4100000-0000-0000-0000-000000000003','d4230000-0000-0000-0000-000000000001',1,'correct'),
 ('f4300000-0000-0000-0000-000000000002','e4000000-0000-0000-0000-000000000003','d4100000-0000-0000-0000-000000000003','d4230000-0000-0000-0000-000000000002',2,'wrong');
SELECT wx_err('AVQ-18 two answers for the same version question rejected',
 $q$INSERT INTO test_responses(response_id,attempt_id,definition_version_id,version_question_id,question_no,response_state) VALUES (gen_random_uuid(),'e4000000-0000-0000-0000-000000000003','d4100000-0000-0000-0000-000000000003','d4230000-0000-0000-0000-000000000002',2,'blank')$q$,'23505');
SELECT wx_err('AVQ-19 submission with an unanswered version question rejected (2 of 3)',
 $q$SELECT submit_test_attempt('e4000000-0000-0000-0000-000000000003',1,1,0,50,'avq-k1',sha256('avq1'::bytea))$q$,'23514','2 responses for 3');
INSERT INTO test_responses(response_id,attempt_id,definition_version_id,version_question_id,question_no,response_state)
VALUES ('f4300000-0000-0000-0000-000000000003','e4000000-0000-0000-0000-000000000003','d4100000-0000-0000-0000-000000000003','d4230000-0000-0000-0000-000000000003',3,'blank');
DO $t$ DECLARE r text; BEGIN
  r := submit_test_attempt('e4000000-0000-0000-0000-000000000003',1,1,1,33.333,'avq-k1',sha256('avq1'::bytea));
  IF r<>'submitted' THEN RAISE EXCEPTION 'FAIL AVQ-20: %', r; END IF;
  RAISE NOTICE 'PASS AVQ-20 submission accepted only when every published question is answered exactly once';
END $t$;

-- ============================ the membership list is the authority ============================
DO $t$ DECLARE n_rows integer; n_count integer; n_resp integer; BEGIN
  SELECT count(*) INTO n_rows FROM test_definition_version_questions WHERE version_id='d4100000-0000-0000-0000-000000000003';
  SELECT question_count INTO n_count FROM test_definition_versions WHERE version_id='d4100000-0000-0000-0000-000000000003';
  SELECT count(DISTINCT version_question_id) INTO n_resp FROM test_responses WHERE attempt_id='e4000000-0000-0000-0000-000000000003';
  IF n_rows<>n_count OR n_resp<>n_rows THEN
    RAISE EXCEPTION 'FAIL AVQ-21: % membership rows, question_count %, % answered questions',n_rows,n_count,n_resp;
  END IF;
  RAISE NOTICE 'PASS AVQ-21 published membership (%) = question_count (%) = answered questions (%)',n_rows,n_count,n_resp;
END $t$;
DO $t$ DECLARE n integer; BEGIN
  SELECT count(*) INTO n FROM test_definition_versions v
   WHERE v.status='published'
     AND (SELECT count(*) FROM test_definition_version_questions q WHERE q.version_id=v.version_id) <> v.question_count;
  IF n<>0 THEN RAISE EXCEPTION 'FAIL AVQ-22: % published versions whose membership does not match question_count',n; END IF;
  RAISE NOTICE 'PASS AVQ-22 every published version in this database has complete question membership';
END $t$;
SELECT 'ASSESSMENT VERSION-QUESTION TESTS PASSED (AVQ-01..AVQ-22)' AS result;
