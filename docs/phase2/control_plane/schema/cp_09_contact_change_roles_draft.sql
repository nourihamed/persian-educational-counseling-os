-- CONTROL PLANE — DRAFT: roles and grants for the contact-change command. Apply after cp_06 and cp_08.
-- Test-design roles (NOLOGIN); production role provisioning is deployment work. Synthetic only (D-014).
-- A separate owner/executor family, as the contract requires: it cannot transfer ownership, rotate keys or admit students.
-- cp_contact_proof_verifier mirrors Product Owner decision A1 (external independent verifier, registration only);
-- applying that pattern to contact-change proofs is a PROPOSAL for Supervisor / Product Owner review.
\set ON_ERROR_STOP on
DO $r$
DECLARE n text;
BEGIN
  FOREACH n IN ARRAY ARRAY['cp_contact_change_function_owner','cp_contact_change_executor','cp_contact_proof_verifier'] LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname=n) THEN
      EXECUTE format('CREATE ROLE %I NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS', n);
    END IF;
  END LOOP;
END $r$;

ALTER TABLE contact_change_proofs OWNER TO cp_table_owner;
ALTER TABLE contact_change_commands OWNER TO cp_table_owner;
ALTER TABLE student_contact_change_audit OWNER TO cp_table_owner;

REVOKE ALL ON contact_change_proofs,contact_change_commands,student_contact_change_audit FROM PUBLIC,
  cp_runtime,cp_transfer_executor,cp_rotation_executor,cp_identity_admission_executor,
  cp_transfer_function_owner,cp_rotation_function_owner,cp_identity_admission_function_owner,
  cp_contact_change_function_owner,cp_contact_change_executor,cp_contact_proof_verifier;
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM cp_contact_change_function_owner,cp_contact_change_executor,cp_contact_proof_verifier;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA public FROM cp_contact_change_function_owner,cp_contact_change_executor,cp_contact_proof_verifier;

GRANT USAGE ON SCHEMA public TO cp_contact_change_function_owner,cp_contact_change_executor,cp_contact_proof_verifier;

-- Verifier: registration only.
GRANT INSERT ON contact_change_proofs TO cp_contact_proof_verifier;

-- Function owner: exactly what the command reads and writes.
GRANT SELECT ON identity_write_gate,student_ownership,enrollment_claims,mobile_hmac_key_versions,
  mobile_encryption_key_versions,student_contact_index,enrollment_claim_identity_aliases,
  contact_change_proofs,contact_change_commands TO cp_contact_change_function_owner;
-- Row locks need UPDATE on at least one column. These columns are either CHECK-fixed or irrelevant to identity.
GRANT UPDATE (singleton) ON identity_write_gate TO cp_contact_change_function_owner;
GRANT UPDATE (updated_at) ON student_ownership TO cp_contact_change_function_owner;
GRANT UPDATE (created_at) ON enrollment_claims TO cp_contact_change_function_owner;
GRANT UPDATE (idempotency_key) ON contact_change_commands TO cp_contact_change_function_owner;   -- lock only; trigger rejects any change
GRANT UPDATE (mobile_hmac,mobile_ciphertext,cipher_key_version,updated_at) ON student_contact_index TO cp_contact_change_function_owner;
GRANT UPDATE (mobile_hmac) ON enrollment_claim_identity_aliases TO cp_contact_change_function_owner;
GRANT UPDATE (status,consumed_at,consumed_by_command) ON contact_change_proofs TO cp_contact_change_function_owner;
GRANT INSERT ON contact_change_commands,student_contact_change_audit,outbox_events TO cp_contact_change_function_owner;
GRANT EXECUTE ON FUNCTION assert_claim_alias_coverage(uuid),assert_all_claim_alias_coverage() TO cp_contact_change_function_owner;

ALTER FUNCTION change_student_mobile_contact(text,bytea,uuid,uuid,bigint,uuid,bytea,integer,jsonb)
  OWNER TO cp_contact_change_function_owner;
REVOKE ALL ON FUNCTION change_student_mobile_contact(text,bytea,uuid,uuid,bigint,uuid,bytea,integer,jsonb)
  FROM PUBLIC,cp_contact_change_function_owner;
GRANT EXECUTE ON FUNCTION change_student_mobile_contact(text,bytea,uuid,uuid,bigint,uuid,bytea,integer,jsonb)
  TO cp_contact_change_executor;
REVOKE CREATE ON SCHEMA public FROM cp_contact_change_function_owner,cp_contact_change_executor,cp_contact_proof_verifier;
