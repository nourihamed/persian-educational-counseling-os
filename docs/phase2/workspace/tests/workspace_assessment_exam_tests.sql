-- =============================================================================
-- EXAM DEFINITION VERSIONS, PER-SUBJECT RESULTS, ANALYSIS VERSIONS AND THE SCORING ALGORITHM VERSION
-- (SYNTHETIC ONLY, D-014). Run on a fresh database after workspace_schema_draft.sql,
-- workspace_activation_transactions.sql, workspace_governance_events_draft.sql and
-- workspace_assessment_exam_draft.sql.
--
-- These cover the structures that ASSESSMENT_DOMAIN_CONTRACT.md section 7 requires and that did not exist:
-- exam definition versions, per-subject exam results reconciling with the aggregate, append-only analysis
-- versions, and an explicit scoring algorithm version. Contract section 8 acceptance tests 11 and 9 are
-- the ones this file addresses directly.
--
-- What these tests do NOT prove: no scoring formula is implemented or validated — the database stores and
-- compares snapshots and never computes a score. The SET of permitted algorithm names is not constrained
-- (OQ-ASM-2). Rank, percentile and cohort comparison are not modelled.
-- =============================================================================
\set ON_ERROR_STOP on

CREATE OR REPLACE FUNCTION ex_err(label text, stmt text, want text, want_msg text DEFAULT '')
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  BEGIN
    EXECUTE stmt;
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE<>want THEN RAISE EXCEPTION 'FAIL %: got % (%), expected %',label,SQLSTATE,SQLERRM,want; END IF;
    IF want_msg<>'' AND position(want_msg IN SQLERRM)=0 THEN
      RAISE EXCEPTION 'FAIL %: wrong reason: %',label,SQLERRM;
    END IF;
    RAISE NOTICE 'PASS % (SQLSTATE %, reason verified)',label,SQLSTATE;
    RETURN;
  END;
  RAISE EXCEPTION 'FAIL %: statement unexpectedly succeeded',label;
