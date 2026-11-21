-- WORKSPACE DB — DRAFT: exam definition versions, per-subject exam results, append-only test analysis
-- versions, and an explicit scoring algorithm version. Synthetic only (D-014). Not a migration.
-- Apply AFTER workspace_schema_draft.sql (and before or after the other Workspace drafts; it depends only
-- on the schema draft).
--
-- WHY THIS EXISTS (Batch 4)
--   `docs/phase2/workspace/ASSESSMENT_DOMAIN_CONTRACT.md` section 7 lists the structures the assessment
--   domain must include. Three were missing entirely, and one requirement had no enforcement at all:
--
--     * `exam_definition_versions` — an immutable published exam blueprint. Absent.
--     * `exam_subject_results`    — per-subject results keyed to the exact exam/student/subject, with the
--                                   aggregate reconciling against them where the blueprint requires it.
--                                   Absent: `exam_results` held only aggregate counts.
--     * `test_analysis_versions`  — append-only analysis, so that a later reclassification is a new
--                                   version rather than a silent mutation of submitted responses. Absent.
--     * an explicit scoring algorithm version. A scoring policy snapshot of `{}` was accepted, so nothing
--                                   recorded WHICH algorithm produced a score. Demonstrated before this
--                                   change: version 2 of a test definition stored `{}` and was published.
--
--   What was already correct, and is NOT re-implemented here (verified by probe, not assumed):
--     * a published `test_definition_version` is immutable and carries its exact question membership and
--       order (AVQ-01..22);
--     * responses reference a question of the attempt's exact version, enforced declaratively by composite
--       foreign keys rather than a trigger;
--     * an attempt's scoring snapshot must equal its published version's;
--     * responses are immutable once the attempt is submitted — change, delete and insert are all refused,
--       so the inputs to a score cannot drift after the fact;
--     * adaptive per-attempt delivery IS disabled: publishing a `per_attempt` version is refused with
--       "per-attempt delivery requires a separate Product Owner decision". `test_attempt_questions` from
--       the contract is therefore NOT needed for MVP and is deliberately not created.
--
-- WHAT THIS DELIBERATELY DOES NOT DECIDE
--   ASSESSMENT_DOMAIN_CONTRACT.md section 9 lists open policy inputs. None is decided here:
--     * No scoring formula, rounding rule or algorithm is implemented. The database stores and compares
--       snapshots; it never computes or validates a score. The SET of permitted algorithm names is not
--       constrained — that is a Product Owner decision, recorded as OQ-ASM-2.
--     * Whether EVERY exam requires per-subject results is not decided. It is per-blueprint data
--       (`requires_subject_results`), so the blueprint says it, not this schema.
--     * Whether analysis can be rerun, and how a version is selected or made "current", is not decided.
--       Analysis versions are append-only and carry no active/current flag.
--     * Rank, percentile and cohort comparison are not modelled. They need a cohort this Workspace may
--       not hold, and no rule for it exists.
--     * An exam blueprint is OPTIONAL on an exam (`definition_version_id` is nullable): requiring one
--       would be a product decision, and existing ad-hoc exam rows have none.
BEGIN;

