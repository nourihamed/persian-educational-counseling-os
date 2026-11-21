-- CONTROL PLANE — DRAFT: idempotent transfer command admission.
-- Apply after cp_01 and cp_02. Not production code; authenticated service boundary required.
BEGIN;

CREATE FUNCTION guard_command_log_mutation() RETURNS trigger LANGUAGE plpgsql AS $body$
BEGIN
  IF TG_OP='DELETE' THEN
    RAISE EXCEPTION 'command_log is append-only' USING ERRCODE='check_violation';
  END IF;
  IF NEW.idempotency_key IS DISTINCT FROM OLD.idempotency_key
     OR NEW.command_name IS DISTINCT FROM OLD.command_name
     OR NEW.payload_hash IS DISTINCT FROM OLD.payload_hash
     OR NEW.recorded_at IS DISTINCT FROM OLD.recorded_at
     OR (OLD.result_case_id IS NOT NULL AND NEW.result_case_id IS DISTINCT FROM OLD.result_case_id)
     OR (OLD.result_case_id IS NULL AND NEW.result_case_id IS NULL) THEN
    RAISE EXCEPTION 'command identity/payload is immutable; only null-to-result binding is allowed'
      USING ERRCODE='check_violation';
  END IF;
  RETURN NEW;
END; $body$;
CREATE TRIGGER command_log_immutable
  BEFORE UPDATE OR DELETE ON command_log
  FOR EACH ROW EXECUTE FUNCTION guard_command_log_mutation();

CREATE FUNCTION request_transfer_case_idempotent(
    p_idempotency_key text,
    p_payload_hash bytea,
    p_case_id uuid,
    p_student_id uuid,
    p_source_workspace_id uuid,
    p_destination_workspace_id uuid,
    p_expected_generation bigint,
    p_initiator_kind text
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_inserted integer;
    v_existing public.command_log%ROWTYPE;
BEGIN
    IF p_idempotency_key IS NULL OR length(p_idempotency_key)=0
       OR p_payload_hash IS NULL OR octet_length(p_payload_hash)<>32 THEN
        RAISE EXCEPTION 'invalid idempotency key or canonical payload hash'
          USING ERRCODE='invalid_parameter_value';
    END IF;

    INSERT INTO public.command_log(idempotency_key,command_name,payload_hash)
    VALUES(p_idempotency_key,'request_transfer_case',p_payload_hash)
    ON CONFLICT (idempotency_key) DO NOTHING;
    GET DIAGNOSTICS v_inserted = ROW_COUNT;

    IF v_inserted = 0 THEN
        SELECT * INTO v_existing FROM public.command_log
         WHERE idempotency_key=p_idempotency_key FOR UPDATE;
        IF v_existing.command_name <> 'request_transfer_case'
           OR v_existing.payload_hash <> p_payload_hash THEN
            RAISE EXCEPTION 'idempotency key reused with a different command or payload'
              USING ERRCODE='unique_violation';
        END IF;
        IF v_existing.result_case_id IS NULL THEN
            RAISE EXCEPTION 'idempotent command is pending; retry after transaction resolution'
              USING ERRCODE='serialization_failure';
        END IF;
        RETURN v_existing.result_case_id;
    END IF;

    INSERT INTO public.transfer_cases(
      case_id,student_id,source_workspace_id,destination_workspace_id,
      expected_generation,initiator_kind,state,idempotency_key
    ) VALUES (
      p_case_id,p_student_id,p_source_workspace_id,p_destination_workspace_id,
      p_expected_generation,p_initiator_kind,'requested',p_idempotency_key
    );

    UPDATE public.command_log SET result_case_id=p_case_id
     WHERE idempotency_key=p_idempotency_key;
    RETURN p_case_id;
END;
$$;

REVOKE ALL ON FUNCTION request_transfer_case_idempotent(text,bytea,uuid,uuid,uuid,uuid,bigint,text) FROM PUBLIC;
COMMIT;
