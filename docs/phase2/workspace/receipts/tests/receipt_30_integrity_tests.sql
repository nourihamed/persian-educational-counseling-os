-- =============================================================================
-- Issue #13 corrective patch: M-01 (retry ordering), M-02 (state/metadata integrity).
-- Synthetic data only (D-014). Run AFTER receipt_10_tests.sql on the SAME database (reuses its fixtures:
-- workspace profile, memberships 1-3, and the receipt e9100000-...-000000000001 consumed by RC-24).
-- Identity switches use SET SESSION AUTHORIZATION; owner-level statements prove guard behaviour.
-- =============================================================================
\set ON_ERROR_STOP on
SET app.workspace_key = :'workspace_key';
SELECT 'ws_'||current_setting('app.workspace_key')||'_governance_adapter_rt' AS adapter_role \gset

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

-- Owner-run factory for fixtures in this file (same shape as receipt_10 test_receipt).
CREATE OR REPLACE FUNCTION test_receipt_i(p_receipt uuid, p_assertion uuid, p_nonce text, p_key text,
  p_nbf timestamptz, p_exp timestamptz, p_payload jsonb DEFAULT '{"role_key":"counselor"}')
RETURNS void LANGUAGE sql AS $$
  INSERT INTO governance_proof_receipts(receipt_id,assertion_id,nonce_digest,issuer_id,audience,key_id,workspace_id,
    actor_membership_id,authn_event_ref,assurance_ref,action,aggregate_type,aggregate_id,target_membership_id,
    role_or_permission_key,scope_digest,authority_ref,policy_version,idempotency_key,payload_digest,canonicalization_version,
    issued_at,not_before,expires_at,verifier_kind,verifier_outcome)
  VALUES(p_receipt,p_assertion,sha256(convert_to(p_nonce,'UTF8')),'test-issuer','governance_adapter','test-key-1',
    'a9100000-0000-0000-0000-000000000001','b9100000-0000-0000-0000-000000000001','authn-event-x','assurance-x',
    'role_granted','membership_role','b9100000-0000-0000-0000-000000000003','b9100000-0000-0000-0000-000000000003',
    'counselor',sha256(convert_to('scope-x','UTF8')),'authority-x','policy-v1',p_key,
    receipt_payload_digest_v1(p_payload),'receipt-canon-v1',
    p_nbf - interval '1 minute', p_nbf, p_exp,'external_independent_verifier','verified');
$$;

-- ============================ M-01: idempotency retry after expiry ============================
SELECT test_receipt_i('e9100000-0000-0000-0000-0000000000b1','f9100000-0000-0000-0000-0000000000b1','m01-n1','m01-key-A',
  now()-interval '1 hour', now()+interval '1 day');
SELECT test_receipt_i('e9100000-0000-0000-0000-0000000000b2','f9100000-0000-0000-0000-0000000000b2','m01-n2','m01-key-B',
  now()-interval '1 second', now()+interval '2 seconds');
SELECT test_receipt_i('e9100000-0000-0000-0000-0000000000b3','f9100000-0000-0000-0000-0000000000b3','m01-n3','m01-key-C',
  now()-interval '1 minute', now()+interval '1 second');

SET SESSION AUTHORIZATION :"adapter_role";
-- M-01-1: consume once, then identical retry before expiry returns the original event (no second effect).
DO $$ DECLARE a record; b record; BEGIN
  SELECT * INTO a FROM consume_governance_receipt_and_apply('e9100000-0000-0000-0000-0000000000b1','b9100000-0000-0000-0000-000000000001','role_granted','membership_role','b9100000-0000-0000-0000-000000000003','b9100000-0000-0000-0000-000000000003','counselor',sha256(convert_to('scope-x','UTF8')),'policy-v1','m01-key-A','{"role_key":"counselor"}'::jsonb,'d9100000-0000-0000-0000-0000000000b1',now());
  SELECT * INTO b FROM consume_governance_receipt_and_apply('e9100000-0000-0000-0000-0000000000b1','b9100000-0000-0000-0000-000000000001','role_granted','membership_role','b9100000-0000-0000-0000-000000000003','b9100000-0000-0000-0000-000000000003','counselor',sha256(convert_to('scope-x','UTF8')),'policy-v1','m01-key-A','{"role_key":"counselor"}'::jsonb,'d9100000-0000-0000-0000-0000000000b9',now());
  IF a.event_id <> b.event_id THEN RAISE EXCEPTION 'FAIL M01-1: identical retry returned a different event'; END IF;
  RAISE NOTICE 'PASS M01-1 identical retry before expiry returns the original event';
