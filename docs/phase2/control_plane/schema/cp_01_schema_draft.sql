-- =============================================================================
-- CONTROL PLANE — DRAFT SCHEMA (PostgreSQL 15+). NOT a production migration.
-- Synthetic data only (D-014). Separate database from every Workspace database.
-- Authoritative here: global student ownership, global E.164+grade claim, ownership
-- generation, transfer case state, approval evidence references, idempotency, outbox.
-- NOT stored here: raw mobile (only ciphertext + keyed HMAC), educational records,
-- counselor-private notes, credit ledgers.
-- Key material (HMAC/encryption keys) is NEVER in this database (OQ-B).
-- No cross-database foreign keys exist; Workspace references are opaque UUIDs
-- validated by the workflow, not by PostgreSQL.
-- =============================================================================
BEGIN;

CREATE FUNCTION forbid_mutation() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION '% on % is forbidden (append-only)', TG_OP, TG_TABLE_NAME USING ERRCODE = 'check_violation';
END;
$$;

CREATE TABLE workspaces (
    workspace_id    uuid PRIMARY KEY,
    workspace_type  text NOT NULL CHECK (workspace_type IN ('organization', 'independent_counselor')),
    status          text NOT NULL CHECK (status IN ('active', 'suspended', 'closed')),
    created_at      timestamptz NOT NULL DEFAULT now()
);

-- Platform-level student identity. Deliberately holds no mobile number.
CREATE TABLE platform_students (
    student_id  uuid PRIMARY KEY,
    created_at  timestamptz NOT NULL DEFAULT now()
);

-- Contact index: recoverable value is ciphertext; lookup/uniqueness uses a keyed HMAC.
-- key_version identifies which HMAC key produced mobile_hmac (rotation, OQ-B).
-- Multiple versions coexist during a write-frozen, fully backfilled rotation.
CREATE TABLE student_contact_index (
    student_id         uuid NOT NULL REFERENCES platform_students (student_id),
    key_version        integer NOT NULL CHECK (key_version > 0),
    mobile_hmac        bytea   NOT NULL CHECK (octet_length(mobile_hmac) = 32),
    mobile_ciphertext  bytea   NOT NULL, -- encrypted canonical E.164; key material external
    cipher_key_version integer NOT NULL CHECK (cipher_key_version > 0),
    updated_at         timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (student_id, key_version)
);

-- During rotation, every holding claim must have an alias for EVERY active HMAC key version.
-- Unique aliases enforce global mobile+grade uniqueness independently for each key version.
-- The write gate/rotation protocol is documented in CONTROL_PLANE_KEY_ROTATION.md.
CREATE TABLE mobile_hmac_key_versions (
    key_version integer PRIMARY KEY CHECK (key_version > 0),
    state text NOT NULL CHECK (state IN ('active','retiring','retired')),
    activated_at timestamptz NOT NULL DEFAULT now(),
    retired_at timestamptz,
    CHECK ((state='retired') = (retired_at IS NOT NULL))
);

-- Global identity-write maintenance gate. A database row lock serializes rotation
-- start/finish with in-flight claim mutations; maintenance mode persists across sessions.
CREATE TABLE identity_write_gate (
    singleton boolean PRIMARY KEY DEFAULT true CHECK (singleton),
    maintenance_mode boolean NOT NULL DEFAULT false,
    rotation_epoch bigint NOT NULL DEFAULT 0,
    changed_at timestamptz NOT NULL DEFAULT now()
);
INSERT INTO identity_write_gate(singleton,maintenance_mode,rotation_epoch) VALUES (true,false,0);

-- Global ownership: exactly one row per student; owner is the authoritative Workspace.
-- ownership_generation is the fencing token: strictly increases on every ownership change.
ALTER TABLE student_contact_index
  ADD CONSTRAINT student_contact_index_key_version_fk
  FOREIGN KEY (key_version) REFERENCES mobile_hmac_key_versions(key_version);

CREATE TABLE student_ownership (
    student_id           uuid PRIMARY KEY REFERENCES platform_students (student_id),
    owner_workspace_id   uuid NOT NULL REFERENCES workspaces (workspace_id),
    ownership_generation bigint NOT NULL CHECK (ownership_generation >= 1),
    lifecycle_state      text NOT NULL CHECK (lifecycle_state IN ('active', 'transfer_pending', 'archived', 'ended')),
    updated_at           timestamptz NOT NULL DEFAULT now()
);

