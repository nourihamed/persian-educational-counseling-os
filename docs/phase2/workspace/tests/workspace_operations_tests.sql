-- Batch 8 — files, notifications, retention and legal hold. SYNTHETIC ONLY (D-014).
-- Run on a FRESH database after workspace_schema_draft.sql, workspace_activation_transactions.sql,
-- workspace_governance_events_draft.sql, workspace_archive_transactions.sql, workspace_inbox_projection.sql,
-- workspace_transfer_freeze.sql, workspace_operations_draft.sql and workspace_roles_setup_draft.sql
-- (-v workspace_key).
--
-- WHAT THESE TESTS PROVE
--   * A stored file object's facts cannot be rewritten and its state machine is forward-only.
--   * A notification cannot be addressed to someone who is not an active member of this Workspace (and, for
--     a notification about a student, a counselor able to reach that student — OPS-13c, 2026-11-18), the
--     student it is about, or a verified guardian OF THAT STUDENT; it cannot carry a plaintext contact
--     number; it cannot be re-pointed or rewritten after the fact; and it is covered by the transfer
--     write barrier, which could not even be expressed before this batch.
--   * A legal hold must resolve to an existing row of a registered type, its placement is immutable, its
--     release is one-way, and it cannot be deleted or truncated.
--   * Retention policy versions are immutable, nothing is approved, and the destructive-disposition gate
--     refuses for five distinct, individually named reasons — AND allows when an approved policy exists,
--     which is what shows the gate discriminates instead of simply always failing.
--   * Append-only tables refuse TRUNCATE, which their row triggers never saw.
--
-- WHAT THEY DO NOT PROVE
--   * Nothing about a retention PERIOD. Q-020 is open; the only approved policy that appears here is a
--     synthetic fixture inserted by OPS-34, labelled as such, and it is not a decision.
--   * Nothing about an actual deletion. There is no disposition executor, no object-store client and no
--     backup tooling in this repository, so completeness of erasure across objects, exports, caches and
--     backups is NOT claimed (retention contract §7).
--   * Nothing about delivery-time authorization. OPS-10..OPS-14 check the recipient AT INSERT; the
--     contracts also require a re-check at delivery, which needs a worker that does not exist.
--   * Nothing about the table owner or a superuser: SEC-08 already records that a trigger-based guard
--     cannot contain either identity.
\set ON_ERROR_STOP on
SET app.workspace_key = :'workspace_key';

CREATE OR REPLACE FUNCTION ops_err(label text, stmt text, want text, want_msg text DEFAULT '')
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
CREATE OR REPLACE FUNCTION ops_ok(label text, stmt text) RETURNS void LANGUAGE plpgsql AS $t$
BEGIN EXECUTE stmt; RAISE NOTICE 'PASS % (accepted)',label; END; $t$;

-- ======================================================================================================
-- Fixtures. Two students, so every student-bound rule can be tested against the WRONG student too.
-- ======================================================================================================
INSERT INTO workspace_profile(singleton,workspace_id,workspace_type)
VALUES(true,'a6000000-0000-0000-0000-000000000001','organization');
INSERT INTO workspace_memberships(membership_id,platform_user_id,status) VALUES
 ('b6000000-0000-0000-0000-000000000001','c6000000-0000-0000-0000-000000000001','active'),
 ('b6000000-0000-0000-0000-000000000002','c6000000-0000-0000-0000-000000000002','suspended');
INSERT INTO workspace_memberships(membership_id,platform_user_id,status) VALUES
 ('b6000000-0000-0000-0000-000000000003','c6000000-0000-0000-0000-000000000003','active');
INSERT INTO membership_roles(membership_id,role_key) VALUES ('b6000000-0000-0000-0000-000000000001','counselor'),
                                                           ('b6000000-0000-0000-0000-000000000003','counselor');
INSERT INTO students(student_id,platform_student_id,display_name,grade_key,lifecycle_state) VALUES
 ('e6000000-0000-0000-0000-000000000001','f6000000-0000-0000-0000-000000000001','Ops Student A','grade_10','active'),
 ('e6000000-0000-0000-0000-000000000002','f6000000-0000-0000-0000-000000000002','Ops Student B','grade_11','active'),
 ('e6000000-0000-0000-0000-000000000003','f6000000-0000-0000-0000-000000000003','Freeze Target','grade_12','active');
INSERT INTO enrollments(enrollment_id,student_id,ownership_generation,state) VALUES
 ('a6100000-0000-0000-0000-000000000001','e6000000-0000-0000-0000-000000000001',1,'requested'),
 ('a6100000-0000-0000-0000-000000000002','e6000000-0000-0000-0000-000000000002',1,'requested'),
 ('a6100000-0000-0000-0000-000000000003','e6000000-0000-0000-0000-000000000003',1,'requested');
