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
  bad text;
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
    ELSE
      -- F-05 follow-up: a role of this name that ALREADY exists is validated against exactly the attributes
      -- this block would have created it with, and never altered. Roles are cluster-wide, so it may have been
      -- created by anyone, in any state. Any difference aborts the bootstrap (fail closed, nothing repaired).
      -- Its memberships are checked after the grants below, by plan_identity_boundary_violations().
      SELECT string_agg(x, ', ') INTO bad FROM (
        SELECT unnest(ARRAY[
          CASE WHEN r.rolcanlogin <> (right(role_name,6)='_login')
               THEN CASE WHEN r.rolcanlogin THEN 'LOGIN (expected NOLOGIN)' ELSE 'NOLOGIN (expected LOGIN)' END END,
          CASE WHEN r.rolinherit <> (right(role_name,6)='_login')
               THEN CASE WHEN r.rolinherit THEN 'INHERIT (expected NOINHERIT)' ELSE 'NOINHERIT (expected INHERIT)' END END,
          CASE WHEN r.rolsuper       THEN 'SUPERUSER' END,
          CASE WHEN r.rolcreatedb    THEN 'CREATEDB' END,
          CASE WHEN r.rolcreaterole  THEN 'CREATEROLE' END,
          CASE WHEN r.rolreplication THEN 'REPLICATION' END,
          CASE WHEN r.rolbypassrls   THEN 'BYPASSRLS' END]) AS x
          FROM pg_roles r WHERE r.rolname = role_name) z
       WHERE x IS NOT NULL;
      IF bad IS NOT NULL THEN
        RAISE EXCEPTION 'F-05: pre-existing application role % has unexpected attributes (%); bootstrap aborted, nothing repaired', role_name, bad
          USING ERRCODE = 'insufficient_privilege';
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
  'program_templates,program_versions,student_plans,student_plan_versions,subjects,chapters,topics,student_topic_mastery,activities,study_sessions,test_definitions,test_definition_versions,test_definition_version_questions,test_attempts,test_responses,exams,exam_results,classes,class_sessions,class_participants,class_session_participants,assignments,reviews,daily_routines,progress_snapshots,risk_assessments,counselor_notes,private_file_objects,notification_preferences,in_app_notifications',
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
  'GRANT SELECT ON TABLE enrollments,students,counselor_assignments,workspace_memberships,credit_wallets,credit_transactions,activation_command_log,workspace_capacity_counters,capacity_events,student_entitlements TO %I',
  'ws_'||current_setting('app.workspace_key')||'_function_owner') \gexec
SELECT format(
  'GRANT INSERT ON TABLE credit_transactions,activation_command_log,capacity_events,audit_events,student_entitlements TO %I',
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
-- The entitlement row is the only credit object the command owner may transition (reserve/re-consume).
-- Identity, amount, activation time and period end stay immutable through the row guard.
SELECT format('GRANT UPDATE(state,reserved_at,reconsumed_at,reversal_transaction_id) ON TABLE student_entitlements TO %I',
  'ws_'||current_setting('app.workspace_key')||'_function_owner') \gexec
SELECT format('GRANT SELECT ON TABLE student_entitlements TO %I',
  'ws_'||current_setting('app.workspace_key')||'_runtime') \gexec
SELECT format('GRANT UPDATE(transaction_id) ON TABLE credit_transactions TO %I',
  'ws_'||current_setting('app.workspace_key')||'_function_owner') \gexec
SELECT format('GRANT UPDATE(idempotency_key) ON TABLE activation_command_log TO %I',
  'ws_'||current_setting('app.workspace_key')||'_function_owner') \gexec
SELECT format('GRANT EXECUTE ON FUNCTION adjust_workspace_capacity(text,integer,text,uuid,uuid,text) TO %I',
  'ws_'||current_setting('app.workspace_key')||'_function_owner') \gexec
-- H-02: the Runtime gets ONLY the production-intended path, which fails closed while OQ-CRD-3 is open.
SELECT format('GRANT EXECUTE ON FUNCTION activate_student_enrollment(text,uuid,uuid,bigint,bigint,uuid) TO %I',
  'ws_'||current_setting('app.workspace_key')||'_runtime') \gexec
-- The caller-supplied-period command is synthetic (D-014) and belongs to one dedicated test identity.
DO $synth_role$
DECLARE r text := 'ws_'||current_setting('app.workspace_key')||'_synth_exec';
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname=r) THEN
    EXECUTE format('CREATE ROLE %I NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS', r);
  END IF;
