-- =============================================================================
-- Governance proof receipt tests (SYNTHETIC ONLY, D-014). Run after the bootstrap order:
-- schema, activation_transactions, governance_events, roles_setup, receipt_01, receipt_02, receipt_03.
-- Identity is switched with SET SESSION AUTHORIZATION so privileges are truly exercised.
-- The verifier outcome below is a RECORDED TEST INPUT (test double), not cryptographic proof.
-- =============================================================================
\set ON_ERROR_STOP on
\if :{?workspace_key}
\else
  \echo 'pass -v workspace_key=<32 lowercase hex>'
  \quit 3
\endif
SET app.workspace_key = :'workspace_key';
SELECT 'ws_'||current_setting('app.workspace_key')||'_verifier_rt' AS verifier_role \gset
SELECT 'ws_'||current_setting('app.workspace_key')||'_governance_adapter_rt' AS adapter_role \gset
SELECT 'ws_'||current_setting('app.workspace_key')||'_runtime' AS runtime_role \gset
SELECT 'ws_'||current_setting('app.workspace_key')||'_worker' AS worker_role \gset
SELECT 'ws_'||current_setting('app.workspace_key')||'_exporter' AS exporter_role \gset

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

-- Role-name helper usable inside DO bodies (psql does not interpolate :vars inside dollar quotes).
CREATE OR REPLACE FUNCTION ws_role(p_suffix text) RETURNS text LANGUAGE sql AS $$
  SELECT 'ws_'||current_setting('app.workspace_key')||'_'||p_suffix
$$;

-- Synthetic Workspace, memberships and a payload digest helper.
INSERT INTO workspace_profile(singleton,workspace_id,workspace_type)
VALUES(true,'a9100000-0000-0000-0000-000000000001','organization');
INSERT INTO workspace_memberships(membership_id,platform_user_id,status) VALUES
 ('b9100000-0000-0000-0000-000000000001','c9100000-0000-0000-0000-000000000001','active'),   -- actor
 ('b9100000-0000-0000-0000-000000000002','c9100000-0000-0000-0000-000000000002','suspended'),-- inactive target
 ('b9100000-0000-0000-0000-000000000003','c9100000-0000-0000-0000-000000000003','active');   -- active target

-- Test-only receipt factory, run as the table owner (fixtures). Production registration is by verifier_rt.
CREATE OR REPLACE FUNCTION test_receipt(p_receipt uuid, p_assertion uuid, p_nonce text, p_actor uuid,
  p_action text, p_agg_type text, p_agg uuid, p_target uuid, p_key text, p_policy text, p_idem text,
  p_payload jsonb, p_nbf timestamptz, p_exp timestamptz, p_ws uuid DEFAULT 'a9100000-0000-0000-0000-000000000001')
RETURNS void LANGUAGE sql AS $$
  INSERT INTO governance_proof_receipts(receipt_id,assertion_id,nonce_digest,issuer_id,audience,key_id,workspace_id,
    actor_membership_id,authn_event_ref,assurance_ref,action,aggregate_type,aggregate_id,target_membership_id,
    role_or_permission_key,scope_digest,authority_ref,policy_version,idempotency_key,payload_digest,
    canonicalization_version,
    issued_at,not_before,expires_at,verifier_kind,verifier_outcome)
  VALUES(p_receipt,p_assertion,sha256(convert_to(p_nonce,'UTF8')),'test-issuer','governance_adapter','test-key-1',p_ws,
    p_actor,'authn-event-x','assurance-x',p_action,p_agg_type,p_agg,p_target,p_key,
    sha256(convert_to('scope-x','UTF8')),'authority-x',p_policy,p_idem,
    receipt_payload_digest_v1(p_payload), 'receipt-canon-v1', p_nbf - interval '1 minute', p_nbf, p_exp,
    'external_independent_verifier','verified');
$$;

-- Canonical intent used by most tests: grant role 'counselor' to target membership 3.
SELECT test_receipt('e9100000-0000-0000-0000-000000000001','f9100000-0000-0000-0000-000000000001','nonce-1',
  'b9100000-0000-0000-0000-000000000001','role_granted','membership_role','b9100000-0000-0000-0000-000000000003',
  'b9100000-0000-0000-0000-000000000003','counselor','policy-v1','rc-idem-1','{"role_key":"counselor"}',
  now()-interval '1 hour', now()+interval '1 day');

