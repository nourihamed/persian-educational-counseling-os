# Product Owner Decision Register — 2026-11-05

**Record type:** Decision-capture addendum  
**Authority:** Product Owner decisions explicitly confirmed in the project conversation  
**Status:** Product Owner decisions confirmed; reconciliation register updated 2026-11-05. Canonical D-number allocation and cross-document reconciliation remain pending; this is not an implementation claim or phase-gate approval.  
**Branch:** `docs/product-owner-decisions-2026-11-05`

## 1. Purpose and authority

This document captures the Product Owner decisions confirmed during the 2026-11-05 architecture-discovery conversation, together with the directly related previously established architectural constraints needed to interpret them safely.

It is an additive decision record. It does not silently rewrite historical decisions, assign new D-numbers that may collide with the existing decision log, approve a database schema, authorize implementation beyond an already approved scope, close open questions, approve a phase, or permit real student/customer data.

Before merge, the existing `DECISION_LOG.md`, `OPEN_QUESTIONS.md`, `PROJECT_SCOPE.md`, `ARCHITECTURE.md`, `DATABASE.md`, `API.md`, `SECURITY.md`, and `PROJECT_STATE.md` must be reconciled against this record. Where an older statement conflicts with a confirmed decision below, the conflict must be explicitly resolved in the canonical documents rather than silently ignored.

## 2. Delivery and scope strategy

The Product Owner confirmed a staged product strategy:
- **MVP:** deliver the minimum coherent educational counseling workflow and the essential identity, workspace, authorization, student lifecycle, and credit foundations required to operate it safely.
- **Post-MVP:** defer advanced or non-essential product capabilities.
- **Architectural Foundations:** design early for future requirements where later retrofitting would create material migration, security, or data-integrity risk.

This is a scope-control principle, not blanket approval to implement every future capability in the MVP. Each capability still needs an explicit phase/scope assignment and phase authorization.

## 3. Workspace-centric tenancy

**Decision confirmed:** The product's tenancy and data-ownership model is Workspace-centric, replacing the older Counselor-as-Tenant conceptual model.

The platform structure is:

`Platform → Workspace → (Organization or Independent Counselor) → Branches / Counselors / Students`

Workspace types:
1. **Organization Workspace:** owned by an organization; may contain multiple counselors and multiple branches.
2. **Independent Counselor Workspace:** owned by one independent counselor; it does not have branches.

Rules:
- Every Workspace owns its student records, settings, resources, and Student Credit Wallet.
- A user may be a member of multiple Workspaces.
- Membership, role, and permissions are independently assigned per Workspace.
- Membership in one Workspace never grants access to another Workspace.
- Branches exist only inside Organization Workspaces; a branch is not a separate tenant/Workspace.
- Suspending one Workspace must not automatically suspend or disrupt another Workspace belonging to the same person.
- Student Credit Wallets belong to their Workspace. Credits cannot be transferred or merged across Workspaces.
- An organization with only one counselor is still represented as an Organization Workspace when it operates as an organization/practice. A counselor operating multiple offices/branches must use an Organization Workspace, not an Independent Counselor Workspace.

**Boundary:** This is a product/domain architecture decision. It does not approve any particular DDL, database topology, RLS policy, or runtime isolation implementation.

## 4. Student ownership and active enrollment

The Product Owner confirmed:
- A student may have only **one active Workspace** at any given time.
- Within that Workspace, the student has exactly **one active responsible counselor**.
- A student may move to another Workspace only through the formal transfer workflow.
- Historical Workspace and counselor assignments must be retained.
- Transfer must not delete or rewrite educational history.
- Merely knowing or entering a student's mobile number never grants access to the student's record.
- Student identity, normalized mobile number, and academic grade are separate domain concepts. A mobile number is not a permanent student identity.
- The previously established platform-wide uniqueness rule for an active enrollment by canonical E.164 mobile number plus academic grade remains a distinct enrollment-integrity control; it must not be confused with identity itself.

Transfer requirements already confirmed and retained:
- A parent/legal guardian, the current counselor, or the destination Workspace may initiate a transfer request; initiation does not authorize or finalize the transfer.
- Valid, auditable consent from at least one registered parent or legally authorized guardian is required.
- The previous counselor must separately confirm receipt of their agreed fee from their own authenticated account.
- These two approvals are cumulative; neither substitutes for or bypasses the other.
- Each student's transfer is individually authorized and atomic.
- The transfer preserves educational history. Private notes and confidential correspondence belonging to the previous counselor are not automatically transferred.
- Caller-supplied user/counselor IDs are not proof of authentication.

