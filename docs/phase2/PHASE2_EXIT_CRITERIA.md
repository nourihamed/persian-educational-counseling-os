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

Status vocabulary, applied to every item: **DONE** (implemented at the schema level and covered by executed
tests), **PARTIAL** (some of the item is implemented, the rest is named below), **NOT IMPLEMENTED**,
**DEFERRED** (allocated to a later phase by an approved decision). A DONE label is the implementation's
assessment of its own work at the database level. It is not a gate decision and does not close a finding:
closure is the independent Supervisor's call. Nothing here claims Phase 2 is approved.

### HIGH
| Item | Status | Evidence / what remains |
|---|---|---|
| WS-DOM-01 assessment total/response/score integrity | **DONE** (schema) | Version question membership and order are authoritative; responses bound by composite FKs; attempt policy = published policy. AVQ-01..22, ASM-01..30, ASM-RACE-01, WS-ROLE-16/17. The database still does not compute or validate a score — that is by design, per the assessment contract. |
| WS-DOM-02 competing membership role sources of truth | **PARTIAL** | Governance event ledger, receipt command boundary and role catalog tests exist (offered as evidence 2026-11-13). No new work in this batch. The Supervisor has not judged this sufficient. |
| WS-DOM-03 guardian relationship/permission auditability | **DONE** (schema) | Append-only link/permission events, projection change refused without its event, effective view. GDN-01..18. Guardian legal authority remains Q-007 and is not encoded. |
| Transfer approval revoked/replacement approvals as immutable events | **DONE** (schema) | Immutable approval events plus separate revocation events, one current per kind, serialized on the case row. APR-01..13, APR-RACE-01, SEP-01..29. |
| Contact-change schema/function/tests | **DONE** (schema) | One-time proof, atomic command, audit, outbox, separate owner/executor/verifier roles. CC-01..42, CC-RACE-01. Concurrency against HMAC rotation and against an ownership switch is **NOT RUN**. |
| Durable Saga event schema and command/outbox/inbox boundaries | **PARTIAL** | Schema reconciled and per-recipient delivery implemented after C-01: `cp_12_saga_outbox_delivery.sql`, `workspace_inbox_projection.sql`, SAGA-01..11, SAGA-R01..R32, INB-01..22. The **service-level** behaviour of contract section 10 is **NOT IMPLEMENTED** (freeze/drain, in-flight barrier, snapshot consistency, destination staging, real process crash, partition, chaos, outage/restore/failover, projection-drift repair, quarantine resolution). The inbox application path is **fail-closed** pending a verified transport (H-05). |
| Workspace lifecycle and capacity archive/reactivation transitions | **DONE** (schema) | Archive with atomic capacity release and the reactivation command with counselor validation. ARC-01..17, CRD-01..31, WS-REACT-RACE-01, WS-CRD-LOCK-01/02. Suspension capacity treatment remains an open policy question. |
| Final-capacity-slot concurrency test needs a fresh successful CI result | **PARTIAL** | The test runs green locally on every full run and in CI on `8abbbe3`. A fresh CI result is required on the final HEAD of this remediation batch and is **NOT VERIFIED by the implementation agent**. |

### MEDIUM
| Item | Status | Evidence / what remains |
|---|---|---|
| Assessment definition/versioning | **DONE** (schema) | AVQ-01..22. |
| Per-subject exam results and the custom error taxonomy | **NOT IMPLEMENTED** | Named in the assessment contract; no schema in this batch. |
| Curriculum subtopics, normalized planning constraints, explicit PlanItem relation | **NOT IMPLEMENTED** | No schema in this batch. |
| Activity taxonomy and class participants | **DONE** (schema) | Typed FK-backed sources, `class_participants`, `class_session_participants`. ACT-01..26. Class recurrence rules remain open. |
| Credit lifecycle: archive return, reserved entitlement, reactivation | **DONE** (schema) | CRD-01..31, WS-CRD-LOCK-01/02. The entitlement **period source** is **NOT IMPLEMENTED** and the production path is fail-closed (H-02, OQ-CRD-3). |
| Credit purchase, renewal, refund execution and payment reconciliation | **DEFERRED** | Phase 21/22 per PD-2026-11-13-F. |
| File scan/quarantine, notification generation and permission fencing | **DEFERRED** (operations) / **NOT IMPLEMENTED** (base contracts) | Base security contracts stay in Phase 2 per PD-2026-11-13-F; no schema in this batch. |
| Retention policy schema integration | **NOT IMPLEMENTED** | Blocked on Q-020 numeric durations. |

### Supervisor findings on head `8abbbe3` (remediation batch 2026-11-14)
| Finding | Status | Evidence |
|---|---|---|
| C-01 Saga delivery per recipient | **DONE** (schema) | `outbox_event_recipients`, delivery keyed `(event_id, workspace_id)`, completion only when all recipients acknowledge. SAGA-R01..R32. |
| H-01 archive clock read before the entitlement lock | **DONE** | Clock read after the lock; WS-CRD-LOCK-01/02, sensitivity verified against the pre-fix code. |
| H-02 entitlement period source | **DONE as fail-closed**; the source itself is **NOT IMPLEMENTED** | Production path refuses (OQ-CRD-3); caller-supplied period is synthetic-only and role-gated. CRD-28..31, WS-ROLE-18/19. |
| H-03 outbox acknowledgement authorization | **DONE** | Declared-recipient check, send-before-acknowledge check, per-recipient idempotency and conflict refusal. SAGA-R01..R03, R11, R12. |
| H-04 activation timestamp and lock order | **DONE** | One authoritative timestamp read after the locks, used for enrollment start, entitlement and audit. CRD-01/01b. |
| H-05 inbox trust boundary | **DONE as fail-closed**; verified transport is **NOT IMPLEMENTED** | Production entry point refuses (OQ-SAGA-1, PS-1..PS-4/PS-6); synthetic path role-gated. INB-02a/b/c/d. |
| H-06 / M-01 reactivation counselor and idempotency | **DONE** | Counselor role required, counselor bound to the command and compared on replay. CRD-07a/b/c, CRD-11b, CRD-12b. |

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
