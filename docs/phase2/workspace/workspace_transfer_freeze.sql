-- WORKSPACE DB — DRAFT: source-side transfer freeze and DATABASE write barrier.
-- Apply AFTER workspace_schema_draft.sql, workspace_activation_transactions.sql,
-- workspace_governance_events_draft.sql, workspace_archive_transactions.sql and
-- workspace_inbox_projection.sql. Synthetic only (D-014). Not a migration.
--
-- WHY THIS EXISTS (Batch 1, Saga contract section 3)
--   Until now the Control Plane recorded that a source freeze had happened (`source_freeze_token`,
--   `source_frozen_at` on transfer_cases) but the Workspace database enforced NOTHING. The source
--   Workspace could keep writing a student's data straight through the cutover, so the final snapshot
--   could miss writes that happened after it was taken. The contract is explicit that "a UI flag or cached
--   membership check is insufficient": the barrier has to be in the database.
--
-- WHAT IS ENFORCED HERE
--   * A durable freeze record, unique per (student, case, source generation) and per freeze token.
--   * A write barrier: every student-scoped table rejects INSERT/UPDATE/DELETE for a frozen student. The
--     guard binds every writer, including the Workspace runtime role and the SECURITY DEFINER commands,
--     because it is a row trigger and not a privilege check.
--   * An in-flight transaction barrier: the freeze command takes the student row and its enrollment rows
--     FOR UPDATE, so it cannot complete until writers already holding those rows commit or abort. Writers
--     that start afterwards see the committed freeze and are rejected. The barrier watermark records the
--     transaction id at which the barrier closed.
--   * Idempotency: the same freeze token replayed is a no-op; a DIFFERENT token for the same case,
--     student and generation is refused rather than blindly accepted.
--   * Unfreeze only before the ownership switch, only with the same token, and permanently prohibited
--     once the source has observed the switch. After the switch the freeze becomes a permanent fence.
--
-- WHAT THIS IS NOT, AND CANNOT BE
--   * This is the DATABASE half of the write barrier. "Reject new writes, background jobs, file
--     mutations, imports" also covers API, worker and export surfaces that DO NOT EXIST in this
--     repository (backend/, frontend/, scripts/ contain only .gitkeep). Those surfaces cannot be frozen
--     by Phase 2 work and are NOT claimed. What is claimed is that any of them which reaches this
--     database is refused.
--   * The database cannot see an application job queue, so `p_outstanding_work` is reported BY the
--     caller. The database only refuses to record a final barrier when that count is non-zero. It is not
--     evidence that the controller counted correctly.
--   * No freeze duration, drain timeout or SLO is invented: the contract says those need measured
--     workload decisions, and none is stored or enforced here.
--   * The freeze receipt is not signed. Signing is OQ-SAGA-1 / PS-1..PS-4 and remains deferred, so
--     nothing here may be read as proof of authenticity.
BEGIN;

-- ======================================================================================================
-- Durable freeze record
-- ======================================================================================================
CREATE TABLE student_transfer_freezes (
  freeze_id              uuid PRIMARY KEY,
  student_id             uuid NOT NULL REFERENCES students(student_id),
  case_id                uuid NOT NULL,              -- Control Plane transfer case; no cross-database FK
  freeze_token           text NOT NULL UNIQUE CHECK (length(btrim(freeze_token)) > 0),
  source_generation      bigint NOT NULL CHECK (source_generation >= 1),
  state                  text NOT NULL CHECK (state IN ('frozen','unfrozen','fenced')),
  controller_version     text NOT NULL CHECK (length(btrim(controller_version)) > 0),
  requested_at           timestamptz NOT NULL,
  barrier_completed_at   timestamptz NOT NULL,
  barrier_watermark_txid bigint NOT NULL,
  outstanding_work_at_barrier integer NOT NULL CHECK (outstanding_work_at_barrier = 0),
  unfrozen_at            timestamptz,
  unfreeze_reason        text,
  fenced_at              timestamptz,
  fenced_generation      bigint CHECK (fenced_generation IS NULL OR fenced_generation > source_generation),
  UNIQUE (student_id, case_id, source_generation),
  CHECK ((state = 'unfrozen') = (unfrozen_at IS NOT NULL)),
  CHECK ((state = 'fenced')   = (fenced_at IS NOT NULL)),
  CHECK (state <> 'fenced' OR fenced_generation IS NOT NULL)
);
-- At most one live freeze per student: a second concurrent transfer cannot freeze the same student.
CREATE UNIQUE INDEX one_live_freeze_per_student
  ON student_transfer_freezes(student_id) WHERE state IN ('frozen','fenced');
