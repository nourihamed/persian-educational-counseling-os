# DATABASE.md

Status: DRAFT — Phase 0 — Conceptual model only. No migrations exist yet.

Stack (Master Prompt §49): PostgreSQL 15+, SQLAlchemy 2.x, Alembic. No manual production schema changes — every change is a migration.

## 1. Conceptual Entity Groups

### Identity & Tenancy
- `User` (base auth identity: email/phone, password hash, status)
- `Role`, `Permission` (table-driven RBAC, not a fixed enum — per DECISION_LOG D-005)
- `Counselor` (tenant root; 1:1 with a `User`)
- `Student` (1:1 with a `User` once activated; belongs to exactly one tenant via `CounselorStudent`)
- `Parent` (1:1 with a `User`; linked to one or more `Student` via explicit, permissioned relation)
- `PlatformAdmin` (cross-tenant; no implicit data access without audited action)

### Relationship
- `CounselorStudent` — fields per Master Prompt §13: `id, counselor_id, student_id, status(Active/Paused/Archived/Ended), started_at, ended_at, access_level, notes, created_at, updated_at`

### Student Profile & Curriculum
- `StudentProfile` (name, birth_date, grade, field, school, academic_year, goal, target, baseline_level, available_study_time, sleep_schedule, school_schedule, fixed_activities)
- `Subject` (tenant-editable: add/delete/rename/deactivate/reorder/categorize/importance/specialized-or-general)
- `CurriculumGrade`, `Book`, `Chapter`, `Topic`, `SubTopic` (hierarchy per §20, customizable)

### Programs (Versioned — §15, §71; minimum viable versioning is an MVP requirement per `DECISION_LOG.md` D-008 — **Accepted**, explicit Product Owner confirmation on 2026-10-10; `OPEN_QUESTIONS.md` Q-012 Resolved)

**Ownership has three distinct cases, which this document keeps explicitly separate so that none is silently conflated with another:**

1. **Tenant-owned `ProgramTemplate`** — the normal case: `tenant_id` is `NOT NULL`, the template belongs to exactly one Counselor's tenant, and it follows the same tenant-scoped access rules as every other tenant table.
2. **Potential platform-owned/shared `ProgramTemplate` — and, as a distinct sub-question, its `ProgramVersion` rows** — mentioned in Master Prompt §14 as a future possibility ("ممکن است Template سطح‌پلتفرم هم باشد"), where a template could be provided by the platform itself rather than a single tenant. **This is explicitly unresolved design work, not a decision made in this document or anywhere else in Phase 0 — see `OPEN_QUESTIONS.md` Q-013 for the full, two-part breakdown.** Two separate things are undecided, not one:
   - **The `ProgramTemplate` itself:** not yet decided whether a platform-owned row would have `tenant_id = NULL`, a distinct `is_platform_template` flag, a different table entirely, or something else — and not yet decided what authorization rule would govern who can read/write it (e.g., read-only to all tenants vs. copy-on-use vs. something else).
   - **Its `ProgramVersion` rows, separately:** a `ProgramTemplate` being platform-owned does **not** automatically determine how the `ProgramVersion`s published under it are owned/authorized — that is an independent open question (Q-013 part 2), not something this document decides or implies. A platform-owned template's versions might themselves stay platform-level, might require a tenant to "claim"/copy a version before use, or something else entirely not yet proposed. **No model has been chosen for `ProgramVersion` ownership in the platform-template case.**

   Whatever the eventual design for either of these two, it applies **only to the template/version catalog entries themselves**, never to a student's enrollment or plan (see case 3).
