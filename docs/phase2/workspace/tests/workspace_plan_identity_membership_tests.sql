-- F-05 (Supervisor review of 8df7d5e, HIGH) — can an application role become, or act as, a privileged plan
-- identity through PostgreSQL role membership?
-- SYNTHETIC ONLY (D-014). Runs in the same database as workspace_plan_items_tests.sql, AFTER it (it reuses
-- that suite's fixtures and its pln_* helpers), with -v workspace_key.
--
-- Every test below exercises real PostgreSQL behaviour: actual GRANTs, actual SET SESSION AUTHORIZATION and
-- SET ROLE, actual INSERTs that the guard triggers see. No result is simulated by setting a variable or by
-- asserting a boolean the test computed itself. Each adversarial state is created inside a transaction that
-- is rolled back, because roles and memberships are cluster-wide.
--
-- The privileged identities are checked by IDENTITY: the session must BE the role, and the role must have no
-- membership in either direction and no LOGIN/SUPERUSER/CREATEROLE/BYPASSRLS/REPLICATION/CREATEDB/INHERIT.
-- These tests show what that rule means in practice. A malicious grant can make PostgreSQL ALLOW a SET ROLE
-- to the privileged role, and can make pg_has_role(..., 'MEMBER') true; the WRITE is still refused, because
-- the identity check fails as soon as a member exists.
\set ON_ERROR_STOP on
SET app.workspace_key = :'workspace_key';
SELECT format('ws_%s_runtime', :'workspace_key')          AS runtime_role \gset
SELECT format('ws_%s_runtime_login', :'workspace_key')    AS runtime_login \gset
SELECT format('ws_%s_worker', :'workspace_key')           AS worker_role \gset
SELECT format('ws_%s_worker_login', :'workspace_key')     AS worker_login \gset
SELECT format('ws_%s_exporter', :'workspace_key')         AS exporter_role \gset
SELECT format('ws_%s_exporter_login', :'workspace_key')   AS exporter_login \gset
SELECT format('ws_%s_table_owner', :'workspace_key')      AS table_owner \gset
SELECT format('ws_%s_function_owner', :'workspace_key')   AS function_owner \gset
SELECT format('ws_%s_governance_owner', :'workspace_key') AS governance_owner \gset
SELECT format('ws_%s_synth_plan_writer', :'workspace_key') AS writer_role \gset
SELECT format('ws_%s_plan_migrator', :'workspace_key')    AS migrator_role \gset
SELECT format('ws_%s_f05_mid_a', :'workspace_key')        AS mid_a \gset
SELECT format('ws_%s_f05_mid_b', :'workspace_key')        AS mid_b \gset

-- The application role inventory is the one workspace_roles_setup_draft.sql provisions ($roles$ list).
SELECT ARRAY[:'table_owner', :'function_owner', format('ws_%s_governance_owner', :'workspace_key'),
             :'runtime_role', :'worker_role', :'exporter_role',
             :'runtime_login', :'worker_login', :'exporter_login']::text AS inventory \gset

CREATE OR REPLACE FUNCTION f05_violations(inv text[], pattern text) RETURNS boolean LANGUAGE sql AS $f$
  SELECT EXISTS (SELECT 1 FROM public.plan_identity_boundary_violations(inv) v WHERE v LIKE pattern);
$f$;

-- ======================================================================================================
-- Version and baseline
-- ======================================================================================================
SELECT format('F-05 tested on: %s', version()) AS f05_server_version \gset
\echo :f05_server_version
SELECT pln_true('F05-00 PostgreSQL 16 or later (membership INHERIT/SET/ADMIN options exist and are exercised below)',
  current_setting('server_version_num')::int >= 160000);
SELECT pln_true('F05-01 the clean bootstrap leaves NO boundary violation',
  NOT EXISTS (SELECT 1 FROM plan_identity_boundary_violations(:'inventory'::text[])));
SELECT pln_true('F05-01b nobody, in the whole cluster, holds either privileged identity, and neither holds anything',
  NOT EXISTS (SELECT 1 FROM pg_auth_members m WHERE m.roleid IN (:'writer_role'::regrole, :'migrator_role'::regrole)
                                                 OR m.member IN (:'writer_role'::regrole, :'migrator_role'::regrole)));
SELECT pln_true('F05-02 a superuser is NOT accepted as the synthetic writer or the migrator (identity, not membership)',
  current_setting('is_superuser') = 'on'
  AND NOT plan_identity_is('synthetic_plan_writer') AND NOT plan_identity_is('legacy_plan_migrator'));

-- ======================================================================================================
-- Fixtures (synthetic). Student s1 and counselor A come from workspace_plan_items_tests.sql.
-- Plan P5 gets a draft normalized version with one item, then it is published so a transition is valid.
-- Plan P6 has no version, so a legacy_json v1 would be valid for the migrator. Plan P7 is a draft (below).
-- ======================================================================================================
INSERT INTO student_plans(plan_id,student_id) VALUES
 ('a5500000-0000-0000-0000-000000000001','e4000000-0000-0000-0000-000000000001'),
 ('a5500000-0000-0000-0000-000000000002','e4000000-0000-0000-0000-000000000001'),
 ('a5500000-0000-0000-0000-000000000003','e4000000-0000-0000-0000-000000000001');
INSERT INTO student_plan_versions(plan_version_id,plan_id,version_no,input_snapshot,rule_version,plan_content,status,created_by_membership_id)
VALUES ('a5510000-0000-0000-0000-000000000001','a5500000-0000-0000-0000-000000000001',1,'{}','manual-v1','{}','draft','b4000000-0000-0000-0000-00000000000a'),
-- P7 stays a DRAFT, so an item written to it would be VALID in every respect but identity: a refusal of
-- item_stmt can then only come from the identity check, and a control that weakens it makes the write succeed.
       ('a5510000-0000-0000-0000-000000000003','a5500000-0000-0000-0000-000000000003',1,'{}','manual-v1','{}','draft','b4000000-0000-0000-0000-00000000000a');

-- F05-14: the synthetic writer's authorized test operation. The only way to act as it is a superuser session
-- assuming it — the isolated test harness.
SET SESSION AUTHORIZATION :"writer_role";
SELECT pln_ok('F05-14 the synthetic writer, assumed by the isolated test harness, can create a plan item',
  $q$INSERT INTO plan_items(plan_item_id,plan_version_id,plan_id,student_id,item_no,topic_id,planned_local_date,timezone_name,created_by_membership_id)
     VALUES ('a5600000-0000-0000-0000-000000000001','a5510000-0000-0000-0000-000000000001','a5500000-0000-0000-0000-000000000001','e4000000-0000-0000-0000-000000000001',1,'a4320000-0000-0000-0000-000000000001','2026-11-23','Asia/Tehran','b4000000-0000-0000-0000-00000000000a')$q$);
RESET SESSION AUTHORIZATION;
UPDATE student_plan_versions SET status='published', published_at=clock_timestamp() WHERE plan_version_id='a5510000-0000-0000-0000-000000000001';

-- The two write statements every adversarial case below attempts.
\set item_stmt 'INSERT INTO public.plan_items(plan_item_id,plan_version_id,plan_id,student_id,item_no,topic_id,planned_local_date,timezone_name,created_by_membership_id) VALUES (gen_random_uuid(),''a5510000-0000-0000-0000-000000000003'',''a5500000-0000-0000-0000-000000000003'',''e4000000-0000-0000-0000-000000000001'',1,''a4320000-0000-0000-0000-000000000001'',''2026-11-24'',''Asia/Tehran'',''b4000000-0000-0000-0000-00000000000a'')'
\set event_stmt 'INSERT INTO public.plan_item_status_events(event_id,plan_item_id,student_id,seq_no,from_status,to_status,reason_note,actor_kind,actor_membership_id) VALUES (gen_random_uuid(),''a5600000-0000-0000-0000-000000000001'',''e4000000-0000-0000-0000-000000000001'',1,''planned'',''in_progress'',''f05'',''membership'',''b4000000-0000-0000-0000-00000000000a'')'
\set legacy_stmt 'INSERT INTO public.student_plan_versions(plan_version_id,plan_id,version_no,input_snapshot,rule_version,plan_content,status,content_model) VALUES (gen_random_uuid(),''a5500000-0000-0000-0000-000000000002'',1,''{}'',''legacy'',''{"legacy":"f05"}'',''draft'',''legacy_json'')'

-- ======================================================================================================
-- Ordinary runtime writes (no adversarial state): refused by privileges
-- ======================================================================================================
SET SESSION AUTHORIZATION :"runtime_login";
SELECT pln_err('F05-13a ordinary runtime plan-item write is refused', :'item_stmt', '42501', 'permission denied for table plan_items');
SELECT pln_err('F05-13b ordinary runtime status-event write is refused', :'event_stmt', '42501', 'permission denied for table plan_item_status_events');
SELECT pln_err('F05-13c ordinary runtime legacy_json version is refused', :'legacy_stmt', '42501', 'permission denied for table student_plan_versions');
RESET SESSION AUTHORIZATION;

-- ======================================================================================================
-- SET ROLE without membership: PostgreSQL itself refuses
-- ======================================================================================================
SET SESSION AUTHORIZATION :"runtime_login";
SELECT pln_err('F05-09a runtime login: SET ROLE to the synthetic writer is refused', format('SET ROLE %I', :'writer_role'), '42501', 'permission denied to set role');
SELECT pln_err('F05-09b runtime login: SET ROLE to the migrator is refused', format('SET ROLE %I', :'migrator_role'), '42501', 'permission denied to set role');
SELECT pln_err('F05-09c runtime login: SET ROLE to the table owner is refused', format('SET ROLE %I', :'table_owner'), '42501', 'permission denied to set role');
SELECT pln_err('F05-09d runtime login: SET ROLE to the function owner is refused', format('SET ROLE %I', :'function_owner'), '42501', 'permission denied to set role');
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION :"worker_login";
SELECT pln_err('F05-09e worker login: SET ROLE to the migrator is refused', format('SET ROLE %I', :'migrator_role'), '42501', 'permission denied to set role');
SELECT pln_err('F05-09f worker login: SET ROLE to the synthetic writer is refused', format('SET ROLE %I', :'writer_role'), '42501', 'permission denied to set role');
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION :"exporter_login";
SELECT pln_err('F05-09g exporter login: SET ROLE to the synthetic writer is refused', format('SET ROLE %I', :'writer_role'), '42501', 'permission denied to set role');
SELECT pln_err('F05-09h exporter login: SET ROLE to the migrator is refused', format('SET ROLE %I', :'migrator_role'), '42501', 'permission denied to set role');
RESET SESSION AUTHORIZATION;

-- ======================================================================================================
-- Granting, altering, dropping the privileged identities: PostgreSQL refuses an application role
-- ======================================================================================================
SET SESSION AUTHORIZATION :"runtime_login";
SELECT pln_err('F05-10a runtime cannot grant itself the synthetic writer', format('GRANT %I TO %I', :'writer_role', :'runtime_role'), '42501', 'permission denied to grant role');
SELECT pln_err('F05-10b runtime cannot grant the migrator to the worker', format('GRANT %I TO %I', :'migrator_role', :'worker_role'), '42501', 'permission denied to grant role');
SELECT pln_err('F05-10c runtime cannot grant itself the table owner', format('GRANT %I TO %I', :'table_owner', :'runtime_role'), '42501', 'permission denied to grant role');
SELECT pln_err('F05-11a runtime cannot give the synthetic writer LOGIN', format('ALTER ROLE %I LOGIN', :'writer_role'), '42501', 'permission denied to alter role');
SELECT pln_err('F05-11b runtime cannot give the migrator SUPERUSER', format('ALTER ROLE %I SUPERUSER', :'migrator_role'), '42501', 'permission denied to alter role');
SELECT pln_err('F05-11c runtime cannot set a password on the synthetic writer', format('ALTER ROLE %I PASSWORD %L', :'writer_role', 'f05-synthetic-not-a-secret'), '42501', 'permission denied to alter role');
SELECT pln_err('F05-11d runtime cannot rename the migrator', format('ALTER ROLE %I RENAME TO %I', :'migrator_role', 'f05_renamed'), '42501', 'permission denied to rename role');
SELECT pln_err('F05-11e runtime cannot drop the synthetic writer', format('DROP ROLE %I', :'writer_role'), '42501', 'permission denied to drop role');
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION :"worker_login";
SELECT pln_err('F05-10d worker cannot grant itself the migrator', format('GRANT %I TO %I', :'migrator_role', :'worker_role'), '42501', 'permission denied to grant role');
SELECT pln_err('F05-11f worker cannot give the migrator CREATEROLE', format('ALTER ROLE %I CREATEROLE', :'migrator_role'), '42501', 'permission denied to alter role');
RESET SESSION AUTHORIZATION;

-- ======================================================================================================
-- Replacing or disabling the guard, and alternate write paths
-- ======================================================================================================
SET SESSION AUTHORIZATION :"runtime_login";
SELECT pln_err('F05-12a runtime cannot replace plan_identity_is()',
  $q$CREATE OR REPLACE FUNCTION public.plan_identity_is(p_purpose text) RETURNS boolean LANGUAGE sql AS 'SELECT true'$q$, '42501', '');
SELECT pln_err('F05-12b runtime cannot replace the plan-item guard',
  $q$CREATE OR REPLACE FUNCTION public.guard_plan_item() RETURNS trigger LANGUAGE plpgsql AS 'BEGIN RETURN NEW; END'$q$, '42501', '');
SELECT pln_err('F05-12c runtime cannot disable the plan-item guard trigger',
  'ALTER TABLE public.plan_items DISABLE TRIGGER plan_items_guard', '42501', 'must be owner of table plan_items');
SELECT pln_err('F05-12d runtime cannot disable the status-event guard trigger',
  'ALTER TABLE public.plan_item_status_events DISABLE TRIGGER plan_item_status_events_guard', '42501', 'must be owner of table plan_item_status_events');
SELECT pln_err('F05-12e runtime cannot drop the version-model guard trigger',
  'DROP TRIGGER student_plan_versions_model_guard ON public.student_plan_versions', '42501', 'must be owner of relation student_plan_versions');
SELECT pln_err('F05-12f runtime cannot take ownership of plan_identity_is()',
  format('ALTER FUNCTION public.plan_identity_is(text) OWNER TO %I', :'runtime_role'), '42501', 'must be owner of function plan_identity_is');
SELECT pln_err('F05-12g runtime cannot switch triggers off with session_replication_role',
  'SET session_replication_role = replica', '42501', 'permission denied to set parameter');
SELECT pln_err('F05-12h runtime cannot repoint the writer identity at itself',
  format('UPDATE public.plan_privileged_identities SET role_name = %L WHERE purpose = %L', :'runtime_role', 'synthetic_plan_writer'), '42501', 'permission denied for table plan_privileged_identities');
SELECT pln_err('F05-12i runtime cannot delete an identity record',
  'DELETE FROM public.plan_privileged_identities', '42501', 'permission denied for table plan_privileged_identities');
SELECT pln_err('F05-12j runtime cannot create a function in the public schema',
  $q$CREATE FUNCTION public.f05_shadow() RETURNS int LANGUAGE sql AS 'SELECT 1'$q$, '42501', 'permission denied for schema public');
SELECT pln_err('F05-12k runtime cannot create a temporary table to shadow the identity record',
  'CREATE TEMP TABLE plan_privileged_identities(purpose text, role_name text, note text)', '42501', 'permission denied to create temporary tables');
RESET SESSION AUTHORIZATION;
SELECT pln_true('F05-12l plan_identity_is() and the guard check run with a pinned search_path',
  (SELECT count(*) FROM pg_proc WHERE oid IN ('public.plan_identity_is(text)'::regprocedure,
                                               'public.plan_identity_boundary_violations(text[])'::regprocedure)
      AND proconfig @> ARRAY['search_path=pg_catalog, pg_temp']) = 2);
SELECT pln_true('F05-12m no SECURITY DEFINER function is owned by either privileged identity (it owns nothing at all)',
  NOT EXISTS (SELECT 1 FROM pg_shdepend d WHERE d.deptype = 'o'
               AND d.refobjid IN (:'writer_role'::regrole, :'migrator_role'::regrole)));

-- ======================================================================================================
-- Adversarial MEMBERSHIP. A superuser (standing in for a mistake or a compromise) grants a privileged
-- identity to an application role. PostgreSQL then ALLOWS what membership allows. The guard must still
-- refuse the WRITE, and the boundary check must name the violation.
-- ======================================================================================================

-- F05-03: runtime DIRECTLY holds the writer with INHERIT (it would inherit the writer's INSERT privilege)
BEGIN;
GRANT :"writer_role" TO :"runtime_role" WITH INHERIT TRUE, SET FALSE;
SELECT pln_true('F05-03a PostgreSQL now reports runtime as a MEMBER of the writer (the old check would have passed)',
  pg_has_role(:'runtime_role', :'writer_role', 'MEMBER'));
SET SESSION AUTHORIZATION :"runtime_login";
SELECT pln_err('F05-03b runtime, inheriting the writer''s INSERT privilege, still cannot create a plan item',
  :'item_stmt', '42501', 'writable only by the synthetic test identity');
SELECT pln_err('F05-03c ... nor a status transition', :'event_stmt', '42501', 'writable only by the synthetic test identity');
RESET SESSION AUTHORIZATION;
SELECT pln_true('F05-03d the boundary check names it', f05_violations(:'inventory'::text[], '%is held by%'||:'runtime_role'||'%'));
ROLLBACK;

-- F05-04: runtime directly holds the writer with SET: SET ROLE now SUCCEEDS at the PostgreSQL level
BEGIN;
GRANT :"writer_role" TO :"runtime_role" WITH INHERIT FALSE, SET TRUE;
SET SESSION AUTHORIZATION :"runtime_login";
SELECT pln_ok('F05-04a with a malicious SET grant, PostgreSQL lets the runtime login SET ROLE to the writer', format('SET ROLE %I', :'writer_role'));
SELECT pln_true('F05-04b current_user is now the writer', current_user = :'writer_role');
SELECT pln_err('F05-04c ... and the plan-item write is STILL refused, because the writer now has a member',
  :'item_stmt', '42501', 'writable only by the synthetic test identity');
SELECT pln_err('F05-04d ... and so is the status transition', :'event_stmt', '42501', 'writable only by the synthetic test identity');
RESET ROLE;
RESET SESSION AUTHORIZATION;
SELECT pln_true('F05-04e the boundary check names it', f05_violations(:'inventory'::text[], '%is held by '||:'runtime_role'||' (admin=f inherit=f set=t)'));
ROLLBACK;

-- F05-05: INDIRECT membership through a two-role chain: runtime -> mid_b -> mid_a -> writer
SELECT format('CREATE ROLE %I NOLOGIN NOINHERIT', :'mid_a') WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'mid_a') \gexec
SELECT format('CREATE ROLE %I NOLOGIN NOINHERIT', :'mid_b') WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'mid_b') \gexec
BEGIN;
GRANT :"writer_role" TO :"mid_a" WITH INHERIT TRUE, SET TRUE;
GRANT :"mid_a" TO :"mid_b" WITH INHERIT TRUE, SET TRUE;
GRANT :"mid_b" TO :"runtime_role" WITH INHERIT TRUE, SET TRUE;
SELECT pln_true('F05-05a PostgreSQL reports the runtime as an INDIRECT member of the writer through the chain',
  pg_has_role(:'runtime_role', :'writer_role', 'MEMBER')
  AND NOT EXISTS (SELECT 1 FROM pg_auth_members WHERE roleid = :'writer_role'::regrole AND member = :'runtime_role'::regrole));
