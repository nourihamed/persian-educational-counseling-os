# Deterministic Planning Inputs & Plan Item Contract — Phase 2

**Status:** DRAFT / NOT APPROVED. Domain/data contract only. No unexplained AI planning or unapproved scheduling policy is authorized. Synthetic data only (D-014).

## 1. Purpose

The planning engine must produce deterministic, explainable, replayable and adjustable student plans. Its inputs and outputs must be modeled as first-class domain data, not hidden inside an opaque JSON blob. The core loop is Plan → Execute → Record → Analyze → Learn → Adjust → Plan Again.

AI may later assist with recommendations and explanations, but the core scheduling decision and persisted plan must be reproducible from structured inputs and a versioned deterministic ruleset.

## 2. Normalized planning inputs

The Workspace domain model must represent, at minimum:

- Student timezone and local planning calendar (canonical event timestamps remain UTC; planned local date/time/timezone is preserved).
- School timetable and school-day exceptions.
- Weekly availability windows and date-specific availability exceptions.
- Sleep/rest windows and fixed personal commitments.
- Fixed online/offline/in-person classes and recurring class sessions/exceptions.
- Exams, quizzes, assignments, due dates and estimated remaining work.
- Scheduled reviews and spaced-review cadence.
- Subject/topic curriculum hierarchy and student mastery/weakness evidence.
- Overdue, unfinished and deferred activities, with original due date and deferral history.
- Counselor-defined priorities, constraints and approved overrides.
- Student plan preferences that are explicitly approved and versioned.

Every input has source, owner, effective interval, timezone semantics, last-updated actor, version and provenance. Derived inputs must retain source references.

## 3. Plan and PlanVersion

- `Plan` is the stable identity for one student planning stream within one Workspace.
- `PlanVersion` is an immutable generated or manually revised snapshot.
- Each version stores algorithm/rule version, generation timestamp, effective local date range, timezone, normalized input snapshot/reference and hash, policy/configuration snapshot and hash, and actor/initiator.
- A published version is immutable. Adjustments create a new version with a parent/supersedes reference and a reason.
- The system must be able to replay a plan version from the same input snapshot and rule version and produce the same normalized output/hash.
- A manual counselor override is explicit, attributable, reasoned and retained in history; it does not silently rewrite the algorithm's original output.

## 4. Explicit PlanItem model

Each PlanVersion has normalized PlanItems with:
- stable item ID and version membership;
- student, subject, topic/subtopic and optional source entity references;
- activity kind and typed source relation (exam, quiz, class follow-up, assignment, review, test, remediation, routine, custom task, etc.);
- planned local date, start/end or duration, timezone and UTC projection;
- estimated workload, priority and urgency;
- dependencies/prerequisites and conflict group where applicable;
- status and completion/deferment reason;
- generation provenance (rule ID/version) and human-readable explanation/reason codes;
- source snapshot/version and idempotency key for generation.

Do not use an unrestricted polymorphic foreign key with no referential integrity. Use typed nullable FKs with exactly-one-source constraints, or normalized subtype/link tables. The choice must be consistent across API and DB.

## 5. Deterministic scheduling invariants

- Fixed commitments are never overwritten by generated study tasks.
- No scheduled task overlaps another fixed or generated task for the same student unless an explicit approved parallel-activity rule permits it.
- Sleep/rest and unavailable windows are hard constraints unless a specific policy marks them soft; the ruleset records which.
- Exams, due dates, overdue work, reviews, weak subjects, mastery, priority and remaining time are explicit inputs to deterministic ranking/scheduling.
- Every unscheduled/deferred item has a machine-readable reason (no available slot, dependency blocked, expired, insufficient remaining time, policy conflict, etc.).
- Every generated item has a reason explaining why it was selected, why that slot was chosen and which constraints were considered.
- Same inputs + same rule/configuration version + same seed (if randomness is ever approved) produce the same output.
- A new plan version never mutates historical execution records; completion links to the relevant plan item/version and is preserved across replanning.

## 6. Execution and feedback linkage

- StudySession and activity execution records reference the plan item/version when generated from a plan.
- Ad-hoc work may exist without a plan item but must retain actor/source and may be considered in future input snapshots.
- Completion, actual duration, test results, errors, reviews and mastery updates are recorded independently from planned values.
- Replanning consumes actual execution evidence and preserves the previous plan version and explanation.
- Overdue work is not silently duplicated or dropped; carry-forward creates a linked item in a new version with original provenance and explicit defer reason.

## 7. Required schema structures

The Workspace schema should include or map:
- `school_schedule_blocks` and schedule exceptions;
- `student_availability_windows` and date-specific exceptions;
- `sleep_rest_windows` and fixed commitments;
- recurring `classes` / `class_sessions` / student participation;
- exam, quiz and assignment calendar references;
- review schedule and mastery evidence;
- immutable `plan_versions` with input/rule/config snapshots;
- normalized `plan_items` and dependency/link tables;
- plan-generation command/idempotency and explanation/reason records.

Existing `student_plan_versions.plan_content` JSON may remain as a transport/export snapshot, but cannot be the only queryable source for scheduling, conflict detection, execution linkage or analytics. If JSON is retained, its schema version and validation rules are mandatory.

## 8. Required acceptance tests

1. Replaying identical input/rule snapshots yields identical PlanItem set and output hash.
2. Changed input or rule version yields a new immutable PlanVersion; old versions remain unchanged.
3. Fixed class/school/sleep/availability constraints cannot be violated without an explicit policy override.
4. Generated items do not overlap; conflict detector is deterministic and timezone/DST/Jalali boundaries are tested.
5. Every unscheduled item has a reason code; every generated item has rule provenance and explanation.
6. Manual counselor override records actor, reason, before/after diff and policy version.
7. Completed work remains linked to its original PlanVersion after replanning.
8. Overdue carry-forward preserves original source/due date and does not double-count.
9. Cross-Workspace and cross-student plan/inputs/outputs are denied.
10. Missing/invalid timezone, ambiguous local time, daylight-saving transition and Jalali month/year boundary are handled deterministically.
11. Background generation is Workspace-scoped, idempotent and rejects stale ownership generation.
12. AI-produced text cannot alter authoritative PlanItem schedule or bypass deterministic validation.

All tests are specifications until schema/service implementations are present and executed.

## 9. Open product inputs

- Exact priority weights, scheduling tie-breakers and minimum/maximum work-block policies.
- Whether a student may manually edit generated items or only request changes through a counselor.
- Rules for soft vs hard sleep/rest/availability constraints.
- Whether randomized/adaptive plan generation is permitted; default is deterministic with no randomness.
- MVP activity taxonomy and specialized entity coverage.

Do not invent weights or timing thresholds to make the engine appear complete.

**Gate impact:** WS-DOM-05 and WS-DOM-06 remain open until the Workspace schema and test plan are reconciled with this contract. Phase 2 remains NOT READY.
