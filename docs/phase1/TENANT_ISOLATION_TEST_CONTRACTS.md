# TENANT_ISOLATION_TEST_CONTRACTS.md — Active Alt-5 Catalog

**Architecture:** D-020 / Q-022 Alt-5 hybrid isolation cells; Alt-4 is the security reference. D-023 Level 3 production-cell and Level 4 critical-backup independence targets are mandatory.  
**Status:** SPECIFICATIONS ONLY. **0 implemented, 0 executed, 0 passing.** No runtime test or infrastructure was created by this documentation update.  
**Hard boundary:** every contract below is a planned acceptance criterion, not evidence that isolation works. The 123 pre-Q-022 contracts are preserved at `archive/TENANT_ISOLATION_TEST_CONTRACTS_PRE_Q022.md` and mapped below. Their former execution/status labels do not carry forward as acceptance results.

## 1. Test modes and evidence rules

- **S — Static:** source/configuration/manifest checks.
- **C — Configuration:** actual deployed/test environment identities, grants, network policy, secret access, backup and cell registry.
- **A — API/application integration:** endpoint/object-level authorization.
- **I — Integration/adversarial/operational:** cross-component attack simulation, jobs, files, restore, lifecycle, or privileged access.

**Status for all active contracts:** NOT-RUN. A test passes only when the specified environment ran it, the expected result was observed, evidence is linked, and a reviewer verified the evidence. Missing harness or unavailable target environment means BLOCKED/NOT-RUN, never PASS. A green static check cannot substitute for a network/credential compromise test.

## 2. Active acceptance contracts

