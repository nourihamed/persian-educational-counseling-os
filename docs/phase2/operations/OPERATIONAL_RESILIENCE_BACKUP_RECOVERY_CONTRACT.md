# Phase 2 Operational Resilience, Backup & Recovery Contract

**Status:** DRAFT / NOT APPROVED. Architecture and acceptance contract only. No hosting provider, production topology, RPO/RTO, retention duration or failover mode is selected here. D-014 synthetic-only restriction applies.

## 1. Scope and approved direction

This contract translates OQ-D Option A and D-023 into provider-neutral design requirements for Control Plane and Workspace data services.

- Control Plane has an independently administered primary/replica topology and independently controlled encrypted backups.
- Workspace databases are deployed within the approved Alt-5 isolation-cell architecture: separate cell host/VM, network boundary and PostgreSQL cluster/instance; each Workspace has a separate database and runtime credential.
- Critical backups and recovery control plane must have an independent administrative/control boundary from ordinary production operations (D-023 Level 4 target).
- The target is an architecture requirement, not evidence that any provider or deployment currently satisfies it.
- OQ-D does not settle replication mode, RPO/RTO, backup retention or failover automation. Those values remain open.

## 2. Failure domains and trust boundaries

Document and test separate failure domains for:
1. Control Plane primary database and its host/account/network.
2. Control Plane replica and its host/account/network.
3. Independent backup repository, backup administration and recovery credentials.
4. Each Workspace isolation cell and its PostgreSQL cluster.
5. Identity/KMS/HSM key services and key-recovery authority.
6. Application/API, worker, migration and break-glass identities.
7. DNS/service discovery, network policy and secrets distribution.

A replica is not an independent backup. A second database in the same host/account/root domain is not independent failure protection. A backup encrypted by keys controlled only by the compromised production account is not independent recovery.

The final hosting design must identify which failures are tolerated and which remain global residual risks (provider-global compromise, all-credentials compromise, KMS/control-plane compromise).

## 3. Replication and failover safety

Before selecting synchronous/asynchronous replication or automatic/manual failover, define the business-approved data-loss and recovery objectives.

Required safety properties:
- At most one writable primary per database authority at any time.
- Promotion requires positive fencing/STONITH or an equivalent independently verified mechanism that prevents the old primary from accepting writes.
- A replica's replay/consistency position is verified before promotion against the approved RPO policy.
- Failover decision, operator identity, evidence, timeline, replication lag and promoted timeline are audited.
- Client pools, workers and background jobs must be drained/revoked or redirected only after primary fencing and target verification.
- Old-primary rejoin is never automatic; it must be quarantined, reconciled and rebuilt/reseeded under a documented runbook.
- Split-brain detection and response are tested, not assumed from provider defaults.
- If ownership/primary status is ambiguous, services fail closed rather than writing to both targets.

No automatic failover is approved until fencing, replication consistency, credential revocation, pool eviction and split-brain drills pass in a representative environment.

## 4. Backup and restore requirements

- Backups are encrypted in transit and at rest; encryption keys and recovery authorization are outside ordinary production-account administration.
- Backup catalog, integrity metadata, database identity, schema version, timeline/LSN, capture time and checksum are protected against unauthorized alteration.
- Retention is category-based and versioned; numeric retention periods remain open and must be approved. Legal hold must override deletion.
- Backup deletion and expiry are auditable and protected against ordinary production operators.
- Restore must preserve Workspace suspension/offboarding/ownership state from authoritative records; restoring an old database must never silently reactivate an ended Workspace or stale student generation.
- Control Plane restore must reconcile owner/generation and identity-claim uniqueness before accepting writes.
- Workspace restore must reconcile the Workspace identity, current Control Plane owner/generation, membership revocations, file references, legal holds and event offsets before serving data.
- Recovery must address encrypted file objects and their key versions; restoring DB rows without usable object/key recovery is not a complete restore.
- Point-in-time recovery, logical/physical backup consistency and cross-service dependency ordering must be documented.

## 5. Restore isolation and recovery authorization

