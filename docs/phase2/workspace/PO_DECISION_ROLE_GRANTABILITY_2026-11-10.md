# Product Owner Decision — Organization Manager Appointment

- **Decision date:** 2026-11-10
- **Status:** ACCEPTED
- **Scope:** Appointment or replacement of an Organization Manager
- **Authority:** Product Owner

## Decision

Only a Platform Admin may approve an Organization Manager appointment or replacement.

An existing Organization Manager may nominate/request a replacement, but cannot approve or complete that appointment. A second Organization Manager's approval is not required; no dual-manager approval workflow is introduced.

## Required controls

1. The Platform Admin approval must be authenticated and bound to the exact target Organization/Workspace and proposed manager.
2. The system must verify that the target principal is eligible and that the action is within the Platform Admin's permitted governance scope.
3. Record the actor, target, Organization/Workspace, decision, timestamp, reason/reference where applicable, and policy version in an auditable event.
4. Do not infer that this decision grants Platform Admin general access to Workspace student data or unrestricted operational privileges.
5. Do not infer any other role-delegation rights from this decision. Unspecified grants remain deny-by-default until separately approved.

## Rationale

This keeps a high-impact governance action under one clearly accountable authority and avoids a more complex second-manager approval workflow.

## Explicitly not decided

- The complete role-to-role grant/revoke matrix for other roles.
- Counselor permission delegation.
- Parent/guardian or student delegation and legal authority rules (Q-007 remains open).
- Platform Admin general write privileges or emergency access.

## Related contract

See [WORKSPACE_GOVERNANCE_AUTHORIZATION_ASSERTION_CONTRACT.md](WORKSPACE_GOVERNANCE_AUTHORIZATION_ASSERTION_CONTRACT.md), section 5.1.
