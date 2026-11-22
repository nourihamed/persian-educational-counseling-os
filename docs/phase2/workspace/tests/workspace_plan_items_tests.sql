-- WS-PLAN-01 — the normalized PlanItem data model (Product Owner decision Option B, 2026-11-18).
-- SYNTHETIC ONLY (D-014). Run on a FRESH database after workspace_schema_draft.sql,
-- workspace_activation_transactions.sql, workspace_governance_events_draft.sql,
-- workspace_archive_transactions.sql, workspace_inbox_projection.sql, workspace_transfer_freeze.sql,
-- workspace_counselor_scope_draft.sql, workspace_plan_items_draft.sql, workspace_operations_draft.sql and
-- workspace_roles_setup_draft.sql (-v workspace_key). The concurrent-transition race is a separate script,
-- workspace_plan_item_status_race.sh.
--
-- WHAT THESE TESTS PROVE: the data model the decision approved — exactly one typed, student-bound source;
-- the approved status and deferral vocabularies; insert-only item definitions; versioned change with a
-- named predecessor and a reason; append-only, ordered, attributable status history; one source of truth
-- with derived output JSON; the transfer write barrier and the counselor boundary on both new tables.
-- WHAT THEY DO NOT PROVE: anything about scheduling, ranking, conflicts, generation or replay (Phase 12),
-- Since WS-ISO-01 decision B (2026-11-20) every actor is the VERIFIED principal of its transaction
-- (workspace_principal_test_harness.sql establishes one through the real command boundary), and the
-- Product Owner's WS-PLAN-01 decisions A2/B1/C1/D1/E1 are enforced (PLN-A*, PLN-D*, PLN-E*).
\set ON_ERROR_STOP on
SET app.workspace_key = :'workspace_key';
SELECT format('ws_%s_runtime', :'workspace_key') AS runtime_role \gset
SELECT format('ws_%s_synth_plan_writer', :'workspace_key') AS writer_role \gset
SELECT format('ws_%s_plan_migrator', :'workspace_key') AS migrator_role \gset

CREATE OR REPLACE FUNCTION pln_err(label text, stmt text, want_state text, want_msg text DEFAULT '')
RETURNS void LANGUAGE plpgsql AS $t$
BEGIN
  BEGIN
    EXECUTE stmt;
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE <> want_state THEN RAISE EXCEPTION 'FAIL %: got % (%), expected %',label,SQLSTATE,SQLERRM,want_state; END IF;
    IF want_msg <> '' AND position(want_msg IN SQLERRM)=0 THEN RAISE EXCEPTION 'FAIL %: wrong reason: %',label,SQLERRM; END IF;
    RAISE NOTICE 'PASS % (SQLSTATE %, reason verified)',label,SQLSTATE;
    RETURN;
  END;
  RAISE EXCEPTION 'FAIL %: statement unexpectedly succeeded',label;
END; $t$;
CREATE OR REPLACE FUNCTION pln_ok(label text, stmt text) RETURNS void LANGUAGE plpgsql AS $t$
BEGIN EXECUTE stmt; RAISE NOTICE 'PASS % (accepted)',label; END; $t$;
CREATE OR REPLACE FUNCTION pln_true(label text, cond boolean) RETURNS void LANGUAGE plpgsql AS $t$
BEGIN
  IF cond IS DISTINCT FROM true THEN RAISE EXCEPTION 'FAIL %: expected true, got %',label,cond; END IF;
  RAISE NOTICE 'PASS %',label;
END; $t$;
GRANT EXECUTE ON FUNCTION pln_err(text,text,text,text), pln_ok(text,text), pln_true(text,boolean) TO PUBLIC;

-- ======================================================================================================
-- Fixtures: counselor A for student s1, counselor B for student s2, a manager, and one source of each of
-- the six approved kinds for s1, plus an exam belonging to s2.
-- ======================================================================================================
INSERT INTO workspace_profile(singleton,workspace_id,workspace_type) VALUES (true,'a4000000-0000-0000-0000-000000000001','organization');
INSERT INTO workspace_memberships(membership_id,platform_user_id,status) VALUES
 ('b4000000-0000-0000-0000-00000000000a','c4000000-0000-0000-0000-00000000000a','active'),
 ('b4000000-0000-0000-0000-00000000000b','c4000000-0000-0000-0000-00000000000b','active'),
 ('b4000000-0000-0000-0000-000000000010','c4000000-0000-0000-0000-000000000010','active'),
 ('b4000000-0000-0000-0000-00000000000c','c4000000-0000-0000-0000-00000000000c','active');
INSERT INTO membership_roles(membership_id,role_key) VALUES
 ('b4000000-0000-0000-0000-00000000000a','counselor'),('b4000000-0000-0000-0000-00000000000b','counselor'),
 ('b4000000-0000-0000-0000-000000000010','organization_manager'),('b4000000-0000-0000-0000-00000000000c','counselor');
INSERT INTO students(student_id,platform_student_id,display_name,grade_key,lifecycle_state) VALUES
 ('e4000000-0000-0000-0000-000000000001','f4000000-0000-0000-0000-000000000001','Plan S1','grade_10','active'),
 ('e4000000-0000-0000-0000-000000000002','f4000000-0000-0000-0000-000000000002','Plan S2','grade_10','active'),
 ('e4000000-0000-0000-0000-000000000003','f4000000-0000-0000-0000-000000000003','Plan Frozen','grade_10','active');
INSERT INTO enrollments(enrollment_id,student_id,ownership_generation,state) VALUES
 ('a4100000-0000-0000-0000-000000000001','e4000000-0000-0000-0000-000000000001',1,'requested'),
 ('a4100000-0000-0000-0000-000000000002','e4000000-0000-0000-0000-000000000002',1,'requested'),
 ('a4100000-0000-0000-0000-000000000003','e4000000-0000-0000-0000-000000000003',1,'requested');
INSERT INTO counselor_assignments(assignment_id,enrollment_id,counselor_membership_id,is_responsible,state,accepted_at) VALUES
 ('a4200000-0000-0000-0000-000000000001','a4100000-0000-0000-0000-000000000001','b4000000-0000-0000-0000-00000000000a',true,'active',clock_timestamp()),
 ('a4200000-0000-0000-0000-000000000002','a4100000-0000-0000-0000-000000000002','b4000000-0000-0000-0000-00000000000b',true,'active',clock_timestamp()),
 ('a4200000-0000-0000-0000-000000000003','a4100000-0000-0000-0000-000000000003','b4000000-0000-0000-0000-00000000000a',true,'active',clock_timestamp()),
 ('a4200000-0000-0000-0000-00000000000c','a4100000-0000-0000-0000-000000000001','b4000000-0000-0000-0000-00000000000c',false,'active',clock_timestamp());
INSERT INTO subjects(subject_id,subject_key,title,grade_key,source_kind,status) VALUES
 ('a4300000-0000-0000-0000-000000000001','pln-physics-10','Physics','grade_10','workspace_custom','active');
INSERT INTO chapters(chapter_id,subject_id,title,order_no) VALUES ('a4310000-0000-0000-0000-000000000001','a4300000-0000-0000-0000-000000000001','Motion',1);
INSERT INTO topics(topic_id,chapter_id,title,order_no) VALUES ('a4320000-0000-0000-0000-000000000001','a4310000-0000-0000-0000-000000000001','Velocity',1);
INSERT INTO subtopics(subtopic_id,topic_id,title,order_no) VALUES ('a4330000-0000-0000-0000-000000000001','a4320000-0000-0000-0000-000000000001','Average velocity',1);
INSERT INTO activities(activity_id,student_id,topic_id,activity_kind,title,state) VALUES
 ('a4400000-0000-0000-0000-000000000001','e4000000-0000-0000-0000-000000000001','a4320000-0000-0000-0000-000000000001','study','Read','planned');
INSERT INTO exams(exam_id,student_id,title,exam_at,scoring_policy_snapshot) VALUES
 ('a4410000-0000-0000-0000-000000000001','e4000000-0000-0000-0000-000000000001','Mock 1',clock_timestamp()+interval '7 days','{}'),
 ('a4410000-0000-0000-0000-000000000002','e4000000-0000-0000-0000-000000000002','Mock S2',clock_timestamp()+interval '7 days','{}');
INSERT INTO reviews(review_id,student_id,topic_id,scheduled_at,state) VALUES
 ('a4420000-0000-0000-0000-000000000001','e4000000-0000-0000-0000-000000000001','a4320000-0000-0000-0000-000000000001',clock_timestamp()+interval '1 day','scheduled');
INSERT INTO assignments(assignment_id,student_id,title,state) VALUES
 ('a4430000-0000-0000-0000-000000000001','e4000000-0000-0000-0000-000000000001','Worksheet','assigned');
INSERT INTO student_plans(plan_id,student_id) VALUES
 ('a4500000-0000-0000-0000-000000000001','e4000000-0000-0000-0000-000000000001'),
 ('a4500000-0000-0000-0000-000000000002','e4000000-0000-0000-0000-000000000002'),
 ('a4500000-0000-0000-0000-000000000003','e4000000-0000-0000-0000-000000000003'),
 ('a4500000-0000-0000-0000-000000000004','e4000000-0000-0000-0000-000000000001');
