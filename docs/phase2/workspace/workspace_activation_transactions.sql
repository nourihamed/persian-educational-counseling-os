-- WORKSPACE DB — DRAFT: atomic student activation + credit debit + capacity reservation.
-- Apply after workspace_schema_draft.sql. Synthetic fixtures only (D-014).
-- The caller must first validate current Control Plane owner/generation and actor permission.
-- This function enforces the local generation projection, ledger balance and capacity atomically.
BEGIN;

-- Serialize every ledger insert on its wallet row and prevent a negative balance.
-- The same guard validates exact, same-wallet, single-use reversal entries.
DROP TRIGGER IF EXISTS credit_reversal_guard ON public.credit_transactions;

CREATE OR REPLACE FUNCTION validate_credit_reversal() RETURNS trigger
LANGUAGE plpgsql AS $body$
DECLARE
  v_wallet uuid;
  v_amount bigint;
  v_kind text;
  v_balance bigint;
  v_held bigint;
BEGIN
  PERFORM 1 FROM public.credit_wallets
   WHERE wallet_id=NEW.wallet_id
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'credit wallet % does not exist',NEW.wallet_id
      USING ERRCODE='foreign_key_violation';
  END IF;

  IF NEW.transaction_kind='reversal' THEN
    SELECT wallet_id,amount,transaction_kind
      INTO v_wallet,v_amount,v_kind
      FROM public.credit_transactions
     WHERE transaction_id=NEW.related_transaction_id
     FOR UPDATE;
    IF NOT FOUND OR v_wallet<>NEW.wallet_id OR v_kind='reversal' OR NEW.amount<>-v_amount THEN
      RAISE EXCEPTION 'reversal must reference one original transaction in the same wallet with exact opposite amount'
        USING ERRCODE='check_violation';
    END IF;
    IF EXISTS (
      SELECT 1 FROM public.credit_transactions
       WHERE transaction_kind='reversal'
         AND related_transaction_id=NEW.related_transaction_id
    ) THEN
      RAISE EXCEPTION 'original credit transaction has already been reversed'
        USING ERRCODE='unique_violation';
    END IF;
  END IF;

  SELECT COALESCE(sum(amount),0) INTO v_balance
    FROM public.credit_transactions
   WHERE wallet_id=NEW.wallet_id;

  -- PD-2026-11-13-D: a credit returned by a compensating reversal is bound to the student it was spent on.
  -- It stays out of the spendable balance in BOTH entitlement states, so it can never fund another
  -- student's activation, and it never exists as wallet balance and reserved entitlement at the same time.
  SELECT COALESCE(sum(e.credit_amount),0) INTO v_held
    FROM public.student_entitlements e
    JOIN public.credit_transactions d ON d.transaction_id=e.debit_transaction_id
   WHERE d.wallet_id=NEW.wallet_id
     AND e.reversal_transaction_id IS NOT NULL;

  IF v_balance - v_held + NEW.amount < 0 THEN
    RAISE EXCEPTION 'insufficient student credit: balance %, reserved for named students %, requested debit %',
      v_balance,v_held,-NEW.amount USING ERRCODE='check_violation';
  END IF;
  RETURN NEW;
END; $body$;

-- Spendable balance = ledger balance minus every credit that a compensating reversal has bound to a student.
CREATE OR REPLACE VIEW credit_wallet_balances AS
SELECT w.wallet_id,
       COALESCE((SELECT sum(t.amount) FROM public.credit_transactions t WHERE t.wallet_id=w.wallet_id),0)::bigint
         AS ledger_balance,
       COALESCE((SELECT sum(e.credit_amount) FROM public.student_entitlements e
                   JOIN public.credit_transactions d ON d.transaction_id=e.debit_transaction_id
                  WHERE d.wallet_id=w.wallet_id AND e.reversal_transaction_id IS NOT NULL AND e.state='reserved'),0)::bigint
         AS reserved_credits,
       COALESCE((SELECT sum(e.credit_amount) FROM public.student_entitlements e
                   JOIN public.credit_transactions d ON d.transaction_id=e.debit_transaction_id
                  WHERE d.wallet_id=w.wallet_id AND e.reversal_transaction_id IS NOT NULL AND e.state='consumed'),0)::bigint
         AS recommitted_credits,
       (COALESCE((SELECT sum(t.amount) FROM public.credit_transactions t WHERE t.wallet_id=w.wallet_id),0)
        - COALESCE((SELECT sum(e.credit_amount) FROM public.student_entitlements e
                      JOIN public.credit_transactions d ON d.transaction_id=e.debit_transaction_id
                     WHERE d.wallet_id=w.wallet_id AND e.reversal_transaction_id IS NOT NULL),0))::bigint
         AS available_balance
  FROM public.credit_wallets w;

