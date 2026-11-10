# Cross-Workspace Transfer Saga, Outbox/Inbox & Recovery Contract — Phase 2

**Status:** DRAFT / NOT APPROVED. Architecture and acceptance contract only; no distributed runtime is claimed. Synthetic data only (D-014). This contract complements `TRANSFER_WORKFLOW_CONTRACT.md`.

## 1. Boundary and authority

- Control Plane (CP) is the sole authority for current owner and monotonically increasing ownership generation.
- Workspace databases hold local projections and educational records; they cannot grant ownership or independently authorize a transfer.
- A transfer spans CP and two Workspace databases. There is no distributed ACID transaction. The protocol is a forward-recoverable Saga.
- Before CP ownership switch, source remains authoritative. After the CP switch commits, destination is authoritative even if projections are delayed. Automatic reverse switch is forbidden.
- All messages are at-least-once. Consumers must be idempotent and generation-fenced.

## 2. Stable identifiers and message envelope

Every transfer command/event must include:
- immutable `event_id` / `command_id`;
- `transfer_case_id`, `platform_student_id`;
- `source_workspace_id`, `destination_workspace_id`;
- `expected_ownership_generation` and, after switch, `new_ownership_generation`;
- `event_type`, `schema_version`, `occurred_at_utc`;
- canonical `payload_hash`, correlation/causation IDs;
- producer identity and signature/key version or authenticated channel provenance.

Do not include mobile numbers, credentials, private counselor notes, OTPs, secrets or unrestricted student payloads in the event envelope. Snapshot content travels through a separately authorized private transfer channel, referenced by opaque immutable snapshot/manifest identifiers.

## 3. Source freeze and write barrier

A CP transfer coordinator requests a source-side freeze using an authenticated command bound to case/student/source/generation. The source-side controller must:
1. Verify current CP owner and generation from a trusted CP decision (or bounded-freshness proof; fail closed when stale).
2. Persist a durable freeze record unique to the case/student/generation.
3. Reject new writes, background jobs, file mutations, imports, and other mutating operations for that student.
4. Drain or settle in-flight transactions and jobs under a database transaction barrier. A UI flag or cached membership check is insufficient.
5. Return a signed/immutable freeze receipt with freeze token, source generation, barrier watermark, completion timestamp, controller version and outstanding-work count (zero at final barrier).
6. Maintain freeze until CP confirms pre-switch abort/unfreeze or the post-switch source-revocation command is applied.

Unfreeze is allowed only before CP ownership switch and only with an authenticated abort/recovery command for the same case and freeze token. After CP switch, source remains permanently fenced at generation N; unfreeze is prohibited.

No maximum freeze duration or drain timeout is invented here. They require measured workload and operational SLO decisions.

## 4. Snapshot and destination staging

- Snapshot must be consistent at/after the completed write barrier and identify source generation and barrier watermark.
- Manifest is versioned and allowlist-based. It explicitly records included entity types, excluded entity types, counts, checksums, schema versions and attachment references.
- Private counselor notes, confidential communications, secrets, credentials, unsupported categories and data lacking an approved legal basis are excluded.
- Snapshot and staging storage are private, encrypted, tenant-scoped and access-controlled. Access is granted only to the transfer worker for this case and expires/revokes on terminal state.
- Destination import occurs in quarantine/staging, never in live tables visible to normal users.
- Validation includes schema compatibility, row counts, checksums, referential integrity, student/Workspace ownership references, attachment authorization, exclusion policy and duplicate detection.
- A signed staging receipt binds the destination, case, source snapshot hash, target schema version, validation suite/version, results and timestamp.
- A failed validation never triggers CP switch. Quarantine cleanup is retention-aware and auditable.

## 5. Cutover and generation fencing

Immediately before switch, CP must revalidate:
- authenticated initiator and all three approvals/authority proofs;
- source owner and expected generation;
- source freeze receipt and final snapshot manifest;
- destination staging receipt and current eligibility/capacity;
- no approval revocation/expiry, legal hold, active dispute or transfer cancellation.

The CP transaction then atomically:
1. locks case and student ownership in the documented lock order;
2. compare-and-swaps source owner + generation N;
3. switches owner to destination and generation N+1 exactly once;
4. updates the global identity claim;
5. appends ownership history and immutable switch event/outbox row;
6. marks case ownership_switched.

Every Workspace write, job, file access, export and notification action must be fenced by current owner and generation. Source generation N is stale after switch; destination projection must accept only N+1. No consumer can change CP ownership.

## 6. Outbox and inbox delivery

### Control Plane outbox
- Outbox row is inserted in the same transaction as the ownership switch or other authoritative CP state transition.
- Rows have immutable event identity and payload hash; mutable delivery metadata is stored separately or updated only through controlled delivery-state transitions.
- Dispatcher claims work with a lease/claim token and bounded batch; it never holds a DB transaction open during network delivery.
- Delivery is at-least-once. A timeout after remote acceptance is treated as unknown and safely retried with the same event ID.
- Retries use bounded exponential backoff with jitter and a configurable maximum attempt/age policy. Numeric values are operational decisions, not hardcoded by this contract.
- Poison events move to an observable dead-letter/manual-intervention state; they are not silently dropped.
- Replay/re-drive is audited and preserves original event ID and payload hash.

