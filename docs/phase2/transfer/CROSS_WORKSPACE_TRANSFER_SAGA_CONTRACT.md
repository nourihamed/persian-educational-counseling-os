# Cross-Workspace Transfer Saga & Durable Delivery Contract

**Status:** DRAFT / NOT APPROVED. Phase 2 architecture contract only. Synthetic data only (D-014). No production distributed workflow or cross-database atomicity is claimed.

## 1. Scope and non-goals

This contract refines `TRANSFER_WORKFLOW_CONTRACT.md` into service/database boundaries for a transfer spanning the Control Plane and two separate Workspace databases. It defines durable commands, events, inbox/outbox semantics, source freeze/drain, destination staging, ownership cutover and forward recovery.

There is no distributed transaction across the three databases. The Control Plane is the sole authority for owner and ownership generation. Workspace databases hold projections and staged educational data only.

## 2. Non-negotiable invariants

1. At any instant the Control Plane has exactly one authoritative owner and generation for a student.
2. Before the Control Plane ownership switch commits, source remains authoritative and destination staging is inaccessible to normal actors.
3. After the switch commits, destination is authoritative at generation N+1; source generation N is permanently stale and all source mutations/access paths fail closed.
4. No operation may claim global atomicity across databases. Each local transaction is atomic; delivery is at-least-once with deduplication and reconciliation.
5. Every command/event is scoped to one immutable transfer case, student, source/destination Workspace and expected generation.
6. No user-supplied tenant, generation, database target, credential or routing hint is trusted.
7. After switch, recovery is forward-only. Reversal requires a new transfer case and all cumulative approvals.
8. Payloads carry identifiers, schema/manifest versions, checksums and opaque references only; no raw mobile, OTP, secrets, credentials, private counselor notes or confidential communications.
9. Every handler is idempotent and rejects stale or impossible generations.
10. Control Plane unavailability, ambiguous ownership, unknown delivery state or failed authorization means deny access/mutation.

## 3. Durable command and event envelope

Every command/event must include:

- immutable `event_id` / `command_id`, `case_id`, `student_id`;
- source and destination Workspace IDs;
- expected ownership generation and, where relevant, resulting generation;
- event type and schema version;
- causation/correlation ID and idempotency key;
- created-at timestamp (UTC) and producer identity;
- opaque manifest/snapshot/freeze/validation references and SHA-256 hashes where applicable;
- bounded retry metadata kept outside the immutable business payload.

Consumers must reject an event whose case/student/Workspace tuple does not match the durable transfer case. A duplicate event ID with the same canonical payload is a no-op; same ID with a different payload is a security/integrity incident. Never place personal data or database credentials in event payloads.

## 4. Control Plane outbox

The business state transition and outbox insertion occur in the same Control Plane transaction. An outbox publisher:

1. claims pending rows using a concurrency-safe lease/claim protocol (e.g. `FOR UPDATE SKIP LOCKED`), with owner, lease expiry and attempt metadata;
2. publishes outside the DB transaction;
3. marks delivery only after broker acknowledgement;
4. retries with bounded exponential backoff and jitter, with maximum attempts / dead-letter escalation set by an operational policy (numeric values remain open);
5. never deletes the immutable business event; delivery/attempt metadata is separate mutable operational state;
6. detects expired leases and safely reclaims them;
7. emits metrics and alerts for age, attempts, poison events and dead-letter backlog.

The publisher may deliver more than once. It must never mark published before broker acknowledgement. An outbox event is not proof that a Workspace projection was applied.

## 5. Workspace inbox and handler transaction

Each Workspace DB maintains an inbox uniqueness constraint on immutable event ID and a processing result keyed by event ID + canonical payload hash.

For each event, the consumer must in one local transaction:

1. validate signature/transport identity and event schema;
2. insert inbox receipt; duplicate same-payload receipt returns prior result; same ID/different hash is rejected and alerted;
3. verify destination/source Workspace ID equals the local DB's immutable identity;
4. consult the Control Plane (or a cryptographically verifiable, bounded-freshness ownership assertion) and verify current owner + generation; inability to validate fails closed;
5. validate transfer case, allowed state and manifest version;
6. apply the projection change idempotently;
7. record applied generation and result; commit inbox receipt and projection together.

A consumer must not acknowledge successful application before its local transaction commits. Out-of-order events are parked/retried or rejected by explicit state policy; they must not regress a projection. Future-generation events are not accepted unless the matching cutover event and ownership assertion are verified.

## 6. Source freeze and write-drain protocol

Source freeze is a source-Workspace-local authorization/mutation barrier, not a UI flag and not merely a Control Plane case state.

- The freeze command is authenticated, signed, case-bound and generation-bound.
- The source Workspace records a durable freeze record with unique token, case ID, student ID, generation N, initiating service identity and timestamp.
- Every write path checks the freeze barrier inside the same transaction boundary as the mutation, including API writes, background jobs, imports, bulk actions, file metadata changes and derived-data writers.
- Freeze blocks new writes and starts a drain protocol for in-flight transactions. The final snapshot cannot begin until the source confirms the barrier and all pre-barrier writes are committed or safely aborted.
- Freeze is idempotent for the same case/token; a different open case/token is rejected.
- Unfreeze is a separate signed command, permitted only before ownership switch and only after the Control Plane confirms the case is still pre-switch. It is itself audited and idempotent.
- Once ownership switch has committed, unfreeze is forbidden. Source remains fenced at generation N.