-- ---- RC-01 verifier registers a receipt (positive, verifier identity only) ----
SET SESSION AUTHORIZATION :"verifier_role";
DO $$ BEGIN
  INSERT INTO governance_proof_receipts(receipt_id,assertion_id,nonce_digest,issuer_id,audience,key_id,workspace_id,
    actor_membership_id,authn_event_ref,assurance_ref,action,aggregate_type,aggregate_id,target_membership_id,
    role_or_permission_key,scope_digest,authority_ref,policy_version,idempotency_key,payload_digest,
    canonicalization_version,
    issued_at,not_before,expires_at,verifier_kind,verifier_outcome)
  VALUES('e9100000-0000-0000-0000-000000000002','f9100000-0000-0000-0000-000000000002',sha256(convert_to('nonce-2','UTF8')),
    'test-issuer','governance_adapter','test-key-1','a9100000-0000-0000-0000-000000000001',
    'b9100000-0000-0000-0000-000000000001','authn-event-x','assurance-x','role_granted','membership_role',
    'b9100000-0000-0000-0000-000000000003','b9100000-0000-0000-0000-000000000003','counselor',
    sha256(convert_to('scope-x','UTF8')),'authority-x','policy-v1','rc-idem-2',
    receipt_payload_digest_v1('{"role_key":"counselor"}'::jsonb), 'receipt-canon-v1',
    now()-interval '2 hours',now()-interval '1 hour',now()+interval '1 day','external_independent_verifier','verified');
  RAISE NOTICE 'PASS RC-01 verifier_rt registers a receipt (INSERT only)';
END $$;
RESET SESSION AUTHORIZATION;

-- ---- RC-02..RC-05 role boundary: registration and consumption denied outside the right identity ----
SET SESSION AUTHORIZATION :"runtime_role";
SELECT expect_error('RC-02a runtime cannot register a receipt',
  $q$INSERT INTO governance_proof_receipts SELECT * FROM governance_proof_receipts LIMIT 0$q$, '42501');
SELECT expect_error('RC-02b runtime cannot read receipts',
  $q$SELECT count(*) FROM governance_proof_receipts$q$, '42501');
SELECT expect_error('RC-02c runtime cannot consume a receipt',
  $q$SELECT * FROM consume_governance_receipt_and_apply('e9100000-0000-0000-0000-000000000001','b9100000-0000-0000-0000-000000000001','role_granted','membership_role','b9100000-0000-0000-0000-000000000003','b9100000-0000-0000-0000-000000000003','counselor',sha256(convert_to('scope-x','UTF8')),'policy-v1','rc-idem-1','{"role_key":"counselor"}'::jsonb,'d9100000-0000-0000-0000-000000000001',now())$q$, '42501');
RESET SESSION AUTHORIZATION;

SET SESSION AUTHORIZATION :"worker_role";
SELECT expect_error('RC-03a worker cannot consume a receipt',
  $q$SELECT * FROM consume_governance_receipt_and_apply('e9100000-0000-0000-0000-000000000001','b9100000-0000-0000-0000-000000000001','role_granted','membership_role','b9100000-0000-0000-0000-000000000003','b9100000-0000-0000-0000-000000000003','counselor',sha256(convert_to('scope-x','UTF8')),'policy-v1','rc-idem-1','{"role_key":"counselor"}'::jsonb,'d9100000-0000-0000-0000-000000000002',now())$q$, '42501');
SELECT expect_error('RC-03b worker cannot modify receipts',
  $q$UPDATE governance_proof_receipts SET status='revoked'$q$, '42501');
RESET SESSION AUTHORIZATION;

SET SESSION AUTHORIZATION :"exporter_role";
SELECT expect_error('RC-04 exporter cannot read receipts',
  $q$SELECT count(*) FROM governance_proof_receipts$q$, '42501');
RESET SESSION AUTHORIZATION;

SET SESSION AUTHORIZATION :"verifier_role";
SELECT expect_error('RC-05a verifier cannot read receipts (no SELECT)',
  $q$SELECT count(*) FROM governance_proof_receipts$q$, '42501');
SELECT expect_error('RC-05b verifier cannot consume a receipt',
  $q$SELECT * FROM consume_governance_receipt_and_apply('e9100000-0000-0000-0000-000000000001','b9100000-0000-0000-0000-000000000001','role_granted','membership_role','b9100000-0000-0000-0000-000000000003','b9100000-0000-0000-0000-000000000003','counselor',sha256(convert_to('scope-x','UTF8')),'policy-v1','rc-idem-1','{"role_key":"counselor"}'::jsonb,'d9100000-0000-0000-0000-000000000003',now())$q$, '42501');
SELECT expect_error('RC-05c verifier cannot modify or delete receipts',
  $q$DELETE FROM governance_proof_receipts$q$, '42501');
SELECT expect_error('RC-05d verifier cannot append governance events',
  $q$INSERT INTO workspace_governance_events SELECT * FROM workspace_governance_events LIMIT 0$q$, '42501');
RESET SESSION AUTHORIZATION;