END $synth_role$;
SELECT format('GRANT EXECUTE ON FUNCTION activate_student_enrollment_synthetic(text,uuid,uuid,bigint,bigint,uuid,timestamptz) TO %I',
  'ws_'||current_setting('app.workspace_key')||'_synth_exec') \gexec
SELECT format('REVOKE ALL ON FUNCTION activate_student_enrollment_synthetic(text,uuid,uuid,bigint,bigint,uuid,timestamptz) FROM PUBLIC,%I,%I,%I,%I',
  'ws_'||current_setting('app.workspace_key')||'_runtime','ws_'||current_setting('app.workspace_key')||'_worker',
  'ws_'||current_setting('app.workspace_key')||'_exporter','ws_'||current_setting('app.workspace_key')||'_function_owner') \gexec
SELECT format('REVOKE ALL ON FUNCTION resolve_student_entitlement_period(uuid,bigint,timestamptz) FROM PUBLIC,%I,%I,%I',
  'ws_'||current_setting('app.workspace_key')||'_runtime','ws_'||current_setting('app.workspace_key')||'_worker','ws_'||current_setting('app.workspace_key')||'_exporter') \gexec
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
SELECT format('GRANT SELECT,INSERT ON TABLE reactivation_command_log TO %I','ws_'||current_setting('app.workspace_key')||'_function_owner') \gexec
SELECT format('GRANT SELECT ON TABLE membership_roles TO %I','ws_'||current_setting('app.workspace_key')||'_function_owner') \gexec
-- The approved reversal-window rule is a pure policy function. The command owner evaluates it; the runtime
-- may read the deadline to display it. Neither can change the rule: that needs a schema change.
SELECT format('GRANT EXECUTE ON FUNCTION credit_reversal_window_end(timestamptz) TO %I,%I',
  'ws_'||current_setting('app.workspace_key')||'_function_owner','ws_'||current_setting('app.workspace_key')||'_runtime') \gexec
SELECT format('GRANT EXECUTE ON FUNCTION credit_reversal_eligible(timestamptz,timestamptz) TO %I,%I',
  'ws_'||current_setting('app.workspace_key')||'_function_owner','ws_'||current_setting('app.workspace_key')||'_runtime') \gexec
SELECT format('GRANT UPDATE(idempotency_key) ON TABLE reactivation_command_log TO %I','ws_'||current_setting('app.workspace_key')||'_function_owner') \gexec
SELECT format('GRANT INSERT ON TABLE enrollments,counselor_assignments TO %I','ws_'||current_setting('app.workspace_key')||'_function_owner') \gexec
SELECT format('GRANT UPDATE(state,started_at) ON TABLE enrollments TO %I','ws_'||current_setting('app.workspace_key')||'_function_owner') \gexec
SELECT format('GRANT EXECUTE ON FUNCTION reactivate_student_enrollment(text,uuid,uuid,bigint,uuid,uuid) TO %I','ws_'||current_setting('app.workspace_key')||'_runtime') \gexec
SELECT format('REVOKE ALL ON FUNCTION reactivate_student_enrollment(text,uuid,uuid,bigint,uuid,uuid) FROM PUBLIC,%I,%I,%I',
  'ws_'||current_setting('app.workspace_key')||'_worker','ws_'||current_setting('app.workspace_key')||'_exporter','ws_'||current_setting('app.workspace_key')||'_function_owner') \gexec
\endif

