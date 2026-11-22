# Phase 2 — authoritative gap matrix

**Reconciled:** 2026-11-22 by the independent Supervisor, against GitHub branch heads, SQL, tests, workflow and Actions logs.

**Baseline**

| Item | SHA |
|---|---|
| PR #12 head | `78155b62f8830fe84c631100ec37bb236e5332e5` |
| Supervisor remediation branch head | `e92bf8f6ea47d5c406e764447f6fd4ce9ac152cd` |
| `main` | `5bb8e4ed07a7c770ecba7c506a1d2c278e36b6d6` |
| PR #12 merge base | `ba5e9d8a9577e5b87e2fc27caaf0bfb07f929114` |

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
| G-02 | Identity, membership, role, permission (WS-DOM-02) | Governance event ledger, projection, receipt boundary, grantability matrix (PO 2026-11-10) | step 18, steps 23–24 | HIGH while no trusted adapter | trusted adapter; enforcement of grantability; API tests | Developer + Platform Security (PS-1..8) | no (fail-closed) | authenticated governance command end-to-end | GOV, RC, VER suites |
| **G-03** | **Counselor-to-counselor isolation (WS-ISO-01)** | Test-only signed principal assertion; RLS ENABLE+FORCE; mandatory RESTRICTIVE principal fence; exact owner/test bypass allowlist; unknown roles fail closed | ISO-C1..54; ISO-P00..P30; ISO-RLS-01..09; ISO-RLS-C3..C16; ISO-P-RACE-01..03; Actions run 45030847506 step 15 | production verification and deployment separation remain fail-closed | PS-1..PS-5; M-01 deployment/test-mode boundary; student read scope; background-job identity; manager vocabulary | **Platform Security**, PO | **YES until remaining trust decisions** | exact allowlist; table/column/PUBLIC/indirect-grant audit; restrictive-policy negative control; built-in pg_read/write roles remain RLS-bound | ISO suite + ISO-RLS-C3..C16 |
| G-04 | Cross-Workspace isolation | Database per Workspace; per-key roles | WS-ROLE cross-database denial (step 22) | low | — | — | no | — | WS-ROLE |
| G-05 | Student–guardian relationship and permissions | Append-only link/permission events; effective view | GDN-01..18 | legal authority unencoded | Q-007 legal matrix | PO / Legal | no (fail-closed) | Q-007 decided and encoded | GDN |
| G-06 | Transfer Saga, outbox, inbox | Per-recipient delivery, leases, dead-letter, generation-fenced inbox; inbox fail-closed | SAGA, SAGA-R, INB (steps 9–10) | service behaviour untested | wire format and signing (OQ-SAGA-1); quarantine resolution (OQ-SAGA-2); workers | PS / PO / later phase | no | — | SAGA, INB |
| G-07 | Transfer freeze and write barrier | 32 tables; both sides of UPDATE; in-flight barrier | FRZ-01..43, race (steps 12–13) | none at database level | controller, timeouts (OQ-E) | later phase | no | — | FRZ, race both modes |
| G-08 | Approval evidence (three approvals, revocation) | Immutable approval and revocation events | APR-01..13, APR-RACE-01, SEP-01..29 (step 8) | conflict-of-interest exception disabled | TRANSFER-EXC-AUTH | PO / Platform Security | no | — | APR, SEP |
| G-09 | Credit ledger and entitlement | Non-negative balance, bound reversal, append-only, single guard | CRD-01..47, races (steps 19–21, 26–27) | — | OQ-CRD-2, OQ-CRD-3 (period source, fail-closed) | PO | no (fail-closed) | decisions recorded | CRD |
| G-10 | Capacity and Workspace lifecycle | Atomic counters, final-slot race, archive and reactivation | CAP race, ARC-01..17 (steps 21, 28) | suspension capacity rule open | suspension policy | PO | no | — | ARC, races |
| **G-11** | **Plan, PlanVersion, PlanItem, audit (WS-PLAN-01)** | Normalized items; A2/B1/C1/D1/E1 enforced; direct published INSERT rejected; publication/item lock protocol; exact transition-rule catalog empty in base schema | Actions run 45030847506 step 16; PLN-H2-01..03; PLN-H4-01..04; WS-PLN-PUB-RACE-01..11; F-05/PLN migration suites | production status execution unavailable until PO graph decision; runtime write path remains closed | exact actor × from_status × to_status graph (OPEN) | **PO**, then Developer | **YES** | explicit PO graph; no test-only edge leaks into base schema; runtime authorization separately approved | all step-16 suites |
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
| G-32 | PR integration | PR #8–#11 remain open; PR #12 head `78155b6`; PR #14 is stacked on PR #12; current `main` remains `5bb8e4e` | GitHub refs and PR metadata | no merge or rebase performed | PO disposition of PR #8–#11 and review/merge order for #12/#13 | PO | **YES** (register) | explicit disposition and approved merge order | — |
| G-33 | Approval-evidence status consistency | RESOLVED 2026-11-22: §2 now says PARTIAL; §3 says approval/revocation event schema DONE, while legal/authority binding and cutover revalidation remain open | `PHASE2_EXIT_CRITERIA.md` §2 and §3 | low | none for this wording; underlying Q-007/transfer authority remains open | Supervisor | no | consistent partial-vs-schema-complete wording | — |

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