INSERT INTO student_plan_versions(plan_version_id,plan_id,version_no,input_snapshot,rule_version,plan_content,status,created_by_membership_id) VALUES
 ('a4510000-0000-0000-0000-000000000001','a4500000-0000-0000-0000-000000000001',1,'{}','manual-v1','{}','draft','b4000000-0000-0000-0000-00000000000a'),
 ('a4510000-0000-0000-0000-000000000002','a4500000-0000-0000-0000-000000000002',1,'{}','manual-v1','{}','draft','b4000000-0000-0000-0000-00000000000b'),
 ('a4510000-0000-0000-0000-000000000003','a4500000-0000-0000-0000-000000000003',1,'{}','manual-v1','{}','draft','b4000000-0000-0000-0000-00000000000a');
-- a LEGACY plan (historical compatibility): JSON content, no items. Written by the MIGRATION identity, the
-- only identity that may create one (F-02).
SET SESSION AUTHORIZATION :"migrator_role";
INSERT INTO student_plan_versions(plan_version_id,plan_id,version_no,input_snapshot,rule_version,plan_content,status,content_model) VALUES
 ('a4510000-0000-0000-0000-000000000004','a4500000-0000-0000-0000-000000000004',1,'{}','legacy','{"legacy":true}','draft','legacy_json');
RESET SESSION AUTHORIZATION;
\ir workspace_principal_test_harness.sql

-- ======================================================================================================
-- CATALOG
-- ======================================================================================================
DO $t$
DECLARE v_bad text;
BEGIN
  SELECT string_agg(table_name, ', ') INTO v_bad FROM student_write_barrier_coverage
   WHERE table_name IN ('plan_items','plan_item_status_events') AND NOT has_barrier;
  IF v_bad IS NOT NULL OR (SELECT count(*) FROM student_write_barrier_coverage
                            WHERE table_name IN ('plan_items','plan_item_status_events')) <> 2 THEN
    RAISE EXCEPTION 'FAIL PLN-C1 the plan tables are not both inside the transfer write barrier: %', v_bad;
  END IF;
  IF EXISTS (SELECT 1 FROM student_write_barrier_coverage WHERE NOT has_barrier) THEN
    RAISE EXCEPTION 'FAIL PLN-C1 a student-scoped table lacks the barrier in this database';
  END IF;
  RAISE NOTICE 'PASS PLN-C1 plan_items and plan_item_status_events are inside the transfer write barrier, and no student-scoped table here lacks it';
END $t$;
DO $t$
DECLARE r text := format('ws_%s_runtime', current_setting('app.workspace_key'));
        w text := format('ws_%s_synth_plan_writer', current_setting('app.workspace_key'));
        t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['plan_items','plan_item_status_events'] LOOP
    IF has_table_privilege(r,t,'INSERT') OR has_table_privilege(r,t,'UPDATE') OR has_table_privilege(r,t,'DELETE') THEN
      RAISE EXCEPTION 'FAIL PLN-C2 the runtime can write %; no application identity can be authenticated as a plan actor (F-01)', t;
    END IF;
    IF NOT has_table_privilege(r,t,'SELECT') THEN RAISE EXCEPTION 'FAIL PLN-C2 the runtime cannot read %', t; END IF;
    IF has_table_privilege(w,t,'UPDATE') OR has_table_privilege(w,t,'DELETE') OR NOT has_table_privilege(w,t,'INSERT') THEN
      RAISE EXCEPTION 'FAIL PLN-C2 the synthetic writer should hold INSERT and no UPDATE/DELETE on %', t;
    END IF;
  END LOOP;
  IF has_column_privilege(r,'student_plan_versions','content_model','INSERT') THEN
    RAISE EXCEPTION 'FAIL PLN-C2 the runtime may name content_model, so it could create legacy_json versions (F-02)';
  END IF;
  RAISE NOTICE 'PASS PLN-C2 the runtime reads plan items and history but writes neither, and cannot name content_model; the synthetic writer may only INSERT';
END $t$;
DO $t$
BEGIN
  -- coalesce: a MISSING constraint yields NULL, and `NULL !~ ...` is NULL, which IF treats as false. Without
  -- it this assertion passed with the constraint dropped (found by the negative control).
  IF coalesce((SELECT pg_get_constraintdef(c.oid) FROM pg_constraint c
       WHERE c.conname='plan_item_exactly_one_source') ~ 'num_nonnulls.*= 1', false) = false THEN
    RAISE EXCEPTION 'FAIL PLN-C3 the exactly-one-source constraint is missing or changed';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='plan_items'
              AND column_name IN ('source_type','source_id','source_kind','entity_type','entity_id')) THEN
    RAISE EXCEPTION 'FAIL PLN-C3 plan_items carries an untyped polymorphic source column';
  END IF;
  RAISE NOTICE 'PASS PLN-C3 exactly one typed source is a CHECK, and no polymorphic source column exists';
END $t$;
DO $t$
DECLARE v_status text; v_reason text;
BEGIN
  SELECT pg_get_constraintdef(c.oid) INTO v_status FROM pg_constraint c
   WHERE c.conrelid='plan_item_status_events'::regclass AND pg_get_constraintdef(c.oid) LIKE '%to_status%partially_completed%';
  SELECT pg_get_constraintdef(c.oid) INTO v_reason FROM pg_constraint c
   WHERE c.conrelid='plan_item_status_events'::regclass AND pg_get_constraintdef(c.oid) LIKE '%deferral_reason%counselor_adjustment%';
  -- the decision's vocabularies, pinned exactly so a silent edit fails here
  IF v_status IS NULL OR (SELECT count(*) FROM regexp_matches(v_status, '''(planned|in_progress|completed|partially_completed|deferred|skipped|cancelled)''', 'g')) <> 7 THEN
    RAISE EXCEPTION 'FAIL PLN-C4 the status vocabulary differs from the decision: %', v_status;
  END IF;
  IF v_reason IS NULL OR (SELECT count(*) FROM regexp_matches(v_reason, '''(insufficient_time|schedule_conflict|prerequisite_not_mastered|difficulty|illness_or_absence|resource_unavailable|higher_priority_task|student_requested|counselor_adjustment|other)''', 'g')) <> 10 THEN
    RAISE EXCEPTION 'FAIL PLN-C4 the deferral-reason vocabulary differs from the decision: %', v_reason;
  END IF;
  RAISE NOTICE 'PASS PLN-C4 the seven statuses and ten deferral reasons match the Product Owner decision exactly';
END $t$;

-- ======================================================================================================
-- ITEMS — as the SYNTHETIC writer, the only identity that may write them (F-01)
-- ======================================================================================================
SET SESSION AUTHORIZATION :"writer_role";
BEGIN;
SELECT test_establish('counselor','b4000000-0000-0000-0000-00000000000a');
SELECT pln_ok('PLN-01 an item on a TOPIC', $q$INSERT INTO plan_items(plan_item_id,plan_version_id,plan_id,student_id,item_no,topic_id,planned_local_date,planned_start_local,planned_minutes,timezone_name,created_by_membership_id)
  VALUES ('a4600000-0000-0000-0000-000000000001','a4510000-0000-0000-0000-000000000001','a4500000-0000-0000-0000-000000000001','e4000000-0000-0000-0000-000000000001',1,'a4320000-0000-0000-0000-000000000001','2026-11-21','08:00',45,'Asia/Tehran','b4000000-0000-0000-0000-00000000000a')$q$);
SELECT pln_ok('PLN-02 an item on a SUBTOPIC', $q$INSERT INTO plan_items(plan_item_id,plan_version_id,plan_id,student_id,item_no,subtopic_id,planned_local_date,timezone_name,created_by_membership_id)
  VALUES ('a4600000-0000-0000-0000-000000000002','a4510000-0000-0000-0000-000000000001','a4500000-0000-0000-0000-000000000001','e4000000-0000-0000-0000-000000000001',2,'a4330000-0000-0000-0000-000000000001','2026-11-21','Asia/Tehran','b4000000-0000-0000-0000-00000000000a')$q$);
SELECT pln_ok('PLN-03 an item on an ACTIVITY', $q$INSERT INTO plan_items(plan_item_id,plan_version_id,plan_id,student_id,item_no,activity_id,planned_local_date,timezone_name,created_by_membership_id)
  VALUES ('a4600000-0000-0000-0000-000000000003','a4510000-0000-0000-0000-000000000001','a4500000-0000-0000-0000-000000000001','e4000000-0000-0000-0000-000000000001',3,'a4400000-0000-0000-0000-000000000001','2026-11-22','Asia/Tehran','b4000000-0000-0000-0000-00000000000a')$q$);
SELECT pln_ok('PLN-04 an item on an EXAM', $q$INSERT INTO plan_items(plan_item_id,plan_version_id,plan_id,student_id,item_no,exam_id,planned_local_date,timezone_name,created_by_membership_id)
  VALUES ('a4600000-0000-0000-0000-000000000004','a4510000-0000-0000-0000-000000000001','a4500000-0000-0000-0000-000000000001','e4000000-0000-0000-0000-000000000001',4,'a4410000-0000-0000-0000-000000000001','2026-11-23','Asia/Tehran','b4000000-0000-0000-0000-00000000000a')$q$);