### Workspace inbox
- Each Workspace consumer has a unique inbox event ID constraint.
- Event signature/channel provenance, target Workspace, case, student and generation are validated before applying.
- Duplicate event ID returns the previously recorded outcome without repeating side effects.
- Stale generation is rejected and recorded. Unexpected future generation is quarantined and alerted, not guessed into acceptance.
- Inbox receipt, local projection mutation and local outbox follow-up (if any) are one local DB transaction.
- A local consumer cannot mark global CP ownership complete merely by receiving an event.

## 7. Reconciliation and recovery states

The coordinator maintains durable per-step checkpoints. Recovery is deterministic and forward-only:
- Before freeze: retry request or cancel.
- Freeze requested/in progress: query source controller by stable command ID; never issue a different freeze token blindly.
- Freeze completed, snapshot absent: resume snapshot from barrier watermark or safely abort/unfreeze before CP switch.
- Snapshot complete, staging incomplete: retry import from immutable snapshot hash.
- Staging validation failed: quarantine, record failure, correct/retry or abort/unfreeze before switch.
- Ready to switch: revalidate every authority and evidence item; stale evidence restarts approval/preflight as policy requires.
- Switch result ambiguous: query CP by case/idempotency key. Never issue a new switch command with a new key.
- Switch committed, event undelivered: retry outbox; CP destination remains authoritative.
- Destination projection pending: retry inbox/projection; source stays fenced.
- Source revocation pending after switch: generation checks must already reject source writes; retry projection cleanup and alert.
- Threshold exceeded: manual intervention; preserve destination as owner after switch and do not rollback.

Every transition records actor/service, checkpoint, attempt, reason code, evidence references and timestamps. Sensitive snapshot contents do not enter logs.

## 8. Completion predicate

A transfer is complete only when all of the following are verified:
- CP owner is destination at generation N+1;
- source is fenced/revoked at generation N for writes, jobs, files, exports and notifications;
- destination projection is active only at N+1;
- destination staging has been promoted and its integrity receipt is durable;
- required outbox/inbox events are acknowledged/deduplicated;
- source and destination projections reconcile with CP;
- transfer audit and excluded-data evidence are complete;
- no unresolved critical reconciliation discrepancy exists.

If any predicate is not met, state remains `projections_finalizing` or `manual_intervention_post_switch`, not `completed`.

## 9. Required observability and operations

Metrics: outbox age/depth, retry count, dead-letter count, inbox lag, stale/future generation rejects, freeze duration, drain work, snapshot duration/size, staging validation failures, projection lag, reconciliation discrepancy count and manual-intervention age.

Alerts must cover: source write accepted while frozen/stale, destination write before N+1 activation, ownership event loss/poisoning, unexpected future generation, conflicting owner projections, snapshot checksum mismatch, authorization/approval revocation during cutover and repeated KMS/storage failures.

Operational thresholds, retention, SLOs, backup/restore and on-call ownership remain explicit deployment decisions and must be measured before pilot. No numeric thresholds are invented.

## 10. Required tests

- source freeze rejects every write surface (API, DB, jobs, files, imports, exports and notifications);
- in-flight transaction barrier prevents post-snapshot writes;
- duplicate freeze/unfreeze commands are idempotent and case/token-bound;
- unfreeze after ownership switch is denied;
- snapshot is consistent at the barrier watermark and excludes prohibited categories;
- staging data is invisible to normal users and tenant-scoped;
- corrupt checksum, schema mismatch, missing FK and unauthorized attachment fail closed;
- CP switch and outbox insert are atomic under failure injection;
- dispatcher crash before send, after send/before ack and during lease expiry retries the same event ID safely;
- duplicate/out-of-order/stale/future events are deduplicated/rejected/quarantined as specified;
- inbox insert + projection update is atomic;
- process crash at every Saga checkpoint resumes from durable state;
- CP switch ambiguity is resolved by idempotency query, not a second logical switch;
- after switch, source write/job/file/export/notification access is denied even when destination projection is delayed;
- destination activates only at generation N+1;
- no automatic reverse owner switch exists;
- dead-letter/re-drive/manual intervention is auditable;
- reconciliation detects and repairs projection drift without changing CP owner;
- load, outage, restore and failover tests validate operationally chosen thresholds.

These are acceptance specifications until executable service, database, chaos and environment tests exist and pass.

## 11. Gate impact

This contract makes the cross-database protocol reviewable but does not implement it. Current SQL drafts cover only the Control Plane ownership switch and local synthetic assertions; they do not prove source freeze/drain, snapshot consistency, destination staging, outbox/inbox delivery or recovery across separate databases. Distributed transfer remains a HIGH finding and Phase 2 remains **NOT READY** until implementation boundaries, schemas, test contracts and operational decisions are reconciled and independently reviewed.