### 2.1 Independent GitHub Actions verification — 2026-11-22

**Commit:** `cad2c0992bda3f1b37e274a14bc4e9c01d5d86cc`  
**Run:** [45030847506](https://github.com/nourihamed/persian-educational-counseling-os/actions/runs/45030847506)  
**Environment:** fresh disposable PostgreSQL 16.16 in GitHub Actions. **Conclusion: success.**

| Step | Result | Verified scope |
|---|---|---|
| 15 | PASS | WS-ISO-01 principal assertions and RLS; ISO-RLS-C3..C16; unknown, indirect, column, PUBLIC, built-in broad-data roles and restrictive-policy controls |
| 16 | PASS | WS-PLAN-01; direct published INSERT controls; exact transition-edge refusal; F-05; historical migration; status race; four PlanItem/publication lock and rollback cases |
| 17 | PASS | Workspace schema regression |
| 30 | PASS | Repository secret/key-shape scan, including tracked files and history |
| 31 | PASS | Unresolved-item register consistency (34 items; 24 mandatory) |

The publication race suite reported all four concurrency/rollback cases PASS:
- item-first commit → publisher waits, sees item and publishes;
- publisher-first commit → late item waits then refuses;
- item-first rollback → publisher waits then rejects empty publication;
- publisher-first rollback → item waits then succeeds on restored draft.

This is evidence for the synthetic draft schema and tests only. It is **not** production-key, deployment, API, runtime-write or Phase 2 approval evidence.

## 3. Security checklist

| Check | State |
|---|---|
| IDOR | database row function answers a foreign id like a missing id (ISO-C1); **API not present** |
| Privilege escalation through role membership | closed for plan identities and owner roles by F-05; application RLS grants audited including indirect membership |
| SQL injection | database functions use `format('%I/%L')` or parameters; no API exists |
| Insecure SECURITY DEFINER | SEC-01..03, SEC-07 |
| Unsafe search_path | SEC-02; two functions with `public` on the path, measured not exploitable (SEC-02b) |
| Excessive grants / PUBLIC | no PUBLIC table/column privileges on student-scoped tables (ISO-RLS-C16); `pg_read_all_data` / `pg_write_all_data` remain RLS-bound; runtime write path still closed |
| RLS bypass | restrictive principal fence on every student-scoped table; unknown roles fail closed; exact bypass identities only; ISO-RLS-C3..C16 and step 15 passed |
| Logs leaking data | no plaintext contact columns (CID-01..03); no application logs exist |
| File references | ownership bound, forward-only (OPS) |
| Export authorization | no export path exists |
| Replay / idempotency | receipts, Saga, activation, credit (RC, SAGA, CRD) |
| Cross-tenant background jobs | no jobs exist; context design in the WS-ISO-01 brief |

## 4. What blocks Phase 2 (agent's view)

1. **G-03 WS-ISO-01**: schema-level principal/RLS fence independently verified by Actions run 45030847506. Still blocking on PS-1..PS-5, M-01 trusted deployment/test-mode separation, student read scope, background-job identity and manager permission vocabulary. Production verification remains disabled.
2. **G-11 WS-PLAN-01**: A2/B1/C1/D1/E1 enforced and H-02/H-03/H-04 technical guards pass CI. The exact transition graph is deliberately empty and remains a Product Owner decision; production status execution is not authorized.
3. **G-15 Review records**: required fields and duplicate-generation invariant remain missing; implement from master §28 before gate.
4. **G-16/G-17**: daily routine counters and normalized progress/risk explainability remain incomplete; reconcile against master requirements and approved MVP.
5. **G-32 PR integration**: PR #8–#11 disposition and stacked PR #12/#14 sequence remain Product Owner-controlled; no merge performed.
6. **G-30**: root ARCHITECTURE/DATABASE/API/ROADMAP reconciliation remains open. **G-33** approval-evidence wording is reconciled; underlying legal/authority binding remains open under Q-007.
7. **G-26 migration framework**: DDL remains a draft, not a production migration; migration strategy and rollback/forward-compatibility evidence remain required before implementation deployment.