SELECT pln_ok('PLN-05 an item on a REVIEW', $q$INSERT INTO plan_items(plan_item_id,plan_version_id,plan_id,student_id,item_no,review_id,planned_local_date,timezone_name,created_by_membership_id)
  VALUES ('a4600000-0000-0000-0000-000000000005','a4510000-0000-0000-0000-000000000001','a4500000-0000-0000-0000-000000000001','e4000000-0000-0000-0000-000000000001',5,'a4420000-0000-0000-0000-000000000001','2026-11-22','Asia/Tehran','b4000000-0000-0000-0000-00000000000a')$q$);
SELECT pln_ok('PLN-06 an item on an ASSIGNMENT', $q$INSERT INTO plan_items(plan_item_id,plan_version_id,plan_id,student_id,item_no,assignment_id,planned_local_date,timezone_name,created_by_membership_id)
  VALUES ('a4600000-0000-0000-0000-000000000006','a4510000-0000-0000-0000-000000000001','a4500000-0000-0000-0000-000000000001','e4000000-0000-0000-0000-000000000001',6,'a4430000-0000-0000-0000-000000000001','2026-11-24','Asia/Tehran','b4000000-0000-0000-0000-00000000000a')$q$);

SELECT pln_err('PLN-07 an item with NO source is refused', $q$INSERT INTO plan_items(plan_item_id,plan_version_id,plan_id,student_id,item_no,planned_local_date,timezone_name,created_by_membership_id)
  VALUES (gen_random_uuid(),'a4510000-0000-0000-0000-000000000001','a4500000-0000-0000-0000-000000000001','e4000000-0000-0000-0000-000000000001',7,'2026-11-21','Asia/Tehran','b4000000-0000-0000-0000-00000000000a')$q$,'23514','plan_item_exactly_one_source');
SELECT pln_err('PLN-08 an item with TWO sources is refused', $q$INSERT INTO plan_items(plan_item_id,plan_version_id,plan_id,student_id,item_no,topic_id,review_id,planned_local_date,timezone_name,created_by_membership_id)
  VALUES (gen_random_uuid(),'a4510000-0000-0000-0000-000000000001','a4500000-0000-0000-0000-000000000001','e4000000-0000-0000-0000-000000000001',7,'a4320000-0000-0000-0000-000000000001','a4420000-0000-0000-0000-000000000001','2026-11-21','Asia/Tehran','b4000000-0000-0000-0000-00000000000a')$q$,'23514','plan_item_exactly_one_source');
SELECT pln_err('PLN-09 s1''s plan cannot schedule s2''s EXAM (student-bound source)', $q$INSERT INTO plan_items(plan_item_id,plan_version_id,plan_id,student_id,item_no,exam_id,planned_local_date,timezone_name,created_by_membership_id)
  VALUES (gen_random_uuid(),'a4510000-0000-0000-0000-000000000001','a4500000-0000-0000-0000-000000000001','e4000000-0000-0000-0000-000000000001',7,'a4410000-0000-0000-0000-000000000002','2026-11-21','Asia/Tehran','b4000000-0000-0000-0000-00000000000a')$q$,'23503');
SELECT pln_err('PLN-11a WS-ISO-01: under A''s verified principal, an item NAMING counselor B is refused (impersonation)', $q$INSERT INTO plan_items(plan_item_id,plan_version_id,plan_id,student_id,item_no,topic_id,planned_local_date,timezone_name,created_by_membership_id)
  VALUES (gen_random_uuid(),'a4510000-0000-0000-0000-000000000001','a4500000-0000-0000-0000-000000000001','e4000000-0000-0000-0000-000000000001',7,'a4320000-0000-0000-0000-000000000001','2026-11-21','Asia/Tehran','b4000000-0000-0000-0000-00000000000b')$q$,'42501','must be the verified principal');
SELECT pln_err('PLN-11b a manager without explicit permission cannot plan for a student', $q$INSERT INTO plan_items(plan_item_id,plan_version_id,plan_id,student_id,item_no,topic_id,planned_local_date,timezone_name,created_by_membership_id)
  VALUES (gen_random_uuid(),'a4510000-0000-0000-0000-000000000001','a4500000-0000-0000-0000-000000000001','e4000000-0000-0000-0000-000000000001',7,'a4320000-0000-0000-0000-000000000001','2026-11-21','Asia/Tehran','b4000000-0000-0000-0000-000000000010')$q$,'42501','must be the verified principal');
SELECT pln_err('PLN-12 an unknown time zone is refused', $q$INSERT INTO plan_items(plan_item_id,plan_version_id,plan_id,student_id,item_no,topic_id,planned_local_date,timezone_name,created_by_membership_id)
  VALUES (gen_random_uuid(),'a4510000-0000-0000-0000-000000000001','a4500000-0000-0000-0000-000000000001','e4000000-0000-0000-0000-000000000001',7,'a4320000-0000-0000-0000-000000000001','2026-11-21','Asia/Teheran-ish','b4000000-0000-0000-0000-00000000000a')$q$,'23514','unknown time zone');
SELECT pln_true('PLN-13 the UTC projection is derived: 08:00 Asia/Tehran on 2026-11-21 is 04:30 UTC',
  (SELECT planned_start_utc FROM plan_items WHERE plan_item_id='a4600000-0000-0000-0000-000000000001') = timestamptz '2026-11-21 04:30:00+00');
SELECT pln_ok('PLN-14a a caller-supplied (wrong) UTC value is accepted only to be replaced', $q$INSERT INTO plan_items(plan_item_id,plan_version_id,plan_id,student_id,item_no,topic_id,planned_local_date,planned_start_local,planned_start_utc,timezone_name,created_by_membership_id)
  VALUES ('a4600000-0000-0000-0000-000000000007','a4510000-0000-0000-0000-000000000001','a4500000-0000-0000-0000-000000000001','e4000000-0000-0000-0000-000000000001',7,'a4320000-0000-0000-0000-000000000001','2026-11-25','20:15','1999-01-01 00:00+00','Asia/Tehran','b4000000-0000-0000-0000-00000000000a')$q$);
SELECT pln_true('PLN-14b ... the stored UTC is the derived one, 16:45 UTC',
  (SELECT planned_start_utc FROM plan_items WHERE plan_item_id='a4600000-0000-0000-0000-000000000007') = timestamptz '2026-11-25 16:45:00+00');
SELECT pln_err('PLN-15 a plan item cannot be UPDATED (no UPDATE privilege)', $q$UPDATE plan_items SET planned_minutes=60 WHERE plan_item_id='a4600000-0000-0000-0000-000000000001'$q$,'42501');
SELECT pln_err('PLN-16 a plan item cannot be DELETED (no DELETE privilege)', $q$DELETE FROM plan_items WHERE plan_item_id='a4600000-0000-0000-0000-000000000001'$q$,'42501');
COMMIT;
-- PLN-11: counselor B, as B's OWN verified principal, still cannot plan for A's student (the boundary)
BEGIN;
SELECT test_establish('counselor','b4000000-0000-0000-0000-00000000000b');
SELECT pln_err('PLN-11 counselor B, as B, cannot plan for counselor A''s student', $q$INSERT INTO plan_items(plan_item_id,plan_version_id,plan_id,student_id,item_no,topic_id,planned_local_date,timezone_name,created_by_membership_id)
  VALUES (gen_random_uuid(),'a4510000-0000-0000-0000-000000000001','a4500000-0000-0000-0000-000000000001','e4000000-0000-0000-0000-000000000001',9,'a4320000-0000-0000-0000-000000000001','2026-11-21','Asia/Tehran','b4000000-0000-0000-0000-00000000000b')$q$,'23514','cannot plan for that student');
SELECT pln_err('PLN-10 an item cannot claim a different student than its plan (as B, who does reach s2)', $q$INSERT INTO plan_items(plan_item_id,plan_version_id,plan_id,student_id,item_no,topic_id,planned_local_date,timezone_name,created_by_membership_id)
  VALUES (gen_random_uuid(),'a4510000-0000-0000-0000-000000000001','a4500000-0000-0000-0000-000000000001','e4000000-0000-0000-0000-000000000002',19,'a4320000-0000-0000-0000-000000000001','2026-11-21','Asia/Tehran','b4000000-0000-0000-0000-00000000000b')$q$,'23503');
COMMIT;
SELECT pln_err('PLN-11c with NO verified principal the writer cannot create an item at all', $q$INSERT INTO plan_items(plan_item_id,plan_version_id,plan_id,student_id,item_no,topic_id,planned_local_date,timezone_name,created_by_membership_id)
  VALUES (gen_random_uuid(),'a4510000-0000-0000-0000-000000000001','a4500000-0000-0000-0000-000000000001','e4000000-0000-0000-0000-000000000001',9,'a4320000-0000-0000-0000-000000000001','2026-11-21','Asia/Tehran','b4000000-0000-0000-0000-00000000000a')$q$,'42501','must be the verified principal');
RESET SESSION AUTHORIZATION;
-- PLN-15b/16b: the same refusals for an identity that HAS the privilege, so the rule does not rest on grants alone
SELECT pln_err('PLN-15b ... and the trigger refuses an UPDATE even where the privilege exists', $q$UPDATE plan_items SET planned_minutes=60 WHERE plan_item_id='a4600000-0000-0000-0000-000000000001'$q$,'23514','insert-only');
SELECT pln_err('PLN-16b ... and a DELETE', $q$DELETE FROM plan_items WHERE plan_item_id='a4600000-0000-0000-0000-000000000001'$q$,'23514','insert-only');
SELECT pln_err('PLN-17 TRUNCATE is refused', $q$TRUNCATE plan_items CASCADE$q$,'23514','TRUNCATE is refused');