END $$;

-- M-01-2: consume a short-lived receipt, wait past its expiry, then retry identically -> original result.
DO $$ DECLARE a record; b record; BEGIN
  SELECT * INTO a FROM consume_governance_receipt_and_apply('e9100000-0000-0000-0000-0000000000b2','b9100000-0000-0000-0000-000000000001','role_granted','membership_role','b9100000-0000-0000-0000-000000000003','b9100000-0000-0000-0000-000000000003','counselor',sha256(convert_to('scope-x','UTF8')),'policy-v1','m01-key-B','{"role_key":"counselor"}'::jsonb,'d9100000-0000-0000-0000-0000000000b2',now());
  PERFORM pg_sleep(3);
  -- Expiry was set to now()+2s at fixture time; the 3s sleep guarantees the receipt is expired here.
  SELECT * INTO b FROM consume_governance_receipt_and_apply('e9100000-0000-0000-0000-0000000000b2','b9100000-0000-0000-0000-000000000001','role_granted','membership_role','b9100000-0000-0000-0000-000000000003','b9100000-0000-0000-0000-000000000003','counselor',sha256(convert_to('scope-x','UTF8')),'policy-v1','m01-key-B','{"role_key":"counselor"}'::jsonb,'d9100000-0000-0000-0000-0000000000ba',now());
  IF a.event_id <> b.event_id THEN RAISE EXCEPTION 'FAIL M01-2: retry after expiry did not return the original event'; END IF;
  RAISE NOTICE 'PASS M01-2 identical retry AFTER expiry returns the original event (no second effect)';
END $$;

-- M-01-3..6: after consumption, any different binding must NOT receive the previous result.
SELECT expect_error('M01-3 retry with a different idempotency key is refused (even after expiry)',
  $q$SELECT * FROM consume_governance_receipt_and_apply('e9100000-0000-0000-0000-0000000000b2','b9100000-0000-0000-0000-000000000001','role_granted','membership_role','b9100000-0000-0000-0000-000000000003','b9100000-0000-0000-0000-000000000003','counselor',sha256(convert_to('scope-x','UTF8')),'policy-v1','m01-key-OTHER','{"role_key":"counselor"}'::jsonb,'d9100000-0000-0000-0000-0000000000bb',now())$q$,
  '23514', 'binding mismatch: idempotency key');
SELECT expect_error('M01-4 retry with an altered payload is refused',
  $q$SELECT * FROM consume_governance_receipt_and_apply('e9100000-0000-0000-0000-0000000000b1','b9100000-0000-0000-0000-000000000001','role_granted','membership_role','b9100000-0000-0000-0000-000000000003','b9100000-0000-0000-0000-000000000003','counselor',sha256(convert_to('scope-x','UTF8')),'policy-v1','m01-key-A','{"role_key":"admin"}'::jsonb,'d9100000-0000-0000-0000-0000000000bc',now())$q$,
  '23514', 'binding mismatch: payload');
SELECT expect_error('M01-5a retry with an altered actor is refused',
  $q$SELECT * FROM consume_governance_receipt_and_apply('e9100000-0000-0000-0000-0000000000b1','b9100000-0000-0000-0000-000000000002','role_granted','membership_role','b9100000-0000-0000-0000-000000000003','b9100000-0000-0000-0000-000000000003','counselor',sha256(convert_to('scope-x','UTF8')),'policy-v1','m01-key-A','{"role_key":"counselor"}'::jsonb,'d9100000-0000-0000-0000-0000000000bd',now())$q$,
  '23514', 'binding mismatch: actor');
SELECT expect_error('M01-5b retry with an altered action is refused',
  $q$SELECT * FROM consume_governance_receipt_and_apply('e9100000-0000-0000-0000-0000000000b1','b9100000-0000-0000-0000-000000000001','role_revoked','membership_role','b9100000-0000-0000-0000-000000000003','b9100000-0000-0000-0000-000000000003','counselor',sha256(convert_to('scope-x','UTF8')),'policy-v1','m01-key-A','{"role_key":"counselor"}'::jsonb,'d9100000-0000-0000-0000-0000000000be',now())$q$,
  '23514', 'binding mismatch: action');
