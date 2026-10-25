-- =============================================================================
-- PHASE 2 — DDL DRAFT v2 (PostgreSQL 15+)
-- Status: DRAFT. Not a migration. Not approved. Not independently reviewed.
-- Synthetic data only (D-014). Requires phase2_roles_setup.sql first (test env).
--
-- Remediation scope (see docs/phase2/REMEDIATION_REPORT.md):
--   P2-H01/H05 credit ledger: writes only via post_credit_transaction(); balance
--              not writable by runtime role; reconciliation view; TRUNCATE blocked.
--   P2-H02     program_versions identity immutable; forbidden transitions enforced.
--   P2-H03     plan_versions / plan_items lifecycle immutability after activation.
--   P2-H04     curriculum_nodes, study_sessions, error_records, exams, exam_results,
--              class_sessions, assignments added. Remaining deferrals documented.
--   P2-M03     column names aligned with the domain document (see report table).
--   P2-M04     audit_logs.scope makes platform vs tenant events explicit.
--
-- Tenant rule: every tenant-owned table has tenant_id NOT NULL; cross-tenant
-- references use composite foreign keys (tenant_id, id).
-- Out of scope: auth/users tables (Phase 4), payment gateway, orders, RLS,
-- market segments, production role provisioning.
-- =============================================================================

BEGIN;

-- ------------------------------------------------------------ helpers ----
-- Used on append-only and immutable tables. Blocks UPDATE, DELETE and TRUNCATE
-- for the role running the statement (including owner).
CREATE FUNCTION forbid_mutation() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION '% on % is forbidden (append-only or immutable)', TG_OP, TG_TABLE_NAME
        USING ERRCODE = 'check_violation';
END;
$$;

-- ------------------------------------------------------------ tenancy ----
CREATE TABLE tenants (
    id          uuid PRIMARY KEY,
    status      text NOT NULL CHECK (status IN ('active', 'suspended', 'closed')),
    created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE counselors (
    id              uuid PRIMARY KEY,
    tenant_id       uuid NOT NULL REFERENCES tenants (id),
    user_id         uuid,                       -- nullable; no FK until Phase 4 (users table)
    display_name    text NOT NULL,
    deactivated_at  timestamptz,
    created_at      timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id)
);

CREATE TABLE students (
    id          uuid PRIMARY KEY,
    tenant_id   uuid NOT NULL REFERENCES tenants (id),
    user_id     uuid,                           -- nullable until student activates; no FK until Phase 4
    status      text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'archived')),
    created_at  timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id)
);

CREATE TABLE student_profiles (
    student_id      uuid PRIMARY KEY,
    tenant_id       uuid NOT NULL,
    full_name       text NOT NULL,
    birth_date      date,
    grade           text,
    field           text,
    school          text,
    goal            text,
    updated_at      timestamptz NOT NULL DEFAULT now(),
    FOREIGN KEY (tenant_id, student_id) REFERENCES students (tenant_id, id)
);

CREATE TABLE counselor_students (
    id           uuid PRIMARY KEY,
    tenant_id    uuid NOT NULL REFERENCES tenants (id),
    counselor_id uuid NOT NULL,
    student_id   uuid NOT NULL,
    status       text NOT NULL CHECK (status IN ('active', 'paused', 'archived', 'ended')),
    started_at   timestamptz NOT NULL,
    ended_at     timestamptz,
    notes        text,
    created_at   timestamptz NOT NULL DEFAULT now(),
    CHECK (ended_at IS NULL OR ended_at >= started_at),
    FOREIGN KEY (tenant_id, counselor_id) REFERENCES counselors (tenant_id, id),
    FOREIGN KEY (tenant_id, student_id)   REFERENCES students (tenant_id, id)
);
CREATE UNIQUE INDEX counselor_students_one_active
    ON counselor_students (tenant_id, student_id) WHERE status = 'active';

