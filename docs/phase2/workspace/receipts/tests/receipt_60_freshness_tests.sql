-- =============================================================================
-- Governance proof receipts — FRESHNESS OF THE VALIDITY WINDOW (SYNTHETIC ONLY, D-014).
-- Run after: schema, activation_transactions, governance_events, roles_setup, receipt_00..03,
-- and after tests/receipt_10_tests.sql, which provides the Workspace, the memberships and test_receipt().
--
-- WHY THIS FILE EXISTS
--   `consume_governance_receipt_and_apply()` checked its validity window with now(), which in PostgreSQL
--   is the TRANSACTION START time and does not advance. An adapter could therefore open a transaction
--   while a receipt was still valid and consume it after it had expired. This was demonstrated before the
--   fix: a receipt with a 2-second lifetime was consumed and applied 4 seconds after expiry, and the
--   receipt ended up `consumed` with a governance event attached.
--
--   That mattered more than an ordinary off-by-one, because the expiry window is the ONLY freshness
--   control the database actually has. Revocation propagation across API, export, worker and notification
--   handoffs is PS-8 and deferred, so there is nothing else to fall back on. The command now reads
--   clock_timestamp() once, AFTER taking the receipt lock — the same pattern the H-01 remediation applied
--   to the credit reversal window.
--
-- HOW THE TESTS ARE STRUCTURED, AND WHY
--   The adapter identity has NO privilege on `governance_proof_receipts` (that is RC-06, and it is
--   deliberate). So every read of the receipt row happens as the table owner, outside the adapter's
--   transaction, and the adapter's transaction does nothing but call the command. Each DO block is a
--   single statement and therefore a single transaction, which is what makes now() inside it a fixed,
--   stale timestamp — exactly the condition the defect needed.
--
-- WHAT THESE TESTS DO AND DO NOT PROVE
--   They prove the window is evaluated against the real moment of use rather than the transaction start.
--   They do NOT prove any signature, any channel authentication, or any end-to-end revocation freshness.
--   `verifier_outcome='verified'` remains a recorded test input, never cryptographic proof.
--   No clock-skew tolerance is asserted: PS-5 is deferred and none is implemented.
-- =============================================================================
\set ON_ERROR_STOP on
\if :{?workspace_key}
\else
  \echo 'pass -v workspace_key=<32 lowercase hex>'
  \quit 3
\endif
SET app.workspace_key = :'workspace_key';
SELECT 'ws_'||current_setting('app.workspace_key')||'_governance_adapter_rt' AS adapter_role \gset

-- ===================================================================================================
-- RC-FRESH-01/02  A receipt that expires WHILE the consuming transaction is open must be refused, and
--                 the refusal must leave nothing applied. This is the exact case now() allowed through.
-- ===================================================================================================
SELECT test_receipt('e9600000-0000-0000-0000-000000000001','f9600000-0000-0000-0000-000000000001','nonce-fresh-1',
  'b9100000-0000-0000-0000-000000000001','role_granted','membership_role','b9100000-0000-0000-0000-000000000003',
  'b9100000-0000-0000-0000-000000000003','counselor','policy-v1','rc-fresh-1','{"role_key":"counselor"}',
  clock_timestamp()-interval '1 second', clock_timestamp()+interval '2 seconds');

-- Captured as the owner: the window this test depends on.
SELECT expires_at AS exp1 FROM governance_proof_receipts
 WHERE receipt_id='e9600000-0000-0000-0000-000000000001' \gset

-- The adapter's transaction. It starts while the receipt is valid, waits past expiry, then consumes.
-- It reads no table: only the command is called.
SET SESSION AUTHORIZATION :"adapter_role";
DO $$
DECLARE
  v_tx_start timestamptz := now();
BEGIN
  PERFORM pg_sleep(3.5);   -- the receipt expires during this wait; now() does not move
  BEGIN
    PERFORM public.consume_governance_receipt_and_apply(
      'e9600000-0000-0000-0000-000000000001','b9100000-0000-0000-0000-000000000001','role_granted',
      'membership_role','b9100000-0000-0000-0000-000000000003','b9100000-0000-0000-0000-000000000003',
      'counselor', sha256(convert_to('scope-x','UTF8')),'policy-v1','rc-fresh-1',
      '{"role_key":"counselor"}'::jsonb,'d9600000-0000-0000-0000-000000000001', now());
    RAISE EXCEPTION 'FAIL RC-FRESH-01 a receipt that expired during the transaction was CONSUMED. The '
                    'validity window is being evaluated against the transaction start time (%), not the '
                    'real moment of use (%).', v_tx_start, clock_timestamp();
  EXCEPTION WHEN check_violation THEN
    IF position('not valid at this time' IN SQLERRM) = 0 THEN
      RAISE EXCEPTION 'FAIL RC-FRESH-01 refused for the wrong reason: %', SQLERRM;
    END IF;
    RAISE NOTICE 'PASS RC-FRESH-01 a receipt that expired during the open transaction is refused '
                 '(tx start %, real %)', v_tx_start, clock_timestamp();
  END;
END $$;
RESET SESSION AUTHORIZATION;

