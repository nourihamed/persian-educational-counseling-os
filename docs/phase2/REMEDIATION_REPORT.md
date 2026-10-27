> **HISTORICAL (v2, 2026-10-25).** Describes the v2 remediation of P2-H01..H05, P2-M01, P2-M03..M05, P2-L01..L02. Its statements about mutation testing, property testing and "remaining weaknesses" are superseded by `SECURITY_REMEDIATION_R01_R04.md` and the v5 evidence (`evidence/test_run_v5_2026-10-26.txt`). Kept for traceability; do not cite its test counts as current.

# Phase 2 — Remediation Report (response to independent supervisor findings on PR #8)

> **Historical remediation snapshot; not current status.** This report predates the D-025 global mobile+grade registry, D-026 fee-confirmation event schema, and the latest program-version UPDATE guard. Its historical execution labels/counts do not validate these new changes. Current gate and pending execution are tracked in PROJECT_STATE.md and docs/phase2/PR_BODY.md. Do not merge or infer approval from this report.


Status: **ready for independent re-review. NOT approved. Do not merge by the author.**
Branch: `docs/phase2-database-domain-model` (to be pushed as new commits on top of `267473b`).
Scope: Phase 2 database/domain model only. No Phase 3 work. No auth, RLS, hosting, or migrations.
Data: synthetic only (D-014).

## 1. Finding-by-finding table

Status key: **FIXED-TESTED** = changed and covered by an executed test. **FIXED-DESIGN** = changed in the design and documented, with an explicit untested boundary. **PO-DECISION** = needs the Product Owner; not decided here. **DEFERRED** = documented deferral with reason.

