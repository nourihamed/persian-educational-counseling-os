## Phase 2 — Database & Domain Model (draft for independent review)

Authorized by Issue #7. **Not approved. Do not merge by the author.**

### Scope completed
- Domain model and tenant ownership rules (`docs/PHASE2_DOMAIN_MODEL.md`).
- ERD and entity specifications, including keys, constraints, nullability, lifecycle and indexes.
- Versioning for `ProgramTemplate`/`ProgramVersion` and `Plan`/`PlanVersion` (D-008, D-012).
- Credit ledger design: append-only `credit_transactions`, cached balance with `balance >= 0`, idempotency key, sign rules.
- DDL draft (`docs/phase2/schema/phase2_schema_draft.sql`) — **not a migration**.
- Constraint test suite (`docs/phase2/schema/phase2_constraint_tests.sql`) and its run evidence.

### Verification actually run
- PostgreSQL 16 fresh database; DDL applied with `ON_ERROR_STOP=1`.
- Constraint suite: **32 PASS, 0 FAIL**, exit 0. Log: `docs/phase2/evidence/test_run_2026-10-25.txt`.
- Synthetic data only (D-014).

### Not executed (explicit)
- Concurrent credit activation (T2-CR-04), end-to-end activation rollback (T2-CR-03), property-based balance reconciliation, concurrent publish (T2-VER-02), all API/app-layer authorization tests.
- No runtime security claim. Alt-5 cell isolation, RLS and hosting are unchanged and unverified. Q-023 remains open.

### Open decisions and dependencies
- **Q-007 (Parent access model) is open.** The parent access grant table is intentionally not modelled. Parent-specific visibility is blocked until the Product Owner decides.
- O-1 to O-9 are proposals in the design document. None is accepted.
- D-006 (BillingPlan naming) is still proposed.

### Requested review focus
- Composite tenant FKs and whether any tenant-owned table is missing one.
- Immutability trigger for published `program_versions` and the status-transition rule.
- Credit ledger invariants and the choice of cached balance (O-2).
- Whether O-9 (one active enrollment per student) is the intended product rule.

Phase 2 gate: **PENDING independent review.** This PR does not declare Phase 2 approved.
