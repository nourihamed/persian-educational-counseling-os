-- =============================================================================
-- WORKSPACE — Atomic command boundary for proof receipts (DRAFT, synthetic only).
-- One transaction: receipt lock -> exact binding check -> time/status check ->
-- idempotency check -> governance event append (which validates the actor membership,
-- the target membership and the projection) -> receipt marked consumed.
-- Any failure rolls back receipt consumption, event append and projection changes together.
-- The database cannot verify the assertion signature. It enforces that the adapter
-- presents the exact bindings recorded by the external verifier.
-- =============================================================================
\set ON_ERROR_STOP on
SET app.workspace_key = :'workspace_key';

-- Owner = governance materializer (NOLOGIN). Caller identity is checked against the allowlist.
SELECT 'ws_'||current_setting('app.workspace_key')||'_governance_owner' AS owner_role \gset
SELECT 'ws_'||current_setting('app.workspace_key')||'_governance_adapter_rt' AS adapter_role \gset

BEGIN;
CREATE FUNCTION consume_governance_receipt_and_apply(
  p_receipt_id           uuid,
  p_actor_membership_id  uuid,
  p_action               text,
  p_aggregate_type       text,
  p_aggregate_id         uuid,
  p_target_membership_id uuid,
  p_role_or_permission_key text,
  p_scope_digest         bytea,
  p_policy_version       text,
  p_idempotency_key      text,
  p_event_payload        jsonb,
  p_event_id             uuid,
  p_effective_at         timestamptz
) RETURNS TABLE(event_id uuid, event_sequence bigint)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $body$
DECLARE
  r public.governance_proof_receipts%ROWTYPE;
  v_ws uuid;
  v_ev record;
  v_seq bigint;
