# Student Transfer Across Isolated Workspaces — Control-Plane Decision

**Status:** ACCEPTED ARCHITECTURAL DIRECTION — Product Owner confirmation, 2026-11-06  
**Decision identifier:** Pending collision-free reconciliation with PR #8 and PR #9 decision numbering  
**Scope:** Architecture and domain constraints only. This document does not approve schema, migrations, code, runtime controls, tests, phase progression, or real-data use.

## 1. Context

The approved isolation direction (D-020 Alt-5) gives each Workspace its own database and runtime credential inside an isolation cell. The product also requires a student to have at most one active Workspace enrollment at a time and permits a formal transfer between Workspaces only after cumulative approvals and destination acceptance.

A normal PostgreSQL transaction cannot atomically commit changes in two independent Workspace databases. Treating two local enrollment updates as one atomic transaction would therefore be an incorrect guarantee.

## 2. Product Owner decision

The Product Owner accepted **Option A: a central control-plane ownership registry plus a durable, recoverable transfer workflow (Saga)**.

The central registry is the authoritative source for the student's current Workspace ownership and enrollment generation. Workspace databases may hold local operational records and projections, but they are not independently authoritative for cross-Workspace ownership.

This decision resolves the architectural direction only. Detailed topology, availability objectives, schema, APIs, migration strategy, implementation, and acceptance tests remain subject to design and independent review.

## 3. Non-negotiable invariants

1. A student has at most one authoritative active Workspace owner at any instant.
2. Only the control-plane registry may authorize which Workspace currently owns the student's active enrollment.
3. Workspace-local enrollment rows are projections/operational records; a local row alone never grants access.
4. Authorization must validate the authenticated actor's Workspace membership, role, resource relationship, scoped permission, current registry owner, and current ownership generation.
5. If the registry cannot be reached or its answer cannot be validated, access to student data and ownership-sensitive writes fail closed. A stale local cache or local enrollment row is not a fallback authorization source.
6. A transfer must not expose the student to both source and destination Workspaces as active at the same time.
7. Every transfer stage and approval is attributable, timestamped, auditable, and protected against replay and duplicate execution.
8. The workflow must be durable and recoverable after process, network, or cell failures. No transfer may be silently abandoned in an ambiguous state.
9. The prior counselor's authenticated fee-receipt confirmation, valid parent/legal-guardian consent, and destination Workspace acceptance are cumulative prerequisites. A request initiator cannot replace any required approval.
10. Educational history is preserved according to policy. Prior counselor-private notes and confidential communications are not automatically copied to the destination.

## 4. Control-plane registry responsibilities

The registry is the platform-level authority for at least:

- Stable platform student identity/reference.
- Current owning Workspace identifier.
- Current ownership/enrollment generation (monotonically increasing fencing value).
- Current ownership lifecycle state, including active, transfer-pending/frozen, and non-active states as needed.
- Transfer workflow identity and durable status.
- Idempotency keys and deduplication outcome for ownership-changing commands.
- References to approval evidence and audit events, without copying unnecessary sensitive content.

The registry must not become a general-purpose copy of all educational records. Data minimization applies. The detailed split between global identity attributes and Workspace-owned student profile data requires privacy and domain-model review.

## 5. Transfer workflow — required logical stages

The following is a required logical sequence, not a final API or database schema:

1. **Request:** An eligible parent/guardian, current counselor, or destination Workspace may initiate a request. Authenticate the initiator and validate the relevant relationship/permission. Create a durable transfer case with an idempotency key.
2. **Approval collection:** Record and verify the required parent/legal-guardian consent, the previous counselor's authenticated fee-receipt confirmation, and destination Workspace acceptance. These approvals are separate, cumulative, scoped to this transfer, revocable only under explicitly designed rules, and auditable.
3. **Preflight:** Validate source ownership and generation, destination Workspace eligibility/status, destination counselor acceptance and capacity, applicable contract/credit requirements, and data-transfer policy.
4. **Destination staging:** Transfer only approved data into an inaccessible staging area in the destination cell. Validate integrity, schema compatibility, record counts/checksums where appropriate, references, attachments, and policy-based exclusions. Staging data must not grant destination access.
5. **Consistency barrier:** Establish a controlled cutover boundary. Prevent further source mutations relevant to the transfer, or use a proven snapshot-plus-change-capture/final-delta mechanism. The exact mechanism must be selected and tested before implementation. The workflow must not switch ownership while destination data is knowingly stale or incomplete.
6. **Atomic ownership switch:** In one transaction in the control-plane database, compare-and-swap the expected source Workspace and ownership generation; verify all prerequisites; mark the transfer committed; set the destination Workspace as authoritative owner; and increment the ownership generation. This is the single authoritative cutover point.
7. **Projection finalization:** Reconcile source and destination local enrollment projections, activate the destination projection, close the source projection, release applicable locks, and record completion. Projection updates may be asynchronous, but authorization continues to follow the registry and generation.
8. **Completion/recovery:** A durable worker retries idempotently until all projections and cleanup tasks converge. The transfer remains visibly pending/recovering until reconciliation is complete; it must never be represented as fully complete based only on the central switch if required finalization is outstanding.

## 6. Failure handling and consistency