CREATE TRIGGER credit_transaction_insert_guard
  BEFORE INSERT ON public.credit_transactions
  FOR EACH ROW EXECUTE FUNCTION validate_credit_reversal();

-- New local enrollments must start inactive. Only the controlled activation function may activate them.
CREATE FUNCTION enforce_enrollment_initial_state() RETURNS trigger
LANGUAGE plpgsql AS $body$
BEGIN
  IF NEW.state NOT IN ('requested','awaiting_consent') OR NEW.started_at IS NOT NULL THEN
    RAISE EXCEPTION 'new enrollment must start requested/awaiting_consent without started_at'
      USING ERRCODE='check_violation';
  END IF;
  RETURN NEW;
END; $body$;
CREATE TRIGGER enrollments_initial_state_guard
  BEFORE INSERT ON public.enrollments
  FOR EACH ROW EXECUTE FUNCTION enforce_enrollment_initial_state();

CREATE TABLE activation_command_log (
  idempotency_key text PRIMARY KEY CHECK (length(idempotency_key)>0),
  enrollment_id uuid NOT NULL REFERENCES enrollments(enrollment_id),
  wallet_id uuid NOT NULL REFERENCES credit_wallets(wallet_id),
  expected_generation bigint NOT NULL CHECK (expected_generation>=1),
  debit_amount bigint NOT NULL CHECK (debit_amount>0),
  actor_membership_id uuid NOT NULL REFERENCES workspace_memberships(membership_id),
  entitlement_period_end timestamptz NOT NULL,
  recorded_at timestamptz NOT NULL DEFAULT now()
);

CREATE FUNCTION reject_activation_command_mutation() RETURNS trigger
LANGUAGE plpgsql AS $body$
BEGIN
  RAISE EXCEPTION 'activation command log is append-only' USING ERRCODE='check_violation';
END; $body$;
CREATE TRIGGER activation_command_log_append_only
  BEFORE UPDATE OR DELETE ON activation_command_log
  FOR EACH ROW EXECUTE FUNCTION reject_activation_command_mutation();