-- ======================================================================================================
-- 1. An explicit scoring algorithm version, so a recorded score is attributable and reproducible.
-- ======================================================================================================
-- Reproducibility needs three things. Two already hold: the policy snapshot is immutable and must equal
-- the published version's, and the response set is immutable after submission. The third was missing —
-- nothing said which algorithm produced the number. A snapshot of `{}` was accepted.
--
-- This predicate requires the snapshot to NAME its algorithm and version. It does NOT constrain which
-- algorithms exist, because that is not this project's decision to make (OQ-ASM-2).
-- COALESCE(..., false) is not decoration. A CHECK constraint PASSES when its expression evaluates to
-- NULL, and in three-valued logic a missing key makes the whole chain NULL: for `{}`,
-- `p -> 'algorithm'` is SQL NULL, `jsonb_typeof(NULL)` is NULL, and `true AND NULL` is NULL. The first
-- version of this function returned NULL for `{}` and the constraint accepted it — exactly the trap this
-- project already hit once in workspace_governance_events_draft.sql, where payload validations used
-- `jsonb_typeof(...) <> 'string'` with no NULL handling and let a missing key through. EXM-42 asserts the
-- predicate is never NULL, which is what stops the trap returning a third time.
CREATE FUNCTION scoring_policy_is_well_formed(p jsonb) RETURNS boolean
LANGUAGE sql IMMUTABLE AS $$
  SELECT COALESCE(
           p IS NOT NULL
       AND jsonb_typeof(p) = 'object'
       AND jsonb_typeof(p -> 'algorithm') = 'string'
       AND length(btrim(COALESCE(p ->> 'algorithm',''))) > 0
       AND jsonb_typeof(p -> 'algorithm_version') = 'number'
       AND COALESCE(p ->> 'algorithm_version','') ~ '^[0-9]+$'
       AND COALESCE((p ->> 'algorithm_version')::numeric, 0) > 0
         , false)
$$;
COMMENT ON FUNCTION scoring_policy_is_well_formed(jsonb) IS
  'A scoring policy snapshot must name its algorithm and a positive integer algorithm_version. Which '
  'algorithms are permitted is NOT decided here (OQ-ASM-2). The database never computes or validates a score.';

ALTER TABLE test_definition_versions
  ADD CONSTRAINT test_definition_versions_scoring_policy_shape
  CHECK (scoring_policy_is_well_formed(scoring_policy_snapshot));
ALTER TABLE test_definitions
  ADD CONSTRAINT test_definitions_scoring_policy_shape
  CHECK (scoring_policy_is_well_formed(scoring_policy_snapshot));
ALTER TABLE test_attempts
  ADD CONSTRAINT test_attempts_scoring_policy_shape
  CHECK (scoring_policy_is_well_formed(scoring_policy_snapshot));
ALTER TABLE exams
  ADD CONSTRAINT exams_scoring_policy_shape
  CHECK (scoring_policy_is_well_formed(scoring_policy_snapshot));
ALTER TABLE exam_results
  ADD CONSTRAINT exam_results_scoring_policy_shape
  CHECK (scoring_policy_is_well_formed(scoring_policy_snapshot));

-- ======================================================================================================
-- 2. Exam definition versions — an immutable published exam blueprint.
-- ======================================================================================================
CREATE TABLE exam_definitions (
  exam_definition_id uuid PRIMARY KEY,
  title text NOT NULL CHECK (length(btrim(title))>0),
  source_label text,                      -- e.g. the external exam provider, as free text; not modelled
  created_by_membership_id uuid REFERENCES workspace_memberships(membership_id),
  created_at timestamptz NOT NULL DEFAULT now()
);

-- Published is immutable, exactly like test_definition_versions. `requires_subject_results` is how the
-- BLUEPRINT states whether per-subject rows are mandatory for this exam; the contract's open question
-- ("whether every assessment type requires per-subject results") is therefore answered per exam by whoever
-- creates the blueprint, and not by this schema.
CREATE TABLE exam_definition_versions (
  exam_version_id uuid PRIMARY KEY,
  exam_definition_id uuid NOT NULL REFERENCES exam_definitions(exam_definition_id),
  version_no integer NOT NULL CHECK (version_no>0),
  status text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','published')),
  question_count integer NOT NULL CHECK (question_count>0),
  requires_subject_results boolean NOT NULL DEFAULT false,
  scoring_policy_snapshot jsonb NOT NULL CHECK (scoring_policy_is_well_formed(scoring_policy_snapshot)),
  published_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (exam_definition_id, version_no),
  UNIQUE (exam_version_id, exam_definition_id),
  CHECK ((status='published') = (published_at IS NOT NULL))
);