-- ======================================================================================================
-- VERSIONS — one source of truth, change with a predecessor and a reason
-- ======================================================================================================
SET SESSION AUTHORIZATION :"runtime_role";
BEGIN;
SELECT test_establish('counselor','b4000000-0000-0000-0000-00000000000b');
SELECT pln_err('PLN-20 a NORMALIZED version cannot also carry JSON content', $q$INSERT INTO student_plan_versions(plan_version_id,plan_id,version_no,input_snapshot,rule_version,plan_content,status,created_by_membership_id,supersedes_plan_version_id,change_reason)
  VALUES (gen_random_uuid(),'a4500000-0000-0000-0000-000000000002',2,'{}','manual-v1','{"x":1}','draft','b4000000-0000-0000-0000-00000000000b','a4510000-0000-0000-0000-000000000002','synthetic')$q$,'23514','normalized_version_has_no_json_content');
COMMIT;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION :"writer_role";
BEGIN;
SELECT test_establish('counselor','b4000000-0000-0000-0000-00000000000a');
SELECT pln_err('PLN-21 items cannot be added to a LEGACY JSON version', $q$INSERT INTO plan_items(plan_item_id,plan_version_id,plan_id,student_id,item_no,topic_id,planned_local_date,timezone_name,created_by_membership_id)
  VALUES (gen_random_uuid(),'a4510000-0000-0000-0000-000000000004','a4500000-0000-0000-0000-000000000004','e4000000-0000-0000-0000-000000000001',1,'a4320000-0000-0000-0000-000000000001','2026-11-21','Asia/Tehran','b4000000-0000-0000-0000-00000000000a')$q$,'23514','only to normalized plan versions');
COMMIT;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION :"runtime_role";
BEGIN;
SELECT test_establish('counselor','b4000000-0000-0000-0000-00000000000a');
SELECT pln_err('PLN-22 a normalized version must record its author', $q$INSERT INTO student_plan_versions(plan_version_id,plan_id,version_no,input_snapshot,rule_version,plan_content,status)
  VALUES (gen_random_uuid(),'a4500000-0000-0000-0000-000000000002',2,'{}','manual-v1','{}','draft')$q$,'23514','must record the membership');
SELECT pln_ok('PLN-23 publish v1 of s1''s plan', $q$UPDATE student_plan_versions SET status='published', published_at=clock_timestamp() WHERE plan_version_id='a4510000-0000-0000-0000-000000000001'$q$);
COMMIT;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION :"writer_role";
BEGIN;
SELECT test_establish('counselor','b4000000-0000-0000-0000-00000000000a');
SELECT pln_err('PLN-24 no item can be added to a PUBLISHED version', $q$INSERT INTO plan_items(plan_item_id,plan_version_id,plan_id,student_id,item_no,topic_id,planned_local_date,timezone_name,created_by_membership_id)
  VALUES (gen_random_uuid(),'a4510000-0000-0000-0000-000000000001','a4500000-0000-0000-0000-000000000001','e4000000-0000-0000-0000-000000000001',8,'a4320000-0000-0000-0000-000000000001','2026-11-21','Asia/Tehran','b4000000-0000-0000-0000-00000000000a')$q$,'23514','DRAFT plan version');
COMMIT;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION :"runtime_role";
BEGIN;
SELECT test_establish('counselor','b4000000-0000-0000-0000-00000000000a');
SELECT pln_err('PLN-25 v2 without a predecessor and a reason is refused', $q$INSERT INTO student_plan_versions(plan_version_id,plan_id,version_no,input_snapshot,rule_version,plan_content,status,created_by_membership_id)
  VALUES (gen_random_uuid(),'a4500000-0000-0000-0000-000000000001',2,'{}','manual-v1','{}','draft','b4000000-0000-0000-0000-00000000000a')$q$,'23514','must name the version it supersedes');
SELECT pln_err('PLN-26 v2 cannot supersede ANOTHER plan''s version', $q$INSERT INTO student_plan_versions(plan_version_id,plan_id,version_no,input_snapshot,rule_version,plan_content,status,created_by_membership_id,supersedes_plan_version_id,change_reason)
  VALUES (gen_random_uuid(),'a4500000-0000-0000-0000-000000000001',2,'{}','manual-v1','{}','draft','b4000000-0000-0000-0000-00000000000a','a4510000-0000-0000-0000-000000000002','synthetic')$q$,'23514','EARLIER version of the SAME plan');
SELECT pln_ok('PLN-27 v2 naming v1 and a reason is accepted', $q$INSERT INTO student_plan_versions(plan_version_id,plan_id,version_no,input_snapshot,rule_version,plan_content,status,created_by_membership_id,supersedes_plan_version_id,change_reason)
  VALUES ('a4510000-0000-0000-0000-000000000011','a4500000-0000-0000-0000-000000000001',2,'{}','manual-v1','{}','draft','b4000000-0000-0000-0000-00000000000a','a4510000-0000-0000-0000-000000000001','synthetic: exam moved forward')$q$);
SELECT pln_err('PLN-28 F-02: the RUNTIME cannot create a legacy_json version — it may not even name content_model', $q$INSERT INTO student_plan_versions(plan_version_id,plan_id,version_no,input_snapshot,rule_version,plan_content,status,content_model)
  VALUES (gen_random_uuid(),'a4500000-0000-0000-0000-000000000002',2,'{}','legacy','{"x":1}','draft','legacy_json')$q$,'42501','permission denied');
SELECT pln_true('PLN-28b F-02: every version the runtime creates is normalized',
  (SELECT content_model FROM student_plan_versions WHERE plan_version_id='a4510000-0000-0000-0000-000000000011')='normalized');
SELECT pln_err('PLN-29 a version''s content model and supersession are fixed at creation', $q$UPDATE student_plan_versions SET change_reason='rewritten' WHERE plan_version_id='a4510000-0000-0000-0000-000000000011'$q$,'23514','fixed at creation');
-- H-02: direct INSERT cannot bypass the guarded publication transition, even for legacy rows.
SET SESSION AUTHORIZATION :"writer_role";
BEGIN;
SELECT test_establish('counselor','b4000000-0000-0000-0000-00000000000a');
SELECT pln_err('PLN-H2-01 a normalized PlanVersion cannot be inserted directly as published',
  $q$INSERT INTO student_plan_versions(plan_version_id,plan_id,version_no,input_snapshot,rule_version,plan_content,status,created_by_membership_id,supersedes_plan_version_id,change_reason)
     VALUES (gen_random_uuid(),'a4500000-0000-0000-0000-000000000001',3,'{}','manual-v1','{}','published','b4000000-0000-0000-0000-00000000000a','a4510000-0000-0000-0000-000000000011','synthetic')$q$,
  '23514','new PlanVersion must be inserted as draft');
COMMIT;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION :"migrator_role";
SELECT pln_err('PLN-H2-02 a migration-created legacy PlanVersion cannot be inserted directly as published',
  $q$INSERT INTO student_plan_versions(plan_version_id,plan_id,version_no,input_snapshot,rule_version,plan_content,status,content_model)
     VALUES (gen_random_uuid(),'a4500000-0000-0000-0000-000000000004',2,'{}','legacy','{"historic":true}','published','legacy_json')$q$,
  '23514','new PlanVersion must be inserted as draft');
RESET SESSION AUTHORIZATION;
SELECT pln_err('PLN-H2-03 a published PlanVersion is immutable, including non-content metadata',
  $q$UPDATE student_plan_versions SET published_at=clock_timestamp() WHERE plan_version_id='a4510000-0000-0000-0000-000000000001'$q$,
  '23514','published PlanVersion is immutable');

SELECT pln_true('PLN-29b the published v1 and its six-plus items are unchanged by v2',
  (SELECT count(*) FROM plan_items WHERE plan_version_id='a4510000-0000-0000-0000-000000000001') = 7);
COMMIT;

-- ======================================================================================================
-- STATUS TRANSITIONS — append-only, ordered, attributable, with a reason
-- ======================================================================================================
RESET SESSION AUTHORIZATION;
-- Every transition below is made by the verified principal it names (WS-ISO-01 B) and follows the Product
-- Owner's decisions: A2 (student: in_progress / completed / partially_completed; responsible counselor:
-- deferred / skipped / cancelled), B1 (published versions only), D1 (completed / skipped / cancelled are
-- terminal). One principal per transaction, so each actor gets its own transaction.
SET SESSION AUTHORIZATION :"writer_role";
BEGIN;
SELECT test_establish('student','e4000000-0000-0000-0000-000000000001');
SELECT pln_ok('PLN-30 student s1, as s1, starts item 1 (planned -> in_progress), with a reason', $q$INSERT INTO plan_item_status_events(event_id,plan_item_id,student_id,seq_no,from_status,to_status,reason_note,actor_kind)
  VALUES (gen_random_uuid(),'a4600000-0000-0000-0000-000000000001','e4000000-0000-0000-0000-000000000001',1,'planned','in_progress','synthetic: started','student')$q$);
