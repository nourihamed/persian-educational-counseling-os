-- =============================================================================
-- WORKSPACE — Verifier and Governance Adapter identities (DRAFT, synthetic only).
-- Role TYPES: verifier_rt (registration only), governance adapter runtime (consume only).
-- Instance names follow the per-Workspace convention (cluster-wide roles):
--   ws_<key>_verifier_rt, ws_<key>_governance_adapter_rt
-- NOLOGIN here. Login identities, certificates and credentials are DEPLOYMENT (Platform
-- Security); none is created or stored by this draft. Requires workspace_roles_setup_draft.sql.
-- Run with: -v workspace_key=<32 lowercase hex>
-- =============================================================================
\set ON_ERROR_STOP on
\if :{?workspace_key}
\else
  \echo 'ERROR: pass -v workspace_key=<32-character lowercase hex>'
  \quit 3
\endif
SET app.workspace_key = :'workspace_key';

DO $roles$
DECLARE r text;
BEGIN
  FOREACH r IN ARRAY ARRAY[
    'ws_'||current_setting('app.workspace_key')||'_verifier_rt',
    'ws_'||current_setting('app.workspace_key')||'_governance_adapter_rt'] LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname=r) THEN
      EXECUTE format('CREATE ROLE %I NOLOGIN NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS', r);
    END IF;
  END LOOP;
END
$roles$;

-- Identity handles used by grants below (resolved from the Workspace key).
SELECT 'ws_'||current_setting('app.workspace_key')||'_verifier_rt' AS verifier_role \gset
SELECT 'ws_'||current_setting('app.workspace_key')||'_governance_adapter_rt' AS adapter_role \gset
SELECT 'ws_'||current_setting('app.workspace_key')||'_governance_owner' AS owner_role \gset
SELECT 'ws_'||current_setting('app.workspace_key')||'_runtime' AS runtime_role \gset
SELECT 'ws_'||current_setting('app.workspace_key')||'_worker' AS worker_role \gset
SELECT 'ws_'||current_setting('app.workspace_key')||'_exporter' AS exporter_role \gset

-- Start from zero for the receipt table and the consume function.
REVOKE ALL ON TABLE governance_proof_receipts FROM PUBLIC, :"runtime_role", :"worker_role", :"exporter_role", :"verifier_role", :"adapter_role";
REVOKE ALL ON TABLE receipt_adapter_allowlist FROM PUBLIC, :"runtime_role", :"worker_role", :"exporter_role", :"verifier_role", :"adapter_role";

-- Verifier: INSERT (registration) ONLY. No SELECT, UPDATE, DELETE, no function execution.
GRANT USAGE ON SCHEMA public TO :"verifier_role", :"adapter_role";
GRANT INSERT ON TABLE governance_proof_receipts TO :"verifier_role";

-- Governance owner (materializer): read receipts and record consumption. Nothing else new.
GRANT SELECT, UPDATE ON TABLE governance_proof_receipts TO :"owner_role";
GRANT SELECT ON TABLE receipt_adapter_allowlist TO :"owner_role";
-- The consume function reads the Workspace identity (single row) to bind receipts to this Workspace.
GRANT SELECT ON TABLE workspace_profile TO :"owner_role";
-- H-03: revocation audit is written by the governance owner only (no verifier, adapter or runtime access).
REVOKE ALL ON TABLE receipt_revocation_audit FROM PUBLIC, :"runtime_role", :"worker_role", :"exporter_role", :"verifier_role", :"adapter_role";
GRANT SELECT, INSERT ON TABLE receipt_revocation_audit TO :"owner_role";
GRANT USAGE ON SEQUENCE receipt_revocation_audit_audit_id_seq TO :"owner_role";

-- Adapter: may call the consume function only (EXECUTE granted in receipt_03).
-- It has no table privilege on receipts or events.
INSERT INTO receipt_adapter_allowlist(role_name) VALUES (:'adapter_role')
  ON CONFLICT DO NOTHING;
