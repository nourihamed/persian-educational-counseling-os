# Control Plane Mobile HMAC Rotation Protocol

**Status:** DRAFT / NOT APPROVED. OQ-B Option K is accepted; this is the required technical protocol proposal. No KMS/HSM integration or rotation has been implemented or tested. D-014 synthetic data only.

## 1. Data model

- Recoverable canonical E.164 is stored only as authenticated ciphertext in `student_contact_index`; encryption keys remain in Platform Security's external KMS/HSM boundary.
- Each student may have one contact-index row per HMAC key version.
- Each claim has one `enrollment_claim_identity_aliases` row per active/retiring HMAC key version. Global uniqueness is enforced on `(key_version, mobile_hmac, grade_key)` for claim states `active` and `transfer_pending`.
- `key_version` is part of the alias identity, not a substitute for cross-version migration safety.
- No raw E.164, HMAC key, encryption key or recoverable secret is stored in source control or ordinary database columns.

## 2. Mandatory rotation protocol: write freeze + complete backfill

A new HMAC version MUST NOT become active for claim writes until every live claim has a new-version alias. Mixed-version partial coverage is unsafe.

1. Platform Security creates a new key version in KMS/HSM and records its non-secret version identifier.
2. Acquire a global Control Plane identity-maintenance lock. The lock must serialize with all claim create/change/end operations and all transfer ownership switches. Application-level maintenance mode alone is insufficient unless database permissions make bypass impossible.
3. Set claim mutation admission to maintenance/fail-closed. New enrollment claims and identity changes are rejected; transfer switches are paused. Existing read access is governed by normal ownership checks.
4. Backfill a new encrypted contact-index version and HMAC alias for every student with a holding claim. Decrypt/recompute only inside the approved security boundary. Never export plaintext or keys to logs.
5. Verify, under the same maintenance lock:
   - every holding claim has exactly one alias for every key version being retained as active/retiring;
   - each alias matches the student's canonical E.164 under that key version;
   - no duplicate `(key_version, mobile_hmac, grade_key)` exists;
   - alias count per holding claim equals the active/retiring key-version count;
   - all non-holding claims have no active aliases.
6. Mark the new key version active and the old one retiring. Keep both aliases for every live claim. Resume writes only after all checks pass.
7. During the overlap period, every new/changed holding claim MUST create aliases for every active and retiring key version in the same Control Plane transaction. A missing alias rejects the entire transaction.
8. Retire the old version only after policy-approved overlap, full coverage verification and rollback/recovery review. Mark it retired; do not delete audit history. Remove old aliases only in a separate approved maintenance operation after confirming no consumer depends on them.

## 3. Concurrency and enforcement requirements

- Rotation lock and claim mutation lock must use the same database-level serialization mechanism (e.g. a dedicated lock row acquired FOR UPDATE or a fixed advisory-lock key). The implementation must prove no insert/update can pass while backfill is incomplete.
- Claim writes must be performed only through a dedicated Control Plane service role and vetted database functions. Revoke direct table writes from application roles; a trigger or deferred constraint trigger should verify alias completeness at transaction end.
- Ownership switch must lock the claim and verify exactly one claim and one alias for each active/retiring version before switching; the draft `switch_student_ownership` checks the alias count.
- Global unique indexes on each alias version prevent concurrent duplicate claims within that version. Cross-version correctness comes from the full-coverage invariant plus the write freeze/dual-write protocol.
- If KMS/HSM is unavailable, key versions disagree, alias coverage is incomplete, or the maintenance lock cannot be established, identity mutation and transfer finalization fail closed.

## 4. Recovery

- Before activation of the new key version: abort backfill, keep old version active, remove only incomplete new-version aliases under maintenance lock, verify old coverage, then resume.
- After activation with both versions complete: keep both active/retiring aliases and retry forward. Do not silently revert application code to a key version whose coverage is incomplete.
- If key compromise is suspected, revoke access and execute an incident-specific rotation/recovery plan with audit and dual control; do not improvise a database-only key change.

## 5. Required tests (specified, not executed)

- Concurrent claim creation blocked while rotation lock is held.
- No new claim can enter with only a subset of active/retiring aliases.
- Rotation backfill produces complete aliases for all holding claims.
- Duplicate identity is rejected when presented under old version, new version, or both.
- Same mobile with a different grade follows the approved D-025 grade rule.
- Crash during backfill leaves old version authoritative and no partial version activation.
- Crash after activation resumes safely with both versions.
- Transfer switch during rotation serializes and validates alias completeness.
- KMS/HSM unavailable, lock unavailable or incomplete alias set fails closed.
- Old key retirement cannot occur while any holding claim lacks a verified replacement alias.

**Current draft status:** `cp_01` and `cp_05_identity_rotation_guard.sql` now define a database-backed maintenance gate, row-lock serialization against in-flight claim mutations, a claim-write pause, deferred alias-coverage checks, contact-index/HMAC consistency checks, and begin/complete/retire rotation functions. `cp_02` verifies exactly one source claim and a matching alias for every active/retiring key version before switching ownership. These are draft SQL controls only and have NOT been executed.

**Remaining HIGH blockers:** no dedicated least-privilege DB role/grants have been created or verified; application roles must not have direct write access to claims, aliases, key versions or contact index; no production claim-admission/contact-change service is implemented; no KMS/HSM integration or authenticated cryptographic backfill exists; crash/recovery and concurrent rotation tests are NOT RUN. The schema does not independently prove that an HMAC corresponds to the decrypted canonical E.164 value—the trusted Platform Security rotation service must do so. Cross-version uniqueness is therefore still NOT APPROVED until role boundaries, service workflow, SQL tests and concurrency/recovery evidence pass.
