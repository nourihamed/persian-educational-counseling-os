-- WORKSPACE DB — DRAFT: atomic student archive (offboarding) with capacity release. Synthetic only (D-014).
-- Apply after workspace_schema_draft.sql and workspace_activation_transactions.sql. Not a production migration.
-- Implements the "Archive/offboarding" row of CAPACITY_LIFECYCLE_CONTRACT.md:
--   release exactly one active-student slot atomically with the archive state; keep the historical enrollment.
-- Implements PD-2026-11-13-D (archive/reactivation credit lifecycle):
--   * archive inside the 7-calendar-day window from the ORIGINAL activation writes one compensating
--     reversal and binds the returned credit to that student as a reserved entitlement;
--   * archive after the window moves no credit;
--   * reactivation is free only until the end of the ORIGINAL entitlement period and never extends it.
-- The 7-day window is evaluated as an exact 168-hour interval from the stored activation timestamptz, so it
-- does not depend on the session time zone. The boundary is INCLUSIVE (archive exactly at +168h still
-- qualifies). If the Product Owner means local calendar-day boundaries in Asia/Tehran instead, this is a
-- one-line policy change and is recorded as an open clarification, not an assumption.
-- NOT decided here (open Product Owner decisions, deliberately not implemented):
--   * what happens to a reserved entitlement once its original period ends (release, forfeit or manual
--     adjustment) — the credit stays reserved and is reported by view expired_reserved_entitlements;
--   * capacity treatment of a SUSPENDED enrollment (this command refuses to archive from 'suspended').
BEGIN;

CREATE TABLE archive_command_log (
  idempotency_key text PRIMARY KEY CHECK (length(btrim(idempotency_key))>0),
  enrollment_id uuid NOT NULL REFERENCES enrollments(enrollment_id),
  expected_generation bigint NOT NULL CHECK (expected_generation>=1),
  actor_membership_id uuid NOT NULL REFERENCES workspace_memberships(membership_id),
  reason_code text NOT NULL CHECK (length(btrim(reason_code))>0),
  credit_returned boolean NOT NULL DEFAULT false,
  entitlement_id uuid REFERENCES student_entitlements(entitlement_id),
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
  v_ent public.student_entitlements%ROWTYPE; v_now timestamptz; v_wallet uuid; v_rev uuid; v_returned boolean := false;
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

  -- Credit treatment is decided from the ORIGINAL activation timestamp, under the entitlement row lock,
  -- with an actual wall-clock reading (not the transaction start time).
  v_now := clock_timestamp();
  SELECT * INTO v_ent FROM public.student_entitlements
   WHERE student_id=v_student_id AND state='consumed'
   ORDER BY activated_at DESC LIMIT 1 FOR UPDATE;
  IF FOUND THEN
    IF v_ent.reversal_transaction_id IS NULL THEN
      IF v_now <= v_ent.activated_at + interval '168 hours' THEN
        SELECT wallet_id INTO v_wallet FROM public.credit_transactions WHERE transaction_id=v_ent.debit_transaction_id;
        INSERT INTO public.credit_transactions(
          transaction_id,wallet_id,transaction_kind,amount,idempotency_key,
          related_transaction_id,student_id,actor_membership_id,reason
        ) VALUES (
          gen_random_uuid(),v_wallet,'reversal',v_ent.credit_amount,'archive-return:'||p_idempotency_key,
          v_ent.debit_transaction_id,v_student_id,p_actor_membership_id,'archive within the reversal window'
        ) RETURNING transaction_id INTO v_rev;
        UPDATE public.student_entitlements
           SET state='reserved', reserved_at=v_now, reversal_transaction_id=v_rev
         WHERE entitlement_id=v_ent.entitlement_id;
        v_returned := true;
      END IF;
      -- Outside the window: the debit stands. No automatic return (PD-2026-11-13-D).
    ELSE
      -- Already compensated once (this student was reactivated on the returned credit). The ledger is not
      -- compensated a second time; the same credit simply becomes reserved again.
      UPDATE public.student_entitlements SET state='reserved', reserved_at=v_now
       WHERE entitlement_id=v_ent.entitlement_id;
    END IF;
  END IF;

  INSERT INTO public.archive_command_log(idempotency_key,enrollment_id,expected_generation,actor_membership_id,reason_code,
                                         credit_returned,entitlement_id)
  VALUES (p_idempotency_key,p_enrollment_id,p_expected_generation,p_actor_membership_id,p_reason_code,
          v_returned,v_ent.entitlement_id);

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
          jsonb_build_object('reason_code',p_reason_code,'ownership_generation',p_expected_generation,
                             'credit_movement',CASE WHEN v_returned THEN 'compensating_reversal' ELSE 'none' END,
                             'entitlement_id',v_ent.entitlement_id));
  RETURN p_enrollment_id;
