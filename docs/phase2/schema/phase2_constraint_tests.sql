-- =============================================================================
-- PHASE 2 — CONSTRAINT TESTS (executable against phase2_schema_draft.sql)
-- Synthetic data only (D-014). Each negative test asserts the exact SQLSTATE.
-- Run inside a throwaway database. Any failure aborts the run (ON_ERROR_STOP).
-- =============================================================================
\set ON_ERROR_STOP on

-- Helper: expect a statement to fail with a specific SQLSTATE.
CREATE OR REPLACE FUNCTION expect_error(label text, stmt text, want text)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    EXECUTE stmt;
    RAISE EXCEPTION 'FAIL %: statement succeeded, expected SQLSTATE %', label, want;
EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = want THEN
        RAISE NOTICE 'PASS %  (SQLSTATE %)', label, SQLSTATE;
    ELSE
        RAISE EXCEPTION 'FAIL %: got SQLSTATE % (%), expected %', label, SQLSTATE, SQLERRM, want;
    END IF;
END;
$$;

-- ----------------------------------------------------------- fixtures -------
INSERT INTO tenants (id, status) VALUES
  ('00000000-0000-0000-0000-000000000001', 'active'),
  ('00000000-0000-0000-0000-000000000002', 'active');

INSERT INTO counselors (id, tenant_id, display_name) VALUES
  ('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'Synthetic Counselor A'),
  ('10000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000002', 'Synthetic Counselor B');

INSERT INTO students (id, tenant_id) VALUES
  ('20000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001'),
  ('20000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000002');

INSERT INTO subjects (id, tenant_id, name) VALUES
  ('30000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'Synthetic Math'),
  ('30000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000002', 'Synthetic Math');

INSERT INTO program_templates (id, tenant_id, name) VALUES
  ('40000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'Synthetic Template A'),
  ('40000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000002', 'Synthetic Template B');

INSERT INTO program_versions (id, tenant_id, program_template_id, version_number, status, payload, published_at) VALUES
  ('50000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001',
   '40000000-0000-0000-0000-000000000001', 1, 'published', '{"weekly":5}', now()),
  ('50000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000002',
   '40000000-0000-0000-0000-000000000002', 1, 'published', '{"weekly":4}', now());

INSERT INTO plans (id, tenant_id, student_id, scope, period_start, period_end) VALUES
  ('60000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001',
   '20000000-0000-0000-0000-000000000001', 'weekly', '2026-11-01', '2026-11-07');

INSERT INTO plan_versions (id, tenant_id, plan_id, version_number, activated_at) VALUES
  ('61000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001',
   '60000000-0000-0000-0000-000000000001', 1, now());

INSERT INTO student_credit_accounts (tenant_id, balance) VALUES
  ('00000000-0000-0000-0000-000000000001', 0),
  ('00000000-0000-0000-0000-000000000002', 0);

-- Positive baseline: valid rows are accepted.
INSERT INTO counselor_students (id, tenant_id, counselor_id, student_id, status, started_at)
VALUES ('70000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001',
        '10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001',
        'active', now());
DO $$ BEGIN RAISE NOTICE 'PASS positive baseline: valid counselor_students row accepted'; END $$;
-- ------------------------------------------------------ T2-TI tenancy -------
SELECT expect_error('T2-TI-01 cross-tenant counselor reference rejected',
  $q$INSERT INTO counselor_students (id, tenant_id, counselor_id, student_id, status, started_at)
     VALUES (gen_random_uuid(), '00000000-0000-0000-0000-000000000001',
             '10000000-0000-0000-0000-000000000002', '20000000-0000-0000-0000-000000000001',
             'paused', now())$q$, '23503');

SELECT expect_error('T2-TI-02 enrollment referencing another tenant program_version rejected',
  $q$INSERT INTO student_program_enrollments (id, tenant_id, student_id, program_version_id)
     VALUES (gen_random_uuid(), '00000000-0000-0000-0000-000000000001',
             '20000000-0000-0000-0000-000000000001', '50000000-0000-0000-0000-000000000002')$q$, '23503');

SELECT expect_error('T2-TI-03 plan_version referencing another tenant program_version rejected',
  $q$INSERT INTO plan_versions (id, tenant_id, plan_id, version_number, program_version_id)
     VALUES (gen_random_uuid(), '00000000-0000-0000-0000-000000000001',
             '60000000-0000-0000-0000-000000000001', 2, '50000000-0000-0000-0000-000000000002')$q$, '23503');

SELECT expect_error('T2-TI-04 NULL tenant_id rejected on tenant-owned table',
  $q$INSERT INTO students (id, tenant_id) VALUES (gen_random_uuid(), NULL)$q$, '23502');

SELECT expect_error('T2-TI-05 program_template cannot reference another tenant (composite FK)',
  $q$INSERT INTO program_versions (id, tenant_id, program_template_id, version_number, status, payload, published_at)
     VALUES (gen_random_uuid(), '00000000-0000-0000-0000-000000000001',
             '40000000-0000-0000-0000-000000000002', 9, 'draft', '{}', NULL)$q$, '23503');

-- ---------------------------------------------- T2-VER versioning -----------
SELECT expect_error('T2-VER-01 published program_version payload is immutable',
  $q$UPDATE program_versions SET payload = '{"weekly":99}'
     WHERE id = '50000000-0000-0000-0000-000000000001'$q$, '23514');

SELECT expect_error('T2-VER-01b published program_version cannot be deleted',
  $q$DELETE FROM program_versions WHERE id = '50000000-0000-0000-0000-000000000001'$q$, '23514');

SELECT expect_error('T2-VER-01c illegal status transition published -> draft',
  $q$UPDATE program_versions SET status = 'draft', published_at = NULL
     WHERE id = '50000000-0000-0000-0000-000000000001'$q$, '23514');

SELECT expect_error('T2-VER-02 duplicate version_number for same template rejected',
  $q$INSERT INTO program_versions (id, tenant_id, program_template_id, version_number, status, payload, published_at)
     VALUES (gen_random_uuid(), '00000000-0000-0000-0000-000000000001',
             '40000000-0000-0000-0000-000000000001', 1, 'draft', '{}', NULL)$q$, '23505');

-- T2-VER-03: a new draft version does not alter an existing enrollment.
INSERT INTO student_program_enrollments (id, tenant_id, student_id, program_version_id)
VALUES ('80000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001',
        '20000000-0000-0000-0000-000000000001', '50000000-0000-0000-0000-000000000001');
INSERT INTO program_versions (id, tenant_id, program_template_id, version_number, status, payload)
VALUES ('50000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-000000000001',
        '40000000-0000-0000-0000-000000000001', 2, 'draft', '{"weekly":6}');
DO $$ BEGIN
  IF (SELECT program_version_id FROM student_program_enrollments
      WHERE id = '80000000-0000-0000-0000-000000000001')
     <> '50000000-0000-0000-0000-000000000001' THEN
    RAISE EXCEPTION 'FAIL T2-VER-03: enrollment changed when a new draft version was created';
  END IF;
  RAISE NOTICE 'PASS T2-VER-03 enrollment pinned to its version after new draft';
END $$;

-- Draft may be edited and then published; published is then superseded by status only.
UPDATE program_versions SET payload = '{"weekly":6,"note":"draft edit"}'
 WHERE id = '50000000-0000-0000-0000-00000000000a';
UPDATE program_versions SET status = 'published', published_at = now()
 WHERE id = '50000000-0000-0000-0000-00000000000a';
UPDATE program_versions SET status = 'superseded'
 WHERE id = '50000000-0000-0000-0000-000000000001';
DO $$ BEGIN RAISE NOTICE 'PASS draft->published->superseded lifecycle accepted'; END $$;
-- T2-VER-04: at most one active plan version.
SELECT expect_error('T2-VER-04 second active plan_version for same plan rejected',
  $q$INSERT INTO plan_versions (id, tenant_id, plan_id, version_number, activated_at)
     VALUES (gen_random_uuid(), '00000000-0000-0000-0000-000000000001',
             '60000000-0000-0000-0000-000000000001', 2, now())$q$, '23505');

SELECT expect_error('plan_version superseded before activated rejected',
  $q$INSERT INTO plan_versions (id, tenant_id, plan_id, version_number, superseded_at)
     VALUES (gen_random_uuid(), '00000000-0000-0000-0000-000000000001',
             '60000000-0000-0000-0000-000000000001', 3, now())$q$, '23514');

SELECT expect_error('plan period_end before period_start rejected',
  $q$INSERT INTO plans (id, tenant_id, student_id, scope, period_start, period_end)
     VALUES (gen_random_uuid(), '00000000-0000-0000-0000-000000000001',
             '20000000-0000-0000-0000-000000000001', 'daily', '2026-11-07', '2026-11-01')$q$, '23514');

-- ---------------------------------------------- T2-REV / T2-TEST records ----
INSERT INTO activities (id, tenant_id, student_id, activity_type, occurred_on)
VALUES ('90000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001',
        '20000000-0000-0000-0000-000000000001', 'test', '2026-11-02');

INSERT INTO test_records (activity_id, tenant_id, question_count, correct, wrong, unanswered)
VALUES ('90000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 10, 7, 2, 1);
DO $$ BEGIN RAISE NOTICE 'PASS T2-TEST positive: 7+2+1=10 accepted'; END $$;
INSERT INTO activities (id, tenant_id, student_id, activity_type, occurred_on)
VALUES ('90000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001',
        '20000000-0000-0000-0000-000000000001', 'test', '2026-11-02');

SELECT expect_error('T2-TEST-01 correct+wrong+unanswered != question_count rejected',
  $q$INSERT INTO test_records (activity_id, tenant_id, question_count, correct, wrong, unanswered)
     VALUES ('90000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001', 10, 7, 2, 2)$q$, '23514');

INSERT INTO activities (id, tenant_id, student_id, activity_type, occurred_on)
VALUES ('90000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000001',
        '20000000-0000-0000-0000-000000000001', 'study', '2026-11-02');

SELECT expect_error('test_record cannot attach to a non-test activity (type-key FK)',
  $q$INSERT INTO test_records (activity_id, tenant_id, question_count, correct, wrong, unanswered)
     VALUES ('90000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000001', 1, 1, 0, 0)$q$, '23503');

INSERT INTO review_schedules (id, tenant_id, original_activity_id, original_type, review_offset_days, review_date)
VALUES ('91000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001',
        '90000000-0000-0000-0000-000000000001', 'test', 1, '2026-11-03');

SELECT expect_error('T2-REV-01 duplicate review for same activity and offset rejected',
  $q$INSERT INTO review_schedules (id, tenant_id, original_activity_id, original_type, review_offset_days, review_date)
     VALUES (gen_random_uuid(), '00000000-0000-0000-0000-000000000001',
             '90000000-0000-0000-0000-000000000001', 'test', 1, '2026-11-04')$q$, '23505');

-- ------------------------------------------------ T2-CR credit ledger -------
-- Positive: purchase +10, activation_consume -1, balance cache updated in the same transaction.
INSERT INTO credit_transactions (id, tenant_id, amount, kind, idempotency_key, reason)
VALUES ('a0000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001',
        10, 'purchase', 'order-1001-paid', NULL);
UPDATE student_credit_accounts SET balance = balance + 10, version = version + 1
 WHERE tenant_id = '00000000-0000-0000-0000-000000000001';

INSERT INTO credit_transactions (id, tenant_id, amount, kind, student_id, idempotency_key)
VALUES ('a0000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001',
        -1, 'activation_consume', '20000000-0000-0000-0000-000000000001', 'activate-s1');
UPDATE student_credit_accounts SET balance = balance - 1, version = version + 1
 WHERE tenant_id = '00000000-0000-0000-0000-000000000001';

-- T2-CR-05 (single-case form): balance equals ledger sum.
DO $$ DECLARE cache int; ledger int; BEGIN
  SELECT balance INTO cache FROM student_credit_accounts WHERE tenant_id = '00000000-0000-0000-0000-000000000001';
  SELECT COALESCE(SUM(amount),0) INTO ledger FROM credit_transactions WHERE tenant_id = '00000000-0000-0000-0000-000000000001';
  IF cache <> ledger THEN RAISE EXCEPTION 'FAIL T2-CR-05: cache % <> ledger %', cache, ledger; END IF;
  RAISE NOTICE 'PASS T2-CR-05 balance (%) equals ledger sum (%)', cache, ledger;
END $$;

SELECT expect_error('T2-CR-02 duplicate idempotency_key rejected',
  $q$INSERT INTO credit_transactions (id, tenant_id, amount, kind, idempotency_key, reason)
     VALUES (gen_random_uuid(), '00000000-0000-0000-0000-000000000001', 10, 'purchase', 'order-1001-paid', NULL)$q$, '23505');

SELECT expect_error('T2-CR-01 zero-amount ledger row rejected',
  $q$INSERT INTO credit_transactions (id, tenant_id, amount, kind, idempotency_key)
     VALUES (gen_random_uuid(), '00000000-0000-0000-0000-000000000001', 0, 'purchase', 'zero-1')$q$, '23514');

SELECT expect_error('sign rule: activation_consume with positive amount rejected',
  $q$INSERT INTO credit_transactions (id, tenant_id, amount, kind, student_id, idempotency_key)
     VALUES (gen_random_uuid(), '00000000-0000-0000-0000-000000000001', 1, 'activation_consume',
             '20000000-0000-0000-0000-000000000001', 'bad-sign-1')$q$, '23514');

SELECT expect_error('sign rule: adjustment without reason rejected',
  $q$INSERT INTO credit_transactions (id, tenant_id, amount, kind, idempotency_key)
     VALUES (gen_random_uuid(), '00000000-0000-0000-0000-000000000001', 1, 'adjustment', 'adj-noreason-1')$q$, '23514');

SELECT expect_error('T2-CR-06 negative balance rejected at DB level',
  $q$UPDATE student_credit_accounts SET balance = -1
     WHERE tenant_id = '00000000-0000-0000-0000-000000000002'$q$, '23514');

SELECT expect_error('T2-CR-07 ledger UPDATE rejected (append-only trigger)',
  $q$UPDATE credit_transactions SET amount = 999 WHERE id = 'a0000000-0000-0000-0000-000000000001'$q$, '23514');

SELECT expect_error('T2-CR-07b ledger DELETE rejected (append-only trigger)',
  $q$DELETE FROM credit_transactions WHERE id = 'a0000000-0000-0000-0000-000000000001'$q$, '23514');

INSERT INTO audit_logs (id, tenant_id, action, entity_type)
VALUES ('b0000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'test.create', 'x');

SELECT expect_error('T2-CR-07c audit_logs UPDATE rejected (append-only trigger)',
  $q$UPDATE audit_logs SET action = 'tampered' WHERE id = 'b0000000-0000-0000-0000-000000000001'$q$, '23514');

SELECT expect_error('T2-CR-07f audit_logs DELETE rejected (append-only trigger)',
  $q$DELETE FROM audit_logs WHERE id = 'b0000000-0000-0000-0000-000000000001'$q$, '23514');

-- Role-level grants: a runtime role with INSERT/SELECT only cannot UPDATE or DELETE.
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_rt') THEN
    CREATE ROLE app_rt NOLOGIN;
  END IF;
END $$;
GRANT USAGE ON SCHEMA public TO app_rt;
GRANT SELECT, INSERT ON credit_transactions TO app_rt;
GRANT SELECT, INSERT, UPDATE ON student_credit_accounts TO app_rt;

SET ROLE app_rt;
SELECT expect_error('T2-CR-07d app role without UPDATE grant cannot update ledger',
  $q$UPDATE credit_transactions SET amount = 5 WHERE id = 'a0000000-0000-0000-0000-000000000001'$q$, '42501');
SELECT expect_error('T2-CR-07e app role without DELETE grant cannot delete ledger',
  $q$DELETE FROM credit_transactions WHERE id = 'a0000000-0000-0000-0000-000000000001'$q$, '42501');
RESET ROLE;

-- Tenant-owned tables reject rows whose tenant has no matching parent key.
SELECT expect_error('T2-TI-06 credit transaction for tenant without account rejected',
  $q$INSERT INTO credit_transactions (id, tenant_id, amount, kind, idempotency_key, reason)
     VALUES (gen_random_uuid(), '00000000-0000-0000-0000-0000000000ff', 1, 'adjustment', 'ghost-1', 'x')$q$, '23503');

DO $$ BEGIN RAISE NOTICE '=== ALL PHASE 2 CONSTRAINT TESTS PASSED (synthetic data) ==='; END $$;