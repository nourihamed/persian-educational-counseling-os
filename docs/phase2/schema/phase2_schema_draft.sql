-- =============================================================================
-- PHASE 2 — DDL DRAFT (PostgreSQL 15+)
-- Status: DRAFT. Not a migration. Not approved. Not PR-reviewed.
-- Purpose: make the Phase 2 constraint rules concrete and executable so that
--          they can be verified against a real database (see phase2_constraint_tests.sql).
-- Data: synthetic only (D-014).
-- Tenant rule: every tenant-owned table has tenant_id NOT NULL; cross-tenant
--          references use composite foreign keys (tenant_id, id).
-- Out of scope: users/auth tables (Phase 4), payment gateway, RLS (defense in
--          depth only, not in this draft), indexes beyond those needed for constraints.
-- =============================================================================

BEGIN;

-- ---------------------------------------------------------------- tenancy ----
CREATE TABLE tenants (
    id          uuid PRIMARY KEY,
    status      text NOT NULL CHECK (status IN ('active', 'suspended', 'closed')),
    created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE counselors (
    id              uuid PRIMARY KEY,
    tenant_id       uuid NOT NULL REFERENCES tenants (id),
    display_name    text NOT NULL,
    deactivated_at  timestamptz,
    created_at      timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id)
);

CREATE TABLE students (
    id          uuid PRIMARY KEY,
    tenant_id   uuid NOT NULL REFERENCES tenants (id),
    status      text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'archived')),
    created_at  timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id)
);

CREATE TABLE student_profiles (
    student_id      uuid PRIMARY KEY,
    tenant_id       uuid NOT NULL,
    full_name       text NOT NULL,
    birth_date      date,              -- nullable: not known at intake
    grade           text,
    field           text,
    school          text,
    goal            text,
    updated_at      timestamptz NOT NULL DEFAULT now(),
    FOREIGN KEY (tenant_id, student_id) REFERENCES students (tenant_id, id)
);

CREATE TABLE counselor_students (
    id          uuid PRIMARY KEY,
    tenant_id   uuid NOT NULL REFERENCES tenants (id),
    counselor_id uuid NOT NULL,
    student_id  uuid NOT NULL,
    status      text NOT NULL CHECK (status IN ('active', 'paused', 'archived', 'ended')),
    started_at  timestamptz NOT NULL,
    ended_at    timestamptz,
    notes       text,
    created_at  timestamptz NOT NULL DEFAULT now(),
    CHECK (ended_at IS NULL OR ended_at >= started_at),
    FOREIGN KEY (tenant_id, counselor_id) REFERENCES counselors (tenant_id, id),
    FOREIGN KEY (tenant_id, student_id)   REFERENCES students (tenant_id, id)
);
-- A student has at most one active counselor relationship per tenant.
CREATE UNIQUE INDEX counselor_students_one_active
    ON counselor_students (tenant_id, student_id) WHERE status = 'active';

-- --------------------------------------------------------------- subjects ----
CREATE TABLE subjects (
    id          uuid PRIMARY KEY,
    tenant_id   uuid NOT NULL REFERENCES tenants (id),
    name        text NOT NULL,
    is_active   boolean NOT NULL DEFAULT true,
    UNIQUE (tenant_id, id)
);
CREATE UNIQUE INDEX subjects_active_name
    ON subjects (tenant_id, name) WHERE is_active;

-- --------------------------------------------------- programs (D-008/D-012) --
CREATE TABLE program_templates (
    id          uuid PRIMARY KEY,
    tenant_id   uuid NOT NULL REFERENCES tenants (id),
    name        text NOT NULL,
    status      text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'archived')),
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
    payload             jsonb NOT NULL,
    created_at          timestamptz NOT NULL DEFAULT now(),
    published_at        timestamptz,
    CHECK (status = 'draft' OR published_at IS NOT NULL),
    UNIQUE (tenant_id, program_template_id, version_number),
    UNIQUE (tenant_id, id),
    FOREIGN KEY (tenant_id, program_template_id)
        REFERENCES program_templates (tenant_id, id)
);