| ID | Mode | Setup / attack | Expected result | Threat addressed | Execution lane |
|---|---|---|---|---|---|
| TI-CELL-01 | S | Control-plane registry: every active tenant maps to exactly one active cell; duplicate/missing mapping fails closed. | Registry invariant query/check passes; invalid mapping is rejected. | Ambiguous or attacker-controlled routing | PR |
| TI-CELL-02 | I | Tenant A submits tenant_id/cell_id/database hint for B in path, body, header, and query variants. | All variants are ignored/rejected; route remains A's trusted cell; no B data is returned. | Request-controlled cross-cell routing / IDOR | PR |
| TI-CELL-03 | I | Attempt a connection from cell A worker/network to cell B database endpoint using its normal workload identity. | Connection denied by network and credential boundary; no global fallback. | Lateral movement between cells | ENV:security-review |
| TI-CELL-04 | S + C | Inspect secret policy and attempt secret enumeration/read by cell A runtime identity. | Only A's secret paths are readable; B and other cells are denied and audited. | Universal secret access | PR + ENV:security-review |
| TI-CELL-05 | I | Compromise simulation in cell A worker; inspect process environment, mounted secrets, workload identity and network routes. | No B-cell credential or route is available; documented impact is bounded to A cell. | Worker compromise spans tenants | ENV:security-review |
| TI-CELL-06 | C | Inspect PostgreSQL instances, database roles, network ACLs and connection endpoints for two cells. | Each cell has a separate PostgreSQL cluster/instance and an independently enforced network boundary. | Logical database names misrepresented as cell isolation | ENV:security-review |
| TI-CELL-07 | C | Enumerate runtime role memberships and grants for every cell. | Runtime role is least-privileged; no CREATEROLE, superuser, replication, DDL or cross-cell membership. | Runtime privilege escalation | PR + ENV:security-review |
| TI-CELL-08 | C | Authenticate using tenant A's runtime credential and attempt tenant B's database in the same cell and all other cell endpoints. | A's credential cannot authenticate to B's database in the same cell or any other cell. | Tenant credential reuse / cross-cell access | ENV:security-review |
| TI-CELL-09 | C | Inspect migration identities and attempt read/write against a different cell. | Migration identity for A is denied on B; each migration action names a cell and emits audit evidence. | Global migrator compromise | ENV:security-review |
| TI-CELL-10 | C | Inspect standing owner/admin roles and secret paths for routine migration workflow. | No routine standing global data-capable owner/migrator; exceptional global privilege is separate, time-bound and audited. | K-O global owner/migrator | ENV:security-review |
| TI-CELL-11 | C | Inspect backup storage/account/organization boundary, backup-admin identities, encryption-key custody, deletion/retention controls and restore permissions; attempt access from a production/cell-admin identity and from cell A's backup identity against other cells. | Production/cell administrators cannot alone delete all critical recovery copies or control all critical backup keys; cell A cannot access B backups; independent backup administrators/keys and retention/deletion controls are evidenced; provider/global control-plane residual is documented. A separate bucket/service name alone is not accepted as evidence. | D-023 Level 4 backup independence; global backup exposure | ENV:security-review |
| TI-CELL-12 | I | Restore a test backup for a suspended/offboarded tenant. | Authoritative lifecycle state prevents restored tenant, user, or credential from silently becoming active. | Restore resurrects revoked access | ENV:security-review |
| TI-CELL-13 | S + C | Inspect deployment controller identity and simulate normal deployment access. | Can deploy approved artifacts but cannot read tenant DB credentials or backup decryption keys by default. | Deployment authority equals data authority | ENV:security-review |
| TI-CELL-14 | I | Request cross-cell break-glass with no second approver, expired approval, or missing incident ticket. | All attempts denied; approved session is scoped, expires, and produces immutable audit evidence. | Uncontrolled support access | ENV:security-review |
| TI-CELL-15 | I | Revoke a cell credential while active sessions and pools exist. | New authentication denied; existing sessions/pools terminated within documented target; evidence and alert emitted. | Credential revocation incomplete | ENV:security-review |
| TI-CELL-16 | C | Provision/configure the pilot cell registry and try assigning a third tenant to a two-tenant cell. | Assignment rejected and audited unless a separately approved policy change exists. | Silent blast-radius expansion | PR + ENV:capacity |
| TI-CELL-17 | I | Simulate compromise separately for (a) tenant-scoped worker/credential and (b) shared cell-level privileged worker/control plane. | (a) impact limited to one tenant database; (b) impact may reach at most the two tenants in that cell; other cells remain unreachable. | Tenant/cell blast-radius confusion | ENV:security-review |
| TI-CELL-18 | I | Simulate global host/cloud administrator compromise in a tabletop/threat exercise. | Residual blast radius, available logs, split-control barriers, key scope and recovery steps are documented; test does not claim topology eliminates root risk. | Undocumented global-root residual | ENV:security-review |
| TI-CELL-19 | I | Attempt cross-cell foreign-key/reference or API relationship between tenant objects. | Rejected; no student-content cross-cell relationship is created. | Cross-cell data coupling | PR + ENV:integration |
| TI-CELL-20 | I | Exercise tenant move between cells with stale jobs/sessions and failure during cutover. | Move requires approved freeze/cutover; stale credentials and jobs cannot write to old/new cell inconsistently; rollback is evidenced. | Unsafe cell migration | ENV:integration |
| TI-CELL-21 | I | Suspended tenant sends API request, job, retry, file URL, and notification action. | All paths fail closed according to lifecycle policy; no cached mapping reactivates access. | Lifecycle bypass | PR + ENV:integration |
| TI-CELL-22 | C + I | In a cell containing tenants A and B, inspect database inventory, grants, runtime credentials and worker secret mounts; attempt A-to-B reads using A's normal credential. | A and B have separate databases and tenant-specific credentials; A's normal worker/credential cannot access B. Shared cell/root compromise is documented as a separate residual. | Intra-cell tenant isolation gap | ENV:security-review |
| TI-CELL-23 | I | Run a controlled tabletop/containment exercise assuming every tenant credential is independently stolen and usable; do not assume topology can prevent broad exposure. | Document reachable data, detection signals, bulk revocation/rotation, session termination, incident containment, recovery integrity, decision/escalation ownership, and residual risk; do not claim guaranteed containment. | K-L-N: all-tenant-credentials-compromised catastrophic residual | ENV:security-review |
| TI-API-01 | A | Counselor A requests a student object owned by tenant B and compares response with nonexistent ID. | Status/body indistinguishable; no identifying metadata leaks. | IDOR / object existence disclosure | PR |
| TI-API-02 | A | Counselor A lists students, including pagination/count/search variants. | Only A tenant records are returned; counts and cursors are tenant-scoped. | List/query leakage | PR |
| TI-API-03 | A | Submit B student/program/version IDs in A create/update body. | Generic validation error; no B object is created or existence disclosed. | Referenced-object IDOR | PR |
| TI-API-04 | A | Exercise student and parent access with same-tenant but wrong-person objects. | Relationship checks deny access; tenant equality alone is insufficient. | Intra-tenant object authorization | PR |
| TI-API-05 | A | Exercise reports, dashboards, exports and aggregate counts for a tenant. | Only authorized tenant data and counts are included. | Analytics/export leakage | PR |
| TI-API-06 | A | Request files, signed URLs and generated PDFs from another tenant/cell. | Denied; object-storage key/prefix and authorization are scoped; URL expires appropriately. | File/object storage IDOR | PR |
| TI-API-07 | A | Queue/retry/dead-letter notification and background-job payload with a forged tenant/cell. | Worker re-resolves trusted mapping; forged routing rejected; no cross-cell delivery or processing. | Async confused deputy | PR |
| TI-API-08 | A | Exercise cache/search/logging paths with same object IDs across tenants. | Tenant/cell namespace is part of keys and queries; no content/secret leakage in logs. | Derived-data leakage | PR |
| TI-API-09 | A | Try Platform Admin content access/write outside D-013 path and scope. | Default denied; only explicitly authorized read-only audited path available; no BYPASSRLS/global data credential. | Platform-admin privilege escalation | PR + ENV:security-review |
| TI-API-10 | A | Exercise published ProgramVersion immutability and PlanVersion creation. | Published versions immutable; new version created with attribution and tenant/cell consistency. | Version/ownership bypass | PR |
| TI-API-11 | A | Attempt student activation with insufficient credit and concurrent requests. | Atomic ledger validation prevents activation and negative/duplicated credit use. | Billing race/tenant mismatch | PR + ENV:integration |
| TI-API-12 | A | Attempt suspended tenant access via API and stale authenticated session. | Access denied and audit evidence emitted; no fallback to another cell. | Suspension/session bypass | PR |
| TI-API-13 | A | Attempt concurrent duplicate mutation/retry across timeout boundary. | Idempotency/transaction behavior prevents duplicate side effects and cross-tenant replay. | Retry/concurrency defect | PR + ENV:integration |
| TI-JOB-01 | I | Replay a background job with stale/forged tenant and cell identifiers. | Job re-resolves registry and membership; stale or forged context fails closed. | Queue payload as authority | PR + ENV:integration |
| TI-JOB-02 | I | Execute delayed job after tenant suspension, move, or credential rotation. | Job stops or reroutes only through approved lifecycle flow; no writes to retired cell. | Stale job/cell mapping | PR + ENV:integration |
| TI-JOB-03 | I | Generate a report/export asynchronously for two tenants in separate cells. | Output artifacts are tenant-scoped; worker cannot merge cross-cell student content. | Async export leakage | PR + ENV:integration |
| TI-FILE-01 | A | Attempt to access another tenant's file by ID, path, signed URL, and object key. | All access denied; storage credentials/prefix are cell-scoped; no existence leak. | Object storage IDOR | PR + ENV:integration |
| TI-FILE-02 | A | Use expired/revoked signed URL after tenant suspension or file ownership change. | Access denied or URL expired within documented limit; revocation behavior verified. | Stale file grant | PR + ENV:integration |
| TI-NOTIF-01 | I | Forge recipient, tenant, or cell in a queued notification and retry. | Delivery recipient and tenant are revalidated at send time; no cross-cell content. | Notification confused deputy | PR + ENV:integration |
| TI-VER-01 | A | Create/update template and student plan versions across tenant/cell boundaries. | Cross-tenant/cell version linkage rejected; history and attribution preserved. | Version lineage leakage | PR |
| TI-AUD-01 | I | Inspect audit events for cross-cell denial, privileged action, secret read, migration, and break-glass. | Required fields present, immutable/externally retained as designed; no credentials or student content payloads. | Audit blind spot / secret leakage | PR + ENV:security-review |
| TI-OPS-01 | I | Simulate cell failure, deploy, restore, revoke, and emergency stop at target load. | Measured containment, recovery, cost, and capacity evidence attached; runbook exercised without reactivating suspended tenants. | Unmeasured operations/capacity | ENV:capacity + ENV:security-review |
| TI-OPS-02 | I | Review target topology, cell size, connection limits, CPU/RAM/I/O, latency and monthly cost for ten tenants/five cells. | Measurements recorded from actual target environment; any limit increase requires explicit owner decision. | Unsupported capacity assumption | ENV:capacity |
| TI-OPS-03 | I | Attempt break-glass without dual approval and verify session expiry/revocation. | Denied or expired access is demonstrable; session/pool closure and audit evidence confirmed. | Emergency privilege persists | ENV:security-review |

