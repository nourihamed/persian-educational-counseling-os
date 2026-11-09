# Control Plane Mobile HMAC Rotation & Claim Admission Protocol

**Status:** DRAFT / NOT APPROVED. OQ-B Option K is accepted. Database-side admission and rotation guards now exist and passed synthetic PostgreSQL 16 CI. No production KMS/HSM integration, cryptographic backfill or real-data operation is authorized. D-014 synthetic data only.

## 1. Data model

- Recoverable canonical E.164 is stored only as authenticated ciphertext in student_contact_index; encryption keys remain in Platform Security's external KMS/HSM boundary.
- Each student has one contact-index row per live HMAC key version.
- Each claim has one enrollment_claim_identity_aliases row per active/retiring HMAC key version.
- Global uniqueness is enforced on (key_version, mobile_hmac, grade_key) for claim states active and transfer_pending.
- The key_version dimension is not itself cross-version uniqueness. Safe overlap requires every holding claim to have an alias for every active/retiring key version.
- No raw E.164, HMAC key, encryption key or recoverable secret is stored in source control or ordinary database columns.

## 2. Initial identity claim admission

cp_07_claim_admission_draft.sql defines admit_student_identity_claim(...). It is a SECURITY DEFINER database operation with a dedicated executor role and no direct table DML for that executor.

The function:
1. Reserves an append-only idempotency command; same key/same payload replays the original claim, same key/different payload is rejected.
2. Acquires a shared lock on the identity-maintenance gate and holds it through transaction commit. Rotation's gate update must wait for in-flight admissions; new admissions fail closed while maintenance is active.
3. Requires an active Workspace, exactly one active HMAC key, an active encryption-key version, non-empty ciphertext, and exactly one valid 32-byte HMAC alias for every active/retiring key version.
4. Atomically creates platform student, initial Workspace ownership at generation 1, the global enrollment claim, encrypted contact-index rows and versioned aliases.
5. Relies on the global per-version unique index to reject duplicate mobile+grade claims across Workspaces; a conflict rolls back the entire admission.
6. Does not store plaintext E.164 or key material.

The trusted service must normalize E.164, compute every alias from the same canonical value, encrypt the mobile, bind the payload hash and authenticate/authorize the caller. SQL verifies alias coverage and uniqueness; it cannot prove cryptographic equivalence of HMAC values or lawful human identity.

## 3. Mandatory rotation protocol: write freeze + complete backfill

A new HMAC version MUST NOT become active for claim writes until every live claim has a new-version alias.

1. Platform Security creates a new HMAC key version in KMS/HSM and records its non-secret version identifier.
2. Acquire the global Control Plane identity-maintenance lock. The database gate row is shared by claim admission and rotation; the rotation operation updates/locks it exclusively.
3. Set claim mutation admission to maintenance/fail-closed. New initial admissions are rejected; contact changes must also be rejected by the future contact-change operation. Transfer switches must pause.
4. Backfill a new encrypted contact-index version and HMAC alias for every student with a holding claim. Decrypt/recompute only inside the approved security boundary. Never export plaintext or keys to logs.
5. Verify under the same maintenance lock:
   - every holding claim has exactly one alias for every active/retiring key version;
   - each alias matches the student's canonical E.164 under that key version;
   - no duplicate (key_version, mobile_hmac, grade_key) exists;
   - alias count per holding claim equals the active/retiring key-version count;
   - all non-holding claims have no active aliases.
6. Mark the new key version active and the old one retiring. The database enforces at most one active HMAC key version. Keep both aliases for every live claim. Resume writes only after all checks pass.
7. Every new claim must dual-write all active/retiring aliases in one transaction. The draft admission function enforces this.
8. Retire the old version only after policy-approved overlap, full coverage verification and rollback/recovery review. Remove retired aliases/contact-index rows only after consumers use the surviving active version; preserve audit history.

## 4. Concurrency and enforcement

- Claim admission acquires the gate FOR SHARE and holds it until commit; rotation's exclusive gate update serializes against it.
- The admission function requires exactly one active HMAC key and complete active/retiring alias coverage.
- Partial unique index enforces at most one active HMAC key version; a second active key is rejected.
- Direct application table writes are revoked. The identity-admission executor can execute only the admission function.
- Transfer switch validates exactly one source claim, owner/generation and aliases for all active/retiring versions before ownership changes.
- Global unique indexes reject concurrent duplicate claims within each key version. Cross-version correctness depends on full alias coverage and trusted cryptographic computation.
- If KMS/HSM is unavailable, key versions disagree, alias coverage is incomplete, or the maintenance lock cannot be established, identity mutation and transfer finalization fail closed.

## 5. Recovery

- Before activation of the new key version: abort backfill, keep old version active, remove only incomplete new-version aliases under maintenance lock, verify old coverage, then resume.
- After activation with both versions complete: keep both aliases and retry forward. Do not revert application code to a key version whose coverage is incomplete.
- If key compromise is suspected, revoke access and execute an incident-specific rotation/recovery plan with audit and dual control; do not improvise a database-only key change.

## 6. Test evidence

GitHub Actions run #148 passed on PostgreSQL 16 at SQL/test tree SHA e97056b44ebfdbfce5344a9c524ba8af1e72055b:
- rotation maintenance gate and alias-coverage regressions: PASS;
- duplicate mobile+grade claim rejection and different-grade allowance: PASS;
- initial admission creates all live-key aliases and ownership atomically: PASS;
- idempotent replay and changed-payload rejection: PASS;
- missing/duplicate/malformed alias, inactive encryption key, inactive Workspace and no-active-HMAC rejection: PASS;
- maintenance-mode fail-closed behavior: PASS;
- concurrent cross-Workspace claim admission race: PASS;
- transfer/ownership fencing and global-identity race suites: PASS.

These are synthetic SQL-draft tests. They do not prove KMS/HSM, actual HMAC derivation, encryption correctness, contact-change operations, real principal authentication, or operational crash recovery.

## 7. Remaining HIGH blockers

- Implement mobile contact-change/reverification with all-key alias updates, ciphertext update, idempotency, audit and global uniqueness.
- Implement authenticated principal binding and legal guardian authority verification; approval UUIDs/evidence references are not authentication.
- Implement KMS/HSM access policy, encryption-key lifecycle, cryptographic backfill and key rotation/revocation drills.
- Implement durable outbox/inbox delivery and transfer saga recovery.
- Add crash injection, KMS outage, transfer-vs-rotation concurrency and target-environment tests.
- Split the broad non-login cp_function_owner DML surface into narrowly scoped transfer, rotation and admission function owners before production.