SET SESSION AUTHORIZATION :"runtime_login";
SELECT pln_err('F05-05b through the chain, the runtime (inheriting) cannot create a plan item',
  :'item_stmt', '42501', 'writable only by the synthetic test identity');
SELECT pln_ok('F05-05c through the chain, PostgreSQL lets the runtime login SET ROLE to the writer', format('SET ROLE %I', :'writer_role'));
SELECT pln_err('F05-05d ... and the write is still refused', :'item_stmt', '42501', 'writable only by the synthetic test identity');
SELECT pln_err('F05-05e ... and so is the status transition', :'event_stmt', '42501', 'writable only by the synthetic test identity');
RESET ROLE;
RESET SESSION AUTHORIZATION;
SELECT pln_true('F05-05f the boundary check names the indirect path', f05_violations(:'inventory'::text[], 'application role '||:'runtime_role'||' can reach privileged identity%'));
ROLLBACK;

-- F05-06: the WORKER becomes a member of the MIGRATOR
BEGIN;
GRANT :"migrator_role" TO :"worker_role" WITH INHERIT TRUE, SET TRUE;
SET SESSION AUTHORIZATION :"worker_login";
SELECT pln_err('F05-06a the worker, inheriting the migrator''s INSERT privilege, cannot create a legacy_json version',
  :'legacy_stmt', '42501', 'can only be written by the migration identity');
