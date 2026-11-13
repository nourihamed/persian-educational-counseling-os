-- PD-2026-11-13-B — Activity as a shared scheduling layer over authoritative specialized entities.
-- Synthetic only (D-014). Run AFTER workspace_schema_tests.sql and workspace_assessment_guardian_tests.sql
-- on the same database (reuses student e1..01, attempt e4..01, exam a5..01, class c5..01, session d5..01,
-- assignment e5..01 and review f5..01).
-- These tests prove referential integrity in the database. They do NOT prove API authorization.
\set ON_ERROR_STOP on
CREATE OR REPLACE FUNCTION av_err(label text, stmt text, want text, want_msg text DEFAULT '')
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
CREATE OR REPLACE FUNCTION av_ok(label text, stmt text) RETURNS void LANGUAGE plpgsql AS $t$
BEGIN EXECUTE stmt; RAISE NOTICE 'PASS % (accepted)',label; END; $t$;

-- A second student with his own exam, assignment and review: every cross-student case below uses him.
INSERT INTO students(student_id,platform_student_id,display_name,grade_key,lifecycle_state)
VALUES ('e1000000-0000-0000-0000-000000000009','f1000000-0000-0000-0000-000000000009','Activity Other','grade_10','active');
INSERT INTO exams(exam_id,student_id,title,exam_at,scoring_policy_snapshot)
VALUES ('a5000000-0000-0000-0000-000000000009','e1000000-0000-0000-0000-000000000009','Other exam',now(),'{}'::jsonb);
INSERT INTO class_participants(class_id,student_id,state) VALUES
 ('c5000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001','enrolled');
INSERT INTO class_session_participants(class_session_id,class_id,student_id,attendance) VALUES
 ('d5000000-0000-0000-0000-000000000001','c5000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001','expected');

-- ============================ every kind links to its own typed source ============================
SELECT av_ok('ACT-01 a test activity links to a test attempt of the same student',
 $q$INSERT INTO activities(activity_id,student_id,activity_kind,title,state,test_attempt_id) VALUES ('b4100000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001','test','Quiz follow-up','planned','e4000000-0000-0000-0000-000000000001')$q$);
SELECT av_ok('ACT-02 an exam activity links to an exam of the same student',
 $q$INSERT INTO activities(activity_id,student_id,activity_kind,title,state,exam_id) VALUES ('b4100000-0000-0000-0000-000000000002','e1000000-0000-0000-0000-000000000001','exam','Exam day','planned','a5000000-0000-0000-0000-000000000001')$q$);
SELECT av_ok('ACT-03 a class follow-up links to a session the student takes part in',
 $q$INSERT INTO activities(activity_id,student_id,activity_kind,title,state,class_session_id) VALUES ('b4100000-0000-0000-0000-000000000003','e1000000-0000-0000-0000-000000000001','class_followup','Class notes','planned','d5000000-0000-0000-0000-000000000001')$q$);
SELECT av_ok('ACT-04 a homework activity links to an assignment of the same student',
 $q$INSERT INTO activities(activity_id,student_id,activity_kind,title,state,assignment_id) VALUES ('b4100000-0000-0000-0000-000000000004','e1000000-0000-0000-0000-000000000001','homework','Do homework','planned','e5000000-0000-0000-0000-000000000001')$q$);
SELECT av_ok('ACT-05 a review activity links to a review of the same student',
 $q$INSERT INTO activities(activity_id,student_id,activity_kind,title,state,review_id) VALUES ('b4100000-0000-0000-0000-000000000005','e1000000-0000-0000-0000-000000000001','review','Review topic','planned','f5000000-0000-0000-0000-000000000001')$q$);

-- ============================ a source is required, and only the matching one ============================
SELECT av_err('ACT-06 a test activity without a test attempt is rejected',
 $q$INSERT INTO activities(activity_id,student_id,activity_kind,title,state) VALUES (gen_random_uuid(),'e1000000-0000-0000-0000-000000000001','test','Dangling test','planned')$q$,'23514');
SELECT av_err('ACT-07 an exam activity without an exam is rejected',
 $q$INSERT INTO activities(activity_id,student_id,activity_kind,title,state) VALUES (gen_random_uuid(),'e1000000-0000-0000-0000-000000000001','exam','Dangling exam','planned')$q$,'23514');
SELECT av_err('ACT-08 a study activity may not carry a domain source',
 $q$INSERT INTO activities(activity_id,student_id,activity_kind,title,state,exam_id) VALUES (gen_random_uuid(),'e1000000-0000-0000-0000-000000000001','study','Study with a source','planned','a5000000-0000-0000-0000-000000000001')$q$,'23514');
SELECT av_err('ACT-09 an activity cannot carry two sources at once',
 $q$INSERT INTO activities(activity_id,student_id,activity_kind,title,state,exam_id,review_id) VALUES (gen_random_uuid(),'e1000000-0000-0000-0000-000000000001','exam','Two sources','planned','a5000000-0000-0000-0000-000000000001','f5000000-0000-0000-0000-000000000001')$q$,'23514');
SELECT av_err('ACT-10 the source column must match the declared kind',
 $q$INSERT INTO activities(activity_id,student_id,activity_kind,title,state,review_id) VALUES (gen_random_uuid(),'e1000000-0000-0000-0000-000000000001','homework','Wrong column','planned','f5000000-0000-0000-0000-000000000001')$q$,'23514');

-- ============================ invalid and cross-student sources ============================
SELECT av_err('ACT-11 an activity cannot reference a non-existent source record',
 $q$INSERT INTO activities(activity_id,student_id,activity_kind,title,state,exam_id) VALUES (gen_random_uuid(),'e1000000-0000-0000-0000-000000000001','exam','Missing exam','planned','a5000000-0000-0000-0000-0000000000ff')$q$,'23503');
