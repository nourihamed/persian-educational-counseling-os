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

CREATE TABLE credit_wallets (
  wallet_id uuid PRIMARY KEY,
  currency_code char(3) NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(currency_code)
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

CREATE FUNCTION reject_ledger_mutation() RETURNS trigger LANGUAGE plpgsql AS $
BEGIN
  RAISE EXCEPTION 'credit_transactions is append-only' USING ERRCODE='check_violation';
END; $$;
CREATE TRIGGER credit_transactions_append_only
  BEFORE UPDATE OR DELETE ON credit_transactions
  FOR EACH ROW EXECUTE FUNCTION reject_ledger_mutation();

COMMIT;

-- IMPORTANT DRAFT LIMITATIONS:
-- 1. This skeleton does not replace the complete Phase 2 domain schema.
-- 2. Draft triggers reject UPDATE/DELETE of published versions; final review must test bypass/owner privileges.
-- 3. Membership/branch/workspace type rules and guardian legal authority require trusted application
--    authorization plus additional constraints/triggers and executable tests.
-- 4. Capacity/entitlement checks must be atomic in the activation transaction and remain separate
--    from the credit ledger.
-- 5. Workspace DB cannot enforce Control Plane global ownership or global mobile+grade uniqueness.