-- H-02 — ENTITLEMENT PERIOD SOURCE IS NOT APPROVED (OQ-CRD-3).
-- This command accepts the entitlement period end from its caller. A Runtime identity that could call it
-- would be able to extend a student's original entitlement by supplying an arbitrary timestamp, so it is
-- NOT an operational path: it exists for synthetic fixtures only (D-014) and is granted exclusively to
-- ws_<key>_synth_exec. The production-intended entry point is
-- activate_student_enrollment(), below, which fails closed until the Product Owner approves a source.
CREATE FUNCTION activate_student_enrollment_synthetic(
  p_idempotency_key text,
  p_enrollment_id uuid,
  p_wallet_id uuid,
  p_expected_generation bigint,
  p_debit_amount bigint,
  p_actor_membership_id uuid,
  p_entitlement_period_end timestamptz
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=pg_catalog,pg_temp
AS $$
DECLARE
  v_inserted integer;
  v_existing public.activation_command_log%ROWTYPE;
  v_student_id uuid;
  v_enrollment_state text;
  v_student_state text;
  v_generation bigint;
  v_responsible_count integer;
  v_credit_key text;
  v_debit_id uuid;
  v_now timestamptz;
BEGIN
  IF p_idempotency_key IS NULL OR length(p_idempotency_key)=0
     OR p_enrollment_id IS NULL OR p_wallet_id IS NULL
     OR p_expected_generation IS NULL OR p_expected_generation<1
     OR p_debit_amount IS NULL OR p_debit_amount<=0
     OR p_actor_membership_id IS NULL THEN
    RAISE EXCEPTION 'activation command arguments are invalid'
      USING ERRCODE='invalid_parameter_value';
  END IF;
  IF p_entitlement_period_end IS NULL THEN
    RAISE EXCEPTION 'activation requires an entitlement period end'
      USING ERRCODE='invalid_parameter_value';
  END IF;
  v_credit_key := 'activation:' || p_idempotency_key;

  INSERT INTO public.activation_command_log(
    idempotency_key,enrollment_id,wallet_id,expected_generation,debit_amount,actor_membership_id,entitlement_period_end
  ) VALUES (
    p_idempotency_key,p_enrollment_id,p_wallet_id,p_expected_generation,p_debit_amount,p_actor_membership_id,p_entitlement_period_end
  )
  ON CONFLICT(idempotency_key) DO NOTHING;
  GET DIAGNOSTICS v_inserted=ROW_COUNT;

  IF v_inserted=0 THEN
    SELECT * INTO v_existing
      FROM public.activation_command_log
     WHERE idempotency_key=p_idempotency_key
     FOR UPDATE;
    IF v_existing.enrollment_id<>p_enrollment_id
       OR v_existing.wallet_id<>p_wallet_id
       OR v_existing.expected_generation<>p_expected_generation
       OR v_existing.debit_amount<>p_debit_amount
       OR v_existing.actor_membership_id<>p_actor_membership_id
       OR v_existing.entitlement_period_end<>p_entitlement_period_end THEN
      RAISE EXCEPTION 'activation idempotency key reused with different intent'
        USING ERRCODE='unique_violation';
    END IF;
    SELECT student_id INTO v_student_id
      FROM public.enrollments WHERE enrollment_id=p_enrollment_id;
    IF NOT FOUND
       OR NOT EXISTS (
         SELECT 1 FROM public.credit_transactions
          WHERE idempotency_key=v_credit_key
            AND wallet_id=p_wallet_id
            AND student_id=v_student_id
            AND transaction_kind='activation_debit'
            AND amount=-p_debit_amount
       )
       OR NOT EXISTS (
         SELECT 1 FROM public.capacity_events
          WHERE idempotency_key=v_credit_key
            AND dimension_key='active_students'
            AND delta=1
            AND student_id=v_student_id
            AND actor_membership_id=p_actor_membership_id
       ) THEN
      RAISE EXCEPTION 'activation command log is inconsistent with ledger/capacity evidence'
        USING ERRCODE='integrity_constraint_violation';
    END IF;
    RETURN p_enrollment_id;
  END IF;

  SELECT e.student_id,e.state,e.ownership_generation,s.lifecycle_state
    INTO v_student_id,v_enrollment_state,v_generation,v_student_state
    FROM public.enrollments e
    JOIN public.students s ON s.student_id=e.student_id
   WHERE e.enrollment_id=p_enrollment_id
   FOR UPDATE OF e,s;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'enrollment % not found',p_enrollment_id
      USING ERRCODE='foreign_key_violation';
  END IF;
  IF v_generation<>p_expected_generation THEN
    RAISE EXCEPTION 'stale local ownership generation: current %, expected %',v_generation,p_expected_generation
      USING ERRCODE='check_violation';
  END IF;
  IF v_enrollment_state NOT IN ('requested','awaiting_consent') THEN
    RAISE EXCEPTION 'enrollment state % cannot be activated',v_enrollment_state
      USING ERRCODE='check_violation';
  END IF;
  IF v_student_state<>'active' THEN
    RAISE EXCEPTION 'archived student cannot be activated; create/reactivate through the approved lifecycle'
      USING ERRCODE='check_violation';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.workspace_memberships
     WHERE membership_id=p_actor_membership_id AND status='active'
  ) THEN
    RAISE EXCEPTION 'activation actor is not an active Workspace member'
      USING ERRCODE='insufficient_privilege';
  END IF;

  -- H-04: the authoritative activation timestamp is read ONCE, after every required row lock is held, and
  -- the entitlement period is validated against THAT timestamp. The same value is then used for the
  -- enrollment start, the entitlement row and the audit record, so the three cannot disagree.
  v_now := clock_timestamp();
  IF p_entitlement_period_end <= v_now THEN
    RAISE EXCEPTION 'the entitlement period ended at % before this activation committed at %',
      p_entitlement_period_end, v_now USING ERRCODE='check_violation';
  END IF;

  SELECT count(*) INTO v_responsible_count
    FROM public.counselor_assignments
   WHERE enrollment_id=p_enrollment_id
     AND state='active'
     AND is_responsible
     AND accepted_at IS NOT NULL;
  IF v_responsible_count<>1 THEN
    RAISE EXCEPTION 'activation requires exactly one accepted responsible counselor; found %',v_responsible_count
      USING ERRCODE='check_violation';
  END IF;

  -- All three mutations occur in this transaction. Any credit/capacity/state failure rolls back all.
  INSERT INTO public.credit_transactions(
    transaction_id,wallet_id,transaction_kind,amount,idempotency_key,
    student_id,actor_membership_id,reason
  ) VALUES (
    gen_random_uuid(),p_wallet_id,'activation_debit',-p_debit_amount,v_credit_key,
    v_student_id,p_actor_membership_id,'student activation'
  ) RETURNING transaction_id INTO v_debit_id;

  -- PD-2026-11-13-D: the entitlement period is declared by the caller at activation and is then immutable.
  -- The database neither chooses nor derives a duration; it only refuses to restart or extend one.
  INSERT INTO public.student_entitlements(
    entitlement_id,student_id,debit_transaction_id,credit_amount,activated_at,period_end,state
  ) VALUES (
    gen_random_uuid(),v_student_id,v_debit_id,p_debit_amount,v_now,p_entitlement_period_end,'consumed'
  );

  PERFORM public.adjust_workspace_capacity(
    'active_students',1,v_credit_key,v_student_id,p_actor_membership_id,'student activation'
  );

  UPDATE public.enrollments
     SET state='active',started_at=COALESCE(started_at,v_now)
   WHERE enrollment_id=p_enrollment_id
     AND ownership_generation=p_expected_generation
     AND state IN ('requested','awaiting_consent');
  GET DIAGNOSTICS v_inserted=ROW_COUNT;
  IF v_inserted<>1 THEN
    RAISE EXCEPTION 'activation state update affected %, expected exactly one row',v_inserted
      USING ERRCODE='check_violation';
  END IF;

  -- The audit record is part of the same transaction; no sensitive student data is copied.
  INSERT INTO public.audit_events(
    audit_event_id,actor_membership_id,event_type,target_type,target_id,outcome,correlation_id,metadata
  ) VALUES (
    gen_random_uuid(),p_actor_membership_id,'student.activation','enrollment',p_enrollment_id,
    'success',p_idempotency_key,
    jsonb_build_object(
      'wallet_id',p_wallet_id,
      'credit_unit','CRD',
      'debit_amount',p_debit_amount,
      'ownership_generation',p_expected_generation,
      'activated_at',v_now,
      'entitlement_period_end',p_entitlement_period_end
    )
  );

  RETURN p_enrollment_id;
