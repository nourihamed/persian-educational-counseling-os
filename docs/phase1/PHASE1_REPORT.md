# CURRENT STATUS ADDENDUM — D-022 Q-023 DEFERRAL (2026-10-23)

- The Product Owner has deferred the final hosted topology/provider decision until hosted deployment planning. This records a schedule choice, not a topology selection or security waiver.
- The exact vendor, instance sizes, prices and target-environment capacity measurements may be deferred until that planning stage. The Phase 1 architecture must still define and independently justify Alt-5's cell host/network boundaries, shared control-plane privileges, global administrator/root compromise residual, and scoped credentials/backup/key access.
- **Gate impact:** Q-023 remains OPEN and remains a Phase 1 blocker under this independent review. No existing security condition is removed by D-022. D-020 and D-014 remain unchanged.
- Local development remains restricted to synthetic data and local-only services under D-021. Phase 1 remains NOT READY / NOT APPROVED; Phase 2 remains NOT STARTED / NOT AUTHORIZED; real student data remains prohibited.
- No code, migration, infrastructure, executable test or runtime security evidence is claimed.

---

# CURRENT STATUS ADDENDUM — 2026-10-23 (Revision 11, D-020/Q-022)

This addendum supersedes conflicting earlier status text below; older revision history is retained for traceability only.

- **Product Owner decision:** Q-022 option A selected and recorded as D-020: Alt-5 hybrid isolation cells; Alt-4 is the security reference.
- **Provisional blast-radius limits:** initial pilot proposal up to 10 tenants, no more than two tenants per cell (up to five cells), subject to measured cost/capacity. Neither capacity nor cost is yet validated; this is not pilot authorization.
- **Active normative design:** `docs/phase1/TENANT_ISOLATION_DESIGN.md` rewritten for Alt-5; `AUTHORIZATION_CONTRACT.md` rewritten for trusted tenant-to-cell routing and object authorization; `TENANT_ISOLATION_TEST_CONTRACTS.md` is the new active Alt-5 catalog.
- **Historical catalog:** 123 pre-Q-022 contracts archived at `docs/phase1/archive/TENANT_ISOLATION_TEST_CONTRACTS_PRE_Q022.md`. They are historical and do not retain PASS status. Active Alt-5 catalog contains 46 contracts.
- **Test state:** active catalog 46 contracts; 0 implemented, 0 executed, 0 passing. No workflows/runs or runtime security evidence are implied.
- **Hosting and operations:** D-011 single-VPS/Docker Compose and D-017 direct pool-size assumptions are not yet reconciled with the selected cell topology. Shared-host containers are not equivalent to separate operational isolation.
- **Residual risks:** theft of all usable tenant credentials and global host/cloud/root compromise remain catastrophic scenarios. No topology-only guarantee is claimed.
- 
## Hosting compatibility follow-up — Q-023 (2026-10-23)

D-011's accepted product objective (Iran-based hosting, portability and low initial complexity) is preserved, but its prior single-VPS assumption is not yet reconciled with D-020. A shared host containing multiple Compose stacks/containers does not create independent cell boundaries against host/root compromise. The Alt-5 design requires a separate PostgreSQL cluster/instance and network boundary per cell.

The new review `docs/phase1/HOSTING_CELL_COMPATIBILITY_REVIEW.md` compares four patterns: one shared VPS (not acceptable for the intended cell-boundary claim), separate host/VM per cell (recommended for further evaluation), separate cloud accounts/projects per cell (stronger isolation, higher expected complexity), and Alt-4 dedicated isolation per tenant. Q-023 is OPEN; the Product Owner has not yet selected the hosting topology. No vendor, pricing, or capacity is verified.

D-017's prior connection arithmetic is not an Alt-5 capacity result. Connection limits must be recalculated per PostgreSQL instance from the actual tenant-scoped worker/process/pool topology and admin/monitoring/recovery reserve. Cost and capacity remain NOT MEASURED. No code, infrastructure, migration or executable test was created or run. Phase 1 remains NOT READY; Phase 2 and real student data remain prohibited.

---

**Gate:** Phase 1 remains NOT READY / NOT APPROVED pending independent review, hosting/capacity/cost analysis and required corrections. Phase 2 remains NOT STARTED / NOT AUTHORIZED. No code, migration, infrastructure, runtime test, or real student data was introduced or authorized.

# CURRENT STATUS ADDENDUM — 2026-10-23 (Revision 10)

This addendum is authoritative for the current state. The revision history below is retained for traceability; statements in earlier revision sections that conflict with this addendum are historical, not current operational guidance.

