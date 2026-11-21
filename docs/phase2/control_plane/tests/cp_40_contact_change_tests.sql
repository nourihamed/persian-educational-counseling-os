-- Control Plane contact-change regression tests. Synthetic only (D-014).
-- Run on a FRESH DB after cp_01, cp_05, cp_07, cp_02, cp_03, cp_04, cp_06, cp_08, cp_09.
-- The command is always called as cp_contact_change_executor; proofs are registered as cp_contact_proof_verifier.
-- "Verified" proofs here are synthetic test inputs, not real verification.
\set ON_ERROR_STOP on
CREATE OR REPLACE FUNCTION cc_err(label text, stmt text, want text, want_msg text DEFAULT '')
RETURNS void LANGUAGE plpgsql AS $t$
BEGIN
  BEGIN
    EXECUTE stmt;
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE<>want THEN RAISE EXCEPTION 'FAIL %: got % (%), expected %',label,SQLSTATE,SQLERRM,want; END IF;
    IF want_msg<>'' AND position(want_msg IN SQLERRM)=0 THEN RAISE EXCEPTION 'FAIL %: wrong reason: %',label,SQLERRM; END IF;
    RAISE NOTICE 'PASS % (SQLSTATE %, reason verified)',label,SQLSTATE;
    RETURN;
  END;
  RAISE EXCEPTION 'FAIL %: statement unexpectedly succeeded',label;
END; $t$;
-- aliases for a synthetic number tag: key 1 -> repeat(tag,32), key 2 -> repeat(tag,31)||'00'
CREATE OR REPLACE FUNCTION cc_aliases(tag text) RETURNS jsonb LANGUAGE sql IMMUTABLE AS $t$
  SELECT jsonb_build_array(jsonb_build_object('key_version',1,'mobile_hmac_hex',repeat(tag,32)),
                           jsonb_build_object('key_version',2,'mobile_hmac_hex',repeat(tag,31)||'00'));
$t$;
-- proof for student/workspace/generation proposing number <tag> (fingerprint under active key 1)
CREATE OR REPLACE FUNCTION cc_proof(p_id uuid, p_student uuid, p_ws uuid, p_gen bigint, tag text,
  p_issued timestamptz DEFAULT now()-interval '1 minute', p_expires timestamptz DEFAULT now()+interval '10 minutes')
RETURNS void LANGUAGE sql AS $t$
  INSERT INTO contact_change_proofs(proof_id,nonce_digest,purpose,student_id,expected_workspace_id,expected_generation,
    new_contact_key_version,new_contact_hmac,authn_event_ref,verifier_outcome,issued_at,expires_at)
  VALUES (p_id, sha256(convert_to('nonce-'||p_id::text,'UTF8')), 'student_mobile_change', p_student, p_ws, p_gen,
    1, decode(repeat(tag,32),'hex'), 'synthetic-authn-'||tag, 'verified', p_issued, p_expires);
$t$;
CREATE OR REPLACE FUNCTION cc_call(p_key text, p_hash text, p_student uuid, p_ws uuid, p_gen bigint, p_proof uuid, tag text,
  p_cipher integer DEFAULT 1, p_aliases jsonb DEFAULT NULL) RETURNS text LANGUAGE sql AS $t$
  SELECT change_student_mobile_contact(p_key, sha256(convert_to(p_hash,'UTF8')), p_student, p_ws, p_gen, p_proof,
    decode('c1c2c3'||tag,'hex'), p_cipher, COALESCE(p_aliases, cc_aliases(tag)));
$t$;

-- Fixtures (owner): two Workspaces, keys (1 active, 2 retiring; cipher 1 active, 2 retired), three students.
INSERT INTO workspaces(workspace_id,workspace_type,status) VALUES
 ('a8000000-0000-0000-0000-000000000001','organization','active'),
 ('a8000000-0000-0000-0000-000000000002','organization','active');
