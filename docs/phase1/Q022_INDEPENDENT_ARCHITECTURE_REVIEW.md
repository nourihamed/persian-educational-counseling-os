# Q-022 Independent Architecture Review and Decision Proposal

**Review date:** 2026-10-23  
**Repository:** `nourihamed/persian-educational-counseling-os`  
**Reviewed PR head at start:** `36480e91125e1b0b0ff5be09bf2ae14224612ca2`  
**Status:** Recommendation only. No final topology selected; no implementation authorized.

## 1. Executive conclusion

**Recommendation: evaluate and select a hybrid isolation-cell architecture (Alt-5), with Alt-4 (separately operated clusters/instances) as the security reference.** For an initial 10-tenant pilot, a conservative starting proposal is at most two tenants per isolation cell (five cells for ten tenants), subject to cost/capacity review. This is a proposed blast-radius limit, not a measured capacity result or an owner decision.

A cell must be a real security and operational boundary—not merely a different database name or schema. It should have:
- its own PostgreSQL cluster/instance and network access boundary, with separation appropriate to the threat model;
- distinct tenant/cell-scoped runtime credentials and a secret-access policy that prevents an ordinary application worker from retrieving credentials for every cell;
- application workers/processes scoped to a single cell, or an equivalently enforceable boundary;
- cell-scoped migration identities, never a routine global migrator that can read/write all tenant data;
- separate backup encryption/access scope and a tested restore process;
- a deployment/control plane that can orchestrate releases but does not automatically receive data-plane credentials;
- audited, time-limited break-glass access for exceptional cross-cell operations, with a named approver and evidence retention.

The two-tenants-per-cell proposal should be accepted only if operating cost, deployment complexity, backup/restore, and connection capacity are shown to be manageable. If separate operational domains cannot be delivered, do not describe a shared-host/shared-secret arrangement as equivalent isolation.

**Important limitation:** no database topology can prevent exposure if an attacker truly obtains every tenant credential and can reach every corresponding database, or compromises a global administrator that controls all cells and keys. The design must prevent a single routine process, vault policy, owner/migrator identity, or host administrator from silently becoming such a universal credential. Remaining global-root/cloud-control-plane risk must be explicitly described and decided.

## 2. Source-grounded review findings

1. At review start, live PR #3 was open and unmerged; the branch was 68 commits ahead and zero behind `main`. The latest returned PR metadata said `mergeable=true`; that is only GitHub mergeability, not architecture approval.
2. No PR workflow runs were returned for the reviewed head. This is not a test pass.
3. The existing alternatives document is qualitative and explicitly says its conclusions are hypotheses, not measured or test-verified results.
4. The existing test catalog contains 123 specifications; zero are implemented, zero executed, and zero passing. It still describes Option C as preferred and includes Option C-specific assumptions. Those labels are stale after D-019 and must not be treated as current acceptance criteria.
5. `TENANT_ISOLATION_DESIGN.md` has a D-019 supersession notice at the top, but its body still contains historical D-009/Option C normative text. Readers could mistake that old body for the active design unless it is replaced after Q-022.
6. The load plan is not evidence of capacity: target host is not confirmed; tests are NOT-RUN/BLOCKED; the 10-tenant cap is provisional.
7. The prior hosting decision D-011 (initial single VPS / Docker Compose) may conflict with the proposed operational isolation cells. D-011 must be re-evaluated against the selected Q-022 architecture; separate database names or containers on one host do not isolate against host/root compromise.

## 3. Trust boundaries required in the final design