CREATE INDEX student_transfer_freezes_case ON student_transfer_freezes(case_id);

-- The record is append-mostly: identity, binding and barrier evidence can never be rewritten, and the
-- state machine is frozen -> unfrozen (pre-switch only) or frozen -> fenced (post-switch, terminal).
CREATE FUNCTION guard_student_transfer_freeze() RETURNS trigger LANGUAGE plpgsql AS $body$
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'a transfer freeze record cannot be deleted' USING ERRCODE='check_violation';
  END IF;
  IF TG_OP = 'INSERT' THEN
    IF NEW.state <> 'frozen' OR NEW.unfrozen_at IS NOT NULL OR NEW.fenced_at IS NOT NULL THEN
      RAISE EXCEPTION 'a freeze is created in the frozen state, with no unfreeze or fence metadata'
        USING ERRCODE='check_violation';
    END IF;
    RETURN NEW;
  END IF;
  IF (NEW.freeze_id, NEW.student_id, NEW.case_id, NEW.freeze_token, NEW.source_generation,
      NEW.requested_at, NEW.barrier_completed_at, NEW.barrier_watermark_txid, NEW.controller_version)
     IS DISTINCT FROM
     (OLD.freeze_id, OLD.student_id, OLD.case_id, OLD.freeze_token, OLD.source_generation,
      OLD.requested_at, OLD.barrier_completed_at, OLD.barrier_watermark_txid, OLD.controller_version) THEN
    RAISE EXCEPTION 'freeze identity, binding and barrier evidence are immutable' USING ERRCODE='check_violation';
  END IF;
  IF OLD.state = 'fenced' THEN
    RAISE EXCEPTION 'the source is permanently fenced at generation %; it cannot be unfrozen or reopened', OLD.source_generation
      USING ERRCODE='check_violation';
  END IF;
  IF OLD.state = 'unfrozen' AND NEW.state <> 'unfrozen' THEN
    RAISE EXCEPTION 'an unfrozen transfer freeze cannot be reactivated; request a new freeze'
      USING ERRCODE='check_violation';
  END IF;
  RETURN NEW;
END; $body$;
CREATE TRIGGER student_transfer_freezes_guard
  BEFORE INSERT OR UPDATE OR DELETE ON student_transfer_freezes
  FOR EACH ROW EXECUTE FUNCTION guard_student_transfer_freeze();

-- ======================================================================================================
-- The write barrier itself
-- ======================================================================================================
-- The ONE write that must pass a live barrier is the transfer outcome itself: when the source applies the
-- ownership-switch event it has to fence its own projection, and that is a write to a guarded table.
-- The exemption is a transaction-scoped row, not a session setting: a GUC would be forgeable by any caller
-- (the lesson of finding H-03), whereas only the inbox owner holds INSERT/DELETE on this table, and the row
-- is valid only inside the transaction that wrote it.
CREATE TABLE student_write_barrier_bypass (
  student_id uuid NOT NULL,
  txid       bigint NOT NULL,
  reason     text NOT NULL CHECK (reason IN ('transfer_fence_projection')),
  PRIMARY KEY (student_id, txid)
);

