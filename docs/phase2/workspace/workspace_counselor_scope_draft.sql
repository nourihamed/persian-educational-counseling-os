-- WORKSPACE DB — DRAFT: the counselor-to-counselor isolation BOUNDARY (WS-ISO-01). Synthetic only (D-014).
-- NOT a migration. Apply AFTER workspace_transfer_freeze.sql (it uses student_scoped_tables and
-- resolve_student_for_barrier) and BEFORE workspace_operations_draft.sql (whose notification recipient
-- rule calls counselor_may_access_student).
--
-- WHY THIS FILE EXISTS
--   The approved rules are not in doubt:
--     * API_AUTHORIZATION_CONTRACT.md §4: "Counselor reads/writes are restricted to students with active
--       counselor assignment and action permission"; §6: "Counselor cannot read another counselor's
--       student absent explicit scope"; "Manager without specific permission cannot access restricted
--       records".
--     * PO_DECISION_ROLE_GRANTABILITY_MATRIX_2026-11-10.md: "a Counselor is confined to assigned
--       students"; "role assignment alone never grants access to all student records".
--   What the database did with those rules, measured before this file (SEC-10): NOTHING. The assignment
--   is RECORDED in counselor_assignments and CONSUMED by no read path — no row-level security, no view,
--   no function, no grant keyed to it — and the single Workspace runtime role holds SELECT on 47 tables in
--   full. Inside one Workspace, any code path holding the runtime role reads every counselor's students.
--
-- THE MISSING BOUNDARY HAS TWO HALVES, AND ONLY ONE OF THEM IS BUILT HERE
--   1. WHICH students a given counselor membership may reach. This is fully determined by approved rules
--      and the existing schema, so it is built here as one predicate, used everywhere, and tested
--      against guessed IDs, list queries, a report and related records in all 32 student-scoped tables.
--   2. WHICH membership is actually calling. The database cannot know that today: every function below
--      takes the membership as an ARGUMENT, and nothing stops a caller passing someone else's. Binding the
--      caller to a membership — per-membership database roles, or a verified signed principal assertion,
--      or something else — is a Platform Security decision that has not been made (WS-ISO-01 options).
--      Session GUCs were already rejected as an authorization mechanism in H-03, so that shortcut is not
--      taken.
--   THEREFORE WS-ISO-01 REMAINS OPEN AND BLOCKING. Half 1 is necessary and now correct; it is not
--   sufficient, and nothing here is evidence that cross-counselor reads are prevented at the database.
--
-- WHAT IS ENFORCED HERE REGARDLESS OF HALF 2
--   Write paths where the ROW ITSELF names the acting membership can be checked now, because no caller
--   identity is needed: a counselor note must be authored by a counselor assigned to that student, and
--   (in workspace_operations_draft.sql) a membership recipient of a notification about a student must be
--   able to reach that student. The second one closes a cross-counselor path that Batch 8 itself had
--   opened: until this file, ANY active member was a valid recipient for a notification about ANY student.
--
-- QUESTIONS NOT DECIDED HERE (registered under WS-ISO-01, not answered)
--   * Whether a suspended or awaiting-consent ENROLLMENT narrows a counselor's access. The approved rule
--     names the ASSIGNMENT, so the predicate does exactly that and no more.
--   * What explicit permission lets an Organization or Branch Manager reach a student. The vocabulary of
--     membership_permissions is not defined anywhere, so no manager path exists: managers are DENIED,
--     which is the contract's own default ("broad organization visibility is not implied by manager role").
BEGIN;

