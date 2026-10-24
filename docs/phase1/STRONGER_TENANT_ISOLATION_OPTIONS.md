# Stronger Tenant-Isolation Architecture — Alternatives and Decision Record

**Status:** Historical design study. Alt-5 is selected by Product Owner decision D-020/Q-022; current normative requirements are in `TENANT_ISOLATION_DESIGN.md`. No implementation is authorized.
**Trigger:** Product Owner selected Q-021 option B on 2026-10-23: the project must not accept the current Option C residual risks for broad tenant-credential compromise (K-L-N) and owner/migrator compromise (K-O).
**Scope:** Phase 1 design/documentation. This document does not authorize code, migrations, infrastructure changes, Phase 2, or real student data.

## 1. Required security outcome

The revised design must make the blast radius of one compromised tenant credential as small as practical, and must avoid a single routine application credential or ordinary migration credential that can read every tenant. It must state honestly what remains possible after compromise of:
- one tenant's credential;
- the application process or shared secret-distribution boundary;
- a privileged database/cluster administrator;
- deployment, backup, or recovery credentials.

“Stronger” must be demonstrated by explicit trust boundaries and adversarial tests, not by naming a technology. No architecture can guarantee isolation after compromise of a superuser or equivalent host/cloud administrator that controls every tenant's storage and keys.

## 2. Alternatives

### Alt-1. Existing Option C baseline — shared database, per-tenant PostgreSQL login roles
- **Isolation boundary:** database role and RLS policy within one shared database.
- **Strength:** an injected query on tenant A's connection should not be able to switch to tenant B absent membership/privilege; preserves one schema and simple shared migrations.
- **Residual weakness:** a compromised application process or secret store holding many tenant credentials can reach many tenants; a privileged owner/migrator boundary can defeat isolation.
- **Disposition:** no longer sufficient as the sole accepted design for the stated risk tolerance. Retain only as a comparison/baseline, not as approved design.

### Alt-2. Separate database per tenant, shared PostgreSQL cluster and shared application process
- **Isolation boundary:** database-level CONNECT/role grants and separate tenant credentials; schema/database lifecycle per tenant.
- **Benefits:** limits accidental SQL/RLS-policy crossovers and enables per-tenant restore/export/deletion.
- **Limits:** cluster superusers and cluster-level backup/automation remain common blast-radius points. A shared application process or secret store holding all tenant credentials can still expose many/all tenants. This alone does not fully address K-L-N or K-O.
- **Cost/risks:** migration orchestration, connection management, schema-version drift, backup/restore automation, monitoring, and higher operational complexity.
- **Assessment:** potentially stronger than A/C for database-level mistakes, but insufficient by itself for broad process/credential or cluster-admin compromise.

### Alt-3. Separate database per tenant plus tenant-scoped runtime identity and secret access
- **Isolation boundary:** separate database per tenant, distinct least-privilege runtime credentials, and an enforced credential-routing boundary. The application must not make every tenant credential available to every request handler by default.
- **Benefits:** combines database-level separation with reduced credential blast radius; allows per-tenant revocation and recovery.
- **Limits:** if one process or secret manager can freely retrieve all credentials, process compromise can still expand to all tenants. Shared cluster administrators, backups, and deployment control remain high-trust boundaries unless further separated.
- **Cost/risks:** more infrastructure and operational work; requires careful tenant lifecycle automation, connection budgets, schema migration orchestration, and incident response.
- **Assessment:** a credible baseline for the next design iteration, conditional on proving that credential access is genuinely tenant-scoped rather than merely stored under different names.

### Alt-4. Separate PostgreSQL clusters/instances for tenant groups, with isolated runtime credentials and privileged operations
- **Isolation boundary:** database/cluster boundary plus separate credential and operational domains; tenants can be partitioned into small blast-radius groups or dedicated instances.
- **Benefits:** limits failures that cross a single database or cluster boundary and permits stronger separation of privileged operations and backups.
- **Limits:** a shared cloud/account administrator, deployment pipeline, or globally privileged operator may still cross boundaries. Full per-tenant clusters can be expensive and operationally heavy.
- **Cost/risks:** highest operating cost and complexity; more monitoring, upgrades, backups, failover, migration orchestration, and capacity management.
- **Assessment:** strongest of these options when operational and credential boundaries are actually separated. Grouping tenants is cheaper but leaves group-level blast radius; the permitted group size must be a deliberate risk decision.

