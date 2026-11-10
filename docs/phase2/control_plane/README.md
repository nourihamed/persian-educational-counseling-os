# Control Plane — draft schema, tests and boundaries

**Status:** DRAFT / NOT APPROVED. Not a production migration. Phase 2 Gate remains NOT READY.
**Synthetic data only (D-014).** No real student/customer data. No production KMS integration.

## Apply order on a fresh PostgreSQL 15+ database

1. schema/cp_01_schema_draft.sql — registry, ownership, claims and versioned HMAC aliases.
2. schema/cp_05_identity_rotation_guard.sql — maintenance gate, deferred alias-completeness checks and rotation lifecycle functions.
3. schema/cp_07_claim_admission_draft.sql — unique active-key guards and atomic initial identity-claim admission with idempotency.
4. schema/cp_02_switch_function_draft.sql — ownership switch with source claim/generation/alias checks and valid cumulative approvals.
5. schema/cp_03_transfer_transitions_draft.sql — transfer state machine; freeze/snapshot evidence required; no post-switch cancellation.
6. schema/cp_04_transfer_command_idempotency.sql — same-key/same-payload replay and different-payload rejection.
7. schema/cp_06_role_privileges_draft.sql — non-login owner/function roles, least-privilege table/sequence grants and scoped executor functions (apply only in an isolated test DB).
8. tests/cp_30_role_privilege_tests.sql — catalog-level role/privilege assertions.
9. tests/cp_10_constraint_tests.sql — synthetic transfer/rotation/ownership regression suite.
10. tests/cp_15_identity_admission_tests.sql — synthetic initial claim admission, idempotency, HMAC coverage, uniqueness and maintenance-gate tests.
11. tests/cp_20_race.sh <dbname> — two-session global alias uniqueness race.
12. tests/cp_25_claim_admission_race.sh <dbname> — two-session initial admission race across Workspaces.

## Database boundary

- Control Plane stores global student reference, current Workspace owner, ownership generation, global mobile+grade claims, transfer approvals, transfer state, command idempotency, outbox and ownership history.
- It does not store educational records, counselor-private notes or Workspace credit ledger.
- No cross-database foreign keys are claimed. Workspace IDs in Control Plane are registry references; Workspace-local projections are not ownership authority.
- The switch is one Control Plane transaction only. It cannot atomically commit a transaction in a separate Workspace database; durable outbox/inbox and forward recovery are required.

## Invariant status

| Invariant | Draft mechanism | Status |
|---|---|---|
| One current Workspace owner per student | PK on student ownership | Schema + synthetic tests |
| Global mobile+grade uniqueness | Unique index on versioned aliases plus exact active/retiring alias coverage | Synthetic admission, duplicate and race tests pass; cryptographic equivalence still depends on trusted service |
| One holding claim per student | Partial unique index | Schema + synthetic tests |
| Exactly one active HMAC key | Partial unique index | Schema + synthetic tests |
| HMAC exactly 32 bytes | CHECK | Schema + synthetic tests |
| All live HMAC key versions represented | Admission function validates complete active/retiring alias set | Synthetic tests pass |
| No admission during rotation maintenance | Shared gate lock held through admission | Synthetic tests pass |
| OQ-A Platform Admin cannot initiate | CHECK on initiator kind | Schema + synthetic tests |
| All three cumulative transfer approvals | Switch function checks active, non-expired approvals | Principal/authority proof remains application boundary |
| Owner/generation fencing | row locks + compare and swap | Function draft + synthetic tests |
| Exactly one valid source claim | source/generation/state check + row count | Function draft + synthetic tests |
| Idempotent command replay | command log and payload hash | Synthetic tests pass |
| No post-switch cancellation | state transition table | Trigger draft + synthetic tests |
| Append-only ownership history | trigger | Schema + synthetic tests |
| Fail-closed if registry unavailable | service/API behavior | Contract only; not runtime-tested |

## Database role boundary — HIGH

The least-privilege role contract is specified in ROLE_PRIVILEGE_CONTRACT.md. cp_06 creates one non-login table owner, three separate non-login function owners (transfer, rotation, identity admission), and separate runtime/transfer/rotation/identity-admission executors. The identity-admission executor can execute only the initial claim admission function and has no direct table privileges. The split-owner SQL and expanded catalog assertions passed GitHub Actions run #222 on PostgreSQL 16 at exact branch HEAD `2f605051440b4198794e710283f0a6d852983316`. Transfer and identity-admission owners receive only column-level UPDATE on the CHECK-constrained identity-gate singleton to support FOR SHARE locking; only the rotation owner can change maintenance state and epoch. The identity-admission owner receives column-level UPDATE on the immutable Workspace UUID only to acquire a FOR SHARE lock; a trigger rejects key changes and no UPDATE on Workspace status is granted. Production service login binding and target-environment verification remain open.

