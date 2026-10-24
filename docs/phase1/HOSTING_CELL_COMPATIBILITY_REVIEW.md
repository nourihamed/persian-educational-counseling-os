# Hosting and Cell Compatibility Review — Q-023

**Date:** 2026-10-23  
**Repository:** nourihamed/persian-educational-counseling-os  
**Decision context:** D-011 (hosting objective), D-017 (connection/pool assumptions), D-020 (Alt-5 hybrid isolation cells), D-023 (Level 3 production / Level 4 critical-backup target)  
**Status:** D-023 target accepted; concrete provider/topology compatibility remains OPEN as a pre-hosting deployment gate under D-024.  
**Gate:** Phase 1 provider-neutral design gate APPROVED; this review does not approve a provider, hosted deployment, or real-data pilot.

## 1. Executive finding

D-011's accepted goal (Iran-based initial hosting, portability, low initial cost/complexity, Docker Compose as an initial deployment tool) is not itself incompatible with Alt-5. The unqualified assumption that one shared VPS can host all cells is incompatible with the intended security claim if separate containers or PostgreSQL instances on that host are treated as independent cell boundaries.

Alt-5 requires each cell to have its own PostgreSQL cluster/instance and network boundary. To make the two-tenant-per-cell limit meaningful against a cell-host compromise, each cell's data plane must not share a single host/root trust boundary with all other cells. Docker Compose may remain a packaging/deployment tool within a cell; it is not a security boundary against host/root compromise.

No target provider, instance size, pricing, network topology, account separation, workload profile, or measured capacity data is currently established by the reviewed documents. Therefore this review makes no cost or capacity claim.

## 2. Verified constraints and unresolved assumptions

### Accepted / normative constraints
- D-020 selects Alt-5; Alt-4 (dedicated operational isolation per tenant) is the security reference.
- Initial proposal: no more than two tenants per cell, up to five cells for a provisional ten-tenant cap. Neither figure proves capacity or authorizes a pilot.
- Each cell requires its own distinct host/VM and network boundary plus its own PostgreSQL cluster/instance.
- Each tenant requires its own database and tenant-specific runtime credential within its cell.
- Level 3 requires cell-scoped administrative boundaries: a routine administrator for one cell must not automatically administer all other cells; separate cloud accounts/projects or demonstrably equivalent controls must be evaluated. Shared organization/root administrators remain an explicit residual.
- Level 4 requires critical backups outside ordinary production-account administrative control, with independently controlled backup administration, encryption keys, deletion/retention controls, and verified restore procedures.
- Routine migration identity, secret access, backup access/keys, and recovery permissions must be scoped; no routine global data-capable migrator/owner.
- Global host/cloud/root compromise and compromise of all usable credentials remain catastrophic residual scenarios.
- D-014 continues to prohibit real student data until all implementation, security-test, capacity, incident-drill, and written-approval gates are satisfied.

### Unresolved
- Which concrete provider/account/host profile can implement the accepted Level 3/Level 4 requirements. Per the Product Owner's instruction, provider comparison and selection are deferred until hosted deployment planning; no provider-specific claim is made here.
- Whether the application/API/control plane is shared, and how it is prevented from holding or enumerating every tenant/cell credential.
- Whether deployment credentials, cloud organization administrators, backup administrators, encryption keys, and monitoring accounts can reach all cells.
- Whether the eventual hosting candidate supports private networking, scoped identities, independently administered backups, restore tests, and required availability.
- Actual cost per cell and the operational cost of maintaining up to five cells.
- The correct connection budget after tenant-scoped workers, per-tenant pools, per-cell clusters, migration/admin connections, monitoring, and recovery processes are defined.

## 3. Options compared

| Option | Topology | Security boundary / blast radius | Cost and operations | Assessment |
|---|---|---|---|---|
| A — One VPS, multiple Compose stacks | All cells and control plane on one host; separate containers/databases/networks | Host/root compromise can reach every cell. Container or network separation on one host does not meet the intended cell-host isolation claim. | Lowest initial complexity/cost; simple to operate. | **Not acceptable as the Alt-5 cell-isolation claim.** Could only be used if the Product Owner explicitly accepted a materially weaker threat model and changed D-020; this review does not recommend that. |
| B — Separate VPS/VM per cell; shared, narrowly privileged control plane | Up to five independently networked cell hosts/VMs; each cell has its own PostgreSQL cluster, tenant DBs and scoped workers/secrets. Shared control plane deploys but does not routinely read tenant data or enumerate tenant credentials. | Cell host compromise is intended to be contained to at most two tenants in that cell, assuming credentials, backups, keys, network rules and administrative paths are genuinely scoped. Shared cloud-account/root compromise remains a global residual unless separately constrained. | Higher cost and operational burden than A; requires provisioning, patching, monitoring, per-cell backup/restore, credential rotation, tenant migration and incident runbooks. | **Recommended starting topology for evaluation**, not yet selected by the Product Owner and not proven secure or capacity-validated. |
| C — Separate cloud accounts/projects per cell, with separate hosts | Cell infrastructure and privileged access are separated across accounts/projects, ideally with a tightly controlled organization-level break-glass path. | Stronger resistance to a single project-level credential compromise; organization/global admin and shared identity-provider compromise remain residuals. | Highest setup and operational complexity among the options shown; potentially higher cost and slower deployments. | Stronger isolation candidate if the threat model requires protection against project-level administrators; cost and operational feasibility unknown. |
| D — Alt-4: dedicated operational isolation per tenant | Separate operational boundary per tenant rather than sharing a cell. | Reduces within-cell cross-tenant blast radius; global platform/cloud/root and shared-control-plane risks still need controls. | Expected highest cost/complexity and more operational units to manage. | Security reference/alternative, not the current selected design. Revisit if two-tenant cell residual risk or evidence is unacceptable. |