SELECT pln_ok('F05-06b PostgreSQL lets the worker login SET ROLE to the migrator', format('SET ROLE %I', :'migrator_role'));
SELECT pln_err('F05-06c ... and the legacy_json version is still refused', :'legacy_stmt', '42501', 'can only be written by the migration identity');
RESET ROLE;
RESET SESSION AUTHORIZATION;
SELECT pln_true('F05-06d the boundary check names it', f05_violations(:'inventory'::text[], '%is held by%'||:'worker_role'||'%'));
ROLLBACK;

-- F05-07: a nested chain reaching the MIGRATOR from the exporter: exporter -> mid_b -> mid_a -> migrator
BEGIN;
GRANT :"migrator_role" TO :"mid_a" WITH INHERIT TRUE, SET TRUE;
GRANT :"mid_a" TO :"mid_b" WITH INHERIT TRUE, SET TRUE;
GRANT :"mid_b" TO :"exporter_role" WITH INHERIT TRUE, SET TRUE;
SET SESSION AUTHORIZATION :"exporter_login";
SELECT pln_ok('F05-07a through the chain, PostgreSQL lets the exporter login SET ROLE to the migrator', format('SET ROLE %I', :'migrator_role'));
SELECT pln_err('F05-07b ... and the legacy_json version is still refused', :'legacy_stmt', '42501', 'can only be written by the migration identity');
RESET ROLE;
RESET SESSION AUTHORIZATION;
SELECT pln_true('F05-07c the boundary check names the indirect path', f05_violations(:'inventory'::text[], 'application role '||:'exporter_role'||' can reach privileged identity%'));
ROLLBACK;

