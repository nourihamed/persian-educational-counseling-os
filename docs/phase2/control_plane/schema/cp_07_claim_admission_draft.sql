-- CONTROL PLANE — DRAFT: atomic initial student identity claim admission.
-- Apply after cp_01 and cp_05. Synthetic data only (D-014). Not a production migration.
-- The trusted service must normalize E.164, compute HMACs for every active/retiring key,
-- encrypt the mobile, authenticate the caller and compute payload_hash. No plaintext is stored.
BEGIN;

-- There must be exactly one current HMAC key and one current encryption key.
CREATE UNIQUE INDEX one_active_mobile_hmac_key_version
  ON mobile_hmac_key_versions ((state)) WHERE state='active';
CREATE UNIQUE INDEX one_active_mobile_encryption_key_version
  ON mobile_encryption_key_versions ((state)) WHERE state='active';

CREATE TABLE identity_admission_commands (
  idempotency_key text PRIMARY KEY CHECK (length(idempotency_key)>0),
  payload_hash bytea NOT NULL CHECK (octet_length(payload_hash)=32),
  student_id uuid NOT NULL REFERENCES platform_students(student_id)
    DEFERRABLE INITIALLY DEFERRED,
  claim_id uuid NOT NULL UNIQUE REFERENCES enrollment_claims(claim_id)
    DEFERRABLE INITIALLY DEFERRED,
  workspace_id uuid NOT NULL REFERENCES workspaces(workspace_id),
  grade_key text NOT NULL CHECK (grade_key IN ('grade_10','grade_11','grade_12')),
  recorded_at timestamptz NOT NULL DEFAULT now()
);

CREATE FUNCTION reject_identity_admission_command_mutation() RETURNS trigger
LANGUAGE plpgsql AS $body$
BEGIN
  RAISE EXCEPTION 'identity admission command log is append-only'
    USING ERRCODE='check_violation';
END; $body$;
CREATE TRIGGER identity_admission_commands_append_only
  BEFORE UPDATE OR DELETE ON identity_admission_commands
  FOR EACH ROW EXECUTE FUNCTION reject_identity_admission_command_mutation();

