-- CONTROL PLANE — DRAFT: HMAC rotation gate and alias completeness enforcement.
-- Apply after cp_01 and before cp_02..cp_04/tests. Not production-ready; KMS/HSM is external.
BEGIN;

CREATE FUNCTION assert_claim_alias_coverage(p_claim_id uuid) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE
  v_state text;
  v_expected integer;
  v_actual integer;
  v_student uuid;
  v_grade text;
BEGIN
  SELECT student_id, grade_key, claim_state
    INTO v_student, v_grade, v_state
    FROM public.enrollment_claims WHERE claim_id=p_claim_id;
  IF NOT FOUND THEN RETURN; END IF;

  IF v_state IN ('active','transfer_pending') THEN
    SELECT count(*) INTO v_expected FROM public.mobile_hmac_key_versions
     WHERE state IN ('active','retiring');
    SELECT count(*) INTO v_actual
      FROM public.enrollment_claim_identity_aliases a
      JOIN public.student_contact_index ci
        ON ci.student_id=v_student
       AND ci.key_version=a.key_version
       AND ci.mobile_hmac=a.mobile_hmac
     WHERE a.claim_id=p_claim_id
       AND a.grade_key=v_grade
       AND a.claim_state IN ('active','transfer_pending')
       AND a.key_version IN (SELECT key_version FROM public.mobile_hmac_key_versions WHERE state IN ('active','retiring'));
    IF v_expected=0 OR v_actual<>v_expected THEN
      RAISE EXCEPTION 'claim % has % verified active/retiring HMAC aliases; expected %',p_claim_id,v_actual,v_expected
        USING ERRCODE='check_violation';
    END IF;
  ELSE
    SELECT count(*) INTO v_actual FROM public.enrollment_claim_identity_aliases
     WHERE claim_id=p_claim_id AND claim_state IN ('active','transfer_pending');
    IF v_actual<>0 THEN
      RAISE EXCEPTION 'non-holding claim % still has % active aliases',p_claim_id,v_actual
        USING ERRCODE='check_violation';
    END IF;
  END IF;
END; $$;

CREATE FUNCTION guard_claim_mutation_during_rotation() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE v_maintenance boolean;
BEGIN
  SELECT maintenance_mode INTO v_maintenance
    FROM public.identity_write_gate WHERE singleton=true FOR SHARE;
  IF NOT FOUND OR v_maintenance IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'identity claim writes are paused or maintenance gate is unavailable'
      USING ERRCODE='object_not_in_prerequisite_state';
  END IF;
  IF TG_OP='DELETE' THEN RETURN OLD; END IF;
  RETURN NEW;
END; $$;
CREATE TRIGGER enrollment_claims_rotation_gate
  BEFORE INSERT OR UPDATE OR DELETE ON enrollment_claims
  FOR EACH ROW EXECUTE FUNCTION guard_claim_mutation_during_rotation();

CREATE FUNCTION sync_claim_alias_state() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.claim_state IS DISTINCT FROM OLD.claim_state THEN
    UPDATE public.enrollment_claim_identity_aliases
       SET claim_state=NEW.claim_state
     WHERE claim_id=NEW.claim_id;
  END IF;
  RETURN NEW;
END; $$;
CREATE TRIGGER enrollment_claims_sync_alias_state
  AFTER UPDATE OF claim_state ON enrollment_claims
  FOR EACH ROW EXECUTE FUNCTION sync_claim_alias_state();

CREATE FUNCTION deferred_check_claim_alias_coverage() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE v_id uuid;
BEGIN
  IF TG_OP='DELETE' THEN v_id:=OLD.claim_id; ELSE v_id:=NEW.claim_id; END IF;
  PERFORM public.assert_claim_alias_coverage(v_id);
  RETURN NULL;
END; $$;
CREATE CONSTRAINT TRIGGER enrollment_claim_alias_coverage_claim
  AFTER INSERT OR UPDATE ON enrollment_claims
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION deferred_check_claim_alias_coverage();
CREATE CONSTRAINT TRIGGER enrollment_claim_alias_coverage_alias
  AFTER INSERT OR UPDATE OR DELETE ON enrollment_claim_identity_aliases
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION deferred_check_claim_alias_coverage();

CREATE FUNCTION assert_all_claim_alias_coverage() RETURNS void
LANGUAGE plpgsql AS $body$
DECLARE r record;
BEGIN
  FOR r IN SELECT claim_id FROM public.enrollment_claims
            WHERE claim_state IN ('active','transfer_pending')
  LOOP
    PERFORM public.assert_claim_alias_coverage(r.claim_id);
  END LOOP;
END; $body$;

