# Workspace Membership & Guardian Governance Event Contract — Phase 2

**Status:** DRAFT / NOT APPROVED. Schema and acceptance contract only. Synthetic data only (D-014). Q-007 legal policy remains OPEN.

## 1. Purpose

The Workspace schema has a canonical role relation (`membership_roles`) and per-child guardian link/permission tables, but current grant/revoke history is insufficiently auditable. This contract defines immutable governance events and current-state projections without inventing legal authority rules.

## 2. Membership and role invariants

1. A Platform User has at most one Workspace membership in this Workspace DB; a person may hold memberships in other Workspaces only in their separate DBs.
2. `workspace_memberships` is the membership lifecycle projection. `membership_roles` is the only role-assignment projection; no scalar role field may be reintroduced.
3. Role and permission changes require an authenticated principal and an explicit permission to grant/revoke the target role/permission. A member cannot grant privileges to themselves unless a separately approved break-glass workflow exists.
4. Every grant/revoke event binds membership, role/permission key, resource scope, actor principal, authentication event, authority basis, policy version, command ID, timestamp and outcome.
5. Events are append-only. Revocation is a new event; historical grants are never overwritten/deleted.
6. Current projections are changed only by narrow, audited command functions or a trusted service boundary. Ordinary runtime roles cannot write role/permission projections directly.
7. A role name does not imply all permissions. Explicit permission rows and resource scope govern actions.
8. Membership suspension/end immediately invalidates role-derived permissions. Re-activation requires a new audited command and does not silently resurrect previously revoked grants.
9. Role/permission evaluation uses a consistent snapshot and denies if membership is inactive, scope mismatched, authority cannot be verified, or policy version is unsupported.

## 3. Guardian relationship and permission invariants

1. A guardian link is a relationship claim, not proof of legal authority.
2. Verification and revocation are separate append-only events bound to the exact student and guardian Platform User, verification method, evidence reference, actor/authentication event, policy version and validity interval.
3. A guardian permission is per student, per scope and per action. It references a currently verified relationship and an authority evidence reference; no broad all-students or implied financial/medical/confidential access.
4. Permission grant, change, expiry and revocation are append-only events. The current permission projection is derived from the latest valid event chain.
5. Every use rechecks current relationship status, authority validity, scope, expiry/revocation, student rights and legal/policy version. A stale cached permission is not sufficient.
6. The system does not infer legal guardianship from surname, phone number, family label, shared address or self-assertion.
7. Guardian access to counselor-private notes and confidential communications is denied by default.
8. Q-007's Iran-specific age, custody, evidence, student-objection and dispute matrix remains an external legal/PO gate. Until approved, the implementation must fail closed for operations that require unresolved legal authority.

## 4. Suggested append-only event families

### Membership governance
- `membership_lifecycle_events`: invited, activated, suspended, reactivated, ended.
- `membership_role_events`: role_granted, role_revoked, superseded.
- `membership_permission_events`: permission_granted, permission_revoked, scope_changed.

### Guardian governance
- `guardian_relationship_events`: relationship_claimed, verification_submitted, verified, rejected, revoked, disputed, reinstated.
- `guardian_permission_events`: permission_granted, permission_expired, permission_revoked, scope_changed.

Each event has immutable event ID, aggregate ID, event sequence, event type, actor principal reference, authn event reference, authority/evidence reference, policy version, effective time, recorded time, idempotency key, payload hash and minimal non-sensitive metadata. Sensitive documents and secrets are stored only in an approved private evidence store and referenced by opaque IDs.

The event tables are the audit source. Current-state tables are projections. If event and projection disagree, deny access and reconcile; do not trust the projection silently.

## 5. Transaction and concurrency rules

- Each aggregate (membership, guardian link, guardian permission) has a monotonic event sequence.
- Append event and update current projection in one Workspace DB transaction.
- Lock the aggregate row and compare expected sequence/version; stale commands reject.
- Same idempotency key/same payload returns the original result; same key/different payload rejects.
- Concurrent revoke and permission use must have a documented linearization point. Authorization decisions must be bounded by the committed event sequence and fail closed if freshness cannot be proven.
- Membership end/suspension revokes effective access immediately in the same transaction or through a fail-closed gate that denies until projection reconciliation.
- No event may grant a permission that is broader than the actor's own authority and grantable scope.

## 6. Required test catalog