-- ======================================================================================================
-- 1. THE PREDICATE. Every other function in this file is built on it, so there is one definition.
-- ======================================================================================================
-- A membership may reach a student only through an assignment that is ACTIVE and ACCEPTED, held by a
-- membership that is ACTIVE and carries the counselor role. Each condition is a stated rule:
--   active          — "students with active counselor assignment";
--   accepted        — assignment change requires "destination counselor acceptance" (§4), so a proposed
--                     but unaccepted assignment grants nothing;
--   active member   — a suspended or ended membership reaches nothing;
--   counselor role  — "role assignment alone never grants access", and the converse: an assignment row
--                     pointing at a membership that is not a counselor is not a counselor assignment.
-- SECURITY INVOKER: the runtime already reads these four tables, and a definer function here would be a
-- PUBLIC-executable definer (SEC-07) for no gain.
CREATE FUNCTION counselor_may_access_student(p_membership uuid, p_student uuid) RETURNS boolean
LANGUAGE sql STABLE AS $body$
  SELECT p_membership IS NOT NULL AND p_student IS NOT NULL AND EXISTS (
    SELECT 1
      FROM public.counselor_assignments ca
      JOIN public.enrollments e          ON e.enrollment_id = ca.enrollment_id
      JOIN public.workspace_memberships m ON m.membership_id = ca.counselor_membership_id
      JOIN public.membership_roles r      ON r.membership_id = m.membership_id AND r.role_key = 'counselor'
     WHERE ca.counselor_membership_id = p_membership
       AND e.student_id = p_student
       AND ca.state = 'active'
       AND ca.accepted_at IS NOT NULL
       AND m.status = 'active');
$body$;

-- ======================================================================================================
-- 2. LIST QUERY — the caseload. A counselor's student list is exactly the predicate's true set.
-- ======================================================================================================
CREATE FUNCTION counselor_visible_students(p_membership uuid) RETURNS SETOF uuid
LANGUAGE sql STABLE AS $body$
  SELECT s.student_id FROM public.students s
   WHERE public.counselor_may_access_student(p_membership, s.student_id);
$body$;

-- ======================================================================================================
-- 3. RELATED RECORDS — any row of any student-scoped table, reached by its primary key.
-- ======================================================================================================
-- This is the guessed-ID case: a caller presents the id of a study session, a test response, a file or a
-- guardian permission, not the student's id. The owner is resolved exactly as the transfer write barrier
-- resolves it (same catalog view, same resolver), so the two boundaries cannot disagree about who owns a
-- row. Counselor notes carry one extra rule: a private_to_author note is visible to its author only, and
-- only while that author can still reach the student.
-- Three student-scoped tables have composite primary keys, and every one of them carries student_id in
-- the key (class_participants, class_session_participants, student_topic_mastery). For those the row IS
-- identified by its student, so the caller uses counselor_may_access_student directly; this function
-- refuses them rather than guessing which key column the caller meant. ISO-C2 pins that list.
CREATE FUNCTION counselor_may_access_row(p_membership uuid, p_table text, p_pk text) RETURNS boolean
LANGUAGE plpgsql STABLE AS $body$
DECLARE
  v_kind text; v_keycol text; v_pkcol text; v_npk integer; v_key uuid; v_student uuid;
  v_author uuid; v_visibility text;
