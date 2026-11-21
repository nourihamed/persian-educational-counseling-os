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

-- Workspace UUID is immutable. The admission function needs a narrow UPDATE privilege on
-- this key column solely to acquire FOR SHARE row locks; this trigger prevents key mutation.
CREATE FUNCTION guard_workspace_id_immutable() RETURNS trigger LANGUAGE plpgsql AS $workspace_guard$
BEGIN
  IF NEW.workspace_id IS DISTINCT FROM OLD.workspace_id THEN
    RAISE EXCEPTION 'workspace_id is immutable' USING ERRCODE='check_violation';
  END IF;
  RETURN NEW;
END;
$workspace_guard$;
CREATE TRIGGER workspaces_workspace_id_immutable
  BEFORE UPDATE OF workspace_id ON workspaces
  FOR EACH ROW EXECUTE FUNCTION guard_workspace_id_immutable();

-- Platform-level student identity. Deliberately holds no mobile number.
CREATE TABLE platform_students (
    student_id  uuid PRIMARY KEY,
    created_at  timestamptz NOT NULL DEFAULT now()
);

-- Contact index: recoverable value is ciphertext; lookup/uniqueness uses a keyed HMAC.
CREATE TABLE mobile_encryption_key_versions (
    key_version integer PRIMARY KEY CHECK (key_version>0),
    state text NOT NULL CHECK (state IN ('active','retiring','retired')),
    key_manager_ref text NOT NULL, -- non-secret KMS/HSM key identifier; never key material
    created_at timestamptz NOT NULL DEFAULT now(),
    retired_at timestamptz,
    CHECK ((state='retired') = (retired_at IS NOT NULL))
);
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
ALTER TABLE student_contact_index
  ADD CONSTRAINT student_contact_index_cipher_key_version_fk
  FOREIGN KEY (cipher_key_version) REFERENCES mobile_encryption_key_versions(key_version);

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
    assertion_id    uuid NOT NULL UNIQUE,           -- one verified assertion, one approval event
    nonce_digest    bytea NOT NULL UNIQUE CHECK (octet_length(nonce_digest) = 32),  -- replay guard; nonce itself not stored
    case_id         uuid NOT NULL REFERENCES transfer_cases (case_id),
    approval_kind   text NOT NULL CHECK (approval_kind IN ('guardian_consent', 'fee_confirmation', 'destination_acceptance')),
    evidence_ref    text NOT NULL,                  -- opaque reference; no personal document content
    approver_ref    text NOT NULL CHECK (length(btrim(approver_ref)) > 0),      -- stable authenticated subject, not caller-supplied authority
    authn_event_ref text NOT NULL CHECK (length(btrim(authn_event_ref)) > 0),   -- reference to verified authentication/step-up event
    authority_snapshot jsonb NOT NULL,              -- verified relationship/assignment/destination authority snapshot
    verified_at     timestamptz NOT NULL,
    valid_until     timestamptz,
    recorded_at     timestamptz NOT NULL DEFAULT now(),
    UNIQUE (evidence_ref),
    CHECK (valid_until IS NULL OR valid_until > verified_at)
);
-- History is kept: several approval events may exist per (case, kind) over time. No UNIQUE(case_id, approval_kind).
CREATE INDEX transfer_approvals_case_kind ON transfer_approvals (case_id, approval_kind);

-- A revocation is its own immutable event; it never rewrites the approval it refers to.
CREATE TABLE transfer_approval_revocations (
    revocation_id   uuid PRIMARY KEY,
    approval_id     uuid NOT NULL UNIQUE REFERENCES transfer_approvals (approval_id),  -- at most one revocation per approval
    actor_ref       text NOT NULL CHECK (length(btrim(actor_ref)) > 0),
    authn_event_ref text NOT NULL CHECK (length(btrim(authn_event_ref)) > 0),
    reason_code     text NOT NULL CHECK (length(btrim(reason_code)) > 0),               -- opaque code; the reason taxonomy is not defined here
    recorded_at     timestamptz NOT NULL DEFAULT now()
);

