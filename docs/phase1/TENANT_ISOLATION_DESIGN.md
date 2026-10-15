# TENANT_ISOLATION_DESIGN.md

Phase: 1 — Architecture & Multi-Tenancy (design only)
Status: DRAFT for Product Owner review. Design artifact only. No code, migration, role, policy, or infrastructure exists or is created by this document.

Binding inputs (accepted, not re-decided here):
- Master Prompt §3 (tenant isolation is non-negotiable), §48 (security baseline)
- D-009 / Q-001: shared PostgreSQL, direct `tenant_id NOT NULL` indexed on tenant-scoped rows, application authorization plus PostgreSQL RLS as defense in depth
- D-012 / Q-013: MVP `ProgramTemplate` and `ProgramVersion` are tenant-owned only; a version must belong to the same tenant as its template
- D-008 / Q-012: minimum auditable versioning in MVP; `PlanVersion` is tenant- and student-scoped with no exception
- D-010 / Q-002: MVP boundary per `PROJECT_SCOPE.md`

What this document does: turns the accepted mechanism into a concrete, reviewable design (layers, roles, context propagation, constraint patterns, surface rules, failure behavior) and identifies the decisions that still need an owner. What it does not do: prove anything runs. Every claim below is a design requirement until executable tests from `TENANT_ISOLATION_TEST_CONTRACTS.md` pass in a later authorized phase.

---

## 1. Principal and Tenant Context

1.1 Request identity comes only from the authenticated principal (session or token validated by the Auth layer). The principal resolves to a `TenantContext`:

```
TenantContext {
  tenant_id      : UUID        # derived from the principal's active CounselorStudent / Counselor membership
  principal_id  : UUID
  roles         : set<Role>
  scope         : TENANT | PLATFORM_ADMIN_AUDITED
  request_id    : UUID        # correlation for audit
}
```

1.2 `tenant_id` values supplied in a path, query string, or request body are never sufficient for authorization. They are treated as untrusted identifiers to be checked against the resource's real tenant (see §5 and `AUTHORIZATION_CONTRACT.md`).

1.3 A `Student` principal's tenant is the tenant of its single active `CounselorStudent` relationship. Students with no active relationship have no tenant data scope and receive an empty, not erroneous, result for tenant-scoped reads.

1.4 A `TenantContext` is immutable for the lifetime of a request or job. It is never mutated mid-operation and never reused across requests.

1.5 `PLATFORM_ADMIN_AUDITED` scope is a separate, explicit scope (see §6). It is never implied by a role name alone.

---

## 2. Layer Responsibilities

| Layer | Responsibility for isolation | Must not |
|---|---|---|
| API (routers) | Resolve `TenantContext` from the principal; validate input shape; map domain outcomes to HTTP | Query data directly; trust path/body tenant IDs; contain tenant conditions as business logic |
| Application services | Take `TenantContext` as an explicit parameter; enforce object-level authorization and business rules; own transaction boundaries | Read a global/ambient tenant; construct raw SQL |
| Repositories (Infrastructure) | Inject `tenant_id` filter on every query; set the DB tenant session variable inside the transaction (§4) | Expose unscoped query methods to the application layer |
| Database | RLS policies on every tenant-owned table; composite constraints that make cross-tenant parent/child links impossible | Be the only control (RLS alone is insufficient, see §7) |

Rule: the application layer has no API to query tenant-owned data without a `TenantContext`. Repository method signatures require it; there is no `get_all()` on a tenant-owned repository.

---

## 3. Database Roles

Three distinct database roles are required. Names are illustrative; final naming is a Phase 2/3 detail.

| Role | Purpose | Ownership of tenant tables | Attributes |
|---|---|---|---|
| `app_migrator` | Runs Alembic migrations only; never used by the running application | Owns schema objects | Not used at runtime; credentials isolated from app config |
| `app_runtime` | Used by the API and workers | **Must not own** any tenant-owned table | No `BYPASSRLS`, no `SUPERUSER`, no `CREATEROLE`, no `CREATEDB`; only DML grants on the tables it needs |
| `platform_ops` | Reserved for audited platform-admin operations (§6) | Must not own tenant tables | Open question Q-015 decides whether it exists in MVP and how it bypasses or avoids RLS |