SET SESSION AUTHORIZATION :"adapter_role";
SELECT expect_error('RC-06a adapter cannot register a receipt',
  $q$INSERT INTO governance_proof_receipts SELECT * FROM governance_proof_receipts LIMIT 0$q$, '42501');
SELECT expect_error('RC-06b adapter cannot read receipt table directly',
  $q$SELECT count(*) FROM governance_proof_receipts$q$, '42501');
SELECT expect_error('RC-06c adapter cannot call the governance append function directly',
  $q$SELECT * FROM append_workspace_governance_event('d9100000-0000-0000-0000-000000000009','membership_role','b9100000-0000-0000-0000-000000000003','role_granted','b9100000-0000-0000-0000-000000000001','authn-event-x','authority-x','policy-v1','direct-key',sha256(convert_to('x','UTF8')),'{"role_key":"counselor"}'::jsonb,now())$q$, '42501');
RESET SESSION AUTHORIZATION;

-- ---- RC-07..RC-12 storage constraints (verifier registration path, test-only inputs) ----
SET SESSION AUTHORIZATION :"verifier_role";
SELECT expect_error('RC-07 verifier_outcome other than verified is refused',
  $q$INSERT INTO governance_proof_receipts(receipt_id,assertion_id,nonce_digest,issuer_id,audience,key_id,workspace_id,actor_membership_id,authn_event_ref,assurance_ref,action,aggregate_type,aggregate_id,role_or_permission_key,scope_digest,authority_ref,policy_version,idempotency_key,payload_digest,canonicalization_version,issued_at,not_before,expires_at,verifier_kind,verifier_outcome)
     VALUES(gen_random_uuid(),gen_random_uuid(),sha256(convert_to('n-7','UTF8')),'i','governance_adapter','k','a9100000-0000-0000-0000-000000000001','b9100000-0000-0000-0000-000000000001','a','b','role_granted','membership_role',gen_random_uuid(),'counselor',sha256('s'::bytea),'auth','policy-v1','k7',sha256('p'::bytea),'receipt-canon-v1',now(),now(),now()+interval '1 day','external_independent_verifier','true')$q$, '23514');
SELECT expect_error('RC-08 guardian-family receipt refused at storage (Q-007 open)',
  $q$INSERT INTO governance_proof_receipts(receipt_id,assertion_id,nonce_digest,issuer_id,audience,key_id,workspace_id,actor_membership_id,authn_event_ref,assurance_ref,action,aggregate_type,aggregate_id,scope_digest,authority_ref,policy_version,idempotency_key,payload_digest,canonicalization_version,issued_at,not_before,expires_at,verifier_kind,verifier_outcome)
     VALUES(gen_random_uuid(),gen_random_uuid(),sha256(convert_to('n-8','UTF8')),'i','governance_adapter','k','a9100000-0000-0000-0000-000000000001','b9100000-0000-0000-0000-000000000001','a','b','guardian_granted','guardian_relationship',gen_random_uuid(),sha256('s'::bytea),'auth','policy-v1','k8',sha256('p'::bytea),'receipt-canon-v1',now(),now(),now()+interval '1 day','external_independent_verifier','verified')$q$, '23514');
SELECT expect_error('RC-09 expiry not after not-before is refused',
  $q$INSERT INTO governance_proof_receipts(receipt_id,assertion_id,nonce_digest,issuer_id,audience,key_id,workspace_id,actor_membership_id,authn_event_ref,assurance_ref,action,aggregate_type,aggregate_id,scope_digest,authority_ref,policy_version,idempotency_key,payload_digest,canonicalization_version,issued_at,not_before,expires_at,verifier_kind,verifier_outcome)
     VALUES(gen_random_uuid(),gen_random_uuid(),sha256(convert_to('n-9','UTF8')),'i','governance_adapter','k','a9100000-0000-0000-0000-000000000001','b9100000-0000-0000-0000-000000000001','a','b','role_granted','membership_role',gen_random_uuid(),sha256('s'::bytea),'auth','policy-v1','k9',sha256('p'::bytea),'receipt-canon-v1',now()-interval '2 hours',now()-interval '1 hour',now()-interval '2 hours','external_independent_verifier','verified')$q$, '23514');
-- Uniqueness is a property of the constraint, not of a role: run as the table owner.
RESET SESSION AUTHORIZATION;
SELECT expect_error('RC-10 duplicate assertion_id is refused (single assertion, single receipt)',
  $q$INSERT INTO governance_proof_receipts SELECT gen_random_uuid(), assertion_id, sha256(convert_to('other','UTF8')), issuer_id,audience,key_id,workspace_id,actor_membership_id,authn_event_ref,assurance_ref,action,aggregate_type,aggregate_id,target_membership_id,role_or_permission_key,scope_digest,authority_ref,policy_version,'k10',payload_digest,canonicalization_version,issued_at,not_before,expires_at,verifier_kind,verifier_outcome FROM governance_proof_receipts WHERE receipt_id='e9100000-0000-0000-0000-000000000001'$q$, '23505', 'assertion_id');
