-- =============================================================================
-- WORKSPACE — Governance proof receipts (DRAFT, synthetic only, NOT a migration).
-- Records a receipt registered by the EXTERNAL independent verifier (decision A1).
-- The database does NOT verify signatures. It stores the verifier's recorded outcome,
-- which is accepted only as one input; the trusted command boundary (receipt_03) still
-- re-checks every binding and the authority/event state in the same transaction.
-- Stores NO secrets, passwords, OTPs, bearer tokens, private keys, raw mobile numbers
-- or identity-document contents. Digests and opaque references only.
-- Requires workspace_schema_draft.sql and workspace_governance_events_draft.sql first.
-- =============================================================================
\set ON_ERROR_STOP on
BEGIN;

CREATE TABLE governance_proof_receipts (
  receipt_id           uuid PRIMARY KEY,
  assertion_id         uuid NOT NULL UNIQUE,                      -- single assertion, single receipt
  nonce_digest         bytea NOT NULL UNIQUE CHECK (octet_length(nonce_digest)=32), -- replay guard; nonce itself not stored
  issuer_id            text NOT NULL CHECK (length(btrim(issuer_id))>0),
  audience             text NOT NULL CHECK (audience='governance_adapter'),
  key_id               text NOT NULL CHECK (length(btrim(key_id))>0),  -- opaque; key registry is OPEN (Platform Security)
  workspace_id         uuid NOT NULL,
  actor_membership_id  uuid NOT NULL,
  authn_event_ref      text NOT NULL CHECK (length(btrim(authn_event_ref))>0),
  assurance_ref        text NOT NULL CHECK (length(btrim(assurance_ref))>0),
  action               text NOT NULL CHECK (length(btrim(action))>0),
  aggregate_type       text NOT NULL,
  aggregate_id         uuid NOT NULL,
  target_membership_id uuid,
  role_or_permission_key text,
  scope_digest         bytea NOT NULL CHECK (octet_length(scope_digest)=32),
  authority_ref        text NOT NULL CHECK (length(btrim(authority_ref))>0),
  policy_version       text NOT NULL CHECK (length(btrim(policy_version))>0),
  idempotency_key      text NOT NULL CHECK (length(btrim(idempotency_key))>0),
  payload_digest       bytea NOT NULL CHECK (octet_length(payload_digest)=32),
  canonicalization_version text NOT NULL CHECK (canonicalization_version = 'receipt-canon-v1'),
  issued_at            timestamptz NOT NULL,
  not_before           timestamptz NOT NULL,
  expires_at           timestamptz NOT NULL,
  verifier_kind        text NOT NULL CHECK (verifier_kind='external_independent_verifier'),
  verifier_outcome     text NOT NULL CHECK (verifier_outcome='verified'), -- recorded input only; not proof by itself
  registered_at        timestamptz NOT NULL DEFAULT now(),
  status               text NOT NULL DEFAULT 'registered' CHECK (status IN ('registered','consumed','revoked')),
  consumed_at          timestamptz,
  consumed_event_id    uuid REFERENCES workspace_governance_events (event_id),
  consumed_idempotency_key text,
  -- Q-007: guardian-family receipts are refused at storage while the question is open.
  CHECK (aggregate_type NOT IN ('guardian_relationship','guardian_permission')),
  CHECK (expires_at > not_before AND not_before >= issued_at),
  -- Consumption metadata is present if and only if status='consumed' (complete, no NULL bypass).
  CHECK (status = 'consumed' OR (consumed_at IS NULL AND consumed_event_id IS NULL AND consumed_idempotency_key IS NULL)),
  CHECK (status <> 'consumed' OR (consumed_at IS NOT NULL AND consumed_event_id IS NOT NULL AND consumed_idempotency_key IS NOT NULL))
);
CREATE INDEX governance_proof_receipts_workspace_idx ON governance_proof_receipts (workspace_id, status);

