-- Governance event ledger tests. Synthetic only; run after workspace_schema_draft.sql
-- and workspace_governance_events_draft.sql in a fresh database.
\set ON_ERROR_STOP on

INSERT INTO workspace_profile(singleton,workspace_id,workspace_type)
VALUES(true,'a9100000-0000-0000-0000-000000000001','organization');
INSERT INTO workspace_memberships(membership_id,platform_user_id,status) VALUES
 ('b9100000-0000-0000-0000-000000000001','c9100000-0000-0000-0000-000000000001','active'),
 ('b9100000-0000-0000-0000-000000000002','c9100000-0000-0000-0000-000000000002','suspended');

DO $tests$
DECLARE first_id uuid; first_seq bigint; replay_id uuid; replay_seq bigint;
BEGIN
  SELECT e.event_id,e.event_sequence INTO first_id,first_seq
  FROM append_workspace_governance_event(
    'd9100000-0000-0000-0000-000000000001','membership_role',
    'b9100000-0000-0000-0000-000000000001','role_granted',
    'b9100000-0000-0000-0000-000000000001','authn-event-1','authority-assertion-1',
    'policy-v1','gov-role-grant-1',decode(repeat('11',32),'hex'),
    '{"role_key":"counselor"}'::jsonb,now()) e;
  IF first_seq<>1 THEN RAISE EXCEPTION 'FAIL GOV-01 first event sequence must be 1'; END IF;

  SELECT e.event_id,e.event_sequence INTO replay_id,replay_seq
  FROM append_workspace_governance_event(
    'd9100000-0000-0000-0000-000000000099','membership_role',
    'b9100000-0000-0000-0000-000000000001','role_granted',
    'b9100000-0000-0000-0000-000000000001','authn-event-1','authority-assertion-1',
    'policy-v1','gov-role-grant-1',decode(repeat('11',32),'hex'),
    '{"role_key":"counselor"}'::jsonb,now()) e;
  IF replay_id<>first_id OR replay_seq<>first_seq THEN
    RAISE EXCEPTION 'FAIL GOV-02 idempotent replay did not return original event';
  END IF;

  PERFORM append_workspace_governance_event(
    'd9100000-0000-0000-0000-000000000002','membership_role',
    'b9100000-0000-0000-0000-000000000001','role_revoked',
    'b9100000-0000-0000-0000-000000000001','authn-event-2',NULL,
    'policy-v1','gov-role-revoke-1',decode(repeat('22',32),'hex'),
    '{"role_key":"counselor"}'::jsonb,now());
  IF (SELECT max(event_sequence) FROM workspace_governance_events
      WHERE aggregate_type='membership_role'
        AND aggregate_id='b9100000-0000-0000-0000-000000000001')<>2 THEN
    RAISE EXCEPTION 'FAIL GOV-03 aggregate sequence did not advance';
  END IF;
  RAISE NOTICE 'PASS GOV-01..03 event sequence and idempotent replay';
END $tests$;

DO $negative$
BEGIN
  BEGIN
    PERFORM append_workspace_governance_event(
      'd9100000-0000-0000-0000-000000000003','membership_role',
      'b9100000-0000-0000-0000-000000000001','role_granted',
      'b9100000-0000-0000-0000-000000000001','authn-event-3',NULL,
      'policy-v1','gov-role-no-authority',decode(repeat('33',32),'hex'),
      '{"role_key":"organization_manager"}'::jsonb,now());
    RAISE EXCEPTION 'FAIL GOV-04 grant without authority reference unexpectedly succeeded';
  EXCEPTION WHEN invalid_parameter_value THEN
    RAISE NOTICE 'PASS GOV-04 grant without authority reference rejected';
  END;

  BEGIN
    PERFORM append_workspace_governance_event(
      'd9100000-0000-0000-0000-000000000004','membership_role',
      'b9100000-0000-0000-0000-000000000001','role_granted',
      'b9100000-0000-0000-0000-000000000002','authn-event-4','authority-4',
      'policy-v1','gov-suspended-actor',decode(repeat('44',32),'hex'),
      '{"role_key":"counselor"}'::jsonb,now());
    RAISE EXCEPTION 'FAIL GOV-05 suspended actor unexpectedly succeeded';
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'PASS GOV-05 suspended actor rejected';
  END;

  BEGIN
    PERFORM append_workspace_governance_event(
      'd9100000-0000-0000-0000-000000000005','membership_role',
      'b9100000-0000-0000-0000-000000000001','role_revoked',
      'b9100000-0000-0000-0000-000000000001','authn-event-5',NULL,
      'policy-v1','gov-role-grant-1',decode(repeat('55',32),'hex'),
      '{"role_key":"counselor"}'::jsonb,now());
    RAISE EXCEPTION 'FAIL GOV-06 idempotency payload mismatch unexpectedly succeeded';
  EXCEPTION WHEN unique_violation THEN
    RAISE NOTICE 'PASS GOV-06 idempotency payload mismatch rejected';
  END;
END $negative$;

DO $immutable$
BEGIN
  BEGIN
    UPDATE workspace_governance_events SET event_payload='{}'::jsonb
    WHERE idempotency_key='gov-role-grant-1';
    RAISE EXCEPTION 'FAIL GOV-07 event UPDATE unexpectedly succeeded';
  EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'PASS GOV-07 event UPDATE rejected';
  END;
  BEGIN
    DELETE FROM workspace_governance_events WHERE idempotency_key='gov-role-grant-1';
    RAISE EXCEPTION 'FAIL GOV-08 event DELETE unexpectedly succeeded';
  EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'PASS GOV-08 event DELETE rejected';
  END;
END $immutable$;

DO $done$ BEGIN RAISE NOTICE '=== WORKSPACE GOVERNANCE EVENT TESTS COMPLETED (synthetic) ==='; END $done$;