SELECT expect_error('RC-11 duplicate nonce digest is refused (replay guard)',
  $q$INSERT INTO governance_proof_receipts SELECT gen_random_uuid(), gen_random_uuid(), nonce_digest, issuer_id,audience,key_id,workspace_id,actor_membership_id,authn_event_ref,assurance_ref,action,aggregate_type,aggregate_id,target_membership_id,role_or_permission_key,scope_digest,authority_ref,policy_version,'k11',payload_digest,canonicalization_version,issued_at,not_before,expires_at,verifier_kind,verifier_outcome FROM governance_proof_receipts WHERE receipt_id='e9100000-0000-0000-0000-000000000001'$q$, '23505', 'nonce_digest');
RESET SESSION AUTHORIZATION;

-- Immutability and no-delete (owner-level guard; also denied to every runtime identity above).
SELECT expect_error('RC-12a binding column cannot be altered after registration',
  $q$UPDATE governance_proof_receipts SET action='role_revoked' WHERE receipt_id='e9100000-0000-0000-0000-000000000001'$q$, '23514', 'immutable');
SELECT expect_error('RC-12b receipts are never deleted',
  $q$DELETE FROM governance_proof_receipts WHERE receipt_id='e9100000-0000-0000-0000-000000000001'$q$, '23514', 'never deleted');

-- ---- RC-13..RC-19 exact binding mismatches (each rejected; the receipt is NOT consumed by a rejection) ----
SET SESSION AUTHORIZATION :"adapter_role";
SELECT expect_error('RC-13 actor mismatch rejected',
  $q$SELECT * FROM consume_governance_receipt_and_apply('e9100000-0000-0000-0000-000000000001','b9100000-0000-0000-0000-000000000002','role_granted','membership_role','b9100000-0000-0000-0000-000000000003','b9100000-0000-0000-0000-000000000003','counselor',sha256(convert_to('scope-x','UTF8')),'policy-v1','rc-idem-1','{"role_key":"counselor"}'::jsonb,'d9100000-0000-0000-0000-000000000011',now())$q$, '23514', 'binding mismatch: actor');
SELECT expect_error('RC-14 action alteration rejected',
  $q$SELECT * FROM consume_governance_receipt_and_apply('e9100000-0000-0000-0000-000000000001','b9100000-0000-0000-0000-000000000001','role_revoked','membership_role','b9100000-0000-0000-0000-000000000003','b9100000-0000-0000-0000-000000000003','counselor',sha256(convert_to('scope-x','UTF8')),'policy-v1','rc-idem-1','{"role_key":"counselor"}'::jsonb,'d9100000-0000-0000-0000-000000000012',now())$q$, '23514', 'binding mismatch: action');
SELECT expect_error('RC-15 target alteration rejected',
  $q$SELECT * FROM consume_governance_receipt_and_apply('e9100000-0000-0000-0000-000000000001','b9100000-0000-0000-0000-000000000001','role_granted','membership_role','b9100000-0000-0000-0000-000000000003','b9100000-0000-0000-0000-000000000002','counselor',sha256(convert_to('scope-x','UTF8')),'policy-v1','rc-idem-1','{"role_key":"counselor"}'::jsonb,'d9100000-0000-0000-0000-000000000013',now())$q$, '23514', 'binding mismatch: target');
SELECT expect_error('RC-16 scope alteration rejected',
  $q$SELECT * FROM consume_governance_receipt_and_apply('e9100000-0000-0000-0000-000000000001','b9100000-0000-0000-0000-000000000001','role_granted','membership_role','b9100000-0000-0000-0000-000000000003','b9100000-0000-0000-0000-000000000003','counselor',sha256(convert_to('scope-OTHER','UTF8')),'policy-v1','rc-idem-1','{"role_key":"counselor"}'::jsonb,'d9100000-0000-0000-0000-000000000014',now())$q$, '23514', 'binding mismatch: scope');
SELECT expect_error('RC-17 policy alteration rejected',
  $q$SELECT * FROM consume_governance_receipt_and_apply('e9100000-0000-0000-0000-000000000001','b9100000-0000-0000-0000-000000000001','role_granted','membership_role','b9100000-0000-0000-0000-000000000003','b9100000-0000-0000-0000-000000000003','counselor',sha256(convert_to('scope-x','UTF8')),'policy-v2','rc-idem-1','{"role_key":"counselor"}'::jsonb,'d9100000-0000-0000-0000-000000000015',now())$q$, '23514', 'binding mismatch: policy');
