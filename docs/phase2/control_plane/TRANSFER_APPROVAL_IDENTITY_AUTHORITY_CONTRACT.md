# Transfer Approval Identity & Authority Verification Contract

**Status:** DRAFT / NOT APPROVED. Phase 2 design contract only. Synthetic data only (D-014). No production identity provider, legal-authority determination or transfer execution is approved by this document.

## 1. Purpose and trust boundary

This contract closes the design gap between recording three transfer approval rows and proving that the approvals were made by authenticated, currently authorized principals for the exact transfer case.

The Control Plane database cannot establish a person's real-world identity, legal guardianship, counselor employment/assignment or organizational delegation from caller-supplied strings or JSON. A trusted Identity & Authorization service must verify those facts and issue a cryptographically authenticated, short-lived, one-time approval assertion. The Control Plane workflow service validates that assertion through a dedicated verifier before invoking a narrowly privileged database command.

A database row containing non-empty `approver_ref`, `authn_event_ref` and `authority_snapshot` is not proof of identity or authority.

## 2. Three cumulative approval roles

All three approval kinds remain required by the existing Product Owner decisions. Their meanings are fixed:

| Approval kind | Permitted principal | Required authority at approval time |
|---|---|---|
| `guardian_consent` | Verified parent/legal guardian for this student | Verified per-child relationship and authority under the approved age/legal matrix |
| `fee_confirmation` | The student's current/prior counselor in the source Workspace | Active assignment to this exact student at the case's expected ownership generation, plus explicit confirmation that the transfer fee was received |
| `destination_acceptance` | Authorized representative of the destination Workspace | Active membership/role and explicit permission to accept this exact student transfer |

The initiator is not automatically an approver. A person may satisfy more than one role only if the policy service independently verifies each authority and the Product Owner's conflict-of-interest policy permits it. No implicit self-approval exception is created here.

Platform Admin cannot initiate, substitute for, or approve any of the three approvals. Platform support may open a support/review ticket but cannot generate approval evidence.

## 3. Required signed approval assertion

For each approval, the trusted service must produce a signed assertion containing at least:

- immutable `assertion_id` and one-time nonce;
- issuer and exact audience (the transfer workflow service);
- authenticated principal subject and authentication event reference;
- authentication assurance / step-up method and timestamp;
- exact `case_id`, `student_id`, source Workspace, destination Workspace and expected ownership generation;
- exact approval kind;
- verified authority type, authority source/reference, scope and policy version;
- guardian relationship/legal verification reference when applicable (not the document contents);
- counselor assignment reference and fee-received attestation reference when applicable;
- destination membership/delegation reference when applicable;
- evidence reference, issued-at, expiry and optional revocation-check reference;
- assertion schema version and cryptographic key identifier.

The signature must be verified against an allow-listed issuer/key set, algorithm policy, audience, subject, expiry, not-before time, nonce uniqueness and revocation status. The assertion must be purpose-bound and unusable for another student, case, Workspace, generation or approval kind. The signed payload must not contain unnecessary personal data or identity documents.

The workflow service must derive the principal from the verified assertion. It must never trust `approver_ref`, `approval_kind`, `authority_snapshot`, or a `verified=true` request field supplied by an ordinary client.

## 4. Authority checks by approval kind

### 4.1 Guardian consent

- Resolve guardian relationship from the authoritative identity/relationship service, not a client-supplied child list.
- Verify authority for this exact student and the current case.
- Check active/revoked status and any legal restrictions at the time of approval and again immediately before ownership switch.
- Store only opaque evidence references, policy version and minimum necessary authority snapshot.
- The age threshold, acceptable legal documents, separated-parent/dispute handling, custody exceptions, and jurisdiction-specific rules remain unresolved under Q-007 and the Iran MVP legal review. This contract does not infer them.

### 4.2 Prior counselor fee confirmation

- Resolve the counselor's authenticated subject to the source Workspace and current student assignment.
- Verify the assignment is active and belongs to the exact student and expected generation at the time of approval.
- Require an explicit attestation that the transfer fee was received, tied to this case. A generic checkbox or an approval from another counselor in the same organization is insufficient.
- Preserve the counselor subject, assignment reference, fee-attestation reference and timestamp for audit. Do not store payment credentials or unrelated financial details here.
- If assignment changes or ownership generation changes before switch, the approval becomes stale and the case must return to the appropriate approval step or fail closed.

### 4.3 Destination acceptance

- Resolve the destination Workspace representative from the authoritative membership/role service.
- Verify active membership and a specific transfer-acceptance permission for that Workspace.
- The approval is scoped to the exact destination Workspace and case; organization membership alone is not sufficient if the actor lacks the delegated permission.
- Re-check membership, Workspace status and permission immediately before switch.

## 5. Recording, revocation and re-approval

Approval evidence is append-only. A revocation is a separate immutable event with actor, reason code, timestamp, authentication event and exact approval/assertion reference; it does not rewrite or delete the original assertion.

A revoked, expired, superseded or authority-stale approval cannot satisfy the switch precondition. A replacement approval must be a new event with a new assertion ID and nonce. The schema must therefore support multiple historical approval events per case and approval kind, while selecting exactly one current, unrevoked, unexpired, authority-valid approval for each of the three kinds.

