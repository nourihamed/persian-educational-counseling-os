-- =============================================================================
-- CONTROL PLANE — DRAFT: atomic ownership switch (PR #11 §5 step 6; OQ-E).
-- ONE transaction inside the Control Plane database. It never touches a Workspace DB.
-- Preconditions enforced here (database-enforced, same transaction):
--   * case exists and is in state 'cutover_frozen' (freeze + final snapshot done, OQ-E);
--   * ALL THREE approvals exist for this case (cumulative: D-026, D-027, PO-8);
--   * current owner == case source, and ownership_generation == expected_generation (CAS / fencing);
--   * the student's claim is held by the source workspace and is switched with the owner.
-- Failure of any check raises and rolls back the whole transaction (no partial switch).
-- Authorization of the CALLER (Phase 4 identity) is NOT enforced here; this function is
-- callable only by the Control Plane workflow role (privilege boundary, see grants below).
-- =============================================================================
BEGIN;

CREATE FUNCTION switch_student_ownership(p_case_id uuid)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_case      public.transfer_cases%ROWTYPE;
    v_owner     uuid;
    v_gen       bigint;
    v_approvals integer;
    v_new_gen   bigint;
BEGIN
    SELECT * INTO v_case FROM public.transfer_cases WHERE case_id = p_case_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'transfer case % not found', p_case_id USING ERRCODE = 'foreign_key_violation';
    END IF;
    IF v_case.state <> 'cutover_frozen' THEN
        RAISE EXCEPTION 'transfer case % is in state %, expected cutover_frozen', p_case_id, v_case.state
            USING ERRCODE = 'check_violation';
    END IF;

    SELECT count(DISTINCT approval_kind) INTO v_approvals
      FROM public.transfer_approvals WHERE case_id = p_case_id;
    IF v_approvals <> 3 THEN
        RAISE EXCEPTION 'transfer case % has % of 3 required approvals', p_case_id, v_approvals
            USING ERRCODE = 'check_violation';
    END IF;

    SELECT owner_workspace_id, ownership_generation INTO v_owner, v_gen
      FROM public.student_ownership WHERE student_id = v_case.student_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'no ownership record for student %', v_case.student_id USING ERRCODE = 'foreign_key_violation';
    END IF;
    IF v_owner <> v_case.source_workspace_id THEN
        RAISE EXCEPTION 'stale source: owner is %, case expects %', v_owner, v_case.source_workspace_id
            USING ERRCODE = 'check_violation';
    END IF;
    IF v_gen <> v_case.expected_generation THEN
        RAISE EXCEPTION 'stale generation: current %, case expects %', v_gen, v_case.expected_generation
            USING ERRCODE = 'check_violation';
    END IF;

    v_new_gen := v_gen + 1;

    UPDATE public.student_ownership
       SET owner_workspace_id = v_case.destination_workspace_id,
           ownership_generation = v_new_gen,
           lifecycle_state = 'active',
           updated_at = now()
     WHERE student_id = v_case.student_id;

    -- Move the claim-holding enrollment to the destination with the new generation (fencing).
    UPDATE public.enrollment_claims
       SET workspace_id = v_case.destination_workspace_id,
           ownership_generation = v_new_gen,
           claim_state = 'active'
     WHERE student_id = v_case.student_id AND claim_state IN ('active', 'transfer_pending');

    INSERT INTO public.ownership_history (student_id, from_workspace_id, to_workspace_id, ownership_generation, case_id)
    VALUES (v_case.student_id, v_case.source_workspace_id, v_case.destination_workspace_id, v_new_gen, p_case_id);

    UPDATE public.transfer_cases SET state = 'ownership_switched', updated_at = now() WHERE case_id = p_case_id;

    INSERT INTO public.outbox_events (event_id, case_id, event_type, payload)
    VALUES (gen_random_uuid(), p_case_id, 'ownership_switched',
            jsonb_build_object('student_id', v_case.student_id,
                               'to_workspace_id', v_case.destination_workspace_id,
                               'generation', v_new_gen));

    RETURN v_new_gen;
END;
$$;

-- Privilege boundary: no PUBLIC execute; only the Control Plane workflow role may call it.
REVOKE ALL ON FUNCTION switch_student_ownership(uuid) FROM PUBLIC;

COMMIT;
