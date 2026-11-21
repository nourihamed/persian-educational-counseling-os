-- TEST HARNESS ONLY — never loaded by a draft, never part of a schema. SYNTHETIC ONLY (D-014).
-- Gives a test session a VERIFIED principal through the real command boundary (establish_principal), by
-- building and signing a fresh assertion with the synthetic test key. Every check establish_principal makes
-- still runs; the harness only saves each test from hand-building assertions. The signature, expiry,
-- replay, tenant and actor checks themselves are tested directly in workspace_principal_assertion_tests.sql.
--
-- test_establish() is a superuser-owned SECURITY DEFINER function so it can read the test key. That is
-- acceptable ONLY because this file is test scaffolding: SEC-01 forbids it in the schema, and no draft
-- creates it. Its EXECUTE is granted to the two identities the tests act as, nobody else.
\set ON_ERROR_STOP on
SET app.workspace_key = :'workspace_key';
INSERT INTO principal_assertion_keys(key_id, algorithm, key_material, max_lifetime)
VALUES ('synthetic-test-harness', 'hmac-sha256-synthetic-test',
        ext_crypto.digest('WS-ISO-01 synthetic harness key - public, not a secret, never for production', 'sha256'),
        interval '5 minutes')
ON CONFLICT (key_id) DO NOTHING;
UPDATE principal_verification_config SET mode = 'synthetic_test';

CREATE OR REPLACE FUNCTION test_establish(p_kind text, p_actor uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $body$
DECLARE v_now bigint := extract(epoch FROM clock_timestamp())::bigint; v_line text;
BEGIN
  v_line := format('wsp1;%s;%s;%s;%s;%s;%s;synthetic-test-harness',
                   (SELECT wp.workspace_id FROM public.workspace_profile wp WHERE wp.singleton),
                   p_kind, p_actor, v_now - 5, v_now + 120, encode(ext_crypto.gen_random_bytes(16), 'hex'));
  PERFORM public.establish_principal(v_line,
    encode(ext_crypto.hmac(convert_to(v_line,'UTF8'),
           (SELECT k.key_material FROM public.principal_assertion_keys k WHERE k.key_id = 'synthetic-test-harness'),
           'sha256'), 'hex'));
END; $body$;
REVOKE ALL ON FUNCTION test_establish(text, uuid) FROM PUBLIC;
SELECT format('GRANT EXECUTE ON FUNCTION test_establish(text, uuid) TO %I, %I',
              'ws_'||current_setting('app.workspace_key')||'_synth_plan_writer',
              'ws_'||current_setting('app.workspace_key')||'_runtime') \gexec