-- Published versions are immutable. Only status may move published -> superseded.
-- Published rows cannot be deleted.
CREATE FUNCTION program_versions_guard() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        IF OLD.status <> 'draft' THEN
            RAISE EXCEPTION 'published program_version % cannot be deleted', OLD.id
                USING ERRCODE = 'check_violation';
        END IF;
        RETURN OLD;
    END IF;

    IF OLD.status = 'draft' THEN
        RETURN NEW;
    END IF;

    IF (NEW.tenant_id, NEW.program_template_id, NEW.version_number, NEW.payload,
        NEW.published_at, NEW.created_at)
       IS DISTINCT FROM
       (OLD.tenant_id, OLD.program_template_id, OLD.version_number, OLD.payload,
        OLD.published_at, OLD.created_at)
    THEN
        RAISE EXCEPTION 'published program_version % is immutable', OLD.id
            USING ERRCODE = 'check_violation';
    END IF;

    IF NOT (OLD.status = 'published' AND NEW.status = 'superseded') AND NEW.status <> OLD.status THEN
        RAISE EXCEPTION 'illegal status transition % -> % for program_version %',
            OLD.status, NEW.status, OLD.id USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER program_versions_guard_trg
    BEFORE UPDATE OR DELETE ON program_versions
    FOR EACH ROW EXECUTE FUNCTION program_versions_guard();

CREATE TABLE student_program_enrollments (
    id                  uuid PRIMARY KEY,
    tenant_id           uuid NOT NULL REFERENCES tenants (id),
    student_id          uuid NOT NULL,
    program_version_id  uuid NOT NULL,
    enrolled_at         timestamptz NOT NULL DEFAULT now(),
    ended_at            timestamptz,
    CHECK (ended_at IS NULL OR ended_at >= enrolled_at),
    FOREIGN KEY (tenant_id, student_id)        REFERENCES students (tenant_id, id),
    FOREIGN KEY (tenant_id, program_version_id) REFERENCES program_versions (tenant_id, id)
);
-- O-9 (proposed): one active program enrollment per student at a time.
CREATE UNIQUE INDEX enrollments_one_active
    ON student_program_enrollments (tenant_id, student_id) WHERE ended_at IS NULL;

-- ---------------------------------------------------- planning (D-008) -------
CREATE TABLE plans (
    id            uuid PRIMARY KEY,
    tenant_id     uuid NOT NULL REFERENCES tenants (id),
    student_id    uuid NOT NULL,
    scope         text NOT NULL CHECK (scope IN
                    ('daily', 'weekly', 'monthly', 'exam', 'review', 'recovery')),
    period_start  date NOT NULL,
    period_end    date NOT NULL,
    created_at    timestamptz NOT NULL DEFAULT now(),
    CHECK (period_end >= period_start),
    UNIQUE (tenant_id, id),
    FOREIGN KEY (tenant_id, student_id) REFERENCES students (tenant_id, id)
);

CREATE TABLE plan_versions (
    id                  uuid PRIMARY KEY,
    tenant_id           uuid NOT NULL REFERENCES tenants (id),
    plan_id             uuid NOT NULL,
    version_number      integer NOT NULL CHECK (version_number > 0),
    program_version_id  uuid,                 -- nullable: plan may not derive from a program
    created_at          timestamptz NOT NULL DEFAULT now(),
    activated_at        timestamptz,
    superseded_at       timestamptz,
    CHECK (superseded_at IS NULL OR activated_at IS NOT NULL),
    CHECK (superseded_at IS NULL OR superseded_at >= activated_at),
    UNIQUE (tenant_id, plan_id, version_number),
    UNIQUE (tenant_id, id),
    FOREIGN KEY (tenant_id, plan_id)            REFERENCES plans (tenant_id, id),
    -- MATCH SIMPLE: when program_version_id IS NULL the check is skipped.
    FOREIGN KEY (tenant_id, program_version_id) REFERENCES program_versions (tenant_id, id)
);
-- At most one active version per plan.
CREATE UNIQUE INDEX plan_versions_one_active
    ON plan_versions (tenant_id, plan_id)
    WHERE activated_at IS NOT NULL AND superseded_at IS NULL;