BEGIN
  SELECT t.key_kind, t.key_column INTO v_kind, v_keycol
    FROM public.student_scoped_tables t WHERE t.table_name = p_table;
  IF NOT FOUND THEN
    RAISE EXCEPTION '% is not a student-scoped table; counselor scope does not apply to it', p_table
      USING ERRCODE='check_violation';
  END IF;
  SELECT count(*), min(a.attname) INTO v_npk, v_pkcol
    FROM pg_index i JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = ANY(i.indkey)
   WHERE i.indrelid = ('public.' || quote_ident(p_table))::regclass AND i.indisprimary;
  IF v_npk <> 1 THEN
    RAISE EXCEPTION '% has a composite primary key that already contains student_id; use '
                    'counselor_may_access_student with that row''s student', p_table
      USING ERRCODE='check_violation';
  END IF;

  EXECUTE format('SELECT (%I)::uuid FROM public.%I WHERE (%I)::text = $1', v_keycol, p_table, v_pkcol)
     INTO v_key USING p_pk;
  IF v_key IS NULL THEN
    -- A row that does not exist, or one with no owner yet, is not reachable. The answer is the same as
    -- for another counselor's row, so a guessed id cannot be used to learn whether a row exists.
    RETURN false;
  END IF;
  v_student := public.resolve_student_for_barrier(v_kind, v_key);
  IF NOT public.counselor_may_access_student(p_membership, v_student) THEN
    RETURN false;
  END IF;

  IF p_table = 'counselor_notes' THEN
    SELECT n.author_membership_id, n.visibility INTO v_author, v_visibility
      FROM public.counselor_notes n WHERE n.counselor_note_id::text = p_pk;
    IF v_visibility = 'private_to_author' AND v_author IS DISTINCT FROM p_membership THEN
      RETURN false;
    END IF;
  END IF;
  RETURN true;
END; $body$;

-- ======================================================================================================
-- 4. A REPORT — the shape that leaks most easily, because aggregates hide which rows they counted.
-- ======================================================================================================
-- One row per reachable student. A student the counselor cannot reach contributes nothing: no row, and
-- nothing inside any total. ISO-R1/R2 assert both.
CREATE FUNCTION counselor_caseload_report(p_membership uuid)
RETURNS TABLE (student_id uuid, study_sessions bigint, study_minutes bigint, test_attempts bigint)
LANGUAGE sql STABLE AS $body$
  SELECT v.sid,
         (SELECT count(*)                         FROM public.study_sessions ss WHERE ss.student_id = v.sid),
         (SELECT coalesce(sum(ss.actual_minutes),0) FROM public.study_sessions ss WHERE ss.student_id = v.sid),
         (SELECT count(*)                         FROM public.test_attempts ta WHERE ta.student_id = v.sid)
    FROM public.counselor_visible_students(p_membership) AS v(sid);
$body$;

-- ======================================================================================================
-- 5. A WRITE PATH THAT CAN BE ENFORCED NOW: counselor notes
-- ======================================================================================================
-- The row names its author, so no caller identity is needed to require that the author can reach the
-- student. Without this, a note about counselor A's student could be written under counselor B's name —
-- by B, or by anything holding the runtime role.
CREATE FUNCTION guard_counselor_note() RETURNS trigger LANGUAGE plpgsql AS $body$
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NOT public.counselor_may_access_student(NEW.author_membership_id, NEW.student_id) THEN
      RAISE EXCEPTION 'membership % is not an active, accepted counselor of student %; a counselor note '
                      'can only be written by a counselor assigned to that student',
                      NEW.author_membership_id, NEW.student_id USING ERRCODE='check_violation';
    END IF;
    RETURN NEW;
  END IF;
  IF TG_OP = 'UPDATE' THEN
    IF (NEW.counselor_note_id, NEW.student_id, NEW.author_membership_id, NEW.created_at)
       IS DISTINCT FROM (OLD.counselor_note_id, OLD.student_id, OLD.author_membership_id, OLD.created_at) THEN
      RAISE EXCEPTION 'a counselor note''s student, author and creation time are immutable'
        USING ERRCODE='check_violation';
    END IF;
    IF OLD.visibility = 'private_to_author' AND NEW.visibility <> 'private_to_author' THEN
      -- Widening a private note exposes it to every other counselor of the student. That is a disclosure
      -- decision, and there is no approved authority for it.
      RAISE EXCEPTION 'a private_to_author note cannot be widened to workspace_scoped'
        USING ERRCODE='check_violation';
    END IF;
  END IF;
  RETURN NEW;
END; $body$;
CREATE TRIGGER counselor_notes_scope_guard
  BEFORE INSERT OR UPDATE ON counselor_notes
  FOR EACH ROW EXECUTE FUNCTION guard_counselor_note();

COMMIT;
