# Independent Workspace Domain Schema Review — Phase 2

**Review date:** 2026-11-09  
**Reviewed artifact:** `docs/phase2/workspace/workspace_schema_draft.sql` and companion schema tests  
**Status:** Findings / remediation plan. The SQL is a draft skeleton, not a production migration. Synthetic data only (D-014).

## Executive result

The current Workspace schema covers many entity families, but it is not yet a complete or internally consistent educational domain model. Several important business invariants are represented only in prose or JSON snapshots and are not enforced by relational constraints or executable tests. The following findings must be reconciled before Phase 2 can be approved.

## Findings

### HIGH

**WS-DOM-01 — Test attempt totals and response counts are not reconciled**

- `test_definitions` has no question_count / total_questions field.
- `test_attempts` stores correct/wrong/blank counters but has no constraint that they sum to the test's total question count.
- `test_responses` stores one response per question number, but no deferred aggregate validation ensures response rows match attempt counters.
- The stored score is not checked against the immutable scoring-policy snapshot.
- Result: inconsistent test analytics can be stored while all current row-level CHECK constraints pass.

Required design: define authoritative question-count semantics (fixed test definition vs per-attempt delivered question set), response finalization boundary, and a deterministic scoring-policy version/snapshot contract. Add transaction-safe finalization that reconciles counts and score before a submitted attempt becomes immutable. Tests must cover missing/duplicate responses, count mismatch, unanswered questions, negative marking ON/OFF and score boundary cases.

**WS-DOM-02 — Membership role source of truth — PARTIALLY ADDRESSED (2026-11-09)**

- The current branch removes scalar `workspace_memberships.role_key`; `membership_roles` is now the sole role-assignment relation. Synthetic fixtures were updated accordingly.
- This removes the two competing writable role sources.
- Role grant/revocation still lacks a dedicated append-only event ledger with authenticated actor/authentication-event evidence, and direct-DML restrictions for the projection have not been independently tested.

Remaining requirement: add auditable role grant/revoke commands/events and prove ordinary runtime/executor roles cannot mutate the role projection outside the authorized path. Do not mark this finding fully closed until those controls and tests exist.

**WS-DOM-03 — Guardian relationship/permission history is not auditable enough**

- `student_guardian_links` stores mutable verification state and revocation timestamps in one row.
- `guardian_permissions` stores mutable grants/revocation in one row and has no immutable grant/revoke event history or actor authentication event.
- The schema does not enforce consistency between `verification_state='revoked'` and `revoked_at`, or require verified authority to be current at permission use.
- A valid permission must be child-scoped and revalidated against the trusted legal-authority source; a stored `authority_ref` string alone is not proof.

Required design: append-only relationship verification/revocation and permission grant/revocation events, authenticated actor/evidence references, policy version and effective interval. Q-007 age/legal matrix remains open and must not be inferred.

### MEDIUM

**WS-DOM-04 — Assessment domain is incomplete**

- `exam_results` is one aggregate row per exam/student; per-subject results are not modeled.
- Test response error reason is a fixed enum and cannot represent the approved custom reason category.
- Test/exam scoring snapshot is JSON without schema/version constraints or deterministic recomputation test.
- Test definitions/attempts lack explicit publication/version lifecycle for changes to questions or scoring rules.

Required design: separate immutable assessment definition version from attempt snapshot; add per-subject exam result rows and a controlled custom error taxonomy; validate correct+wrong+blank totals and deterministic score formula.

**WS-DOM-05 — Curriculum and planning inputs are incomplete in the relational skeleton**

- No `subtopics` entity exists although the curriculum hierarchy calls for it.
- Student availability, school timetable, sleep windows and fixed commitments are not represented as normalized, versioned planning inputs in the schema.
- No explicit plan-item relation is visible in the current draft; `student_plan_versions.plan_content` is opaque JSON.
- Without input snapshots and rule versions with validated structure, deterministic plan generation is difficult to replay and explain.

Required design: define normalized planning constraints/schedule inputs, explicit PlanItem/PlanItem dependency and conflict rules, curriculum subtopic hierarchy, plus a versioned JSON schema if any snapshot remains JSON. Preserve the immutable input/rule snapshot used for each plan version.

**WS-DOM-06 — Activity taxonomy is narrower than the approved educational scope**

The `activities.activity_kind` enum currently contains only study, homework, review, test, class_followup and custom, while the product scope includes overdue/static/custom work, exam/quiz, exercise/problem-solving, summaries, flashcards, remediation and routine tests. It is not clear whether these are Activity kinds, linked domain records or tags.

Required design: define canonical activity taxonomy and relationships to specialized entities. Avoid an unrestricted polymorphic table without referential integrity.

**WS-DOM-07 — Class participation/schedule assignment is underspecified**

Classes and class sessions exist, but a clear student enrollment/participant relation and recurring-session expansion/exception model are absent. Ensure a class shared by students does not imply cross-student visibility and that timetable conflicts can be computed reproducibly.

**WS-DOM-08 — Capacity and ledger edge cases remain**

