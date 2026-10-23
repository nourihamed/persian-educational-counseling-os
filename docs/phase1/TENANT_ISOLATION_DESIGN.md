# TENANT_ISOLATION_DESIGN.md — Alt-5 Hybrid Isolation Cells

**Phase:** 1 — Architecture & Multi-Tenancy (design only)  
**Status:** DRAFT — aligned to Product Owner decision D-020 / Q-022 (2026-10-23); pending independent review and Phase 1 gate.  
**Scope boundary:** architecture and contracts only. No code, migrations, roles, grants, policies, infrastructure, or runtime tests are authorized or claimed to exist.  
**Decision source:** `DECISION_LOG.md` D-020; `OPEN_QUESTIONS.md` Q-022.  
**Historical material:** the former shared-database/Option C design is archived in Git history and is not normative. Any contradictory historical references elsewhere are superseded by this document and D-020.

## 1. Architecture decision and invariants

The selected direction is **Alt-5: hybrid isolation cells**, with Alt-4 (separate operational isolation per tenant) as the security reference. Each cell is an operational and data-plane boundary containing at most two tenants during the initial pilot proposal. The proposed initial pilot maximum is 10 tenants, up to five cells. Both figures are limits for design/cost evaluation, not measured capacity or authorization to run a pilot.

Non-negotiable invariants:
1. A counselor, student, parent, or ordinary application process cannot access another tenant's data except through an explicitly authorized, narrowly scoped support/break-glass procedure.
2. Tenant-to-cell routing is derived from authenticated, server-verified membership. A request-supplied tenant ID, cell ID, database name, or connection hint is never authoritative.
3. A worker's effective credentials and network reach are restricted to its assigned cell. An ordinary worker cannot list, read, or exchange into other cells' secrets.
4. Every tenant-owned object, derivative, background job, export, file, notification, report, cache entry, and audit event retains tenant authorization and cell scope.
5. Routine migration authority is cell-scoped. There is no standing global data-capable owner/migrator for ordinary migrations.
6. Deployment authority does not automatically imply tenant-data read authority. Privileged control-plane access is separated, just-in-time where possible, audited, and revocable.
7. Backups, encryption keys, restore permissions, and recovery procedures are scoped to the cell. A restore cannot silently reactivate a suspended/offboarded tenant.
8. The two-tenants-per-cell proposal cannot be raised without measured capacity/cost evidence and a separate explicit Product Owner decision.
9. RLS may be used as defense in depth inside a cell, but is not the cell boundary and is not a defense against a superuser or compromised host/cloud root.
10. All security claims remain design hypotheses until supported by implementation evidence and executed tests.

## 2. Scope, topology, and cell definition

A cell is not merely a schema, database name, Docker container, process label, or connection-pool partition. For this design, each cell requires:
- a separate PostgreSQL cluster/instance;
- a cell-specific network access policy so a worker assigned to one cell cannot connect to other cell databases by default;
- cell-scoped runtime credentials and secret retrieval policy;
- runtime worker/process isolation bound to one cell;
- cell-scoped migration identity and controlled migration orchestration;
- cell-scoped backup access and encryption-key permissions;
- cell-specific monitoring labels, audit context, restore/suspension state, and revocation procedures.

**Hosting consequence:** the previous D-011 initial single-VPS/Docker-Compose assumption is not automatically compatible. Multiple containers on one host do not isolate tenants against host/root compromise. Before approval, a hosting design must state whether cells have separate VMs/accounts/network security boundaries or share a host; any shared-host design must explicitly narrow its threat claim and be accepted only after an evidence-based risk review. This document does not select a cloud/host provider or assert capacity.

**Cell membership:** a tenant maps to exactly one active cell at a time. The mapping is stored in a control-plane registry with strict write permissions, audit history, and uniqueness constraints. Tenant-to-cell migration is an explicit operation with a maintenance state, verified export/import or replication process, integrity checks, authorization freeze, and a rollback plan. It must not be an ordinary user-editable field.

## 3. Trust boundaries and failure domains

