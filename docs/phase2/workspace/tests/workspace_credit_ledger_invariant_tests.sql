-- =============================================================================
-- STUDENT CREDIT — LEDGER INVARIANTS (SYNTHETIC ONLY, D-014).
-- Run in the same database and AFTER workspace_credit_entitlement_tests.sql, which builds the wallet,
-- the memberships, the students, the entitlements and the helper cr_err() that this file reuses.
--
-- WHY THIS FILE EXISTS
--   Batch 3 of the Supervisor brief asks for verification of thirteen credit-ledger properties. Checking
--   them against the existing suite rather than assuming they were covered found that several had NO test
--   at all, including the single most important one:
--
--     "No negative or inconsistent spendable balance."
--
--   The guard that enforces it existed and worked — a probe confirmed it refuses an over-debit — but
--   nothing in the test suite ever exercised that branch. CRD-27 checked the balance IDENTITY
--   (available = ledger - reserved - recommitted), which is a different claim: an identity can hold
--   perfectly while the balance is negative. An untested guard is one refactor away from being a
--   no-op, and this one is the reason a Workspace cannot spend credit it does not have.
--
--   Checking the rest of the list the same way found two real defects, both fixed in the same batch:
--     * a compensating reversal could name a DIFFERENT student than the debit it reverses, and was
--       accepted (demonstrated: the row landed with student_matches_debit = false). The brief requires the
--       compensating transaction to be tied to the original debit, the student AND the entitlement. The
--       ledger is append-only, so a wrong attribution cannot be corrected afterwards, and whatever
--       implements OQ-CRD-2 will read it. Now CRD-42/43.
--     * the ledger guard was defined TWICE — a weak copy beside the table and a strong CREATE OR REPLACE
--       copy in workspace_activation_transactions.sql. The strong copy won in the normal load order, so
--       every credit suite was testing the right thing, but loading workspace_schema_draft.sql alone gave
--       a ledger with no wallet lock and NO balance check, and one CI step does exactly that. A
--       maintainer editing the copy next to the table would also have changed nothing. Now CRD-47.
--
-- WHAT THESE TESTS DO NOT PROVE
--   They are database-level. They do not prove any service-layer behaviour, and no service layer exists.
--   They say nothing about OQ-CRD-2 (what happens to a reserved entitlement after its period ends) or
--   OQ-CRD-3 (where the entitlement duration comes from); both remain OPEN and neither is decided here.
-- =============================================================================
\set ON_ERROR_STOP on
\if :{?workspace_key}
\else
  \echo 'pass -v workspace_key=<32 lowercase hex>'
  \quit 3
\endif
SET app.workspace_key = :'workspace_key';
SELECT 'ws_'||current_setting('app.workspace_key')||'_runtime' AS runtime_role \gset
SELECT 'ws_'||current_setting('app.workspace_key')||'_worker'  AS worker_role  \gset
SELECT 'c7600000-0000-0000-0000-000000000001'::uuid AS wallet \gset

-- Record the starting point so every assertion below can be stated against a known balance.
DO $t$
DECLARE b record;
BEGIN
  SELECT * INTO b FROM public.credit_wallet_balances
   WHERE wallet_id='c7600000-0000-0000-0000-000000000001';
  RAISE NOTICE 'ledger invariant tests start from ledger=%, reserved=%, recommitted=%, available=%',
    b.ledger_balance, b.reserved_credits, b.recommitted_credits, b.available_balance;
END $t$;

-- ===================================================================================================
-- THE CENTRAL INVARIANT: the spendable balance can never go negative.
-- ===================================================================================================
SELECT cr_err('CRD-39 a debit larger than the whole ledger balance is refused',
 $q$INSERT INTO credit_transactions(transaction_id,wallet_id,transaction_kind,amount,idempotency_key,reason)
    VALUES(gen_random_uuid(),'c7600000-0000-0000-0000-000000000001','activation_debit',-1000000,'inv-overdebit','synthetic over-debit')$q$,
 '23514','insufficient student credit');

