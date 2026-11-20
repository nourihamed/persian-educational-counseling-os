# Phase 2 Exit Evidence Package — PROVISIONAL — NOT READY FOR PHASE APPROVAL

> **This is a provisional evidence package for independent review. It is not a completion declaration, not
> a phase approval and not a request to pass the gate.** It was prepared by the implementation agent, which
> may not approve its own work. Every status below is the agent's assessment, labelled with the kind of
> evidence behind it. The Supervisor decides the gate; the Product Owner separately decides progression.

**Prepared:** 2026-11-18 · **Phase:** 2 — Database & Domain Model · **Gate:** NOT READY
**Recommended gate status:** **NOT READY** (§12). **Phase 3:** not authorized. **D-014:** synthetic data only.

---

**Status (consistent across this package):**

| Item | Status |
|---|---|
| F-05 | **ACCEPTED — ARCHITECTURE REVIEW LEVEL** (`fe08a77`) |
| WS-PLAN-01 | **NOT ACCEPTED / BLOCKING** until Product Owner decisions A–E are recorded and implemented |
| WS-ISO-01 | **CRITICAL / BLOCKING** until ISO-GAP-01..03 are closed |
| Phase 2 | **NOT READY** |
| Phase 3 | **NOT AUTHORIZED** |

## 1. Exact revision

| Item | Value |
|---|---|
| Repository | `nourihamed/persian-educational-counseling-os` (private) |
| Branch / PR | `docs/product-owner-decisions-consolidation-2026-11-07` · PR #12 · **Draft, open, unmerged** |
| Last HEAD verified on GitHub | `fe08a77336557a51aca36313230b5e082e5ed3ad` (F-05 follow-up), verified 2026-11-20 by `git fetch`; F-05 accepted by the Supervisor at architecture-review level |
| This package | reconciled in the documentation-only commit **after** `fe08a77`; its SHA is reported in the handoff, not in this file |
| `main` | `5bb8e4ed07a7c770ecba7c506a1d2c278e36b6d6` — the branch is **2 commits behind**: `4004360` adds `docs/phase2/control_plane/tests/cp_30_role_privilege_tests.sql` (89 lines), `5bb8e4e` reverts it. Net difference from merge base `ba5e9d8` to `main`: **0 files**. Not merged, rebased or force-pushed (BRANCH-SYNC). |
| `SUPERVISOR_REVIEW.md` | not edited by the implementation agent |

## 2. Evidence links and CI runs

