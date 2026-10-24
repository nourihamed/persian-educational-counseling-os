# TENANT_ISOLATION_DESIGN.md — Alt-5 Hybrid Isolation Cells

**Phase:** 1 — Architecture & Multi-Tenancy (design only)  
**Status:** APPROVED — provider-neutral design only, after independent supervisor review under D-024 (2026-10-24). Provider-specific compatibility remains an OPEN pre-hosting gate under Q-023.  
**Scope boundary:** architecture and contracts only. No code, migrations, roles, grants, policies, infrastructure, or runtime tests are authorized or claimed to exist.  
**Decision source:** `DECISION_LOG.md` D-020, D-023 and D-024; `OPEN_QUESTIONS.md` Q-022 and Q-023.  
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
10. All security claims remain design hypotheses until supported by implementation evidence and executed tests. Tenant-level isolation inside a two-tenant cell is a required control, not an optional future enhancement.
11. Production cell boundaries target Level 3 infrastructure and administrative independence as defined by D-023; separate containers or VMs under one unrestricted global administrator do not alone establish that independence.
12. Critical backup/recovery controls target Level 4 independent administration under D-023: production administrators must not be able, by themselves, to destroy all critical recovery copies or control all backup decryption keys.

## 2. Scope, topology, and cell definition

A cell is not merely a schema, database name, Docker container, process label, or connection-pool partition. For this design, each cell requires:
- a separate PostgreSQL cluster/instance;
- a cell-specific network access policy so a worker assigned to one cell cannot connect to other cell databases by default;
- tenant-specific database/credential boundaries within each cell, plus cell-scoped infrastructure and secret retrieval policy;
- runtime workers/processes scoped to a single tenant within its assigned cell where feasible; any shared cell worker must not hold reusable credentials for both tenants at once;
- cell-scoped migration identity and controlled migration orchestration;
- cell-scoped backup access and encryption-key permissions;
- cell-specific monitoring labels, audit context, restore/suspension state, and revocation procedures.

**Hosting and administrative boundary (D-023):** the previous D-011 single-VPS/Docker-Compose assumption is not automatically compatible. Each production cell requires a distinct host/VM and network boundary, a separate PostgreSQL cluster/instance, cell-scoped runtime/worker/secret/migration identities, and an administrative boundary that prevents routine administrators of one cell from automatically administering all others. Separate VMs or networks under a common unrestricted root/organization administrator are not, by themselves, proof of Level 3 independence. The eventual provider/account design must disclose all global administrators, control-plane identities, deployment authority, secret-store administrators, and emergency access. Provider-wide control-plane compromise remains an explicit residual risk. This document does not select a provider or assert that any provider can meet the target.

**Cell membership and tenant data boundary:** a tenant maps to exactly one active cell at a time and to its own database inside that cell. A tenant database must not be shared with another tenant. The mapping is stored in a control-plane registry with strict write permissions, audit history, and uniqueness constraints. Tenant-to-cell migration is an explicit operation with a maintenance state, verified export/import or replication process, integrity checks, authorization freeze, and a rollback plan. It must not be an ordinary user-editable field.

## 3. Trust boundaries and failure domains

| Boundary | Principal/assets | Required property | Maximum intended routine blast radius |
|---|---|---|---|
| TB-1 Identity and authorization | Counselor/student/parent identity, tenant membership, object IDs | Membership is server-verified; object-level authorization on every action | One request/tenant |
| TB-2 Control-plane tenant registry | Tenant-to-cell mapping, lifecycle state | Only narrow control-plane service can mutate mapping; changes are audited and integrity-checked | One mapping operation; control-plane compromise is broader residual |
| TB-3 Runtime worker | Process memory, active DB session, loaded secrets | Worker is assigned to one cell; no cross-cell secret retrieval or network access | One cell |
| TB-4 Secret distribution | Workload identity, secret store, rotation | Ordinary workload cannot enumerate all cell secrets; each secret has cell audience/scope | One cell; global vault-admin compromise remains |
| TB-5 Cell database/network | PostgreSQL cluster, role grants, network ACLs, RLS if used | Credential/network path from cell A cannot access cell B | One cell |
| TB-6 Migration and ownership | DDL role, data owner, migration runner | Per-cell identities; no routine global data-capable owner/migrator | One cell per migration identity |
| TB-7 Backup and restore | Snapshots, encryption keys, backup account/admin, restore operators | Level 4 independent admin/control boundary; production account cannot alone destroy all recovery copies or control all keys; restore preserves lifecycle state | One cell; provider/global compromise remains residual |
| TB-8 Deployment/control plane | CI/CD, artifact signing, host/cloud control plane | Deploying software does not inherently grant data-read or backup-key access | Explicitly documented; global root can be catastrophic |
| TB-9 Support/platform administration | Platform Admin, break-glass | Default no cross-tenant content access; exceptional access scoped, dual-approved, time-limited, audited | Approved incident scope |
| TB-10 Derived data | Files, exports, reports, logs, caches, search, notifications, jobs | Same or narrower tenant/cell scope; no cross-cell fan-out by untrusted identifiers | Source tenant/cell |
| TB-11 Recovery/offboarding | Disable/revoke, sessions, pool connections, restore | Revocation is prompt, observable, and survives recovery | Affected tenant/cell |
| TB-12 Operations and monitoring | Alerts, audit pipeline, incident responders | Detect cross-cell attempts, privilege changes, secret enumeration and unexpected egress | Detection scope must include cross-cell patterns |