-- --------------------------------------------------------- curriculum ----
CREATE TABLE subjects (
    id          uuid PRIMARY KEY,
    tenant_id   uuid NOT NULL REFERENCES tenants (id),
    name        text NOT NULL,
    category    text,                           -- values pending product definition (deferred)
    sort_order  integer NOT NULL DEFAULT 0,
    is_active   boolean NOT NULL DEFAULT true,
    UNIQUE (tenant_id, id)
);
CREATE UNIQUE INDEX subjects_active_name
    ON subjects (tenant_id, name) WHERE is_active;

CREATE TABLE curriculum_nodes (
    id           uuid PRIMARY KEY,
    tenant_id    uuid NOT NULL REFERENCES tenants (id),
    subject_id   uuid NOT NULL,
    parent_id    uuid,
    level        text NOT NULL CHECK (level IN ('grade', 'book', 'chapter', 'topic', 'subtopic')),
    name         text NOT NULL,
    sort_order   integer NOT NULL DEFAULT 0,
    is_active    boolean NOT NULL DEFAULT true,
    UNIQUE (tenant_id, id),
    FOREIGN KEY (tenant_id, subject_id) REFERENCES subjects (tenant_id, id),
    FOREIGN KEY (tenant_id, parent_id)  REFERENCES curriculum_nodes (tenant_id, id)
);

-- --------------------------------------------- programs (D-008 / D-012) ----
CREATE TABLE program_templates (
    id          uuid PRIMARY KEY,
    tenant_id   uuid NOT NULL REFERENCES tenants (id),
    name        text NOT NULL,
    status      text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'archived')),
    created_by  uuid,
    created_at  timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id)
);

CREATE TABLE program_versions (
    id                  uuid PRIMARY KEY,
    tenant_id           uuid NOT NULL REFERENCES tenants (id),
    program_template_id uuid NOT NULL,
    version_number      integer NOT NULL CHECK (version_number > 0),
    status              text NOT NULL DEFAULT 'draft'
                        CHECK (status IN ('draft', 'published', 'superseded')),
    payload_json        jsonb NOT NULL,
    created_by          uuid,
    created_at          timestamptz NOT NULL DEFAULT now(),
    published_by        uuid,
    published_at        timestamptz,
    CHECK (status = 'draft' OR (published_at IS NOT NULL AND published_by IS NOT NULL)),
    UNIQUE (tenant_id, program_template_id, version_number),
    UNIQUE (tenant_id, id),
    FOREIGN KEY (tenant_id, program_template_id) REFERENCES program_templates (tenant_id, id)
);

-- Lifecycle (P2-H02):
--   Identity (id, tenant_id, program_template_id, version_number, created_by,
--   created_at) is immutable for ALL statuses.
--   draft      -> draft (edit payload) | published
--   published  -> superseded only; payload_json, published_at, published_by frozen
--   superseded -> terminal; no change at all
--   DELETE allowed only for draft rows.
CREATE FUNCTION program_versions_guard() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        IF OLD.status <> 'draft' THEN
            RAISE EXCEPTION 'program_version % is % and cannot be deleted', OLD.id, OLD.status
                USING ERRCODE = 'check_violation';
        END IF;
        RETURN OLD;
    END IF;

    IF (NEW.id, NEW.tenant_id, NEW.program_template_id, NEW.version_number,
        NEW.created_by, NEW.created_at)
       IS DISTINCT FROM
       (OLD.id, OLD.tenant_id, OLD.program_template_id, OLD.version_number,
        OLD.created_by, OLD.created_at) THEN
        RAISE EXCEPTION 'program_version % identity is immutable', OLD.id
            USING ERRCODE = 'check_violation';
    END IF;

    IF OLD.status = 'draft' THEN
        IF NEW.status IN ('draft', 'published') THEN
            RETURN NEW;
        END IF;
        RAISE EXCEPTION 'illegal program_version transition % -> % (draft may only become published)',
            OLD.status, NEW.status USING ERRCODE = 'check_violation';
    ELSIF OLD.status = 'published' THEN
        IF NEW.status NOT IN ('published', 'superseded') THEN
            RAISE EXCEPTION 'illegal program_version transition % -> % (published may only become superseded)',
                OLD.status, NEW.status USING ERRCODE = 'check_violation';
        END IF;
        IF (NEW.payload_json, NEW.published_by, NEW.published_at)
           IS DISTINCT FROM (OLD.payload_json, OLD.published_by, OLD.published_at) THEN
            RAISE EXCEPTION 'published program_version % content is immutable', OLD.id
                USING ERRCODE = 'check_violation';
        END IF;
        RETURN NEW;
    ELSE
        RAISE EXCEPTION 'superseded program_version % is terminal', OLD.id
            USING ERRCODE = 'check_violation';
    END IF;
