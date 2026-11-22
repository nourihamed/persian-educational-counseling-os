# WS-PLAN-01 — Product Owner decision: PlanItem status transition graph

**Status:** APPROVED BY PRODUCT OWNER — exact graph approved; implementation and independent verification pending.  
**Decision date:** 2026-11-22  
**Authority:** Explicit Product Owner selection of Option A in the 2026-11-22 conversation.  
**Scope:** Product-policy approval only. This is not approval of production runtime writes, migrations, Phase 2 exit, or Phase 3.

## 1. Approved exact transition graph

Only the following exact actor/from/to tuples are approved. Every edge not listed remains denied.

| Actor | From | To | Required condition / reason |
|---|---|---|---|
| Student | planned | in_progress | Student starts assigned work |
| Student | planned | partially_completed | Student reports partial work without a separate start event |
| Student | planned | completed | Student reports completion without a separate start event |
| Student | in_progress | partially_completed | Student reports partial completion |
| Student | in_progress | completed | Student completes the work |
| Student | partially_completed | in_progress | Student resumes unfinished work |
| Student | partially_completed | completed | Student completes remaining work |
| Student | deferred | in_progress | Student resumes work previously deferred by counselor |
| Student | deferred | partially_completed | Student reports partial completion after deferral |
| Student | deferred | completed | Student reports completion after deferral |
| Responsible counselor | planned | deferred | Required deferral reason |
| Responsible counselor | planned | skipped | Counselor decides work should be skipped |
| Responsible counselor | planned | cancelled | Counselor cancels work |
| Responsible counselor | in_progress | deferred | Required deferral reason |
| Responsible counselor | in_progress | skipped | Counselor decides work should be skipped |
| Responsible counselor | in_progress | cancelled | Counselor cancels work |
| Responsible counselor | partially_completed | deferred | Required deferral reason |
| Responsible counselor | partially_completed | skipped | Counselor decides remaining work should be skipped |
| Responsible counselor | partially_completed | cancelled | Counselor cancels remaining work |
| Responsible counselor | deferred | skipped | Counselor closes previously deferred work as skipped |
| Responsible counselor | deferred | cancelled | Counselor cancels previously deferred work |

## 2. Explicitly denied transitions

- Any transition whose destination is `planned`.
- Any student transition to `deferred`, `skipped`, or `cancelled`.
- Any counselor transition to `in_progress`, `partially_completed`, or `completed`.
- Any transition out of `completed`, `skipped`, or `cancelled`.
- Any same-status transition.
- Any actor/from/to tuple not listed in §1.

## 3. Existing approved constraints remain in force

- Status changes on unpublished/draft PlanVersions are prohibited.
- Only the authorized responsible counselor may perform counselor transitions.
- Student transitions require the authenticated student principal for the relevant student.
- `deferred` requires a valid approved deferral reason.
- Published PlanVersions remain immutable except for the separately governed status-event mechanism already specified by the domain contract.
- Legacy JSON-based plans remain read-only.
- Every status event retains exact actor attribution, timestamp, and audit history.
- The PlanItem transition-rule catalog is not mutable by runtime/application roles.

## 4. Implementation and verification requirements

1. Add exactly the approved tuples to the reviewed base policy/migration; do not add inferred edges.
2. Keep runtime and application roles unable to insert, update, or delete transition-rule catalog rows.
3. Add exhaustive positive tests for all 21 approved tuples.
4. Add exhaustive negative tests for all other actor/from/to combinations, including actor mismatch and same-status attempts.
5. Test non-responsible counselor, wrong student, draft/unpublished PlanVersion, terminal states, stale from_status, missing/invalid deferral reason, replay, concurrent transitions, and rollback.
6. Preserve append-only status-event history and transactional enforcement.
7. Run fresh PostgreSQL tests and CI on the exact resulting commit, followed by independent review.

## 5. Gate boundary

This approval resolves the Product Owner policy question for the exact transition graph. It does not itself establish that the graph is implemented, tested, secure, or migration-safe. WS-PLAN-01 remains implementation-pending until evidence passes independent review. Phase 2 remains NOT READY; Phase 3 remains NOT AUTHORIZED; D-014 synthetic-only restrictions remain in force.