INSERT INTO mobile_encryption_key_versions(key_version,state,key_manager_ref) VALUES (1,'active','kms://synthetic/enc-v1');
INSERT INTO mobile_hmac_key_versions(key_version,state) VALUES (1,'active'),(2,'retiring');
SELECT admit_student_identity_claim('cc-admit-1',decode(repeat('01',32),'hex'),'b8000000-0000-0000-0000-000000000001','c8000000-0000-0000-0000-000000000001','a8000000-0000-0000-0000-000000000001','grade_10',decode('aa01','hex'),1,cc_aliases('11'));
SELECT admit_student_identity_claim('cc-admit-2',decode(repeat('02',32),'hex'),'b8000000-0000-0000-0000-000000000002','c8000000-0000-0000-0000-000000000002','a8000000-0000-0000-0000-000000000002','grade_10',decode('aa02','hex'),1,cc_aliases('22'));
SELECT admit_student_identity_claim('cc-admit-3',decode(repeat('03',32),'hex'),'b8000000-0000-0000-0000-000000000003','c8000000-0000-0000-0000-000000000003','a8000000-0000-0000-0000-000000000002','grade_11',decode('aa03','hex'),1,cc_aliases('33'));

-- ---- Proof registration boundary ----
SET SESSION AUTHORIZATION cp_contact_proof_verifier;
SELECT cc_proof('d8000000-0000-0000-0000-000000000001','b8000000-0000-0000-0000-000000000001','a8000000-0000-0000-0000-000000000001',1,'44');
SELECT cc_err('CC-01 verifier cannot read proofs','SELECT count(*) FROM contact_change_proofs','42501');
SELECT cc_err('CC-02 verifier cannot consume or alter a proof',$q$UPDATE contact_change_proofs SET status='consumed'$q$,'42501');
SELECT cc_err('CC-03 verifier cannot call the contact-change command',
 $q$SELECT cc_call('k-v','h','b8000000-0000-0000-0000-000000000001','a8000000-0000-0000-0000-000000000001',1,'d8000000-0000-0000-0000-000000000001','44')$q$,'42501');
SELECT cc_err('CC-04 a proof cannot be registered already consumed',
 $q$INSERT INTO contact_change_proofs(proof_id,nonce_digest,purpose,student_id,expected_workspace_id,expected_generation,new_contact_key_version,new_contact_hmac,authn_event_ref,verifier_outcome,issued_at,expires_at,status,consumed_at,consumed_by_command) VALUES (gen_random_uuid(),sha256('n4'::bytea),'student_mobile_change','b8000000-0000-0000-0000-000000000001','a8000000-0000-0000-0000-000000000001',1,1,decode(repeat('44',32),'hex'),'a','verified',now(),now()+interval '1 minute','consumed',now(),'x')$q$,'23514','registered unconsumed');
SELECT cc_err('CC-05 a proof for another purpose cannot be registered',
 $q$INSERT INTO contact_change_proofs(proof_id,nonce_digest,purpose,student_id,expected_workspace_id,expected_generation,new_contact_key_version,new_contact_hmac,authn_event_ref,verifier_outcome,issued_at,expires_at) VALUES (gen_random_uuid(),sha256('n5'::bytea),'transfer','b8000000-0000-0000-0000-000000000001','a8000000-0000-0000-0000-000000000001',1,1,decode(repeat('44',32),'hex'),'a','verified',now(),now()+interval '1 minute')$q$,'23514');
RESET SESSION AUTHORIZATION;
SELECT cc_err('CC-06 a nonce cannot be registered twice',
 $q$INSERT INTO contact_change_proofs(proof_id,nonce_digest,purpose,student_id,expected_workspace_id,expected_generation,new_contact_key_version,new_contact_hmac,authn_event_ref,verifier_outcome,issued_at,expires_at) SELECT gen_random_uuid(),nonce_digest,purpose,student_id,expected_workspace_id,expected_generation,new_contact_key_version,new_contact_hmac,authn_event_ref,verifier_outcome,issued_at,expires_at FROM contact_change_proofs WHERE proof_id='d8000000-0000-0000-0000-000000000001'$q$,'23505');