-- Receipts are never deleted. Only two state changes are allowed:
--   registered -> consumed  (adapter function, consume path)
--   registered -> revoked   (revocation handling, OPEN: revocation source is not yet defined)
-- Every binding column is immutable after registration.
CREATE FUNCTION receipt_guard() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'governance proof receipts are never deleted' USING ERRCODE='check_violation';
  END IF;

  -- Identity and authorization binding: immutable after registration (NULL-safe comparison).
  IF (NEW.receipt_id, NEW.assertion_id, NEW.nonce_digest, NEW.issuer_id, NEW.audience, NEW.key_id,
      NEW.workspace_id, NEW.actor_membership_id, NEW.authn_event_ref, NEW.assurance_ref, NEW.action,
      NEW.aggregate_type, NEW.aggregate_id, NEW.target_membership_id, NEW.role_or_permission_key,
      NEW.scope_digest, NEW.authority_ref, NEW.policy_version, NEW.idempotency_key, NEW.payload_digest,
      NEW.canonicalization_version, NEW.issued_at, NEW.not_before, NEW.expires_at, NEW.verifier_kind,
      NEW.verifier_outcome, NEW.registered_at)
     IS DISTINCT FROM
     (OLD.receipt_id, OLD.assertion_id, OLD.nonce_digest, OLD.issuer_id, OLD.audience, OLD.key_id,
      OLD.workspace_id, OLD.actor_membership_id, OLD.authn_event_ref, OLD.assurance_ref, OLD.action,
      OLD.aggregate_type, OLD.aggregate_id, OLD.target_membership_id, OLD.role_or_permission_key,
      OLD.scope_digest, OLD.authority_ref, OLD.policy_version, OLD.idempotency_key, OLD.payload_digest,
      OLD.canonicalization_version, OLD.issued_at, OLD.not_before, OLD.expires_at, OLD.verifier_kind,
      OLD.verifier_outcome, OLD.registered_at) THEN
    RAISE EXCEPTION 'receipt binding columns are immutable' USING ERRCODE='check_violation';
  END IF;

  -- Terminal states: no further change of any kind (including metadata, references and status).
  IF OLD.status IN ('consumed','revoked') THEN
    RAISE EXCEPTION 'receipt is terminal (%) and immutable', OLD.status USING ERRCODE='check_violation';
  END IF;

  -- From 'registered' only three destinations are admissible.
  IF NEW.status = 'registered' THEN
    -- Same-state update: consumption metadata may not be written without a transition.
    IF NEW.consumed_at IS NOT NULL OR NEW.consumed_event_id IS NOT NULL OR NEW.consumed_idempotency_key IS NOT NULL THEN
      RAISE EXCEPTION 'consumption metadata may only be written with the registered->consumed transition'
        USING ERRCODE='check_violation';
    END IF;
    RETURN NEW;
  ELSIF NEW.status = 'consumed' THEN
    IF NEW.consumed_at IS NULL OR NEW.consumed_event_id IS NULL OR NEW.consumed_idempotency_key IS NULL THEN
      RAISE EXCEPTION 'incomplete consumption metadata' USING ERRCODE='check_violation';
    END IF;
    RETURN NEW;
  ELSIF NEW.status = 'revoked' THEN
    IF NEW.consumed_at IS NOT NULL OR NEW.consumed_event_id IS NOT NULL OR NEW.consumed_idempotency_key IS NOT NULL THEN
      RAISE EXCEPTION 'revocation must not carry consumption metadata' USING ERRCODE='check_violation';
    END IF;
    RETURN NEW;
  END IF;
  RAISE EXCEPTION 'illegal receipt transition % -> %', OLD.status, NEW.status USING ERRCODE='check_violation';
END;
$$;
CREATE TRIGGER governance_proof_receipts_guard
  BEFORE UPDATE OR DELETE ON governance_proof_receipts
  FOR EACH ROW EXECUTE FUNCTION receipt_guard();

-- Allowlist of identities that may call the consume function. Owned by the table owner;
-- no runtime, worker, exporter, verifier or adapter role can write it.
CREATE TABLE receipt_adapter_allowlist (
  role_name text PRIMARY KEY
);

COMMIT;
