\set ON_ERROR_STOP on
\if :{?workspace_key}
\else
  \echo 'ERROR: pass -v workspace_key=<unique-lowercase-key> (32-character lowercase hex Workspace UUID)'
  \quit 3
\endif

SET app.workspace_key = :'workspace_key';

DO $validate$
BEGIN
  IF current_setting('app.workspace_key') !~ '^[0-9a-f]{32}$' THEN
    RAISE EXCEPTION 'workspace_key must match ^[0-9a-f]{32}$';
  END IF;
END $validate$;

-- PostgreSQL roles are cluster-wide. Every Workspace receives distinct role names,
-- login identities and database CONNECT grants; generic role names must never be shared.
DO $roles$
DECLARE
  k text := current_setting('app.workspace_key');
  role_name text;
  role_names text[] := ARRAY[
    'ws_'||k||'_table_owner',
    'ws_'||k||'_function_owner',
    'ws_'||k||'_governance_owner',
    'ws_'||k||'_runtime',
    'ws_'||k||'_worker',
    'ws_'||k||'_exporter',
    'ws_'||k||'_runtime_login',
    'ws_'||k||'_worker_login',
    'ws_'||k||'_exporter_login'
  ];
BEGIN
  FOREACH role_name IN ARRAY role_names LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname=role_name) THEN
      IF right(role_name,6)='_login' THEN
        EXECUTE format(
          'CREATE ROLE %I LOGIN INHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS PASSWORD NULL',
          role_name
        );
      ELSE
        EXECUTE format(
          'CREATE ROLE %I NOLOGIN NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS',
          role_name
        );
      END IF;
    END IF;
  END LOOP;
END $roles$;

DO $membership$
DECLARE k text := current_setting('app.workspace_key');
BEGIN
  EXECUTE format('GRANT %I TO %I', 'ws_'||k||'_runtime', 'ws_'||k||'_runtime_login');
  EXECUTE format('GRANT %I TO %I', 'ws_'||k||'_worker', 'ws_'||k||'_worker_login');
  EXECUTE format('GRANT %I TO %I', 'ws_'||k||'_exporter', 'ws_'||k||'_exporter_login');
END $membership$;

-- A database is connectable only by the login identities provisioned for this Workspace
-- (plus the controlled migration operator executing this script).
SELECT format('REVOKE CONNECT, TEMPORARY ON DATABASE %I FROM PUBLIC',current_database()) \gexec
SELECT format('GRANT CONNECT ON DATABASE %I TO %I,%I,%I,%I',
  current_database(),
  'ws_'||current_setting('app.workspace_key')||'_runtime_login',
  'ws_'||current_setting('app.workspace_key')||'_worker_login',
  'ws_'||current_setting('app.workspace_key')||'_exporter_login',
  current_user) \gexec

REVOKE CREATE ON SCHEMA public FROM PUBLIC;
SELECT format('GRANT CREATE,USAGE ON SCHEMA public TO %I', 'ws_'||current_setting('app.workspace_key')||'_table_owner') \gexec
SELECT format('GRANT CREATE,USAGE ON SCHEMA public TO %I', 'ws_'||current_setting('app.workspace_key')||'_function_owner') \gexec
SELECT format('GRANT USAGE ON SCHEMA public TO %I,%I,%I',
  'ws_'||current_setting('app.workspace_key')||'_runtime',
  'ws_'||current_setting('app.workspace_key')||'_worker',
  'ws_'||current_setting('app.workspace_key')||'_exporter') \gexec

-- Reassign all current Workspace objects to non-login owners.
DO $owners$
DECLARE
  k text := current_setting('app.workspace_key');
  v_table_owner text := 'ws_'||k||'_table_owner';
  v_function_owner text := 'ws_'||k||'_function_owner';
  r record;
BEGIN
  FOR r IN SELECT schemaname,tablename FROM pg_tables WHERE schemaname='public' LOOP
    EXECUTE format('ALTER TABLE %I.%I OWNER TO %I',r.schemaname,r.tablename,v_table_owner);
  END LOOP;
  FOR r IN SELECT sequence_schema,sequence_name FROM information_schema.sequences WHERE sequence_schema='public' LOOP
    EXECUTE format('ALTER SEQUENCE %I.%I OWNER TO %I',r.sequence_schema,r.sequence_name,v_table_owner);
  END LOOP;
  FOR r IN
    SELECT p.oid::regprocedure AS signature
      FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='public' AND p.prokind IN ('f','p')
  LOOP
    EXECUTE format('ALTER FUNCTION %s OWNER TO %I',r.signature,v_function_owner);
  END LOOP;
