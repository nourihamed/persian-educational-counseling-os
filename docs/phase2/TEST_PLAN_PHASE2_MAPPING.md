# Phase 2 test mapping (status per ID, as of evidence v5, 2026-10-26)

Status key: PASS = executed and passed in the cited evidence. FAIL = executed and failed. KNOWN-RESIDUAL = executed; a limitation remains. BLOCKED = cannot run here. NOT RUN = not executed. SPEC-ONLY = specification without an executable test.
Evidence file: `docs/phase2/evidence/test_run_v5_2026-10-26.txt` (author-executed). "Independently reproduced" is **not** claimed for any row.

| Test family | Invariant | Where | Status (v5) | Limitation |
|---|---|---|---|---|
| T2-TI-01..08 | Cross-tenant references rejected (composite FKs, NULL tenant) | `phase2_constraint_tests.sql` | PASS | Owner can drop constraints (deployment). |
| T2-VER-01a..14 | Published version immutable; transitions enforced; identity immutable; enrollment pinned | same | PASS | Owner bypass (deployment). |
| T2-PLAN-01..13 | Plan version/items frozen after activation; one active version per plan | same | PASS | Owner bypass (deployment). |
| T2-TEST / STUDY / ERR / REV / EXAM / CLS / ASG / CURR / AUD | Sum rule, time order, error labels, duplicate review and exam results, class and assignment rules, audit scope | same | PASS | Semantic rules beyond the DDL are not modelled. |
| T2-CR-01..13 | Ledger constraints, function-only writes, insufficient credit, reconciliation, rollback, owner-level truncate blocked | same | PASS | Owner tampering detected, not prevented. |
| T2-R01-01..18 | Authorization matrix; tenant substitution denied; no direct table writes; default-deny | same | PASS | Payment and human identity not verified by the database. |
| T2-R02-00..08 | Each canonical payload field rejects replay; identical replay one effect | same | PASS | Only the six listed fields. |
| T2-R03-01..08 | PUBLIC has no EXECUTE; runtime roles not superusers; no CREATE in public or schema; hostile search_path and hostile function ignored | same | PASS | Owner remains trusted by design. |
| T2-PRIV (retired v2 set) | Superseded by T2-R01 | — | SUPERSEDED | — |
| T2-CR-04 | Concurrent activation, one credit: one winner, loser reason verified | `concurrency/run_concurrency.sh` | PASS | Two-session race only. |
| T2-CR-04b | Concurrent identical canonical payload: one row | same | PASS | — |
| T2-CR-04c | Concurrent same key, different payload: rejected with reason | same | PASS | — |
| T2-VER-02 | Concurrent same version number: one winner | same | PASS | — |
| Lock mutant | Lock removal is detected | `concurrency/run_mutation.sh` | DETECTED | Detected by reason and idempotency; balance held by CHECK. |
| AUTH-1..4 mutants | Binding and permission checks detect weakened identity | `mutation/run_mutants.sh` | DETECTED ×4 | Targeted, not exhaustive. |
| IDEM-kind..reason mutants | Each canonical field detected | same | DETECTED ×6 | Targeted, not exhaustive. |
| Property, 12 seeds | No negative balance; drift 0 | `mutation/run_property_seeds.sh` | PASS ×12 | One property; not an exhaustive model. |
| Controlled faults ×3 | Runner returns non-zero and never reports success | evidence `controlled_fault_*_v5` | PASS (runner behaviour) | Copies of the suite only. |
| Independent reproduction | Same results by another reviewer | — | NOT RUN | Pending reviewer. |
| Owner/superuser bypass | Cannot bypass | — | KNOWN-RESIDUAL / BLOCKED | Deployment-dependent. |
| RLS, API/app authorization, production roles, migrations, backup/restore, Alt-5, hosting | — | — | NOT RUN / SPEC-ONLY | Out of Phase 2 scope. |