-- The per-subject blueprint: which subjects the exam covers and how many questions each carries.
CREATE TABLE exam_definition_version_subjects (
  exam_version_subject_id uuid PRIMARY KEY,
  exam_version_id uuid NOT NULL REFERENCES exam_definition_versions(exam_version_id),
  subject_id uuid NOT NULL REFERENCES subjects(subject_id),
  question_count integer NOT NULL CHECK (question_count>0),
  display_order integer NOT NULL CHECK (display_order>0),
  UNIQUE (exam_version_id, subject_id),
  UNIQUE (exam_version_id, display_order),
  UNIQUE (exam_version_subject_id, exam_version_id),
  -- FK target for a per-subject result, so a result can only cite a subject of its OWN exam version.
  UNIQUE (exam_version_subject_id, exam_version_id, subject_id)
);
CREATE INDEX exam_definition_version_subjects_version_idx
  ON exam_definition_version_subjects(exam_version_id, display_order);

-- Publication rules, mirroring test_definition_version_guard: created as draft, immutable once published,
-- and a published version must be internally consistent.
CREATE FUNCTION exam_definition_version_guard() RETURNS trigger LANGUAGE plpgsql AS $body$
DECLARE n_subjects integer; sum_q integer;
BEGIN
  IF TG_OP='INSERT' THEN
    IF NEW.status<>'draft' THEN
      RAISE EXCEPTION 'an exam definition version must be created as draft' USING ERRCODE='check_violation';
    END IF;
    RETURN NEW;
  END IF;
  IF TG_OP='DELETE' THEN
    IF OLD.status='published' THEN
      RAISE EXCEPTION 'a published exam definition version cannot be deleted' USING ERRCODE='check_violation';
    END IF;
    RETURN OLD;
  END IF;
  IF OLD.status='published' THEN
    RAISE EXCEPTION 'published exam definition version is immutable' USING ERRCODE='check_violation';
  END IF;
  IF NEW.status='published' THEN
    SELECT count(*), COALESCE(sum(question_count),0) INTO n_subjects, sum_q
      FROM public.exam_definition_version_subjects WHERE exam_version_id=NEW.exam_version_id;
    -- A blueprint that demands per-subject results must say what those subjects are, and its subject
    -- question counts must add up to the exam's own count. Otherwise "reconciles with the aggregate"
    -- could never hold.
    IF NEW.requires_subject_results THEN
      IF n_subjects = 0 THEN
        RAISE EXCEPTION 'an exam version requiring per-subject results must declare at least one subject'
          USING ERRCODE='check_violation';
      END IF;
      IF sum_q <> NEW.question_count THEN
        RAISE EXCEPTION 'subject question counts sum to % but the exam version declares %', sum_q, NEW.question_count
          USING ERRCODE='check_violation';
      END IF;
    ELSIF n_subjects > 0 AND sum_q <> NEW.question_count THEN
      -- Subjects are optional, but if they are declared they must still add up.
      RAISE EXCEPTION 'declared subject question counts sum to % but the exam version declares %', sum_q, NEW.question_count
        USING ERRCODE='check_violation';
    END IF;
  END IF;
  RETURN NEW;
END; $body$;
CREATE TRIGGER exam_definition_version_guard_trg
  BEFORE INSERT OR UPDATE OR DELETE ON exam_definition_versions
  FOR EACH ROW EXECUTE FUNCTION exam_definition_version_guard();

-- The subject blueprint of a published version is immutable, for the same reason the question membership
-- of a published test version is.
CREATE FUNCTION exam_definition_version_subject_guard() RETURNS trigger LANGUAGE plpgsql AS $body$
DECLARE v_status text; v_id uuid;
BEGIN
  v_id := COALESCE(NEW.exam_version_id, OLD.exam_version_id);
  SELECT status INTO v_status FROM public.exam_definition_versions WHERE exam_version_id=v_id FOR SHARE;
  IF v_status IS DISTINCT FROM 'draft' THEN
    RAISE EXCEPTION 'subject blueprint of a published or missing exam definition version is immutable'
      USING ERRCODE='check_violation';
  END IF;
  RETURN COALESCE(NEW, OLD);