-- Counselor scope (added 2026-11-18 with the WS-ISO-01 boundary). b6..01 is the accepted counselor of
-- students A and 3; b6..03 is the accepted counselor of student B only, and has a PROPOSED (unaccepted)
-- assignment to A, which must grant nothing.
INSERT INTO counselor_assignments(assignment_id,enrollment_id,counselor_membership_id,is_responsible,state,accepted_at) VALUES
 ('a6110000-0000-0000-0000-000000000001','a6100000-0000-0000-0000-000000000001','b6000000-0000-0000-0000-000000000001',true,'active',clock_timestamp()),
 ('a6110000-0000-0000-0000-000000000003','a6100000-0000-0000-0000-000000000003','b6000000-0000-0000-0000-000000000001',true,'active',clock_timestamp()),
 ('a6110000-0000-0000-0000-000000000002','a6100000-0000-0000-0000-000000000002','b6000000-0000-0000-0000-000000000003',true,'active',clock_timestamp()),
 ('a6110000-0000-0000-0000-000000000004','a6100000-0000-0000-0000-000000000001','b6000000-0000-0000-0000-000000000003',false,'active',NULL);
-- A verified guardian of student A only. Guardian projections need their event in the SAME transaction
-- (WS-DOM-03, a deferred constraint trigger), so the link and its two events go together.
BEGIN;
INSERT INTO student_guardian_links(link_id,student_id,guardian_platform_user_id,relationship_type,
                                   verification_state,legal_authority_ref,verified_at)
VALUES ('a6200000-0000-0000-0000-000000000001','e6000000-0000-0000-0000-000000000001',
        'c6000000-0000-0000-0000-00000000000a','parent','verified','synthetic-authority-ops',clock_timestamp());
INSERT INTO guardian_link_events(event_id,link_id,event_type,actor_ref,authn_event_ref,evidence_ref,
                                 policy_version,effective_at)
VALUES (gen_random_uuid(),'a6200000-0000-0000-0000-000000000001','link_created','synthetic-actor',
        'synthetic-authn',NULL,'p1',clock_timestamp()),
       (gen_random_uuid(),'a6200000-0000-0000-0000-000000000001','verified','synthetic-actor',
        'synthetic-authn','synthetic-evidence','p1',clock_timestamp());
COMMIT;
INSERT INTO private_file_objects(file_id,student_id,object_key,storage_provider,content_type,byte_size,
                                 sha256,encryption_key_version,state,uploaded_by_membership_id) VALUES
 ('d6000000-0000-0000-0000-000000000001','e6000000-0000-0000-0000-000000000001','workspace/ops/a1','synthetic',
  'application/pdf',1024,decode(repeat('a1',32),'hex'),1,'available','b6000000-0000-0000-0000-000000000001'),
 ('d6000000-0000-0000-0000-000000000002','e6000000-0000-0000-0000-000000000001','workspace/ops/a2','synthetic',
  'image/png',2048,decode(repeat('a2',32),'hex'),1,'quarantined','b6000000-0000-0000-0000-000000000001');

-- ======================================================================================================
-- FILES
-- ======================================================================================================
SELECT ops_err('OPS-01 content hash is immutable',
  $$UPDATE private_file_objects SET sha256=decode(repeat('00',32),'hex')
     WHERE file_id='d6000000-0000-0000-0000-000000000001'$$,
  '23514','content hash');
SELECT ops_err('OPS-02 object key is immutable',
  $$UPDATE private_file_objects SET object_key='workspace/ops/moved'
     WHERE file_id='d6000000-0000-0000-0000-000000000001'$$,
  '23514','immutable');
SELECT ops_ok('OPS-03 a cleared quarantine may become available',
  $$UPDATE private_file_objects SET state='available' WHERE file_id='d6000000-0000-0000-0000-000000000002'$$);
SELECT ops_err('OPS-04 an available object cannot be returned to quarantine',
  $$UPDATE private_file_objects SET state='quarantined' WHERE file_id='d6000000-0000-0000-0000-000000000002'$$,
  '23514','returned to quarantine');
SELECT ops_ok('OPS-05 an object may be archived',
  $$UPDATE private_file_objects SET state='archived', archived_at=clock_timestamp()
     WHERE file_id='d6000000-0000-0000-0000-000000000002'$$);
SELECT ops_err('OPS-06 archived is terminal',
  $$UPDATE private_file_objects SET state='available', archived_at=NULL
     WHERE file_id='d6000000-0000-0000-0000-000000000002'$$,
  '23514','cannot be reopened');
SELECT ops_err('OPS-07 a file row cannot be deleted',
  $$DELETE FROM private_file_objects WHERE file_id='d6000000-0000-0000-0000-000000000002'$$,
  '23514','authorized disposition');
SELECT ops_err('OPS-08 an object is not created archived',
  $$INSERT INTO private_file_objects(file_id,student_id,object_key,storage_provider,content_type,byte_size,
      sha256,encryption_key_version,state,archived_at,uploaded_by_membership_id)
    VALUES (gen_random_uuid(),'e6000000-0000-0000-0000-000000000001','workspace/ops/a3','synthetic','text/plain',
      10,decode(repeat('a3',32),'hex'),1,'archived',clock_timestamp(),'b6000000-0000-0000-0000-000000000001')$$,
  '23514','not created in the archived state');

