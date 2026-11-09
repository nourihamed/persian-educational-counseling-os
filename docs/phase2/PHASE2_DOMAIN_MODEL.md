# Phase 2 — Canonical Workspace-Centric Domain Model

**Status:** DESIGN DRAFT / NOT APPROVED. This document supersedes the Counselor/Organization tenant assumptions in PR #8's earlier `docs/PHASE2_DOMAIN_MODEL.md` for the current target model. PR #8 remains Open/Draft/Unmerged and must not be merged as-is.
**Synthetic data only (D-014).** No production migration, runtime authorization or real-data permission is implied.

## 1. Product and tenant hierarchy

`Platform → Workspace → Students`

A Workspace is exactly one of:
- **Organization Workspace:** organization identity, optional branches, multiple counselor memberships and students.
- **Independent Counselor Workspace:** one independent counselor workspace, no branches.

A counselor is a Platform User with a Workspace membership and counselor assignment; counselor is not the tenant root. One person may have multiple Workspace memberships with independent roles and permissions. Organization membership or manager title does not automatically grant access to student records. Counselor access is limited to students with an active responsible-counselor assignment and explicit scope.

Each Workspace is an isolated database/credential boundary inside its assigned deployment cell. The provisional Alt-5 policy is at most two Workspaces per cell and at most ten Workspaces in the initial pilot; these are provisional policy ceilings, not measured capacity or pilot authorization.

## 2. Two database domains

### 2.1 Control Plane (global authority)

| Entity | Responsibility |
|---|---|
| PlatformUser reference | Stable identity subject reference; mobile is mutable contact/login data |
| Workspace | Global Workspace registry, type, status and cell placement |
| PlatformStudent | Global student identity reference |
| StudentContactIndex | Encrypted recoverable canonical E.164 and versioned keyed HMAC contact index |
| MobileHmacKeyVersion | HMAC version lifecycle |
| StudentOwnership | Exactly one current owner Workspace and monotonic ownership generation |
| EnrollmentClaim | Global mobile+grade claim; one holding claim per student |
| EnrollmentClaimIdentityAlias | One alias per active/retiring HMAC version; unique global mobile+grade per version |
| TransferCase / TransferApproval | Durable transfer workflow and cumulative approvals |
| CommandLog | Idempotency key + canonical payload hash + resulting case |
| OwnershipHistory | Append-only ownership changes |
| Outbox / Inbox | Durable event publication and deduplication |

Control Plane does not own educational content, counselor-private notes or Workspace credit ledger.

### 2.2 Workspace DB (local domain authority)

| Entity group | Main entities | Ownership |
|---|---|---|
| Workspace profile/governance | WorkspaceProfile, Membership, MembershipRole, MembershipPermission, Branch | One Workspace DB |
| Student | Student, Enrollment, GuardianLink, GuardianPermission | Workspace-local projection keyed by PlatformStudent ID + generation |
| Counselor assignment | CounselorAssignment | Workspace-local; one responsible counselor per active enrollment |
| Curriculum | Subject, Chapter, Topic, StudentTopicMastery | Reference/custom curriculum plus student-specific mastery |
| Planning | ProgramTemplate, ProgramVersion, StudentPlan, StudentPlanVersion | Workspace-owned content; versioned |
| Execution | Activity, StudySession, Assignment, Review, DailyRoutine | Student execution and scheduling records |
| Assessment | TestDefinition, TestAttempt, TestResponse, Exam, ExamResult | Scoring-policy snapshots preserved |
| Classes | Class, ClassSession | Online/offline/onsite |
| Analysis | ProgressSnapshot, RiskAssessment | Deterministic/versioned; explanation and inputs retained |
| Counseling | CounselorNote | Private-to-author or explicitly Workspace-scoped |
| Finance | CreditWallet, CreditTransaction | Workspace-owned append-only ledger |
| Capacity | WorkspaceCapacityCounter, CapacityEvent | Workspace-local limits; atomic/idempotent counter updates |
| Operations | PrivateFileObject, InAppNotification, NotificationPreference, LegalHold, AuditEvent | Private storage, in-app notifications, retention/legal holds and audit |

No cross-database foreign key or cross-database atomic transaction is claimed. A Workspace DB's Enrollment is a projection, not the global ownership authority.

## 3. Global identity and enrollment invariants

