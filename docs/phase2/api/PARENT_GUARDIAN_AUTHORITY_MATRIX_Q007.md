# Parent / Guardian Authority Matrix — Q-007 Decision Template

**Status:** DRAFT / BLOCKED FOR LEGAL POLICY. OQ-G Option A is accepted at high level: per-child, per-permission access. This document does not define Iranian legal age thresholds, legal guardianship or evidence standards. Qualified Iran legal review and Product Owner approval are required before Parent API implementation. Synthetic data only (D-014).

## 1. Accepted high-level rules

- A guardian relationship is distinct from legal authority.
- Access is granted independently for each child and each permission/scope.
- A phone number, family label, self-assertion or existing account link is not proof of legal authority.
- Sensitive scopes require explicit permission; counselor-private notes and confidential communications are denied by default.
- Grants have authenticated issuer, evidence reference, effective interval, expiry where applicable, revocation and audit.
- Student rights and applicable law override ordinary parent settings.
- A permission for child A never grants access to child B.
- Authority must be revalidated when used for high-risk actions and transfer approval.

## 2. Policy matrix — intentionally unresolved cells

| Dimension | Required policy value | Current status |
|---|---|---|
| Age bands / legal majority | Exact age bands and legal effect | NEEDS IRAN LEGAL REVIEW |
| Parent vs legal guardian | Recognized relationship/authority types | NEEDS IRAN LEGAL REVIEW |
| Evidence | Acceptable documents/verification sources and assurance | NEEDS IRAN LEGAL REVIEW |
| Separated parents / dispute | Conflict, objection, court order and precedence | NEEDS IRAN LEGAL REVIEW |
| Custody / appointed guardian | Scope, expiry and revocation rules | NEEDS IRAN LEGAL REVIEW |
| Student consent / objection | When student consent is required and how objection affects access | NEEDS IRAN LEGAL REVIEW |
| Emergency / safeguarding | Narrow emergency access, approver and audit | NEEDS LEGAL + PO DECISION |
| Revocation | Effective time, propagation SLA and queued-job cancellation | NEEDS POLICY |
| Re-verification | Trigger events and freshness policy | NEEDS POLICY |
| Record retention | Evidence retention and access restrictions | NEEDS RETENTION APPROVAL |

No age threshold, document list, legal presumption or exception may be inferred from this table.

## 3. Permission taxonomy proposal for review (not approved)

The technical permission model should support independent scopes rather than one broad "parent access" switch. Candidate scopes to map to actual product features:

- academic_plan_read;
- progress_read;
- attendance_read;
- assignments_read;
- test_results_read;
- exam_results_read;
- communication_read / communication_send;
- financial_summary_read;
- invoices_read;
- consent_manage (only where legally authorized);
- transfer_consent (only where legally authorized).

The final scope catalog must define read/create/update/export separately where relevant. No scope grants access to counselor-private notes, confidential communications, internal risk deliberations or another child's records by inheritance.

## 4. Required technical evidence

Each grant/use must be bound to:
- guardian Platform User subject;
- exact Platform Student and Workspace;
- verified relationship and legal-authority reference;
- scope/action and policy version;
- grantor/approver authenticated principal;
- valid-from/valid-until and revocation state;
- authentication event and audit correlation;
- current Workspace ownership generation.

A trusted authority-verification service must produce a signed assertion or equivalent server-verifiable proof. The Workspace DB must not accept caller-supplied `verified=true` or an arbitrary `authority_ref` as proof.

Relationship and permission grant/revoke must be append-only events. Current effective state is a projection over those events. Every request re-evaluates expiry, revocation, student status, current owner/generation and scope. Background jobs, exports, files and notifications re-check authorization before execution/delivery.

## 5. Required acceptance tests

- Child A permission cannot be used for child B, including guessed IDs, exports, files, jobs and notifications.
- Unverified relationship never grants access.
- Legal authority absent, expired, revoked, disputed or outside scope denies access.
- Conflicting guardian assertions fail closed and route to reviewed dispute workflow.
- Student objection/consent rules follow the approved age/legal matrix.
- Permission revocation invalidates sessions/cache/queued work within the approved propagation SLA.
- Cross-Workspace/nonexistent object returns indistinguishable 404.
- Sensitive scopes are independently granted and cannot be inferred from general progress permission.
- Transfer guardian consent is bound to exact transfer case and current ownership generation.
- Audit proves principal, authority evidence, policy version, child, scope, decision and timestamp without retaining unnecessary document content.

All tests remain NOT IMPLEMENTED / NOT RUN until policy and runtime services are approved.

## 6. Decisions required to close Q-007

1. Obtain qualified Iran legal review of age/majority, guardianship, custody, evidence and student rights.
2. Product Owner approves the resulting age/authority/scope matrix.
3. Assign policy owner, verification authority and dispute escalation responsibility.
4. Approve scope taxonomy and revocation propagation requirements.
5. Approve evidence retention under the category-based retention policy.
6. Add versioned policy and executable tests before Parent APIs or guardian transfer approvals are enabled.

**Gate:** Q-007 remains OPEN. The high-level per-child/per-permission direction is accepted; the legal and operational policy is not. Phase 2 remains NOT READY and D-014 remains in force.