Requirements:
- `FORCE ROW LEVEL SECURITY` is enabled on every tenant-owned table, so that even the table owner is subject to policies if it ever connects. The owner role must still not be `app_runtime`.
- The runtime role's effective privileges are verified from catalogs (`pg_roles`, `pg_class.relrowsecurity`, `pg_class.relforcerowsecurity`, `pg_policies`, `information_schema.table_privileges`), not from configuration files alone. This is the basis of test group TI-ROLE in the test contracts.
- Managed-hosting caveat: some managed PostgreSQL offerings grant superuser-like roles. The pilot target (Q-010, Iran-based VPS with Docker Compose) is self-managed, which makes role configuration verifiable. Any future managed host must pass the same TI-ROLE tests before adoption.

---

## 4. Tenant Context Propagation into PostgreSQL

4.1 Mechanism: inside each transaction, the repository layer sets a transaction-local variable before any tenant-owned query:

```sql
SELECT set_config('app.current_tenant_id', $1, true);  -- true = transaction-local (SET LOCAL semantics)
```

4.2 Policy template (illustrative; not a migration):

```sql
ALTER TABLE plan ENABLE ROW LEVEL SECURITY;
ALTER TABLE plan FORCE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON plan
  USING      (tenant_id = NULLIF(current_setting('app.current_tenant_id', true), '')::uuid)
  WITH CHECK (tenant_id = NULLIF(current_setting('app.current_tenant_id', true), '')::uuid);
```

4.3 Fail-closed behavior:
- If the variable is unset, `current_setting(..., true)` returns NULL, so the predicate is NULL and no rows are visible or writable.
- `NULLIF(..., '')` prevents a cast error when the variable is set to an empty string and turns it into the same fail-closed NULL.
- Writes with a `tenant_id` that does not match the context are rejected by `WITH CHECK`.

4.4 Connection pooling: transaction-local settings are the only permitted form. Session-level `SET` (without `LOCAL`) is forbidden in application code because a pooled connection could carry one tenant's context into another tenant's request. Pooler mode (session vs. transaction pooling in PgBouncer or equivalent) is open question Q-016; the design requires that transaction-local context works in whichever mode is chosen, and that a test proves no context leaks between consecutive requests on the same pooled connection (TI-CTX tests).

4.5 Views: any view over tenant-owned tables must be created with `security_invoker = true` (PostgreSQL 15+) or must not exist in MVP. Views owned by a privileged role without `security_invoker` bypass the caller's RLS. This is a named test (TI-DB-VIEW).

4.6 Functions: `SECURITY DEFINER` functions are forbidden on tenant-owned tables in MVP unless individually reviewed, because they run with the owner's privileges and can bypass policies.

---

## 5. Relational Integrity Across Tenants (Composite Keys)

RLS restricts which rows are visible. It does not stop a child row in tenant A from pointing at a parent row in tenant B if the foreign key ignores `tenant_id`. The design therefore requires composite keys wherever a tenant-owned child references a tenant-owned parent.

Pattern:

```sql
-- parent
ALTER TABLE plan ADD CONSTRAINT plan_id_tenant_uq UNIQUE (id, tenant_id);

-- child
ALTER TABLE plan_version
  ADD CONSTRAINT plan_version_plan_fk
  FOREIGN KEY (plan_id, tenant_id) REFERENCES plan (id, tenant_id);
```

Applied to, at minimum:
- `ProgramVersion (program_template_id, tenant_id) → ProgramTemplate (id, tenant_id)` (D-012 requirement)
- `StudentProgramEnrollment (program_version_id, tenant_id) → ProgramVersion (id, tenant_id)`
- `StudentProgramEnrollment (student_id, tenant_id) → Student (id, tenant_id)`
- `PlanVersion (plan_id, tenant_id) → Plan (id, tenant_id)`
- `PlanItem (plan_version_id, tenant_id) → PlanVersion (id, tenant_id)`
- `PlanVersion (program_version_id, tenant_id) → ProgramVersion (id, tenant_id)` where set (nullable FK column: the composite FK is only enforced when the referencing column is non-null; NULL semantics must be tested, TI-DB-FK-02)
- `CounselorStudent (counselor_id, tenant_id) → Counselor (id, tenant_id)` and the student side, as applicable

Every such child table also stores its own `tenant_id NOT NULL`, consistent with the D-009 contract in `DATABASE.md`. The composite FK guarantees that the child's tenant equals its parent's tenant.

---

## 6. Platform Admin Cross-Tenant Access

6.1 Requirement (Master Prompt §5, §3; D-009): platform-level access to tenant data is explicit, least-privileged, and audited.

