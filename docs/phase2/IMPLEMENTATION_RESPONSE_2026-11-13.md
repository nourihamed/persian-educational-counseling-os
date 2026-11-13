# Implementation response to Phase 2 exit findings — 2026-11-13 (NOT a supervisor review)

**Author:** implementation agent. **Base:** PR #12 head `fc33baa`. Drafts only, synthetic data only (D-014). Nothing here approves Phase 2, closes a finding, or decides an open Product Owner question. Closure is the independent Supervisor's call.

## 1. What changed

| Finding | Change | Files |
|---|---|---|
| WS-DOM-01 assessment totals/responses | `test_definition_versions` (draft → published, then immutable); attempts bind to one published version by composite FK and carry an immutable `question_count`; attempts start as `started`; submission is rejected unless there is exactly one response per delivered question and the counters equal the grouped responses; submitted attempts and their responses are immutable; `submit_test_attempt()` is atomic and idempotent (same key + same payload replays, different payload rejected); custom error reason needs a description | `workspace/workspace_schema_draft.sql`, `workspace/tests/workspace_assessment_guardian_tests.sql`, `workspace/tests/workspace_assessment_submit_race.sh` |
| WS-DOM-03 guardian history | Append-only `guardian_link_events` and `guardian_permission_events` (actor, authentication-event, evidence, policy version, effective interval); a projection change without its event in the same transaction is rejected at commit; `revoked` ⇔ `revoked_at`; revoked link is terminal; permissions are immutable except one revocation and require a verified link; `guardian_permissions_effective` view | same schema file and suite |
| Transfer approvals as events | `transfer_approvals` is now immutable evidence with unique assertion id and nonce digest, and **no** `UNIQUE(case_id, approval_kind)`; `transfer_approval_revocations` is a separate append-only table; one current approval per kind; recording and revoking lock the transfer case row, the same lock the ownership switch takes; the switch counts only unrevoked, unexpired approvals | `control_plane/schema/cp_01`, `cp_02`, `cp_06`; `control_plane/tests/cp_35_approval_event_tests.sql`, `cp_36_approval_revocation_race.sh` |
| WS-DOM-02 role source of truth | No new code. The remaining requirement named in the review (append-only grant/revoke events with actor and authentication evidence; runtime cannot write the projection outside the authorised path) is covered by the governance event ledger, the proof-receipt command boundary and the role catalog tests already on this branch. Offered as evidence for the Supervisor to judge | `workspace/workspace_governance_events_draft.sql`, `workspace/receipts/`, `workspace/tests/workspace_role_privilege_tests.sql` |

## 2. What the database does and does not enforce

- **Score:** the database checks counts, not the score formula. `score` is supplied by the service, as the assessment contract requires. No scoring formula was added.
- **Delivery mode:** `fixed` forces the attempt denominator to equal the version's question count. `per_attempt` exists only so the schema does not preclude adaptive delivery; adaptive delivery is **not** approved for MVP ("Assessment semantics" in `PHASE2_OPEN_DECISIONS.md` stays open).
- **Guardian authority:** event references are opaque. The database does not verify identity, relationship or legal authority, and encodes no age or legal matrix. Q-007 stays open. Guardian history tables have no runtime grant at all (fail closed).
- **Approvals:** the database keeps history, uniqueness and ordering. It does not verify the assertion signature or the approver's authority; that is the verifier and Phase 4.
- **Owner/superuser:** can still disable triggers or change grants. Deployment control, not a schema guarantee.

## 3. Not done in this change (still open against the exit criteria)

- Approval-recording **command** for a dedicated workflow executor (tables are written by the owner in tests; no executor grant was added).
- Contact-change schema, function and tests (contract only).
- Saga event schema and outbox/inbox reconciliation with the Control Plane DDL.
- Workspace suspension/archive/reactivation lifecycle and its capacity effects.
- WS-DOM-04 remainder: per-subject exam results, exam definition versions, analysis versions.
- MEDIUM items in `PHASE2_EXIT_CRITERIA.md` section 3.
- PR #8–#11 disposition and bringing PR #12 up to date with `main`.
- M-05 and M-06: their definitions are not in the repository.

## 4. Evidence

See `TEST_PLAN.md` (section dated 2026-11-13). Local runs are author-executed and not independently reproduced.