| Boundary | Principal/assets | Required property | Maximum intended routine blast radius |
|---|---|---|---|
| TB-1 Identity and authorization | Counselor/student/parent identity, tenant membership, object IDs | Membership is server-verified; object-level authorization on every action | One request/tenant |
| TB-2 Control-plane tenant registry | Tenant-to-cell mapping, lifecycle state | Only narrow control-plane service can mutate mapping; changes are audited and integrity-checked | One mapping operation; control-plane compromise is broader residual |
| TB-3 Runtime worker | Process memory, active DB session, loaded secrets | Worker is assigned to one cell; no cross-cell secret retrieval or network access | One cell |
| TB-4 Secret distribution | Workload identity, secret store, rotation | Ordinary workload cannot enumerate all cell secrets; each secret has cell audience/scope | One cell; global vault-admin compromise remains |
| TB-5 Cell database/network | PostgreSQL cluster, role grants, network ACLs, RLS if used | Credential/network path from cell A cannot access cell B | One cell |
| TB-6 Migration and ownership | DDL role, data owner, migration runner | Per-cell identities; no routine global data-capable owner/migrator | One cell per migration identity |
| TB-7 Backup and restore | Snapshots, encryption keys, restore operators | Cell-scoped keys/access; lifecycle state remains correct after restore | One cell |
| TB-8 Deployment/control plane | CI/CD, artifact signing, host/cloud control plane | Deploying software does not inherently grant data-read or backup-key access | Explicitly documented; global root can be catastrophic |
| TB-9 Support/platform administration | Platform Admin, break-glass | Default no cross-tenant content access; exceptional access scoped, dual-approved, time-limited, audited | Approved incident scope |
| TB-10 Derived data | Files, exports, reports, logs, caches, search, notifications, jobs | Same or narrower tenant/cell scope; no cross-cell fan-out by untrusted identifiers | Source tenant/cell |
| TB-11 Recovery/offboarding | Disable/revoke, sessions, pool connections, restore | Revocation is prompt, observable, and survives recovery | Affected tenant/cell |
| TB-12 Operations and monitoring | Alerts, audit pipeline, incident responders | Detect cross-cell attempts, privilege changes, secret enumeration and unexpected egress | Detection scope must include cross-cell patterns |

A common host, universal secret, global backup key, unrestricted control-plane role, or universal network path can collapse the intended isolation. If any such component is shared, it must be listed as a high-trust dependency with compensating controls and an explicit residual-risk statement.

## 4. Threat model and residual risks

### 4.1 Ordinary application/API defect or IDOR
Tenant and object access must be checked against authenticated membership and loaded within the tenant/cell. IDs are references, not capabilities. A tenant A request must never select tenant B's cell by changing a path/body/header value. Uniform not-found behavior for invisible and nonexistent objects is required, subject to Q-014's final status-code choice.

### 4.2 SQL injection or arbitrary query on one cell connection
The database credential and network reach available to that connection must be confined to one cell. RLS and least-privilege grants can provide defense in depth, but cannot be presented as the cell boundary. Tests must deliberately omit application filters and verify that a cell A credential cannot connect to or query cell B.

### 4.3 One tenant credential stolen
The stolen credential must be valid only within its cell and must not enable access to other cell endpoints. Within-cell impact may include both tenants assigned to that cell; this is the accepted *design blast-radius target*, not an accepted security incident outcome. Detection, rotation, session termination, and cell-level containment are required.

### 4.4 One worker or one cell secret set compromised
Expected maximum routine data-plane impact is the assigned cell (up to two tenants under the pilot proposal). A worker must not possess an all-cells secret list or global credential. The design must test secret enumeration, network reach, token audience, workload identity, and process/pool assignment.

### 4.5 All tenant credentials stolen (K-L-N)
If an attacker independently obtains all valid credentials and can connect to every corresponding database, the architecture cannot guarantee that broad exposure is prevented. The design must make this require multiple independent compromises rather than one worker or one ordinary secret policy, reduce credential lifetime, detect anomalous use, and enable rapid revocation. This remains a catastrophic residual scenario for pre-pilot risk review.

### 4.6 Migration/owner compromise (K-O)
A routine migration identity must not read/write every cell. Migration orchestration may coordinate releases, but each database operation authenticates using the specific cell's migration identity. A compromised cell migrator should be bounded to that cell. Global cloud/host/database root or an operator able to assume all cell identities remains a high-trust residual; use split administration, just-in-time access, dual approval for cross-cell actions, short sessions, immutable audit, and tested revocation. Do not claim RLS protects against superuser.

### 4.7 Backup, restore, and offboarding
Backup access and keys must be cell-scoped. Restore must preserve tenant suspension/deletion/retention state from an authoritative lifecycle source and must not resurrect revoked accounts or credentials. Role deletion is not automatic: disable login, revoke grants, terminate sessions/pools, rotate secrets, retain audit evidence, review ownership/dependencies/retention, and obtain the designated approval first.

### 4.8 Global host/cloud/control-plane compromise
A global administrator able to control every cell, workload identity, network rule, backup key, or deployment artifact may still cause broad exposure. Cell topology alone cannot eliminate this. The design must enumerate global authorities, separate duties, minimize standing privilege, log privileged actions outside the compromised boundary where feasible, and require explicit risk review before real-data use.

## 5. Runtime and authorization flow

1. Authenticate the actor and resolve server-verified tenant membership.
2. Resolve the tenant's cell from the trusted control-plane mapping; reject missing, ambiguous, suspended, or inconsistent mappings closed by default.
3. Route only to the worker/connection pool assigned to that cell. User input cannot override the cell.
4. Apply role-based and object-level authorization inside the request path.
5. Query only the selected cell. The cell credential/network boundary prevents access to another cell even if a query filter is defective.
6. Validate every referenced object belongs to the same tenant; use tenant-aware foreign keys or equivalent constraints within the cell.
7. Commit writes transactionally and append audit evidence for sensitive changes.
8. Ensure background jobs, reports, exports, files, notifications, caches, and retries carry a trusted tenant/cell identity rather than accepting an arbitrary identifier from a message payload.
9. On revocation/suspension, stop new work, invalidate sessions/tokens as applicable, terminate DB sessions and pool connections, revoke/rotate credentials, and verify containment through audit evidence.

