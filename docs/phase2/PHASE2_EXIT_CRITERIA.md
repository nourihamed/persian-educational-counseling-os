# Phase 2 Exit Criteria & Evidence Matrix

**Phase:** Database & Domain Model  
**Current Gate:** NOT READY  
**Scope:** Architecture/domain model, draft schema, constraints, API/service contracts and executable synthetic database tests. This phase does not authorize production deployment or real student data.

## 1. Gate interpretation

Phase 2 must finish the database/domain architecture and define testable contracts before implementation phases. It must not silently absorb full production infrastructure, API service delivery, KMS deployment, distributed worker deployment or live backup/failover drills if those belong to later authorized phases.

However, a later implementation may not begin with an undefined security/domain contract. Phase 2 must define the trust boundaries, data model, invariants, state transitions, failure behavior, acceptance tests and explicit dependencies for those later implementations.

A design contract is not implementation evidence. A draft SQL test is not runtime/API/operational evidence. Each evidence type must be reported separately.

## 2. Phase 2 exit checklist

| Area | Phase 2 design/schema exit requirement | Current status |
|---|---|---|
| Canonical architecture | Workspace-centric Control Plane / Workspace DB ERD and authority boundaries, no false cross-DB atomicity | PARTIAL — baseline exists; reconcile all artifacts |
| Product decisions | Collision-free decision crosswalk; no unapproved D-number allocation; all accepted PO choices traced | PARTIAL — crosswalk exists; PR #8–#11 cleanup remains |
| Global identity | Initial admission, mobile+grade uniqueness, HMAC rotation and contact-change data contract | PARTIAL — initial admission/rotation SQL tested; contact-change contract only |
| Approval evidence | Three cumulative approval types, principal/authority binding, revocation/reapproval event model and cutover revalidation | NOT READY — contract exists; current schema shape conflicts |
| Transfer | Freeze/snapshot/staging/Saga state model, event envelope, outbox/inbox semantics, recovery matrix | PARTIAL — contracts and switch draft exist; schema/runtime boundary needs reconciliation |
| Tenant authorization | Principal, membership, role, permission, assignment, guardian relationship and object scope model | PARTIAL — contract exists; membership/guardian schema gaps |
| Workspace lifecycle | Activation, suspension, archive/reactivation, transfer projection and capacity invariants | PARTIAL — activation tested; lifecycle closure incomplete |
| Educational domain | Curriculum, planning inputs/items, execution, assessments, analysis, classes, reviews and history | NOT READY — skeleton exists; WS-DOM findings open |
| Versioning | Program/Plan version ownership, immutability, provenance, publication and edit rules | PARTIAL — draft triggers; plan edit-state decisions/tests incomplete |
| Student Credit | Wallet/ledger, debit, reversal, purchase/refund/renewal boundaries and idempotency | PARTIAL — activation/debit/reversal draft; commercial lifecycle incomplete |
| Capacity | Dimension model, atomic counters, archive adjustment, final-slot races and reconciliation | PARTIAL — same-enrollment race tested; final-slot test added, fresh CI pending; archive lifecycle open |
| Files/notifications | Private object metadata, quarantine/scan, authorization, transfer fencing, recipient isolation | PARTIAL — skeleton/contract only |
| Retention/legal hold | Category-based versioned policy model, legal-hold and restore-suppression contract | PARTIAL — contract only; schema integration and legal approvals open |
| Operations | HA/backup/restore/failover/capacity boundaries and acceptance evidence requirements | PARTIAL — contract only; environment execution belongs to later gate |
| SQL quality | Fresh PostgreSQL 16 CI on exact final tree, role catalog tests, constraints, races, regression | NOT READY — Run #231 is historical; new capacity race not covered |
| Documentation | Root canonical docs, Project State, Roadmap, Test Plan, Changelog and Supervisor Review agree | PARTIAL — active reconciliation underway |
| PR integration | PR #8–#11 disposition, PR #12 base/head consistency, no accidental main changes | NOT READY — PRs #8–#12 still open; PR #12 diverged 2 commits behind main |
| Independent review | Final review against exact SHA and evidence; PO accepts gate separately | NOT READY |