-- SECURITY DEFINER on purpose: the barrier must be evaluated for EVERY writer, and a writer must not need
-- read access to the freeze tables to be stopped by them. It returns void or raises; it discloses only the
-- fact that the student is frozen, which the writer needs in order to understand the refusal.
CREATE FUNCTION assert_student_not_frozen(p_student_id uuid) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=pg_catalog,pg_temp
AS $body$
DECLARE f public.student_transfer_freezes%ROWTYPE;
BEGIN
  IF p_student_id IS NULL THEN RETURN; END IF;
  IF EXISTS (SELECT 1 FROM public.student_write_barrier_bypass b
              WHERE b.student_id = p_student_id AND b.txid = txid_current()) THEN
    RETURN;   -- the transfer outcome being recorded by the inbox, inside its own transaction
  END IF;

  -- THE TRANSACTION BARRIER. Every writer of this student takes a SHARE lock on the student row and holds
  -- it until its own transaction ends. freeze_student_for_transfer() takes the same row FOR UPDATE, so:
  --   * writers already in flight must settle before the freeze can complete - they are drained, not lost;
  --   * writers that arrive while the freeze is committing wait here and then meet the committed freeze,
  --     so none of them can slip past the barrier watermark.
  -- Without this lock the freeze would complete while in-flight transactions were still writing, and a
  -- snapshot taken at the barrier could miss their rows. A flag check alone cannot provide this.
  PERFORM 1 FROM public.students WHERE student_id = p_student_id FOR SHARE;

  SELECT * INTO f FROM public.student_transfer_freezes
   WHERE student_id = p_student_id AND state IN ('frozen','fenced')
   LIMIT 1;
  IF NOT FOUND THEN RETURN; END IF;
  IF f.state = 'fenced' THEN
    RAISE EXCEPTION 'student % left this Workspace at generation %; local writes are permanently fenced',
      p_student_id, f.fenced_generation USING ERRCODE='check_violation';
  END IF;
  RAISE EXCEPTION 'student % is frozen for transfer case % at generation %; writes are refused until the transfer is aborted or completed',
    p_student_id, f.case_id, f.source_generation USING ERRCODE='check_violation';
END; $body$;

-- TG_ARGV[0] is the column that identifies the student, and TG_ARGV[1] says how to read it:
--   'student'    the column IS the student id
--   'enrollment' the column is an enrollment id and the student is resolved through it
-- The indirect form matters: counselor_assignments, activation_command_log and archive_command_log belong
-- to a student only through their enrollment. A first version of this barrier scanned for a student_id
-- column alone and left those three writable during a freeze; test FRZ-18 caught it.
-- The resolution itself, factored out so the barrier can resolve BOTH sides of an UPDATE. Deliberately
-- SECURITY INVOKER: it runs as the writer, exactly as the inline resolution it replaced did, so no writer
-- gains read access it did not already have.
CREATE FUNCTION resolve_student_for_barrier(p_kind text, p_key uuid) RETURNS uuid
LANGUAGE plpgsql AS $body$
DECLARE v_student uuid;
BEGIN
  IF p_key IS NULL THEN RETURN NULL; END IF;
  IF p_kind = 'enrollment' THEN
    SELECT e.student_id INTO v_student FROM public.enrollments e WHERE e.enrollment_id = p_key;
  ELSIF p_kind = 'plan' THEN
    -- student_plan_versions reaches its student only through student_plans. Added 2026-11-15; see below.
    SELECT p.student_id INTO v_student FROM public.student_plans p WHERE p.plan_id = p_key;
  ELSIF p_kind = 'attempt' THEN
    -- test_responses reaches its student only through test_attempts. Added 2026-11-15; see below.
    SELECT a.student_id INTO v_student FROM public.test_attempts a WHERE a.attempt_id = p_key;
  ELSIF p_kind = 'guardian_link' THEN
    -- guardian_permissions and guardian_link_events reach the student through the link.
    SELECT l.student_id INTO v_student FROM public.student_guardian_links l WHERE l.link_id = p_key;
  ELSIF p_kind = 'guardian_permission' THEN
    -- guardian_permission_events are two hops out: permission -> link -> student.
    SELECT l.student_id INTO v_student
      FROM public.guardian_permissions gp
      JOIN public.student_guardian_links l ON l.link_id = gp.guardian_link_id
     WHERE gp.permission_id = p_key;
  ELSE
    v_student := p_key;
  END IF;
  RETURN v_student;
END; $body$;