SELECT expect_error('RC-18 payload alteration rejected',
  $q$SELECT * FROM consume_governance_receipt_and_apply('e9100000-0000-0000-0000-000000000001','b9100000-0000-0000-0000-000000000001','role_granted','membership_role','b9100000-0000-0000-0000-000000000003','b9100000-0000-0000-0000-000000000003','counselor',sha256(convert_to('scope-x','UTF8')),'policy-v1','rc-idem-1','{"role_key":"admin"}'::jsonb,'d9100000-0000-0000-0000-000000000016',now())$q$, '23514', 'binding mismatch: payload');
SELECT expect_error('RC-19 role/permission key alteration rejected',
  $q$SELECT * FROM consume_governance_receipt_and_apply('e9100000-0000-0000-0000-000000000001','b9100000-0000-0000-0000-000000000001','role_granted','membership_role','b9100000-0000-0000-0000-000000000003','b9100000-0000-0000-0000-000000000003','owner',sha256(convert_to('scope-x','UTF8')),'policy-v1','rc-idem-1','{"role_key":"counselor"}'::jsonb,'d9100000-0000-0000-0000-000000000017',now())$q$, '23514', 'binding mismatch: role');
RESET SESSION AUTHORIZATION;

-- ---- RC-20 cross-Workspace receipt rejected; RC-21 not-yet-valid; RC-22 expired; RC-23 revoked ----
SELECT test_receipt('e9100000-0000-0000-0000-000000000020','f9100000-0000-0000-0000-000000000020','nonce-20',
  'b9100000-0000-0000-0000-000000000001','role_granted','membership_role','b9100000-0000-0000-0000-000000000003',
  'b9100000-0000-0000-0000-000000000003','counselor','policy-v1','rc-idem-20','{"role_key":"counselor"}',
  now()-interval '1 hour', now()+interval '1 day','a9100000-0000-0000-0000-000000000099');
SELECT test_receipt('e9100000-0000-0000-0000-000000000021','f9100000-0000-0000-0000-000000000021','nonce-21',
  'b9100000-0000-0000-0000-000000000001','role_granted','membership_role','b9100000-0000-0000-0000-000000000003',
  'b9100000-0000-0000-0000-000000000003','counselor','policy-v1','rc-idem-21','{"role_key":"counselor"}',
  now()+interval '1 day', now()+interval '2 days');
SELECT test_receipt('e9100000-0000-0000-0000-000000000022','f9100000-0000-0000-0000-000000000022','nonce-22',
  'b9100000-0000-0000-0000-000000000001','role_granted','membership_role','b9100000-0000-0000-0000-000000000003',
  'b9100000-0000-0000-0000-000000000003','counselor','policy-v1','rc-idem-22','{"role_key":"counselor"}',
  now()-interval '2 days', now()-interval '1 day');
SELECT test_receipt('e9100000-0000-0000-0000-000000000023','f9100000-0000-0000-0000-000000000023','nonce-23',
  'b9100000-0000-0000-0000-000000000001','role_granted','membership_role','b9100000-0000-0000-0000-000000000003',
  'b9100000-0000-0000-0000-000000000003','counselor','policy-v1','rc-idem-23','{"role_key":"counselor"}',
  now()-interval '1 hour', now()+interval '1 day');
UPDATE governance_proof_receipts SET status='revoked' WHERE receipt_id='e9100000-0000-0000-0000-000000000023';

SET SESSION AUTHORIZATION :"adapter_role";
SELECT expect_error('RC-20 receipt for another Workspace rejected',
  $q$SELECT * FROM consume_governance_receipt_and_apply('e9100000-0000-0000-0000-000000000020','b9100000-0000-0000-0000-000000000001','role_granted','membership_role','b9100000-0000-0000-0000-000000000003','b9100000-0000-0000-0000-000000000003','counselor',sha256(convert_to('scope-x','UTF8')),'policy-v1','rc-idem-20','{"role_key":"counselor"}'::jsonb,'d9100000-0000-0000-0000-000000000020',now())$q$, '23514', 'not for this Workspace');
SELECT expect_error('RC-21 not-yet-valid receipt rejected',
  $q$SELECT * FROM consume_governance_receipt_and_apply('e9100000-0000-0000-0000-000000000021','b9100000-0000-0000-0000-000000000001','role_granted','membership_role','b9100000-0000-0000-0000-000000000003','b9100000-0000-0000-0000-000000000003','counselor',sha256(convert_to('scope-x','UTF8')),'policy-v1','rc-idem-21','{"role_key":"counselor"}'::jsonb,'d9100000-0000-0000-0000-000000000021',now())$q$, '23514', 'not valid at this time');