## 5. Parent / guardian account model

**Decision confirmed:** A parent has one independent Platform-level user account and may be linked to multiple children, including children whose records are held in different Workspaces.

Each parent–student link:
- requires verification of the legal relationship and authority;
- requires valid consent where applicable;
- has its own explicit, independently configurable permission scope;
- must be revocable and auditable;
- does not arise merely from a matching phone number or an asserted relationship.

A parent account or a link to one child does not confer access to other children or other Workspaces.

Private counselor notes and confidential student–counselor communications are not visible to parents by default. Student rights, applicable age-related rules, and legal restrictions take precedence over a parent's requested access.

This decision confirms the account and relationship architecture; detailed permission matrices, evidence standards, retention, and jurisdiction-specific legal requirements still require specification.

## 6. Platform identity and multiple roles

**Decision confirmed:** One natural person has one Platform-level account and one stable user identity, and may hold multiple roles simultaneously.

Examples include parent, student, counselor, assistant, and organization manager. A person may hold roles in multiple Workspaces.

Rules:
- Workspace membership and role assignments are separate from the Platform identity.
- Roles and permissions are scoped independently to each Workspace.
- A role in one Workspace never creates implicit access in another.
- A change or revocation in one membership must not silently alter other memberships.
- The authorization model must combine role-based permissions with resource, relationship, and scope checks. Role names alone are not sufficient authorization.

## 7. Authentication methods and account recovery

The Product Owner confirmed the following MVP login methods:
1. Mobile number plus one-time password (OTP).
2. Mobile number plus password.
3. Risk-based MFA/2FA: mandatory for high-risk roles (including counselors and managers) under the approved risk policy; lower-risk roles follow the applicable policy. Exact step-up triggers and session parameters remain to be specified.

Security requirements:
- Mobile number is a login/contact attribute, not the permanent user ID.
- Changing a mobile number requires re-authentication, verification of the new number, and an auditable history.
- Account recovery and number-change workflows must be resistant to account takeover.
- OTPs must expire, be single-use, and be protected against guessing, replay, and abuse.
- Login attempts and OTP requests must be rate-limited and monitored.
- Passwords and authentication secrets must be stored and handled using current secure practices.
- The exact OTP delivery provider, password policy parameters, and recovery evidence requirements remain implementation/design details to be specified.

## 8. Session and device management

The Product Owner confirmed:
- Users can view their active sessions/devices.
- Users can revoke one session or all other sessions.
- Sessions have expiry and controlled renewal.
- Important security events—such as password change, mobile-number change, or suspected compromise—must support revocation of prior sessions.
- Counselors and managers should be subject to stricter session policies than ordinary low-risk accounts.
- Important login, logout, renewal, and revocation events must be auditable.
- Session tokens must be protected against theft and replay; token rotation/revocation behavior must be designed and tested.

Exact lifetimes, idle timeouts, device recognition semantics, and risk-based step-up rules are not yet specified.

## 9. Account registration and Workspace creation

**Decision confirmed:** Platform account registration and Workspace creation are separate workflows.

1. A person first creates a Platform account.
2. The person may then request an Organization Workspace or an Independent Counselor Workspace.
3. Creating a Workspace does not itself grant access to student records or create permission to consume credits.
4. Workspace approval, rejection, suspension, and status changes must be auditable.
5. An Organization Workspace request requires verification of the owner or legal representative and review of organization information.
6. An Independent Counselor Workspace request requires identity verification and acceptance of applicable terms.

## 10. Counselor identity and professional approval

**Decision confirmed:** Counselor identity/professional approval and organization approval are separate controls.

Before a counselor can accept an active student:
- the counselor's personal identity must be verified;
- relevant education/professional information and supporting documents must be submitted and reviewed;
- Platform approval must be recorded;
- approval, rejection, suspension, and revocation must record actor, time, and reason.

Approval of an organization does not approve every counselor in that organization. Approval of a counselor does not approve an organization.

The exact legal/professional credentials required must be defined against applicable jurisdictions and must not be invented as a universal rule.

## 11. Organization verification and governance

