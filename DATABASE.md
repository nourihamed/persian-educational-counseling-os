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

### Programs (Versioned — §15, §71)
- `ProgramTemplate` (owned by a tenant or, later, platform-provided)
- `ProgramVersion` (immutable snapshot: subjects, weekly rules, study/review/test rules)
- `StudentProgramEnrollment` (student ↔ specific `ProgramVersion`, not the template)
- `MarketSegment` (§17) and `ProgramTemplateSegment` (which segments a template targets)

### Planning (Versioned — §72)
- `Plan` (scope: daily/weekly/monthly/exam/review/recovery; belongs to a student + period)
- `PlanVersion` (v1, v2, v3... immutable once superseded)
- `PlanItem` (a scheduled activity instance within a plan version)

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
"Plan" is used in Master Prompt both for the **commercial Plan** (billing tier) and the **study Plan** (daily/weekly schedule). This document proposes renaming the commercial one to `BillingPlan` in the actual schema to avoid ambiguity. Recorded as a proposal in `DECISION_LOG.md`; not yet approved.

## 3. Cross-cutting Rules
- Every tenant-scoped table has a `tenant_id` column, indexed, `NOT NULL`.
- Append-only tables (`CreditTransaction`, `AuditLog`) have no `UPDATE`/`DELETE` grants at the application layer.
- Every "versioned" concept (`ProgramVersion`, `PlanVersion`) is immutable once superseded; edits create new rows, never mutate history.
- Soft-delete (`Archived`/`Ended` status) is preferred over hard delete for anything with historical/reporting value (students, plans, programs).

## 4. Explicitly Deferred
- Full column-level types, constraints, and indexes → Phase 2.
- Actual ERD diagram (image) and Alembic migrations → Phase 2.
- Final decision on RLS policy definitions → Phase 1/2, pending Q-001.