-- Source transfer freeze and write barrier (workspace_transfer_freeze.sql). Applied only when loaded.
SELECT to_regprocedure('freeze_student_for_transfer(uuid,text,uuid,uuid,bigint,text,integer,timestamptz)') IS NOT NULL AS has_freeze \gset
\if :has_freeze
DO $freeze_role$
DECLARE r text := 'ws_'||current_setting('app.workspace_key')||'_transfer_ctl';
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname=r) THEN
    EXECUTE format('CREATE ROLE %I NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS', r);
  END IF;
END $freeze_role$;
DO $freeze_owner$
DECLARE r text := 'ws_'||current_setting('app.workspace_key')||'_freeze_owner';
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname=r) THEN
    EXECUTE format('CREATE ROLE %I NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS', r);
  END IF;
END $freeze_owner$;
SELECT format('ALTER FUNCTION freeze_student_for_transfer(uuid,text,uuid,uuid,bigint,text,integer,timestamptz) OWNER TO %I',
  'ws_'||current_setting('app.workspace_key')||'_freeze_owner') \gexec
SELECT format('ALTER FUNCTION unfreeze_student_after_abort(text,uuid,text) OWNER TO %I',
  'ws_'||current_setting('app.workspace_key')||'_freeze_owner') \gexec
SELECT format('GRANT SELECT ON TABLE students,enrollments,workspace_inbox_events TO %I',
  'ws_'||current_setting('app.workspace_key')||'_freeze_owner') \gexec
SELECT format('GRANT UPDATE(student_id) ON TABLE students TO %I', 'ws_'||current_setting('app.workspace_key')||'_freeze_owner') \gexec
SELECT format('GRANT UPDATE(enrollment_id) ON TABLE enrollments TO %I', 'ws_'||current_setting('app.workspace_key')||'_freeze_owner') \gexec
SELECT format('GRANT SELECT,INSERT,UPDATE ON TABLE student_transfer_freezes TO %I',
  'ws_'||current_setting('app.workspace_key')||'_freeze_owner') \gexec
SELECT format('GRANT SELECT ON TABLE student_write_barrier_bypass TO %I', 'ws_'||current_setting('app.workspace_key')||'_freeze_owner') \gexec
SELECT format('ALTER FUNCTION assert_student_not_frozen(uuid) OWNER TO %I', 'ws_'||current_setting('app.workspace_key')||'_freeze_owner') \gexec
SELECT format('GRANT INSERT ON TABLE audit_events TO %I', 'ws_'||current_setting('app.workspace_key')||'_freeze_owner') \gexec
-- Only the transfer controller may freeze or unfreeze. The Workspace runtime, worker and exporter cannot,
-- and no identity may write the freeze record or the barrier exemption directly.
SELECT format('GRANT EXECUTE ON FUNCTION freeze_student_for_transfer(uuid,text,uuid,uuid,bigint,text,integer,timestamptz) TO %I',
  'ws_'||current_setting('app.workspace_key')||'_transfer_ctl') \gexec
SELECT format('GRANT EXECUTE ON FUNCTION unfreeze_student_after_abort(text,uuid,text) TO %I',
  'ws_'||current_setting('app.workspace_key')||'_transfer_ctl') \gexec
SELECT format('REVOKE ALL ON FUNCTION freeze_student_for_transfer(uuid,text,uuid,uuid,bigint,text,integer,timestamptz) FROM PUBLIC,%I,%I,%I,%I',
  'ws_'||current_setting('app.workspace_key')||'_runtime','ws_'||current_setting('app.workspace_key')||'_worker','ws_'||current_setting('app.workspace_key')||'_exporter','ws_'||current_setting('app.workspace_key')||'_function_owner') \gexec
SELECT format('REVOKE ALL ON FUNCTION unfreeze_student_after_abort(text,uuid,text) FROM PUBLIC,%I,%I,%I,%I',
  'ws_'||current_setting('app.workspace_key')||'_runtime','ws_'||current_setting('app.workspace_key')||'_worker','ws_'||current_setting('app.workspace_key')||'_exporter','ws_'||current_setting('app.workspace_key')||'_function_owner') \gexec
