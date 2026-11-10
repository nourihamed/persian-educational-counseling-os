# Workspace Governance Authorization Assertion Contract — Phase 2

**Status:** DRAFT / NOT APPROVED. Design contract only. Synthetic data only (D-014). No production credential, signing key, verifier, API or application role is created by this document.

## 1. Purpose and trust boundary

The Workspace governance event materializer now provides atomic append-only events and current-state projections. It is deliberately not an authorization decision engine. Its `authn_event_ref` and `authority_ref` fields are opaque references and must never be treated as proof merely because they are non-empty.

A separate trusted Governance Authorization Adapter (GAA) must validate the caller's identity, authentication event, authority to perform the exact action, target, scope, policy version and replay protection before it can invoke the materializer.

The ordinary API/runtime role must not receive direct EXECUTE on the governance materializer or DML on governance/projection tables. The per-Workspace `governance_owner` remains NOLOGIN and is not a credential for an application service.

## 2. Signed assertion envelope

The trusted verifier must accept a versioned, integrity-protected assertion envelope containing at least:

| Claim | Required binding |
|---|---|
| assertion_id | Globally unique immutable identifier |
| issuer | Explicitly trusted Platform Security / identity issuer |
| audience | Exact Workspace ID and intended governance command service |
| subject | Platform User ID of the authenticated actor |
| actor_membership_id | Exact active membership in the target Workspace |
| authn_event_id | Immutable authentication event reference |
| authentication_assurance | Assurance level / step-up result required by action policy |
| action | Exact command, e.g. role grant/revoke, permission scope change, membership suspension |
| aggregate_type + aggregate_id | Exact target aggregate |
| target_membership_id | Exact target membership when applicable |
| role_key / permission_key | Exact role or permission affected |
| scope_digest | Digest of canonicalized exact resource scope |
| authority_basis_ref | Immutable evidence/policy reference for the actor's authority |
| policy_version | Version of the grantability and authorization policy evaluated |
| idempotency_key + payload_digest | Exact command identity and canonical payload binding |
| nonce | Cryptographically strong one-use anti-replay value |
| issued_at / not_before / expires_at | Bounded validity interval |
| key_id + signature_metadata | Key/version and approved signature-format metadata |

Do not include passwords, OTPs, bearer tokens, raw mobile numbers, signing keys or identity-document contents in the assertion or event payload. Sensitive evidence stays in the approved private evidence store and is referenced by opaque IDs.

The signature algorithm, issuer key registry, key rotation/revocation protocol and clock-skew bounds must be selected by Platform Security and recorded as a separate decision. The verifier must use an explicit algorithm allowlist; it must not trust an algorithm chosen by an untrusted assertion.

## 3. Mandatory verification sequence

Before issuing a verified assertion, the verifier must:

1. Verify signature/integrity against a trusted, non-revoked issuer key and approved algorithm.
2. Verify issuer, exact audience, Workspace ID, assertion version, time window and expiry.
3. Resolve subject to the exact active Workspace membership; reject mismatched or cross-Workspace membership.
4. Verify the authentication event and action-specific step-up assurance.
5. Evaluate a versioned role/permission grantability policy for the actor, target, action and exact scope.
6. Reject self-grant, privilege escalation, grant of equal/higher privilege, scope expansion beyond actor authority, and any unapproved delegation.
7. Verify target state and relationship preconditions (e.g. target active for role/permission grant).
8. Verify the exact payload digest and idempotency key.
9. Atomically reserve/consume the nonce or assertion ID so concurrent replay cannot succeed.
10. Emit an immutable verification receipt/proof reference and audit outcome.

A mere role label is not sufficient: grantability must derive from explicit permissions and scope. A counselor must not grant or inspect authority outside their Workspace assignment. Cross-Workspace or non-existent objects must follow the Product Owner's uniform 404 behavior; visible objects with a forbidden action may return 403.

## 4. Database handoff and atomicity

The intended boundary is a two-stage trusted handoff:

- **Verifier stage:** a separately credentialed verifier validates the signed assertion and records a minimal, single-use verification receipt bound to the exact Workspace, actor, action, target, scope digest, policy version, payload digest, nonce and expiry.
- **Command stage:** the Governance Authorization Adapter submits the command with the receipt ID. The database command must lock and consume the receipt exactly once, recheck target membership state and expected aggregate sequence, append the governance event, and update the current projection in the same transaction.
- Any failure rolls back receipt consumption, event append and projection update together.
- Same-key/same-intent retry returns the original command result; same key with any changed actor, action, target, scope, policy or payload rejects.
- Receipt expiry, issuer/key revocation, policy-version deprecation or stale aggregate version fails closed.
- The ordinary API runtime cannot register receipts, consume receipts, invoke the command function or write projection tables.

The exact database role topology, receipt schema and verifier deployment are design targets only. Do not add EXECUTE grants until a separate review proves that only the intended adapter/verifier identities can reach these boundaries.

## 5. Policy and unresolved Product Owner input

