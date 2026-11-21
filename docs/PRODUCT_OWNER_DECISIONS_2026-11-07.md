# Product Owner Decision Register — 2026-11-07

---

## Product Owner decision consolidation — 2026-11-07

This section records Product Owner decisions confirmed in the 2026-11-05 to 2026-11-07 architecture decision sessions and reconciles them with the existing open PRs. It is a decision record, not evidence of implementation, test execution, security verification, phase approval, or real-data authorization.

### Workspace-centric product and domain decisions (35 decisions; source: PR #9)

The following 35 Product Owner choices are accepted at product/architecture-policy level. Their exact detailed rationale and source wording remain in PR #9 and its decision register; this index is not a substitute for the detailed crosswalk or technical contracts.

1. Student lifecycle: controlled archival; preserve history, restrict access, and apply legal/policy deletion; transfers remain separate.
2. Parent access: per-child and per-permission; counselor-private notes and confidential communications hidden by default; law and student rights prevail.
3. Capacity: independent Workspace/Counselor/Branch capacity; archived students do not consume active capacity; capacity is separate from credits; checks are atomic.
4. Counselor assignment: one active responsible counselor and at most one active primary branch; counselors may serve multiple branches; changes are formal/audited; collaboration requires scoped permission.
5. Organization governance: one primary owner and multiple managers with separated permissions; ownership, management, membership, and permissions are distinct.
6. Identity: stable Platform User ID; mobile is changeable login/contact data; changes require re-authentication, verification, and audit.
7. Enrollment lifecycle: explicit state machine (requested, awaiting consent/approval, active, suspended, ended, archived) with transition history.
8. Transfer initiation and approvals: parent/guardian, current counselor, or destination Workspace may initiate; no initiator can finalize alone; valid guardian consent, prior counselor fee-receipt confirmation, and destination acceptance are cumulative.
9. Organization Manager: explicit limited scope; global scope only through a specific permission and audit.
10. Guardian authority: relationship and legal authority must be verified according to age/law; consent scope, expiry, revocation, and audit are required; mobile number or assertion alone is insufficient.
11. Counselor/branch assignment changes: authorized owner/manager with explicit permission and destination counselor acceptance; cross-Workspace transfer is separate.
12. Archived reactivation: permitted owner/manager; recheck capacity, credit, contract, and assignment; a new Enrollment is preferred for a new period.
13. Retention/deletion: category-based legal/contractual retention and legal hold; durations must not be guessed.
14. Commercial entitlements, Student Credit ledger, and capacity/quota have separate lifecycles.
15. Credit debit: only after successful activation; activation and debit atomic/idempotent; renewals have separate policy; reversals use compensating ledger entries.
16. Content ownership: Platform reference/curriculum, Organization content, and counselor-personal content have explicit ownership/licensing and versioning; reconcile with D-012.
17. MVP versioning: minimum auditable versioning for ProgramTemplate and StudentPlan; published versions immutable; changes create new versions.
18. Object disclosure: cross-tenant and nonexistent resources return the same 404; 403 only when the object is visible but the action is forbidden.
19. Background jobs: each job is scoped to one Workspace/tenant, with immutable tenant identity, ownership/membership validation, and idempotent retry safety.
20. File storage: private S3-compatible storage, tenant namespace, server-side authorization before short-lived signed URLs; provider remains open.
21. Time: UTC canonical timestamps; Jalali default display and optional Gregorian display; scheduled events retain local date/time and timezone.
22. Risk engine: deterministic, explainable, versioned, configurable; AI is assistive; counselor override is audited.
23. Sessions/MFA: risk-based session controls; MFA mandatory for high-risk roles; session inventory, revocation, expiry, and renewal.
24. Audit: security, finance, sensitive access, transfer, permission changes, and critical events are protected/append-only; no secrets or unnecessary confidential content.
25. Notifications: provider-neutral Notification Core with In-App MVP; SMS/Telegram/Email later; template versioning, preferences/consent, delivery/retry/rate limits.
26. Import/export: scoped exports, data minimization, audit, rate limits; imports use staging, validation, and preview; export authorization is separate.
27. Planning: deterministic, explainable, testable planning; counselor approval; AI recommendations only; published plans never auto-change; inputs/rule version/explanation recorded.
28. Test analysis/mastery: subject/chapter/topic granularity; correct/wrong/blank, timing, error reasons; incremental mastery model.
29. Backlog: explicit prioritization; no unbounded automatic carry-over; review/approval before rescheduling.
30. Hosting/capacity: provider-neutral until benchmark, threat model, cost, backup/restore, and capacity evidence; Alt-5 hybrid isolation; maximum two Workspaces per cell for initial pilot; provisional ten-tenant pilot cap pending measurement.
31. Backup/recovery: layered independent encrypted immutable backups and restore drills; RPO/RTO/retention values require business/legal/cost analysis; replication is not backup.
32. Platform Admin: least privilege, time-bound, approved, audited; MVP read-only; no BYPASSRLS or runtime table-owner role; emergency write requires a separate future decision/dual control.
33. Public results: public release limited to aggregate/anonymized statistics; no public individual rankings/results; internal Workspace ranking remains permission/privacy-controlled.
34. Exam scoring: negative marking configurable per exam and ON by default; scoring-policy snapshot preserves historical results.
35. Real-data gate: no real student/customer data until independent tenant-isolation, authorization/RLS, migration, backup/restore, file/API tests and review pass and the Product Owner gives written approval.

### Transfer and global identity decisions previously recorded in PR #8 / PR #11