SELECT format('REVOKE ALL ON TABLE student_transfer_freezes,student_write_barrier_bypass FROM PUBLIC,%I,%I,%I,%I,%I',
  'ws_'||current_setting('app.workspace_key')||'_runtime','ws_'||current_setting('app.workspace_key')||'_worker','ws_'||current_setting('app.workspace_key')||'_exporter','ws_'||current_setting('app.workspace_key')||'_function_owner',
  'ws_'||current_setting('app.workspace_key')||'_transfer_ctl') \gexec
SELECT format('GRANT SELECT ON TABLE student_transfer_freezes TO %I,%I',
  'ws_'||current_setting('app.workspace_key')||'_runtime','ws_'||current_setting('app.workspace_key')||'_transfer_ctl') \gexec
SELECT format('GRANT SELECT ON student_write_barrier_coverage TO %I', 'ws_'||current_setting('app.workspace_key')||'_runtime') \gexec
\endif

-- Saga inbox (workspace_inbox_projection.sql). Applied only when that draft is loaded.
SELECT to_regprocedure('apply_inbox_event_synthetic(uuid,integer,text,jsonb,bytea,uuid,uuid,uuid,bigint,uuid)') IS NOT NULL AS has_inbox \gset
\if :has_inbox
DO $inbox_role$
DECLARE r text := 'ws_'||current_setting('app.workspace_key')||'_inbox_owner';
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname=r) THEN
    EXECUTE format('CREATE ROLE %I NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS', r);
  END IF;
END $inbox_role$;
SELECT format('ALTER FUNCTION apply_inbox_event_synthetic(uuid,integer,text,jsonb,bytea,uuid,uuid,uuid,bigint,uuid) OWNER TO %I',
  'ws_'||current_setting('app.workspace_key')||'_inbox_owner') \gexec
SELECT format('ALTER FUNCTION apply_inbox_event(uuid,integer,text,jsonb,bytea,uuid,uuid,uuid,bigint,uuid) OWNER TO %I',
  'ws_'||current_setting('app.workspace_key')||'_inbox_owner') \gexec
SELECT format('ALTER FUNCTION assert_inbox_transport_verified(uuid) OWNER TO %I',
  'ws_'||current_setting('app.workspace_key')||'_inbox_owner') \gexec
SELECT format('GRANT SELECT ON TABLE workspace_profile,students,enrollments,counselor_assignments TO %I',
  'ws_'||current_setting('app.workspace_key')||'_inbox_owner') \gexec
-- Row-lock privilege only; workspace_inbox_events is append-only through its trigger.
SELECT format('GRANT UPDATE(event_id) ON TABLE workspace_inbox_events TO %I',
  'ws_'||current_setting('app.workspace_key')||'_inbox_owner') \gexec
SELECT format('GRANT SELECT,INSERT,DELETE ON TABLE student_write_barrier_bypass TO %I',
  'ws_'||current_setting('app.workspace_key')||'_inbox_owner') \gexec
SELECT format('GRANT SELECT,UPDATE(state,fenced_at,fenced_generation) ON TABLE student_transfer_freezes TO %I',
  'ws_'||current_setting('app.workspace_key')||'_inbox_owner') \gexec
SELECT format('GRANT SELECT,INSERT ON TABLE workspace_inbox_events TO %I',
  'ws_'||current_setting('app.workspace_key')||'_inbox_owner') \gexec
-- Column-scoped: the inbox may move the local fence and close assignments, nothing else.
SELECT format('GRANT UPDATE(ownership_generation,state,ended_at) ON TABLE enrollments TO %I',
  'ws_'||current_setting('app.workspace_key')||'_inbox_owner') \gexec
SELECT format('GRANT UPDATE(state,ended_at) ON TABLE counselor_assignments TO %I',
  'ws_'||current_setting('app.workspace_key')||'_inbox_owner') \gexec
-- Row-lock privilege only (PostgreSQL requires UPDATE for SELECT ... FOR UPDATE). The student_id column
-- is immutable through students_primary_key_immutable, so this grant conveys no ability to change it.
SELECT format('GRANT UPDATE(student_id) ON TABLE students TO %I',
  'ws_'||current_setting('app.workspace_key')||'_inbox_owner') \gexec