BEGIN
  -- 1. Caller must be an allowlisted adapter identity (never a runtime/worker/exporter/verifier).
  IF NOT EXISTS (SELECT 1 FROM public.receipt_adapter_allowlist a WHERE a.role_name = session_user) THEN
    RAISE EXCEPTION 'caller % is not an allowlisted governance adapter', session_user
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- 2. Lock the receipt. A missing receipt is a failure, not an implicit create.
  SELECT * INTO r FROM public.governance_proof_receipts WHERE receipt_id = p_receipt_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'receipt % not found', p_receipt_id USING ERRCODE = 'no_data_found';
  END IF;

  -- 3. Exact binding checks against the Workspace and the request.
  SELECT workspace_id INTO v_ws FROM public.workspace_profile WHERE singleton;
  IF r.workspace_id IS DISTINCT FROM v_ws THEN
    RAISE EXCEPTION 'receipt is not for this Workspace' USING ERRCODE = 'check_violation';
  END IF;
  IF r.actor_membership_id IS DISTINCT FROM p_actor_membership_id THEN
    RAISE EXCEPTION 'receipt binding mismatch: actor' USING ERRCODE = 'check_violation';
  END IF;
  IF r.action IS DISTINCT FROM p_action THEN
    RAISE EXCEPTION 'receipt binding mismatch: action' USING ERRCODE = 'check_violation';
  END IF;
  IF r.aggregate_type IS DISTINCT FROM p_aggregate_type OR r.aggregate_id IS DISTINCT FROM p_aggregate_id THEN
    RAISE EXCEPTION 'receipt binding mismatch: aggregate' USING ERRCODE = 'check_violation';
  END IF;
  IF r.target_membership_id IS DISTINCT FROM p_target_membership_id THEN
    RAISE EXCEPTION 'receipt binding mismatch: target' USING ERRCODE = 'check_violation';
  END IF;
  IF r.role_or_permission_key IS DISTINCT FROM p_role_or_permission_key THEN
    RAISE EXCEPTION 'receipt binding mismatch: role/permission' USING ERRCODE = 'check_violation';
  END IF;
  IF r.scope_digest IS DISTINCT FROM p_scope_digest THEN
    RAISE EXCEPTION 'receipt binding mismatch: scope' USING ERRCODE = 'check_violation';
  END IF;
  IF r.policy_version IS DISTINCT FROM p_policy_version THEN
    RAISE EXCEPTION 'receipt binding mismatch: policy' USING ERRCODE = 'check_violation';
  END IF;
  IF r.idempotency_key IS DISTINCT FROM p_idempotency_key THEN
    RAISE EXCEPTION 'receipt binding mismatch: idempotency key' USING ERRCODE = 'check_violation';
  END IF;
  -- Canonicalization version is bound to the receipt; an unknown version fails closed (contract M-03).
  IF r.canonicalization_version IS DISTINCT FROM 'receipt-canon-v1' THEN
    RAISE EXCEPTION 'unsupported canonicalization version' USING ERRCODE = 'check_violation';
  END IF;
  IF receipt_payload_digest_v1(p_event_payload) IS DISTINCT FROM r.payload_digest THEN
    RAISE EXCEPTION 'receipt binding mismatch: payload' USING ERRCODE = 'check_violation';
  END IF;

  -- 4. Status. The FULL binding above has already been validated, so an identical retry of a
  --    consumed receipt is recognised regardless of time (M-01). Revoked receipts fail closed.
  IF r.status = 'revoked' THEN
    RAISE EXCEPTION 'receipt is revoked' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF r.status = 'consumed' THEN
    -- H-03: the stored consumption must be CONSISTENT with the receipt binding and the referenced event.
    -- Never return an unrelated event.
    SELECT e.* INTO v_ev FROM public.workspace_governance_events e WHERE e.event_id = r.consumed_event_id;
    IF NOT FOUND
       OR v_ev.idempotency_key IS DISTINCT FROM r.consumed_idempotency_key
       OR v_ev.idempotency_key IS DISTINCT FROM r.idempotency_key
       OR v_ev.aggregate_type IS DISTINCT FROM r.aggregate_type
       OR v_ev.aggregate_id IS DISTINCT FROM r.aggregate_id
       OR v_ev.event_type IS DISTINCT FROM r.action
       OR v_ev.actor_membership_id IS DISTINCT FROM r.actor_membership_id
       OR v_ev.payload_hash IS DISTINCT FROM r.payload_digest THEN
      RAISE EXCEPTION 'consumed receipt is inconsistent with its consumption event' USING ERRCODE='check_violation';
    END IF;
    -- Full binding matched and the event is consistent: return the original result.
    RETURN QUERY SELECT v_ev.event_id, v_ev.event_sequence;
    RETURN;
  END IF;

  -- 5. Validity window applies ONLY to an unconsumed receipt. An unconsumed expired receipt fails closed.
  IF now() < r.not_before OR now() >= r.expires_at THEN
    RAISE EXCEPTION 'receipt is not valid at this time' USING ERRCODE = 'check_violation';
  END IF;

  -- 6. Idempotency key must not already belong to a different receipt's event.
  IF EXISTS (SELECT 1 FROM public.workspace_governance_events e WHERE e.idempotency_key = p_idempotency_key) THEN
    RAISE EXCEPTION 'idempotency key already used by another governance event' USING ERRCODE = 'unique_violation';
  END IF;

  -- 7. Event append and supported projection update: same transaction as step 8.
  SELECT * INTO v_ev FROM public.append_workspace_governance_event(
    p_event_id, p_aggregate_type, p_aggregate_id, p_action,
    p_actor_membership_id, r.authn_event_ref, r.authority_ref, r.policy_version,
    p_idempotency_key, r.payload_digest, p_event_payload, p_effective_at);

  -- 8. Mark consumed (single-use). The guard accepts this transition only for this receipt id.
  PERFORM set_config('receipt.consume_active', p_receipt_id::text, true);
  UPDATE public.governance_proof_receipts
     SET status = 'consumed', consumed_at = now(),
         consumed_event_id = v_ev.event_id, consumed_idempotency_key = p_idempotency_key
   WHERE receipt_id = p_receipt_id;
  PERFORM set_config('receipt.consume_active', '', true);

  RETURN QUERY SELECT v_ev.event_id, v_ev.event_sequence;
END;
$body$;

ALTER FUNCTION consume_governance_receipt_and_apply(uuid,uuid,text,text,uuid,uuid,text,bytea,text,text,jsonb,uuid,timestamptz)
  OWNER TO :"owner_role";
REVOKE ALL ON FUNCTION consume_governance_receipt_and_apply(uuid,uuid,text,text,uuid,uuid,text,bytea,text,text,jsonb,uuid,timestamptz)
  FROM PUBLIC, :"owner_role";
GRANT EXECUTE ON FUNCTION consume_governance_receipt_and_apply(uuid,uuid,text,text,uuid,uuid,text,bytea,text,text,jsonb,uuid,timestamptz)
  TO :"adapter_role";
COMMIT;
