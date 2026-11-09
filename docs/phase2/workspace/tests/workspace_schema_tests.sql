-- Workspace DB core schema regression tests. Synthetic only. Run after workspace_schema_draft.sql.
\set ON_ERROR_STOP on
CREATE OR REPLACE FUNCTION ws_expect_error(label text, stmt text, want text)
RETURNS void LANGUAGE plpgsql AS $test$
BEGIN
  EXECUTE stmt;
  RAISE EXCEPTION 'FAIL %: statement unexpectedly succeeded',label;
EXCEPTION WHEN OTHERS THEN
  IF SQLSTATE<>want THEN RAISE EXCEPTION 'FAIL %: got %, expected %',label,SQLSTATE,want; END IF;
  RAISE NOTICE 'PASS % (SQLSTATE %)',label,SQLSTATE;
END; $test$;

INSERT INTO workspace_profile(singleton,workspace_id,workspace_type)
VALUES(true,'a1000000-0000-0000-0000-000000000001','organization');
INSERT INTO workspace_memberships(membership_id,platform_user_id,role_key,status) VALUES
 ('b1000000-0000-0000-0000-000000000001','c1000000-0000-0000-0000-000000000001','counselor','active'),
 ('b1000000-0000-0000-0000-000000000002','c1000000-0000-0000-0000-000000000002','counselor','active'),
 ('b1000000-0000-0000-0000-000000000003','c1000000-0000-0000-0000-000000000003','manager','active');
INSERT INTO membership_roles(membership_id,role_key) VALUES
 ('b1000000-0000-0000-0000-000000000001','counselor'),
 ('b1000000-0000-0000-0000-000000000003','organization_manager');
INSERT INTO branches(branch_id,name,status) VALUES
 ('d1000000-0000-0000-0000-000000000001','Branch A','active');
INSERT INTO students(student_id,platform_student_id,display_name,grade_key,lifecycle_state)
VALUES ('e1000000-0000-0000-0000-000000000001','f1000000-0000-0000-0000-000000000001','Synthetic Student','grade_10','active');
INSERT INTO enrollments(enrollment_id,student_id,ownership_generation,state)
VALUES ('a2000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001',1,'requested');
INSERT INTO counselor_assignments(assignment_id,enrollment_id,counselor_membership_id,branch_id,is_responsible,is_primary_branch,state,accepted_at)
VALUES ('b2000000-0000-0000-0000-000000000001','a2000000-0000-0000-0000-000000000001','b1000000-0000-0000-0000-000000000001','d1000000-0000-0000-0000-000000000001',true,true,'active',now());