## 3. Findings that block design/schema exit

### HIGH
- WS-DOM-01 assessment total/response/score integrity.
- WS-DOM-02 competing membership role sources of truth.
- WS-DOM-03 guardian relationship/permission auditability and authority proof.
- Transfer approval table cannot preserve revoked and replacement approvals as separate immutable events.
- Contact-change has no schema/function/test draft yet; current contract is specification only.
- Durable Saga event schema and command/outbox/inbox boundaries need final reconciliation with current Control Plane DDL.
- Workspace lifecycle and capacity archive/reactivation transitions need explicit schema and tests.
- Final-capacity-slot concurrency test needs a fresh successful CI result.

### MEDIUM
- Assessment definition/versioning and per-subject exam results/custom error taxonomy.
- Curriculum subtopics, normalized planning constraints and explicit PlanItem relation.
- Canonical activity taxonomy and class participant/recurrence model.
- Credit purchase/refund/renewal data model and payment reconciliation boundary.
- File scan/quarantine and notification generation/permission fencing.
- Retention policy schema integration and Q-007/Q-020 ownership decisions.

## 4. Later-phase implementation gates (not Phase 2 implementation claims)

The following are required before their corresponding production features/pilot, but Phase 2's responsibility is to define the contract and tests:
- production KMS/HSM, key custody, cryptographic verifier and backfill/revocation drills;
- HTTP API authentication/RBAC/object authorization and E2E IDOR/file/export/notification tests;
- durable Saga workers, freeze/drain controller, snapshot/staging service, crash recovery;
- production Workspace credentials, secret rotation/revocation and pool eviction;
- independent backup/restore, failover, split-brain, RPO/RTO and measured capacity on the selected target;
- legal/tax/privacy approval of numeric retention and Iranian guardian/age rules;
- D-014 written Product Owner authorization before any real student data.

These items must remain visible as downstream gates; their absence must not be described as production readiness.

## 5. Product Owner / legal decisions that must remain explicit

- Q-007: detailed Iran age/guardian/evidence/dispute/student-rights matrix.
- Q-020 / OQ-F2: numeric category retention periods, named legal/privacy reviewer and deletion approver.
- OQ-D: RPO/RTO, replication mode, failover mode and split-brain authority.
- OQ-E: freeze/drain timeout and recovery thresholds.
- OQ-B: production KMS/HSM and key custody implementation details.
- Conflict-of-interest policy if one principal holds multiple transfer approval roles.
- Exact activity/assessment taxonomy where product behavior is not already determined.
- Credit purchase/refund/renewal and cancellation policy values.

No value may be invented to make the checklist appear complete.

## 6. Integration safeguards

- Work only on the Phase 2 draft branch until a separately approved integration plan exists.
- Do not merge PR #12 or close PR #8–#11 without Product Owner authorization.
- Do not force-push/rebase the long-running branch without an explicit history-rewrite plan.
- Verify exact branch HEAD, base HEAD, compare status and CI on the final SHA.
- Keep D-014 synthetic-only; do not start Phase 3.
- A green mergeability flag is not a phase approval.


## 6A. Newly added contract coverage (2026-11-10)

- `control_plane/CONTACT_CHANGE_REVERIFICATION_CONTRACT.md`
- `transfer/TRANSFER_APPROVAL_IDENTITY_AUTHORITY_CONTRACT.md`
- `transfer/TRANSFER_SAGA_OUTBOX_INBOX_RECOVERY_CONTRACT.md`
- `workspace/WORKSPACE_GOVERNANCE_EVENT_CONTRACT.md`

These contracts improve design completeness but do not satisfy schema, executable-test, CI or runtime evidence rows above. The approval SQL's current non-empty-reference checks remain insufficient; the Workspace governance event model is not yet implemented. Exact branch SHA and CI must be refreshed after all later SQL/test changes.

## 7. Gate rule

