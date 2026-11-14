-- CONTROL PLANE — DRAFT: student mobile contact change (CONTACT_CHANGE_REVERIFICATION_CONTRACT.md).
-- Apply after cp_01, cp_05 and cp_07. Roles and grants: cp_09 (after cp_06). Synthetic data only (D-014).
-- Not a production migration. The database never sees plaintext E.164, OTPs or key material.
-- The database CANNOT prove that a proof was really verified or that the HMACs were derived correctly:
-- it enforces single use, exact binding, key coverage, uniqueness, atomicity and history.
BEGIN;

-- One-time proof reference registered by the trusted proof verifier (INSERT only; see cp_09).
-- new_contact_hmac is the keyed fingerprint of the proposed number under new_contact_key_version.
CREATE TABLE contact_change_proofs (
  proof_id                uuid PRIMARY KEY,
  nonce_digest            bytea NOT NULL UNIQUE CHECK (octet_length(nonce_digest)=32),
  purpose                 text NOT NULL CHECK (purpose='student_mobile_change'),
  student_id              uuid NOT NULL REFERENCES platform_students(student_id),
  expected_workspace_id   uuid NOT NULL REFERENCES workspaces(workspace_id),
  expected_generation     bigint NOT NULL CHECK (expected_generation>=1),
  new_contact_key_version integer NOT NULL REFERENCES mobile_hmac_key_versions(key_version),
  new_contact_hmac        bytea NOT NULL CHECK (octet_length(new_contact_hmac)=32),
  authn_event_ref         text NOT NULL CHECK (length(btrim(authn_event_ref))>0),
  verifier_outcome        text NOT NULL CHECK (verifier_outcome='verified'),   -- recorded input, not proof by itself
  issued_at               timestamptz NOT NULL,
  expires_at              timestamptz NOT NULL,
  status                  text NOT NULL DEFAULT 'registered' CHECK (status IN ('registered','consumed','revoked')),
  consumed_at             timestamptz,
  consumed_by_command     text,
  registered_at           timestamptz NOT NULL DEFAULT now(),
  CHECK (expires_at > issued_at),
  CHECK (status='consumed' OR (consumed_at IS NULL AND consumed_by_command IS NULL)),
  CHECK (status<>'consumed' OR (consumed_at IS NOT NULL AND consumed_by_command IS NOT NULL))
);
CREATE FUNCTION contact_change_proof_guard() RETURNS trigger LANGUAGE plpgsql AS $body$
BEGIN
  IF TG_OP='INSERT' THEN
    IF NEW.status IS DISTINCT FROM 'registered' OR NEW.consumed_at IS NOT NULL OR NEW.consumed_by_command IS NOT NULL THEN
      RAISE EXCEPTION 'a contact-change proof must be registered unconsumed' USING ERRCODE='check_violation';
    END IF;
    RETURN NEW;
  END IF;
  IF TG_OP='DELETE' THEN
    RAISE EXCEPTION 'contact-change proofs are never deleted' USING ERRCODE='check_violation';
  END IF;
  IF OLD.status<>'registered' THEN
    RAISE EXCEPTION 'contact-change proof is terminal (%) and immutable', OLD.status USING ERRCODE='check_violation';
  END IF;
  IF (NEW.proof_id,NEW.nonce_digest,NEW.purpose,NEW.student_id,NEW.expected_workspace_id,NEW.expected_generation,
      NEW.new_contact_key_version,NEW.new_contact_hmac,NEW.authn_event_ref,NEW.verifier_outcome,NEW.issued_at,NEW.expires_at,NEW.registered_at)
     IS DISTINCT FROM
     (OLD.proof_id,OLD.nonce_digest,OLD.purpose,OLD.student_id,OLD.expected_workspace_id,OLD.expected_generation,
      OLD.new_contact_key_version,OLD.new_contact_hmac,OLD.authn_event_ref,OLD.verifier_outcome,OLD.issued_at,OLD.expires_at,OLD.registered_at) THEN
    RAISE EXCEPTION 'contact-change proof binding is immutable' USING ERRCODE='check_violation';
  END IF;
  IF NEW.status='registered' AND (NEW.consumed_at IS NOT NULL OR NEW.consumed_by_command IS NOT NULL) THEN
    RAISE EXCEPTION 'consumption metadata requires the registered->consumed transition' USING ERRCODE='check_violation';
  END IF;
  RETURN NEW;
