-- WS-ISO-01 — counselor-to-counselor isolation inside ONE Workspace. SYNTHETIC ONLY (D-014).
-- Run on a FRESH database after workspace_schema_draft.sql, workspace_activation_transactions.sql,
-- workspace_governance_events_draft.sql, workspace_archive_transactions.sql, workspace_inbox_projection.sql,
-- workspace_transfer_freeze.sql, workspace_counselor_scope_draft.sql, workspace_operations_draft.sql and
-- workspace_roles_setup_draft.sql (-v workspace_key).
--
-- READ THIS BEFORE READING ANY PASS LINE BELOW
--   These tests prove that the BOUNDARY is defined correctly: given a counselor membership, exactly the
--   students reachable through an active, accepted counselor assignment are reachable, for direct ids,
--   guessed ids of related records, list queries, a report and note visibility, and that access ends the
--   moment the assignment, the membership or the role does.
--   They do NOT prove that a counselor is prevented from reading another counselor's students at the
--   database. Every boundary function takes the membership as an argument, and the database cannot tell
--   whether the caller is that membership. The runtime role still reads every student-scoped table in
--   full, and ISO-GAP-01..03 print that residual as OPEN lines, which are not counted as PASS.
--   WS-ISO-01 stays OPEN and BLOCKING until a caller-binding mechanism is decided and enforced.
\set ON_ERROR_STOP on
SET app.workspace_key = :'workspace_key';
SELECT format('ws_%s_runtime', :'workspace_key') AS runtime_role \gset

CREATE OR REPLACE FUNCTION iso_true(label text, cond boolean) RETURNS void LANGUAGE plpgsql AS $t$
BEGIN
  IF cond IS DISTINCT FROM true THEN RAISE EXCEPTION 'FAIL %: expected true, got %', label, cond; END IF;
  RAISE NOTICE 'PASS %', label;
END; $t$;
CREATE OR REPLACE FUNCTION iso_false(label text, cond boolean) RETURNS void LANGUAGE plpgsql AS $t$
BEGIN
  IF cond IS DISTINCT FROM false THEN RAISE EXCEPTION 'FAIL %: expected false, got %', label, cond; END IF;
  RAISE NOTICE 'PASS %', label;
END; $t$;
CREATE OR REPLACE FUNCTION iso_err(label text, stmt text, want_msg text) RETURNS void LANGUAGE plpgsql AS $t$
BEGIN
  BEGIN
    EXECUTE stmt;
  EXCEPTION WHEN check_violation THEN
    IF position(want_msg IN SQLERRM)=0 THEN RAISE EXCEPTION 'FAIL %: wrong reason: %',label,SQLERRM; END IF;
    RAISE NOTICE 'PASS % (refused, reason verified)',label;
    RETURN;
  END;
  RAISE EXCEPTION 'FAIL %: statement unexpectedly succeeded',label;
END; $t$;
GRANT EXECUTE ON FUNCTION iso_true(text,boolean), iso_false(text,boolean), iso_err(text,text,text) TO PUBLIC;

-- ======================================================================================================
-- Fixtures. ONE Workspace, which is the point: per-Workspace isolation is already tested elsewhere, and
-- this requirement is about two counselors who share a Workspace, a runtime role and a database.
--   counselor A  (b5..0a)  accepted for students a1, a2
--   counselor B  (b5..0b)  accepted for student b1
--   counselor C  (b5..0c)  accepted, NON-responsible, co-assigned to a1 (note visibility)
--   counselor P  (b5..0d)  a PROPOSED assignment to b1 that was never accepted
--   counselor S  (b5..0e)  accepted for b1 but SUSPENDED as a member
--   assistant T  (b5..0f)  an accepted assignment to b1 but WITHOUT the counselor role
--   manager   M  (b5..10)  organization_manager, no assignment, no explicit permission
-- ======================================================================================================
INSERT INTO workspace_profile(singleton,workspace_id,workspace_type)
VALUES (true,'a5000000-0000-0000-0000-000000000001','organization');
INSERT INTO workspace_memberships(membership_id,platform_user_id,status) VALUES
 ('b5000000-0000-0000-0000-00000000000a','c5000000-0000-0000-0000-00000000000a','active'),
 ('b5000000-0000-0000-0000-00000000000b','c5000000-0000-0000-0000-00000000000b','active'),
 ('b5000000-0000-0000-0000-00000000000c','c5000000-0000-0000-0000-00000000000c','active'),
 ('b5000000-0000-0000-0000-00000000000d','c5000000-0000-0000-0000-00000000000d','active'),
 ('b5000000-0000-0000-0000-00000000000e','c5000000-0000-0000-0000-00000000000e','suspended'),
 ('b5000000-0000-0000-0000-00000000000f','c5000000-0000-0000-0000-00000000000f','active'),
 ('b5000000-0000-0000-0000-000000000010','c5000000-0000-0000-0000-000000000010','active');