-- M-01-7: an UNCONSUMED receipt past its expiry fails closed.
SELECT expect_error('M01-7 unconsumed expired receipt fails closed',
  $q$SELECT * FROM consume_governance_receipt_and_apply('e9100000-0000-0000-0000-0000000000b3','b9100000-0000-0000-0000-000000000001','role_granted','membership_role','b9100000-0000-0000-0000-000000000003','b9100000-0000-0000-0000-000000000003','counselor',sha256(convert_to('scope-x','UTF8')),'policy-v1','m01-key-C','{"role_key":"counselor"}'::jsonb,'d9100000-0000-0000-0000-0000000000bf',now())$q$,
  '23514', 'not valid at this time');
DO $$ BEGIN PERFORM pg_sleep(2); END $$;
SELECT expect_error('M01-7b the expired unconsumed receipt is still registered after the refusal',
  $q$SELECT CASE WHEN (SELECT status FROM governance_proof_receipts WHERE receipt_id='e9100000-0000-0000-0000-0000000000b3')='registered' THEN 1 ELSE 1/0 END$q$, '22012');
RESET SESSION AUTHORIZATION;

-- ============================ M-02: state and metadata integrity ============================
-- Owner-level statements: the guard must hold even for the table owner.
SELECT test_receipt_i('e9100000-0000-0000-0000-0000000000c1','f9100000-0000-0000-0000-0000000000c1','m02-n1','m02-key-1',
  now()-interval '1 hour', now()+interval '1 day');
SELECT expect_error('M02-1 consumption metadata written while state stays registered',
  $q$UPDATE governance_proof_receipts SET consumed_at=now() WHERE receipt_id='e9100000-0000-0000-0000-0000000000c1'$q$,
  '23514', 'may only be written');
SELECT expect_error('M02-2a a transition to consumed outside the consume command is refused (H-03)',
  $q$UPDATE governance_proof_receipts SET status='consumed', consumed_at=now() WHERE receipt_id='e9100000-0000-0000-0000-0000000000c1'$q$,
  '23514', 'only the consume command');
-- Simulate the consume command's scope to exercise the metadata-completeness rule itself.
SELECT set_config('receipt.consume_active','e9100000-0000-0000-0000-0000000000c1',false);
SELECT expect_error('M02-2 incomplete consumption metadata on a transition to consumed',
  $q$UPDATE governance_proof_receipts SET status='consumed', consumed_at=now() WHERE receipt_id='e9100000-0000-0000-0000-0000000000c1'$q$,
  '23514', 'incomplete consumption metadata');
SELECT set_config('receipt.consume_active','',false);
SELECT expect_error('M02-6 NULL status cannot bypass the state machine (guard rejects before NOT NULL)',
  $q$UPDATE governance_proof_receipts SET status=NULL WHERE receipt_id='e9100000-0000-0000-0000-0000000000c1'$q$, '23514', 'illegal receipt transition');
SELECT expect_error('M02-7 a consumed state cannot be inserted directly without metadata (CHECK, no NULL bypass)',
  $q$INSERT INTO governance_proof_receipts(receipt_id,assertion_id,nonce_digest,issuer_id,audience,key_id,workspace_id,actor_membership_id,authn_event_ref,assurance_ref,action,aggregate_type,aggregate_id,target_membership_id,role_or_permission_key,scope_digest,authority_ref,policy_version,idempotency_key,payload_digest,canonicalization_version,issued_at,not_before,expires_at,verifier_kind,verifier_outcome,status)
     SELECT gen_random_uuid(),gen_random_uuid(),sha256(convert_to('m02-direct','UTF8')),issuer_id,audience,key_id,workspace_id,actor_membership_id,authn_event_ref,assurance_ref,action,aggregate_type,aggregate_id,target_membership_id,role_or_permission_key,scope_digest,authority_ref,policy_version,'m02-direct-key',payload_digest,canonicalization_version,issued_at,not_before,expires_at,verifier_kind,verifier_outcome,'consumed'
     FROM governance_proof_receipts WHERE receipt_id='e9100000-0000-0000-0000-0000000000c1'$q$, '23514');

-- Consume c1 through the command so it becomes a real consumed receipt.
SET SESSION AUTHORIZATION :"adapter_role";
DO $$ BEGIN
  PERFORM * FROM consume_governance_receipt_and_apply('e9100000-0000-0000-0000-0000000000c1','b9100000-0000-0000-0000-000000000001','role_granted','membership_role','b9100000-0000-0000-0000-000000000003','b9100000-0000-0000-0000-000000000003','counselor',sha256(convert_to('scope-x','UTF8')),'policy-v1','m02-key-1','{"role_key":"counselor"}'::jsonb,'d9100000-0000-0000-0000-0000000000c1',now());