-- Current = not revoked and inside its validity window. Authority freshness is revalidated by the workflow (Phase 4).
CREATE VIEW transfer_approvals_current AS
  SELECT a.* FROM transfer_approvals a
   WHERE NOT EXISTS (SELECT 1 FROM transfer_approval_revocations r WHERE r.approval_id = a.approval_id)
     AND a.verified_at <= clock_timestamp() AND (a.valid_until IS NULL OR a.valid_until > clock_timestamp());

CREATE FUNCTION guard_transfer_approval_mutation() RETURNS trigger LANGUAGE plpgsql AS $body$
BEGIN
  RAISE EXCEPTION '% is append-only; record a revocation event or a new approval instead', TG_TABLE_NAME
    USING ERRCODE='check_violation';
END; $body$;
CREATE TRIGGER transfer_approvals_immutable
  BEFORE UPDATE OR DELETE ON transfer_approvals
  FOR EACH ROW EXECUTE FUNCTION guard_transfer_approval_mutation();
CREATE TRIGGER transfer_approval_revocations_immutable
  BEFORE UPDATE OR DELETE ON transfer_approval_revocations
  FOR EACH ROW EXECUTE FUNCTION guard_transfer_approval_mutation();

-- Recording and revoking serialise on the transfer case row (the same lock the ownership switch takes):
-- whichever commits first decides whether the approval is valid at cutover. At most one CURRENT approval
-- per (case, kind): a replacement is accepted only after the previous one is revoked or expired.
CREATE FUNCTION guard_transfer_approval_insert() RETURNS trigger LANGUAGE plpgsql AS $body$
BEGIN
  PERFORM 1 FROM public.transfer_cases WHERE case_id = NEW.case_id FOR UPDATE;
  IF EXISTS (SELECT 1 FROM public.transfer_approvals a
              WHERE a.case_id = NEW.case_id AND a.approval_kind = NEW.approval_kind
                AND NOT EXISTS (SELECT 1 FROM public.transfer_approval_revocations r WHERE r.approval_id = a.approval_id)
                AND (a.valid_until IS NULL OR a.valid_until > clock_timestamp())) THEN
    RAISE EXCEPTION 'a current % approval already exists for this transfer case; revoke it before recording a replacement', NEW.approval_kind
      USING ERRCODE='unique_violation';
  END IF;
  RETURN NEW;
END; $body$;
CREATE TRIGGER transfer_approvals_one_current
  BEFORE INSERT ON transfer_approvals
  FOR EACH ROW EXECUTE FUNCTION guard_transfer_approval_insert();

-- PD-2026-11-13-C — separation of approval duties.
-- Default rule: one person may not satisfy incompatible approval kinds for the same transfer.
-- The ONLY contemplated exception is 'source_destination_owner' (the source counselor is also the owner of
-- the destination Workspace). Its approval authority and exact boundary are DEFERRED, so the exception is
-- disabled and the transfer fails closed when it would be needed. The CHECK below makes an enabled row
-- unstorable: enabling it is a reviewable schema change, not DML, and no role - including any Platform
-- Admin role - can turn it on. No conflict-resolution authority is granted to anyone by this table.
CREATE TABLE transfer_approval_conflict_exceptions (
    exception_case       text PRIMARY KEY CHECK (exception_case IN ('source_destination_owner')),
    enabled              boolean NOT NULL DEFAULT false,
    authority_decision_ref text,     -- the recorded decision that would permit it; none exists yet
    recorded_at          timestamptz NOT NULL DEFAULT now(),
    CHECK (enabled = false),                                  -- DEFERRED: fail closed
    CHECK (authority_decision_ref IS NULL OR enabled)          -- no decision reference without an enabled rule
);
INSERT INTO transfer_approval_conflict_exceptions (exception_case) VALUES ('source_destination_owner');

