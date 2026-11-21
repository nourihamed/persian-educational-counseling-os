# Phase 2 — authoritative gap matrix

**Prepared:** 2026-11-20 by the implementation agent, from the repository itself (SQL, tests, workflow, Git), not from
status documents alone.

**Baseline**

| Item | SHA |
|---|---|
| PR head | `bba728193d8d044bb65c4efe3c33662e8ad686c2` |
| Latest implementation commit | `fe08a77336557a51aca36313230b5e082e5ed3ad` |
| `main` | `5bb8e4ed07a7c770ecba7c506a1d2c278e36b6d6` |
| Merge base | `ba5e9d8a9577e5b87e2fc27caaf0bfb07f929114` |

**Gate:** Phase 2 NOT READY. Phase 3 not authorized. D-014: synthetic data only.

**How to read it**
- **Status:**
  - **DONE (schema)**: implemented in draft SQL and covered by executed tests.
  - **PARTIAL**
  - **OPEN**
  - **NOT IMPL.**
  - **DEFERRED**: by a recorded decision.
- **No status here is a gate decision.** Closure is the Supervisor's call.
- **"Evidence"** names test IDs and the GitHub workflow step (YAML step + 2).
- **Blocking** is the agent's recommendation.

## 1. Matrix

| ID | Requirement | Current implementation | Evidence | Risk | Missing work | Owner | Blocking | Acceptance criteria | Regression tests |
|---|---|---|---|---|---|---|---|---|---|
| G-01 | Workspace, Organization, Branch, CounselorAssignment | Tables with composite keys; assignment accepted/active states | WS schema suite (step 17), ISO-01..09 (step 15) | low | Branch scoping of access not defined | Developer / PO | no | branch rules defined or deferred | schema suite |
| G-02 | Identity, membership, role, permission (WS-DOM-02) | Governance event ledger, projection, receipt boundary, grantability matrix (PO 2026-11-10) | step 18, steps 23–24 | HIGH while no trusted adapter | trusted adapter; enforcement of grantability; API tests | Developer + Platform Security (PS-1..4) | no (fail-closed) | authenticated governance command end-to-end | GOV, RC, VER suites |
| **G-03** | **Counselor-to-counselor isolation (WS-ISO-01)** | 2026-11-20: decision B with a test-only key — verified principal assertions; RLS ENABLE+FORCE on every student-scoped table bound to the verified principal | ISO-C1..54 (as owner) + ISO-P00..P30, ISO-RLS-01..09, ISO-RLS-C3, ISO-P-RACE-01..03, step 15; 11 controls | production verification fail-closed until PS-1..PS-4 | PS-1..PS-4; student read scope; job identity; manager vocabulary | **Platform Security** (PS-1..PS-4), PO | **YES until reviewed** | brief §4, items 1–11 | ISO suite as own identity; GAP lines as assertions |
| G-04 | Cross-Workspace isolation | Database per Workspace; per-key roles | WS-ROLE cross-database denial (step 22) | low | — | — | no | — | WS-ROLE |
| G-05 | Student–guardian relationship and permissions | Append-only link/permission events; effective view | GDN-01..18 | legal authority unencoded | Q-007 legal matrix | PO / Legal | no (fail-closed) | Q-007 decided and encoded | GDN |
| G-06 | Transfer Saga, outbox, inbox | Per-recipient delivery, leases, dead-letter, generation-fenced inbox; inbox fail-closed | SAGA, SAGA-R, INB (steps 9–10) | service behaviour untested | wire format and signing (OQ-SAGA-1); quarantine resolution (OQ-SAGA-2); workers | PS / PO / later phase | no | — | SAGA, INB |
| G-07 | Transfer freeze and write barrier | 32 tables; both sides of UPDATE; in-flight barrier | FRZ-01..43, race (steps 12–13) | none at database level | controller, timeouts (OQ-E) | later phase | no | — | FRZ, race both modes |
| G-08 | Approval evidence (three approvals, revocation) | Immutable approval and revocation events | APR-01..13, APR-RACE-01, SEP-01..29 (step 8) | conflict-of-interest exception disabled | TRANSFER-EXC-AUTH | PO / Platform Security | no | — | APR, SEP |
| G-09 | Credit ledger and entitlement | Non-negative balance, bound reversal, append-only, single guard | CRD-01..47, races (steps 19–21, 26–27) | — | OQ-CRD-2, OQ-CRD-3 (period source, fail-closed) | PO | no (fail-closed) | decisions recorded | CRD |
| G-10 | Capacity and Workspace lifecycle | Atomic counters, final-slot race, archive and reactivation | CAP race, ARC-01..17 (steps 21, 28) | suspension capacity rule open | suspension policy | PO | no | — | ARC, races |
| **G-11** | **Plan, PlanVersion, PlanItem, audit (WS-PLAN-01)** | Normalized items; decisions A2/B1/C1/D1/E1 enforced under verified principals; runtime write path still closed | step 16: PLN incl. A2/D1/E1, race (student actors), PLN-M, F05, F05-BOOT; 8 controls | undetermined transitions refused | transitions A2/D1 do not name (open) | **PO**, then Developer | **YES** | decisions recorded; actor, graph, concurrency and migration tests | all step-16 suites |
| G-12 | Curriculum (Subject, Chapter, Topic, Subtopic) | Hierarchy; no deletes | CUR-01..10 (step 11) | — | Book/Edition (WS-DOM-05) | DEFERRED to Phase 7 (PO) | no | — | CUR |
| G-13 | Activity, class, participants, assignments | Typed FK sources; participants | ACT-01..26 | — | class recurrence rules | PO | no | — | ACT |
| G-14 | Exam, test, analysis, per-subject results | Versioned blueprints; per-subject results; analysis versions | AVQ, ASM, EXM-01..42 | — | custom error taxonomy (**NOT IMPL.**); OQ-ASM-1/2 | Developer (taxonomy); PO (OQ-ASM) | no | taxonomy table with tests | EXM, ASM |
| **G-15** | **Review records** (master §28: original activity, method, mastery before/after, result, **no duplicate generation**) | `reviews` table: topic, schedule, cadence, state only | inserted by the schema suite only | **duplicate reviews not prevented; required fields absent** | review source link, fields, uniqueness rule | Developer; PO if the uniqueness rule is not fixed by §28 | **recommend YES** (data integrity) | duplicate generation refused; fields present | new REV suite (not written) |
| G-16 | Daily routine counters (master §29: numeric target/completed) | `daily_routines.schedule_spec` jsonb; no counters | schema suite insert only | counters not modelled | counter tables | Developer | recommend no (Phase 2 scope to confirm) | — | — |
| G-17 | Progress, mastery, risk records | `progress_snapshots.metrics` jsonb; `risk_assessments` | schema suite insert only | opaque metrics; explainability not modelled | formula documentation (master §38) | later phase (16) | no | — | — |
| G-18 | File metadata and access contract | Ownership bound, forward-only, immutable facts; in barrier | OPS-01..24 (step 14) | no scan service; no access API | scan, download authorization | later phase | no | — | OPS |
| G-19 | Notification records and recipient isolation | Recipient rule incl. counselor scope; payload hygiene | OPS, ISO-43, OPS-13c | delivery-time re-check absent | OPS-NOTIF-DELIVERY | later phase | no | — | OPS, ISO-43 |
| G-20 | Audit, retention, legal hold | Policy versions all `needs_decision`; disposition gate fail-closed | OPS-30..51 | — | Q-020, OPS-HOLD-AUTH, OPS-DISP-AUTH, OPS-RETENTION-SCOPE | PO / Legal / Operations | no (fail-closed) | — | OPS |
| G-21 | Governance proof receipts and verifier | Receipt consumption, freshness, test-double verifier; production fail-closed | RC, VER (steps 23–24) | — | PS-1..8 | Platform Security | no (fail-closed) | — | RC, VER, CLK |
| G-22 | Global identity and contact change | HMAC rotation, admission, contact change and races | CID, CC, CID-RACE (steps 5–7, 25) | — | PS-1..4 for production keys | Platform Security | no | — | CID, CC |
| G-23 | Privileged plan identities (F-05) | Identity check; bootstrap validation; transitive owner reach | F05-00..23, F05-BOOT-01..20 | superuser outside the database's control | production provisioning, superuser audit, DDL monitoring (`F05_PRODUCTION_HARDENING_REQUIREMENTS.md`) | Operations / Platform Security | no — **ACCEPTED (architecture review)** | — | F05 suites |
| G-24 | SECURITY DEFINER hygiene, grants, PUBLIC | Pinned search_path, NOLOGIN owners, no PUBLIC table privilege | SEC-01..10 | two functions keep `public` on path (SEC-02c) | remove `public` from path | Developer | no | SEC-02c becomes PASS | SEC |
| G-25 | Clock discipline | Post-lock `clock_timestamp()` | CLK-01..03 (step 29) | — | PS-5 skew | Platform Security | no | — | CLK |
| G-26 | Migration safety | Draft SQL with a CI load order; one historical migration fixture (PLN-M) | PLN-M01..08 | **no migration framework (Alembic), no rollback, no lock-impact measurement** | migrations from the drafts; rollback; volume tests | Developer (with an Operations target) | recommend yes before Phase 3 | migrations reproduce the drafts; rollback tested | migration suite (not written) |
| G-27 | API object authorization, IDOR, uniform 404 | Contract only | — | later-phase | API | later phase | no | — | — |
| G-28 | Background-job tenant and actor context | Worker role grants only | WS-ROLE | — | immutable job context (part of G-03 §4.8) | Platform Security / Developer | with G-03 | — | — |
| G-29 | No secret material | History-content scan | SEC-REPO (step 30) | fixtures in history | REPO-HIST-CONTACTS | PO | no | — | scan |
| G-30 | Register and documentation consistency | REG-01..09 | step 31 | root docs (ARCHITECTURE, DATABASE, API, ROADMAP) not reconciled to Batches 1–8 | reconcile root docs | Developer | no | — | REG |
| G-31 | M-05 duplicate JSON keys; M-06 shared canonicalization vectors | not implemented | — | MEDIUM | as defined by the Supervisor | Developer | no (technical debt) | Supervisor closure criteria | — |
| G-32 | PR integration | PR #8–#11 open; branch 2 commits behind `main` (net 0 files) | `git` | — | disposition | PO | **YES** (register) | decision recorded | — |
| G-33 | Exit-criteria row "Approval evidence: NOT READY — schema shape conflicts" | contradicts the DONE row for approval events (§3 HIGH) | `PHASE2_EXIT_CRITERIA.md` §2 vs §3 | documentation inconsistency | Supervisor to confirm which statement is current | Supervisor | no | one consistent status | — |