SELECT pln_err('PLN-31 a STALE transition (still believing planned) is refused', $q$INSERT INTO plan_item_status_events(event_id,plan_item_id,student_id,seq_no,from_status,to_status,reason_note,actor_kind)
  VALUES (gen_random_uuid(),'a4600000-0000-0000-0000-000000000001','e4000000-0000-0000-0000-000000000001',2,'planned','completed','synthetic','student')$q$,'23514','stale transition');
SELECT pln_err('PLN-34 a status outside the student''s three (here: one outside the approved seven) is refused', $q$INSERT INTO plan_item_status_events(event_id,plan_item_id,student_id,seq_no,from_status,to_status,reason_note,actor_kind)
  VALUES (gen_random_uuid(),'a4600000-0000-0000-0000-000000000001','e4000000-0000-0000-0000-000000000001',2,'in_progress','overdue','synthetic','student')$q$,'42501','may record only');
SELECT pln_err('PLN-A2a a student may NOT defer (decision A2)', $q$INSERT INTO plan_item_status_events(event_id,plan_item_id,student_id,seq_no,from_status,to_status,deferral_reason,actor_kind)
  VALUES (gen_random_uuid(),'a4600000-0000-0000-0000-000000000001','e4000000-0000-0000-0000-000000000001',2,'in_progress','deferred','other','student')$q$,'42501','may record only');
SELECT pln_err('PLN-A2b a student may NOT cancel', $q$INSERT INTO plan_item_status_events(event_id,plan_item_id,student_id,seq_no,from_status,to_status,reason_note,actor_kind)
  VALUES (gen_random_uuid(),'a4600000-0000-0000-0000-000000000001','e4000000-0000-0000-0000-000000000001',2,'in_progress','cancelled','synthetic','student')$q$,'42501','may record only');
SELECT pln_err('PLN-A2c a student may NOT skip', $q$INSERT INTO plan_item_status_events(event_id,plan_item_id,student_id,seq_no,from_status,to_status,reason_note,actor_kind)
  VALUES (gen_random_uuid(),'a4600000-0000-0000-0000-000000000001','e4000000-0000-0000-0000-000000000001',2,'in_progress','skipped','synthetic','student')$q$,'42501','may record only');
SELECT pln_err('PLN-A2d a student principal cannot record a COUNSELOR actor', $q$INSERT INTO plan_item_status_events(event_id,plan_item_id,student_id,seq_no,from_status,to_status,reason_note,actor_kind,actor_membership_id)
  VALUES (gen_random_uuid(),'a4600000-0000-0000-0000-000000000001','e4000000-0000-0000-0000-000000000001',2,'in_progress','cancelled','synthetic','membership','b4000000-0000-0000-0000-00000000000a')$q$,'42501','must be the verified principal');
COMMIT;
BEGIN;
SELECT test_establish('counselor','b4000000-0000-0000-0000-00000000000a');
SELECT pln_err('PLN-32 deferred WITHOUT a reason code is refused', $q$INSERT INTO plan_item_status_events(event_id,plan_item_id,student_id,seq_no,from_status,to_status,reason_note,actor_kind,actor_membership_id)
  VALUES (gen_random_uuid(),'a4600000-0000-0000-0000-000000000001','e4000000-0000-0000-0000-000000000001',2,'in_progress','deferred','synthetic','membership','b4000000-0000-0000-0000-00000000000a')$q$,'23514');
SELECT pln_err('PLN-33 a reason code OUTSIDE the approved ten is refused', $q$INSERT INTO plan_item_status_events(event_id,plan_item_id,student_id,seq_no,from_status,to_status,deferral_reason,actor_kind,actor_membership_id)
  VALUES (gen_random_uuid(),'a4600000-0000-0000-0000-000000000001','e4000000-0000-0000-0000-000000000001',2,'in_progress','deferred','tired','membership','b4000000-0000-0000-0000-00000000000a')$q$,'23514');
SELECT pln_ok('PLN-35 the RESPONSIBLE counselor A defers with reason ''other'' and NO note (the note is optional)', $q$INSERT INTO plan_item_status_events(event_id,plan_item_id,student_id,seq_no,from_status,to_status,deferral_reason,actor_kind,actor_membership_id)
  VALUES (gen_random_uuid(),'a4600000-0000-0000-0000-000000000001','e4000000-0000-0000-0000-000000000001',2,'in_progress','deferred','other','membership','b4000000-0000-0000-0000-00000000000a')$q$);
SELECT pln_err('PLN-A2e counselor A may NOT record in_progress: undecided by A2, refused', $q$INSERT INTO plan_item_status_events(event_id,plan_item_id,student_id,seq_no,from_status,to_status,reason_note,actor_kind,actor_membership_id)
  VALUES (gen_random_uuid(),'a4600000-0000-0000-0000-000000000001','e4000000-0000-0000-0000-000000000001',3,'deferred','in_progress','synthetic','membership','b4000000-0000-0000-0000-00000000000a')$q$,'42501','undecided');
SELECT pln_err('PLN-A2f counselor A may NOT record completed: undecided by A2, refused', $q$INSERT INTO plan_item_status_events(event_id,plan_item_id,student_id,seq_no,from_status,to_status,reason_note,actor_kind,actor_membership_id)
  VALUES (gen_random_uuid(),'a4600000-0000-0000-0000-000000000001','e4000000-0000-0000-0000-000000000001',3,'deferred','completed','synthetic','membership','b4000000-0000-0000-0000-00000000000a')$q$,'42501','undecided');
SELECT pln_err('PLN-41b NO actor may record a transition TO planned (deferred -> planned): undecided, refused', $q$INSERT INTO plan_item_status_events(event_id,plan_item_id,student_id,seq_no,from_status,to_status,reason_note,actor_kind,actor_membership_id)
  VALUES (gen_random_uuid(),'a4600000-0000-0000-0000-000000000001','e4000000-0000-0000-0000-000000000001',3,'deferred','planned','synthetic','membership','b4000000-0000-0000-0000-00000000000a')$q$,'42501','no actor is authorized to record a transition to planned');
SELECT pln_err('PLN-A2g a counselor principal cannot record a STUDENT actor', $q$INSERT INTO plan_item_status_events(event_id,plan_item_id,student_id,seq_no,from_status,to_status,reason_note,actor_kind)
  VALUES (gen_random_uuid(),'a4600000-0000-0000-0000-000000000001','e4000000-0000-0000-0000-000000000001',3,'deferred','in_progress','synthetic','student')$q$,'42501','a student transition must be made by that student');
SELECT pln_err('PLN-A2h under A''s principal, an actor NAMING counselor B is refused (impersonation)', $q$INSERT INTO plan_item_status_events(event_id,plan_item_id,student_id,seq_no,from_status,to_status,reason_note,actor_kind,actor_membership_id)
  VALUES (gen_random_uuid(),'a4600000-0000-0000-0000-000000000001','e4000000-0000-0000-0000-000000000001',3,'deferred','cancelled','synthetic','membership','b4000000-0000-0000-0000-00000000000b')$q$,'42501','must be the verified principal');
COMMIT;
BEGIN;
SELECT test_establish('counselor','b4000000-0000-0000-0000-00000000000c');
SELECT pln_err('PLN-A2i a co-assigned counselor who is NOT responsible cannot cancel', $q$INSERT INTO plan_item_status_events(event_id,plan_item_id,student_id,seq_no,from_status,to_status,reason_note,actor_kind,actor_membership_id)
  VALUES (gen_random_uuid(),'a4600000-0000-0000-0000-000000000001','e4000000-0000-0000-0000-000000000001',3,'deferred','cancelled','synthetic','membership','b4000000-0000-0000-0000-00000000000c')$q$,'42501','not the responsible counselor');
COMMIT;
BEGIN;
SELECT test_establish('counselor','b4000000-0000-0000-0000-00000000000b');
SELECT pln_err('PLN-39 counselor B, as B, cannot transition counselor A''s student''s item', $q$INSERT INTO plan_item_status_events(event_id,plan_item_id,student_id,seq_no,from_status,to_status,reason_note,actor_kind,actor_membership_id)
  VALUES (gen_random_uuid(),'a4600000-0000-0000-0000-000000000001','e4000000-0000-0000-0000-000000000001',3,'deferred','cancelled','synthetic','membership','b4000000-0000-0000-0000-00000000000b')$q$,'42501','not the responsible counselor');
SELECT pln_err('PLN-40 an event cannot name a different student than its item', $q$INSERT INTO plan_item_status_events(event_id,plan_item_id,student_id,seq_no,from_status,to_status,reason_note,actor_kind,actor_membership_id)
  VALUES (gen_random_uuid(),'a4600000-0000-0000-0000-000000000001','e4000000-0000-0000-0000-000000000002',3,'deferred','cancelled','synthetic','membership','b4000000-0000-0000-0000-00000000000b')$q$,'23503');
COMMIT;
BEGIN;
SELECT test_establish('student','e4000000-0000-0000-0000-000000000002');
SELECT pln_err('PLN-A2j student s2 cannot record a transition on s1''s item', $q$INSERT INTO plan_item_status_events(event_id,plan_item_id,student_id,seq_no,from_status,to_status,reason_note,actor_kind)
  VALUES (gen_random_uuid(),'a4600000-0000-0000-0000-000000000001','e4000000-0000-0000-0000-000000000001',3,'deferred','in_progress','synthetic','student')$q$,'42501','a student transition must be made by that student');