-- F05-08: the privileged role is made a MEMBER of something (it would carry extra privileges), or is given
-- an attribute after bootstrap. The identity check re-reads that state on every write.
BEGIN;
GRANT :"runtime_role" TO :"writer_role";
SET SESSION AUTHORIZATION :"writer_role";
SELECT pln_err('F05-08a the writer, once made a member of another role, is no longer accepted', :'item_stmt', '42501', 'writable only by the synthetic test identity');
RESET SESSION AUTHORIZATION;
SELECT pln_true('F05-08b the boundary check names it', f05_violations(:'inventory'::text[], '%is itself a member of%'));
ROLLBACK;
BEGIN;
ALTER ROLE :"writer_role" LOGIN;
SET SESSION AUTHORIZATION :"writer_role";
SELECT pln_err('F05-08c the writer, once given LOGIN, is no longer accepted', :'item_stmt', '42501', 'writable only by the synthetic test identity');
RESET SESSION AUTHORIZATION;
SELECT pln_true('F05-08d the boundary check names it', f05_violations(:'inventory'::text[], '%has LOGIN%'));
ROLLBACK;
BEGIN;
ALTER ROLE :"migrator_role" CREATEROLE;
SET SESSION AUTHORIZATION :"migrator_role";
SELECT pln_err('F05-08e the migrator, once given CREATEROLE, is no longer accepted', :'legacy_stmt', '42501', 'can only be written by the migration identity');
RESET SESSION AUTHORIZATION;
SELECT pln_true('F05-08f the boundary check names it', f05_violations(:'inventory'::text[], '%has CREATEROLE%'));
ROLLBACK;
BEGIN;
ALTER ROLE :"writer_role" BYPASSRLS;
SET SESSION AUTHORIZATION :"writer_role";
SELECT pln_err('F05-08g the writer, once given BYPASSRLS, is no longer accepted', :'event_stmt', '42501', 'writable only by the synthetic test identity');
RESET SESSION AUTHORIZATION;
SELECT pln_true('F05-08h the boundary check names it', f05_violations(:'inventory'::text[], '%has BYPASSRLS%'));
ROLLBACK;