-- Global active claim for (canonical mobile, grade). Only states that hold the claim are unique.
-- Active and transfer_pending hold the claim; ended and archived release it.
-- grade_key is the MVP enumeration (D-025); same mobile may be used for a different grade.
CREATE TABLE enrollment_claims (
    claim_id           uuid PRIMARY KEY,
    student_id         uuid NOT NULL REFERENCES platform_students (student_id),
    workspace_id       uuid NOT NULL REFERENCES workspaces (workspace_id),
    grade_key          text NOT NULL CHECK (grade_key IN ('grade_10', 'grade_11', 'grade_12')),
    claim_state        text NOT NULL CHECK (claim_state IN ('active', 'transfer_pending', 'ended', 'archived')),
    ownership_generation bigint NOT NULL CHECK (ownership_generation >= 1),
    created_at         timestamptz NOT NULL DEFAULT now(),
    ended_at           timestamptz,
    CHECK ((claim_state IN ('ended', 'archived')) = (ended_at IS NOT NULL)),
    UNIQUE (claim_id, grade_key)
);
-- HMAC aliases are separate rows so multiple key versions can coexist during safe rotation.
CREATE TABLE enrollment_claim_identity_aliases (
    claim_id      uuid NOT NULL REFERENCES enrollment_claims(claim_id),
    grade_key     text NOT NULL CHECK (grade_key IN ('grade_10','grade_11','grade_12')),
    key_version   integer NOT NULL REFERENCES mobile_hmac_key_versions(key_version),
    mobile_hmac   bytea NOT NULL CHECK (octet_length(mobile_hmac)=32),
    claim_state   text NOT NULL CHECK (claim_state IN ('active','transfer_pending','ended','archived')),
    PRIMARY KEY (claim_id, key_version),
    FOREIGN KEY (claim_id, grade_key) REFERENCES enrollment_claims(claim_id, grade_key)
);
-- D-025: every live identity alias is globally unique within its key version and grade.
CREATE UNIQUE INDEX enrollment_claims_global_identity
    ON enrollment_claim_identity_aliases (key_version, mobile_hmac, grade_key)
    WHERE claim_state IN ('active','transfer_pending');
-- One claim-holding enrollment per student platform-wide (PO-4).
CREATE UNIQUE INDEX enrollment_claims_one_per_student
    ON enrollment_claims (student_id)
    WHERE claim_state IN ('active', 'transfer_pending');

-- Transfer case. initiator_kind excludes platform admin by construction (OQ-A).
CREATE TABLE transfer_cases (
    case_id              uuid PRIMARY KEY,
    student_id           uuid NOT NULL REFERENCES platform_students (student_id),
    source_workspace_id  uuid NOT NULL REFERENCES workspaces (workspace_id),
    destination_workspace_id uuid NOT NULL REFERENCES workspaces (workspace_id),
    expected_generation  bigint NOT NULL CHECK (expected_generation >= 1),
    initiator_kind       text NOT NULL CHECK (initiator_kind IN ('guardian', 'current_counselor', 'destination_workspace')),
    state                text NOT NULL CHECK (state IN (
        'requested', 'approvals_pending', 'approved', 'preflight_ok', 'staging',
        'staged_verified', 'cutover_frozen', 'ownership_switched',
        'projections_finalizing', 'completed', 'cancelled', 'failed_recoverable', 'manual_intervention_pre_switch', 'manual_intervention_post_switch')),
    idempotency_key      text NOT NULL CHECK (length(idempotency_key) > 0),
    source_freeze_token text,
    source_frozen_at timestamptz,
    source_unfrozen_at timestamptz,
    final_snapshot_ref text,
    final_snapshot_at timestamptz,
    snapshot_manifest_hash bytea CHECK (snapshot_manifest_hash IS NULL OR octet_length(snapshot_manifest_hash)=32),
    destination_validation_ref text,
    destination_validated_at timestamptz,
    created_at           timestamptz NOT NULL DEFAULT now(),
    CHECK (final_snapshot_at IS NULL OR (source_frozen_at IS NOT NULL AND final_snapshot_at>=source_frozen_at)),
    CHECK (destination_validated_at IS NULL OR (final_snapshot_at IS NOT NULL AND destination_validated_at>=final_snapshot_at)),
    CHECK (source_unfrozen_at IS NULL OR (source_frozen_at IS NOT NULL AND source_unfrozen_at>=source_frozen_at)),
    updated_at           timestamptz NOT NULL DEFAULT now(),
    CHECK (source_workspace_id <> destination_workspace_id),
    UNIQUE (idempotency_key),
    UNIQUE (source_freeze_token),
    UNIQUE (final_snapshot_ref),
    UNIQUE (destination_validation_ref)
);
-- At most one open (non-terminal) transfer per student.
CREATE UNIQUE INDEX transfer_cases_one_open_per_student
    ON transfer_cases (student_id)
    WHERE state NOT IN ('completed', 'cancelled');