SELECT cc_err('CC-07 proof binding is immutable (owner level)',
 $q$UPDATE contact_change_proofs SET student_id='b8000000-0000-0000-0000-000000000002' WHERE proof_id='d8000000-0000-0000-0000-000000000001'$q$,'23514','binding is immutable');
SELECT cc_err('CC-08 proofs are never deleted',
 $q$DELETE FROM contact_change_proofs WHERE proof_id='d8000000-0000-0000-0000-000000000001'$q$,'23514','never deleted');

-- ---- Role boundary for the command and tables ----
SET SESSION AUTHORIZATION cp_runtime;
SELECT cc_err('CC-09 general runtime cannot call the command',
 $q$SELECT cc_call('k-r','h','b8000000-0000-0000-0000-000000000001','a8000000-0000-0000-0000-000000000001',1,'d8000000-0000-0000-0000-000000000001','44')$q$,'42501');
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION cp_contact_change_executor;
SELECT cc_err('CC-10 executor cannot write the contact index directly',$q$UPDATE student_contact_index SET mobile_hmac=decode(repeat('99',32),'hex')$q$,'42501');
SELECT cc_err('CC-11 executor cannot write claim aliases directly',$q$UPDATE enrollment_claim_identity_aliases SET mobile_hmac=decode(repeat('99',32),'hex')$q$,'42501');
SELECT cc_err('CC-12 executor cannot register or read proofs',$q$SELECT count(*) FROM contact_change_proofs$q$,'42501');
SELECT cc_err('CC-13 executor cannot call the ownership switch',$q$SELECT switch_student_ownership(gen_random_uuid())$q$,'42501');

-- ---- Rejections before any mutation ----
SELECT cc_err('CC-14 stale ownership generation rejected',
 $q$SELECT cc_call('k-14','h14','b8000000-0000-0000-0000-000000000001','a8000000-0000-0000-0000-000000000001',2,'d8000000-0000-0000-0000-000000000001','44')$q$,'23514','stale or unknown ownership');
SELECT cc_err('CC-15 wrong owner Workspace rejected',
 $q$SELECT cc_call('k-15','h15','b8000000-0000-0000-0000-000000000001','a8000000-0000-0000-0000-000000000002',1,'d8000000-0000-0000-0000-000000000001','44')$q$,'23514','stale or unknown ownership');
SELECT cc_err('CC-16 proof cannot authorise a different proposed contact',
 $q$SELECT cc_call('k-16','h16','b8000000-0000-0000-0000-000000000001','a8000000-0000-0000-0000-000000000001',1,'d8000000-0000-0000-0000-000000000001','55')$q$,'23514','proposed contact');
SELECT cc_err('CC-17 proof of another student rejected',
 $q$SELECT cc_call('k-17','h17','b8000000-0000-0000-0000-000000000002','a8000000-0000-0000-0000-000000000002',1,'d8000000-0000-0000-0000-000000000001','44')$q$,'23514','subject or ownership context');
SELECT cc_err('CC-18 missing alias for a live key version rejected',
 $q$SELECT cc_call('k-18','h18','b8000000-0000-0000-0000-000000000001','a8000000-0000-0000-0000-000000000001',1,'d8000000-0000-0000-0000-000000000001','44',1,jsonb_build_array(jsonb_build_object('key_version',1,'mobile_hmac_hex',repeat('44',32))))$q$,'23514','exactly cover');
SELECT cc_err('CC-19 alias for an unknown key version rejected',
 $q$SELECT cc_call('k-19','h19','b8000000-0000-0000-0000-000000000001','a8000000-0000-0000-0000-000000000001',1,'d8000000-0000-0000-0000-000000000001','44',1,jsonb_build_array(jsonb_build_object('key_version',1,'mobile_hmac_hex',repeat('44',32)),jsonb_build_object('key_version',9,'mobile_hmac_hex',repeat('44',32))))$q$,'23514','exactly cover');