| ID | Verified condition (before) | Change made | Files | Test IDs | Execution | Remaining risk |
|---|---|---|---|---|---|---|
| **P2-H01** credit integrity | Balance was an ordinary writable column; the app role could set it; no atomic write path; concurrency unverified. | Single atomic function `post_credit_transaction()` (locks account, idempotent replay, overspend check, ledger + balance in one call). Runtime role has no direct INSERT/UPDATE on either table. `credit_reconciliation` view reports drift. | `phase2_schema_draft.sql`; `PHASE2_DOMAIN_MODEL.md` §5 | T2-CR-01, 03, 05, 06, 07–12, PRIV-01..09, CR-04/04b (concurrency) | **EXECUTED** (87 suite + 3 concurrency PASS) | Owner-level tampering is **detected, not prevented** (T2-CR-12). Prevention needs deployment controls (UNVERIFIED). O-2 open. |
| **P2-H02** program version lifecycle | Trigger did not compare `id`, so a published version's primary key could change; draft→superseded was not explicitly checked; FK was the only identity guard. | Identity (`id`, `tenant_id`, `program_template_id`, `version_number`, `created_by`, `created_at`) immutable in every state. Transition table enforced; superseded is terminal; published content frozen; delete only for draft; TRUNCATE blocked. | `phase2_schema_draft.sql` | T2-VER-01a–01d, 02a/b, 03, 04, 05, 06, 08, 09–14 | **EXECUTED** | Trigger can be dropped by owner (deployment-dependent). |
| **P2-H03** plan version/item immutability | Doc claimed activated versions/items are immutable; DDL enforced nothing. | `plan_versions` identity/origin immutable; `activated_at` frozen; supersession set once; `plan_items` frozen when parent activated; item ownership immutable; activated version undeletable; TRUNCATE blocked. | `phase2_schema_draft.sql` | T2-PLAN-01..13 | **EXECUTED** | Activation itself is not gated on having items (no product rule). Owner can bypass (deployment). |
| **P2-H04** missing core entities | `curriculum_nodes`, `study_sessions`, `error_records`, `exams`, `exam_results`, `class_sessions`, `assignments` absent. | All seven added with tenant-scoped composite FKs and constraints. Deferred entities listed with reasons in domain doc §3. | `phase2_schema_draft.sql`; domain doc §2–3 | T2-CURR-01, STUDY-00/01, ERR-01/02, EXAM-01, CLS-01/02, ASG-01/02, TI-06/07 | **EXECUTED** | Semantic rules not modelled: e.g., exam sum rules (none specified), class recurrence expansion, assignment status transitions. |
| **P2-H05** append-only and privilege boundary | Append-only was a trigger only; TRUNCATE not covered; no runtime-role test. | TRUNCATE forbidden by trigger (for non-FK tables) and by PostgreSQL (for FK-referenced tables, 0A000). Runtime role limited to SELECT and EXECUTE. Trigger disable forbidden to non-owner. | `phase2_schema_draft.sql`; `phase2_roles_setup.sql` (test-only) | T2-CR-13, T2-AUD-06, T2-PLAN-13, T2-VER-08, PRIV-01..05 | **EXECUTED** | Guarantees against the owner/superuser are **UNVERIFIED — deployment-dependent**. Production role provisioning is out of scope. |
| **P2-M01** version transition regression test | v1 `T2-VER-01c` changed `published_at` at the same time as status, so it could fail for the wrong reason. | Status-only illegal transition is tested alone; the reason is asserted. Helper now requires a reason substring, so a wrong-reason failure is a FAIL. | `phase2_constraint_tests.sql` | T2-VER-01c, 01d, 12 | **EXECUTED** | None known. |
| **P2-M03** domain document vs DDL | Multiple mismatches (users, subject fields, template status, actor fields, JSON names, curriculum link, review fields, credit order/actor). | Each mismatch resolved and recorded in a table with rationale (domain doc §3). `access_level` and `importance` deferred because their values are undefined. | `PHASE2_DOMAIN_MODEL.md` §3; `phase2_schema_draft.sql` | All suite tests that insert these fields | **EXECUTED** (DDL loads and tests pass); document-level review still needs a human | `access_level` and `importance` need Product Owner input before they can be added. |
| **P2-M04** audit tenant semantics | `audit_logs.tenant_id` nullable with no enforced meaning. | Explicit `scope` column; CHECK `(scope='platform') = (tenant_id IS NULL)`. Append-only. | `phase2_schema_draft.sql` | T2-AUD-01..06 | **EXECUTED** | Who may write platform events is authorization (Phase 4). |
| **P2-M05** status and evidence consistency | Doc said "32 PASS" for a schema that no longer matched; v1 evidence described v1 only. | Domain doc §9 separates seven evidence categories. v1 evidence marked superseded, kept for history. New evidence file produced from a single full run. | `PHASE2_DOMAIN_MODEL.md` §9; `evidence/test_run_v2_2026-10-25.txt` | — | **EXECUTED** (run_all.sh, exit 0) | Independent reproduction still pending. |
| **P2-L01** index coverage | Index policy not documented against actual indexes. | Mandatory vs created vs deferred indexes listed with reasons (domain doc §7). Only one extra index added (ledger history). | `PHASE2_DOMAIN_MODEL.md` §7; DDL | — | Documented; index existence verified by the DDL load | Query-driven indexes deferred until measurements exist. |
| **P2-L02** O-9 record | O-9 described as a rule, risk of being read as accepted. | O-9 kept as **proposal**; labelled in DDL comment, domain doc §8, PR body. | `PHASE2_DOMAIN_MODEL.md` §8; DDL comment | enrollment partial unique (exercised indirectly by T2-VER-07 setup) | Documented | **PO-DECISION**. |
| **Concurrency** T2-CR-04 | Not executed in v1. | Two parallel psql sessions, one credit, two students. Exactly one succeeds; the loser sees the committed balance and fails with insufficient credit. | `concurrency/run_concurrency.sh`, `session_credit.sql` | T2-CR-04 | **EXECUTED** | No mutation control: lock removal was not tried to prove the test would fail. |
| **Concurrency** T2-CR-04b | Not executed. | Two sessions with the same idempotency key: one ledger row, both succeed, balance changed once. | same | T2-CR-04b | **EXECUTED** | — |
| **Concurrency** T2-VER-02 | Not executed. | Two sessions create the same template version number: one wins, the other fails on the unique key. | `concurrency/session_publish.sql` | T2-VER-02 | **EXECUTED** | — |
| **Concurrency** T2-CR-03 (activation rollback) | Not executed. | Sequential rollback test: failure after the credit write restores balance and ledger. | `phase2_constraint_tests.sql` | T2-CR-03 | **EXECUTED** (sequential, not concurrent) | Full application-level activation (student insert plus credit) is not modelled. |