- The latest independently reviewed pre-correction head was `4715e3d168d3f680ab98b682688980f845a24d45`; corrective changes are now committed to PR #3 on `docs/phase1-tenant-isolation-design`. Re-fetch the current live head before recording the final review verdict.
- The review found that §6 prescribed Option A's `set_config/current_setting` mechanism despite the then-current D-016 Option C direction. A later Product Owner decision D-019 (2026-10-23) requires stronger architecture; the prior Option C normative contract is now superseded pending Q-022 and a new independent design review.
- The test-contract catalog remains 123 specifications. The 12 Option A-only TI-CTX contracts (01–10, 13–14) are now SPEC-ONLY; TI-CTX-11/12 are redefined as future direct per-tenant connection-pool lifecycle checks. No contract is represented as implemented, executed, or passed.
- Current CI-column breakdown (123 rows): PR 91; PR (Phase 2-3) 2; ENV:direct-pool (D-017) 2; ENV:direct-pool (Phase 3) 1; ENV:pooler (Q-016) 1; ENV:worker (Q-017) 1; ENV:security-review (Phase 26) 1; ENV:security-review (Phase 3 and 26) 1; BLOCKED:Q-007 1; BLOCKED:implementation (Option C, D-016) 4; BLOCKED:implementation (Option C, D-016); Option D part SPEC-ONLY 1; SPEC-ONLY (Option A not selected) 12; SPEC-ONLY (Option D not selected, D-016) 5. These are execution routing labels, not results. All 123 remain NOT-RUN; 0 implemented, 0 executed, 0 passing.
- D-017: pilot connection mode is direct PostgreSQL connections, pool size 1 per tenant per application process. Transaction pooling is deferred. The A1 cap of 10 is provisional; capacity remains ESTIMATE — NOT MEASURED.
- Q-020 retention duration and responsible people remain unresolved. This does not silently authorize real data.
- Q-021 resolved by D-019 on 2026-10-23: Product Owner selected option B, requiring stronger architecture; K-L-N and K-O residual risks are not accepted as sufficient. Q-022 is OPEN for final topology selection. Phase 1 remains NOT READY.
- Gate remains **NOT READY / NOT APPROVED** pending stronger-architecture design, Q-022 resolution, and independent review. Phase 2 is not authorized. No real student data is permitted under D-014.

---
# PHASE 1 REPORT — Architecture & Multi-Tenancy (design only, revision 2)

Date: 2026-10-15
Phase: 1 — Architecture & Multi-Tenancy
Milestone: Corrective pass on Phase 1 design artifacts, ready for independent review
Status: **PENDING INDEPENDENT REVIEW. NOT APPROVED.** This report does not approve Phase 1. Phase 2 is not started and not authorized.

---

## 1. Files Reviewed and Changed

| File | Change in revision 2 |
|---|---|
| docs/phase1/TENANT_ISOLATION_DESIGN.md | Rewritten: explicit threat model (§1), trust boundary and what RLS does not prove (§2), options A–E, claims ledger, testable runtime-role requirements, FORCE RLS decision, context behavior for invalid/changed/pooled cases, platform admin conditions revised, Q-019 added |
| docs/phase1/AUTHORIZATION_CONTRACT.md | Aligned with Q-014 (exact status pending), object-level authorization identified as primary control against authenticated users, checklist updated |
| docs/phase1/TENANT_ISOLATION_TEST_CONTRACTS.md | Rewritten: explicit modes per contract (C, S, R, A, I), CI column (PR / ENV / BLOCKED), failure consequence per contract, groups aligned with TEST_PLAN, 120 contracts at revision 5 (see §17; current count in §3 and §20) |
| docs/phase1/PHASE1_REPORT.md | This report |
| OPEN_QUESTIONS.md | Phase 1 block rewritten: Q-014 to Q-018 status and blocking flags; Q-019 added |
| SUPERVISOR_REVIEW.md | Temporary PENDING section replaced by the revision-2 block in APPEND_TO_SUPERVISOR_REVIEW_REV2.md. Verdict field left empty for the reviewer |
| PROJECT_STATE.md, ROADMAP.md, CHANGELOG.md | Not changed in this pass; to be updated only after the owner accepts the revised documents |

Reviewed for consistency (not all changed): DECISION_LOG.md (D-008, D-009, D-010, D-011, D-012 read; none modified), TEST_PLAN.md (groups and R/A/I definitions read), SECURITY.md, DATABASE.md, PROJECT_SCOPE.md (read for consistency).

---

## 2. Summary of Changes

1. **Trust boundary made explicit.** The earlier draft implied RLS plus a session variable gave strong isolation. Revision 2 states that arbitrary SQL execution as the runtime role (threat T4) bypasses the session-variable mechanism. This is an accepted residual risk of D-009 until Q-019 is decided. No D-009 text was changed.
2. **Runtime-role requirements made testable.** R-DB-01 to R-DB-08 each map to a configuration test. TRUNCATE (not subject to RLS) is now an explicit check (TI-CFG-07).
3. **FORCE RLS** is now a stated requirement on all tenant-owned tables, with its migration impact recorded.
4. **Context behavior** specified for unset, empty, invalid UUID, mid-transaction change, rollback, and pooled connections.
5. **Platform admin** conditions made explicit and proposal-only; no bypass role by default.
6. **Test contracts** rebuilt: explicit modes, CI columns, BLOCKED items, failure consequences, and coverage of all TEST_PLAN groups including repository direct access, reports, exports, files, notifications, jobs, version history, and platform admin.
7. **Q-014 to Q-018** have explicit status, owner decision needed, dependency, phase-of-resolution, and whether they block Phase 1 approval. None is marked resolved.
8. **Q-019** added for the trust boundary against arbitrary SQL.
9. **Test count corrected** from the earlier unverified figure to the recounted total in §3.

---

## 3. Test Contract Count (recounted from the file)

Total: **123** contracts (105 PR, 4 ENV:pooler, 1 ENV:worker, 2 ENV:security-review, 1 BLOCKED:Q-007, 5 BLOCKED:implementation (Option C, D-016), 5 SPEC-ONLY (Option D not selected, D-016)). No contract is blocked by Q-015 (resolved, D-013), and none is blocked by Q-019, which now has its direction decided (D-016).