A common host, universal secret, global backup key, unrestricted control-plane role, or universal network path can collapse the intended isolation. If any such component is shared, it must be listed as a high-trust dependency with compensating controls and an explicit residual-risk statement.

## 4. Threat model and residual risks

### 4.1 Ordinary application/API defect or IDOR
Tenant and object access must be checked against authenticated membership and loaded within the tenant/cell. IDs are references, not capabilities. A tenant A request must never select tenant B's cell by changing a path/body/header value. Uniform not-found behavior for invisible and nonexistent objects is required, subject to Q-014's final status-code choice.

### 4.2 SQL injection or arbitrary query on one tenant connection
A tenant-specific database credential must be confined to that tenant's database within its assigned cell; the network and cluster boundary then prevents access outside the cell. Tests must deliberately omit application filters and verify both that tenant A cannot read tenant B even when they share a cell, and that no credential in cell A can connect to cell B. RLS and least-privilege grants are defense in depth, not the cell boundary.

### 4.3 One tenant credential stolen
The stolen credential must authenticate only to that tenant's database and must not enable access to the other tenant in the same cell or any other cell. The cell-level shared cluster/host remains a residual boundary for privileged compromise, but ordinary tenant credentials must be tenant-specific. Detection, rotation, session termination, and revocation are required.

### 4.4 One worker or one cell secret set compromised
Expected maximum impact depends on the compromised identity: a tenant-scoped worker/secret must be limited to one tenant; compromise of a shared cell control-plane/worker or cell-level privileged identity may expose up to the two tenants assigned to that cell. No ordinary worker may possess reusable credentials for both tenants or an all-cells secret list. Test secret enumeration, network reach, workload identity, and process/pool assignment.

### 4.5 All tenant credentials stolen (K-L-N)
If an attacker independently obtains all valid credentials and can connect to every corresponding database, the architecture cannot guarantee that broad exposure is prevented. The design must make this require multiple independent compromises rather than one worker or one ordinary secret policy, reduce credential lifetime, detect anomalous use, and enable rapid revocation. This remains a catastrophic residual scenario for pre-pilot risk review.

### 4.6 Migration/owner compromise (K-O)
A routine migration identity must not read/write every cell. Migration orchestration may coordinate releases, but each database operation authenticates using the specific cell's migration identity. A compromised cell migrator should be bounded to that cell. Global cloud/host/database root or an operator able to assume all cell identities remains a high-trust residual; use split administration, just-in-time access, dual approval for cross-cell actions, short sessions, immutable audit, and tested revocation. Do not claim RLS protects against superuser.

### 4.7 Backup, restore, and offboarding
Cell-scoped backup permissions are necessary but do **not** by themselves satisfy D-023's Level 4 target. Critical recovery copies must be outside ordinary production-account administrative control, with independently controlled backup administration, encryption keys, deletion permissions, retention/immutability settings, and audit evidence. Production compromise alone must not permit an attacker to delete all critical copies or obtain all keys. Independence must be demonstrated, not inferred from a different bucket, project label, or service name. Recovery testing must prove integrity and restore ability and must reconcile against an authoritative tenant lifecycle source so suspended, deleted, offboarded, or revoked identities cannot silently become active. Role deletion is not automatic: disable login, revoke grants, terminate sessions/pools, rotate secrets, retain audit evidence, review ownership/dependencies/retention, and obtain the designated approval first.

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
| Tenant runtime identity | One tenant database within its assigned cell, least privilege | Connect to the other tenant database or other cells; DDL; create roles; read global secrets |
| Tenant/cell migration identity | A specifically named tenant database or approved cell migration scope | Routine read/write access to all cells; manage global credentials |
| Cell backup/restore identity | Backup/restore for assigned cell only | Decrypt other cells' backups; administer all critical backup copies or keys |
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