-- H-05: the background worker is the consumer identity, and it gets ONLY the production-intended entry
-- point, which fails closed until an approved verified transport exists. The synthetic application path
-- belongs to one dedicated test identity and is unreachable for every operational role.
SELECT format('GRANT EXECUTE ON FUNCTION apply_inbox_event(uuid,integer,text,jsonb,bytea,uuid,uuid,uuid,bigint,uuid) TO %I',
  'ws_'||current_setting('app.workspace_key')||'_worker') \gexec
SELECT format('REVOKE ALL ON FUNCTION apply_inbox_event(uuid,integer,text,jsonb,bytea,uuid,uuid,uuid,bigint,uuid) FROM PUBLIC,%I,%I,%I',
  'ws_'||current_setting('app.workspace_key')||'_runtime','ws_'||current_setting('app.workspace_key')||'_exporter','ws_'||current_setting('app.workspace_key')||'_function_owner') \gexec
DO $synth_inbox$
DECLARE r text := 'ws_'||current_setting('app.workspace_key')||'_synth_inbox';
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname=r) THEN
    EXECUTE format('CREATE ROLE %I NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS', r);
  END IF;
END $synth_inbox$;
SELECT format('GRANT EXECUTE ON FUNCTION apply_inbox_event_synthetic(uuid,integer,text,jsonb,bytea,uuid,uuid,uuid,bigint,uuid) TO %I',
  'ws_'||current_setting('app.workspace_key')||'_synth_inbox') \gexec
SELECT format('REVOKE ALL ON FUNCTION apply_inbox_event_synthetic(uuid,integer,text,jsonb,bytea,uuid,uuid,uuid,bigint,uuid) FROM PUBLIC,%I,%I,%I,%I',
  'ws_'||current_setting('app.workspace_key')||'_runtime','ws_'||current_setting('app.workspace_key')||'_worker',
  'ws_'||current_setting('app.workspace_key')||'_exporter','ws_'||current_setting('app.workspace_key')||'_function_owner') \gexec
SELECT format('REVOKE ALL ON FUNCTION assert_inbox_transport_verified(uuid) FROM PUBLIC,%I,%I,%I',
  'ws_'||current_setting('app.workspace_key')||'_runtime','ws_'||current_setting('app.workspace_key')||'_worker','ws_'||current_setting('app.workspace_key')||'_exporter') \gexec
SELECT format('GRANT SELECT ON TABLE workspace_inbox_events TO %I,%I',
  'ws_'||current_setting('app.workspace_key')||'_runtime','ws_'||current_setting('app.workspace_key')||'_worker') \gexec
SELECT format('GRANT SELECT ON quarantined_inbox_events TO %I,%I',
  'ws_'||current_setting('app.workspace_key')||'_runtime','ws_'||current_setting('app.workspace_key')||'_worker') \gexec
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

-- ======================================================================================================
-- BATCH 8 — retention, legal hold and the disposition gate. Applied only when
-- workspace_operations_draft.sql is loaded in this database, because the freeze and inbox steps load the
-- roles file without it.
--
-- WHAT IS DELIBERATELY NOT GRANTED, AND WHY
--   * NO role receives INSERT or UPDATE on legal_holds. Who may place and who may release a hold is a
--     Product Owner decision (retention contract §9; register item OPS-HOLD-AUTH). Until it is made, only
--     the NOLOGIN table owner can write the table, which is a synthetic posture, not an authority model.
--   * NO role receives EXECUTE on assert_destructive_disposition_allowed(), and PUBLIC's default EXECUTE
--     is revoked. There is no disposition executor identity to grant it to (OPS-DISP-AUTH), and a gate
--     nobody may call is the correct fail-closed state while that authority is undecided.
--   * The gate owner gets COLUMN-SCOPED SELECT on the primary keys of the registered entity tables, not
--     table SELECT. An existence check needs the key and nothing else, and audit_events in particular
--     must not become readable by the function owner just so a row can be counted.
-- ======================================================================================================
DO $batch8$
DECLARE
  k text := current_setting('app.workspace_key');
  fo text := 'ws_'||k||'_function_owner';
