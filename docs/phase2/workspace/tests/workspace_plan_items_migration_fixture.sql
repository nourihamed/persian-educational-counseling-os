-- WS-PLAN-01 F-04 — SYNTHETIC HISTORICAL ROWS, loaded BEFORE workspace_plan_items_draft.sql.
-- Synthetic only (D-014). This file stands in for a Workspace that already has plan versions in the
-- pre-WS-PLAN-01 shape (plan_content as the only representation), so the migration can be shown to be safe
-- on data that exists before it runs — which an empty test database never shows.
\set ON_ERROR_STOP on
INSERT INTO workspace_profile(singleton,workspace_id,workspace_type) VALUES (true,'a2000000-0000-0000-0000-000000000001','organization');
INSERT INTO workspace_memberships(membership_id,platform_user_id,status) VALUES ('b2000000-0000-0000-0000-00000000000a','c2000000-0000-0000-0000-00000000000a','active');
INSERT INTO membership_roles(membership_id,role_key) VALUES ('b2000000-0000-0000-0000-00000000000a','counselor');
INSERT INTO students(student_id,platform_student_id,display_name,grade_key,lifecycle_state) VALUES
 ('e2000000-0000-0000-0000-000000000001','f2000000-0000-0000-0000-000000000001','Hist S1','grade_10','active');
-- an active, accepted, responsible assignment, so the counselor can act on this student under WS-ISO-01 B
INSERT INTO enrollments(enrollment_id,student_id,ownership_generation,state) VALUES
 ('a2100000-0000-0000-0000-000000000001','e2000000-0000-0000-0000-000000000001',1,'requested');
INSERT INTO counselor_assignments(assignment_id,enrollment_id,counselor_membership_id,is_responsible,state,accepted_at) VALUES
 ('a2200000-0000-0000-0000-000000000001','a2100000-0000-0000-0000-000000000001','b2000000-0000-0000-0000-00000000000a',true,'active',clock_timestamp());
INSERT INTO student_plans(plan_id,student_id) VALUES
 ('a2500000-0000-0000-0000-000000000001','e2000000-0000-0000-0000-000000000001'),
 ('a2500000-0000-0000-0000-000000000002','e2000000-0000-0000-0000-000000000001');
-- h1 v1: PUBLISHED, real JSON content; h1 v2: DRAFT whose JSON happens to be '{}' (the subtle case: with a
-- 'normalized' default it would silently pass the empty-JSON CHECK and become an item-less normalized plan);
-- h2 v1: DRAFT with JSON content.
INSERT INTO student_plan_versions(plan_version_id,plan_id,version_no,input_snapshot,rule_version,plan_content,status,published_at) VALUES
 ('a2510000-0000-0000-0000-000000000001','a2500000-0000-0000-0000-000000000001',1,'{"src":"hist"}','legacy-rules-1','{"items":[{"topic":"velocity","minutes":45}]}','published',clock_timestamp()),
 ('a2510000-0000-0000-0000-000000000002','a2500000-0000-0000-0000-000000000001',2,'{}','legacy-rules-1','{}','draft',NULL),
 ('a2510000-0000-0000-0000-000000000003','a2500000-0000-0000-0000-000000000002',1,'{}','legacy-rules-1','{"items":[]}','draft',NULL);
-- A snapshot of exactly what was stored, to compare against after the migration.
CREATE TABLE pln_hist_snapshot AS SELECT plan_version_id, plan_content, status, published_at FROM student_plan_versions;
SELECT 'historical plan versions loaded: ' || count(*) AS fixture FROM student_plan_versions;