-- ======================================================================================================
-- NOTIFICATIONS — recipient isolation is the point. The guardian case is the one that matters most:
-- a guardian verified for student A must not be a recipient for student B (guardian authority matrix).
-- ======================================================================================================
SELECT ops_ok('OPS-10 an active member is a valid recipient',
  $$INSERT INTO in_app_notifications(notification_id,recipient_platform_user_id,student_id,notification_type,
      template_version,payload,idempotency_key)
    VALUES ('c6300000-0000-0000-0000-000000000001','c6000000-0000-0000-0000-000000000001',
            'e6000000-0000-0000-0000-000000000001','exam_reminder','v1','{"exam_id":"synthetic"}','ops-idem-1')$$);
SELECT ops_ok('OPS-11 the student the notification is about is a valid recipient',
  $$INSERT INTO in_app_notifications(notification_id,recipient_platform_user_id,student_id,notification_type,
      template_version,payload,idempotency_key)
    VALUES ('c6300000-0000-0000-0000-000000000002','f6000000-0000-0000-0000-000000000001',
            'e6000000-0000-0000-0000-000000000001','plan_published','v1','{}','ops-idem-2')$$);
SELECT ops_ok('OPS-12 a verified guardian of THAT student is a valid recipient',
  $$INSERT INTO in_app_notifications(notification_id,recipient_platform_user_id,student_id,notification_type,
      template_version,payload,idempotency_key)
    VALUES ('c6300000-0000-0000-0000-000000000003','c6000000-0000-0000-0000-00000000000a',
            'e6000000-0000-0000-0000-000000000001','weekly_summary','v1','{}','ops-idem-3')$$);
SELECT ops_err('OPS-13 the SAME guardian is NOT a recipient for another student (child A / child B)',
  $$INSERT INTO in_app_notifications(notification_id,recipient_platform_user_id,student_id,notification_type,
      template_version,payload,idempotency_key)
    VALUES (gen_random_uuid(),'c6000000-0000-0000-0000-00000000000a',
            'e6000000-0000-0000-0000-000000000002','weekly_summary','v1','{}','ops-idem-4')$$,
  '23514','not a verified guardian of that student');
SELECT ops_err('OPS-14 a SUSPENDED membership is not a recipient',
  $$INSERT INTO in_app_notifications(notification_id,recipient_platform_user_id,student_id,notification_type,
      template_version,payload,idempotency_key)
    VALUES (gen_random_uuid(),'c6000000-0000-0000-0000-000000000002',
            'e6000000-0000-0000-0000-000000000001','weekly_summary','v1','{}','ops-idem-5')$$,
  '23514','not an active member');
SELECT ops_err('OPS-13c an active COUNSELOR of this Workspace is not a recipient for a student assigned to another counselor',
  $$INSERT INTO in_app_notifications(notification_id,recipient_platform_user_id,student_id,notification_type,
      template_version,payload,idempotency_key)
    VALUES (gen_random_uuid(),'c6000000-0000-0000-0000-000000000003',
            'e6000000-0000-0000-0000-000000000001','weekly_summary','v1','{}','ops-idem-13c')$$,
  '23514','able to reach that student');
SELECT ops_ok('OPS-13d that counselor IS a recipient for their own student',
  $$INSERT INTO in_app_notifications(notification_id,recipient_platform_user_id,student_id,notification_type,
      template_version,payload,idempotency_key)
    VALUES (gen_random_uuid(),'c6000000-0000-0000-0000-000000000003',
            'e6000000-0000-0000-0000-000000000002','weekly_summary','v1','{}','ops-idem-13d')$$);
SELECT ops_err('OPS-15 a stranger is not a recipient',
  $$INSERT INTO in_app_notifications(notification_id,recipient_platform_user_id,student_id,notification_type,
      template_version,payload,idempotency_key)
    VALUES (gen_random_uuid(),'c6000000-0000-0000-0000-0000000000ff',
            'e6000000-0000-0000-0000-000000000001','weekly_summary','v1','{}','ops-idem-6')$$,
  '23514','not an active member');
SELECT ops_err('OPS-16 a Workspace-level notice still needs a member recipient',
  $$INSERT INTO in_app_notifications(notification_id,recipient_platform_user_id,student_id,notification_type,
      template_version,payload,idempotency_key)
    VALUES (gen_random_uuid(),'c6000000-0000-0000-0000-0000000000ff',NULL,'system_notice','v1','{}','ops-idem-7')$$,
  '23514','not an active member');
