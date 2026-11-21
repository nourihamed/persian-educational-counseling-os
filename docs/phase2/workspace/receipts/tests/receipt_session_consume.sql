-- One concurrent adapter session. Parameters: -v tag -v receipt -v key -v event -v sleep_before -v hold -v ws_adapter
\set ON_ERROR_STOP on
SELECT pg_sleep(:sleep_before);
SET SESSION AUTHORIZATION :"ws_adapter";
BEGIN;
SELECT :'tag' AS tag, event_id, event_sequence FROM consume_governance_receipt_and_apply(
  :'receipt'::uuid, 'b9100000-0000-0000-0000-000000000001', 'role_granted', 'membership_role',
  'b9100000-0000-0000-0000-000000000003', 'b9100000-0000-0000-0000-000000000003', 'counselor',
  sha256(convert_to('scope-x','UTF8')), 'policy-v1', :'key', '{"role_key":"counselor"}'::jsonb,
  :'event'::uuid, now());
SELECT pg_sleep(:hold);
COMMIT;