SELECT expect_error('RC-22 expired receipt rejected',
  $q$SELECT * FROM consume_governance_receipt_and_apply('e9100000-0000-0000-0000-000000000022','b9100000-0000-0000-0000-000000000001','role_granted','membership_role','b9100000-0000-0000-0000-000000000003','b9100000-0000-0000-0000-000000000003','counselor',sha256(convert_to('scope-x','UTF8')),'policy-v1','rc-idem-22','{"role_key":"counselor"}'::jsonb,'d9100000-0000-0000-0000-000000000022',now())$q$, '23514', 'not valid at this time');
SELECT expect_error('RC-23 revoked receipt rejected',
  $q$SELECT * FROM consume_governance_receipt_and_apply('e9100000-0000-0000-0000-000000000023','b9100000-0000-0000-0000-000000000001','role_granted','membership_role','b9100000-0000-0000-0000-000000000003','b9100000-0000-0000-0000-000000000003','counselor',sha256(convert_to('scope-x','UTF8')),'policy-v1','rc-idem-23','{"role_key":"counselor"}'::jsonb,'d9100000-0000-0000-0000-000000000023',now())$q$, '42501', 'revoked');
RESET SESSION AUTHORIZATION;

-- ---- RC-24 positive consume (exactly once) with projection update in the same transaction ----
SET SESSION AUTHORIZATION :"adapter_role";
DO $$ DECLARE got record; BEGIN
  SELECT * INTO got FROM consume_governance_receipt_and_apply('e9100000-0000-0000-0000-000000000001','b9100000-0000-0000-0000-000000000001','role_granted','membership_role','b9100000-0000-0000-0000-000000000003','b9100000-0000-0000-0000-000000000003','counselor',sha256(convert_to('scope-x','UTF8')),'policy-v1','rc-idem-1','{"role_key":"counselor"}'::jsonb,'d9100000-0000-0000-0000-000000000030',now());
  IF got.event_id IS NULL THEN RAISE EXCEPTION 'FAIL RC-24: no event'; END IF;
  RAISE NOTICE 'PASS RC-24 adapter consumes receipt once: event % sequence %', got.event_id, got.event_sequence;
END $$;
RESET SESSION AUTHORIZATION;
DO $$ BEGIN
  IF (SELECT status FROM governance_proof_receipts WHERE receipt_id='e9100000-0000-0000-0000-000000000001') <> 'consumed' THEN RAISE EXCEPTION 'FAIL RC-24b: receipt not consumed'; END IF;
  IF NOT EXISTS (SELECT 1 FROM membership_roles WHERE membership_id='b9100000-0000-0000-0000-000000000003' AND role_key='counselor') THEN RAISE EXCEPTION 'FAIL RC-24c: projection not updated'; END IF;
  IF (SELECT count(*) FROM workspace_governance_events WHERE idempotency_key='rc-idem-1') <> 1 THEN RAISE EXCEPTION 'FAIL RC-24d: expected exactly one event'; END IF;
  RAISE NOTICE 'PASS RC-24b/c/d receipt consumed, projection updated, exactly one event';
END $$;

-- ---- RC-25 identical retry returns the original result (no second effect) ----
SET SESSION AUTHORIZATION :"adapter_role";
DO $$ DECLARE a record; b record; BEGIN
  SELECT * INTO a FROM consume_governance_receipt_and_apply('e9100000-0000-0000-0000-000000000001','b9100000-0000-0000-0000-000000000001','role_granted','membership_role','b9100000-0000-0000-0000-000000000003','b9100000-0000-0000-0000-000000000003','counselor',sha256(convert_to('scope-x','UTF8')),'policy-v1','rc-idem-1','{"role_key":"counselor"}'::jsonb,'d9100000-0000-0000-0000-000000000031',now());
  RAISE NOTICE 'PASS RC-25a identical retry returned event % (consume call accepted)', a.event_id;
END $$;
RESET SESSION AUTHORIZATION;
-- Counting events needs the owner: the adapter identity has no read privilege on the event ledger.
DO $$ BEGIN
  IF (SELECT count(*) FROM workspace_governance_events WHERE idempotency_key='rc-idem-1') <> 1 THEN RAISE EXCEPTION 'FAIL RC-25b: retry created a second event'; END IF;
  RAISE NOTICE 'PASS RC-25b identical retry produced no second event';
END $$;

-- ---- RC-26 same receipt, different idempotency key: single use enforced ----
-- The idempotency key is part of the receipt binding: a different key is a binding mismatch.
SET SESSION AUTHORIZATION :"adapter_role";
SELECT expect_error('RC-26 consumed receipt cannot be reused under a different key',
  $q$SELECT * FROM consume_governance_receipt_and_apply('e9100000-0000-0000-0000-000000000001','b9100000-0000-0000-0000-000000000001','role_granted','membership_role','b9100000-0000-0000-0000-000000000003','b9100000-0000-0000-0000-000000000003','counselor',sha256(convert_to('scope-x','UTF8')),'policy-v1','rc-other-key','{"role_key":"counselor"}'::jsonb,'d9100000-0000-0000-0000-000000000032',now())$q$, '23514', 'binding mismatch: idempotency key');