SELECT ops_err('OPS-17 a plaintext Iranian mobile NESTED in the payload is refused',
  $$INSERT INTO in_app_notifications(notification_id,recipient_platform_user_id,student_id,notification_type,
      template_version,payload,idempotency_key)
    VALUES (gen_random_uuid(),'c6000000-0000-0000-0000-000000000001','e6000000-0000-0000-0000-000000000001',
            'contact_changed','v1','{"meta":{"lines":["new number 09000000000"]}}','ops-idem-8')$$,  -- NOT-A-REAL-CONTACT: all-zero subscriber body, synthetic fixture; this test asserts the payload is REFUSED
  '23514','plaintext contact number');
SELECT ops_err('OPS-18 an E.164 number in the payload is refused',
  $$INSERT INTO in_app_notifications(notification_id,recipient_platform_user_id,student_id,notification_type,
      template_version,payload,idempotency_key)
    VALUES (gen_random_uuid(),'c6000000-0000-0000-0000-000000000001','e6000000-0000-0000-0000-000000000001',
            'contact_changed','v1','{"display":"+10000000000"}','ops-idem-9')$$,  -- NOT-A-REAL-CONTACT: all-zero E.164 body, synthetic fixture; this test asserts the payload is REFUSED
  '23514','plaintext contact number');
SELECT ops_ok('OPS-19 a masked display is accepted',
  $$INSERT INTO in_app_notifications(notification_id,recipient_platform_user_id,student_id,notification_type,
      template_version,payload,idempotency_key)
    VALUES ('c6300000-0000-0000-0000-000000000004','c6000000-0000-0000-0000-000000000001',
            'e6000000-0000-0000-0000-000000000001','contact_changed','v1','{"masked":"0912***4567"}','ops-idem-10')$$);
SELECT ops_err('OPS-20 the recipient of a written notification is immutable',
  $$UPDATE in_app_notifications SET recipient_platform_user_id='c6000000-0000-0000-0000-00000000000a'
     WHERE notification_id='c6300000-0000-0000-0000-000000000001'$$,
  '23514','recipient, subject, template and payload are immutable');
SELECT ops_ok('OPS-21 read_at may be set once',
  $$UPDATE in_app_notifications SET read_at=clock_timestamp()
     WHERE notification_id='c6300000-0000-0000-0000-000000000001'$$);
SELECT ops_err('OPS-22 read_at cannot be rewritten',
  $$UPDATE in_app_notifications SET read_at=clock_timestamp()
     WHERE notification_id='c6300000-0000-0000-0000-000000000001'$$,
  '23514','set once');
SELECT ops_err('OPS-23 a notification cannot be deleted',
  $$DELETE FROM in_app_notifications WHERE notification_id='c6300000-0000-0000-0000-000000000001'$$,
  '23514','retention gate');

-- OPS-24  The reason student_id was added at all: the transfer write barrier can now cover notifications.
--         Asserted from the coverage view AND behaviourally below (OPS-45).
DO $t$
DECLARE v_has boolean;
BEGIN
  SELECT has_barrier INTO v_has FROM student_write_barrier_coverage WHERE table_name='in_app_notifications';
  IF v_has IS NULL THEN
    RAISE EXCEPTION 'FAIL OPS-24 in_app_notifications is not in the write barrier coverage view at all, so '
                    'the transfer fence does not apply to notifications';
  END IF;
  IF NOT v_has THEN
    RAISE EXCEPTION 'FAIL OPS-24 in_app_notifications has no write barrier trigger';
  END IF;
  RAISE NOTICE 'PASS OPS-24 notifications are inside the transfer write barrier';
END $t$;

-- ======================================================================================================
-- LEGAL HOLDS AND THE ENTITY REGISTRY
-- ======================================================================================================
SELECT ops_err('OPS-30 a hold on an unregistered entity type is refused',
  $$INSERT INTO legal_holds(legal_hold_id,entity_type,entity_id,hold_ref,reason,placed_by_membership_id)
    VALUES (gen_random_uuid(),'counselor_note','d6000000-0000-0000-0000-000000000001','case-x','synthetic',
            'b6000000-0000-0000-0000-000000000001')$$,
  '23514','not registered for retention');
SELECT ops_err('OPS-31 a hold on a target that does not exist is refused (it would protect nothing)',
  $$INSERT INTO legal_holds(legal_hold_id,entity_type,entity_id,hold_ref,reason,placed_by_membership_id)
    VALUES (gen_random_uuid(),'private_file_object','d6000000-0000-0000-0000-0000000000ff','case-x','synthetic',
            'b6000000-0000-0000-0000-000000000001')$$,
  '23514','does not exist');
SELECT ops_err('OPS-32 a hold needs an authority reference and a reason',
  $$INSERT INTO legal_holds(legal_hold_id,entity_type,entity_id,hold_ref,reason,placed_by_membership_id)
    VALUES (gen_random_uuid(),'private_file_object','d6000000-0000-0000-0000-000000000001','   ','synthetic',
            'b6000000-0000-0000-0000-000000000001')$$,
  '23514','authority reference and a reason');
