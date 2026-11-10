-- Governance event ledger tests. Synthetic only; run after workspace_schema_draft.sql
-- and workspace_governance_events_draft.sql in a fresh database.
\set ON_ERROR_STOP on

INSERT INTO workspace_profile(singleton,workspace_id,workspace_type)
VALUES(true,'a9100000-0000-0000-0000-000000000001','organization');
INSERT INTO workspace_memberships(membership_id,platform_user_id,status) VALUES
 ('b9100000-0000-0000-0000-000000000001','c9100000-0000-0000-0000-000000000001','active'),
 ('b9100000-0000-0000-0000-000000000002','c9100000-0000-0000-0000-000000000002','suspended'),
 ('b9100000-0000-0000-0000-000000000003','c9100000-0000-0000-0000-000000000003','active');

DO $tests$
DECLARE first_id uuid; first_seq bigint; replay_id uuid; replay_seq bigint;
BEGIN
  SELECT e.event_id,e.event_sequence INTO first_id,first_seq
  FROM append_workspace_governance_event(
    'd9100000-0000-0000-0000-000000000001','membership_role',
    'b9100000-0000-0000-0000-000000000001','role_granted',
    'b9100000-0000-0000-0000-000000000001','authn-event-1','authority-assertion-1',
    'policy-v1','gov-role-grant-1',decode(repeat('11',32),'hex'),
    '{"role_key":"counselor"}'::jsonb,TIMESTAMPTZ '2026-11-10 00:00:00+00') e;
  IF first_seq<>1 THEN RAISE EXCEPTION 'FAIL GOV-01 first event sequence must be 1'; END IF;

  IF NOT EXISTS (SELECT 1 FROM membership_roles
      WHERE membership_id='b9100000-0000-0000-0000-000000000001' AND role_key='counselor') THEN
    RAISE EXCEPTION 'FAIL GOV-09 role grant event did not update canonical projection';
  END IF;
  SELECT e.event_id,e.event_sequence INTO replay_id,replay_seq
  FROM append_workspace_governance_event(
    'd9100000-0000-0000-0000-000000000099','membership_role',
    'b9100000-0000-0000-0000-000000000001','role_granted',
    'b9100000-0000-0000-0000-000000000001','authn-event-1','authority-assertion-1',
    'policy-v1','gov-role-grant-1',decode(repeat('11',32),'hex'),
    '{"role_key":"counselor"}'::jsonb,TIMESTAMPTZ '2026-11-10 00:00:00+00') e;
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
  IF EXISTS (SELECT 1 FROM membership_roles
      WHERE membership_id='b9100000-0000-0000-0000-000000000001' AND role_key='counselor') THEN
    RAISE EXCEPTION 'FAIL GOV-10 role revoke event did not remove canonical projection';
  END IF;

  PERFORM append_workspace_governance_event(
    'd9100000-0000-0000-0000-000000000006','membership_permission',
    'b9100000-0000-0000-0000-000000000001','permission_granted',
    'b9100000-0000-0000-0000-000000000001','authn-event-6','authority-6',
    'policy-v1','gov-permission-grant-1',decode(repeat('66',32),'hex'),
    '{"permission_key":"student.read","resource_scope":{"student_ids":["s1"]}}'::jsonb,now());
  IF NOT EXISTS (SELECT 1 FROM membership_permissions
      WHERE membership_id='b9100000-0000-0000-0000-000000000001'
        AND permission_key='student.read'
        AND resource_scope='{"student_ids":["s1"]}'::jsonb) THEN
    RAISE EXCEPTION 'FAIL GOV-11 permission grant projection mismatch';
  END IF;

  PERFORM append_workspace_governance_event(
    'd9100000-0000-0000-0000-000000000007','membership_permission',
    'b9100000-0000-0000-0000-000000000001','permission_scope_changed',
    'b9100000-0000-0000-0000-000000000001','authn-event-7','authority-7',
    'policy-v1','gov-permission-scope-1',decode(repeat('77',32),'hex'),
    '{"permission_key":"student.read","resource_scope":{"student_ids":["s1","s2"]}}'::jsonb,now());
  IF NOT EXISTS (SELECT 1 FROM membership_permissions
      WHERE membership_id='b9100000-0000-0000-0000-000000000001'
        AND permission_key='student.read'
        AND resource_scope='{"student_ids":["s1","s2"]}'::jsonb) THEN
    RAISE EXCEPTION 'FAIL GOV-12 permission scope change projection mismatch';
  END IF;

  PERFORM append_workspace_governance_event(
    'd9100000-0000-0000-0000-000000000008','membership_permission',
    'b9100000-0000-0000-0000-000000000001','permission_revoked',
    'b9100000-0000-0000-0000-000000000001','authn-event-8',NULL,
    'policy-v1','gov-permission-revoke-1',decode(repeat('88',32),'hex'),
    '{"permission_key":"student.read"}'::jsonb,now());
  IF EXISTS (SELECT 1 FROM membership_permissions
      WHERE membership_id='b9100000-0000-0000-0000-000000000001'
        AND permission_key='student.read') THEN
    RAISE EXCEPTION 'FAIL GOV-13 permission revoke projection mismatch';
  END IF;

  PERFORM append_workspace_governance_event(
    'd9100000-0000-0000-0000-000000000009','membership',
    'b9100000-0000-0000-0000-000000000001','membership_suspended',
    'b9100000-0000-0000-0000-000000000003','authn-event-9',NULL,
    'policy-v1','gov-membership-suspend-1',decode(repeat('99',32),'hex'),
    '{"reason":"synthetic"}'::jsonb,now());
  IF (SELECT status FROM workspace_memberships
      WHERE membership_id='b9100000-0000-0000-0000-000000000001')<>'suspended'
     OR EXISTS (SELECT 1 FROM membership_roles
      WHERE membership_id='b9100000-0000-0000-0000-000000000001')
     OR EXISTS (SELECT 1 FROM membership_permissions
      WHERE membership_id='b9100000-0000-0000-0000-000000000001') THEN
    RAISE EXCEPTION 'FAIL GOV-14 suspension did not invalidate role/permission projections';
  END IF;
  RAISE NOTICE 'PASS GOV-01..14 event sequencing, idempotency and projection consistency';
