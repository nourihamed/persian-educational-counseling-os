# Workspace Database Design — Phase 2 draft

**Status:** DRAFT / NOT APPROVED. Design contract only; not a production migration. Synthetic data only under D-014.
**Authority:** Product Owner decisions consolidated through 2026-11-07. Control Plane owns global student identity, current ownership and global mobile+grade claims. A Workspace DB owns only that Workspace's educational and operational records.

## 1. Topology and trust boundary

- Each Workspace has a logically and credential-isolated PostgreSQL database. The deployment cell may host at most two Workspaces provisionally; this is not capacity evidence or pilot authorization.
- A Workspace DB MUST NOT be treated as an authority for global ownership, global mobile+grade uniqueness, or transfer finalization.
- Control Plane IDs are opaque references. No cross-database foreign keys are claimed.
- A request must obtain a current ownership decision from the Control Plane before reading or writing student data. If Control Plane validation is unavailable, stale, ambiguous, or fails, access is denied (fail-closed).
- Every student projection carries `platform_student_id` and `ownership_generation`. Every write path checks the expected generation and the Workspace identity from trusted server-side context.
- A Workspace credential is never shared with another Workspace. Membership in one Workspace grants no access to another.

## 2. Workspace-local entity groups

### Workspace configuration
- `workspace_profile`: local display/configuration record; the authoritative Workspace registry remains Control Plane.
- `branches`: belong to this Workspace only. Independent Counselor Workspace has no branches; Organization Workspace may have branches.
- `workspace_memberships`: Platform User membership with Workspace-scoped role/status. Platform User identity is external; no global user table is copied.
- `counselor_assignments`: active assignment of a counselor to a student; at most one responsible counselor per active student and at most one active primary branch per counselor/student assignment according to PO decision 4. Assignment changes require an authorized owner/manager and destination counselor acceptance.

### Student and guardian projections
- `students`: local educational profile keyed by a local UUID and unique `platform_student_id` in this Workspace.
- `enrollments`: local operational projection with lifecycle and ownership generation. It is not the global ownership registry.
- `student_guardian_links`: relationship and verification status. A link is not, by itself, proof of legal authority.
- `guardian_permissions`: per-child, per-scope permissions with grantor, verified authority reference, scope, validity interval, revocation and audit reference. Q-007 remains open for the detailed age/legal matrix; deny sensitive access unless a specific valid permission exists.

### Educational domain
- Curriculum/reference catalog and student-specific mastery/progress are separate concepts. Platform-owned reference curriculum is not copied as mutable Workspace-owned content.
- `program_templates` and `program_versions`: minimum auditable versioning; published versions immutable; edit creates a new version.
- `student_plans` and `student_plan_versions`: each version records its source template version, input snapshot/rule version, author, approval and publication time. Published versions are immutable.
- Study sessions, tests, test analyses, exams, classes, assignments, reviews, routines, progress, risks and counselor notes remain Workspace-local.
- Counselor-private notes and confidential communications are not included in transfer snapshots by default.

### Commercial and audit
- `credit_wallets` and `credit_transactions`: Workspace-owned append-only Student Credit ledger. MVP wallet unit is `CRD` (a credit unit, not IRR or another fiat currency); monetary payments, invoices and counselor fees remain separate billing/finance records. Activation debit and activation are atomic/idempotent; reversal is a compensating entry, never an update/delete.
- Capacity/quota is independent of Student Credit and is checked atomically at activation.
- Security, finance, sensitive access, transfer projection, permission changes and critical domain events are audited through append-only audit records. Private file metadata stores provider-neutral object keys (not public URLs), checksums and encryption-key version; server-side authorization is required before short-lived signed URL issuance. In-App notifications use template versions and idempotency keys. Legal holds are explicit and auditable; retention durations remain unapproved and must not be invented. Never store OTPs, tokens, passwords, encryption keys or unnecessary confidential content in audit payloads.

## 3. Required local invariants