## HMAC rotation and initial admission — HIGH

cp_05 defines the database-backed maintenance gate and begin/complete/retire rotation functions. cp_07 defines initial claim admission:
- It holds a shared lock on the same identity-maintenance gate used by rotation.
- It requires exactly one active HMAC key and an alias for every active/retiring HMAC version.
- It stores encrypted contact ciphertext and key-version references; plaintext E.164 and key material never enter the database.
- It creates platform student, initial ownership, claim, contact-index rows and aliases atomically.
- It uses an append-only idempotency command log and rejects same-key/different-payload requests.
- A per-version global unique index rejects duplicate mobile+grade claims across Workspaces.

These controls do not prove that the trusted service computed each HMAC from the same canonical E.164 value. Production KMS/HSM integration, cryptographic backfill, key custody, encryption-key rotation, contact-change operation and operational crash recovery remain open.

## Approval limitation — HIGH

The database stores authenticated subject, authentication-event reference, authority snapshot, verification time, expiry and revocation. It cannot independently prove that the subject was the lawful guardian, current prior counselor or authorized destination actor. That proof must come from the identity/authorization service and be bound to the case. Caller-supplied strings are not evidence of authentication.

## Test execution status

GitHub Actions run #148: PASS on PostgreSQL 16 at schema/test tree SHA e97056b44ebfdbfce5344a9c524ba8af1e72055b.
- Control Plane role catalog assertions: PASS.
- Control Plane transfer/rotation/ownership regression suite: PASS.
- Concurrent global identity alias race: PASS.
- Initial claim admission tests CP-ADMIT-01 through CP-ADMIT-13: PASS.
- Concurrent initial claim admission race CP-ADMIT-RACE-01: PASS.
- Workspace core schema, activation/credit/capacity tests, concurrent activation race and two-Workspace role/CONNECT tests: PASS.

Run evidence is synthetic and validates the SQL drafts only. It does not prove KMS/HSM correctness, real principal authentication, runtime APIs, cross-database transfer Saga, backup/restore or production deployment.

## Remaining Control Plane blockers

- Implement mobile contact-change/reverification workflow using the same all-key alias protocol.
- Implement principal-bound guardian/prior-counselor/destination authority verification and approval evidence binding.
- Implement durable outbox/inbox delivery, retries, deduplication, reconciliation and crash recovery; DB delivery functions/worker integration remain incomplete.
- Implement the real cross-database freeze/drain/final-snapshot/staging Saga and source/destination projection orchestration.
- Independently verify KMS/HSM, cryptographic backfill and encryption-key lifecycle.
- Verify the new transfer/rotation/admission function-owner grants against every SECURITY DEFINER and trigger/helper path in fresh PostgreSQL 16 CI; do not treat the draft split as production approval.
- Define measured HA/failover, RPO/RTO, split-brain and backup/restore evidence (OQ-D).



## Transfer approval identity and authority

See `../transfer/TRANSFER_APPROVAL_IDENTITY_AUTHORITY_CONTRACT.md` for the trusted-principal, authority, exact-case binding, replay prevention, revocation and cutover revalidation contract. The current SQL schema stores references and an authority snapshot, but the switch function's non-empty-string checks do **not** authenticate those references or prove authority. This remains a HIGH finding; no trusted verifier or executable authority tests are implemented.

## Mobile contact change and reverification — design contract added

`CONTACT_CHANGE_REVERIFICATION_CONTRACT.md` specifies the missing contact-change path. It requires step-up authentication, verified possession of the proposed number, a single-use proof bound to the exact student/Workspace/generation/contact fingerprint, all active/retiring HMAC aliases, active-key ciphertext, atomic uniqueness enforcement, idempotency, append-only audit and transactional outbox.

This is a **design contract only**. No contact-change SQL function, proof verifier, API or executable test has been implemented. The contract explicitly leaves account recovery without the old contact, guardian-age policy, retention durations and notification disclosure policy unresolved. D-014 remains synthetic-only.


## Transfer approval identity and authority

`TRANSFER_APPROVAL_IDENTITY_AUTHORITY_CONTRACT.md` defines the trusted identity/authorization boundary for guardian consent, source-counselor fee confirmation and destination acceptance. It requires a signed, one-time, case/student/Workspace/generation-bound assertion from a trusted verifier, authority revalidation at cutover, append-only approval/revocation history and serialization of revocation against ownership switch.

**Schema gap identified:** current `transfer_approvals` has one row per (case, kind) and mutable `revoked_at`; it cannot retain a revoked approval and a replacement approval as separate immutable events. This must be reconciled before approval workflow implementation. Q-007 legal guardian/age policy remains open. Design only; no executable approval verifier or API tests are claimed.
