-- WORKSPACE DB — DRAFT: atomic student archive (offboarding) with capacity release. Synthetic only (D-014).
-- Apply after workspace_schema_draft.sql and workspace_activation_transactions.sql. Not a production migration.
-- Implements the "Archive/offboarding" row of CAPACITY_LIFECYCLE_CONTRACT.md:
--   release exactly one active-student slot atomically with the archive state; keep the historical enrollment.
-- NOT decided here (open Product Owner decisions, deliberately not implemented):
--   * credit treatment on archive (no refund, no reversal is made by this command);
--   * reactivation (capacity re-reservation and CRD policy);
--   * capacity treatment of a SUSPENDED enrollment (this command refuses to archive from 'suspended').
BEGIN;

CREATE TABLE archive_command_log (
  idempotency_key text PRIMARY KEY CHECK (length(btrim(idempotency_key))>0),
  enrollment_id uuid NOT NULL REFERENCES enrollments(enrollment_id),
  expected_generation bigint NOT NULL CHECK (expected_generation>=1),
  actor_membership_id uuid NOT NULL REFERENCES workspace_memberships(membership_id),
  reason_code text NOT NULL CHECK (length(btrim(reason_code))>0),
  recorded_at timestamptz NOT NULL DEFAULT now()
);
CREATE FUNCTION reject_archive_command_mutation() RETURNS trigger LANGUAGE plpgsql AS $body$
BEGIN
  RAISE EXCEPTION 'archive command log is append-only' USING ERRCODE='check_violation';
END; $body$;
CREATE TRIGGER archive_command_log_append_only BEFORE UPDATE OR DELETE ON archive_command_log
  FOR EACH ROW EXECUTE FUNCTION reject_archive_command_mutation();

CREATE FUNCTION archive_student_enrollment(
  p_idempotency_key text,
  p_enrollment_id uuid,
  p_expected_generation bigint,
  p_actor_membership_id uuid,
  p_reason_code text
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=pg_catalog,pg_temp
AS $$
DECLARE
  v_existing public.archive_command_log%ROWTYPE;
  v_student_id uuid; v_state text; v_generation bigint; v_student_state text; v_n integer;
BEGIN
  IF p_idempotency_key IS NULL OR length(btrim(p_idempotency_key))=0 OR p_enrollment_id IS NULL
     OR p_expected_generation IS NULL OR p_expected_generation<1 OR p_actor_membership_id IS NULL
     OR p_reason_code IS NULL OR length(btrim(p_reason_code))=0 THEN
    RAISE EXCEPTION 'archive command arguments are invalid' USING ERRCODE='invalid_parameter_value';
  END IF;

  SELECT * INTO v_existing FROM public.archive_command_log WHERE idempotency_key=p_idempotency_key FOR UPDATE;
  IF FOUND THEN
    IF v_existing.enrollment_id IS DISTINCT FROM p_enrollment_id OR v_existing.expected_generation IS DISTINCT FROM p_expected_generation
       OR v_existing.actor_membership_id IS DISTINCT FROM p_actor_membership_id OR v_existing.reason_code IS DISTINCT FROM p_reason_code THEN
      RAISE EXCEPTION 'archive idempotency key reused with different intent' USING ERRCODE='unique_violation';
    END IF;
    RETURN v_existing.enrollment_id;   -- exact replay: no second release
  END IF;

  SELECT e.student_id, e.state, e.ownership_generation, s.lifecycle_state
    INTO v_student_id, v_state, v_generation, v_student_state
    FROM public.enrollments e JOIN public.students s ON s.student_id=e.student_id
   WHERE e.enrollment_id=p_enrollment_id FOR UPDATE OF e, s;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'enrollment % not found', p_enrollment_id USING ERRCODE='foreign_key_violation';
  END IF;
  IF v_generation<>p_expected_generation THEN
    RAISE EXCEPTION 'stale local ownership generation: current %, expected %', v_generation, p_expected_generation
      USING ERRCODE='check_violation';
  END IF;
  IF v_state<>'active' THEN
    RAISE EXCEPTION 'enrollment state % cannot be archived by this command (only active)', v_state
      USING ERRCODE='check_violation';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.workspace_memberships WHERE membership_id=p_actor_membership_id AND status='active') THEN
    RAISE EXCEPTION 'archive actor is not an active Workspace member' USING ERRCODE='insufficient_privilege';
  END IF;

  INSERT INTO public.archive_command_log(idempotency_key,enrollment_id,expected_generation,actor_membership_id,reason_code)
  VALUES (p_idempotency_key,p_enrollment_id,p_expected_generation,p_actor_membership_id,p_reason_code);

  -- Release exactly one active-student slot. Underflow is impossible: the counter cannot go below zero.
  PERFORM public.adjust_workspace_capacity('active_students',-1,'archive:'||p_idempotency_key,v_student_id,p_actor_membership_id,'student archive');

  UPDATE public.enrollments SET state='archived', ended_at=now()
   WHERE enrollment_id=p_enrollment_id AND state='active' AND ownership_generation=p_expected_generation;
  GET DIAGNOSTICS v_n=ROW_COUNT;
  IF v_n<>1 THEN
    RAISE EXCEPTION 'archive state update affected %, expected exactly one row', v_n USING ERRCODE='check_violation';
  END IF;
  -- Historical rows are kept; active counselor assignments of the archived enrollment are ended, not deleted.
  UPDATE public.counselor_assignments SET state='ended', ended_at=now()
   WHERE enrollment_id=p_enrollment_id AND state='active';
  UPDATE public.students SET lifecycle_state='archived', archived_at=now()
   WHERE student_id=v_student_id AND lifecycle_state='active';

  INSERT INTO public.audit_events(audit_event_id,actor_membership_id,event_type,target_type,target_id,outcome,correlation_id,metadata)
  VALUES (gen_random_uuid(),p_actor_membership_id,'student.archive','enrollment',p_enrollment_id,'success',p_idempotency_key,
          jsonb_build_object('reason_code',p_reason_code,'ownership_generation',p_expected_generation,'credit_movement','none'));
  RETURN p_enrollment_id;
END;
$$;
REVOKE ALL ON FUNCTION archive_student_enrollment(text,uuid,bigint,uuid,text) FROM PUBLIC;

-- Counters are projections over the immutable capacity events (contract section 5, test 9).
CREATE VIEW capacity_counter_reconciliation AS
  SELECT c.dimension_key, c.current_value AS stored_value, COALESCE(sum(e.delta),0)::integer AS ledger_value,
         c.current_value = COALESCE(sum(e.delta),0) AS consistent
    FROM workspace_capacity_counters c LEFT JOIN capacity_events e ON e.dimension_key=c.dimension_key
   GROUP BY c.dimension_key, c.current_value;
COMMIT;