SELECT av_err('ACT-12 an activity cannot reference another student''s exam',
 $q$INSERT INTO activities(activity_id,student_id,activity_kind,title,state,exam_id) VALUES (gen_random_uuid(),'e1000000-0000-0000-0000-000000000001','exam','Foreign exam','planned','a5000000-0000-0000-0000-000000000009')$q$,'23503');
SELECT av_err('ACT-13 an activity cannot reference another student''s test attempt',
 $q$INSERT INTO activities(activity_id,student_id,activity_kind,title,state,test_attempt_id) VALUES (gen_random_uuid(),'e1000000-0000-0000-0000-000000000009','test','Foreign attempt','planned','e4000000-0000-0000-0000-000000000002')$q$,'23503');
SELECT av_err('ACT-14 a class follow-up for a student who does not take part in the session is rejected',
 $q$INSERT INTO activities(activity_id,student_id,activity_kind,title,state,class_session_id) VALUES (gen_random_uuid(),'e1000000-0000-0000-0000-000000000009','class_followup','Not a participant','planned','d5000000-0000-0000-0000-000000000001')$q$,'23503');
SELECT av_err('ACT-15 a session participant row cannot name a class the session does not belong to',
 $q$INSERT INTO class_session_participants(class_session_id,class_id,student_id,attendance) SELECT 'd5000000-0000-0000-0000-000000000001',gen_random_uuid(),'e1000000-0000-0000-0000-000000000009','expected'$q$,'23503');
SELECT av_err('ACT-16 a session participant row cannot name a student who is not in the class',
 $q$INSERT INTO class_session_participants(class_session_id,class_id,student_id,attendance) VALUES ('d5000000-0000-0000-0000-000000000001','c5000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000009','expected')$q$,'23503');

-- ============================ no duplicate or drifting relationships ============================
SELECT av_err('ACT-17 a second activity for the same test attempt is rejected',
 $q$INSERT INTO activities(activity_id,student_id,activity_kind,title,state,test_attempt_id) VALUES (gen_random_uuid(),'e1000000-0000-0000-0000-000000000001','test','Duplicate schedule','planned','e4000000-0000-0000-0000-000000000001')$q$,'23505');
SELECT av_err('ACT-18 a second activity for the same assignment is rejected',
 $q$INSERT INTO activities(activity_id,student_id,activity_kind,title,state,assignment_id) VALUES (gen_random_uuid(),'e1000000-0000-0000-0000-000000000001','homework','Duplicate homework','planned','e5000000-0000-0000-0000-000000000001')$q$,'23505');
SELECT av_err('ACT-19 an activity cannot be moved to another student',
 $q$UPDATE activities SET student_id='e1000000-0000-0000-0000-000000000009' WHERE activity_id='b4100000-0000-0000-0000-000000000002'$q$,'23514','immutable');
SELECT av_err('ACT-20 an activity cannot change its kind',
 $q$UPDATE activities SET activity_kind='study' WHERE activity_id='b4100000-0000-0000-0000-000000000002'$q$,'23514','immutable');
SELECT av_ok('ACT-21 the shared layer may still reschedule and complete its own fields',
 $q$UPDATE activities SET state='completed', completed_at=now(), due_at=now()+interval '2 days', priority=1 WHERE activity_id='b4100000-0000-0000-0000-000000000002'$q$);

-- ============================ lifecycle: the domain record outlives its schedule ============================
SELECT av_err('ACT-22 a referenced exam cannot be deleted while an activity schedules it',
 $q$DELETE FROM exams WHERE exam_id='a5000000-0000-0000-0000-000000000001'$q$,'23503');
SELECT av_err('ACT-23 a referenced review cannot be deleted while an activity schedules it',
 $q$DELETE FROM reviews WHERE review_id='f5000000-0000-0000-0000-000000000001'$q$,'23503');
SELECT av_ok('ACT-24 removing the schedule leaves the domain record untouched',
 $q$DELETE FROM activities WHERE activity_id='b4100000-0000-0000-0000-000000000005'$q$);
DO $t$ BEGIN
  IF (SELECT count(*) FROM reviews WHERE review_id='f5000000-0000-0000-0000-000000000001')<>1 THEN RAISE EXCEPTION 'FAIL ACT-24 domain record lost'; END IF;
  RAISE NOTICE 'PASS ACT-24b the review survived the removal of its activity';
END $t$;

-- ============================ no polymorphic escape hatch ============================
DO $t$ DECLARE n integer; BEGIN
  SELECT count(*) INTO n FROM information_schema.columns
   WHERE table_name='activities' AND column_name IN ('source_type','source_id','source_ref','entity_type','entity_id');
  IF n<>0 THEN RAISE EXCEPTION 'FAIL ACT-25: activities carries % untyped polymorphic column(s)',n; END IF;
  RAISE NOTICE 'PASS ACT-25 activities has no untyped polymorphic source column';
END $t$;
DO $t$ DECLARE n integer; BEGIN
  SELECT count(*) INTO n FROM pg_constraint c JOIN pg_class t ON t.oid=c.conrelid
   WHERE t.relname='activities' AND c.contype='f'
     AND c.conname IN ('activities_test_attempt_fk','activities_exam_fk','activities_class_session_fk',
                       'activities_assignment_fk','activities_review_fk');
  IF n<>5 THEN RAISE EXCEPTION 'FAIL ACT-26: % of 5 typed source foreign keys present',n; END IF;
  RAISE NOTICE 'PASS ACT-26 all five typed source foreign keys are present on activities';
END $t$;
SELECT 'ACTIVITY SOURCE INTEGRITY TESTS PASSED (ACT-01..ACT-26)' AS result;