## 3. Required traceability for each contract

For each executed contract, record: test run ID and commit; target environment/cell topology; test identity and privilege; preconditions/positive control; exact attack/input; expected and actual result; logs/metrics or other evidence; status (PASS/FAIL/BLOCKED/NOT-RUN); defect and regression-test link; reviewer and timestamp. Redact secrets and student data from evidence.

## 4. Migration of pre-Q-022 contracts

The prior catalog contained 123 unique test IDs. It is archived intact for traceability; its old status labels are not evidence and must not be copied into the active result register. Each old ID receives the following disposition for planning:

| Historical contract ID | Required disposition |
|---|---|
| TI-CFG-01 | REWRITE / SPLIT for Alt-5. Old shared-DB/RLS/GUC/per-tenant-connection assumptions are historical, not current acceptance criteria. |
| TI-CFG-02 | REWRITE / SPLIT for Alt-5. Old shared-DB/RLS/GUC/per-tenant-connection assumptions are historical, not current acceptance criteria. |
| TI-CFG-03 | REWRITE / SPLIT for Alt-5. Old shared-DB/RLS/GUC/per-tenant-connection assumptions are historical, not current acceptance criteria. |
| TI-CFG-04 | REWRITE / SPLIT for Alt-5. Old shared-DB/RLS/GUC/per-tenant-connection assumptions are historical, not current acceptance criteria. |
| TI-CFG-05 | REWRITE / SPLIT for Alt-5. Old shared-DB/RLS/GUC/per-tenant-connection assumptions are historical, not current acceptance criteria. |
| TI-CFG-06 | REWRITE / SPLIT for Alt-5. Old shared-DB/RLS/GUC/per-tenant-connection assumptions are historical, not current acceptance criteria. |
| TI-CFG-07 | REWRITE / SPLIT for Alt-5. Old shared-DB/RLS/GUC/per-tenant-connection assumptions are historical, not current acceptance criteria. |
| TI-CFG-08 | REWRITE / SPLIT for Alt-5. Old shared-DB/RLS/GUC/per-tenant-connection assumptions are historical, not current acceptance criteria. |
| TI-CFG-09 | REWRITE / SPLIT for Alt-5. Old shared-DB/RLS/GUC/per-tenant-connection assumptions are historical, not current acceptance criteria. |
| TI-CFG-10 | REWRITE / SPLIT for Alt-5. Old shared-DB/RLS/GUC/per-tenant-connection assumptions are historical, not current acceptance criteria. |
| TI-CFG-11 | REWRITE / SPLIT for Alt-5. Old shared-DB/RLS/GUC/per-tenant-connection assumptions are historical, not current acceptance criteria. |
| TI-CFG-12 | REWRITE / SPLIT for Alt-5. Old shared-DB/RLS/GUC/per-tenant-connection assumptions are historical, not current acceptance criteria. |
| TI-CFG-13 | REWRITE / SPLIT for Alt-5. Old shared-DB/RLS/GUC/per-tenant-connection assumptions are historical, not current acceptance criteria. |
| TI-CFG-14 | REWRITE / SPLIT for Alt-5. Old shared-DB/RLS/GUC/per-tenant-connection assumptions are historical, not current acceptance criteria. |
| TI-CTX-01 | REWRITE / SPLIT for Alt-5. Old shared-DB/RLS/GUC/per-tenant-connection assumptions are historical, not current acceptance criteria. |
| TI-CTX-02 | REWRITE / SPLIT for Alt-5. Old shared-DB/RLS/GUC/per-tenant-connection assumptions are historical, not current acceptance criteria. |
| TI-CTX-03 | REWRITE / SPLIT for Alt-5. Old shared-DB/RLS/GUC/per-tenant-connection assumptions are historical, not current acceptance criteria. |
| TI-CTX-04 | REWRITE / SPLIT for Alt-5. Old shared-DB/RLS/GUC/per-tenant-connection assumptions are historical, not current acceptance criteria. |
| TI-CTX-05 | REWRITE / SPLIT for Alt-5. Old shared-DB/RLS/GUC/per-tenant-connection assumptions are historical, not current acceptance criteria. |
| TI-CTX-06 | REWRITE / SPLIT for Alt-5. Old shared-DB/RLS/GUC/per-tenant-connection assumptions are historical, not current acceptance criteria. |
| TI-CTX-07 | REWRITE / SPLIT for Alt-5. Old shared-DB/RLS/GUC/per-tenant-connection assumptions are historical, not current acceptance criteria. |
| TI-CTX-08 | REWRITE / SPLIT for Alt-5. Old shared-DB/RLS/GUC/per-tenant-connection assumptions are historical, not current acceptance criteria. |
| TI-CTX-09 | REWRITE / SPLIT for Alt-5. Old shared-DB/RLS/GUC/per-tenant-connection assumptions are historical, not current acceptance criteria. |
| TI-CTX-10 | REWRITE / SPLIT for Alt-5. Old shared-DB/RLS/GUC/per-tenant-connection assumptions are historical, not current acceptance criteria. |
| TI-CTX-11 | REWRITE / SPLIT for Alt-5. Old shared-DB/RLS/GUC/per-tenant-connection assumptions are historical, not current acceptance criteria. |
| TI-CTX-12 | REWRITE / SPLIT for Alt-5. Old shared-DB/RLS/GUC/per-tenant-connection assumptions are historical, not current acceptance criteria. |
| TI-CTX-13 | REWRITE / SPLIT for Alt-5. Old shared-DB/RLS/GUC/per-tenant-connection assumptions are historical, not current acceptance criteria. |
| TI-CTX-14 | REWRITE / SPLIT for Alt-5. Old shared-DB/RLS/GUC/per-tenant-connection assumptions are historical, not current acceptance criteria. |
| TI-CTX-15 | REWRITE / SPLIT for Alt-5. Old shared-DB/RLS/GUC/per-tenant-connection assumptions are historical, not current acceptance criteria. |
| TI-CTX-16 | REWRITE / SPLIT for Alt-5. Old shared-DB/RLS/GUC/per-tenant-connection assumptions are historical, not current acceptance criteria. |
| TI-CTX-17 | REWRITE / SPLIT for Alt-5. Old shared-DB/RLS/GUC/per-tenant-connection assumptions are historical, not current acceptance criteria. |
| TI-CTX-18 | REWRITE / SPLIT for Alt-5. Old shared-DB/RLS/GUC/per-tenant-connection assumptions are historical, not current acceptance criteria. |
| TI-FK-01 | REWRITE / SPLIT for Alt-5. Old shared-DB/RLS/GUC/per-tenant-connection assumptions are historical, not current acceptance criteria. |
| TI-FK-02 | REWRITE / SPLIT for Alt-5. Old shared-DB/RLS/GUC/per-tenant-connection assumptions are historical, not current acceptance criteria. |
| TI-FK-03 | REWRITE / SPLIT for Alt-5. Old shared-DB/RLS/GUC/per-tenant-connection assumptions are historical, not current acceptance criteria. |
| TI-FK-04 | REWRITE / SPLIT for Alt-5. Old shared-DB/RLS/GUC/per-tenant-connection assumptions are historical, not current acceptance criteria. |
| TI-FK-05 | REWRITE / SPLIT for Alt-5. Old shared-DB/RLS/GUC/per-tenant-connection assumptions are historical, not current acceptance criteria. |
| TI-FK-06 | REWRITE / SPLIT for Alt-5. Old shared-DB/RLS/GUC/per-tenant-connection assumptions are historical, not current acceptance criteria. |
| TI-FK-07 | REWRITE / SPLIT for Alt-5. Old shared-DB/RLS/GUC/per-tenant-connection assumptions are historical, not current acceptance criteria. |
| TI-FK-08 | REWRITE / SPLIT for Alt-5. Old shared-DB/RLS/GUC/per-tenant-connection assumptions are historical, not current acceptance criteria. |
| TI-BYP-01 | REWRITE / SPLIT for Alt-5. Old shared-DB/RLS/GUC/per-tenant-connection assumptions are historical, not current acceptance criteria. |
| TI-BYP-02 | REWRITE / SPLIT for Alt-5. Old shared-DB/RLS/GUC/per-tenant-connection assumptions are historical, not current acceptance criteria. |
| TI-BYP-03 | REWRITE / SPLIT for Alt-5. Old shared-DB/RLS/GUC/per-tenant-connection assumptions are historical, not current acceptance criteria. |
| TI-BYP-04 | REWRITE / SPLIT for Alt-5. Old shared-DB/RLS/GUC/per-tenant-connection assumptions are historical, not current acceptance criteria. |
| TI-BYP-05 | REWRITE / SPLIT for Alt-5. Old shared-DB/RLS/GUC/per-tenant-connection assumptions are historical, not current acceptance criteria. |
| TI-BYP-06 | REWRITE / SPLIT for Alt-5. Old shared-DB/RLS/GUC/per-tenant-connection assumptions are historical, not current acceptance criteria. |
| TI-API-01 | RETAIN SEMANTICS; re-map routing/storage assertions to trusted tenant→cell mapping and active cell controls before implementation. |
| TI-API-02 | RETAIN SEMANTICS; re-map routing/storage assertions to trusted tenant→cell mapping and active cell controls before implementation. |
| TI-API-03 | RETAIN SEMANTICS; re-map routing/storage assertions to trusted tenant→cell mapping and active cell controls before implementation. |
| TI-API-04 | RETAIN SEMANTICS; re-map routing/storage assertions to trusted tenant→cell mapping and active cell controls before implementation. |
| TI-API-05 | RETAIN SEMANTICS; re-map routing/storage assertions to trusted tenant→cell mapping and active cell controls before implementation. |
| TI-API-06 | RETAIN SEMANTICS; re-map routing/storage assertions to trusted tenant→cell mapping and active cell controls before implementation. |
| TI-API-07 | RETAIN SEMANTICS; re-map routing/storage assertions to trusted tenant→cell mapping and active cell controls before implementation. |
| TI-API-08 | RETAIN SEMANTICS; re-map routing/storage assertions to trusted tenant→cell mapping and active cell controls before implementation. |
| TI-API-09 | RETAIN SEMANTICS; re-map routing/storage assertions to trusted tenant→cell mapping and active cell controls before implementation. |
| TI-API-10 | RETAIN SEMANTICS; re-map routing/storage assertions to trusted tenant→cell mapping and active cell controls before implementation. |
| TI-API-11 | RETAIN SEMANTICS; re-map routing/storage assertions to trusted tenant→cell mapping and active cell controls before implementation. |
| TI-API-12 | RETAIN SEMANTICS; re-map routing/storage assertions to trusted tenant→cell mapping and active cell controls before implementation. |
| TI-API-13 | RETAIN SEMANTICS; re-map routing/storage assertions to trusted tenant→cell mapping and active cell controls before implementation. |
| TI-API-14 | RETAIN SEMANTICS; re-map routing/storage assertions to trusted tenant→cell mapping and active cell controls before implementation. |
| TI-API-15 | RETAIN SEMANTICS; re-map routing/storage assertions to trusted tenant→cell mapping and active cell controls before implementation. |
| TI-API-16 | RETAIN SEMANTICS; re-map routing/storage assertions to trusted tenant→cell mapping and active cell controls before implementation. |
| TI-API-17 | RETAIN SEMANTICS; re-map routing/storage assertions to trusted tenant→cell mapping and active cell controls before implementation. |
| TI-REPO-01 | RETAIN SEMANTICS; re-map routing/storage assertions to trusted tenant→cell mapping and active cell controls before implementation. |
| TI-REPO-02 | RETAIN SEMANTICS; re-map routing/storage assertions to trusted tenant→cell mapping and active cell controls before implementation. |
| TI-REPO-03 | RETAIN SEMANTICS; re-map routing/storage assertions to trusted tenant→cell mapping and active cell controls before implementation. |
| TI-REPO-04 | RETAIN SEMANTICS; re-map routing/storage assertions to trusted tenant→cell mapping and active cell controls before implementation. |
| TI-REPO-05 | RETAIN SEMANTICS; re-map routing/storage assertions to trusted tenant→cell mapping and active cell controls before implementation. |
| TI-REPO-06 | RETAIN SEMANTICS; re-map routing/storage assertions to trusted tenant→cell mapping and active cell controls before implementation. |
| TI-RPT-01 | RETAIN SEMANTICS; re-map routing/storage assertions to trusted tenant→cell mapping and active cell controls before implementation. |
| TI-RPT-02 | RETAIN SEMANTICS; re-map routing/storage assertions to trusted tenant→cell mapping and active cell controls before implementation. |
| TI-RPT-03 | RETAIN SEMANTICS; re-map routing/storage assertions to trusted tenant→cell mapping and active cell controls before implementation. |
| TI-EXP-01 | RETAIN SEMANTICS; re-map routing/storage assertions to trusted tenant→cell mapping and active cell controls before implementation. |
| TI-EXP-02 | RETAIN SEMANTICS; re-map routing/storage assertions to trusted tenant→cell mapping and active cell controls before implementation. |
| TI-EXP-03 | RETAIN SEMANTICS; re-map routing/storage assertions to trusted tenant→cell mapping and active cell controls before implementation. |
| TI-FILE-01 | RETAIN SEMANTICS; re-map routing/storage assertions to trusted tenant→cell mapping and active cell controls before implementation. |
| TI-FILE-02 | RETAIN SEMANTICS; re-map routing/storage assertions to trusted tenant→cell mapping and active cell controls before implementation. |
| TI-FILE-03 | RETAIN SEMANTICS; re-map routing/storage assertions to trusted tenant→cell mapping and active cell controls before implementation. |
| TI-FILE-04 | RETAIN SEMANTICS; re-map routing/storage assertions to trusted tenant→cell mapping and active cell controls before implementation. |
| TI-FILE-05 | RETAIN SEMANTICS; re-map routing/storage assertions to trusted tenant→cell mapping and active cell controls before implementation. |
| TI-FILE-06 | RETAIN SEMANTICS; re-map routing/storage assertions to trusted tenant→cell mapping and active cell controls before implementation. |
| TI-FILE-07 | RETAIN SEMANTICS; re-map routing/storage assertions to trusted tenant→cell mapping and active cell controls before implementation. |
| TI-NOTIF-01 | RETAIN SEMANTICS; re-map routing/storage assertions to trusted tenant→cell mapping and active cell controls before implementation. |
| TI-NOTIF-02 | RETAIN SEMANTICS; re-map routing/storage assertions to trusted tenant→cell mapping and active cell controls before implementation. |
| TI-NOTIF-03 | RETAIN SEMANTICS; re-map routing/storage assertions to trusted tenant→cell mapping and active cell controls before implementation. |
| TI-NOTIF-04 | RETAIN SEMANTICS; re-map routing/storage assertions to trusted tenant→cell mapping and active cell controls before implementation. |
| TI-NOTIF-05 | RETAIN SEMANTICS; re-map routing/storage assertions to trusted tenant→cell mapping and active cell controls before implementation. |
| TI-JOB-01 | RETAIN SEMANTICS; re-map routing/storage assertions to trusted tenant→cell mapping and active cell controls before implementation. |
| TI-JOB-02 | RETAIN SEMANTICS; re-map routing/storage assertions to trusted tenant→cell mapping and active cell controls before implementation. |
| TI-JOB-03 | RETAIN SEMANTICS; re-map routing/storage assertions to trusted tenant→cell mapping and active cell controls before implementation. |
| TI-JOB-04 | RETAIN SEMANTICS; re-map routing/storage assertions to trusted tenant→cell mapping and active cell controls before implementation. |
| TI-JOB-05 | RETAIN SEMANTICS; re-map routing/storage assertions to trusted tenant→cell mapping and active cell controls before implementation. |
| TI-VER-01 | RETAIN SEMANTICS; re-map routing/storage assertions to trusted tenant→cell mapping and active cell controls before implementation. |
| TI-VER-02 | RETAIN SEMANTICS; re-map routing/storage assertions to trusted tenant→cell mapping and active cell controls before implementation. |
| TI-VER-03 | RETAIN SEMANTICS; re-map routing/storage assertions to trusted tenant→cell mapping and active cell controls before implementation. |
| TI-VER-04 | RETAIN SEMANTICS; re-map routing/storage assertions to trusted tenant→cell mapping and active cell controls before implementation. |
| TI-VER-05 | RETAIN SEMANTICS; re-map routing/storage assertions to trusted tenant→cell mapping and active cell controls before implementation. |
| TI-VER-06 | RETAIN SEMANTICS; re-map routing/storage assertions to trusted tenant→cell mapping and active cell controls before implementation. |
| TI-VER-07 | RETAIN SEMANTICS; re-map routing/storage assertions to trusted tenant→cell mapping and active cell controls before implementation. |
| TI-AUD-01 | RETAIN SEMANTICS; re-map routing/storage assertions to trusted tenant→cell mapping and active cell controls before implementation. |
| TI-AUD-02 | RETAIN SEMANTICS; re-map routing/storage assertions to trusted tenant→cell mapping and active cell controls before implementation. |
| TI-AUD-03 | RETAIN SEMANTICS; re-map routing/storage assertions to trusted tenant→cell mapping and active cell controls before implementation. |
| TI-PLAT-01 | RETAIN SEMANTICS; re-map routing/storage assertions to trusted tenant→cell mapping and active cell controls before implementation. |
| TI-PLAT-02 | RETAIN SEMANTICS; re-map routing/storage assertions to trusted tenant→cell mapping and active cell controls before implementation. |
| TI-PLAT-03 | RETAIN SEMANTICS; re-map routing/storage assertions to trusted tenant→cell mapping and active cell controls before implementation. |
| TI-PLAT-04 | RETAIN SEMANTICS; re-map routing/storage assertions to trusted tenant→cell mapping and active cell controls before implementation. |
| TI-PLAT-05 | RETAIN SEMANTICS; re-map routing/storage assertions to trusted tenant→cell mapping and active cell controls before implementation. |
| TI-PLAT-06 | RETAIN SEMANTICS; re-map routing/storage assertions to trusted tenant→cell mapping and active cell controls before implementation. |
| TI-PLAT-07 | RETAIN SEMANTICS; re-map routing/storage assertions to trusted tenant→cell mapping and active cell controls before implementation. |
| TI-PLAT-08 | RETAIN SEMANTICS; re-map routing/storage assertions to trusted tenant→cell mapping and active cell controls before implementation. |
| TI-PLAT-09 | RETAIN SEMANTICS; re-map routing/storage assertions to trusted tenant→cell mapping and active cell controls before implementation. |
| TI-PLAT-10 | RETAIN SEMANTICS; re-map routing/storage assertions to trusted tenant→cell mapping and active cell controls before implementation. |
| TI-CONN-01 | REWRITE / SPLIT for Alt-5. Old shared-DB/RLS/GUC/per-tenant-connection assumptions are historical, not current acceptance criteria. |
| TI-CONN-02 | REWRITE / SPLIT for Alt-5. Old shared-DB/RLS/GUC/per-tenant-connection assumptions are historical, not current acceptance criteria. |
| TI-CONN-03 | REWRITE / SPLIT for Alt-5. Old shared-DB/RLS/GUC/per-tenant-connection assumptions are historical, not current acceptance criteria. |
| TI-CONN-04 | REWRITE / SPLIT for Alt-5. Old shared-DB/RLS/GUC/per-tenant-connection assumptions are historical, not current acceptance criteria. |
| TI-CONN-05 | REWRITE / SPLIT for Alt-5. Old shared-DB/RLS/GUC/per-tenant-connection assumptions are historical, not current acceptance criteria. |
| TI-CONN-06 | REWRITE / SPLIT for Alt-5. Old shared-DB/RLS/GUC/per-tenant-connection assumptions are historical, not current acceptance criteria. |
| TI-ADV-01 | REWRITE / SPLIT for Alt-5. Old shared-DB/RLS/GUC/per-tenant-connection assumptions are historical, not current acceptance criteria. |
| TI-ADV-02 | REWRITE / SPLIT for Alt-5. Old shared-DB/RLS/GUC/per-tenant-connection assumptions are historical, not current acceptance criteria. |
| TI-ADV-03 | REWRITE / SPLIT for Alt-5. Old shared-DB/RLS/GUC/per-tenant-connection assumptions are historical, not current acceptance criteria. |
| TI-ADV-04 | REWRITE / SPLIT for Alt-5. Old shared-DB/RLS/GUC/per-tenant-connection assumptions are historical, not current acceptance criteria. |
| TI-ADV-05 | REWRITE / SPLIT for Alt-5. Old shared-DB/RLS/GUC/per-tenant-connection assumptions are historical, not current acceptance criteria. |