The options are architecture patterns, not provider-specific offers. No prices, product capabilities, or vendor assurances have been verified or assumed.

## 4. Recommendation

Evaluate **Option B — a separate host/VM and private network boundary per cell**, with a narrowly privileged shared control plane, as the minimum plausible topology consistent with the current Alt-5 intent. Keep Option C as the stronger account-boundary alternative if the threat model or independent review shows Option B's shared control plane/cloud account is too broad a compromise domain.

Conditions for Option B to be accepted:
1. Each cell's host/VM, network, PostgreSQL instance, runtime identities, secret access, migration identity, backup permissions and encryption keys are scoped to that cell.
2. Ordinary application/worker identities cannot enumerate or retrieve credentials for other tenants or cells.
3. The deployment controller cannot routinely read tenant databases or decrypt backups.
4. Critical backups, keys, deletion/retention controls and backup-administration identities are outside ordinary production-account control; a production-account compromise alone cannot destroy all recovery copies.
5. Cross-cell break-glass is time-limited, dual-approved, ticketed, auditable, revocable and followed by review.
6. Global cloud/root/organization-admin compromise is documented as a residual, with mitigations and detection; do not claim it is impossible.
7. Cost and capacity are assessed on the actual proposed target environment before any real-data pilot.

This is a technical recommendation only. It does not silently change D-011 or select the hosting topology on behalf of the Product Owner.

## 5. D-017 connection/pool assumption review

D-017's previous estimate (10 tenants × 6 application processes × pool size 1, plus a reserve) was an estimate for the earlier connection topology. It must not be reused as a validated Alt-5 capacity number.

Under Alt-5, the connection budget must be calculated **per cell and per PostgreSQL instance**, using the actual number of tenant-scoped worker processes, whether any process serves more than one tenant, pool size, migration/admin/monitoring connections, failover/restore headroom, and the configured PostgreSQL connection/memory budget. Summing across five cells is useful for total cost/operations, but each cluster's local max-connections and memory ceiling must be checked separately. Pool size 1 per tenant per process remains a constraint from D-017 until the Product Owner changes it; it is not evidence that the design fits.

No new pooler mode is selected by this review. Transaction pooling remains outside the current accepted D-017 design unless separately decided and compatibility-tested.

## 6. Cost and capacity evidence required

No numeric estimate is defensible until the target provider/instance type and workload assumptions are supplied. Before any capacity claim, prepare a reproducible worksheet for up to five cells / ten tenants including:
- Per-cell compute, RAM, storage, network and PostgreSQL connection/memory budget.
- Number of API/worker processes per tenant and per cell, pool sizes, background jobs, monitoring and admin connections.
- Expected and peak request rate, concurrent sessions, query profile, data growth, backup size, restore-time target and recovery-point target.
- Monthly infrastructure and backup/egress cost; deployment/monitoring labor and incident-response overhead.
- Load test, failure-containment test, backup restore and tenant-suspension/offboarding preservation results on the actual target environment.
- Headroom and explicit stop/go thresholds. If a cell fails the target, reduce tenants per cell, resize, or revisit Alt-4; do not increase the two-tenant limit without a separate Product Owner decision.

All of the above is **NOT MEASURED / NOT RUN** at this point.

## 7. Product Owner decision — D-023 target accepted; provider topology still open

The Product Owner has selected the following target:
- **Production:** Level 3 infrastructure and administrative independence for isolation cells.
- **Critical backups/recovery:** Level 4 independent administrative/control boundary.

The target is specified normatively in DECISION_LOG.md D-023. It does not mean Option B or C in this review is already selected, and it does not establish that a provider can meet the target.

**Next evaluation (deferred provider work):** during hosted deployment planning, compare concrete candidates against this already-defined provider-neutral acceptance baseline; determine whether organization/root identities can administer all cells; verify that production cannot delete/alter all critical backups or control all keys; and measure cost/capacity. If no candidate meets the target, return to the Product Owner with explicit options and residual risks. No provider has been selected or validated. The architecture-level requirements and their residual risks are specified in D-020/D-023 and `TENANT_ISOLATION_DESIGN.md`; the unresolved Q-023 gate remains open until the required independent review and candidate-compatibility evidence exist.

## 8. Gate and scope

- No code, migration, infrastructure, secrets, database roles, grants, policies, or executable tests were created by this review.
- No vendor or price has been selected or verified.
- No capacity has been measured and no test is claimed as executed or passed.
- Phase 1 design-only gate is APPROVED under D-024 after independent review of provider-neutral requirements and residual risks. Provider comparisons are deferred as requested; Q-023 remains OPEN and must be closed with candidate compatibility evidence before hosted deployment. This does not waive D-023 or D-014.
- PR #3 must remain open and unmerged pending independent review.
- Phase 2 and real student data remain prohibited under D-014.