BEGIN
  IF to_regclass('public.retention_entity_types') IS NULL THEN
    RETURN;
  END IF;
  EXECUTE format('GRANT SELECT ON TABLE retention_entity_types,retention_categories,'
                 'retention_policy_versions,legal_holds TO %I', fo);
  EXECUTE format('GRANT SELECT(file_id) ON TABLE private_file_objects TO %I', fo);
  EXECUTE format('GRANT SELECT(notification_id) ON TABLE in_app_notifications TO %I', fo);
  EXECUTE format('GRANT SELECT(audit_event_id) ON TABLE audit_events TO %I', fo);
  EXECUTE 'REVOKE ALL ON FUNCTION assert_destructive_disposition_allowed(text,uuid,text) FROM PUBLIC';
  EXECUTE format('REVOKE ALL ON FUNCTION assert_destructive_disposition_allowed(text,uuid,text) '
                 'FROM %I,%I,%I', 'ws_'||k||'_runtime', 'ws_'||k||'_worker', 'ws_'||k||'_exporter');
END $batch8$;

-- WS-ISO-01 boundary functions (workspace_counselor_scope_draft.sql) are SECURITY INVOKER and resolve a
-- row's owner through the student_scoped_tables catalog view, so the runtime needs to read that VIEW. It
-- holds no data: it lists table names and key columns derived from the system catalog.
DO $iso$
DECLARE k text := current_setting('app.workspace_key');
BEGIN
  IF to_regprocedure('public.counselor_may_access_row(uuid,text,text)') IS NULL THEN
    RETURN;
  END IF;
  EXECUTE format('GRANT SELECT ON TABLE student_scoped_tables TO %I', 'ws_'||k||'_runtime');
END $iso$;

-- WS-PLAN-01 (workspace_plan_items_draft.sql), corrected after the Supervisor review of d75d039.
--   F-01: the runtime holds SELECT ONLY on plan items and their status history. It cannot write either,
--         because no application identity can yet be authenticated as the actor a row names (WS-ISO-01).
--         The only writer is a dedicated NOLOGIN synthetic test identity (D-014).
--   F-02: the runtime may INSERT plan versions but may not NAME content_model (column-level privilege), so
--         everything it creates is normalized. legacy_json is writable only by a dedicated NOLOGIN migration
--         identity, which can do nothing else.
--   Both identities are recorded in plan_privileged_identities, and the triggers check the IDENTITY
--   (current_user, set by PostgreSQL, unlike a session variable, which the caller sets). Since F-05 this is
--   identity, not membership: holding the role is grounds for refusal, not acceptance.
DO $plan$
DECLARE
  k text := current_setting('app.workspace_key');
  rt text := 'ws_'||k||'_runtime';
  wr text := 'ws_'||k||'_synth_plan_writer';
  mg text := 'ws_'||k||'_plan_migrator';
  k0 text := current_setting('app.workspace_key');  -- k is reused as a loop variable below
  inv text[];
  bad text;
