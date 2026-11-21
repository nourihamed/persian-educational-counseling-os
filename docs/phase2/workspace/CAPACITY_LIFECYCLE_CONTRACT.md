# Workspace Capacity Lifecycle & Reservation Contract — Phase 2

**Status:** DRAFT / NOT APPROVED. Capacity invariants and transaction boundaries only. Numeric limits and unresolved state treatment require Product Owner/Operations decisions. Synthetic data only (D-014).

## 1. Capacity dimensions

The capacity engine must support independently configured dimensions:
- total active students per Workspace;
- active students per counselor;
- active students per branch;
- concurrent active users/sessions where approved;
- Workspace count and Workspace-per-cell placement;
- other explicitly versioned product entitlements.

Capacity is distinct from Student Credit. A Workspace may have sufficient CRD but insufficient capacity, or capacity but insufficient CRD.

## 2. Reservation and transaction rules

- Capacity limits are configured per Workspace/branch/counselor/cell with effective dates and policy version.
- Every reservation has a unique idempotency key, dimension, subject/reference, actor/service identity, expected policy version and reason.
- Counter updates and reservation events commit atomically with the business transition they protect.
- A counter row is locked/updated atomically; a check-then-insert without serialization is prohibited.
- A capacity reservation cannot be applied to a different student, enrollment, dimension or Workspace on replay.
- Capacity changes/reconciliation are audited; counters are projections over immutable reservation/release events and can be rebuilt.
- Final-slot race tests use two different students/enrollments and sufficient credits so the losing transaction proves capacity serialization rather than credit exhaustion.

## 3. Lifecycle impact — policy points requiring explicit values

| Lifecycle event | Required capacity behavior | Policy status |
|---|---|---|
| Requested / awaiting consent | No active-student slot until activation; optional temporary reservation must be explicitly modeled | NEEDS POLICY |
| Activation | Atomically reserve active-student capacity with CRD debit and enrollment activation | DRAFT SQL IMPLEMENTED / synthetic tests |
| Temporary suspension | Whether slot remains consumed depends on suspension semantics and grace period | NEEDS PO DECISION |
| Archive/offboarding | Release active-student slot atomically with archive state; preserve historical enrollment | REQUIRED DESIGN; function/test missing |
| Reactivation | Re-reserve capacity and revalidate entitlement/credit policy before active state | REQUIRED DESIGN; function/test missing |
| Transfer destination preflight | Check destination limits and create an expiring transfer reservation before cutover | REQUIRED DESIGN; Saga contract only |
| Transfer cutover | Destination capacity reservation must be valid at ownership switch; source slot release follows source fencing/ownership switch | REQUIRED DESIGN; no cross-DB atomicity claim |
| Workspace suspension/closure | Block new reservations; existing active student treatment follows approved lifecycle policy | NEEDS POLICY |
| Capacity increase/decrease | Versioned policy change; cannot silently invalidate existing reservations | NEEDS POLICY |

## 4. Transfer-specific accounting

- Source and destination capacity are separate Workspace-local ledgers.
- The Control Plane ownership switch is authoritative, but cannot atomically update both Workspace counters.
- Destination reservation must be durable and case/generation-bound before cutover.
- After switch, destination activation/projection finalization is retried forward; source capacity release is reconciled after the source is fenced.
- Temporary double-reservation during transfer may be necessary to prevent overbooking; the policy and reporting semantics must be explicit.
- If destination reservation expires or capacity is consumed before cutover, the switch must fail closed and the case must re-preflight.
- No credit or wallet transfer occurs as part of capacity movement.

## 5. Reconciliation

A periodic reconciler compares:
- active enrollments vs active-student reservation events/counters;
- counselor/branch assignments vs scoped capacity reservations;
- transfer reservation state vs Control Plane case/ownership generation;
- current policy version vs reservation policy version.

The reconciler may repair counters/projections only from authoritative events; it must never silently change enrollment lifecycle or Control Plane ownership.

## 6. Required tests

1. Two different enrollments race for the final active-student slot; exactly one succeeds.
2. Same activation idempotency key cannot reserve twice or alter another student's reservation.
3. Activation failure rolls back CRD debit, capacity event and enrollment state.
4. Archive releases exactly one slot; duplicate archive does not underflow.
5. Reactivation cannot exceed capacity and is idempotent.
6. Suspension behavior matches approved policy.
7. Transfer destination reservation is case/generation-bound, expires safely and cannot be reused.
8. Transfer cutover and source release recover correctly after crash at each boundary.
9. Counter rebuild from event ledger matches stored projection.
10. Capacity policy change does not silently overbook or invalidate existing reservations.
11. Counselor/branch/cell capacity boundaries are enforced independently.
12. Cross-Workspace capacity events cannot affect another Workspace.

Existing CI Run #336 passed the first final-slot race test on SHA 52bd034; later membership-role schema changes are not covered by that run. Fresh CI remains pending.

## 7. Open decisions

- Suspension capacity treatment and grace period.
- Temporary reservation rules for pending activation and transfer.
- Whether transfer permits temporary double-reservation and how it is reported/billed.
- Numeric limits and overage/upgrade behavior per dimension.
- Archive/reactivation eligibility and associated CRD policy.
- Reconciliation frequency and manual intervention thresholds.

No numeric limit or suspension/refund policy is inferred here.

**Gate impact:** Activation foundation exists, but archive/reactivation, transfer reservation and multi-dimensional reconciliation remain open. Phase 2 remains NOT READY.