END; $body$;
CREATE TRIGGER exam_definition_version_subject_guard_trg
  BEFORE INSERT OR UPDATE OR DELETE ON exam_definition_version_subjects
  FOR EACH ROW EXECUTE FUNCTION exam_definition_version_subject_guard();

-- An exam sitting MAY cite a published blueprint. Nullable on purpose: requiring one would be a product
-- decision, and the existing ad-hoc exam rows have none.
ALTER TABLE exams
  ADD COLUMN definition_version_id uuid REFERENCES exam_definition_versions(exam_version_id);

CREATE FUNCTION exam_blueprint_must_be_published() RETURNS trigger LANGUAGE plpgsql AS $body$
DECLARE v_status text;
BEGIN
  IF NEW.definition_version_id IS NULL THEN RETURN NEW; END IF;
  SELECT status INTO v_status FROM public.exam_definition_versions
   WHERE exam_version_id=NEW.definition_version_id FOR SHARE;
  IF v_status IS DISTINCT FROM 'published' THEN
    RAISE EXCEPTION 'an exam may only cite a published exam definition version' USING ERRCODE='check_violation';
  END IF;
  RETURN NEW;
END; $body$;
CREATE TRIGGER exam_blueprint_must_be_published_trg
  BEFORE INSERT OR UPDATE OF definition_version_id ON exams
  FOR EACH ROW EXECUTE FUNCTION exam_blueprint_must_be_published();

-- ======================================================================================================
-- 3. Per-subject exam results.
-- ======================================================================================================
-- Keyed to the exact exam, student and subject. The composite foreign keys make a cross-exam or
-- cross-student subject result impossible declaratively:
--   (exam_id, student_id)                              -> the exam sitting of THAT student
--   (exam_version_subject_id, exam_version_id, subject) -> a subject of THAT exam's blueprint
CREATE TABLE exam_subject_results (
  exam_subject_result_id uuid PRIMARY KEY,
  exam_id uuid NOT NULL,
  student_id uuid NOT NULL REFERENCES students(student_id),
  exam_version_id uuid NOT NULL,
  exam_version_subject_id uuid NOT NULL,
  subject_id uuid NOT NULL REFERENCES subjects(subject_id),
  question_count integer NOT NULL CHECK (question_count>0),
  correct_count integer NOT NULL CHECK (correct_count>=0),
  wrong_count integer NOT NULL CHECK (wrong_count>=0),
  blank_count integer NOT NULL CHECK (blank_count>=0),
  score numeric(7,3),
  scoring_policy_snapshot jsonb NOT NULL CHECK (scoring_policy_is_well_formed(scoring_policy_snapshot)),
  recorded_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (exam_id, student_id) REFERENCES exams(exam_id, student_id),
  FOREIGN KEY (exam_version_subject_id, exam_version_id, subject_id)
    REFERENCES exam_definition_version_subjects(exam_version_subject_id, exam_version_id, subject_id),
  UNIQUE (exam_id, subject_id),                       -- one row per subject per sitting
  UNIQUE (exam_subject_result_id, student_id),
  -- The counts must account for every question of that subject. This one IS checkable in the row,
  -- because question_count is carried here and validated against the blueprint by the trigger below.
  CHECK (correct_count + wrong_count + blank_count = question_count)
);
CREATE INDEX exam_subject_results_student_idx ON exam_subject_results(student_id, subject_id);

