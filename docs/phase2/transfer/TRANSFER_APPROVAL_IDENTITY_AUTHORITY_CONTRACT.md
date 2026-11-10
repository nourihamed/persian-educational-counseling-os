# Transfer Approval Identity & Authority Contract — Phase 2

**Status:** DRAFT / NOT APPROVED. Design contract only. Synthetic data only (D-014). This document does not assert that approval authority is currently authenticated or enforced by the SQL drafts.

## 1. Purpose and threat model

The transfer workflow requires three cumulative approvals: (1) verified parent/legal guardian consent, (2) the currently responsible source counselor's explicit fee-receipt confirmation, and (3) authorized destination Workspace acceptance. A database row containing a non-empty `approver_ref` or `authn_event_ref` is not proof that the person authenticated, held the required authority, or approved this exact transfer.

Threats include forged actor IDs, replay across cases/students/Workspaces, stale authority after role/relationship revocation, approval by a different counselor in the same organization, guardian relationship without legal authority, approval after expiry, and time-of-check/time-of-use races with ownership or assignment changes.

## 2. Non-negotiable invariants

1. Each approval is a distinct immutable assertion by an authenticated principal. The principal identity is obtained from a trusted identity provider/service, never from a caller-supplied UUID.
2. The assertion is bound to one `case_id`, `student_id`, `source_workspace_id`, `destination_workspace_id`, `expected_ownership_generation`, approval kind, exact approval payload hash, and intended operation.
3. The assertion includes issuer, audience, subject, authentication event, authentication strength/step-up context, issued-at, expiry, unique nonce/assertion ID, and authority-evidence reference. Signature/issuer/audience/expiry/nonce validation occurs in a trusted service boundary; PostgreSQL does not pretend to verify identity from strings.
4. Authority is checked at approval time and rechecked immediately before cutover. Revocation, expiry, changed relationship, changed counselor assignment, changed Workspace permission, or changed ownership generation invalidates the approval.
5. An approval is single-use for the exact case and action. It cannot be copied to another case, student, transfer direction, Workspace, generation, or approval kind.
6. All three approvals are cumulative. No role can substitute for another approval. Platform Admin/support staff cannot impersonate a guardian, source counselor, or destination approver.
7. Approval records and their revocation/supersession history are append-only. Corrections create a new event; no UPDATE/DELETE may erase evidence.
8. Only minimal references and signed assertion digest/claims are stored. No OTP, password, bearer token, private signing key, or unnecessary identity document is stored in the transfer row or audit log.
9. The same approval cannot be accepted twice for different transfer cases. Idempotent replay for the same case returns the original result.
10. If identity, authority, relationship, or evidence cannot be established, fail closed.

## 3. Approval kinds and authority predicates

### 3.1 Guardian consent

Required proof:
- authenticated principal from the trusted identity service;
- verified relationship to the exact student;
- legal authority applicable to this student and this decision, including any required custody/guardianship restrictions;
- authority scope explicitly includes transfer of the student's educational service/data to the named destination Workspace;
- evidence source/reference, verification method, verifier, verification timestamp and validity interval;
- no active revocation, dispute, legal hold or conflicting authority record.

A family/guardian relationship alone is insufficient. The system must not infer legal authority from surname, phone ownership, account label, or a manually supplied boolean.

The exact Iranian age/capacity/custody/legal evidence matrix remains unresolved under Q-007 and applicable legal review. Until approved, the guardian-authority predicate is a blocked integration contract, not an implemented policy.

### 3.2 Source counselor fee-receipt confirmation

Required proof:
- authenticated principal;
- principal has an active counselor assignment to this exact student/enrollment in the source Workspace at approval time;
- principal is the currently responsible counselor, not merely another counselor or organization member;
- explicit affirmative confirmation that the agreed transfer-related fee has been received/settled, scoped to this transfer case;
- confirmation payload includes the fee settlement reference or documented manual-attestation reason, amount/currency reference where applicable, and timestamp. The approval contract does not invent fee terms or assert payment-provider evidence if none exists;
- the assignment and authority are revalidated immediately before cutover.

The confirmation is an attestation by the prior counselor; it must not be misrepresented as independently verified payment settlement unless an actual payment/ledger integration proves it.

### 3.3 Destination acceptance

Required proof:
- authenticated principal;
- principal has current Workspace-level permission to accept students/transfers for the exact destination Workspace;
- destination Workspace is active and eligible;
- destination counselor assignment/acceptance is present when the product's approved policy requires it;
- capacity, entitlement and enrollment eligibility are revalidated before cutover;
- assertion is bound to the destination Workspace and exact student/case/generation.

An organization manager's general role does not automatically authorize all actions; permission must be explicit and scoped.

## 4. Trusted approval assertion

The trusted identity/authorization service should produce a signed, short-lived assertion with a versioned schema containing at minimum:

