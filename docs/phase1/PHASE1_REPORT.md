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
| docs/phase1/TENANT_ISOLATION_TEST_CONTRACTS.md | Rewritten: explicit modes per contract (C, S, R, A, I), CI column (PR / ENV / BLOCKED), failure consequence per contract, groups aligned with TEST_PLAN, 103 contracts |
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

Total: **103** contracts.

| Group | Count |
|---|---|
| TI-CFG | 11 |
| TI-CTX | 14 |
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
| TI-PLAT | 8 |

Verification command (run from repository root; counts TI row identifiers in the contracts file):

```
grep -cE "^\| TI-[A-Z]+-[0-9]+ " docs/phase1/TENANT_ISOLATION_TEST_CONTRACTS.md
```

Expected output: `103`.

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
| Platform admin access | TI-PLAT-01 to 08 |

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
| Q-014 to Q-019 | OPEN. No decision recorded. Recommendations only |
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
| Test contracts (103) | Yes (specification) | Yes | n/a | **No. None has been executed.** |

**Nothing in this report is test-verified.** Isolation is not claimed to work at runtime.

---

## 7. Residual Risks

1. **T4 — arbitrary SQL as runtime role.** The session-variable mechanism does not stop it. Mitigation depends on SQL injection prevention and privilege minimization, not on RLS. Decision Q-019.
2. **Owner-role misconfiguration** in the real environment, including managed hosting that may grant superuser-like roles. Mitigated by TI-CFG tests on the actual target; not yet executed.
3. **Pooler leakage** if transaction-local discipline is broken. Q-016.
4. **Platform-admin misuse** if Q-015 chooses a bypass role. Default is no bypass role.
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
- Platform admin implementation (Phase 4 and later, Q-015).
- Option D or C for stronger context boundary (Q-019; owner decision before real-data pilot).
- All executable tests and CI wiring.
- Migrations, roles, policies, and grants.

---

## 9. Items Requiring Product Owner Decision

1. Q-015: platform admin mechanism, or explicit acceptance of the recommended default.
2. Q-019: accept residual risk T4 for MVP in writing, or require Option D or C.
3. Q-014: exact not-found status (can be deferred to Phase 4).
4. Q-016, Q-017, Q-018: can be deferred to their owning phases, but must be resolved there.
5. Whether real student data may enter any pilot before Q-019 is resolved.

---

## 10. Phase 1 Readiness Statement (for the reviewer)

- Documents are internally consistent on: role names, tenant vocabulary, error policy (identical not-found responses), test counts, Q-status.
- Documents are NOT evidence of security. No claim of runtime isolation is made.
- Q-015 and Q-019 are blocking unless the owner explicitly accepts the recommended defaults for the Phase 1 review.
- Matching against the Master Prompt: the Master Prompt is not present in this repository as a file. The matching against it was therefore done only through the references recorded in the accepted decisions (D-008 to D-012) and in TEST_PLAN.md. A direct match to the Master Prompt text could not be confirmed and is not claimed.

---

## 11. Checklist: Consistency with D-009 and TEST_PLAN

- [x] Shared PostgreSQL database; direct indexed NOT NULL tenant_id (design §4, §7)
- [x] Authorization in Application/API layer; RLS as defense in depth, not sufficient alone (design §1, §2)
- [x] Composite constraints or equivalent for parent/child consistency (design §7)
- [x] Platform Admin cross-tenant access limited, audited, explicit (design §8, Q-015)
- [x] Runtime role not owner and not bypass-capable (design §5, TI-CFG-01 to 07)
- [x] Negative cross-tenant tests for API, repository, jobs, reports/exports, files, notifications (test contracts)
- [x] R, A, I modes defined and applied per contract (test contracts §0)
- [x] Isolated Postgres per run; no SQLite (TEST_PLAN) — recorded as a requirement, not yet implemented
- [x] No test claimed as executed
- [ ] Owner decision on T4 / Q-019 — open
- [ ] Owner decision on platform admin / Q-015 — open
- [ ] Parent access / Q-007 — open

---

## 12. Recommendation on Readiness for Independent Review

The documents are ready to be reviewed. They are not ready to be approved: two items (Q-015 and Q-019) need an owner decision or explicit acceptance, and no test has been executed. The reviewer should check the threat model (design §1–§2) and the claims ledger (design §2.5) first, because the rest of the design depends on them.
