-- =============================================================================
-- PHASE 2 — CONSTRAINT TEST SUITE v2
-- Run order: phase2_roles_setup.sql -> phase2_schema_draft.sql -> this file.
-- Fresh database for every run (fixtures are not idempotent).
-- Each negative test asserts the exact SQLSTATE and, where the reason matters,
-- a substring of the error message, so a failure for an unrelated reason FAILS.
-- Synthetic data only (D-014).
-- =============================================================================
\set ON_ERROR_STOP on

-- ----------------------------------------------------------- helpers -------
CREATE OR REPLACE FUNCTION expect_error(label text, stmt text, want text, want_msg text DEFAULT '')
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    EXECUTE stmt;
    RAISE EXCEPTION 'FAIL %: statement succeeded, expected SQLSTATE %', label, want;
EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE <> want THEN
        RAISE EXCEPTION 'FAIL %: got SQLSTATE % (%), expected %', label, SQLSTATE, SQLERRM, want;
    END IF;
    IF want_msg <> '' AND position(want_msg IN SQLERRM) = 0 THEN
        RAISE EXCEPTION 'FAIL %: right SQLSTATE but wrong reason: %', label, SQLERRM;
    END IF;
    RAISE NOTICE 'PASS % (SQLSTATE %, reason verified)', label, SQLSTATE;
END;
$$;

CREATE OR REPLACE FUNCTION expect_ok(label text, stmt text)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    EXECUTE stmt;
    RAISE NOTICE 'PASS % (accepted)', label;
END;
$$;

-- ------------------------------------------------------------ fixtures -----
INSERT INTO tenants (id, status) VALUES
  ('00000000-0000-0000-0000-000000000001', 'active'),
  ('00000000-0000-0000-0000-000000000002', 'active');

-- Test-environment authorization seed (NOT production configuration). Synthetic only.
INSERT INTO credit_role_permissions (role_name, kind) VALUES
  ('app_t1', 'activation_consume'), ('app_t2', 'activation_consume'),
  ('issuer_rt', 'purchase'),
  ('adjuster_rt', 'refund'), ('adjuster_rt', 'cancellation_release'), ('adjuster_rt', 'adjustment'),
  ('postgres', 'purchase'), ('postgres', 'activation_consume'), ('postgres', 'refund'),
  ('postgres', 'cancellation_release'), ('postgres', 'adjustment');
INSERT INTO tenant_role_bindings (role_name, tenant_id) VALUES
  ('app_t1', '00000000-0000-0000-0000-000000000001'),
  ('app_t2', '00000000-0000-0000-0000-000000000002'),
  ('issuer_rt', '00000000-0000-0000-0000-000000000001'),
  ('adjuster_rt', '00000000-0000-0000-0000-000000000001'),
  ('postgres', '00000000-0000-0000-0000-000000000001'),
  ('postgres', '00000000-0000-0000-0000-000000000002');