SELECT ops_ok('OPS-33 a resolvable hold is accepted',
  $$INSERT INTO legal_holds(legal_hold_id,entity_type,entity_id,hold_ref,reason,placed_by_membership_id)
    VALUES ('c6400000-0000-0000-0000-000000000001','private_file_object','d6000000-0000-0000-0000-000000000001',
            'synthetic-case-1','synthetic hold for OPS','b6000000-0000-0000-0000-000000000001')$$);
SELECT ops_err('OPS-34 hold scope and placement are immutable',
  $$UPDATE legal_holds SET entity_id='d6000000-0000-0000-0000-000000000002'
     WHERE legal_hold_id='c6400000-0000-0000-0000-000000000001'$$,
  '23514','immutable');
SELECT ops_err('OPS-35 the only permitted change to a live hold is its release',
  $$UPDATE legal_holds SET hold_ref='synthetic-case-2'
     WHERE legal_hold_id='c6400000-0000-0000-0000-000000000001'$$,
  '23514','immutable');
SELECT ops_err('OPS-36 a hold cannot be deleted',
  $$DELETE FROM legal_holds WHERE legal_hold_id='c6400000-0000-0000-0000-000000000001'$$,
  '23514','cannot be deleted');
SELECT ops_err('OPS-37 an entity type naming a table that does not exist is refused',
  $$INSERT INTO retention_entity_types(entity_type,table_name,pk_column,category_key)
    VALUES ('ghost','no_such_table','ghost_id','R1')$$,
  '23514','does not exist');
SELECT ops_err('OPS-38 an entity key that is not uuid is refused',
  $$INSERT INTO retention_entity_types(entity_type,table_name,pk_column,category_key)
    VALUES ('bad_key','students','display_name','R1')$$,
  '23514','must be uuid');
SELECT ops_err('OPS-39 a registered entity type cannot be removed',
  $$DELETE FROM retention_entity_types WHERE entity_type='private_file_object'$$,
  '23514','cannot be removed');

-- ======================================================================================================
-- RETENTION POLICY AND THE DISPOSITION GATE
-- ======================================================================================================
-- OPS-40  The seeded state: nine categories, every one needs_decision, NOTHING approved. If this ever
--         fails because a policy was approved in the schema draft, that is a Product Owner decision being
--         made in code, which is exactly what must not happen (Q-020).
DO $t$
DECLARE v_cat integer; v_needs integer; v_appr integer;
BEGIN
  SELECT count(*) INTO v_cat FROM retention_categories;
  SELECT count(*) INTO v_needs FROM retention_policy_versions WHERE status='needs_decision';
  SELECT count(*) INTO v_appr  FROM retention_policy_versions WHERE status='approved';
  IF v_cat <> 9 THEN RAISE EXCEPTION 'FAIL OPS-40 expected the nine phase 1 categories, found %',v_cat; END IF;
  IF v_needs <> 9 THEN RAISE EXCEPTION 'FAIL OPS-40 expected nine needs_decision policies, found %',v_needs; END IF;
  IF v_appr <> 0 THEN
    RAISE EXCEPTION 'FAIL OPS-40 % retention policy version(s) are APPROVED in the draft. No period is '
                    'approved (Q-020); approving one here would be a Product Owner decision made in code',v_appr;
  END IF;
  RAISE NOTICE 'PASS OPS-40 nine categories, nine needs_decision policies, no approved period';
END $t$;

SELECT ops_err('OPS-41 a policy version cannot be flipped to approved by UPDATE',
  $$UPDATE retention_policy_versions SET status='approved'
     WHERE category_key='R1' AND policy_version='v0-needs-decision'$$,
  '23514','immutable');
SELECT ops_err('OPS-42 a policy version cannot be deleted',
  $$DELETE FROM retention_policy_versions WHERE category_key='R1'$$,
  '23514','immutable history');
SELECT ops_err('OPS-43 approved without a duration, action, approval reference and date is refused',
  $$INSERT INTO retention_policy_versions(policy_id,category_key,policy_version,status)
    VALUES (gen_random_uuid(),'R6','bad-approved','approved')$$,
  '23514','retention_policy_versions_check');
SELECT ops_err('OPS-44 a needs_decision policy may not carry a duration',
  $$INSERT INTO retention_policy_versions(policy_id,category_key,policy_version,status,duration_days)
    VALUES (gen_random_uuid(),'R6','bad-needs','needs_decision',30)$$,
  '23514','retention_policy_versions_check');

-- OPS-45  THE BEHAVIOURAL FENCE TEST for notifications. A frozen student's notification row must be
--         refused. This is the property that did not exist before Batch 8, because the table had no
--         reference to a student to fence on. Student 3 is frozen here and stays frozen, so this test
--         runs after every other fixture write.
SELECT public.freeze_student_for_transfer('c6500000-0000-0000-0000-000000000001','ops-freeze-token-1',
  'e6000000-0000-0000-0000-000000000003','c6500000-0000-0000-0000-0000000000ff',1,'ops-controller-1',0,
  clock_timestamp()) AS freeze_state;
