-- WS-ISO-01 — CALLER BINDING: signed, short-lived principal assertions verified INSIDE the database.
-- Product Owner decision (2026-11-20): "ISO: B with a test-only key."
-- NOT a migration. Draft SQL. SYNTHETIC ONLY (D-014).
-- Apply AFTER workspace_counselor_scope_draft.sql and BEFORE workspace_plan_items_draft.sql;
-- workspace_counselor_rls_draft.sql is applied after every student-scoped table exists.
--
-- WHAT THIS ESTABLISHES
--   The database learns WHO is calling — which counselor membership or which student — from an assertion
--   whose signature it verifies itself, at the command boundary, with every claim checked. Nothing the
--   caller supplies is trusted as identity: not a function argument, not a GUC, not a "verified" flag, not
--   an opaque receipt reference. The verified principal lives for ONE transaction on ONE backend, so a
--   pooled connection cannot carry it into the next request.
--
-- WHAT THIS DOES NOT ESTABLISH (and must not be read as)
--   * A production key or algorithm. PS-1 (algorithm), PS-2 (allowlist), PS-3 (key registry) and PS-4 (key
--     procedures) are OPEN. Production verification is therefore FAIL-CLOSED: the verification mode is
--     'disabled' unless a superuser test harness switches it to 'synthetic_test', and the key table can hold
--     only keys whose id begins 'synthetic-test-' and whose algorithm is the test-only HMAC. Registering any
--     other key is impossible without a reviewed schema change.
--   * A trustworthy key: the synthetic test key is DERIVED from a public string inside the test files. It is
--     not a secret and protects nothing. It never appears in this file.
--   * Any new runtime write path. The runtime receives EXECUTE on establish_principal() only, which writes
--     to principal bookkeeping tables the runtime cannot read or write directly.
--
-- ASSERTION FORMAT v1 (one canonical ASCII line, no JSON, so no canonicalization question arises — M-05/M-06):
--   wsp1;<workspace uuid>;<counselor|student>;<actor uuid>;<issued epoch s>;<expires epoch s>;<nonce: 32 hex>;<key id>
-- SIGNATURE: lowercase hex of HMAC-SHA256(assertion line, key material). Test-only algorithm; see above.
BEGIN;

-- The HMAC primitive. In its own schema so the role bootstrap (which re-owns everything in `public`) never
-- touches extension members, and so the runtime, which gets no USAGE on it, cannot even name it.
CREATE SCHEMA IF NOT EXISTS ext_crypto;
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA ext_crypto;

-- ======================================================================================================
-- 1. Configuration: fail-closed by default
-- ======================================================================================================
CREATE TABLE principal_verification_config (
  singleton boolean PRIMARY KEY DEFAULT true CHECK (singleton),
  -- 'disabled'       : every assertion is refused (production default; PS-1..PS-4 undecided)
  -- 'synthetic_test' : only synthetic-test keys are accepted; set by a superuser test harness only
  mode      text NOT NULL DEFAULT 'disabled' CHECK (mode IN ('disabled','synthetic_test'))
);
INSERT INTO principal_verification_config(singleton, mode) VALUES (true, 'disabled');

CREATE TABLE principal_assertion_keys (
  -- Structurally test-only: a key that is not a synthetic test key cannot be stored at all.
  key_id        text PRIMARY KEY CHECK (key_id ~ '^synthetic-test-[a-z0-9-]{1,48}$'),
  algorithm     text NOT NULL CHECK (algorithm = 'hmac-sha256-synthetic-test'),
  key_material  bytea NOT NULL CHECK (length(key_material) = 32),
  -- the longest lifetime an assertion signed with this key may claim
  max_lifetime  interval NOT NULL CHECK (max_lifetime > interval '0' AND max_lifetime <= interval '15 minutes'),
  created_at    timestamptz NOT NULL DEFAULT clock_timestamp(),
  revoked_at    timestamptz
);

-- Every accepted nonce, forever: a replayed assertion is refused even after it expires.
CREATE TABLE principal_assertion_nonces (
  nonce        text PRIMARY KEY CHECK (nonce ~ '^[0-9a-f]{32}$'),
  key_id       text NOT NULL REFERENCES principal_assertion_keys(key_id),
  actor_kind   text NOT NULL CHECK (actor_kind IN ('counselor','student')),
  actor_id     uuid NOT NULL,
  consumed_at  timestamptz NOT NULL DEFAULT clock_timestamp()
);

