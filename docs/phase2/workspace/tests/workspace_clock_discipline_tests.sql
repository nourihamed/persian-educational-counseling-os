-- =============================================================================
-- CLOCK DISCIPLINE — a catalog-driven guard against stale time reads (SYNTHETIC ONLY, D-014).
-- Run after every Workspace draft and, where available, the receipt drafts, so the scan sees them.
--
-- WHY THIS FILE EXISTS
--   The same defect was found three times in this project, in three unrelated places:
--     * the credit reversal window (H-01, fixed earlier),
--     * the governance proof-receipt validity window (`now()` let an expired receipt be consumed;
--       demonstrated, then fixed 2026-11-14),
--     * the contact-change one-time proof window (same shape, same file family, fixed 2026-11-14),
--     * and `guardian_permissions_effective`, which is the authorization read shape for guardian access.
--   In PostgreSQL `now()`, `transaction_timestamp()` and `CURRENT_TIMESTAMP` all return the TRANSACTION
--   START time and do not advance. Any authorization, expiry or freshness decision made with them can be
--   defeated by holding a transaction open. `clock_timestamp()` advances.
--
--   Fixing the four sites does not stop a fifth appearing. This test is the thing that does: it scans the
--   catalog, not a list of files, so a NEW SECURITY DEFINER function or view that reads a transaction-start
--   clock fails the suite by name, and the author must either fix it or add it to the reviewed allowlist
--   below with a reason.
--
-- WHAT IS ALLOWED, AND WHY
--   Writing a stored timestamp (`granted_at=now()`, `recorded_at DEFAULT now()`) is not a decision: all
--   rows written by one transaction getting one consistent timestamp is reasonable. Only sites that
--   DECIDE something from the clock are defects. That distinction cannot be made by regex, so each
--   remaining site is named in the allowlist with the reason it was accepted.
--
-- WHAT THIS DOES NOT PROVE
--   It is a static scan. It does not prove the windows are correct, only that they do not read a
--   transaction-start clock. The behavioural proof is RC-FRESH-01..04, CC-FRESH-01..02 and
--   GPE-FRESH-01..03, each of which was shown to FAIL against the pre-fix code.
-- =============================================================================
\set ON_ERROR_STOP on

DO $$
DECLARE
  r record;
  v_bad text[] := ARRAY[]::text[];
  -- Reviewed and accepted: these read a transaction-start clock only to WRITE a stored timestamp.
  -- Adding a name here is a review decision, not a formality. State the reason in the comment.
  v_allowed text[] := ARRAY[
    'function:append_workspace_governance_event'  -- granted_at=now() on the role/permission projection:
                                                  -- a recorded value, not a decision. The authority
                                                  -- decision is made by the caller's receipt check.
  ];