-- The row-level CHECK above cannot see the blueprint, so this trigger ties question_count, the exam
-- version and the policy snapshot to the exam and its blueprint.
CREATE FUNCTION exam_subject_result_guard() RETURNS trigger LANGUAGE plpgsql AS $body$
DECLARE v_exam record; v_bp_count integer;
BEGIN
  IF TG_OP='DELETE' THEN
    RETURN OLD;
  END IF;
  -- Immutability FIRST. On an UPDATE this is the stronger statement, and checking it after the blueprint
  -- comparison would report a changed denominator as "differs from the blueprint" rather than as an
  -- attempt to amend a recorded result — a correct refusal for a misleading reason.
  IF TG_OP='UPDATE' AND (OLD.exam_id,OLD.student_id,OLD.subject_id,OLD.exam_version_id,OLD.question_count,
                         OLD.scoring_policy_snapshot)
     IS DISTINCT FROM (NEW.exam_id,NEW.student_id,NEW.subject_id,NEW.exam_version_id,NEW.question_count,
                       NEW.scoring_policy_snapshot) THEN
    RAISE EXCEPTION 'the identity, denominator and scoring snapshot of a subject result are immutable'
      USING ERRCODE='check_violation';
  END IF;
  SELECT definition_version_id, scoring_policy_snapshot INTO v_exam
    FROM public.exams WHERE exam_id=NEW.exam_id FOR SHARE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'exam % does not exist', NEW.exam_id USING ERRCODE='foreign_key_violation';
  END IF;
  IF v_exam.definition_version_id IS NULL THEN
    RAISE EXCEPTION 'per-subject results require the exam to cite a published exam definition version'
      USING ERRCODE='check_violation';
  END IF;
  IF NEW.exam_version_id IS DISTINCT FROM v_exam.definition_version_id THEN
    RAISE EXCEPTION 'subject result cites exam version % but the exam sits version %',
      NEW.exam_version_id, v_exam.definition_version_id USING ERRCODE='check_violation';
  END IF;
  -- The question count is the blueprint's, not the caller's.
  SELECT question_count INTO v_bp_count FROM public.exam_definition_version_subjects
   WHERE exam_version_subject_id=NEW.exam_version_subject_id;
  IF NEW.question_count IS DISTINCT FROM v_bp_count THEN
    RAISE EXCEPTION 'subject result declares % questions but the blueprint declares %',
      NEW.question_count, v_bp_count USING ERRCODE='check_violation';
  END IF;
  -- The policy is the exam's, snapshotted. A later policy change must not rewrite history, so the
  -- comparison is against the exam row as it stands, and both are immutable after the fact.
  IF NEW.scoring_policy_snapshot IS DISTINCT FROM v_exam.scoring_policy_snapshot THEN
    RAISE EXCEPTION 'subject result scoring policy differs from the exam policy' USING ERRCODE='check_violation';
  END IF;
  RETURN NEW;
END; $body$;
CREATE TRIGGER exam_subject_result_guard_trg
  BEFORE INSERT OR UPDATE OR DELETE ON exam_subject_results
  FOR EACH ROW EXECUTE FUNCTION exam_subject_result_guard();

-- ------------------------------------------------------------------------------------------------------
-- Reconciliation: the aggregate must equal the sum of its per-subject rows, where the blueprint requires
-- per-subject rows. DEFERRABLE INITIALLY DEFERRED because the aggregate and the subject rows arrive in
-- whatever order the writer chooses, and neither is wrong on its own mid-transaction.
--
-- NOTE for producers: a deferred constraint trigger runs at COMMIT with the CALLER's privileges. Any
-- SECURITY DEFINER command that writes these tables must therefore run
--   SET CONSTRAINTS exam_results_reconcile_trg IMMEDIATE; ... SET CONSTRAINTS ... DEFERRED;
-- inside its own security context, as the other commands in this project already do.
-- ------------------------------------------------------------------------------------------------------
CREATE FUNCTION exam_results_reconcile() RETURNS trigger LANGUAGE plpgsql AS $body$
DECLARE
  v_exam_id uuid;
  v_student uuid;
  v_agg_c integer; v_agg_w integer; v_agg_b integer;
  v_sub record;
  v_requires boolean;
  v_bp_subjects integer;