INSERT INTO subjects(subject_id,subject_key,title,grade_key,source_kind,status)
VALUES ('e3000000-0000-0000-0000-000000000001','bio-10','Biology','grade_10','workspace_custom','active');
INSERT INTO chapters(chapter_id,subject_id,title,order_no)
VALUES ('f3000000-0000-0000-0000-000000000001','e3000000-0000-0000-0000-000000000001','Cell','1');
INSERT INTO topics(topic_id,chapter_id,title,order_no)
VALUES ('a4000000-0000-0000-0000-000000000001','f3000000-0000-0000-0000-000000000001','Membrane','1');
INSERT INTO student_topic_mastery(student_id,topic_id,mastery_score,confidence,last_assessed_at)
VALUES ('e1000000-0000-0000-0000-000000000001','a4000000-0000-0000-0000-000000000001',72.5,'medium',now());
INSERT INTO activities(activity_id,student_id,topic_id,activity_kind,title,state,created_by_membership_id)
VALUES ('b4000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001','a4000000-0000-0000-0000-000000000001','study','Read topic','planned','b1000000-0000-0000-0000-000000000001');
INSERT INTO study_sessions(study_session_id,student_id,activity_id,started_at,ended_at,planned_minutes,actual_minutes,outcome)
VALUES ('c4000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001','b4000000-0000-0000-0000-000000000001',now()-interval '30 minutes',now(),30,28,'completed');
INSERT INTO test_definitions(test_id,title,subject_id,topic_id,test_kind,scoring_policy_snapshot)
VALUES ('d4000000-0000-0000-0000-000000000001','Topic quiz','e3000000-0000-0000-0000-000000000001','a4000000-0000-0000-0000-000000000001','educational','{"negative_marking":true,"version":"v1"}'::jsonb);
INSERT INTO test_attempts(attempt_id,test_id,student_id,state,started_at,submitted_at,correct_count,wrong_count,blank_count,score,scoring_policy_snapshot)
VALUES ('e4000000-0000-0000-0000-000000000001','d4000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001','analysed',now()-interval '15 minutes',now(),8,1,1,75,'{"negative_marking":true,"version":"v1"}'::jsonb);
INSERT INTO test_responses(response_id,attempt_id,question_no,topic_id,response_state,time_spent_seconds,error_reason)
VALUES ('f4000000-0000-0000-0000-000000000001','e4000000-0000-0000-0000-000000000001',1,'a4000000-0000-0000-0000-000000000001','wrong',50,'concept');
INSERT INTO exams(exam_id,student_id,title,exam_at,scoring_policy_snapshot)
VALUES ('a5000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001','Synthetic exam',now(),'{"negative_marking":true}'::jsonb);
INSERT INTO exam_results(exam_result_id,exam_id,student_id,correct_count,wrong_count,blank_count,score,scoring_policy_snapshot)
VALUES ('b5000000-0000-0000-0000-000000000001','a5000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001',10,2,3,80,'{"negative_marking":true}'::jsonb);
INSERT INTO classes(class_id,subject_id,class_kind,title)
VALUES ('c5000000-0000-0000-0000-000000000001','e3000000-0000-0000-0000-000000000001','online','Online biology');
INSERT INTO class_sessions(class_session_id,class_id,starts_at,ends_at,timezone_name)
VALUES ('d5000000-0000-0000-0000-000000000001','c5000000-0000-0000-0000-000000000001',now(),now()+interval '1 hour','Asia/Tehran');
INSERT INTO assignments(assignment_id,student_id,class_session_id,title,due_at,state,created_by_membership_id)
VALUES ('e5000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001','d5000000-0000-0000-0000-000000000001','Homework',now()+interval '1 day','assigned','b1000000-0000-0000-0000-000000000001');
INSERT INTO reviews(review_id,student_id,topic_id,scheduled_at,cadence_days,state)
VALUES ('f5000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001','a4000000-0000-0000-0000-000000000001',now()+interval '1 day',1,'scheduled');
INSERT INTO daily_routines(routine_id,student_id,title,schedule_spec,timezone_name)
VALUES ('a6000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001','Daily biology','{"minutes":20}'::jsonb,'Asia/Tehran');
INSERT INTO progress_snapshots(progress_snapshot_id,student_id,snapshot_date,metrics)
VALUES ('b6000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001',current_date,'{"completed":4}'::jsonb);
INSERT INTO risk_assessments(risk_assessment_id,student_id,risk_level,engine_version,input_snapshot,explanation)
VALUES ('c6000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001','medium','risk-v1','{"late_tasks":2}'::jsonb,'Synthetic explanation');
INSERT INTO counselor_notes(counselor_note_id,student_id,author_membership_id,visibility,content)
VALUES ('d6000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001','b1000000-0000-0000-0000-000000000001','private_to_author','Synthetic private note');
INSERT INTO audit_events(audit_event_id,actor_membership_id,event_type,target_type,target_id,outcome)
VALUES ('e6000000-0000-0000-0000-000000000001','b1000000-0000-0000-0000-000000000003','student.view','student','e1000000-0000-0000-0000-000000000001','success');
SELECT ws_expect_error('WS-AUDIT-01 audit events are append-only','UPDATE audit_events SET outcome=''denied'' WHERE audit_event_id=''e6000000-0000-0000-0000-000000000001''','23514');

INSERT INTO private_file_objects(file_id,student_id,object_key,storage_provider,content_type,byte_size,sha256,encryption_key_version,state,uploaded_by_membership_id)
VALUES ('f6000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001','workspace/synthetic/student/file-1','s3-compatible','application/pdf',128,decode(repeat('aa',32),'hex'),1,'available','b1000000-0000-0000-0000-000000000001');
SELECT ws_expect_error('WS-FILE-01 public URL cannot be used as object key','INSERT INTO private_file_objects(file_id,object_key,storage_provider,content_type,byte_size,sha256,encryption_key_version,state) VALUES (gen_random_uuid(),''https://public.example/file.pdf'',''s3-compatible'',''application/pdf'',128,decode(repeat(''aa'',32),''hex''),1,''available'')','23514');

