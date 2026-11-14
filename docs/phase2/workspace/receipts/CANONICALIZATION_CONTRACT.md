# Canonical payload contract — receipt-canon-v1 (DRAFT, synthetic only)

Status: **contract definition for test and draft use.** Not a production cryptographic policy. Not approved. Phase 2 gate: NOT READY.

## 1. Three separated layers
1. **Contract definition** (this document): the rules below.
2. **Test-only reference implementation:** `verifier_interface/canonical/canonical_v1.py`. Used only by tests.
3. **Draft SQL implementation:** `receipt_00_canonical_payload_draft.sql`. Implements the same rules for the draft database.
**Production implementation: DEFERRED** (Platform Security, PS-1/PS-2). No production signature or hash policy is approved here.

## 2. Scope of the digest
The digest covers the **event payload** (`p_event_payload` of the consume command). It is bound to the receipt as `payload_digest` together with `canonicalization_version`.

## 3. Rules (version `receipt-canon-v1`)
- **Fields:** every key and value of the payload is included. No field is excluded. Metadata of the receipt is not part of this digest.
- **Object keys:** sorted by Unicode code point. Equivalent to UTF-8 byte order (`COLLATE "C"` in SQL). No duplicate keys are admissible.
- **Arrays:** element order is preserved.
- **Strings:** JSON string escaping as produced by `to_json`: `"` and `\` escaped; `\b \f \n \r \t` short forms; other control characters below U+0020 as `\u00xx` (lowercase hex). Non-ASCII characters are written as UTF-8 and **not normalised** (no NFC/NFD conversion).
- **Numbers:** only integers matching `^-?(0|[1-9][0-9]*)$` with `|n| <= 2^53-1`. `-0` is normalised to `0`. Floats, exponent forms and larger integers are **not admissible** and must be rejected.
- **Booleans and null:** the literals `true`, `false`, `null`.
- **Whitespace:** none between tokens.
- **Fail-closed:** an inadmissible payload has no digest.

## 4. Digest
- Algorithm identifier in this contract: **SHA-256** over the UTF-8 bytes of the canonical text.
- This is a **byte fingerprint for binding and integrity**. It is **not a signature**, and computing it does not verify any assertion. Signature verification and key trust are deferred (Decision C).

## 5. Version behaviour
- A receipt stores `canonicalization_version` (immutable after registration, CHECK = `receipt-canon-v1`).
- A receipt whose version is not `receipt-canon-v1` cannot be registered (database CHECK) and cannot be consumed (command check: `unsupported canonicalization version`).
- The verifier test double rejects any other version (`unsupported_canonicalization_version`).
- Introducing a new version requires a new contract version, new vectors in both implementations, and a deliberate migration decision. It is **not** a silent change.

## 6. Ingress requirements (not enforced by PostgreSQL)
- PostgreSQL `jsonb` silently keeps the **last** value of a duplicate key. Therefore duplicate-key rejection **must happen at ingress**, before the payload is converted to `jsonb`. The SQL draft cannot detect duplicates.
- Ingress must produce the payload from the verifier-approved source, not from unverified caller text.

## 7. Test vectors
Shared vectors are asserted by both suites (`test_vectors_v1.py` and `receipt_40_canonical_vectors_tests.sql`): key-order independence, Unicode, nested objects and arrays, booleans and null, escapes, integer edge values, empty containers, `-0` normalisation, rejection of floats and out-of-range integers and NULL, and digest equality with the reference values.

## 8. Known limitations
- Digest agreement between implementations is verified only for the listed vectors, not for all inputs.
- Duplicate keys: see section 6.
- The contract does not define canonical form for numbers outside the integer domain. Such payloads are rejected, not canonicalised.
