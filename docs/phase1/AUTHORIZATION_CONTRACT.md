# AUTHORIZATION_CONTRACT.md — Alt-5 Hybrid Isolation Cells

**Phase:** 1 — Architecture & Multi-Tenancy (design only)  
**Status:** DESIGN CONTRACT — reviewed for Phase 1 design readiness under D-024. No endpoint exists and no behavior is implemented or test-verified. Q-023 provider-specific validation remains a pre-hosting gate.  
**Normative architecture:** `docs/phase1/TENANT_ISOLATION_DESIGN.md`; security targets D-020/D-023 apply. Historical pre-Q-022 contract versions are not normative.

## 1. Purpose and mandatory rule

Every endpoint, job, report, export, file operation, notification, search, cache operation, and support action must declare its authorization behavior before implementation. An undeclared path is not reviewable and must not be merged.

Authorization has two independent boundaries:
1. **Application/object authorization:** who may perform which action on which object.
2. **Cell isolation:** the worker, credentials, and network route used for the request are limited to the tenant's trusted cell. Application filters are not a substitute for cell isolation; cell isolation is not a substitute for object-level authorization.

## 2. Request decision procedure

1. Authenticate the actor; otherwise return 401.
2. Resolve tenant membership from trusted identity/session state. Never trust tenant_id, cell_id, database name, connection string, or routing hint supplied by the request.
3. Resolve the tenant's active cell through the trusted control-plane mapping. Missing, duplicate, suspended, draining, or inconsistent mapping fails closed and raises an operational alert.
4. Dispatch only to a worker/pool assigned to that cell. The worker's workload identity and secret policy must not permit access to other cells.
5. Check RBAC action permission; denied action returns 403.
6. Load the target object inside the authorized tenant and cell. Invisible cross-tenant/cell and nonexistent objects must produce indistinguishable responses (exact status pending Q-014; 404 recommended).
7. Check object-level relationship/status and referenced object IDs. IDs never grant authority. Every referenced object must belong to the same tenant; cross-cell references are rejected.
8. Execute mutations transactionally with appropriate concurrency and idempotency controls.
9. Emit audit events for sensitive/state-changing operations, including actor, tenant, cell, action, target type/ID, request/correlation ID, outcome, and reason where appropriate. Never log credentials or student-content payloads.
10. Ensure retries/background jobs preserve a server-signed or otherwise trusted tenant/cell context and revalidate lifecycle status at execution time.

## 3. Principal scope

| Principal | Permitted scope | Prohibited by default |
|---|---|---|
| Counselor | Own tenant, own authorized students and plans, routed only to its cell | Other counselor's tenant or any arbitrary cell |
| Student | Own records within the active tenant relationship | Other students, even within the same tenant |
| Parent | Only explicitly linked students under Q-007 policy | Unlinked students, counselor-private notes |
| Teacher | Not in MVP | Any permission until explicitly designed |
| Platform Admin | Metadata and the D-013 limited audited read-only path | Default cross-cell content access, writes, or bypass of cell controls |
| Cell runtime worker | One assigned cell and least-privilege data operations | Other cell endpoints/secrets; DDL/role administration/global secret enumeration |
| Cell migration runner | Approved migration for one named cell | Routine global data access or all-cell owner/migrator authority |
| Break-glass operator | Only approved incident scope, dual-authorized, time-limited | Standing cross-cell access or unlogged actions |

## 4. Cell routing and lifecycle authorization

- Tenant-to-cell mapping comes only from the protected control-plane registry; mapping changes require a privileged, audited operation.
- The tenant's cell must be revalidated for sensitive jobs and on lifecycle transitions; do not rely only on a stale queue payload or cached mapping.
- Suspended/draining/retired cells reject new writes and ordinary reads according to a documented maintenance policy; fail closed if routing cannot be verified.
- A move between cells is not a CRUD update. It requires an approved migration workflow, access freeze, integrity checks, explicit cutover, revocation of old credentials/sessions, and rollback plan.
- Cell occupancy must not exceed two tenants in the proposed pilot. Attempting to assign a third tenant is rejected unless a separate Product Owner decision changes the limit after measured capacity/cost evidence.
- No cross-cell foreign keys or student-content references are allowed. Shared reference data must be explicitly classified and read-only.