A versioned grantability matrix is required for at least:
- Platform Admin / Platform Support (including explicit restrictions on cross-Workspace role changes);
- Organization Manager;
- Counselor / Branch-scoped counselor;
- other Workspace staff roles, if approved;
- parent/guardian and student self-service principals.

### 5.1 Accepted Product Owner rule — Organization Manager appointment

**Accepted 2026-11-10:** Appointment or replacement of an Organization Manager requires approval by a Platform Admin only.

- An Organization Manager may request or nominate a proposed replacement, but cannot approve or complete the appointment.
- No second-Organization-Manager approval workflow is required.
- Platform Admin is the sole approving authority for this specific high-impact role assignment.
- The action must be authenticated, explicitly scoped to the target Organization/Workspace, and audited with actor, target, time, decision and policy version.
- This rule does not grant Platform Admin unrestricted access to student data or general Workspace operations; existing least-privilege and Platform Admin restrictions remain in force.
- This decision settles only Organization Manager appointment/replacement. It does not approve a complete role-to-role grantability matrix or authorize counselors/parents/students to delegate permissions.

**Remaining Decision Required:** approve the exact role-to-role grant/revoke matrix for roles other than the Organization Manager appointment rule above, including whether a counselor may delegate any permission and which other permissions require additional approval.

**Recommendation:** default deny; a principal may grant only explicitly delegated lower/equal-scope permissions listed in a versioned policy; no self-grant; no implicit authority from role names. Do not introduce a second-manager approval workflow for Organization Manager appointment.

No role hierarchy or delegation rights are inferred by this contract beyond the accepted rule above.

Q-007 remains open. Guardian verification, custody/age/student-objection and dispute rules must not be implemented from assumptions. Guardian relationship/permission event families continue to fail closed until legal policy and evidence-verification rules are approved.

## 6. Required acceptance tests

The tests below are acceptance criteria for a future trusted verifier/adapter implementation. They do not imply that unresolved grantability rules have been approved. Role-specific positive cases must be added only after the Product Owner approves the corresponding matrix entries. Until then, unspecified grants and delegations must be denied.

The test suite must cover these principal categories once their permitted actions are explicitly defined:
- Platform Admin / Platform Support, with narrow governance scope and no implied cross-Workspace student-data access;
- Organization Manager;
- Counselor / Branch-scoped counselor;
- other Workspace staff roles, if approved;
- parent/guardian and student self-service principals.

The accepted Organization Manager appointment rule in section 5.1 is controlling. Do not add a second-Manager approval or generic dual-approval requirement unless a separate Product Owner decision explicitly requires it. Q-007 remains open; guardian authority tests must remain fail-closed until legal policy and evidence-verification rules are approved.



### Cryptographic and identity binding
- Invalid signature, unknown/revoked key, disallowed algorithm, issuer/audience mismatch and expired/not-yet-valid assertion reject.
- Subject, actor membership, Workspace, authn event or assurance mismatch rejects.
- Assertion with altered action, target, role/permission, scope, policy or payload digest rejects.
- Key rotation/revocation and old assertion replay behave deterministically.

### Authorization / anti-escalation
- Self-grant and equal/higher privilege grant reject.
- Counselor cannot grant manager role or out-of-assignment scope.
- Organization manager cannot grant outside the approved matrix.
- Cross-Workspace, non-existent and stale-generation targets reject without leaking existence.
- Inactive target rejects grant/scope expansion; revoke remains possible where policy permits.

### Replay / concurrency / atomicity
- Same assertion/nonce submitted concurrently yields exactly one accepted command.
- Same idempotency key with altered claims rejects.
- Receipt cannot be consumed twice or by a different Workspace/actor/action.
- Failure during event insert or projection update rolls back receipt consumption.
- Revoke-vs-read and suspension-vs-access have a documented linearization point; stale authorization snapshots fail closed.
- Audit record binds the verifier receipt, event ID, actor, target, action, policy version and outcome without storing secrets.

### Privilege boundaries
- Runtime, worker and exporter cannot register/consume proofs or execute governance commands.
- Only dedicated verifier/adapter roles receive narrowly scoped privileges.
- `governance_owner` remains NOLOGIN and cannot be assumed by service logins.
- No role has direct DML on role/permission projections outside the reviewed command boundary.

All tests remain NOT IMPLEMENTED / NOT RUN until executable schema and service-level suites are added.

## 7. Gate impact

This contract closes neither trusted authorization nor guardian authority. The current SQL materializer remains an internal projection mechanism, not an application authorization service. WS-DOM-02 and WS-DOM-03 remain HIGH. Phase 2 remains **NOT READY**; Phase 3 must not start.

## 8. Related contracts

- `WORKSPACE_GOVERNANCE_EVENT_CONTRACT.md`
- `WORKSPACE_DOMAIN_SCHEMA_REVIEW.md`
- `../../phase1/AUTHORIZATION_CONTRACT.md` (Phase 1 tenant/object authorization baseline)
- `../PHASE2_OPEN_DECISIONS.md`
