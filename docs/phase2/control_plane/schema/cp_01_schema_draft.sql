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
-- key_version identifies WHICH HMAC key produced mobile_hmac (rotation, OQ-B).
-- Rotation: the new key_version rows are written for every student BEFORE the
-- Control Plane's current_key_version is advanced; both versions may coexist during migration.
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

-- Global ownership: exactly one row per student; owner is the authoritative Workspace.
-- ownership_generation is the fencing token: strictly increases on every ownership change.
CREATE TABLE student_ownership (
    student_id           uuid PRIMARY KEY REFERENCES platform_students (student_id),
    owner_workspace_id   uuid NOT NULL REFERENCES workspaces (workspace_id),
    ownership_generation bigint NOT NULL CHECK (ownership_generation >= 1),
    lifecycle_state      text NOT NULL CHECK (lifecycle_state IN ('active', 'transfer_pending', 'archived', 'ended')),
    updated_at           timestamptz NOT NULL DEFAULT now()
);

-- Global active claim for (canonical mobile, grade). Only states that hold the claim are unique.
-- Proposed (requires Product Owner confirmation): 'active' and 'transfer_pending' hold the claim;
-- 'ended' and 'archived' release it. grade_key is the MVP enumeration (D-025).
CREATE TABLE enrollment_claims (
    claim_id           uuid PRIMARY KEY,
    student_id         uuid NOT NULL REFERENCES platform_students (student_id),
    workspace_id       uuid NOT NULL REFERENCES workspaces (workspace_id),
    grade_key          text NOT NULL CHECK (grade_key IN ('grade_10', 'grade_11', 'grade_12')),
    claim_state        text NOT NULL CHECK (claim_state IN ('active', 'transfer_pending', 'ended', 'archived')),
    ownership_generation bigint NOT NULL CHECK (ownership_generation >= 1),
    created_at         timestamptz NOT NULL DEFAULT now(),
    ended_at           timestamptz,
    CHECK ((claim_state IN ('ended', 'archived')) = (ended_at IS NOT NULL))
);
-- HMAC aliases are separate rows so multiple key versions can coexist during safe rotation.
CREATE TABLE enrollment_claim_identity_aliases (
    claim_id      uuid NOT NULL REFERENCES enrollment_claims(claim_id),
    grade_key     text NOT NULL CHECK (grade_key IN ('grade_10','grade_11','grade_12')),
    key_version   integer NOT NULL REFERENCES mobile_hmac_key_versions(key_version),
    mobile_hmac   bytea NOT NULL CHECK (octet_length(mobile_hmac)=32),
    claim_state   text NOT NULL CHECK (claim_state IN ('active','transfer_pending','ended','archived')),
    PRIMARY KEY (claim_id, key_version)
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
        'projections_finalizing', 'completed', 'cancelled', 'failed_recoverable', 'manual_intervention')),
    idempotency_key      text NOT NULL CHECK (length(idempotency_key) > 0),
    created_at           timestamptz NOT NULL DEFAULT now(),
    updated_at           timestamptz NOT NULL DEFAULT now(),
    CHECK (source_workspace_id <> destination_workspace_id),
    UNIQUE (idempotency_key)
);
-- At most one open (non-terminal) transfer per student.
CREATE UNIQUE INDEX transfer_cases_one_open_per_student
    ON transfer_cases (student_id)
    WHERE state NOT IN ('completed', 'cancelled');

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

-- Idempotency / command deduplication for ownership-changing commands.
CREATE TABLE command_log (
    idempotency_key  text PRIMARY KEY,
    command_name     text NOT NULL,
    payload_hash     bytea NOT NULL CHECK (octet_length(payload_hash) = 32),
    result_case_id   uuid REFERENCES transfer_cases (case_id),
    recorded_at      timestamptz NOT NULL DEFAULT now()
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