| Group | Count |
|---|---|
| TI-CFG | 14 |
| TI-CTX | 18 |
| TI-FK | 8 |
| TI-BYP | 6 |
| TI-API | 17 |
| TI-REPO | 6 |
| TI-RPT | 3 |
| TI-EXP | 3 |
| TI-FILE | 7 |
| TI-NOTIF | 5 |
| TI-JOB | 5 |
| TI-VER | 7 |
| TI-AUD | 3 |
| TI-PLAT | 10 |
| TI-CONN (Option C, selected D-016) | 6 |
| TI-ADV (threat-based) | 5 |
| **Sum** | **123** |

Verification command (run from repository root; counts TI row identifiers in the contracts file):

```
grep -cE "^\| TI-[A-Z]+-[0-9]+ " docs/phase1/TENANT_ISOLATION_TEST_CONTRACTS.md
```

Expected output: `123`.

Count vocabulary (revision 8). These four figures must not be confused:

| Measure | Value | Basis |
|---|---|---|
| Specified contracts | 123 | Unique contract rows in TENANT_ISOLATION_TEST_CONTRACTS.md |
| Implemented test code | 0 | No test code exists in the repository |
| Executed tests | 0 | No test has been run |
| Passing tests | 0 | No passing result exists |

Note: the count is of specifications only. It is not evidence of coverage. Coverage of all tenant-isolation paths is not claimed (see TENANT_PATH_INVENTORY.md).

---

## 4. TEST_PLAN Group Coverage

| TEST_PLAN requirement | Contract groups |
|---|---|
| Runtime role configuration and privileges | TI-CFG-01 to 11 |
| Table ownership and RLS policies (enabled, forced, policies) | TI-CFG-02, 03, 04 |
| RLS alone, independent of app filters | TI-CTX-01 to 08, TI-FILE-04, TI-BYP-02 |
| Application authorization alone, in isolated test environment | TI-API (A rows), TI-REPO (A rows), TI-FILE (A rows), TI-JOB-03, TI-VER (A rows) |
| Integrated | TI-API (I rows), TI-FK, TI-NOTIF, TI-JOB, TI-VER, TI-AUD, TI-PLAT |
| API and ID manipulation | TI-API-01 to 08 |
| Direct repository access | TI-REPO-01 to 06 |
| Reports and exports | TI-RPT-01 to 03, TI-EXP-01 to 03 |
| Files and temporary links | TI-FILE-01 to 07 |
| Notifications | TI-NOTIF-01 to 05 |
| Background jobs | TI-JOB-01 to 05 |
| Version history | TI-VER-01 to 07 |
| Platform admin access | TI-PLAT-01 to 10 |

Coverage of "100% of Tenant isolation paths" is a future measurement. It requires a path inventory that does not exist yet. It is therefore NOT claimed.

---

## 5. Decisions

| Item | State |
|---|---|
| D-008 (versioning) | Accepted; applied in design, not re-decided |
| D-009 (tenant isolation mechanism) | Accepted; applied; not changed. Residual risk T4 documented (Q-019) |
| D-010 (MVP scope) | Accepted; applied |
| D-011 (pilot hosting) | Accepted; referenced by Q-018 for reachability check |
| D-004 (Tenant Isolation strategy) | Accepted (2026-10-12) |
| D-001, D-002, D-003, D-005 | Proposed (status as recorded in DECISION_LOG) |
| D-006 (Plan naming) | Proposed; requires confirmation in Phase 2 |
| D-012 (tenant-only templates) | Accepted; applied in composite key requirements |
| D-013 (Q-015: Option A for platform admin) | ACCEPTED 2026-10-15; applied; product decision only, not implemented |
| D-014 (Q-019: direction and pilot data rule) | Direction ACCEPTED 2026-10-15; superseded for mechanism by D-016 (Option C preferred direction, 2026-10-17); pilot data prohibited until conditions met |
| Q-014, Q-016, Q-017, Q-018 | OPEN. Recommendations only |
| Q-019 | Direction decided (D-014); mechanism direction decided (D-016: Option C preferred, subject to design review; Option D not selected). Not implemented |
| Q-015 | RESOLVED (D-013) |
| Q-007 (parent access) | OPEN. Blocks TI-API-09 |

---

## 6. Claims: Designed, Reviewed, Implemented, Test-Verified

| Item | Designed | Reviewed for design | Implemented | Test-verified |
|---|---|---|---|---|
| Tenant context model (§3 design) | Yes | Yes (this pass) | No | No |
| Layer responsibilities | Yes | Yes | No | No |
| Runtime role requirements R-DB-01 to 08 | Yes | Yes | No | No |
| FORCE RLS on tenant tables | Yes (required) | Yes | No | No |
| Composite key pattern | Yes | Yes | No | No |
| Context behavior (invalid, unset, changed, pooled) | Yes | Yes | No | No |
| Platform admin access | Yes (proposal) | Yes | No | No |
| Authorization procedure and error mapping | Yes | Yes | No | No |
| Test contracts (120 at revision 6, historical) | Yes (specification) | Yes | n/a | **No. None has been executed.** |

**Nothing in this report is test-verified.** Isolation is not claimed to work at runtime.

---

## 7. Residual Risks

