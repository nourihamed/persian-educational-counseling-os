-- WORKSPACE DB — DRAFT: Saga inbox and generation-fenced ownership projection.
-- Apply AFTER workspace_schema_draft.sql and workspace_activation_transactions.sql. Synthetic only (D-014).
--
-- WHAT THIS IS
--   The consuming half of the transfer Saga. One row per delivered Control Plane event, keyed by the
--   Control Plane event_id, so at-least-once delivery becomes exactly-once effect. The recorded outcome
--   and the projection change happen in ONE local transaction.
--
-- WHAT THIS IS NOT
--   * It is NOT a distributed transaction with the Control Plane. The two databases are separate; this
--     side only guarantees that its own inbox row and its own projection move together.
--   * The Workspace database holds no global ownership. Applying an event NEVER changes Control Plane
--     ownership - there is nothing here that could. It only moves this Workspace's local fence.
--   * No retry, timeout or quarantine-resolution policy is chosen here. A quarantined event stays
--     quarantined and visible; resolving it is an operator action whose policy is OPEN (OQ-E).
--
-- FENCING RULE (contract section 5): the destination accepts generation N+1 and nothing else; the source
-- is fenced at the same generation and every later local write for that student fails.
BEGIN;

CREATE TABLE workspace_inbox_events (
  event_id uuid PRIMARY KEY,                       -- the Control Plane event id: duplicates are no-ops
  schema_version integer NOT NULL CHECK (schema_version >= 1),
  event_type text NOT NULL CHECK (length(btrim(event_type)) > 0),
  payload jsonb NOT NULL CHECK (jsonb_typeof(payload) = 'object'),
  payload_hash bytea NOT NULL CHECK (octet_length(payload_hash) = 32),
  platform_student_id uuid NOT NULL,
  ownership_generation bigint NOT NULL CHECK (ownership_generation >= 1),
  correlation_id uuid NOT NULL,
  outcome text NOT NULL CHECK (outcome IN
    ('applied','ignored_stale','quarantined_future','rejected_payload','rejected_schema','rejected_not_addressed')),
  outcome_reason text,
  local_student_id uuid REFERENCES students(student_id),
  received_at timestamptz NOT NULL DEFAULT now(),
  applied_at timestamptz,
  CHECK ((outcome = 'applied') = (applied_at IS NOT NULL))
);
CREATE INDEX workspace_inbox_events_student ON workspace_inbox_events(platform_student_id, ownership_generation);
CREATE INDEX workspace_inbox_events_outcome ON workspace_inbox_events(outcome) WHERE outcome = 'quarantined_future';

CREATE FUNCTION reject_inbox_event_mutation() RETURNS trigger LANGUAGE plpgsql AS $body$
BEGIN
  RAISE EXCEPTION 'the inbox is append-only; a re-delivered event returns its recorded outcome'
    USING ERRCODE='check_violation';
END; $body$;
CREATE TRIGGER workspace_inbox_events_append_only BEFORE UPDATE OR DELETE ON workspace_inbox_events
  FOR EACH ROW EXECUTE FUNCTION reject_inbox_event_mutation();

-- Events that arrived too far ahead of the local projection. They are kept, visible and unapplied.
CREATE VIEW quarantined_inbox_events AS
  SELECT event_id, event_type, platform_student_id, ownership_generation, correlation_id,
         outcome_reason, received_at
    FROM workspace_inbox_events WHERE outcome = 'quarantined_future';

-- Returns the recorded outcome. A re-delivery of the same event returns that same outcome and changes
-- nothing; the same event id with different content is refused rather than silently re-interpreted.
CREATE FUNCTION apply_inbox_event(
  p_event_id uuid,
  p_schema_version integer,
  p_event_type text,
  p_payload jsonb,
  p_payload_hash bytea,
  p_platform_student_id uuid,
  p_source_workspace_id uuid,
  p_destination_workspace_id uuid,
  p_ownership_generation bigint,
  p_correlation_id uuid
) RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=pg_catalog,pg_temp
AS $$
DECLARE
  v_existing public.workspace_inbox_events%ROWTYPE;
  v_me uuid; v_is_destination boolean; v_is_source boolean;
  v_student uuid; v_enrollment uuid; v_local_gen bigint; v_state text;
  v_outcome text; v_reason text; v_now timestamptz; v_n integer;
