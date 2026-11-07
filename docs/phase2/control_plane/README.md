# Control Plane — draft schema, tests and boundaries (PR #12 branch)

**Status:** DRAFT. Not a production migration. Not approved. Phase 2 gate: NOT READY pending independent Supervisor review.
**Synthetic data only (D-014).** No real student or customer data. No production KMS integration (OQ-B: Platform Security owns keys; none are stored here).

## Execution order (fresh PostgreSQL 15+ database, owner role, `ON_ERROR_STOP=1`)
1. `schema/cp_01_schema_draft.sql` — tables, global identity index, ownership generation, transfer cases, approvals, idempotency, outbox, append-only history.
2. `schema/cp_02_switch_function_draft.sql` — atomic ownership switch (`switch_student_ownership`).
3. `schema/cp_03_transfer_transitions_draft.sql` — transfer state-transition table and guards.
4. `tests/cp_10_constraint_tests.sql` — constraint, workflow and fencing tests.
5. `tests/cp_20_race.sh <db>` — two-session global identity race (run on a fresh DB where steps 1–3 and the Workspace rows it needs exist).

## Database boundary
- **This is the Control Plane database only.** It contains no educational records, no counselor-private notes, no credit ledgers.
- **No cross-database foreign keys** exist. `workspace_id` values are opaque UUIDs validated by the workflow, not by PostgreSQL. A Workspace database cannot enforce global ownership or global uniqueness.
- The switch is **one transaction in this database**. It does not, and cannot, include any Workspace database.

## Invariant enforcement classes (required by the reconciliation brief)
| Invariant | Enforced by | Where |
|---|---|---|
| Global mobile(HMAC)+grade uniqueness for holding claims (D-025) | Database (partial unique index) | cp_01 |
| One claim-holding enrollment per student platform-wide (PO-4) | Database (partial unique index) | cp_01 |
| Grade limited to grade_10/11/12 | Database (CHECK) | cp_01 |
| HMAC is exactly 32 bytes | Database (CHECK) | cp_01 |
| No plaintext mobile column in this database | Database test (catalog check) | cp_10 CP-PRIV-01 |
| Platform Admin cannot be a transfer initiator (OQ-A) | Database (CHECK on initiator_kind) | cp_01 |
| One open transfer per student | Database (partial unique index) | cp_01 |
| Exactly one approval of each kind per case | Database (UNIQUE) | cp_01 |
| All three cumulative approvals before switch | Database (function precondition, same transaction) | cp_02 |
| Owner/generation compare-and-swap (fencing) | Database (function, row locks, same transaction) | cp_02 |
| Legal transfer state transitions only | Database (trigger + table) | cp_03 |
| Transfer starts in `requested` | Database (trigger) | cp_03 |
| Ownership history append-only | Database (trigger) | cp_01 |
| Caller identity and authority (who may call the switch) | **NOT database-enforced.** Phase 4 identity; only a privilege boundary (REVOKE FROM PUBLIC) is drafted | — |
| Guardian consent validity, scope and expiry | **NOT database-enforced.** Application/workflow + Phase 4 identity; evidence reference only | — |
| Destination capacity and credit checks | **NOT database-enforced.** Workspace-side checks; capacity separate from credit (PO-3, OQ-F3) | — |
| Non-reuse of an approval across cases | **NOT database-enforced** (approval rows are per case; reuse of an evidence_ref is a workflow check) | — |
| Freeze boundary, timeouts, recovery thresholds | **Not designed yet** (OQ-E details open) | — |

## Proposed rules that need Product Owner confirmation
- Which claim states hold the global key: this draft holds `active` and `transfer_pending`; `ended` and `archived` release it (cp_01 comment; test CP-GU-07).
- Recovery paths `failed_recoverable → staging | cutover_frozen` and `manual_intervention` transitions (cp_03 comment).
These are marked PROPOSED; they are not decisions.

## Test execution — recorded for this exact draft set
Run on: PostgreSQL 16.15 (Ubuntu), fresh database `p_cp`, owner role, `ON_ERROR_STOP=1`, synthetic data.
- `cp_01`, `cp_02`, `cp_03` applied: exit 0 each.
- `cp_10_constraint_tests.sql`: exit 0; **26 PASS, 0 FAIL**.
- `cp_20_race.sh`: **5 of 5 runs PASS** (each on a fresh database; exit A=0, B=3, active claims = 1, B failed on `enrollment_claims_global_identity`).
Not executed: independent reproduction; Workspace-side tests; cross-database workflow tests; crash/recovery tests; outage (fail-closed) tests; load/concurrency beyond two sessions.

## Known limitations
- The Control Plane cannot prove that a caller is the guardian, the prior counselor or the destination counselor; those proofs are Phase 4 identity inputs.
- The switch function's privilege boundary is drafted (no PUBLIC EXECUTE); the production role design is deployment work.
- Mobile encryption and HMAC keying are designed, not implemented. Rotation/dual-index migration is not yet drafted as executable SQL.
- Registry topology, RPO/RTO, failover and split-brain handling are open (OQ-D).
