-- Workspace governance event ledger (Phase 2 draft; synthetic data only).
-- This is an append-only evidence ledger, NOT a complete authorization command service.
-- The caller must be a trusted service that has independently verified authentication,
-- grant authority, exact target/scope and policy. Runtime roles receive no table/function access.

BEGIN;

CREATE TABLE workspace_governance_events (
  event_id uuid PRIMARY KEY,
  aggregate_type text NOT NULL CHECK (aggregate_type IN (
    'membership','membership_role','membership_permission',
    'guardian_relationship','guardian_permission'
  )),
  aggregate_id uuid NOT NULL,
  event_sequence bigint NOT NULL CHECK (event_sequence > 0),
  event_type text NOT NULL CHECK (event_type IN (
    'membership_invited','membership_activated','membership_suspended','membership_reactivated','membership_ended',
    'role_granted','role_revoked',
    'permission_granted','permission_revoked','permission_scope_changed',
    'guardian_relationship_claimed','guardian_verification_submitted','guardian_verified',
    'guardian_verification_rejected','guardian_relationship_revoked','guardian_relationship_disputed','guardian_relationship_reinstated',
    'guardian_permission_granted','guardian_permission_expired','guardian_permission_revoked','guardian_permission_scope_changed'
  )),
  actor_membership_id uuid REFERENCES workspace_memberships(membership_id),
  authn_event_ref text,
  authority_ref text,
  policy_version text NOT NULL,
  idempotency_key text NOT NULL UNIQUE,
  payload_hash bytea NOT NULL CHECK (octet_length(payload_hash)=32),
  event_payload jsonb NOT NULL,
  effective_at timestamptz NOT NULL,
  recorded_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(aggregate_type,aggregate_id,event_sequence),
  CHECK (actor_membership_id IS NULL OR (authn_event_ref IS NOT NULL AND length(btrim(authn_event_ref))>0)),
  CHECK (event_type NOT IN (
    'role_granted','permission_granted','guardian_verified',
    'guardian_permission_granted','guardian_relationship_reinstated'
  ) OR (authority_ref IS NOT NULL AND length(btrim(authority_ref))>0))
);

CREATE INDEX workspace_governance_events_aggregate_idx
  ON workspace_governance_events(aggregate_type,aggregate_id,event_sequence DESC);

CREATE FUNCTION reject_workspace_governance_event_mutation()
RETURNS trigger LANGUAGE plpgsql AS $body$
BEGIN
  RAISE EXCEPTION 'workspace_governance_events is append-only' USING ERRCODE='check_violation';
END; $body$;

CREATE TRIGGER workspace_governance_events_append_only
  BEFORE UPDATE OR DELETE ON workspace_governance_events
  FOR EACH ROW EXECUTE FUNCTION reject_workspace_governance_event_mutation();

CREATE FUNCTION append_workspace_governance_event(
  p_event_id uuid,
  p_aggregate_type text,
  p_aggregate_id uuid,
  p_event_type text,
  p_actor_membership_id uuid,
  p_authn_event_ref text,
  p_authority_ref text,
  p_policy_version text,
  p_idempotency_key text,
  p_payload_hash bytea,
  p_event_payload jsonb,
  p_effective_at timestamptz
) RETURNS TABLE(event_id uuid,event_sequence bigint)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,public
AS $body$
DECLARE
  v_existing public.workspace_governance_events%ROWTYPE;
  v_sequence bigint;
  v_role_key text;
  v_permission_key text;
  v_resource_scope jsonb;
  v_membership_status text;
