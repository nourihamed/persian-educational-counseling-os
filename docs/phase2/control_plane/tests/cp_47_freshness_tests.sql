-- =============================================================================
-- CONTROL PLANE — FRESHNESS OF THE CONTACT-CHANGE PROOF WINDOW (SYNTHETIC ONLY, D-014).
-- Run in the same database and AFTER cp_40_contact_change_tests.sql, which creates the Workspaces, the
-- key versions, the students and the helpers cc_proof / cc_call / cc_aliases / cc_err reused here.
--
-- WHY THIS FILE EXISTS
--   `change_student_mobile_contact()` validated its one-time proof with now(), which in PostgreSQL is the
--   TRANSACTION START time and does not advance. A caller could therefore open a transaction while the
--   proof was still valid, hold it open past `expires_at`, and still consume it. This proof is what
--   authorizes changing a student's GLOBAL contact identity, and its expiry window is the entire point of
--   it being one-time, so a stale clock removed the only time bound on it.
--
--   The same defect was found in the governance proof-receipt command on the same day (RC-FRESH-01..04)
--   and in `guardian_permissions_effective` (CLK-01..03). All three now read clock_timestamp() AFTER the
--   relevant row lock, which is the pattern the H-01 remediation established for the credit reversal
--   window.
--
-- WHAT THESE TESTS DO AND DO NOT PROVE
--   They prove the proof window is evaluated at the real moment of use, not at transaction start, and that
--   a refusal leaves the proof, the command reservation, the contact rows and the audit untouched. They do
--   NOT prove any signature: `verifier_outcome='verified'` is a recorded test input. They assert no
--   clock-skew tolerance, because PS-5 is deferred and none is implemented.
-- =============================================================================
\set ON_ERROR_STOP on

-- ===================================================================================================
-- CC-FRESH-01/02  A proof that expires WHILE the consuming transaction is open must be refused, and the
--                 refusal must leave the proof usable and nothing else written.
-- ===================================================================================================
-- A proof valid now, expiring in 2 seconds. Timestamps come from clock_timestamp() so the window is
-- anchored to real time and not to this script's transaction.
SELECT cc_proof('d8000000-0000-0000-0000-000000000047','b8000000-0000-0000-0000-000000000001',
                'a8000000-0000-0000-0000-000000000001',1,'47',
                clock_timestamp()-interval '1 second', clock_timestamp()+interval '2 seconds');

SET SESSION AUTHORIZATION cp_contact_change_executor;
DO $t$
DECLARE
  v_tx_start timestamptz := now();
BEGIN
  PERFORM pg_sleep(3.5);   -- the proof expires during this wait; now() does not move
  BEGIN
    PERFORM cc_call('k-fresh-47','h47','b8000000-0000-0000-0000-000000000001',
                    'a8000000-0000-0000-0000-000000000001',1,'d8000000-0000-0000-0000-000000000047','47');
    RAISE EXCEPTION 'FAIL CC-FRESH-01 a contact-change proof that expired during the transaction was '
                    'CONSUMED. The proof window is being evaluated against the transaction start time '
                    '(%), not the real moment of use (%).', v_tx_start, clock_timestamp();
  EXCEPTION WHEN check_violation THEN
    IF position('not valid at this time' IN SQLERRM) = 0 THEN
      RAISE EXCEPTION 'FAIL CC-FRESH-01 refused for the wrong reason: %', SQLERRM;
    END IF;
    RAISE NOTICE 'PASS CC-FRESH-01 a contact-change proof that expired during the open transaction is '
                 'refused (tx start %, real %)', v_tx_start, clock_timestamp();
  END;
END $t$;
RESET SESSION AUTHORIZATION;

DO $t$
DECLARE p public.contact_change_proofs%ROWTYPE;
BEGIN
  SELECT * INTO p FROM public.contact_change_proofs
   WHERE proof_id='d8000000-0000-0000-0000-000000000047';
  -- The test only means something if the proof really did expire between transaction start and use.
  IF p.expires_at >= clock_timestamp() THEN
    RAISE EXCEPTION 'FAIL CC-FRESH-01 setup: the proof had not expired by the end of the test '
                    '(expires %, now %)', p.expires_at, clock_timestamp();
  END IF;
  IF p.status <> 'registered' OR p.consumed_at IS NOT NULL OR p.consumed_by_command IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL CC-FRESH-02 the refusal consumed or marked the proof (status %, consumed_at %)',
      p.status, p.consumed_at;
  END IF;
  IF EXISTS (SELECT 1 FROM public.contact_change_commands WHERE idempotency_key='k-fresh-47') THEN
    RAISE EXCEPTION 'FAIL CC-FRESH-02 the refusal left a command reservation behind';
  END IF;
  IF EXISTS (SELECT 1 FROM public.student_contact_change_audit a
             WHERE a.idempotency_key='k-fresh-47'
                OR a.proof_id='d8000000-0000-0000-0000-000000000047') THEN
    RAISE EXCEPTION 'FAIL CC-FRESH-02 the refusal left an audit row behind';
  END IF;
  RAISE NOTICE 'PASS CC-FRESH-02 the refused proof stays registered with no command and no audit row';
END $t$;

-- ===================================================================================================
-- CC-FRESH-03  Static guard. The command must not reach for a transaction-start clock. This is what
--              stops the defect being reintroduced by a later edit that looks harmless.
-- ===================================================================================================
DO $t$
DECLARE v_src text;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='change_student_mobile_contact' LIMIT 1;
  IF v_src IS NULL THEN
    RAISE EXCEPTION 'FAIL CC-FRESH-03 change_student_mobile_contact() was not found';
  END IF;
  -- Strip line comments first so the explanatory text inside the function does not trip the check.
  v_src := regexp_replace(v_src, '--[^' || chr(10) || ']*', '', 'g');
  IF v_src ~* '\mnow\s*\(' OR v_src ~* '\mtransaction_timestamp\s*\('
     OR v_src ~* '\mcurrent_timestamp\M' THEN
    RAISE EXCEPTION 'FAIL CC-FRESH-03 change_student_mobile_contact() reads a transaction-start clock; '
                    'its proof window could be defeated by holding a transaction open';
  END IF;
  IF v_src !~* '\mclock_timestamp\s*\(' THEN
    RAISE EXCEPTION 'FAIL CC-FRESH-03 change_student_mobile_contact() does not read clock_timestamp() at all';
  END IF;
  RAISE NOTICE 'PASS CC-FRESH-03 the contact-change command reads clock_timestamp() and no '
               'transaction-start clock';
END $t$;

\echo 'CONTROL PLANE FRESHNESS TESTS COMPLETED (CC-FRESH-01..03)'