**Schema reconciliation finding:** the current `transfer_approvals` table has `UNIQUE(case_id, approval_kind)` and a mutable one-way `revoked_at` column. That shape prevents recording a replacement approval after revocation and mixes immutable evidence with revocation state. Before executable approval work is accepted, replace this with append-only approval and revocation event records (or an equivalently auditable versioned model). Do not silently drop old evidence.

Before ownership switch, the workflow must lock the transfer case and the selected approval evidence/revocation state in a consistent order, revalidate authority freshness, then perform the switch in the same Control Plane transaction. Revocation and switch must serialize on the same case-level lock: whichever commits first determines whether the approval is valid at cutover.

After ownership switch, an approval cannot be used to reverse ownership. A post-switch discovery of fraud or invalid authority creates an audited incident and forward-recovery/support process; no automatic rollback is permitted.

## 6. Database and service boundary

- Only a dedicated transfer workflow executor may invoke the approval-recording command; it may not insert/update approval tables directly.
- The verifier service validates signature, issuer, audience, key status, nonce, subject, case binding and expiry before issuing a trusted internal command.
- Database functions must still enforce case/student/Workspace/generation/kind consistency, unique assertion/nonce use, one current valid approval per kind, and append-only history.
- The database must not accept raw JWTs or cryptographic private keys, and must not claim to validate legal documents itself.
- Function ownership remains separated from identity admission and HMAC rotation owners. No shared broad SECURITY DEFINER owner.
- Approval payloads and outbox events contain identifiers and opaque references only; no identity documents, OTPs, payment credentials or unnecessary personal data.
- Authorization failures must be non-enumerating for callers who cannot view the case.

## 7. Required acceptance and regression tests

1. Unsigned, malformed, expired, not-yet-valid, wrong-issuer, wrong-audience or disallowed-algorithm assertion is rejected.
2. Assertion with wrong case, student, source/destination Workspace, generation or approval kind is rejected.
3. Assertion subject must equal the authenticated principal; caller-supplied approver identity is ignored/rejected.
4. Replayed assertion ID or nonce is rejected; exact idempotent command replay returns the original result without recording a second approval.
5. Guardian without verified per-child authority, revoked relationship or wrong child is rejected.
6. Counselor not assigned to this student/source Workspace/generation, or lacking fee-received attestation, is rejected.
7. Destination actor without active membership or exact transfer-acceptance permission is rejected.
8. Platform Admin cannot create any approval or substitute for an eligible principal.
9. Revoked/expired/stale approvals cannot satisfy switch; a replacement approval is append-only and does not erase the prior event.
10. Concurrent revocation and ownership switch serialize on the case lock; no switch may consume an approval revoked before switch commit.
11. Membership/assignment/guardian authority revoked after initial approval but before switch is detected at cutover.
12. Duplicate approval attempts, idempotency key payload mismatch and assertion replay have deterministic outcomes.
13. Direct DML by application/executor roles is denied; only the narrow workflow function is executable.
14. Catalog tests prove transfer function owners cannot rotate keys, admit identities or mutate unrelated Workspace data.
15. Audit events prove who approved, under which authentication event and authority policy version, for which exact case, without exposing sensitive payloads.
16. Failure injection around assertion consumption, approval event append, revocation and switch proves atomic rollback and safe retry.

All listed tests are specifications until executable service/database tests are implemented and run.

## 8. Open policy decisions

- Q-007 legal guardian/age matrix and Iran-specific legal evidence requirements remain open.
- Conflict-of-interest/self-approval rules where one person holds multiple roles require Product Owner approval; this contract grants no exception.
- Revalidation freshness windows and step-up assurance levels require a versioned security policy; do not invent fixed durations here.
- Retention periods for approval evidence and revocation records remain governed by the unresolved data-retention policy.
- Dispute, court order, deceased/absent guardian, and account recovery paths require separately reviewed policies.

## 9. Gate impact

This contract is a Phase 2 design target only. It does not prove identity, legal authority, production cryptographic verification or runtime authorization. The current approval schema is not sufficient as-is and must be reconciled before approval-related implementation is accepted. The Control Plane and Phase 2 Gate remain **NOT READY**. D-014 synthetic-only restriction remains in force.

## Implementation status — 2026-11-14 (draft SQL, synthetic; not an approval)

Implemented: separation of duties (one person may not hold two incompatible current approval kinds for the
same transfer); `transfer_approval_conflict_exceptions` holding the single contemplated
`source_destination_owner` case with `CHECK (enabled = false)`, so enabling it is a reviewable schema change
and not DML, and the guard still fails closed even if a row were enabled; a structural side check binding
`fee_confirmation` to the case's source Workspace and `destination_acceptance` to its destination;
`record_transfer_approval()` and `revoke_transfer_approval()` as the only way to write approval evidence,
restricted to `cp_transfer_approval_executor`; expiry evaluated with `clock_timestamp()` after the case row
is locked, in the insert guard, the `transfer_approvals_current` view and the switch's approval count.

No Platform Admin override exists anywhere, and none was granted.

The database verifies the shape, side, separation and freshness of recorded evidence and which identity may
record it. It does NOT verify that an assertion is authentic, that a person holds guardian or legal
authority (Q-007), or that a fee was paid.

Still open: the approval authority for the exception; Q-007; the reason-code taxonomy.

Tests: SEP-01..SEP-29, APR-01..13, APR-RACE-01, APR-SWITCH-01 (executed).
