-- =============================================================================
-- H-03 regression suite (Issue #13 corrective). Synthetic only (D-014).
-- Runs AFTER receipt_10, receipt_30 and receipt_40 on the same database (reuses their consumed
-- receipts b1, b2 and events, and the unrelated event c1). Identities: verifier_rt and the adapter
-- identity are used with SET SESSION AUTHORIZATION, not superuser shortcuts.
-- Corruption scenarios run inside a transaction that is ROLLED BACK; they simulate owner-level
-- data damage and check that the consume retry path refuses it.
-- =============================================================================
\set ON_ERROR_STOP on
SET app.workspace_key = :'workspace_key';
SELECT 'ws_'||current_setting('app.workspace_key')||'_verifier_rt' AS verifier_role \gset
SELECT 'ws_'||current_setting('app.workspace_key')||'_governance_adapter_rt' AS adapter_role \gset

-- Role-name helper usable inside DO bodies (psql does not interpolate :vars inside dollar quotes).
CREATE OR REPLACE FUNCTION ws_role(p_suffix text) RETURNS text LANGUAGE sql AS $$
  SELECT 'ws_'||current_setting('app.workspace_key')||'_'||p_suffix
$$;

CREATE OR REPLACE FUNCTION expect_error(label text, stmt text, want text, want_msg text DEFAULT '')
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE stmt;
  RAISE EXCEPTION 'FAIL %: statement succeeded, expected SQLSTATE %', label, want;
EXCEPTION WHEN OTHERS THEN
  IF SQLSTATE <> want THEN RAISE EXCEPTION 'FAIL %: got SQLSTATE % (%), expected %', label, SQLSTATE, SQLERRM, want; END IF;
  IF want_msg <> '' AND position(want_msg IN SQLERRM) = 0 THEN RAISE EXCEPTION 'FAIL %: wrong reason: %', label, SQLERRM; END IF;
  RAISE NOTICE 'PASS % (SQLSTATE %, reason verified)', label, SQLSTATE;
END; $$;
CREATE OR REPLACE FUNCTION expect_ok(label text, stmt text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN EXECUTE stmt; RAISE NOTICE 'PASS % (accepted)', label; END; $$;

-- Owner-run factory for registered receipts (same shape as receipt_30).
CREATE OR REPLACE FUNCTION test_receipt_h(p_receipt uuid, p_assertion uuid, p_nonce text, p_key text)
RETURNS void LANGUAGE sql AS $$
  INSERT INTO governance_proof_receipts(receipt_id,assertion_id,nonce_digest,issuer_id,audience,key_id,workspace_id,
    actor_membership_id,authn_event_ref,assurance_ref,action,aggregate_type,aggregate_id,target_membership_id,
    role_or_permission_key,scope_digest,authority_ref,policy_version,idempotency_key,payload_digest,canonicalization_version,
    issued_at,not_before,expires_at,verifier_kind,verifier_outcome)
  VALUES(p_receipt,p_assertion,sha256(convert_to(p_nonce,'UTF8')),'test-issuer','governance_adapter','test-key-1',
    'a9100000-0000-0000-0000-000000000001','b9100000-0000-0000-0000-000000000001','authn-event-x','assurance-x',
    'role_granted','membership_role','b9100000-0000-0000-0000-000000000003','b9100000-0000-0000-0000-000000000003',
    'counselor',sha256(convert_to('scope-x','UTF8')),'authority-x','policy-v1',p_key,
    receipt_payload_digest_v1('{"role_key":"counselor"}'::jsonb),'receipt-canon-v1',
    now()-interval '2 minutes', now()-interval '1 minute', now()+interval '1 day','external_independent_verifier','verified');
$$;

-- ---- H-03 (a): the verifier identity cannot insert a receipt that is already consumed ----
SET SESSION AUTHORIZATION :"verifier_role";
SELECT expect_error('H03-1 verifier_rt direct INSERT with status=consumed and complete metadata is refused',
  $q$INSERT INTO governance_proof_receipts(receipt_id,assertion_id,nonce_digest,issuer_id,audience,key_id,workspace_id,actor_membership_id,authn_event_ref,assurance_ref,action,aggregate_type,aggregate_id,target_membership_id,role_or_permission_key,scope_digest,authority_ref,policy_version,idempotency_key,payload_digest,canonicalization_version,issued_at,not_before,expires_at,verifier_kind,verifier_outcome,status,consumed_at,consumed_event_id,consumed_idempotency_key)
     VALUES('e9100000-0000-0000-0000-0000000000d1','f9100000-0000-0000-0000-0000000000d1',sha256(convert_to('h03-1','UTF8')),'i','governance_adapter','k','a9100000-0000-0000-0000-000000000001','b9100000-0000-0000-0000-000000000001','a','b','role_granted','membership_role','b9100000-0000-0000-0000-000000000003','b9100000-0000-0000-0000-000000000003','counselor',sha256('s'::bytea),'auth','policy-v1','h03-1-key',receipt_payload_digest_v1('{"role_key":"counselor"}'::jsonb),'receipt-canon-v1',now()-interval '2 minutes',now()-interval '1 minute',now()+interval '1 day','external_independent_verifier','verified','consumed',now(),'d9100000-0000-0000-0000-0000000000c1','h03-1-key')$q$,
  '23514', 'only an initially registered receipt');
SELECT expect_error('H03-2 verifier_rt direct INSERT with status=revoked is refused',
  $q$INSERT INTO governance_proof_receipts(receipt_id,assertion_id,nonce_digest,issuer_id,audience,key_id,workspace_id,actor_membership_id,authn_event_ref,assurance_ref,action,aggregate_type,aggregate_id,target_membership_id,role_or_permission_key,scope_digest,authority_ref,policy_version,idempotency_key,payload_digest,canonicalization_version,issued_at,not_before,expires_at,verifier_kind,verifier_outcome,status)
     VALUES('e9100000-0000-0000-0000-0000000000d2','f9100000-0000-0000-0000-0000000000d2',sha256(convert_to('h03-2','UTF8')),'i','governance_adapter','k','a9100000-0000-0000-0000-000000000001','b9100000-0000-0000-0000-000000000001','a','b','role_granted','membership_role','b9100000-0000-0000-0000-000000000003','b9100000-0000-0000-0000-000000000003','counselor',sha256('s'::bytea),'auth','policy-v1','h03-2-key',receipt_payload_digest_v1('{"role_key":"counselor"}'::jsonb),'receipt-canon-v1',now()-interval '2 minutes',now()-interval '1 minute',now()+interval '1 day','external_independent_verifier','verified','revoked')$q$,
  '23514', 'only an initially registered receipt');
SELECT expect_ok('H03-3 an ordinary registered INSERT by verifier_rt remains valid',
  $q$INSERT INTO governance_proof_receipts(receipt_id,assertion_id,nonce_digest,issuer_id,audience,key_id,workspace_id,actor_membership_id,authn_event_ref,assurance_ref,action,aggregate_type,aggregate_id,target_membership_id,role_or_permission_key,scope_digest,authority_ref,policy_version,idempotency_key,payload_digest,canonicalization_version,issued_at,not_before,expires_at,verifier_kind,verifier_outcome)
     VALUES('e9100000-0000-0000-0000-0000000000d3','f9100000-0000-0000-0000-0000000000d3',sha256(convert_to('h03-3','UTF8')),'i','governance_adapter','k','a9100000-0000-0000-0000-000000000001','b9100000-0000-0000-0000-000000000001','a','b','role_granted','membership_role','b9100000-0000-0000-0000-000000000003','b9100000-0000-0000-0000-000000000003','counselor',sha256('s'::bytea),'auth','policy-v1','h03-3-key',receipt_payload_digest_v1('{"role_key":"counselor"}'::jsonb),'receipt-canon-v1',now()-interval '2 minutes',now()-interval '1 minute',now()+interval '1 day','external_independent_verifier','verified')$q$);
-- Verifier cannot revoke, and cannot write the revocation audit.
SELECT expect_error('H03-6 verifier_rt cannot revoke a receipt (no UPDATE)',
  $q$UPDATE governance_proof_receipts SET status='revoked' WHERE receipt_id='e9100000-0000-0000-0000-0000000000d3'$q$, '42501');
SELECT expect_error('H03-7 verifier_rt cannot write the revocation audit',
  $q$INSERT INTO receipt_revocation_audit(receipt_id, revoked_by) VALUES ('e9100000-0000-0000-0000-0000000000d3', 'x')$q$, '42501');
RESET SESSION AUTHORIZATION;

-- ---- H-03 (b): only the consume command performs registered -> consumed ----
SELECT test_receipt_h('e9100000-0000-0000-0000-0000000000d4','f9100000-0000-0000-0000-0000000000d4','h03-n4','h03-key-4');
SELECT expect_error('H03-4 owner-level UPDATE registered -> consumed outside the consume command is refused',
  $q$UPDATE governance_proof_receipts SET status='consumed', consumed_at=now(), consumed_event_id='d9100000-0000-0000-0000-0000000000c1', consumed_idempotency_key='h03-key-4' WHERE receipt_id='e9100000-0000-0000-0000-0000000000d4'$q$,
  '23514', 'only the consume command');

-- ---- H-03 (c): revocation is separately authorised and audited ----
SELECT test_receipt_h('e9100000-0000-0000-0000-0000000000d5','f9100000-0000-0000-0000-0000000000d5','h03-n5','h03-key-5');
UPDATE governance_proof_receipts SET status='revoked' WHERE receipt_id='e9100000-0000-0000-0000-0000000000d5';
DO $$ BEGIN
  IF (SELECT count(*) FROM receipt_revocation_audit WHERE receipt_id='e9100000-0000-0000-0000-0000000000d5' AND revoked_by='postgres') <> 1 THEN
    RAISE EXCEPTION 'FAIL H03-5: revocation not audited with the revoking identity';
  END IF;
  RAISE NOTICE 'PASS H03-5 revocation is audited with revoked_by and time';
END $$;
SELECT expect_error('H03-5b the revocation audit is append-only',
  $q$UPDATE receipt_revocation_audit SET revoked_by='tampered' WHERE receipt_id='e9100000-0000-0000-0000-0000000000d5'$q$, '23514', 'append-only');

-- ---- H-03 (d): consume and exact retry remain valid (new receipt) ----
SELECT test_receipt_h('e9100000-0000-0000-0000-0000000000d6','f9100000-0000-0000-0000-0000000000d6','h03-n6','h03-key-6');
SET SESSION AUTHORIZATION :"adapter_role";
DO $$ DECLARE a record; b record; BEGIN
  SELECT * INTO a FROM consume_governance_receipt_and_apply('e9100000-0000-0000-0000-0000000000d6','b9100000-0000-0000-0000-000000000001','role_granted','membership_role','b9100000-0000-0000-0000-000000000003','b9100000-0000-0000-0000-000000000003','counselor',sha256(convert_to('scope-x','UTF8')),'policy-v1','h03-key-6','{"role_key":"counselor"}'::jsonb,'d9100000-0000-0000-0000-0000000000d6',now());
  SELECT * INTO b FROM consume_governance_receipt_and_apply('e9100000-0000-0000-0000-0000000000d6','b9100000-0000-0000-0000-000000000001','role_granted','membership_role','b9100000-0000-0000-0000-000000000003','b9100000-0000-0000-0000-000000000003','counselor',sha256(convert_to('scope-x','UTF8')),'policy-v1','h03-key-6','{"role_key":"counselor"}'::jsonb,'d9100000-0000-0000-0000-0000000000d7',now());
  IF a.event_id IS DISTINCT FROM b.event_id THEN RAISE EXCEPTION 'FAIL H03-8: exact retry returned a different event'; END IF;
  RAISE NOTICE 'PASS H03-8 normal consume and exact retry return the same event';
END $$;
RESET SESSION AUTHORIZATION;

-- ---- H-03 (e): corruption of stored consumption, refused by the retry path (rolled back) ----
-- H03-9: consumed receipt pointing at an existing but UNRELATED event (b1 -> c1).
BEGIN;
ALTER TABLE governance_proof_receipts DISABLE TRIGGER governance_proof_receipts_guard;
UPDATE governance_proof_receipts SET consumed_event_id='d9100000-0000-0000-0000-0000000000c1' WHERE receipt_id='e9100000-0000-0000-0000-0000000000b1';
SET SESSION AUTHORIZATION :"adapter_role";
SELECT expect_error('H03-9 consumed receipt referencing an existing but unrelated event is refused on retry',
  $q$SELECT * FROM consume_governance_receipt_and_apply('e9100000-0000-0000-0000-0000000000b1','b9100000-0000-0000-0000-000000000001','role_granted','membership_role','b9100000-0000-0000-0000-000000000003','b9100000-0000-0000-0000-000000000003','counselor',sha256(convert_to('scope-x','UTF8')),'policy-v1','m01-key-A','{"role_key":"counselor"}'::jsonb,'d9100000-0000-0000-0000-0000000000e1',now())$q$,
  '23514', 'inconsistent');
RESET SESSION AUTHORIZATION;
ROLLBACK;

-- H03-10: consumed receipt whose stored idempotency key does not match its event.
BEGIN;
ALTER TABLE governance_proof_receipts DISABLE TRIGGER governance_proof_receipts_guard;
UPDATE governance_proof_receipts SET consumed_idempotency_key='tampered-key' WHERE receipt_id='e9100000-0000-0000-0000-0000000000b2';
SET SESSION AUTHORIZATION :"adapter_role";
SELECT expect_error('H03-10 inconsistent stored consumption idempotency key is refused on retry',
  $q$SELECT * FROM consume_governance_receipt_and_apply('e9100000-0000-0000-0000-0000000000b2','b9100000-0000-0000-0000-000000000001','role_granted','membership_role','b9100000-0000-0000-0000-000000000003','b9100000-0000-0000-0000-000000000003','counselor',sha256(convert_to('scope-x','UTF8')),'policy-v1','m01-key-B','{"role_key":"counselor"}'::jsonb,'d9100000-0000-0000-0000-0000000000e2',now())$q$,
  '23514', 'inconsistent');
RESET SESSION AUTHORIZATION;
ROLLBACK;

-- The rollbacks must have restored the real stored state.
DO $$ BEGIN
  IF (SELECT consumed_event_id FROM governance_proof_receipts WHERE receipt_id='e9100000-0000-0000-0000-0000000000b1') <> 'd9100000-0000-0000-0000-0000000000b1' THEN
    RAISE EXCEPTION 'FAIL H03-R: rollback did not restore b1';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='governance_proof_receipts_guard' AND NOT tgisinternal AND tgenabled <> 'D') THEN
    RAISE EXCEPTION 'FAIL H03-R2: guard trigger not re-enabled after rollback';
  END IF;
  RAISE NOTICE 'PASS H03-R rollbacks restored stored state and the guard trigger';
END $$;
SELECT 'ws_'||current_setting('app.workspace_key')||'_governance_owner' AS owner_role \gset
SELECT 'ws_'||current_setting('app.workspace_key')||'_receipt_consume_definer' AS definer_role \gset
SELECT 'ws_'||current_setting('app.workspace_key')||'_runtime' AS runtime_role \gset
SELECT 'ws_'||current_setting('app.workspace_key')||'_worker' AS worker_role \gset
SELECT 'ws_'||current_setting('app.workspace_key')||'_exporter' AS exporter_role \gset

-- ---- H-03 corrective (Supervisor finding): a session setting is NOT an authorisation ----
-- H03-11 / H03-12: an identity that HAS UPDATE privilege sets receipt.consume_active to the target id,
-- then attempts a direct registered -> consumed transition. Must be refused: no consume grant exists.
SELECT test_receipt_h('e9100000-0000-0000-0000-0000000000d8','f9100000-0000-0000-0000-0000000000d8','h03-n8','h03-key-8');
SELECT test_receipt_h('e9100000-0000-0000-0000-0000000000d9','f9100000-0000-0000-0000-0000000000d9','h03-n9','h03-key-9');
SET SESSION AUTHORIZATION :"owner_role";
SELECT set_config('receipt.consume_active','e9100000-0000-0000-0000-0000000000d8',false);
SELECT expect_error('H03-11 governance owner with UPDATE privilege cannot consume by setting receipt.consume_active',
  $q$UPDATE governance_proof_receipts SET status='consumed', consumed_at=now(), consumed_event_id='d9100000-0000-0000-0000-0000000000c1', consumed_idempotency_key='h03-key-8' WHERE receipt_id='e9100000-0000-0000-0000-0000000000d8'$q$,
  '23514', 'only the consume command');
SELECT set_config('receipt.consume_active','',false);
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION :"definer_role";
SELECT set_config('receipt.consume_active','e9100000-0000-0000-0000-0000000000d9',false);
SELECT expect_error('H03-12 consume definer role cannot consume without its command-scoped grant, even with the setting',
  $q$UPDATE governance_proof_receipts SET status='consumed', consumed_at=now(), consumed_event_id='d9100000-0000-0000-0000-0000000000c1', consumed_idempotency_key='h03-key-9' WHERE receipt_id='e9100000-0000-0000-0000-0000000000d9'$q$,
  '23514', 'only the consume command');
SELECT set_config('receipt.consume_active','',false);
RESET SESSION AUTHORIZATION;

-- H03-13: no identity other than the consume definer can write consume grants (forgery).
SET SESSION AUTHORIZATION :"owner_role";
SELECT expect_error('H03-13a governance owner cannot forge a consume grant',
  $q$INSERT INTO receipt_consume_grants(receipt_id, txid) VALUES ('e9100000-0000-0000-0000-0000000000d8', txid_current())$q$, '42501');
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION :"verifier_role";
SELECT expect_error('H03-13b verifier_rt cannot forge a consume grant',
  $q$INSERT INTO receipt_consume_grants(receipt_id, txid) VALUES ('e9100000-0000-0000-0000-0000000000d8', txid_current())$q$, '42501');
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION :"adapter_role";
SELECT expect_error('H03-13c adapter cannot forge a consume grant',
  $q$INSERT INTO receipt_consume_grants(receipt_id, txid) VALUES ('e9100000-0000-0000-0000-0000000000d8', txid_current())$q$, '42501');
SELECT expect_error('H03-13d adapter cannot read consume grants',
  $q$SELECT count(*) FROM receipt_consume_grants$q$, '42501');
RESET SESSION AUTHORIZATION;

-- H03-14: narrow privileges retained (catalog). Runtime, worker, exporter, verifier and adapter hold no grant
-- privilege; the governance owner cannot assume the definer; the definer owns the consume function.
DO $$ BEGIN
  IF has_table_privilege(ws_role('runtime'),'receipt_consume_grants','SELECT,INSERT,UPDATE,DELETE')
  OR has_table_privilege(ws_role('worker'),'receipt_consume_grants','SELECT,INSERT,UPDATE,DELETE')
  OR has_table_privilege(ws_role('exporter'),'receipt_consume_grants','SELECT,INSERT,UPDATE,DELETE')
  OR has_table_privilege(ws_role('verifier_rt'),'receipt_consume_grants','SELECT,INSERT,UPDATE,DELETE')
  OR has_table_privilege(ws_role('governance_adapter_rt'),'receipt_consume_grants','SELECT,INSERT,UPDATE,DELETE')
  OR has_table_privilege(ws_role('governance_owner'),'receipt_consume_grants','INSERT,UPDATE,DELETE') THEN
    RAISE EXCEPTION 'FAIL H03-14a: a non-definer identity holds a consume-grant privilege';
  END IF;
  IF NOT has_table_privilege(ws_role('receipt_consume_definer'),'receipt_consume_grants','INSERT,DELETE') THEN
    RAISE EXCEPTION 'FAIL H03-14b: the consume definer lost its grant privileges';
  END IF;
  IF (SELECT pg_get_userbyid(proowner) FROM pg_proc WHERE proname='consume_governance_receipt_and_apply') <> ws_role('receipt_consume_definer') THEN
    RAISE EXCEPTION 'FAIL H03-14c: consume function is not owned by the definer role';
  END IF;
  IF pg_has_role(ws_role('governance_owner'), ws_role('receipt_consume_definer'), 'MEMBER') OR pg_has_role(ws_role('verifier_rt'), ws_role('receipt_consume_definer'), 'MEMBER')
     OR pg_has_role(ws_role('governance_adapter_rt'), ws_role('receipt_consume_definer'), 'MEMBER') THEN
    RAISE EXCEPTION 'FAIL H03-14d: a caller can assume the consume definer';
  END IF;
  RAISE NOTICE 'PASS H03-14 narrow privileges retained: grants writable only by the definer; definer owns the function; no role membership';
END $$;

-- H03-15: legitimate consume still succeeds through the command (grant scoped to its own transaction).
SELECT test_receipt_h('e9100000-0000-0000-0000-0000000000da','f9100000-0000-0000-0000-0000000000da','h03-na','h03-key-a');
SET SESSION AUTHORIZATION :"adapter_role";
SELECT expect_ok('H03-15 the legitimate consume command still succeeds for a registered receipt',
  $q$SELECT * FROM consume_governance_receipt_and_apply('e9100000-0000-0000-0000-0000000000da','b9100000-0000-0000-0000-000000000001','role_granted','membership_role','b9100000-0000-0000-0000-000000000003','b9100000-0000-0000-0000-000000000003','counselor',sha256(convert_to('scope-x','UTF8')),'policy-v1','h03-key-a','{"role_key":"counselor"}'::jsonb,'d9100000-0000-0000-0000-0000000000db',now())$q$);
RESET SESSION AUTHORIZATION;
DO $$ BEGIN
  IF (SELECT count(*) FROM receipt_consume_grants WHERE receipt_id='e9100000-0000-0000-0000-0000000000da') <> 0 THEN
    RAISE EXCEPTION 'FAIL H03-15b: consume grant not released after the command';
  END IF;
  RAISE NOTICE 'PASS H03-15b the command releases its grant (no residue)';
END $$;

DO $$ BEGIN RAISE NOTICE '=== H-03 SUITE COMPLETED (synthetic) ==='; END $$;