END;
$$;

CREATE TRIGGER program_versions_guard_trg
    BEFORE UPDATE OR DELETE ON program_versions
    FOR EACH ROW EXECUTE FUNCTION program_versions_guard();
CREATE TRIGGER program_versions_no_truncate
    BEFORE TRUNCATE ON program_versions
    FOR EACH STATEMENT EXECUTE FUNCTION forbid_mutation();

CREATE TABLE student_program_enrollments (
    id                 uuid PRIMARY KEY,
    tenant_id          uuid NOT NULL REFERENCES tenants (id),
    student_id         uuid NOT NULL,
    program_version_id uuid NOT NULL,
    enrolled_by        uuid,
    enrolled_at        timestamptz NOT NULL DEFAULT now(),
    ended_at           timestamptz,
    CHECK (ended_at IS NULL OR ended_at >= enrolled_at),
    FOREIGN KEY (tenant_id, student_id)         REFERENCES students (tenant_id, id),
    FOREIGN KEY (tenant_id, program_version_id) REFERENCES program_versions (tenant_id, id)
);
-- O-9 (PROPOSAL, not accepted): at most one active enrollment per student.
CREATE UNIQUE INDEX enrollments_one_active
    ON student_program_enrollments (tenant_id, student_id) WHERE ended_at IS NULL;

-- Only published or superseded versions can be enrolled (not drafts).
CREATE FUNCTION enrollment_requires_published_version() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE v_status text;
BEGIN
    SELECT status INTO v_status FROM program_versions
     WHERE tenant_id = NEW.tenant_id AND id = NEW.program_version_id;
    IF v_status IS NULL OR v_status NOT IN ('published', 'superseded') THEN
        RAISE EXCEPTION 'enrollment requires a published program_version (found %)', v_status
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER enrollment_requires_published
    BEFORE INSERT ON student_program_enrollments
    FOR EACH ROW EXECUTE FUNCTION enrollment_requires_published_version();

-- ------------------------------------------------- planning (D-008 / P2-H03) ----
CREATE TABLE plans (
    id           uuid PRIMARY KEY,
    tenant_id    uuid NOT NULL REFERENCES tenants (id),
    student_id   uuid NOT NULL,
    scope        text NOT NULL CHECK (scope IN ('daily', 'weekly', 'monthly', 'exam', 'review', 'recovery')),
    period_start date NOT NULL,
    period_end   date NOT NULL,
    created_by   uuid,
    created_at   timestamptz NOT NULL DEFAULT now(),
    CHECK (period_end >= period_start),
    UNIQUE (tenant_id, id),
    FOREIGN KEY (tenant_id, student_id) REFERENCES students (tenant_id, id)
);