SELECT ops_err('OPS-45 a notification about a FROZEN student is refused by the write barrier',
  $$INSERT INTO in_app_notifications(notification_id,recipient_platform_user_id,student_id,notification_type,
      template_version,payload,idempotency_key)
    VALUES (gen_random_uuid(),'c6000000-0000-0000-0000-000000000001','e6000000-0000-0000-0000-000000000003',
            'exam_reminder','v1','{}','ops-idem-frozen')$$,
  '23514','is frozen for transfer case');
SELECT ops_ok('OPS-46 a notification about an unfrozen student is still accepted',
  $$INSERT INTO in_app_notifications(notification_id,recipient_platform_user_id,student_id,notification_type,
      template_version,payload,idempotency_key)
    VALUES ('c6300000-0000-0000-0000-000000000005','c6000000-0000-0000-0000-000000000001',
            'e6000000-0000-0000-0000-000000000001','exam_reminder','v1','{}','ops-idem-11')$$);

-- OPS-47  THE GATE. Five named refusals, then the positive path, then a hold, then release. The positive
--         path is what shows the gate discriminates: a gate that always raises would pass every refusal
--         test in this file and be worthless.
DO $t$
DECLARE v_msg text; v_state text;
BEGIN
  -- 1. a non-destructive action is not this gate's business
  BEGIN
    PERFORM public.assert_destructive_disposition_allowed('private_file_object',
              'd6000000-0000-0000-0000-000000000001','archive');
    RAISE EXCEPTION 'FAIL OPS-47.1 the gate accepted a non-destructive action';
  EXCEPTION WHEN check_violation THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF position('not a destructive action' IN v_msg)=0 THEN
      RAISE EXCEPTION 'FAIL OPS-47.1 wrong reason: %',v_msg; END IF;
  END;
  -- 2. an unregistered entity type
  BEGIN
    PERFORM public.assert_destructive_disposition_allowed('counselor_note',
              'd6000000-0000-0000-0000-000000000001','delete_record');
    RAISE EXCEPTION 'FAIL OPS-47.2 the gate accepted an unregistered entity type';
  EXCEPTION WHEN check_violation THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF position('not registered for retention' IN v_msg)=0 THEN
      RAISE EXCEPTION 'FAIL OPS-47.2 wrong reason: %',v_msg; END IF;
  END;
  -- 3. a target that does not exist: refuse rather than report a deletion that did not happen
  BEGIN
    PERFORM public.assert_destructive_disposition_allowed('private_file_object',
              'd6000000-0000-0000-0000-0000000000ff','delete_object');
    RAISE EXCEPTION 'FAIL OPS-47.3 the gate accepted a target that does not exist';
  EXCEPTION WHEN check_violation THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF position('does not exist' IN v_msg)=0 THEN
      RAISE EXCEPTION 'FAIL OPS-47.3 wrong reason: %',v_msg; END IF;
  END;
  -- 4. a live legal hold (OPS-33 placed one on this file and it has not been released)
  BEGIN
    PERFORM public.assert_destructive_disposition_allowed('private_file_object',
              'd6000000-0000-0000-0000-000000000001','delete_object');
    RAISE EXCEPTION 'FAIL OPS-47.4 the gate accepted a disposition while a legal hold was live';
  EXCEPTION WHEN check_violation THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF position('legal hold is active' IN v_msg)=0 THEN
      RAISE EXCEPTION 'FAIL OPS-47.4 wrong reason: %',v_msg; END IF;
  END;
  RAISE NOTICE 'PASS OPS-47a the gate refuses a non-destructive action, an unregistered type, a missing '
               'target and a live legal hold, each with its own reason';

  -- 5. release the hold; the remaining refusal must be the missing DECISION, not the hold
  UPDATE legal_holds SET released_at=clock_timestamp(),
         released_by_membership_id='b6000000-0000-0000-0000-000000000001'
   WHERE legal_hold_id='c6400000-0000-0000-0000-000000000001';
  BEGIN
    PERFORM public.assert_destructive_disposition_allowed('private_file_object',
              'd6000000-0000-0000-0000-000000000001','delete_object');
    RAISE EXCEPTION 'FAIL OPS-47.5 the gate accepted a disposition with NO approved retention policy';
  EXCEPTION WHEN check_violation THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF position('no approved retention policy' IN v_msg)=0 THEN
      RAISE EXCEPTION 'FAIL OPS-47.5 wrong reason: %',v_msg; END IF;
  END;
  RAISE NOTICE 'PASS OPS-47b with every hold released the gate still refuses, because the period is an '
               'open Product Owner decision (Q-020) — an unresolved duration blocks destructive '
               'disposition rather than defaulting either way';
END $t$;