The exact write-path inventory, barrier implementation, drain timeout and force-abort policy are implementation/operations acceptance items; no numeric threshold is invented here.

## 7. Final snapshot and destination staging

- Snapshot is taken only after a confirmed write barrier/drain checkpoint.
- Manifest includes version, case/student, source Workspace, generation N, object types, record counts, canonical checksums, attachment references and explicit excluded categories.
- Snapshot integrity metadata is immutable and signed or otherwise protected by a trusted snapshot service.
- Destination import occurs into isolated staging namespace/tables inaccessible to application users, counselors, parents, exports and notifications.
- Staging importer is idempotent by case + manifest hash + item key. Duplicate same payload is a no-op; mismatch quarantines the case.
- Validation checks schema compatibility, counts, checksums, foreign keys, ownership references, attachment availability/authorization, exclusions and destination eligibility/capacity.
- A successful validation yields a short-lived, case-bound attestation; the Control Plane verifies it again at cutover.
- No source-private counselor notes, confidential communications, secrets, credentials or excluded records may enter the transfer manifest.

## 8. Cutover and forward recovery

Immediately before switch, the orchestrator revalidates: all three approvals (per the approval identity contract), current authority, source freeze token and drain evidence, final snapshot hash, destination validation attestation, destination status/capacity/entitlement, source owner and expected generation.

The Control Plane transaction then locks the case and ownership row, validates approvals and evidence, compare-and-swaps owner and generation N→N+1, updates the global claim, appends ownership history and writes a `ownership_switched` outbox event. It does not contact either Workspace database inside this transaction.

After switch:
- destination applies/activates only generation N+1;
- source remains frozen and its generation N is rejected for writes, reads requiring current ownership, jobs, files, exports and notifications;
- projection finalization retries forward;
- if destination projection is unavailable, access is denied rather than falling back to source;
- no cancellation, unfreeze or automatic owner rollback is permitted.

## 9. Recovery and reconciliation

A durable orchestrator records each step and checkpoint. Recovery reads Control Plane authority first; it never infers ownership from a Workspace-local row.

- Pre-switch failure: source remains owner. Resume from a verified checkpoint or unfreeze source after confirming no switch occurred and staging is quarantined.
- Ambiguous switch result: query Control Plane by case/idempotency key and ownership generation. Do not repeat a new switch command blindly.
- Post-switch delivery failure: destination remains owner; retry outbox/inbox and forward projection finalization.
- Duplicate or poison event: deduplicate by event ID/hash; quarantine mismatched payload and alert.
- Reconciliation compares Control Plane owner/generation with source/destination projections, freeze records, applied inbox generations and outbox state. It repairs only projections and delivery state, never authoritative ownership.
- Manual intervention is required when evidence conflicts, hashes mismatch, ownership cannot be established, or configured retry/age thresholds are exceeded. Numeric thresholds and SLA remain operational decisions.

## 10. Required acceptance tests

- Outbox row is committed atomically with each relevant Control Plane state change.
- Publisher crash before publish, after publish/before mark, expired lease and duplicate publish all recover safely.
- Two publishers cannot corrupt delivery state; concurrent claim uses lease fencing.
- Inbox duplicate same ID/same hash is idempotent; same ID/different hash is rejected and alerted.
- Inbox receipt and projection mutation commit/rollback together.
- Wrong Workspace, wrong case, wrong student, stale generation, future generation and invalid signature reject.
- Every source write path is blocked after freeze, including jobs, imports, bulk changes, files and derived data.
- In-flight writes drain before snapshot; failure to drain prevents snapshot and switch.
- Snapshot manifest mismatch, missing attachment, excluded data or checksum mismatch prevents switch.
- Destination staging cannot be read by normal roles before ownership switch.
- Concurrent freeze/unfreeze/switch operations serialize safely and are case/generation fenced.
- Failure injection at every saga step yields the crash matrix's required recovery.
- After switch, source writes and protected reads reject even if outbox delivery is delayed.
- Destination outage after switch causes fail-closed behavior and forward retries, never source fallback.
- Reconciliation cannot modify Control Plane ownership.
- Revocation and ownership switch serialize as specified by the approval identity contract.
- Observability contains correlation IDs and reason codes but no contact plaintext, secrets or sensitive payload.

All tests are specifications until implemented and executed in isolated synthetic databases/services.

## 11. Open operational parameters

No numeric values are selected here for outbox lease duration, retry count/backoff, dead-letter age, freeze/drain timeout, snapshot retention, staging TTL, reconciliation interval, manual-intervention SLA, alert thresholds, RPO/RTO or backup retention. These require measured target-environment evidence and Product Owner/security approval where they affect business policy.

## 12. Gate impact

This contract establishes design boundaries only. Durable publisher/consumer, source freeze controller, staging importer, saga orchestrator, reconciliation worker and failure-injection tests remain unimplemented. Phase 2 remains **NOT READY**; D-014 synthetic-only restriction remains in force.