1. **T4 — arbitrary SQL as runtime role.** The session-variable mechanism does not stop it. Mitigation depends on SQL injection prevention and privilege minimization, not on RLS. Decision Q-019.
2. **Owner-role misconfiguration** in the real environment, including managed hosting that may grant superuser-like roles. Mitigated by TI-CFG tests on the actual target; not yet executed.
3. **Pooler leakage** if transaction-local discipline is broken. Q-016.
4. **Platform-admin misuse.** Mitigated by D-013 (read-only, audited, no bypass role, denials audited). Implementation not yet verified.
5. **Jobs and retries crossing tenants.** Q-017.
6. **Files reachable through guessable or long-lived links.** Q-018.
7. **Parent over-exposure** until Q-007 is decided. TI-API-09 is BLOCKED.
8. **Documentation overclaim risk.** Any future document that says "RLS guarantees isolation" is incorrect under T4 and must be corrected.

---

## 8. Items Deliberately Deferred

- Parent access design (Q-007).
- Pooler mode and infrastructure (Phase 3, Q-016).
- Job execution model (Phase 3, Q-017).
- File storage provider (Q-018, before first file feature).
- Platform admin implementation (Phase 4 and later, per D-013).
- Implementation of Option C (Phase 2 or later) and its validation before any real-data pilot (D-014).
- All executable tests and CI wiring.
- Migrations, roles, policies, and grants.

---

## 9. Items Requiring Product Owner Decision

1. Q-015: DONE (D-013, Option A).
2. Q-019: direction DONE (D-014); mechanism direction DONE (D-016, Option C preferred, subject to design review).
3. Q-014: exact not-found status (can be deferred to Phase 4).
4. Q-016, Q-017, Q-018: can be deferred to their owning phases, but must be resolved there.
5. Pilot gate: real student data is prohibited until the four conditions in D-014 are met and the owner approves the gate in writing.

---

## 10. Phase 1 Readiness Statement (for the reviewer)

- Documents are internally consistent on: role names, tenant vocabulary, error policy (identical not-found responses), test counts, Q-status.
- Documents are NOT evidence of security. No claim of runtime isolation is made.
- Q-015 is resolved (D-013). Q-019 direction is decided (D-016); Phase 1 design approval is a design-review gate; no T4 boundary is claimed as implemented or verified.
- Matching against the Master Prompt: the Master Prompt is not present in this repository as a file. The matching against it was therefore done only through the references recorded in the accepted decisions (D-008 to D-012) and in TEST_PLAN.md. A direct match to the Master Prompt text could not be confirmed and is not claimed.

---

## 11. Checklist: Consistency with D-009 and TEST_PLAN

- [x] Shared PostgreSQL database; direct indexed NOT NULL tenant_id (design §4, §7)
- [x] Authorization in Application/API layer; RLS as defense in depth, not sufficient alone (design §1, §2)
- [x] Composite constraints or equivalent for parent/child consistency (design §7)
- [x] Platform Admin cross-tenant access limited, read-only, audited, explicit (design §8, D-013)
- [x] Runtime role not owner and not bypass-capable (design §5, TI-CFG-01 to 07)
- [x] Negative cross-tenant tests for API, repository, jobs, reports/exports, files, notifications (test contracts)
- [x] R, A, I modes defined and applied per contract (test contracts §0)
- [x] Isolated Postgres per run; no SQLite (TEST_PLAN) — recorded as a requirement, not yet implemented
- [x] No test claimed as executed
- [x] Q-019: direction decided (D-014); mechanism direction decided (D-016)
- [x] Q-015 decided (D-013, Option A)
- [ ] Parent access / Q-007 — open

---

## 12. Recommendation on Readiness for Independent Review

The documents are ready to be reviewed. They are not ready to be approved: the Q-019 mechanism is open, and no test has been executed. The reviewer should check the threat model (design §1–§2) and the claims ledger (design §2.5) first, because the rest of the design depends on them.

---

## 13. Resolution of Independent Review Items (Revision 2)

Review verdict as received: CONDITIONAL PASS. Verdict is recorded in SUPERVISOR_REVIEW.md as reviewer-stated; final gate remains PENDING.

| # | Review item | Status after this pass |
|---|---|---|
| 1 | Option D underspecified (SECURITY DEFINER alone does not stop GUC forgery) | Addressed in design: §2.3.1 lists the six required points (issuance, verification location, context-row design with no GUC in policies, policy predicate, key management, negative tests). Option D remains a CANDIDATE, not proven. Open points listed. |
| 2 | Claims ledger: policy evaluation must cover all effective policies | Addressed: TI-CFG-04 requires exact policy-name set; TI-CFG-12 evaluates effective predicate with permissive OR and restrictive AND; TI-CFG-13 forbids GUC references in policies. Ledger row added. |
| 3 | Path inventory (coverage 100% not measurable) | Partly addressed: `TENANT_PATH_INVENTORY.md` created with 32 paths, all traced to contracts or marked BLOCKED. Endpoint-level inventory still missing; 100% NOT claimed. |
| 4 | Q-015 decision | RESOLVED by owner: Option A (D-013), matching the reviewer's recommendation. Implementation not done. |
| 5 | Q-019 decision | Direction DECIDED by owner (D-014): strengthen before real-data pilot; pilot rule adopted. Mechanism OPEN. |
| 6 | Gate impact of Q-007 (TI-API-09) | Proposal recorded in OPEN_QUESTIONS (Q-007 gate section): block phase 23 closure, not Phase 1 approval. Reviewer must confirm. |
| 7 | Re-review after changes; no automatic APPROVED | Not done by the assistant. Requires reviewer re-review. Status unchanged. |