- D-025 business rule remains: at most one active enrollment globally per canonical E.164 mobile + academic grade. **Implementation authority is the central Control Plane registry**, not a Workspace-local database table. Workspace-local registries cannot enforce global uniqueness across isolated databases.
- D-026 fee confirmation remains cumulative: the previous counselor must personally confirm receipt from their authenticated account for the exact prior enrollment; this is an auditable assertion, not independent proof of payment.
- D-027 guardian consent remains cumulative: explicit, scoped, auditable consent from one registered parent or a legally authorized guardian; default requirement is not consent from both parents.
- Destination Workspace acceptance is an additional cumulative prerequisite.
- Transfer architectural direction (accepted 2026-11-06; recorded in PR #11): central Control Plane ownership registry is authoritative for current Workspace owner and monotonically increasing ownership generation; durable recoverable Saga; atomic ownership switch in the Control Plane; generation fencing; idempotent outbox/inbox or equivalent; fail-closed when ownership cannot be validated; prior counselor-private notes/confidential communications are not automatically transferred.
- Workspace-local enrollment rows are projections/operational records, not global ownership authority.

### Additional Product Owner decisions confirmed 2026-11-07

These identifiers are deliberately OQ labels pending the collision-free D-number crosswalk required by OQ-C.

**OQ-A — Platform Admin as transfer initiator: ACCEPTED, Option A**
- Platform Admin cannot initiate a student transfer.
- Platform Admin may create a support/administrative review request only; that request is not a transfer request and cannot bypass guardian consent, prior counselor fee confirmation, or destination acceptance.
- Eligible initiators remain: verified parent/legal guardian, current counselor, or destination Workspace.

**OQ-B — Control Plane mobile-number protection: ACCEPTED, Option K**
- Normalize mobile numbers to canonical E.164.
- Store the recoverable mobile value encrypted in the Control Plane.
- Use a keyed deterministic HMAC index for lookup/global uniqueness; HMAC is not a substitute for encryption.
- Platform Security infrastructure owns management of encryption and HMAC keys. Keys must not be stored in database rows, source code, or Git.
- Key rotation, recovery, versioning, dual-index migration, and access/audit controls require detailed design and tests.

**OQ-C — Decision numbering/replacement: ACCEPTED, Option A**
- Perform a collision-free crosswalk across PRs #8, #9, #10, and #11 before assigning D-028 onward.
- Each decision is individually approved; a proposed number is not approval.
- Preserve superseded decisions with SUPERSEDED status and a reference to the replacement; do not silently delete history.
- Keep unresolved items in OPEN_QUESTIONS.md.

**OQ-D — Control Plane topology/recovery: ACCEPTED, Option A**
- Independent Control Plane infrastructure.
- Primary database plus a replica for availability.
- Encrypted backups independently controlled from the primary infrastructure and periodic restore drills.
- Student-data access is fail-closed if registry ownership cannot be validated.
- Replica is not a substitute for independent backup. RPO, RTO, retention, failover consistency, split-brain prevention, and measured capacity/cost remain open.

**OQ-E — Transfer cutover: ACCEPTED, Option B**
- MVP uses controlled write freeze at source followed by a final snapshot, destination staging/import, integrity validation, and only then the atomic Control Plane ownership switch.
- Destination access is enabled only after required checks and ownership switch.
- Freeze duration, precise freeze boundary, failure recovery, and acceptance thresholds require detailed design and tests.
- Snapshot + final-delta is not selected for MVP.

**OQ-F1 — Legal jurisdiction: ACCEPTED, Option A**
- MVP legal workflow is designed for Iran only.
- Architecture remains extensible to additional jurisdictions.
- Specific evidence requirements must be validated against applicable Iranian law; no unsupported document rule is presumed.

**OQ-F2 — Retention/deletion: ACCEPTED, Option A**
- Category-based retention with independently determined durations.
- Durations are set only after legal, contractual, operational, and cost analysis.
- Support deletion or anonymization at expiry and legal hold where required.
- Retention policies are versioned and auditable; no numeric duration is approved yet.

**OQ-F3 — Capacity: ACCEPTED, Option A**
- Independently configurable capacity for Workspace, counselor, branch, concurrency, and cell resources.
- Active students consume active capacity; archived students do not.
- Capacity checks are atomic and separate from Student Credits.
- Provisional initial pilot cap: at most 10 Workspaces total and at most 2 Workspaces per cell; neither is measured capacity evidence or pilot authorization.
- Per-counselor, branch, concurrency, and cell limits require benchmark evidence.

**OQ-G — General parent access / Q-007: HIGH-LEVEL POLICY ACCEPTED, Option A**
- Parent access is independently configurable per child and per information/action scope.
- Relationship and legal authority must be verified; age and applicable law govern.
- Consent/permission supports scope, expiry, change, revocation, and audit.
- Counselor-private notes and confidential communications are hidden by default; sensitive/financial/test data require separate permissions.
- Student rights and applicable law prevail over ordinary settings.
- Q-007 remains OPEN for the detailed age-based permission matrix, legal evidence, exceptions, and executable authorization tests.

### Precedence and status rules

1. OQ-A supersedes only the former D-026 statement that Platform Admin may initiate transfer. D-026's prior counselor fee confirmation remains required; D-027 guardian consent and destination acceptance remain cumulative.
2. OQ-B chooses encrypted mobile plus keyed HMAC index; it does not approve key-management implementation or define key rotation.
3. OQ-D/OQ-E settle architectural direction only; they do not approve schema, code, deployment, tests, or production readiness.
4. OQ-G settles the high-level parent-access policy only; Q-007 must remain open for detailed legal and technical rules.
5. All decisions above are product/architecture decisions, not proof of implementation or test success. Phase 2 remains NOT READY until independent review of reconciled artifacts and evidence. D-014 real-data prohibition remains in force.