COMMIT;
BEGIN;
SELECT test_establish('student','e4000000-0000-0000-0000-000000000001');
SELECT pln_err('PLN-36 a non-deferred transition WITHOUT a reason is refused', $q$INSERT INTO plan_item_status_events(event_id,plan_item_id,student_id,seq_no,from_status,to_status,actor_kind)
  VALUES (gen_random_uuid(),'a4600000-0000-0000-0000-000000000001','e4000000-0000-0000-0000-000000000001',3,'deferred','in_progress','student')$q$,'23514');
SELECT pln_err('PLN-37 a deferral reason on a NON-deferred transition is refused', $q$INSERT INTO plan_item_status_events(event_id,plan_item_id,student_id,seq_no,from_status,to_status,deferral_reason,reason_note,actor_kind)
  VALUES (gen_random_uuid(),'a4600000-0000-0000-0000-000000000001','e4000000-0000-0000-0000-000000000001',3,'deferred','in_progress','difficulty','synthetic','student')$q$,'23514');
SELECT pln_err('PLN-38 a transition with a skipped sequence number is refused', $q$INSERT INTO plan_item_status_events(event_id,plan_item_id,student_id,seq_no,from_status,to_status,reason_note,actor_kind)
  VALUES (gen_random_uuid(),'a4600000-0000-0000-0000-000000000001','e4000000-0000-0000-0000-000000000001',5,'deferred','in_progress','synthetic','student')$q$,'23514','out of order');
SELECT pln_ok('PLN-41 student s1 resumes it (deferred -> in_progress), attributed and reasoned', $q$INSERT INTO plan_item_status_events(event_id,plan_item_id,student_id,seq_no,from_status,to_status,reason_note,actor_kind)
  VALUES (gen_random_uuid(),'a4600000-0000-0000-0000-000000000001','e4000000-0000-0000-0000-000000000001',3,'deferred','in_progress','synthetic: resumed after review','student')$q$);
SELECT pln_ok('PLN-D1a student s1 COMPLETES item 2 (planned -> completed)', $q$INSERT INTO plan_item_status_events(event_id,plan_item_id,student_id,seq_no,from_status,to_status,reason_note,actor_kind)
  VALUES (gen_random_uuid(),'a4600000-0000-0000-0000-000000000002','e4000000-0000-0000-0000-000000000001',1,'planned','completed','synthetic','student')$q$);
SELECT pln_err('PLN-D1b completed is TERMINAL: s1 cannot move it back to in_progress', $q$INSERT INTO plan_item_status_events(event_id,plan_item_id,student_id,seq_no,from_status,to_status,reason_note,actor_kind)
  VALUES (gen_random_uuid(),'a4600000-0000-0000-0000-000000000002','e4000000-0000-0000-0000-000000000001',2,'completed','in_progress','synthetic','student')$q$,'23514','terminal status');
SELECT pln_ok('PLN-A2k student s1 records partially_completed on item 5 (planned -> partially_completed)', $q$INSERT INTO plan_item_status_events(event_id,plan_item_id,student_id,seq_no,from_status,to_status,reason_note,actor_kind)
  VALUES (gen_random_uuid(),'a4600000-0000-0000-0000-000000000005','e4000000-0000-0000-0000-000000000001',1,'planned','partially_completed','synthetic','student')$q$);
SELECT pln_ok('PLN-A2l ... and then completed (partially_completed -> completed)', $q$INSERT INTO plan_item_status_events(event_id,plan_item_id,student_id,seq_no,from_status,to_status,reason_note,actor_kind)
  VALUES (gen_random_uuid(),'a4600000-0000-0000-0000-000000000005','e4000000-0000-0000-0000-000000000001',2,'partially_completed','completed','synthetic','student')$q$);
COMMIT;
BEGIN;
SELECT test_establish('counselor','b4000000-0000-0000-0000-00000000000a');
SELECT pln_err('PLN-D1c completed is terminal for the counselor too: A cannot cancel completed item 2', $q$INSERT INTO plan_item_status_events(event_id,plan_item_id,student_id,seq_no,from_status,to_status,reason_note,actor_kind,actor_membership_id)
  VALUES (gen_random_uuid(),'a4600000-0000-0000-0000-000000000002','e4000000-0000-0000-0000-000000000001',2,'completed','cancelled','synthetic','membership','b4000000-0000-0000-0000-00000000000a')$q$,'23514','terminal status');
SELECT pln_ok('PLN-D1d the responsible counselor CANCELS item 3', $q$INSERT INTO plan_item_status_events(event_id,plan_item_id,student_id,seq_no,from_status,to_status,reason_note,actor_kind,actor_membership_id)
  VALUES (gen_random_uuid(),'a4600000-0000-0000-0000-000000000003','e4000000-0000-0000-0000-000000000001',1,'planned','cancelled','synthetic','membership','b4000000-0000-0000-0000-00000000000a')$q$);
SELECT pln_ok('PLN-D1e the responsible counselor SKIPS item 4', $q$INSERT INTO plan_item_status_events(event_id,plan_item_id,student_id,seq_no,from_status,to_status,reason_note,actor_kind,actor_membership_id)
  VALUES (gen_random_uuid(),'a4600000-0000-0000-0000-000000000004','e4000000-0000-0000-0000-000000000001',1,'planned','skipped','synthetic','membership','b4000000-0000-0000-0000-00000000000a')$q$);
COMMIT;
BEGIN;
SELECT test_establish('student','e4000000-0000-0000-0000-000000000001');
SELECT pln_err('PLN-D1f cancelled is TERMINAL: the student cannot restart item 3', $q$INSERT INTO plan_item_status_events(event_id,plan_item_id,student_id,seq_no,from_status,to_status,reason_note,actor_kind)
  VALUES (gen_random_uuid(),'a4600000-0000-0000-0000-000000000003','e4000000-0000-0000-0000-000000000001',2,'cancelled','in_progress','synthetic','student')$q$,'23514','terminal status');
SELECT pln_err('PLN-D1g skipped is TERMINAL: the student cannot complete item 4', $q$INSERT INTO plan_item_status_events(event_id,plan_item_id,student_id,seq_no,from_status,to_status,reason_note,actor_kind)
  VALUES (gen_random_uuid(),'a4600000-0000-0000-0000-000000000004','e4000000-0000-0000-0000-000000000001',2,'skipped','completed','synthetic','student')$q$,'23514','terminal status');
COMMIT;
SELECT pln_err('PLN-A2m with NO verified principal, even the synthetic writer cannot record a transition', $q$INSERT INTO plan_item_status_events(event_id,plan_item_id,student_id,seq_no,from_status,to_status,reason_note,actor_kind)
  VALUES (gen_random_uuid(),'a4600000-0000-0000-0000-000000000001','e4000000-0000-0000-0000-000000000001',4,'in_progress','completed','synthetic','student')$q$,'42501','a student transition must be made by that student');
SELECT pln_true('PLN-42 the current status is derived from the latest transition',
  (SELECT status FROM plan_item_current_status WHERE plan_item_id='a4600000-0000-0000-0000-000000000001')='in_progress'
  AND (SELECT status FROM plan_item_current_status WHERE plan_item_id='a4600000-0000-0000-0000-000000000002')='completed'
  AND (SELECT status FROM plan_item_current_status WHERE plan_item_id='a4600000-0000-0000-0000-000000000006')='planned');
SELECT pln_true('PLN-43 the full history is retained and attributed: student in_progress > counselor deferred(other) > student in_progress',
  (SELECT string_agg(to_status||coalesce('('||deferral_reason||')','')||'/'||actor_kind,'>' ORDER BY seq_no) FROM plan_item_status_events
    WHERE plan_item_id='a4600000-0000-0000-0000-000000000001') = 'in_progress/student>deferred(other)/membership>in_progress/student');
SELECT pln_err('PLN-44 status history cannot be UPDATED (no UPDATE privilege)', $q$UPDATE plan_item_status_events SET to_status='completed'$q$,'42501');
RESET SESSION AUTHORIZATION;
SELECT pln_err('PLN-44b ... nor by an identity holding the privilege', $q$UPDATE plan_item_status_events SET reason_note='rewritten'$q$,'23514','append-only');
SELECT pln_err('PLN-45 status history cannot be DELETED', $q$DELETE FROM plan_item_status_events$q$,'23514','append-only');
SELECT pln_err('PLN-46 status history cannot be TRUNCATED', $q$TRUNCATE plan_item_status_events$q$,'23514','TRUNCATE is refused');


-- ======================================================================================================
-- F-01 / F-02 / F-03 — ADVERSARIAL TESTS (Supervisor review of d75d039)
-- ======================================================================================================
-- An identity that HOLDS the table privileges but is NOT the synthetic writer: it shows the trigger refuses
-- on its own, so the protection is not merely a missing GRANT that someone could add back.
-- Roles are cluster-wide, so the name carries the workspace key, as every other role here does.
SELECT format('ws_%s_pln_intruder', :'workspace_key') AS intruder_role \gset
SELECT format('CREATE ROLE %I NOLOGIN', :'intruder_role')
 WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'intruder_role') \gexec