6.2 Proposed design (requires Q-015 decision before implementation):
- No ordinary admin account gets `BYPASSRLS` or `scope = PLATFORM_ADMIN_AUDITED` by default.
- A cross-tenant read requires: a named platform-admin principal with a dedicated permission, a stated reason, a target `tenant_id`, and a time-bounded grant.
- Each such access writes an audit record (actor, target tenant, resource, reason, request_id, timestamp) before data is returned. If the audit write fails, the access is refused.
- Preferred technical route: a narrow set of audited, read-only SECURITY DEFINER-free query paths in the application, with the tenant context set explicitly to the target tenant. Creating a bypass role is the fallback only if Q-015 chooses it, and then only with the audit requirement above.

6.3 Platform jobs (aggregate metrics, billing reconciliation) must operate on aggregates or on a per-tenant loop with the tenant context set per iteration. They must not read unscoped tenant rows.

---

## 7. Why RLS Is Defense in Depth, Not the Primary Control

RLS is necessary but not sufficient, for these reasons:
- Mis-set or missing context fails closed, but a bug that sets the wrong tenant still passes RLS. Application-level authorization catches IDOR-style cases RLS cannot see (for example, a valid tenant A user requesting a student of tenant A whom they are not assigned to).
- Some operations legitimately need object-level rules (active `CounselorStudent` relationship, student's own plan vs. counselor's plan) that RLS does not express.
- RLS does not protect against a privileged role, a view without `security_invoker`, or a `SECURITY DEFINER` function, which is why §3, §4.5 and §4.6 exist.

Therefore the test contracts require each layer to be tested alone (RLS-only, application-only) and together (integrated), as mandated in `TEST_PLAN.md`.

---

## 8. Surface Rules

| Surface | Design rule | Failure mode addressed |
|---|---|---|
| API | Tenant derived from principal; object-level check on every resource ID; list endpoints apply tenant filter in the query, never post-filter in memory | IDOR, post-filter leaks, pagination leaks |
| Services | Explicit `TenantContext` parameter; no thread-local/global tenant | Ambient-context bugs in async code |
| Repositories | Tenant filter injected; raw SQL forbidden outside Infrastructure; bulk operations must be tenant-scoped | Unscoped `UPDATE`/`DELETE`, bulk-export leaks |
| Reports / exports | Generated inside a tenant-scoped transaction; file name and content contain only that tenant's data; no cross-tenant aggregation in tenant reports | Export of other tenants' rows |
| Files | Storage path namespaced: `tenants/{tenant_id}/...`; the path tenant is derived from the stored record, not from the request; access via short-lived signed URLs generated only after an authorization check; file metadata row is tenant-scoped under RLS | Guessable or shared file URLs, path traversal across tenants |
| Notifications | Delivery rows carry `tenant_id` and recipient; adapters receive one recipient and one tenant's content; no fan-out across tenants in a single adapter call; delivery status updates are tenant-scoped | Message sent to wrong tenant's recipient, duplicate cross-tenant sends |
| Background jobs | Every job payload carries exactly one `tenant_id` (or an explicit `platform` marker with aggregate-only access, §6.3); worker sets the tenant context per job within its transaction; a failed job for tenant A must not retry or write under tenant B's context | Cross-tenant processing, retry leaks |
| Audit logs | Each entry records actor, action, target `tenant_id` (nullable only for pure platform events), request_id; audit rows are append-only | Missing evidence for platform access |

---

## 9. Failure Behavior (Summary)

| Condition | Required behavior |
|---|---|
| Tenant context missing in a repository call | Programming error: raise an internal error; never run an unscoped query |
| RLS session variable unset | Queries return no rows / write nothing (fail-closed) |
| Object exists but belongs to another tenant | Respond as if it does not exist (not-found response), see `AUTHORIZATION_CONTRACT.md` and Q-014 |
| Audit write fails during platform-admin access | Refuse the access |
| Cross-tenant composite FK violation | Database rejects the write; application maps it to a validation/conflict error without revealing the other tenant's data |

---

## 10. Non-Goals for Phase 1

- No schema, migration, RLS policy, role, or grant is created in this phase.
- No choice of PgBouncer mode, managed host, or storage provider.
- No Parent-access design (Q-007 remains open).
- No runtime security claim.

---

## 11. Open Decisions Raised by This Design

Recorded in `OPEN_QUESTIONS.md` with recommended option, alternatives, and impact (per the No-Guessing rule):
- Q-014: Not-found vs. forbidden response for cross-tenant object access
- Q-015: Platform-admin cross-tenant access mechanism (audited query path vs. bypass role)
- Q-016: PostgreSQL connection-pooling mode and its interaction with transaction-local tenant context
- Q-017: Background-job execution model (per-tenant jobs vs. platform aggregate jobs)
- Q-018: Tenant-scoped file storage provider and signed-URL mechanism for the pilot

Until these are answered, the affected parts of Phase 2 and later must not be implemented.