| Boundary | Assets / identity | Required security property | Failure blast radius to measure |
|---|---|---|---|
| TB-1 Counselor/student API | Authenticated user, tenant membership, object IDs | Tenant derived from authenticated principal; object-level checks; IDs never grant access | One request / one tenant |
| TB-2 Runtime worker | Process memory, connection pools, loaded credentials | A worker cannot retrieve/use credentials outside its assigned tenant/cell | One tenant or one cell |
| TB-3 Secret distribution | Vault policy, workload identity, secret rotation | No ordinary app identity can enumerate all tenant/cell credentials | One tenant/cell; vault-admin compromise remains separate |
| TB-4 Database data plane | PostgreSQL roles, network ACLs, databases/clusters, RLS/constraints | A compromised tenant/cell credential cannot cross its permitted boundary; RLS is not the only control | One tenant/cell |
| TB-5 Migration/owner operations | DDL, migration credentials, ownership, maintenance | Runtime and migration roles differ; no standing routine global data-capable owner | One cell per migration identity; global platform/root remains high-trust |
| TB-6 Backup/restore | Backup service, encryption keys, snapshots, restore operator | Cell-scoped access and keys; restore cannot silently reactivate suspended/deleted tenants | One cell, unless backup control plane is compromised |
| TB-7 Deployment/host/cloud control plane | CI/CD, VM/root, cloud account, global operator | Deployment authority is not automatically data-read authority; privileged operations are audited and constrained | Explicitly disclose any global blast radius |
| TB-8 Support/platform administration | Platform Admin, emergency access | Default no cross-tenant data access; explicit, least-privilege, time-limited, audited break-glass | Only approved incident scope |
| TB-9 Logs, exports, notifications, files | Derived/copy data and object storage | Tenant/cell authorization follows data into every derivative path; secrets/PII not leaked in logs | Same or narrower than source tenant/cell |
| TB-10 Recovery and tenant offboarding | Disable, revoke, terminate sessions, rotate, delete | Revocation is prompt, observable, and survives restore | Affected tenant/cell; no automatic role deletion |

A shared physical host, global root account, global backup key, or universal secret-manager identity can collapse otherwise separate logical boundaries. If any remain, the threat model must state this plainly.

## 4. Comparative residual-risk assessment

Ratings are qualitative design assessments, not empirical proof.

### Alt-1 — Shared database with per-tenant roles (prior Option C baseline)
- **Boundary:** role/RLS inside one shared database.
- **Strength:** can constrain a single tenant login against other tenants if role membership, ownership, grants, policies, functions, views, and routing are correct.
- **Residual:** broad credential/secret-store or process compromise can reach many tenants; a sufficiently privileged owner/operator can defeat separation; shared schema/configuration mistakes have broad impact.
- **Assessment:** **not recommended** for the risk tolerance recorded in D-019.

### Alt-2 — Separate database per tenant on a shared PostgreSQL cluster
- **Boundary:** database CONNECT/grants and per-tenant database credentials.
- **Strength:** reduces accidental cross-database query/policy mistakes and improves per-tenant lifecycle operations.
- **Residual:** cluster superuser, shared host/root, global backups, shared secret store, or one app process holding all credentials can still expose all tenants.
- **Assessment:** **insufficient by itself**. Do not choose it without independent runtime/secret/privileged-operation boundaries.

### Alt-3 — Separate database per tenant plus tenant-scoped runtime identity and secret access
- **Boundary:** database per tenant plus enforceable workload identity, secret policy, and tenant-scoped worker/connection routing.
- **Strength:** materially reduces the blast radius of one worker or one credential-distribution boundary if isolation is enforced.
- **Residual:** shared cluster/root, global deployment/backup control, or a vault administrator with unrestricted access can still cross tenants; all credentials stolen remains a broad compromise.
- **Assessment:** viable only if the secret/process boundary is demonstrated, not asserted. It does not by itself solve K-O.

### Alt-4 — Separately operated PostgreSQL clusters/instances with separated operational access
- **Boundary:** database/cluster plus network, workload, credential, backup, and privileged-operator boundaries.
- **Strength:** strongest of the listed choices when “separate” includes operational identity and host/cloud boundaries, not just separate database objects.
- **Residual:** global cloud/account root, global CI/CD deployment authority, universal backup keys, or stolen credentials for every tenant can still create broad exposure. Per-tenant dedicated infrastructure may be costly.
- **Assessment:** **security reference architecture**. Use it to judge whether Alt-5's shared components are acceptable.

### Alt-5 — Hybrid isolation cells
- **Boundary:** small groups of tenants, each on a separately controlled cell; runtime, secrets, migrations, and backups are scoped to the cell.
- **Strength:** limits ordinary compromise to a bounded group while avoiding one full cluster per tenant; can scale to dedicated cells for higher-risk tenants.
- **Residual:** a cell compromise exposes its entire group; global control-plane/root compromise may still span cells; multiple deployment profiles enlarge the test and operations matrix.
- **Assessment:** **recommended candidate**, conditional on a small explicit maximum cell size, real credential/operational separation, and measured capacity/cost.

## 5. Critical clarification: K-L-N and K-O

### K-L-N — all tenant login credentials stolen
If an attacker has actually obtained every tenant's valid database credential and can connect to every database, topology alone cannot prevent access to every tenant. Stronger architecture can prevent one worker or one secret-store policy from collecting all credentials, require cell-specific network/workload identity, limit credential lifetime, and detect/revoke misuse. The test plan must distinguish: (1) one tenant credential stolen; (2) one worker or one cell's secrets compromised; (3) secret-store administrator compromised; and (4) every tenant credential independently stolen and usable.