BEGIN
  v_exam_id := COALESCE(NEW.exam_id, OLD.exam_id);
  v_student := COALESCE(NEW.student_id, OLD.student_id);

  -- Does this exam's blueprint demand per-subject rows? NULL (no blueprint) means no.
  SELECT v.requires_subject_results INTO v_requires
    FROM public.exams e
    JOIN public.exam_definition_versions v ON v.exam_version_id = e.definition_version_id
   WHERE e.exam_id = v_exam_id;

  SELECT correct_count, wrong_count, blank_count
    INTO v_agg_c, v_agg_w, v_agg_b
    FROM public.exam_results WHERE exam_id=v_exam_id AND student_id=v_student;
  IF NOT FOUND THEN
    -- No aggregate row: nothing to reconcile against. The aggregate is not mandatory here, because
    -- whether an exam must have one is not this schema's decision.
    RETURN NULL;
  END IF;

  SELECT COALESCE(sum(correct_count),0) AS c, COALESCE(sum(wrong_count),0) AS w,
         COALESCE(sum(blank_count),0) AS b, count(*) AS n
    INTO v_sub
    FROM public.exam_subject_results WHERE exam_id=v_exam_id AND student_id=v_student;

  IF COALESCE(v_requires,false) THEN
    SELECT count(*) INTO v_bp_subjects FROM public.exam_definition_version_subjects s
      JOIN public.exams e ON e.definition_version_id = s.exam_version_id
     WHERE e.exam_id = v_exam_id;
    IF v_sub.n <> v_bp_subjects THEN
      RAISE EXCEPTION 'exam % student %: blueprint requires per-subject results for % subjects but % are recorded',
        v_exam_id, v_student, v_bp_subjects, v_sub.n USING ERRCODE='check_violation';
    END IF;
  END IF;

  IF v_sub.n > 0 AND (v_agg_c, v_agg_w, v_agg_b) IS DISTINCT FROM (v_sub.c, v_sub.w, v_sub.b) THEN
    RAISE EXCEPTION 'exam % student %: aggregate (%,%,%) does not reconcile with the per-subject totals (%,%,%)',
      v_exam_id, v_student, v_agg_c, v_agg_w, v_agg_b, v_sub.c, v_sub.w, v_sub.b
      USING ERRCODE='check_violation';
  END IF;
  RETURN NULL;
END; $body$;

CREATE CONSTRAINT TRIGGER exam_results_reconcile_trg
  AFTER INSERT OR UPDATE OR DELETE ON exam_results
  DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION exam_results_reconcile();
CREATE CONSTRAINT TRIGGER exam_subject_results_reconcile_trg
  AFTER INSERT OR UPDATE OR DELETE ON exam_subject_results
  DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION exam_results_reconcile();

-- ======================================================================================================
-- 4. Append-only test analysis versions.
-- ======================================================================================================
-- The contract requires that "a later reclassification is a new analysis event/version, not a silent
-- mutation of submitted responses". Submitted responses are already immutable, so a reclassification had
-- nowhere to go. These rows are that place.
--
-- NOT decided here, per contract section 9: whether analysis can be rerun, and how a version is selected
-- or exposed as "current". So there is no active/current flag and no selection rule — only an append-only
-- history with a monotonic version number.
CREATE TABLE test_analysis_versions (
  analysis_version_id uuid PRIMARY KEY,
  attempt_id uuid NOT NULL,
  student_id uuid NOT NULL,
  analysis_no integer NOT NULL CHECK (analysis_no>0),
  analyst_membership_id uuid REFERENCES workspace_memberships(membership_id),
  analysis_algorithm text NOT NULL CHECK (length(btrim(analysis_algorithm))>0),
  analysis_algorithm_version integer NOT NULL CHECK (analysis_algorithm_version>0),
  notes text,
  recorded_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (attempt_id, student_id) REFERENCES test_attempts(attempt_id, student_id),
  UNIQUE (attempt_id, analysis_no),
  UNIQUE (analysis_version_id, attempt_id)
);

