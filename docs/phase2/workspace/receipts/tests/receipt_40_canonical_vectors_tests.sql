-- =============================================================================
-- M-03: canonical payload contract vectors (receipt-canon-v1). Synthetic only.
-- The expected canonical texts and digests are the SAME values asserted by the Python reference
-- (verifier_interface/canonical/tests). Divergence in either implementation fails its suite.
-- =============================================================================
\set ON_ERROR_STOP on
CREATE OR REPLACE FUNCTION expect_text(label text, got text, want text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  IF got IS DISTINCT FROM want THEN RAISE EXCEPTION 'FAIL %: got % expected %', label, got, want; END IF;
  RAISE NOTICE 'PASS %', label;
END; $$;

SELECT expect_text('M03-V1 key order is canonical ({"b":1,"a":2})', receipt_canonical_text_v1('{"b":1,"a":2}'::jsonb), '{"a":2,"b":1}');
SELECT expect_text('M03-V2 key order independent (same semantic payload)', receipt_canonical_text_v1('{"a":2,"b":1}'::jsonb), '{"a":2,"b":1}');
SELECT expect_text('M03-V3 unicode keys and values kept as UTF-8', receipt_canonical_text_v1('{"name":"محمد","k":"é"}'::jsonb), '{"k":"é","name":"محمد"}');
SELECT expect_text('M03-V4 nested objects, arrays, true, false, null', receipt_canonical_text_v1('{"z":[{"y":1,"x":[true,false,null]}],"a":{}}'::jsonb), '{"a":{},"z":[{"x":[true,false,null],"y":1}]}');
SELECT expect_text('M03-V5 string escapes', receipt_canonical_text_v1('"a\"b\\c\n"'::jsonb), '"a\"b\\c\n"');
SELECT expect_text('M03-V6 integer 1000', receipt_canonical_text_v1('1000'::jsonb), '1000');
SELECT expect_text('M03-V7 max safe integer', receipt_canonical_text_v1('9007199254740991'::jsonb), '9007199254740991');
SELECT expect_text('M03-V8 empty array', receipt_canonical_text_v1('[]'::jsonb), '[]');
SELECT expect_text('M03-V9 empty object', receipt_canonical_text_v1('{}'::jsonb), '{}');
SELECT expect_text('M03-V10 -0 normalises to 0 (contract rule)', receipt_canonical_text_v1('-0'::jsonb), '0');

-- Digests: same values as the Python reference.
SELECT expect_text('M03-D1 digest of key-order vector', encode(receipt_payload_digest_v1('{"b":1,"a":2}'::jsonb),'hex'), 'd3626ac30a87e6f7a6428233b3c68299976865fa5508e4267c5415c76af7a772');
SELECT expect_text('M03-D2 digest of unicode vector', encode(receipt_payload_digest_v1('{"name":"محمد","k":"é"}'::jsonb),'hex'), '4f545be67fb40cce775087b3055e1a1423c15439a296725ea08f4eb6612b0ee8');
SELECT expect_text('M03-D3 digest of nested vector', encode(receipt_payload_digest_v1('{"z":[{"y":1,"x":[true,false,null]}],"a":{}}'::jsonb),'hex'), '8dbc40f91fce2c44fa3023aa598db8162d8d339c6f555c215519ed9c83896d60');
SELECT expect_text('M03-D4 a changed value changes the digest', CASE WHEN receipt_payload_digest_v1('{"role_key":"counselor"}') = receipt_payload_digest_v1('{"role_key":"admin"}') THEN 'same' ELSE 'different' END, 'different');

-- Inadmissible inputs fail closed.
DO $$ BEGIN PERFORM receipt_canonical_text_v1('1.5'::jsonb); RAISE EXCEPTION 'FAIL M03-R1: float admitted';
EXCEPTION WHEN invalid_parameter_value THEN RAISE NOTICE 'PASS M03-R1 float rejected'; END $$;
DO $$ BEGIN PERFORM receipt_canonical_text_v1('9007199254740992'::jsonb); RAISE EXCEPTION 'FAIL M03-R2: out-of-range integer admitted';
EXCEPTION WHEN invalid_parameter_value THEN RAISE NOTICE 'PASS M03-R2 integer above 2^53-1 rejected'; END $$;
DO $$ BEGIN PERFORM receipt_canonical_text_v1(NULL::jsonb); RAISE EXCEPTION 'FAIL M03-R3: NULL admitted';
EXCEPTION WHEN invalid_parameter_value THEN RAISE NOTICE 'PASS M03-R3 NULL payload rejected'; END $$;
DO $$ BEGIN RAISE NOTICE '=== CANONICAL CONTRACT VECTORS (M-03) COMPLETED (synthetic) ==='; END $$;