-- A debit of exactly one more than the available balance must be refused, and a debit of exactly the
-- available balance must be ACCEPTED. Testing only the first would pass against a guard that refuses
-- everything.
DO $t$
DECLARE
  v_avail bigint;
  v_after bigint;
BEGIN
  SELECT available_balance INTO v_avail FROM public.credit_wallet_balances
   WHERE wallet_id='c7600000-0000-0000-0000-000000000001';

  BEGIN
    INSERT INTO public.credit_transactions(transaction_id,wallet_id,transaction_kind,amount,idempotency_key,reason)
    VALUES(gen_random_uuid(),'c7600000-0000-0000-0000-000000000001','activation_debit',-(v_avail+1),
           'inv-avail-plus-one','synthetic one over the available balance');
    RAISE EXCEPTION 'FAIL CRD-40 a debit of % (available + 1) was ACCEPTED; the spendable balance can go negative',
      v_avail+1;
  EXCEPTION WHEN check_violation THEN
    IF position('insufficient student credit' IN SQLERRM)=0 THEN
      RAISE EXCEPTION 'FAIL CRD-40 refused for the wrong reason: %', SQLERRM;
    END IF;
    RAISE NOTICE 'PASS CRD-40 a debit of exactly available+1 (%) is refused', v_avail+1;
  END;

  -- The control: exactly the available balance must go through, otherwise CRD-39/40 prove nothing.
  IF v_avail > 0 THEN
    INSERT INTO public.credit_transactions(transaction_id,wallet_id,transaction_kind,amount,idempotency_key,reason)
    VALUES(gen_random_uuid(),'c7600000-0000-0000-0000-000000000001','activation_debit',-v_avail,
           'inv-avail-exact','synthetic exactly the available balance');
    SELECT available_balance INTO v_after FROM public.credit_wallet_balances
     WHERE wallet_id='c7600000-0000-0000-0000-000000000001';
    IF v_after <> 0 THEN
      RAISE EXCEPTION 'FAIL CRD-41 after spending the whole available balance it is % and not 0', v_after;
    END IF;
    RAISE NOTICE 'PASS CRD-41 a debit of exactly the available balance (%) is accepted and leaves 0', v_avail;
  ELSE
    -- Make the control meaningful even when the preceding suite left nothing spendable.
    INSERT INTO public.credit_transactions(transaction_id,wallet_id,transaction_kind,amount,idempotency_key,reason)
    VALUES(gen_random_uuid(),'c7600000-0000-0000-0000-000000000001','grant',7,'inv-topup','synthetic top-up for the control');
    INSERT INTO public.credit_transactions(transaction_id,wallet_id,transaction_kind,amount,idempotency_key,reason)
    VALUES(gen_random_uuid(),'c7600000-0000-0000-0000-000000000001','activation_debit',-7,'inv-avail-exact','synthetic exactly the available balance');
    SELECT available_balance INTO v_after FROM public.credit_wallet_balances
     WHERE wallet_id='c7600000-0000-0000-0000-000000000001';
    IF v_after <> 0 THEN
      RAISE EXCEPTION 'FAIL CRD-41 after granting 7 and spending 7 the available balance is %, not 0', v_after;
    END IF;
    RAISE NOTICE 'PASS CRD-41 a debit of exactly the available balance is accepted and leaves 0 (via a 7-credit control)';
  END IF;

  -- And the balance is still not negative after all of the above.
  SELECT available_balance INTO v_after FROM public.credit_wallet_balances
   WHERE wallet_id='c7600000-0000-0000-0000-000000000001';
  IF v_after < 0 THEN
    RAISE EXCEPTION 'FAIL CRD-41 the available balance is negative (%)', v_after;
  END IF;
END $t$;

-- ===================================================================================================
-- THE COMPENSATING REVERSAL IS TIED TO THE STUDENT, NOT ONLY TO THE AMOUNT AND THE WALLET.
-- This is the defect found in Batch 3: before the fix, the insert below SUCCEEDED.
-- ===================================================================================================
DO $t$
DECLARE
  v_debit uuid;
  v_student uuid;
  v_other uuid;
  v_amount bigint;