INSERT INTO membership_roles(membership_id,role_key) VALUES
 ('b5000000-0000-0000-0000-00000000000a','counselor'),
 ('b5000000-0000-0000-0000-00000000000b','counselor'),
 ('b5000000-0000-0000-0000-00000000000c','counselor'),
 ('b5000000-0000-0000-0000-00000000000d','counselor'),
 ('b5000000-0000-0000-0000-00000000000e','counselor'),
 ('b5000000-0000-0000-0000-00000000000f','assistant'),
 ('b5000000-0000-0000-0000-000000000010','organization_manager');
INSERT INTO students(student_id,platform_student_id,display_name,grade_key,lifecycle_state) VALUES
 ('e5000000-0000-0000-0000-0000000000a1','f5000000-0000-0000-0000-0000000000a1','Iso A1','grade_10','active'),
 ('e5000000-0000-0000-0000-0000000000a2','f5000000-0000-0000-0000-0000000000a2','Iso A2','grade_10','active'),
 ('e5000000-0000-0000-0000-0000000000b1','f5000000-0000-0000-0000-0000000000b1','Iso B1','grade_11','active');
INSERT INTO enrollments(enrollment_id,student_id,ownership_generation,state) VALUES
 ('a5100000-0000-0000-0000-0000000000a1','e5000000-0000-0000-0000-0000000000a1',1,'requested'),
 ('a5100000-0000-0000-0000-0000000000a2','e5000000-0000-0000-0000-0000000000a2',1,'requested'),
 ('a5100000-0000-0000-0000-0000000000b1','e5000000-0000-0000-0000-0000000000b1',1,'requested');
INSERT INTO counselor_assignments(assignment_id,enrollment_id,counselor_membership_id,is_responsible,state,accepted_at) VALUES
 ('a5200000-0000-0000-0000-0000000000a1','a5100000-0000-0000-0000-0000000000a1','b5000000-0000-0000-0000-00000000000a',true, 'active',clock_timestamp()),
 ('a5200000-0000-0000-0000-0000000000a2','a5100000-0000-0000-0000-0000000000a2','b5000000-0000-0000-0000-00000000000a',true, 'active',clock_timestamp()),
 ('a5200000-0000-0000-0000-0000000000b1','a5100000-0000-0000-0000-0000000000b1','b5000000-0000-0000-0000-00000000000b',true, 'active',clock_timestamp()),
 ('a5200000-0000-0000-0000-0000000000c1','a5100000-0000-0000-0000-0000000000a1','b5000000-0000-0000-0000-00000000000c',false,'active',clock_timestamp()),
 ('a5200000-0000-0000-0000-0000000000d1','a5100000-0000-0000-0000-0000000000b1','b5000000-0000-0000-0000-00000000000d',false,'active',NULL),
 ('a5200000-0000-0000-0000-0000000000e1','a5100000-0000-0000-0000-0000000000b1','b5000000-0000-0000-0000-00000000000e',false,'active',clock_timestamp()),
 ('a5200000-0000-0000-0000-0000000000f1','a5100000-0000-0000-0000-0000000000b1','b5000000-0000-0000-0000-00000000000f',false,'active',clock_timestamp());

-- Related records for b1 (the target) and for A's students (the control). Minutes are distinct per
-- student so a report total that included a row it should not have is detectable arithmetically.
INSERT INTO study_sessions(study_session_id,student_id,started_at,actual_minutes) VALUES
 ('a5300000-0000-0000-0000-0000000000a1','e5000000-0000-0000-0000-0000000000a1',clock_timestamp(),30),
 ('a5300000-0000-0000-0000-0000000000a2','e5000000-0000-0000-0000-0000000000a2',clock_timestamp(),45),
 ('a5300000-0000-0000-0000-0000000000b1','e5000000-0000-0000-0000-0000000000b1',clock_timestamp(),999);