CREATE FUNCTION guard_transfer_case_mutation() RETURNS trigger LANGUAGE plpgsql AS $body$
BEGIN
  IF TG_OP='DELETE' THEN RAISE EXCEPTION 'transfer cases are durable; use state transitions, never DELETE' USING ERRCODE='check_violation'; END IF;
  IF NEW.case_id IS DISTINCT FROM OLD.case_id
     OR NEW.student_id IS DISTINCT FROM OLD.student_id
     OR NEW.source_workspace_id IS DISTINCT FROM OLD.source_workspace_id
     OR NEW.destination_workspace_id IS DISTINCT FROM OLD.destination_workspace_id
     OR NEW.expected_generation IS DISTINCT FROM OLD.expected_generation
     OR NEW.initiator_kind IS DISTINCT FROM OLD.initiator_kind
     OR NEW.idempotency_key IS DISTINCT FROM OLD.idempotency_key
     OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
    RAISE EXCEPTION 'transfer case identity fields are immutable' USING ERRCODE='check_violation';
  END IF;
  IF (OLD.source_freeze_token IS NOT NULL AND NEW.source_freeze_token IS DISTINCT FROM OLD.source_freeze_token)
     OR (OLD.source_frozen_at IS NOT NULL AND NEW.source_frozen_at IS DISTINCT FROM OLD.source_frozen_at)
     OR (OLD.source_unfrozen_at IS NOT NULL AND NEW.source_unfrozen_at IS DISTINCT FROM OLD.source_unfrozen_at)
     OR (OLD.final_snapshot_ref IS NOT NULL AND NEW.final_snapshot_ref IS DISTINCT FROM OLD.final_snapshot_ref)
     OR (OLD.final_snapshot_at IS NOT NULL AND NEW.final_snapshot_at IS DISTINCT FROM OLD.final_snapshot_at)
     OR (OLD.snapshot_manifest_hash IS NOT NULL AND NEW.snapshot_manifest_hash IS DISTINCT FROM OLD.snapshot_manifest_hash)
     OR (OLD.destination_validation_ref IS NOT NULL AND NEW.destination_validation_ref IS DISTINCT FROM OLD.destination_validation_ref)
     OR (OLD.destination_validated_at IS NOT NULL AND NEW.destination_validated_at IS DISTINCT FROM OLD.destination_validated_at) THEN
    RAISE EXCEPTION 'transfer evidence is write-once' USING ERRCODE='check_violation';
  END IF;
  RETURN NEW;
END; $body$;
CREATE TRIGGER transfer_cases_identity_guard
  BEFORE UPDATE OR DELETE ON transfer_cases
  FOR EACH ROW EXECUTE FUNCTION guard_transfer_case_mutation();

-- Cumulative approvals: all three kinds must exist before the ownership switch (D-026/D-027/PO-8).
CREATE TABLE transfer_approvals (
    approval_id     uuid PRIMARY KEY,
    case_id         uuid NOT NULL REFERENCES transfer_cases (case_id),
    approval_kind   text NOT NULL CHECK (approval_kind IN ('guardian_consent', 'fee_confirmation', 'destination_acceptance')),
    evidence_ref    text NOT NULL,                  -- opaque reference; no personal document content
    approver_ref    text NOT NULL,                  -- stable authenticated subject, not caller-supplied authority
    authn_event_ref text NOT NULL,                  -- reference to verified authentication/step-up event
    authority_snapshot jsonb NOT NULL,              -- verified relationship/assignment/destination authority snapshot
    verified_at     timestamptz NOT NULL,
    valid_until     timestamptz,
    revoked_at      timestamptz,
    recorded_at     timestamptz NOT NULL DEFAULT now(),
    UNIQUE (case_id, approval_kind),
    UNIQUE (evidence_ref),
    CHECK (valid_until IS NULL OR valid_until > verified_at)
);