END;
$$;

REVOKE ALL ON FUNCTION activate_student_enrollment_synthetic(text,uuid,uuid,bigint,bigint,uuid,timestamptz) FROM PUBLIC;

-- ======================================================================================================
-- H-02 — production-intended activation, FAIL CLOSED.
-- Where does a student's entitlement period come from? That is OQ-CRD-3 and it is unresolved. No source is
-- invented here: the resolver refuses, so the production-intended path cannot establish entitlement
-- validity and therefore cannot activate. When the Product Owner approves a source, the resolver is
-- replaced by a lookup against that authoritative, versioned record and the resolved value is SNAPSHOTTED
-- into student_entitlements.period_end, which is already immutable and can never be restarted or extended.
--
-- Recommendation only, not an approved decision: derive the period from the purchased Plan/Product version
-- that funded the activation, and store both the resolved period end and the plan version that produced it.
-- ======================================================================================================
CREATE FUNCTION resolve_student_entitlement_period(p_student_id uuid, p_debit_amount bigint, p_now timestamptz)
RETURNS timestamptz
LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'no approved entitlement period source exists (OQ-CRD-3); activation cannot establish entitlement validity'
    USING ERRCODE='feature_not_supported';
END; $$;

CREATE FUNCTION activate_student_enrollment(
  p_idempotency_key text,
  p_enrollment_id uuid,
  p_wallet_id uuid,
  p_expected_generation bigint,
  p_debit_amount bigint,
  p_actor_membership_id uuid
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=pg_catalog,pg_temp
AS $$
DECLARE v_student_id uuid; v_period_end timestamptz; v_now timestamptz;
BEGIN
  -- The locks that the activation itself needs are taken by the inner command. This entry point only
  -- resolves the entitlement period from an authoritative source, and there is none yet, so it stops here.
  SELECT student_id INTO v_student_id FROM public.enrollments WHERE enrollment_id=p_enrollment_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'enrollment % not found', p_enrollment_id USING ERRCODE='foreign_key_violation';
  END IF;
  v_now := clock_timestamp();
  v_period_end := public.resolve_student_entitlement_period(v_student_id, p_debit_amount, v_now);
  RETURN public.activate_student_enrollment_synthetic(
    p_idempotency_key, p_enrollment_id, p_wallet_id, p_expected_generation, p_debit_amount,
    p_actor_membership_id, v_period_end);
END; $$;
REVOKE ALL ON FUNCTION activate_student_enrollment(text,uuid,uuid,bigint,bigint,uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION resolve_student_entitlement_period(uuid,bigint,timestamptz) FROM PUBLIC;
REVOKE ALL ON FUNCTION adjust_workspace_capacity(text,integer,text,uuid,uuid,text) FROM PUBLIC;

COMMIT;