-- The verified principal of the CURRENT transaction on a backend. One row per backend, overwritten by the
-- next establishment; it is honoured only while xact_id is the backend's current transaction id, so it
-- dies with the transaction that established it.
CREATE TABLE verified_principal_context (
  backend_pid    integer PRIMARY KEY,
  xact_id        xid8 NOT NULL,
  session_role   name NOT NULL,
  actor_kind     text NOT NULL CHECK (actor_kind IN ('counselor','student')),
  membership_id  uuid,
  -- not named student_id on purpose: this is identity bookkeeping, not a student-owned record, and the
  -- catalog view student_scoped_tables classifies any table with a student_id column as student data
  principal_student_id uuid,
  nonce          text NOT NULL REFERENCES principal_assertion_nonces(nonce),
  verified_at    timestamptz NOT NULL,
  CHECK ((actor_kind = 'counselor') = (membership_id IS NOT NULL AND principal_student_id IS NULL)),
  CHECK ((actor_kind = 'student')   = (principal_student_id IS NOT NULL AND membership_id IS NULL))
);

CREATE FUNCTION guard_append_only_nonce() RETURNS trigger LANGUAGE plpgsql AS $body$
BEGIN
  RAISE EXCEPTION 'principal assertion nonces are append-only' USING ERRCODE='check_violation';
END; $body$;
CREATE TRIGGER principal_assertion_nonces_append_only
  BEFORE UPDATE OR DELETE ON principal_assertion_nonces
  FOR EACH ROW EXECUTE FUNCTION guard_append_only_nonce();