1. A student has exactly one current owner Workspace in Control Plane.
2. Ownership generation increases by exactly one on each successful transfer.
3. A student has at most one holding global enrollment claim.
4. D-025: at most one active/transfer-pending claim per canonical E.164 mobile + grade across the platform; same mobile with a different grade is allowed by the accepted rule.
5. During HMAC key overlap, every holding claim must have a matching alias for every active/retiring key version. A write freeze, backfill, database gate, deferred completeness checks and version retirement protocol are required.
6. A Workspace DB has at most one active local enrollment projection for a PlatformStudent.
7. All reads/writes/jobs/exports/files must validate current Control Plane owner and generation. Missing, stale or unavailable ownership validation denies access.
8. Workspace membership never implies membership or access in another Workspace.

## 4. Workspace domain invariants

- Organization Workspace may have branches; Independent Counselor Workspace may not.
- Membership roles and permissions are many-to-many and Workspace-scoped.
- One active responsible counselor per active enrollment. Assignment change requires authorized owner/manager permission and destination counselor acceptance.
- Guardian relationship and legal authority are separate facts. Permission is per child and per scope, with validity, expiry, revocation and audit. Q-007 remains open for the Iran age/legal evidence matrix.
- Platform reference curriculum and Workspace-custom curriculum have distinct origin/ownership. Student mastery/progress is always student-specific.
- Published ProgramVersion and StudentPlanVersion are immutable. Corrections create new versions; plan versions retain input snapshot, rule version, source template version and approval.
- Planning is deterministic, explainable, versioned and counselor-approved. AI is assistive only; it cannot silently mutate a published plan.
- Test/exam scoring policy is snapshotted per attempt/result; negative marking is configurable per exam and ON by default.
- Backlog is explicit and prioritized; no unbounded automatic carry-over.
- Student Credit is separate from capacity. Successful activation and credit debit must be atomic/idempotent; reversals are compensating entries.
- Capacity counters are dimension-specific and adjusted atomically/idempotently. Cell-level capacity is controlled by Platform/Control Plane.
- Audit and credit ledgers are append-only. No OTPs, tokens, secrets or encryption keys in audit metadata.
- File objects use provider-neutral private storage keys, tenant namespace and server-side authorization before short-lived signed URLs.
- Retention is category-based and versioned. Numeric durations remain unapproved; legal holds must block deletion/anonymization.

## 5. Student lifecycle and transfer

Enrollment lifecycle: requested → awaiting consent/approval → active → suspended → ended/archived, with immutable transition history. Archived students do not consume active student capacity. Reactivation requires authorized actor, capacity, entitlement, credit and assignment checks; a new enrollment is preferred for a new service period.

Transfer is cross-Workspace and requires:
1. verified parent/legal guardian consent;
2. previous responsible counselor's own authenticated fee-receipt confirmation for the exact prior enrollment;
3. authorized destination Workspace acceptance.

Only a verified guardian, current counselor or destination Workspace may initiate. Platform Admin cannot initiate or bypass. MVP uses source write freeze + final consistent snapshot, destination staging and integrity validation, then one atomic Control Plane owner/generation switch. After the switch, recovery is forward-only; reverse movement is a new authorized transfer.

## 6. Explicit reconciliation with PR #8

PR #8's earlier schema uses `tenants`, `counselors`, `counselor_students`, tenant-local `active_student_counselor_registry` and plaintext-normalized mobile in Workspace tables. That design is not the current target because:
- it models organization as the only tenant and cannot represent Independent Counselor Workspace;
- global uniqueness is attempted inside a Workspace schema and cannot be enforced across isolated Workspace DBs;
- it does not provide a separate Control Plane ownership authority/generation;
- transfer remains an evidence fragment, not a durable cross-database Saga;
- the old schema's tests/evidence do not validate the new Control Plane/Workspace model.

The new `docs/phase2/control_plane/` and `docs/phase2/workspace/` drafts define the replacement direction. Existing PR #8 test evidence remains valid only for its exact old schema/contract and must not be counted as current Phase 2 acceptance evidence. PR #8 must be reconciled/rebased or superseded before any merge.

## 7. Current implementation and evidence boundary

The companion SQL files are schema/function drafts. They do not constitute runtime services or production migrations. Control Plane regression, race and Workspace schema tests are specified but NOT RUN against the current PR #12 HEAD. Dedicated DB roles/grants, trusted identity verification, KMS/HSM, outbox/inbox delivery, cross-database freeze/snapshot orchestration, crash recovery, backup/restore and measured HA/capacity evidence remain open.

**Phase 2 Gate: NOT READY.** D-014 remains in force; synthetic data only. Phase 3 is not authorized.