### 13.1 Items not resolved by the assistant (require decisions)
- Q-019: none required for design approval (direction decided, D-016). Implementation and pilot validation are later gates
- Q-007 gate proposal (reviewer confirmation)
- Endpoint-level path inventory (Phase 2 and Phase 4)
- Actual execution of any contract (not in Phase 1 scope)

### 13.2 Claim status after this pass
Designed, reviewed by the assistant, reviewed by the independent reviewer (CONDITIONAL PASS, as received). Not implemented. Not test-verified. Not proven secure.


---

## 14. Implementation of Owner Decisions (Revision 4)

- **Q-015 (Option A, D-013):** applied to design §5.1 and §8, test contracts TI-PLAT-06 (now PR, no longer blocked), TI-PLAT-08 (static guard), TI-PLAT-09 and TI-PLAT-10 (new), path inventory P-25 and P-26, authorization contract, OPEN_QUESTIONS (moved to Resolved).
- **Q-019 (direction, D-014):** applied to OPEN_QUESTIONS, design §2.4 (Option C as proposed technical candidate, Option D as alternative, both pending review), test contracts TI-CONN-01 to 03 (new, mechanism-dependent), path inventory P-33 (new), DECISION_LOG.
- **Pilot rule (D-014):** no real student data until four conditions are met and the owner approves the gate in writing. Recorded in DECISION_LOG and this report.
- **Counts at that revision (historical):** 120 contracts; 103 PR; 3 ENV:pooler; 1 ENV:worker; 2 ENV:security-review; 1 BLOCKED:Q-007; 10 BLOCKED:Q-019 (mechanism-dependent). Path inventory: 33 paths, 30 mapped, 3 blocked, 0 unmapped.

### 14.1 Status by category (not merged, not run)
| Item | Status |
|---|---|
| Q-015 product decision | Recorded (D-013) |
| Q-015 implementation | Not done |
| Q-019 direction | Recorded (D-014) |
| Q-019 mechanism | OPEN; candidates under review |
| Q-019 security tests | Specified only (mechanism-dependent); NOT run |
| Pilot with real data | PROHIBITED until D-014 conditions met |
| Phase 1 approval | NOT granted; reviewer re-review required |

### 14.2 Explicit non-claims
- No test has been executed or passed.
- No runtime isolation, no defense against T4, and no production security is claimed.
- Option C and Option D are candidates, not selected and not proven.
- Phase 2 is not started.


---

## 15. Independent Review of Revision 4 (reviewer-stated, PR #3) and Response

Reviewer-stated gate: **NOT READY.** Reviewer reported PR #3 at commit `10cb7a5`. Note: the developer's local branch at revision 4 is commit `4ea224e` (based on `9655db0`). The reviewed commit and this revision must be reconciled before the next review; see the Process note below.

| Finding | Response in this revision |
|---|---|
| C-01 T4 combined three threats; Option C claim overstated | Decomposed into T4a, T4b, T4c (design §1.2, §1.4). Option C limits stated explicitly (§2.4). Claims ledger split (§2.5). Adversarial contracts TI-ADV-01 to 03 added. Mechanism still OPEN |
| H-01 endpoint inventory contradiction | Clarified: endpoint inventory is a Phase 2 and Phase 4 deliverable, not a Phase 1 approval criterion (path inventory notes). Phase 1 claims no endpoint coverage |
| H-02 Option C claim must match its limits | Addressed in §2.4 and §1.4; TI-CONN contracts unchanged in scope |
| M-01 Q-007 gate | Reviewer confirmed the gate proposal (block Phase 23, not Phase 1). Recorded in OPEN_QUESTIONS and SUPERVISOR_REVIEW. Q-007 product question still OPEN |
| M-02 D-001 to D-006 status | Corrected: D-004 Accepted; D-001, D-002, D-003, D-005 Proposed; D-006 Proposed pending Phase 2 |
| M-03 PROJECT_STATE vs PR status | PROJECT_STATE updated to state "design submitted for review, not authorized or approved" |
| Required change 5: Q-019 stays OPEN | Kept OPEN |
| Required change 6: Pilot ban, no unexecuted success claims | Kept (D-014). No test is claimed as run |

### Process note
The reviewer's PR head (`10cb7a5`) is not the same commit as the developer's current revision (`4ea224e`). The next review must use the commit that is actually pushed to the Phase 1 branch, and the report must state its hash.

### Status
- Phase 1: NOT APPROVED. Reviewer-stated NOT READY.
- Q-015: resolved by owner decision (D-013); implementation not done.
- Q-019: direction decided (D-014); mechanism direction decided (D-016).
- Pilot with real data: prohibited.
- Phase 2: not authorized.


---

## 16. Revision 6 — Work Completed Before Re-Review (self-review)