CREATE FUNCTION admit_student_identity_claim(
  p_idempotency_key text,
  p_payload_hash bytea,
  p_student_id uuid,
  p_claim_id uuid,
  p_workspace_id uuid,
  p_grade_key text,
  p_mobile_ciphertext bytea,
  p_cipher_key_version integer,
  p_aliases jsonb
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=pg_catalog,pg_temp
AS $$
DECLARE
  v_inserted integer;
  v_existing public.identity_admission_commands%ROWTYPE;
  v_maintenance boolean;
  v_expected_keys integer;
  v_supplied_keys integer;
  v_distinct_keys integer;
  v_alias record;
BEGIN
  IF p_idempotency_key IS NULL OR length(p_idempotency_key)=0
     OR p_payload_hash IS NULL OR octet_length(p_payload_hash)<>32
     OR p_student_id IS NULL OR p_claim_id IS NULL OR p_workspace_id IS NULL
     OR p_grade_key NOT IN ('grade_10','grade_11','grade_12')
     OR p_mobile_ciphertext IS NULL OR octet_length(p_mobile_ciphertext)=0
     OR p_cipher_key_version IS NULL
     OR p_aliases IS NULL OR jsonb_typeof(p_aliases)<>'array'
     OR jsonb_array_length(p_aliases)=0 THEN
    RAISE EXCEPTION 'identity admission arguments are invalid'
      USING ERRCODE='invalid_parameter_value';
  END IF;

  -- Reserve the idempotency key first. The deferred FKs are checked at transaction commit.
  INSERT INTO public.identity_admission_commands(
    idempotency_key,payload_hash,student_id,claim_id,workspace_id,grade_key
  ) VALUES (
    p_idempotency_key,p_payload_hash,p_student_id,p_claim_id,p_workspace_id,p_grade_key
  )
  ON CONFLICT(idempotency_key) DO NOTHING;
  GET DIAGNOSTICS v_inserted=ROW_COUNT;

  IF v_inserted=0 THEN
    SELECT * INTO v_existing
      FROM public.identity_admission_commands
     WHERE idempotency_key=p_idempotency_key
     FOR UPDATE;
    IF v_existing.payload_hash<>p_payload_hash
       OR v_existing.student_id<>p_student_id
       OR v_existing.claim_id<>p_claim_id
       OR v_existing.workspace_id<>p_workspace_id
       OR v_existing.grade_key<>p_grade_key THEN
      RAISE EXCEPTION 'identity admission idempotency key reused with different intent'
        USING ERRCODE='unique_violation';
    END IF;
    IF NOT EXISTS (
      SELECT 1 FROM public.enrollment_claims
       WHERE claim_id=v_existing.claim_id
         AND student_id=v_existing.student_id
         AND workspace_id=v_existing.workspace_id
         AND grade_key=v_existing.grade_key
    ) THEN
      RAISE EXCEPTION 'identity admission command has no matching claim'
        USING ERRCODE='integrity_constraint_violation';
    END IF;
    RETURN v_existing.claim_id;
  END IF;

  -- A shared lock is held until commit; rotation's gate UPDATE cannot pass this admission.
  SELECT maintenance_mode INTO v_maintenance
    FROM public.identity_write_gate
   WHERE singleton=true
   FOR SHARE;
  IF NOT FOUND OR v_maintenance THEN
    RAISE EXCEPTION 'identity writes are in maintenance mode or gate is unavailable'
      USING ERRCODE='object_not_in_prerequisite_state';
  END IF;

  PERFORM 1 FROM public.workspaces
   WHERE workspace_id=p_workspace_id AND status='active'
   FOR SHARE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'destination Workspace is missing or inactive'
      USING ERRCODE='foreign_key_violation';
  END IF;

  PERFORM 1 FROM public.mobile_encryption_key_versions
   WHERE key_version=p_cipher_key_version AND state='active';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'cipher key version is not the active encryption key'
      USING ERRCODE='check_violation';
  END IF;

  SELECT count(*) INTO v_expected_keys
    FROM public.mobile_hmac_key_versions
   WHERE state IN ('active','retiring');
  SELECT count(*),count(DISTINCT a.key_version)
    INTO v_supplied_keys,v_distinct_keys
    FROM jsonb_to_recordset(p_aliases) AS a(key_version integer,mobile_hmac_hex text);

  IF v_expected_keys<1 OR v_supplied_keys<>v_expected_keys OR v_distinct_keys<>v_expected_keys THEN
    RAISE EXCEPTION 'one unique HMAC alias is required for every active/retiring key version'
      USING ERRCODE='check_violation';
  END IF;

  IF EXISTS (
    SELECT 1
      FROM jsonb_to_recordset(p_aliases) AS a(key_version integer,mobile_hmac_hex text)
      LEFT JOIN public.mobile_hmac_key_versions k ON k.key_version=a.key_version
     WHERE k.key_version IS NULL
        OR k.state NOT IN ('active','retiring')
        OR a.mobile_hmac_hex IS NULL
        OR a.mobile_hmac_hex !~ '^[0-9a-fA-F]{64}$'
  ) OR EXISTS (
    SELECT 1
      FROM public.mobile_hmac_key_versions k
     WHERE k.state IN ('active','retiring')
       AND NOT EXISTS (
         SELECT 1 FROM jsonb_to_recordset(p_aliases) AS a(key_version integer,mobile_hmac_hex text)
          WHERE a.key_version=k.key_version
       )
  ) THEN
    RAISE EXCEPTION 'HMAC aliases do not exactly cover the active/retiring key set'
      USING ERRCODE='check_violation';
  END IF;

  INSERT INTO public.platform_students(student_id) VALUES (p_student_id);
  INSERT INTO public.student_ownership(
    student_id,owner_workspace_id,ownership_generation,lifecycle_state
  ) VALUES (p_student_id,p_workspace_id,1,'active');
  INSERT INTO public.enrollment_claims(
    claim_id,student_id,workspace_id,grade_key,key_version,mobile_hmac,
    claim_state,ownership_generation
  ) VALUES (
    p_claim_id,p_student_id,p_workspace_id,p_grade_key,
    (SELECT key_version FROM public.mobile_hmac_key_versions WHERE state='active'),
    (SELECT decode(a.mobile_hmac_hex,'hex')
       FROM jsonb_to_recordset(p_aliases) AS a(key_version integer,mobile_hmac_hex text)
      WHERE a.key_version=(SELECT key_version FROM public.mobile_hmac_key_versions WHERE state='active')),
    'active',1
  );

  FOR v_alias IN
    SELECT a.key_version,a.mobile_hmac_hex
      FROM jsonb_to_recordset(p_aliases) AS a(key_version integer,mobile_hmac_hex text)
     ORDER BY a.key_version
  LOOP
    INSERT INTO public.student_contact_index(
      student_id,key_version,mobile_hmac,mobile_ciphertext,cipher_key_version
    ) VALUES (
      p_student_id,v_alias.key_version,decode(v_alias.mobile_hmac_hex,'hex'),
      p_mobile_ciphertext,p_cipher_key_version
    );
    INSERT INTO public.enrollment_claim_identity_aliases(
      claim_id,grade_key,key_version,mobile_hmac,claim_state
    ) VALUES (
      p_claim_id,p_grade_key,v_alias.key_version,decode(v_alias.mobile_hmac_hex,'hex'),'active'
    );
  END LOOP;

  RETURN p_claim_id;
END;
$$;

REVOKE ALL ON FUNCTION admit_student_identity_claim(text,bytea,uuid,uuid,uuid,text,bytea,integer,jsonb) FROM PUBLIC;
COMMIT;
