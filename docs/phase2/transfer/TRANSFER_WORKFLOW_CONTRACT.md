# Student Transfer Workflow — Phase 2 contract

**Status:** DRAFT / NOT APPROVED. OQ-E Option B is the accepted MVP direction. Synthetic data only (D-014).

## 1. Authority and invariants

- Control Plane is authoritative for current Workspace owner and monotonically increasing `ownership_generation`.
- Exactly one active owner exists for a platform student.
- Global mobile+grade claim is enforced only in Control Plane.
- A transfer requires all cumulative approvals: verified guardian consent, prior counselor's own authenticated fee-receipt confirmation, and destination Workspace acceptance.
- Initiators are verified parent/legal guardian, current counselor, or destination Workspace. Platform Admin cannot initiate; support review is not a transfer.
- No private counselor notes/confidential communications transfer automatically.
- Workspace DB records are projections, not ownership authority.

## 2. State machine

`requested → approvals_pending → approved → preflight_ok → staging → staged_verified → cutover_frozen → ownership_switched → projections_finalizing → completed`

Before ownership switch, a case may move to `cancelled` only when source writes are safely unfrozen and staged destination data is quarantined/deleted according to retention policy. Pre-switch recoverable failures may enter `failed_recoverable` and resume only from a verified checkpoint or move to `manual_intervention`.

After `ownership_switched`, cancellation and automatic rollback are forbidden. Recovery must move forward through `projections_finalizing → completed` or `manual_intervention → projections_finalizing`. A reverse transfer is a new transfer case with all required approvals.

## 3. MVP protocol (freeze + final snapshot)

1. Create transfer case with idempotency key and canonical payload hash. Same key + same hash returns the original case/result; same key + different hash is rejected and audited.
2. Validate authenticated initiator, source ownership, destination active status, capacity, contract/entitlement, and eligibility. These checks are revalidated immediately before cutover.
3. Collect approvals bound to authenticated principals and exact student/enrollment/case:
   - guardian: verified relationship + applicable legal authority + scope + expiry + no revocation;
   - prior counselor: authenticated principal currently responsible for source enrollment; explicit fee-receipt confirmation for this transfer;
   - destination: authorized Workspace manager/owner and destination counselor acceptance where required.
4. Preflight confirms destination resources and a transfer manifest allowlist. Exclude counselor-private notes, confidential communications, secrets, credentials and unsupported data categories.
5. Freeze source writes at a defined server-side boundary. The freeze is enforced by source-side authorization/mutation gate, not UI state. Record freeze token, generation, time and actor. Reject new writes; drain/settle in-flight writes under a documented transaction barrier.
6. Take a final consistent snapshot after the barrier. Record manifest version, record counts, checksums, source generation and snapshot identifier.
7. Import into destination staging tables/namespace that is inaccessible to normal users. Validate schema version, row counts, checksums, foreign-key integrity, ownership references, attachment references and excluded-data policy.
8. Revalidate all approvals, destination capacity, source owner/generation and freeze token. Any expiry/revocation/change aborts before switch and triggers safe unfreeze/recovery.
9. In one Control Plane transaction: lock transfer case and ownership row; verify state, source Workspace, expected generation, exact approvals, active claim; compare-and-swap owner; increment generation exactly once; update global claim; append ownership history; write outbox event; mark `ownership_switched`.
10. After switch, destination projection is activated only for generation N+1. Source projection is marked ended/read-only. Every source write/job/file access checks Control Plane owner and generation and fails closed.
11. Outbox is delivered at least once. Workspace inbox deduplicates immutable event ID and rejects stale generations. Reconciliation job retries projection finalization; it never changes global owner.
12. Mark completed only when destination projection and source revocation are verified and auditable.

## 4. Crash/recovery matrix

| Failure point | Required behavior |
|---|---|
| Before freeze | Retry idempotently or cancel |
| During freeze / in-flight writes | Keep source authoritative; complete barrier or safely unfreeze; never snapshot an inconsistent boundary |
| After snapshot, before import | Resume from immutable snapshot or cancel/unfreeze |
| During destination staging | Keep staging quarantined; retry idempotently or clean up |
| Integrity validation failure | Do not switch; quarantine, record reason, recover/cancel |
| Before Control Plane switch | Source remains owner; destination remains inaccessible |
| During switch transaction | Atomic commit or rollback; no partial ownership/outbox/history |
| After switch, before outbox delivery | Control Plane destination is authoritative; retry outbox; fail closed where projection unavailable |
| After destination activation, source still writable | Critical incident; generation fencing must reject source writes; reconcile and alert |
| Projection finalization outage | Keep destination as owner; retry forward; manual intervention if thresholds exceeded |
| Duplicate/out-of-order events | Deduplicate by event ID and generation; ignore stale generation; alert on impossible future generation |

## 5. Required fencing rules

- Every write/job carries immutable `workspace_id`, `platform_student_id`, expected generation, and event/job ID from trusted server-side context.
- No caller-supplied Workspace or generation is trusted as authorization.
- Before mutation, validate current Control Plane owner and generation; cache use requires bounded staleness proof, otherwise deny.
- A source Workspace at generation N is permanently stale after switch to N+1.
- Signed file URLs must be minted only after current owner + membership + object authorization; short TTL; no pre-signed URL survives a transfer beyond its TTL.

## 6. Unresolved operational parameters

Still open: freeze maximum duration, in-flight transaction drain timeout, snapshot format/version, retry/backoff, manual-intervention SLA, alert thresholds, RPO/RTO, backup retention, failover consistency, split-brain prevention, and exact legal retention periods. Do not invent numeric values.


## 8. Authenticated approval authority contract

The detailed identity and authority requirements are specified in `TRANSFER_APPROVAL_IDENTITY_AUTHORITY_CONTRACT.md`. This companion contract is normative for future implementation: a non-empty `approver_ref` / `authn_event_ref` or a count of three approval kinds is not proof of authenticated identity or authority. Every approval must be bound to the exact case/student/source/destination/generation/payload, verified by a trusted issuer/audience-pinned service, single-use, revocable before cutover, and revalidated immediately before ownership switch. Guardian legal authority remains blocked on Q-007; no Iranian legal age/custody rule is inferred.

## 7. Acceptance test catalog (specified, not executed)

- Same idempotency key/same payload returns same case; same key/different payload rejects.
- Concurrent transfer requests serialize to one open case.
- Missing/expired/revoked guardian consent rejects.
- Fee confirmation from wrong/non-current counselor rejects.
- Destination acceptance from unauthorized principal rejects.
- Freeze barrier rejects source writes and drains in-flight writes before snapshot.
- Snapshot is consistent and excludes private notes/confidential communications.
- Destination staging remains invisible until switch and validation.
- Checksum/count/schema mismatch prevents switch.
- Ownership switch atomically updates owner, generation, claim, history and outbox.
- Crash at every matrix boundary recovers correctly.
- Duplicate/out-of-order inbox/outbox events are idempotent and fenced.
- Stale source writes, jobs, exports and file access reject after switch.
- Control Plane unavailable/ambiguous returns deny (fail-closed).
- Post-switch recovery never cancels or silently reverts ownership.

**No test execution is claimed by this contract.**


## Durable cross-database delivery refinement

See `CROSS_WORKSPACE_TRANSFER_SAGA_CONTRACT.md` for the required outbox publisher lease protocol, Workspace inbox transaction, immutable event envelope, source-side freeze/drain barrier, destination staging isolation, failure recovery and reconciliation rules. This is design-only; no distributed Saga runtime or failure-injection evidence is claimed.