### 16.1 Changes and files
| Item | File | Change |
|---|---|---|
| Q-019 technical evaluation (not a decision) | `docs/phase1/Q019_MECHANISM_EVALUATION.md` (new) | Attacker models AM1 to AM5; forging paths for A, C, D; comparison; claim scope per option; evidence required; reviewer questions |
| Threat model order | `TENANT_ISOLATION_DESIGN.md` | §1.3 now precedes §1.4; duplicate §1.4 removed |
| Claims ledger | `TENANT_ISOLATION_DESIGN.md` §2.5 | Each claim has one status: DESIGNED, REVIEWED (document-level), IMPLEMENTED, TEST-VERIFIED, NOT CLAIMABLE |
| Composite key wording | `TENANT_ISOLATION_DESIGN.md` §7 | Qualified as DESIGNED until constraints exist and TI-FK tests pass |
| Result vocabulary | `TENANT_ISOLATION_TEST_CONTRACTS.md` §0.6 | PASS, FAIL, KNOWN-RESIDUAL, BLOCKED, NOT-RUN, SPEC-ONLY; known vulnerabilities never PASS |
| TI-ADV-01, 02 | same | Per-option expected results; Option A is KNOWN-RESIDUAL |
| TI-CFG-14 (new) | same | PUBLIC privileges revoked on tenant objects |
| Q-014 | `OPEN_QUESTIONS.md` | Deferral condition to Phase 4 |
| Q-019 | `OPEN_QUESTIONS.md` | Points to the evaluation; owner decision still required |
| ROADMAP status line | `ROADMAP.md` | Phase 1 submitted for review; NOT approved; Phase 2 not authorized |
| PROJECT_STATE count at revision 6 (historical) | `PROJECT_STATE.md` | 120 |

### 16.2 Counts (recounted from files)
- Contracts at that revision (historical): **120** (103 PR; 3 ENV:pooler; 1 ENV:worker; 2 ENV:security-review; 1 BLOCKED:Q-007; 10 BLOCKED:Q-019).
- Path inventory: 33 paths (30 mapped; 3 blocked; 0 unmapped).

### 16.3 Self-review checks performed
Checks run on the files before submission (static text checks only; no test executed):
- Contract IDs cited in documents exist in the contract file.
- No document states that RLS alone isolates tenants (checked by search; remaining matches are negations or scoped statements).
- Every contract has exactly one CI column value.
- Decision references (D-0xx) and open-question references (Q-0xx) exist in DECISION_LOG.md and OPEN_QUESTIONS.md.

Results of these checks are reported in the final message of this revision, not claimed here as a passing test.

### 16.4 Items NOT completed in this revision (and why)
- **Q-019 selection:** owner decision after independent review. Not made by the assistant.
- **Execution of any contract:** out of Phase 1 scope.
- **Endpoint-level path inventory:** Phase 2 and Phase 4 deliverable.
- **Q-016, Q-017, Q-018:** owning phases.
- **Pool and role limits on D-011 host:** requires measurement, not design.
- **Independent re-review:** requires the pushed commit.

### 16.5 Status (unchanged by this revision)
- Phase 1: NOT APPROVED. Reviewer-stated gate NOT READY.
- Q-015: resolved (D-013).
- Q-019: direction decided (D-014); mechanism direction decided (D-016); technical evaluation provided.
- Pilot with real data: prohibited.
- Phase 2: not authorized.


---

## 17. Revision 7 — Response to Reviewer Findings (NOT READY, PR #3, commit cc4b576)

| Finding | Response | Where |
|---|---|---|
| C-01 deadlock: selection depends on tests and capacity measurement scheduled later; Phase 2 depends on Phase 1 | Design-selection criteria separated from pilot-validation criteria. Phase 1 approval may rely on design criteria, all documentary and reviewable without running tests. Pilot validation remains a precondition for real data (D-014). Proposed for reviewer and owner decision | Q019 evaluation §6.1 |
| H-01 theft analysis for option D conflated classes | Credential classes analysed separately: K-L login, K-T token, K-S signing key, K-O owner or migrator; each option has an outcome per class | Q019 evaluation §4.4; design §1.4 |
| H-02 TI-ADV-02 outcomes incomplete for option D | Same attacker assumption and object for every option (stolen tenant login reading B rows). Option D pass criterion stated for login-only theft (NOT-RUN): zero rows | TI-ADV-02 |
| M-01 capacity measurement fallback unclear | Rule defined: estimate marked ESTIMATE; measured capacity becomes a pilot criterion; if below requirement, Option C is not used for the pilot and Option D or a new decision is re-reviewed | Q019 evaluation §6.2 |
| Add-on: token and owner classes need contracts | TI-ADV-04 (token replay, Option D only) and TI-ADV-05 (key and owner compromise, evidence) added | TI-ADV-04, 05 |

### 17.1 Counts
- Contracts at that revision (historical): **120** (103 PR; 3 ENV:pooler; 1 ENV:worker; 2 ENV:security-review; 1 BLOCKED:Q-007; 10 BLOCKED:Q-019).
- Paths: 33 (30 mapped; 3 blocked; 0 unmapped).

### 17.2 Status (unchanged)
- Phase 1: NOT APPROVED. Reviewer-stated gate NOT READY (commit cc4b576).
- Q-019: mechanism direction decided (D-016); implementation not started.
- All contracts (123 at revision 9) NOT-RUN. No CI status is claimed.
- Pilot with real data: prohibited (D-014).
- Phase 2: not authorized.

### 17.3 Open for the owner and reviewer
1. Accept or reject the separation in §6.1 (design selection versus pilot validation) as the basis for Phase 1 approval.
2. Choose C, D or a documented residual acceptance for Q-019, using the per-class outcomes in §4.4.
3. Confirm the capacity fallback rule in §6.2.

---

## 18. Owner Acceptance of the Gate Separation (D-015, 2026-10-17)

