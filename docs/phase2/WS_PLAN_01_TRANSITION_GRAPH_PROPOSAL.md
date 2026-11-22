# WS-PLAN-01 — Product Owner decision request: PlanItem status transition graph

**Status:** PROPOSAL ONLY — NOT APPROVED. No production transition rule is added by this document.
**Date:** 2026-11-22
**Authority:** Product Owner decision required.

## 1. Existing approved constraints

The following are already approved and must not be changed by this proposal:

- Student may record only `in_progress`, `completed`, and `partially_completed`.
- Only the responsible counselor may record `deferred`, `skipped`, and `cancelled`.
- Status changes on unpublished/draft PlanVersions are prohibited.
- `completed`, `skipped`, and `cancelled` are terminal.
- Legacy JSON PlanVersions remain read-only.
- `deferred` requires a deferral reason.
- No transition to `planned` is currently approved.
- A transition not explicitly approved must remain refused.

## 2. Recommended exact transition graph

The table below is a conservative, explicit proposal. Each row is one allowed edge. Every edge not listed remains denied.

| Actor | From | To | Reason |
|---|---|---|---|
| Student | planned | in_progress | Student starts the assigned work |
| Student | planned | partially_completed | Student reports partial work without a separate start event |
| Student | planned | completed | Student reports completion without a separate start event |
| Student | in_progress | partially_completed | Student reports partial completion |
| Student | in_progress | completed | Student completes the work |
| Student | partially_completed | in_progress | Student resumes unfinished work |
| Student | partially_completed | completed | Student completes the remaining work |
| Student | deferred | in_progress | Student resumes work previously deferred by counselor |
| Student | deferred | partially_completed | Student reports partial completion after deferral |
| Student | deferred | completed | Student reports completion after deferral |
| Responsible counselor | planned | deferred | Counselor defers planned work with required reason |
| Responsible counselor | planned | skipped | Counselor decides the work should be skipped |
| Responsible counselor | planned | cancelled | Counselor cancels the work |
| Responsible counselor | in_progress | deferred | Counselor defers work already started, with required reason |
| Responsible counselor | in_progress | skipped | Counselor decides the work should be skipped |
| Responsible counselor | in_progress | cancelled | Counselor cancels the work |
| Responsible counselor | partially_completed | deferred | Counselor defers remaining work, with required reason |
| Responsible counselor | partially_completed | skipped | Counselor decides remaining work should be skipped |
| Responsible counselor | partially_completed | cancelled | Counselor cancels remaining work |
| Responsible counselor | deferred | skipped | Counselor closes previously deferred work as skipped |
| Responsible counselor | deferred | cancelled | Counselor cancels previously deferred work |

## 3. Explicitly denied edges under this proposal

- Any transition whose destination is `planned`.
- Any student transition to `deferred`, `skipped`, or `cancelled`.
- Any counselor transition to `in_progress`, `partially_completed`, or `completed`.
- Any transition out of `completed`, `skipped`, or `cancelled`.
- Any same-status transition.
- Any edge not listed in §2.

## 4. Product Owner decision

Choose one:

- **A — Approve the recommended graph exactly as listed.**
- **B — Approve with amendments:** specify exact rows to add/remove.
- **C — Do not approve yet:** keep the base transition-rule table empty and fail-closed.

No transition-rule rows may be inserted into the base schema or production migration until the Product Owner's exact choice is recorded and independently reviewed.

## 5. Implementation after approval

After approval, the implementation must:

1. Populate only the approved actor/from/to tuples in a reviewed migration.
2. Keep runtime and application roles unable to modify the transition-rule catalog.
3. Test every approved edge as allowed under the correct actor and every unapproved edge as refused.
4. Test actor mismatch, non-responsible counselor, draft PlanVersion, terminal state, stale from_status, missing deferral reason, replay, concurrent transitions and rollback.
5. Preserve append-only event history and exact actor attribution.