Within each cell, each tenant receives a separate database and tenant-specific runtime credential; no shared tenant-content database is assumed by this design. Within that database, tenant-owned tables still need explicit ownership, foreign keys, uniqueness and authorization constraints appropriate to the domain. Cross-tenant and cross-cell relationships are forbidden in the MVP data plane. A cell-level migration must authenticate using a named, narrowly scoped identity and may not become a routine all-tenant data credential. Shared global reference data must be read-only, explicitly classified, and contain no tenant content or identifiers.

## 8. Capacity, cost, and hosting gates

Before any pilot:
- select the actual target hosting profile and document the cell-to-host/VM/account/network mapping and every global/root/organization administrator;
- demonstrate the D-023 Level 3 boundary: separate cell host/VM and network, cell-scoped identities, and no routine single-cell administrator able to administer other cells; document the provider-global compromise residual;
- demonstrate the D-023 Level 4 backup boundary: critical copies, keys, deletion/retention controls and backup administration are outside ordinary production-account control;
- measure CPU, memory, disk I/O, connection count, connection churn, latency, restore time, deploy time, and cost at the proposed ten-tenant/five-cell maximum;
- test failure of one cell without disrupting unrelated cells;
- document per-cell connection pool settings; D-017's recorded pilot baseline remains direct PostgreSQL connections with pool size 1 per tenant per process, but its compatibility and capacity under the Alt-5 cell topology are unverified and must be measured per PostgreSQL instance before hosting/pilot; changing the baseline requires a separate Product Owner decision;
- confirm that migration, monitoring, backups, security patches, and incident response are affordable and operationally repeatable;
- do not increase two tenants per cell or ten tenants overall without a separate owner decision backed by measurements.

A capacity plan or estimate is not a measurement. No capacity result is recorded by this document.

## 9. Required adversarial evidence before approval

At minimum, the test catalog must cover:
- one tenant credential cannot reach another cell;
- one worker cannot enumerate or retrieve other cell secrets;
- cross-cell network and routing are denied by default;
- per-cell migration identity cannot read/write another cell;
- backup keys/restore identities are cell-scoped, critical backups have independent administrative/deletion/key controls outside ordinary production-account control, and restore preserves suspension/offboarding;
- deployment controller lacks routine data-plane credentials;
- break-glass requires dual approval, expires, is audited, and revokes sessions;
- API, repository, jobs, reports, exports, files, notifications, search, cache, and logs remain tenant-scoped;
- suspension/revocation terminates existing sessions and pooled connections;
- capacity, failure containment, restore, and emergency-stop drills are measured on the actual target environment.

All contracts remain NOT-RUN until executed with evidence. Threat/control/test mappings are required; source review alone is not proof.

## 10. Explicit non-goals and open dependencies

- This is not a choice of host/provider, exact cloud account topology, secret-manager product, or implementation framework. The provider-neutral Level 3/Level 4 requirements in D-023 are mandatory; a real candidate must be verified against them before hosted deployment and Q-023 can close. Under D-024, candidate-specific verification is not a prerequisite for the Phase 1 design-only gate.
- It does not resolve Q-007 parent access, Q-014 exact response status, Q-017 job execution model, Q-018 file storage provider, retention durations, named incident roles, or legal/tax requirements.
- D-011 hosting and D-017 pool assumptions must be re-evaluated for cell compatibility; this document does not silently change those business decisions.
- It does not authorize implementation, migration, infrastructure, Phase 2, real student data, or a pilot.
- D-014 pilot gates remain fully in force.

## 11. Current gate

**Phase 1 design gate: APPROVED (2026-10-24), documentation/architecture only.** The provider-neutral Alt-5 trust boundaries, Level 3/Level 4 requirements, and global-admin/provider compromise residuals are specified here. Q-023 remains OPEN for candidate-specific validation and is a hard gate before hosted deployment, not a blocker to this documentation-only phase under D-024. Cost/capacity, implementation, operational controls, and runtime-test evidence remain future hosted-deployment/pilot gates. This document does not authorize Phase 2 automatically or any real-data pilot. No code, migration, infrastructure, runtime test, or real-data pilot is claimed.