## 2. Issues I found during this remediation (and fixed)

These were real defects in my own earlier work, not reviewer findings:

1. v1's trigger did not check `id`; a published version's primary key could be changed. (Fixed under P2-H02.)
2. v1's `plan_items` and `plan_versions` had no immutability at all, although the domain document said they were immutable. (Fixed under P2-H03.)
3. The v2 trigger initially reported "illegal transition" instead of "content is immutable" for a published row whose status did not change. Found by the test suite and fixed in the trigger.
4. The enrollment guard passed silently when the referenced version did not exist in the tenant (NULL status). Found by reading the code and fixed to raise.
5. Test-harness mistakes: a multi-statement `EXECUTE` (PostgreSQL rejects it), two fixtures written as negative tests, and a test that changed the item to the version it already belonged to, so it tested the wrong rule. All fixed; the suite now fails on wrong SQLSTATE and wrong reason.
6. One test expected a trigger to fire on TRUNCATE of an FK-referenced table; PostgreSQL rejects that statement earlier (0A000). The test now asserts that exact reason, and a separate trigger test is used for tables without inbound FKs.

## 3. Changed files (repository paths)

| Path | Change |
|---|---|
| `docs/PHASE2_DOMAIN_MODEL.md` | Replaced with v2: tenancy, entity map, M03 reconciliation table, lifecycle rules, ledger design, audit scope, indexes, O-1..O-9, seven-category execution status. |
| `docs/phase2/schema/phase2_roles_setup.sql` | **New.** Test-only runtime role (`app_rt`), idempotent. Not production provisioning. |
| `docs/phase2/schema/phase2_schema_draft.sql` | Replaced with v2: triggers, function, view, privileges, new entities. |
| `docs/phase2/schema/phase2_constraint_tests.sql` | Replaced with v2: 87 checks with SQLSTATE and reason assertions. |
| `docs/phase2/concurrency/run_concurrency.sh` | **New.** Parallel sessions, three concurrency checks. |
| `docs/phase2/concurrency/session_credit.sql` | **New.** One concurrent credit operation. |
| `docs/phase2/concurrency/session_publish.sql` | **New.** One concurrent version creation. |
| `docs/phase2/run_all.sh` | **New.** One reproducible command for everything. |
| `docs/phase2/evidence/test_run_v2_2026-10-25.txt` | **New.** Output of the full run (exit 0). |
| `docs/phase2/evidence/test_run_2026-10-25.txt` | **Superseded.** Kept as history. Do not cite as current evidence. |
| `docs/phase2/PR_BODY.md` | Replaced for v2 (see the file). |
| `docs/phase2/REMEDIATION_REPORT.md` | **New.** This file. |
| `docs/phase2/PROJECT_STATE_ADDENDUM.md` | **New.** Dated addendum to paste into `PROJECT_STATE.md`. Not applied directly. |