INSERT INTO private_file_objects(file_id,student_id,object_key,storage_provider,content_type,byte_size,
                                 sha256,encryption_key_version,state,uploaded_by_membership_id) VALUES
 ('a5400000-0000-0000-0000-0000000000b1','e5000000-0000-0000-0000-0000000000b1','workspace/iso/b1','synthetic',
  'application/pdf',100,decode(repeat('c5',32),'hex'),1,'available','b5000000-0000-0000-0000-00000000000b');
INSERT INTO in_app_notifications(notification_id,recipient_platform_user_id,student_id,notification_type,
                                 template_version,payload,idempotency_key) VALUES
 ('a5500000-0000-0000-0000-0000000000b1','c5000000-0000-0000-0000-00000000000b','e5000000-0000-0000-0000-0000000000b1',
  'weekly_summary','v1','{}','iso-idem-b1');
INSERT INTO student_plans(plan_id,student_id) VALUES
 ('a5600000-0000-0000-0000-0000000000b1','e5000000-0000-0000-0000-0000000000b1');
INSERT INTO student_plan_versions(plan_version_id,plan_id,version_no,input_snapshot,rule_version,plan_content,status) VALUES
 ('a5610000-0000-0000-0000-0000000000b1','a5600000-0000-0000-0000-0000000000b1',1,'{}','synthetic-v1','{}','draft');
BEGIN;
INSERT INTO student_guardian_links(link_id,student_id,guardian_platform_user_id,relationship_type,
                                   verification_state,legal_authority_ref,verified_at)
VALUES ('a5700000-0000-0000-0000-0000000000b1','e5000000-0000-0000-0000-0000000000b1',
        'c5000000-0000-0000-0000-0000000000ff','parent','verified','synthetic-authority-iso',clock_timestamp());
INSERT INTO guardian_link_events(event_id,link_id,event_type,actor_ref,authn_event_ref,evidence_ref,policy_version,effective_at)
VALUES ('a5710000-0000-0000-0000-0000000000b1','a5700000-0000-0000-0000-0000000000b1','link_created','synthetic-actor','synthetic-authn',NULL,'p1',clock_timestamp()),
       ('a5710000-0000-0000-0000-0000000000b2','a5700000-0000-0000-0000-0000000000b1','verified','synthetic-actor','synthetic-authn','synthetic-evidence','p1',clock_timestamp());
COMMIT;
INSERT INTO counselor_notes(counselor_note_id,student_id,author_membership_id,visibility,content) VALUES
 ('a5800000-0000-0000-0000-0000000000b1','e5000000-0000-0000-0000-0000000000b1','b5000000-0000-0000-0000-00000000000b','private_to_author','synthetic B note'),
 ('a5800000-0000-0000-0000-0000000000a1','e5000000-0000-0000-0000-0000000000a1','b5000000-0000-0000-0000-00000000000a','private_to_author','synthetic A private'),
 ('a5800000-0000-0000-0000-0000000000a2','e5000000-0000-0000-0000-0000000000a1','b5000000-0000-0000-0000-00000000000a','workspace_scoped','synthetic A shared');