### K-O — owner/migrator compromise
A single global owner or migrator with effective access to every tenant defeats tenant separation. The target design should use cell-scoped migration identities and no standing global data-capable owner for routine work. A global database/host/cloud administrator remains a separate, high-trust residual; mitigate with split administration, just-in-time access, dual approval for cross-cell operations, short sessions, audit evidence, and tested revocation. Do not claim RLS protects against a superuser.

## 6. Specific proposal for Q-022

**Proposed decision draft — for the Product Owner, not yet accepted:**

1. Select **Alt-5, hybrid isolation cells**, as the target design direction, with **Alt-4** as the comparison baseline.
2. For the first 10-tenant pilot, propose **no more than two tenants per cell** (up to five cells). This is a proposed security blast-radius limit, not a capacity finding. If cost/capacity makes this infeasible, present evidence and ask the Product Owner before increasing the limit.
3. Require a separate PostgreSQL cluster/instance and network boundary per cell; distinct cell-scoped runtime credentials; worker/process isolation per cell; cell-scoped migration identities; separately scoped backup keys and restore permissions.
4. The deployment controller may deploy artifacts but must not receive tenant database credentials or backup decryption keys as routine privileges. No routine global migrator/owner may read or write all tenant data.
5. Require time-limited break-glass with dual approval for cross-cell access, reason/ticket, immutable audit evidence, session termination and post-incident review.
6. Re-open D-011 (single VPS/Docker Compose) and D-017 (direct connection pool size/cap) for compatibility review. Do not assume the current host or pool model supports cells.
7. Treat actual theft of every tenant credential and global host/cloud root compromise as explicit catastrophic scenarios. The revised design must minimize likelihood and improve detection/revocation; it cannot honestly claim topology makes them impossible. The Product Owner must explicitly decide the remaining global-root risk before real-data use.
8. Do not implement until the design is revised and reviewed. Do not authorize real student data until D-014's separate implementation, security-test, capacity, incident-drill, and written-approval conditions are all met.

### Alternatives for the owner

- **A — Accept the recommended Alt-5 proposal:** up to two tenants per pilot cell, subject to capacity/cost evidence; cell-scoped workers/secrets/migrations/backups and audited break-glass.
- **B — Choose Alt-4 dedicated operational isolation per tenant:** strongest listed separation, higher expected operating cost and complexity; still requires secret/process/global-admin controls.
- **C — Request another design:** specify a different cost or maximum-blast-radius target; no implementation starts while architecture remains unresolved.

**Supervisor recommendation: A**, conditional on demonstrating the controls above and validating cost/capacity. If the priority is minimizing cross-tenant blast radius regardless of operating cost, choose B instead. Neither choice approves Phase 1 or authorizes a real-data pilot.

## 7. Required changes after Q-022 is decided

1. Update D-009/D-011/D-016/D-017 status and record topology, cell-size rule, trust boundaries, and residual risks in `DECISION_LOG.md`.
2. Replace the superseded normative portions of `TENANT_ISOLATION_DESIGN.md`; do not merely append another banner.
3. Rewrite `AUTHORIZATION_CONTRACT.md` to define tenant-to-cell routing, object-level authorization, worker/secret scopes, and platform/support access.
4. Reclassify all 123 test contracts: retain reusable API/repository/file/job/export/notification tests; replace Option C-only database/connection tests with tests for the chosen cell/cluster/credential model; add negative tests for cross-cell routing, secret enumeration, worker compromise assumptions, migration-role scope, backup/restore isolation, cell suspension, credential rotation/revocation, and global control-plane privileges.
5. Separate PR CI tests from environment/security-review tests. Keep every unexecuted test NOT-RUN/BLOCKED; no SPEC-ONLY/NOT-RUN test may count as PASS.
6. Revisit target-host architecture, connection/capacity estimates, backup/restore plan, emergency stop, monitoring, and on-call responsibilities. Measure capacity on the actual target environment; the provisional ten-tenant cap is not proof.
7. Independently review the full resulting diff and trace each threat → control → contract → evidence → pass criterion before changing the Phase 1 gate.

## 8. Current gate

**NOT READY / NOT APPROVED.** This is a recommendation, not a Product Owner decision. Q-022 remains OPEN until the owner chooses A/B/C or requests a different proposal. Phase 2 remains unauthorized. No code, migration, infrastructure, runtime test, or real-data pilot is authorized.
