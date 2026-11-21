-- WS-PLAN-01 F-04 — the migration is safe on rows that existed before it. SYNTHETIC ONLY (D-014).
-- Order: base drafts through workspace_counselor_scope_draft.sql, then workspace_plan_items_migration_fixture.sql
-- (historical rows), THEN workspace_plan_items_draft.sql, workspace_operations_draft.sql and
-- workspace_roles_setup_draft.sql, then this file. It is NOT a production migration and proves nothing about
-- real data volumes, lock duration or rollback (see WS_PLAN_01_MIGRATION_NOTES.md).
\set ON_ERROR_STOP on
SET app.workspace_key = :'workspace_key';
SELECT format('ws_%s_runtime', :'workspace_key') AS runtime_role \gset

CREATE OR REPLACE FUNCTION plm_true(label text, cond boolean) RETURNS void LANGUAGE plpgsql AS $t$
BEGIN
  IF cond IS DISTINCT FROM true THEN RAISE EXCEPTION 'FAIL %: expected true, got %',label,cond; END IF;
  RAISE NOTICE 'PASS %',label;
END; $t$;
CREATE OR REPLACE FUNCTION plm_err(label text, stmt text, want_msg text) RETURNS void LANGUAGE plpgsql AS $t$
BEGIN
  BEGIN EXECUTE stmt;
  EXCEPTION WHEN OTHERS THEN
    IF position(want_msg IN SQLERRM)=0 THEN RAISE EXCEPTION 'FAIL %: wrong reason: %',label,SQLERRM; END IF;
    RAISE NOTICE 'PASS % (refused, reason verified)',label; RETURN;
  END;
  RAISE EXCEPTION 'FAIL %: statement unexpectedly succeeded',label;
END; $t$;
GRANT EXECUTE ON FUNCTION plm_true(text,boolean), plm_err(text,text,text) TO PUBLIC;

SELECT plm_true('PLN-M01 every row that existed before the migration is classified legacy_json',
  (SELECT count(*) FILTER (WHERE content_model='legacy_json') = count(*) AND count(*) = 3
     FROM student_plan_versions v JOIN pln_hist_snapshot h USING (plan_version_id)));
SELECT plm_true('PLN-M02 the historical draft whose JSON was ''{}'' did NOT silently become an item-less normalized plan',
  (SELECT content_model FROM student_plan_versions WHERE plan_version_id='a2510000-0000-0000-0000-000000000002')='legacy_json');
SELECT plm_true('PLN-M03 no historical content, status or publication time changed',
  NOT EXISTS (SELECT 1 FROM student_plan_versions v JOIN pln_hist_snapshot h USING (plan_version_id)
               WHERE (v.plan_content, v.status, v.published_at) IS DISTINCT FROM (h.plan_content, h.status, h.published_at)));
SELECT plm_true('PLN-M04 read compatibility: every historical version renders its stored JSON unchanged',
  NOT EXISTS (SELECT 1 FROM plan_version_rendered r JOIN pln_hist_snapshot h USING (plan_version_id)
               WHERE r.rendered IS DISTINCT FROM h.plan_content));
SELECT plm_true('PLN-M05 the column default for rows created AFTER the migration is normalized',
  (SELECT column_default FROM information_schema.columns
    WHERE table_name='student_plan_versions' AND column_name='content_model') LIKE '''normalized''%');

\ir workspace_principal_test_harness.sql
-- Through the runtime, under the counselor's verified principal (WS-ISO-01 B; decision E1: a counselor
-- converts a legacy plan by creating a new normalized version that supersedes it).
SET SESSION AUTHORIZATION :"runtime_role";
BEGIN;
SELECT test_establish('counselor','b2000000-0000-0000-0000-00000000000a');
INSERT INTO student_plan_versions(plan_version_id,plan_id,version_no,input_snapshot,rule_version,plan_content,status,created_by_membership_id,supersedes_plan_version_id,change_reason)
VALUES ('a2510000-0000-0000-0000-000000000011','a2500000-0000-0000-0000-000000000001',3,'{}','manual-v1','{}','draft','b2000000-0000-0000-0000-00000000000a','a2510000-0000-0000-0000-000000000001','synthetic: migrated to normalized items');
SELECT plm_true('PLN-M06 a version created after the migration is normalized, and may supersede a historical one with a reason',
  (SELECT content_model FROM student_plan_versions WHERE plan_version_id='a2510000-0000-0000-0000-000000000011')='normalized');
SELECT plm_err('PLN-M07 a historical legacy row cannot be re-labelled normalized in place (legacy is read-only, E1)',
  $q$UPDATE student_plan_versions SET content_model='normalized' WHERE plan_version_id='a2510000-0000-0000-0000-000000000003'$q$,
  'read-only');
SELECT plm_err('PLN-M08 a published historical row stays immutable after the migration',
  $q$UPDATE student_plan_versions SET plan_content='{"rewritten":true}' WHERE plan_version_id='a2510000-0000-0000-0000-000000000001'$q$,
  'published versions are immutable');
COMMIT;
RESET SESSION AUTHORIZATION;

SELECT 'PLAN ITEM MIGRATION TESTS COMPLETED (PLN-M01..M08): historical rows are preserved and classified legacy_json; new rows are normalized' AS result;