-- ======================================================================================================
-- CATALOG — the boundary covers every student-scoped table, so a table added later cannot sit outside it.
-- ======================================================================================================
-- ISO-C1  Every table the transfer barrier treats as student-scoped is either resolvable row-by-row by
--         counselor_may_access_row (one-column primary key) or is one of the reviewed composite-key tables
--         whose key already contains student_id. Anything else would be a student-scoped table the
--         counselor boundary cannot answer for.
DO $t$
DECLARE v_bad text; v_n integer;
BEGIN
  WITH pk AS (
    SELECT t.table_name,
           (SELECT count(*) FROM pg_index i JOIN pg_attribute a ON a.attrelid=i.indrelid AND a.attnum=ANY(i.indkey)
             WHERE i.indrelid=('public.'||t.table_name)::regclass AND i.indisprimary) AS ncols,
           EXISTS (SELECT 1 FROM pg_index i JOIN pg_attribute a ON a.attrelid=i.indrelid AND a.attnum=ANY(i.indkey)
                    WHERE i.indrelid=('public.'||t.table_name)::regclass AND i.indisprimary AND a.attname='student_id') AS has_sid
      FROM student_scoped_tables t)
  SELECT string_agg(table_name, ', ' ORDER BY table_name), count(*) FILTER (WHERE true)
    INTO v_bad, v_n
    FROM pk WHERE NOT (ncols = 1 OR (ncols > 1 AND has_sid));
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL ISO-C1 student-scoped tables the counselor boundary cannot resolve: %', v_bad;
  END IF;
  SELECT count(*) INTO v_n FROM student_scoped_tables;
  IF v_n < 32 THEN RAISE EXCEPTION 'FAIL ISO-C1 only % student-scoped tables; expected at least 32', v_n; END IF;
  RAISE NOTICE 'PASS ISO-C1 all % student-scoped tables are within the counselor boundary', v_n;
END $t$;
-- ISO-C2  The composite-key exceptions, pinned by name.
DO $t$
DECLARE v_list text;
BEGIN
  SELECT string_agg(t.table_name, ',' ORDER BY t.table_name) INTO v_list
    FROM student_scoped_tables t
   WHERE (SELECT count(*) FROM pg_index i JOIN pg_attribute a ON a.attrelid=i.indrelid AND a.attnum=ANY(i.indkey)
           WHERE i.indrelid=('public.'||t.table_name)::regclass AND i.indisprimary) > 1;
  IF v_list IS DISTINCT FROM 'class_participants,class_session_participants,student_topic_mastery' THEN
    RAISE EXCEPTION 'FAIL ISO-C2 composite-key student tables changed: %. Review whether the new table is '
                    'identified by its student before adding it here', v_list;
  END IF;
  RAISE NOTICE 'PASS ISO-C2 the three composite-key student tables are pinned, each keyed by student_id';
END $t$;

-- ======================================================================================================
-- BEHAVIOUR — run AS THE RUNTIME ROLE, the identity every counselor shares today.
-- ======================================================================================================
SET SESSION AUTHORIZATION :"runtime_role";

-- Direct student ids.
SELECT iso_true ('ISO-01 counselor A reaches own student a1',
  counselor_may_access_student('b5000000-0000-0000-0000-00000000000a','e5000000-0000-0000-0000-0000000000a1'));
SELECT iso_false('ISO-02 counselor A does NOT reach counselor B''s student b1',
  counselor_may_access_student('b5000000-0000-0000-0000-00000000000a','e5000000-0000-0000-0000-0000000000b1'));
SELECT iso_false('ISO-03 counselor B does NOT reach counselor A''s student a1',
  counselor_may_access_student('b5000000-0000-0000-0000-00000000000b','e5000000-0000-0000-0000-0000000000a1'));
SELECT iso_false('ISO-04 an UNACCEPTED (proposed) assignment grants nothing',
  counselor_may_access_student('b5000000-0000-0000-0000-00000000000d','e5000000-0000-0000-0000-0000000000b1'));
SELECT iso_false('ISO-05 a SUSPENDED membership reaches nothing, even with an accepted assignment',
  counselor_may_access_student('b5000000-0000-0000-0000-00000000000e','e5000000-0000-0000-0000-0000000000b1'));
SELECT iso_false('ISO-06 an assignment held by a membership WITHOUT the counselor role grants nothing',
  counselor_may_access_student('b5000000-0000-0000-0000-00000000000f','e5000000-0000-0000-0000-0000000000b1'));
SELECT iso_false('ISO-07 a manager reaches no student without the explicit permission the contract requires',
  counselor_may_access_student('b5000000-0000-0000-0000-000000000010','e5000000-0000-0000-0000-0000000000b1'));
SELECT iso_false('ISO-08 a guessed, non-existent student id is not reachable',
  counselor_may_access_student('b5000000-0000-0000-0000-00000000000a','e5000000-0000-0000-0000-0000000000ff'));
SELECT iso_false('ISO-09 a NULL membership reaches nothing',
  counselor_may_access_student(NULL,'e5000000-0000-0000-0000-0000000000a1'));

