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
VALUES ('a2000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001',1,'active');
INSERT INTO counselor_assignments(assignment_id,enrollment_id,counselor_membership_id,branch_id,is_responsible,is_primary_branch,state,accepted_at)
VALUES ('b2000000-0000-0000-0000-000000000001','a2000000-0000-0000-0000-000000000001','b1000000-0000-0000-0000-000000000001','d1000000-0000-0000-0000-000000000001',true,true,'active',now());
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

-- Organization Workspace may have branches; changing the type while branches exist is forbidden.
SELECT ws_expect_error('WS-BRANCH-02 Workspace type cannot change while branches exist','UPDATE workspace_profile SET workspace_type=''independent_counselor'' WHERE singleton=true','23514');
-- After removing branches, changing the test profile to independent must block future branches.
DELETE FROM branches WHERE branch_id='d1000000-0000-0000-0000-000000000001';
UPDATE workspace_profile SET workspace_type='independent_counselor' WHERE singleton=true;
SELECT ws_expect_error('WS-BRANCH-01 Independent Counselor Workspace cannot add branches','INSERT INTO branches(branch_id,name,status) VALUES (gen_random_uuid(),''Forbidden Branch'',''active'')','23514');

DO $test$ BEGIN RAISE NOTICE '=== WORKSPACE CORE SCHEMA TESTS COMPLETED (synthetic) ==='; END $test$;
