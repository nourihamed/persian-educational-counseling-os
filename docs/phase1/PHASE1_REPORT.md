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
| docs/phase1/TENANT_ISOLATION_TEST_CONTRACTS.md | Rewritten: explicit modes per contract (C, S, R, A, I), CI column (PR / ENV / BLOCKED), failure consequence per contract, groups aligned with TEST_PLAN, 109 contracts |
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

Total: **114** contracts (102 PR, 3 ENV:pooler, 1 ENV:worker, 1 BLOCKED:Q-007, 7 BLOCKED:Q-019 mechanism-dependent: TI-CTX-15 to 18 only if Option D, TI-CONN-01 to 03 only if Option C). No contract is blocked by Q-015 (resolved, D-013).

| Group | Count |
|---|---|
| TI-CFG | 13 |
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
| TI-CONN (Option C only) | 3 |

Verification command (run from repository root; counts TI row identifiers in the contracts file):

```
grep -cE "^\| TI-[A-Z]+-[0-9]+ " docs/phase1/TENANT_ISOLATION_TEST_CONTRACTS.md
```

Expected output: `114`.

Note: this count is of specifications. No contract has been implemented or executed.

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
| D-012 (tenant-only templates) | Accepted; applied in composite key requirements |
| D-013 (Q-015: Option A for platform admin) | ACCEPTED 2026-10-15; applied; product decision only, not implemented |
| D-014 (Q-019: direction and pilot data rule) | Direction ACCEPTED 2026-10-15; mechanism OPEN; pilot data prohibited until conditions met |
| Q-014, Q-016, Q-017, Q-018 | OPEN. Recommendations only |
| Q-019 | Direction decided (D-014); mechanism OPEN (Option C or D candidate, pending independent review) |
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
| Test contracts (114) | Yes (specification) | Yes | n/a | **No. None has been executed.** |

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
- Selection of Option C or D for the stronger context boundary (Q-019 mechanism; requires independent security review before any real-data pilot, D-014).
- All executable tests and CI wiring.
- Migrations, roles, policies, and grants.

---

## 9. Items Requiring Product Owner Decision

1. Q-015: DONE (D-013, Option A).
2. Q-019: direction DONE (D-014). Owner must still choose the mechanism (C or D) after independent review, or explicitly decide otherwise in writing.
3. Q-014: exact not-found status (can be deferred to Phase 4).
4. Q-016, Q-017, Q-018: can be deferred to their owning phases, but must be resolved there.
5. Pilot gate: real student data is prohibited until the four conditions in D-014 are met and the owner approves the gate in writing.

---

## 10. Phase 1 Readiness Statement (for the reviewer)

- Documents are internally consistent on: role names, tenant vocabulary, error policy (identical not-found responses), test counts, Q-status.
- Documents are NOT evidence of security. No claim of runtime isolation is made.
- Q-015 is resolved (D-013). Q-019 mechanism is OPEN; Phase 1 cannot be approved as having a T4 boundary until it is selected and reviewed.
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
- [~] Q-019: direction decided (D-014); mechanism selection open
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
- Q-019 mechanism selection (owner, after independent review)
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
- **Counts after this revision:** 114 contracts; 102 PR; 3 ENV:pooler; 1 ENV:worker; 1 BLOCKED:Q-007; 7 BLOCKED:Q-019 (mechanism-dependent). Path inventory: 33 paths, 30 mapped, 3 blocked, 0 unmapped.

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