-- ======================================================================================================
-- The boundary check also catches the administrative paths (detection only; these are superuser actions)
-- ======================================================================================================
BEGIN;
GRANT :"function_owner" TO :"runtime_role";
SELECT pln_true('F05-15a an application role holding the OWNER of the security functions is a violation',
  f05_violations(:'inventory'::text[], 'owner '||:'function_owner'||' of the plan security objects is held by%'));
ROLLBACK;
BEGIN;
ALTER TABLE plan_items DISABLE TRIGGER plan_items_guard;
SELECT pln_true('F05-15b a disabled guard trigger is a violation', f05_violations(:'inventory'::text[], '%plan_items_guard%not enabled%'));
ROLLBACK;
BEGIN;
GRANT INSERT ON plan_items TO PUBLIC;
SELECT pln_true('F05-15c a PUBLIC write privilege on a plan table is a violation', f05_violations(:'inventory'::text[], 'public holds INSERT on public.plan_items'));
ROLLBACK;
BEGIN;
GRANT UPDATE (role_name) ON plan_privileged_identities TO :"worker_role";
SELECT pln_true('F05-15d a column-level write on the identity record by an application role is a violation',
  f05_violations(:'inventory'::text[], :'worker_role'||' holds UPDATE on public.plan_privileged_identities'));
