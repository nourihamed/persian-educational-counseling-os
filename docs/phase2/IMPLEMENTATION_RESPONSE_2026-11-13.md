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

---

# Second batch — 2026-11-13 (base `92dca8b`)

## 5. Defect found in existing Control Plane commands (HIGH, fixed)

**Finding EXE-1.** Every Control Plane command failed when called by its own executor role (`cp_identity_admission_executor`, `cp_transfer_executor`, `cp_rotation_executor`). Cause: the alias-coverage checks are `DEFERRABLE INITIALLY DEFERRED` constraint triggers. PostgreSQL runs deferred triggers at COMMIT with the privileges of the **calling** role, not of the SECURITY DEFINER function owner, and executors hold no table or assertion-function privilege. Observed error before the fix: `permission denied for function assert_claim_alias_coverage` on a plain admission by the admission executor.

Why it was not seen: every existing Control Plane suite (`cp_10`, `cp_15`, `cp_20`, `cp_25`) calls the commands as superuser; none switched identity.

Impact: fail-closed (nothing unauthorised became possible), but admission, ownership switch and HMAC rotation were unusable under the designed role model, and the role model had never been exercised end to end.

Fix: each command runs its queued coverage triggers inside its own security context (`SET CONSTRAINTS <named triggers> IMMEDIATE`, then back to `DEFERRED`) before returning. The admission owner additionally receives `EXECUTE` on the read-only `assert_all_claim_alias_coverage()`. Files: `cp_02`, `cp_05`, `cp_07`, `cp_06`. Regression: `cp_45_executor_identity_tests.sql` (EXE-01..05) calls each command under its real executor.

Residual: the transfer **case evidence and approvals** in EXE-02 are still staged by the table owner; no executor command for approval recording exists yet.

## 6. Contact change (was: contract only)

`cp_08_contact_change_draft.sql`, `cp_09_contact_change_roles_draft.sql`, tests `cp_40`, race `cp_46`.

- One-time proof rows (`contact_change_proofs`): registered insert-only by `cp_contact_proof_verifier`; bound to student, owner Workspace, ownership generation and the keyed fingerprint of the proposed number; single use; terminal once consumed or revoked.
- `change_student_mobile_contact()`: lock order gate → ownership → active claim → contact/alias rows; idempotent; replaces every live-key contact row and alias atomically; a global mobile+grade conflict rolls back everything including proof consumption; ownership, generation and the single claim are unchanged; audit row and outbox event carry keyed fingerprints or ids only.
- Separate owner/executor family with no access to transfer, rotation or admission.

Not enforced by the database: that a proof was really verified, that the HMACs were derived from the same number, guardian approval for a minor (Q-007), recovery when the old number is unavailable. Rejected attempts leave no row (the transaction rolls back), so recording a security event for a rejected attempt is a service responsibility. Applying decision A1 (external verifier, registration only) to contact proofs is a **proposal**.

Not tested: concurrent contact change versus HMAC rotation, and versus ownership switch (sequential gate and generation checks only).

## 7. Workspace archive (was: function/test missing)

`workspace/workspace_archive_transactions.sql`, tests `workspace/tests/workspace_archive_tests.sql`.

- `archive_student_enrollment()`: releases exactly one active-student slot atomically with `enrollments.state='archived'` and `students.lifecycle_state='archived'`; idempotent; second archive under a new key is rejected, so no underflow; historical enrollment and assignment rows are kept (assignments ended, not deleted); audit event.
- `capacity_counter_reconciliation` view: stored counter versus the sum of its event ledger.

Deliberately not implemented (open Product Owner decisions): credit treatment on archive (the command moves no credit), reactivation, archiving from `suspended`, Workspace suspension/closure, transfer reservations, per-counselor and per-branch capacity.

## 8. Still open after this batch

- Saga event schema and outbox/inbox reconciliation (HIGH) — not started.
- Approval-recording command for a workflow executor.
- Reactivation and the other capacity lifecycle rows that need policy.
- WS-DOM-04 remainder and the MEDIUM items.
- M-05 / M-06 definitions; PR #8–#11 disposition; PR #12 behind `main`.