## 2. Executed-test accounting (fresh disposable PostgreSQL 16.15 cluster, 2026-11-20, local)

A new cluster was created for this run, so no roles or databases carried over. **This is local evidence, not CI.**

| | Count |
|---|---|
| Implementation steps | 25, all exit 0 |
| PASS lines | 1067. A line is an assertion or a named group; for example "WS-ROLE-01..16,18,19" is one line |
| FAIL lines | 0 |
| OPEN lines (findings printed, not passed) | 3: ISO-GAP-01, 02, 03 |
| SKIP lines | 1: WS-ROLE-17 in the mirror run of step 22, which has no published test version. It executes and passes in the first run of the same step. |
| Python verifier tests | 15 + 6, OK |

**WS-ROLE-17 skip.** The group line used to say "PASS WS-ROLE-01..19" although WS-ROLE-17 was reported separately and
skipped in one of its two runs. The line is corrected to "01..16,18,19" and the skip says it is not counted.

**Negative controls.** Measured controls are listed per suite in TEST_PLAN.md: F-05 has 13 and the PlanItem F-01..F-04 work has 9. Controls for the earlier suites are recorded in their own TEST_PLAN sections and are not re-counted here.

## 3. Security checklist

| Check | State |
|---|---|
| IDOR | database row function answers a foreign id like a missing id (ISO-C1); **API not present** |
| Privilege escalation through role membership | closed for plan identities and owners (F-05) |
| SQL injection | database functions use `format('%I/%L')` or parameters; no API exists |
| Insecure SECURITY DEFINER | SEC-01..03, SEC-07 |
| Unsafe search_path | SEC-02; two functions with `public` on the path, measured not exploitable (SEC-02b) |
| Excessive grants / PUBLIC | SEC-06, SEC-10; **runtime reads all student tables (G-03)** |
| RLS bypass | **no RLS exists (ISO-GAP-03)** |
| Logs leaking data | no plaintext contact columns (CID-01..03); no application logs exist |
| File references | ownership bound, forward-only (OPS) |
| Export authorization | no export path exists |
| Replay / idempotency | receipts, Saga, activation, credit (RC, SAGA, CRD) |
| Cross-tenant background jobs | no jobs exist; context design in the WS-ISO-01 brief |

## 4. What blocks Phase 2 (agent's view)

1. **G-03 WS-ISO-01**: decided (B, test-only key) and implemented 2026-11-20; independent review; PS-1..PS-4 for production.
2. **G-11 WS-PLAN-01**: decided (A2/B1/C1/D1/E1) and implemented 2026-11-20; independent review.
3. **G-32 PR integration**: Product Owner.
4. **G-15 review integrity and G-26 migration framework**: newly identified, not yet classified by the Supervisor.