**Important:** “retain semantics” does not mean the old test is ready to run. Its setup, identity, expected result, execution lane, and linkage must be rewritten against the selected cell topology. The active catalog currently contains 47 architecture-specific/current contracts. The old catalog and this new catalog are different inventories; do not add their counts and claim one is passing.

## 5. Coverage obligations

The active contracts cover:
- tenant-to-cell registry and trusted routing;
- independent PostgreSQL/network boundary;
- worker identity, secret distribution, and runtime credentials;
- cell-scoped migration, owner, backup, restore, and deployment privileges, including D-023 Level 3 administrative independence and Level 4 backup/key/deletion-control independence;
- cell occupancy limit, cell migration, suspension, credential rotation, and revocation;
- API object authorization and every derived-data path;
- audit, break-glass, incident containment, capacity, cost, and emergency stop.

For Phase 1 design approval, every threat in `TENANT_ISOLATION_DESIGN.md` must map to at least one active contract, and every active contract must map to a stated threat/control. This catalog's threat/control traceability is a design artifact, not evidence of control effectiveness. No threat is closed for implementation or pilot merely because a specification exists.

## 6. CI vs environment-only evidence

- PR CI can cover static rules, unit/integration authorization behavior, mocked routing guards, contract completeness, and test inventory consistency.
- Actual cross-network reach, secret-store policy, per-cell database identity, backup-key and backup-admin independence, deletion/retention protection, restore behavior, privileged roles, revocation of live sessions/pools, capacity, cost, and emergency-stop drills require a representative isolated environment and cannot be reported as passed from PR CI alone.
- The exact target host and cell placement are not yet selected. Environment-only contracts remain BLOCKED until a target exists and must be run before real-data use.
- D-014 continues to prohibit real student data until independent implementation review, required security tests, blocking-finding remediation, capacity evidence, incident drill, and written Product Owner approval are complete.

## 7. Current gate

**Design status:** this catalog defines 47 active Alt-5 acceptance specifications; 0 are implemented, 0 executed, and 0 passing. Under D-024, NOT-RUN status does not by itself block the documentation-only Phase 1 gate. Actual implementation, environment-only security tests, backup/restore evidence, capacity, and incident drills remain hard pre-hosting/pre-pilot gates under Q-023 and D-014. This catalog does not authorize implementation, migrations, infrastructure, Phase 2 automatically, or real student data. The global-root and all-credentials-compromised residuals must remain explicit.