**Decision confirmed:** Before an Organization Workspace can accept students:
- the owner or legal representative must be verified;
- organization name, activity type, and contact information must be recorded;
- legal documents or licenses must be reviewed where legally required;
- Platform approval must be recorded;
- one primary owner must be designated; multiple managers may be appointed with independent, explicit permissions;
- ownership and manager changes must retain an auditable history.

Ownership, management, and membership are distinct concepts. A manager title alone does not grant unrestricted access to student records, counselor-private notes, or private financial information.

## 12. Student activation and credit consumption

**Decision confirmed:** Student activation in a Workspace is conditional on all applicable checks succeeding:

1. Required basic student profile and academic-grade information is recorded.
2. The student's or parent's mobile number is verified as appropriate to age and applicable law.
3. Valid parent/guardian consent is recorded where required.
4. Exactly one responsible counselor is assigned.
5. Workspace and counselor capacity limits are checked.
6. Sufficient Workspace Student Credits are available.
7. Credit consumption and activation occur only after successful completion of the workflow.

Integrity requirements:
- Entering a mobile number alone never authorizes record access.
- A failed or rolled-back activation must not consume credits.
- Activation and credit-ledger effects must be transaction-safe and idempotent against retries.
- All material steps and changes must be auditable.
- The one-active-Workspace rule and formal transfer rules must be enforced under concurrency, not only by UI checks.

## 13. Related established constraints that remain in force

These are not newly created by this addendum; they are included to prevent the new decisions from being misinterpreted:
- Strict isolation between Workspaces and strict counselor-to-student authorization within a Workspace.
- Organization management or branch membership does not by itself authorize access to a counselor's student records.
- Platform administrative access remains explicitly scoped, least-privileged, audited, and read-only in MVP where the existing decision requires it.
- Student Credit is a Workspace-owned, auditable append-only ledger; it is distinct from counselor service fees and student/parent payments.
- Minimum auditable versioning for Program Templates and Student Plans remains an MVP requirement.
- The planning core remains deterministic, explainable, testable, and adjustable; AI must not become an opaque source of truth or silently change an approved student plan.
- Real student/customer data remains prohibited until every applicable D-014 gate has passed and the Product Owner has explicitly authorized it in writing.
- Phase approval, implementation authorization, runtime security evidence, and permission to use real data are separate states.

## 14. Unresolved items — explicitly not decided by this record

The following must remain open unless separately decided and recorded:
- Exact capacity values, thresholds, override permissions, and capacity governance.
- Exact parent permission matrix, consent evidence/verification process, age thresholds, and legal review.
- Exact counselor credential types and organization-document requirements by jurisdiction.
- OTP delivery vendor, password/session parameter values, and detailed recovery/incident workflows.
- Exact Workspace/counselor capacity values and capacity override governance.
- Retention durations and deletion/legal-hold rules.
- Detailed schema, API contracts, migrations, implementation, and test evidence for all decisions above.
- Reconciliation of the older Counselor-as-Tenant language and any other conflicting canonical documents.
- Canonical D-number allocation after reconciling PR #8's D-025–D-027 additions with the main-branch decision log.
- Phase 2 status/gate and PR #8 status must be verified independently; this decision capture does not change either.

## 15. Required repository reconciliation before approval

1. Assign collision-free decision identifiers in `DECISION_LOG.md` after checking the latest main/PR history.
2. Update `PROJECT_SCOPE.md` and `ARCHITECTURE.md` to make Workspace-centric ownership normative and remove or explicitly mark superseded Counselor-as-Tenant statements.
3. Update `DATABASE.md` and the Phase 2 domain model for Platform identity, Workspace types, memberships, branches, student ownership, guardian links, counselor responsibility, and Workspace-owned credit wallets.
4. Update `API.md` and `SECURITY.md` for object-level authorization, identity/authentication, session management, approvals, activation, and transfer workflows.
5. Update `OPEN_QUESTIONS.md` without closing questions that remain unresolved.
6. Update `PROJECT_STATE.md` only after verifying the live repository and PR state; do not claim implementation or phase completion based on this decision record.
7. Add traceable acceptance criteria and negative tests, especially cross-Workspace and cross-counselor access, guardian authorization/revocation, session revocation, activation idempotency, credit atomicity, and concurrent student enrollment/transfer.
8. Obtain independent Supervisor review before merge/phase progression.

## 16. Approval boundary

