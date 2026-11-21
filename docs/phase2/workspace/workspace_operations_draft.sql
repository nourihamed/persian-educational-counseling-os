-- WORKSPACE DB — DRAFT: files, notifications, retention and legal hold (Batch 8).
-- Apply AFTER workspace_schema_draft.sql, workspace_activation_transactions.sql, workspace_counselor_scope_draft.sql
-- (which must itself follow workspace_transfer_freeze.sql),
-- workspace_governance_events_draft.sql, workspace_archive_transactions.sql, workspace_inbox_projection.sql
-- and workspace_transfer_freeze.sql. Synthetic only (D-014). NOT a migration.
--
-- WHAT THE BASELINE INSPECTION FOUND, MEASURED ON A LOADED DATABASE
--   The five operations tables existed as bare skeletons. Interrogating the catalog rather than reading the
--   DDL showed what that meant in practice:
--     * `private_file_objects` carried the transfer write barrier (good) and NOTHING else: the runtime role
--       holds UPDATE on every column, so sha256, object_key, byte_size, content_type and
--       encryption_key_version were all rewritable after the fact, and `archived` was not terminal. A
--       mutable content hash is not an integrity control.
--     * `in_app_notifications` had no reference to a student at all, so the transfer fence COULD NOT BE
--       EXPRESSED for it, and no constraint tied a recipient to this Workspace. The Saga contract
--       ("source ... is rejected for writes, jobs, files, exports and notifications"), the API
--       authorization contract (threats: "recipient substitution; child/Workspace mismatch; stale queued
--       notification after transfer; sensitive data in event payload") and the guardian authority matrix
--       ("Child A permission cannot be used for child B, including ... notifications") all require the
--       opposite.
--     * `legal_holds` had NO grants to any application role, no immutability, no referential integrity for
--       its polymorphic (entity_type, entity_id), and nothing anywhere consulted it. A hold on a mistyped
--       id silently protected nothing: it failed OPEN.
--     * No retention policy, category or disposition model existed at all, although the retention contract
--       §3 requires one. Section 4 of the same contract requires that a destructive disposition be refused
--       while a duration is unresolved — and every single duration in the phase 1 schedule is
--       NEEDS-DECISION, PROPOSAL or LEGAL-REVIEW (Q-020).
--     * 23 append-only or immutable tables guarded UPDATE and DELETE with row triggers. A row trigger does
--       not see TRUNCATE.
--
-- WHAT IS ENFORCED HERE
--   * File object facts are immutable and the state machine is forward-only, with `archived` terminal.
--   * A notification names the student it concerns, so the transfer barrier covers it through the existing
--     catalog-driven coverage view; its recipient must be a member of this Workspace (for a notification about a
--     student, one who can reach that student; corrected 2026-11-18), the student itself, or a verified
--     guardian OF THAT STUDENT; its payload may not carry a plaintext contact number; and
--     its content is immutable once written.
--   * A legal hold resolves its target through a reviewed entity-type registry and is refused if the
--     target does not exist. Placement facts are immutable, release is one-way and a hold cannot be
--     deleted or truncated.
--   * Retention policy versions are immutable and category-scoped. A policy is `approved` only with a
--     duration AND an approval reference; the nine categories are seeded `needs_decision` exactly as the
--     phase 1 schedule records them.
--   * A single fail-closed gate, assert_destructive_disposition_allowed(), which refuses when the
--     category is unknown, the entity type is unregistered, the target row is absent, ANY hold is active,
--     or no approved policy version is effective. Today the last condition alone refuses everything,
--     which is the behaviour the contract requires while Q-020 is open.
--   * Append-only tables reject TRUNCATE as well as UPDATE and DELETE.
--
-- WHAT IS NOT CLAIMED, AND CANNOT BE
--   * No retention period is chosen, proposed or implied. Q-020 stays open; the seeded rows carry NULL
--     durations on purpose and the gate treats them as a refusal, never as "delete now" or "keep forever".
--   * No authority is invented. WHO may place or release a legal hold, and WHO may authorize an
--     irreversible disposition, are Product Owner decisions (retention contract §9); no application role
--     is granted either capability here, so in this draft only the table owner can, which is a synthetic
--     posture and not a production authority model. Registered as OPS-HOLD-AUTH and OPS-DISP-AUTH.
--   * There is no disposition executor, no job runner, no object-store client and no backup tooling in
--     this repository. The gate is a database mechanism that any future executor must pass; it does not
--     delete anything, does not reach object storage, caches, exports or backups, and is NOT evidence
--     that a deletion would be complete. Retention contract §7 remains unimplemented.
--   * Recipient authority is checked AT INSERT. The contracts also require a re-check at DELIVERY, which
--     needs a notification worker; none exists, so that is not claimed (PS-8 / OPS-NOTIF-DELIVERY).
--   * No notification channel adapter (Telegram, SMS, e-mail) is implemented or designed here; those are
--     later phases, and nothing in core depends on a channel.
BEGIN;

-- ======================================================================================================
-- 1. PRIVATE FILE OBJECTS — immutable facts, forward-only state
-- ======================================================================================================
-- Which columns are facts about the stored object (immutable) and which are lifecycle (mutable) is stated
-- once, here, rather than left to whoever writes the next UPDATE.
CREATE FUNCTION guard_private_file_object() RETURNS trigger LANGUAGE plpgsql AS $body$
BEGIN
  IF TG_OP = 'DELETE' THEN
    -- A file row is the only record that an object exists in the store. Deleting the row without
    -- deleting the object loses the object; deleting both is a disposition, which must pass the gate in
    -- section 5. Neither can be done by a bare DELETE.
    RAISE EXCEPTION 'a private file object row cannot be deleted; archive it, or run an authorized disposition'
      USING ERRCODE='check_violation';
  END IF;
  IF TG_OP = 'INSERT' THEN
    IF NEW.state = 'archived' THEN
      RAISE EXCEPTION 'a file object is not created in the archived state' USING ERRCODE='check_violation';
    END IF;
    RETURN NEW;
  END IF;

  IF (NEW.file_id, NEW.object_key, NEW.storage_provider, NEW.content_type, NEW.byte_size, NEW.sha256,
      NEW.encryption_key_version, NEW.uploaded_by_membership_id, NEW.created_at)
     IS DISTINCT FROM
     (OLD.file_id, OLD.object_key, OLD.storage_provider, OLD.content_type, OLD.byte_size, OLD.sha256,
      OLD.encryption_key_version, OLD.uploaded_by_membership_id, OLD.created_at) THEN
    RAISE EXCEPTION 'file identity, location, size, content hash, key version and uploader are immutable'
      USING ERRCODE='check_violation';
  END IF;

  -- quarantined -> available (a scan cleared it) or quarantined -> archived; available -> archived.
  -- archived is terminal: an archived object must not become servable again without a new record.
  IF OLD.state = 'archived' AND NEW.state <> 'archived' THEN
    RAISE EXCEPTION 'an archived file object cannot be reopened' USING ERRCODE='check_violation';
  END IF;
  IF OLD.state = 'available' AND NEW.state = 'quarantined' THEN
    RAISE EXCEPTION 'a file object cannot be returned to quarantine; archive it and record a new object'
      USING ERRCODE='check_violation';
  END IF;
  RETURN NEW;
END; $body$;
CREATE TRIGGER private_file_objects_guard
  BEFORE INSERT OR UPDATE OR DELETE ON private_file_objects
  FOR EACH ROW EXECUTE FUNCTION guard_private_file_object();

-- ======================================================================================================
-- 2. IN-APP NOTIFICATIONS — recipient isolation, payload hygiene, immutability
-- ======================================================================================================
-- The student_id column itself is declared in workspace_schema_draft.sql, NOT here, so that the
-- catalog-driven barrier installation in workspace_transfer_freeze.sql picks the table up automatically.
-- If it were added in this file the coverage view would list it without a trigger, and FRZ-01 would fail —
-- which is the coverage test doing its job.

-- A recipient is legitimate in exactly three cases, and the third is student-bound: a guardian verified
-- for student A is not a recipient for student B. This is the "recipient substitution" and "child /
-- Workspace mismatch" threat from the API authorization contract, and the guardian authority matrix's
-- rule that child A's authority can never be used for child B, notifications included.
-- SECURITY INVOKER on purpose. It is called from a trigger by whoever inserts the notification, and the
-- Workspace runtime already holds SELECT on all three authority tables it reads. Making it a definer
-- function would mean granting PUBLIC the right to execute a definer function (SEC-07), which buys
-- nothing here: an inserter that cannot read the authority tables is refused by PostgreSQL instead of by
-- this message, and both outcomes are a refusal.
CREATE FUNCTION assert_notification_recipient_allowed(p_recipient uuid, p_student uuid) RETURNS void
LANGUAGE plpgsql AS $body$
BEGIN
  IF p_recipient IS NULL THEN
    RAISE EXCEPTION 'a notification needs a recipient' USING ERRCODE='check_violation';
  END IF;
  -- 1. an ACTIVE member of this Workspace. 'invited' and 'suspended' are not recipients: a suspended
  --    membership must not keep receiving student information.
  --    For a notification ABOUT A STUDENT, membership is not enough: the member must be able to reach that
  --    student through an active, accepted counselor assignment (workspace_counselor_scope_draft.sql).
  --    CORRECTED 2026-11-18. As first written in Batch 8, this branch accepted ANY active member as the
  --    recipient of a notification about ANY student, which is a cross-counselor disclosure path: counselor
  --    B could be sent a notification about counselor A's student. OPS-13c is the regression test.
  --    Managers are not special-cased: the explicit manager permission the contract requires has no
  --    defined vocabulary yet, so a manager is refused here, which is the contract's own default.
  IF p_student IS NULL THEN
    IF EXISTS (SELECT 1 FROM public.workspace_memberships m
                WHERE m.platform_user_id = p_recipient AND m.status = 'active') THEN
      RETURN;
    END IF;
  ELSIF EXISTS (SELECT 1 FROM public.workspace_memberships m
                 WHERE m.platform_user_id = p_recipient AND m.status = 'active'
                   AND public.counselor_may_access_student(m.membership_id, p_student)) THEN
    RETURN;
  END IF;
  IF p_student IS NOT NULL THEN
    -- 2. the student the notification is about.
    IF EXISTS (SELECT 1 FROM public.students s
                WHERE s.student_id = p_student AND s.platform_student_id = p_recipient) THEN
      RETURN;
    END IF;
    -- 3. a guardian with a verified, unrevoked link TO THAT STUDENT. This is a necessary condition, not a
    --    sufficient one: scope and permission are re-checked at delivery, which needs a worker that does
    --    not exist (OPS-NOTIF-DELIVERY).
    IF EXISTS (SELECT 1 FROM public.student_guardian_links l
                WHERE l.student_id = p_student
                  AND l.guardian_platform_user_id = p_recipient
                  AND l.verification_state = 'verified'
                  AND l.revoked_at IS NULL) THEN
      RETURN;
    END IF;
  END IF;
  RAISE EXCEPTION 'recipient % is not an active member of this Workspace able to reach that student, not the '
                  'student the notification is about, and not a verified guardian of that student', p_recipient
    USING ERRCODE='check_violation';
END; $body$;

-- A plaintext contact number must never reach a notification payload. The Control Plane encrypts contacts
-- and indexes only a keyed fingerprint (CID-01..CID-05); a notification that quoted the number would
-- defeat that, and the contact-change contract says so explicitly: "Notifications must not include the
-- full new number; use a masked display only after authorization."
-- The scan is over jsonb STRING leaves at any depth, so nesting does not hide a number.
CREATE FUNCTION jsonb_has_plaintext_contact(p jsonb) RETURNS boolean
LANGUAGE sql IMMUTABLE AS $body$
  SELECT EXISTS (
    SELECT 1
      FROM jsonb_path_query(p, 'strict $.**') AS leaf
     WHERE jsonb_typeof(leaf) = 'string'
       AND (leaf #>> '{}') ~ '(^|[^0-9])(\+98|0)9[0-9]{9}([^0-9]|$)'
    UNION ALL
    SELECT 1
      FROM jsonb_path_query(p, 'strict $.**') AS leaf
     WHERE jsonb_typeof(leaf) = 'string'
       AND (leaf #>> '{}') ~ '(^|[^0-9+])\+[1-9][0-9]{9,14}([^0-9]|$)'
  );
$body$;

CREATE FUNCTION guard_in_app_notification() RETURNS trigger LANGUAGE plpgsql AS $body$
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'an in-app notification cannot be deleted; disposition goes through the retention gate'
      USING ERRCODE='check_violation';
  END IF;
  IF TG_OP = 'INSERT' THEN
    PERFORM public.assert_notification_recipient_allowed(NEW.recipient_platform_user_id, NEW.student_id);
    IF public.jsonb_has_plaintext_contact(NEW.payload) THEN
      RAISE EXCEPTION 'a notification payload must not carry a plaintext contact number; reference the '
                      'subject by id and render a masked display only after authorization'
        USING ERRCODE='check_violation';
    END IF;
    IF NEW.read_at IS NOT NULL THEN
      RAISE EXCEPTION 'a notification is not created already read' USING ERRCODE='check_violation';
    END IF;
    RETURN NEW;
  END IF;

  -- Everything except read_at is immutable: re-pointing a delivered notification at another recipient, or
  -- rewriting its payload, is recipient substitution after the fact.
  IF (NEW.notification_id, NEW.recipient_platform_user_id, NEW.student_id, NEW.notification_type,
      NEW.template_version, NEW.payload, NEW.idempotency_key, NEW.created_at)
     IS DISTINCT FROM
     (OLD.notification_id, OLD.recipient_platform_user_id, OLD.student_id, OLD.notification_type,
      OLD.template_version, OLD.payload, OLD.idempotency_key, OLD.created_at) THEN
    RAISE EXCEPTION 'notification identity, recipient, subject, template and payload are immutable; only '
                    'read_at may change' USING ERRCODE='check_violation';
  END IF;
  IF OLD.read_at IS NOT NULL AND NEW.read_at IS DISTINCT FROM OLD.read_at THEN
    RAISE EXCEPTION 'read_at is set once and cannot be rewritten or cleared' USING ERRCODE='check_violation';
  END IF;
  RETURN NEW;
END; $body$;
CREATE TRIGGER in_app_notifications_guard
  BEFORE INSERT OR UPDATE OR DELETE ON in_app_notifications
  FOR EACH ROW EXECUTE FUNCTION guard_in_app_notification();

-- ======================================================================================================
-- 3. RETENTION ENTITY REGISTRY — enforceable integrity for a polymorphic reference
-- ======================================================================================================
-- (entity_type, entity_id) on legal_holds is a polymorphic reference, which the brief forbids leaving
-- without enforceable referential integrity. The registry makes it enforceable: an entity type must name
-- a real table and a real uuid primary-key column, which is checked against the catalog when the row is
-- registered, and every hold then resolves its target through it.
CREATE TABLE retention_entity_types (
  entity_type  text PRIMARY KEY,
  table_name   text NOT NULL,
  pk_column    text NOT NULL,
  category_key text NOT NULL,
  registered_at timestamptz NOT NULL DEFAULT now()
);

CREATE FUNCTION guard_retention_entity_type() RETURNS trigger LANGUAGE plpgsql AS $body$
DECLARE v_oid oid; v_typ text;
BEGIN
  IF TG_OP = 'DELETE' THEN
    -- Removing a type would silently make every hold that used it unresolvable.
    RAISE EXCEPTION 'a registered retention entity type cannot be removed' USING ERRCODE='check_violation';
  END IF;
  v_oid := to_regclass('public.' || quote_ident(NEW.table_name));
  IF v_oid IS NULL THEN
    RAISE EXCEPTION 'retention entity type % names table %, which does not exist', NEW.entity_type, NEW.table_name
      USING ERRCODE='check_violation';
  END IF;
  SELECT format_type(a.atttypid, NULL) INTO v_typ
    FROM pg_attribute a
   WHERE a.attrelid = v_oid AND a.attname = NEW.pk_column AND a.attnum > 0 AND NOT a.attisdropped;
  IF v_typ IS NULL THEN
    RAISE EXCEPTION 'retention entity type % names column %.%, which does not exist',
      NEW.entity_type, NEW.table_name, NEW.pk_column USING ERRCODE='check_violation';
  END IF;
  IF v_typ <> 'uuid' THEN
    RAISE EXCEPTION 'retention entity key %.% must be uuid, not %', NEW.table_name, NEW.pk_column, v_typ
      USING ERRCODE='check_violation';
  END IF;
  RETURN NEW;
END; $body$;
CREATE TRIGGER retention_entity_types_guard
  BEFORE INSERT OR UPDATE OR DELETE ON retention_entity_types
  FOR EACH ROW EXECUTE FUNCTION guard_retention_entity_type();

-- Resolves whether a target row exists, disclosing a boolean and nothing else. SECURITY INVOKER: inside
-- the gate below it therefore runs with the gate owner's privileges, which are column-scoped to the
-- primary keys of the registered tables (see workspace_roles_setup_draft.sql). Keeping it invoker avoids
-- a second PUBLIC-executable definer function (SEC-07).
CREATE FUNCTION retention_entity_exists(p_entity_type text, p_entity_id uuid) RETURNS boolean
LANGUAGE plpgsql AS $body$
DECLARE r public.retention_entity_types%ROWTYPE; v_found boolean;
BEGIN
  SELECT * INTO r FROM public.retention_entity_types WHERE entity_type = p_entity_type;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'entity type % is not registered for retention; register it or correct the caller',
      p_entity_type USING ERRCODE='check_violation';
  END IF;
  EXECUTE format('SELECT EXISTS (SELECT 1 FROM public.%I WHERE %I = $1)', r.table_name, r.pk_column)
     INTO v_found USING p_entity_id;
  RETURN v_found;
END; $body$;

-- ======================================================================================================
-- 4. LEGAL HOLDS — resolvable, immutable, one-way release
-- ======================================================================================================
CREATE FUNCTION guard_legal_hold() RETURNS trigger LANGUAGE plpgsql AS $body$
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'a legal hold record cannot be deleted; release it, which is recorded'
      USING ERRCODE='check_violation';
  END IF;
  IF TG_OP = 'INSERT' THEN
    IF length(btrim(NEW.hold_ref)) = 0 OR length(btrim(NEW.reason)) = 0 THEN
      RAISE EXCEPTION 'a legal hold needs an authority reference and a reason' USING ERRCODE='check_violation';
    END IF;
    IF NEW.released_at IS NOT NULL THEN
      RAISE EXCEPTION 'a legal hold is not created already released' USING ERRCODE='check_violation';
    END IF;
    -- FAIL CLOSED: a hold whose target cannot be resolved protects nothing, and a hold that silently
    -- protects nothing is worse than no hold, because the register says the data is held.
    IF NOT public.retention_entity_exists(NEW.entity_type, NEW.entity_id) THEN
      RAISE EXCEPTION 'legal hold target %:% does not exist', NEW.entity_type, NEW.entity_id
        USING ERRCODE='check_violation';
    END IF;
    RETURN NEW;
  END IF;

  IF (NEW.legal_hold_id, NEW.entity_type, NEW.entity_id, NEW.hold_ref, NEW.reason,
      NEW.placed_by_membership_id, NEW.placed_at)
     IS DISTINCT FROM
     (OLD.legal_hold_id, OLD.entity_type, OLD.entity_id, OLD.hold_ref, OLD.reason,
      OLD.placed_by_membership_id, OLD.placed_at) THEN
    RAISE EXCEPTION 'legal hold scope, authority reference, reason and placement are immutable'
      USING ERRCODE='check_violation';
  END IF;
  IF OLD.released_at IS NOT NULL THEN
    RAISE EXCEPTION 'a released legal hold cannot be changed or re-placed; place a new hold'
      USING ERRCODE='check_violation';
  END IF;
  IF NEW.released_at IS NULL THEN
    RAISE EXCEPTION 'the only permitted change to a live legal hold is its release' USING ERRCODE='check_violation';
  END IF;
  RETURN NEW;
END; $body$;
CREATE TRIGGER legal_holds_guard
  BEFORE INSERT OR UPDATE OR DELETE ON legal_holds
  FOR EACH ROW EXECUTE FUNCTION guard_legal_hold();

CREATE INDEX legal_holds_active_lookup ON legal_holds(entity_type, entity_id) WHERE released_at IS NULL;

-- ======================================================================================================
-- 5. RETENTION POLICY VERSIONS AND THE FAIL-CLOSED DISPOSITION GATE
-- ======================================================================================================
-- The nine categories are transcribed from docs/phase1/DATA_RETENTION_SCHEDULE_DRAFT.md §1. The STATUS of
-- every period in §2 of that document is NEEDS-DECISION, PROPOSAL or LEGAL-REVIEW; not one is approved.
-- That is why every seeded row below is `needs_decision` with a NULL duration. No period is invented here.
CREATE TABLE retention_categories (
  category_key text PRIMARY KEY CHECK (category_key ~ '^R[1-9]$'),
  title        text NOT NULL,
  source_ref   text NOT NULL        -- where the category is defined; this schema does not define it
);

CREATE TABLE retention_policy_versions (
  policy_id          uuid PRIMARY KEY,
  category_key       text NOT NULL REFERENCES retention_categories(category_key),
  policy_version     text NOT NULL CHECK (length(btrim(policy_version)) > 0),
  status             text NOT NULL CHECK (status IN ('needs_decision','approved')),
  duration_days      integer CHECK (duration_days IS NULL OR duration_days > 0),
  disposition_action text CHECK (disposition_action IS NULL OR disposition_action IN
                        ('restrict_access','archive','pseudonymize','anonymize','delete_record','delete_object')),
  approval_ref       text,
  jurisdiction       text,
  effective_from     timestamptz,
  recorded_at        timestamptz NOT NULL DEFAULT now(),
  UNIQUE (category_key, policy_version),
  -- An approved policy cannot exist without a duration, an action, an approval reference AND an effective
  -- date. This is what stops a policy becoming "approved" by accident or by a partial UPDATE.
  CHECK (status <> 'approved' OR (duration_days IS NOT NULL AND disposition_action IS NOT NULL
                                  AND approval_ref IS NOT NULL AND length(btrim(approval_ref)) > 0
                                  AND effective_from IS NOT NULL)),
  CHECK (status <> 'needs_decision' OR (duration_days IS NULL AND approval_ref IS NULL))
);
-- Deterministic effective-date selection: at most one approved policy per category per instant.
CREATE UNIQUE INDEX one_approved_policy_per_category_date
  ON retention_policy_versions(category_key, effective_from) WHERE status = 'approved';

CREATE FUNCTION guard_retention_policy_version() RETURNS trigger LANGUAGE plpgsql AS $body$
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'a retention policy version is immutable history and cannot be deleted'
      USING ERRCODE='check_violation';
  END IF;
  IF TG_OP = 'UPDATE' THEN
    -- Including status: a needs-decision policy does not become approved by an UPDATE. Approval is a new
    -- version, so the record of what was in force at any past moment stays true.
    RAISE EXCEPTION 'a retention policy version is immutable; record a NEW version to change a policy'
      USING ERRCODE='check_violation';
  END IF;
  RETURN NEW;
END; $body$;
CREATE TRIGGER retention_policy_versions_guard
  BEFORE INSERT OR UPDATE OR DELETE ON retention_policy_versions
  FOR EACH ROW EXECUTE FUNCTION guard_retention_policy_version();

INSERT INTO retention_categories(category_key, title, source_ref) VALUES
 ('R1','Student profile and educational records','docs/phase1/DATA_RETENTION_SCHEDULE_DRAFT.md §1'),
 ('R2','Accounts and authentication',            'docs/phase1/DATA_RETENTION_SCHEDULE_DRAFT.md §1'),
 ('R3','Audit records',                          'docs/phase1/DATA_RETENTION_SCHEDULE_DRAFT.md §1'),
 ('R4','Orders, subscriptions and payments',     'docs/phase1/DATA_RETENTION_SCHEDULE_DRAFT.md §1'),
 ('R5','Notifications and delivery logs',        'docs/phase1/DATA_RETENTION_SCHEDULE_DRAFT.md §1'),
 ('R6','Files and exports',                      'docs/phase1/DATA_RETENTION_SCHEDULE_DRAFT.md §1'),
 ('R7','Backups and snapshots',                  'docs/phase1/DATA_RETENTION_SCHEDULE_DRAFT.md §1'),
 ('R8','Operational logs',                       'docs/phase1/DATA_RETENTION_SCHEDULE_DRAFT.md §1'),
 ('R9','Workspace database roles and routing metadata','docs/phase1/DATA_RETENTION_SCHEDULE_DRAFT.md §1');

-- One `needs_decision` version per category, so the gate has something to find and refuse rather than
-- failing with "no policy at all", which a future caller might mistake for a misconfiguration.
INSERT INTO retention_policy_versions(policy_id, category_key, policy_version, status)
SELECT gen_random_uuid(), category_key, 'v0-needs-decision', 'needs_decision' FROM retention_categories;

-- The entity types this draft can resolve. The category of each is read from the phase 1 definitions
-- (R1 student records, R5 notifications, R6 files, R3 audit) — those are the document's own categories,
-- not a classification invented here. The DURATION for each remains undecided.
INSERT INTO retention_entity_types(entity_type, table_name, pk_column, category_key) VALUES
 ('student',             'students',             'student_id',       'R1'),
 ('enrollment',          'enrollments',          'enrollment_id',    'R1'),
 ('private_file_object', 'private_file_objects', 'file_id',          'R6'),
 ('in_app_notification', 'in_app_notifications', 'notification_id',  'R5'),
 ('audit_event',         'audit_events',         'audit_event_id',   'R3');

-- THE GATE. Every destructive disposition path that is ever built must call this and must not catch its
-- exception. It refuses for five distinct reasons, each named in its message so an operator can tell a
-- legal hold apart from a missing decision.
-- clock_timestamp() on purpose (CLK-01/CLK-02): an effective-date decision read from a transaction-start
-- clock can be defeated by holding a transaction open.
CREATE FUNCTION assert_destructive_disposition_allowed(
  p_entity_type text,
  p_entity_id   uuid,
  p_action      text
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=pg_catalog,pg_temp
AS $body$
DECLARE
  r public.retention_entity_types%ROWTYPE;
  v_now timestamptz;
  v_holds integer;
  v_policies integer;
  v_status text;
BEGIN
  IF p_action IS NULL OR p_action NOT IN ('pseudonymize','anonymize','delete_record','delete_object') THEN
    RAISE EXCEPTION 'disposition action % is not a destructive action this gate governs; '
                    'restrict_access and archive are not erasure', coalesce(p_action,'<null>')
      USING ERRCODE='check_violation';
  END IF;

  SELECT * INTO r FROM public.retention_entity_types WHERE entity_type = p_entity_type;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'entity type % is not registered for retention; a disposition cannot be authorized '
                    'for data whose category is unknown', p_entity_type USING ERRCODE='check_violation';
  END IF;

  IF NOT public.retention_entity_exists(p_entity_type, p_entity_id) THEN
    RAISE EXCEPTION 'disposition target %:% does not exist; refusing rather than reporting a deletion that '
                    'did not happen', p_entity_type, p_entity_id USING ERRCODE='check_violation';
  END IF;

  SELECT count(*) INTO v_holds FROM public.legal_holds h
   WHERE h.entity_type = p_entity_type AND h.entity_id = p_entity_id AND h.released_at IS NULL;
  IF v_holds > 0 THEN
    RAISE EXCEPTION 'a legal hold is active on %:% (% live hold(s)); destructive disposition is blocked',
      p_entity_type, p_entity_id, v_holds USING ERRCODE='check_violation';
  END IF;

  v_now := clock_timestamp();
  SELECT count(*) INTO v_policies
    FROM public.retention_policy_versions p
   WHERE p.category_key = r.category_key AND p.status = 'approved'
     AND p.effective_from <= v_now
     AND p.disposition_action = p_action;
  IF v_policies = 0 THEN
    SELECT string_agg(DISTINCT p.status, ',') INTO v_status
      FROM public.retention_policy_versions p WHERE p.category_key = r.category_key;
    RAISE EXCEPTION 'no approved retention policy authorizes % for category % (status: %); the period is a '
                    'Product Owner and legal decision (Q-020) and an unresolved duration BLOCKS '
                    'destructive disposition — it means neither "delete now" nor "keep forever"',
      p_action, r.category_key, coalesce(v_status,'none') USING ERRCODE='check_violation';
  END IF;
  IF v_policies > 1 THEN
    RAISE EXCEPTION 'ambiguous retention policy for category %: % approved versions are effective; '
                    'ambiguity fails closed', r.category_key, v_policies USING ERRCODE='check_violation';
  END IF;
END; $body$;

-- ======================================================================================================
-- 6. APPEND-ONLY MEANS APPEND-ONLY, INCLUDING TRUNCATE
-- ======================================================================================================
-- A BEFORE UPDATE OR DELETE row trigger does not fire for TRUNCATE. 23 tables in this database were
-- append-only or immutable by row trigger and none of them refused TRUNCATE.
--
-- MEASURED REACHABILITY, so this is not overstated: TRUNCATE is not held by any application role. In a
-- loaded database the only grantee is ws_<key>_table_owner, which is the NOLOGIN owner; runtime, worker
-- and exporter hold no TRUNCATE on any table. So this closes a gap that an ordinary identity could not
-- reach today — it is hardening, not a fixed vulnerability. It matters because the owner role is used by
-- migrations and by any future maintenance script, and because "append-only" is claimed as evidence in
-- this project's own exit criteria.
CREATE FUNCTION reject_truncate() RETURNS trigger LANGUAGE plpgsql AS $body$
BEGIN
  RAISE EXCEPTION '% is append-only or immutable; TRUNCATE is refused', TG_TABLE_NAME
    USING ERRCODE='check_violation';
END; $body$;

DO $install$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT c.oid, c.relname
      FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE n.nspname = 'public' AND c.relkind = 'r'
       AND EXISTS (SELECT 1 FROM pg_trigger t JOIN pg_proc p ON p.oid = t.tgfoid
                    WHERE t.tgrelid = c.oid AND NOT t.tgisinternal
                      AND (p.prosrc ILIKE '%append-only%' OR p.prosrc ILIKE '%immutable%'
                           OR t.tgname ILIKE '%append%' OR t.tgname ILIKE '%immutable%'
                           OR t.tgname ILIKE '%guard%'))
       AND NOT EXISTS (SELECT 1 FROM pg_trigger t2
                        WHERE t2.tgrelid = c.oid AND NOT t2.tgisinternal AND (t2.tgtype & 32) > 0)
     ORDER BY c.relname
  LOOP
    EXECUTE format(
      'CREATE TRIGGER %I BEFORE TRUNCATE ON public.%I FOR EACH STATEMENT EXECUTE FUNCTION public.reject_truncate()',
      'zz_reject_truncate_' || r.relname, r.relname);
  END LOOP;
END
$install$;

-- Which tables claim immutability, and whether TRUNCATE is actually refused there. A row with
-- truncate_guarded = false is a hole, not an exemption.
CREATE VIEW append_only_truncate_coverage AS
  SELECT c.relname AS table_name,
         EXISTS (SELECT 1 FROM pg_trigger t2
                  WHERE t2.tgrelid = c.oid AND NOT t2.tgisinternal AND (t2.tgtype & 32) > 0) AS truncate_guarded
    FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname = 'public' AND c.relkind = 'r'
     AND EXISTS (SELECT 1 FROM pg_trigger t JOIN pg_proc p ON p.oid = t.tgfoid
                  WHERE t.tgrelid = c.oid AND NOT t.tgisinternal
                    AND (p.prosrc ILIKE '%append-only%' OR p.prosrc ILIKE '%immutable%'
                         OR t.tgname ILIKE '%append%' OR t.tgname ILIKE '%immutable%'
                         OR t.tgname ILIKE '%guard%'));

COMMIT;