BEGIN
  IF p_event_id IS NULL OR p_schema_version IS NULL OR p_event_type IS NULL OR p_payload IS NULL
     OR p_payload_hash IS NULL OR p_platform_student_id IS NULL OR p_ownership_generation IS NULL
     OR p_ownership_generation < 1 OR p_correlation_id IS NULL THEN
    RAISE EXCEPTION 'inbox event arguments are invalid' USING ERRCODE='invalid_parameter_value';
  END IF;

  SELECT * INTO v_existing FROM public.workspace_inbox_events WHERE event_id=p_event_id FOR UPDATE;
  IF FOUND THEN
    IF v_existing.payload_hash IS DISTINCT FROM p_payload_hash
       OR v_existing.schema_version IS DISTINCT FROM p_schema_version
       OR v_existing.event_type IS DISTINCT FROM p_event_type
       OR v_existing.ownership_generation IS DISTINCT FROM p_ownership_generation THEN
      RAISE EXCEPTION 'event % was already received with different content', p_event_id
        USING ERRCODE='unique_violation';
    END IF;
    RETURN v_existing.outcome;        -- duplicate / out-of-order redelivery: recorded outcome, no effect
  END IF;

  v_now := clock_timestamp();
  v_outcome := NULL;

  IF p_payload_hash <> sha256(convert_to(p_payload::text,'UTF8')) THEN
    v_outcome := 'rejected_payload'; v_reason := 'payload hash does not match the delivered payload';
  ELSIF p_schema_version <> 1 THEN
    v_outcome := 'rejected_schema'; v_reason := 'unsupported envelope schema version';
  END IF;

  IF v_outcome IS NULL THEN
    SELECT workspace_id INTO v_me FROM public.workspace_profile WHERE singleton;
    v_is_destination := (p_destination_workspace_id IS NOT NULL AND p_destination_workspace_id = v_me);
    v_is_source      := (p_source_workspace_id IS NOT NULL AND p_source_workspace_id = v_me);
    IF NOT v_is_destination AND NOT v_is_source THEN
      -- No cross-Workspace context substitution: an event for another Workspace has no effect here.
      v_outcome := 'rejected_not_addressed'; v_reason := 'event is addressed to another Workspace';
    END IF;
  END IF;

  IF v_outcome IS NULL THEN
    SELECT s.student_id INTO v_student FROM public.students s
     WHERE s.platform_student_id = p_platform_student_id FOR UPDATE;
    IF NOT FOUND THEN
      IF v_is_destination THEN
        v_outcome := 'quarantined_future'; v_reason := 'student is not projected in this Workspace yet';
      ELSE
        v_outcome := 'ignored_stale'; v_reason := 'no local projection of this student to fence';
      END IF;
    END IF;
  END IF;

  IF v_outcome IS NULL THEN
    SELECT e.enrollment_id, e.ownership_generation, e.state
      INTO v_enrollment, v_local_gen, v_state
      FROM public.enrollments e
     WHERE e.student_id = v_student
     ORDER BY e.created_at DESC LIMIT 1
     FOR UPDATE;
    IF NOT FOUND THEN
      v_outcome := 'quarantined_future'; v_reason := 'student has no local enrollment to fence';
    ELSIF p_ownership_generation <= v_local_gen THEN
      v_outcome := 'ignored_stale';
      v_reason := format('event generation %s is not newer than the local generation %s',
                         p_ownership_generation, v_local_gen);
    ELSIF p_ownership_generation > v_local_gen + 1 THEN
      v_outcome := 'quarantined_future';
      v_reason := format('event generation %s is ahead of the local generation %s',
                         p_ownership_generation, v_local_gen);
    END IF;
  END IF;

  IF v_outcome IS NULL THEN
    IF v_is_source THEN
      -- The student has left: fence the local projection at the new generation and end the assignments.
      UPDATE public.enrollments
         SET ownership_generation = p_ownership_generation,
             state = 'ended',
             ended_at = COALESCE(ended_at, v_now)
       WHERE enrollment_id = v_enrollment;
      UPDATE public.counselor_assignments SET state='ended', ended_at=v_now
       WHERE enrollment_id = v_enrollment AND state='active';
    ELSE
      -- The student has arrived: the local projection advances to exactly N+1.
      UPDATE public.enrollments
         SET ownership_generation = p_ownership_generation
       WHERE enrollment_id = v_enrollment;
    END IF;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    IF v_n <> 1 THEN
      RAISE EXCEPTION 'projection update affected %, expected exactly one row', v_n USING ERRCODE='check_violation';
    END IF;
    v_outcome := 'applied';
    v_reason := CASE WHEN v_is_source THEN 'source projection fenced' ELSE 'destination projection advanced' END;
  END IF;

  -- The inbox row and the projection change commit together. If this insert fails, nothing was applied.
  INSERT INTO public.workspace_inbox_events(
    event_id,schema_version,event_type,payload,payload_hash,platform_student_id,ownership_generation,
    correlation_id,outcome,outcome_reason,local_student_id,applied_at)
  VALUES (p_event_id,p_schema_version,p_event_type,p_payload,p_payload_hash,p_platform_student_id,
          p_ownership_generation,p_correlation_id,v_outcome,v_reason,v_student,
          CASE WHEN v_outcome='applied' THEN v_now END);
  RETURN v_outcome;
END;
$$;
REVOKE ALL ON FUNCTION apply_inbox_event(uuid,integer,text,jsonb,bytea,uuid,uuid,uuid,bigint,uuid) FROM PUBLIC;

COMMIT;