CREATE FUNCTION guard_transfer_approval_separation() RETURNS trigger LANGUAGE plpgsql AS $body$
DECLARE v_other text; v_exception_enabled boolean;
BEGIN
  SELECT a.approval_kind INTO v_other
    FROM public.transfer_approvals a
   WHERE a.case_id = NEW.case_id
     AND a.approver_ref = NEW.approver_ref
     AND a.approval_kind <> NEW.approval_kind
     AND NOT EXISTS (SELECT 1 FROM public.transfer_approval_revocations r WHERE r.approval_id = a.approval_id)
     AND (a.valid_until IS NULL OR a.valid_until > clock_timestamp())
   LIMIT 1;
  IF v_other IS NULL THEN
    RETURN NEW;
  END IF;
  SELECT enabled INTO v_exception_enabled
    FROM public.transfer_approval_conflict_exceptions WHERE exception_case = 'source_destination_owner';
  IF v_exception_enabled IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'approver already holds the % approval for this transfer: one person cannot satisfy incompatible approval kinds (the source_destination_owner exception is disabled)', v_other
      USING ERRCODE='check_violation';
  END IF;
  -- Unreachable while the exception is disabled. Even if it were enabled, there is no approved independent
  -- authority to evaluate it here, so the transfer still fails closed rather than self-approving.
  RAISE EXCEPTION 'the source_destination_owner exception has no approved enforcement authority; transfer fails closed'
    USING ERRCODE='check_violation';
END; $body$;
CREATE TRIGGER transfer_approvals_separation
  BEFORE INSERT ON transfer_approvals
  FOR EACH ROW EXECUTE FUNCTION guard_transfer_approval_separation();

-- The recorded authority snapshot must name the side of the case the approval kind belongs to. This is a
-- structural cross-Workspace check on the stored evidence; it does NOT verify the authority itself.
CREATE FUNCTION guard_transfer_approval_side() RETURNS trigger LANGUAGE plpgsql AS $body$
DECLARE v_src uuid; v_dst uuid; v_claimed uuid;
BEGIN
  SELECT source_workspace_id, destination_workspace_id INTO v_src, v_dst
    FROM public.transfer_cases WHERE case_id = NEW.case_id;
  BEGIN
    v_claimed := (NEW.authority_snapshot->>'workspace_id')::uuid;
  EXCEPTION WHEN invalid_text_representation THEN
    RAISE EXCEPTION 'authority_snapshot.workspace_id is not a uuid' USING ERRCODE='check_violation';
  END;
  IF NEW.approval_kind = 'fee_confirmation' AND v_claimed IS DISTINCT FROM v_src THEN
    RAISE EXCEPTION 'fee confirmation must be recorded by the SOURCE Workspace of this case' USING ERRCODE='check_violation';
  END IF;
  IF NEW.approval_kind = 'destination_acceptance' AND v_claimed IS DISTINCT FROM v_dst THEN
    RAISE EXCEPTION 'destination acceptance must be recorded by the DESTINATION Workspace of this case' USING ERRCODE='check_violation';
  END IF;
  RETURN NEW;
END; $body$;
CREATE TRIGGER transfer_approvals_side
  BEFORE INSERT ON transfer_approvals
  FOR EACH ROW EXECUTE FUNCTION guard_transfer_approval_side();

CREATE FUNCTION guard_transfer_approval_revocation_insert() RETURNS trigger LANGUAGE plpgsql AS $body$
DECLARE v_case uuid;
BEGIN
  SELECT case_id INTO v_case FROM public.transfer_approvals WHERE approval_id = NEW.approval_id;
  PERFORM 1 FROM public.transfer_cases WHERE case_id = v_case FOR UPDATE;
  RETURN NEW;
END; $body$;
CREATE TRIGGER transfer_approval_revocations_serialise
  BEFORE INSERT ON public.transfer_approval_revocations
  FOR EACH ROW EXECUTE FUNCTION guard_transfer_approval_revocation_insert();

-- Idempotency / command deduplication for ownership-changing commands.
CREATE TABLE command_log (
    idempotency_key  text PRIMARY KEY,
    command_name     text NOT NULL,
    payload_hash     bytea NOT NULL CHECK (octet_length(payload_hash) = 32),
    result_case_id   uuid REFERENCES transfer_cases (case_id),
    recorded_at      timestamptz NOT NULL DEFAULT now()
);

