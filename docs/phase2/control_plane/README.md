# Control Plane — draft schema, tests and boundaries

**Status:** DRAFT / NOT APPROVED. Not a production migration. Phase 2 Gate remains NOT READY.
**Synthetic data only (D-014).** No real student/customer data. No production KMS integration.

## Apply order on a fresh PostgreSQL 15+ database

1. `schema/cp_01_schema_draft.sql` — registry, ownership, claims and versioned HMAC aliases.
2. `schema/cp_02_switch_function_draft.sql` — ownership switch with source claim/generation/alias checks and valid cumulative approvals.
3. `schema/cp_03_transfer_transitions_draft.sql` — transfer state machine; no cancellation after ownership switch.
4. `schema/cp_04_transfer_command_idempotency.sql` — same-key/same-payload replay and different-payload rejection.
5. `tests/cp_10_constraint_tests.sql` — synthetic regression suite.
6. `tests/cp_20_race.sh <dbname>` — two-session alias uniqueness race; requires three fixture Workspace IDs to exist.

## Database boundary

- Control Plane stores global student reference, current Workspace owner, ownership generation, global mobile+grade claims, transfer approvals, transfer state, command idempotency, outbox and ownership history.
- It does not store educational records, counselor-private notes or credit ledger.
- No cross-database foreign keys are claimed. Workspace IDs in Control Plane are registry references; Workspace-local projections are not ownership authority.
- The switch is one Control Plane transaction only. It cannot atomically commit a transaction in a separate Workspace database; durable outbox/inbox and forward recovery are required.

## Invariant status

| Invariant | Draft mechanism | Status |
|---|---|---|
| One current Workspace owner per student | PK on student ownership | Schema specified |
| Global mobile+grade uniqueness | Unique index on versioned identity aliases | Per-version only; rotation protocol required |
| One holding claim per student | Partial unique index | Schema specified |
| HMAC exactly 32 bytes | CHECK | Schema specified |
| OQ-A Platform Admin cannot initiate | CHECK on initiator kind | Schema specified |
| All three cumulative approvals | Switch function checks active, non-expired approvals | Principal/authority proof remains application boundary |
| Owner/generation fencing | row locks + compare and swap | Function draft |
| Exactly one valid source claim | source/generation/state check + row count | Function draft |
| Idempotent command replay | cp_04 command log and payload hash | Function draft; tests required |
| No post-switch cancellation | state transition table | Trigger draft |
| Append-only ownership history | trigger | Schema specified |
| Fail-closed if registry unavailable | service/API behavior | Contract only; not runtime-tested |

## HMAC rotation limitation — HIGH

The alias table allows multiple HMAC key versions, but the database draft does not yet implement the global write-maintenance lock, complete dual-write gate, completeness trigger or KMS integration. A partial backfill could still leave incomplete alias coverage unless all claim mutations are routed through the specified controlled workflow. See `CONTROL_PLANE_KEY_ROTATION.md`. Cross-version uniqueness is NOT yet proven.

## Approval limitation — HIGH

The database stores authenticated subject, authentication-event reference, authority snapshot, verification time, expiry and revocation. It cannot independently prove that the subject was the lawful guardian, current prior counselor or authorized destination actor. That proof must come from the identity/authorization service and be bound to the case. Caller-supplied strings are not evidence of authentication.

## Test execution status

The previous reported test counts (26 PASS / 0 FAIL and 5/5 race runs) apply to an earlier schema revision and are **superseded** by the schema and test changes in this branch. The revised SQL suite and race script have NOT been executed against the current HEAD in this session. Status: SPECIFIED / NOT RUN / NOT VERIFIED.

## Remaining Control Plane blockers

- Implement and test rotation lock, complete alias dual-write, alias completeness enforcement and KMS/HSM lifecycle.
- Implement principal-bound approval verification in the identity/authorization service.
- Define dedicated non-login function owner and workflow role grants; verify no table-owner/BYPASSRLS privileges.
- Implement inbox/outbox delivery, retries, deduplication, reconciliation and crash recovery.
- Execute fresh-database SQL tests and concurrency/crash tests against the exact reviewed SHA.
- Define measured HA/failover, RPO/RTO, split-brain and backup/restore evidence (OQ-D).