BEGIN
  IF to_regclass('public.plan_items') IS NULL THEN
    RETURN;
  END IF;
  -- F-05: an EXISTING privileged role is validated, never trusted and never silently repaired. Roles are
  -- cluster-wide, so a role of this name may predate this bootstrap, and nothing says who created it or why
  -- it looks the way it does. Any unexpected attribute or membership aborts the bootstrap. No reviewed
  -- procedure for repairing such a role exists (who may provision these identities is an open operational
  -- decision), so stopping is the only safe outcome.
  FOREACH k IN ARRAY ARRAY[wr, mg] LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = k) THEN
      EXECUTE format('CREATE ROLE %I NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS NOREPLICATION', k);
    ELSE
      SELECT string_agg(x, ', ') INTO bad FROM (
        SELECT unnest(ARRAY[
          CASE WHEN r.rolcanlogin    THEN 'LOGIN' END,
          CASE WHEN r.rolsuper       THEN 'SUPERUSER' END,
          CASE WHEN r.rolcreaterole  THEN 'CREATEROLE' END,
          CASE WHEN r.rolbypassrls   THEN 'BYPASSRLS' END,
          CASE WHEN r.rolreplication THEN 'REPLICATION' END,
          CASE WHEN r.rolcreatedb    THEN 'CREATEDB' END,
          CASE WHEN r.rolinherit     THEN 'INHERIT' END]) AS x
          FROM pg_roles r WHERE r.rolname = k
        UNION ALL
        SELECT 'held by ' || m.member::regrole::text FROM pg_auth_members m WHERE m.roleid = k::regrole
        UNION ALL
        SELECT 'member of ' || m.roleid::regrole::text FROM pg_auth_members m WHERE m.member = k::regrole
      ) z WHERE x IS NOT NULL;
      IF bad IS NOT NULL THEN
        RAISE EXCEPTION 'F-05: pre-existing privileged role % is unsafe (%); bootstrap aborted, nothing repaired', k, bad
          USING ERRCODE = 'insufficient_privilege';
      END IF;
    END IF;
  END LOOP;
  DELETE FROM plan_privileged_identities;
  INSERT INTO plan_privileged_identities(purpose, role_name, note) VALUES
   ('synthetic_plan_writer', wr, 'SYNTHETIC ONLY (D-014). Stands in for an authenticated actor until WS-ISO-01 caller binding exists. Not a production identity.'),
   ('legacy_plan_migrator',  mg, 'Migration of historical legacy_json plan versions only. Not granted to any application role.');

  -- runtime: read plan items, history and derived views; never write them
  EXECUTE format('REVOKE ALL ON TABLE plan_items, plan_item_status_events FROM %I', rt);
  EXECUTE format('GRANT SELECT ON TABLE plan_items, plan_item_status_events, plan_item_current_status, '
                 'plan_version_rendered, plan_privileged_identities, plan_item_transition_rules TO %I', rt);
  -- runtime: create plan versions WITHOUT being able to choose legacy_json
  EXECUTE format('REVOKE INSERT ON TABLE student_plan_versions FROM %I', rt);
  EXECUTE format('GRANT INSERT (plan_version_id, plan_id, version_no, source_program_version_id, input_snapshot, '
                 'rule_version, plan_content, status, approved_by_membership_id, created_at, published_at, '
                 'supersedes_plan_version_id, change_reason, created_by_membership_id) '
                 'ON TABLE student_plan_versions TO %I', rt);

  -- synthetic writer: exactly what writing items and transitions needs, and nothing else
  EXECUTE format('GRANT SELECT, INSERT ON TABLE plan_items, plan_item_status_events TO %I', wr);
  EXECUTE format('GRANT SELECT ON TABLE plan_item_current_status, plan_version_rendered, plan_privileged_identities, '
                 'plan_item_transition_rules, student_plan_versions, student_plans, counselor_assignments, enrollments, workspace_memberships, '
                 'membership_roles, students, topics, subtopics, activities, exams, reviews, assignments TO %I', wr);

  -- migration identity: insert plan versions (including legacy_json) and read what the guard reads
  EXECUTE format('GRANT SELECT, INSERT ON TABLE student_plan_versions TO %I', mg);
  EXECUTE format('GRANT SELECT ON TABLE plan_privileged_identities, plan_items, student_plans TO %I', mg);

  -- F-05: after every grant above, the whole boundary is checked against the actual catalog, for the actual
  -- role inventory of this file (the $roles$ list). It runs in THIS block on purpose: a violation aborts the
  -- block's transaction, so the identity records and grants above are rolled back too, and no session can
  -- then act as a privileged identity (plan_identity_is() finds no record). This is the point-in-time
  -- check; plan_identity_is() re-checks the privileged identities' own state on every write.
  inv := ARRAY['ws_'||k0||'_table_owner', 'ws_'||k0||'_function_owner', 'ws_'||k0||'_governance_owner',
               'ws_'||k0||'_runtime', 'ws_'||k0||'_worker', 'ws_'||k0||'_exporter',
               'ws_'||k0||'_runtime_login', 'ws_'||k0||'_worker_login', 'ws_'||k0||'_exporter_login'];
  SELECT string_agg(x, '; ') INTO bad FROM public.plan_identity_boundary_violations(inv) x;
  IF bad IS NOT NULL THEN
    RAISE EXCEPTION 'F-05: plan identity boundary violated; bootstrap aborted, nothing recorded: %', bad
      USING ERRCODE = 'insufficient_privilege';
  END IF;
  RAISE NOTICE 'F-05: plan identity boundary verified (% application roles, 2 privileged identities)', cardinality(inv);