- `assertion_id` (globally unique, single-use);
- `issuer`, `audience`, `subject_principal_id`;
- `authn_event_ref`, `authn_time`, `authn_strength`;
- `approval_kind`, `case_id`, `student_id`;
- `source_workspace_id`, `destination_workspace_id`;
- `expected_ownership_generation`;
- `approval_payload_hash`, `purpose`;
- `authority_type`, `authority_evidence_ref`, `authority_checked_at`, `authority_version`;
- `issued_at`, `expires_at`, `nonce`, `schema_version`.

The signed assertion must be verified by a trusted service with a pinned issuer/audience and managed public-key trust configuration. Key rotation, revocation and clock-skew rules must be explicit. The database stores the assertion digest and verified claims/reference, not the bearer assertion or secrets. If the service uses opaque proof references instead, the verifier must provide equivalent binding and one-time-consumption guarantees.

## 5. Database acceptance and cutover protocol

At approval submission:
1. Authenticate the principal and verify step-up requirements.
2. Load current relationship/assignment/Workspace permission from authoritative sources.
3. Validate exact case state, source/destination, student and generation.
4. Validate assertion signature, issuer, audience, purpose, payload hash, expiry, nonce and one-time status.
5. Persist a new append-only approval event and consume the assertion atomically/idempotently.
6. Record authority snapshot/version and evidence reference sufficient for later audit without copying sensitive documents.

Immediately before ownership switch:
1. Lock transfer case and student ownership in a documented global lock order.
2. Revalidate source owner and expected generation.
3. Revalidate guardian authority/relationship, source counselor assignment and destination permission from authoritative sources or a signed freshness-bounded authorization decision.
4. Verify all three approval events are valid, unrevoked, unexpired and bound to the same exact case/student/direction/generation/payload.
5. Verify no approval assertion has been consumed by another case and no authority has changed since the snapshot.
6. Perform the ownership compare-and-swap and append history/outbox in the same Control Plane transaction.

A mere `COUNT(DISTINCT approval_kind)=3` with non-empty reference strings is insufficient. The switch function must consume verified approval records or a trusted authorization decision with cryptographic/service-level provenance; it must not trust caller-provided `verified=true`.

## 6. Revocation, expiry and correction

- A principal may revoke their approval before ownership switch, subject to product/legal rules; revocation is an append-only event.
- Revocation or expiry before switch blocks cutover and requires a fresh approval assertion.
- After ownership switch, approvals are historical evidence and cannot reverse ownership. Any reverse movement is a new transfer case.
- If a guardian's legal authority or counselor assignment changes, the pending case is re-evaluated; stale approvals are invalidated.
- Duplicate submission of the same assertion for the same case is idempotent. Reuse in another case is rejected and security-audited.
- Revocation of the identity provider signing key or evidence source triggers policy-driven invalidation/review of affected pending approvals; already completed transfers require incident/legal review, not automatic rollback.

## 7. Required tests

- forged principal ID / caller-supplied actor UUID is ignored or rejected;
- invalid signature, issuer, audience, purpose, schema version, expiry, clock skew and revoked signing key reject;
- assertion for a different student, case, source/destination, generation, payload or approval kind rejects;
- replay in another case rejects; same-case same-assertion replay is idempotent;
- guardian relationship without legal authority rejects;
- guardian authority expired, revoked, disputed or scope-limited rejects;
- wrong counselor, inactive assignment, assignment revoked after approval, or another counselor in same Workspace rejects;
- destination manager without explicit transfer permission rejects;
- each approval kind cannot substitute for another; all three are required;
- revocation/expiry between approval and cutover rejects;
- ownership generation or source assignment changed between approval and cutover rejects;
- concurrent approval revocation and cutover serialize safely with a deterministic winner;
- approval records are append-only; direct runtime DML is denied;
- audit contains actor/authn/evidence references and payload digest but no OTP, token, secret or unnecessary personal data;
- API errors do not disclose cross-Workspace student existence;
- negative tests cover Platform Admin/support attempting to initiate or impersonate an approval.

All are acceptance specifications until executable service/database tests exist and pass.

## 8. Open policy decisions

The following are not inferred:
- Q-007 legal age, guardian/custody evidence and exception matrix for Iran;
- whether destination counselor acceptance is always required or only in specified cases;
- exact fee-settlement evidence acceptable when no payment integration exists;
- assertion lifetime, clock-skew tolerance and authorization freshness SLA;
- retention periods and legal holds for authority evidence;
- appeal/dispute handling and manual review authority.

These require Product Owner/legal/security decisions. The design must keep policy values configurable/versioned rather than hardcoding invented rules.

## 9. Gate impact

This contract is design-only and closes no runtime security finding. Existing SQL checks for non-empty `approver_ref` and `authn_event_ref` do not satisfy this contract. Control Plane transfer authority remains **NOT READY** until trusted identity/authorization integration, immutable approval-event schema, cutover revalidation, executable abuse/replay/race tests and independent review are complete.