SELECT cc_err('CC-20 duplicate key version in aliases rejected',
 $q$SELECT cc_call('k-20','h20','b8000000-0000-0000-0000-000000000001','a8000000-0000-0000-0000-000000000001',1,'d8000000-0000-0000-0000-000000000001','44',1,jsonb_build_array(jsonb_build_object('key_version',1,'mobile_hmac_hex',repeat('44',32)),jsonb_build_object('key_version',1,'mobile_hmac_hex',repeat('44',32))))$q$,'23514','exactly cover');
SELECT cc_err('CC-21 malformed HMAC rejected',
 $q$SELECT cc_call('k-21','h21','b8000000-0000-0000-0000-000000000001','a8000000-0000-0000-0000-000000000001',1,'d8000000-0000-0000-0000-000000000001','44',1,jsonb_build_array(jsonb_build_object('key_version',1,'mobile_hmac_hex','zz'),jsonb_build_object('key_version',2,'mobile_hmac_hex',repeat('44',32))))$q$,'23514','exactly cover');
SELECT cc_err('CC-22 cipher key that is not the active encryption key rejected',
 $q$SELECT cc_call('k-22','h22','b8000000-0000-0000-0000-000000000001','a8000000-0000-0000-0000-000000000001',1,'d8000000-0000-0000-0000-000000000001','44',7)$q$,'23514','active encryption key');
SELECT cc_err('CC-23 unknown proof rejected',
 $q$SELECT cc_call('k-23','h23','b8000000-0000-0000-0000-000000000001','a8000000-0000-0000-0000-000000000001',1,gen_random_uuid(),'44')$q$,'P0002');
RESET SESSION AUTHORIZATION;

-- maintenance mode (rotation gate)
UPDATE identity_write_gate SET maintenance_mode=true WHERE singleton;
SET SESSION AUTHORIZATION cp_contact_change_executor;
SELECT cc_err('CC-24 contact change rejected while identity maintenance is active',
 $q$SELECT cc_call('k-24','h24','b8000000-0000-0000-0000-000000000001','a8000000-0000-0000-0000-000000000001',1,'d8000000-0000-0000-0000-000000000001','44')$q$,'55000','maintenance');
RESET SESSION AUTHORIZATION;
UPDATE identity_write_gate SET maintenance_mode=false WHERE singleton;

-- After all rejections nothing was written and the proof is still usable.
DO $t$ BEGIN
  IF (SELECT status FROM contact_change_proofs WHERE proof_id='d8000000-0000-0000-0000-000000000001')<>'registered'
     OR (SELECT count(*) FROM contact_change_commands)<>0 OR (SELECT count(*) FROM student_contact_change_audit)<>0
     OR (SELECT encode(mobile_hmac,'hex') FROM student_contact_index WHERE student_id='b8000000-0000-0000-0000-000000000001' AND key_version=1)<>repeat('11',32) THEN
    RAISE EXCEPTION 'FAIL CC-25';
  END IF;
  RAISE NOTICE 'PASS CC-25 rejected attempts left proof, commands, audit and contact untouched';
END $t$;

-- ---- Duplicate number, same grade, another Workspace: full rollback ----
SELECT cc_proof('d8000000-0000-0000-0000-000000000002','b8000000-0000-0000-0000-000000000001','a8000000-0000-0000-0000-000000000001',1,'22');
SET SESSION AUTHORIZATION cp_contact_change_executor;
SELECT cc_err('CC-26 number already claimed for the same grade in another Workspace rejected',
 $q$SELECT cc_call('k-26','h26','b8000000-0000-0000-0000-000000000001','a8000000-0000-0000-0000-000000000001',1,'d8000000-0000-0000-0000-000000000002','22')$q$,'23505','enrollment_claims_global_identity');