-- Guessed ids of RELATED records: the caller presents the record's own id, never the student's.
SELECT iso_true ('ISO-10 A reaches own student''s study session by its id',
  counselor_may_access_row('b5000000-0000-0000-0000-00000000000a','study_sessions','a5300000-0000-0000-0000-0000000000a1'));
SELECT iso_false('ISO-11 A does NOT reach b1''s study session by guessing its id',
  counselor_may_access_row('b5000000-0000-0000-0000-00000000000a','study_sessions','a5300000-0000-0000-0000-0000000000b1'));
SELECT iso_false('ISO-12 a non-existent id answers exactly like another counselor''s id (no existence oracle)',
  counselor_may_access_row('b5000000-0000-0000-0000-00000000000a','study_sessions','a5300000-0000-0000-0000-0000000000ff'));
SELECT iso_false('ISO-13 A does NOT reach b1''s private file object',
  counselor_may_access_row('b5000000-0000-0000-0000-00000000000a','private_file_objects','a5400000-0000-0000-0000-0000000000b1'));
SELECT iso_false('ISO-14 A does NOT reach b1''s notification',
  counselor_may_access_row('b5000000-0000-0000-0000-00000000000a','in_app_notifications','a5500000-0000-0000-0000-0000000000b1'));
SELECT iso_false('ISO-15 A does NOT reach b1''s plan VERSION, which reaches its student only through the plan',
  counselor_may_access_row('b5000000-0000-0000-0000-00000000000a','student_plan_versions','a5610000-0000-0000-0000-0000000000b1'));
SELECT iso_true ('ISO-15b B DOES reach that plan version (the indirect path resolves, it is not merely denied)',
  counselor_may_access_row('b5000000-0000-0000-0000-00000000000b','student_plan_versions','a5610000-0000-0000-0000-0000000000b1'));
RESET SESSION AUTHORIZATION;
-- ISO-16 runs as the owner: the runtime role holds no SELECT on guardian_link_events at all (it is
-- append-only authority evidence), so a runtime caller cannot reach those rows by any path and the
-- question only arises for an identity that can read them. The answer must still be "not counselor A".
SELECT iso_false('ISO-16 A does NOT reach b1''s guardian link EVENT, two hops from the student',
  counselor_may_access_row('b5000000-0000-0000-0000-00000000000a','guardian_link_events','a5710000-0000-0000-0000-0000000000b1'));
SELECT iso_true ('ISO-16b B DOES reach it (the two-hop path resolves)',
  counselor_may_access_row('b5000000-0000-0000-0000-00000000000b','guardian_link_events','a5710000-0000-0000-0000-0000000000b1'));
SET SESSION AUTHORIZATION :"runtime_role";
SELECT iso_false('ISO-17 A does NOT reach b1''s enrollment',
  counselor_may_access_row('b5000000-0000-0000-0000-00000000000a','enrollments','a5100000-0000-0000-0000-0000000000b1'));
SELECT iso_false('ISO-18 A does NOT reach counselor B''s ASSIGNMENT row (enrollment-keyed)',
  counselor_may_access_row('b5000000-0000-0000-0000-00000000000a','counselor_assignments','a5200000-0000-0000-0000-0000000000b1'));
SELECT iso_err('ISO-19 a table outside the student scope is refused, not silently answered',
  $q$SELECT counselor_may_access_row('b5000000-0000-0000-0000-00000000000a','workspace_memberships','b5000000-0000-0000-0000-00000000000b')$q$,
  'is not a student-scoped table');
SELECT iso_err('ISO-19b a composite-key table is refused with directions rather than guessed',
  $q$SELECT counselor_may_access_row('b5000000-0000-0000-0000-00000000000a','student_topic_mastery','x')$q$,
  'composite primary key');

-- Notes: a private note is its author's alone, even from a co-assigned counselor.
SELECT iso_true ('ISO-20 the author reaches own private note',
  counselor_may_access_row('b5000000-0000-0000-0000-00000000000a','counselor_notes','a5800000-0000-0000-0000-0000000000a1'));
SELECT iso_false('ISO-21 a CO-ASSIGNED counselor does NOT reach another counselor''s private note on the same student',
  counselor_may_access_row('b5000000-0000-0000-0000-00000000000c','counselor_notes','a5800000-0000-0000-0000-0000000000a1'));