-- Preconditions and post-state, both checked as the owner.
DO $$
DECLARE r public.governance_proof_receipts%ROWTYPE;
BEGIN
  SELECT * INTO r FROM public.governance_proof_receipts
   WHERE receipt_id='e9600000-0000-0000-0000-000000000001';
  -- The test only means something if the receipt really did expire between transaction start and use.
  IF r.expires_at >= clock_timestamp() THEN
    RAISE EXCEPTION 'FAIL RC-FRESH-01 setup: the receipt had not expired by the end of the test '
                    '(expires %, now %)', r.expires_at, clock_timestamp();
  END IF;
  IF r.status <> 'registered' THEN
    RAISE EXCEPTION 'FAIL RC-FRESH-02 the receipt is % after a refused consumption, expected registered',
      r.status;
  END IF;
  IF r.consumed_event_id IS NOT NULL OR r.consumed_at IS NOT NULL
     OR r.consumed_idempotency_key IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL RC-FRESH-02 the refusal left consumption metadata on the receipt';
  END IF;
  IF EXISTS (SELECT 1 FROM public.workspace_governance_events WHERE idempotency_key='rc-fresh-1') THEN
    RAISE EXCEPTION 'FAIL RC-FRESH-02 the refusal still appended a governance event';
  END IF;
  RAISE NOTICE 'PASS RC-FRESH-02 the refused receipt stays registered, with no metadata and no event';
END $$;

-- ===================================================================================================
-- RC-FRESH-03  The mirror case. A receipt whose not_before falls AFTER the transaction started but
--              BEFORE the real moment of use must be ACCEPTED. A "fix" that merely froze the clock
--              somewhere else, or compared in the wrong direction, fails here.
-- ===================================================================================================
SELECT test_receipt('e9600000-0000-0000-0000-000000000003','f9600000-0000-0000-0000-000000000003','nonce-fresh-3',
  'b9100000-0000-0000-0000-000000000001','role_granted','membership_role','b9100000-0000-0000-0000-000000000003',
  'b9100000-0000-0000-0000-000000000003','counselor','policy-v1','rc-fresh-3','{"role_key":"counselor"}',
  clock_timestamp()+interval '3 seconds', clock_timestamp()+interval '1 hour');

SET SESSION AUTHORIZATION :"adapter_role";
DO $$
DECLARE
  v_tx_start timestamptz := now();
  v_event    uuid;
BEGIN
  PERFORM pg_sleep(4.5);   -- the receipt becomes valid during this wait
  SELECT event_id INTO v_event FROM public.consume_governance_receipt_and_apply(
    'e9600000-0000-0000-0000-000000000003','b9100000-0000-0000-0000-000000000001','role_granted',
    'membership_role','b9100000-0000-0000-0000-000000000003','b9100000-0000-0000-0000-000000000003',
    'counselor', sha256(convert_to('scope-x','UTF8')),'policy-v1','rc-fresh-3',
    '{"role_key":"counselor"}'::jsonb,'d9600000-0000-0000-0000-000000000003', now());
  IF v_event IS NULL THEN
    RAISE EXCEPTION 'FAIL RC-FRESH-03 the command returned no event';
  END IF;
  RAISE NOTICE 'PASS RC-FRESH-03 a receipt that became valid during the open transaction is accepted '
               '(tx start %, real %)', v_tx_start, clock_timestamp();
END $$;
RESET SESSION AUTHORIZATION;

DO $$
DECLARE r public.governance_proof_receipts%ROWTYPE;
BEGIN
  SELECT * INTO r FROM public.governance_proof_receipts
   WHERE receipt_id='e9600000-0000-0000-0000-000000000003';
  IF r.not_before <= (SELECT consumed_at FROM public.governance_proof_receipts
                       WHERE receipt_id='e9600000-0000-0000-0000-000000000003') IS NOT TRUE THEN
    RAISE EXCEPTION 'FAIL RC-FRESH-03 consumed_at (%) is not at or after not_before (%)',
      r.consumed_at, r.not_before;
  END IF;
  IF r.status <> 'consumed' OR r.consumed_event_id IS NULL THEN
    RAISE EXCEPTION 'FAIL RC-FRESH-03 the receipt is % with event %, expected consumed with an event',
      r.status, r.consumed_event_id;
  END IF;
  RAISE NOTICE 'PASS RC-FRESH-03b consumed_at is a post-lock clock read at or after not_before';
END $$;

-- ===================================================================================================
-- RC-FRESH-04  Static guard. The command must not reach for a transaction-start clock for its freshness
--              decision. This is what stops the defect being reintroduced by a later edit that looks
--              harmless. transaction_timestamp() and CURRENT_TIMESTAMP are the same stale value under
--              other names, so they are rejected too.
-- ===================================================================================================
DO $$
DECLARE
  v_src text;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'consume_governance_receipt_and_apply';
  IF v_src IS NULL THEN
    RAISE EXCEPTION 'FAIL RC-FRESH-04 the consume function was not found';
  END IF;
  -- Strip line comments first, so the explanatory text inside the function does not trip the check.
  v_src := regexp_replace(v_src, '--[^' || chr(10) || ']*', '', 'g');
  IF v_src ~* '\mnow\s*\(' THEN
    RAISE EXCEPTION 'FAIL RC-FRESH-04 the consume function calls now(); its freshness decision would use '
                    'the transaction start time';
  END IF;
  IF v_src ~* '\mtransaction_timestamp\s*\(' OR v_src ~* '\mcurrent_timestamp\M' THEN
    RAISE EXCEPTION 'FAIL RC-FRESH-04 the consume function uses a transaction-start clock under another name';
  END IF;
  IF v_src !~* '\mclock_timestamp\s*\(' THEN
    RAISE EXCEPTION 'FAIL RC-FRESH-04 the consume function does not read clock_timestamp() at all';
  END IF;
  RAISE NOTICE 'PASS RC-FRESH-04 the consume function reads clock_timestamp() and no transaction-start clock';
END $$;

\echo 'RECEIPT FRESHNESS TESTS COMPLETED (RC-FRESH-01..04)'