RESET SESSION AUTHORIZATION;
DO $t$ BEGIN
  IF (SELECT status FROM contact_change_proofs WHERE proof_id='d8000000-0000-0000-0000-000000000002')<>'registered'
     OR EXISTS (SELECT 1 FROM contact_change_commands WHERE idempotency_key='k-26')
     OR (SELECT count(*) FROM student_contact_index WHERE student_id='b8000000-0000-0000-0000-000000000001' AND encode(mobile_hmac,'hex') LIKE '11%')<>2 THEN
    RAISE EXCEPTION 'FAIL CC-27';
  END IF;
  RAISE NOTICE 'PASS CC-27 conflict rolled back proof consumption, command reservation and every contact row';
END $t$;

-- ---- Valid change ----
SET SESSION AUTHORIZATION cp_contact_change_executor;
DO $t$ DECLARE r text; BEGIN
  r := cc_call('k-ok','h-ok','b8000000-0000-0000-0000-000000000001','a8000000-0000-0000-0000-000000000001',1,'d8000000-0000-0000-0000-000000000001','44');
  IF r<>'applied' THEN RAISE EXCEPTION 'FAIL CC-28: %', r; END IF;
  RAISE NOTICE 'PASS CC-28 verified contact change applied by the executor';
  r := cc_call('k-ok','h-ok','b8000000-0000-0000-0000-000000000001','a8000000-0000-0000-0000-000000000001',1,'d8000000-0000-0000-0000-000000000001','44');
  IF r<>'replayed' THEN RAISE EXCEPTION 'FAIL CC-29: %', r; END IF;
  RAISE NOTICE 'PASS CC-29 exact replay returns without a second mutation';
END $t$;
SELECT cc_err('CC-30 same idempotency key with a different payload rejected',
 $q$SELECT cc_call('k-ok','h-DIFFERENT','b8000000-0000-0000-0000-000000000001','a8000000-0000-0000-0000-000000000001',1,'d8000000-0000-0000-0000-000000000001','44')$q$,'23505','different intent');
SELECT cc_err('CC-31 a consumed proof cannot authorise a new command',
 $q$SELECT cc_call('k-again','h-again','b8000000-0000-0000-0000-000000000001','a8000000-0000-0000-0000-000000000001',1,'d8000000-0000-0000-0000-000000000001','44')$q$,'23514','consumed');
RESET SESSION AUTHORIZATION;
DO $t$ BEGIN
  IF (SELECT count(*) FROM student_contact_index WHERE student_id='b8000000-0000-0000-0000-000000000001'
        AND ((key_version=1 AND encode(mobile_hmac,'hex')=repeat('44',32)) OR (key_version=2 AND encode(mobile_hmac,'hex')=repeat('44',31)||'00'))
        AND cipher_key_version=1 AND mobile_ciphertext=decode('c1c2c344','hex'))<>2 THEN RAISE EXCEPTION 'FAIL CC-32a contact index'; END IF;
  IF (SELECT count(*) FROM enrollment_claim_identity_aliases a JOIN student_contact_index ci
        ON ci.student_id='b8000000-0000-0000-0000-000000000001' AND ci.key_version=a.key_version AND ci.mobile_hmac=a.mobile_hmac
       WHERE a.claim_id='c8000000-0000-0000-0000-000000000001' AND a.claim_state='active')<>2 THEN RAISE EXCEPTION 'FAIL CC-32b aliases'; END IF;
  IF (SELECT owner_workspace_id::text||'/'||ownership_generation FROM student_ownership WHERE student_id='b8000000-0000-0000-0000-000000000001')<>'a8000000-0000-0000-0000-000000000001/1'
     OR (SELECT count(*) FROM enrollment_claims WHERE student_id='b8000000-0000-0000-0000-000000000001' AND claim_state='active')<>1 THEN RAISE EXCEPTION 'FAIL CC-32c ownership'; END IF;
  RAISE NOTICE 'PASS CC-32 every live-key contact row and alias replaced atomically; owner, generation and single claim unchanged';
  IF (SELECT count(*) FROM student_contact_change_audit WHERE idempotency_key='k-ok' AND outcome='applied'
        AND old_fingerprints->>'1'=repeat('11',32) AND new_fingerprints->>'1'=repeat('44',32))<>1
     OR (SELECT count(*) FROM student_contact_change_audit)<>1 THEN RAISE EXCEPTION 'FAIL CC-33 audit'; END IF;
  IF (SELECT count(*) FROM outbox_events WHERE event_type='student_contact_changed' AND payload->>'command'='k-ok')<>1
     OR EXISTS (SELECT 1 FROM outbox_events WHERE event_type='student_contact_changed' AND payload::text ~* 'hmac|mobile|cipher') THEN RAISE EXCEPTION 'FAIL CC-33 outbox'; END IF;
  IF (SELECT status||'/'||consumed_by_command FROM contact_change_proofs WHERE proof_id='d8000000-0000-0000-0000-000000000001')<>'consumed/k-ok' THEN RAISE EXCEPTION 'FAIL CC-33 proof'; END IF;
  RAISE NOTICE 'PASS CC-33 one audit row with keyed fingerprints only, one outbox event without contact data, proof consumed by its command';