SELECT iso_true ('ISO-22 the co-assigned counselor DOES reach the workspace_scoped note',
  counselor_may_access_row('b5000000-0000-0000-0000-00000000000c','counselor_notes','a5800000-0000-0000-0000-0000000000a2'));
SELECT iso_false('ISO-23 A does NOT reach B''s private note on b1',
  counselor_may_access_row('b5000000-0000-0000-0000-00000000000a','counselor_notes','a5800000-0000-0000-0000-0000000000b1'));

-- List queries.
SELECT iso_true('ISO-30 A''s student list is exactly {a1, a2}',
  (SELECT array_agg(x ORDER BY x) FROM counselor_visible_students('b5000000-0000-0000-0000-00000000000a') x)
   = ARRAY['e5000000-0000-0000-0000-0000000000a1'::uuid,'e5000000-0000-0000-0000-0000000000a2'::uuid]);
SELECT iso_true('ISO-31 B''s student list is exactly {b1}',
  (SELECT array_agg(x) FROM counselor_visible_students('b5000000-0000-0000-0000-00000000000b') x)
   = ARRAY['e5000000-0000-0000-0000-0000000000b1'::uuid]);
SELECT iso_true('ISO-32 the manager, the suspended counselor, the unaccepted counselor and the non-counselor all list NOTHING',
  NOT EXISTS (SELECT 1 FROM counselor_visible_students('b5000000-0000-0000-0000-000000000010')
              UNION ALL SELECT 1 FROM counselor_visible_students('b5000000-0000-0000-0000-00000000000e')
              UNION ALL SELECT 1 FROM counselor_visible_students('b5000000-0000-0000-0000-00000000000d')
              UNION ALL SELECT 1 FROM counselor_visible_students('b5000000-0000-0000-0000-00000000000f')));

-- A report, where a leak hides inside a total.
SELECT iso_true('ISO-33 A''s caseload report has rows for a1 and a2 only',
  (SELECT array_agg(student_id ORDER BY student_id) FROM counselor_caseload_report('b5000000-0000-0000-0000-00000000000a'))
   = ARRAY['e5000000-0000-0000-0000-0000000000a1'::uuid,'e5000000-0000-0000-0000-0000000000a2'::uuid]);
SELECT iso_true('ISO-34 A''s report totals 75 study minutes; b1''s 999 is in no total',
  (SELECT sum(study_minutes) FROM counselor_caseload_report('b5000000-0000-0000-0000-00000000000a')) = 75);

-- Write paths where the row names the actor.
SELECT iso_err('ISO-40 counselor B cannot write a note about counselor A''s student',
  $q$INSERT INTO counselor_notes(counselor_note_id,student_id,author_membership_id,visibility,content)
     VALUES (gen_random_uuid(),'e5000000-0000-0000-0000-0000000000a1','b5000000-0000-0000-0000-00000000000b','workspace_scoped','x')$q$,
  'not an active, accepted counselor of student');
SELECT iso_err('ISO-41 a note cannot be RE-ATTRIBUTED to another author',
  $q$UPDATE counselor_notes SET author_membership_id='b5000000-0000-0000-0000-00000000000c'
      WHERE counselor_note_id='a5800000-0000-0000-0000-0000000000a1'$q$,
  'immutable');
SELECT iso_err('ISO-42 a private note cannot be widened to every counselor of the student',
  $q$UPDATE counselor_notes SET visibility='workspace_scoped' WHERE counselor_note_id='a5800000-0000-0000-0000-0000000000a1'$q$,
  'cannot be widened');
SELECT iso_err('ISO-43 counselor A cannot be the recipient of a notification about counselor B''s student',
  $q$INSERT INTO in_app_notifications(notification_id,recipient_platform_user_id,student_id,notification_type,
       template_version,payload,idempotency_key)
     VALUES (gen_random_uuid(),'c5000000-0000-0000-0000-00000000000a','e5000000-0000-0000-0000-0000000000b1',
             'weekly_summary','v1','{}','iso-idem-43')$q$,
  'able to reach that student');

RESET SESSION AUTHORIZATION;

