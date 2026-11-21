# Phase 2 Data Retention, Legal Hold & Erasure Contract

**Status:** DRAFT / NOT APPROVED. Implements the design direction of OQ-F2 Option A only. Not legal advice. No numeric retention duration is approved. D-014 synthetic-only restriction applies.

## 1. Purpose and policy principles

Retention is category-based and policy-versioned. The system must not apply one global retention period to all records. Each policy version defines data category, purpose, trigger event, retention basis, responsible role, disposition, legal-hold behavior, backup behavior and approval evidence.

This contract defines technical capabilities and lifecycle states; it does not select legal/tax periods or decide whether a record must be retained. Those require Product Owner approval after qualified Iran legal, tax and privacy review.

## 2. Data categories and ownership

The canonical category inventory is maintained in `docs/phase1/DATA_RETENTION_SCHEDULE_DRAFT.md`:
- R1 student profile and educational records;
- R2 accounts and authentication;
- R3 security/audit records;
- R4 orders, invoices, payment references and financial ledger;
- R5 notifications and delivery metadata;
- R6 files and exports;
- R7 backups and snapshots;
- R8 operational logs;
- R9 Workspace/cell roles, credentials metadata and routing lifecycle.

A data item must be tagged with a category and owning authority at creation. Derived data inherits the strictest applicable category/retention rule of its source unless a separately approved anonymization policy applies. Backups, caches, search indexes, exports, notification queues and analytics are included in the data inventory; deletion from the primary row alone is not complete disposition.

## 3. Versioned policy model

The domain model must support:
- immutable `retention_policy_versions` with policy version, effective-from, approval reference, jurisdiction, category and policy owner;
- immutable category rules with purpose, trigger, duration reference (nullable only while explicitly NEEDS-DECISION), disposition action and backup-expiry behavior;
- data/record category tagging or a reliable entity-to-category registry;
- lifecycle events such as relationship ended, account disabled, Workspace suspended/closed, consent revoked, legal hold placed/released and deletion authorized;
- a durable disposition request with idempotency key, policy version, scope, requester/approver, reason code and execution status;
- append-only disposition audit events for every system and storage target;
- legal holds that are scoped to exact records/categories and block all destructive disposition paths while active.

No default duration may be inferred from missing values. A policy with an unresolved duration must be marked blocked for destructive deletion; it must not mean immediate deletion or indefinite retention by accident.

## 4. Disposition workflow

1. Detect a lifecycle trigger and create a disposition evaluation, not an immediate delete.
2. Resolve the applicable approved policy version and data category for every target record and derived copy.
3. Check legal holds, disputes, safeguarding/child-protection restrictions, financial obligations, active transfer cases and unresolved security incidents.
4. Determine eligible actions: restrict access, disable account/session, archive, pseudonymize, anonymize, delete primary record, delete object-store object, expire export/cache/index, or schedule backup expiry. The action must be category-specific and policy-authorized.
5. Require independent approval for irreversible actions according to the approved authority matrix. The requester cannot approve their own high-impact deletion.
6. Execute through a durable, idempotent job with immutable scope snapshot and generation fencing. Jobs must be Workspace-scoped and must not accept caller-controlled Workspace routing.
7. Record per-target success/failure and retry safely. Partial completion is visible and reconciled; it is never reported as full deletion.
8. Verify downstream copies, file objects, exports, search/cache, notifications and replicas are handled.
9. Record backup residuals and expiry schedule. A restore must re-apply valid post-backup suspension, legal-hold and deletion/suppression events before the restored dataset becomes available.
10. Close only after independent verification and audit evidence are complete.

## 5. Legal hold

- Legal holds are explicit, case/reference-bound, scoped and auditable.
- Placement immediately blocks deletion/anonymization for covered records and all copies under system control.
- Release requires an authorized actor and evidence reference; a hold cannot be released by the same unrestricted deletion job that it blocks.
- Conflicting or ambiguous holds fail closed.
- Hold state must be reconciled after restore before any recovered data is served.
- The system must preserve who placed/released the hold, when, scope, authority reference and reason code; avoid storing unnecessary legal document contents.

## 6. Access restriction versus erasure

Suspension/offboarding and deletion are distinct:
- Disable credentials/sessions and revoke access promptly when required by the lifecycle policy.
- Preserve ownership, audit, financial and legal-hold metadata as required by their own category policies.
- Archival is not anonymization; pseudonymization is not erasure.
- Anonymized analytics are permitted only if re-identification risk and purpose are reviewed and the transformation is irreversible under the approved standard.
- No automatic deletion of Workspace PostgreSQL roles is permitted; D-017's lifecycle checklist and Q-020 govern disable/revoke/session-termination/dependency checks before role removal.

## 7. Backup, replicas and derived copies

- A primary-record deletion does not imply immediate deletion from immutable backups.
- Backup retention/expiry is separately policy-versioned and must disclose residual copies until expiry.
- Restore must apply a durable suppression/disposition ledger so a record deleted or restricted after the backup timestamp is not silently resurrected.
- Replica lag and point-in-time recovery must be included in disposition verification.
- Object storage, export archives, temporary files, caches, search indexes, analytics, event payloads and dead-letter queues must be included in the inventory.
- Cryptographic erasure may be used only when key scope, shared-object dependencies, backups, legal holds and recovery behavior are explicitly proven; it is not assumed to be available for all categories.

## 8. Required tests

- Policy version is immutable and effective-date selection is deterministic.
- Unresolved duration blocks destructive disposition.
- Legal hold blocks delete/anonymize across primary, file, export, cache and restore paths.
- Hold release requires authorized evidence and is audited.
- Repeated disposition job is idempotent; same key/different payload rejects.
- Partial failure is retried/reconciled and never marked complete prematurely.
- Workspace-scoped jobs cannot affect another Workspace.
- Archived/ended records follow the correct category policy and do not disappear due to unrelated account deletion.
- Restore reapplies post-backup suppression, suspension and legal-hold events before service.
- Backup expiry and object deletion are independently verified.
- Role/credential deletion follows D-017's disable, revoke, terminate sessions/pools, dependency-check, retention and approval checklist.
- Audit records are immutable and contain no secrets or unnecessary personal content.

All tests are specifications until executable jobs and representative restore/storage tests are implemented and run.

## 9. Decisions and evidence still required

- Numeric periods for R1–R8, backup retention and financial/accounting records.
- Qualified legal/tax/privacy reviewer and named operational data owners.
- Approver authority for irreversible deletion and Workspace role removal.
- Exact anonymization standard and analytics use cases.
- Legal hold categories, triggers, release authority and dispute handling.
- Backup expiry, immutable retention and restore suppression mechanics on the selected target.
- Whether any category requires a longer/shorter period due to Iran-specific rules; no assumption is made here.

These remain Product Owner/legal decisions. The existing retention schedule stays NEEDS-DECISION / LEGAL-REVIEW until formally approved.

## 10. Gate impact

This contract makes the technical policy requirements explicit but does not approve a retention period, implement deletion, or establish legal compliance. Phase 2 remains **NOT READY** until the schema and workflow are reconciled and executable tests exist; pre-pilot retention/legal approval remains a separate gate. D-014 remains in force.