BEGIN
  IF p_event_id IS NULL OR p_aggregate_type IS NULL OR p_aggregate_id IS NULL
     OR p_event_type IS NULL OR p_idempotency_key IS NULL
     OR length(btrim(p_idempotency_key))=0 OR p_policy_version IS NULL
     OR length(btrim(p_policy_version))=0 OR p_payload_hash IS NULL
     OR octet_length(p_payload_hash)<>32 OR p_event_payload IS NULL
     OR jsonb_typeof(p_event_payload)<>'object' OR p_effective_at IS NULL THEN
    RAISE EXCEPTION 'required governance event fields missing or invalid' USING ERRCODE='invalid_parameter_value';
  END IF;

  -- Fail closed for guardian changes until Q-007 and trusted legal verification are approved.
  IF p_aggregate_type IN ('guardian_relationship','guardian_permission') THEN
    RAISE EXCEPTION 'guardian governance projection is blocked pending Q-007/legal verification'
      USING ERRCODE='feature_not_supported';
  END IF;

  -- Validate event family and its exact projection payload before writing any event.
  IF p_event_type IN ('role_granted','role_revoked') THEN
    IF p_aggregate_type<>'membership_role'
       OR jsonb_typeof(p_event_payload->'role_key')<>'string'
       OR length(btrim(p_event_payload->>'role_key'))=0 THEN
      RAISE EXCEPTION 'role event requires membership_role aggregate and non-empty role_key'
        USING ERRCODE='invalid_parameter_value';
    END IF;
    v_role_key:=p_event_payload->>'role_key';
  ELSIF p_event_type IN ('permission_granted','permission_revoked','permission_scope_changed') THEN
    IF p_aggregate_type<>'membership_permission'
       OR jsonb_typeof(p_event_payload->'permission_key')<>'string'
       OR length(btrim(p_event_payload->>'permission_key'))=0 THEN
      RAISE EXCEPTION 'permission event requires membership_permission aggregate and non-empty permission_key'
        USING ERRCODE='invalid_parameter_value';
    END IF;
    v_permission_key:=p_event_payload->>'permission_key';
    IF p_event_type IN ('permission_granted','permission_scope_changed') THEN
      IF jsonb_typeof(p_event_payload->'resource_scope')<>'object' THEN
        RAISE EXCEPTION 'permission grant/scope change requires object resource_scope'
          USING ERRCODE='invalid_parameter_value';
      END IF;
      v_resource_scope:=p_event_payload->'resource_scope';
    END IF;
  ELSIF p_event_type IN ('membership_invited','membership_activated','membership_suspended',
                          'membership_reactivated','membership_ended') THEN
    IF p_aggregate_type<>'membership' THEN
      RAISE EXCEPTION 'membership lifecycle event requires membership aggregate'
        USING ERRCODE='invalid_parameter_value';
    END IF;
  ELSE
    RAISE EXCEPTION 'event type is not supported by the current projection materializer'
      USING ERRCODE='feature_not_supported';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(p_aggregate_type||':'||p_aggregate_id::text,0));

  SELECT * INTO v_existing FROM public.workspace_governance_events
    WHERE idempotency_key=p_idempotency_key;
  IF FOUND THEN
    IF v_existing.payload_hash<>p_payload_hash
       OR v_existing.aggregate_type<>p_aggregate_type
       OR v_existing.aggregate_id<>p_aggregate_id
       OR v_existing.event_type<>p_event_type
       OR v_existing.event_payload<>p_event_payload
       OR v_existing.actor_membership_id IS DISTINCT FROM p_actor_membership_id
       OR v_existing.authn_event_ref IS DISTINCT FROM p_authn_event_ref
       OR v_existing.authority_ref IS DISTINCT FROM p_authority_ref
       OR v_existing.policy_version<>p_policy_version
       OR v_existing.effective_at<>p_effective_at THEN
      RAISE EXCEPTION 'governance idempotency key reused with different intent'
        USING ERRCODE='unique_violation';
    END IF;
    RETURN QUERY SELECT v_existing.event_id,v_existing.event_sequence;
    RETURN;
  END IF;

  IF p_actor_membership_id IS NOT NULL THEN
    PERFORM 1 FROM public.workspace_memberships
      WHERE membership_id=p_actor_membership_id AND status='active';
    IF NOT FOUND THEN
      RAISE EXCEPTION 'governance actor membership is not active' USING ERRCODE='insufficient_privilege';
    END IF;
    IF p_authn_event_ref IS NULL OR length(btrim(p_authn_event_ref))=0 THEN
      RAISE EXCEPTION 'authenticated actor event reference is required' USING ERRCODE='invalid_parameter_value';
    END IF;
  END IF;

  IF p_event_type IN ('role_granted','permission_granted','guardian_verified',
                      'guardian_permission_granted','guardian_relationship_reinstated')
     AND (p_authority_ref IS NULL OR length(btrim(p_authority_ref))=0) THEN
    RAISE EXCEPTION 'authority evidence reference is required for grant/verification' USING ERRCODE='invalid_parameter_value';
  END IF;

  SELECT coalesce(max(e.event_sequence),0)+1 INTO v_sequence
    FROM public.workspace_governance_events e
    WHERE e.aggregate_type=p_aggregate_type AND e.aggregate_id=p_aggregate_id;

  INSERT INTO public.workspace_governance_events(
    event_id,aggregate_type,aggregate_id,event_sequence,event_type,
    actor_membership_id,authn_event_ref,authority_ref,policy_version,
    idempotency_key,payload_hash,event_payload,effective_at
  ) VALUES (
    p_event_id,p_aggregate_type,p_aggregate_id,v_sequence,p_event_type,
    p_actor_membership_id,p_authn_event_ref,p_authority_ref,p_policy_version,
    p_idempotency_key,p_payload_hash,p_event_payload,p_effective_at
  );

  -- Materialize supported projections in the SAME transaction as the immutable event.
  IF p_event_type='role_granted' THEN
    INSERT INTO public.membership_roles(membership_id,role_key)
    VALUES(p_aggregate_id,v_role_key) ON CONFLICT(membership_id,role_key) DO NOTHING;
  ELSIF p_event_type='role_revoked' THEN
    DELETE FROM public.membership_roles
      WHERE membership_id=p_aggregate_id AND role_key=v_role_key;
  ELSIF p_event_type='permission_granted' THEN
    INSERT INTO public.membership_permissions(membership_id,permission_key,resource_scope)
    VALUES(p_aggregate_id,v_permission_key,v_resource_scope)
    ON CONFLICT(membership_id,permission_key)
    DO UPDATE SET resource_scope=EXCLUDED.resource_scope,granted_at=now();
  ELSIF p_event_type='permission_scope_changed' THEN
    UPDATE public.membership_permissions
       SET resource_scope=v_resource_scope,granted_at=now()
     WHERE membership_id=p_aggregate_id AND permission_key=v_permission_key;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'permission scope change requires an existing permission projection'
        USING ERRCODE='no_data_found';
    END IF;
  ELSIF p_event_type='permission_revoked' THEN
    DELETE FROM public.membership_permissions
      WHERE membership_id=p_aggregate_id AND permission_key=v_permission_key;
  ELSE
    v_membership_status:=CASE p_event_type
      WHEN 'membership_invited' THEN 'invited'
      WHEN 'membership_activated' THEN 'active'
      WHEN 'membership_reactivated' THEN 'active'
      WHEN 'membership_suspended' THEN 'suspended'
      WHEN 'membership_ended' THEN 'ended'
    END;
    UPDATE public.workspace_memberships
       SET status=v_membership_status,
           ended_at=CASE WHEN v_membership_status='ended' THEN p_effective_at ELSE NULL END
     WHERE membership_id=p_aggregate_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'membership lifecycle target does not exist'
        USING ERRCODE='no_data_found';
    END IF;
    IF v_membership_status IN ('suspended','ended') THEN
      DELETE FROM public.membership_roles WHERE membership_id=p_aggregate_id;
      DELETE FROM public.membership_permissions WHERE membership_id=p_aggregate_id;
    END IF;
  END IF;

  RETURN QUERY SELECT p_event_id,v_sequence;
END; $body$;

REVOKE ALL ON TABLE workspace_governance_events FROM PUBLIC;
REVOKE ALL ON FUNCTION append_workspace_governance_event(uuid,text,uuid,text,uuid,text,text,text,text,bytea,jsonb,timestamptz) FROM PUBLIC;

COMMIT;

-- Explicit limitations:
-- 1. This ledger does not update membership_roles, membership_permissions or guardian projections.
-- 2. No runtime/service role is granted EXECUTE yet; a separately reviewed trusted authorization
--    adapter must validate signed/opaque authority assertions and then call this function.
-- 3. A non-empty authority_ref/authn_event_ref is a reference, not cryptographic proof.
-- 4. Guardian legal eligibility remains blocked by unresolved Q-007.