CREATE TABLE plan_versions (
    id                 uuid PRIMARY KEY,
    tenant_id          uuid NOT NULL REFERENCES tenants (id),
    plan_id            uuid NOT NULL,
    version_number     integer NOT NULL CHECK (version_number > 0),
    program_version_id uuid,                    -- nullable; fixed at creation (see guard)
    created_by         uuid,
    created_at         timestamptz NOT NULL DEFAULT now(),
    activated_at       timestamptz,
    superseded_at      timestamptz,
    CHECK (activated_at IS NULL OR created_at <= activated_at),
    CHECK (superseded_at IS NULL OR activated_at IS NOT NULL),
    CHECK (superseded_at IS NULL OR superseded_at >= activated_at),
    UNIQUE (tenant_id, plan_id, version_number),
    UNIQUE (tenant_id, id),
    FOREIGN KEY (tenant_id, plan_id)            REFERENCES plans (tenant_id, id),
    FOREIGN KEY (tenant_id, program_version_id) REFERENCES program_versions (tenant_id, id)
);
CREATE UNIQUE INDEX plan_versions_one_active
    ON plan_versions (tenant_id, plan_id)
    WHERE activated_at IS NOT NULL AND superseded_at IS NULL;

-- Lifecycle (P2-H03):
--   Identity and origin (id, tenant_id, plan_id, version_number, program_version_id,
--   created_by, created_at) are immutable.
--   draft (activated_at NULL): items may change; version may be deleted.
--   activated (activated_at set): activated_at frozen; items frozen; no delete.
--   superseded_at may be set once (NULL -> value) after activation; then frozen.
CREATE FUNCTION plan_versions_guard() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        IF OLD.activated_at IS NOT NULL THEN
            RAISE EXCEPTION 'activated plan_version % cannot be deleted', OLD.id
                USING ERRCODE = 'check_violation';
        END IF;
        RETURN OLD;
    END IF;

    IF (NEW.id, NEW.tenant_id, NEW.plan_id, NEW.version_number,
        NEW.program_version_id, NEW.created_by, NEW.created_at)
       IS DISTINCT FROM
       (OLD.id, OLD.tenant_id, OLD.plan_id, OLD.version_number,
        OLD.program_version_id, OLD.created_by, OLD.created_at) THEN
        RAISE EXCEPTION 'plan_version % identity/origin is immutable', OLD.id
            USING ERRCODE = 'check_violation';
    END IF;

    IF OLD.activated_at IS NULL THEN
        RETURN NEW;                              -- draft: activation and supersession checked by CHECKs
    END IF;

    IF NEW.activated_at IS DISTINCT FROM OLD.activated_at THEN
        RAISE EXCEPTION 'plan_version % activation time is immutable', OLD.id
            USING ERRCODE = 'check_violation';
    END IF;
    IF OLD.superseded_at IS NOT NULL AND NEW.superseded_at IS DISTINCT FROM OLD.superseded_at THEN
        RAISE EXCEPTION 'plan_version % supersession is final', OLD.id
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER plan_versions_guard_trg
    BEFORE UPDATE OR DELETE ON plan_versions
    FOR EACH ROW EXECUTE FUNCTION plan_versions_guard();
CREATE TRIGGER plan_versions_no_truncate
    BEFORE TRUNCATE ON plan_versions
    FOR EACH STATEMENT EXECUTE FUNCTION forbid_mutation();

CREATE TABLE plan_items (
    id                  uuid PRIMARY KEY,
    tenant_id           uuid NOT NULL REFERENCES tenants (id),
    plan_version_id     uuid NOT NULL,
    activity_type       text NOT NULL CHECK (activity_type IN
                          ('study', 'test', 'review', 'exam', 'class', 'assignment', 'custom')),
    subject_id          uuid,
    curriculum_node_id  uuid,
    scheduled_start     timestamptz NOT NULL,
    scheduled_end       timestamptz NOT NULL,
    rationale_json      jsonb NOT NULL DEFAULT '[]'::jsonb,
    CHECK (scheduled_end > scheduled_start),
    FOREIGN KEY (tenant_id, plan_version_id)     REFERENCES plan_versions (tenant_id, id),
    FOREIGN KEY (tenant_id, subject_id)          REFERENCES subjects (tenant_id, id),
    FOREIGN KEY (tenant_id, curriculum_node_id)  REFERENCES curriculum_nodes (tenant_id, id)
);

