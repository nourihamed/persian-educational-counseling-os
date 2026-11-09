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
  role_key text NOT NULL,
  status text NOT NULL CHECK (status IN ('invited','active','suspended','ended')),
  granted_at timestamptz NOT NULL DEFAULT now(),
  ended_at timestamptz,
  UNIQUE (platform_user_id),
  CHECK ((status='ended') = (ended_at IS NOT NULL))
);

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
  CHECK (verification_state <> 'verified' OR (verified_at IS NOT NULL AND legal_authority_ref IS NOT NULL))
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
  activity_kind text NOT NULL CHECK (activity_kind IN ('study','homework','review','test','class_followup','custom')),
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
CREATE TABLE test_attempts (
  attempt_id uuid PRIMARY KEY,
  test_id uuid NOT NULL REFERENCES test_definitions(test_id),
  student_id uuid NOT NULL REFERENCES students(student_id),
  state text NOT NULL CHECK (state IN ('started','submitted','analysed','cancelled')),
  started_at timestamptz NOT NULL,
  submitted_at timestamptz,
  correct_count integer NOT NULL DEFAULT 0 CHECK (correct_count>=0),
  wrong_count integer NOT NULL DEFAULT 0 CHECK (wrong_count>=0),
  blank_count integer NOT NULL DEFAULT 0 CHECK (blank_count>=0),
  score numeric(7,3),
  scoring_policy_snapshot jsonb NOT NULL,
  CHECK ((state IN ('submitted','analysed')) = (submitted_at IS NOT NULL))
);
CREATE TABLE test_responses (
  response_id uuid PRIMARY KEY,
  attempt_id uuid NOT NULL REFERENCES test_attempts(attempt_id),
  question_no integer NOT NULL CHECK (question_no>0),
  topic_id uuid REFERENCES topics(topic_id),
  response_state text NOT NULL CHECK (response_state IN ('correct','wrong','blank')),
  time_spent_seconds integer CHECK (time_spent_seconds IS NULL OR time_spent_seconds>=0),
  error_reason text CHECK (error_reason IN ('concept','memory','careless','time','strategy','unknown')),
  UNIQUE(attempt_id,question_no)
);

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
  CHECK (ends_at>starts_at)
);
CREATE TABLE assignments (
  assignment_id uuid PRIMARY KEY,
  student_id uuid NOT NULL REFERENCES students(student_id),
  class_session_id uuid REFERENCES class_sessions(class_session_id),
  title text NOT NULL,
  due_at timestamptz,
  state text NOT NULL CHECK (state IN ('assigned','in_progress','submitted','reviewed','overdue','cancelled')),
  created_by_membership_id uuid REFERENCES workspace_memberships(membership_id),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE reviews (
  review_id uuid PRIMARY KEY,
  student_id uuid NOT NULL REFERENCES students(student_id),
  topic_id uuid REFERENCES topics(topic_id),
  scheduled_at timestamptz NOT NULL,
  cadence_days integer CHECK (cadence_days IS NULL OR cadence_days>0),
  state text NOT NULL CHECK (state IN ('scheduled','completed','missed','cancelled')),
  completed_at timestamptz
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

CREATE FUNCTION reject_ledger_mutation() RETURNS trigger LANGUAGE plpgsql AS $body$
BEGIN
  RAISE EXCEPTION 'credit_transactions is append-only' USING ERRCODE='check_violation';
END; $body$;
CREATE TRIGGER credit_transactions_append_only
  BEFORE UPDATE OR DELETE ON credit_transactions
  FOR EACH ROW EXECUTE FUNCTION reject_ledger_mutation();

COMMIT;

-- IMPORTANT DRAFT LIMITATIONS:
-- 1. This skeleton does not replace the complete Phase 2 domain schema.
-- 2. Draft triggers reject UPDATE/DELETE of published versions; final review must test bypass/owner privileges.
-- 3. Membership/branch/workspace type rules and guardian legal authority require trusted application
--    authorization plus additional constraints/triggers and executable tests.
-- 4. Atomic activation/debit/capacity orchestration is in companion workspace_activation_transactions.sql;
--    it remains a draft and still requires trusted Control Plane/API authorization.
-- 5. Workspace DB cannot enforce Control Plane global ownership or global mobile+grade uniqueness.