GRANT SELECT, INSERT ON plan_items, plan_item_status_events, student_plan_versions TO :"intruder_role";
GRANT SELECT ON student_plans, counselor_assignments, enrollments, workspace_memberships, membership_roles,
  students, topics, plan_privileged_identities, plan_item_current_status TO :"intruder_role";

SET SESSION AUTHORIZATION :"runtime_role";
SELECT pln_err('PLN-70 F-01: the runtime cannot record a transition CLAIMING TO BE THE STUDENT', $q$INSERT INTO plan_item_status_events(event_id,plan_item_id,student_id,seq_no,from_status,to_status,reason_note,actor_kind)
  VALUES (gen_random_uuid(),'a4600000-0000-0000-0000-000000000002','e4000000-0000-0000-0000-000000000001',1,'planned','completed','impersonation','student')$q$,'42501','permission denied');
SELECT pln_err('PLN-71 F-01: the runtime cannot record a transition CLAIMING TO BE counselor A', $q$INSERT INTO plan_item_status_events(event_id,plan_item_id,student_id,seq_no,from_status,to_status,reason_note,actor_kind,actor_membership_id)
  VALUES (gen_random_uuid(),'a4600000-0000-0000-0000-000000000002','e4000000-0000-0000-0000-000000000001',1,'planned','completed','impersonation','membership','b4000000-0000-0000-0000-00000000000a')$q$,'42501','permission denied');
SELECT pln_err('PLN-72 F-01: the runtime cannot create a plan item CLAIMING TO BE counselor A', $q$INSERT INTO plan_items(plan_item_id,plan_version_id,plan_id,student_id,item_no,topic_id,planned_local_date,timezone_name,created_by_membership_id)
  VALUES (gen_random_uuid(),'a4510000-0000-0000-0000-000000000011','a4500000-0000-0000-0000-000000000001','e4000000-0000-0000-0000-000000000001',1,'a4320000-0000-0000-0000-000000000001','2026-11-26','Asia/Tehran','b4000000-0000-0000-0000-00000000000a')$q$,'42501','permission denied');
RESET SESSION AUTHORIZATION;

SET SESSION AUTHORIZATION :"intruder_role";
SELECT pln_err('PLN-73 F-01: WITH the INSERT privilege, a non-writer identity is still refused a transition', $q$INSERT INTO plan_item_status_events(event_id,plan_item_id,student_id,seq_no,from_status,to_status,reason_note,actor_kind,actor_membership_id)
  VALUES (gen_random_uuid(),'a4600000-0000-0000-0000-000000000002','e4000000-0000-0000-0000-000000000001',1,'planned','completed','impersonation','membership','b4000000-0000-0000-0000-00000000000a')$q$,'42501','writable only by the synthetic test identity');
SELECT pln_err('PLN-74 F-01: ... and a plan item', $q$INSERT INTO plan_items(plan_item_id,plan_version_id,plan_id,student_id,item_no,topic_id,planned_local_date,timezone_name,created_by_membership_id)
  VALUES (gen_random_uuid(),'a4510000-0000-0000-0000-000000000011','a4500000-0000-0000-0000-000000000001','e4000000-0000-0000-0000-000000000001',1,'a4320000-0000-0000-0000-000000000001','2026-11-26','Asia/Tehran','b4000000-0000-0000-0000-00000000000a')$q$,'42501','writable only by the synthetic test identity');
SELECT pln_err('PLN-75 F-02: WITH full INSERT on plan versions, a non-migration identity still cannot create legacy_json', $q$INSERT INTO student_plan_versions(plan_version_id,plan_id,version_no,input_snapshot,rule_version,plan_content,status,content_model)
  VALUES (gen_random_uuid(),'a4500000-0000-0000-0000-000000000002',2,'{}','legacy','{"x":1}','draft','legacy_json')$q$,'42501','only be written by the migration identity');
RESET SESSION AUTHORIZATION;

SET SESSION AUTHORIZATION :"writer_role";
BEGIN;
SELECT test_establish('counselor','b4000000-0000-0000-0000-00000000000a');
SELECT pln_err('PLN-76 a STUDENT actor without that student''s verified principal is refused (here the principal is counselor A)', $q$INSERT INTO plan_item_status_events(event_id,plan_item_id,student_id,seq_no,from_status,to_status,reason_note,actor_kind)
  VALUES (gen_random_uuid(),'a4600000-0000-0000-0000-000000000006','e4000000-0000-0000-0000-000000000001',1,'planned','in_progress','synthetic','student')$q$,'42501','a student transition must be made by that student');
SELECT pln_err('PLN-77 decision B1: a transition on an item of a DRAFT version is prohibited', $q$INSERT INTO plan_items(plan_item_id,plan_version_id,plan_id,student_id,item_no,topic_id,planned_local_date,timezone_name,created_by_membership_id)
  VALUES ('a4600000-0000-0000-0000-000000000021','a4510000-0000-0000-0000-000000000011','a4500000-0000-0000-0000-000000000001','e4000000-0000-0000-0000-000000000001',1,'a4320000-0000-0000-0000-000000000001','2026-11-26','Asia/Tehran','b4000000-0000-0000-0000-00000000000a');
  INSERT INTO plan_item_status_events(event_id,plan_item_id,student_id,seq_no,from_status,to_status,reason_note,actor_kind,actor_membership_id)
  VALUES (gen_random_uuid(),'a4600000-0000-0000-0000-000000000021','e4000000-0000-0000-0000-000000000001',1,'planned','cancelled','synthetic','membership','b4000000-0000-0000-0000-00000000000a')$q$,'23514','DRAFT plan version');
COMMIT;
RESET SESSION AUTHORIZATION;

SET SESSION AUTHORIZATION :"runtime_role";
BEGIN;
SELECT test_establish('counselor','b4000000-0000-0000-0000-00000000000b');
SELECT pln_err('PLN-78 decision C1: publishing an EMPTY normalized version is prohibited', $q$UPDATE student_plan_versions SET status='published', published_at=clock_timestamp() WHERE plan_version_id='a4510000-0000-0000-0000-000000000002'$q$,'23514','EMPTY normalized plan version');
COMMIT;
RESET SESSION AUTHORIZATION;

-- ======================================================================================================
-- (fixture for PLN-E1e: an empty plan of s1, created by the test owner)
-- DECISION E1 — legacy JSON plans stay read-only; a counselor may EXPLICITLY create a new normalized
-- version from one. Through the runtime, under the counselor's verified principal; row-level security
-- and the version guard decide.
-- ======================================================================================================
INSERT INTO student_plans(plan_id,student_id) VALUES ('a4500000-0000-0000-0000-000000000006','e4000000-0000-0000-0000-000000000001');
SET SESSION AUTHORIZATION :"runtime_role";
BEGIN;
SELECT test_establish('counselor','b4000000-0000-0000-0000-00000000000a');
SELECT pln_err('PLN-E1a the legacy version itself cannot be edited (read-only)', $q$UPDATE student_plan_versions SET plan_content='{"edited":true}' WHERE plan_version_id='a4510000-0000-0000-0000-000000000004'$q$,'23514');
SELECT pln_err('PLN-E1b ... nor written in counselor C''s name (impersonation)', $q$INSERT INTO student_plan_versions(plan_version_id,plan_id,version_no,input_snapshot,rule_version,plan_content,status,created_by_membership_id,supersedes_plan_version_id,change_reason)
  VALUES (gen_random_uuid(),'a4500000-0000-0000-0000-000000000004',2,'{}','manual-v1','{}','draft','b4000000-0000-0000-0000-00000000000c','a4510000-0000-0000-0000-000000000004','synthetic: converted from legacy')$q$,'42501','row-level security');
SELECT pln_ok('PLN-E1c counselor A explicitly creates a NEW normalized version superseding the legacy one, with a reason', $q$INSERT INTO student_plan_versions(plan_version_id,plan_id,version_no,input_snapshot,rule_version,plan_content,status,created_by_membership_id,supersedes_plan_version_id,change_reason)
  VALUES ('a4510000-0000-0000-0000-000000000014','a4500000-0000-0000-0000-000000000004',2,'{}','manual-v1','{}','draft','b4000000-0000-0000-0000-00000000000a','a4510000-0000-0000-0000-000000000004','synthetic: converted from legacy by the counselor')$q$);
COMMIT;
BEGIN;
SELECT test_establish('counselor','b4000000-0000-0000-0000-00000000000b');
SELECT pln_true('PLN-E1d0 counselor B cannot even SEE A''s student''s plan versions (row-level security)',
  NOT EXISTS (SELECT 1 FROM student_plan_versions WHERE plan_id='a4500000-0000-0000-0000-000000000004'));
SELECT pln_err('PLN-E1d counselor B cannot do it for A''s student: the predecessor is invisible to B, so the version is refused', $q$INSERT INTO student_plan_versions(plan_version_id,plan_id,version_no,input_snapshot,rule_version,plan_content,status,created_by_membership_id,supersedes_plan_version_id,change_reason)
  VALUES (gen_random_uuid(),'a4500000-0000-0000-0000-000000000004',3,'{}','manual-v1','{}','draft','b4000000-0000-0000-0000-00000000000b','a4510000-0000-0000-0000-000000000014','synthetic')$q$,'23514','EARLIER version of the SAME plan');