CREATE FUNCTION deferred_check_all_claim_alias_coverage() RETURNS trigger
LANGUAGE plpgsql AS $body$
BEGIN
  PERFORM public.assert_all_claim_alias_coverage();
  RETURN NULL;
END; $body$;
CREATE CONSTRAINT TRIGGER hmac_key_version_alias_coverage
  AFTER INSERT OR UPDATE OR DELETE ON mobile_hmac_key_versions
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION deferred_check_all_claim_alias_coverage();
CREATE CONSTRAINT TRIGGER contact_index_alias_coverage
  AFTER INSERT OR UPDATE OR DELETE ON student_contact_index
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION deferred_check_all_claim_alias_coverage();

-- Begin rotation: waits for in-flight claim mutations (they hold FOR SHARE on the gate row),
-- then pauses all claim changes until complete_identity_hmac_rotation succeeds.
CREATE FUNCTION begin_identity_hmac_rotation() RETURNS bigint
LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,pg_temp AS $$
DECLARE v_epoch bigint;
BEGIN
  UPDATE public.identity_write_gate
     SET maintenance_mode=true, rotation_epoch=rotation_epoch+1, changed_at=now()
   WHERE singleton=true AND maintenance_mode=false
   RETURNING rotation_epoch INTO v_epoch;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'identity rotation is already in maintenance mode'
      USING ERRCODE='object_not_in_prerequisite_state';
  END IF;
  RETURN v_epoch;
END; $$;
REVOKE ALL ON FUNCTION begin_identity_hmac_rotation() FROM PUBLIC;

-- Complete rotation only after the new key version is staged as 'retiring', all
-- contact-index rows and claim aliases are backfilled, and deferred checks pass.
CREATE FUNCTION complete_identity_hmac_rotation(p_new_key_version integer) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,pg_temp AS $$
DECLARE v_maintenance boolean;
BEGIN
  SELECT maintenance_mode INTO v_maintenance
    FROM public.identity_write_gate WHERE singleton=true FOR UPDATE;
  IF NOT FOUND OR v_maintenance IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'identity rotation is not in maintenance mode or gate is unavailable'
      USING ERRCODE='object_not_in_prerequisite_state';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.mobile_hmac_key_versions
                  WHERE key_version=p_new_key_version AND state='retiring') THEN
    RAISE EXCEPTION 'new HMAC key version must be staged as retiring'
      USING ERRCODE='check_violation';
  END IF;

  PERFORM public.assert_all_claim_alias_coverage();
  UPDATE public.mobile_hmac_key_versions
     SET state='retiring'
   WHERE state='active' AND key_version<>p_new_key_version;
  UPDATE public.mobile_hmac_key_versions
     SET state='active', activated_at=now(), retired_at=NULL
   WHERE key_version=p_new_key_version;
  PERFORM public.assert_all_claim_alias_coverage();

  UPDATE public.identity_write_gate
     SET maintenance_mode=false, changed_at=now()
   WHERE singleton=true;
END; $$;
REVOKE ALL ON FUNCTION complete_identity_hmac_rotation(integer) FROM PUBLIC;

-- Retire an old version only after overlap/recovery policy is approved. Old HMAC aliases and
-- that version's contact-index row are removed; ciphertext remains in the surviving active row.
CREATE FUNCTION retire_identity_hmac_version(p_old_key_version integer) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,pg_temp AS $$
DECLARE v_maintenance boolean;
BEGIN
  SELECT maintenance_mode INTO v_maintenance
    FROM public.identity_write_gate WHERE singleton=true FOR UPDATE;
  IF NOT FOUND OR v_maintenance IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'retirement requires identity maintenance mode and an available gate'
      USING ERRCODE='object_not_in_prerequisite_state';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.mobile_hmac_key_versions
                  WHERE key_version=p_old_key_version AND state='retiring') THEN
    RAISE EXCEPTION 'only a retiring key version may be retired'
      USING ERRCODE='check_violation';
  END IF;
  IF (SELECT count(*) FROM public.mobile_hmac_key_versions WHERE state='active')=0 THEN
    RAISE EXCEPTION 'cannot retire the last active HMAC key version'
      USING ERRCODE='check_violation';
  END IF;
  UPDATE public.mobile_hmac_key_versions
     SET state='retired', retired_at=now()
   WHERE key_version=p_old_key_version;
  DELETE FROM public.enrollment_claim_identity_aliases WHERE key_version=p_old_key_version;
  DELETE FROM public.student_contact_index WHERE key_version=p_old_key_version;
  PERFORM public.assert_all_claim_alias_coverage();
  UPDATE public.identity_write_gate
     SET maintenance_mode=false, changed_at=now()
   WHERE singleton=true;
END; $$;
REVOKE ALL ON FUNCTION retire_identity_hmac_version(integer) FROM PUBLIC;

COMMIT;
