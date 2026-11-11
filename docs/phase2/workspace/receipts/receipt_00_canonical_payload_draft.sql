-- =============================================================================
-- WORKSPACE — Canonical payload contract v1 (receipt-canon-v1). DRAFT, synthetic only.
-- Contract: docs/phase2/workspace/receipts/CANONICALIZATION_CONTRACT.md
-- Rules implemented here (must match the contract and the Python reference):
--   * objects: keys sorted by Unicode code point (COLLATE "C" over UTF-8 bytes); no duplicates
--   * arrays: element order preserved
--   * strings: JSON string escaping as produced by to_json (UTF-8 kept, not normalised)
--   * numbers: ONLY integers matching ^-?(0|[1-9][0-9]*)$, excluding -0, |n| <= 2^53-1
--   * booleans and null: literal true / false / null
--   * anything else (floats, out-of-range integers, NULL input) is REJECTED (fail closed)
-- Digest: SHA-256 over the UTF-8 bytes of the canonical text. This is an integrity
-- fingerprint of the bytes, NOT a signature and NOT production cryptographic approval.
-- =============================================================================
\set ON_ERROR_STOP on
BEGIN;

CREATE FUNCTION receipt_canonical_text_v1(p jsonb) RETURNS text
LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
  t text;
  s text;
BEGIN
  IF p IS NULL THEN
    RAISE EXCEPTION 'canonical v1: NULL payload is not admissible' USING ERRCODE = 'invalid_parameter_value';
  END IF;
  t := jsonb_typeof(p);
  IF t = 'object' THEN
    SELECT '{' || COALESCE(string_agg(to_json(k.key)::text || ':' || receipt_canonical_text_v1(k.value), ',' ORDER BY k.key COLLATE "C"), '') || '}'
      INTO s FROM jsonb_each(p) AS k(key, value);
    RETURN s;
  ELSIF t = 'array' THEN
    SELECT '[' || COALESCE(string_agg(receipt_canonical_text_v1(a.value), ',' ORDER BY a.ord), '') || ']'
      INTO s FROM jsonb_array_elements(p) WITH ORDINALITY AS a(value, ord);
    RETURN s;
  ELSIF t = 'string' THEN
    RETURN to_json(p #>> '{}')::text;
  ELSIF t = 'boolean' THEN
    RETURN CASE WHEN p = 'true'::jsonb THEN 'true' ELSE 'false' END;
  ELSIF t = 'null' THEN
    RETURN 'null';
  ELSIF t = 'number' THEN
    s := p #>> '{}';
    IF s !~ '^-?(0|[1-9][0-9]*)$' OR s = '-0' OR abs((s)::numeric) > 9007199254740991 THEN
      RAISE EXCEPTION 'canonical v1: number % is outside the admissible integer domain', s
        USING ERRCODE = 'invalid_parameter_value';
    END IF;
    RETURN s;
  END IF;
  RAISE EXCEPTION 'canonical v1: unsupported JSON type %', t USING ERRCODE = 'invalid_parameter_value';
END;
$$;

CREATE FUNCTION receipt_payload_digest_v1(p jsonb) RETURNS bytea
LANGUAGE sql IMMUTABLE AS $$
  SELECT sha256(convert_to(receipt_canonical_text_v1(p), 'UTF8'));
$$;

COMMIT;