-- One classification per response per analysis version. The response must belong to the analysed attempt,
-- enforced by the composite foreign key rather than by a trigger.
CREATE TABLE test_analysis_response_findings (
  finding_id uuid PRIMARY KEY,
  analysis_version_id uuid NOT NULL,
  attempt_id uuid NOT NULL,
  response_id uuid NOT NULL REFERENCES test_responses(response_id),
  error_reason text NOT NULL CHECK (error_reason IN ('concept','memory','careless','time','strategy','unknown','custom')),
  custom_error_reason text,
  FOREIGN KEY (analysis_version_id, attempt_id) REFERENCES test_analysis_versions(analysis_version_id, attempt_id),
  UNIQUE (analysis_version_id, response_id),
  CHECK ((error_reason = 'custom') = (custom_error_reason IS NOT NULL AND length(btrim(custom_error_reason))>0))
);
CREATE INDEX test_analysis_response_findings_version_idx
  ON test_analysis_response_findings(analysis_version_id);

-- Append-only, both tables. A correction is a NEW analysis version, which is the whole point.
CREATE FUNCTION test_analysis_append_only() RETURNS trigger LANGUAGE plpgsql AS $body$
BEGIN
  RAISE EXCEPTION '% is append-only: record a new analysis version instead of amending one', TG_TABLE_NAME
    USING ERRCODE='check_violation';
END; $body$;
CREATE TRIGGER test_analysis_versions_append_only
  BEFORE UPDATE OR DELETE ON test_analysis_versions
  FOR EACH ROW EXECUTE FUNCTION test_analysis_append_only();
CREATE TRIGGER test_analysis_response_findings_append_only
  BEFORE UPDATE OR DELETE ON test_analysis_response_findings
  FOR EACH ROW EXECUTE FUNCTION test_analysis_append_only();

-- An analysis may only be recorded against an attempt that has actually been submitted, and a finding may
-- only cite a response of the analysed attempt.
CREATE FUNCTION test_analysis_version_guard() RETURNS trigger LANGUAGE plpgsql AS $body$
DECLARE v_state text; v_prev integer;
BEGIN
  SELECT state INTO v_state FROM public.test_attempts WHERE attempt_id=NEW.attempt_id FOR SHARE;
  IF v_state NOT IN ('submitted','analysed') THEN
    RAISE EXCEPTION 'an attempt must be submitted before it can be analysed (state %)', v_state
      USING ERRCODE='check_violation';
  END IF;
  -- Monotonic, gapless version numbering, so "a later reclassification" has an unambiguous order.
  SELECT COALESCE(max(analysis_no),0) INTO v_prev
    FROM public.test_analysis_versions WHERE attempt_id=NEW.attempt_id;
  IF NEW.analysis_no <> v_prev + 1 THEN
    RAISE EXCEPTION 'analysis_no must be % for this attempt, got %', v_prev+1, NEW.analysis_no
      USING ERRCODE='check_violation';
  END IF;
  RETURN NEW;
END; $body$;
CREATE TRIGGER test_analysis_version_guard_trg
  BEFORE INSERT ON test_analysis_versions
  FOR EACH ROW EXECUTE FUNCTION test_analysis_version_guard();

CREATE FUNCTION test_analysis_finding_guard() RETURNS trigger LANGUAGE plpgsql AS $body$
DECLARE v_attempt uuid;
BEGIN
  SELECT attempt_id INTO v_attempt FROM public.test_responses WHERE response_id=NEW.response_id;
  IF v_attempt IS DISTINCT FROM NEW.attempt_id THEN
    RAISE EXCEPTION 'finding cites response % of attempt %, but the analysis is of attempt %',
      NEW.response_id, v_attempt, NEW.attempt_id USING ERRCODE='check_violation';
  END IF;
  RETURN NEW;
END; $body$;
CREATE TRIGGER test_analysis_finding_guard_trg
  BEFORE INSERT ON test_analysis_response_findings
  FOR EACH ROW EXECUTE FUNCTION test_analysis_finding_guard();

COMMIT;