-- OPS-48  The positive path, with a SYNTHETIC approved policy. THIS ROW IS A TEST FIXTURE AND NOT A
--         DECISION: its approval_ref says so, it exists only in this test database, and OPS-40 asserts
--         that the schema draft itself approves nothing. Without this test the whole gate could be a
--         function that raises unconditionally and every other assertion here would still pass.
DO $t$
DECLARE v_msg text;
BEGIN
  INSERT INTO retention_policy_versions(policy_id,category_key,policy_version,status,duration_days,
                                        disposition_action,approval_ref,jurisdiction,effective_from)
  VALUES (gen_random_uuid(),'R6','SYNTHETIC-ops-48','approved',30,'delete_object',
          'SYNTHETIC-TEST-FIXTURE-NOT-A-PRODUCT-OWNER-DECISION','synthetic',clock_timestamp()-interval '1 day');

  PERFORM public.assert_destructive_disposition_allowed('private_file_object',
            'd6000000-0000-0000-0000-000000000001','delete_object');
  RAISE NOTICE 'PASS OPS-48a with a synthetic approved policy and no live hold, the gate ALLOWS the '
               'disposition — so its refusals above are decisions, not an unconditional raise';

  -- a hold placed now must win over the approved policy
  INSERT INTO legal_holds(legal_hold_id,entity_type,entity_id,hold_ref,reason,placed_by_membership_id)
  VALUES ('c6400000-0000-0000-0000-000000000002','private_file_object','d6000000-0000-0000-0000-000000000001',
          'synthetic-case-3','synthetic hold over an approved policy','b6000000-0000-0000-0000-000000000001');
  BEGIN
    PERFORM public.assert_destructive_disposition_allowed('private_file_object',
              'd6000000-0000-0000-0000-000000000001','delete_object');
    RAISE EXCEPTION 'FAIL OPS-48b a legal hold did not override an approved retention policy';
  EXCEPTION WHEN check_violation THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF position('legal hold is active' IN v_msg)=0 THEN
      RAISE EXCEPTION 'FAIL OPS-48b wrong reason: %',v_msg; END IF;
  END;
  RAISE NOTICE 'PASS OPS-48b a legal hold overrides an approved policy: placement blocks deletion';

  -- ambiguity fails closed: a second approved policy effective for the same category and action
  INSERT INTO retention_policy_versions(policy_id,category_key,policy_version,status,duration_days,
                                        disposition_action,approval_ref,jurisdiction,effective_from)
  VALUES (gen_random_uuid(),'R6','SYNTHETIC-ops-48b','approved',90,'delete_object',
          'SYNTHETIC-TEST-FIXTURE-NOT-A-PRODUCT-OWNER-DECISION','synthetic',clock_timestamp()-interval '2 days');
  UPDATE legal_holds SET released_at=clock_timestamp(),
         released_by_membership_id='b6000000-0000-0000-0000-000000000001'
   WHERE legal_hold_id='c6400000-0000-0000-0000-000000000002';
  BEGIN
    PERFORM public.assert_destructive_disposition_allowed('private_file_object',
              'd6000000-0000-0000-0000-000000000001','delete_object');
    RAISE EXCEPTION 'FAIL OPS-48c two conflicting approved policies did not fail closed';
  EXCEPTION WHEN check_violation THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF position('ambiguous retention policy' IN v_msg)=0 THEN
      RAISE EXCEPTION 'FAIL OPS-48c wrong reason: %',v_msg; END IF;
  END;
  RAISE NOTICE 'PASS OPS-48c two conflicting approved policies fail CLOSED rather than one winning silently';
END $t$;

-- OPS-49  The gate reads clock_timestamp(). CLK-01 scans for this generically; this assertion is narrower
--         and survives an over-broad edit to that allowlist, because an effective-date decision made from
--         a transaction-start clock can be defeated by holding a transaction open.
DO $t$
DECLARE v_src text;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='assert_destructive_disposition_allowed';
  IF v_src IS NULL THEN RAISE EXCEPTION 'FAIL OPS-49 the disposition gate does not exist'; END IF;
  IF v_src !~* '\mclock_timestamp\s*\(' THEN
    RAISE EXCEPTION 'FAIL OPS-49 the disposition gate does not read clock_timestamp()';
  END IF;
  IF regexp_replace(v_src,'--[^'||chr(10)||']*','','g') ~* '\mnow\s*\(' THEN
    RAISE EXCEPTION 'FAIL OPS-49 the disposition gate reads a transaction-start clock';
  END IF;
  RAISE NOTICE 'PASS OPS-49 the disposition gate decides from clock_timestamp()';
END $t$;

-- OPS-50  Nobody may call the gate. There is no disposition executor identity (OPS-DISP-AUTH), and
--         PUBLIC EXECUTE on a SECURITY DEFINER function would be a privilege in itself (SEC-07).
DO $t$
DECLARE v_bad text; k text := current_setting('app.workspace_key');
BEGIN
  IF has_function_privilege('public','public.assert_destructive_disposition_allowed(text,uuid,text)','EXECUTE') THEN
    RAISE EXCEPTION 'FAIL OPS-50 PUBLIC can execute the disposition gate';
  END IF;
  SELECT string_agg(r.rolname,', ' ORDER BY r.rolname) INTO v_bad
    FROM pg_roles r
   WHERE r.rolname IN ('ws_'||k||'_runtime','ws_'||k||'_worker','ws_'||k||'_exporter')
     AND has_function_privilege(r.rolname,'public.assert_destructive_disposition_allowed(text,uuid,text)','EXECUTE');
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL OPS-50 these application roles can execute the disposition gate: %',v_bad;
  END IF;
  RAISE NOTICE 'PASS OPS-50 no application role and not PUBLIC may execute the disposition gate; the '
               'executor authority is an open decision and the gate stays uncallable until it is made';