ROLLBACK;
BEGIN;
ALTER ROLE :"runtime_login" CREATEROLE;
SELECT pln_true('F05-15e an application role with CREATEROLE is a violation', f05_violations(:'inventory'::text[], 'application role '||:'runtime_login'||' has CREATEROLE'));
ROLLBACK;
BEGIN;
DELETE FROM plan_privileged_identities WHERE purpose = 'legacy_plan_migrator';
SELECT pln_true('F05-15f a missing identity record is a violation (and nobody can then act as the migrator)',
  f05_violations(:'inventory'::text[], 'legacy_plan_migrator: no privileged identity is recorded'));
SET SESSION AUTHORIZATION :"migrator_role";
SELECT pln_true('F05-15g ... the migrator itself is refused once its record is gone', NOT plan_identity_is('legacy_plan_migrator'));
RESET SESSION AUTHORIZATION;
ROLLBACK;

-- ======================================================================================================
-- After every rollback, the state is clean again, and the trusted test paths still work
-- ======================================================================================================
SELECT pln_true('F05-16a every adversarial grant was rolled back: no boundary violation remains',
  NOT EXISTS (SELECT 1 FROM plan_identity_boundary_violations(:'inventory'::text[])));
SET SESSION AUTHORIZATION :"writer_role";
SELECT pln_ok('F05-16b the synthetic writer, assumed by the harness, records a transition', :'event_stmt');
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION :"migrator_role";
SELECT pln_ok('F05-16c the migrator, assumed by the harness, imports a legacy_json version (its trusted test path)', :'legacy_stmt');
RESET SESSION AUTHORIZATION;
-- ======================================================================================================
-- F-05 FOLLOW-UP (Supervisor review of 38f2561): TRANSITIVE reach to the three OWNER roles.
-- An owner can replace the security functions, disable the guard triggers or rewrite the identity record,
-- so reaching an owner through ANY chain is as dangerous as reaching a privileged identity. Each case first
-- shows what PostgreSQL actually lets the application login DO through the chain (inside a rolled-back
-- transaction), then that the boundary check names the exact path.
-- ======================================================================================================
\set path_pfx 'application role '

-- F05-17: runtime_login -> mid_a -> function_owner, INHERIT TRUE on every link
BEGIN;
GRANT :"function_owner" TO :"mid_a" WITH INHERIT TRUE, SET TRUE;
GRANT :"mid_a" TO :"runtime_login" WITH INHERIT TRUE, SET TRUE;
SET SESSION AUTHORIZATION :"runtime_login";
SELECT pln_ok('F05-17a REAL EFFECT: through runtime_login -> mid_a -> function_owner (INHERIT), the runtime login can REPLACE plan_identity_is()',
  $q$CREATE OR REPLACE FUNCTION public.plan_identity_is(p_purpose text) RETURNS boolean LANGUAGE sql STABLE SET search_path = pg_catalog, pg_temp AS 'SELECT true'$q$);
RESET SESSION AUTHORIZATION;
SELECT pln_true('F05-17b the boundary check names the transitive path to the function owner',
  f05_violations(:'inventory'::text[], :'path_pfx'||:'runtime_login'||' can reach owner '||:'function_owner'||' via '||:'runtime_login'||' -> '||:'mid_a'||' -> '||:'function_owner'));
ROLLBACK;

