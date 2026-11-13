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
    v_claim_count integer;
    v_alias_count integer;
    v_active_key_count integer;
BEGIN
    SELECT * INTO v_case FROM public.transfer_cases WHERE case_id = p_case_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'transfer case % not found', p_case_id USING ERRCODE = 'foreign_key_violation';
    END IF;
    IF v_case.state <> 'cutover_frozen' THEN
        RAISE EXCEPTION 'transfer case % is in state %, expected cutover_frozen', p_case_id, v_case.state
            USING ERRCODE = 'check_violation';
    END IF;
    IF v_case.source_freeze_token IS NULL OR v_case.source_frozen_at IS NULL
       OR v_case.final_snapshot_ref IS NULL OR v_case.final_snapshot_at IS NULL OR v_case.snapshot_manifest_hash IS NULL
       OR v_case.destination_validation_ref IS NULL OR v_case.destination_validated_at IS NULL THEN
        RAISE EXCEPTION 'cutover evidence incomplete: freeze, final snapshot and destination validation are required'
            USING ERRCODE = 'check_violation';
    END IF;

    SELECT count(DISTINCT approval_kind) INTO v_approvals
      FROM public.transfer_approvals a
     WHERE case_id = p_case_id
       AND NOT EXISTS (SELECT 1 FROM public.transfer_approval_revocations r WHERE r.approval_id = a.approval_id)
       AND (valid_until IS NULL OR valid_until > now())
       AND verified_at <= now()
       AND authn_event_ref <> ''
       AND approver_ref <> '';
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

    -- Exactly one valid source claim is mandatory; otherwise ownership must not switch.
    PERFORM 1 FROM public.enrollment_claims
     WHERE student_id = v_case.student_id
       AND workspace_id = v_case.source_workspace_id
       AND ownership_generation = v_gen
       AND claim_state IN ('active','transfer_pending')
     FOR UPDATE;
    GET DIAGNOSTICS v_claim_count = ROW_COUNT;
    IF v_claim_count <> 1 THEN
        RAISE EXCEPTION 'expected exactly one valid source enrollment claim, found %', v_claim_count
            USING ERRCODE = 'check_violation';
    END IF;

    SELECT count(*) INTO v_active_key_count
      FROM public.mobile_hmac_key_versions WHERE state IN ('active','retiring');
    SELECT count(*) INTO v_alias_count
      FROM public.enrollment_claim_identity_aliases a
      JOIN public.enrollment_claims c ON c.claim_id=a.claim_id
      JOIN public.student_contact_index ci
        ON ci.student_id=c.student_id AND ci.key_version=a.key_version AND ci.mobile_hmac=a.mobile_hmac
     WHERE c.student_id=v_case.student_id
       AND a.claim_state IN ('active','transfer_pending')
       AND a.key_version IN (SELECT key_version FROM public.mobile_hmac_key_versions WHERE state IN ('active','retiring'));
    IF v_active_key_count = 0 OR v_alias_count <> v_active_key_count THEN
        RAISE EXCEPTION 'identity aliases incomplete: found %, expected one per active/retiring key version %', v_alias_count, v_active_key_count
            USING ERRCODE = 'check_violation';
    END IF;

    UPDATE public.enrollment_claims
       SET workspace_id = v_case.destination_workspace_id,
           ownership_generation = v_new_gen,
           claim_state = 'active'
     WHERE student_id = v_case.student_id
       AND workspace_id = v_case.source_workspace_id
       AND ownership_generation = v_gen
       AND claim_state IN ('active', 'transfer_pending');
    GET DIAGNOSTICS v_claim_count = ROW_COUNT;
    IF v_claim_count <> 1 THEN
        RAISE EXCEPTION 'claim update affected %, expected exactly one', v_claim_count
            USING ERRCODE = 'check_violation';
    END IF;

    UPDATE public.enrollment_claim_identity_aliases a
       SET claim_state='active'
      FROM public.enrollment_claims c
     WHERE c.claim_id=a.claim_id AND c.student_id=v_case.student_id
       AND a.claim_state IN ('active','transfer_pending');

    INSERT INTO public.ownership_history (student_id, from_workspace_id, to_workspace_id, ownership_generation, case_id)
    VALUES (v_case.student_id, v_case.source_workspace_id, v_case.destination_workspace_id, v_new_gen, p_case_id);

    UPDATE public.transfer_cases SET state = 'ownership_switched', updated_at = now() WHERE case_id = p_case_id;

    INSERT INTO public.outbox_events (event_id, case_id, event_type, payload)
    VALUES (gen_random_uuid(), p_case_id, 'ownership_switched',
            jsonb_build_object('student_id', v_case.student_id,
                               'to_workspace_id', v_case.destination_workspace_id,
                               'generation', v_new_gen));

    -- Deferred coverage triggers would otherwise run at COMMIT as the CALLER; an executor role has no table access,
    -- so the command would fail for its own executor. Run them here, in this function's security context.
    SET CONSTRAINTS public.enrollment_claim_alias_coverage_claim, public.enrollment_claim_alias_coverage_alias IMMEDIATE;
    SET CONSTRAINTS public.enrollment_claim_alias_coverage_claim, public.enrollment_claim_alias_coverage_alias DEFERRED;
    RETURN v_new_gen;
END;
$$;

-- Privilege boundary: no PUBLIC execute. Deployment must grant EXECUTE only to a dedicated
-- Control Plane workflow role after verifying the function owner is a non-login, least-privilege
-- role with no table-owner/BYPASSRLS capability. No application/user role may call directly.
REVOKE ALL ON FUNCTION switch_student_ownership(uuid) FROM PUBLIC;

COMMIT;