END $tests$;

DO $replay_after_suspension$
DECLARE replay_id uuid;
BEGIN
  SELECT e.event_id INTO replay_id
  FROM append_workspace_governance_event(
    'd9100000-0000-0000-0000-000000000099','membership_role',
    'b9100000-0000-0000-0000-000000000001','role_granted',
    'b9100000-0000-0000-0000-000000000001','authn-event-1','authority-assertion-1',
    'policy-v1','gov-role-grant-1',decode(repeat('11',32),'hex'),
    '{"role_key":"counselor"}'::jsonb,TIMESTAMPTZ '2026-11-10 00:00:00+00') e;
  IF replay_id<>'d9100000-0000-0000-0000-000000000001'::uuid THEN
    RAISE EXCEPTION 'FAIL GOV-15 replay after actor suspension did not return original event';
  END IF;
  RAISE NOTICE 'PASS GOV-15 idempotent replay remains stable after actor suspension';
END $replay_after_suspension$;

DO $lifecycle$
BEGIN
  PERFORM append_workspace_governance_event(
    'd9100000-0000-0000-0000-000000000010','membership',
    'b9100000-0000-0000-0000-000000000001','membership_reactivated',
    'b9100000-0000-0000-0000-000000000003','authn-event-10','authority-10',
    'policy-v1','gov-membership-reactivate-1',decode(repeat('aa',32),'hex'),
    '{"reason":"synthetic reactivation"}'::jsonb,TIMESTAMPTZ '2026-11-10 01:00:00+00');
  IF (SELECT status FROM workspace_memberships
      WHERE membership_id='b9100000-0000-0000-0000-000000000001')<>'active'
     OR EXISTS (SELECT 1 FROM membership_roles
      WHERE membership_id='b9100000-0000-0000-0000-000000000001')
     OR EXISTS (SELECT 1 FROM membership_permissions
      WHERE membership_id='b9100000-0000-0000-0000-000000000001') THEN
    RAISE EXCEPTION 'FAIL GOV-16 reactivation resurrected stale role/permission grants';
  END IF;

  PERFORM append_workspace_governance_event(
    'd9100000-0000-0000-0000-000000000011','membership',
    'b9100000-0000-0000-0000-000000000001','membership_ended',
    'b9100000-0000-0000-0000-000000000003','authn-event-11','authority-11',
    'policy-v1','gov-membership-end-1',decode(repeat('bb',32),'hex'),
    '{"reason":"synthetic end"}'::jsonb,TIMESTAMPTZ '2026-11-10 02:00:00+00');
  IF (SELECT status FROM workspace_memberships
      WHERE membership_id='b9100000-0000-0000-0000-000000000001')<>'ended'
     OR (SELECT ended_at FROM workspace_memberships
      WHERE membership_id='b9100000-0000-0000-0000-000000000001')<>TIMESTAMPTZ '2026-11-10 02:00:00+00' THEN
    RAISE EXCEPTION 'FAIL GOV-17 membership end state/timestamp incorrect';
  END IF;
  RAISE NOTICE 'PASS GOV-16..17 reactivation does not resurrect grants; end timestamp is recorded';
END $lifecycle$;

DO $negative$
BEGIN
  BEGIN
    PERFORM append_workspace_governance_event(
      'd9100000-0000-0000-0000-000000000003','membership_role',
      'b9100000-0000-0000-0000-000000000001','role_granted',
      'b9100000-0000-0000-0000-000000000003','authn-event-3',NULL,
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
      'd9100000-0000-0000-0000-000000000012','membership_role',
      'b9100000-0000-0000-0000-000000000002','role_granted',
      'b9100000-0000-0000-0000-000000000003','authn-event-12','authority-12',
      'policy-v1','gov-role-grant-to-suspended',decode(repeat('cc',32),'hex'),
      '{"role_key":"counselor"}'::jsonb,now());
    RAISE EXCEPTION 'FAIL GOV-18 role grant to suspended target unexpectedly succeeded';
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'PASS GOV-18 role grant to suspended target rejected';
  END;

  BEGIN
    PERFORM append_workspace_governance_event(
      'd9100000-0000-0000-0000-000000000013','membership',
      'b9100000-0000-0000-0000-000000000003','membership_reactivated',
      'b9100000-0000-0000-0000-000000000003','authn-event-13','authority-13',
      'policy-v1','gov-invalid-reactivation',decode(repeat('dd',32),'hex'),
      '{"reason":"invalid transition"}'::jsonb,now());
    RAISE EXCEPTION 'FAIL GOV-19 invalid membership transition unexpectedly succeeded';
  EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'PASS GOV-19 invalid membership transition rejected';
  END;

  BEGIN
    PERFORM append_workspace_governance_event(
      'd9100000-0000-0000-0000-000000000005','membership_role',
      'b9100000-0000-0000-0000-000000000001','role_revoked',
      'b9100000-0000-0000-0000-000000000003','authn-event-5',NULL,
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
