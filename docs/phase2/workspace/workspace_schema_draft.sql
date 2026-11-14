-- WORKSPACE DATABASE — CORE DOMAIN SKELETON (PostgreSQL 15+)
-- DRAFT ONLY. Not a production migration. Synthetic data only (D-014).
-- One database/credential boundary per Workspace. No global constraints are claimed.
BEGIN;

CREATE TABLE workspace_profile (
  singleton boolean PRIMARY KEY DEFAULT true CHECK (singleton),
  workspace_id uuid NOT NULL UNIQUE,
  workspace_type text NOT NULL CHECK (workspace_type IN ('organization','independent_counselor')),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE workspace_memberships (
  membership_id uuid PRIMARY KEY,
  platform_user_id uuid NOT NULL,
  status text NOT NULL CHECK (status IN ('invited','active','suspended','ended')),
  granted_at timestamptz NOT NULL DEFAULT now(),
  ended_at timestamptz,
  UNIQUE (platform_user_id),
  CHECK ((status='ended') = (ended_at IS NOT NULL))
);

-- Canonical source of Workspace role assignments. Do not duplicate a role on workspace_memberships.
CREATE TABLE membership_roles (
  membership_id uuid NOT NULL REFERENCES workspace_memberships(membership_id),
  role_key text NOT NULL,
  granted_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (membership_id, role_key)
);

CREATE TABLE membership_permissions (
  membership_id uuid NOT NULL REFERENCES workspace_memberships(membership_id),
  permission_key text NOT NULL,
  resource_scope jsonb NOT NULL DEFAULT '{}'::jsonb,
  granted_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (membership_id, permission_key)
);

CREATE TABLE branches (
  branch_id uuid PRIMARY KEY,
  name text NOT NULL,
  status text NOT NULL CHECK (status IN ('active','archived')),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE FUNCTION reject_branch_for_independent_workspace() RETURNS trigger LANGUAGE plpgsql AS $body$
DECLARE wt text;
BEGIN
  SELECT workspace_type INTO wt FROM workspace_profile WHERE singleton=true;
  IF NOT FOUND THEN RAISE EXCEPTION 'workspace profile must exist before branch creation' USING ERRCODE='foreign_key_violation'; END IF;
  IF wt='independent_counselor' THEN
    RAISE EXCEPTION 'Independent Counselor Workspace cannot contain branches' USING ERRCODE='check_violation';
  END IF;
  RETURN NEW;
END; $body$;
CREATE TRIGGER branches_workspace_type_guard
  BEFORE INSERT OR UPDATE ON branches
  FOR EACH ROW EXECUTE FUNCTION reject_branch_for_independent_workspace();


CREATE FUNCTION guard_workspace_type_change() RETURNS trigger LANGUAGE plpgsql AS $body$
BEGIN
  IF NEW.workspace_type IS DISTINCT FROM OLD.workspace_type
     AND EXISTS (SELECT 1 FROM branches) THEN
    RAISE EXCEPTION 'Workspace type cannot change while branch records exist' USING ERRCODE='check_violation';
  END IF;
  RETURN NEW;
END; $body$;
CREATE TRIGGER workspace_type_change_guard
  BEFORE UPDATE OF workspace_type ON workspace_profile
  FOR EACH ROW EXECUTE FUNCTION guard_workspace_type_change();

CREATE TABLE students (
  student_id uuid PRIMARY KEY,
  platform_student_id uuid NOT NULL UNIQUE,
  display_name text NOT NULL,
  grade_key text NOT NULL CHECK (grade_key IN ('grade_10','grade_11','grade_12')),
  lifecycle_state text NOT NULL CHECK (lifecycle_state IN ('active','archived')),
  created_at timestamptz NOT NULL DEFAULT now(),
  archived_at timestamptz,
  CHECK ((lifecycle_state='archived') = (archived_at IS NOT NULL))
);

CREATE FUNCTION guard_student_primary_key_mutation() RETURNS trigger LANGUAGE plpgsql AS $body$
BEGIN
  IF NEW.student_id IS DISTINCT FROM OLD.student_id THEN
    RAISE EXCEPTION 'student_id is immutable' USING ERRCODE='check_violation';
  END IF;
  RETURN NEW;
END; $body$;
CREATE TRIGGER students_primary_key_immutable
  BEFORE UPDATE OF student_id ON students
  FOR EACH ROW EXECUTE FUNCTION guard_student_primary_key_mutation();

-- This is a local projection only; Control Plane remains global ownership authority.
CREATE TABLE enrollments (
  enrollment_id uuid PRIMARY KEY,
  student_id uuid NOT NULL REFERENCES students(student_id),
  ownership_generation bigint NOT NULL CHECK (ownership_generation >= 1),
  state text NOT NULL CHECK (state IN ('requested','awaiting_consent','active','suspended','ended','archived')),
  started_at timestamptz,
  ended_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK ((state IN ('ended','archived')) = (ended_at IS NOT NULL))
);
CREATE UNIQUE INDEX one_active_local_enrollment_per_student
  ON enrollments(student_id) WHERE state IN ('active','suspended','awaiting_consent');

CREATE TABLE counselor_assignments (
  assignment_id uuid PRIMARY KEY,
  enrollment_id uuid NOT NULL REFERENCES enrollments(enrollment_id),
  counselor_membership_id uuid NOT NULL REFERENCES workspace_memberships(membership_id),
  branch_id uuid REFERENCES branches(branch_id),
  is_responsible boolean NOT NULL DEFAULT false,
  is_primary_branch boolean NOT NULL DEFAULT false,
  state text NOT NULL CHECK (state IN ('active','ended')),
  accepted_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  ended_at timestamptz,
  CHECK ((state='ended') = (ended_at IS NOT NULL)),
  CHECK (NOT is_primary_branch OR branch_id IS NOT NULL)
);
CREATE UNIQUE INDEX one_responsible_counselor_per_enrollment
  ON counselor_assignments(enrollment_id) WHERE state='active' AND is_responsible;
CREATE UNIQUE INDEX one_primary_branch_per_enrollment
  ON counselor_assignments(enrollment_id) WHERE state='active' AND is_primary_branch;

CREATE TABLE student_guardian_links (
  link_id uuid PRIMARY KEY,
  student_id uuid NOT NULL REFERENCES students(student_id),
  guardian_platform_user_id uuid NOT NULL,
  relationship_type text NOT NULL,
  verification_state text NOT NULL CHECK (verification_state IN ('unverified','verified','revoked')),
  legal_authority_ref text,
  verified_at timestamptz,
  revoked_at timestamptz,
  UNIQUE(student_id, guardian_platform_user_id),
  CHECK (verification_state <> 'verified' OR (verified_at IS NOT NULL AND legal_authority_ref IS NOT NULL)),
  CHECK ((verification_state = 'revoked') = (revoked_at IS NOT NULL))          -- WS-DOM-03
);

CREATE TABLE guardian_permissions (
  permission_id uuid PRIMARY KEY,
  guardian_link_id uuid NOT NULL REFERENCES student_guardian_links(link_id),
  scope_key text NOT NULL,
  granted_by_membership_id uuid REFERENCES workspace_memberships(membership_id),
  authority_ref text NOT NULL,
  valid_from timestamptz NOT NULL,
  valid_until timestamptz,
  revoked_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (valid_until IS NULL OR valid_until > valid_from)
);
CREATE INDEX guardian_permissions_active_lookup
  ON guardian_permissions(guardian_link_id, scope_key, valid_from, valid_until)
  WHERE revoked_at IS NULL;

-- WS-DOM-03: append-only history. The two tables above are projections; every state change of a projection
-- must be accompanied, in the SAME transaction, by an event row carrying actor, authentication-event and
-- evidence references and the policy version. References are opaque: the database does not verify identity or
-- legal authority (Phase 4 / Q-007). No age/legal matrix is encoded here.
CREATE TABLE guardian_link_events (
  event_id uuid PRIMARY KEY,
  link_id uuid NOT NULL REFERENCES student_guardian_links(link_id),
  event_type text NOT NULL CHECK (event_type IN ('link_created','verified','revoked')),
  actor_ref text NOT NULL CHECK (length(btrim(actor_ref))>0),
  authn_event_ref text NOT NULL CHECK (length(btrim(authn_event_ref))>0),
  evidence_ref text,
  policy_version text NOT NULL CHECK (length(btrim(policy_version))>0),
  effective_at timestamptz NOT NULL,
  recorded_at timestamptz NOT NULL DEFAULT now(),
  txid bigint NOT NULL DEFAULT txid_current(),
  CHECK (event_type <> 'verified' OR (evidence_ref IS NOT NULL AND length(btrim(evidence_ref))>0))
);
CREATE TABLE guardian_permission_events (
  event_id uuid PRIMARY KEY,
  permission_id uuid NOT NULL REFERENCES guardian_permissions(permission_id),
  event_type text NOT NULL CHECK (event_type IN ('granted','revoked')),
  actor_ref text NOT NULL CHECK (length(btrim(actor_ref))>0),
  authn_event_ref text NOT NULL CHECK (length(btrim(authn_event_ref))>0),
  authority_ref text NOT NULL CHECK (length(btrim(authority_ref))>0),
  policy_version text NOT NULL CHECK (length(btrim(policy_version))>0),
  effective_from timestamptz NOT NULL,
  effective_until timestamptz,
  recorded_at timestamptz NOT NULL DEFAULT now(),
  txid bigint NOT NULL DEFAULT txid_current(),
  CHECK (effective_until IS NULL OR effective_until > effective_from)
);
CREATE FUNCTION guardian_events_append_only() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP='INSERT' THEN
    IF NEW.txid IS DISTINCT FROM txid_current() THEN
      RAISE EXCEPTION 'guardian event txid must be the current transaction' USING ERRCODE='check_violation';
    END IF;
    RETURN NEW;
  END IF;
  RAISE EXCEPTION '% is append-only', TG_TABLE_NAME USING ERRCODE='check_violation';
END; $$;
CREATE TRIGGER guardian_link_events_guard BEFORE INSERT OR UPDATE OR DELETE ON guardian_link_events
  FOR EACH ROW EXECUTE FUNCTION guardian_events_append_only();
CREATE TRIGGER guardian_permission_events_guard BEFORE INSERT OR UPDATE OR DELETE ON guardian_permission_events
  FOR EACH ROW EXECUTE FUNCTION guardian_events_append_only();

-- Projection rules (row level).
CREATE FUNCTION guardian_link_guard() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP='DELETE' THEN
    RAISE EXCEPTION 'guardian links are never deleted; revoke instead' USING ERRCODE='check_violation';
  END IF;
  IF (NEW.link_id,NEW.student_id,NEW.guardian_platform_user_id) IS DISTINCT FROM (OLD.link_id,OLD.student_id,OLD.guardian_platform_user_id) THEN
    RAISE EXCEPTION 'guardian link identity is immutable' USING ERRCODE='check_violation';
  END IF;
  IF OLD.verification_state='revoked' THEN
    RAISE EXCEPTION 'a revoked guardian link is terminal; a new verification needs a new link decision' USING ERRCODE='check_violation';
  END IF;
  IF NOT ((OLD.verification_state,NEW.verification_state) IN (('unverified','unverified'),('unverified','verified'),
          ('unverified','revoked'),('verified','verified'),('verified','revoked'))) THEN
    RAISE EXCEPTION 'illegal guardian link transition % -> %', OLD.verification_state, NEW.verification_state USING ERRCODE='check_violation';
  END IF;
  RETURN NEW;
END; $$;
CREATE TRIGGER student_guardian_links_guard BEFORE UPDATE OR DELETE ON student_guardian_links
  FOR EACH ROW EXECUTE FUNCTION guardian_link_guard();

CREATE FUNCTION guardian_permission_guard() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE st text;
BEGIN
  IF TG_OP='DELETE' THEN
    RAISE EXCEPTION 'guardian permissions are never deleted; revoke instead' USING ERRCODE='check_violation';
  END IF;
  IF TG_OP='INSERT' THEN
    SELECT verification_state INTO st FROM student_guardian_links WHERE link_id=NEW.guardian_link_id FOR SHARE;
    IF st IS DISTINCT FROM 'verified' THEN
      RAISE EXCEPTION 'a permission requires a currently verified guardian link (state %)', COALESCE(st,'missing') USING ERRCODE='check_violation';
    END IF;
    IF NEW.revoked_at IS NOT NULL THEN
      RAISE EXCEPTION 'a permission cannot be created already revoked' USING ERRCODE='check_violation';
    END IF;
    RETURN NEW;
  END IF;
  -- UPDATE: the only permitted change is a single revocation.
  IF (NEW.permission_id,NEW.guardian_link_id,NEW.scope_key,NEW.granted_by_membership_id,NEW.authority_ref,NEW.valid_from,NEW.valid_until,NEW.created_at)
     IS DISTINCT FROM
     (OLD.permission_id,OLD.guardian_link_id,OLD.scope_key,OLD.granted_by_membership_id,OLD.authority_ref,OLD.valid_from,OLD.valid_until,OLD.created_at)
     OR OLD.revoked_at IS NOT NULL OR NEW.revoked_at IS NULL THEN
    RAISE EXCEPTION 'a guardian permission is immutable except for one revocation' USING ERRCODE='check_violation';
  END IF;
  RETURN NEW;
END; $$;
CREATE TRIGGER guardian_permissions_guard BEFORE INSERT OR UPDATE OR DELETE ON guardian_permissions
  FOR EACH ROW EXECUTE FUNCTION guardian_permission_guard();

-- Commit-time rule: no projection state change without its event in the same transaction.
CREATE FUNCTION guardian_link_requires_event() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE want text;
BEGIN
  IF TG_OP='INSERT' THEN
    -- A link may be inserted already verified (import of a verified decision): then both events are required.
    IF NOT EXISTS (SELECT 1 FROM guardian_link_events e WHERE e.link_id=NEW.link_id AND e.event_type='link_created' AND e.txid=txid_current()) THEN
      RAISE EXCEPTION 'guardian link % has no link_created event in this transaction', NEW.link_id USING ERRCODE='check_violation';
    END IF;
    want := CASE WHEN NEW.verification_state='unverified' THEN NULL ELSE NEW.verification_state END;
  ELSE
    want := CASE WHEN NEW.verification_state IS DISTINCT FROM OLD.verification_state THEN NEW.verification_state END;
  END IF;
  IF want IS NOT NULL AND NOT EXISTS (SELECT 1 FROM guardian_link_events e
       WHERE e.link_id=NEW.link_id AND e.event_type=want AND e.txid=txid_current()) THEN
    RAISE EXCEPTION 'guardian link % changed to % without a % event in this transaction', NEW.link_id, want, want USING ERRCODE='check_violation';
  END IF;
  RETURN NULL;
END; $$;
CREATE CONSTRAINT TRIGGER student_guardian_links_require_event AFTER INSERT OR UPDATE ON student_guardian_links
  DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION guardian_link_requires_event();

CREATE FUNCTION guardian_permission_requires_event() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE want text := CASE WHEN TG_OP='INSERT' THEN 'granted' ELSE 'revoked' END;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM guardian_permission_events e
       WHERE e.permission_id=NEW.permission_id AND e.event_type=want AND e.txid=txid_current()) THEN
    RAISE EXCEPTION 'guardian permission % has no % event in this transaction', NEW.permission_id, want USING ERRCODE='check_violation';
  END IF;
  RETURN NULL;
END; $$;
CREATE CONSTRAINT TRIGGER guardian_permissions_require_event AFTER INSERT OR UPDATE ON guardian_permissions
  DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION guardian_permission_requires_event();

-- A stored permission is effective only while its link is verified and the time window is open.
-- This view is the ONLY read shape that may be used for a guardian access decision inside the Workspace DB;
-- the service must still revalidate identity and legal authority at use (Phase 4, Q-007).
CREATE VIEW guardian_permissions_effective AS
  SELECT p.permission_id, p.guardian_link_id, l.student_id, l.guardian_platform_user_id, p.scope_key, p.valid_from, p.valid_until
    FROM guardian_permissions p JOIN student_guardian_links l ON l.link_id=p.guardian_link_id
   WHERE p.revoked_at IS NULL AND l.verification_state='verified'
     AND p.valid_from <= now() AND (p.valid_until IS NULL OR p.valid_until > now());

CREATE TABLE program_templates (
  template_id uuid PRIMARY KEY,
  name text NOT NULL,
  status text NOT NULL CHECK (status IN ('draft','published','archived')),
  created_by_membership_id uuid REFERENCES workspace_memberships(membership_id),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE program_versions (
  program_version_id uuid PRIMARY KEY,
  template_id uuid NOT NULL REFERENCES program_templates(template_id),
  version_no integer NOT NULL CHECK (version_no > 0),
  content jsonb NOT NULL,
  status text NOT NULL CHECK (status IN ('draft','published')),
  created_by_membership_id uuid REFERENCES workspace_memberships(membership_id),
  created_at timestamptz NOT NULL DEFAULT now(),
  published_at timestamptz,
  UNIQUE(template_id, version_no),
  CHECK ((status='published') = (published_at IS NOT NULL))
);

CREATE FUNCTION reject_published_version_mutation() RETURNS trigger LANGUAGE plpgsql AS $body$
BEGIN
  IF OLD.status='published' THEN
    RAISE EXCEPTION 'published versions are immutable; create a new version' USING ERRCODE='check_violation';
  END IF;
  IF TG_OP='DELETE' THEN RETURN OLD; END IF;
  RETURN NEW;
END; $body$;
CREATE TRIGGER program_versions_immutable
  BEFORE UPDATE OR DELETE ON program_versions
  FOR EACH ROW EXECUTE FUNCTION reject_published_version_mutation();

CREATE TABLE student_plans (
  plan_id uuid PRIMARY KEY,
  student_id uuid NOT NULL REFERENCES students(student_id),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE student_plan_versions (
  plan_version_id uuid PRIMARY KEY,
  plan_id uuid NOT NULL REFERENCES student_plans(plan_id),
  version_no integer NOT NULL CHECK (version_no > 0),
  source_program_version_id uuid REFERENCES program_versions(program_version_id),
  input_snapshot jsonb NOT NULL,
  rule_version text NOT NULL,
  plan_content jsonb NOT NULL,
  status text NOT NULL CHECK (status IN ('draft','published')),
  approved_by_membership_id uuid REFERENCES workspace_memberships(membership_id),
  created_at timestamptz NOT NULL DEFAULT now(),
  published_at timestamptz,
  UNIQUE(plan_id, version_no),
  CHECK ((status='published') = (published_at IS NOT NULL))
);

CREATE TRIGGER student_plan_versions_immutable
  BEFORE UPDATE OR DELETE ON student_plan_versions
  FOR EACH ROW EXECUTE FUNCTION reject_published_version_mutation();

-- Educational domain: reference curriculum, student mastery, execution and analysis.
CREATE TABLE subjects (
  subject_id uuid PRIMARY KEY,
  subject_key text NOT NULL UNIQUE,
  title text NOT NULL,
  grade_key text NOT NULL CHECK (grade_key IN ('grade_10','grade_11','grade_12')),
  source_kind text NOT NULL CHECK (source_kind IN ('platform_reference','workspace_custom')),
  source_ref text,
  status text NOT NULL CHECK (status IN ('active','archived')),
  CHECK ((source_kind='platform_reference') = (source_ref IS NOT NULL))
);
CREATE TABLE chapters (
  chapter_id uuid PRIMARY KEY,
  subject_id uuid NOT NULL REFERENCES subjects(subject_id),
  title text NOT NULL,
  order_no integer NOT NULL CHECK (order_no>0),
  UNIQUE(subject_id,order_no)
);
CREATE TABLE topics (
  topic_id uuid PRIMARY KEY,
  chapter_id uuid NOT NULL REFERENCES chapters(chapter_id),
  title text NOT NULL,
  order_no integer NOT NULL CHECK (order_no>0),
  UNIQUE(chapter_id,order_no)
);
CREATE TABLE student_topic_mastery (
  student_id uuid NOT NULL REFERENCES students(student_id),
  topic_id uuid NOT NULL REFERENCES topics(topic_id),
  mastery_score numeric(5,2) NOT NULL CHECK (mastery_score BETWEEN 0 AND 100),
  confidence text NOT NULL CHECK (confidence IN ('low','medium','high')),
  last_assessed_at timestamptz,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(student_id,topic_id)
);

CREATE TABLE activities (
  activity_id uuid PRIMARY KEY,
  student_id uuid NOT NULL REFERENCES students(student_id),
  topic_id uuid REFERENCES topics(topic_id),
  activity_kind text NOT NULL CHECK (activity_kind IN ('study','homework','review','test','exam','class_followup','custom')),
  title text NOT NULL,
  description text,
  due_at timestamptz,
  priority smallint NOT NULL DEFAULT 3 CHECK (priority BETWEEN 1 AND 5),
  state text NOT NULL CHECK (state IN ('planned','in_progress','completed','overdue','cancelled')),
  created_by_membership_id uuid REFERENCES workspace_memberships(membership_id),
  created_at timestamptz NOT NULL DEFAULT now(),
  completed_at timestamptz
);
CREATE INDEX activities_student_due_idx ON activities(student_id,due_at) WHERE state IN ('planned','in_progress','overdue');

CREATE TABLE study_sessions (
  study_session_id uuid PRIMARY KEY,
  student_id uuid NOT NULL REFERENCES students(student_id),
  activity_id uuid REFERENCES activities(activity_id),
  started_at timestamptz NOT NULL,
  ended_at timestamptz,
  planned_minutes integer CHECK (planned_minutes IS NULL OR planned_minutes>0),
  actual_minutes integer CHECK (actual_minutes IS NULL OR actual_minutes>=0),
  outcome text CHECK (outcome IN ('completed','partial','interrupted')),
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (ended_at IS NULL OR ended_at>=started_at)
);

CREATE TABLE test_definitions (
  test_id uuid PRIMARY KEY,
  title text NOT NULL,
  subject_id uuid NOT NULL REFERENCES subjects(subject_id),
  topic_id uuid REFERENCES topics(topic_id),
  test_kind text NOT NULL CHECK (test_kind IN ('educational','mastery','exam_simulation')),
  time_limit_seconds integer CHECK (time_limit_seconds IS NULL OR time_limit_seconds>0),
  negative_marking boolean NOT NULL DEFAULT true,
  scoring_policy_snapshot jsonb NOT NULL,
  created_by_membership_id uuid REFERENCES workspace_memberships(membership_id),
  created_at timestamptz NOT NULL DEFAULT now()
);
-- WS-DOM-01: immutable published definition version; attempts bind to exactly one version.
-- delivery_mode: 'fixed' => attempt.question_count must equal the version's question_count;
-- 'per_attempt' => the attempt carries its own delivered count (adaptive delivery is NOT approved for MVP;
-- the value exists so the schema does not preclude it; see PHASE2_OPEN_DECISIONS "Assessment semantics").
CREATE TABLE test_definition_versions (
  version_id uuid PRIMARY KEY,
  test_id uuid NOT NULL REFERENCES test_definitions(test_id),
  version_no integer NOT NULL CHECK (version_no>0),
  status text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','published')),
  delivery_mode text NOT NULL DEFAULT 'fixed' CHECK (delivery_mode IN ('fixed','per_attempt')),
  question_count integer NOT NULL CHECK (question_count>0),
  time_limit_seconds integer CHECK (time_limit_seconds IS NULL OR time_limit_seconds>0),
  scoring_policy_snapshot jsonb NOT NULL CHECK (jsonb_typeof(scoring_policy_snapshot)='object'),
  published_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(test_id, version_no),
  UNIQUE(version_id, test_id),
  CHECK ((status='published') = (published_at IS NOT NULL))
);
-- PD-2026-11-13-A: a published version carries its exact question membership AND order.
-- question_count is only a consistency check; these rows are the authoritative membership list.
-- item_ref is the stable identifier of the question in the counselor's own item source; the item bank
-- itself is NOT modelled in Phase 2 and no item-bank ownership rule is decided here.
CREATE TABLE test_definition_version_questions (
  version_question_id uuid PRIMARY KEY,
  version_id uuid NOT NULL REFERENCES test_definition_versions(version_id),
  question_no integer NOT NULL CHECK (question_no>0),
  item_ref text NOT NULL CHECK (length(btrim(item_ref))>0),
  topic_id uuid REFERENCES topics(topic_id),      -- authoritative topic of the question (responses do not carry their own)
  UNIQUE (version_id, question_no),               -- unique order within the version
  UNIQUE (version_id, item_ref),                  -- unique membership within the version
  UNIQUE (version_question_id, version_id),
  UNIQUE (version_question_id, version_id, question_no)   -- FK target for responses
);
CREATE INDEX test_definition_version_questions_version_idx ON test_definition_version_questions(version_id, question_no);

CREATE FUNCTION test_definition_version_guard() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE n_q integer; n_min integer; n_max integer;
BEGIN
  IF TG_OP='INSERT' THEN
    IF NEW.status<>'draft' THEN
      RAISE EXCEPTION 'a definition version must be created as draft' USING ERRCODE='check_violation';
    END IF;
    RETURN NEW;
  END IF;
  IF OLD.status='published' THEN
    RAISE EXCEPTION 'published test definition version is immutable' USING ERRCODE='check_violation';
  END IF;
  IF TG_OP='DELETE' THEN RETURN OLD; END IF;
  IF (NEW.version_id,NEW.test_id,NEW.version_no) IS DISTINCT FROM (OLD.version_id,OLD.test_id,OLD.version_no) THEN
    RAISE EXCEPTION 'definition version identity is immutable' USING ERRCODE='check_violation';
  END IF;
  IF NEW.status='published' THEN
    -- MVP gate (PD-2026-11-13-A): per-attempt/adaptive delivery is NOT approved. Fail closed; the column
    -- stays as a reserved extension point and must not be read as permission to deliver variable sets.
    IF NEW.delivery_mode<>'fixed' THEN
      RAISE EXCEPTION 'delivery_mode % cannot be published: per-attempt delivery requires a separate Product Owner decision', NEW.delivery_mode
        USING ERRCODE='check_violation';
    END IF;
    SELECT count(*), COALESCE(min(question_no),0), COALESCE(max(question_no),0) INTO n_q, n_min, n_max
      FROM public.test_definition_version_questions WHERE version_id=NEW.version_id;
    IF n_q<>NEW.question_count THEN
      RAISE EXCEPTION 'version has % question rows but question_count is %; membership is the authority', n_q, NEW.question_count
        USING ERRCODE='check_violation';
    END IF;
    IF n_q=0 OR n_min<>1 OR n_max<>n_q THEN
      RAISE EXCEPTION 'published question order must be exactly 1..% (found min %, max %)', n_q, n_min, n_max
        USING ERRCODE='check_violation';
    END IF;
  END IF;
  RETURN NEW;
END; $$;
CREATE TRIGGER test_definition_versions_guard BEFORE INSERT OR UPDATE OR DELETE ON test_definition_versions
  FOR EACH ROW EXECUTE FUNCTION test_definition_version_guard();

-- Membership/order may change only while the owning version is a draft. The check is role-independent:
-- it binds every writer, including the runtime role, not only the command functions.
-- FOR SHARE on the version row serialises against a concurrent publish.
CREATE FUNCTION test_definition_version_question_guard() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_status text; v_id uuid;
BEGIN
  IF TG_OP='UPDATE' AND NEW.version_id IS DISTINCT FROM OLD.version_id THEN
    RAISE EXCEPTION 'a version question cannot be moved to another version' USING ERRCODE='check_violation';
  END IF;
  IF TG_OP='UPDATE' AND NEW.version_question_id IS DISTINCT FROM OLD.version_question_id THEN
    RAISE EXCEPTION 'version_question_id is immutable' USING ERRCODE='check_violation';
  END IF;
  v_id := CASE WHEN TG_OP='DELETE' THEN OLD.version_id ELSE NEW.version_id END;
  SELECT status INTO v_status FROM public.test_definition_versions WHERE version_id=v_id FOR SHARE;
  IF v_status IS DISTINCT FROM 'draft' THEN
    RAISE EXCEPTION 'question membership/order of a % definition version is immutable', COALESCE(v_status,'missing')
      USING ERRCODE='check_violation';
  END IF;
  RETURN CASE WHEN TG_OP='DELETE' THEN OLD ELSE NEW END;
END; $$;
CREATE TRIGGER test_definition_version_questions_guard BEFORE INSERT OR UPDATE OR DELETE ON test_definition_version_questions
  FOR EACH ROW EXECUTE FUNCTION test_definition_version_question_guard();

CREATE TABLE test_attempts (
  attempt_id uuid PRIMARY KEY,
  test_id uuid NOT NULL REFERENCES test_definitions(test_id),
  definition_version_id uuid NOT NULL,
  student_id uuid NOT NULL REFERENCES students(student_id),
  state text NOT NULL DEFAULT 'started' CHECK (state IN ('started','submitted','analysed','cancelled')),
  started_at timestamptz NOT NULL,
  submitted_at timestamptz,
  question_count integer NOT NULL CHECK (question_count>0),   -- authoritative denominator for this attempt
  correct_count integer NOT NULL DEFAULT 0 CHECK (correct_count>=0),
  wrong_count integer NOT NULL DEFAULT 0 CHECK (wrong_count>=0),
  blank_count integer NOT NULL DEFAULT 0 CHECK (blank_count>=0),
  score numeric(7,3),                                          -- computed by the service; NOT validated by the database
  scoring_policy_snapshot jsonb NOT NULL CHECK (jsonb_typeof(scoring_policy_snapshot)='object'),
  submission_idempotency_key text,
  submission_payload_hash bytea CHECK (submission_payload_hash IS NULL OR octet_length(submission_payload_hash)=32),
  FOREIGN KEY (definition_version_id, test_id) REFERENCES test_definition_versions(version_id, test_id),
  UNIQUE (attempt_id, definition_version_id),   -- FK target: a response can only cite its own attempt's version
  UNIQUE (attempt_id, student_id),              -- FK target: an Activity cites a source of its OWN student
  UNIQUE (submission_idempotency_key),
  CHECK ((state IN ('submitted','analysed')) = (submitted_at IS NOT NULL)),
  CHECK (state NOT IN ('submitted','analysed') OR (
         correct_count + wrong_count + blank_count = question_count
         AND score IS NOT NULL
         AND submission_idempotency_key IS NOT NULL AND length(btrim(submission_idempotency_key))>0
         AND submission_payload_hash IS NOT NULL)),
  CHECK (state IN ('submitted','analysed') OR (
         correct_count=0 AND wrong_count=0 AND blank_count=0 AND score IS NULL
         AND submission_idempotency_key IS NULL AND submission_payload_hash IS NULL))
);
-- A response names the exact question of the exact version the attempt was started on. The two composite
-- foreign keys make cross-version substitution impossible declaratively, without a trigger:
--   (attempt_id, definition_version_id)                -> the attempt's own version
--   (version_question_id, definition_version_id, no)   -> a question of that same version, at its own order
-- Field ownership: topic belongs to test_definition_version_questions, not to the response.
CREATE TABLE test_responses (
  response_id uuid PRIMARY KEY,
  attempt_id uuid NOT NULL REFERENCES test_attempts(attempt_id),
  definition_version_id uuid NOT NULL,
  version_question_id uuid NOT NULL,
  question_no integer NOT NULL CHECK (question_no>0),
  response_state text NOT NULL CHECK (response_state IN ('correct','wrong','blank')),
  time_spent_seconds integer CHECK (time_spent_seconds IS NULL OR time_spent_seconds>=0),
  error_reason text CHECK (error_reason IN ('concept','memory','careless','time','strategy','unknown','custom')),
  custom_error_reason text,
  FOREIGN KEY (attempt_id, definition_version_id) REFERENCES test_attempts(attempt_id, definition_version_id),
  FOREIGN KEY (version_question_id, definition_version_id, question_no)
    REFERENCES test_definition_version_questions(version_question_id, version_id, question_no),
  UNIQUE(attempt_id,version_question_id),
  UNIQUE(attempt_id,question_no),
  -- A custom reason needs a non-empty description; a description is only allowed for a custom reason (NULL-safe).
  CHECK ((error_reason IS NOT DISTINCT FROM 'custom') = (custom_error_reason IS NOT NULL AND length(btrim(custom_error_reason))>0))
);

-- Attempt lifecycle. The submission invariant is checked by the trigger itself against the stored responses,
-- so it holds for ANY writer (it does not depend on which function or role performs the UPDATE).
CREATE FUNCTION test_attempt_guard() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v record; n_total integer; n_c integer; n_w integer; n_b integer; n_max integer;
BEGIN
  IF TG_OP='INSERT' THEN
    IF NEW.state<>'started' THEN
      RAISE EXCEPTION 'a test attempt must be created in state started' USING ERRCODE='check_violation';
    END IF;
    SELECT status, delivery_mode, question_count, scoring_policy_snapshot INTO v
      FROM test_definition_versions WHERE version_id=NEW.definition_version_id FOR SHARE;
    IF v.status IS DISTINCT FROM 'published' THEN
      RAISE EXCEPTION 'an attempt requires a published definition version' USING ERRCODE='check_violation';
    END IF;
    IF v.delivery_mode='fixed' AND NEW.question_count<>v.question_count THEN
      RAISE EXCEPTION 'attempt question_count % differs from fixed definition version count %', NEW.question_count, v.question_count
        USING ERRCODE='check_violation';
    END IF;
    -- PD-2026-11-13-A: the scoring policy is derived from the published version, never from caller-supplied
    -- attempt data. The database stores and compares the snapshot; it does not compute or validate a score.
    IF NEW.scoring_policy_snapshot IS DISTINCT FROM v.scoring_policy_snapshot THEN
      RAISE EXCEPTION 'attempt scoring policy snapshot differs from the published version policy'
        USING ERRCODE='check_violation';
    END IF;
    RETURN NEW;
  END IF;
  IF TG_OP='DELETE' THEN
    IF OLD.state IN ('submitted','analysed') THEN
      RAISE EXCEPTION 'a submitted test attempt cannot be deleted' USING ERRCODE='check_violation';
    END IF;
    RETURN OLD;
  END IF;
  IF (NEW.attempt_id,NEW.test_id,NEW.definition_version_id,NEW.student_id,NEW.question_count,NEW.started_at,NEW.scoring_policy_snapshot)
     IS DISTINCT FROM
     (OLD.attempt_id,OLD.test_id,OLD.definition_version_id,OLD.student_id,OLD.question_count,OLD.started_at,OLD.scoring_policy_snapshot) THEN
    RAISE EXCEPTION 'test attempt identity, denominator and scoring snapshot are immutable' USING ERRCODE='check_violation';
  END IF;
  IF OLD.state='started' AND NEW.state IN ('started','cancelled') THEN
    RETURN NEW;   -- table CHECK keeps counters at zero and score NULL
  ELSIF OLD.state='started' AND NEW.state='submitted' THEN
    SELECT count(*), count(*) FILTER (WHERE response_state='correct'), count(*) FILTER (WHERE response_state='wrong'),
           count(*) FILTER (WHERE response_state='blank'), COALESCE(max(question_no),0)
      INTO n_total, n_c, n_w, n_b, n_max FROM test_responses WHERE attempt_id=NEW.attempt_id;
    IF n_total<>NEW.question_count OR n_max<>NEW.question_count THEN
      RAISE EXCEPTION 'submission rejected: % responses for % delivered questions (highest question_no %)', n_total, NEW.question_count, n_max
        USING ERRCODE='check_violation';
    END IF;
    IF (NEW.correct_count,NEW.wrong_count,NEW.blank_count) IS DISTINCT FROM (n_c,n_w,n_b) THEN
      RAISE EXCEPTION 'submission rejected: counters (%,%,%) differ from responses (%,%,%)',
        NEW.correct_count,NEW.wrong_count,NEW.blank_count,n_c,n_w,n_b USING ERRCODE='check_violation';
    END IF;
    RETURN NEW;
  ELSIF OLD.state='submitted' AND NEW.state='analysed' THEN
    IF (NEW.submitted_at,NEW.correct_count,NEW.wrong_count,NEW.blank_count,NEW.score,NEW.submission_idempotency_key,NEW.submission_payload_hash)
       IS DISTINCT FROM
       (OLD.submitted_at,OLD.correct_count,OLD.wrong_count,OLD.blank_count,OLD.score,OLD.submission_idempotency_key,OLD.submission_payload_hash) THEN
      RAISE EXCEPTION 'analysis must not rewrite the submitted attempt' USING ERRCODE='check_violation';
    END IF;
    RETURN NEW;
  END IF;
  RAISE EXCEPTION 'illegal test attempt change % -> % (submitted attempts are immutable)', OLD.state, NEW.state USING ERRCODE='check_violation';
END; $$;
CREATE TRIGGER test_attempts_guard BEFORE INSERT OR UPDATE OR DELETE ON test_attempts
  FOR EACH ROW EXECUTE FUNCTION test_attempt_guard();

-- Responses can change only while the attempt is started. FOR SHARE on the attempt serialises against a concurrent submission.
CREATE FUNCTION test_response_guard() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE st text; qc integer; aid uuid;
BEGIN
  aid := CASE WHEN TG_OP='DELETE' THEN OLD.attempt_id ELSE NEW.attempt_id END;
  IF TG_OP='UPDATE' AND NEW.attempt_id IS DISTINCT FROM OLD.attempt_id THEN
    RAISE EXCEPTION 'a response cannot move to another attempt' USING ERRCODE='check_violation';
  END IF;
  SELECT state, question_count INTO st, qc FROM test_attempts WHERE attempt_id=aid FOR SHARE;
  IF st IS DISTINCT FROM 'started' THEN
    RAISE EXCEPTION 'responses are immutable once the attempt is %', COALESCE(st,'missing') USING ERRCODE='check_violation';
  END IF;
  IF TG_OP<>'DELETE' AND NEW.question_no>qc THEN
    RAISE EXCEPTION 'question_no % is outside the % delivered questions', NEW.question_no, qc USING ERRCODE='check_violation';
  END IF;
  RETURN CASE WHEN TG_OP='DELETE' THEN OLD ELSE NEW END;
END; $$;
CREATE TRIGGER test_responses_guard BEFORE INSERT OR UPDATE OR DELETE ON test_responses
  FOR EACH ROW EXECUTE FUNCTION test_response_guard();

-- Atomic, idempotent submission. SECURITY INVOKER: it adds no privilege; the trigger above is the integrity boundary.
-- p_score is the service-computed score (formula per the approved policy snapshot; the database does not recompute it).
CREATE FUNCTION submit_test_attempt(p_attempt_id uuid, p_correct integer, p_wrong integer, p_blank integer,
  p_score numeric, p_idempotency_key text, p_payload_hash bytea) RETURNS text LANGUAGE plpgsql AS $$
DECLARE a test_attempts%ROWTYPE;
BEGIN
  SELECT * INTO a FROM test_attempts WHERE attempt_id=p_attempt_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'test attempt % not found', p_attempt_id USING ERRCODE='no_data_found'; END IF;
  IF a.state IN ('submitted','analysed') THEN
    IF a.submission_idempotency_key=p_idempotency_key AND a.submission_payload_hash IS NOT DISTINCT FROM p_payload_hash THEN
      RETURN 'replayed';
    END IF;
    RAISE EXCEPTION 'attempt already submitted; idempotency key or payload differs' USING ERRCODE='unique_violation';
  END IF;
  UPDATE test_attempts SET state='submitted', submitted_at=now(), correct_count=p_correct, wrong_count=p_wrong,
         blank_count=p_blank, score=p_score, submission_idempotency_key=p_idempotency_key, submission_payload_hash=p_payload_hash
   WHERE attempt_id=p_attempt_id;
  RETURN 'submitted';
END; $$;

CREATE TABLE exams (
  exam_id uuid PRIMARY KEY,
  student_id uuid NOT NULL REFERENCES students(student_id),
  title text NOT NULL,
  exam_at timestamptz NOT NULL,
  scoring_policy_snapshot jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(exam_id,student_id)
);
CREATE TABLE exam_results (
  exam_result_id uuid PRIMARY KEY,
  exam_id uuid NOT NULL REFERENCES exams(exam_id),
  student_id uuid NOT NULL REFERENCES students(student_id),
  correct_count integer NOT NULL CHECK (correct_count>=0),
  wrong_count integer NOT NULL CHECK (wrong_count>=0),
  blank_count integer NOT NULL CHECK (blank_count>=0),
  score numeric(7,3),
  scoring_policy_snapshot jsonb NOT NULL,
  UNIQUE(exam_id,student_id),
  FOREIGN KEY(exam_id,student_id) REFERENCES exams(exam_id,student_id)
);

CREATE TABLE classes (
  class_id uuid PRIMARY KEY,
  subject_id uuid REFERENCES subjects(subject_id),
  class_kind text NOT NULL CHECK (class_kind IN ('online','offline','onsite')),
  title text NOT NULL,
  instructor_label text,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE class_sessions (
  class_session_id uuid PRIMARY KEY,
  class_id uuid NOT NULL REFERENCES classes(class_id),
  starts_at timestamptz NOT NULL,
  ends_at timestamptz NOT NULL,
  timezone_name text NOT NULL,
  join_or_location_ref text,
  CHECK (ends_at>starts_at),
  UNIQUE (class_session_id, class_id)
);
-- Who takes part in a class, and in each of its sessions. These rows are what makes a class-follow-up
-- Activity referentially valid for a given student: a student who is not a participant of the session's
-- class cannot have an Activity pointing at that session.
CREATE TABLE class_participants (
  class_id uuid NOT NULL REFERENCES classes(class_id),
  student_id uuid NOT NULL REFERENCES students(student_id),
  state text NOT NULL CHECK (state IN ('enrolled','withdrawn')),
  enrolled_at timestamptz NOT NULL DEFAULT now(),
  withdrawn_at timestamptz,
  PRIMARY KEY (class_id, student_id),
  CHECK ((state='withdrawn') = (withdrawn_at IS NOT NULL))
);
CREATE TABLE class_session_participants (
  class_session_id uuid NOT NULL,
  class_id uuid NOT NULL,
  student_id uuid NOT NULL,
  attendance text NOT NULL CHECK (attendance IN ('expected','attended','absent','excused')),
  recorded_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (class_session_id, student_id),
  UNIQUE (class_session_id, student_id),
  FOREIGN KEY (class_session_id, class_id) REFERENCES class_sessions(class_session_id, class_id),
  FOREIGN KEY (class_id, student_id) REFERENCES class_participants(class_id, student_id)
);

CREATE TABLE assignments (
  assignment_id uuid PRIMARY KEY,
  student_id uuid NOT NULL REFERENCES students(student_id),
  class_session_id uuid REFERENCES class_sessions(class_session_id),
  title text NOT NULL,
  due_at timestamptz,
  state text NOT NULL CHECK (state IN ('assigned','in_progress','submitted','reviewed','overdue','cancelled')),
  created_by_membership_id uuid REFERENCES workspace_memberships(membership_id),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (assignment_id, student_id)
);
CREATE TABLE reviews (
  review_id uuid PRIMARY KEY,
  student_id uuid NOT NULL REFERENCES students(student_id),
  topic_id uuid REFERENCES topics(topic_id),
  scheduled_at timestamptz NOT NULL,
  cadence_days integer CHECK (cadence_days IS NULL OR cadence_days>0),
  state text NOT NULL CHECK (state IN ('scheduled','completed','missed','cancelled')),
  completed_at timestamptz,
  UNIQUE (review_id, student_id)
);
CREATE TABLE daily_routines (
  routine_id uuid PRIMARY KEY,
  student_id uuid NOT NULL REFERENCES students(student_id),
  title text NOT NULL,
  schedule_spec jsonb NOT NULL,
  timezone_name text NOT NULL,
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE progress_snapshots (
  progress_snapshot_id uuid PRIMARY KEY,
  student_id uuid NOT NULL REFERENCES students(student_id),
  snapshot_date date NOT NULL,
  metrics jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(student_id,snapshot_date)
);
CREATE TABLE risk_assessments (
  risk_assessment_id uuid PRIMARY KEY,
  student_id uuid NOT NULL REFERENCES students(student_id),
  risk_level text NOT NULL CHECK (risk_level IN ('low','medium','high','critical')),
  engine_version text NOT NULL,
  input_snapshot jsonb NOT NULL,
  explanation text NOT NULL,
  overridden_by_membership_id uuid REFERENCES workspace_memberships(membership_id),
  override_reason text,
  assessed_at timestamptz NOT NULL DEFAULT now(),
  CHECK ((overridden_by_membership_id IS NULL) = (override_reason IS NULL))
);
CREATE TABLE counselor_notes (
  counselor_note_id uuid PRIMARY KEY,
  student_id uuid NOT NULL REFERENCES students(student_id),
  author_membership_id uuid NOT NULL REFERENCES workspace_memberships(membership_id),
  visibility text NOT NULL CHECK (visibility IN ('private_to_author','workspace_scoped')),
  content text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  archived_at timestamptz
);

-- Workspace-local capacity counters; Cell-level limits remain Control Plane/platform concerns.
-- Activation must lock/update the relevant counter and debit credit in the same transaction.
CREATE TABLE workspace_capacity_counters (
  dimension_key text PRIMARY KEY CHECK (dimension_key IN ('active_students','counselors','branches','concurrent_users')),
  current_value integer NOT NULL DEFAULT 0 CHECK (current_value>=0),
  max_value integer NOT NULL CHECK (max_value>0),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK (current_value<=max_value)
);
CREATE TABLE capacity_events (
  capacity_event_id uuid PRIMARY KEY,
  dimension_key text NOT NULL REFERENCES workspace_capacity_counters(dimension_key),
  delta integer NOT NULL CHECK (delta<>0),
  idempotency_key text NOT NULL UNIQUE,
  student_id uuid REFERENCES students(student_id),
  actor_membership_id uuid REFERENCES workspace_memberships(membership_id),
  reason text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE FUNCTION reject_capacity_event_mutation() RETURNS trigger LANGUAGE plpgsql AS $body$
BEGIN
  RAISE EXCEPTION 'capacity_events is append-only' USING ERRCODE='check_violation';
END; $body$;
CREATE TRIGGER capacity_events_append_only
  BEFORE UPDATE OR DELETE ON capacity_events
  FOR EACH ROW EXECUTE FUNCTION reject_capacity_event_mutation();

-- Atomic counter adjustment. Call inside the same transaction as student activation/archive
-- and credit debit/reversal. Reusing an idempotency key with different intent is rejected.
CREATE FUNCTION adjust_workspace_capacity(
  p_dimension_key text,
  p_delta integer,
  p_idempotency_key text,
  p_student_id uuid,
  p_actor_membership_id uuid,
  p_reason text
) RETURNS integer LANGUAGE plpgsql AS $body$
DECLARE v_inserted integer; v_existing public.capacity_events%ROWTYPE; v_current integer;
BEGIN
  IF p_delta=0 OR p_idempotency_key IS NULL OR p_idempotency_key='' THEN
    RAISE EXCEPTION 'capacity delta and idempotency key are required' USING ERRCODE='invalid_parameter_value';
  END IF;
  INSERT INTO public.capacity_events(capacity_event_id,dimension_key,delta,idempotency_key,student_id,actor_membership_id,reason)
  VALUES(gen_random_uuid(),p_dimension_key,p_delta,p_idempotency_key,p_student_id,p_actor_membership_id,p_reason)
  ON CONFLICT(idempotency_key) DO NOTHING;
  GET DIAGNOSTICS v_inserted=ROW_COUNT;
  IF v_inserted=0 THEN
    SELECT * INTO v_existing FROM public.capacity_events WHERE idempotency_key=p_idempotency_key;
    IF v_existing.dimension_key<>p_dimension_key OR v_existing.delta<>p_delta
       OR v_existing.student_id IS DISTINCT FROM p_student_id
       OR v_existing.actor_membership_id IS DISTINCT FROM p_actor_membership_id
       OR v_existing.reason IS DISTINCT FROM p_reason THEN
      RAISE EXCEPTION 'capacity idempotency key reused with different intent' USING ERRCODE='unique_violation';
    END IF;
    SELECT current_value INTO v_current FROM public.workspace_capacity_counters WHERE dimension_key=p_dimension_key;
    IF NOT FOUND THEN RAISE EXCEPTION 'capacity counter is not configured for %',p_dimension_key USING ERRCODE='check_violation'; END IF;
    RETURN v_current;
  END IF;
  UPDATE public.workspace_capacity_counters
     SET current_value=current_value+p_delta,updated_at=now()
   WHERE dimension_key=p_dimension_key
     AND current_value+p_delta>=0
     AND current_value+p_delta<=max_value
   RETURNING current_value INTO v_current;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'capacity unavailable or decrement would underflow for dimension %',p_dimension_key
      USING ERRCODE='check_violation';
  END IF;
  RETURN v_current;
END; $body$;

-- Provider-neutral private object metadata. URLs are never stored as object keys.
CREATE TABLE private_file_objects (
  file_id uuid PRIMARY KEY,
  student_id uuid REFERENCES students(student_id),
  object_key text NOT NULL UNIQUE CHECK (object_key LIKE 'workspace/%' AND object_key !~* '^https?://'),
  storage_provider text NOT NULL,
  content_type text NOT NULL,
  byte_size bigint NOT NULL CHECK (byte_size>0),
  sha256 bytea NOT NULL CHECK (octet_length(sha256)=32),
  encryption_key_version integer NOT NULL CHECK (encryption_key_version>0),
  state text NOT NULL CHECK (state IN ('quarantined','available','archived')),
  uploaded_by_membership_id uuid REFERENCES workspace_memberships(membership_id),
  created_at timestamptz NOT NULL DEFAULT now(),
  archived_at timestamptz,
  CHECK ((state='archived') = (archived_at IS NOT NULL))
);

CREATE TABLE notification_preferences (
  platform_user_id uuid NOT NULL,
  notification_type text NOT NULL,
  in_app_enabled boolean NOT NULL DEFAULT true,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(platform_user_id,notification_type)
);
CREATE TABLE in_app_notifications (
  notification_id uuid PRIMARY KEY,
  recipient_platform_user_id uuid NOT NULL,
  notification_type text NOT NULL,
  template_version text NOT NULL,
  payload jsonb NOT NULL,
  idempotency_key text NOT NULL UNIQUE,
  created_at timestamptz NOT NULL DEFAULT now(),
  read_at timestamptz
);

CREATE TABLE legal_holds (
  legal_hold_id uuid PRIMARY KEY,
  entity_type text NOT NULL,
  entity_id uuid NOT NULL,
  hold_ref text NOT NULL,
  reason text NOT NULL,
  placed_by_membership_id uuid REFERENCES workspace_memberships(membership_id),
  placed_at timestamptz NOT NULL DEFAULT now(),
  released_by_membership_id uuid REFERENCES workspace_memberships(membership_id),
  released_at timestamptz,
  CHECK ((released_at IS NULL) = (released_by_membership_id IS NULL)),
  UNIQUE(entity_type,entity_id,hold_ref)
);

CREATE TABLE audit_events (
  audit_event_id uuid PRIMARY KEY,
  actor_membership_id uuid REFERENCES workspace_memberships(membership_id),
  event_type text NOT NULL,
  target_type text NOT NULL,
  target_id uuid,
  outcome text NOT NULL CHECK (outcome IN ('allowed','denied','success','failure')),
  correlation_id text,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE FUNCTION reject_audit_mutation() RETURNS trigger LANGUAGE plpgsql AS $body$
BEGIN
  RAISE EXCEPTION 'audit_events is append-only' USING ERRCODE='check_violation';
END; $body$;
CREATE TRIGGER audit_events_append_only
  BEFORE UPDATE OR DELETE ON audit_events
  FOR EACH ROW EXECUTE FUNCTION reject_audit_mutation();

CREATE TABLE credit_wallets (
  wallet_id uuid PRIMARY KEY,
  unit_code char(3) NOT NULL CHECK (unit_code = 'CRD'), -- Student Credit unit, never fiat currency
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(unit_code)
);

CREATE FUNCTION reject_credit_wallet_mutation() RETURNS trigger LANGUAGE plpgsql AS $body$
BEGIN
  RAISE EXCEPTION 'credit wallet identity/unit is immutable' USING ERRCODE='check_violation';
END; $body$;
CREATE TRIGGER credit_wallets_immutable
  BEFORE UPDATE OR DELETE ON credit_wallets
  FOR EACH ROW EXECUTE FUNCTION reject_credit_wallet_mutation();
CREATE TABLE credit_transactions (
  transaction_id uuid PRIMARY KEY,
  wallet_id uuid NOT NULL REFERENCES credit_wallets(wallet_id),
  transaction_kind text NOT NULL CHECK (transaction_kind IN ('purchase','grant','activation_debit','adjustment','reversal')),
  amount bigint NOT NULL CHECK (amount <> 0),
  idempotency_key text NOT NULL UNIQUE,
  related_transaction_id uuid REFERENCES credit_transactions(transaction_id),
  student_id uuid REFERENCES students(student_id),
  actor_membership_id uuid REFERENCES workspace_memberships(membership_id),
  reason text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (transaction_kind <> 'reversal' OR related_transaction_id IS NOT NULL),
  CHECK (transaction_kind NOT IN ('purchase','grant') OR amount > 0),
  CHECK (transaction_kind <> 'activation_debit' OR amount < 0)
);

CREATE UNIQUE INDEX one_reversal_per_credit_transaction
  ON credit_transactions(related_transaction_id)
  WHERE transaction_kind='reversal';

CREATE FUNCTION validate_credit_reversal() RETURNS trigger LANGUAGE plpgsql AS $body$
DECLARE v_wallet uuid; v_amount bigint; v_kind text;
BEGIN
  IF NEW.transaction_kind='reversal' THEN
    SELECT wallet_id,amount,transaction_kind INTO v_wallet,v_amount,v_kind
      FROM credit_transactions WHERE transaction_id=NEW.related_transaction_id FOR UPDATE;
    IF NOT FOUND OR v_wallet<>NEW.wallet_id OR v_kind='reversal' OR NEW.amount<>-v_amount THEN
      RAISE EXCEPTION 'reversal must reference one original transaction in the same wallet with exact opposite amount'
        USING ERRCODE='check_violation';
    END IF;
  END IF;
  RETURN NEW;
END; $body$;
CREATE TRIGGER credit_reversal_guard
  BEFORE INSERT ON credit_transactions
  FOR EACH ROW EXECUTE FUNCTION validate_credit_reversal();

-- PD-2026-11-13-D — Student Credit entitlement.
-- One row per activation that spent credit. It records WHICH student the credit was spent on, WHEN the
-- original activation happened (the start of the 7-calendar-day reversal window) and WHEN the original
-- entitlement period ends. The period end is supplied by the caller: no entitlement duration is decided
-- here, and the database never derives, extends or restarts it.
--   state 'consumed' : the credit is spent on this student's enrollment.
--   state 'reserved' : the enrollment was archived inside the reversal window, the original debit has been
--                      compensated in the ledger, and the returned credit is bound to THIS student.
-- A reversed entitlement (reversal_transaction_id IS NOT NULL) keeps holding its credit in both states, so
-- the returned credit never becomes generally spendable wallet balance (see view credit_wallet_balances).
CREATE TABLE student_entitlements (
  entitlement_id uuid PRIMARY KEY,
  student_id uuid NOT NULL REFERENCES students(student_id),
  debit_transaction_id uuid NOT NULL UNIQUE REFERENCES credit_transactions(transaction_id),
  credit_amount bigint NOT NULL CHECK (credit_amount>0),
  activated_at timestamptz NOT NULL,
  period_end timestamptz NOT NULL,
  state text NOT NULL CHECK (state IN ('consumed','reserved')),
  reversal_transaction_id uuid UNIQUE REFERENCES credit_transactions(transaction_id),
  reserved_at timestamptz,
  reconsumed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (period_end > activated_at),
  CHECK (state<>'reserved' OR reserved_at IS NOT NULL),   -- reserved_at is kept as history after re-consumption
  CHECK (state<>'reserved' OR reversal_transaction_id IS NOT NULL)
);
CREATE INDEX student_entitlements_student_idx ON student_entitlements(student_id, state);

CREATE FUNCTION student_entitlement_guard() RETURNS trigger LANGUAGE plpgsql AS $body$
BEGIN
  IF TG_OP='DELETE' THEN
    RAISE EXCEPTION 'student entitlements are not deletable' USING ERRCODE='check_violation';
  END IF;
  IF TG_OP='INSERT' THEN
    IF NEW.state<>'consumed' OR NEW.reversal_transaction_id IS NOT NULL OR NEW.reconsumed_at IS NOT NULL THEN
      RAISE EXCEPTION 'an entitlement is created as consumed, without compensation metadata' USING ERRCODE='check_violation';
    END IF;
    RETURN NEW;
  END IF;
  -- The original period can never be restarted or extended, and the credit cannot change student.
  IF (NEW.entitlement_id,NEW.student_id,NEW.debit_transaction_id,NEW.credit_amount,NEW.activated_at,NEW.period_end)
     IS DISTINCT FROM
     (OLD.entitlement_id,OLD.student_id,OLD.debit_transaction_id,OLD.credit_amount,OLD.activated_at,OLD.period_end) THEN
    RAISE EXCEPTION 'entitlement identity, amount, activation time and period end are immutable' USING ERRCODE='check_violation';
  END IF;
  IF OLD.reversal_transaction_id IS NOT NULL
     AND NEW.reversal_transaction_id IS DISTINCT FROM OLD.reversal_transaction_id THEN
    RAISE EXCEPTION 'the compensating ledger entry of an entitlement is immutable' USING ERRCODE='check_violation';
  END IF;
  IF OLD.state='consumed' AND NEW.state='reserved' THEN
    IF NOT EXISTS (SELECT 1 FROM public.credit_transactions t
                    WHERE t.transaction_id=NEW.reversal_transaction_id
                      AND t.transaction_kind='reversal'
                      AND t.related_transaction_id=NEW.debit_transaction_id
                      AND t.student_id IS NOT DISTINCT FROM NEW.student_id) THEN
      RAISE EXCEPTION 'reserving an entitlement requires its own compensating reversal of the original debit'
        USING ERRCODE='check_violation';
    END IF;
    RETURN NEW;
  ELSIF OLD.state='reserved' AND NEW.state='consumed' THEN
    IF NEW.reconsumed_at IS NULL THEN
      RAISE EXCEPTION 'reactivation must record reconsumed_at' USING ERRCODE='check_violation';
    END IF;
    RETURN NEW;
  ELSIF OLD.state=NEW.state THEN
    RETURN NEW;
  END IF;
  RAISE EXCEPTION 'illegal entitlement transition % -> %', OLD.state, NEW.state USING ERRCODE='check_violation';
END; $body$;
CREATE TRIGGER student_entitlements_guard BEFORE INSERT OR UPDATE OR DELETE ON student_entitlements
  FOR EACH ROW EXECUTE FUNCTION student_entitlement_guard();

CREATE FUNCTION reject_ledger_mutation() RETURNS trigger LANGUAGE plpgsql AS $body$
BEGIN
  RAISE EXCEPTION 'credit_transactions is append-only' USING ERRCODE='check_violation';
END; $body$;
CREATE TRIGGER credit_transactions_append_only
  BEFORE UPDATE OR DELETE ON credit_transactions
  FOR EACH ROW EXECUTE FUNCTION reject_ledger_mutation();

-- ======================================================================================================
-- PD-2026-11-13-B — Activity is the shared scheduling/tracking/execution layer over AUTHORITATIVE
-- specialized entities. The link is one typed, foreign-key-backed column per source kind. There is no
-- source_type/source_id pair: an unrestricted polymorphic reference cannot be checked by the database and
-- is not an acceptable substitute for referential integrity.
--
-- Field ownership (the Activity never duplicates these):
--   Test attempt   -> test_attempts        owns version, denominator, counters, score, submission evidence
--   Exam           -> exams/exam_results   owns schedule, scoring policy and results
--   Class session  -> class_sessions       owns time, timezone and joining/location reference
--   Assignment     -> assignments          owns due date and submission state
--   Review         -> reviews              owns cadence, scheduled time and completion
-- The Activity owns only its own scheduling and execution fields: title, due_at, priority, state.
-- Each source foreign key carries student_id, so an Activity can only cite a source of its OWN student.
-- ======================================================================================================
ALTER TABLE activities
  ADD COLUMN test_attempt_id    uuid,
  ADD COLUMN exam_id            uuid,
  ADD COLUMN class_session_id   uuid,
  ADD COLUMN assignment_id      uuid,
  ADD COLUMN review_id          uuid,
  ADD CONSTRAINT activities_test_attempt_fk
    FOREIGN KEY (test_attempt_id, student_id)  REFERENCES test_attempts(attempt_id, student_id),
  ADD CONSTRAINT activities_exam_fk
    FOREIGN KEY (exam_id, student_id)          REFERENCES exams(exam_id, student_id),
  ADD CONSTRAINT activities_class_session_fk
    FOREIGN KEY (class_session_id, student_id) REFERENCES class_session_participants(class_session_id, student_id),
  ADD CONSTRAINT activities_assignment_fk
    FOREIGN KEY (assignment_id, student_id)    REFERENCES assignments(assignment_id, student_id),
  ADD CONSTRAINT activities_review_fk
    FOREIGN KEY (review_id, student_id)        REFERENCES reviews(review_id, student_id),
  -- Exactly the column that matches activity_kind is set, and no other.
  ADD CONSTRAINT activities_single_typed_source CHECK (
    (CASE WHEN test_attempt_id  IS NOT NULL THEN 1 ELSE 0 END
   + CASE WHEN exam_id          IS NOT NULL THEN 1 ELSE 0 END
   + CASE WHEN class_session_id IS NOT NULL THEN 1 ELSE 0 END
   + CASE WHEN assignment_id    IS NOT NULL THEN 1 ELSE 0 END
   + CASE WHEN review_id        IS NOT NULL THEN 1 ELSE 0 END)
   = CASE WHEN activity_kind IN ('test','exam','class_followup','homework','review') THEN 1 ELSE 0 END),
  ADD CONSTRAINT activities_source_matches_kind CHECK (
       (activity_kind = 'test')           = (test_attempt_id  IS NOT NULL)
   AND (activity_kind = 'exam')           = (exam_id          IS NOT NULL)
   AND (activity_kind = 'class_followup') = (class_session_id IS NOT NULL)
   AND (activity_kind = 'homework')       = (assignment_id    IS NOT NULL)
   AND (activity_kind = 'review')         = (review_id        IS NOT NULL));
-- One Activity per source record: the shared layer never forks a domain record into two schedules.
CREATE UNIQUE INDEX activities_one_per_test_attempt  ON activities(test_attempt_id)  WHERE test_attempt_id  IS NOT NULL;
CREATE UNIQUE INDEX activities_one_per_exam          ON activities(exam_id)          WHERE exam_id          IS NOT NULL;
CREATE UNIQUE INDEX activities_one_per_class_session ON activities(class_session_id,student_id) WHERE class_session_id IS NOT NULL;
CREATE UNIQUE INDEX activities_one_per_assignment    ON activities(assignment_id)    WHERE assignment_id    IS NOT NULL;
CREATE UNIQUE INDEX activities_one_per_review        ON activities(review_id)        WHERE review_id        IS NOT NULL;

-- The student of an Activity is immutable: moving an Activity to another student would silently detach it
-- from the source record the foreign key validated.
CREATE FUNCTION activity_student_immutable() RETURNS trigger LANGUAGE plpgsql AS $body$
BEGIN
  IF NEW.student_id IS DISTINCT FROM OLD.student_id OR NEW.activity_kind IS DISTINCT FROM OLD.activity_kind THEN
    RAISE EXCEPTION 'the student and kind of an activity are immutable' USING ERRCODE='check_violation';
  END IF;
  RETURN NEW;
END; $body$;
CREATE TRIGGER activities_student_kind_immutable BEFORE UPDATE ON activities
  FOR EACH ROW EXECUTE FUNCTION activity_student_immutable();

COMMIT;

-- IMPORTANT DRAFT LIMITATIONS:
-- 1. This skeleton does not replace the complete Phase 2 domain schema.
-- 2. Draft triggers reject UPDATE/DELETE of published versions; final review must test bypass/owner privileges.
-- 3. Membership/branch/workspace type rules and guardian legal authority require trusted application
--    authorization plus additional constraints/triggers and executable tests.
-- 4. Atomic activation/debit/capacity orchestration is in companion workspace_activation_transactions.sql;
--    it remains a draft and still requires trusted Control Plane/API authorization.
-- 5. Workspace DB cannot enforce Control Plane global ownership or global mobile+grade uniqueness.