COMMIT;
SELECT pln_err('PLN-E1e with NO verified principal the runtime cannot create even a first version of A''s student''s plan', $q$INSERT INTO student_plan_versions(plan_version_id,plan_id,version_no,input_snapshot,rule_version,plan_content,status,created_by_membership_id)
  VALUES (gen_random_uuid(),'a4500000-0000-0000-0000-000000000006',1,'{}','manual-v1','{}','draft','b4000000-0000-0000-0000-00000000000a')$q$,'42501','row-level security');
RESET SESSION AUTHORIZATION;
SELECT pln_true('PLN-E1f the legacy version is unchanged and still renders its stored JSON',
  (SELECT rendered FROM plan_version_rendered WHERE plan_version_id='a4510000-0000-0000-0000-000000000004') = '{"legacy":true}'::jsonb
  AND (SELECT content_model FROM student_plan_versions WHERE plan_version_id='a4510000-0000-0000-0000-000000000014') = 'normalized');

INSERT INTO student_plans(plan_id,student_id) VALUES ('a4500000-0000-0000-0000-000000000005','e4000000-0000-0000-0000-000000000002');
SET SESSION AUTHORIZATION :"migrator_role";
SELECT pln_ok('PLN-79 F-02: the migration identity CAN record a historical legacy version', $q$INSERT INTO student_plan_versions(plan_version_id,plan_id,version_no,input_snapshot,rule_version,plan_content,status,content_model)
  VALUES ('a4510000-0000-0000-0000-000000000005','a4500000-0000-0000-0000-000000000005',1,'{}','legacy','{"migrated":true}','draft','legacy_json')$q$);
SELECT pln_err('PLN-79b F-02: ... but not after the plan already has a normalized version', $q$INSERT INTO student_plan_versions(plan_version_id,plan_id,version_no,input_snapshot,rule_version,plan_content,status,content_model)
  VALUES (gen_random_uuid(),'a4500000-0000-0000-0000-000000000001',3,'{}','legacy','{"x":1}','draft','legacy_json')$q$,'23514','cannot follow it');
RESET SESSION AUTHORIZATION;
SELECT pln_true('PLN-79c F-02: the migration-written legacy version is readable through the derived view, unchanged',
  (SELECT rendered FROM plan_version_rendered WHERE plan_version_id='a4510000-0000-0000-0000-000000000004')='{"legacy":true}'::jsonb
  AND (SELECT content_model FROM student_plan_versions WHERE plan_version_id='a4510000-0000-0000-0000-000000000004')='legacy_json');
DO $t$
DECLARE v_bad text;
BEGIN
  SELECT string_agg(DISTINCT grantee||':'||table_name||':'||privilege_type, ', ') INTO v_bad
    FROM information_schema.role_table_grants
   WHERE table_name IN ('plan_items','plan_item_status_events') AND privilege_type IN ('INSERT','UPDATE','DELETE')
     AND grantee ~ '_(runtime|worker|exporter|function_owner|table_owner_runtime)$';
  IF v_bad IS NOT NULL THEN RAISE EXCEPTION 'FAIL PLN-80 an application role can write plan items or transitions: %', v_bad; END IF;
  IF (SELECT count(*) FROM plan_privileged_identities) <> 2 THEN
    RAISE EXCEPTION 'FAIL PLN-80 plan_privileged_identities does not name exactly the two reviewed identities';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles r JOIN plan_privileged_identities i ON i.role_name=r.rolname WHERE r.rolcanlogin) THEN
    RAISE EXCEPTION 'FAIL PLN-80 a privileged plan identity can LOG IN';
  END IF;
  RAISE NOTICE 'PASS PLN-80 F-01/F-02: no application role can write plan items or transitions, and the two privileged identities are NOLOGIN';
END $t$;

-- ======================================================================================================
-- OUTPUT JSON IS DERIVED
-- ======================================================================================================
SELECT pln_true('PLN-50 the rendered JSON lists the seven items in order, each with its source kind',
  (SELECT string_agg(x->>'source', ',' ORDER BY (x->>'item_no')::int)
     FROM plan_version_rendered r, jsonb_array_elements(r.rendered->'items') x
    WHERE r.plan_version_id='a4510000-0000-0000-0000-000000000001') = 'topic,subtopic,activity,exam,review,assignment,topic');
SELECT pln_true('PLN-51 ... and carries the CURRENT status of each item, not a stored copy',
  (SELECT x->>'status' FROM plan_version_rendered r, jsonb_array_elements(r.rendered->'items') x
    WHERE r.plan_version_id='a4510000-0000-0000-0000-000000000001' AND x->>'item_no'='1') = 'in_progress');
SELECT pln_true('PLN-52 a legacy version renders its stored JSON unchanged',
  (SELECT rendered FROM plan_version_rendered WHERE plan_version_id='a4510000-0000-0000-0000-000000000004') = '{"legacy":true}'::jsonb);

-- ======================================================================================================
-- BOUNDARIES: counselor scope and the transfer fence
-- ======================================================================================================
SELECT pln_true('PLN-60 counselor B cannot reach counselor A''s plan item by its id (WS-ISO-01 boundary covers the new table)',
  counselor_may_access_row('b4000000-0000-0000-0000-00000000000b','plan_items','a4600000-0000-0000-0000-000000000001') = false
  AND counselor_may_access_row('b4000000-0000-0000-0000-00000000000a','plan_items','a4600000-0000-0000-0000-000000000001') = true);
SELECT pln_true('PLN-61 ... nor its status history',
  counselor_may_access_row('b4000000-0000-0000-0000-00000000000b','plan_item_status_events',
    (SELECT event_id::text FROM plan_item_status_events WHERE plan_item_id='a4600000-0000-0000-0000-000000000001' AND seq_no=1)) = false);

-- F-05: a superuser is not accepted as the synthetic writer (identity, not membership), so the fixture
-- item is written as the writer itself.
SET SESSION AUTHORIZATION :"writer_role";
BEGIN;
SELECT test_establish('counselor','b4000000-0000-0000-0000-00000000000a');
INSERT INTO plan_items(plan_item_id,plan_version_id,plan_id,student_id,item_no,topic_id,planned_local_date,timezone_name,created_by_membership_id)
VALUES ('a4600000-0000-0000-0000-000000000031','a4510000-0000-0000-0000-000000000003','a4500000-0000-0000-0000-000000000003','e4000000-0000-0000-0000-000000000003',1,'a4320000-0000-0000-0000-000000000001','2026-11-21','Asia/Tehran','b4000000-0000-0000-0000-00000000000a');
COMMIT;
RESET SESSION AUTHORIZATION;
UPDATE student_plan_versions SET status='published', published_at=clock_timestamp() WHERE plan_version_id='a4510000-0000-0000-0000-000000000003';
-- a DRAFT v2 for the same plan, created before the freeze, so PLN-62 meets the barrier rather than the
-- published-version rule
INSERT INTO student_plan_versions(plan_version_id,plan_id,version_no,input_snapshot,rule_version,plan_content,status,created_by_membership_id,supersedes_plan_version_id,change_reason)
VALUES ('a4510000-0000-0000-0000-000000000013','a4500000-0000-0000-0000-000000000003',2,'{}','manual-v1','{}','draft','b4000000-0000-0000-0000-00000000000a','a4510000-0000-0000-0000-000000000003','synthetic: before freeze');
SELECT public.freeze_student_for_transfer('a4700000-0000-0000-0000-000000000001','pln-freeze-1',
  'e4000000-0000-0000-0000-000000000003','a4700000-0000-0000-0000-0000000000ff',1,'pln-ctl-1',0,clock_timestamp()) AS freeze_state;
SET SESSION AUTHORIZATION :"writer_role";
BEGIN;
SELECT test_establish('counselor','b4000000-0000-0000-0000-00000000000a');
SELECT pln_err('PLN-62 a FROZEN student''s plan cannot gain an item', $q$INSERT INTO plan_items(plan_item_id,plan_version_id,plan_id,student_id,item_no,topic_id,planned_local_date,timezone_name,created_by_membership_id)
  VALUES (gen_random_uuid(),'a4510000-0000-0000-0000-000000000013','a4500000-0000-0000-0000-000000000003','e4000000-0000-0000-0000-000000000003',1,'a4320000-0000-0000-0000-000000000001','2026-11-22','Asia/Tehran','b4000000-0000-0000-0000-00000000000a')$q$,'23514','is frozen for transfer case');
SELECT pln_err('PLN-63 ... nor record a status transition', $q$INSERT INTO plan_item_status_events(event_id,plan_item_id,student_id,seq_no,from_status,to_status,reason_note,actor_kind,actor_membership_id)
  VALUES (gen_random_uuid(),'a4600000-0000-0000-0000-000000000031','e4000000-0000-0000-0000-000000000003',1,'planned','cancelled','synthetic','membership','b4000000-0000-0000-0000-00000000000a')$q$,'23514','is frozen for transfer case');
COMMIT;
RESET SESSION AUTHORIZATION;


SELECT 'PLAN ITEM TESTS COMPLETED (PLN-C1..C4, PLN-01..80, PLN-A2*, PLN-D1*, PLN-E1*): decisions A2/B1/C1/D1/E1 enforced under verified principals; no scheduling logic exists' AS result;