END $owners$;

-- No inherited PUBLIC or stale direct privileges. New objects default to deny.
REVOKE ALL PRIVILEGES ON ALL TABLES IN SCHEMA public FROM PUBLIC;
REVOKE ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public FROM PUBLIC;
SELECT format('REVOKE ALL PRIVILEGES ON ALL TABLES IN SCHEMA public FROM %I,%I,%I,%I',
  'ws_'||current_setting('app.workspace_key')||'_runtime',
  'ws_'||current_setting('app.workspace_key')||'_worker',
  'ws_'||current_setting('app.workspace_key')||'_exporter',
  'ws_'||current_setting('app.workspace_key')||'_function_owner') \gexec
SELECT format('REVOKE ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public FROM %I,%I,%I,%I',
  'ws_'||current_setting('app.workspace_key')||'_runtime',
  'ws_'||current_setting('app.workspace_key')||'_worker',
  'ws_'||current_setting('app.workspace_key')||'_exporter',
  'ws_'||current_setting('app.workspace_key')||'_function_owner') \gexec

-- Backend runtime may operate only inside this Workspace. Object-level counselor/manager/guardian
-- authorization remains mandatory in the API; these grants are not a substitute for RBAC.
SELECT format(
  'GRANT SELECT,INSERT,UPDATE ON TABLE %s TO %I',
  'program_templates,program_versions,student_plans,student_plan_versions,subjects,chapters,topics,student_topic_mastery,activities,study_sessions,test_definitions,test_definition_versions,test_attempts,test_responses,exams,exam_results,classes,class_sessions,assignments,reviews,daily_routines,progress_snapshots,risk_assessments,counselor_notes,private_file_objects,notification_preferences,in_app_notifications',
  'ws_'||current_setting('app.workspace_key')||'_runtime') \gexec
-- Authorization source tables are read-only to the general runtime role.
-- Membership, role, permission, branch, counselor assignment and guardian grants
-- must be changed only through a separately reviewed, audited authorization workflow.
SELECT format('GRANT SELECT ON TABLE workspace_memberships,membership_roles,membership_permissions,branches,counselor_assignments,student_guardian_links,guardian_permissions TO %I',
  'ws_'||current_setting('app.workspace_key')||'_runtime') \gexec
SELECT format('GRANT SELECT,INSERT ON TABLE students,enrollments TO %I',
  'ws_'||current_setting('app.workspace_key')||'_runtime') \gexec
SELECT format('GRANT UPDATE(display_name) ON TABLE students TO %I',
  'ws_'||current_setting('app.workspace_key')||'_runtime') \gexec
SELECT format('GRANT SELECT ON TABLE workspace_profile,credit_wallets,workspace_capacity_counters TO %I',
  'ws_'||current_setting('app.workspace_key')||'_runtime') \gexec
SELECT format('GRANT INSERT ON TABLE audit_events TO %I',
  'ws_'||current_setting('app.workspace_key')||'_runtime') \gexec

-- Governance history is deny-by-default for all existing Workspace service roles.
-- No runtime, worker, exporter or activation function owner may write/read the ledger
-- or execute its append function until a dedicated trusted authorization adapter is reviewed.
SELECT format('REVOKE ALL PRIVILEGES ON TABLE workspace_governance_events FROM %I,%I,%I,%I',
  'ws_'||current_setting('app.workspace_key')||'_runtime',
  'ws_'||current_setting('app.workspace_key')||'_worker',
  'ws_'||current_setting('app.workspace_key')||'_exporter',
  'ws_'||current_setting('app.workspace_key')||'_function_owner') \gexec
SELECT format('REVOKE ALL ON FUNCTION append_workspace_governance_event(uuid,text,uuid,text,uuid,text,text,text,text,bytea,jsonb,timestamptz) FROM PUBLIC,%I,%I,%I,%I',
  'ws_'||current_setting('app.workspace_key')||'_runtime',
  'ws_'||current_setting('app.workspace_key')||'_worker',
  'ws_'||current_setting('app.workspace_key')||'_exporter',
  'ws_'||current_setting('app.workspace_key')||'_function_owner') \gexec