INSERT INTO in_app_notifications(notification_id,recipient_platform_user_id,notification_type,template_version,payload,idempotency_key)
VALUES ('a7000000-0000-0000-0000-000000000001','c1000000-0000-0000-0000-000000000001','plan.published','v1','{"plan_id":"synthetic"}'::jsonb,'notification-1');
SELECT ws_expect_error('WS-NOTIFY-01 duplicate notification idempotency key rejected','INSERT INTO in_app_notifications(notification_id,recipient_platform_user_id,notification_type,template_version,payload,idempotency_key) VALUES (gen_random_uuid(),''c1000000-0000-0000-0000-000000000001'',''plan.published'',''v1'',''{}'',''notification-1'')','23505');
INSERT INTO legal_holds(legal_hold_id,entity_type,entity_id,hold_ref,reason,placed_by_membership_id)
VALUES ('b7000000-0000-0000-0000-000000000001','student','e1000000-0000-0000-0000-000000000001','hold-1','Synthetic legal hold','b1000000-0000-0000-0000-000000000003');

SELECT ws_expect_error('WS-ASSIGN-01 second responsible counselor rejected','INSERT INTO counselor_assignments(assignment_id,enrollment_id,counselor_membership_id,is_responsible,state,accepted_at) VALUES (gen_random_uuid(),''a2000000-0000-0000-0000-000000000001'',''b1000000-0000-0000-0000-000000000002'',true,''active'',now())','23505');

INSERT INTO student_guardian_links(link_id,student_id,guardian_platform_user_id,relationship_type,verification_state,legal_authority_ref,verified_at)
VALUES ('c2000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001','c1000000-0000-0000-0000-000000000003','parent','verified','synthetic-authority-ref',now());
INSERT INTO guardian_permissions(permission_id,guardian_link_id,scope_key,authority_ref,valid_from)
VALUES ('d2000000-0000-0000-0000-000000000001','c2000000-0000-0000-0000-000000000001','progress.read','synthetic-authority-ref',now());

INSERT INTO program_templates(template_id,name,status) VALUES ('e2000000-0000-0000-0000-000000000001','Synthetic Template','draft');
INSERT INTO program_versions(program_version_id,template_id,version_no,content,status)
VALUES ('f2000000-0000-0000-0000-000000000001','e2000000-0000-0000-0000-000000000001',1,'{"items":[]}'::jsonb,'draft');
UPDATE program_versions SET status='published',published_at=now()
WHERE program_version_id='f2000000-0000-0000-0000-000000000001';
SELECT ws_expect_error('WS-VERSION-01 published ProgramVersion is immutable','UPDATE program_versions SET content=''{"items":[1]}''::jsonb WHERE program_version_id=''f2000000-0000-0000-0000-000000000001''','23514');

INSERT INTO student_plans(plan_id,student_id)
VALUES ('a3000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001');
INSERT INTO student_plan_versions(plan_version_id,plan_id,version_no,source_program_version_id,input_snapshot,rule_version,plan_content,status)
VALUES ('b3000000-0000-0000-0000-000000000001','a3000000-0000-0000-0000-000000000001',1,'f2000000-0000-0000-0000-000000000001','{}','rules-v1','{}','draft');
UPDATE student_plan_versions SET status='published',published_at=now()
WHERE plan_version_id='b3000000-0000-0000-0000-000000000001';
SELECT ws_expect_error('WS-VERSION-02 published StudentPlanVersion is immutable','DELETE FROM student_plan_versions WHERE plan_version_id=''b3000000-0000-0000-0000-000000000001''','23514');