Phase 2 may be recommended **APPROVED** only when all Phase 2 design/schema requirements are closed, every unresolved decision is either approved or explicitly deferred with a named downstream gate, the draft schema/test tree passes fresh CI on the exact final SHA, PR/canonical-document reconciliation is complete, and the independent Supervisor review has no open HIGH design/schema findings.

If a bounded set of non-critical design details remains but is explicitly constrained and does not block the next phase, a **CONDITIONAL PASS** may be considered. Any unresolved HIGH security/data-integrity/tenant-boundary defect means **NOT READY**.

**Current status: NOT READY.**


## 8. Open decision register

The consolidated list of unresolved Product Owner and specialist inputs, with recommendations and required authority, is maintained in `PHASE2_OPEN_DECISIONS.md`. This register does not make decisions or assign unapproved values.


## 9. Educational domain contract references

The required educational-domain design targets are now explicit:
- `workspace/ASSESSMENT_DOMAIN_CONTRACT.md` — assessment versioning, response integrity, deterministic scoring and per-subject exam results.
- `workspace/DETERMINISTIC_PLANNING_DOMAIN_CONTRACT.md` — normalized planning inputs, explicit PlanItems, replayability and explainability.
- `workspace/CURRICULUM_DOMAIN_CONTRACT.md` — complete curriculum hierarchy, ownership, versioning and mastery evidence.

The current Workspace SQL skeleton has not yet been reconciled with these contracts; design documents do not close WS-DOM findings.


## 10. Additional Workspace domain contracts

- `workspace/ACTIVITY_CLASS_DOMAIN_CONTRACT.md` — activity taxonomy, class participation, recurrence, attendance and assignment scope.
- `workspace/STUDENT_CREDIT_COMMERCIAL_LIFECYCLE_CONTRACT.md` — CRD vs fiat separation, payment-to-credit reconciliation and commercial lifecycle.
- `workspace/CAPACITY_LIFECYCLE_CONTRACT.md` — capacity dimensions, reservations, archive/reactivation and transfer capacity coordination.

The current SQL skeleton does not implement these complete lifecycles; all open product values remain explicit in `PHASE2_OPEN_DECISIONS.md`.


## 11. Governance event/projection status — 2026-11-10

The Workspace event ledger now has a draft transactional projection materializer for membership roles, permissions and lifecycle. Its dedicated non-login owner and least-privilege grants are part of the provisioning draft. This is not a trusted authorization service and no application role is granted execute.

Exit criteria still require:
- cryptographic or otherwise independently verifiable authentication and authority assertions bound to actor, target, action, scope, policy and event;
- explicit role/permission grantability matrix and anti-self-escalation rules; **Product Owner policy decision now accepted 2026-11-10** in `workspace/PO_DECISION_ROLE_GRANTABILITY_MATRIX_2026-11-10.md`; enforcement, trusted adapter and executable tests remain NOT IMPLEMENTED;
- trusted API/service adapter and object-level authorization tests;
- concurrent revoke-vs-read freshness/linearization tests;
- guardian legal authority, per-child permissions and revocation semantics after Q-007 is resolved;
- fresh CI on the latest branch head.

Until these pass, WS-DOM-02/03 remain HIGH and the phase gate remains **NOT READY**.


### 11.1 Latest verification — 2026-11-10

CI run #519 passed all 13 PostgreSQL workflow steps on commit `d45753924513f9920f714b966361b9697e8264d5`. Governance projection and role-privilege assertions passed. This is evidence for the SQL draft only. The remaining exit criteria listed above are still open; WS-DOM-02/03 remain HIGH and the phase gate remains **NOT READY**.


### 11.2 Trusted governance assertion contract

`workspace/WORKSPACE_GOVERNANCE_AUTHORIZATION_ASSERTION_CONTRACT.md` is now the required design target for authenticated governance commands. It does not close the gate: signature/issuer verification, proof receipt storage/consumption, role grantability policy, trusted adapter, API tests and guardian legal policy remain unimplemented. Application EXECUTE remains prohibited.