-- THE BARRIER HAS TO LOOK AT BOTH SIDES OF AN UPDATE — A DEFECT FOUND AND MEASURED IN BATCH 8.
-- The first version of this function resolved the owner from NEW on INSERT and UPDATE and from OLD only on
-- DELETE. A DELETE of a frozen student's row was therefore refused, but an UPDATE that REWROTE the
-- ownership column was evaluated against its DESTINATION. Measured on a loaded database with student
-- e8..01 frozen, all three of these were ACCEPTED:
--     UPDATE private_file_objects SET student_id = <other student> WHERE file_id = <frozen student's file>
--     UPDATE study_sessions       SET student_id = <other student> WHERE study_session_id = <frozen row>
--     UPDATE private_file_objects SET student_id = NULL            WHERE file_id = <frozen student's file>
-- The third worked because assert_student_not_frozen(NULL) returns, so a NULL destination was a universal
-- escape. What that costs is exactly the property Batch 1 claimed to establish: rows could LEAVE a frozen
-- student's dataset after the barrier watermark, so the snapshot the destination imports is not the
-- snapshot the source froze, and nothing downstream would notice, because the source's own tables stay
-- self-consistent.
-- Two rules are enforced now:
--   1. an UPDATE is asserted against the OLD owner as well as the NEW one;
--   2. the ownership key of a guarded row is forward-only: NULL -> value is allowed (a row that acquires
--      its owner later), while value -> other value and value -> NULL are refused for every writer,
--      frozen or not. No path in this repository re-points a guarded row at another student, so this
--      forbids nothing that exists; it removes the class rather than the one demonstrated instance.
CREATE FUNCTION student_write_barrier() RETURNS trigger LANGUAGE plpgsql AS $body$
DECLARE v_old_key uuid; v_new_key uuid; v_old uuid; v_new uuid;
BEGIN
  IF TG_OP <> 'INSERT' THEN
    EXECUTE format('SELECT ($1).%I', TG_ARGV[0]) INTO v_old_key USING OLD;
    v_old := public.resolve_student_for_barrier(TG_ARGV[1], v_old_key);
  END IF;
  IF TG_OP <> 'DELETE' THEN
    EXECUTE format('SELECT ($1).%I', TG_ARGV[0]) INTO v_new_key USING NEW;
    v_new := public.resolve_student_for_barrier(TG_ARGV[1], v_new_key);
  END IF;

  -- The freeze is asserted FIRST and on both sides, so that a frozen student's row is refused with the
  -- freeze reason rather than the weaker ownership reason. NULL is a no-op inside the assertion; both
  -- calls are made so an UPDATE spanning two students is refused when EITHER of them is frozen.
  PERFORM public.assert_student_not_frozen(v_old);
  IF v_new IS DISTINCT FROM v_old THEN
    PERFORM public.assert_student_not_frozen(v_new);
  END IF;

  IF TG_OP = 'UPDATE' AND v_old_key IS NOT NULL AND v_new_key IS DISTINCT FROM v_old_key THEN
    RAISE EXCEPTION
      'the ownership key %.% is forward-only: a row already bound to a student cannot be re-pointed or cleared',
      TG_TABLE_NAME, TG_ARGV[0] USING ERRCODE='check_violation';
  END IF;
  RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END; $body$;

