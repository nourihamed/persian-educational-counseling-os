# Student Mobile Contact Change & Reverification — Phase 2 Contract

**Status:** DRAFT / NOT APPROVED. Design contract only; no production operation is authorized. Synthetic data only (D-014). This contract complements OQ-B Option K and the initial-claim protocol in `CONTROL_PLANE_KEY_ROTATION.md`.

## 1. Scope and non-goals

This contract covers changing the canonical mobile contact associated with an existing Platform Student and its currently claim-holding enrollment. It does not define initial admission, account recovery when the current contact cannot be verified, legal-identity correction, student merge/split, or a change of guardian authority. Those require separate reviewed workflows.

The mobile number is a contact/identity uniqueness key under D-025, not proof of a person's legal identity. A successful mobile change must not change the Platform Student UUID, Workspace owner, ownership generation, grade, counselor assignment, or educational records.

## 2. Security invariants

1. The caller is authenticated by the trusted identity service; caller-supplied student, Workspace, actor, generation, or authority identifiers are never accepted as proof.
2. The operation requires step-up authentication and verified possession of the proposed new E.164 number. The trusted service verifies the existing account/contact according to the approved recovery policy before issuing a short-lived, single-use proof reference.
3. The proof is bound to the exact student, current owner Workspace, current ownership generation, normalized proposed contact fingerprint, operation purpose, expiry and authentication event. It is single-use and cannot be replayed for another student, number, Workspace or operation.
4. The service normalizes E.164 and computes all HMAC aliases from the same canonical byte sequence using every HMAC key version whose state is `active` or `retiring`. It encrypts the same canonical value using the active encryption key. Database code checks shape, key coverage and uniqueness; it cannot prove the HMACs were correctly derived.
5. Plaintext E.164, OTP values, HMAC key material, encryption keys and decrypted contact values MUST NOT be stored in the database, source control, audit payloads, traces or logs.
6. The update is atomic across the student's contact-index rows and claim aliases. A duplicate (mobile, grade) conflict in any active/retiring key version rejects the whole transaction.
7. Exactly one active claim remains for the student. Ownership and generation do not change.
8. Every contact mutation is idempotent, auditable and protected against concurrent transfer and HMAC rotation.
9. Any missing, expired, revoked, ambiguous or unverifiable proof fails closed.

## 3. Required command contract

A trusted service command should carry:

- `idempotency_key`: unique per logical attempt;
- `payload_hash`: SHA-256 of a canonical, versioned command envelope (not plaintext mobile);
- `student_id`, `expected_workspace_id`, `expected_ownership_generation`;
- `proof_ref`: opaque reference to the verified, single-use proof;
- `authn_event_ref`: immutable step-up authentication event reference;
- `new_mobile_ciphertext` and active `cipher_key_version`;
- `aliases[]`: exactly one `(key_version, mobile_hmac)` for each active/retiring HMAC key version;
- `normalization_version` and `command_schema_version`.

The proof service must bind the new-contact fingerprint to the command. The database must not trust a caller-provided `verified=true` flag or free-form actor UUID. The exact principal and proof binding must be validated through a trusted internal verifier or a signed, audience-restricted, short-lived assertion whose signature, issuer, audience, subject, purpose, expiry and one-time nonce are verified by the trusted service. Secret/signing-key custody is external to PostgreSQL.

## 4. Transaction and locking protocol

The database operation must perform the following in one transaction:

1. Validate argument shapes and reserve an append-only idempotency record. A same-key/same-payload replay returns the original result; same-key/different-payload rejects.
2. Acquire the identity maintenance gate using the same shared-lock protocol as initial admission. If maintenance is active or the gate is unavailable, reject. This serializes the operation against HMAC rotation's exclusive gate lock.
3. Lock the `student_ownership` row `FOR UPDATE`; verify the expected Workspace and ownership generation. This serializes contact change with ownership transfer's compare-and-swap on the same student.
4. Lock and verify the unique active claim; require its grade and Workspace to match the ownership row and command context.
5. Validate the one-time proof through the trusted verifier before mutation. Proof consumption must be atomic/idempotent and bound to the command hash; a proof cannot authorize a different proposed contact.
6. Verify exactly one active encryption key and exactly one HMAC key in `active` state. Require one syntactically valid alias for every `active` or `retiring` HMAC key and reject unknown, duplicate, missing or retired versions.
7. Update every `student_contact_index` row for the student to the new ciphertext and active encryption-key version, and update the matching claim identity aliases to the supplied HMACs. Preserve one row per live key version. A uniqueness conflict must roll back all writes, including proof consumption and command reservation.
8. Verify alias coverage and cross-table equality between contact-index HMACs and claim aliases for all live versions before commit.
9. Append an immutable contact-change audit event containing identifiers, old/new keyed fingerprints or non-reversible references, key-version set, actor/authentication/proof references, timestamp, command ID and outcome. Do not store the mobile number or OTP.
10. Commit. Emit a minimal outbox event in the same transaction; consumers deduplicate by immutable event ID and must not receive the contact value.