CREATE FUNCTION guard_transfer_approval_mutation() RETURNS trigger LANGUAGE plpgsql AS $body$
BEGIN
  IF TG_OP='DELETE' THEN RAISE EXCEPTION 'transfer approvals are immutable; use revocation' USING ERRCODE='check_violation'; END IF;
  IF NEW.approval_id IS DISTINCT FROM OLD.approval_id
     OR NEW.case_id IS DISTINCT FROM OLD.case_id
     OR NEW.approval_kind IS DISTINCT FROM OLD.approval_kind
     OR NEW.evidence_ref IS DISTINCT FROM OLD.evidence_ref
     OR NEW.approver_ref IS DISTINCT FROM OLD.approver_ref
     OR NEW.authn_event_ref IS DISTINCT FROM OLD.authn_event_ref
     OR NEW.authority_snapshot IS DISTINCT FROM OLD.authority_snapshot
     OR NEW.verified_at IS DISTINCT FROM OLD.verified_at
     OR NEW.valid_until IS DISTINCT FROM OLD.valid_until
     OR NEW.recorded_at IS DISTINCT FROM OLD.recorded_at
     OR (OLD.revoked_at IS NOT NULL AND NEW.revoked_at IS DISTINCT FROM OLD.revoked_at)
     OR (OLD.revoked_at IS NULL AND NEW.revoked_at IS NULL) THEN
    RAISE EXCEPTION 'approval evidence is immutable; only one-way revocation is allowed'
      USING ERRCODE='check_violation';
  END IF;
  RETURN NEW;
END; $body$;
CREATE TRIGGER transfer_approvals_immutable
  BEFORE UPDATE OR DELETE ON transfer_approvals
  FOR EACH ROW EXECUTE FUNCTION guard_transfer_approval_mutation();

-- Idempotency / command deduplication for ownership-changing commands.
CREATE TABLE command_log (
    idempotency_key  text PRIMARY KEY,
    command_name     text NOT NULL,
    payload_hash     bytea NOT NULL CHECK (octet_length(payload_hash) = 32),
    result_case_id   uuid REFERENCES transfer_cases (case_id),
    recorded_at      timestamptz NOT NULL DEFAULT now()
);

-- Inbox deduplication ledger. Consumers insert event_id once and reject stale generations.
CREATE TABLE inbox_events (
    event_id uuid PRIMARY KEY,
    workspace_id uuid NOT NULL REFERENCES workspaces(workspace_id),
    student_id uuid NOT NULL REFERENCES platform_students(student_id),
    ownership_generation bigint NOT NULL CHECK (ownership_generation >= 1),
    received_at timestamptz NOT NULL DEFAULT now(),
    processed_at timestamptz
);

-- Transactional outbox: written in the same transaction as the ownership switch.
CREATE TABLE outbox_events (
    event_id     uuid PRIMARY KEY,
    case_id      uuid REFERENCES transfer_cases (case_id),
    event_type   text NOT NULL,
    payload      jsonb NOT NULL DEFAULT '{}'::jsonb,   -- ids and generations only; no personal data
    created_at   timestamptz NOT NULL DEFAULT now(),
    published_at timestamptz
);

CREATE FUNCTION guard_outbox_event_mutation() RETURNS trigger LANGUAGE plpgsql AS $body$
BEGIN
  IF TG_OP='DELETE' THEN RAISE EXCEPTION 'outbox events are immutable' USING ERRCODE='check_violation'; END IF;
  IF NEW.event_id IS DISTINCT FROM OLD.event_id
     OR NEW.case_id IS DISTINCT FROM OLD.case_id
     OR NEW.event_type IS DISTINCT FROM OLD.event_type
     OR NEW.payload IS DISTINCT FROM OLD.payload
     OR NEW.created_at IS DISTINCT FROM OLD.created_at
     OR (OLD.published_at IS NOT NULL AND NEW.published_at IS DISTINCT FROM OLD.published_at)
     OR (OLD.published_at IS NULL AND NEW.published_at IS NULL) THEN
    RAISE EXCEPTION 'outbox payload is immutable; only null-to-published timestamp is allowed'
      USING ERRCODE='check_violation';
  END IF;
  RETURN NEW;
END; $body$;
CREATE TRIGGER outbox_events_immutable
  BEFORE UPDATE OR DELETE ON outbox_events
  FOR EACH ROW EXECUTE FUNCTION guard_outbox_event_mutation();

-- Append-only audit of ownership changes (fencing history).
CREATE TABLE ownership_history (
    history_id           bigserial PRIMARY KEY,
    student_id           uuid NOT NULL REFERENCES platform_students (student_id),
    from_workspace_id    uuid,
    to_workspace_id      uuid NOT NULL REFERENCES workspaces (workspace_id),
    ownership_generation bigint NOT NULL,
    case_id              uuid REFERENCES transfer_cases (case_id),
    recorded_at          timestamptz NOT NULL DEFAULT now(),
    UNIQUE (student_id, ownership_generation)
);
CREATE TRIGGER ownership_history_append_only
    BEFORE UPDATE OR DELETE ON ownership_history
    FOR EACH ROW EXECUTE FUNCTION forbid_mutation();

COMMIT;
