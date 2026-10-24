# DATABASE.md

Status: conceptual domain model only; no migrations exist. Current tenant-isolation topology is governed by D-020/D-023 and Phase 1 design docs.

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

**MVP ownership rule (D-012 accepted; Q-013 resolved):**

1. **Tenant-owned `ProgramTemplate`:** every template in MVP belongs to exactly one Counselor Tenant and has `tenant_id NOT NULL`.
2. **Tenant-owned `ProgramVersion`:** every version in MVP belongs to the same Tenant as its source `ProgramTemplate`. Database foreign-key/unique constraints or equivalent safeguards must prevent a version from linking to a template owned by another Tenant.
3. **Platform-owned/shared catalog:** platform-level `ProgramTemplate` and their `ProgramVersion` rows are explicitly out of MVP. Do not implement nullable `tenant_id`, mixed-ownership shared catalog rows, or global read-only access based on the old hypothetical case. If a central catalog is needed later, its ownership, publication, copying, versioning, and authorization model must be decided before implementation.
4. **Student data remains strictly scoped:** `StudentProgramEnrollment`, `Plan`, and `PlanVersion` always carry tenant/student scope and never become platform-owned or cross-tenant-visible as a result of template/version reuse. Every operation on a template or version requires authorization.


Fields (conceptual, not implemented):
- `ProgramTemplate` (`id`, `tenant_id NOT NULL`, `name`, ..., stable identity that outlives any individual version; MVP supports tenant-owned templates only)
- `ProgramVersion` (`id`, `program_template_id`, `version_number`, immutable snapshot of subjects/weekly rules/study/review/test rules, `created_by` (actor attribution), `created_at`, `published_at`; immutable once published — no `UPDATE` after publish, only new rows. **MVP ownership:** tenant-scoped, same Tenant as the source `ProgramTemplate`; platform-template versions are out of MVP under D-012.
- `StudentProgramEnrollment` (`id`, `tenant_id` `NOT NULL`, `student_id` `NOT NULL`, student ↔ a specific `ProgramVersion`, not the template — this is the mechanism that records which `ProgramVersion` produced each student's plan, satisfying the "explain the origin of an existing plan" requirement in D-008)
- `MarketSegment` (§17) and `ProgramTemplateSegment` (which segments a template targets)

### Planning (Versioned — §72; minimum viable versioning is an MVP requirement per D-008 — Accepted, Q-012 Resolved)
- `Plan` (`id`, `tenant_id`, `student_id`, scope: daily/weekly/monthly/exam/review/recovery; belongs to a student + period — the stable identity that persists across versions)
- `PlanVersion` (`id`, `plan_id`, `version_number`, `created_by` (actor attribution), `created_at`, `activated_at`, `program_version_id` nullable FK recording which `ProgramVersion`, if any, informed this plan version; immutable once superseded — a later version never overwrites an earlier published one, consistent with D-008's "no silent overwrite" requirement)
- `PlanItem` (a scheduled activity instance within a specific plan version)
- Which `Plan` states are directly editable in place versus which require creating a new `PlanVersion`, and how an existing plan behaves when its source `ProgramVersion` is later updated, are open schema decisions for Phase 2 — not decided here (see D-008 points 5 and 7). D-008's acceptance (Q-012 Resolved) settles that these questions *must* have an answer before implementation, not what that answer is.
- **Tenant-column contract (conceptual; no migration exists):** `Plan`, `PlanVersion`, and `PlanItem` are expected to carry direct, indexed, `NOT NULL` `tenant_id` columns for explicit ownership and defense in depth, with constraints ensuring child and parent tenant identifiers agree. Under active D-020 Alt-5, each tenant has its own database and tenant-specific runtime credential within its cell; `tenant_id` and application authorization do not replace the cell's host/network/credential boundary. All three entities remain subject to tenant-and-student-scoped authorization. **This statement applies only to `Plan`/`PlanVersion`/`PlanItem`, not `ProgramVersion`**, whose MVP ownership is tenant-scoped under D-012 and must match its source `ProgramTemplate`. `ProgramTemplate` is not a parent of `Plan` and does not supply the tenant identifier for these rows.

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
- Every **tenant-owned** row/table has a direct `tenant_id` column, indexed and `NOT NULL`. Do not interpret this as requiring `tenant_id` on platform-owned/global catalog rows. MVP does not support platform-owned `ProgramTemplate`/`ProgramVersion` rows (D-012). Do not implement nullable-tenant or mixed-ownership catalog rows. A future platform catalog requires a separate decision before implementation. Regardless of catalog ownership, student enrollments, plans, and all student-facing records remain tenant-owned and isolated.
- Append-only tables (`CreditTransaction`, `AuditLog`) have no `UPDATE`/`DELETE` grants at the application layer.
- Every "versioned" concept (`ProgramVersion`, `PlanVersion`) is immutable once superseded; edits create new rows, never mutate history.
- Soft-delete (`Archived`/`Ended` status) is preferred over hard delete for anything with historical/reporting value (students, plans, programs).

## 4. Explicitly Deferred
- Full column-level types, constraints, and indexes → Phase 2.
- Actual ERD diagram (image) and Alembic migrations → Phase 2.
- Detailed tenant schema/constraints, least-privilege runtime identities, cell routing, network/credential boundaries, backup independence and executable isolation tests → design contracts in Phase 1 and implementation in authorized later phases. D-009/Q-001's former shared-database mechanism is historical; active topology is D-020/D-023.
- Final column-level design of `ProgramVersion`/`PlanVersion` (exact fields beyond the conceptual ones listed above, editable-vs-new-version state rules, template-update-vs-existing-plan behavior) → Phase 2. The MVP Versioning *policy* itself is no longer pending (`DECISION_LOG.md` D-008 — Accepted, `OPEN_QUESTIONS.md` Q-012 Resolved); what remains pending is ordinary Phase 2 schema design work, not a Product Owner decision. Nothing describing `ProgramVersion`/`PlanVersion` in this document has been implemented as a migration, table, or endpoint.


## Tenant Isolation — Current Alt-5 Direction (D-020 / D-023; design only)

The former D-009/Q-001 shared-database mechanism is retained as historical decision context, not the active isolation topology. The active design is Alt-5 hybrid isolation cells: each cell has a distinct host/VM and network boundary and its own PostgreSQL cluster/instance; each tenant has a separate database and tenant-specific runtime credential within that cell. D-023 requires Level 3 infrastructure/administrative independence for production cells and Level 4 independent administrative control for critical backups/recovery. Q-023 remains open; no provider, hosted topology, cost or capacity is verified.

- Tenant-owned relationships must use composite foreign keys/unique constraints or equivalent safeguards so a child row cannot reference a parent from another tenant.
- Runtime credentials must be least-privileged; ordinary tenant identities cannot access another tenant database or another cell.
- RLS may be applied as defense in depth within a tenant database, but it is not the cell boundary and does not protect against host/root compromise.
- Trusted tenant membership and cell mapping are resolved server-side; request-supplied tenant/cell IDs are never authoritative.
- Test API/object authorization, direct database credentials, network reach, jobs, reports/exports, files, notifications, backup administration/keys, restore lifecycle, revocation and privileged access.

This is a design decision only; no migrations, roles, policies or executable tests exist yet.
