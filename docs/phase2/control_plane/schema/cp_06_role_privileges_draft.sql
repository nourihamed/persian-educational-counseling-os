-- CONTROL PLANE — DRAFT least-privilege roles and grants.
-- Apply only in an isolated test database after cp_01..cp_07. Requires a privileged
-- migration operator. Do not apply to production without security review.
-- SECURITY BOUNDARY: each SECURITY DEFINER family has a distinct NOLOGIN owner.
BEGIN;

DO $roles$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='cp_table_owner') THEN
    CREATE ROLE cp_table_owner NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='cp_transfer_function_owner') THEN
    CREATE ROLE cp_transfer_function_owner NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='cp_rotation_function_owner') THEN
    CREATE ROLE cp_rotation_function_owner NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='cp_identity_admission_function_owner') THEN
    CREATE ROLE cp_identity_admission_function_owner NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='cp_runtime') THEN
    CREATE ROLE cp_runtime NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='cp_transfer_executor') THEN
    CREATE ROLE cp_transfer_executor NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='cp_rotation_executor') THEN
    CREATE ROLE cp_rotation_executor NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='cp_identity_admission_executor') THEN
    CREATE ROLE cp_identity_admission_executor NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS;
  END IF;
END $roles$;

REVOKE CREATE ON SCHEMA public FROM PUBLIC;
GRANT USAGE ON SCHEMA public TO
  cp_table_owner,cp_transfer_function_owner,cp_rotation_function_owner,
  cp_identity_admission_function_owner,cp_runtime,cp_transfer_executor,
  cp_rotation_executor,cp_identity_admission_executor;

-- Temporary CREATE is required by PostgreSQL when changing function ownership.
GRANT CREATE ON SCHEMA public TO
  cp_transfer_function_owner,cp_rotation_function_owner,cp_identity_admission_function_owner;

ALTER TABLE workspaces OWNER TO cp_table_owner;
ALTER TABLE platform_students OWNER TO cp_table_owner;
ALTER TABLE student_contact_index OWNER TO cp_table_owner;
ALTER TABLE mobile_encryption_key_versions OWNER TO cp_table_owner;
ALTER TABLE mobile_hmac_key_versions OWNER TO cp_table_owner;
ALTER TABLE identity_write_gate OWNER TO cp_table_owner;
ALTER TABLE student_ownership OWNER TO cp_table_owner;
ALTER TABLE enrollment_claims OWNER TO cp_table_owner;
ALTER TABLE enrollment_claim_identity_aliases OWNER TO cp_table_owner;
ALTER TABLE transfer_cases OWNER TO cp_table_owner;
ALTER TABLE transfer_approvals OWNER TO cp_table_owner;
ALTER TABLE transfer_approval_revocations OWNER TO cp_table_owner;
ALTER VIEW transfer_approvals_current OWNER TO cp_table_owner;
ALTER TABLE command_log OWNER TO cp_table_owner;
ALTER TABLE identity_admission_commands OWNER TO cp_table_owner;
ALTER TABLE inbox_events OWNER TO cp_table_owner;
ALTER TABLE outbox_events OWNER TO cp_table_owner;
ALTER TABLE ownership_history OWNER TO cp_table_owner;
ALTER TABLE transfer_state_transitions OWNER TO cp_table_owner;
ALTER SEQUENCE ownership_history_history_id_seq OWNER TO cp_table_owner;

REVOKE ALL ON ALL TABLES IN SCHEMA public FROM PUBLIC;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM PUBLIC;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA public FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM
  cp_runtime,cp_transfer_executor,cp_rotation_executor,cp_identity_admission_executor,
  cp_transfer_function_owner,cp_rotation_function_owner,cp_identity_admission_function_owner;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM
  cp_runtime,cp_transfer_executor,cp_rotation_executor,cp_identity_admission_executor,
  cp_transfer_function_owner,cp_rotation_function_owner,cp_identity_admission_function_owner;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA public FROM
  cp_runtime,cp_transfer_executor,cp_rotation_executor,cp_identity_admission_executor,
  cp_transfer_function_owner,cp_rotation_function_owner,cp_identity_admission_function_owner;

-- Transfer owner: only the records read/written by transfer commands and their transition guard.
GRANT SELECT ON transfer_cases,transfer_approvals,transfer_approval_revocations,student_ownership,enrollment_claims,
  identity_write_gate,mobile_hmac_key_versions,enrollment_claim_identity_aliases,student_contact_index,
  transfer_state_transitions,command_log TO cp_transfer_function_owner;