-- Revocation takes effect immediately, through every surface. Run as the owner because the runtime role
-- holds no UPDATE on assignments or memberships (and must not).
UPDATE counselor_assignments SET state='ended', ended_at=clock_timestamp()
 WHERE assignment_id='a5200000-0000-0000-0000-0000000000a2';
SELECT iso_false('ISO-50 ending an assignment removes the student at once (predicate)',
  counselor_may_access_student('b5000000-0000-0000-0000-00000000000a','e5000000-0000-0000-0000-0000000000a2'));
SELECT iso_true ('ISO-51 ... from the list',
  (SELECT array_agg(x) FROM counselor_visible_students('b5000000-0000-0000-0000-00000000000a') x)
   = ARRAY['e5000000-0000-0000-0000-0000000000a1'::uuid]);
SELECT iso_true ('ISO-52 ... and from the report total (75 -> 30)',
  (SELECT sum(study_minutes) FROM counselor_caseload_report('b5000000-0000-0000-0000-00000000000a')) = 30);
SELECT iso_false('ISO-53 ... and from its related records',
  counselor_may_access_row('b5000000-0000-0000-0000-00000000000a','study_sessions','a5300000-0000-0000-0000-0000000000a2'));
UPDATE workspace_memberships SET status='suspended' WHERE membership_id='b5000000-0000-0000-0000-00000000000a';
SELECT iso_false('ISO-54 suspending the membership removes every remaining student, private notes included',
  counselor_may_access_row('b5000000-0000-0000-0000-00000000000a','counselor_notes','a5800000-0000-0000-0000-0000000000a1'));
UPDATE workspace_memberships SET status='active' WHERE membership_id='b5000000-0000-0000-0000-00000000000a';

-- ======================================================================================================
-- THE RESIDUAL. These are OPEN lines, deliberately not PASS lines: they measure that WS-ISO-01 is NOT
-- enforced at the database, so nobody can read the PASS count above as proof that it is. Each one FAILS
-- the suite if the measurement changes, so this record cannot silently go stale when isolation is built.
-- ======================================================================================================
SET SESSION AUTHORIZATION :"runtime_role";
DO $t$
DECLARE v_minutes integer;
BEGIN
  SELECT actual_minutes INTO v_minutes FROM public.study_sessions
   WHERE study_session_id='a5300000-0000-0000-0000-0000000000b1';
  IF v_minutes IS DISTINCT FROM 999 THEN
    RAISE EXCEPTION 'FAIL ISO-GAP-01 the runtime role could NOT read counselor B''s study session directly. '
                    'If that is because isolation is now enforced, update WS-ISO-01 and this test together';
  END IF;
  RAISE NOTICE 'OPEN ISO-GAP-01 the runtime role every counselor shares reads counselor B''s study session '
               'directly (999 minutes); the boundary above is not bound to the caller';
END $t$;
DO $t$
DECLARE v_n integer;
BEGIN
  SELECT count(*) INTO v_n FROM public.counselor_notes WHERE visibility='private_to_author';
  IF v_n < 2 THEN
    RAISE EXCEPTION 'FAIL ISO-GAP-02 the runtime role no longer reads every private note; update WS-ISO-01';
  END IF;
  RAISE NOTICE 'OPEN ISO-GAP-02 the runtime role reads all % private_to_author notes, authors notwithstanding', v_n;
END $t$;
RESET SESSION AUTHORIZATION;
DO $t$
DECLARE v_rls integer; v_total integer;
BEGIN
  SELECT count(*) FILTER (WHERE c.relrowsecurity), count(*) INTO v_rls, v_total
    FROM student_scoped_tables t JOIN pg_class c ON c.oid = ('public.'||t.table_name)::regclass;
  IF v_rls <> 0 THEN
    RAISE EXCEPTION 'FAIL ISO-GAP-03 % of % student-scoped tables now have row-level security; WS-ISO-01 and '
                    'this record must be updated together', v_rls, v_total;
  END IF;
  RAISE NOTICE 'OPEN ISO-GAP-03 0 of % student-scoped tables have row-level security', v_total;
END $t$;

SELECT 'COUNSELOR ISOLATION TESTS COMPLETED: the BOUNDARY is correct; it is NOT bound to the caller — WS-ISO-01 OPEN' AS result;