-- Every student-scoped table in this database gets the barrier. The list is derived from the catalog so a
-- table added later without a barrier is visible as a gap rather than silently unprotected (see the
-- coverage view and FRZ-01/FRZ-02 below).
--
-- student_transfer_freezes and student_write_barrier_bypass are excluded for an obvious reason: the freeze
-- commands and the inbox fence must be able to write them WHILE a student is frozen. Both are unreachable
-- for every ordinary identity, so excluding them opens no write surface.
--
-- THE HARD PART IS KNOWING WHICH TABLES ARE STUDENT-SCOPED.
-- Scanning for a student_id or enrollment_id column is not enough, and this project has now been caught by
-- that twice. Batch 1: counselor_assignments, activation_command_log and archive_command_log reach a
-- student only through an enrollment (FRZ-18). Batch 5: student_plan_versions reaches its student only
-- through student_plans, and test_responses only through test_attempts — so a frozen student's plan
-- versions and test responses could still be written straight through cutover. Both are listed explicitly
-- below, and FRZ-02 now audits indirect reachability from the catalog so a third one fails the suite by
-- name instead of being missed.
CREATE VIEW student_scoped_tables AS
  SELECT c.relname AS table_name,
         CASE WHEN EXISTS (SELECT 1 FROM pg_attribute a
                            WHERE a.attrelid = c.oid AND a.attname = 'student_id' AND a.attnum > 0)
              THEN 'student_id' ELSE 'enrollment_id' END AS key_column,
         CASE WHEN EXISTS (SELECT 1 FROM pg_attribute a
                            WHERE a.attrelid = c.oid AND a.attname = 'student_id' AND a.attnum > 0)
              THEN 'student' ELSE 'enrollment' END AS key_kind
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname = 'public' AND c.relkind = 'r'
     AND c.relname NOT IN ('student_transfer_freezes','student_write_barrier_bypass','enrollments')
     AND EXISTS (SELECT 1 FROM pg_attribute a
                  WHERE a.attrelid = c.oid AND a.attnum > 0
                    AND a.attname IN ('student_id','enrollment_id'))
   UNION ALL
  SELECT 'enrollments', 'student_id', 'student'
   UNION ALL
  -- Per-student tables that carry neither key column. Each is listed with the column that reaches its
  -- owner and the resolution path student_write_barrier() must use.
  SELECT 'student_plan_versions', 'plan_id', 'plan'
   WHERE to_regclass('public.student_plan_versions') IS NOT NULL
   UNION ALL
  SELECT 'test_responses', 'attempt_id', 'attempt'
   WHERE to_regclass('public.test_responses') IS NOT NULL
   UNION ALL
  -- Guardian authority is per-student too. A frozen student's guardian permissions must not change
  -- mid-cutover: the destination Workspace would then import a different authority set than the one the
  -- source froze. Found by the FRZ-01b indirect-reachability audit on 2026-11-15, immediately after that
  -- audit was written to catch exactly this.
  SELECT 'guardian_permissions', 'guardian_link_id', 'guardian_link'
   WHERE to_regclass('public.guardian_permissions') IS NOT NULL
   UNION ALL
  SELECT 'guardian_link_events', 'link_id', 'guardian_link'
   WHERE to_regclass('public.guardian_link_events') IS NOT NULL
   UNION ALL
  SELECT 'guardian_permission_events', 'permission_id', 'guardian_permission'
   WHERE to_regclass('public.guardian_permission_events') IS NOT NULL;

DO $install$
DECLARE r record;
BEGIN
  FOR r IN SELECT table_name, key_column, key_kind FROM public.student_scoped_tables ORDER BY table_name
  LOOP
    EXECUTE format(
      'CREATE TRIGGER %I BEFORE INSERT OR UPDATE OR DELETE ON public.%I
         FOR EACH ROW EXECUTE FUNCTION public.student_write_barrier(%L, %L)',
      'zz_transfer_write_barrier_' || r.table_name, r.table_name, r.key_column, r.key_kind);
  END LOOP;
END
$install$;

-- Which student-scoped tables carry the barrier, and which do not. A row with has_barrier = false is a
-- hole in the write barrier and must be treated as a defect, not as an exemption.
CREATE VIEW student_write_barrier_coverage AS
  SELECT s.table_name, s.key_column, s.key_kind,
         EXISTS (SELECT 1 FROM pg_trigger t
                   JOIN pg_class c ON c.oid = t.tgrelid
                   JOIN pg_namespace n ON n.oid = c.relnamespace
                  WHERE n.nspname = 'public' AND c.relname = s.table_name
                    AND NOT t.tgisinternal
                    AND t.tgname = 'zz_transfer_write_barrier_' || s.table_name) AS has_barrier
    FROM public.student_scoped_tables s;

