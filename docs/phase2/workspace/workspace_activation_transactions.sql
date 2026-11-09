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
  IF v_balance + NEW.amount < 0 THEN
    RAISE EXCEPTION 'insufficient student credit: balance %, requested debit %',v_balance,-NEW.amount
      USING ERRCODE='check_violation';
  END IF;
  RETURN NEW;
END; $body$;

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
DECLARE
  v_inserted integer;
  v_existing public.activation_command_log%ROWTYPE;
  v_student_id uuid;
  v_enrollment_state text;
  v_student_state text;
  v_generation bigint;
  v_responsible_count integer;
  v_credit_key text;
BEGIN
  IF p_idempotency_key IS NULL OR length(p_idempotency_key)=0
     OR p_enrollment_id IS NULL OR p_wallet_id IS NULL
     OR p_expected_generation IS NULL OR p_expected_generation<1
     OR p_debit_amount IS NULL OR p_debit_amount<=0
     OR p_actor_membership_id IS NULL THEN
    RAISE EXCEPTION 'activation command arguments are invalid'
      USING ERRCODE='invalid_parameter_value';
  END IF;
  v_credit_key := 'activation:' || p_idempotency_key;

  INSERT INTO public.activation_command_log(
    idempotency_key,enrollment_id,wallet_id,expected_generation,debit_amount,actor_membership_id
  ) VALUES (
    p_idempotency_key,p_enrollment_id,p_wallet_id,p_expected_generation,p_debit_amount,p_actor_membership_id
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
       OR v_existing.actor_membership_id<>p_actor_membership_id THEN
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
  );

  PERFORM public.adjust_workspace_capacity(
    'active_students',1,v_credit_key,v_student_id,p_actor_membership_id,'student activation'
  );

  UPDATE public.enrollments
     SET state='active',started_at=COALESCE(started_at,now())
   WHERE enrollment_id=p_enrollment_id
     AND ownership_generation=p_expected_generation
     AND state IN ('requested','awaiting_consent');
  GET DIAGNOSTICS v_inserted=ROW_COUNT;
  IF v_inserted<>1 THEN
    RAISE EXCEPTION 'activation state update affected %, expected exactly one row',v_inserted
      USING ERRCODE='check_violation';
  END IF;

  RETURN p_enrollment_id;
END;
$$;

REVOKE ALL ON FUNCTION activate_student_enrollment(text,uuid,uuid,bigint,bigint,uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION adjust_workspace_capacity(text,integer,text,uuid,uuid,text) FROM PUBLIC;

COMMIT;