END $t$;
DO $t$ DECLARE n int; BEGIN
  SELECT count(*) INTO n FROM information_schema.columns WHERE table_schema='public'
   AND table_name IN ('contact_change_proofs','contact_change_commands','student_contact_change_audit')
   AND column_name ~* '(mobile|phone|msisdn|otp|e164)' AND column_name NOT IN ('new_contact_hmac');
  IF n<>0 THEN RAISE EXCEPTION 'FAIL CC-34: % plaintext-like column(s)', n; END IF;
  RAISE NOTICE 'PASS CC-34 no plaintext mobile, OTP or key column in the contact-change tables';
END $t$;
SELECT cc_err('CC-35 command ledger is append-only',$q$DELETE FROM contact_change_commands$q$,'23514','append-only');
SELECT cc_err('CC-36 contact-change audit is append-only',$q$UPDATE student_contact_change_audit SET outcome='applied'$q$,'23514','append-only');
SELECT cc_err('CC-37 a consumed proof is terminal',$q$UPDATE contact_change_proofs SET status='registered',consumed_at=NULL,consumed_by_command=NULL WHERE proof_id='d8000000-0000-0000-0000-000000000001'$q$,'23514','terminal');

-- ---- Same number, different grade (D-025 is grade-scoped): student 3 (grade_11) takes student 2's number ----
SELECT cc_proof('d8000000-0000-0000-0000-000000000003','b8000000-0000-0000-0000-000000000003','a8000000-0000-0000-0000-000000000002',1,'22');
-- ---- Expired and revoked proofs ----
SELECT cc_proof('d8000000-0000-0000-0000-000000000004','b8000000-0000-0000-0000-000000000002','a8000000-0000-0000-0000-000000000002',1,'66', now()-interval '2 hours', now()-interval '1 hour');
SELECT cc_proof('d8000000-0000-0000-0000-000000000005','b8000000-0000-0000-0000-000000000002','a8000000-0000-0000-0000-000000000002',1,'77');
UPDATE contact_change_proofs SET status='revoked' WHERE proof_id='d8000000-0000-0000-0000-000000000005';
SET SESSION AUTHORIZATION cp_contact_change_executor;
DO $t$ DECLARE r text; BEGIN
  r := cc_call('k-grade','h-grade','b8000000-0000-0000-0000-000000000003','a8000000-0000-0000-0000-000000000002',1,'d8000000-0000-0000-0000-000000000003','22');
  IF r<>'applied' THEN RAISE EXCEPTION 'FAIL CC-38'; END IF;
  RAISE NOTICE 'PASS CC-38 same number in a different grade is allowed (D-025 is grade-scoped)';
END $t$;
SELECT cc_err('CC-39 expired proof rejected',
 $q$SELECT cc_call('k-39','h39','b8000000-0000-0000-0000-000000000002','a8000000-0000-0000-0000-000000000002',1,'d8000000-0000-0000-0000-000000000004','66')$q$,'23514','not valid at this time');