3. **`StudentProgramEnrollment`, `Plan`, and `PlanVersion` — always tenant-owned and student-owned, with no ambiguity and no exception.** Regardless of whether the `ProgramVersion` a student is enrolled in came from a tenant-owned or a (possible, future) platform-owned template — and regardless of how that `ProgramVersion` itself ends up owned once Q-013 part 2 is decided — the `StudentProgramEnrollment` row itself always carries `tenant_id` (the counselor's tenant) and `student_id`, `NOT NULL`, and is governed by the same tenant-and-student-scoped repository access pattern as every other student-facing row (`ARCHITECTURE.md` §2/§3/§6). **A platform-owned template or platform-owned ProgramVersion does not and cannot imply that the resulting student enrollment or plan is platform-owned or visible across tenants.** This preserves, without exception, the requirement that no counselor can access or modify another tenant's students or data.

Fields (conceptual, not implemented):
- `ProgramTemplate` (`id`, `tenant_id` — nullable only if/when the platform-template case above is formally designed, `NOT NULL` for every tenant-owned template today, `name`, ..., stable identity that outlives any individual version)
- `ProgramVersion` (`id`, `program_template_id`, `version_number`, immutable snapshot of subjects/weekly rules/study/review/test rules, `created_by` (actor attribution), `created_at`, `published_at`; immutable once published — no `UPDATE` after publish, only new rows. **Ownership/authorization field(s) for this table are explicitly not yet decided for the platform-template case** — see case 2 above and `OPEN_QUESTIONS.md` Q-013 part 2; no `tenant_id` or equivalent is asserted here one way or the other for that case)
- `StudentProgramEnrollment` (`id`, `tenant_id` `NOT NULL`, `student_id` `NOT NULL`, student ↔ a specific `ProgramVersion`, not the template — this is the mechanism that records which `ProgramVersion` produced each student's plan, satisfying the "explain the origin of an existing plan" requirement in D-008)
- `MarketSegment` (§17) and `ProgramTemplateSegment` (which segments a template targets)

### Planning (Versioned — §72; minimum viable versioning is an MVP requirement per D-008 — Accepted, Q-012 Resolved)
- `Plan` (`id`, `tenant_id`, `student_id`, scope: daily/weekly/monthly/exam/review/recovery; belongs to a student + period — the stable identity that persists across versions)
- `PlanVersion` (`id`, `plan_id`, `version_number`, `created_by` (actor attribution), `created_at`, `activated_at`, `program_version_id` nullable FK recording which `ProgramVersion`, if any, informed this plan version; immutable once superseded — a later version never overwrites an earlier published one, consistent with D-008's "no silent overwrite" requirement)
- `PlanItem` (a scheduled activity instance within a specific plan version)
- Which `Plan` states are directly editable in place versus which require creating a new `PlanVersion`, and how an existing plan behaves when its source `ProgramVersion` is later updated, are open schema decisions for Phase 2 — not decided here (see D-008 points 5 and 7). D-008's acceptance (Q-012 Resolved) settles that these questions *must* have an answer before implementation, not what that answer is.
- Every row above carries `tenant_id` (directly or via its parent `Plan`/`ProgramTemplate`) and is subject to the same tenant-scoped repository access pattern as every other tenant table (`ARCHITECTURE.md` §2/§3/§6) — there is no version-specific exception to tenant isolation or authorization.

### Activities & Records (§21–§28)
- `Activity` (polymorphic-ish base: type = Study/Test/TestAnalysis/Review/Exam/Quiz/SchoolAssignment/OnlineClass/InPersonClass/Exercise/ProblemSolving/Summary/Flashcards/Remediation/Project/OverdueWork/RoutineTest/Custom)
- `StudySession` (subject, topic, start, end, duration, goal, result, mastery_before, mastery_after, notes)
- `Test` (subject, topic, source, question_count, correct, wrong, unanswered, duration, percentage, date) — constraint: `correct+wrong+unanswered = question_count` unless explicitly overridden
- `ErrorRecord` (error_type incl. custom, linked to a `Test`/`Activity`)
- `Exam` (title, date, time, duration, type, online/offline, source, goal) + `ExamResult` (per subject: correct/wrong/unanswered/percentage/score/rank/time)
- `ClassSession` (online/in-person/recurring; teacher, subject, date, time, duration, platform, link, location)
- `Assignment` (title, subject, description, due_date, priority, estimated_time, actual_time, status, attachment)
- `ReviewSchedule` (original_activity_id, review_date, method, mastery_before, mastery_after, result, notes) — generation governed by Review Engine rules (default 1-3-7), duplicate-prevention is a DB-level uniqueness constraint on `(original_activity_id, review_offset)`

### Progress / Risk / Analytics
- `ProgressSnapshot` (per student/period; documented formula inputs, not a black box — per §38, §35)
- `RiskAssessment` (student, computed_at, outcome, **reasons[]** — explainability stored, not just the score)

### Billing (§10, §45)
- `Product`, `Plan` (commercial plan, distinct from the planning-engine `Plan` above — naming collision noted, see Decision below), `Subscription`, `Order`, `Payment`, `Invoice`
- `StudentCredit` (tenant-level balance, **derived**, not directly writable)
- `CreditTransaction` (append-only ledger: `+10 purchased`, `-1 activated`, `+1 refunded`, ...)
- `Coupon`, `Promotion`

### Notifications
- `Notification` (content, type, tenant_id, target_user_id)
- `NotificationDelivery` (channel: InApp/Telegram/SMS; status; retry metadata)

### Audit
- `AuditLog` (tenant_id nullable for platform-level actions; actor, action, entity, before/after where applicable, created_at)

## 2. Naming Decision Needed
"Plan" is used in Master Prompt both for the **commercial Plan** (billing tier) and the **study Plan** (daily/weekly schedule, now also carrying its own `PlanVersion` per the accepted D-008 policy). This document proposes renaming the commercial one to `BillingPlan` in the actual schema to avoid ambiguity, so that `Plan`/`PlanVersion` unambiguously refer to the educational, student-facing concept. Recorded as a proposal in `DECISION_LOG.md` (D-006); **D-006 itself is still Proposed, not yet approved** — this is a separate, independent decision from D-008. D-008's acceptance on 2026-10-10 settled only the versioning policy; it did not approve or otherwise decide D-006's naming question.

## 3. Cross-cutting Rules
- Every tenant-scoped table has a `tenant_id` column, indexed, `NOT NULL`.
- Append-only tables (`CreditTransaction`, `AuditLog`) have no `UPDATE`/`DELETE` grants at the application layer.
- Every "versioned" concept (`ProgramVersion`, `PlanVersion`) is immutable once superseded; edits create new rows, never mutate history.
- Soft-delete (`Archived`/`Ended` status) is preferred over hard delete for anything with historical/reporting value (students, plans, programs).

## 4. Explicitly Deferred
- Full column-level types, constraints, and indexes → Phase 2.
- Actual ERD diagram (image) and Alembic migrations → Phase 2.
- Final decision on RLS policy definitions → Phase 1/2, pending Q-001.
- Final column-level design of `ProgramVersion`/`PlanVersion` (exact fields beyond the conceptual ones listed above, editable-vs-new-version state rules, template-update-vs-existing-plan behavior) → Phase 2. The MVP Versioning *policy* itself is no longer pending (`DECISION_LOG.md` D-008 — Accepted, `OPEN_QUESTIONS.md` Q-012 Resolved); what remains pending is ordinary Phase 2 schema design work, not a Product Owner decision. Nothing describing `ProgramVersion`/`PlanVersion` in this document has been implemented as a migration, table, or endpoint.