CREATE TABLE plan_items (
    id                uuid PRIMARY KEY,
    tenant_id         uuid NOT NULL REFERENCES tenants (id),
    plan_version_id   uuid NOT NULL,
    activity_type     text NOT NULL,
    subject_id        uuid,
    scheduled_start   timestamptz NOT NULL,
    scheduled_end     timestamptz NOT NULL,
    rationale         jsonb NOT NULL DEFAULT '[]'::jsonb,   -- explainability (Master §68)
    CHECK (scheduled_end > scheduled_start),
    FOREIGN KEY (tenant_id, plan_version_id) REFERENCES plan_versions (tenant_id, id),
    FOREIGN KEY (tenant_id, subject_id)      REFERENCES subjects (tenant_id, id)
);

-- ---------------------------------------------------- activities (sample) ----
-- Base table + type tables (O-4). Type tables use the composite key
-- (tenant_id, activity_id, activity_type) so a row can only extend an activity
-- of the matching type and the same tenant.
CREATE TABLE activities (
    id            uuid PRIMARY KEY,
    tenant_id     uuid NOT NULL REFERENCES tenants (id),
    student_id    uuid NOT NULL,
    activity_type text NOT NULL CHECK (activity_type IN ('study', 'test', 'review', 'exam', 'class', 'assignment')),
    subject_id    uuid,
    occurred_on   date NOT NULL,
    created_at    timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id, activity_type),
    FOREIGN KEY (tenant_id, student_id) REFERENCES students (tenant_id, id),
    FOREIGN KEY (tenant_id, subject_id) REFERENCES subjects (tenant_id, id)
);

CREATE TABLE test_records (
    activity_id     uuid PRIMARY KEY,
    tenant_id       uuid NOT NULL,
    activity_type   text NOT NULL DEFAULT 'test' CHECK (activity_type = 'test'),
    question_count  integer NOT NULL CHECK (question_count > 0),
    correct         integer NOT NULL CHECK (correct >= 0),
    wrong           integer NOT NULL CHECK (wrong >= 0),
    unanswered      integer NOT NULL CHECK (unanswered >= 0),
    -- Strict by default (§23). Override path is O-5 and is NOT modelled here.
    CHECK (correct + wrong + unanswered = question_count),
    FOREIGN KEY (tenant_id, activity_id, activity_type)
        REFERENCES activities (tenant_id, id, activity_type)
);

CREATE TABLE review_schedules (
    id                    uuid PRIMARY KEY,
    tenant_id             uuid NOT NULL REFERENCES tenants (id),
    original_activity_id  uuid NOT NULL,
    original_type         text NOT NULL,
    review_offset_days    integer NOT NULL CHECK (review_offset_days > 0),
    review_date           date NOT NULL,
    result                text,
    -- DB-level duplicate prevention for review generation (DATABASE.md).
    UNIQUE (tenant_id, original_activity_id, review_offset_days),
    FOREIGN KEY (tenant_id, original_activity_id, original_type)
        REFERENCES activities (tenant_id, id, activity_type)
);

-- ---------------------------------------------------- credit ledger (§45) ----
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
    idempotency_key  text NOT NULL,
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

-- Append-only: no UPDATE/DELETE at the application role (see GRANTs in tests).
CREATE FUNCTION append_only_guard() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION '% is append-only', TG_TABLE_NAME USING ERRCODE = 'check_violation';
END;
$$;

CREATE TRIGGER credit_transactions_append_only
    BEFORE UPDATE OR DELETE ON credit_transactions
    FOR EACH ROW EXECUTE FUNCTION append_only_guard();

-- --------------------------------------------------------------- audit -------
CREATE TABLE audit_logs (
    id           uuid PRIMARY KEY,
    tenant_id    uuid REFERENCES tenants (id),          -- NULL only for platform actions
    actor_id     uuid,
    action       text NOT NULL,
    entity_type  text NOT NULL,
    entity_id    uuid,
    before_json  jsonb,
    after_json   jsonb,
    created_at   timestamptz NOT NULL DEFAULT now()
);

CREATE TRIGGER audit_logs_append_only
    BEFORE UPDATE OR DELETE ON audit_logs
    FOR EACH ROW EXECUTE FUNCTION append_only_guard();

COMMIT;
