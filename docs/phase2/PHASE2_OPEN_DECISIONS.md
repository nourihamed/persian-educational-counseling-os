# Phase 2 Open Decisions & Required Product Owner / Specialist Inputs

**Status:** Preparation register; no new Product Owner decision is made by this document.  
**Authority:** Product Owner makes product decisions; qualified specialists provide legal/security/operations evidence.  
**Gate:** Phase 2 NOT READY. D-014 synthetic-only restriction remains in force.

## 1. Decisions that cannot be safely inferred

| ID | Topic | What remains open | Supervisor recommendation | Required authority |
|---|---|---|---|---|
| Q-007 | Parent/guardian legal authority | Iran age bands, legal guardianship evidence, custody/dispute, student rights/objection, emergency exceptions | Keep per-child/per-scope model; block Parent APIs and guardian transfer approval until qualified Iran legal review and PO approval | Iran legal reviewer + PO |
| Q-020 / OQ-F2 | Retention periods | Numeric durations by R1–R9 category, backup expiry, audit retention, financial/tax periods, approvers and owners | Do not enter numbers until legal/tax/privacy review; unresolved duration must block destructive deletion | Legal/tax/privacy reviewer + PO |
| OQ-D | Control Plane HA | RPO/RTO, sync/async replication, acceptable lag, manual/automatic promotion, fencing/quorum | Prefer conservative single-writer with independently verified fencing; select mode only after workload and loss-tolerance analysis | PO + Security/Operations |
| OQ-E | Transfer freeze/drain | Maximum freeze duration, in-flight transaction drain timeout, abort policy, manual intervention thresholds | Define a hard bounded freeze with no snapshot until barrier/drain is proven; exact values require measured workload and service SLA | PO + Engineering/Operations |
| Approval conflict policy | Multiple approval roles | Whether one person may satisfy multiple approval kinds (e.g. owner is also destination counselor) | Default deny self-approval / incompatible role combinations unless explicitly approved and independently evidenced | PO |
| Contact recovery | Old mobile unavailable | Whether recovery can use guardian, manual support, documentary proof or alternate channel | Separate high-assurance recovery workflow; never bypass new-number proof or reuse ordinary contact-change flow | PO + Security + legal |
| Assessment semantics | Dynamic test delivery | Fixed question count vs per-attempt delivered set, custom error reasons, exam subject-level results, versioning | Store immutable assessment version and per-attempt delivered question set; reconcile all responses/counts/score at finalization | PO / Educational domain owner |
| Activity taxonomy | Activity types | Whether exam, quiz, flashcards, remediation, overdue work, routine test and class follow-up are kinds, linked entities or tags | Use typed specialized entities with referential integrity; keep shared Activity as scheduling/execution projection | PO / Educational domain owner |
| Credit lifecycle | Purchases/refunds/cancellation | Purchase, grant, renewal, refund, cancel/reactivate and fee accounting semantics | Keep Student Credit ledger separate from fiat billing; define compensating entries and refund eligibility before implementing payment flow | PO / Finance |
| Capacity policy | Dimension ceilings | Counselor, branch, concurrent user, active student, cell capacity values and overage behavior | Model configurable dimensions; no numeric defaults except explicitly accepted provisional limits, which are not measured capacity | PO + Operations |
| Notification disclosure | Parent/student/counselor | Which events may disclose student details, and how revocation/transfer affects queued messages | Default minimum disclosure; re-check recipient permission and current ownership immediately before delivery | PO + Privacy |
| File storage | Provider and URL TTL | Provider, region, max signed URL lifetime, malware scanner and key custody | Provider-neutral private object model; no public buckets; authorize immediately before signing | PO + Security/Operations |

## 2. Technical closure items that do not require new business decisions

1. Replace `transfer_approvals` with append-only approval/revocation/supersession event model; preserve historical evidence and serialize revocation against switch.
2. Add contact-change command/audit/idempotency schema and trusted verifier boundary; do not accept caller-provided proof flags.
3. Complete durable Saga command/event envelope, outbox publisher metadata, inbox payload-hash dedupe and source/destination projection state.
4. Resolve Workspace schema HIGH findings WS-DOM-01..03 and add the missing assessment/planning/curriculum/class structures.
5. Add archive/reactivation capacity transaction and final-slot concurrency regression.
6. Reconcile API contracts, root docs, and the PR #8–#11 historical branches against PR #12.
7. Run fresh PostgreSQL 16 CI on the exact final SHA; current Run #231 predates the new final-slot race workflow step.
8. Perform final independent review and obtain explicit PO gate decision.

## 3. Decision sequencing recommendation

1. First resolve structural data-model choices that affect schema shape: membership role authority, assessment version/count semantics, activity taxonomy, approval event history.
2. Then obtain legal/privacy decisions: Q-007 and Q-020.
3. Then set operational parameters from measured requirements: OQ-D, OQ-E, capacity, storage and notification policy.
4. Only after the contracts and tests are reconciled should implementation phases begin.

## 4. No silent defaults

- No legal age threshold, guardian document, retention duration, RPO/RTO, retry count, freeze timeout, URL TTL, capacity limit, fee amount or refund policy is selected here.
- Recommendations are not decisions.
- Existing high-level accepted decisions remain controlling (Workspace-centric tenancy, OQ-B Option K, OQ-D Option A direction, OQ-E Option B direction, OQ-F2 category-based retention, OQ-G per-child/per-permission parent access).
- This register does not authorize Phase 3, production deployment, merging, or real student data.

**Current status: NOT READY.**

## Product Owner decisions resolved/clarified on 2026-11-13

These are now approved at the product-policy level and must be reflected in the contracts/schema. They do not constitute implementation evidence.

| Topic | Approved direction | Still open / fail-closed boundary |
|---|---|---|
| Assessment semantics | Fixed immutable question set and order per published version for MVP; adaptive/per-attempt delivery disabled | Schema must persist version-question membership/order and enforce response FK consistency; adaptive mode needs a separate decision |
| Activity | Specialized Test/Exam/Class/Assignment/Review entities plus shared Activity scheduling/tracking layer | Exact taxonomy and detailed subtype links must be reconciled with MVP scope |
| Transfer approval conflict | Default incompatible approvals separated; only contemplated exception is source counselor = destination Workspace owner | Exception disabled until independent approver and exact authority are approved; no implied Platform Admin privilege |
| Student Credit archive/reactivation | Archive within 7 calendar days of original activation permits compensating credit return; free reactivation only within original entitlement period | Returned credit is reserved for same student and cannot be spent elsewhere; after original period, new debit required |
| OQ-D HA | Existing Option A preserved; manual promotion may be pilot runbook procedure | Replica, independent backup and restore drills remain; RPO/RTO, replication/lag, fencing and split-brain evidence remain open |
| MEDIUM scope | Supervisor's base-schema/security-contract allocation accepted | Deferred provider/operational implementations must not remove required base ownership, audit, authorization or idempotency contracts |

The transfer exception authority remains a Product Owner/specialist decision item. Q-007 and Q-020 remain open. Production verifier/key policy remains deferred to Platform Security. Phase 2 remains NOT READY.
