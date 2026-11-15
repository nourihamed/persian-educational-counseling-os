-- =============================================================================
-- DATABASE HARDENING — CATALOG-DRIVEN PRIVILEGE ASSERTIONS (SYNTHETIC ONLY, D-014).
-- Run after every Workspace draft and the receipt drafts, and after workspace_roles_setup_draft.sql and
-- receipt_02_roles_draft.sql, so every role exists and every ownership reassignment has happened.
--
-- WHY THIS FILE EXISTS
--   Batch 6 is an adversarial review. Reviewing the SQL by reading it is how the problems below survived
--   several passes, so these assertions interrogate the CATALOG instead: they describe properties that
--   must hold for every SECURITY DEFINER function and every role, not for a list of names someone
--   remembered to check.
--
--   What the review found:
--     * receipt_consume_grant_guard() was SECURITY DEFINER and owned by a SUPERUSER, because it is
--       created before the role that should own it exists. A SECURITY DEFINER function owned by a
--       superuser runs AS superuser. It also carried `public` on its search_path.
--     * There is NO row-level security anywhere in this database, so counselor-to-counselor isolation
--       inside one Workspace is not enforced here at all. SEC-10 records that as a measured fact rather
--       than letting its absence be mistaken for a passing property.
--
-- WHAT THESE TESTS DO NOT PROVE
--   Nothing about an API, object-level authorization, IDOR or uniform 404 behaviour: no service layer
--   exists in this repository. Nothing about superuser or table-owner behaviour — see SEC-08, which
--   records the limitation instead of pretending it away.
-- =============================================================================
\set ON_ERROR_STOP on

-- ===================================================================================================
-- SEC-01  No SECURITY DEFINER function may be owned by a superuser.
--         This is the one that was broken. It is asserted for EVERY definer function, so a new function
--         created before its owner role exists fails here instead of shipping as a superuser.
-- ===================================================================================================
DO $t$
DECLARE v_bad text;
BEGIN
  SELECT string_agg(p.proname || ' (owner ' || pg_get_userbyid(p.proowner) || ')', ', ' ORDER BY p.proname)
    INTO v_bad
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    JOIN pg_roles r ON r.oid = p.proowner
   WHERE n.nspname = 'public' AND p.prosecdef AND r.rolsuper;
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL SEC-01 these SECURITY DEFINER functions are owned by a SUPERUSER and therefore '
                    'execute with superuser privilege: %. Create the owning role first, or reassign with '
                    'ALTER FUNCTION ... OWNER TO, as receipt_02_roles_draft.sql does.', v_bad;
  END IF;
  RAISE NOTICE 'PASS SEC-01 no SECURITY DEFINER function is owned by a superuser';
END $t$;

-- ===================================================================================================
-- SEC-02  Every SECURITY DEFINER function must pin a search_path. An unpinned definer function resolves
--         names through the CALLER's search_path, which is the classic escalation vector.
-- ===================================================================================================
DO $t$
DECLARE v_unpinned text;
BEGIN
  SELECT string_agg(p.proname, ', ' ORDER BY p.proname) INTO v_unpinned
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.prosecdef
     AND NOT EXISTS (SELECT 1 FROM unnest(coalesce(p.proconfig,'{}')) c WHERE c LIKE 'search_path=%');
  IF v_unpinned IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL SEC-02 these SECURITY DEFINER functions do not pin a search_path, so they '
                    'resolve names through the caller''s: %', v_unpinned;
  END IF;
  RAISE NOTICE 'PASS SEC-02 every SECURITY DEFINER function pins its search_path';
END $t$;