- **Before the ownership switch:** The source remains authoritative unless the workflow has explicitly entered a safe freeze state. On cancellation or unrecoverable pre-cutover failure, staged destination data is quarantined/deleted under retention policy and the source is safely unfrozen.
- **At the ownership switch:** Use one control-plane database transaction with optimistic generation checking and appropriate row-level serialization/locking. The transaction must be idempotent and must reject stale source generation, duplicate active ownership, missing approvals, or an invalid transfer state.
- **After the ownership switch:** Do not automatically switch ownership back as a generic compensation. The destination is authoritative. Recovery should proceed forward by repairing projections and finalization. Any reversal is a new, separately authorized transfer with its own approvals and audit trail.
- **Fencing:** Every ownership-sensitive request and background job must carry or resolve the current ownership generation. Stale source-cell workers and delayed messages must be rejected after the generation changes.
- **Retries:** All commands and consumers must be idempotent. Use a durable outbox/inbox or equivalent reliable delivery mechanism; do not rely on in-memory queues or best-effort events.
- **Concurrency:** Concurrent transfers, activation, archival, reassignment, and ownership changes must serialize against the same authoritative student ownership record.
- **Observability:** Provide operational visibility into stuck transfers, retries, failed validation, projection drift, and manual intervention. Manual repair must be privileged, reasoned, and audited.

## 7. Authorization and availability behavior

The control-plane registry is security-critical. Its availability, integrity, backup, recovery, and administrative access must be designed as core security controls.

For student-data access, a Workspace database may serve a request only after the platform has validated that the requested Workspace is the current owner and that the request's ownership generation is current. If this validation cannot be completed, deny access rather than relying on stale ownership data.

The design must explicitly analyze the registry outage blast radius, high availability, failover consistency, split-brain prevention, recovery point/objective, backup independence, and privileged administration. These values and mechanisms are not decided by this ADR.

## 8. Data-transfer and privacy boundaries

- Preserve required educational records and their provenance/history according to the approved retention and transfer policy.
- Do not automatically transfer prior counselor-private notes or confidential communications.
- Do not treat a phone number, client-supplied identifier, or a local database row as identity or transfer authority.
- Transfer attachments only after authorization, malware/security checks, and policy validation.
- Record the source, destination, actor, approval evidence references, timestamps, generation before/after, and outcome.
- Define how legal guardian authority, student age/rights, consent expiry/revocation, and jurisdictional requirements affect transfer before implementation.

## 9. Required tests before implementation can be accepted

The design and later implementation must include, at minimum:

- Two concurrent transfer requests for the same student: only one can commit.
- A stale ownership generation cannot read or mutate student data.
- Registry unavailable, timeout, inconsistent failover, or unknown result: access fails closed.
- Source and destination local projections disagree with registry: authorization follows registry; repair is observable and recoverable.
- Crash at every workflow stage, including immediately before and after the ownership switch.
- Duplicate requests, duplicate messages, retries, out-of-order messages, and idempotency-key payload mismatch.
- Destination staging failure, checksum/reference mismatch, insufficient capacity, or invalid counselor acceptance.
- Missing, revoked, expired, or incorrectly scoped parent consent; missing previous counselor confirmation; missing destination acceptance.
- Source write racing with snapshot/cutover; no acknowledged source write is silently lost.
- Delayed source-cell background job after ownership generation changes.
- Attempted access by the former counselor, another counselor in the source Workspace, an unrelated destination member, and a Platform Admin without explicit authority.
- Private notes and confidential communications excluded from transfer by default.
- Audit completeness and recovery of stuck transfers without duplicate activation or credit debit.

These are acceptance requirements, not evidence that tests currently exist or have passed.

## 10. Decisions still open

The Product Owner's approval does not settle the following:

- Registry physical topology, database isolation, hosting location, HA/failover and split-brain prevention.
- Registry service ownership, runtime identity, key/secrets management, and privileged operational access.
- Exact student global identity versus Workspace-owned profile attribute split.
- Exact snapshot/final-delta or write-freeze consistency mechanism.
- Transfer data mapping, schema evolution and compatibility policy across Workspace cells.
- Exact lifecycle statuses, timeout/expiry rules, cancellation boundaries, manual intervention and reversal policy.
- Registry backup/restore, RPO/RTO, retention, disaster recovery and restore-drill requirements.
- API contracts, table names, constraints, indexes, migrations, implementation and performance/capacity evidence.
- Whether a Workspace cell may continue serving already-open sessions during a registry outage; default authorization remains fail-closed unless a separately reviewed bounded protocol is approved.

Do not silently close related open questions such as hosting/cell topology, retention, guardian legal evidence, or GitHub operational access.

## 11. Required repository follow-up

1. Reconcile this decision into DECISION_LOG.md using a collision-free identifier after PR #8 D-025–D-027 and PR #9's 35 decisions are reconciled.
2. Update OPEN_QUESTIONS.md to distinguish the now-decided transfer architecture direction from the still-open operational/design parameters.
3. Reconcile the Phase 2 domain model and DDL with Workspace ownership and the control-plane authority model; do not treat the existing tenants/counselors schema as compliant without review.
4. Define the registry contract, transfer state machine, authorization checks, failure semantics and acceptance tests before finalizing transfer-related DDL.
5. Independently review the complete diff and test evidence. Do not merge by assertion.
6. Keep Phase 2 Gate **NOT READY** until all required blockers are resolved and independently verified. No real student/customer data is authorized.

## 12. Approval boundary

This ADR records the Product Owner's acceptance of Option A as the architectural direction. It does not constitute implementation approval, schema approval, security certification, test acceptance, Phase 2 approval, production approval, or permission to use real student/customer data.