-- Inbox deduplication ledger. Consumers insert event_id once and reject stale generations.
-- Transfer Saga event envelope. The row is written in the SAME transaction as the state change it reports
-- and is then COMPLETELY immutable: delivery state lives in outbox_deliveries (cp_12), never here.
--   schema_version   consumers reject an envelope version they do not understand
--   payload_hash     transport integrity of the stored payload (see cp_12 for what this hash is and is not)
--   correlation_id   one Saga run; causation_id is the event this one was caused by, if any
-- The payload carries identifiers and generations only, never personal data.
CREATE TABLE outbox_events (
    event_id     uuid PRIMARY KEY,
    case_id      uuid REFERENCES transfer_cases (case_id),
    event_type   text NOT NULL CHECK (length(btrim(event_type)) > 0),
    schema_version integer NOT NULL CHECK (schema_version >= 1),
    payload      jsonb NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(payload) = 'object'),
    payload_hash bytea NOT NULL CHECK (octet_length(payload_hash) = 32),
    student_id   uuid NOT NULL REFERENCES platform_students (student_id),
    source_workspace_id      uuid REFERENCES workspaces (workspace_id),
    destination_workspace_id uuid REFERENCES workspaces (workspace_id),
    ownership_generation bigint NOT NULL CHECK (ownership_generation >= 1),
    correlation_id uuid NOT NULL,
    causation_id   uuid,
    created_at   timestamptz NOT NULL DEFAULT now(),
    CHECK (source_workspace_id IS NULL OR destination_workspace_id IS NULL
           OR source_workspace_id <> destination_workspace_id)
);
CREATE INDEX outbox_events_student_generation ON outbox_events (student_id, ownership_generation);
CREATE INDEX outbox_events_correlation ON outbox_events (correlation_id);

CREATE FUNCTION guard_outbox_event_mutation() RETURNS trigger LANGUAGE plpgsql AS $body$
BEGIN
  RAISE EXCEPTION 'outbox events are immutable; delivery state belongs in outbox_deliveries'
    USING ERRCODE='check_violation';
END; $body$;
CREATE TRIGGER outbox_events_immutable
  BEFORE UPDATE OR DELETE ON outbox_events
  FOR EACH ROW EXECUTE FUNCTION guard_outbox_event_mutation();

-- The envelope hash is verified against the payload actually stored, so a producer cannot record an
-- envelope whose hash does not describe its own payload.
CREATE FUNCTION guard_outbox_payload_hash() RETURNS trigger LANGUAGE plpgsql AS $body$
BEGIN
  IF NEW.payload_hash <> sha256(convert_to(NEW.payload::text, 'UTF8')) THEN
    RAISE EXCEPTION 'outbox payload_hash does not match the stored payload' USING ERRCODE='check_violation';
  END IF;
  RETURN NEW;
END; $body$;
CREATE TRIGGER outbox_events_payload_hash
  BEFORE INSERT ON outbox_events
  FOR EACH ROW EXECUTE FUNCTION guard_outbox_payload_hash();

-- What a Workspace reported back about one delivered event. One row per (event, workspace): a second
-- report for the same pair is a duplicate acknowledgement and must not create a second row.
-- The outcome is the Workspace's own recorded result; the Control Plane does not re-derive it.
CREATE TABLE inbox_events (
    event_id uuid NOT NULL REFERENCES outbox_events (event_id),
    workspace_id uuid NOT NULL REFERENCES workspaces(workspace_id),
    student_id uuid NOT NULL REFERENCES platform_students(student_id),
    ownership_generation bigint NOT NULL CHECK (ownership_generation >= 1),
    outcome text NOT NULL CHECK (outcome IN ('applied','ignored_stale','quarantined_future','rejected_payload')),
    outcome_reason text,
    received_at timestamptz NOT NULL DEFAULT now(),
    processed_at timestamptz,
    PRIMARY KEY (event_id, workspace_id)
);

-- Transactional outbox: written in the same transaction as the ownership switch.

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