-- ===================================================================================================
-- SEC-02b THE PROPERTY THAT ACTUALLY CARRIES THE WEIGHT: no application role may CREATE in a schema that
--         appears on a definer function's search_path.
--
--         Several definer functions carry `public` on their search_path. That is worth tightening, and
--         receipt_consume_grant_guard() was tightened, but on its own it is NOT a live hole here — and
--         the review measured that rather than asserting it. Shadowing an unqualified name requires
--         CREATE on the schema, and the measurement is:
--            PUBLIC                              -> cannot CREATE in public
--            runtime / worker / exporter          -> cannot
--            verifier_rt / adapter_rt / synth_exec-> cannot
--            table_owner / function_owner         -> CAN, and they are NOLOGIN and already trusted
--         So this test guards the real precondition. If an application role ever gains CREATE on public,
--         every definer function with `public` on its path becomes exploitable at once, and this fails.
-- ===================================================================================================
DO $t$
DECLARE v_bad text;
BEGIN
  IF has_schema_privilege('public', 'public', 'CREATE') THEN
    RAISE EXCEPTION 'FAIL SEC-02b PUBLIC can CREATE in schema public. Any role could then shadow an '
                    'unqualified name inside a SECURITY DEFINER function and have it executed with that '
                    'function owner''s privileges.';
  END IF;

  SELECT string_agg(r.rolname, ', ' ORDER BY r.rolname) INTO v_bad
    FROM pg_roles r
   WHERE r.rolname ~ '_(runtime|worker|exporter|verifier_rt|governance_adapter_rt|synth_exec|synth_inbox|transfer_ctl)(_login)?$'
     AND has_schema_privilege(r.rolname, 'public', 'CREATE');
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL SEC-02b these application roles can CREATE in schema public: %', v_bad;
  END IF;
  RAISE NOTICE 'PASS SEC-02b neither PUBLIC nor any application role can CREATE in schema public, so an '
               'unqualified name inside a definer function cannot be shadowed';
END $t$;

-- ===================================================================================================
-- SEC-02c A definer function that carries `public` on its path must schema-qualify what it touches.
--         Reported as a NOTICE and not a failure, because SEC-02b shows the precondition for exploiting
--         it does not hold — overstating it would be as misleading as ignoring it. Tightening the rest
--         to pg_catalog,pg_temp is recorded as hardening work in the register, not claimed as done.
-- ===================================================================================================
DO $t$
DECLARE v_list text; v_n integer;
BEGIN
  SELECT count(*), string_agg(p.proname, ', ' ORDER BY p.proname) INTO v_n, v_list
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.prosecdef
     AND EXISTS (SELECT 1 FROM unnest(coalesce(p.proconfig,'{}')) c
                  WHERE c LIKE 'search_path=%' AND c ~ '(^|[=,[:space:]])public([,[:space:]]|$)');
  IF v_n > 0 THEN
    RAISE NOTICE 'PASS SEC-02c % definer function(s) still carry `public` on their search_path: %. Not a '
                 'live hole (SEC-02b), tracked as hardening, not claimed as fixed.', v_n, v_list;
  ELSE
    RAISE NOTICE 'PASS SEC-02c no definer function carries `public` on its search_path';
  END IF;
END $t$;

-- ===================================================================================================
-- SEC-03  Definer-function owners must be NOLOGIN. An owner that can log in is an identity an attacker
--         could try to obtain directly, which would hand them everything the definer function can do.
-- ===================================================================================================
DO $t$
DECLARE v_bad text;
BEGIN
  SELECT string_agg(DISTINCT r.rolname, ', ' ORDER BY r.rolname) INTO v_bad
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    JOIN pg_roles r ON r.oid = p.proowner
   WHERE n.nspname = 'public' AND p.prosecdef AND r.rolcanlogin;
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL SEC-03 these roles own SECURITY DEFINER functions and can LOG IN: %', v_bad;
  END IF;
  RAISE NOTICE 'PASS SEC-03 every SECURITY DEFINER owner is NOLOGIN';
END $t$;