BEGIN
  SELECT d.transaction_id, d.amount, e.student_id
    INTO v_debit, v_amount, v_student
    FROM public.student_entitlements e
    JOIN public.credit_transactions d ON d.transaction_id=e.debit_transaction_id
   WHERE e.reversal_transaction_id IS NULL
   LIMIT 1;
  IF v_debit IS NULL THEN
    RAISE EXCEPTION 'FAIL CRD-42 setup: no unreversed entitlement debit to work with';
  END IF;
  SELECT student_id INTO v_other FROM public.students WHERE student_id <> v_student LIMIT 1;
  IF v_other IS NULL THEN
    RAISE EXCEPTION 'FAIL CRD-42 setup: no second student to misattribute to';
  END IF;

  -- Same wallet, exact opposite amount, unreversed debit — everything the old guard checked — but the
  -- WRONG student. This must be refused.
  BEGIN
    INSERT INTO public.credit_transactions(transaction_id,wallet_id,transaction_kind,amount,
                                           idempotency_key,related_transaction_id,student_id,reason)
    SELECT gen_random_uuid(), d.wallet_id, 'reversal', -d.amount, 'inv-wrong-student', v_debit, v_other,
           'synthetic reversal attributed to the wrong student'
      FROM public.credit_transactions d WHERE d.transaction_id=v_debit;
    RAISE EXCEPTION 'FAIL CRD-42 a reversal naming student % was ACCEPTED against a debit for student %. '
                    'The ledger is append-only, so this misattribution could never be corrected.',
                    v_other, v_student;
  EXCEPTION WHEN check_violation THEN
    IF position('same student as the transaction it reverses' IN SQLERRM)=0 THEN
      RAISE EXCEPTION 'FAIL CRD-42 refused for the wrong reason: %', SQLERRM;
    END IF;
    RAISE NOTICE 'PASS CRD-42 a reversal naming a different student than its debit is refused';
  END;

  -- NULL is not a loophole: a debit that names a student needs a reversal that names the same student.
  BEGIN
    INSERT INTO public.credit_transactions(transaction_id,wallet_id,transaction_kind,amount,
                                           idempotency_key,related_transaction_id,student_id,reason)
    SELECT gen_random_uuid(), d.wallet_id, 'reversal', -d.amount, 'inv-null-student', v_debit, NULL,
           'synthetic reversal with no student'
      FROM public.credit_transactions d WHERE d.transaction_id=v_debit;
    RAISE EXCEPTION 'FAIL CRD-43 a reversal with a NULL student was ACCEPTED against a debit for student %',
      v_student;
  EXCEPTION WHEN check_violation THEN
    IF position('same student as the transaction it reverses' IN SQLERRM)=0 THEN
      RAISE EXCEPTION 'FAIL CRD-43 refused for the wrong reason: %', SQLERRM;
    END IF;
    RAISE NOTICE 'PASS CRD-43 a reversal with a NULL student is refused against a debit that names one';
  END;
END $t$;

-- ===================================================================================================
-- APPEND-ONLY APPLIES TO UPDATE, NOT ONLY DELETE. CRD-05 covered DELETE; UPDATE was untested.
-- ===================================================================================================
SELECT cr_err('CRD-44 an existing ledger row cannot be amended',
 $q$UPDATE credit_transactions SET amount=-1 WHERE transaction_kind='activation_debit'$q$,
 '23514','append-only');
SELECT cr_err('CRD-45 a ledger row cannot be re-pointed at another student',
 $q$UPDATE credit_transactions SET student_id=NULL WHERE transaction_kind='reversal'$q$,
 '23514','append-only');

-- ===================================================================================================
-- SHAPE AND SCOPE OF LEDGER ROWS
-- ===================================================================================================
SELECT cr_err('CRD-46 a grant with a negative amount is refused',
 $q$INSERT INTO credit_transactions(transaction_id,wallet_id,transaction_kind,amount,idempotency_key,reason)
    VALUES(gen_random_uuid(),'c7600000-0000-0000-0000-000000000001','grant',-5,'inv-neg-grant','synthetic negative grant')$q$,
 '23514');
