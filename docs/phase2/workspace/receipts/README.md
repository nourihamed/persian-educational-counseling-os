# Governance proof receipts and the Governance Authorization Adapter (Issue #13) — DRAFT

**Status:** synthetic PostgreSQL draft + executable tests. NOT production. NOT approved. Phase 2 gate: NOT READY pending independent Supervisor review. Synthetic data only (D-014).

## Accepted architecture (Product Owner, Issue #13)
- **A1 External Independent Verifier:** a separate service. Its only DB identity is `ws_<key>_verifier_rt`, which may INSERT receipts and nothing else.
- **B3 Combined trust:** (1) mutually authenticated service channel (mTLS or approved equivalent — NOT implemented here) and (2) an independently verifiable signed assertion. mTLS authenticates the channel; it does not prove authorization claims.
- **C Deferred (not approved, not implemented):** signature algorithm, algorithm allowlist values, issuer-key registry, key provisioning/rotation/revocation, clock-skew allowance, certificates/trust store, production credentials, deployment topology.

## Files (execution order)
1. `../workspace_schema_draft.sql`, `../workspace_activation_transactions.sql`, `../workspace_governance_events_draft.sql`, `../workspace_roles_setup_draft.sql` (`-v workspace_key`)
2. `receipt_01_schema_draft.sql` — receipt table, guard trigger (binding columns immutable, never deleted, only registered→consumed/revoked), adapter allowlist.
3. `receipt_02_roles_draft.sql` (`-v workspace_key`) — `ws_<key>_verifier_rt`, `ws_<key>_governance_adapter_rt`; grants.
4. `receipt_03_consume_function_draft.sql` (`-v workspace_key`) — atomic command boundary.
5. `tests/receipt_10_tests.sql` (`-v workspace_key`) — 44 notices (see evidence).
6. `tests/receipt_20_race.sh <db> <key> <dir>` — concurrency RR-01, RR-02.
7. `verifier_interface/verifier_contract.py` + `verifier_interface/tests/test_verifier_contract.py` — verifier boundary (production fail-closed; test double only).

## What the database enforces (executed by the tests)
- Runtime, worker and exporter: no receipt table privilege, no consume execution (RC-02..04, RC-31).
- Verifier: INSERT only; cannot read, update, delete, consume, or write governance events (RC-01, RC-05, RC-31).
- Adapter: consume execution only; no table privilege; cannot register, read the table, call the append function directly, or assume the governance owner (RC-06, RC-31).
- Storage refusals: non-`verified` outcome, guardian-family aggregates (Q-007), expiry ≤ not-before, duplicate assertion and duplicate nonce digest (RC-07..RC-11).
- Atomic consume: exact actor, action, aggregate, target, role/permission, scope digest, policy, idempotency key and payload digest must match (RC-13..RC-19). Validity window and revocation (RC-21..RC-23). Single use with idempotent identical retry returning the original event (RC-24..RC-26). Idempotency key already used by another event refused (RC-27). Failed append leaves the receipt registered (RC-28). Inactive target fails closed (RC-29). Cross-Workspace refused (RC-20).
- Concurrency: one winner for the same assertion; exactly one effect for the same receipt and key under two sessions (RR-01, RR-02).

## What the database does NOT prove (explicit)
- It does **not verify any signature**. `verifier_outcome='verified'` is a recorded input from the external verifier, not proof. The consume function checks that the presented bindings equal the recorded ones; it does not recheck the signature.
- It does not authenticate the mTLS channel or the human actor. `authn_event_ref` and `authority_ref` are opaque references.
- The `expires_at` / `not_before` check uses the database clock with **no** skew allowance (Decision C deferred).
- Revocation source and membership-revocation freshness across API, export, worker and notification handoffs are **NOT IMPLEMENTED** (no service integration exists). DB-only tests do not prove end-to-end freshness.
- Owner/superuser bypass remains deployment-dependent.

## Defect found and fixed in the existing governance draft
`workspace_governance_events_draft.sql`: payload validations used `jsonb_typeof(...) <> 'string'` and `length(...)=0` without NULL handling. A payload missing `role_key` / `permission_key` / `resource_scope` evaluated to NULL and was NOT rejected by the validation; it fell through to the table NOT NULL constraint with the wrong error class (23502 instead of 22023). Fixed with `COALESCE` in six comparisons. The existing governance suite (`tests/workspace_governance_event_tests.sql`) passes after the fix (exit 0, 10 notices).

## Test-only verifier double
`verify_test_double` accepts a test-supplied `test_signature_ok` flag. Passing it proves only the non-cryptographic rules. `verify_production` always refuses (`VerificationFailClosed`).

## Not run / blocked
- GitHub Actions run for this commit: NOT RUN by the implementation agent (no push access from this environment). The workflow step was added and its YAML was parsed locally.
- Full RBAC role-grantability matrix positive/negative cases beyond the receipt-related privileges: NOT RUN in this task.
- Revocation freshness across service handoffs: NOT IMPLEMENTED.