-- F05-18: worker_login -> mid_a -> table_owner, INHERIT TRUE
BEGIN;
GRANT :"table_owner" TO :"mid_a" WITH INHERIT TRUE, SET TRUE;
GRANT :"mid_a" TO :"worker_login" WITH INHERIT TRUE, SET TRUE;
SET SESSION AUTHORIZATION :"worker_login";
SELECT pln_ok('F05-18a REAL EFFECT: through worker_login -> mid_a -> table_owner (INHERIT), the worker login can DISABLE the plan-item guard',
  'ALTER TABLE public.plan_items DISABLE TRIGGER plan_items_guard');
RESET SESSION AUTHORIZATION;
SELECT pln_true('F05-18b the boundary check names the transitive path to the table owner',
  f05_violations(:'inventory'::text[], :'path_pfx'||:'worker_login'||' can reach owner '||:'table_owner'||' via '||:'worker_login'||' -> '||:'mid_a'||' -> '||:'table_owner'));
ROLLBACK;

-- F05-19: exporter -> mid_b -> mid_a -> governance_owner (nested, starting at the NOLOGIN service role)
BEGIN;
GRANT :"governance_owner" TO :"mid_a" WITH INHERIT TRUE, SET TRUE;
GRANT :"mid_a" TO :"mid_b" WITH INHERIT TRUE, SET TRUE;
GRANT :"mid_b" TO :"exporter_role" WITH INHERIT TRUE, SET TRUE;
SET SESSION AUTHORIZATION :"exporter_login";
SELECT pln_ok('F05-19a REAL EFFECT: through exporter_login -> exporter -> mid_b -> mid_a -> governance_owner, the exporter login can SET ROLE to the governance owner',
  format('SET ROLE %I', :'governance_owner'));
RESET ROLE;
RESET SESSION AUTHORIZATION;
SELECT pln_true('F05-19b the boundary check names the nested path from the exporter',
  f05_violations(:'inventory'::text[], :'path_pfx'||:'exporter_role'||' can reach owner '||:'governance_owner'||' via '||:'exporter_role'||' -> '||:'mid_b'||' -> '||:'mid_a'||' -> '||:'governance_owner'));
SELECT pln_true('F05-19c ... and from the exporter login, one link longer',
  f05_violations(:'inventory'::text[], :'path_pfx'||:'exporter_login'||' can reach owner '||:'governance_owner'||' via %'));
ROLLBACK;

-- F05-20: SET TRUE, INHERIT FALSE: no inherited privilege, but SET ROLE to the owner works
BEGIN;
GRANT :"table_owner" TO :"mid_a" WITH INHERIT FALSE, SET TRUE;
GRANT :"mid_a" TO :"runtime_login" WITH INHERIT FALSE, SET TRUE;
SET SESSION AUTHORIZATION :"runtime_login";
SELECT pln_err('F05-20a with INHERIT FALSE the runtime login does NOT inherit ownership (disable refused as itself)',
  'ALTER TABLE public.plan_items DISABLE TRIGGER plan_items_guard', '42501', 'must be owner of table plan_items');
SELECT pln_ok('F05-20b REAL EFFECT: with SET TRUE the runtime login can SET ROLE to the table owner through the chain', format('SET ROLE %I', :'table_owner'));
SELECT pln_ok('F05-20c REAL EFFECT: ... and then disable the guard', 'ALTER TABLE public.plan_items DISABLE TRIGGER plan_items_guard');
RESET ROLE;
RESET SESSION AUTHORIZATION;
SELECT pln_true('F05-20d the boundary check names the SET-only path',
  f05_violations(:'inventory'::text[], :'path_pfx'||:'runtime_login'||' can reach owner '||:'table_owner'||' via '||:'runtime_login'||' -> '||:'mid_a'||' -> '||:'table_owner'));
ROLLBACK;

-- F05-21: ADMIN OPTION only (INHERIT FALSE, SET FALSE) on the function owner, held by mid_a, which the runtime
-- login inherits. Neither inheritance nor SET ROLE reaches the owner directly, but ADMIN lets the holder
-- GRANT the owner to itself, and then SET ROLE works.
BEGIN;
GRANT :"function_owner" TO :"mid_a" WITH ADMIN TRUE, INHERIT FALSE, SET FALSE;
GRANT :"mid_a" TO :"runtime_login" WITH INHERIT TRUE, SET TRUE;
SET SESSION AUTHORIZATION :"runtime_login";
SELECT pln_err('F05-21a with ADMIN only, SET ROLE to the function owner is refused at first',
  format('SET ROLE %I', :'function_owner'), '42501', 'permission denied to set role');
SELECT pln_ok('F05-21b REAL EFFECT: ... but the inherited ADMIN OPTION lets the runtime login GRANT the function owner to itself',
  format('GRANT %I TO %I', :'function_owner', :'runtime_login'));