END;
$$;
REVOKE ALL ON FUNCTION archive_student_enrollment(text,uuid,bigint,uuid,text) FROM PUBLIC;

-- ============================ reactivation on the reserved entitlement ============================
CREATE TABLE reactivation_command_log (
  idempotency_key text PRIMARY KEY CHECK (length(btrim(idempotency_key))>0),
  student_id uuid NOT NULL REFERENCES students(student_id),
  new_enrollment_id uuid NOT NULL,
  entitlement_id uuid NOT NULL REFERENCES student_entitlements(entitlement_id),
  expected_generation bigint NOT NULL CHECK (expected_generation>=1),
  actor_membership_id uuid NOT NULL REFERENCES workspace_memberships(membership_id),
  recorded_at timestamptz NOT NULL DEFAULT now()
);
CREATE FUNCTION reject_reactivation_command_mutation() RETURNS trigger LANGUAGE plpgsql AS $body$
BEGIN
  RAISE EXCEPTION 'reactivation command log is append-only' USING ERRCODE='check_violation';
END; $body$;
CREATE TRIGGER reactivation_command_log_append_only BEFORE UPDATE OR DELETE ON reactivation_command_log
  FOR EACH ROW EXECUTE FUNCTION reject_reactivation_command_mutation();

-- Free reactivation of the SAME student on the credit that was returned to them. It never debits a new
-- credit, never changes period_end, and refuses once the original period has ended.
CREATE FUNCTION reactivate_student_enrollment(
  p_idempotency_key text,
  p_student_id uuid,
  p_new_enrollment_id uuid,
  p_expected_generation bigint,
  p_actor_membership_id uuid,
  p_counselor_membership_id uuid
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=pg_catalog,pg_temp
AS $$
DECLARE
  v_existing public.reactivation_command_log%ROWTYPE;
  v_ent public.student_entitlements%ROWTYPE;
  v_student_state text; v_now timestamptz; v_n integer;
BEGIN
  IF p_idempotency_key IS NULL OR length(btrim(p_idempotency_key))=0 OR p_student_id IS NULL
     OR p_new_enrollment_id IS NULL OR p_expected_generation IS NULL OR p_expected_generation<1
     OR p_actor_membership_id IS NULL OR p_counselor_membership_id IS NULL THEN
    RAISE EXCEPTION 'reactivation command arguments are invalid' USING ERRCODE='invalid_parameter_value';
  END IF;

  -- Lock the student first so a concurrent reactivation of the same student serialises here.
  SELECT lifecycle_state INTO v_student_state FROM public.students WHERE student_id=p_student_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'student % not found', p_student_id USING ERRCODE='foreign_key_violation';
  END IF;

  SELECT * INTO v_existing FROM public.reactivation_command_log WHERE idempotency_key=p_idempotency_key FOR UPDATE;
  IF FOUND THEN
    IF v_existing.student_id IS DISTINCT FROM p_student_id
       OR v_existing.new_enrollment_id IS DISTINCT FROM p_new_enrollment_id
       OR v_existing.expected_generation IS DISTINCT FROM p_expected_generation
       OR v_existing.actor_membership_id IS DISTINCT FROM p_actor_membership_id THEN
      RAISE EXCEPTION 'reactivation idempotency key reused with different intent' USING ERRCODE='unique_violation';
    END IF;
    RETURN v_existing.new_enrollment_id;   -- exact replay: no second slot, no second consumption
  END IF;

  IF v_student_state<>'archived' THEN
    RAISE EXCEPTION 'only an archived student can be reactivated (state %)', v_student_state USING ERRCODE='check_violation';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.workspace_memberships WHERE membership_id=p_actor_membership_id AND status='active') THEN
    RAISE EXCEPTION 'reactivation actor is not an active Workspace member' USING ERRCODE='insufficient_privilege';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.workspace_memberships WHERE membership_id=p_counselor_membership_id AND status='active') THEN
    RAISE EXCEPTION 'the responsible counselor is not an active Workspace member' USING ERRCODE='insufficient_privilege';
  END IF;

  SELECT * INTO v_ent FROM public.student_entitlements
   WHERE student_id=p_student_id AND state='reserved'
   ORDER BY reserved_at DESC LIMIT 1 FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'no reserved entitlement for student %: reactivation requires a new credit debit', p_student_id
      USING ERRCODE='check_violation';
  END IF;

  -- Expiry is read from the wall clock AFTER the entitlement row is locked, not from the transaction start.
  v_now := clock_timestamp();
  IF v_now > v_ent.period_end THEN
    RAISE EXCEPTION 'the original entitlement period ended at %; reactivation requires a new credit debit', v_ent.period_end
      USING ERRCODE='check_violation';
  END IF;

  INSERT INTO public.enrollments(enrollment_id,student_id,ownership_generation,state)
  VALUES (p_new_enrollment_id,p_student_id,p_expected_generation,'requested');
  INSERT INTO public.counselor_assignments(assignment_id,enrollment_id,counselor_membership_id,is_responsible,state,accepted_at)
  VALUES (gen_random_uuid(),p_new_enrollment_id,p_counselor_membership_id,true,'active',v_now);

  PERFORM public.adjust_workspace_capacity('active_students',1,'reactivation:'||p_idempotency_key,
                                           p_student_id,p_actor_membership_id,'student reactivation');

  UPDATE public.enrollments SET state='active', started_at=v_now WHERE enrollment_id=p_new_enrollment_id;
  GET DIAGNOSTICS v_n=ROW_COUNT;
  IF v_n<>1 THEN
    RAISE EXCEPTION 'reactivation state update affected %, expected exactly one row', v_n USING ERRCODE='check_violation';
  END IF;
  UPDATE public.students SET lifecycle_state='active', archived_at=NULL WHERE student_id=p_student_id;

  -- The SAME entitlement is consumed again. period_end is untouched: the period is never restarted.
  UPDATE public.student_entitlements SET state='consumed', reconsumed_at=v_now WHERE entitlement_id=v_ent.entitlement_id;

  INSERT INTO public.reactivation_command_log(idempotency_key,student_id,new_enrollment_id,entitlement_id,
                                              expected_generation,actor_membership_id)
  VALUES (p_idempotency_key,p_student_id,p_new_enrollment_id,v_ent.entitlement_id,p_expected_generation,p_actor_membership_id);

  INSERT INTO public.audit_events(audit_event_id,actor_membership_id,event_type,target_type,target_id,outcome,correlation_id,metadata)
  VALUES (gen_random_uuid(),p_actor_membership_id,'student.reactivation','enrollment',p_new_enrollment_id,'success',p_idempotency_key,
          jsonb_build_object('entitlement_id',v_ent.entitlement_id,'period_end',v_ent.period_end,
                             'credit_movement','reserved entitlement re-consumed','new_debit',false));
  RETURN p_new_enrollment_id;
END;
$$;
REVOKE ALL ON FUNCTION reactivate_student_enrollment(text,uuid,uuid,bigint,uuid,uuid) FROM PUBLIC;

-- Reserved credits whose original period has ended. Their disposition is an OPEN Product Owner decision;
-- this view only makes them visible, it does not release, forfeit or adjust anything.
CREATE VIEW expired_reserved_entitlements AS
  SELECT e.entitlement_id, e.student_id, e.credit_amount, e.activated_at, e.period_end, e.reserved_at
    FROM student_entitlements e
   WHERE e.state='reserved' AND e.period_end < now();

-- Counters are projections over the immutable capacity events (contract section 5, test 9).
CREATE VIEW capacity_counter_reconciliation AS
  SELECT c.dimension_key, c.current_value AS stored_value, COALESCE(sum(e.delta),0)::integer AS ledger_value,
         c.current_value = COALESCE(sum(e.delta),0) AS consistent
    FROM workspace_capacity_counters c LEFT JOIN capacity_events e ON e.dimension_key=c.dimension_key
   GROUP BY c.dimension_key, c.current_value;
COMMIT;