Not changed: `SUPERVISOR_REVIEW.md` (the reviewer's record; not written by the implementation agent), `ROADMAP.md`, `DECISION_LOG.md`, `OPEN_QUESTIONS.md`, `TEST_PLAN.md`, `DATABASE.md`. Their required updates are listed in §7 rather than applied silently.

## 4. Exact commands and results

Environment: Ubuntu 24.04 sandbox, PostgreSQL 16.15 (server), `psql` from the same package. Synthetic data only.

```bash
sudo -u postgres bash docs/phase2/run_all.sh docs/phase2 > docs/phase2/evidence/test_run_v2_2026-10-25.txt 2>&1
echo "exit=$?"
```

Result: **exit 0**. Excerpt of the run (full log in the evidence file):

```
roles exit=0
schema exit=0
suite psql exit=0
PASS notices: 87 (includes 2 fixture acceptance lines)
FAIL lines:   0
...
concurrency exit=0
=== RESULT: ALL_EXECUTED_CHECKS_PASSED (exit 0) ===
```

Individual steps and their exit codes were also run separately during development. Each was run on a fresh database.

## 5. Not executed, and why

| Item | Why not executed |
|---|---|
| Lock-removal mutation test for T2-CR-04 | Not performed; would show the test catches a broken lock. Recommended before approval. |
| Property-based test over many seeds | One seeded deterministic run (seed 0.42, 60 ops) only. |
| Owner-level prevention (trigger bypass by owner) | Deployment property; not verifiable in the draft. |
| RLS, application/API authorization | Out of Phase 2 scope; Phase 4. |
| Alembic migrations, production roles, backup/restore | Out of Phase 2 scope; forbidden without authorization. |
| Alt-5 cell isolation and Q-023 hosting | Architecture and hosting gates unchanged; no hosted environment. |
| Independent reproduction | Pending the reviewer; this report is author-reported. |

## 6. Product Owner decisions still open (not decided here)

- **Q-007:** parent access model. Parent grant table and visibility are not modelled.
- **O-1..O-9** remain proposals. O-2 (cached balance vs derived-only) and O-9 (one active enrollment per student) most affect the schema.
- **D-006:** `Plan` vs `BillingPlan` naming.
- **`counselor_students.access_level` and `subjects.importance`:** value sets not defined; deferred until the owner defines them.
- **Q-020 / O-8:** retention duration and responsible persons.
- **Q-023:** hosting topology and provider gate; unchanged.

## 7. Documentation updates required (for the maintainers)

These are listed for explicit approval, not applied silently:

- `PROJECT_STATE.md`: a dated addendum is provided (`PROJECT_STATE_ADDENDUM.md`). The top-level summary should be updated by the owner.
- `TEST_PLAN.md`: T2 specifications now have IDs matching the suite; add the concurrency IDs.
- `DECISION_LOG.md`: add the proposals O-1..O-9 as proposals only.
- `OPEN_QUESTIONS.md`: add O-2 and O-9 as decision items; keep Q-007 open.
- `CHANGELOG.md`: one entry for Phase 2 remediation.
- `DATABASE.md`: it still contains the conceptual model; it should point to `PHASE2_DOMAIN_MODEL.md` for the executed design.

## 8. Self-review: remaining weaknesses

1. **The owner can bypass everything.** Triggers, the append-only guarantee, and the balance check all depend on who runs the SQL. The reconciliation view detects drift but does not prevent it. This is the most important remaining weakness and is correctly labelled UNVERIFIED.
2. **The concurrency tests are not mutation-tested.** They show the current code behaves correctly under two sessions; they do not yet prove a broken lock would be caught.
3. **Some domain rules are missing from the schema on purpose:** exam sums, assignment transitions, curriculum parent being in the same subject, and the link between plan items and activities. These need product rules first.
4. **`post_credit_transaction` is `SECURITY DEFINER`.** It runs with the owner's rights. The search path is pinned; the function's grants are restricted. Even so, this needs review in the deployment hardening phase.
5. **Evidence is from a sandbox.** It is author-reported. Independent reproduction is required before anything is considered reviewed.
6. **The v1 evidence file still exists** and shows 32 PASS. It is marked superseded, but anyone reading the directory may still quote it. Consider deleting it before the PR is reviewed.

## 9. Completion status

- Remediation of P2-H01..H05, P2-M01, P2-M03..M05, P2-L01, P2-L02 and the three concurrency checks is **complete in the draft, with the boundaries listed above**.
- Phase 2 status: **PENDING independent review.** Not approved. Phase 3 not started.