- Existing tests do not cover two different students racing for the final active-student slot or archived-capacity exclusion.
- Credit purchase/refund/renewal and payment-to-credit reconciliation are not modeled as a complete auditable workflow.
- Capacity counter reconciliation against active enrollments needs a repair/audit contract.

These were already recorded as open in the Supervisor Review; this review keeps them open.

**WS-DOM-09 — File and notification lifecycle controls are incomplete**

File metadata has quarantine/available/archive states but no explicit malware scan result, content-disposition policy, upload actor authentication event, or transfer generation binding. Notification payload schema and recipient authorization are not constrained, and queued notifications are not fenced against revoked permission/ownership changes.


### Remediation update — 2026-11-10

The scalar `workspace_memberships.role_key` field has been removed in the current branch and `membership_roles` is the canonical role-assignment projection. This closes the competing-role-source portion of WS-DOM-02 only. The append-only grant/revoke ledger, authenticated actor evidence, narrow command functions and direct-DML denial tests remain open.

A companion `WORKSPACE_GOVERNANCE_EVENT_CONTRACT.md` now specifies the target event/projection model for membership roles, permissions and guardian relationships/permissions. This is a design contract, not implemented schema or test evidence. WS-DOM-02 and WS-DOM-03 remain HIGH and open.

## Passed / useful foundations

- Workspace-local DB is correctly treated as a projection boundary; Control Plane remains global owner.
- Membership, assignments, guardian records, curriculum, planning, assessment, execution, risk, notes, capacity, files, notifications, legal holds, audit and credit ledger entity families are present as a starting skeleton.
- Published program/plan versions have mutation guards in the draft.
- Credit transactions, capacity events and audit events have append-only guards in the draft.
- Student Credit uses CRD and is separate from fiat money.
- Workspace DB does not claim global mobile uniqueness or cross-database foreign keys.

## Required remediation order

1. Resolve membership role source of truth and make membership/permission grant/revocation auditable.
2. Define guardian relationship and permission event model without deciding the still-open legal matrix.
3. Complete test/exam data consistency and immutable scoring snapshots.
4. Complete curriculum hierarchy, planning inputs, PlanItem and canonical Activity taxonomy.
5. Add class participation and recurring schedule semantics.
6. Complete capacity race/reconciliation and credit purchase/refund/renewal contracts.
7. Complete file upload/quarantine and notification recipient/generation fencing.
8. Add executable PostgreSQL constraints/triggers/tests and service-level tests for every accepted invariant.

## Gate impact

This review is a design/schema review, not an implementation approval. The HIGH findings WS-DOM-01 through WS-DOM-03 block acceptance of the current Workspace domain schema as complete. The MEDIUM findings must be resolved or explicitly deferred to a later authorized phase with documented dependencies and no false claim of Phase 2 completeness.

**Phase 2 Gate: NOT READY.** D-014 synthetic-only restriction remains in force.


### Remediation update — 2026-11-10 (governance event ledger draft)

Added an executable PostgreSQL event-ledger draft and synthetic regression tests for append-only behavior, per-aggregate sequencing, idempotent replay, payload mismatch, missing authority reference and inactive actor rejection. CI now installs the ledger in Workspace test databases and checks that runtime/worker/exporter/activation-function roles have no event-table or append-function access.

This is a partial schema/test improvement only. It does not update current role/permission/guardian projections and deliberately grants no service role permission to append events until a trusted authorization adapter and authority-verification contract are reviewed. WS-DOM-02 and WS-DOM-03 remain HIGH/open; Phase 2 remains NOT READY.

### Remediation update — 2026-11-10 (transactional governance projections)

The append-only event materializer now updates supported membership projections in the same transaction: role grant/revoke, permission grant/scope change/revoke, and membership lifecycle status. Suspension/end invalidates current role and permission projections. Guardian event families fail closed pending Q-007 and trusted legal verification.

The function has a dedicated non-login per-Workspace `governance_owner`, separate from the activation function owner, with narrowly scoped grants. Runtime, worker, exporter and activation function owner cannot execute it or access the event ledger. Synthetic CI tests cover projection effects, idempotent replay after actor suspension, payload mismatch, inactive actor rejection and role privilege boundaries.

This is still **not** an authorization command service. Authentication/authority references are not cryptographically verified, no grantability/self-escalation matrix is enforced, no application role can execute the function, and there is no API/service adapter. WS-DOM-02 remains HIGH/partially remediated; WS-DOM-03 remains HIGH. Phase 2 remains NOT READY.


### Verification update — CI #519 (2026-11-10)

The latest commit `d45753924513f9920f714b966361b9697e8264d5` passed the complete 13-step PostgreSQL workflow, including governance ledger/projection tests and per-Workspace privilege tests. Lifecycle transition tests verify invited→active, active→suspended, suspended→active, and end semantics; invalid transitions and role grants to suspended targets are rejected. Reactivation does not resurrect prior role/permission grants.

This closes the SQL-draft test gap for the supported membership projections only. It does not close WS-DOM-02's trusted authorization/anti-escalation requirements or WS-DOM-03 guardian legal-authority requirements. Phase 2 remains NOT READY.