END $plan$;

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

-- ======================================================================================================
-- WS-ISO-01 caller binding (Product Owner decision 2026-11-20: B with a test-only key).
-- Applied only where workspace_principal_assertion_draft.sql and workspace_counselor_rls_draft.sql were
-- loaded. Grants nothing that writes student data: the runtime receives EXECUTE on establish_principal()
-- only, and that function writes principal bookkeeping the runtime cannot otherwise read or write.
-- ======================================================================================================
DO $iso_principal$
DECLARE
  k  text := current_setting('app.workspace_key');
  fo text := 'ws_'||current_setting('app.workspace_key')||'_function_owner';
  rt text := 'ws_'||current_setting('app.workspace_key')||'_runtime';
  wr text := 'ws_'||current_setting('app.workspace_key')||'_synth_plan_writer';
  r  text;
BEGIN
  IF to_regclass('public.verified_principal_context') IS NULL THEN
    RETURN;
  END IF;
  -- the definer functions run as the function owner and need exactly these
  EXECUTE format('GRANT USAGE ON SCHEMA ext_crypto TO %I', fo);
  EXECUTE format('GRANT EXECUTE ON FUNCTION ext_crypto.hmac(bytea, bytea, text) TO %I', fo);
  EXECUTE format('GRANT SELECT ON TABLE principal_verification_config, principal_assertion_keys TO %I', fo);
  EXECUTE format('GRANT SELECT, INSERT ON TABLE principal_assertion_nonces TO %I', fo);
  EXECUTE format('GRANT SELECT, INSERT, UPDATE ON TABLE verified_principal_context TO %I', fo);
  EXECUTE format('GRANT SELECT ON TABLE workspace_profile, workspace_memberships, membership_roles, students, '
                 'enrollments, counselor_assignments, student_plans, test_attempts, student_guardian_links, '
                 'guardian_permissions TO %I', fo);
  -- the command boundary: the runtime may present an assertion, and nothing more
  EXECUTE format('GRANT EXECUTE ON FUNCTION establish_principal(text, text) TO %I', rt);
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = wr) THEN
    -- the synthetic plan writer acts for a verified principal in the isolated test harness only
    EXECUTE format('GRANT EXECUTE ON FUNCTION establish_principal(text, text) TO %I', wr);
  END IF;
  IF to_regclass('public.iso_application_roles') IS NOT NULL THEN
    EXECUTE format('GRANT SELECT ON TABLE iso_application_roles TO %I', fo);
    DELETE FROM iso_application_roles;
    FOREACH r IN ARRAY ARRAY['runtime','runtime_login','worker','worker_login','exporter','exporter_login'] LOOP
      INSERT INTO iso_application_roles(role_name) VALUES ('ws_'||k||'_'||r);
    END LOOP;
  END IF;
  IF to_regclass('public.iso_rls_bypass_roles') IS NOT NULL THEN
    EXECUTE format('GRANT SELECT ON TABLE iso_rls_bypass_roles TO %I', fo);
    DELETE FROM iso_rls_bypass_roles;
    FOREACH r IN ARRAY ARRAY['table_owner','function_owner','governance_owner','freeze_owner',
                              'inbox_owner','synth_exec','synth_inbox','synth_plan_writer','plan_migrator'] LOOP
      INSERT INTO iso_rls_bypass_roles(role_name) VALUES ('ws_'||k||'_'||r);
    END LOOP;
  END IF;
END $iso_principal$;
