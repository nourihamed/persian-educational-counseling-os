-- Property test: randomized credit operations under an explicit seed (synthetic data only).
-- Invariants checked after every run: balance >= 0; balance = SUM(ledger); drift = 0;
-- every rejected operation is an insufficient-credit rejection (no other error class is expected).
CREATE OR REPLACE FUNCTION property_run(p_tenant uuid, p_student uuid, p_seed double precision, p_ops int)
RETURNS text LANGUAGE plpgsql AS $$
DECLARE i int; amt int; ok int := 0; rej int := 0; bal int; led int; drift int;
BEGIN
  PERFORM setseed(p_seed);
  FOR i IN 1..p_ops LOOP
    amt := (floor(random() * 6) + 1)::int;
    BEGIN
      IF random() < 0.5 THEN
        PERFORM post_credit_transaction(p_tenant, 'purchase', amt, NULL, NULL, 'prop-' || i, NULL, NULL);
      ELSE
        PERFORM post_credit_transaction(p_tenant, 'activation_consume', -amt, p_student, NULL, 'prop-' || i, NULL, NULL);
      END IF;
      ok := ok + 1;
    EXCEPTION WHEN check_violation THEN
      IF SQLERRM NOT LIKE 'insufficient credit%' THEN RAISE; END IF;
      rej := rej + 1;
    END;
  END LOOP;
  SELECT balance INTO bal FROM public.student_credit_accounts WHERE tenant_id = p_tenant;
  SELECT COALESCE(SUM(amount),0) INTO led FROM public.credit_transactions WHERE tenant_id = p_tenant;
  drift := bal - led;
  IF bal < 0 THEN RAISE EXCEPTION 'FAIL property: negative balance % (seed %)', bal, p_seed; END IF;
  IF drift <> 0 THEN RAISE EXCEPTION 'FAIL property: drift % (seed %)', drift, p_seed; END IF;
  RETURN format('seed=%s ok=%s rejected=%s final_balance=%s drift=%s', p_seed, ok, rej, bal, drift);
END $$;
