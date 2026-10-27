## Phase 2 — Database & Domain Model: remediation and evidence (draft for independent re-review)

Authorized by Product Owner (Issue #7). **Not approved. Not to be merged by the author.** Phase 3 is not started. No real student data.
Reviewed HEAD before this change: `e04ef9f`. Evidence: `docs/phase2/evidence/test_run_v5_2026-10-26.txt`.

### What this PR contains
- Domain model and DDL draft (PostgreSQL): tenant-scoped entities, composite tenant foreign keys, version lifecycle, plan immutability after activation, credit ledger with a single write path `post_credit_transaction()`, append-only ledger and audit logs.
- Authorization of credit operations via `session_user` against tenant bindings and kind permissions (test model; see the report for the matrix and limits).
- Canonical idempotency payload `(kind, amount, student_id, order_id, actor_id, reason)`, NULL-safe.
- `SECURITY DEFINER` boundary: pinned `search_path`, schema-qualified objects, no PUBLIC execute, least EXECUTE, runtime roles not superusers.
- Hardened test runner: checks every required setup step, classifies failures (environment / script-or-test / other), skips dependent stages, reports cleanup failures, exits non-zero on any failed stage.

### Verification (author-reported; not yet independently reproduced)
Environment: PostgreSQL 16.15, fresh databases, synthetic data only (D-014). One full run of `docs/phase2/run_all.sh` → **exit 0**.

| Check | Result |
|---|---|
| Constraint, privilege and authorization suite | **111 test cases PASS**, 2 fixture acceptances PASS, **0 FAIL** |
| Concurrency on canonical schema (T2-CR-04, 04b, 04c, T2-VER-02) | **PASS** |
| Lock-removal mutant | **DETECTED** |
| Authorization and idempotency mutants | **10 of 10 DETECTED** (AUTH-1..4; IDEM-kind, amount, student, order, actor, reason) |
| Canonical restoration after mutants | **PASS** (schema hash unchanged) |
| Property test, explicit seeds | **12 of 12 PASS** — seeds 0.11, 0.22, 0.33, 0.44, 0.55, 0.66, 0.77, 0.88, 0.12, 0.23, 0.34, 0.45; no negative balance, drift 0 |
| Controlled faults (3) | **each returns exit 1**, no success summary |

Controlled-fault logs: `controlled_fault_env_down_v5_2026-10-26.txt`, `controlled_fault_sqlstate_v5_2026-10-26.txt`, `controlled_fault_mutant_target_v5_2026-10-26.txt`.

Mutation coverage is targeted, not exhaustive. A detection means the suite failed on the mutant; it is not proof of general security. Each mutant stops at its first failing test (the suite uses `ON_ERROR_STOP`).

### Not executed or not established
- Independent reproduction by a reviewer (this run is author-executed).
- Mutants for constraint-level checks (non-null tenant, version transition table) and for bindings specific to `issuer_rt` / `adjuster_rt`.
- Multi-seed runs of the concurrency tests (only the property test uses seeds).
- Owner/superuser bypass: the table owner can bypass triggers and grants. This is a deployment property and is **unverified**.
- RLS, application/API authorization, production roles, migrations, backup/restore, Alt-5 cell isolation, hosting. None is claimed.

### Known residual risks
- Payment verification and human identity mapping are outside this database design (Phase 22 and Phase 4). `issuer_rt` is a role; the database cannot prove a payment.
- No runtime read-path tenant isolation is proven by the credit-write tests.
- The test tenant-binding model is not the approved Alt-5 deployment topology (D-020).

### Open decisions (not decided by this PR)
- **Q-007** parent access model (open; parent grant table not modelled).
- **O-2** cached vs derived balance; **O-9** one active enrollment per student; **O-10** (proposal) purchase issuer, refund–order linkage, adjustment approval.
- **D-006** `Plan` vs `BillingPlan`; **access_level** and **importance** value sets; **Q-020 / O-8** retention and ownership.
- **Q-023** hosting topology and provider gate (hard pre-hosting gate).

Phase 2 gate: **PENDING independent review.** This PR does not declare Phase 2 approved.