### Alt-5. Hybrid tiered isolation
- **Isolation boundary:** small tenant groups on separate clusters/instances, with a path to dedicated isolation for high-risk or larger tenants.
- **Benefits:** balances blast radius and operating cost; allows measured growth without assuming one shared database is suitable for every tenant.
- **Limits:** introduces multiple deployment profiles and increases test matrix and operational complexity. The default group size and upgrade path must be explicit.
- **Assessment:** plausible product compromise, but only after the required risk tolerance and operating capacity are defined.

## 3. Comparative matrix

| Criterion | Alt-1: shared DB / per-tenant roles | Alt-2: DB per tenant / shared cluster | Alt-3: DB per tenant + scoped credentials | Alt-4: separate clusters + isolated operations | Alt-5: hybrid groups |
|---|---|---|---|---|---|
| One tenant SQL-injection blast radius | Intended one tenant; must test | Usually one DB | Usually one DB | One tenant/cluster boundary | One tenant/group boundary |
| All tenant credentials stolen | Broad exposure possible | Broad exposure possible | Depends on enforced secret/process isolation | Reduced if credentials and operations are truly separated | Group-dependent |
| Owner/cluster administrator compromised | Can defeat isolation | Cluster admin can reach all DBs | Cluster admin can reach all DBs | Global admin remains a critical trust boundary; split administration reduces blast radius | Group-level/global admin risk |
| Operational complexity | Lowest | Medium-high | High | Highest | High |
| Per-tenant restore/deletion | More complex | Good | Good | Strongest options | Good within group |
| Capacity efficiency | High | Mixed; connection limits matter | Mixed | Lower at small scale | Configurable |
| Adequate without further controls? | No for Q-021 risk tolerance | No | Not yet demonstrated | Not automatically; requires threat review | Not automatically; requires threat review |

These are qualitative design hypotheses, not measured or test-verified results.

## 4. Recommended next design direction (not an architecture selection)

Investigate **Alt-3 and Alt-5 first**, and retain Alt-4 as the higher-isolation reference point. Do not select Alt-2 alone as the final answer: a separate database per tenant on a shared cluster does not, by itself, solve broad credential theft or cluster-owner compromise.

The next design must explicitly address:
1. No routine runtime identity can enumerate or use all tenant credentials.
2. Tenant credential retrieval is authorized per request/worker boundary, logged, revocable, and tested under application-process compromise assumptions.
3. Migration authority is separated from runtime authority. Prefer tenant-by-tenant migrations using tenant-scoped credentials; any unavoidable global operator capability is documented as a high-trust residual with break-glass controls and audit.
4. Backups, exports, restore tooling, secret manager, deployment pipeline, monitoring, and support access are included in the threat model—not treated as outside scope.
5. Recovery, tenant offboarding, key/credential rotation, emergency stop, and incident notification are operationally testable.
6. Connection count, memory, migration duration, backup/restore time, expected tenant count, and operating cost are estimated and then measured on the target host.
7. Every security claim maps to a threat, control, test contract, evidence owner, and pass criterion.

## 5. Decisions still required before implementation

Do not silently choose a final topology. The Product Owner must approve a specific revised architecture after the independent comparison answers:
- What maximum cross-tenant blast radius is acceptable after compromise of one application worker, the secret store, a cluster administrator, or the deployment pipeline?
- Is a shared PostgreSQL cluster acceptable, or must the threat boundary include separate clusters/accounts?
- What is the target tenant count and acceptable monthly operating/operational burden?
- Is tenant-group isolation acceptable, and if so, what maximum group size?
- Which privileged actions require dual control or time-limited break-glass access?

## 6. Hard gates

- Phase 1 remains **NOT READY / NOT APPROVED** until the revised design is completed and independently reviewed.
- Q-021 option B required stronger architecture. Q-022/D-020 subsequently selected Alt-5; the alternatives here remain comparative history, not the active normative design.
- Phase 2 remains NOT STARTED and NOT AUTHORIZED until the Phase 1 gate is separately approved.
- No real student data until every D-014 pilot condition is met and written Product Owner approval is recorded.
- No code, migration, infrastructure, or runtime test is authorized by this design study.