-- ======================================================================================================
-- Commands. The controller identity is the only caller; the Workspace runtime cannot freeze or unfreeze.
-- ======================================================================================================
-- Returns 'frozen' on the first call and 'replayed' when the SAME token is presented again.
CREATE FUNCTION freeze_student_for_transfer(
  p_freeze_id         uuid,
  p_freeze_token      text,
  p_student_id        uuid,
  p_case_id           uuid,
  p_source_generation bigint,
  p_controller_version text,
  p_outstanding_work  integer,
  p_requested_at      timestamptz
) RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=pg_catalog,pg_temp
AS $$
DECLARE
  v_existing public.student_transfer_freezes%ROWTYPE;
  v_local_generation bigint; v_now timestamptz; v_lifecycle text;
BEGIN
  IF p_freeze_id IS NULL OR p_freeze_token IS NULL OR length(btrim(p_freeze_token)) = 0
     OR p_student_id IS NULL OR p_case_id IS NULL OR p_source_generation IS NULL
     OR p_source_generation < 1 OR p_controller_version IS NULL OR p_outstanding_work IS NULL
     OR p_requested_at IS NULL THEN
    RAISE EXCEPTION 'freeze command arguments are invalid' USING ERRCODE='invalid_parameter_value';
  END IF;

  -- IN-FLIGHT TRANSACTION BARRIER. Taking the student row and every enrollment row FOR UPDATE means this
  -- command cannot complete while another transaction still holds them. Writers that began earlier settle
  -- first; writers that begin afterwards meet the committed freeze and are refused by the barrier trigger.
  SELECT lifecycle_state INTO v_lifecycle FROM public.students WHERE student_id = p_student_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'student % is not projected in this Workspace', p_student_id USING ERRCODE='foreign_key_violation';
  END IF;
  PERFORM 1 FROM public.enrollments WHERE student_id = p_student_id FOR UPDATE;

  SELECT * INTO v_existing FROM public.student_transfer_freezes
   WHERE freeze_token = p_freeze_token FOR UPDATE;
  IF FOUND THEN
    IF v_existing.student_id IS DISTINCT FROM p_student_id
       OR v_existing.case_id IS DISTINCT FROM p_case_id
       OR v_existing.source_generation IS DISTINCT FROM p_source_generation
       OR v_existing.freeze_id IS DISTINCT FROM p_freeze_id THEN
      RAISE EXCEPTION 'freeze token % is already bound to a different case, student or generation', p_freeze_token
        USING ERRCODE='unique_violation';
    END IF;
    RETURN 'replayed';
  END IF;

  -- A different token for the same case/student/generation is refused: the contract forbids issuing a new
  -- freeze token blindly when a freeze may already be in progress.
  IF EXISTS (SELECT 1 FROM public.student_transfer_freezes
              WHERE student_id = p_student_id AND case_id = p_case_id
                AND source_generation = p_source_generation) THEN
    RAISE EXCEPTION 'a freeze already exists for this case, student and generation under a different token; query the controller by its stable command id instead'
      USING ERRCODE='unique_violation';
  END IF;

  -- Fail closed on a stale generation: the caller's view of ownership must match the local projection.
  SELECT max(ownership_generation) INTO v_local_generation
    FROM public.enrollments WHERE student_id = p_student_id;
  IF v_local_generation IS NULL THEN
    RAISE EXCEPTION 'student % has no local enrollment to freeze', p_student_id USING ERRCODE='check_violation';
  END IF;
  IF p_source_generation <> v_local_generation THEN
    RAISE EXCEPTION 'freeze requested at generation % but this Workspace projects generation %; refusing a freeze on a stale view',
      p_source_generation, v_local_generation USING ERRCODE='check_violation';
  END IF;

  -- The database cannot see the controller's job queue. It only refuses to record a FINAL barrier whose
  -- reported outstanding work is non-zero; a non-zero count means the drain is not finished.
  IF p_outstanding_work <> 0 THEN
    RAISE EXCEPTION 'the final write barrier requires zero outstanding work, the controller reported %', p_outstanding_work
      USING ERRCODE='check_violation';
  END IF;

  v_now := clock_timestamp();
  INSERT INTO public.student_transfer_freezes(
    freeze_id, student_id, case_id, freeze_token, source_generation, state, controller_version,
    requested_at, barrier_completed_at, barrier_watermark_txid, outstanding_work_at_barrier)
  VALUES (p_freeze_id, p_student_id, p_case_id, p_freeze_token, p_source_generation, 'frozen',
          p_controller_version, p_requested_at, v_now, txid_current(), p_outstanding_work);

  INSERT INTO public.audit_events(audit_event_id, actor_membership_id, event_type, target_type, target_id,
                                  outcome, correlation_id, metadata)
  VALUES (gen_random_uuid(), NULL, 'transfer.source_freeze', 'student', p_student_id, 'success',
          p_freeze_token,
          jsonb_build_object('case_id', p_case_id, 'source_generation', p_source_generation,
                             'barrier_watermark_txid', txid_current(),
                             'controller_version', p_controller_version,
                             'signed_receipt', false));
  RETURN 'frozen';