## 5. Object-level rules

| Action | Required rule |
|---|---|
| Counselor reads/updates student | Active CounselorStudent relationship and matching tenant; route to that tenant's cell |
| Counselor edits plan | Active relationship; edits create a new PlanVersion; no silent overwrite |
| Student executes plan item | Student owns plan and item belongs to active plan version |
| Student reads another student's plan | Forbidden, including within the same tenant |
| Writes to published ProgramVersion | Forbidden; create a new version |
| Create PlanVersion from ProgramVersion | Same tenant and cell; student belongs to the owning counselor/program relationship |
| Activate student | Credit availability checked transactionally against the auditable credit ledger |
| Report/export | Query and output limited to authorized tenant; pagination/counts do not leak other tenants |
| File download/upload | Object authorization plus tenant/cell-scoped object-storage prefix/key and short-lived signed URL if used |
| Notification delivery | Recipient, tenant, and cell are revalidated at delivery; no recipient supplied by untrusted job payload alone |
| Background job | Signed/trusted tenant+cell context; re-resolve mapping and lifecycle before processing |
| Support access | D-013 limits: read-only, audited, explicitly scoped; no default content access or write capability |

## 6. Derived data and indirect access

The same tenant/cell restrictions apply to:
- reports, dashboards, aggregate counts and exports;
- files, attachments, generated PDFs, and signed URLs;
- search indexes and autocomplete;
- caches and cache keys;
- queues, retries, scheduled jobs, dead-letter queues;
- notifications and delivery logs;
- audit events, application logs, traces and metrics labels;
- backup/restore and data-repair workflows.

**Backup/recovery authorization under D-023:** a cell backup identity may operate only within its approved cell scope. Critical recovery copies, backup-administration permissions, encryption keys, deletion/retention controls, and audit evidence must be outside ordinary production-account administrative control. Production deployment or cell-admin credentials must not automatically grant backup deletion or decryption authority. Restore operators must verify authoritative tenant suspension/offboarding/retention state before service is returned. A different bucket or service label alone is not evidence of administrative independence. Every exceptional restore or recovery action must be scoped, approved, audited, and verified after completion.

No endpoint may fetch broad results then filter by tenant in memory. Tenant/cell constraints must be applied at the query/selection boundary, and the cell network/credential boundary remains independent defense in depth.

## 7. Error handling

| Situation | Response policy |
|---|---|
| Unauthenticated | 401 |
| Authenticated but action not allowed | 403 |
| Cross-tenant/cell object invisible | Same status/body as nonexistent object; 404 recommended, pending Q-014 |
| Visible object but relationship/status forbids action | 403 |
| Invalid or cross-tenant referenced ID | Generic 422 without confirming existence elsewhere |
| Conflict/idempotency/version race | 409 |
| Missing/inconsistent tenant-to-cell mapping | Fail closed; generic server error and internal alert, no tenant data disclosed |
| Cross-cell routing/network denial | Fail closed; security event and alert; no fallback to a global connection |

Error messages must not disclose another tenant's identifiers, names, counts, cell assignment, or existence.

## 8. Required endpoint review checklist

- [ ] Actor and authentication mechanism identified.
- [ ] Tenant membership resolved from trusted identity, never request-supplied tenant/cell IDs.
- [ ] Active tenant-to-cell mapping checked.
- [ ] Worker/credential/network scope bound to one cell.
- [ ] RBAC action permission and object-level relationship declared.
- [ ] All body/path IDs verified within same tenant/cell.
- [ ] List filters applied in query, not after fetching.
- [ ] Derived data and async paths listed and tested.
- [ ] Sensitive mutations and privileged actions audited.
- [ ] Error response does not reveal cross-tenant existence.
- [ ] At least one applicable test contract from the active catalog linked.
- [ ] Revocation/suspension and idempotency behavior defined where relevant.
- [ ] Backup/restore and emergency recovery identities are scoped; critical backups, keys and deletion/retention controls meet D-023's independent administrative boundary.
- [ ] Restore workflow rechecks authoritative tenant lifecycle state and cannot reactivate suspended/offboarded users or tenants.

No authorization contract in this document constitutes runtime evidence. All behavior requires implementation and executed tests after the relevant phase is authorized.