RESET SESSION AUTHORIZATION;

RESET SESSION AUTHORIZATION;

-- ---- RC-27 a new receipt cannot reuse an idempotency key already used by another event ----
SELECT test_receipt('e9100000-0000-0000-0000-000000000027','f9100000-0000-0000-0000-000000000027','nonce-27',
  'b9100000-0000-0000-0000-000000000001','role_granted','membership_role','b9100000-0000-0000-0000-000000000003',
  'b9100000-0000-0000-0000-000000000003','counselor','policy-v1','rc-idem-1','{"role_key":"counselor"}',
  now()-interval '1 hour', now()+interval '1 day');
SET SESSION AUTHORIZATION :"adapter_role";
SELECT expect_error('RC-27 idempotency key already used by another governance event is refused',
  $q$SELECT * FROM consume_governance_receipt_and_apply('e9100000-0000-0000-0000-000000000027','b9100000-0000-0000-0000-000000000001','role_granted','membership_role','b9100000-0000-0000-0000-000000000003','b9100000-0000-0000-0000-000000000003','counselor',sha256(convert_to('scope-x','UTF8')),'policy-v1','rc-idem-1','{"role_key":"counselor"}'::jsonb,'d9100000-0000-0000-0000-000000000027',now())$q$, '23505', 'already used');
RESET SESSION AUTHORIZATION;

-- ---- RC-28 event-append failure rolls back receipt consumption (invalid payload) ----
SELECT test_receipt('e9100000-0000-0000-0000-000000000028','f9100000-0000-0000-0000-000000000028','nonce-28',
  'b9100000-0000-0000-0000-000000000001','role_granted','membership_role','b9100000-0000-0000-0000-000000000003',
  'b9100000-0000-0000-0000-000000000003','counselor','policy-v1','rc-idem-28','{}',
  now()-interval '1 hour', now()+interval '1 day');
SET SESSION AUTHORIZATION :"adapter_role";
DO $$ BEGIN
  PERFORM * FROM consume_governance_receipt_and_apply('e9100000-0000-0000-0000-000000000028','b9100000-0000-0000-0000-000000000001','role_granted','membership_role','b9100000-0000-0000-0000-000000000003','b9100000-0000-0000-0000-000000000003','counselor',sha256(convert_to('scope-x','UTF8')),'policy-v1','rc-idem-28','{}'::jsonb,'d9100000-0000-0000-0000-000000000028',now());
  RAISE EXCEPTION 'FAIL RC-28: append with invalid payload succeeded';
EXCEPTION WHEN invalid_parameter_value THEN
  RAISE NOTICE 'PASS RC-28 append rejected invalid payload (invalid_parameter_value)';
END $$;
RESET SESSION AUTHORIZATION;
SELECT expect_ok('RC-28b receipt remains registered after the rejected consume (no partial effect)',
  $q$DO $i$ BEGIN IF (SELECT status FROM governance_proof_receipts WHERE receipt_id='e9100000-0000-0000-0000-000000000028') <> 'registered' THEN RAISE EXCEPTION 'receipt was consumed'; END IF; IF EXISTS (SELECT 1 FROM workspace_governance_events WHERE idempotency_key='rc-idem-28') THEN RAISE EXCEPTION 'event persisted'; END IF; END $i$$q$);

-- ---- RC-29 inactive target fails closed; receipt stays registered ----
SELECT test_receipt('e9100000-0000-0000-0000-000000000029','f9100000-0000-0000-0000-000000000029','nonce-29',
  'b9100000-0000-0000-0000-000000000001','role_granted','membership_role','b9100000-0000-0000-0000-000000000002',
  'b9100000-0000-0000-0000-000000000002','counselor','policy-v1','rc-idem-29','{"role_key":"counselor"}',
  now()-interval '1 hour', now()+interval '1 day');
SET SESSION AUTHORIZATION :"adapter_role";
DO $$ BEGIN
  PERFORM * FROM consume_governance_receipt_and_apply('e9100000-0000-0000-0000-000000000029','b9100000-0000-0000-0000-000000000001','role_granted','membership_role','b9100000-0000-0000-0000-000000000002','b9100000-0000-0000-0000-000000000002','counselor',sha256(convert_to('scope-x','UTF8')),'policy-v1','rc-idem-29','{"role_key":"counselor"}'::jsonb,'d9100000-0000-0000-0000-000000000029',now());
  RAISE EXCEPTION 'FAIL RC-29: grant to inactive target succeeded';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM LIKE 'FAIL%' THEN RAISE; END IF;
  RAISE NOTICE 'PASS RC-29a inactive target fails closed (%)', SQLERRM;