END $t$;

-- OPS-51  No role may place or release a legal hold either, for the same reason (OPS-HOLD-AUTH).
DO $t$
DECLARE v_bad text; k text := current_setting('app.workspace_key');
BEGIN
  SELECT string_agg(grantee||':'||privilege_type,', ' ORDER BY grantee||':'||privilege_type) INTO v_bad
    FROM information_schema.role_table_grants
   WHERE table_schema='public' AND table_name='legal_holds'
     AND privilege_type IN ('INSERT','UPDATE','DELETE')
     AND grantee <> 'ws_'||k||'_table_owner' AND grantee <> current_user;
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL OPS-51 legal_holds is writable by: %. Who may place or release a hold is an open '
                    'Product Owner decision and must not be granted by default',v_bad;
  END IF;
  RAISE NOTICE 'PASS OPS-51 only the NOLOGIN table owner can write legal_holds, which is a synthetic '
               'posture and not an authority model';
END $t$;

-- ======================================================================================================
-- APPEND-ONLY MEANS APPEND-ONLY, INCLUDING TRUNCATE
-- ======================================================================================================
-- OPS-60  Catalog coverage. A table that claims immutability through a row trigger and does not refuse
--         TRUNCATE is a hole; anything added later fails here by name.
DO $t$
DECLARE v_n integer; v_bad text;
BEGIN
  SELECT count(*) INTO v_n FROM append_only_truncate_coverage;
  SELECT string_agg(table_name,', ' ORDER BY table_name) INTO v_bad
    FROM append_only_truncate_coverage WHERE NOT truncate_guarded;
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL OPS-60 these tables guard UPDATE/DELETE with a row trigger but accept TRUNCATE: %. '
                    'A row trigger never fires for TRUNCATE.',v_bad;
  END IF;
  IF v_n < 20 THEN
    RAISE EXCEPTION 'FAIL OPS-60 only % immutable table(s) found; the catalog scan looks wrong',v_n;
  END IF;
  RAISE NOTICE 'PASS OPS-60 all % tables that claim immutability refuse TRUNCATE',v_n;
END $t$;

-- OPS-61 is the SENSITIVE one: audit_events is referenced by no foreign key, so nothing but the new
-- statement trigger can refuse this TRUNCATE. Measured: with the trigger removed, this statement
-- succeeds and empties the audit log.
SELECT ops_err('OPS-61 TRUNCATE of the audit log is refused',
  $$TRUNCATE audit_events$$, '23514','TRUNCATE is refused');
-- OPS-62/63 are partially MASKED and are recorded as such. A plain TRUNCATE of a table that another
-- table references is refused by PostgreSQL with 0A000 before any trigger runs, which proves nothing
-- about this guard — the same class of masking as the foreign-key row lock in the freeze race. CASCADE
-- is therefore used, which does reach the trigger.
SELECT ops_err('OPS-62 TRUNCATE CASCADE of the credit ledger is refused by the guard, not by a foreign key',
  $$TRUNCATE credit_transactions CASCADE$$, '23514','TRUNCATE is refused');
SELECT ops_err('OPS-63 TRUNCATE of the governance event ledger is refused',
  $$TRUNCATE workspace_governance_events$$, '23514','TRUNCATE is refused');

-- OPS-64  HONESTY ASSERTION, measured rather than assumed. TRUNCATE was never reachable by an
--         application role, so OPS-60..63 are hardening and not a fixed vulnerability. If an application
--         role ever gains TRUNCATE this fails, and the hardening becomes load-bearing.
DO $t$
DECLARE v_bad text;
BEGIN
  SELECT string_agg(DISTINCT grantee,', ' ORDER BY grantee) INTO v_bad
    FROM information_schema.role_table_grants
   WHERE table_schema='public' AND privilege_type='TRUNCATE'
     AND grantee ~ '_(runtime|worker|exporter|verifier_rt|governance_adapter_rt|synth_exec|synth_inbox|transfer_ctl)(_login)?$';
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL OPS-64 these application roles hold TRUNCATE: %',v_bad;
  END IF;
  RAISE NOTICE 'PASS OPS-64 measured: no application role holds TRUNCATE on any table, so the TRUNCATE '
               'guards close a gap reachable only by the owner — hardening, not a live hole';
END $t$;

SELECT 'OPERATIONS TESTS COMPLETED (OPS-01..OPS-64: files, notifications, retention, legal hold, truncate)' AS result;