1. Unique `platform_student_id` per Workspace.
2. Enrollment generation must equal the latest generation validated by Control Plane at the time of mutation.
3. Only one active local enrollment per student in this Workspace.
4. At most one active responsible counselor per active enrollment.
5. At most one active primary branch per applicable assignment.
6. Membership and role are Workspace-scoped; no query accepts a caller-supplied Workspace as authority.
7. Guardian permissions are child-scoped and scope-specific; revoked/expired permissions are ineffective.
8. Published program/plan versions are immutable.
9. Credit ledger is append-only; wallet balance is derived or transactionally maintained against the ledger.
10. Archive does not consume active student capacity; activation/reactivation performs atomic capacity and entitlement checks.

## 4. Transfer projection lifecycle

- Source write freeze is coordinated by a durable transfer workflow, not by a best-effort UI flag.
- Snapshot contains only explicitly transferable educational records and excludes private counselor notes/confidential communications by default.
- Destination import is staged and inaccessible to users until integrity checks pass and Control Plane ownership switches.
- On successful Control Plane switch, destination projection is activated at generation N+1. Source projection becomes read-only/ended and every stale write is rejected.
- Outbox/inbox messages are at-least-once; consumers deduplicate by immutable event ID and generation.
- If the switch has occurred, recovery proceeds forward. No rollback to source through a state toggle; a reverse move is a new authorized transfer.

## 5. Authorization contract

Authorization requires all of:
- authenticated Platform User principal;
- active membership in this exact Workspace;
- permission for the requested action and resource;
- student assignment/relationship scope where applicable;
- current Control Plane owner Workspace and generation match;
- valid consent/guardian scope where applicable.

A role label alone is insufficient. Cross-Workspace and nonexistent objects return the same 404. A visible object with a forbidden action may return 403.

## 6. Schema status and omissions

This document defines responsibilities and invariants, not a complete executable schema. The companion `workspace_schema_draft.sql` now includes a draft relational skeleton for membership/roles, enrollment/assignment, guardian permissions, curriculum/subject/chapter/topic, mastery, activities/study sessions, tests/attempts/responses, exams/results, classes/sessions, assignments/reviews/routines, progress/risk/counselor notes, capacity counters, audit, versioning and credit ledger. It is still not the complete production domain model: activation + credit + capacity transaction orchestration, complete retention/file/notification structures, authorization enforcement and several domain-specific constraints remain open. No migrations or runtime services are authorized.

## 7. Acceptance tests (not executed here)

- Workspace A credentials cannot read/write Workspace B records.
- Missing/unavailable Control Plane ownership validation denies access.
- Stale ownership generation rejects reads/writes requiring current ownership.
- Same platform student cannot have two active local enrollments.
- At most one responsible counselor per active enrollment.
- Manager scope and counselor assignment scope are enforced at object level.
- Parent permission is isolated per child and per scope; expired/revoked permission denied.
- Published versions cannot be mutated/deleted.
- Credit debit and activation are atomic/idempotent; reversals append compensating entries.
- Archived students do not consume active capacity; concurrent activation cannot exceed capacity.
- Transfer source/destination projection and generation fencing work under retries, duplicate and out-of-order events.

**Gate:** Phase 2 remains NOT READY until schema reconciliation, executable tests, independent review and written PO authorization. D-014 remains in force.


## 8. Workspace database roles and credentials

PostgreSQL roles are cluster-wide, not database-local. The companion `workspace_roles_setup_draft.sql` therefore derives every group/login role name from the canonical 32-character lowercase hexadecimal Workspace UUID. It revokes database CONNECT/TEMPORARY from PUBLIC and grants CONNECT only to that Workspace's runtime/worker/exporter logins plus the migration operator. Runtime cannot directly update enrollment state, change student lifecycle/grade, delete student data, write credit/capacity ledgers or call the low-level capacity function. Activation is exposed only through the controlled function. Worker access is limited to in-app notifications; exporter has no base-table grants until reviewed export views exist. The companion `workspace_role_privilege_tests.sql` verifies object ownership, role attributes, grants and cross-Workspace database CONNECT denial across two synthetic databases. Login roles are placeholders with no password; production secret binding and rotation remain external and unverified.