The exact application framework and implementation are outside this design-only artifact. No endpoint or control is claimed implemented.

## 6. Privileged identities and lifecycle

| Identity | Allowed scope | Prohibited standing capability |
|---|---|---|
| Cell runtime identity | One cell's application data, least privilege | Connect to other cells; DDL; create roles; read global secrets |
| Cell migration identity | One cell's approved schema/data migration | Routine read/write access to all cells; manage global credentials |
| Cell backup/restore identity | Backup/restore for assigned cell only | Decrypt every cell's backups by default |
| Deployment controller | Release orchestration, artifact integrity | Routine access to tenant DB credentials or backup keys |
| Control-plane registry service | Tenant-to-cell mapping and lifecycle metadata | General access to student content |
| Platform Admin | Metadata and explicitly approved read-only support path per D-013 | Default cross-cell student-content access or writes |
| Break-glass operator | Approved incident scope, time-limited | Standing universal access or unlogged actions |
| Global infrastructure administrator | Infrastructure-level emergency duties | Unreviewed, unaudited routine access; this role remains a high-trust residual |

Credential rotation and tenant offboarding must define owners, time targets, failure alerts, and verification evidence. A disabled login is not sufficient if existing sessions or pool connections remain active.

## 7. Data model, constraints, and cell registry

The cell registry must enforce:
- stable tenant ID mapped to exactly one cell in an active state;
- cell state (provisioning, active, suspended, draining, retired) and audited transitions;
- no active tenant assignment to a non-active cell;
- a configurable cell occupancy ceiling, with the pilot policy set to at most two tenants per cell;
- no move that temporarily leaves data accessible from both old and new cells without an explicit controlled migration state;
- a migration manifest and integrity verification before cutover;
- idempotent, resumable provisioning and teardown with secrets handled outside logs.

Within a cell, tenant-owned tables still need explicit tenant ownership, foreign keys, uniqueness and authorization constraints appropriate to the domain. Cross-cell relationships are forbidden in the MVP data plane. Shared global reference data must be read-only, explicitly classified, and contain no tenant content or identifiers.

## 8. Capacity, cost, and hosting gates

Before any pilot:
- select the actual target hosting profile and document the cell-to-host/VM/account/network mapping;
- measure CPU, memory, disk I/O, connection count, connection churn, latency, restore time, deploy time, and cost at the proposed ten-tenant/five-cell maximum;
- test failure of one cell without disrupting unrelated cells;
- document per-cell connection pool settings; D-017's former pool size 1 per tenant per process is a provisional historical assumption and must be re-evaluated against cell workers and actual concurrency;
- confirm that migration, monitoring, backups, security patches, and incident response are affordable and operationally repeatable;
- do not increase two tenants per cell or ten tenants overall without a separate owner decision backed by measurements.

A capacity plan or estimate is not a measurement. No capacity result is recorded by this document.

## 9. Required adversarial evidence before approval

At minimum, the test catalog must cover:
- one tenant credential cannot reach another cell;
- one worker cannot enumerate or retrieve other cell secrets;
- cross-cell network and routing are denied by default;
- per-cell migration identity cannot read/write another cell;
- backup keys/restore identities are cell-scoped and restore preserves suspension/offboarding;
- deployment controller lacks routine data-plane credentials;
- break-glass requires dual approval, expires, is audited, and revokes sessions;
- API, repository, jobs, reports, exports, files, notifications, search, cache, and logs remain tenant-scoped;
- suspension/revocation terminates existing sessions and pooled connections;
- capacity, failure containment, restore, and emergency-stop drills are measured on the actual target environment.

All contracts remain NOT-RUN until executed with evidence. Threat/control/test mappings are required; source review alone is not proof.

## 10. Explicit non-goals and open dependencies

- This is not a choice of host/provider, cloud account topology, secret-manager product, or implementation framework.
- It does not resolve Q-007 parent access, Q-014 exact response status, Q-017 job execution model, Q-018 file storage provider, retention durations, named incident roles, or legal/tax requirements.
- D-011 hosting and D-017 pool assumptions must be re-evaluated for cell compatibility; this document does not silently change those business decisions.
- It does not authorize implementation, migration, infrastructure, Phase 2, real student data, or a pilot.
- D-014 pilot gates remain fully in force.

## 11. Current gate

**NOT READY / NOT APPROVED.** Alt-5 is the selected design direction, but its implementation feasibility, hosting boundary, cost/capacity, operational controls, test evidence, and residual risks remain to be independently reviewed. Phase 2 is not authorized. No code, migration, infrastructure, runtime test, or real-data pilot is authorized.