-- ===================================================================================================
-- SEC-04  No application role may own a table. A table owner can disable triggers (see SEC-08), so
--         handing an application identity ownership would hand it a way around every guard.
-- ===================================================================================================
DO $t$
DECLARE v_bad text;
BEGIN
  SELECT string_agg(c.relname || ' (owner ' || pg_get_userbyid(c.relowner) || ')', ', ' ORDER BY c.relname)
    INTO v_bad
    FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname = 'public' AND c.relkind = 'r'
     AND pg_get_userbyid(c.relowner) ~ '_(runtime|worker|exporter|verifier_rt|governance_adapter_rt)(_login)?$';
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL SEC-04 these tables are owned by an application role: %', v_bad;
  END IF;
  RAISE NOTICE 'PASS SEC-04 no application role owns a table';
END $t$;

-- ===================================================================================================
-- SEC-05  No login role may hold a superuser, createrole, createdb or bypassrls attribute.
-- ===================================================================================================
DO $t$
DECLARE v_bad text;
BEGIN
  SELECT string_agg(rolname, ', ' ORDER BY rolname) INTO v_bad
    FROM pg_roles
   WHERE rolname LIKE 'ws\_%' AND (rolsuper OR rolcreaterole OR rolcreatedb OR rolbypassrls);
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL SEC-05 these Workspace roles hold a dangerous attribute: %', v_bad;
  END IF;
  RAISE NOTICE 'PASS SEC-05 no Workspace role is superuser / createrole / createdb / bypassrls';
END $t$;

-- ===================================================================================================
-- SEC-06  PUBLIC must hold no table privilege at all. A single stray grant to PUBLIC would give every
--         role in the cluster — including another Workspace's roles, which live in the same cluster —
--         access to this Workspace's data.
-- ===================================================================================================
DO $t$
DECLARE v_bad text;
BEGIN
  SELECT string_agg(DISTINCT table_name || ':' || privilege_type, ', ' ORDER BY table_name || ':' || privilege_type)
    INTO v_bad
    FROM information_schema.role_table_grants
   WHERE grantee = 'PUBLIC' AND table_schema = 'public';
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL SEC-06 PUBLIC holds table privileges: %. Every role in the cluster, including '
                    'other Workspaces'' roles, would inherit them.', v_bad;
  END IF;
  RAISE NOTICE 'PASS SEC-06 PUBLIC holds no table privilege in this database';
END $t$;

-- ===================================================================================================
-- SEC-07  Only trigger functions and the deliberately-public freeze assertion may be EXECUTE-able by
--         PUBLIC. A trigger function cannot be invoked directly — PostgreSQL refuses — so a PUBLIC
--         EXECUTE on one grants nothing; a PUBLIC EXECUTE on an ordinary definer function would.
-- ===================================================================================================
DO $t$
DECLARE v_bad text;
BEGIN
  SELECT string_agg(p.proname, ', ' ORDER BY p.proname) INTO v_bad
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.prosecdef
     AND has_function_privilege('public', p.oid, 'EXECUTE')
     AND pg_get_function_result(p.oid) <> 'trigger'
     -- assert_student_not_frozen is PUBLIC on purpose: every writer's barrier trigger calls it, it only
     -- reads freeze state and raises, and it returns void.
     AND p.proname <> 'assert_student_not_frozen';
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL SEC-07 these non-trigger SECURITY DEFINER functions are executable by PUBLIC: %',
      v_bad;
  END IF;
  RAISE NOTICE 'PASS SEC-07 no unexpected SECURITY DEFINER function is executable by PUBLIC';
END $t$;