SELECT cr_err('CRD-46b a transaction against a wallet that does not exist is refused',
 $q$INSERT INTO credit_transactions(transaction_id,wallet_id,transaction_kind,amount,idempotency_key,reason)
    VALUES(gen_random_uuid(),'c7600000-0000-0000-0000-0000000000ff','activation_debit',-1,'inv-no-wallet','synthetic unknown wallet')$q$,
 '23503','does not exist');

-- ===================================================================================================
-- AUTHORIZATION: no application role may write the ledger directly. Credit only moves through a command.
-- ===================================================================================================
SET SESSION AUTHORIZATION :"runtime_role";
SELECT cr_err('CRD-46c the Workspace runtime cannot insert a ledger row directly',
 $q$INSERT INTO credit_transactions(transaction_id,wallet_id,transaction_kind,amount,idempotency_key,reason)
    VALUES(gen_random_uuid(),'c7600000-0000-0000-0000-000000000001','grant',1,'inv-runtime-grant','synthetic')$q$,
 '42501');
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION :"worker_role";
SELECT cr_err('CRD-46d the Workspace worker cannot insert a ledger row directly',
 $q$INSERT INTO credit_transactions(transaction_id,wallet_id,transaction_kind,amount,idempotency_key,reason)
    VALUES(gen_random_uuid(),'c7600000-0000-0000-0000-000000000001','grant',1,'inv-worker-grant','synthetic')$q$,
 '42501');
RESET SESSION AUTHORIZATION;

-- ===================================================================================================
-- CRD-47  Exactly one ledger insert guard, and its body still carries the checks.
--         This is what stops the weak duplicate silently winning again. It asserts from the catalog, so
--         it does not care which file defined the guard — only that one guard exists and is the strong one.
-- ===================================================================================================
DO $t$
DECLARE
  v_triggers integer;
  v_src text;
BEGIN
  SELECT count(*) INTO v_triggers
    FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid
   WHERE c.relname='credit_transactions' AND NOT t.tgisinternal
     AND t.tgfoid = (SELECT oid FROM pg_proc WHERE proname='validate_credit_reversal' LIMIT 1);
  IF v_triggers <> 1 THEN
    RAISE EXCEPTION 'FAIL CRD-47 expected exactly one ledger insert guard trigger, found %', v_triggers;
  END IF;

  SELECT count(*) INTO v_triggers FROM pg_proc WHERE proname='validate_credit_reversal';
  IF v_triggers <> 1 THEN
    RAISE EXCEPTION 'FAIL CRD-47 expected exactly one validate_credit_reversal(), found % — a second '
                    'definition can silently replace the first at load time, which is how a weak copy '
                    'went unnoticed before', v_triggers;
  END IF;

  SELECT prosrc INTO v_src FROM pg_proc WHERE proname='validate_credit_reversal';
  IF v_src !~ 'insufficient student credit' THEN
    RAISE EXCEPTION 'FAIL CRD-47 the ledger guard no longer checks the balance; a negative spendable '
                    'balance would be possible';
  END IF;
  IF v_src !~ 'same student as the transaction it reverses' THEN
    RAISE EXCEPTION 'FAIL CRD-47 the ledger guard no longer binds a reversal to its debit''s student';
  END IF;
  IF v_src !~ 'FOR UPDATE' THEN
    RAISE EXCEPTION 'FAIL CRD-47 the ledger guard no longer takes a row lock; concurrent debits could '
                    'each read the same balance and both succeed';
  END IF;
  RAISE NOTICE 'PASS CRD-47 exactly one ledger guard exists and it still checks the balance, the student '
               'binding and the wallet lock';
END $t$;

SELECT 'STUDENT CREDIT LEDGER INVARIANT TESTS COMPLETED (CRD-39..CRD-47)' AS result;