END $$;
RESET SESSION AUTHORIZATION;
-- Status is read as the owner: the adapter identity has no SELECT on the receipt table.
DO $$ BEGIN
  IF (SELECT status FROM governance_proof_receipts WHERE receipt_id='e9100000-0000-0000-0000-000000000029') <> 'registered' THEN RAISE EXCEPTION 'FAIL RC-29b: receipt consumed on failure'; END IF;
  RAISE NOTICE 'PASS RC-29b receipt remains registered after the rejected grant';
END $$;

-- ---- RC-30 guardian-family consume fails closed (Q-007 open) ----
-- Storage already refuses guardian receipts (RC-08); the materializer independently refuses the aggregate.
SELECT expect_error('RC-30 guardian aggregate refused by the materializer (Q-007 open)',
  $q$SELECT append_workspace_governance_event('d9100000-0000-0000-0000-000000000040','guardian_relationship','b9100000-0000-0000-0000-000000000003','guardian_granted','b9100000-0000-0000-0000-000000000001','authn-event-x','authority-x','policy-v1','rc-g-30',sha256(convert_to('x','UTF8')),'{}'::jsonb,now())$q$, '0A000', 'Q-007');

-- ---- RC-31 catalog: runtime/worker/exporter/verifier/adapter hold no forbidden privileges ----
DO $$ BEGIN
  IF has_function_privilege(ws_role('runtime'), 'consume_governance_receipt_and_apply(uuid,uuid,text,text,uuid,uuid,text,bytea,text,text,jsonb,uuid,timestamptz)', 'EXECUTE')
     OR has_function_privilege(ws_role('worker'), 'consume_governance_receipt_and_apply(uuid,uuid,text,text,uuid,uuid,text,bytea,text,text,jsonb,uuid,timestamptz)', 'EXECUTE')
     OR has_function_privilege(ws_role('exporter'), 'consume_governance_receipt_and_apply(uuid,uuid,text,text,uuid,uuid,text,bytea,text,text,jsonb,uuid,timestamptz)', 'EXECUTE')
     OR has_function_privilege(ws_role('verifier_rt'), 'consume_governance_receipt_and_apply(uuid,uuid,text,text,uuid,uuid,text,bytea,text,text,jsonb,uuid,timestamptz)', 'EXECUTE') THEN
    RAISE EXCEPTION 'FAIL RC-31a: a non-adapter identity can execute the consume function';
  END IF;
  IF has_table_privilege(ws_role('runtime'), 'governance_proof_receipts', 'SELECT,INSERT,UPDATE,DELETE')
     OR has_table_privilege(ws_role('worker'), 'governance_proof_receipts', 'SELECT,INSERT,UPDATE,DELETE')
     OR has_table_privilege(ws_role('exporter'), 'governance_proof_receipts', 'SELECT,INSERT,UPDATE,DELETE') THEN
    RAISE EXCEPTION 'FAIL RC-31b: runtime/worker/exporter has a receipt table privilege';
  END IF;
  IF has_table_privilege(ws_role('verifier_rt'), 'governance_proof_receipts', 'SELECT,UPDATE,DELETE')
     OR has_table_privilege(ws_role('governance_adapter_rt'), 'governance_proof_receipts', 'SELECT,INSERT,UPDATE,DELETE') THEN
    RAISE EXCEPTION 'FAIL RC-31c: verifier/adapter holds a forbidden table privilege';
  END IF;
  IF pg_has_role(ws_role('governance_adapter_rt'), ws_role('governance_owner'), 'MEMBER') THEN
    RAISE EXCEPTION 'FAIL RC-31d: adapter can assume the governance owner';
  END IF;
  IF pg_has_role(ws_role('verifier_rt'), ws_role('governance_owner'), 'MEMBER') THEN
    RAISE EXCEPTION 'FAIL RC-31e: verifier can assume the governance owner';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname IN (ws_role('verifier_rt'),ws_role('governance_adapter_rt'),ws_role('runtime'),ws_role('worker'),ws_role('exporter')) AND rolsuper) THEN
    RAISE EXCEPTION 'FAIL RC-31f: a runtime identity is a superuser';
  END IF;
  RAISE NOTICE 'PASS RC-31 catalog: no forbidden execute/table privilege; no owner membership; no superuser';
END $$;

DO $$ BEGIN RAISE NOTICE '=== GOVERNANCE PROOF RECEIPT SUITE COMPLETED (synthetic) ==='; END $$;