SELECT cc_err('CC-40 revoked proof rejected',
 $q$SELECT cc_call('k-40','h40','b8000000-0000-0000-0000-000000000002','a8000000-0000-0000-0000-000000000002',1,'d8000000-0000-0000-0000-000000000005','77')$q$,'23514','revoked');
RESET SESSION AUTHORIZATION;

-- ---- Catalog: the contact-change owner family is isolated from transfer, rotation and admission ----
DO $t$ DECLARE o text := 'cp_contact_change_function_owner'; BEGIN
  IF has_table_privilege(o,'transfer_cases','SELECT,INSERT,UPDATE,DELETE') OR has_table_privilege(o,'transfer_approvals','SELECT,INSERT,UPDATE,DELETE')
     OR has_table_privilege(o,'ownership_history','SELECT,INSERT,UPDATE,DELETE') OR has_table_privilege(o,'platform_students','INSERT,UPDATE,DELETE')
     OR has_table_privilege(o,'student_ownership','INSERT,DELETE') OR has_column_privilege(o,'student_ownership','owner_workspace_id','UPDATE')
     OR has_column_privilege(o,'student_ownership','ownership_generation','UPDATE')
     OR has_table_privilege(o,'mobile_hmac_key_versions','INSERT,UPDATE,DELETE') OR has_column_privilege(o,'identity_write_gate','maintenance_mode','UPDATE')
     OR has_table_privilege(o,'student_contact_index','INSERT,DELETE') OR has_table_privilege(o,'enrollment_claim_identity_aliases','INSERT,DELETE')
     OR has_column_privilege(o,'enrollment_claims','workspace_id','UPDATE') OR has_column_privilege(o,'enrollment_claims','claim_state','UPDATE')
     OR has_function_privilege(o,'switch_student_ownership(uuid)','EXECUTE')
     OR has_function_privilege(o,'begin_identity_hmac_rotation()','EXECUTE')
     OR has_function_privilege(o,'admit_student_identity_claim(text,bytea,uuid,uuid,uuid,text,bytea,integer,jsonb)','EXECUTE') THEN
    RAISE EXCEPTION 'FAIL CC-41 contact-change owner holds a privilege outside its command';
  END IF;
  IF (SELECT pg_get_userbyid(proowner) FROM pg_proc WHERE proname='change_student_mobile_contact')<>o
     OR has_function_privilege('cp_runtime','change_student_mobile_contact(text,bytea,uuid,uuid,bigint,uuid,bytea,integer,jsonb)','EXECUTE')
     OR has_function_privilege('cp_transfer_executor','change_student_mobile_contact(text,bytea,uuid,uuid,bigint,uuid,bytea,integer,jsonb)','EXECUTE')
     OR has_function_privilege('cp_contact_proof_verifier','change_student_mobile_contact(text,bytea,uuid,uuid,bigint,uuid,bytea,integer,jsonb)','EXECUTE')
     OR NOT has_function_privilege('cp_contact_change_executor','change_student_mobile_contact(text,bytea,uuid,uuid,bigint,uuid,bytea,integer,jsonb)','EXECUTE')
     OR has_table_privilege('cp_contact_proof_verifier','contact_change_proofs','SELECT,UPDATE,DELETE')
     OR has_table_privilege('cp_contact_change_executor','contact_change_proofs','SELECT,INSERT,UPDATE,DELETE')
     OR pg_has_role('cp_contact_change_executor',o,'MEMBER') OR pg_has_role('cp_contact_proof_verifier',o,'MEMBER') THEN
    RAISE EXCEPTION 'FAIL CC-42 executor/verifier scope is incorrect';
  END IF;
  RAISE NOTICE 'PASS CC-41/42 contact-change owner, executor and verifier privileges are scoped to this command only';
END $t$;
DO $t$ BEGIN RAISE NOTICE '=== CONTROL PLANE CONTACT-CHANGE TESTS COMPLETED (synthetic) ==='; END $t$;