END; $body$;
CREATE TRIGGER contact_change_proofs_guard BEFORE INSERT OR UPDATE OR DELETE ON contact_change_proofs
  FOR EACH ROW EXECUTE FUNCTION contact_change_proof_guard();

-- Append-only idempotency ledger. A proof authorises exactly one command (UNIQUE proof_id).
CREATE TABLE contact_change_commands (
  idempotency_key       text PRIMARY KEY CHECK (length(btrim(idempotency_key))>0),
  payload_hash          bytea NOT NULL CHECK (octet_length(payload_hash)=32),
  student_id            uuid NOT NULL REFERENCES platform_students(student_id),
  expected_workspace_id uuid NOT NULL REFERENCES workspaces(workspace_id),
  expected_generation   bigint NOT NULL,
  proof_id              uuid NOT NULL UNIQUE REFERENCES contact_change_proofs(proof_id),
  claim_id              uuid NOT NULL REFERENCES enrollment_claims(claim_id),
  recorded_at           timestamptz NOT NULL DEFAULT now()
);
-- Append-only audit of applied changes: keyed fingerprints only, never the number.
CREATE TABLE student_contact_change_audit (
  audit_id            uuid PRIMARY KEY,
  idempotency_key     text NOT NULL UNIQUE REFERENCES contact_change_commands(idempotency_key),
  student_id          uuid NOT NULL REFERENCES platform_students(student_id),
  claim_id            uuid NOT NULL REFERENCES enrollment_claims(claim_id),
  proof_id            uuid NOT NULL REFERENCES contact_change_proofs(proof_id),
  authn_event_ref     text NOT NULL,
  old_fingerprints    jsonb NOT NULL,   -- {"<key_version>":"<hmac hex>"}
  new_fingerprints    jsonb NOT NULL,
  cipher_key_version  integer NOT NULL,
  ownership_generation bigint NOT NULL,
  outcome             text NOT NULL CHECK (outcome='applied'),
  recorded_at         timestamptz NOT NULL DEFAULT now()
);
CREATE FUNCTION contact_change_append_only() RETURNS trigger LANGUAGE plpgsql AS $body$
BEGIN
  RAISE EXCEPTION '% is append-only', TG_TABLE_NAME USING ERRCODE='check_violation';
END; $body$;
CREATE TRIGGER contact_change_commands_append_only BEFORE UPDATE OR DELETE ON contact_change_commands
  FOR EACH ROW EXECUTE FUNCTION contact_change_append_only();
CREATE TRIGGER student_contact_change_audit_append_only BEFORE UPDATE OR DELETE ON student_contact_change_audit
  FOR EACH ROW EXECUTE FUNCTION contact_change_append_only();

-- Lock order (same as initial admission): identity gate -> student ownership -> active claim -> contact/alias rows.
CREATE FUNCTION change_student_mobile_contact(
  p_idempotency_key text,
  p_payload_hash bytea,
  p_student_id uuid,
  p_expected_workspace_id uuid,
  p_expected_generation bigint,
  p_proof_id uuid,
  p_mobile_ciphertext bytea,
  p_cipher_key_version integer,
  p_aliases jsonb
) RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=pg_catalog,pg_temp
AS $$
DECLARE
  v_inserted integer;
  v_cmd public.contact_change_commands%ROWTYPE;
  v_maintenance boolean;
  v_owner uuid; v_gen bigint; v_life text;
  v_payload jsonb;
  v_event_id uuid;
  v_claim public.enrollment_claims%ROWTYPE;
  v_claims integer;
  v_proof public.contact_change_proofs%ROWTYPE;
  v_expected_keys integer; v_supplied_keys integer; v_distinct_keys integer;
  v_alias record; v_n integer;
  v_old jsonb; v_new jsonb;