BEGIN
  FOR r IN
    WITH src AS (
      -- SECURITY DEFINER functions: these run with the definer's privileges, so a decision they make from
      -- a stale clock is a decision the caller could not otherwise have obtained.
      SELECT p.proname AS name, 'function' AS kind,
             regexp_replace(pg_get_functiondef(p.oid), '--[^' || chr(10) || ']*', '', 'g') AS body
        FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
       WHERE n.nspname = 'public' AND p.prosecdef
      UNION ALL
      -- Views: a view is a read shape, and several of this project's read shapes ARE the decision.
      SELECT c.relname, 'view',
             regexp_replace(pg_get_viewdef(c.oid), '--[^' || chr(10) || ']*', '', 'g')
        FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
       WHERE n.nspname = 'public' AND c.relkind = 'v'
    )
    SELECT kind, name FROM src
     WHERE body ~* '\mnow\s*\('
        OR body ~* '\mtransaction_timestamp\s*\('
        OR body ~* '\mcurrent_timestamp\M'
     ORDER BY kind, name
  LOOP
    IF NOT ((r.kind || ':' || r.name) = ANY (v_allowed)) THEN
      v_bad := v_bad || (r.kind || ' ' || r.name);
    END IF;
  END LOOP;

  IF array_length(v_bad, 1) IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL CLK-01 these read a transaction-start clock (now() / transaction_timestamp() / '
                    'CURRENT_TIMESTAMP): %. A transaction-start clock does not advance, so any expiry, '
                    'freshness or authorization decision made from it can be defeated by holding a '
                    'transaction open. Use clock_timestamp(), read after any row lock. If the site only '
                    'WRITES a stored timestamp and decides nothing, add it to v_allowed in this test with '
                    'the reason.', array_to_string(v_bad, ', ');
  END IF;
  RAISE NOTICE 'PASS CLK-01 no SECURITY DEFINER function or view decides from a transaction-start clock '
               '(% reviewed exception(s))', coalesce(array_length(v_allowed,1),0);
END $$;

-- ---------------------------------------------------------------------------------------------------
-- CLK-02  The specific windows that were defective must read clock_timestamp(). This is narrower than
--         CLK-01 and survives an over-broad edit to the allowlist above.
-- ---------------------------------------------------------------------------------------------------
DO $$
DECLARE
  r record;
  v_src text;
  v_missing text[] := ARRAY[]::text[];
BEGIN
  FOR r IN
    SELECT * FROM (VALUES
      ('function','archive_student_enrollment','the credit reversal window (H-01)'),
      ('view','guardian_permissions_effective','the guardian authorization read shape'),
      ('view','expired_reserved_entitlements','the reserved-entitlement report (OQ-CRD-2 will read it)')
    ) AS t(kind, name, why)
  LOOP
    IF r.kind = 'function' THEN
      SELECT pg_get_functiondef(p.oid) INTO v_src FROM pg_proc p
        JOIN pg_namespace n ON n.oid=p.pronamespace
       WHERE n.nspname='public' AND p.proname=r.name LIMIT 1;
    ELSE
      SELECT pg_get_viewdef(c.oid) INTO v_src FROM pg_class c
        JOIN pg_namespace n ON n.oid=c.relnamespace
       WHERE n.nspname='public' AND c.relname=r.name AND c.relkind='v' LIMIT 1;
    END IF;
    IF v_src IS NULL THEN
      RAISE EXCEPTION 'FAIL CLK-02 % % does not exist; this test is out of date with the schema',
        r.kind, r.name;
    END IF;
    IF v_src !~* '\mclock_timestamp\s*\(' THEN
      v_missing := v_missing || (r.kind || ' ' || r.name || ' (' || r.why || ')');
    END IF;
  END LOOP;

  IF array_length(v_missing, 1) IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL CLK-02 these no longer read clock_timestamp(): %', array_to_string(v_missing, ', ');
  END IF;
  RAISE NOTICE 'PASS CLK-02 every previously defective time window reads clock_timestamp()';
END $$;

-- ---------------------------------------------------------------------------------------------------
-- CLK-03  Behavioural: guardian_permissions_effective must drop a permission that expires WHILE the
--         reading transaction is open. A static check alone would not catch a view rewritten to compare
--         against a column holding a transaction-start value.
-- ---------------------------------------------------------------------------------------------------
DO $$
DECLARE
  v_link uuid := 'a9a00000-0000-0000-0000-000000000001';
  v_perm uuid := 'a9a00000-0000-0000-0000-000000000002';
  v_student uuid := 'a9a00000-0000-0000-0000-000000000003';
  v_tx_start timestamptz := now();
  v_seen_before boolean;
  v_seen_after boolean;
  v_until timestamptz;
BEGIN
  INSERT INTO public.students(student_id, platform_student_id, display_name, grade_key, lifecycle_state)
  VALUES (v_student, gen_random_uuid(), 'Clock Discipline Subject', 'grade_10', 'active');

  -- The guardian tables are projections: WS-DOM-03 requires an accompanying append-only event in the SAME
  -- transaction, enforced by deferred constraint triggers. The fixture satisfies that rather than
  -- bypassing it, so this test exercises the real write path.
  INSERT INTO public.student_guardian_links(link_id, student_id, guardian_platform_user_id,
                                            relationship_type, verification_state, legal_authority_ref,
                                            verified_at)
  VALUES (v_link, v_student, gen_random_uuid(), 'parent', 'verified', 'synthetic-authority-clk',
          clock_timestamp());
  INSERT INTO public.guardian_link_events(event_id, link_id, event_type, actor_ref, authn_event_ref,
                                          policy_version, effective_at)
  VALUES (gen_random_uuid(), v_link, 'link_created', 'actor-clk', 'authn-clk', 'policy-clk',
          clock_timestamp());
  INSERT INTO public.guardian_link_events(event_id, link_id, event_type, actor_ref, authn_event_ref,
                                          evidence_ref, policy_version, effective_at)
  VALUES (gen_random_uuid(), v_link, 'verified', 'actor-clk', 'authn-clk', 'evidence-clk', 'policy-clk',
          clock_timestamp());

  v_until := clock_timestamp() + interval '2 seconds';
  INSERT INTO public.guardian_permissions(permission_id, guardian_link_id, scope_key, authority_ref,
                                          valid_from, valid_until)
  VALUES (v_perm, v_link, 'progress_summary', 'synthetic-authority-clk',
          clock_timestamp() - interval '1 second', v_until);
  INSERT INTO public.guardian_permission_events(event_id, permission_id, event_type, actor_ref,
                                                authn_event_ref, authority_ref, policy_version,
                                                effective_from, effective_until)
  VALUES (gen_random_uuid(), v_perm, 'granted', 'actor-clk', 'authn-clk', 'synthetic-authority-clk',
          'policy-clk', clock_timestamp() - interval '1 second', v_until);

  SELECT EXISTS (SELECT 1 FROM public.guardian_permissions_effective WHERE permission_id = v_perm)
    INTO v_seen_before;
  IF NOT v_seen_before THEN
    RAISE EXCEPTION 'FAIL CLK-03 setup: the permission was not effective even before expiry';
  END IF;

  PERFORM pg_sleep(3.5);   -- it expires during this wait; now() does not move, clock_timestamp() does

  SELECT EXISTS (SELECT 1 FROM public.guardian_permissions_effective WHERE permission_id = v_perm)
    INTO v_seen_after;
  IF v_seen_after THEN
    RAISE EXCEPTION 'FAIL CLK-03 a guardian permission that expired at % is STILL effective inside a '
                    'transaction that started at % (real time now %). The authorization read shape is '
                    'using a transaction-start clock.', v_until, v_tx_start, clock_timestamp();
  END IF;
  RAISE NOTICE 'PASS CLK-03 a guardian permission that expires mid-transaction stops being effective '
               '(tx start %, expired %, real %)', v_tx_start, v_until, clock_timestamp();

  -- The fixture is NOT cleaned up, and that is correct rather than lazy: `guardian_permission_events` and
  -- `guardian_link_events` are append-only (WS-DOM-03 guard triggers refuse DELETE), so removing the
  -- events is impossible and the projections cannot be removed while the events reference them. An
  -- earlier version of this test tried to delete them and failed with "guardian_permission_events is
  -- append-only" — which is the guard working. This suite therefore runs in its OWN database in CI so the
  -- leftover rows cannot perturb another suite's counts.
END $$;

\echo 'CLOCK DISCIPLINE TESTS COMPLETED (CLK-01..03)'
