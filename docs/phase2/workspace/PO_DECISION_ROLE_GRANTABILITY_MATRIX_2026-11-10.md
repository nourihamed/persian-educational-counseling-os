# Product Owner Decision — Workspace Role Grantability Matrix

- **Decision date:** 2026-11-10
- **Status:** ACCEPTED
- **Authority:** Product Owner
- **Scope:** Role assignment, membership lifecycle and permission delegation within a Workspace/Organization
- **Data policy:** Synthetic data only (D-014); this decision does not authorize real student data.

## 1. Accepted decisions

The Product Owner explicitly approved all five recommendations below.

| Principal / role | Allowed authority | Explicit restrictions |
|---|---|---|
| Platform Admin | Perform narrowly scoped Platform Governance operations, including the already accepted approval of initial/replacement Organization Manager appointments | No general Workspace write access; no unrestricted student-data access; no implied right to manage ordinary Workspace roles or permissions |
| Organization Manager | Invite, activate and revoke counselor memberships within that manager's own Organization/Workspace, subject to authenticated and audited commands | Cannot appoint or approve another Organization Manager; cannot act outside own Workspace; does not automatically gain access to every student's private records |
| Counselor | No role or permission delegation | Student access remains limited to students explicitly assigned to that counselor |
| Branch Manager | Operational management of the assigned Branch only | No organizational role-granting authority; no authority beyond assigned Branch scope |
| Other Workspace staff | Operational access only, limited to explicitly assigned permissions and scope | No role or permission delegation |

## 2. Organization Manager appointment rule

The previously accepted decision remains controlling:

- Only a Platform Admin may approve an initial Organization Manager appointment or replacement.
- An existing Organization Manager may nominate/request a replacement but cannot approve or complete the appointment.
- No second-Organization-Manager approval workflow is required.
- The Platform Admin action is a narrow Governance capability and does not grant general Workspace or student-data access.

## 3. Mandatory authorization invariants

1. **Deny by default:** any role, permission, delegation or action not explicitly allowed by this matrix or another accepted Product Owner decision is denied.
2. **No self-grant:** a principal cannot grant, activate or expand their own role/permissions.
3. **No privilege escalation:** an actor cannot grant a role/permission equal to or above their own authority, nor broaden scope beyond their authority.
4. **Tenant/Workspace isolation:** an Organization Manager is confined to their own Workspace; a Branch Manager is confined to the assigned Branch; a Counselor is confined to assigned students.
5. **No implied data access:** role assignment alone never grants access to all student records. Student-level access requires explicit relationship/assignment and object-level authorization.
6. **Auditable lifecycle:** invite, activation, revocation, replacement, rejection and scope changes must be authenticated, bound to exact actor/target/Workspace/scope/policy version, idempotent where applicable, and append-only audited.
7. **Revocation freshness:** revoked membership/permission must not authorize subsequent reads, writes, exports, background jobs or notifications. Cache and queued-work revalidation rules must enforce this.
8. **No delegation by implication:** operational permissions do not imply authority to grant permissions to another principal.

## 4. Explicitly not decided

- Parent/guardian and student delegation or legal authority; Q-007 remains open and guardian event families remain fail-closed.
- Transfer approval conflict-of-interest rules (e.g. one principal satisfying multiple approval kinds); this remains a separate Product Owner decision.
- Platform Admin emergency access, general write permissions or access to student content.
- Any staff role or permission not explicitly listed in this decision.
- Legal age thresholds, guardian evidence, retention durations or production security credentials.

## 5. Required acceptance tests

The future implementation must include positive and negative tests for:

- Organization Manager can invite, activate and revoke a counselor only in the same Workspace.
- Organization Manager cannot appoint/replace another Organization Manager, grant self, cross-Workspace membership, or access all student records by role alone.
- Platform Admin can perform the narrowly scoped Organization Manager appointment approval, but cannot use that capability as general Workspace DML or student-data access.
- Counselor cannot grant roles/permissions or access an unassigned student's records.
- Branch Manager cannot grant organization-level roles or operate outside the assigned Branch.
- Other staff cannot delegate roles/permissions.
- Self-grant, privilege escalation, scope expansion, stale membership, replay and cross-Workspace IDOR attempts fail closed.
- Revocation takes effect for subsequent API reads/writes, exports, background jobs and notifications, with a documented authorization linearization point.
- Audit events bind actor, target, Workspace/Branch, action, exact scope, policy version, timestamp and outcome without storing secrets.

These are acceptance criteria only. Unless separately reported as implemented and executed on an exact commit, they must be treated as NOT IMPLEMENTED / NOT RUN.

## 6. Related decisions and contracts

- `PO_DECISION_ROLE_GRANTABILITY_2026-11-10.md` — Organization Manager appointment approval.
- `WORKSPACE_GOVERNANCE_AUTHORIZATION_ASSERTION_CONTRACT.md` — trusted verifier and governance command boundary.
- `WORKSPACE_GOVERNANCE_EVENT_CONTRACT.md` — append-only governance events and projections.
- `../PHASE2_OPEN_DECISIONS.md` — unresolved legal, operational and product decisions.

**Gate impact:** This closes the Product Owner decision for the listed role-grantability matrix. It does not implement the verifier/adapter, schema, API authorization or acceptance tests. Phase 2 remains **NOT READY** until the outstanding HIGH findings and required evidence are closed.