END;
$$;

-- Unfreeze is a pre-switch abort path only. Once the source has observed the ownership switch, the freeze
-- is a permanent fence and this command refuses.
CREATE FUNCTION unfreeze_student_after_abort(
  p_freeze_token text,
  p_case_id      uuid,
  p_reason_code  text
) RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=pg_catalog,pg_temp
AS $$
DECLARE f public.student_transfer_freezes%ROWTYPE; v_now timestamptz; v_switched bigint;
BEGIN
  IF p_freeze_token IS NULL OR p_case_id IS NULL OR p_reason_code IS NULL OR length(btrim(p_reason_code)) = 0 THEN
    RAISE EXCEPTION 'unfreeze command arguments are invalid' USING ERRCODE='invalid_parameter_value';
  END IF;
  SELECT * INTO f FROM public.student_transfer_freezes WHERE freeze_token = p_freeze_token FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'no freeze exists for token %', p_freeze_token USING ERRCODE='no_data_found';
  END IF;
  IF f.case_id IS DISTINCT FROM p_case_id THEN
    RAISE EXCEPTION 'freeze token % belongs to another transfer case', p_freeze_token USING ERRCODE='insufficient_privilege';
  END IF;
  IF f.state = 'unfrozen' THEN RETURN 'replayed'; END IF;
  IF f.state = 'fenced' THEN
    RAISE EXCEPTION 'the ownership switch has already been applied; unfreeze is prohibited after the switch'
      USING ERRCODE='check_violation';
  END IF;

  -- Independent of the fence flag: if this Workspace has already applied an event at a newer generation,
  -- the switch happened and unfreeze must be refused even if the fence was not recorded yet.
  SELECT max(ownership_generation) INTO v_switched
    FROM public.workspace_inbox_events
   WHERE platform_student_id = (SELECT platform_student_id FROM public.students WHERE student_id = f.student_id)
     AND outcome = 'applied' AND ownership_generation > f.source_generation;
  IF v_switched IS NOT NULL THEN
    RAISE EXCEPTION 'this Workspace has already applied generation %; unfreeze is prohibited after the switch', v_switched
      USING ERRCODE='check_violation';
  END IF;

  v_now := clock_timestamp();
  UPDATE public.student_transfer_freezes
     SET state = 'unfrozen', unfrozen_at = v_now, unfreeze_reason = p_reason_code
   WHERE freeze_id = f.freeze_id;
  INSERT INTO public.audit_events(audit_event_id, actor_membership_id, event_type, target_type, target_id,
                                  outcome, correlation_id, metadata)
  VALUES (gen_random_uuid(), NULL, 'transfer.source_unfreeze', 'student', f.student_id, 'success',
          p_freeze_token, jsonb_build_object('case_id', f.case_id, 'reason_code', p_reason_code));
  RETURN 'unfrozen';
END;
$$;

REVOKE ALL ON FUNCTION freeze_student_for_transfer(uuid,text,uuid,uuid,bigint,text,integer,timestamptz) FROM PUBLIC;
REVOKE ALL ON FUNCTION unfreeze_student_after_abort(text,uuid,text) FROM PUBLIC;
-- Every writer reaches this through its table's barrier trigger, so EXECUTE stays open; the privilege
-- that matters is who may CREATE or REMOVE a freeze, not who may be refused by one.
GRANT EXECUTE ON FUNCTION assert_student_not_frozen(uuid) TO PUBLIC;

COMMIT;
