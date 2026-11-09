-- CONTROL PLANE — DRAFT least-privilege roles and grants.
-- Apply only in an isolated test database after cp_01..cp_05. Requires a privileged
-- migration operator. Do not apply to production without security review.
BEGIN;

DO $roles$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='cp_table_owner') THEN
    CREATE ROLE cp_table_owner NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='cp_function_owner') THEN
    CREATE ROLE cp_function_owner NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS;
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
END $roles$;

REVOKE CREATE ON SCHEMA public FROM PUBLIC;
GRANT CREATE ON SCHEMA public TO cp_table_owner,cp_function_owner;
GRANT USAGE ON SCHEMA public TO cp_function_owner,cp_runtime,cp_transfer_executor,cp_rotation_executor;

-- The table owner is a non-login role. The function owner is deliberately not a table owner.
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
ALTER TABLE command_log OWNER TO cp_table_owner;
ALTER TABLE inbox_events OWNER TO cp_table_owner;
ALTER TABLE outbox_events OWNER TO cp_table_owner;
ALTER TABLE ownership_history OWNER TO cp_table_owner;
ALTER TABLE transfer_state_transitions OWNER TO cp_table_owner;

REVOKE ALL ON ALL TABLES IN SCHEMA public FROM PUBLIC;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM PUBLIC;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA public FROM PUBLIC;

-- Only the non-login SECURITY DEFINER owner can mutate protected tables.
GRANT SELECT,INSERT,UPDATE,DELETE ON
  workspaces,platform_students,student_contact_index,mobile_encryption_key_versions,
  mobile_hmac_key_versions,identity_write_gate,student_ownership,enrollment_claims,
  enrollment_claim_identity_aliases,transfer_cases,transfer_approvals,command_log,
  inbox_events,outbox_events,ownership_history,transfer_state_transitions
TO cp_function_owner;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO cp_function_owner;

-- Runtime roles have no direct table privileges.
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM cp_runtime,cp_transfer_executor,cp_rotation_executor;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA public FROM cp_runtime,cp_transfer_executor,cp_rotation_executor;

-- Transfer service receives only the two ownership-changing operations.
ALTER FUNCTION switch_student_ownership(uuid) OWNER TO cp_function_owner;
ALTER FUNCTION request_transfer_case_idempotent(text,bytea,uuid,uuid,uuid,uuid,bigint,text) OWNER TO cp_function_owner;
GRANT EXECUTE ON FUNCTION switch_student_ownership(uuid) TO cp_transfer_executor;
GRANT EXECUTE ON FUNCTION request_transfer_case_idempotent(text,bytea,uuid,uuid,uuid,uuid,bigint,text) TO cp_transfer_executor;

-- Rotation service receives only the version lifecycle operations.
ALTER FUNCTION begin_identity_hmac_rotation() OWNER TO cp_function_owner;
ALTER FUNCTION complete_identity_hmac_rotation(integer) OWNER TO cp_function_owner;
ALTER FUNCTION retire_identity_hmac_version(integer) OWNER TO cp_function_owner;
GRANT EXECUTE ON FUNCTION begin_identity_hmac_rotation() TO cp_rotation_executor;
GRANT EXECUTE ON FUNCTION complete_identity_hmac_rotation(integer) TO cp_rotation_executor;
GRANT EXECUTE ON FUNCTION retire_identity_hmac_version(integer) TO cp_rotation_executor;

COMMIT;