END $$;
RESET SESSION AUTHORIZATION;

SELECT expect_error('M02-3 mutation of consumption metadata after consumption is refused',
  $q$UPDATE governance_proof_receipts SET consumed_idempotency_key='tampered' WHERE receipt_id='e9100000-0000-0000-0000-0000000000c1'$q$, '23514', 'terminal');
SELECT expect_error('M02-4 consumed -> revoked is an invalid transition',
  $q$UPDATE governance_proof_receipts SET status='revoked' WHERE receipt_id='e9100000-0000-0000-0000-0000000000c1'$q$, '23514', 'terminal');
SELECT expect_error('M02-5 the event reference cannot be redirected after consumption',
  $q$UPDATE governance_proof_receipts SET consumed_event_id=gen_random_uuid() WHERE receipt_id='e9100000-0000-0000-0000-0000000000c1'$q$, '23514', 'terminal');

-- Revocation: no consumption metadata, and terminal afterwards.
SELECT test_receipt_i('e9100000-0000-0000-0000-0000000000c2','f9100000-0000-0000-0000-0000000000c2','m02-n2','m02-key-2',
  now()-interval '1 hour', now()+interval '1 day');
SELECT expect_error('M02-8 a revocation must not carry consumption metadata',
  $q$UPDATE governance_proof_receipts SET status='revoked', consumed_at=now() WHERE receipt_id='e9100000-0000-0000-0000-0000000000c2'$q$,
  '23514', 'must not carry consumption metadata');
UPDATE governance_proof_receipts SET status='revoked' WHERE receipt_id='e9100000-0000-0000-0000-0000000000c2';
SELECT expect_error('M02-9 mutation after revocation is refused (revoked -> registered)',
  $q$UPDATE governance_proof_receipts SET status='registered' WHERE receipt_id='e9100000-0000-0000-0000-0000000000c2'$q$, '23514', 'terminal');

-- Consumption must reference an event that exists (FK, same Workspace database).
SELECT test_receipt_i('e9100000-0000-0000-0000-0000000000c3','f9100000-0000-0000-0000-0000000000c3','m02-n3','m02-key-3',
  now()-interval '1 hour', now()+interval '1 day');
SELECT set_config('receipt.consume_active','e9100000-0000-0000-0000-0000000000c3',false);
SELECT expect_error('M02-10 consumption metadata pointing at a non-existent event is refused',
  $q$UPDATE governance_proof_receipts SET status='consumed', consumed_at=now(), consumed_event_id=gen_random_uuid(), consumed_idempotency_key='m02-key-3' WHERE receipt_id='e9100000-0000-0000-0000-0000000000c3'$q$, '23503');
SELECT set_config('receipt.consume_active','',false);

-- Binding columns (including the canonicalization version) cannot change after registration.
SELECT expect_error('M02-11 canonicalization version is immutable after registration',
  $q$UPDATE governance_proof_receipts SET canonicalization_version='receipt-canon-v2' WHERE receipt_id='e9100000-0000-0000-0000-0000000000c3'$q$, '23514', 'immutable');
SELECT expect_error('M02-12 an unknown canonicalization version cannot be registered',
  $q$INSERT INTO governance_proof_receipts(receipt_id,assertion_id,nonce_digest,issuer_id,audience,key_id,workspace_id,actor_membership_id,authn_event_ref,assurance_ref,action,aggregate_type,aggregate_id,scope_digest,authority_ref,policy_version,idempotency_key,payload_digest,canonicalization_version,issued_at,not_before,expires_at,verifier_kind,verifier_outcome)
     VALUES(gen_random_uuid(),gen_random_uuid(),sha256(convert_to('m02-v2','UTF8')),'i','governance_adapter','k','a9100000-0000-0000-0000-000000000001','b9100000-0000-0000-0000-000000000001','a','b','role_granted','membership_role',gen_random_uuid(),sha256('s'::bytea),'auth','policy-v1','m02-v2-key',sha256('p'::bytea),'receipt-canon-v2',now(),now(),now()+interval '1 day','external_independent_verifier','verified')$q$, '23514');

DO $$ BEGIN RAISE NOTICE '=== ISSUE 13 CORRECTIVE SUITE (M-01, M-02) COMPLETED (synthetic) ==='; END $$;