- Restore drills run in an isolated recovery environment with no public ingress and no production notification/payment side effects.
- Recovery credentials are distinct from normal application, migration and production administrator credentials.
- A restore operator cannot unilaterally approve both data restoration and deletion/retention policy exceptions.
- Restored databases remain read-only/quarantined until identity, ownership, generation, schema, integrity and legal-hold reconciliation passes.
- Recovered Workspace runtime credentials are rotated/rebound before the database returns to service.
- Recovery actions, approvals, data scope, source backup, target identity and verification results are audited.
- Real student data remains prohibited in development/testing; synthetic fixtures are used until the D-014 gate is explicitly passed.

## 6. Capacity, load and connection isolation

The provisional ceiling of at most two Workspaces per cell and at most ten Workspaces in the initial pilot is not capacity evidence or pilot authorization.

Before pilot:
- Measure per-cell CPU, memory, storage IOPS, network, PostgreSQL connections, replication lag, backup throughput and restore throughput under representative synthetic load.
- Measure connection-pool multiplication across API processes, workers, exporters, migrations and administrative tools. D-017's direct connection / size-1 per-tenant-per-process pilot rule remains the baseline; changing pooling mode or pool size requires a separate decision and compatibility tests.
- Test noisy-neighbor behavior between Workspaces in the same cell and confirm database/credential/network boundaries.
- Test cell saturation and safe placement rejection; do not overcommit by assuming average usage.
- Measure Control Plane primary/replica capacity and global identity/ownership hot-key contention.
- Define headroom, alert thresholds, scaling triggers and admission controls from measured data, not estimates.

## 7. Required acceptance and failure-injection tests

| ID | Test | Status |
|---|---|---|
| OPS-HA-01 | Primary failure with verified fencing; no dual writer | NOT RUN |
| OPS-HA-02 | Replica promotion verifies replay position against approved RPO | NOT RUN |
| OPS-HA-03 | Old primary cannot accept writes after promotion; rejoin is quarantined | NOT RUN |
| OPS-HA-04 | Split-brain / network partition drill; fail-closed behavior | NOT RUN |
| OPS-HA-05 | Pool/worker credential revocation and eviction after failover | NOT RUN |
| OPS-BACKUP-01 | Independent backup administration/key custody boundary | NOT RUN |
| OPS-BACKUP-02 | Backup tamper/integrity verification and immutable audit | NOT RUN |
| OPS-RESTORE-01 | Control Plane restore with owner/generation/claim reconciliation | NOT RUN |
| OPS-RESTORE-02 | Workspace restore with ownership, membership, legal hold and inbox/outbox reconciliation | NOT RUN |
| OPS-RESTORE-03 | File-object and encryption-key recovery as a complete dataset | NOT RUN |
| OPS-RESTORE-04 | Restore quarantine/read-only and credential rotation before service | NOT RUN |
| OPS-CAP-01 | Synthetic load, noisy-neighbor and cell saturation measurements | NOT RUN |
| OPS-CAP-02 | Connection multiplication, pool isolation and exhaustion behavior | NOT RUN |
| OPS-CAP-03 | Backup/restore throughput and recovery-time measurements | NOT RUN |

Each drill must retain reproducible logs, exact topology/configuration, data fixture version, observed RPO/RTO, operator approvals and independent review. A successful CI SQL test is not a substitute for environment-level evidence.

## 8. Decisions still required

The following must not be guessed or silently selected:
- numeric RPO and RTO per Control Plane and Workspace data class;
- replication mode and acceptable lag/data-loss semantics;
- automatic versus manual promotion and required quorum/fencing authority;
- backup frequency, retention periods, immutable retention/lock policy and legal-hold interaction;
- restore priority/dependency order and recovery operator separation;
- target hosting/provider/account topology and measured cost/capacity;
- alert thresholds and manual-intervention SLA.

These should be presented as explicit Product Owner/security decisions with measured options before production hosting or pilot authorization.

## 9. Gate impact

This contract documents architecture and acceptance criteria only. No provider, replica, backup service, KMS/HSM, failover controller, restore drill or capacity measurement is implemented or verified. Phase 2 design can specify these boundaries, but operational acceptance remains a later environment gate.

**Phase 2 Gate: NOT READY.** D-014 remains in force; synthetic data only.