-- Workers can process only in-app notification delivery state; no student-domain table access.
SELECT format('GRANT SELECT,UPDATE ON TABLE in_app_notifications TO %I',
  'ws_'||current_setting('app.workspace_key')||'_worker') \gexec
SELECT format('GRANT SELECT ON TABLE notification_preferences TO %I',
  'ws_'||current_setting('app.workspace_key')||'_worker') \gexec

-- Exporter deliberately receives no base-table access. It remains deny-by-default until
-- separately reviewed, scope-safe export views are created and explicitly granted.

-- SECURITY DEFINER activation function owner has only the DML needed for its transaction.
SELECT format(
  'GRANT SELECT ON TABLE enrollments,students,counselor_assignments,workspace_memberships,credit_wallets,credit_transactions,activation_command_log,workspace_capacity_counters,capacity_events TO %I',
  'ws_'||current_setting('app.workspace_key')||'_function_owner') \gexec
SELECT format(
  'GRANT INSERT ON TABLE credit_transactions,activation_command_log,capacity_events,audit_events TO %I',
  'ws_'||current_setting('app.workspace_key')||'_function_owner') \gexec
SELECT format(
  'GRANT UPDATE(student_id) ON TABLE students TO %I',
  'ws_'||current_setting('app.workspace_key')||'_function_owner') \gexec
SELECT format(
  'GRANT UPDATE(state,started_at) ON TABLE enrollments TO %I',
  'ws_'||current_setting('app.workspace_key')||'_function_owner') \gexec
SELECT format(
  'GRANT UPDATE(current_value,updated_at) ON TABLE workspace_capacity_counters TO %I',
  'ws_'||current_setting('app.workspace_key')||'_function_owner') \gexec
-- Narrow UPDATE privileges exist only to permit SELECT ... FOR UPDATE row locks.
-- Append-only/immutable triggers reject any actual change to these lock-only columns.
SELECT format('GRANT UPDATE(wallet_id) ON TABLE credit_wallets TO %I',
  'ws_'||current_setting('app.workspace_key')||'_function_owner') \gexec
SELECT format('GRANT UPDATE(transaction_id) ON TABLE credit_transactions TO %I',
  'ws_'||current_setting('app.workspace_key')||'_function_owner') \gexec
SELECT format('GRANT UPDATE(idempotency_key) ON TABLE activation_command_log TO %I',
  'ws_'||current_setting('app.workspace_key')||'_function_owner') \gexec
SELECT format('GRANT EXECUTE ON FUNCTION adjust_workspace_capacity(text,integer,text,uuid,uuid,text) TO %I',
  'ws_'||current_setting('app.workspace_key')||'_function_owner') \gexec
SELECT format('GRANT EXECUTE ON FUNCTION activate_student_enrollment(text,uuid,uuid,bigint,bigint,uuid) TO %I',
  'ws_'||current_setting('app.workspace_key')||'_runtime') \gexec
SELECT format('REVOKE ALL ON FUNCTION adjust_workspace_capacity(text,integer,text,uuid,uuid,text) FROM PUBLIC,%I,%I,%I',
  'ws_'||current_setting('app.workspace_key')||'_runtime',
  'ws_'||current_setting('app.workspace_key')||'_worker',
  'ws_'||current_setting('app.workspace_key')||'_exporter') \gexec
SELECT format('REVOKE ALL ON FUNCTION activate_student_enrollment(text,uuid,uuid,bigint,bigint,uuid) FROM PUBLIC,%I,%I,%I',
  'ws_'||current_setting('app.workspace_key')||'_worker',
  'ws_'||current_setting('app.workspace_key')||'_exporter',
  'ws_'||current_setting('app.workspace_key')||'_function_owner') \gexec