-- ===================================================================================================
-- SEC-08  A LIMITATION, recorded rather than hidden. The table owner can disable triggers, and a
--         superuser can do anything. Every guard in this schema is a trigger or a CHECK, so neither
--         identity is contained by it. This test asserts that the limitation is what we think it is —
--         that the owner really can disable a trigger — so the threat model stays honest and nobody
--         later claims the barrier binds the owner.
-- ===================================================================================================
DO $t$
DECLARE v_disabled boolean;
BEGIN
  ALTER TABLE public.students DISABLE TRIGGER USER;
  SELECT bool_or(NOT tgenabled = 'O') INTO v_disabled
    FROM pg_trigger WHERE tgrelid = 'public.students'::regclass AND NOT tgisinternal;
  ALTER TABLE public.students ENABLE TRIGGER USER;
  IF NOT coalesce(v_disabled, false) THEN
    RAISE EXCEPTION 'FAIL SEC-08 the owner could not disable triggers, so this project''s stated threat '
                    'model is wrong and the surrounding documentation must be corrected';
  END IF;
  RAISE NOTICE 'PASS SEC-08 confirmed limitation: the TABLE OWNER can disable triggers, so no trigger-based '
               'guard contains the owner or a superuser. Containing them needs operational control of '
               'those credentials, which is outside the database.';
END $t$;

-- ===================================================================================================
-- SEC-09  Every table has a primary key. Without one there is no stable row identity, so an audit trail
--         cannot reliably point at a row and a replication or repair tool cannot address it.
-- ===================================================================================================
DO $t$
DECLARE v_bad text;
BEGIN
  SELECT string_agg(c.relname, ', ' ORDER BY c.relname) INTO v_bad
    FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname = 'public' AND c.relkind = 'r'
     AND NOT EXISTS (SELECT 1 FROM pg_constraint k WHERE k.conrelid = c.oid AND k.contype = 'p');
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL SEC-09 these tables have no primary key: %', v_bad;
  END IF;
  RAISE NOTICE 'PASS SEC-09 every table has a primary key';
END $t$;

-- ===================================================================================================
-- SEC-10  THE HEADLINE NEGATIVE RESULT, asserted so it cannot be mistaken for a passing property.
--
--         The Supervisor brief requires: "No counselor may access another counselor's students, even
--         within the same Organization."
--
--         This database does NOT enforce that, and this test proves it rather than describing it. There
--         is no row-level security on any table, and the Workspace runtime role can SELECT whole tables.
--         Tenant isolation here is per-Workspace — one database per Workspace, no cross-database grants
--         (which the cross-database denial step does test) — and WITHIN a Workspace every counselor's
--         students are visible to the one runtime role. Counselor-to-counselor isolation therefore
--         depends entirely on an application layer that does not exist in this repository.
--
--         The test fails if the situation changes in either direction, so the record cannot silently rot:
--         if RLS is added, this assertion must be replaced with real isolation tests.
-- ===================================================================================================
DO $t$
DECLARE
  v_rls integer;
  v_runtime text := 'ws_' || current_setting('app.workspace_key') || '_runtime';
  v_readable integer;
BEGIN
  SELECT count(*) INTO v_rls
    FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname = 'public' AND c.relkind = 'r' AND c.relrowsecurity;

  SELECT count(*) INTO v_readable
    FROM information_schema.role_table_grants
   WHERE grantee = v_runtime AND privilege_type = 'SELECT' AND table_schema = 'public';

  IF v_rls > 0 THEN
    RAISE EXCEPTION 'SEC-10 OUT OF DATE: % table(s) now have row-level security. Counselor-to-counselor '
                    'isolation may now be enforceable in the database — replace this assertion with real '
                    'isolation tests and update PHASE2_EXIT_CRITERIA.md and the unresolved-item register.',
                    v_rls;
  END IF;
  IF v_readable = 0 THEN
    RAISE EXCEPTION 'SEC-10 OUT OF DATE: the runtime role can no longer SELECT any table; the isolation '
                    'model has changed and this assertion must be rewritten';
  END IF;

  RAISE NOTICE 'PASS SEC-10 recorded NEGATIVE result: no row-level security on any table, and the runtime '
               'role can SELECT % tables in full. Counselor-to-counselor isolation inside a Workspace is '
               'NOT enforced by this database and is NOT claimed. Isolation here is per-Workspace only.',
               v_readable;
END $t$;

SELECT 'PRIVILEGE HARDENING TESTS COMPLETED (SEC-01..SEC-10)' AS result;