- No duplicate membership for the same Platform User in one Workspace.
- No scalar role source; all role evaluation derives from `membership_roles` plus explicit permissions.
- Runtime cannot directly mutate membership roles/permissions or governance event tables.
- Unauthorized self-grant, privilege escalation, cross-scope grant and grant-to-higher-role reject.
- Grant/revoke events are append-only; event sequence cannot fork or skip.
- Same-key/same-payload replay is idempotent; payload mismatch rejects.
- Suspension/end invalidates all effective roles/permissions; reactivation does not resurrect revoked grants.
- Guardian relationship verification requires trusted evidence; a relationship claim alone cannot grant legal authority.
- Guardian grant/revoke events bind exact child, guardian, scope, authority evidence and actor/authentication event.
- Revoked/expired/disputed guardian relationship invalidates all dependent permissions.
- Q-007 unresolved authority fails closed; no default legal age or custody rule is inferred.
- Concurrent grant/revoke and access checks serialize or deny on stale state.
- Direct projection tampering is denied and event/projection drift is detected.
- Audit events contain no OTP, bearer token, passwords, keys or unnecessary identity-document content.

All tests are specifications until executable SQL and service tests exist and pass.

## 7. Gate impact

This contract closes neither WS-DOM-02 nor WS-DOM-03 by itself. The current role projection is canonical, but append-only grant/revoke evidence and runtime command restrictions remain to be implemented/tested. Guardian authority remains blocked by Q-007 and trusted verification. Phase 2 remains **NOT READY**.


## 8. Executable draft status — 2026-11-10

A companion PostgreSQL draft now exists at `workspace_governance_events_draft.sql`, with synthetic regression tests at `tests/workspace_governance_event_tests.sql` and CI integration in `.github/workflows/phase2-schema-tests.yml`.

Implemented in the draft:
- Unified append-only event ledger for membership lifecycle, role, permission, guardian relationship and guardian permission event families.
- Per-aggregate monotonic sequence allocation serialized with a transaction advisory lock.
- Unique idempotency key; exact replay returns the original event, while payload/aggregate/type mismatch is rejected.
- Active membership check for membership actors, required authentication reference for actor-attributed events, and required authority reference for grant/verification event types.
- UPDATE/DELETE rejection and deny-by-default table/function grants for runtime, worker, exporter and existing activation function-owner roles.

Not implemented and intentionally not implied:
- Projection updates to `membership_roles`, `membership_permissions`, `student_guardian_links` or `guardian_permissions`.
- Cryptographic validation of authentication/authority references. Non-empty references are not proof.
- Trusted authorization adapter, role-grant matrix, guardian legal verification, concurrent access-vs-revocation service semantics, and projection reconciliation.
- No application role is granted EXECUTE on the append function yet.

The CI test verifies ledger behavior only. WS-DOM-02/03 remain HIGH until the trusted command adapter, projection transaction boundary, authorization tests and Q-007 legal decision are complete.

## 9. Projection materializer and ownership boundary — 2026-11-10

The PostgreSQL draft now materializes the supported membership projections in the same transaction as the immutable event:
- `role_granted` / `role_revoked` update `membership_roles`.
- `permission_granted` / `permission_scope_changed` / `permission_revoked` update `membership_permissions`.
- Membership lifecycle events update `workspace_memberships`; suspension/end remove current role and permission projections.
- Guardian relationship/permission events fail closed and are not materialized pending Q-007 and trusted legal verification.
- Idempotent replay returns the original event without reapplying projection effects, including after the original actor has since been suspended. Reuse with changed payload/actor/evidence/policy/effective time rejects.

The function is transferred to a dedicated non-login `governance_owner` per Workspace, distinct from the activation `function_owner`. Its grants are limited to the event ledger and membership/role/permission projection tables/columns needed by this materializer. Runtime, worker, exporter and activation function owner receive no execute or event-table access. The owner has no persistent schema CREATE privilege.

**Important gate boundary:** the function is an internal projection materializer, not an authorization decision engine. It does not prove the authenticity of `authn_event_ref` or `authority_ref`, decide which roles an actor may grant, prevent self-escalation by policy, or provide a trusted application adapter. No application role is granted EXECUTE. Do not connect a service until a separate signed/opaque assertion verifier, grantability matrix, actor/target/scope checks and concurrency contract are reviewed and tested.

Synthetic CI now verifies event-to-projection atomic behavior, revocation, suspension invalidation, replay after actor suspension, and the dedicated owner privilege boundary. Guardian projections remain blocked. WS-DOM-02 is partially remediated, not closed; WS-DOM-03 remains HIGH. Phase 2 remains **NOT READY**.