END; $$;
CREATE OR REPLACE FUNCTION ex_ok(label text, stmt text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN EXECUTE stmt; RAISE NOTICE 'PASS % (accepted)',label; END; $$;

-- Fixtures
INSERT INTO workspace_profile(singleton,workspace_id,workspace_type)
VALUES(true,'a1000000-0000-0000-0000-000000000001','organization');
INSERT INTO workspace_memberships(membership_id,platform_user_id,status)
VALUES('b1000000-0000-0000-0000-000000000001','c1000000-0000-0000-0000-000000000001','active');
INSERT INTO subjects(subject_id,subject_key,title,grade_key,source_kind,status) VALUES
 ('e1000000-0000-0000-0000-000000000001','biology','Biology','grade_10','workspace_custom','active'),
 ('e1000000-0000-0000-0000-000000000002','chemistry','Chemistry','grade_10','workspace_custom','active'),
 ('e1000000-0000-0000-0000-000000000003','physics','Physics','grade_10','workspace_custom','active');
INSERT INTO students(student_id,platform_student_id,display_name,grade_key,lifecycle_state) VALUES
 ('e2000000-0000-0000-0000-000000000001',gen_random_uuid(),'Exam Subject A','grade_10','active'),
 ('e2000000-0000-0000-0000-000000000002',gen_random_uuid(),'Exam Subject B','grade_10','active');

\set POL '{"algorithm":"standard_negative","algorithm_version":1,"negative_marking":true}'
\set POL2 '{"algorithm":"standard_negative","algorithm_version":2,"negative_marking":false}'

-- ===================================================================================================
-- 1. THE SCORING ALGORITHM VERSION IS EXPLICIT
--    Before this batch a snapshot of `{}` was accepted and published, so nothing recorded WHICH
--    algorithm produced a score.
-- ===================================================================================================
INSERT INTO test_definitions(test_id,title,subject_id,test_kind,scoring_policy_snapshot)
VALUES('d4000000-0000-0000-0000-000000000001','Quiz','e1000000-0000-0000-0000-000000000001','educational',:'POL'::jsonb);

SELECT ex_err('EXM-01 an empty scoring policy snapshot is refused',
 $q$INSERT INTO test_definition_versions(version_id,test_id,version_no,question_count,scoring_policy_snapshot)
    VALUES(gen_random_uuid(),'d4000000-0000-0000-0000-000000000001',90,3,'{}'::jsonb)$q$,
 '23514','scoring_policy_shape');
SELECT ex_err('EXM-02 a policy naming no algorithm_version is refused',
 $q$INSERT INTO test_definition_versions(version_id,test_id,version_no,question_count,scoring_policy_snapshot)
    VALUES(gen_random_uuid(),'d4000000-0000-0000-0000-000000000001',91,3,'{"algorithm":"standard_negative"}'::jsonb)$q$,
 '23514','scoring_policy_shape');
SELECT ex_err('EXM-03 a policy naming no algorithm is refused',
 $q$INSERT INTO test_definition_versions(version_id,test_id,version_no,question_count,scoring_policy_snapshot)
    VALUES(gen_random_uuid(),'d4000000-0000-0000-0000-000000000001',92,3,'{"algorithm_version":1}'::jsonb)$q$,
 '23514','scoring_policy_shape');
SELECT ex_err('EXM-04 algorithm_version 0 is refused',
 $q$INSERT INTO test_definition_versions(version_id,test_id,version_no,question_count,scoring_policy_snapshot)
    VALUES(gen_random_uuid(),'d4000000-0000-0000-0000-000000000001',93,3,'{"algorithm":"x","algorithm_version":0}'::jsonb)$q$,
 '23514','scoring_policy_shape');
SELECT ex_err('EXM-05 a non-integer algorithm_version is refused',
 $q$INSERT INTO test_definition_versions(version_id,test_id,version_no,question_count,scoring_policy_snapshot)
    VALUES(gen_random_uuid(),'d4000000-0000-0000-0000-000000000001',94,3,'{"algorithm":"x","algorithm_version":1.5}'::jsonb)$q$,
 '23514','scoring_policy_shape');
SELECT ex_err('EXM-06 an empty algorithm name is refused',
 $q$INSERT INTO test_definition_versions(version_id,test_id,version_no,question_count,scoring_policy_snapshot)
    VALUES(gen_random_uuid(),'d4000000-0000-0000-0000-000000000001',95,3,'{"algorithm":"  ","algorithm_version":1}'::jsonb)$q$,
 '23514','scoring_policy_shape');
-- The control: a well-formed policy must be ACCEPTED, otherwise the six refusals above prove nothing.
SELECT ex_ok('EXM-07 a policy naming its algorithm and a positive integer version is accepted',
 format($q$INSERT INTO test_definition_versions(version_id,test_id,version_no,question_count,scoring_policy_snapshot)
    VALUES('d4100000-0000-0000-0000-000000000001','d4000000-0000-0000-0000-000000000001',1,2,%L::jsonb)$q$, :'POL'));
-- The same requirement reaches exams and exam results, not only tests.
SELECT ex_err('EXM-08 an exam with a shapeless policy is refused',
 $q$INSERT INTO exams(exam_id,student_id,title,exam_at,scoring_policy_snapshot)
    VALUES(gen_random_uuid(),'e2000000-0000-0000-0000-000000000001','Bad',now(),'{}'::jsonb)$q$,
 '23514','scoring_policy_shape');

-- ===================================================================================================
-- 2. EXAM DEFINITION VERSIONS — immutable published blueprint
-- ===================================================================================================
INSERT INTO exam_definitions(exam_definition_id,title) VALUES('f1000000-0000-0000-0000-000000000001','Mock Exam');

SELECT ex_err('EXM-09 an exam definition version cannot be created already published',
 format($q$INSERT INTO exam_definition_versions(exam_version_id,exam_definition_id,version_no,status,question_count,scoring_policy_snapshot,published_at)
    VALUES(gen_random_uuid(),'f1000000-0000-0000-0000-000000000001',9,'published',10,%L::jsonb,now())$q$, :'POL'),
 '23514','created as draft');

-- A blueprint that demands per-subject results must declare subjects that add up.
INSERT INTO exam_definition_versions(exam_version_id,exam_definition_id,version_no,question_count,requires_subject_results,scoring_policy_snapshot)
VALUES('f2000000-0000-0000-0000-000000000001','f1000000-0000-0000-0000-000000000001',1,10,true,:'POL'::jsonb);
SELECT ex_err('EXM-10 a blueprint requiring per-subject results cannot publish with no subjects',
 $q$UPDATE exam_definition_versions SET status='published',published_at=now()
     WHERE exam_version_id='f2000000-0000-0000-0000-000000000001'$q$,
 '23514','must declare at least one subject');

INSERT INTO exam_definition_version_subjects(exam_version_subject_id,exam_version_id,subject_id,question_count,display_order) VALUES
 ('f3000000-0000-0000-0000-000000000001','f2000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001',4,1),
 ('f3000000-0000-0000-0000-000000000002','f2000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000002',3,2);
SELECT ex_err('EXM-11 subject question counts that do not sum to the exam count cannot publish',
 $q$UPDATE exam_definition_versions SET status='published',published_at=now()
     WHERE exam_version_id='f2000000-0000-0000-0000-000000000001'$q$,
 '23514','sum to 7 but the exam version declares 10');

INSERT INTO exam_definition_version_subjects(exam_version_subject_id,exam_version_id,subject_id,question_count,display_order)
VALUES('f3000000-0000-0000-0000-000000000003','f2000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000003',3,3);
SELECT ex_ok('EXM-12 a blueprint whose subjects add up publishes',
 $q$UPDATE exam_definition_versions SET status='published',published_at=now()
     WHERE exam_version_id='f2000000-0000-0000-0000-000000000001'$q$);

SELECT ex_err('EXM-13 a published exam definition version is immutable',
 $q$UPDATE exam_definition_versions SET question_count=11 WHERE exam_version_id='f2000000-0000-0000-0000-000000000001'$q$,
 '23514','immutable');
SELECT ex_err('EXM-14 a published exam definition version cannot be deleted',
 $q$DELETE FROM exam_definition_versions WHERE exam_version_id='f2000000-0000-0000-0000-000000000001'$q$,
 '23514','cannot be deleted');
SELECT ex_err('EXM-15 the subject blueprint of a published version is immutable',
 $q$UPDATE exam_definition_version_subjects SET question_count=5
     WHERE exam_version_subject_id='f3000000-0000-0000-0000-000000000001'$q$,
 '23514','immutable');
SELECT ex_err('EXM-16 a subject cannot be added to a published blueprint',
 $q$INSERT INTO exam_definition_version_subjects(exam_version_subject_id,exam_version_id,subject_id,question_count,display_order)
    VALUES(gen_random_uuid(),'f2000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001',1,9)$q$,
 '23514','immutable');

-- ===================================================================================================
-- 3. AN EXAM SITTING MAY CITE A PUBLISHED BLUEPRINT
-- ===================================================================================================
INSERT INTO exam_definition_versions(exam_version_id,exam_definition_id,version_no,question_count,scoring_policy_snapshot)
VALUES('f2000000-0000-0000-0000-000000000002','f1000000-0000-0000-0000-000000000001',2,5,:'POL'::jsonb);
SELECT ex_err('EXM-17 an exam cannot cite a draft exam definition version',
 format($q$INSERT INTO exams(exam_id,student_id,title,exam_at,scoring_policy_snapshot,definition_version_id)
    VALUES(gen_random_uuid(),'e2000000-0000-0000-0000-000000000001','Draft blueprint',now(),%L::jsonb,
           'f2000000-0000-0000-0000-000000000002')$q$, :'POL'),
 '23514','only cite a published');

SELECT ex_ok('EXM-18 an exam citing a published blueprint is accepted',
 format($q$INSERT INTO exams(exam_id,student_id,title,exam_at,scoring_policy_snapshot,definition_version_id)
    VALUES('a5000000-0000-0000-0000-000000000001','e2000000-0000-0000-0000-000000000001','Mock sitting A',now(),%L::jsonb,
           'f2000000-0000-0000-0000-000000000001')$q$, :'POL'));
-- An exam with no blueprint at all stays legal: requiring one is a product decision, not a schema rule.
SELECT ex_ok('EXM-19 an exam with no blueprint is still accepted',
 format($q$INSERT INTO exams(exam_id,student_id,title,exam_at,scoring_policy_snapshot)
    VALUES('a5000000-0000-0000-0000-000000000009','e2000000-0000-0000-0000-000000000002','Ad-hoc sitting',now(),%L::jsonb)$q$, :'POL'));

-- ===================================================================================================
-- 4. PER-SUBJECT EXAM RESULTS
-- ===================================================================================================
SELECT ex_err('EXM-20 a per-subject result requires the exam to cite a blueprint',
 format($q$INSERT INTO exam_subject_results(exam_subject_result_id,exam_id,student_id,exam_version_id,
      exam_version_subject_id,subject_id,question_count,correct_count,wrong_count,blank_count,score,scoring_policy_snapshot)
    VALUES(gen_random_uuid(),'a5000000-0000-0000-0000-000000000009','e2000000-0000-0000-0000-000000000002',
      'f2000000-0000-0000-0000-000000000001','f3000000-0000-0000-0000-000000000001',
      'e1000000-0000-0000-0000-000000000001',4,2,1,1,1.0,%L::jsonb)$q$, :'POL'),
 '23514','cite a published exam definition version');

SELECT ex_err('EXM-21 a per-subject result whose counts do not account for every question is refused',
 format($q$INSERT INTO exam_subject_results(exam_subject_result_id,exam_id,student_id,exam_version_id,
      exam_version_subject_id,subject_id,question_count,correct_count,wrong_count,blank_count,score,scoring_policy_snapshot)
    VALUES(gen_random_uuid(),'a5000000-0000-0000-0000-000000000001','e2000000-0000-0000-0000-000000000001',
      'f2000000-0000-0000-0000-000000000001','f3000000-0000-0000-0000-000000000001',
      'e1000000-0000-0000-0000-000000000001',4,1,1,1,1.0,%L::jsonb)$q$, :'POL'),
 '23514');

SELECT ex_err('EXM-22 a per-subject result declaring a different question count than the blueprint is refused',
 format($q$INSERT INTO exam_subject_results(exam_subject_result_id,exam_id,student_id,exam_version_id,
      exam_version_subject_id,subject_id,question_count,correct_count,wrong_count,blank_count,score,scoring_policy_snapshot)
    VALUES(gen_random_uuid(),'a5000000-0000-0000-0000-000000000001','e2000000-0000-0000-0000-000000000001',
      'f2000000-0000-0000-0000-000000000001','f3000000-0000-0000-0000-000000000001',
      'e1000000-0000-0000-0000-000000000001',3,1,1,1,1.0,%L::jsonb)$q$, :'POL'),
 '23514','blueprint declares 4');

SELECT ex_err('EXM-23 a per-subject result whose policy differs from the exam policy is refused',
 format($q$INSERT INTO exam_subject_results(exam_subject_result_id,exam_id,student_id,exam_version_id,
      exam_version_subject_id,subject_id,question_count,correct_count,wrong_count,blank_count,score,scoring_policy_snapshot)
    VALUES(gen_random_uuid(),'a5000000-0000-0000-0000-000000000001','e2000000-0000-0000-0000-000000000001',
      'f2000000-0000-0000-0000-000000000001','f3000000-0000-0000-0000-000000000001',
      'e1000000-0000-0000-0000-000000000001',4,2,1,1,1.0,%L::jsonb)$q$, :'POL2'),
 '23514','differs from the exam policy');

-- A subject result naming another student than the exam sitting's: refused by the composite foreign key,
-- declaratively, without a trigger.
SELECT ex_err('EXM-24 a per-subject result for another student''s exam is refused by referential integrity',
 format($q$INSERT INTO exam_subject_results(exam_subject_result_id,exam_id,student_id,exam_version_id,
      exam_version_subject_id,subject_id,question_count,correct_count,wrong_count,blank_count,score,scoring_policy_snapshot)
    VALUES(gen_random_uuid(),'a5000000-0000-0000-0000-000000000001','e2000000-0000-0000-0000-000000000002',
      'f2000000-0000-0000-0000-000000000001','f3000000-0000-0000-0000-000000000001',
      'e1000000-0000-0000-0000-000000000001',4,2,1,1,1.0,%L::jsonb)$q$, :'POL'),
 '23503');

-- A subject result citing a subject of a DIFFERENT exam version: also refused declaratively.
SELECT ex_err('EXM-25 a per-subject result citing a subject of another exam version is refused',
 format($q$INSERT INTO exam_subject_results(exam_subject_result_id,exam_id,student_id,exam_version_id,
      exam_version_subject_id,subject_id,question_count,correct_count,wrong_count,blank_count,score,scoring_policy_snapshot)
    VALUES(gen_random_uuid(),'a5000000-0000-0000-0000-000000000001','e2000000-0000-0000-0000-000000000001',
      'f2000000-0000-0000-0000-000000000002','f3000000-0000-0000-0000-000000000001',
      'e1000000-0000-0000-0000-000000000001',4,2,1,1,1.0,%L::jsonb)$q$, :'POL'),
 '23514','the exam sits version');

-- ===================================================================================================
-- 5. RECONCILIATION BETWEEN THE AGGREGATE AND THE PER-SUBJECT ROWS (deferred to COMMIT)
-- ===================================================================================================
-- The blueprint of this exam REQUIRES per-subject results, so an aggregate alone must not commit.
DO $t$
DECLARE pol jsonb := '{"algorithm":"standard_negative","algorithm_version":1,"negative_marking":true}';
BEGIN
  BEGIN
    INSERT INTO public.exam_results(exam_result_id,exam_id,student_id,correct_count,wrong_count,blank_count,score,scoring_policy_snapshot)
    VALUES(gen_random_uuid(),'a5000000-0000-0000-0000-000000000001','e2000000-0000-0000-0000-000000000001',5,3,2,3.0,pol);
    -- Force the deferred constraint to be evaluated now, inside this block, so the test can observe it.
    SET CONSTRAINTS exam_results_reconcile_trg IMMEDIATE;
    RAISE EXCEPTION 'FAIL EXM-26 an aggregate with no per-subject rows committed although the blueprint requires them';
  EXCEPTION WHEN check_violation THEN
    IF position('requires per-subject results for 3 subjects but 0 are recorded' IN SQLERRM)=0 THEN
      RAISE EXCEPTION 'FAIL EXM-26 wrong reason: %', SQLERRM;
    END IF;
    RAISE NOTICE 'PASS EXM-26 an aggregate without the required per-subject rows is refused at constraint time';
  END;
END $t$;

-- Aggregate that does NOT match the per-subject totals: refused.
DO $t$
DECLARE pol jsonb := '{"algorithm":"standard_negative","algorithm_version":1,"negative_marking":true}';
BEGIN
  BEGIN
    INSERT INTO public.exam_subject_results(exam_subject_result_id,exam_id,student_id,exam_version_id,
      exam_version_subject_id,subject_id,question_count,correct_count,wrong_count,blank_count,score,scoring_policy_snapshot) VALUES
     (gen_random_uuid(),'a5000000-0000-0000-0000-000000000001','e2000000-0000-0000-0000-000000000001',
      'f2000000-0000-0000-0000-000000000001','f3000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001',4,2,1,1,1.0,pol),
     (gen_random_uuid(),'a5000000-0000-0000-0000-000000000001','e2000000-0000-0000-0000-000000000001',
      'f2000000-0000-0000-0000-000000000001','f3000000-0000-0000-0000-000000000002','e1000000-0000-0000-0000-000000000002',3,2,1,0,1.5,pol),
     (gen_random_uuid(),'a5000000-0000-0000-0000-000000000001','e2000000-0000-0000-0000-000000000001',
      'f2000000-0000-0000-0000-000000000001','f3000000-0000-0000-0000-000000000003','e1000000-0000-0000-0000-000000000003',3,1,1,1,0.5,pol);
    -- subject totals are correct=5, wrong=3, blank=2. Claim something else in the aggregate.
    INSERT INTO public.exam_results(exam_result_id,exam_id,student_id,correct_count,wrong_count,blank_count,score,scoring_policy_snapshot)
    VALUES(gen_random_uuid(),'a5000000-0000-0000-0000-000000000001','e2000000-0000-0000-0000-000000000001',6,2,2,3.0,pol);
    SET CONSTRAINTS exam_results_reconcile_trg, exam_subject_results_reconcile_trg IMMEDIATE;
    RAISE EXCEPTION 'FAIL EXM-27 an aggregate that contradicts the per-subject totals was accepted';
  EXCEPTION WHEN check_violation THEN
    IF position('does not reconcile with the per-subject totals' IN SQLERRM)=0 THEN
      RAISE EXCEPTION 'FAIL EXM-27 wrong reason: %', SQLERRM;
    END IF;
    RAISE NOTICE 'PASS EXM-27 an aggregate contradicting the per-subject totals is refused';
  END;
END $t$;

-- The control: matching totals must COMMIT. Without this the two refusals above prove nothing.
BEGIN;
INSERT INTO exam_subject_results(exam_subject_result_id,exam_id,student_id,exam_version_id,
  exam_version_subject_id,subject_id,question_count,correct_count,wrong_count,blank_count,score,scoring_policy_snapshot) VALUES
 ('f4000000-0000-0000-0000-000000000001','a5000000-0000-0000-0000-000000000001','e2000000-0000-0000-0000-000000000001',
  'f2000000-0000-0000-0000-000000000001','f3000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001',4,2,1,1,1.0,:'POL'::jsonb),
 ('f4000000-0000-0000-0000-000000000002','a5000000-0000-0000-0000-000000000001','e2000000-0000-0000-0000-000000000001',
  'f2000000-0000-0000-0000-000000000001','f3000000-0000-0000-0000-000000000002','e1000000-0000-0000-0000-000000000002',3,2,1,0,1.5,:'POL'::jsonb),
 ('f4000000-0000-0000-0000-000000000003','a5000000-0000-0000-0000-000000000001','e2000000-0000-0000-0000-000000000001',
  'f2000000-0000-0000-0000-000000000001','f3000000-0000-0000-0000-000000000003','e1000000-0000-0000-0000-000000000003',3,1,1,1,0.5,:'POL'::jsonb);
INSERT INTO exam_results(exam_result_id,exam_id,student_id,correct_count,wrong_count,blank_count,score,scoring_policy_snapshot)
VALUES('f5000000-0000-0000-0000-000000000001','a5000000-0000-0000-0000-000000000001','e2000000-0000-0000-0000-000000000001',5,3,2,3.0,:'POL'::jsonb);
COMMIT;
DO $t$ BEGIN
  IF (SELECT count(*) FROM public.exam_subject_results WHERE exam_id='a5000000-0000-0000-0000-000000000001')<>3
     OR NOT EXISTS (SELECT 1 FROM public.exam_results WHERE exam_result_id='f5000000-0000-0000-0000-000000000001') THEN
    RAISE EXCEPTION 'FAIL EXM-28 the reconciling aggregate and its three subject rows did not persist';
  END IF;
  RAISE NOTICE 'PASS EXM-28 an aggregate that reconciles with its three per-subject rows commits';
END $t$;

SELECT ex_err('EXM-29 only one per-subject result per subject per sitting',
 format($q$INSERT INTO exam_subject_results(exam_subject_result_id,exam_id,student_id,exam_version_id,
      exam_version_subject_id,subject_id,question_count,correct_count,wrong_count,blank_count,score,scoring_policy_snapshot)
    VALUES(gen_random_uuid(),'a5000000-0000-0000-0000-000000000001','e2000000-0000-0000-0000-000000000001',
      'f2000000-0000-0000-0000-000000000001','f3000000-0000-0000-0000-000000000001',
      'e1000000-0000-0000-0000-000000000001',4,4,0,0,2.0,%L::jsonb)$q$, :'POL'),
 '23505');

SELECT ex_err('EXM-30 the denominator of a recorded per-subject result is immutable',
 $q$UPDATE exam_subject_results SET question_count=9 WHERE exam_subject_result_id='f4000000-0000-0000-0000-000000000001'$q$,
 '23514','immutable');

-- An exam with NO blueprint may carry an aggregate and no subject rows: the schema does not decide that
-- every exam needs a per-subject breakdown.
SELECT ex_ok('EXM-31 an exam without a blueprint may hold an aggregate result alone',
 format($q$INSERT INTO exam_results(exam_result_id,exam_id,student_id,correct_count,wrong_count,blank_count,score,scoring_policy_snapshot)
    VALUES(gen_random_uuid(),'a5000000-0000-0000-0000-000000000009','e2000000-0000-0000-0000-000000000002',1,1,0,0.5,%L::jsonb)$q$, :'POL'));

-- ===================================================================================================
-- 6. APPEND-ONLY TEST ANALYSIS VERSIONS
--    The contract requires that a later reclassification is a NEW version, never a mutation of
--    submitted responses. Submitted responses are already immutable, so this is where it goes.
-- ===================================================================================================
INSERT INTO test_definition_version_questions(version_question_id,version_id,question_no,item_ref) VALUES
 ('d4200000-0000-0000-0000-000000000001','d4100000-0000-0000-0000-000000000001',1,'item-1'),
 ('d4200000-0000-0000-0000-000000000002','d4100000-0000-0000-0000-000000000001',2,'item-2');
UPDATE test_definition_versions SET status='published',published_at=now()
 WHERE version_id='d4100000-0000-0000-0000-000000000001';
INSERT INTO test_attempts(attempt_id,test_id,definition_version_id,student_id,started_at,question_count,scoring_policy_snapshot)
VALUES('e4000000-0000-0000-0000-000000000001','d4000000-0000-0000-0000-000000000001','d4100000-0000-0000-0000-000000000001',
       'e2000000-0000-0000-0000-000000000001',now(),2,:'POL'::jsonb);

SELECT ex_err('EXM-32 an attempt that has not been submitted cannot be analysed',
 $q$INSERT INTO test_analysis_versions(analysis_version_id,attempt_id,student_id,analysis_no,analysis_algorithm,analysis_algorithm_version)
    VALUES(gen_random_uuid(),'e4000000-0000-0000-0000-000000000001','e2000000-0000-0000-0000-000000000001',1,'reason_taxonomy',1)$q$,
 '23514','must be submitted before it can be analysed');

INSERT INTO test_responses(response_id,attempt_id,definition_version_id,version_question_id,question_no,response_state,error_reason) VALUES
 ('e5000000-0000-0000-0000-000000000001','e4000000-0000-0000-0000-000000000001','d4100000-0000-0000-0000-000000000001',
  'd4200000-0000-0000-0000-000000000001',1,'wrong','careless'),
 ('e5000000-0000-0000-0000-000000000002','e4000000-0000-0000-0000-000000000001','d4100000-0000-0000-0000-000000000001',
  'd4200000-0000-0000-0000-000000000002',2,'correct',NULL);
UPDATE test_attempts SET state='submitted',submitted_at=now(),correct_count=1,wrong_count=1,blank_count=0,score=0.5,
  submission_idempotency_key='exm-sub-1',submission_payload_hash=sha256('exm'::bytea)
 WHERE attempt_id='e4000000-0000-0000-0000-000000000001';

SELECT ex_err('EXM-33 analysis_no must be the next in sequence',
 $q$INSERT INTO test_analysis_versions(analysis_version_id,attempt_id,student_id,analysis_no,analysis_algorithm,analysis_algorithm_version)
    VALUES(gen_random_uuid(),'e4000000-0000-0000-0000-000000000001','e2000000-0000-0000-0000-000000000001',2,'reason_taxonomy',1)$q$,
 '23514','analysis_no must be 1');

SELECT ex_ok('EXM-34 the first analysis version of a submitted attempt is accepted',
 $q$INSERT INTO test_analysis_versions(analysis_version_id,attempt_id,student_id,analysis_no,analysis_algorithm,analysis_algorithm_version)
    VALUES('e6000000-0000-0000-0000-000000000001','e4000000-0000-0000-0000-000000000001','e2000000-0000-0000-0000-000000000001',1,'reason_taxonomy',1)$q$);
SELECT ex_ok('EXM-35 a finding classifies a response of the analysed attempt',
 $q$INSERT INTO test_analysis_response_findings(finding_id,analysis_version_id,attempt_id,response_id,error_reason)
    VALUES(gen_random_uuid(),'e6000000-0000-0000-0000-000000000001','e4000000-0000-0000-0000-000000000001',
           'e5000000-0000-0000-0000-000000000001','careless')$q$);
SELECT ex_err('EXM-36 a custom finding reason requires a description',
 $q$INSERT INTO test_analysis_response_findings(finding_id,analysis_version_id,attempt_id,response_id,error_reason)
    VALUES(gen_random_uuid(),'e6000000-0000-0000-0000-000000000001','e4000000-0000-0000-0000-000000000001',
           'e5000000-0000-0000-0000-000000000002','custom')$q$,
 '23514');
SELECT ex_err('EXM-37 an analysis version is append-only',
 $q$UPDATE test_analysis_versions SET notes='changed' WHERE analysis_version_id='e6000000-0000-0000-0000-000000000001'$q$,
 '23514','append-only');
SELECT ex_err('EXM-38 a finding is append-only',
 $q$UPDATE test_analysis_response_findings SET error_reason='concept' WHERE analysis_version_id='e6000000-0000-0000-0000-000000000001'$q$,
 '23514','append-only');
SELECT ex_err('EXM-39 an analysis version cannot be deleted',
 $q$DELETE FROM test_analysis_versions WHERE analysis_version_id='e6000000-0000-0000-0000-000000000001'$q$,
 '23514','append-only');

-- The point of the whole structure: a reclassification is a NEW version, and the submitted response is
-- untouched by it.
DO $t$
DECLARE v_before text;
BEGIN
  SELECT error_reason INTO v_before FROM public.test_responses WHERE response_id='e5000000-0000-0000-0000-000000000001';
  INSERT INTO public.test_analysis_versions(analysis_version_id,attempt_id,student_id,analysis_no,analysis_algorithm,analysis_algorithm_version)
  VALUES('e6000000-0000-0000-0000-000000000002','e4000000-0000-0000-0000-000000000001','e2000000-0000-0000-0000-000000000001',2,'reason_taxonomy',2);
  INSERT INTO public.test_analysis_response_findings(finding_id,analysis_version_id,attempt_id,response_id,error_reason)
  VALUES(gen_random_uuid(),'e6000000-0000-0000-0000-000000000002','e4000000-0000-0000-0000-000000000001',
         'e5000000-0000-0000-0000-000000000001','concept');
  IF (SELECT error_reason FROM public.test_responses WHERE response_id='e5000000-0000-0000-0000-000000000001')
     IS DISTINCT FROM v_before THEN
    RAISE EXCEPTION 'FAIL EXM-40 the reclassification mutated the submitted response';
  END IF;
  IF (SELECT count(*) FROM public.test_analysis_versions WHERE attempt_id='e4000000-0000-0000-0000-000000000001')<>2 THEN
    RAISE EXCEPTION 'FAIL EXM-40 the attempt does not carry two analysis versions';
  END IF;
  RAISE NOTICE 'PASS EXM-40 a reclassification is a new analysis version and the submitted response (%) is unchanged', v_before;
END $t$;

-- EXM-41 needs a REAL second attempt, not a NULL. An earlier version of this test used
-- `(SELECT response_id FROM test_responses WHERE attempt_id<>...)` when no other attempt existed, so the
-- subquery returned NULL and the test was really asserting NULL handling. A second submitted attempt makes
-- it a genuine cross-attempt citation.
INSERT INTO test_attempts(attempt_id,test_id,definition_version_id,student_id,started_at,question_count,scoring_policy_snapshot)
VALUES('e4000000-0000-0000-0000-000000000002','d4000000-0000-0000-0000-000000000001','d4100000-0000-0000-0000-000000000001',
       'e2000000-0000-0000-0000-000000000002',now(),2,:'POL'::jsonb);
INSERT INTO test_responses(response_id,attempt_id,definition_version_id,version_question_id,question_no,response_state) VALUES
 ('e5000000-0000-0000-0000-00000000000b','e4000000-0000-0000-0000-000000000002','d4100000-0000-0000-0000-000000000001',
  'd4200000-0000-0000-0000-000000000001',1,'wrong'),
 ('e5000000-0000-0000-0000-00000000000c','e4000000-0000-0000-0000-000000000002','d4100000-0000-0000-0000-000000000001',
  'd4200000-0000-0000-0000-000000000002',2,'blank');
UPDATE test_attempts SET state='submitted',submitted_at=now(),correct_count=0,wrong_count=1,blank_count=1,score=0.0,
  submission_idempotency_key='exm-sub-2',submission_payload_hash=sha256('exm2'::bytea)
 WHERE attempt_id='e4000000-0000-0000-0000-000000000002';

SELECT ex_err('EXM-41 a finding cannot cite a response of another attempt',
 $q$INSERT INTO test_analysis_response_findings(finding_id,analysis_version_id,attempt_id,response_id,error_reason)
    VALUES(gen_random_uuid(),'e6000000-0000-0000-0000-000000000002','e4000000-0000-0000-0000-000000000001',
           'e5000000-0000-0000-0000-00000000000b','concept')$q$,
 '23514','but the analysis is of attempt');

-- ===================================================================================================
-- EXM-42  The predicate must never return NULL, for ANY input.
--         A CHECK constraint PASSES on NULL. The first version of scoring_policy_is_well_formed()
--         returned NULL for `{}` because a missing key makes the AND chain NULL in three-valued logic,
--         and the constraint accepted the empty policy. This test is what stops that returning: it is
--         cheaper and more reliable than remembering the rule.
-- ===================================================================================================
DO $t$
DECLARE
  v record;
  v_nulls text[] := ARRAY[]::text[];
BEGIN
  FOR v IN SELECT * FROM (VALUES
      (NULL::jsonb, 'SQL NULL'),
      ('null'::jsonb, 'JSON null'),
      ('{}'::jsonb, 'empty object'),
      ('[]'::jsonb, 'array'),
      ('"text"'::jsonb, 'string'),
      ('7'::jsonb, 'number'),
      ('{"algorithm":"x"}'::jsonb, 'no algorithm_version'),
      ('{"algorithm_version":1}'::jsonb, 'no algorithm'),
      ('{"algorithm":null,"algorithm_version":1}'::jsonb, 'null algorithm'),
      ('{"algorithm":"x","algorithm_version":null}'::jsonb, 'null algorithm_version'),
      ('{"algorithm":"x","algorithm_version":"1"}'::jsonb, 'algorithm_version as a string'),
      ('{"algorithm":5,"algorithm_version":1}'::jsonb, 'algorithm as a number')
    ) AS t(p, label)
  LOOP
    IF public.scoring_policy_is_well_formed(v.p) IS NULL THEN
      v_nulls := v_nulls || v.label;
    END IF;
  END LOOP;
  IF array_length(v_nulls,1) IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL EXM-42 the predicate returned NULL for: %. A CHECK constraint PASSES on NULL, '
                    'so every one of those policies would be accepted.', array_to_string(v_nulls, ', ');
  END IF;
  -- And every one of them must be rejected, not merely non-NULL.
  FOR v IN SELECT * FROM (VALUES
      (NULL::jsonb, 'SQL NULL'), ('null'::jsonb,'JSON null'), ('{}'::jsonb,'empty object'),
      ('[]'::jsonb,'array'), ('"text"'::jsonb,'string'), ('7'::jsonb,'number'),
      ('{"algorithm":"x"}'::jsonb,'no algorithm_version'), ('{"algorithm_version":1}'::jsonb,'no algorithm'),
      ('{"algorithm":null,"algorithm_version":1}'::jsonb,'null algorithm'),
      ('{"algorithm":"x","algorithm_version":null}'::jsonb,'null algorithm_version'),
      ('{"algorithm":"x","algorithm_version":"1"}'::jsonb,'algorithm_version as a string'),
      ('{"algorithm":5,"algorithm_version":1}'::jsonb,'algorithm as a number')
    ) AS t(p, label)
  LOOP
    IF public.scoring_policy_is_well_formed(v.p) THEN
      RAISE EXCEPTION 'FAIL EXM-42 the predicate accepted a malformed policy (%)', v.label;
    END IF;
  END LOOP;
  IF NOT public.scoring_policy_is_well_formed('{"algorithm":"standard_negative","algorithm_version":3}'::jsonb) THEN
    RAISE EXCEPTION 'FAIL EXM-42 the predicate rejected a well-formed policy';
  END IF;
  RAISE NOTICE 'PASS EXM-42 the predicate is never NULL, rejects 12 malformed policies and accepts a well-formed one';
END $t$;

SELECT 'ASSESSMENT AND EXAM TESTS COMPLETED (EXM-01..EXM-42)' AS result;