-- ======================================================================================================
-- 2. The command boundary
-- ======================================================================================================
-- SECURITY DEFINER because it must read the key and write the bookkeeping tables, none of which the caller
-- may touch. It establishes identity and nothing else: no row of student data is read or written here.
CREATE FUNCTION establish_principal(p_assertion text, p_signature text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $body$
DECLARE
  v_mode text; f text[]; v_ws uuid; v_kind text; v_actor uuid; v_iat timestamptz; v_exp timestamptz;
  v_nonce text; v_key_id text; k record; v_now timestamptz; v_sig bytea; v_expected bytea;
  v_existing record;
BEGIN
  -- (1) Production is fail-closed until PS-1..PS-4 are decided.
  SELECT c.mode INTO v_mode FROM public.principal_verification_config c WHERE c.singleton;
  IF v_mode IS DISTINCT FROM 'synthetic_test' THEN
    RAISE EXCEPTION 'principal verification is not configured: production verification is fail-closed until '
                    'PS-1..PS-4 are approved' USING ERRCODE='insufficient_privilege';
  END IF;

  -- (2) Strict parse. Anything that is not exactly the v1 shape is refused before any lookup.
  IF p_assertion IS NULL OR p_signature IS NULL
     OR p_assertion !~ '^wsp1;[0-9a-f-]{36};(counselor|student);[0-9a-f-]{36};[0-9]{1,12};[0-9]{1,12};[0-9a-f]{32};synthetic-test-[a-z0-9-]{1,48}$'
     OR p_signature !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'malformed principal assertion' USING ERRCODE='insufficient_privilege';
  END IF;
  f := string_to_array(p_assertion, ';');
  BEGIN
    v_ws := f[2]::uuid; v_kind := f[3]; v_actor := f[4]::uuid;
    v_iat := to_timestamp(f[5]::bigint); v_exp := to_timestamp(f[6]::bigint);
  EXCEPTION WHEN others THEN
    RAISE EXCEPTION 'malformed principal assertion' USING ERRCODE='insufficient_privilege';
  END;
  v_nonce := f[7]; v_key_id := f[8];

  -- (3) The key: known, test-only by construction, not revoked.
  SELECT * INTO k FROM public.principal_assertion_keys pk WHERE pk.key_id = v_key_id;
  IF NOT FOUND OR k.revoked_at IS NOT NULL THEN
    RAISE EXCEPTION 'unknown or revoked assertion key' USING ERRCODE='insufficient_privilege';
  END IF;

  -- (4) The signature over the EXACT bytes received. Any change to any claim invalidates it.
  v_sig := decode(p_signature, 'hex');
  v_expected := ext_crypto.hmac(convert_to(p_assertion, 'UTF8'), k.key_material, 'sha256');
  IF v_sig IS DISTINCT FROM v_expected THEN
    RAISE EXCEPTION 'principal assertion signature is invalid' USING ERRCODE='insufficient_privilege';
  END IF;

  -- (5) Tenant: the assertion must name THIS Workspace.
  IF v_ws IS DISTINCT FROM (SELECT wp.workspace_id FROM public.workspace_profile wp WHERE wp.singleton) THEN
    RAISE EXCEPTION 'principal assertion is for another Workspace' USING ERRCODE='insufficient_privilege';
  END IF;

  -- (6) Time, read after nothing is locked that could delay it; no skew tolerance (PS-5 undecided).
  v_now := clock_timestamp();
  IF v_iat > v_now THEN
    RAISE EXCEPTION 'principal assertion is not yet valid' USING ERRCODE='insufficient_privilege';
  END IF;
  IF v_exp <= v_now THEN
    RAISE EXCEPTION 'principal assertion has expired' USING ERRCODE='insufficient_privilege';
  END IF;
  IF v_exp <= v_iat OR v_exp - v_iat > k.max_lifetime THEN
    RAISE EXCEPTION 'principal assertion lifetime exceeds what its key allows' USING ERRCODE='insufficient_privilege';
  END IF;

  -- (7) The actor must exist and be current NOW, not merely when the assertion was issued.
  IF v_kind = 'counselor' THEN
    IF NOT EXISTS (SELECT 1 FROM public.workspace_memberships m
                     JOIN public.membership_roles r ON r.membership_id = m.membership_id AND r.role_key = 'counselor'
                    WHERE m.membership_id = v_actor AND m.status = 'active') THEN
      RAISE EXCEPTION 'principal is not an active counselor membership' USING ERRCODE='insufficient_privilege';
    END IF;
  ELSE
    IF NOT EXISTS (SELECT 1 FROM public.students s WHERE s.student_id = v_actor AND s.lifecycle_state = 'active') THEN
      RAISE EXCEPTION 'principal is not an active student' USING ERRCODE='insufficient_privilege';
    END IF;
  END IF;

  -- (8) One principal per transaction: a second establishment cannot switch identity mid-transaction.
  SELECT * INTO v_existing FROM public.verified_principal_context vc
   WHERE vc.backend_pid = pg_backend_pid() AND vc.xact_id = pg_current_xact_id();
  IF FOUND THEN
    RAISE EXCEPTION 'a principal is already established in this transaction' USING ERRCODE='insufficient_privilege';
  END IF;

  -- (9) Replay: the nonce is consumed exactly once, ever. Two sessions racing on one nonce serialize on the
  -- primary key and the second fails.
  BEGIN
    INSERT INTO public.principal_assertion_nonces(nonce, key_id, actor_kind, actor_id)
    VALUES (v_nonce, v_key_id, v_kind, v_actor);
  EXCEPTION WHEN unique_violation THEN
    RAISE EXCEPTION 'principal assertion replayed' USING ERRCODE='insufficient_privilege';
  END;

  INSERT INTO public.verified_principal_context(backend_pid, xact_id, session_role, actor_kind, membership_id,
                                                principal_student_id, nonce, verified_at)
  VALUES (pg_backend_pid(), pg_current_xact_id(), session_user, v_kind,
          CASE WHEN v_kind = 'counselor' THEN v_actor END,
          CASE WHEN v_kind = 'student'   THEN v_actor END, v_nonce, v_now)
  ON CONFLICT (backend_pid) DO UPDATE
     SET xact_id = EXCLUDED.xact_id, session_role = EXCLUDED.session_role, actor_kind = EXCLUDED.actor_kind,
         membership_id = EXCLUDED.membership_id, principal_student_id = EXCLUDED.principal_student_id,
         nonce = EXCLUDED.nonce, verified_at = EXCLUDED.verified_at;
END; $body$;
REVOKE ALL ON FUNCTION establish_principal(text, text) FROM PUBLIC;

-- ======================================================================================================
-- 3. Reading the verified principal
-- ======================================================================================================
-- Honoured only for the same backend, the same transaction and the same session role, and only while
-- verification is enabled. Anything else is NULL — and NULL reaches nothing.
CREATE FUNCTION current_principal_membership() RETURNS uuid
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $body$
  SELECT vc.membership_id
    FROM public.verified_principal_context vc
    JOIN public.principal_verification_config c ON c.singleton AND c.mode = 'synthetic_test'
   WHERE vc.backend_pid = pg_backend_pid()
     AND vc.xact_id = pg_current_xact_id_if_assigned()
     AND vc.session_role = session_user;
$body$;
CREATE FUNCTION current_principal_student() RETURNS uuid
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $body$
  SELECT vc.principal_student_id
    FROM public.verified_principal_context vc
    JOIN public.principal_verification_config c ON c.singleton AND c.mode = 'synthetic_test'
   WHERE vc.backend_pid = pg_backend_pid()
     AND vc.xact_id = pg_current_xact_id_if_assigned()
     AND vc.session_role = session_user;
$body$;
-- EXECUTE stays with PUBLIC on purpose (SEC-07 allowlist): the row-level policies call these for every
-- reader, and each returns only the CALLER'S OWN verified principal, or NULL.

-- The RESPONSIBLE counselor (WS-PLAN-01 decision A2: "the authorized responsible counselor"): the predicate
-- of the counselor boundary AND the responsible flag on that same active, accepted assignment.
CREATE FUNCTION counselor_is_responsible_for(p_membership uuid, p_student uuid) RETURNS boolean
LANGUAGE sql STABLE AS $body$
  SELECT public.counselor_may_access_student(p_membership, p_student) AND EXISTS (
    SELECT 1 FROM public.counselor_assignments ca
      JOIN public.enrollments e ON e.enrollment_id = ca.enrollment_id
     WHERE ca.counselor_membership_id = p_membership AND e.student_id = p_student
       AND ca.state = 'active' AND ca.accepted_at IS NOT NULL AND ca.is_responsible);
$body$;

COMMIT;
