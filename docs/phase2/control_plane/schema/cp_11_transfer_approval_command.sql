-- CONTROL PLANE — DRAFT: approval recording/revocation commands for a dedicated workflow executor.
-- Apply AFTER cp_01..cp_07 and cp_06_role_privileges_draft.sql. Synthetic only (D-014). Not a migration.
--
-- Why a command and not a table grant: approval evidence must be written by one narrow identity whose only
-- capability is "record an approval event" / "record a revocation event". No ordinary runtime, worker or
-- exporter identity may write approval rows, and the executor cannot switch ownership, change a case state,
-- enable the deferred conflict exception, or alter the evidence it has written.
--
-- NOT decided and NOT implemented here (PD-2026-11-13-C and Q-007):
--   * who may act as guardian/legal authority (Q-007: Iran legal review and Product Owner approval);
--   * the source_destination_owner conflict exception (deferred; disabled and fail-closed in cp_01);
--   * any conflict-resolution or override authority for Platform Admin (none is granted anywhere).
-- The database verifies the SHAPE and SEPARATION of the recorded evidence. It cannot verify that an
-- assertion is authentic or that a person truly holds the authority the snapshot claims.
BEGIN;

DO $roles$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='cp_transfer_approval_function_owner') THEN
    CREATE ROLE cp_transfer_approval_function_owner NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='cp_transfer_approval_executor') THEN
    CREATE ROLE cp_transfer_approval_executor NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS;
  END IF;
END
$roles$;

GRANT SELECT ON transfer_cases, transfer_approvals, transfer_approval_revocations,
                transfer_approval_conflict_exceptions TO cp_transfer_approval_function_owner;
GRANT INSERT ON transfer_approvals, transfer_approval_revocations TO cp_transfer_approval_function_owner;
-- Row-lock privilege only: PostgreSQL requires an UPDATE privilege for SELECT ... FOR UPDATE. This column
-- grant lets the command serialise on the case row; it conveys no ability to change the case state.
GRANT UPDATE(updated_at) ON transfer_cases TO cp_transfer_approval_function_owner;

-- 'recorded' on first write, 'replayed' when the same assertion is presented again unchanged.
CREATE FUNCTION record_transfer_approval(
  p_approval_id      uuid,
  p_assertion_id     uuid,
  p_nonce_digest     bytea,
  p_case_id          uuid,
  p_approval_kind    text,
  p_evidence_ref     text,
  p_approver_ref     text,
  p_authn_event_ref  text,
  p_authority_snapshot jsonb,
  p_verified_at      timestamptz,
  p_valid_until      timestamptz
) RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=pg_catalog,pg_temp
AS $$
DECLARE v_existing public.transfer_approvals%ROWTYPE; v_state text; v_now timestamptz;
BEGIN
  IF session_user <> 'cp_transfer_approval_executor' THEN
    RAISE EXCEPTION 'only the transfer approval executor may record approval evidence (session_user %)', session_user
      USING ERRCODE='insufficient_privilege';
  END IF;
  IF p_approval_id IS NULL OR p_assertion_id IS NULL OR p_nonce_digest IS NULL OR p_case_id IS NULL
     OR p_approval_kind IS NULL OR p_evidence_ref IS NULL OR p_approver_ref IS NULL
     OR p_authn_event_ref IS NULL OR p_authority_snapshot IS NULL OR p_verified_at IS NULL THEN
    RAISE EXCEPTION 'approval command arguments are invalid' USING ERRCODE='invalid_parameter_value';
  END IF;

  -- Serialise against the ownership switch and against concurrent revocation on the same case row.
  SELECT state INTO v_state FROM public.transfer_cases WHERE case_id=p_case_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'transfer case % not found', p_case_id USING ERRCODE='foreign_key_violation';
  END IF;

  SELECT * INTO v_existing FROM public.transfer_approvals WHERE assertion_id=p_assertion_id;
  IF FOUND THEN
    IF v_existing.approval_id IS DISTINCT FROM p_approval_id
       OR v_existing.case_id IS DISTINCT FROM p_case_id
       OR v_existing.approval_kind IS DISTINCT FROM p_approval_kind
       OR v_existing.approver_ref IS DISTINCT FROM p_approver_ref
       OR v_existing.nonce_digest IS DISTINCT FROM p_nonce_digest
       OR v_existing.evidence_ref IS DISTINCT FROM p_evidence_ref
       OR v_existing.authority_snapshot IS DISTINCT FROM p_authority_snapshot THEN
      RAISE EXCEPTION 'assertion % was already recorded with different content', p_assertion_id
        USING ERRCODE='unique_violation';
    END IF;
    RETURN 'replayed';
  END IF;

  -- Approvals are evidence for a cutover that has not happened yet. After the switch, or once the case is
  -- closed, new approval evidence is refused rather than silently appended to history.
  IF v_state NOT IN ('requested','approvals_pending','approved','preflight_ok','staging','staged_verified') THEN
    RAISE EXCEPTION 'transfer case state % no longer accepts approval evidence', v_state USING ERRCODE='check_violation';
  END IF;

  v_now := clock_timestamp();
  IF p_verified_at > v_now THEN
    RAISE EXCEPTION 'approval verified_at is in the future' USING ERRCODE='check_violation';
  END IF;
  IF p_valid_until IS NOT NULL AND p_valid_until <= v_now THEN
    RAISE EXCEPTION 'approval evidence is already expired at recording time' USING ERRCODE='check_violation';
  END IF;

  INSERT INTO public.transfer_approvals(
    approval_id,assertion_id,nonce_digest,case_id,approval_kind,evidence_ref,approver_ref,
    authn_event_ref,authority_snapshot,verified_at,valid_until
  ) VALUES (
    p_approval_id,p_assertion_id,p_nonce_digest,p_case_id,p_approval_kind,p_evidence_ref,p_approver_ref,
    p_authn_event_ref,p_authority_snapshot,p_verified_at,p_valid_until
  );
  RETURN 'recorded';