The operation must use a single documented lock order across all identity mutations: identity gate, student ownership, active claim, then contact/alias rows. Transfer and rotation functions must be reviewed for compatible lock ordering to prevent deadlocks.

## 5. Failure and recovery behavior

| Condition | Required result |
|---|---|
| New number already claimed for same grade | Reject; no contact, proof, audit-success or alias partial write |
| Same number with a different grade | Apply the existing D-025 rule; uniqueness is grade-scoped |
| Missing/expired/reused proof | Reject and record a security event without sensitive values |
| Ownership or generation changed | Reject as stale context; caller must reload and re-authorize |
| Rotation maintenance active | Reject/retry later; do not queue plaintext contact data |
| Missing/extra/duplicate HMAC alias | Reject before mutation |
| KMS/HSM unavailable or encryption failure | Reject; preserve existing contact |
| Process crash before commit | Transaction rolls back; exact retry is safe |
| Process crash after commit before event delivery | Outbox retries; no second contact mutation |
| Ambiguous result after timeout | Query by idempotency key; never issue a fresh command blindly |

A uniqueness conflict must not disclose which other Workspace owns the conflicting number. External API responses should follow the approved non-enumerating error contract.

## 6. Data model requirements (design only)

The implementation should add:

- An append-only `contact_change_commands` ledger with idempotency key, canonical payload hash, student, expected owner/generation, result reference and timestamp.
- A one-time proof/verification reference with a unique nonce or proof ID, purpose, subject binding, contact fingerprint, expiry and consumed-by command reference. Prefer storing an opaque verifier reference if proof validation is owned by a dedicated identity service.
- An append-only `student_contact_change_audit` record with actor/authentication/proof references, old/new keyed fingerprints (never raw mobile), key-version set, command reference, timestamp and outcome.
- A transactional outbox event for downstream notification/cache invalidation. Notifications must not include the full new number; use a masked display only after authorization.
- Narrow SECURITY DEFINER ownership and executor permissions, separate from initial admission, transfer and key rotation. No shared broad function owner.

Exact table names, proof-verifier integration, cryptographic envelope and notification policy must be reconciled with the final service identity architecture before DDL is approved.

## 7. Required acceptance and regression tests

- Valid verified change updates all contact-index and claim-alias rows atomically for every active/retiring key.
- New ciphertext uses the active encryption-key version; no plaintext or key material is persisted or logged.
- Duplicate same-grade mobile across another Workspace is rejected with full rollback.
- Same mobile with a different grade follows D-025 and is allowed.
- Missing, expired, revoked, wrong-student, wrong-generation, wrong-purpose, wrong-contact and replayed proofs reject.
- Same idempotency key/same payload returns the original result; same key/different payload rejects.
- Concurrent attempts to assign the same mobile+grade yield exactly one winner.
- Concurrent contact change and HMAC rotation serialize through the maintenance gate; no partial alias set is visible.
- Concurrent contact change and ownership transfer serialize on the ownership row; stale generation rejects.
- Unknown, retired, missing, duplicate and malformed aliases reject.
- KMS/HSM outage and encryption failure preserve the old contact.
- Failure injection before commit rolls back all writes; failure after commit is recovered through outbox retry.
- Direct DML by runtime/executor roles is denied; only the narrow command function is executable.
- Catalog tests prove the contact-change function owner cannot transfer ownership, rotate keys, admit new students or write unrelated tables.
- Cross-Workspace API responses do not reveal whether a conflicting mobile exists or which Workspace owns it.

**All tests above are specifications until executable SQL/service tests are implemented and run.**

## 8. Open decisions and boundaries

- Account recovery when the existing mobile is unavailable is explicitly out of scope and needs a separate Product Owner decision and legal review.
- Whether guardian approval is required for a student's contact change depends on the approved age/authority matrix; Q-007 is not silently extended by this contract.
- Contact-change notification recipients and disclosure level require a privacy decision; never notify an unverified new number with student details.
- Retention duration for proof references and contact-change audit is governed by the still-open data-retention policy; no numeric period is invented.
- Production KMS/HSM, cryptographic verification, key custody, service identity, API authorization, monitoring and incident response remain separate operational gates.

## 9. Gate impact

This contract closes no implementation or runtime-security finding by itself. It provides a reviewable Phase 2 design target. The Control Plane identity work remains **NOT READY** until the contract is reconciled with the schema, implemented as a draft database/service boundary, covered by regression and concurrency tests, and independently reviewed.