SELECT pln_ok('F05-21c REAL EFFECT: ... and then SET ROLE to it', format('SET ROLE %I', :'function_owner'));
RESET ROLE;
RESET SESSION AUTHORIZATION;
SELECT pln_true('F05-21d the boundary check names the ADMIN-only path',
  f05_violations(:'inventory'::text[], :'path_pfx'||:'runtime_login'||' can reach owner '||:'function_owner'||' via '||:'runtime_login'||' -> '||:'mid_a'||' -> '||:'function_owner'));
SELECT pln_true('F05-21e ... and reports the ADMIN option on the link as an unexpected membership',
  f05_violations(:'inventory'::text[], 'unexpected membership: '||:'mid_a'||' holds '||:'function_owner'||' (admin=t inherit=f set=f)'));
ROLLBACK;

-- F05-22: without any chain, an application role cannot grant, administer or alter an owner
SET SESSION AUTHORIZATION :"runtime_login";
SELECT pln_err('F05-22a runtime login cannot grant itself the function owner', format('GRANT %I TO %I', :'function_owner', :'runtime_login'), '42501', 'permission denied to grant role');
SELECT pln_err('F05-22b runtime login cannot grant the governance owner to the runtime', format('GRANT %I TO %I', :'governance_owner', :'runtime_role'), '42501', 'permission denied to grant role');
SELECT pln_err('F05-22c runtime login cannot SET ROLE to the governance owner', format('SET ROLE %I', :'governance_owner'), '42501', 'permission denied to set role');
SELECT pln_err('F05-22d runtime login cannot give the table owner LOGIN', format('ALTER ROLE %I LOGIN', :'table_owner'), '42501', 'permission denied to alter role');
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION :"worker_login";
SELECT pln_err('F05-22e worker login cannot grant itself the table owner WITH ADMIN', format('GRANT %I TO %I WITH ADMIN TRUE', :'table_owner', :'worker_login'), '42501', 'permission denied to grant role');
SELECT pln_err('F05-22f worker login cannot revoke the runtime login''s service role', format('REVOKE %I FROM %I', :'runtime_role', :'runtime_login'), '42501', 'permission denied to revoke role');
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION :"exporter_login";
SELECT pln_err('F05-22g exporter login cannot SET ROLE to the table owner', format('SET ROLE %I', :'table_owner'), '42501', 'permission denied to set role');
RESET SESSION AUTHORIZATION;

-- F05-23: the EXPECTED attributes and memberships of all nine roles (detection; superuser-made changes)
BEGIN;
ALTER ROLE :"runtime_role" LOGIN;
SELECT pln_true('F05-23a a service role with LOGIN is a violation (expected NOLOGIN)',
  f05_violations(:'inventory'::text[], :'path_pfx'||:'runtime_role'||': expected NOLOGIN, found LOGIN'));
ROLLBACK;
BEGIN;
ALTER ROLE :"governance_owner" INHERIT;
SELECT pln_true('F05-23b an owner with INHERIT is a violation (expected NOINHERIT)',
  f05_violations(:'inventory'::text[], :'path_pfx'||:'governance_owner'||': expected NOINHERIT, found INHERIT'));
ROLLBACK;
BEGIN;
ALTER ROLE :"worker_login" NOINHERIT;
SELECT pln_true('F05-23c a login role with NOINHERIT is a violation (expected INHERIT)',
  f05_violations(:'inventory'::text[], :'path_pfx'||:'worker_login'||': expected INHERIT, found NOINHERIT'));
ROLLBACK;
BEGIN;
ALTER ROLE :"exporter_role" CREATEDB;
SELECT pln_true('F05-23d a service role with CREATEDB is a violation',
  f05_violations(:'inventory'::text[], :'path_pfx'||:'exporter_role'||' has CREATEDB'));
ROLLBACK;
BEGIN;
GRANT :"worker_role" TO :"runtime_login";
SELECT pln_true('F05-23e a login holding ANOTHER service role is an unexpected membership',
  f05_violations(:'inventory'::text[], 'unexpected membership: '||:'runtime_login'||' holds '||:'worker_role'||'%'));
ROLLBACK;
BEGIN;
REVOKE :"runtime_role" FROM :"runtime_login";
GRANT :"runtime_role" TO :"runtime_login" WITH ADMIN TRUE;
SELECT pln_true('F05-23f the expected login -> service grant WITH ADMIN is an unexpected membership',
  f05_violations(:'inventory'::text[], 'unexpected membership: '||:'runtime_login'||' holds '||:'runtime_role'||' (admin=t%'));
ROLLBACK;
SELECT pln_true('F05-23g after every rollback no violation remains, and the three expected grants are exactly what exists',
  NOT EXISTS (SELECT 1 FROM plan_identity_boundary_violations(:'inventory'::text[]))
  AND (SELECT count(*) FROM pg_auth_members m WHERE m.member::regrole::text = ANY (:'inventory'::text[])
                                              OR m.roleid::regrole::text = ANY (:'inventory'::text[])) = 3);

SELECT format('DROP ROLE %I, %I', :'mid_a', :'mid_b') \gexec

\echo 'PLAN IDENTITY MEMBERSHIP TESTS (F-05) COMPLETED'