The Product Owner confirmations represented here approve the **product and architectural directions** described above. They do not approve a particular implementation, schema, migration, API, security control, test result, phase gate, or production deployment. No phase progression or real-data permission is granted by this document.


## 17. Confirmed Product Owner decision set — 35 decisions

The following 35 choices were explicitly confirmed by the Product Owner on 2026-11-05. They are authoritative product/architecture decisions. They do not, by themselves, approve DDL, implementation, test results, phase progression, or real-data use.

| No. | Confirmed choice | Normative decision |
|---:|:---:|---|
| 1 | C | Student lifecycle uses controlled archival: end the active Enrollment, preserve educational/financial/audit history, restrict operational access, and permit physical deletion only under an approved legal/retention process. Transfer is a separate workflow. |
| 2 | C | Parent access is configured per child and per permission scope. Counselor-private notes and confidential communications are hidden by default; student rights, privacy, age-related rules, and law take precedence. |
| 3 | C | Capacity is multi-level: Workspace, Counselor, and Branch where applicable. Archived students do not consume active capacity. Capacity is independent of Student Credit and must be checked atomically. |
| 4 | C | Each active student has one responsible counselor and at most one primary active branch. A counselor may serve multiple branches. Changes are formal and audited; collaborators receive only limited explicit permissions. |
| 5 | C | An Organization Workspace has one primary owner and may have multiple managers with separately assigned permissions. Ownership, management, membership, and permissions are distinct and auditable. |
| 6 | B | One stable Platform User ID identifies a person. Mobile is a mutable login/contact attribute; changing it requires re-authentication, verification of the new number, and audit history. |
| 7 | B | Enrollment follows a constrained state machine: requested, awaiting consent/approval, active, suspended, ended, and archived, with validated transitions and history. |
| 8 | C | Transfer requests may be initiated by a parent/guardian, current counselor, or destination Workspace. None can finalize it alone. Parent/legal-guardian consent, previous counselor's authenticated fee-receipt confirmation, destination acceptance, and an atomic transfer are required. |
| 9 | C | Organization Manager access is explicitly permission- and scope-based. Broad access requires a specific permission and audit; the role title alone grants no universal access. |
| 10 | C | Parent/legal-guardian relationship and authority must be verified proportionately to age and applicable law. Consent, scope, expiry, revocation, and audit are required; a phone match or assertion is insufficient. |
| 11 | B | Counselor/branch assignment changes require the owner or a manager with explicit permission and acceptance by the destination counselor. Cross-Workspace transfer remains a separate workflow. |
| 12 | B | Reactivating an archived student requires an authorized owner/manager and checks of capacity, credit, contract, and counselor assignment. Prefer a new Enrollment for a new service period while retaining history. |
| 13 | C | Retention and deletion are category-based and governed by law, contract, legal hold, and approved policy. No unsupported retention durations are invented. |
| 14 | C | Product/Plan entitlements, Student Credit ledger, and capacity/quota are separate concepts with independent lifecycle and enforcement. |
| 15 | B | Credit is debited only after successful activation; activation and debit are atomic and idempotent. Later renewals need their own policy. Ledger corrections use auditable reversal entries, not mutation. |
| 16 | C | Platform reference/curriculum data, Organization-owned content, and counselor-personal content have distinct ownership/licensing rules and versioning. This must be reconciled with D-012; it does not silently reintroduce platform-owned Program Templates into MVP. |
| 17 | B | MVP includes minimum auditable versioning for ProgramTemplate and StudentPlan. Published versions are immutable; changes create a new version. |
| 18 | A | Cross-tenant and nonexistent resources return the same 404. Return 403 only when the object is visible to the caller but the requested action is forbidden. |
| 19 | A | Each background job is scoped to one tenant/Workspace, carries an immutable tenant identifier, validates ownership/membership, and is idempotent and retry-safe. |
| 20 | B | Use private S3-compatible object storage with tenant namespaces, server-side authorization before issuing short-lived signed URLs, upload limits, and scanning. Provider selection remains open. |
| 21 | B | Store canonical timestamps in UTC; use Jalali as the default display calendar and Gregorian optionally. Scheduled local events also retain local date/time and timezone context. |
| 22 | B | Risk Engine rules are deterministic, explainable, versioned, and configurable. AI may assist but is not the source of truth; counselor overrides are audited. |
| 23 | C | Session and MFA policy is risk-based. MFA is mandatory for high-risk roles (including counselors/managers) under policy; sessions are inventoried, revocable, expiring, and renewable. Exact timeout values remain open. |
| 24 | B | Audit security, finance, sensitive access, transfers, permission changes, and critical domain events. Logs are append-only/protected and exclude secrets, OTPs, tokens, and unnecessary confidential content. |
| 25 | B | MVP Notification Core is provider-neutral and includes In-App notifications. SMS, Telegram, and Email are later adapters; templates are versioned and preferences/consent, retries, delivery, and rate limits are controlled. |
| 26 | B | Imports use staging, validation, and preview. Exports are separately authorized, scoped, minimized, rate-limited, and audited because they can bypass online access controls. |
| 27 | B | Planning is deterministic, explainable, and testable; counselor approval is required. AI may recommend but cannot silently change a published/approved plan. Record inputs, rule version, and explanation. |
| 28 | B | Test analysis/mastery can be represented by subject/chapter/topic and correct/wrong/blank outcomes, timing, and error reasons as needed; use an incremental model. |
| 29 | B | Backlog is explicit and prioritized. No unbounded automatic carry-over; rescheduling requires review/approval. |
| 30 | B | Keep hosting/provider-neutral architecture until benchmark, threat-model, cost, backup/restore, and capacity evidence exist. Retain Alt-5 hybrid cells, initial maximum two tenants/cell and provisional ten-tenant pilot cap subject to measured capacity. |
| 31 | B | Use layered, independent, encrypted, immutable backups and periodic restore drills. RPO/RTO and retention periods require business/legal/cost analysis before values are selected; replication is not a backup substitute. |
| 32 | B | Platform Admin follows least privilege, time-bound access, approval, and audit; MVP remains read-only. Runtime DB role is neither table owner nor BYPASSRLS. Emergency write access requires a separate future decision and dual control. |
| 33 | C | Public release is limited to aggregated/anonymized statistics. No public individual student ranking/result. Internal Workspace ranking may exist under explicit permissions and privacy controls. This supersedes the older preference for public individual ranking with parent opt-out. |
| 34 | C | Negative marking is configurable per exam and ON by default. Preserve a scoring-policy snapshot so later configuration changes do not alter historical results. |
| 35 | B | Real student data remains prohibited until independent tenant-isolation, authorization/RLS, migration, backup/restore, file/API security tests and review pass, blockers are fixed, and the Product Owner gives written authorization. |