INSERT INTO credit_wallets(wallet_id,currency_code) VALUES ('c3000000-0000-0000-0000-000000000001','IRR');
INSERT INTO credit_transactions(transaction_id,wallet_id,transaction_kind,amount,idempotency_key,reason)
VALUES ('d3000000-0000-0000-0000-000000000001','c3000000-0000-0000-0000-000000000001','purchase',100,'ws-credit-1','synthetic purchase');
SELECT ws_expect_error('WS-CREDIT-01 credit ledger UPDATE forbidden','UPDATE credit_transactions SET amount=200 WHERE transaction_id=''d3000000-0000-0000-0000-000000000001''','23514');
SELECT ws_expect_error('WS-CREDIT-02 reversal must be exact opposite amount','INSERT INTO credit_transactions(transaction_id,wallet_id,transaction_kind,amount,idempotency_key,related_transaction_id,reason) VALUES (gen_random_uuid(),''c3000000-0000-0000-0000-000000000001'',''reversal'',-50,''ws-credit-bad-reversal'',''d3000000-0000-0000-0000-000000000001'',''synthetic bad reversal'')','23514');
INSERT INTO credit_transactions(transaction_id,wallet_id,transaction_kind,amount,idempotency_key,related_transaction_id,reason)
VALUES ('e3000000-0000-0000-0000-000000000001','c3000000-0000-0000-0000-000000000001','reversal',-100,'ws-credit-reversal','d3000000-0000-0000-0000-000000000001','synthetic exact reversal');
SELECT ws_expect_error('WS-CREDIT-03 duplicate reversal forbidden','INSERT INTO credit_transactions(transaction_id,wallet_id,transaction_kind,amount,idempotency_key,related_transaction_id,reason) VALUES (gen_random_uuid(),''c3000000-0000-0000-0000-000000000001'',''reversal'',-100,''ws-credit-duplicate-reversal'',''d3000000-0000-0000-0000-000000000001'',''synthetic duplicate reversal'')','23505');

INSERT INTO workspace_capacity_counters(dimension_key,current_value,max_value)
VALUES ('active_students',0,1);
SELECT adjust_workspace_capacity('active_students',1,'capacity-activate-1','e1000000-0000-0000-0000-000000000001','b1000000-0000-0000-0000-000000000003','synthetic activation');
SELECT adjust_workspace_capacity('active_students',1,'capacity-activate-1','e1000000-0000-0000-0000-000000000001','b1000000-0000-0000-0000-000000000003','synthetic activation');
SELECT ws_expect_error('WS-CAP-01 capacity ceiling enforced','SELECT adjust_workspace_capacity(''active_students'',1,''capacity-activate-2'',''e1000000-0000-0000-0000-000000000001'',''b1000000-0000-0000-0000-000000000003'',''second activation'')','23514');
SELECT adjust_workspace_capacity('active_students',-1,'capacity-archive-1','e1000000-0000-0000-0000-000000000001','b1000000-0000-0000-0000-000000000003','synthetic archive');
SELECT ws_expect_error('WS-CAP-02 capacity underflow rejected','SELECT adjust_workspace_capacity(''active_students'',-1,''capacity-archive-2'',''e1000000-0000-0000-0000-000000000001'',''b1000000-0000-0000-0000-000000000003'',''duplicate archive'')','23514');


-- Organization Workspace may have branches; changing the type while branches exist is forbidden.
SELECT ws_expect_error('WS-BRANCH-02 Workspace type cannot change while branches exist','UPDATE workspace_profile SET workspace_type=''independent_counselor'' WHERE singleton=true','23514');
-- After removing branches, changing the test profile to independent must block future branches.
UPDATE counselor_assignments SET branch_id=NULL,is_primary_branch=false WHERE assignment_id='b2000000-0000-0000-0000-000000000001';
DELETE FROM branches WHERE branch_id='d1000000-0000-0000-0000-000000000001';
UPDATE workspace_profile SET workspace_type='independent_counselor' WHERE singleton=true;
SELECT ws_expect_error('WS-BRANCH-01 Independent Counselor Workspace cannot add branches','INSERT INTO branches(branch_id,name,status) VALUES (gen_random_uuid(),''Forbidden Branch'',''active'')','23514');

DO $test$ BEGIN RAISE NOTICE '=== WORKSPACE CORE SCHEMA TESTS COMPLETED (synthetic) ==='; END $test$;