- The Product Owner accepted the separation in `Q019_MECHANISM_EVALUATION.md` §6.1: design-selection criteria versus pilot-validation criteria. This resolves the process deadlock C-01 (`OPEN_QUESTIONS.md`, Resolved section).
- Test execution that belongs to later phases is not a precondition for design decisions or for starting those phases.
- Not changed by this acceptance: Phase 1 approval (requires reviewer verdict on the new commit and owner gate decision); the Q-019 mechanism (OPEN); the capacity rule §6.2 (awaiting owner acceptance); D-014 (no real student data until pilot-validation criteria are met).
- Status: Phase 1 NOT APPROVED. Q-019 direction decided (D-016). All contracts (123 at revision 9) NOT-RUN. No CI status claimed. Phase 2 not authorized.

---

## 19. Revision 8 — Corrective Pass After Independent Review (commit before this revision: 1c36dc5)

Reviewer finding IDs are as stated in the review. Review ID 5573172802 (PR #3). Gate: NOT READY (reviewer-stated). This revision does not change the gate.

| Finding | What changed | Exact location | Validation evidence | Remaining limitation |
|---|---|---|---|---|
| H-01 credential-theft comparison not equivalent | Common scenarios K-L-1 and K-L-N defined; per-option table of credential, identity, capability, reach to B, conditions, status; Option D no-token case assessed explicitly; K-T, K-S, K-O separated | Q019 §4.4.1 to §4.4.8 | Reviewed by the developer. Static consistency checks (§19.2). No test executed | Option D conclusions depend on verifying conditions (TI-CFG-05, 06, 14; TI-CTX-15, 16; TI-BYP-03). Not verified |
| H-02 Option D selection-readiness | Option D classified NOT SELECTION-READY; seven design-critical points listed with owners and recommendations; PO decisions listed; §6.1 readiness table shows criterion 1 not met for D | Q019 §6.1 readiness table, §6.3; design §2.3.1; OPEN_QUESTIONS Q-019 | Consistency check: §6.1 criterion 1 status matches §6.3 | All seven points are OPEN. Asymmetric versus HMAC is a Product Owner decision |
| M-01 Option C capacity estimate | Assumptions A1 to A8; direct and pooled calculations; drivers; fallback restated; labelled ESTIMATE — NOT MEASURED | Q019 §6.2 | Arithmetic reproduced in §19.3 | Assumptions are not measured. Pilot tenant count, pool strategy, pooler, memory and max_connections are unknown |
| M-02 contract count reconciliation | Group table in §3 now includes TI-ADV (5) and sums to 120; CI breakdown corrected (2 security-review, 10 Q-019); count vocabulary added | PHASE1_REPORT §3; TENANT_ISOLATION_TEST_CONTRACTS.md index | Recount: 120 unique IDs; groups sum to 120; CI categories sum to 120 (§19.2) | None for the count itself |
| TI-ADV-02, 04, 05 alignment | Same objects and attacker assumptions across options; K-S and K-O separated; no PASS for conditions not verified | TENANT_ISOLATION_TEST_CONTRACTS.md | Static check of row shape (§19.2) | All NOT-RUN |

### 19.1 Option C capacity — final estimate (ESTIMATE — NOT MEASURED)
- (Superseded by §20 for A1 = 10.) Direct connections, worst case at 50 tenants: 610 (or 310 with pool size 1). Against default `max_connections` 100: not feasible under these assumptions without a large increase whose memory cost is unknown.
- Per-user pooler (server pool 1 or 2 per tenant role, 50 tenants, reserve 10): **60** or **110** server connections. Feasible in count only under these assumptions, and only with a pooler in front of PostgreSQL (Q-016).
- C remains unselectable for the pilot until the pilot tenant count, pool strategy and pooler are decided and capacity is measured on the D-011 host.

### 19.2 Validation performed in this revision (static only; no test executed)
- Contract rows: 120; unique IDs: 120; group totals sum to 120; CI categories sum to 120.
- Every TI, Q and D identifier referenced in the Phase 1 documents is defined.
- Every contract row has six table cells.
- Q019 §4.4 and §6.2 tables have consistent cell counts.
Results of these checks are reported in the commit message and in the final message to the owner. They are not test results.

### 19.3 Arithmetic check
- 6 × 50 × 2 + 10 = 610; 6 × 50 × 1 + 10 = 310; 50 × 2 + 10 = 110; 50 × 1 + 10 = 60.

### 19.4 Counts (vocabulary)
- Specified: 120. Implemented: 0. Executed: 0. Passing: 0.

### 19.5 CI status
No CI status or workflow run for this revision is available to the developer. Absence of CI results is not success.

### 19.6 Confirmations
- D-014 unchanged: no real student data in any pilot.
- Q-019 remains OPEN. No mechanism selected.
- Phase 2 not started.
- Phase 1 not approved. Gate remains NOT READY until the supervisor re-reviews the new commit.

---

## 20. Revision 9 — Owner Decisions Applied (D-016, 2026-10-17)

### 20.1 Decisions recorded (DECISION_LOG D-016)
1. Q-019 direction: **Option C is the preferred design direction**, subject to design review. Not runtime security; not pilot authorization.
2. **Option D not selected**; NOT SELECTION-READY until seven points are resolved and reviewed.
3. Option D reconsideration: asymmetric signatures first; one-time versus reusable token decision and `jti` policy must be explicit.
4. **A1 provisional cap: 10 tenants**, subject to capacity analysis and owner confirmation before pilot.
5. Pool strategy: **bounded, lazy, per-tenant**. Pooler mode not selected by the owner; OPEN under Q-016 with a recommendation for review.
6. Role lifecycle: specified in design §5.5 (immediate login disable, revocation, session termination, audit retention, guarded drop).
7. **Shared-role fallback prohibited.**
8. Capacity rule accepted as a constraint: estimate is not measurement; measurement required before real-data pilot.
9. D-014 unchanged.
10. Phase 1 remains unapproved until the supervisor gate is satisfied.

### 20.2 Changes to documents
- `Q019_MECHANISM_EVALUATION.md`: A1 = 10 (provisional); capacity recalculated: direct at pool size 2 = **130** (not feasible at default 100); direct at pool size 1 = **70**; per-user pooler = **30** (pool 2) or **20** (pool 1); Option D classification NOT SELECTED.
- `TENANT_ISOLATION_DESIGN.md`: §2.4 records the decision and limitations; §5.5 specifies pool strategy and lifecycle.
- `TENANT_ISOLATION_TEST_CONTRACTS.md`: TI-CONN-04 (offboarding, ENV:pooler), TI-CONN-05 (ownership, PR), TI-CONN-06 (identity mapping, PR) added. TI-CONN-01 to 03, TI-ADV-01 and 02 are BLOCKED until implementation; TI-CTX-15 to 18 and TI-ADV-04 are SPEC-ONLY.
- `OPEN_QUESTIONS.md`: Q-019 updated (direction decided); Q-016 note (pooler mode open); Q-020 added (retention period and role-drop criteria).

### 20.3 Counts (recounted)
- Specified: **123** (105 PR; 4 ENV:pooler; 1 ENV:worker; 2 ENV:security-review; 1 BLOCKED:Q-007; 5 BLOCKED:implementation; 5 SPEC-ONLY).
- Implemented: 0. Executed: 0. Passing: 0.
- Paths: 33 (30 mapped; 3 blocked; 0 unmapped).

### 20.4 Status
- Phase 1: NOT APPROVED. Gate NOT READY until the supervisor re-reviews the corrected commit.
- Q-019: direction decided (D-016); design review pending; no implementation.
- D-014: unchanged; real student data prohibited.
- Phase 2: not started.

---

## 21. Remaining Phase 1 and Pre-Pilot Work — Status (2026-10-17)

| Work item | Status | Owner | Evidence |
|---|---|---|---|
| Design documents for independent review | Completed as documents; NOT APPROVED | Developer; reviewer | this repository |
| Q-019 direction (Option C preferred, subject to design review; Option D not selected) | Decided (D-016); design review pending | Product Owner; reviewer | DECISION_LOG D-016 |
| Q-016 pooler / connection mode | Decided for pilot (D-017): direct connections, pool 1 per tenant per process | Product Owner | DECISION_LOG D-017 |
| Q-020 retention principle | Decided (D-017): no automatic role deletion | Product Owner | DECISION_LOG D-017 |
| Q-020 retention durations and approver | NEEDS-DECISION; legal/tax/privacy review required | Product Owner; reviewers (not yet assigned) | `DATA_RETENTION_SCHEDULE_DRAFT.md` |
| A1 pilot cap (10 tenants) | Decided as initial cap; capacity NOT measured | Product Owner | D-017; `TARGET_ENV_LOAD_TEST_PLAN.md` |
| Target-environment load and connection tests | PLAN ONLY; BLOCKED (host not confirmed; implementation not started) | Technical lead | `TARGET_ENV_LOAD_TEST_PLAN.md` |
| Tenant isolation contracts on implementation | NOT-RUN (123 specified contracts; 0 implemented; 0 executed) | Technical lead | TENANT_ISOLATION_TEST_CONTRACTS.md |
| Security review of implementation | NOT-RUN | Independent reviewer | — |
| Blocking findings | None recorded in this document set beyond the NOT READY gate | Reviewer | SUPERVISOR_REVIEW.md |
| Real student data in pilot | PROHIBITED until every D-014 condition is met and recorded | Product Owner | D-014 |
| Phase 2 | NOT started; NOT authorized | Product Owner | ROADMAP.md |
| Phase 1 approval | NOT APPROVED; requires independent re-review of the pushed commit | Independent reviewer; Product Owner | SUPERVISOR_REVIEW.md |

Statement: this document does not record any test as executed or passing, and does not record any capacity as measured.

### 21.1 Update after D-018 (2026-10-17)
- Retention approach, reviewer engagement, role-deletion approver (Product Owner), host profile to test, independent security review, and runbook as draft: ACCEPTED (D-018).
- Retention durations: still NEEDS-DECISION after legal and tax review. Not set.
- Incident lead, delegate, and data-incident notifier: still NEEDS-DECISION (owner must name them).
- Phase 1 approval: NOT granted by D-018; requires independent re-review of the pushed commit.
- No test, drill, measurement, or security review has been executed.



## Local-first development direction — D-021 (2026-10-23)

The Product Owner has chosen to run the development environment on their own laptop first and consider server deployment once the product reaches an agreed demonstrable stage. The local-development workflow is documented in `docs/phase1/LOCAL_DEVELOPMENT_AND_LATER_DEPLOYMENT.md`. Use synthetic data only, keep local services unexposed, protect secrets, and do not treat local containers as an Alt-5 security boundary.

This direction does not select the eventual server topology; Q-023 remains OPEN. It does not approve Phase 1, authorize Phase 2, or waive D-014's prohibition on real student data before the required gates and explicit Product Owner approval. No code, infrastructure, migration, or executable test was created or run by this documentation change.

---