### 17.1 Conflict and precedence resolutions

1. **Transfer initiation:** the newer decision 8 supersedes only the older restriction on who may initiate a request (including the earlier D-026 wording). The previous counselor's authenticated fee confirmation and valid parent/guardian consent remain cumulative, non-substitutable prerequisites. Destination acceptance is additionally required.
2. **Public rankings:** decision 33 supersedes the earlier public-individual-ranking/parent-opt-out preference. Public reporting is aggregate/anonymized only; internal Workspace ranking remains permission-controlled.
3. **MFA:** decision 23 supersedes any wording that describes MFA as merely optional for high-risk roles.
4. **Student lifecycle:** decision 1 resolves the prior open choice between deletion and archival in favor of controlled archival; exact retention durations remain open under the retention policy.
5. **Workspace model:** Workspace-centric ownership supersedes the older Counselor-as-Tenant conceptual model. This does not itself validate the Phase 2 schema or runtime isolation.
6. **D-012 compatibility:** decision 16 distinguishes platform reference/curriculum data from platform-owned Program Templates. The existing MVP exclusion of platform-owned ProgramTemplate/ProgramVersion remains unless separately changed by the Product Owner.
7. **Unresolved implementation/legal parameters:** exact retention periods, legal evidence standards, capacity numbers/overrides, session timeouts, storage provider, calendar edge-case rules, and implementation/test details remain open. Their omission is intentional, not an implicit approval.

### 17.2 Registration and merge boundary

This register captures the Product Owner's confirmed choices in GitHub on this branch. It does not assign D-028 onward yet: PR #8 currently carries D-025–D-027 on a separate unmerged branch, so assigning subsequent identifiers against main would create a collision/reconciliation hazard. The canonical Decision Log must be updated after PR #8's decision entries are reconciled and the final collision-free sequence is established. PR #8 remains NOT READY and must not be merged merely to enable numbering.