-- Archive command (workspace_archive_transactions.sql). Applied only when that draft is loaded.
SELECT to_regprocedure('archive_student_enrollment(text,uuid,bigint,uuid,text)') IS NOT NULL AS has_archive \gset
\if :has_archive
SELECT format('GRANT SELECT,INSERT ON TABLE archive_command_log TO %I','ws_'||current_setting('app.workspace_key')||'_function_owner') \gexec
SELECT format('GRANT UPDATE(idempotency_key) ON TABLE archive_command_log TO %I','ws_'||current_setting('app.workspace_key')||'_function_owner') \gexec
SELECT format('GRANT UPDATE(state,ended_at) ON TABLE enrollments TO %I','ws_'||current_setting('app.workspace_key')||'_function_owner') \gexec
SELECT format('GRANT UPDATE(state,ended_at) ON TABLE counselor_assignments TO %I','ws_'||current_setting('app.workspace_key')||'_function_owner') \gexec
SELECT format('GRANT UPDATE(lifecycle_state,archived_at) ON TABLE students TO %I','ws_'||current_setting('app.workspace_key')||'_function_owner') \gexec
SELECT format('GRANT EXECUTE ON FUNCTION archive_student_enrollment(text,uuid,bigint,uuid,text) TO %I','ws_'||current_setting('app.workspace_key')||'_runtime') \gexec
SELECT format('REVOKE ALL ON FUNCTION archive_student_enrollment(text,uuid,bigint,uuid,text) FROM PUBLIC,%I,%I,%I',
  'ws_'||current_setting('app.workspace_key')||'_worker','ws_'||current_setting('app.workspace_key')||'_exporter',
  'ws_'||current_setting('app.workspace_key')||'_function_owner') \gexec
\endif

SELECT format('GRANT CREATE,USAGE ON SCHEMA public TO %I',
  'ws_'||current_setting('app.workspace_key')||'_governance_owner') \gexec

-- A dedicated non-login owner isolates the governance materializer from the broader
-- activation function owner. It has only the minimum DML needed for supported projections.
SELECT format('GRANT SELECT,INSERT ON TABLE workspace_governance_events TO %I',
  'ws_'||current_setting('app.workspace_key')||'_governance_owner') \gexec
SELECT format('GRANT SELECT,INSERT,DELETE ON TABLE membership_roles TO %I',
  'ws_'||current_setting('app.workspace_key')||'_governance_owner') \gexec
SELECT format('GRANT SELECT,INSERT,UPDATE,DELETE ON TABLE membership_permissions TO %I',
  'ws_'||current_setting('app.workspace_key')||'_governance_owner') \gexec
SELECT format('GRANT SELECT ON TABLE workspace_memberships TO %I',
  'ws_'||current_setting('app.workspace_key')||'_governance_owner') \gexec
SELECT format('GRANT UPDATE(status,ended_at) ON TABLE workspace_memberships TO %I',
  'ws_'||current_setting('app.workspace_key')||'_governance_owner') \gexec
SELECT format('ALTER FUNCTION append_workspace_governance_event(uuid,text,uuid,text,uuid,text,text,text,text,bytea,jsonb,timestamptz) OWNER TO %I',
  'ws_'||current_setting('app.workspace_key')||'_governance_owner') \gexec
SELECT format('GRANT EXECUTE ON FUNCTION append_workspace_governance_event(uuid,text,uuid,text,uuid,text,text,text,text,bytea,jsonb,timestamptz) TO %I',
  'ws_'||current_setting('app.workspace_key')||'_governance_owner') \gexec
SELECT format('REVOKE CREATE ON SCHEMA public FROM %I',
  'ws_'||current_setting('app.workspace_key')||'_governance_owner') \gexec
SELECT format('REVOKE ALL ON FUNCTION append_workspace_governance_event(uuid,text,uuid,text,uuid,text,text,text,text,bytea,jsonb,timestamptz) FROM PUBLIC,%I,%I,%I,%I',
  'ws_'||current_setting('app.workspace_key')||'_runtime',
  'ws_'||current_setting('app.workspace_key')||'_worker',
  'ws_'||current_setting('app.workspace_key')||'_exporter',
  'ws_'||current_setting('app.workspace_key')||'_function_owner') \gexec

-- Default privileges remain deny-by-default for future migrations.
SELECT format('ALTER DEFAULT PRIVILEGES FOR ROLE %I IN SCHEMA public REVOKE ALL ON TABLES FROM PUBLIC',
  'ws_'||current_setting('app.workspace_key')||'_table_owner') \gexec
SELECT format('ALTER DEFAULT PRIVILEGES FOR ROLE %I IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC',
  'ws_'||current_setting('app.workspace_key')||'_function_owner') \gexec

DO $done$
BEGIN
  RAISE NOTICE 'Workspace role setup complete for key % and database %',
    current_setting('app.workspace_key'),current_database();
END $done$;