BEGIN
  IF p_idempotency_key IS NULL OR length(btrim(p_idempotency_key))=0
     OR p_payload_hash IS NULL OR octet_length(p_payload_hash)<>32
     OR p_student_id IS NULL OR p_expected_workspace_id IS NULL OR p_expected_generation IS NULL
     OR p_proof_id IS NULL
     OR p_mobile_ciphertext IS NULL OR octet_length(p_mobile_ciphertext)=0
     OR p_cipher_key_version IS NULL
     OR p_aliases IS NULL OR jsonb_typeof(p_aliases)<>'array' OR jsonb_array_length(p_aliases)=0 THEN
    RAISE EXCEPTION 'contact change arguments are invalid' USING ERRCODE='invalid_parameter_value';
  END IF;

  -- Replay check first. An exact replay returns without touching anything.
  SELECT * INTO v_cmd FROM public.contact_change_commands WHERE idempotency_key=p_idempotency_key FOR UPDATE;
  IF FOUND THEN
    IF v_cmd.payload_hash IS DISTINCT FROM p_payload_hash OR v_cmd.student_id IS DISTINCT FROM p_student_id
       OR v_cmd.expected_workspace_id IS DISTINCT FROM p_expected_workspace_id
       OR v_cmd.expected_generation IS DISTINCT FROM p_expected_generation
       OR v_cmd.proof_id IS DISTINCT FROM p_proof_id THEN
      RAISE EXCEPTION 'contact change idempotency key reused with different intent' USING ERRCODE='unique_violation';
    END IF;
    RETURN 'replayed';
  END IF;

  -- 1. Identity gate (shared): serialises with HMAC rotation's exclusive gate update.
  SELECT maintenance_mode INTO v_maintenance FROM public.identity_write_gate WHERE singleton=true FOR SHARE;
  IF NOT FOUND OR v_maintenance THEN
    RAISE EXCEPTION 'identity writes are in maintenance mode or gate is unavailable'
      USING ERRCODE='object_not_in_prerequisite_state';
  END IF;

  -- 2. Ownership row: serialises with the ownership switch; stale context is rejected.
  SELECT owner_workspace_id, ownership_generation, lifecycle_state INTO v_owner, v_gen, v_life
    FROM public.student_ownership WHERE student_id=p_student_id FOR UPDATE;
  IF NOT FOUND OR v_owner IS DISTINCT FROM p_expected_workspace_id OR v_gen IS DISTINCT FROM p_expected_generation
     OR v_life IS DISTINCT FROM 'active' THEN
    RAISE EXCEPTION 'stale or unknown ownership context for contact change' USING ERRCODE='check_violation';
  END IF;

  -- 3. The single active claim.
  SELECT count(*) INTO v_claims FROM public.enrollment_claims WHERE student_id=p_student_id AND claim_state='active';
  IF v_claims<>1 THEN
    RAISE EXCEPTION 'contact change requires exactly one active claim (found %)', v_claims USING ERRCODE='check_violation';
  END IF;
  SELECT * INTO v_claim FROM public.enrollment_claims WHERE student_id=p_student_id AND claim_state='active' FOR UPDATE;
  IF v_claim.workspace_id IS DISTINCT FROM v_owner THEN
    RAISE EXCEPTION 'active claim does not belong to the owner Workspace' USING ERRCODE='check_violation';
  END IF;

  -- 4. Keys and alias coverage (before any mutation).
  PERFORM 1 FROM public.mobile_encryption_key_versions WHERE key_version=p_cipher_key_version AND state='active';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'cipher key version is not the active encryption key' USING ERRCODE='check_violation';
  END IF;
  IF (SELECT count(*) FROM public.mobile_hmac_key_versions WHERE state='active')<>1 THEN
    RAISE EXCEPTION 'exactly one active HMAC key version is required' USING ERRCODE='check_violation';
  END IF;
  SELECT count(*) INTO v_expected_keys FROM public.mobile_hmac_key_versions WHERE state IN ('active','retiring');
  SELECT count(*), count(DISTINCT a.key_version) INTO v_supplied_keys, v_distinct_keys
    FROM jsonb_to_recordset(p_aliases) AS a(key_version integer, mobile_hmac_hex text);
  IF v_supplied_keys<>v_expected_keys OR v_distinct_keys<>v_expected_keys
     OR EXISTS (SELECT 1 FROM jsonb_to_recordset(p_aliases) AS a(key_version integer, mobile_hmac_hex text)
                 LEFT JOIN public.mobile_hmac_key_versions k ON k.key_version=a.key_version
                WHERE k.key_version IS NULL OR k.state NOT IN ('active','retiring')
                   OR a.mobile_hmac_hex IS NULL OR a.mobile_hmac_hex !~ '^[0-9a-fA-F]{64}$') THEN
    RAISE EXCEPTION 'HMAC aliases do not exactly cover the active/retiring key set' USING ERRCODE='check_violation';
  END IF;

  -- 5. One-time proof: exact binding, validity, single use. A different proposed contact cannot use it.
  SELECT * INTO v_proof FROM public.contact_change_proofs WHERE proof_id=p_proof_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'contact-change proof not found' USING ERRCODE='no_data_found';
  END IF;
  IF v_proof.status<>'registered' THEN
    RAISE EXCEPTION 'contact-change proof is % and cannot be used', v_proof.status USING ERRCODE='check_violation';
  END IF;
  IF now() < v_proof.issued_at OR now() >= v_proof.expires_at THEN
    RAISE EXCEPTION 'contact-change proof is not valid at this time' USING ERRCODE='check_violation';
  END IF;
  IF v_proof.student_id IS DISTINCT FROM p_student_id
     OR v_proof.expected_workspace_id IS DISTINCT FROM p_expected_workspace_id
     OR v_proof.expected_generation IS DISTINCT FROM p_expected_generation THEN
    RAISE EXCEPTION 'contact-change proof binding mismatch: subject or ownership context' USING ERRCODE='check_violation';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM jsonb_to_recordset(p_aliases) AS a(key_version integer, mobile_hmac_hex text)
                  WHERE a.key_version=v_proof.new_contact_key_version
                    AND decode(a.mobile_hmac_hex,'hex')=v_proof.new_contact_hmac) THEN
    RAISE EXCEPTION 'contact-change proof binding mismatch: proposed contact' USING ERRCODE='check_violation';
  END IF;

  -- 6. Reserve the command (UNIQUE proof_id: one proof, one command) and consume the proof.
  INSERT INTO public.contact_change_commands(idempotency_key,payload_hash,student_id,expected_workspace_id,expected_generation,proof_id,claim_id)
  VALUES (p_idempotency_key,p_payload_hash,p_student_id,p_expected_workspace_id,p_expected_generation,p_proof_id,v_claim.claim_id);
  UPDATE public.contact_change_proofs SET status='consumed', consumed_at=now(), consumed_by_command=p_idempotency_key
   WHERE proof_id=p_proof_id;

  -- 7. Replace the contact for every live key version. Any uniqueness conflict rolls everything back.
  SELECT jsonb_object_agg(ci.key_version::text, encode(ci.mobile_hmac,'hex')) INTO v_old
    FROM public.student_contact_index ci WHERE ci.student_id=p_student_id;
  FOR v_alias IN SELECT a.key_version, a.mobile_hmac_hex
                   FROM jsonb_to_recordset(p_aliases) AS a(key_version integer, mobile_hmac_hex text) ORDER BY a.key_version LOOP
    UPDATE public.student_contact_index
       SET mobile_hmac=decode(v_alias.mobile_hmac_hex,'hex'), mobile_ciphertext=p_mobile_ciphertext,
           cipher_key_version=p_cipher_key_version, updated_at=now()
     WHERE student_id=p_student_id AND key_version=v_alias.key_version;
    GET DIAGNOSTICS v_n=ROW_COUNT;
    IF v_n<>1 THEN
      RAISE EXCEPTION 'contact index row missing for key version %', v_alias.key_version USING ERRCODE='check_violation';
    END IF;
    UPDATE public.enrollment_claim_identity_aliases
       SET mobile_hmac=decode(v_alias.mobile_hmac_hex,'hex')
     WHERE claim_id=v_claim.claim_id AND key_version=v_alias.key_version;
    GET DIAGNOSTICS v_n=ROW_COUNT;
    IF v_n<>1 THEN
      RAISE EXCEPTION 'claim alias row missing for key version %', v_alias.key_version USING ERRCODE='check_violation';
    END IF;
  END LOOP;

  -- 8. Coverage and cross-table equality for all live versions.
  PERFORM public.assert_claim_alias_coverage(v_claim.claim_id);
  -- The deferred coverage triggers would otherwise run at COMMIT as the CALLER (the executor has no table
  -- access). Run them here, inside this function's security context, then restore deferred mode.
  SET CONSTRAINTS public.enrollment_claim_alias_coverage_alias, public.contact_index_alias_coverage IMMEDIATE;
  SET CONSTRAINTS public.enrollment_claim_alias_coverage_alias, public.contact_index_alias_coverage DEFERRED;
  SELECT jsonb_object_agg(ci.key_version::text, encode(ci.mobile_hmac,'hex')) INTO v_new
    FROM public.student_contact_index ci WHERE ci.student_id=p_student_id;

  -- 9. Audit and outbox in the same transaction. No contact value in either.
  INSERT INTO public.student_contact_change_audit(audit_id,idempotency_key,student_id,claim_id,proof_id,authn_event_ref,
         old_fingerprints,new_fingerprints,cipher_key_version,ownership_generation,outcome)
  VALUES (gen_random_uuid(),p_idempotency_key,p_student_id,v_claim.claim_id,p_proof_id,v_proof.authn_event_ref,
          v_old,v_new,p_cipher_key_version,v_gen,'applied');
  v_event_id := gen_random_uuid();
  v_payload := jsonb_build_object('student_id',p_student_id::text,'command',p_idempotency_key,
                                  'ownership_generation',v_gen);
  INSERT INTO public.outbox_events(event_id,case_id,event_type,schema_version,payload,payload_hash,
                                   student_id,source_workspace_id,ownership_generation,correlation_id)
  VALUES (v_event_id,NULL,'student_contact_changed',1,v_payload,
          sha256(convert_to(v_payload::text,'UTF8')),p_student_id,v_owner,v_gen,
          md5(p_idempotency_key)::uuid);
  -- C-01: this event has exactly one required recipient, the Workspace that currently owns the student.
  IF to_regclass('public.outbox_event_recipients') IS NOT NULL THEN
    INSERT INTO public.outbox_event_recipients(event_id,workspace_id,recipient_role)
    VALUES (v_event_id,v_owner,'owner');
    SET CONSTRAINTS public.outbox_event_requires_recipient IMMEDIATE;
    SET CONSTRAINTS public.outbox_event_requires_recipient DEFERRED;
  END IF;
  RETURN 'applied';
END;
$$;
REVOKE ALL ON FUNCTION change_student_mobile_contact(text,bytea,uuid,uuid,bigint,uuid,bytea,integer,jsonb) FROM PUBLIC;
COMMIT;