-- FOR SHARE requires UPDATE privilege on at least one column. singleton is CHECK-constrained TRUE,
-- so these two owners can take the gate lock but cannot change maintenance state or epoch.
GRANT UPDATE (singleton) ON identity_write_gate
  TO cp_transfer_function_owner,cp_identity_admission_function_owner;
GRANT INSERT ON transfer_cases,ownership_history,outbox_events,command_log TO cp_transfer_function_owner;
GRANT UPDATE ON transfer_cases,student_ownership,enrollment_claims,
  enrollment_claim_identity_aliases,command_log TO cp_transfer_function_owner;
GRANT EXECUTE ON FUNCTION assert_claim_alias_coverage(uuid)
  TO cp_transfer_function_owner;
GRANT USAGE ON SEQUENCE ownership_history_history_id_seq TO cp_transfer_function_owner;

-- Rotation owner: identity gate, HMAC key lifecycle and alias/contact-index retirement only.
GRANT SELECT ON identity_write_gate,mobile_hmac_key_versions,enrollment_claims,
  enrollment_claim_identity_aliases,student_contact_index TO cp_rotation_function_owner;
GRANT UPDATE ON identity_write_gate,mobile_hmac_key_versions TO cp_rotation_function_owner;
GRANT DELETE ON enrollment_claim_identity_aliases,student_contact_index TO cp_rotation_function_owner;
GRANT EXECUTE ON FUNCTION assert_claim_alias_coverage(uuid),
  assert_all_claim_alias_coverage() TO cp_rotation_function_owner;

-- Initial admission owner: create the initial identity graph; no transfer/rotation access.
GRANT SELECT ON identity_write_gate,mobile_hmac_key_versions,mobile_encryption_key_versions,
  workspaces,enrollment_claims,enrollment_claim_identity_aliases,student_contact_index,
  identity_admission_commands TO cp_identity_admission_function_owner;
GRANT INSERT ON platform_students,student_ownership,enrollment_claims,
  student_contact_index,enrollment_claim_identity_aliases,identity_admission_commands
  TO cp_identity_admission_function_owner;
GRANT UPDATE (workspace_id) ON workspaces TO cp_identity_admission_function_owner;
-- FOR UPDATE on the append-only admission command requires UPDATE on a column.
-- The existing BEFORE UPDATE trigger rejects all mutations, so this grant permits locking only.
GRANT UPDATE (idempotency_key) ON identity_admission_commands TO cp_identity_admission_function_owner;
GRANT EXECUTE ON FUNCTION assert_claim_alias_coverage(uuid)
  TO cp_identity_admission_function_owner;

-- Assign each SECURITY DEFINER family to its own non-login owner.
ALTER FUNCTION switch_student_ownership(uuid) OWNER TO cp_transfer_function_owner;
ALTER FUNCTION request_transfer_case_idempotent(text,bytea,uuid,uuid,uuid,uuid,bigint,text)
  OWNER TO cp_transfer_function_owner;
ALTER FUNCTION begin_identity_hmac_rotation() OWNER TO cp_rotation_function_owner;
ALTER FUNCTION complete_identity_hmac_rotation(integer) OWNER TO cp_rotation_function_owner;
ALTER FUNCTION retire_identity_hmac_version(integer) OWNER TO cp_rotation_function_owner;
ALTER FUNCTION admit_student_identity_claim(text,bytea,uuid,uuid,uuid,text,bytea,integer,jsonb)
  OWNER TO cp_identity_admission_function_owner;

-- Executor roles expose only their intended function capabilities.
GRANT EXECUTE ON FUNCTION switch_student_ownership(uuid),
  request_transfer_case_idempotent(text,bytea,uuid,uuid,uuid,uuid,bigint,text)
  TO cp_transfer_executor;
GRANT EXECUTE ON FUNCTION begin_identity_hmac_rotation(),
  complete_identity_hmac_rotation(integer),retire_identity_hmac_version(integer)
  TO cp_rotation_executor;
GRANT EXECUTE ON FUNCTION admit_student_identity_claim(text,bytea,uuid,uuid,uuid,text,bytea,integer,jsonb)
  TO cp_identity_admission_executor;

-- Remove temporary schema creation rights; owners retain USAGE only.
REVOKE CREATE ON SCHEMA public FROM
  cp_transfer_function_owner,cp_rotation_function_owner,cp_identity_admission_function_owner;

COMMIT;