-- Plan items may be written only while their plan_version is not activated.
CREATE FUNCTION plan_items_guard() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE v_activated timestamptz;
BEGIN
    IF TG_OP = 'UPDATE' AND (NEW.id, NEW.tenant_id, NEW.plan_version_id)
                          IS DISTINCT FROM (OLD.id, OLD.tenant_id, OLD.plan_version_id) THEN
        RAISE EXCEPTION 'plan_item % identity/ownership is immutable', OLD.id
            USING ERRCODE = 'check_violation';
    END IF;

    IF TG_OP = 'DELETE' THEN
        SELECT activated_at INTO v_activated FROM plan_versions
         WHERE tenant_id = OLD.tenant_id AND id = OLD.plan_version_id;
    ELSE
        SELECT activated_at INTO v_activated FROM plan_versions
         WHERE tenant_id = NEW.tenant_id AND id = NEW.plan_version_id;
    END IF;

    IF v_activated IS NOT NULL THEN
        RAISE EXCEPTION 'plan_items of an activated plan_version are frozen (%)', TG_OP
            USING ERRCODE = 'check_violation';
    END IF;

    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER plan_items_guard_trg
    BEFORE INSERT OR UPDATE OR DELETE ON plan_items
    FOR EACH ROW EXECUTE FUNCTION plan_items_guard();
CREATE TRIGGER plan_items_no_truncate
    BEFORE TRUNCATE ON plan_items
    FOR EACH STATEMENT EXECUTE FUNCTION forbid_mutation();

-- --------------------------------------------- activities & records (P2-H04) ----
CREATE TABLE activities (
    id            uuid PRIMARY KEY,
    tenant_id     uuid NOT NULL REFERENCES tenants (id),
    student_id    uuid NOT NULL,
    activity_type text NOT NULL CHECK (activity_type IN ('study', 'test', 'review')),
    subject_id    uuid,
    occurred_on   date NOT NULL,
    created_at    timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id, activity_type),
    FOREIGN KEY (tenant_id, student_id) REFERENCES students (tenant_id, id),
    FOREIGN KEY (tenant_id, subject_id) REFERENCES subjects (tenant_id, id)
);

CREATE TABLE study_sessions (
    activity_id      uuid PRIMARY KEY,
    tenant_id        uuid NOT NULL,
    activity_type   text NOT NULL DEFAULT 'study' CHECK (activity_type = 'study'),
    started_at       timestamptz NOT NULL,
    ended_at         timestamptz NOT NULL,
    goal             text,
    result           text,
    mastery_before   smallint CHECK (mastery_before BETWEEN 0 AND 100),
    mastery_after    smallint CHECK (mastery_after BETWEEN 0 AND 100),
    notes            text,
    CHECK (ended_at > started_at),
    FOREIGN KEY (tenant_id, activity_id, activity_type)
        REFERENCES activities (tenant_id, id, activity_type)
);

CREATE TABLE test_records (
    activity_id     uuid PRIMARY KEY,
    tenant_id       uuid NOT NULL,
    activity_type   text NOT NULL DEFAULT 'test' CHECK (activity_type = 'test'),
    question_count  integer NOT NULL CHECK (question_count > 0),
    correct         integer NOT NULL CHECK (correct >= 0),
    wrong           integer NOT NULL CHECK (wrong >= 0),
    unanswered      integer NOT NULL CHECK (unanswered >= 0),
    duration_minutes integer CHECK (duration_minutes > 0),
    -- Strict by default (Master §23). Override is O-5 and NOT modelled.
    CHECK (correct + wrong + unanswered = question_count),
    UNIQUE (tenant_id, activity_id),
    FOREIGN KEY (tenant_id, activity_id, activity_type)
        REFERENCES activities (tenant_id, id, activity_type)
);