END;
$$;

CREATE FUNCTION revoke_transfer_approval(
  p_revocation_id    uuid,
  p_approval_id      uuid,
  p_actor_ref        text,
  p_authn_event_ref  text,
  p_reason_code      text
) RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=pg_catalog,pg_temp
AS $$
DECLARE v_existing public.transfer_approval_revocations%ROWTYPE; v_case uuid; v_state text;
BEGIN
  IF session_user <> 'cp_transfer_approval_executor' THEN
    RAISE EXCEPTION 'only the transfer approval executor may revoke approval evidence (session_user %)', session_user
      USING ERRCODE='insufficient_privilege';
  END IF;
  IF p_revocation_id IS NULL OR p_approval_id IS NULL OR p_actor_ref IS NULL
     OR p_authn_event_ref IS NULL OR p_reason_code IS NULL THEN
    RAISE EXCEPTION 'revocation command arguments are invalid' USING ERRCODE='invalid_parameter_value';
  END IF;

  SELECT case_id INTO v_case FROM public.transfer_approvals WHERE approval_id=p_approval_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'approval % not found', p_approval_id USING ERRCODE='foreign_key_violation';
  END IF;
  SELECT state INTO v_state FROM public.transfer_cases WHERE case_id=v_case FOR UPDATE;

  SELECT * INTO v_existing FROM public.transfer_approval_revocations WHERE approval_id=p_approval_id;
  IF FOUND THEN
    IF v_existing.revocation_id IS DISTINCT FROM p_revocation_id
       OR v_existing.actor_ref IS DISTINCT FROM p_actor_ref
       OR v_existing.reason_code IS DISTINCT FROM p_reason_code THEN
      RAISE EXCEPTION 'approval % was already revoked with different content', p_approval_id
        USING ERRCODE='unique_violation';
    END IF;
    RETURN 'replayed';
  END IF;

  -- After the ownership switch the approval evidence that justified it stays as it was: revoking it then
  -- would rewrite the justification of a completed switch. There is no automatic reverse switch.
  IF v_state IN ('ownership_switched','projections_finalizing','completed','manual_intervention_post_switch') THEN
    RAISE EXCEPTION 'approval evidence cannot be revoked after the ownership switch (case state %)', v_state
      USING ERRCODE='check_violation';
  END IF;

  INSERT INTO public.transfer_approval_revocations(revocation_id,approval_id,actor_ref,authn_event_ref,reason_code)
  VALUES (p_revocation_id,p_approval_id,p_actor_ref,p_authn_event_ref,p_reason_code);
  RETURN 'revoked';
END;
$$;

ALTER FUNCTION record_transfer_approval(uuid,uuid,bytea,uuid,text,text,text,text,jsonb,timestamptz,timestamptz)
  OWNER TO cp_transfer_approval_function_owner;
ALTER FUNCTION revoke_transfer_approval(uuid,uuid,text,text,text)
  OWNER TO cp_transfer_approval_function_owner;
REVOKE ALL ON FUNCTION record_transfer_approval(uuid,uuid,bytea,uuid,text,text,text,text,jsonb,timestamptz,timestamptz) FROM PUBLIC;
REVOKE ALL ON FUNCTION revoke_transfer_approval(uuid,uuid,text,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION record_transfer_approval(uuid,uuid,bytea,uuid,text,text,text,text,jsonb,timestamptz,timestamptz)
  TO cp_transfer_approval_executor;
GRANT EXECUTE ON FUNCTION revoke_transfer_approval(uuid,uuid,text,text,text)
  TO cp_transfer_approval_executor;

-- No ordinary identity may write approval evidence directly, and the executor gets nothing else.
REVOKE INSERT, UPDATE, DELETE ON transfer_approvals, transfer_approval_revocations
  FROM cp_runtime, cp_transfer_executor, cp_transfer_function_owner;
REVOKE ALL ON transfer_approval_conflict_exceptions
  FROM cp_runtime, cp_transfer_executor, cp_transfer_function_owner, cp_transfer_approval_executor;
GRANT SELECT ON transfer_approval_conflict_exceptions TO cp_runtime;
GRANT SELECT ON transfer_cases, transfer_approvals, transfer_approval_revocations TO cp_transfer_approval_executor;

COMMIT;