| Evidence | Where | Result | Kind |
|---|---|---|---|
| Actions run **43725323633** at `fc3416ed` | GitHub Actions | **FAILED** — database steps passed; step 28 (secret scan) failed; step 29 (register check) skipped | independent CI, reported by the Supervisor; **the agent cannot read Actions logs** |
| Actions run **43725318826** at `fc3416ed` | GitHub Actions | **FAILED** — same | as above |
| Reproduction of that failure | `fc3416ed` scanner on the exact `fc3416ed` tree | 2 findings: `workspace_operations_tests.sql:165 [iranian-mobile]`, `:171 [e164]` | local; **to be confirmed against the CI log** |
| Last Actions run the agent was told passed | run 43551722112 (job 132315462233) at `ad3bf28` | passed | independent CI; predates every batch below |
| Actions for Batches 1–7 heads (`cc8cd64` … `d6d81f8b`) | — | **never reported to the agent** | unknown |
| Local full workflow at the F-05 follow-up commit | cleared PostgreSQL 16.15, run after `git add` | **25 implementation steps passed, 1067 PASS lines, 0 FAIL**; Python verifier 15 + 6 OK; secret scan PASS; register check PASS | local, agent-executed, **not independently reproduced** |
| Actions at `467a029` (the corrections commit) | runs [44362679187](https://github.com/nourihamed/persian-educational-counseling-os/actions/runs/44362679187) (job 135008003418) and [44362668276](https://github.com/nourihamed/persian-educational-counseling-os/actions/runs/44362668276) (job 135007959995) | **success, both** | independent CI; conclusions read from the PR check runs, step logs not read by the agent |
| Actions at `b7d4b28` (Product Owner decision records) | runs 44369152676, 44369143862 | **FAILED** — register check REG-08 (WS-DOM-05 §6 row); fixed in `d75d039` | independent CI |
| Actions at `d75d039` (WS-PLAN-01 data model) | runs 44376897878, 44376886372 | **passed**, as reported by the Supervisor; reviewed NOT ACCEPTED (F-01..F-04) | independent CI |
| Actions at `8df7d5e` (F-01..F-04 remediation) | runs [44382515348](https://github.com/nourihamed/persian-educational-counseling-os/actions/runs/44382515348) (job 135078318581) and [44383233656](https://github.com/nourihamed/persian-educational-counseling-os/actions/runs/44383233656) (job 135080826317) | **success, both**; reviewed, F-05 raised | independent CI |
| Actions at `38f2561` (F-05 remediation) | runs [44693197767](https://github.com/nourihamed/persian-educational-counseling-os/actions/runs/44693197767) (job 136143681714) and [44693205261](https://github.com/nourihamed/persian-educational-counseling-os/actions/runs/44693205261) (job 136143703579) | **success, both**; logs verified by the Supervisor; F-05 not closed | independent CI |
| Actions at `bba7281` (documentation only) | runs [44724614335](https://github.com/nourihamed/persian-educational-counseling-os/actions/runs/44724614335) (job 136248754264) and [44724622970](https://github.com/nourihamed/persian-educational-counseling-os/actions/runs/44724622970) (job 136248780337) | **success, both** | independent CI |
| Actions at `fe08a77` (F-05 follow-up) | runs [44705627331](https://github.com/nourihamed/persian-educational-counseling-os/actions/runs/44705627331) (job 136184380490) and [44705633469](https://github.com/nourihamed/persian-educational-counseling-os/actions/runs/44705633469) (job 136184402186) | **success, both**; F-05 accepted at architecture-review level | independent CI |

Step numbering: GitHub's step N is the workflow's step N−2 (GitHub adds "Set up job" and "Initialize
containers"). The workflow has 29 YAML steps. GitHub numbering (YAML step + 2, for "Set up job" and "Initialize containers"): counselor isolation is step **15**, PlanItem with its race, migration and F-05 suites step **16**, secret scan step **30**, register check step **31**. The 2026-11-18 handoff said 13 and 14 for the first two; that was wrong (YAML numbering), and the Supervisor's correction is adopted.

## 3. Scope and traceability

| # | Supervisor batch | Implementation (draft SQL) | Executable tests | Agent's status |
|---|---|---|---|---|
| 1 | Source transfer freeze, database write barrier | `workspace_transfer_freeze.sql` | FRZ-01..43, WS-FRZ-BARRIER-01..04 (2 modes) | **Implemented (schema), corrected twice** — §6 D-1, D-2 |
| 2 | Clock discipline at security decisions | receipt consume, contact change, guardian effective view | CLK-01..03, RC-FRESH-01..04, CC-FRESH-01..03 | Implemented (schema) |
| 3 | Student Credit lifecycle | `workspace_schema_draft.sql` ledger guard, entitlements | CRD-01..47, WS-CRD-LOCK, WS-CRD-LAST-01..05 | Implemented (schema); **OQ-CRD-2/3 open**; commercial lifecycle deferred to Phase 21/22 |
| 4 | Assessment, exam, analysis | `workspace_assessment_exam_draft.sql` | EXM suite | Implemented (schema); **OQ-ASM-1/2 open** |
| 5 | Curriculum, plan, activity | subtopics; activity taxonomy | CUR-01..10, ACT-01..26 | **Partial** — WS-PLAN-01 decided (B); data model implemented at `d75d039`, reviewed NOT ACCEPTED, F-01..F-04 remediated at `8df7d5e`, F-05 **ACCEPTED — ARCHITECTURE REVIEW LEVEL** at `fe08a77` (`workspace_plan_items_draft.sql`; PLN-C1..C4, PLN-01..80, WS-PLN-RACE-01..03, PLN-M01..M08, F05-00..23, F05-BOOT-01..20); WS-PLAN-01 **NOT ACCEPTED / BLOCKING** pending PO decisions A–E; WS-DOM-05 decided (A), deferred to Phase 7 |
| 6 | Adversarial privilege review | role setup, ownership fixes | SEC-01..10 | Implemented (schema); produced **WS-ISO-01** |
| 7 | Contact identity, HMAC rotation, concurrency | Control Plane cp_07/cp_08 | CID-RACE-A1..B3, CID-01..05b | Implemented (schema); **PS-1..PS-4 deferred** |
| 8 | Files, notifications, retention, operations | `workspace_operations_draft.sql` | OPS-01..64 | **Partial** — delivery, erasure completeness and authorities open |
| — | 2026-11-18 corrections | `workspace_counselor_scope_draft.sql`, scanner, workflow, register | ISO-C1..54, SEC-REPO-01..05, REG-01..08 | boundary implemented; **caller binding not** |

Requirement-to-test traceability is maintained per batch in `TEST_PLAN.md` and per area in
`PHASE2_EXIT_CRITERIA.md`.

## 4. Implemented · partial · deferred · not implemented

**Implemented at schema level, with local executable evidence** (GitHub Actions success at `467a029` and, for the
WS-PLAN-01 model and its remediations, at `d75d039`, `8df7d5e`, `38f2561` and `fe08a77`):
the transfer freeze record, write barrier on all 32 student-scoped tables (both sides of an UPDATE, forward-only
owner key) and in-flight transaction barrier; clock discipline at every security decision point found;
the Student Credit ledger with one authoritative guard and the non-negative-balance invariant; the assessment
model; curriculum subtopics; the activity taxonomy and class participants; privilege hygiene (definer ownership,
pinned search paths, no PUBLIC table privileges); contact identity serialization against rotation and against
the ownership switch; file-object immutability; notification recipient isolation at insert, payload hygiene and
fencing; legal-hold integrity; immutable retention policy versions; the fail-closed disposition gate;
TRUNCATE guards; the counselor-isolation **boundary**.

**Partial:** counselor-to-counselor isolation (boundary yes, caller binding no); retention (mechanism yes,
periods/authority/completeness no); notifications (insert-time yes, delivery-time no); the transfer freeze
(database half yes, controller and thresholds no); Student Credit (no post-period disposition, no duration
source — production activation is fail-closed); guardian authority (mechanisms yes, matrix values no).

**Deferred by decision:** PS-1..PS-8 (Platform Security); commercial credit lifecycle (Phase 21/22);
notification channels (Phases 18–20); operational topology, RPO/RTO, failover (OQ-D).

**Not implemented:** any API, service, worker, job runner, object store, export, backup or restore tooling
(`backend/`, `frontend/`, `scripts/`, `tests/` hold only `.gitkeep`); normalized PlanItem model; curriculum
edition model; manager explicit-permission vocabulary; any production migration.

## 5. Findings and severity

| Finding | Severity | State |
|---|---|---|
| **WS-ISO-01** — counselor-to-counselor isolation fails open inside a Workspace | **CRITICAL (design), BLOCKING** | boundary implemented; caller binding needs a Platform Security decision |
| WS-PLAN-01 — plan content was opaque JSON | HIGH, BLOCKING until verified | decided B; model at `d75d039` NOT ACCEPTED; F-01..F-04 remediated at `8df7d5e`; **F-05 accepted at architecture-review level (`fe08a77`); WS-PLAN-01 as a whole not accepted, still BLOCKING**. Open within it: who may provision or assume the privileged identities (Platform Security / Operations); who may record transitions (needs WS-ISO-01 caller binding), whether drafts carry status, whether an empty plan may be published, the transition graph — all fail closed |
| WS-DOM-05 — curriculum edition/ownership model | MEDIUM, **LATER_PHASE** | decided A: deferred to Phase 7; four governance questions open |
| WS-DOM-02 — governance commands lack verifiable authority | HIGH, fail-closed | depends on Issue #13 / PS-* |
| M-05 — duplicate JSON object keys not rejected at raw ingress | MEDIUM, **NON_BLOCKING_TECHNICAL_DEBT** | defined by the Supervisor 2026-11-18; not implemented (needs a raw-ingress layer) |
| M-06 — no single machine-readable canonicalization vector source for SQL and Python | MEDIUM, **NON_BLOCKING_TECHNICAL_DEBT** | defined by the Supervisor 2026-11-18; not implemented |
| REPO-HIST-CONTACTS — contact-shaped fixtures in Git history | LOW | Product Owner decision |
| All others | see register §6 | 19 held fail-closed, 7 later-phase |

## 6. Known defects and remediation evidence

Every defect below was found in the project's own earlier work. Each is recorded rather than quietly amended.

| ID | Defect | Found | Fix | Regression / control |
|---|---|---|---|---|
| D-1 | Write barrier covered 26 tables by column scan; five per-student tables reached **indirectly** (`student_plan_versions`, `test_responses`, `guardian_permissions`, `guardian_link_events`, `guardian_permission_events`) were unprotected | Batch 5 | resolution paths per kind; 26 → 31 | FRZ-01b (catalog audit, fails by name), FRZ-01c, FRZ-18b/18c |
| D-2 | Write barrier read only the **NEW** side of an UPDATE: a frozen student's file and study session were moved to another student, and a file orphaned with `student_id = NULL`, all **accepted** | Batch 8 | assert OLD and NEW; owner key forward-only | FRZ-38..43; reverting the function fails FRZ-38 (46 → 40) |
| D-3 | Notification recipient rule (Batch 8) accepted **any active member** for a notification about **any student** — a cross-counselor disclosure path | 2026-11-18 | member must reach the student | OPS-13c, ISO-43; restoring the old rule fails OPS-13c |
| D-4 | Secret-scan allowlist matched the whole line: "synthetic" anywhere on a line exempted every pattern, including PEM | 2026-11-18 (Batch 7 code) | allowlist matched against the matched text; never for PEM | SEC-REPO-05 regression cases |
| D-5 | Secret scan claimed history coverage but checked file **names** only | 2026-11-18 (Supervisor) | SEC-REPO-03 scans every historical blob's content; shallow clone fails closed | planted-then-deleted PEM found; shallow clone fails |
| D-6 | Batch 8 reported a local scan pass that CI failed | 2026-11-18 (CI) | scan was run before `git add`; SEC-REPO-04 now warns on untracked files | runs 43725323633/43725318826 |
| D-7 | Notifications had no student reference, so the transfer fence could not apply | Batch 8 | `student_id` added; barrier 31 → 32 | OPS-24, OPS-45 |
| D-8 | `legal_holds` polymorphic reference had no integrity and the table was inert | Batch 8 | entity registry, immutability, one-way release | OPS-30..39, OPS-51 |
| D-9 | SECURITY DEFINER function owned by a superuser | Batch 6 | reassigned; search path pinned | SEC-01 |
| D-10 | Three security decisions read a transaction-start clock | Batch 2 | `clock_timestamp()` after the lock | CLK-01..03, RC-FRESH, CC-FRESH |
| D-11 | A credit reversal could name a different student; a weaker duplicate ledger guard was reachable | Batch 3 | one authoritative guard | CRD-39..47 |
| D-12 | BRANCH-SYNC was falsely "corrected" for several batches (stale `base.sha` read) | Batch 6 | retracted; measured with the branch listing | register BRANCH-SYNC |

**What this list implies.** Three consecutive reviews (Batches 5, 8 and 2026-11-18) found defects in work
already reported as done. A fourth is not unlikely, and nothing in this package should be read as a claim of
completeness.

## 7. NOT-RUN tests

- **Production provisioning of the privileged plan identities**, a non-superuser provisioning procedure, and
  production superuser control and audit — undecided (Platform Security / Operations).
- **Actions results for Batches 1–7** were never reported to the agent.
- **Counselor isolation as each counselor's own database identity** — cannot exist until WS-ISO-01's caller
  binding is decided.
- **Any API, IDOR, uniform-404, background-job tenant-context, file-download or notification-delivery test** —
  no API, job runner or worker exists.
- **Erasure completeness** across objects, exports, caches, indexes, replicas and backups; restore-time
  suppression (OPS-RETENTION-SCOPE).
- **Backup, restore, failover, load and performance tests** (OQ-D; later phases).
- **Rotation recovery across a process crash**; production key management (PS-1..PS-4).
- **Transfer controller end to end**, including freeze timeout and recovery (OQ-E).
- **Planning invariants** (no conflicts, no impossible workload, no duplicates) — no planning engine exists;
  the normalized items make them expressible, but nothing schedules.
- **Acting as a privileged plan identity outside a superuser test session** — by design impossible now (F-05);
  the production provisioning of these identities is undecided.
- **Plan writes by a real counselor or student identity** — no application identity may write plan items or
  transitions until caller binding exists (WS-ISO-01). Only the synthetic writer is tested.
- **A production migration** of historical plan versions at volume, and its rollback (`WS_PLAN_01_MIGRATION_NOTES.md` §4).

## 8. Unresolved items and owners

32 items, each classified in `docs/phase2/UNRESOLVED_ITEM_REGISTER.md` §6 with kind, whether code can resolve
it, recommended gate impact and closure evidence; JSON and Markdown agreement is checked row by row (REG-08).

| Recommended gate impact | Items |
|---|---|
| **BLOCKING** | WS-ISO-01, WS-PLAN-01 (implemented, pending verification), PR-8-11-DISPOSITION |
| Non-blocking technical debt | M-05, M-06 (defined by the Supervisor 2026-11-18) |
| Non-blocking, held fail-closed | Q-007, Q-020, OQ-CRD-2, OQ-CRD-3, OQ-SAGA-1, OQ-SAGA-2, OQ-ASM-1, OQ-ASM-2, PS-1, PS-2, PS-3, PS-5, PS-8, WS-DOM-02, TRANSFER-EXC-AUTH, BRANCH-SYNC, OPS-HOLD-AUTH, OPS-DISP-AUTH, REPO-HIST-CONTACTS |
| Later phase | WS-DOM-05 (Phase 7, by decision), OQ-D, OQ-E, PS-4, PS-6, PS-7, OPS-RETENTION-SCOPE, OPS-NOTIF-DELIVERY |

Owners: Product Owner (most), Platform Security (PS-*, WS-ISO-01 caller binding, WS-DOM-02, OQ-SAGA-1),
Supervisor (M-05/M-06 closure review), operations owner (OQ-D, OQ-E, OPS-RETENTION-SCOPE). **Not all are decisions only:**
13 can be resolved partly or wholly by code once their decision is made — including WS-ISO-01, WS-PLAN-01,
WS-DOM-05, OQ-E, PS-3, PS-8, WS-DOM-02, OPS-RETENTION-SCOPE and OPS-NOTIF-DELIVERY.

## 9. Architecture, database, API, authorization and tenant-isolation assessment

- **Architecture.** Two database domains — Control Plane (global identity, ownership, transfer cases, outbox)
  and one Workspace database per Workspace (educational data, credit ledger, inbox projection) — with no
  cross-database transactions or foreign keys and no claim of distributed atomicity. Consistent with the
  approved Workspace-centric model.
- **Database.** Integrity is enforced in the database where it can be: composite ownership-bound foreign keys,
  deferred constraint triggers, append-only ledgers (now including TRUNCATE), catalog-driven guards whose
  allowlists carry per-entry reasons. **Limitation, recorded (SEC-08):** every guard is a trigger or a CHECK,
  so the table owner and a superuser are not contained.
- **API.** None exists. API authorization exists as a contract only, and is not evidence.
- **Authorization.** Role and grant hygiene is tested. Governance commands have no verifiable authority yet
  (WS-DOM-02), and are uncallable by application roles meanwhile — fail-closed.
- **Tenant isolation.** **Per-Workspace:** implemented and tested (separate database, roles, CONNECT
  boundaries, cross-database denial). **Per-counselor inside a Workspace: NOT enforced — fails open**
  (WS-ISO-01, CRITICAL). The boundary definition is implemented and tested; the database cannot tell which
  counselor is calling.

## 10. Documentation consistency

Reconciled on 2026-11-18: `PROJECT_STATE.md` (current block rewritten; the stale Batch 1 header and the
"Actions not available" claim replaced with the actual CI result; the Batch 8 entry corrected by a dated
note rather than rewritten), `PHASE2_EXIT_CRITERIA.md`, `UNRESOLVED_ITEM_REGISTER.md` and its JSON,
`CHANGELOG.md`, `TEST_PLAN.md`, `OPEN_QUESTIONS.md`.

**Known inconsistencies left for review:**
- Root `ROADMAP.md`, `ARCHITECTURE.md`, `DATABASE.md`, `API.md` and `SECURITY.md` were last reconciled on or
  before 2026-11-10 and do not describe Batches 1–8. `ROADMAP.md` now points to `PROJECT_STATE.md` for current
  status, but its body is not re-reconciled.
- Several dated entries in `PROJECT_STATE.md` and `TEST_PLAN.md` carry the numbers true at their date (26, 27,
  31 guarded tables; 476, 653, 749, 808 PASS lines). They are history, deliberately not rewritten; the current
  numbers are at the top of each file.
- The PR #12 description on GitHub is not updated by the agent (no write access); replacement text is supplied
  in the handoff.

## 11. Technical debt and migration risks

- **The drafts are not migrations.** Turning 25 draft SQL files with interdependent load order into Alembic
  migrations is unplanned work; the load order is currently encoded only in the CI workflow.
- **WS-ISO-01 enforcement** changes the result of every query run as the runtime role and needs
  supporting indexes; it is a coordinated change across every suite, not a patch (proposal §7).
- **Legacy `plan_content` JSON** (WS-PLAN-01): historical rows are backfilled as `legacy_json` and stay readable; only the migration identity may create one. Whether legacy content is ever converted into items is a Product Owner question (D-014: no real data exists).
- **Trigger-heavy integrity** depends on triggers staying enabled; a maintenance script run as the owner can
  disable them (SEC-08).
- **Historical fixtures in Git** (REPO-HIST-CONTACTS) stay unless history is rewritten.
- **Test-suite cost:** 25 sequential database steps with fresh databases each; acceptable now, but some race
  suites rely on process coordination that will need care in parallel CI.
- **Evidence gap:** Actions results for the Batch 1–7 heads were never reported; known results since `ad3bf28`: `fc3416ed` failed, `467a029` and `b519080` succeeded, `b7d4b28` failed (REG-08), `d75d039` passed.

## 12. Recommended gate status

**NOT READY.** Recommended by the implementation agent, for the Supervisor's independent decision:

1. **WS-ISO-01 is CRITICAL and fails open.** A core product security requirement is not enforced by the
   database, and the fix needs a decision that has not been made.
2. **CI passed at every WS-PLAN-01 commit, and the Supervisor still found F-01..F-05.** CI is evidence for draft SQL and synthetic suites, not for the gate.
3. **F-05 is accepted at architecture-review level; WS-PLAN-01 as a whole is not accepted.** Production writer or migrator privileges and production runtime plan-item writes are not approved. Curriculum editions are deferred to Phase 7 by decision (WS-DOM-05).
4. **M-05 and M-06 are now defined** as MEDIUM technical debt, non-blocking, and are not implemented.
5. **PR integration is unresolved** (PR #8–#11; the branch is behind `main`).

What would move it, in order: the WS-ISO-01 caller-binding decision and its
enforcement; independent review of the WS-PLAN-01 remediation; the PR
disposition. **None of these can be closed by the implementation agent alone, and none is claimed.**