CREATE TABLE error_records (
    id               uuid PRIMARY KEY,
    tenant_id        uuid NOT NULL REFERENCES tenants (id),
    test_activity_id uuid NOT NULL,
    error_type       text NOT NULL CHECK (error_type IN (
                       'conceptual', 'calculation', 'carelessness', 'misreading',
                       'time_management', 'unknown_topic', 'incomplete_learning',
                       'memory', 'strategy', 'other', 'custom')),
    custom_label     text,
    note             text,
    created_at       timestamptz NOT NULL DEFAULT now(),
    CHECK (error_type <> 'custom' OR custom_label IS NOT NULL),
    FOREIGN KEY (tenant_id, test_activity_id) REFERENCES test_records (tenant_id, activity_id)
);

CREATE TABLE review_schedules (
    id                   uuid PRIMARY KEY,
    tenant_id            uuid NOT NULL REFERENCES tenants (id),
    original_activity_id uuid NOT NULL,
    original_type        text NOT NULL,
    review_offset_days   integer NOT NULL CHECK (review_offset_days > 0),
    review_date          date NOT NULL,
    method               text,
    mastery_before       smallint CHECK (mastery_before BETWEEN 0 AND 100),
    mastery_after        smallint CHECK (mastery_after BETWEEN 0 AND 100),
    result               text,
    notes                text,
    UNIQUE (tenant_id, original_activity_id, review_offset_days),
    FOREIGN KEY (tenant_id, original_activity_id, original_type)
        REFERENCES activities (tenant_id, id, activity_type)
);

CREATE TABLE exams (
    id               uuid PRIMARY KEY,
    tenant_id        uuid NOT NULL REFERENCES tenants (id),
    title            text NOT NULL,
    exam_date        date NOT NULL,
    duration_minutes integer CHECK (duration_minutes > 0),
    exam_type        text,
    delivery_mode    text CHECK (delivery_mode IN ('online', 'offline')),
    source           text,
    goal             text,
    created_at       timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id)
);

CREATE TABLE exam_results (
    id          uuid PRIMARY KEY,
    tenant_id   uuid NOT NULL REFERENCES tenants (id),
    exam_id     uuid NOT NULL,
    student_id  uuid NOT NULL,
    subject_id  uuid,
    correct     integer CHECK (correct >= 0),
    wrong       integer CHECK (wrong >= 0),
    unanswered  integer CHECK (unanswered >= 0),
    percentage  numeric(5, 2) CHECK (percentage BETWEEN 0 AND 100),
    score       numeric(10, 2),
    rank        integer CHECK (rank > 0),
    time_minutes integer CHECK (time_minutes >= 0),
    UNIQUE NULLS NOT DISTINCT (tenant_id, exam_id, student_id, subject_id),
    FOREIGN KEY (tenant_id, exam_id)    REFERENCES exams (tenant_id, id),
    FOREIGN KEY (tenant_id, student_id) REFERENCES students (tenant_id, id),
    FOREIGN KEY (tenant_id, subject_id) REFERENCES subjects (tenant_id, id)
);

CREATE TABLE class_sessions (
    id              uuid PRIMARY KEY,
    tenant_id       uuid NOT NULL REFERENCES tenants (id),
    student_id      uuid NOT NULL,
    subject_id      uuid,
    teacher_name    text,
    class_format    text NOT NULL CHECK (class_format IN ('online', 'in_person')),
    is_recurring    boolean NOT NULL DEFAULT false,
    recurrence_rule text,
    starts_at       timestamptz NOT NULL,
    ends_at         timestamptz NOT NULL,
    platform        text,
    link            text,
    location        text,
    CHECK (ends_at > starts_at),
    CHECK (is_recurring = false OR recurrence_rule IS NOT NULL),
    FOREIGN KEY (tenant_id, student_id) REFERENCES students (tenant_id, id),
    FOREIGN KEY (tenant_id, subject_id) REFERENCES subjects (tenant_id, id)
);