INSERT INTO counselors (id, tenant_id, display_name) VALUES
  ('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'Synthetic Counselor A'),
  ('10000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000002', 'Synthetic Counselor B');

INSERT INTO students (id, tenant_id) VALUES
  ('20000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001'),
  ('20000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000002'),
  ('20000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000001');

INSERT INTO subjects (id, tenant_id, name) VALUES
  ('30000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'Synthetic Math'),
  ('30000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000002', 'Synthetic Math');

INSERT INTO curriculum_nodes (id, tenant_id, subject_id, parent_id, level, name) VALUES
  ('31000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001',
   '30000000-0000-0000-0000-000000000001', NULL, 'grade', 'Synthetic Grade 10'),
  ('31000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001',
   '30000000-0000-0000-0000-000000000001', '31000000-0000-0000-0000-000000000001', 'book', 'Synthetic Book');
INSERT INTO curriculum_nodes (id, tenant_id, subject_id, parent_id, level, name) VALUES
  ('31000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000002',
   '30000000-0000-0000-0000-000000000002', NULL, 'grade', 'Synthetic Grade B');

INSERT INTO program_templates (id, tenant_id, name) VALUES
  ('40000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'Synthetic Template A'),
  ('40000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000002', 'Synthetic Template B');

-- Drafts first, then publish, so the publication rule is exercised by the fixture itself.
INSERT INTO program_versions (id, tenant_id, program_template_id, version_number, status, payload_json) VALUES
  ('50000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001',
   '40000000-0000-0000-0000-000000000001', 1, 'draft', '{"weekly":5}'),
  ('50000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000002',
   '40000000-0000-0000-0000-000000000002', 1, 'draft', '{"weekly":4}');
UPDATE program_versions SET status = 'published', published_by = '90000000-0000-0000-0000-00000000aaaa', published_at = now()
 WHERE id IN ('50000000-0000-0000-0000-000000000001', '50000000-0000-0000-0000-000000000002');
DO $$ BEGIN RAISE NOTICE 'PASS fixture: draft -> published transition accepted'; END $$;

INSERT INTO program_versions (id, tenant_id, program_template_id, version_number, status, payload_json) VALUES
  ('50000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000001',
   '40000000-0000-0000-0000-000000000001', 2, 'draft', '{"weekly":6}');

INSERT INTO student_program_enrollments (id, tenant_id, student_id, program_version_id) VALUES
  ('80000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001',
   '20000000-0000-0000-0000-000000000001', '50000000-0000-0000-0000-000000000001');

INSERT INTO plans (id, tenant_id, student_id, scope, period_start, period_end) VALUES
  ('60000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001',
   '20000000-0000-0000-0000-000000000001', 'weekly', '2026-11-01', '2026-11-07');
INSERT INTO plan_versions (id, tenant_id, plan_id, version_number, program_version_id) VALUES
  ('61000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001',
   '60000000-0000-0000-0000-000000000001', 1, '50000000-0000-0000-0000-000000000001');
INSERT INTO plan_items (id, tenant_id, plan_version_id, activity_type, subject_id, scheduled_start, scheduled_end) VALUES
  ('62000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001',
   '61000000-0000-0000-0000-000000000001', 'study', '30000000-0000-0000-0000-000000000001',
   '2026-11-02 08:00+03:30', '2026-11-02 09:00+03:30');

INSERT INTO activities (id, tenant_id, student_id, activity_type, subject_id, occurred_on) VALUES
  ('90000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001',
   '20000000-0000-0000-0000-000000000001', 'test', '30000000-0000-0000-0000-000000000001', '2026-11-02'),
  ('90000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001',
   '20000000-0000-0000-0000-000000000001', 'study', '30000000-0000-0000-0000-000000000001', '2026-11-02');
INSERT INTO test_records (activity_id, tenant_id, question_count, correct, wrong, unanswered) VALUES
  ('90000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 10, 7, 2, 1);
INSERT INTO study_sessions (activity_id, tenant_id, started_at, ended_at, goal) VALUES
  ('90000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001',
   '2026-11-02 08:00+03:30', '2026-11-02 09:00+03:30', 'synthetic goal');
INSERT INTO error_records (id, tenant_id, test_activity_id, error_type) VALUES
  ('a1000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001',
   '90000000-0000-0000-0000-000000000001', 'conceptual');
INSERT INTO review_schedules (id, tenant_id, original_activity_id, original_type, review_offset_days, review_date) VALUES
  ('91000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001',
   '90000000-0000-0000-0000-000000000001', 'test', 1, '2026-11-03');

INSERT INTO exams (id, tenant_id, title, exam_date) VALUES
  ('b0000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'Synthetic Exam', '2026-12-01');
INSERT INTO exam_results (id, tenant_id, exam_id, student_id, subject_id, correct) VALUES
  ('b1000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001',
   'b0000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', NULL, 5);

INSERT INTO student_credit_accounts (tenant_id, balance) VALUES
  ('00000000-0000-0000-0000-000000000001', 0),
  ('00000000-0000-0000-0000-000000000002', 0);

INSERT INTO audit_logs (id, scope, tenant_id, action, entity_type) VALUES
  ('e0000000-0000-0000-0000-000000000001', 'tenant', '00000000-0000-0000-0000-000000000001', 'fixture.seed', 'tenant');
DO $$ BEGIN RAISE NOTICE 'PASS fixture: valid positive rows accepted across Phase 2 entities'; END $$;

-- =========================================================== T2-TI tenancy ==
SELECT expect_error('T2-TI-01 cross-tenant counselor reference rejected',
  $q$INSERT INTO counselor_students (id, tenant_id, counselor_id, student_id, status, started_at)
     VALUES (gen_random_uuid(), '00000000-0000-0000-0000-000000000001',
             '10000000-0000-0000-0000-000000000002', '20000000-0000-0000-0000-000000000001', 'paused', now())$q$,
  '23503');

SELECT expect_error('T2-TI-02 enrollment to another tenant program_version rejected',
  $q$INSERT INTO student_program_enrollments (id, tenant_id, student_id, program_version_id)
     VALUES (gen_random_uuid(), '00000000-0000-0000-0000-000000000001',
             '20000000-0000-0000-0000-000000000001', '50000000-0000-0000-0000-000000000002')$q$,
  '23514', 'published');  -- missing-in-tenant version is caught by the enrollment guard before the FK

SELECT expect_error('T2-TI-03 plan_version referencing another tenant program_version rejected',
  $q$INSERT INTO plan_versions (id, tenant_id, plan_id, version_number, program_version_id)
     VALUES (gen_random_uuid(), '00000000-0000-0000-0000-000000000001',
             '60000000-0000-0000-0000-000000000001', 9, '50000000-0000-0000-0000-000000000002')$q$,
  '23503');

SELECT expect_error('T2-TI-04 NULL tenant_id rejected on tenant-owned table',
  $q$INSERT INTO students (id, tenant_id) VALUES (gen_random_uuid(), NULL)$q$, '23502');

SELECT expect_error('T2-TI-05 program_version cannot reference another tenant template',
  $q$INSERT INTO program_versions (id, tenant_id, program_template_id, version_number, payload_json)
     VALUES (gen_random_uuid(), '00000000-0000-0000-0000-000000000001',
             '40000000-0000-0000-0000-000000000002', 9, '{}')$q$, '23503');

SELECT expect_error('T2-TI-06 curriculum parent from another tenant rejected',
  $q$INSERT INTO curriculum_nodes (id, tenant_id, subject_id, parent_id, level, name)
     VALUES (gen_random_uuid(), '00000000-0000-0000-0000-000000000001',
             '30000000-0000-0000-0000-000000000001', '31000000-0000-0000-0000-000000000003', 'book', 'x')$q$,
  '23503');

SELECT expect_error('T2-TI-07 exam_result for another tenant student rejected',
  $q$INSERT INTO exam_results (id, tenant_id, exam_id, student_id, subject_id, correct)
     VALUES (gen_random_uuid(), '00000000-0000-0000-0000-000000000001',
             'b0000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000002', '30000000-0000-0000-0000-000000000001', 1)$q$,
  '23503');

SELECT expect_error('T2-TI-08 credit transaction for tenant without account rejected (owner insert)',
  $q$INSERT INTO credit_transactions (id, tenant_id, amount, kind, idempotency_key, reason)
     VALUES (gen_random_uuid(), '00000000-0000-0000-0000-0000000000ff', 1, 'adjustment', 'ghost-1', 'x')$q$,
  '23503');

-- ========================================================= T2-VER versions ==
SELECT expect_error('T2-VER-01a published payload is immutable',
  $q$UPDATE program_versions SET payload_json = '{"weekly":99}' WHERE id = '50000000-0000-0000-0000-000000000001'$q$,
  '23514', 'content is immutable');

SELECT expect_error('T2-VER-01b published version cannot be deleted',
  $q$DELETE FROM program_versions WHERE id = '50000000-0000-0000-0000-000000000001'$q$,
  '23514', 'cannot be deleted');

SELECT expect_error('T2-VER-01c status-only illegal transition published -> draft (published_at unchanged)',
  $q$UPDATE program_versions SET status = 'draft' WHERE id = '50000000-0000-0000-0000-000000000001'$q$,
  '23514', 'illegal program_version transition');

SELECT expect_error('T2-VER-01d illegal draft -> superseded (skips publication)',
  $q$UPDATE program_versions SET status = 'superseded' WHERE id = '50000000-0000-0000-0000-000000000003'$q$,
  '23514', 'illegal program_version transition');

SELECT expect_error('T2-VER-02a identity mutation of published version (id) rejected',
  $q$UPDATE program_versions SET id = gen_random_uuid() WHERE id = '50000000-0000-0000-0000-000000000001'$q$,
  '23514', 'identity is immutable');

SELECT expect_error('T2-VER-02b identity mutation of draft version (id) rejected',
  $q$UPDATE program_versions SET id = gen_random_uuid() WHERE id = '50000000-0000-0000-0000-000000000003'$q$,
  '23514', 'identity is immutable');

SELECT expect_error('T2-VER-03 tenant reassignment of a version rejected',
  $q$UPDATE program_versions SET tenant_id = '00000000-0000-0000-0000-000000000002' WHERE id = '50000000-0000-0000-0000-000000000003'$q$,
  '23514', 'identity is immutable');

SELECT expect_error('T2-VER-04 template reassignment of a version rejected',
  $q$UPDATE program_versions SET program_template_id = '40000000-0000-0000-0000-000000000002' WHERE id = '50000000-0000-0000-0000-000000000003'$q$,
  '23514', 'identity is immutable');

SELECT expect_error('T2-VER-05 published_at rewrite of a published version rejected',
  $q$UPDATE program_versions SET published_at = now() + interval '1 day' WHERE id = '50000000-0000-0000-0000-000000000001'$q$,
  '23514', 'content is immutable');

SELECT expect_error('T2-VER-06 duplicate version_number for same template rejected',
  $q$INSERT INTO program_versions (id, tenant_id, program_template_id, version_number, payload_json)
     VALUES (gen_random_uuid(), '00000000-0000-0000-0000-000000000001',
             '40000000-0000-0000-0000-000000000001', 2, '{}')$q$, '23505');

SELECT expect_error('T2-VER-07 enrollment to a draft version rejected',
  $q$INSERT INTO student_program_enrollments (id, tenant_id, student_id, program_version_id)
     VALUES (gen_random_uuid(), '00000000-0000-0000-0000-000000000001',
             '20000000-0000-0000-0000-000000000003', '50000000-0000-0000-0000-000000000003')$q$,
  '23514', 'published');

-- program_versions is referenced by FKs, so PostgreSQL rejects TRUNCATE itself (0A000) before any trigger runs.
SELECT expect_error('T2-VER-08 TRUNCATE of program_versions rejected (FK-referenced table)',
  $q$TRUNCATE program_versions$q$, '0A000', 'foreign key');

-- Positive lifecycle transitions (must be accepted)
SELECT expect_ok('T2-VER-09 draft version may be edited while draft',
  $q$UPDATE program_versions SET payload_json = '{"weekly":7}' WHERE id = '50000000-0000-0000-0000-000000000003'$q$);

SELECT expect_ok('T2-VER-10 draft -> published with publisher attribution',
  $q$UPDATE program_versions SET status = 'published', published_by = '90000000-0000-0000-0000-00000000aaaa', published_at = now()
     WHERE id = '50000000-0000-0000-0000-000000000003'$q$);

SELECT expect_ok('T2-VER-11 published -> superseded (status-only)',
  $q$UPDATE program_versions SET status = 'superseded' WHERE id = '50000000-0000-0000-0000-000000000001'$q$);

SELECT expect_error('T2-VER-12 superseded is terminal (superseded -> published rejected)',
  $q$UPDATE program_versions SET status = 'published' WHERE id = '50000000-0000-0000-0000-000000000001'$q$,
  '23514', 'terminal');

SELECT expect_ok('T2-VER-13a draft version (to be deleted) accepted',
  $q$INSERT INTO program_versions (id, tenant_id, program_template_id, version_number, payload_json)
     VALUES ('50000000-0000-0000-0000-000000000009', '00000000-0000-0000-0000-000000000001',
             '40000000-0000-0000-0000-000000000001', 9, '{}')$q$);
SELECT expect_ok('T2-VER-13b draft version may be deleted',
  $q$DELETE FROM program_versions WHERE id = '50000000-0000-0000-0000-000000000009'$q$);

DO $$ BEGIN
  IF (SELECT program_version_id FROM student_program_enrollments WHERE id = '80000000-0000-0000-0000-000000000001')
     <> '50000000-0000-0000-0000-000000000001' THEN
    RAISE EXCEPTION 'FAIL T2-VER-14: enrollment moved when template evolved';
  END IF;
  RAISE NOTICE 'PASS T2-VER-14 enrollment remains pinned to its version after new versions';
END $$;

-- ============================================================ T2-PLAN ==
SELECT expect_error('T2-PLAN-01 plan_version identity/origin change rejected',
  $q$UPDATE plan_versions SET program_version_id = '50000000-0000-0000-0000-000000000003'
     WHERE id = '61000000-0000-0000-0000-000000000001'$q$, '23514', 'identity/origin is immutable');

SELECT expect_ok('T2-PLAN-02 draft plan_version activation accepted',
  $q$UPDATE plan_versions SET activated_at = now() WHERE id = '61000000-0000-0000-0000-000000000001'$q$);

SELECT expect_error('T2-PLAN-03 insert plan_item into activated version rejected',
  $q$INSERT INTO plan_items (id, tenant_id, plan_version_id, activity_type, scheduled_start, scheduled_end)
     VALUES (gen_random_uuid(), '00000000-0000-0000-0000-000000000001', '61000000-0000-0000-0000-000000000001',
             'review', '2026-11-03 08:00+03:30', '2026-11-03 09:00+03:30')$q$, '23514', 'frozen');

SELECT expect_error('T2-PLAN-04 update plan_item of activated version rejected',
  $q$UPDATE plan_items SET scheduled_end = '2026-11-02 10:00+03:30' WHERE id = '62000000-0000-0000-0000-000000000001'$q$,
  '23514', 'frozen');

SELECT expect_error('T2-PLAN-05 delete plan_item of activated version rejected',
  $q$DELETE FROM plan_items WHERE id = '62000000-0000-0000-0000-000000000001'$q$, '23514', 'frozen');

SELECT expect_error('T2-PLAN-06 activation time rewrite rejected',
  $q$UPDATE plan_versions SET activated_at = now() + interval '1 hour' WHERE id = '61000000-0000-0000-0000-000000000001'$q$,
  '23514', 'activation time is immutable');

SELECT expect_error('T2-PLAN-07 delete of activated plan_version rejected',
  $q$DELETE FROM plan_versions WHERE id = '61000000-0000-0000-0000-000000000001'$q$, '23514', 'cannot be deleted');

-- A draft item (its version is not activated) is used so the OWNERSHIP rule is what is tested.
SELECT expect_ok('T2-PLAN-08a draft plan_version with a draft item (fixture)',
  $q$INSERT INTO plan_versions (id, tenant_id, plan_id, version_number) VALUES
     ('61000000-0000-0000-0000-000000000005', '00000000-0000-0000-0000-000000000001',
      '60000000-0000-0000-0000-000000000001', 5)$q$);
SELECT expect_ok('T2-PLAN-08b draft item created under draft version (fixture)',
  $q$INSERT INTO plan_items (id, tenant_id, plan_version_id, activity_type, scheduled_start, scheduled_end) VALUES
     ('62000000-0000-0000-0000-000000000005', '00000000-0000-0000-0000-000000000001',
      '61000000-0000-0000-0000-000000000005', 'review', '2026-11-04 08:00+03:30', '2026-11-04 09:00+03:30')$q$);
SELECT expect_error('T2-PLAN-08 draft item ownership reassignment rejected (identity rule)',
  $q$UPDATE plan_items SET plan_version_id = '61000000-0000-0000-0000-000000000001' WHERE id = '62000000-0000-0000-0000-000000000005'$q$,
  '23514', 'identity/ownership is immutable');

SELECT expect_ok('T2-PLAN-09 supersession set once after activation',
  $q$UPDATE plan_versions SET superseded_at = now() WHERE id = '61000000-0000-0000-0000-000000000001'$q$);

SELECT expect_error('T2-PLAN-10 supersession cannot be rewritten',
  $q$UPDATE plan_versions SET superseded_at = now() + interval '1 hour' WHERE id = '61000000-0000-0000-0000-000000000001'$q$,
  '23514', 'supersession is final');

INSERT INTO plan_versions (id, tenant_id, plan_id, version_number) VALUES
  ('61000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001',
   '60000000-0000-0000-0000-000000000001', 2),
  ('61000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000001',
   '60000000-0000-0000-0000-000000000001', 3);
SELECT expect_ok('T2-PLAN-11 a new version may be activated after the previous is superseded',
  $q$UPDATE plan_versions SET activated_at = now() WHERE id = '61000000-0000-0000-0000-000000000002'$q$);
SELECT expect_error('T2-PLAN-12 second concurrently-active version for a plan rejected',
  $q$UPDATE plan_versions SET activated_at = now() WHERE id = '61000000-0000-0000-0000-000000000003'$q$, '23505');

-- plan_items has no inbound FK, so the statement-level TRIGGER is the guard that fires here.
SELECT expect_error('T2-PLAN-13 TRUNCATE of plan_items rejected by trigger (no inbound FK)',
  $q$TRUNCATE plan_items$q$, '23514', 'forbidden');

-- =============================================================== T2-TEST / ERR / REV / STUDY ==
SELECT expect_ok('T2-TEST-00 test activity for sum-rule test accepted',
  $q$INSERT INTO activities (id, tenant_id, student_id, activity_type, occurred_on)
     VALUES ('90000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000001',
             '20000000-0000-0000-0000-000000000001', 'test', '2026-11-02')$q$);
SELECT expect_error('T2-TEST-01 correct+wrong+unanswered != question_count rejected',
  $q$INSERT INTO test_records (activity_id, tenant_id, question_count, correct, wrong, unanswered)
     VALUES ('90000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000001', 10, 7, 2, 2)$q$, '23514');

SELECT expect_error('T2-TEST-02 test_record cannot attach to a study activity',
  $q$INSERT INTO test_records (activity_id, tenant_id, question_count, correct, wrong, unanswered)
     VALUES ('90000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001', 1, 1, 0, 0)$q$, '23503');

SELECT expect_ok('T2-STUDY-00 study activity accepted',
  $q$INSERT INTO activities (id, tenant_id, student_id, activity_type, occurred_on)
     VALUES ('90000000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000001',
             '20000000-0000-0000-0000-000000000001', 'study', '2026-11-02')$q$);
SELECT expect_error('T2-STUDY-01 study_sessions time order enforced',
  $q$INSERT INTO study_sessions (activity_id, tenant_id, started_at, ended_at)
     VALUES ('90000000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000001',
             '2026-11-02 09:00+03:30', '2026-11-02 08:00+03:30')$q$, '23514');

SELECT expect_error('T2-ERR-01 custom error_type without label rejected',
  $q$INSERT INTO error_records (id, tenant_id, test_activity_id, error_type)
     VALUES (gen_random_uuid(), '00000000-0000-0000-0000-000000000001',
             '90000000-0000-0000-0000-000000000001', 'custom')$q$, '23514');

SELECT expect_error('T2-ERR-02 error_record must reference a test record',
  $q$INSERT INTO error_records (id, tenant_id, test_activity_id, error_type)
     VALUES (gen_random_uuid(), '00000000-0000-0000-0000-000000000001',
             '90000000-0000-0000-0000-000000000002', 'memory')$q$, '23503');

SELECT expect_error('T2-REV-01 duplicate review for same activity and offset rejected',
  $q$INSERT INTO review_schedules (id, tenant_id, original_activity_id, original_type, review_offset_days, review_date)
     VALUES (gen_random_uuid(), '00000000-0000-0000-0000-000000000001',
             '90000000-0000-0000-0000-000000000001', 'test', 1, '2026-11-04')$q$, '23505');

-- ================================================= T2-EXAM / CLASS / ASSIGN ==
SELECT expect_error('T2-EXAM-01 duplicate exam result with NULL subject rejected (NULLS NOT DISTINCT)',
  $q$INSERT INTO exam_results (id, tenant_id, exam_id, student_id, subject_id, correct)
     VALUES (gen_random_uuid(), '00000000-0000-0000-0000-000000000001',
             'b0000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', NULL, 6)$q$, '23505');

SELECT expect_error('T2-CLS-01 class ends before it starts rejected',
  $q$INSERT INTO class_sessions (id, tenant_id, student_id, class_format, starts_at, ends_at)
     VALUES (gen_random_uuid(), '00000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001',
             'online', '2026-11-02 10:00+03:30', '2026-11-02 09:00+03:30')$q$, '23514');

SELECT expect_error('T2-CLS-02 recurring class requires a recurrence rule',
  $q$INSERT INTO class_sessions (id, tenant_id, student_id, class_format, is_recurring, starts_at, ends_at)
     VALUES (gen_random_uuid(), '00000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001',
             'online', true, '2026-11-02 09:00+03:30', '2026-11-02 10:00+03:30')$q$, '23514');

SELECT expect_ok('T2-ASG-01 valid assignment accepted',
  $q$INSERT INTO assignments (id, tenant_id, student_id, title, status)
     VALUES (gen_random_uuid(), '00000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001',
             'Synthetic homework', 'in_progress')$q$);

SELECT expect_error('T2-ASG-02 invalid assignment status rejected',
  $q$INSERT INTO assignments (id, tenant_id, student_id, title, status)
     VALUES (gen_random_uuid(), '00000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001',
             'x', 'done')$q$, '23514');

SELECT expect_error('T2-CURR-01 invalid curriculum level rejected',
  $q$INSERT INTO curriculum_nodes (id, tenant_id, subject_id, level, name)
     VALUES (gen_random_uuid(), '00000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000001', 'unit', 'x')$q$,
  '23514');

-- ================================================================ T2-AUD ==
SELECT expect_ok('T2-AUD-01 platform event with NULL tenant accepted',
  $q$INSERT INTO audit_logs (id, scope, tenant_id, action, entity_type)
     VALUES (gen_random_uuid(), 'platform', NULL, 'platform.note', 'system')$q$);
SELECT expect_error('T2-AUD-02 platform-scope event carrying a tenant rejected',
  $q$INSERT INTO audit_logs (id, scope, tenant_id, action, entity_type)
     VALUES (gen_random_uuid(), 'platform', '00000000-0000-0000-0000-000000000001', 'x', 'y')$q$, '23514');
SELECT expect_error('T2-AUD-03 tenant-scope event without tenant rejected',
  $q$INSERT INTO audit_logs (id, scope, tenant_id, action, entity_type)
     VALUES (gen_random_uuid(), 'tenant', NULL, 'x', 'y')$q$, '23514');
SELECT expect_error('T2-AUD-04 audit row UPDATE rejected',
  $q$UPDATE audit_logs SET action = 'tampered' WHERE id = 'e0000000-0000-0000-0000-000000000001'$q$,
  '23514', 'forbidden');
SELECT expect_error('T2-AUD-05 audit row DELETE rejected',
  $q$DELETE FROM audit_logs WHERE id = 'e0000000-0000-0000-0000-000000000001'$q$, '23514', 'forbidden');

-- ============================================================ T2-CR ledger ==
-- Owner-level direct writes: constraints still apply.
SELECT expect_error('T2-CR-01 zero-amount ledger row rejected (direct)',
  $q$INSERT INTO credit_transactions (id, tenant_id, amount, kind, idempotency_key)
     VALUES (gen_random_uuid(), '00000000-0000-0000-0000-000000000001', 0, 'purchase', 'zero-1')$q$, '23514');
SELECT expect_error('T2-CR-06 negative cached balance rejected (direct owner write)',
  $q$UPDATE student_credit_accounts SET balance = -1 WHERE tenant_id = '00000000-0000-0000-0000-000000000002'$q$, '23514');

-- Atomic write path via the single function.
SELECT expect_ok('T2-CR-07 purchase +5 via post_credit_transaction',
  $q$SELECT post_credit_transaction('00000000-0000-0000-0000-000000000001', 'purchase', 5, NULL, NULL, 'order-1001-paid', NULL, NULL)$q$);

SELECT expect_ok('T2-CR-08 consume -1 for S1 via post_credit_transaction',
  $q$SELECT post_credit_transaction('00000000-0000-0000-0000-000000000001', 'activation_consume', -1,
       '20000000-0000-0000-0000-000000000001', NULL, 'activate-s1', NULL, NULL)$q$);

DO $$ DECLARE v int; BEGIN
  SELECT balance INTO v FROM student_credit_accounts WHERE tenant_id = '00000000-0000-0000-0000-000000000001';
  IF v <> 4 THEN RAISE EXCEPTION 'FAIL T2-CR-08b: balance % expected 4', v; END IF;
  RAISE NOTICE 'PASS T2-CR-08b balance is 4 after purchase 5 and consume 1';
END $$;

-- Idempotent replay: same key, same payload -> same id, no second effect.
DO $$ DECLARE a uuid; b uuid; n int; BEGIN
  a := post_credit_transaction('00000000-0000-0000-0000-000000000001', 'activation_consume', -1,
       '20000000-0000-0000-0000-000000000001', NULL, 'activate-s1', NULL, NULL);
  b := post_credit_transaction('00000000-0000-0000-0000-000000000001', 'activation_consume', -1,
       '20000000-0000-0000-0000-000000000001', NULL, 'activate-s1', NULL, NULL);
  SELECT count(*) INTO n FROM credit_transactions WHERE idempotency_key = 'activate-s1';
  IF a <> b OR n <> 1 THEN RAISE EXCEPTION 'FAIL T2-CR-09: replay not idempotent (ids %, %; rows %)', a, b, n; END IF;
  IF (SELECT balance FROM student_credit_accounts WHERE tenant_id = '00000000-0000-0000-0000-000000000001') <> 4
  THEN RAISE EXCEPTION 'FAIL T2-CR-09: replay changed balance'; END IF;
  RAISE NOTICE 'PASS T2-CR-09 idempotent replay returns same id; single effect';
END $$;

SELECT expect_error('T2-CR-10 same key with different payload rejected',
  $q$SELECT post_credit_transaction('00000000-0000-0000-0000-000000000001', 'activation_consume', -2,
       '20000000-0000-0000-0000-000000000001', NULL, 'activate-s1', NULL, NULL)$q$, '23505', 'different canonical payload');

SELECT expect_error('T2-CR-11 overspend rejected by function (insufficient credit)',
  $q$SELECT post_credit_transaction('00000000-0000-0000-0000-000000000001', 'activation_consume', -10,
       '20000000-0000-0000-0000-000000000003', NULL, 'activate-big', NULL, NULL)$q$, '23514', 'insufficient credit');

DO $$ DECLARE v int; BEGIN
  SELECT balance INTO v FROM student_credit_accounts WHERE tenant_id = '00000000-0000-0000-0000-000000000001';
  IF v <> 4 THEN RAISE EXCEPTION 'FAIL T2-CR-11b: rejected overspend changed balance to %', v; END IF;
  RAISE NOTICE 'PASS T2-CR-11b rejected overspend left balance unchanged';
END $$;

-- T2-CR-03 activation rollback: a failure after the credit write rolls the credit back.
DO $$ DECLARE vb int; va int; nb bigint; na bigint; BEGIN
  SELECT balance INTO vb FROM student_credit_accounts WHERE tenant_id = '00000000-0000-0000-0000-000000000001';
  SELECT count(*) INTO nb FROM credit_transactions WHERE tenant_id = '00000000-0000-0000-0000-000000000001';
  BEGIN
    PERFORM post_credit_transaction('00000000-0000-0000-0000-000000000001', 'activation_consume', -1,
            '20000000-0000-0000-0000-000000000003', NULL, 'activate-s3-rollback', NULL, NULL);
    RAISE EXCEPTION 'simulated student-insert failure after credit write';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'simulated student-insert failure after credit write' THEN RAISE; END IF;
  END;
  SELECT balance INTO va FROM student_credit_accounts WHERE tenant_id = '00000000-0000-0000-0000-000000000001';
  SELECT count(*) INTO na FROM credit_transactions WHERE tenant_id = '00000000-0000-0000-0000-000000000001';
  IF va <> vb OR na <> nb THEN RAISE EXCEPTION 'FAIL T2-CR-03: rollback left balance % (was %) rows % (was %)', va, vb, na, nb; END IF;
  RAISE NOTICE 'PASS T2-CR-03 activation rollback restored balance and ledger';
END $$;

-- T2-CR-05 deterministic reconciliation run: many random operations, drift must stay 0.
SELECT setseed(0.42);
DO $$ DECLARE i int; amt int; k text; BEGIN
  FOR i IN 1..60 LOOP
    amt := (floor(random() * 6) + 1)::int;
    k := 'prop-' || i;
    BEGIN
      IF random() < 0.5 THEN
        PERFORM post_credit_transaction('00000000-0000-0000-0000-000000000001', 'purchase', amt, NULL, NULL, k, NULL, NULL);
      ELSE
        PERFORM post_credit_transaction('00000000-0000-0000-0000-000000000001', 'activation_consume', -amt,
                '20000000-0000-0000-0000-000000000003', NULL, k, NULL, NULL);
      END IF;
    EXCEPTION WHEN check_violation THEN NULL;   -- insufficient credit is an expected outcome
    END;
  END LOOP;
END $$;
DO $$ DECLARE d int; BEGIN
  SELECT drift INTO d FROM credit_reconciliation WHERE tenant_id = '00000000-0000-0000-0000-000000000001';
  IF d <> 0 THEN RAISE EXCEPTION 'FAIL T2-CR-05: drift % after random operations', d; END IF;
  RAISE NOTICE 'PASS T2-CR-05 reconciliation drift = 0 after 60 randomized operations (seed 0.42)';
END $$;

-- Detection (not prevention) of owner-level tampering: probe then roll back.
DO $$ DECLARE d int; BEGIN
  UPDATE student_credit_accounts SET balance = balance + 100 WHERE tenant_id = '00000000-0000-0000-0000-000000000001';
  SELECT drift INTO d FROM credit_reconciliation WHERE tenant_id = '00000000-0000-0000-0000-000000000001';
  IF d <> 100 THEN RAISE EXCEPTION 'FAIL T2-CR-12: reconciliation did not detect owner-level tamper (drift %)', d; END IF;
  RAISE EXCEPTION 'probe rollback';
EXCEPTION WHEN raise_exception THEN
  IF SQLERRM <> 'probe rollback' THEN RAISE; END IF;
  RAISE NOTICE 'PASS T2-CR-12 reconciliation detects owner-level balance tampering (probe rolled back)';
END $$;
DO $$ DECLARE d int; BEGIN
  SELECT drift INTO d FROM credit_reconciliation WHERE tenant_id = '00000000-0000-0000-0000-000000000001';
  IF d <> 0 THEN RAISE EXCEPTION 'FAIL T2-CR-12b: probe not rolled back, drift %', d; END IF;
  RAISE NOTICE 'PASS T2-CR-12b probe fully rolled back (drift 0)';
END $$;

SELECT expect_error('T2-CR-13 owner-level TRUNCATE of credit_transactions rejected by trigger',
  $q$TRUNCATE credit_transactions$q$, '23514', 'forbidden');
SELECT expect_error('T2-AUD-06 owner-level TRUNCATE of audit_logs rejected by trigger',
  $q$TRUNCATE audit_logs$q$, '23514', 'forbidden');

-- ==================================== T2-AUTHZ / R01 authorization matrix ==
-- Identity is switched with SET SESSION AUTHORIZATION; the function reads session_user.
-- Baseline funding by the trusted owner (purchase path) so runtime consumes can succeed.
SELECT post_credit_transaction('00000000-0000-0000-0000-000000000001', 'purchase', 10, NULL,
       '70000000-0000-0000-0000-0000000000a1', 'r00-fund', '90000000-0000-0000-0000-00000000aaaa', 'baseline');

SET SESSION AUTHORIZATION app_t1;
SELECT expect_ok('T2-R01-01 app_t1 consumes credit for its own tenant (authorized)',
  $q$SELECT post_credit_transaction('00000000-0000-0000-0000-000000000001', 'activation_consume', -1,
       '20000000-0000-0000-0000-000000000003', NULL, 'r01-app-consume', NULL, NULL)$q$);
SELECT expect_error('T2-R01-02 app_t1 cannot issue purchase credit (no purchase path)',
  $q$SELECT post_credit_transaction('00000000-0000-0000-0000-000000000001', 'purchase', 100, NULL, NULL,
       'r01-app-purchase', NULL, NULL)$q$, '42501', 'may not perform purchase');
SELECT expect_error('T2-R01-03 app_t1 cannot issue a refund',
  $q$SELECT post_credit_transaction('00000000-0000-0000-0000-000000000001', 'refund', 5, NULL,
       '70000000-0000-0000-0000-0000000000a1', 'r01-app-refund', NULL, 'x')$q$, '42501', 'may not perform refund');
SELECT expect_error('T2-R01-04 app_t1 cannot post an adjustment (even with a reason)',
  $q$SELECT post_credit_transaction('00000000-0000-0000-0000-000000000001', 'adjustment', 50, NULL, NULL,
       'r01-app-adjust', NULL, 'self-granted')$q$, '42501', 'may not perform adjustment');
SELECT expect_error('T2-R01-05 app_t1 cannot release a cancellation credit',
  $q$SELECT post_credit_transaction('00000000-0000-0000-0000-000000000001', 'cancellation_release', 1, NULL,
       NULL, 'r01-app-cancel', NULL, NULL)$q$, '42501', 'may not perform cancellation_release');
SELECT expect_error('T2-R01-06 app_t1 cannot operate on tenant 2 by substituting tenant_id',
  $q$SELECT post_credit_transaction('00000000-0000-0000-0000-000000000002', 'activation_consume', -1,
       NULL, NULL, 'r01-substitute', NULL, NULL)$q$, '42501', 'is not bound to tenant');
SELECT expect_error('T2-R01-07 app_t1 cannot write ledger rows by direct INSERT',
  $q$INSERT INTO credit_transactions (id, tenant_id, amount, kind, idempotency_key, reason)
     VALUES (gen_random_uuid(), '00000000-0000-0000-0000-000000000001', 1000, 'adjustment', 'r01-direct', 'x')$q$, '42501');
SELECT expect_error('T2-R01-08 app_t1 cannot set the cached balance directly',
  $q$UPDATE student_credit_accounts SET balance = 999999 WHERE tenant_id = '00000000-0000-0000-0000-000000000001'$q$, '42501');
SELECT expect_error('T2-R01-09 app_t1 cannot read the ledger (no cross-tenant read by grant)',
  $q$SELECT count(*) FROM credit_transactions$q$, '42501');
SELECT expect_error('T2-R01-10 app_t1 cannot read the reconciliation view (all tenants)',
  $q$SELECT drift FROM credit_reconciliation$q$, '42501');
SELECT expect_error('T2-R01-11 app_t1 cannot self-grant a purchase permission',
  $q$INSERT INTO credit_role_permissions (role_name, kind) VALUES ('app_t1', 'purchase')$q$, '42501');
SELECT expect_error('T2-R01-12 app_t1 cannot self-bind to tenant 2',
  $q$INSERT INTO tenant_role_bindings (role_name, tenant_id) VALUES ('app_t1', '00000000-0000-0000-0000-000000000002')$q$, '42501');
RESET SESSION AUTHORIZATION;

SET SESSION AUTHORIZATION app_t2;
SELECT expect_error('T2-R01-13 app_t2 cannot consume tenant 1 credit (not bound)',
  $q$SELECT post_credit_transaction('00000000-0000-0000-0000-000000000001', 'activation_consume', -1,
       NULL, NULL, 'r01-t2-on-t1', NULL, NULL)$q$, '42501', 'is not bound to tenant');
RESET SESSION AUTHORIZATION;

SET SESSION AUTHORIZATION issuer_rt;
SELECT expect_ok('T2-R01-14 issuer_rt issues purchase credit on its bound tenant (authorized path)',
  $q$SELECT post_credit_transaction('00000000-0000-0000-0000-000000000001', 'purchase', 2, NULL,
       '70000000-0000-0000-0000-0000000000a2', 'r01-issuer-purchase', NULL, 'verified-payment-stub')$q$);
SELECT expect_error('T2-R01-15 issuer_rt cannot consume credit (wrong operation)',
  $q$SELECT post_credit_transaction('00000000-0000-0000-0000-000000000001', 'activation_consume', -1,
       NULL, NULL, 'r01-issuer-consume', NULL, NULL)$q$, '42501', 'may not perform activation_consume');
RESET SESSION AUTHORIZATION;

SET SESSION AUTHORIZATION adjuster_rt;
SELECT expect_ok('T2-R01-16 adjuster_rt posts an adjustment with reason (authorized path)',
  $q$SELECT post_credit_transaction('00000000-0000-0000-0000-000000000001', 'adjustment', 1, NULL, NULL,
       'r01-adjuster-adjust', NULL, 'synthetic correction')$q$);
SELECT expect_error('T2-R01-17 adjuster_rt cannot issue purchase credit',
  $q$SELECT post_credit_transaction('00000000-0000-0000-0000-000000000001', 'purchase', 1, NULL, NULL,
       'r01-adjuster-purchase', NULL, NULL)$q$, '42501', 'may not perform purchase');
RESET SESSION AUTHORIZATION;

SET SESSION AUTHORIZATION nogrant_rt;
SELECT expect_error('T2-R01-18 role without EXECUTE grant is denied (default-deny)',
  $q$SELECT post_credit_transaction('00000000-0000-0000-0000-000000000001', 'activation_consume', -1,
       NULL, NULL, 'r01-nogrant', NULL, NULL)$q$, '42501', 'permission denied for function');
RESET SESSION AUTHORIZATION;

-- ----------------------------------------- R03 SECURITY DEFINER hardening ----
DO $$ BEGIN
  IF has_function_privilege('public', 'post_credit_transaction(uuid,text,integer,uuid,uuid,text,uuid,text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'FAIL T2-R03-01: PUBLIC has EXECUTE on post_credit_transaction';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname IN ('app_t1','app_t2','issuer_rt','adjuster_rt','nogrant_rt') AND rolsuper) THEN
    RAISE EXCEPTION 'FAIL T2-R03-01b: a runtime role is a superuser';
  END IF;
  RAISE NOTICE 'PASS T2-R03-01 PUBLIC has no EXECUTE; runtime roles are not superusers';
END $$;

SET SESSION AUTHORIZATION app_t1;
SELECT expect_error('T2-R03-02 app_t1 cannot create a schema (no database CREATE)',
  $q$CREATE SCHEMA r03_attacker$q$, '42501');
SELECT expect_error('T2-R03-03 app_t1 cannot create objects in public',
  $q$CREATE FUNCTION public.r03_evil() RETURNS int LANGUAGE sql AS $f$ SELECT 1 $f$$q$, '42501');
SELECT expect_error('T2-R03-04 app_t1 cannot replace the credit function',
  $q$CREATE OR REPLACE FUNCTION public.post_credit_transaction(uuid,text,integer,uuid,uuid,text,uuid,text)
     RETURNS uuid LANGUAGE sql AS $f$ SELECT gen_random_uuid() $f$$q$, '42501');
SELECT expect_error('T2-R03-05 app_t1 cannot alter a credit table',
  $q$ALTER TABLE student_credit_accounts ADD COLUMN r03_x int$q$, '42501');
SELECT expect_error('T2-R03-06 app_t1 cannot drop the authorization table',
  $q$DROP TABLE tenant_role_bindings$q$, '42501');
RESET SESSION AUTHORIZATION;

-- Hostile object resolution: a schema placed FIRST on the caller's search_path holds a
-- fake gen_random_uuid() and a fake ledger/account table. The pinned, qualified function must ignore both.
CREATE SCHEMA hostile;
CREATE FUNCTION hostile.gen_random_uuid() RETURNS uuid LANGUAGE sql AS $f$ SELECT '99999999-9999-9999-9999-999999999999'::uuid $f$;
CREATE TABLE hostile.student_credit_accounts (tenant_id uuid, balance int, version int, updated_at timestamptz);
INSERT INTO hostile.student_credit_accounts VALUES ('00000000-0000-0000-0000-000000000001', 1000000, 0, now());
GRANT USAGE ON SCHEMA hostile TO app_t1;
GRANT EXECUTE ON FUNCTION hostile.gen_random_uuid() TO app_t1;

SET SESSION AUTHORIZATION app_t1;
SET search_path = hostile, public;
DO $$ DECLARE v_id uuid; BEGIN
  v_id := post_credit_transaction('00000000-0000-0000-0000-000000000001', 'activation_consume', -1,
            '20000000-0000-0000-0000-000000000003', NULL, 'r03-hostile-path', NULL, NULL);
  IF v_id = '99999999-9999-9999-9999-999999999999' THEN
    RAISE EXCEPTION 'FAIL T2-R03-07: hostile gen_random_uuid() was resolved by the definer function';
  END IF;
  RAISE NOTICE 'PASS T2-R03-07 hostile search_path did not redirect the definer function (id is not the hostile constant)';
END $$;
RESET search_path;
RESET SESSION AUTHORIZATION;

DO $$ DECLARE hb int; pb int; BEGIN
  SELECT balance INTO hb FROM hostile.student_credit_accounts WHERE tenant_id = '00000000-0000-0000-0000-000000000001';
  SELECT balance INTO pb FROM public.student_credit_accounts WHERE tenant_id = '00000000-0000-0000-0000-000000000001';
  IF hb <> 1000000 THEN RAISE EXCEPTION 'FAIL T2-R03-08: hostile table was modified (%)', hb; END IF;
  RAISE NOTICE 'PASS T2-R03-08 hostile table untouched; public balance is % (authorized consume applied)', pb;
END $$;

-- ================================================ R02 idempotency payload ==
-- Base canonical payload, then one mutation per field. Every mutated replay must be
-- rejected with unique_violation and leave no second ledger row or balance change.
DO $$ DECLARE v_base uuid; BEGIN
  v_base := post_credit_transaction('00000000-0000-0000-0000-000000000001', 'purchase', 1,
            NULL, '70000000-0000-0000-0000-0000000000b1', 'r02-key', '90000000-0000-0000-0000-00000000aaaa', 'base');
  IF post_credit_transaction('00000000-0000-0000-0000-000000000001', 'purchase', 1,
       NULL, '70000000-0000-0000-0000-0000000000b1', 'r02-key', '90000000-0000-0000-0000-00000000aaaa', 'base') <> v_base
  THEN RAISE EXCEPTION 'FAIL T2-R02-00: identical canonical replay returned a different id'; END IF;
  IF (SELECT count(*) FROM credit_transactions WHERE idempotency_key = 'r02-key') <> 1
  THEN RAISE EXCEPTION 'FAIL T2-R02-00b: identical replay created a second ledger row'; END IF;
  RAISE NOTICE 'PASS T2-R02-00 identical canonical payload replays to the same id with one effect';
END $$;

SELECT expect_error('T2-R02-01 differing kind rejected',
  $q$SELECT post_credit_transaction('00000000-0000-0000-0000-000000000001', 'adjustment', 1, NULL,
       '70000000-0000-0000-0000-0000000000b1', 'r02-key', '90000000-0000-0000-0000-00000000aaaa', 'base')$q$,
  '23505', 'different canonical payload');
SELECT expect_error('T2-R02-02 differing amount rejected',
  $q$SELECT post_credit_transaction('00000000-0000-0000-0000-000000000001', 'purchase', 2, NULL,
       '70000000-0000-0000-0000-0000000000b1', 'r02-key', '90000000-0000-0000-0000-00000000aaaa', 'base')$q$,
  '23505', 'different canonical payload');
SELECT expect_error('T2-R02-03 differing student_id rejected (NULL vs value)',
  $q$SELECT post_credit_transaction('00000000-0000-0000-0000-000000000001', 'purchase', 1,
       '20000000-0000-0000-0000-000000000003', '70000000-0000-0000-0000-0000000000b1', 'r02-key',
       '90000000-0000-0000-0000-00000000aaaa', 'base')$q$, '23505', 'different canonical payload');
SELECT expect_error('T2-R02-04 differing order_id rejected',
  $q$SELECT post_credit_transaction('00000000-0000-0000-0000-000000000001', 'purchase', 1, NULL,
       '70000000-0000-0000-0000-0000000000b2', 'r02-key', '90000000-0000-0000-0000-00000000aaaa', 'base')$q$,
  '23505', 'different canonical payload');
SELECT expect_error('T2-R02-05 differing actor_id rejected',
  $q$SELECT post_credit_transaction('00000000-0000-0000-0000-000000000001', 'purchase', 1, NULL,
       '70000000-0000-0000-0000-0000000000b1', 'r02-key', '90000000-0000-0000-0000-00000000bbbb', 'base')$q$,
  '23505', 'different canonical payload');
SELECT expect_error('T2-R02-06 differing reason rejected',
  $q$SELECT post_credit_transaction('00000000-0000-0000-0000-000000000001', 'purchase', 1, NULL,
       '70000000-0000-0000-0000-0000000000b1', 'r02-key', '90000000-0000-0000-0000-00000000aaaa', 'other')$q$,
  '23505', 'different canonical payload');
SELECT expect_error('T2-R02-07 actor NULL vs value rejected (NULL-safe comparison)',
  $q$SELECT post_credit_transaction('00000000-0000-0000-0000-000000000001', 'purchase', 1, NULL,
       '70000000-0000-0000-0000-0000000000b1', 'r02-key', NULL, 'base')$q$,
  '23505', 'different canonical payload');

DO $$ DECLARE n int; BEGIN
  SELECT count(*) INTO n FROM credit_transactions WHERE idempotency_key = 'r02-key';
  IF n <> 1 THEN RAISE EXCEPTION 'FAIL T2-R02-08: rejected replays left % rows', n; END IF;
  RAISE NOTICE 'PASS T2-R02-08 seven rejected replays left exactly one ledger row';
END $$;

DO $$ BEGIN RAISE NOTICE '=== PHASE 2 CONSTRAINT SUITE v3 COMPLETED (synthetic data) ==='; END $$;