CREATE TABLE assignments (
    id                uuid PRIMARY KEY,
    tenant_id         uuid NOT NULL REFERENCES tenants (id),
    student_id        uuid NOT NULL,
    subject_id        uuid,
    title             text NOT NULL,
    description       text,
    due_at            timestamptz,
    priority          text CHECK (priority IN ('low', 'medium', 'high')),
    estimated_minutes integer CHECK (estimated_minutes >= 0),
    actual_minutes    integer CHECK (actual_minutes >= 0),
    status            text NOT NULL DEFAULT 'not_started' CHECK (status IN (
                        'not_started', 'in_progress', 'completed', 'incomplete',
                        'overdue', 'rescheduled', 'cancelled', 'no_longer_needed')),
    attachment_ref    text,                    -- storage design deferred
    FOREIGN KEY (tenant_id, student_id) REFERENCES students (tenant_id, id),
    FOREIGN KEY (tenant_id, subject_id) REFERENCES subjects (tenant_id, id)
);

-- ------------------------------------------------ credit ledger (P2-H01/H05) ----
-- The balance is a CACHE of SUM(credit_transactions.amount). Under the test
-- environment it is writable only by post_credit_transaction(), which runs as
-- its owner (SECURITY DEFINER). The runtime role cannot write either table.
-- Whether the owner itself can tamper is a DEPLOYMENT guarantee, detected (not
-- prevented) by credit_reconciliation. Open decision O-2 is NOT decided here.
CREATE TABLE student_credit_accounts (
    tenant_id   uuid PRIMARY KEY REFERENCES tenants (id),
    balance     integer NOT NULL DEFAULT 0 CHECK (balance >= 0),
    version     integer NOT NULL DEFAULT 0,
    updated_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE credit_transactions (
    id               uuid PRIMARY KEY,
    tenant_id        uuid NOT NULL REFERENCES student_credit_accounts (tenant_id),
    amount           integer NOT NULL CHECK (amount <> 0),
    kind             text NOT NULL CHECK (kind IN
                       ('purchase', 'activation_consume', 'refund',
                        'cancellation_release', 'adjustment')),
    student_id       uuid,
    order_id         uuid,                      -- no orders table in Phase 2 (deferred); no FK
    actor_id         uuid,
    idempotency_key  text NOT NULL CHECK (length(idempotency_key) > 0),
    reason           text,
    created_at       timestamptz NOT NULL DEFAULT now(),
    CHECK (
        (kind IN ('purchase', 'refund', 'cancellation_release') AND amount > 0)
     OR (kind = 'activation_consume' AND amount < 0)
     OR (kind = 'adjustment' AND reason IS NOT NULL)
    ),
    UNIQUE (tenant_id, idempotency_key),
    FOREIGN KEY (tenant_id, student_id) REFERENCES students (tenant_id, id)
);
CREATE INDEX credit_transactions_tenant_time ON credit_transactions (tenant_id, created_at);

CREATE TRIGGER credit_transactions_append_only
    BEFORE UPDATE OR DELETE ON credit_transactions
    FOR EACH ROW EXECUTE FUNCTION forbid_mutation();
CREATE TRIGGER credit_transactions_no_truncate
    BEFORE TRUNCATE ON credit_transactions
    FOR EACH STATEMENT EXECUTE FUNCTION forbid_mutation();

-- Single atomic write path. Caller's transaction controls atomicity with other work
-- (e.g. student creation). Locks the account row (serialises spend per tenant),
-- replays idempotent requests, rejects overspend, and writes ledger + balance together.
CREATE FUNCTION post_credit_transaction(
    p_tenant          uuid,
    p_kind            text,
    p_amount          integer,
    p_student         uuid,
    p_order           uuid,
    p_idempotency_key text,
    p_actor           uuid,
    p_reason          text
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
    v_balance  integer;
    v_existing record;
    v_id       uuid;
BEGIN
    IF p_idempotency_key IS NULL OR length(p_idempotency_key) = 0 THEN
        RAISE EXCEPTION 'idempotency_key is required' USING ERRCODE = 'check_violation';
    END IF;

    SELECT balance INTO v_balance FROM student_credit_accounts
     WHERE tenant_id = p_tenant FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'no credit account for tenant %', p_tenant USING ERRCODE = 'foreign_key_violation';
    END IF;

    SELECT id, kind, amount, student_id INTO v_existing FROM credit_transactions
     WHERE tenant_id = p_tenant AND idempotency_key = p_idempotency_key;
    IF FOUND THEN
        IF v_existing.kind = p_kind AND v_existing.amount = p_amount
           AND v_existing.student_id IS NOT DISTINCT FROM p_student THEN
            RETURN v_existing.id;                -- idempotent replay: no second effect
        END IF;
        RAISE EXCEPTION 'idempotency_key reused with a different payload'
            USING ERRCODE = 'unique_violation';
    END IF;

    IF v_balance + p_amount < 0 THEN
        RAISE EXCEPTION 'insufficient credit: balance %, requested %', v_balance, p_amount
            USING ERRCODE = 'check_violation';
    END IF;

    INSERT INTO credit_transactions
        (id, tenant_id, amount, kind, student_id, order_id, actor_id, idempotency_key, reason)
    VALUES
        (gen_random_uuid(), p_tenant, p_amount, p_kind, p_student, p_order, p_actor, p_idempotency_key, p_reason)
    RETURNING id INTO v_id;

    UPDATE student_credit_accounts
       SET balance = balance + p_amount, version = version + 1, updated_at = now()
     WHERE tenant_id = p_tenant;

    RETURN v_id;
END;
$$;

-- Detection, not prevention: any drift between cache and ledger is visible here.
CREATE VIEW credit_reconciliation AS
SELECT a.tenant_id,
       a.balance                          AS cached_balance,
       COALESCE(SUM(t.amount), 0)         AS ledger_sum,
       a.balance - COALESCE(SUM(t.amount), 0) AS drift
  FROM student_credit_accounts a
  LEFT JOIN credit_transactions t ON t.tenant_id = a.tenant_id
 GROUP BY a.tenant_id, a.balance;

-- --------------------------------------------------- audit (P2-M04) ----
CREATE TABLE audit_logs (
    id           uuid PRIMARY KEY,
    scope        text NOT NULL CHECK (scope IN ('platform', 'tenant')),
    tenant_id    uuid REFERENCES tenants (id),
    actor_id     uuid,
    action       text NOT NULL,
    entity_type  text NOT NULL,
    entity_id    uuid,
    before_json  jsonb,
    after_json   jsonb,
    created_at   timestamptz NOT NULL DEFAULT now(),
    -- platform events have no tenant; tenant events must name their tenant.
    CHECK ((scope = 'platform') = (tenant_id IS NULL))
);

CREATE TRIGGER audit_logs_append_only
    BEFORE UPDATE OR DELETE ON audit_logs
    FOR EACH ROW EXECUTE FUNCTION forbid_mutation();
CREATE TRIGGER audit_logs_no_truncate
    BEFORE TRUNCATE ON audit_logs
    FOR EACH STATEMENT EXECUTE FUNCTION forbid_mutation();

-- ------------------------------------------- privileges (P2-H05, test env) ----
-- Runtime role: may read, and may call the single credit write function.
-- It may NOT write ledger/balance tables directly, truncate, or alter triggers.
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM PUBLIC;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA public FROM PUBLIC;
GRANT USAGE ON SCHEMA public TO app_rt;
GRANT SELECT ON student_credit_accounts, credit_transactions, credit_reconciliation TO app_rt;
GRANT EXECUTE ON FUNCTION post_credit_transaction(uuid, text, integer, uuid, uuid, text, uuid, text) TO app_rt;

COMMIT;
