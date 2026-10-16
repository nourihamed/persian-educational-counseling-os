# TENANT_ISOLATION_DESIGN.md

Phase: 1 — Architecture & Multi-Tenancy (design only)
Status: DRAFT (revision 2, corrective pass). Design artifact only. No code, migration, role, policy, grant, or infrastructure exists or was created. No test was run. Nothing here is a security proof. Phase 1 is NOT approved by this document.

Binding inputs (accepted decisions, not re-decided here):
- D-009 (ACCEPTED 2026-10-12, answer to Q-001): shared PostgreSQL database/schema; direct `tenant_id NOT NULL` indexed on tenant-scoped rows; authorization in the Application/API layer with PostgreSQL RLS as defense in depth; composite constraints or equivalent for parent/child tenant consistency; Platform Admin cross-tenant access only with explicit, limited, audited permission; "RLS به‌تنهایی کافی نیست".
- D-010 (ACCEPTED): MVP scope per `PROJECT_SCOPE.md`.
- D-008 / Q-012 (ACCEPTED): minimum auditable versioning in MVP.
- D-012 / Q-013 (ACCEPTED): MVP Program Template/Version is tenant-owned; a version belongs to the same tenant as its template.
- TEST_PLAN.md: mandatory tenant isolation test groups; R/A/I test modes; isolated Postgres per test run.

Terminology used throughout:
- **Defense in depth against application defects:** protects against a missing or wrong filter in our own code (developer error, forgotten WHERE clause).
- **Security boundary against an attacker:** an attacker who can execute arbitrary SQL as the runtime database role, or who holds the runtime database credentials, must not be able to read or write another tenant's data. This document does NOT claim that property for the current design (see §2).

---

## 1. Threat Model

### 1.1 Assets
Student personal and educational data (potentially minors), counselor business data, billing ledger, uploaded files, reports and exports, audit records.

### 1.2 Actors and threats

| ID | Actor / threat | Example | Primary control in this design | Covered by RLS session context? |
|---|---|---|---|---|
| T1 | Authenticated user probes IDs in another tenant | Counselor B requests `/students/{A1}` | Application authorization (tenant from principal; object lookup tenant-scoped; §8) | Partially (only if the query reaches the table with context set) |
| T2 | Developer defect: query omits tenant filter | Repository method forgets `WHERE tenant_id` | Repository API requires TenantContext; RLS denies cross-tenant rows | Yes (this is the main intended use) |
| T3 | Developer defect: wrong tenant passed to repository | Service passes B's id while processing A's request | Composite FKs, WITH CHECK on writes, tests TI-REPO | No (context is set to the wrong tenant consistently) |
| T4 | Attacker achieves arbitrary SQL execution as `app_runtime` (SQL injection, RCE in app, stolen runtime DB credentials) | Attacker runs `SELECT set_config('app.current_tenant_id', '<B>', true); SELECT * FROM student;` | Prevent injection (parameterized queries only, static checks, code review), least-privilege grants, secret management, network isolation. The session variable itself is NOT a boundary against T4 | **No.** The attacker can set any tenant value. This is an accepted residual risk of the D-009 mechanism unless §2.3 option D or another boundary is adopted (Q-019). |
| T5 | Misconfigured privileges (owner role, BYPASSRLS, membership, TRUNCATE, views, SECURITY DEFINER) | Runtime role owns tables; TRUNCATE bypasses RLS | Configuration and catalog tests (TI-CFG, TI-BYP) | Depends on config; RLS is not sufficient if misconfigured |
| T6 | Platform operator misuse | Platform admin reads tenant data without permission | Audited access path (§8), no default BYPASSRLS | No |
| T7 | Background job / notification / file pipeline crosses tenants | Job loads tenant B rows while processing A | Job payload tenant binding, per-job context (§9) | Partially |
| T8 | Connection-pool context leakage | Request for B reuses a connection still holding A's setting | Transaction-local context, pooling tests (§6.4) | Yes, if transaction-local settings are used correctly |

### 1.3 What this document asserts
- It mitigates T1, T2, T5 (when configuration tests pass), T7, and T8 (when tests pass).
- It does not mitigate T4 by itself. Mitigation of T4 relies on SQL injection prevention and privilege minimization, and is not a property the session variable provides.
- T3 and T6 are addressed by API/repository design and audited access, not by RLS.

---

## 2. Trust Boundary: What RLS Does and Does Not Prove

### 2.1 Why the current mechanism is not a boundary against arbitrary SQL
The tenant value lives in a session variable (`app.current_tenant_id`) that the runtime role can set with `set_config`. Any code path that can run arbitrary SQL as `app_runtime` can therefore set any tenant value before querying. RLS then faithfully enforces the wrong tenant. The policy is correct; the input it trusts is not authenticated by the database.

### 2.2 Consequences
- Claims of the form "RLS guarantees tenant isolation" are FALSE for this design and must not appear in any document.
- Claims that are TRUE, once the tests pass: RLS prevents accidental cross-tenant access by application code that does not set the right tenant, and prevents cross-tenant access from ordinary queries issued under a correctly set context.
- Preventing T4 is a separate control set (§2.4) and must be reviewed in Phase 3 and Phase 26 (Security Hardening).

### 2.3 Options for a stronger tenant-context boundary (for owner decision, Q-019)

| Option | Mechanism | Resists T4? | Advantages | Costs and risks |
|---|---|---|---|---|
| A (current D-009 design) | `set_config` transaction-local; RLS reads it | No | Simple; works with a shared pool; standard Postgres | Injection can choose any tenant |
| B | Per-tenant database roles; RLS on `current_user`; app switches with `SET ROLE` | Partly. Runtime role needs membership in tenant roles, so injected SQL can also `SET ROLE` to any of them | Familiar model | Role explosion; membership is itself an escalation path; does not solve T4 by itself |
| C | Per-tenant database credentials or per-tenant connection pools | Yes for the connection's tenant. Injection can only reach that tenant's role, provided no other role is reachable | Strongest DB-side separation without separate databases | Pool per tenant; credential management per tenant; operational cost; scales poorly |
| D (candidate, NOT proven) | Tenant context is written only by a `SECURITY DEFINER` function that verifies a signed, short-lived token; policies read a context row that only that function can write (§2.3.1). Policies never read a GUC | Yes, if §2.3.1 requirements are met and reviewed. Not yet proven | Injected SQL cannot forge a tenant without a valid token for that tenant | Complex; dedicated security review required; the function is a bypass surface (TI-BYP-03); key management and token design open |
| E | Separate database or schema per tenant (D-009 rejected this for MVP) | Yes | Strongest isolation | Operationally heavy; contradicts accepted D-009 for MVP |

### 2.3.1 Option D — required design points (candidate; each must be answered before Option D can be evaluated as a boundary)

A `SECURITY DEFINER` function alone does not make Option D work. If a policy still reads `app.current_tenant_id`, `app_runtime` can set that GUC itself and the function adds nothing. Option D therefore requires all of the following:

1. **Token issuance and format.** The application issues the token at authentication. It contains tenant_id, principal_id, issued-at, expiry (short, minutes), audience, and a key identifier. Token issuance and any revocation list are outside application SQL.
2. **Where the signature is verified.** Inside the SECURITY DEFINER function, because a verifier outside the database cannot stop injected SQL from calling a context-writing function with arbitrary values. Consequence: the verification key must be stored in the database, in a table readable only by the function owner role.
3. **What prevents app_runtime from setting context.** Policies do NOT read any GUC. They read a context row. The context row table (`request_tenant_context`) has no INSERT, UPDATE or DELETE grant for `app_runtime`. Only the function owner role can write it, and the function writes it only after successful verification. Rows are keyed by transaction and backend, and are removed at transaction end. A SECURITY DEFINER helper returning the current tenant from that table is a bypass surface and goes on the TI-BYP-03 allowlist.
4. **How the context is validated by policy.** Policy predicate: `tenant_id = current_request_tenant()`, where the helper returns NULL when no valid row exists for the current transaction (fail closed). A static check forbids any policy referencing `current_setting` or any custom GUC.
5. **Key management.** The verification key is generated outside the repository, stored only in the database table readable by the owner role, never logged, never returned by any function, and rotatable with a key identifier in the token. The owner role is not a login role. Residual risk: compromise of the owner role or of a superuser exposes the key; this is recorded, not hidden.
6. **Negative tests (new, only if Option D is chosen):** TI-CTX-15 (runtime cannot write the context table), TI-CTX-16 (runtime cannot obtain a context row for a tenant without a valid token), TI-CTX-17 (valid token for A, then reads of B return zero rows), TI-CTX-18 (setting the GUC changes nothing). Also TI-CFG-13 (no policy references a GUC).

Open points not decided here: token format (HMAC versus asymmetric signature), key storage location within the database, interaction with connection pooling (TI-CTX-11/12 must still pass), and whether a Phase 2 migration is needed to restructure policies.

### 2.4 Recommended approach (proposal, not decision)
- Keep D-009 as the accepted MVP mechanism (Option A) for defense against defects (T1, T2, T5, T7, T8).
- Treat T4 as a named residual risk for MVP. Mitigate it through: parameterized queries only; banning string-built SQL in the codebase with a static check; least-privilege runtime role; no runtime access to migration credentials; secrets outside the repository; network restriction of the database to the application host.
- Before any pilot with real student data, the owner decides whether Option D (or C) is required. This decision is recorded as Q-019 and must be resolved before Phase 26 (Security Hardening) and before any real-data pilot. It is NOT resolved by this document.
- This recommendation does not change D-009.

### 2.5 Claims ledger

| Claim | Status |
|---|---|
| Repository and API design enforce tenant scoping on every tenant-owned query | Designed (this document). Not implemented. |
| RLS denies cross-tenant rows for a correctly configured runtime role with context set | Designed. Requires TI-CTX and TI-CFG tests to pass. |
| Composite keys prevent cross-tenant parent/child links | Designed. Requires TI-DB-FK tests to pass. |
| Runtime role cannot bypass RLS through privileges | Designed. Requires TI-CFG tests to pass. |
| Arbitrary-SQL attacker cannot cross tenants | **NOT claimable.** Residual risk T4 (§2.3, Q-019). |
| Tenant context forgery by arbitrary SQL is prevented by policy | **Not claimable.** Option D (§2.3.1) is a candidate pending review; it is not proven |
| Platform Admin access is limited and audited | Designed as proposal (§8, Q-015). Not decided. |
| Tenant isolation holds in production | **NOT claimable in Phase 1.** |

---

## 3. Principal and Tenant Context (Application Level)

3.1 Request identity comes only from the authenticated principal. The principal resolves to an immutable `TenantContext`:

```
TenantContext {
  tenant_id     : UUID     # derived from the principal's membership / active relationship
  principal_id : UUID
  roles        : set<Role>
  scope        : TENANT | PLATFORM_ADMIN_AUDITED
  request_id   : UUID
}
```

3.2 `tenant_id` values in path, query, or body are never sufficient for authorization. They are untrusted identifiers checked against the resource's real tenant (§8 and `AUTHORIZATION_CONTRACT.md`).

3.3 A Student principal's tenant is the tenant of its single active `CounselorStudent` relationship. A Student with no active relationship has no tenant data scope and receives an empty result for tenant-scoped reads.

3.4 `TenantContext` is immutable for the lifetime of a request or job.

3.5 `PLATFORM_ADMIN_AUDITED` is a distinct scope. It is never implied by a role name.

---

## 4. Layer Responsibilities

| Layer | Responsibility | Must not |
|---|---|---|
| API (routers) | Resolve TenantContext from principal; validate shape; map outcomes to HTTP | Trust path/body tenant IDs; query data directly |
| Application services | Take TenantContext explicitly; enforce object-level authorization and business rules; own transaction boundaries | Use an ambient/global tenant; build raw SQL |
| Repositories (Infrastructure) | Require TenantContext in every method signature; inject tenant filter; set transaction-local DB context once per transaction | Expose unscoped methods for tenant-owned tables; accept tenant IDs from callers without a context object |
| Database | RLS policies on tenant-owned tables; composite constraints; immutable `tenant_id` on tenant-owned rows | Be the only control (see §2) |

Rule: no tenant-owned repository method exists without a required TenantContext parameter. There is no `get_all()` on a tenant-owned repository.

---

## 5. Database Roles and Required Properties

### 5.1 Roles

| Role | Purpose | Owns tenant tables? | Used by |
|---|---|---|---|
| `app_migrator` | Schema migrations only | Yes (owner) | Migration job only; credentials never present in application runtime configuration |
| `app_runtime` | API and workers | **No** | Application runtime |
| `platform_ops` | Audited platform-admin operations (§8); existence decided in Q-015 | No | Platform admin tooling only; not used by normal application requests |

Role names are illustrative; final names are a Phase 2/3 detail.

### 5.2 Required properties of `app_runtime` (each becomes a TI-CFG test)
- R-DB-01: not superuser; no `BYPASSRLS`; no `CREATEROLE`; no `CREATEDB`; no `REPLICATION`.
- R-DB-02: owns no tenant-owned table, view, sequence used for tenant data, or schema containing them.
- R-DB-03: is not a member, directly or through any chain of memberships, of any role with the above privileges or ownership of tenant tables. Checked recursively through `pg_auth_members`.
- R-DB-04: has no `TRUNCATE` privilege on tenant-owned tables. TRUNCATE is not subject to RLS in PostgreSQL, so it is a bypass.
- R-DB-05: has no `CREATE` on schemas containing tenant tables and no DDL privilege.
- R-DB-06: has no `EXECUTE` privilege on any `SECURITY DEFINER` function that touches tenant tables, unless the function is on a reviewed allowlist (TI-BYP-03).
- R-DB-07: effective privileges on each tenant table are checked with `has_table_privilege` and `pg_class` ACLs, not only with configuration files. Only the DML privileges needed by the application are granted.
- R-DB-08: no RULE objects and no row-security-bypassing triggers on tenant tables (`pg_rules`, `pg_trigger`), reviewed.

### 5.3 `FORCE ROW LEVEL SECURITY`
Decision in this revision: FORCE is REQUIRED on every tenant-owned table. Reason: the owner role must not silently bypass policies if it ever connects through a path other than the migration job. Impact: migrations that move tenant data must either run with context set explicitly or be written as reviewed migration steps; this is a Phase 2 design rule, recorded here. If the owner later rejects FORCE, that is a change to this rule and must be recorded as a decision, not a silent exception.

### 5.4 `app_migrator`
- Owns schema objects; runs only in the migration pipeline.
- Its credentials must not appear in application runtime configuration (static check TI-CFG-10).
- Migration pipeline is a privileged surface and is listed in Phase 3 review.

---

## 6. Tenant Context Propagation into PostgreSQL

### 6.1 Mechanism
Inside each transaction, the repository layer sets the context once, before any tenant-owned statement:

```sql
SELECT set_config('app.current_tenant_id', $1, true);  -- transaction-local
```

### 6.2 Policy template (illustrative only; not a migration)

```sql
ALTER TABLE plan ENABLE ROW LEVEL SECURITY;
ALTER TABLE plan FORCE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON plan
  USING      (tenant_id = NULLIF(current_setting('app.current_tenant_id', true), '')::uuid)
  WITH CHECK (tenant_id = NULLIF(current_setting('app.current_tenant_id', true), '')::uuid);
```

### 6.3 Required behavior of the context (each becomes a TI-CTX test)
- Unset setting: no rows visible, no rows writable (fail closed).
- Empty string: same as unset (handled by NULLIF).
- Invalid UUID text (e.g. `'abc'`): the cast raises an error. Requirement: the error is raised, zero rows are returned or written, and the error message contains no tenant data. The application maps it to an internal error, never a data response.
- Context changed within one transaction: the repository API must not allow it. The database would apply the last value. A static check and a repository test enforce a single set per transaction.
- Context outside a transaction: `set_config(..., true)` outside a transaction has no effect beyond the statement; the application must never rely on it. Enforced by static check and TI-CTX-14.
- Commit and rollback: the context does not survive the end of the transaction (TI-CTX-10).

### 6.4 Connection pooling and transaction boundaries
- Transaction-local settings are the only permitted form. Session-level `set_config(..., false)` and `SET` are forbidden in application code (static check).
- Pooler mode (session, transaction, or none) is open question Q-016. The design requires that TI-CTX-11 and TI-CTX-12 pass for the chosen mode.
- A failed transaction must not leave the connection in a state where the next request sees a previous context (TI-CTX-12).

### 6.5 Views, functions, rules
- Views over tenant tables must use `security_invoker = true` (PostgreSQL 15+) or must not exist in MVP (TI-BYP-01).
- `SECURITY DEFINER` functions are forbidden on tenant tables in MVP unless individually reviewed and allowlisted (TI-BYP-03). Note: Option D in §2.3 would require such a function and therefore a dedicated review.
- Materialized views over tenant data must not be readable by `app_runtime`, because RLS does not apply to them (TI-BYP-04).

---

## 7. Relational Integrity Across Tenants

RLS restricts which rows are visible. It does not stop a child row of tenant A from referencing a parent row of tenant B unless the foreign key includes `tenant_id`. Required pattern:

```sql
ALTER TABLE plan ADD CONSTRAINT plan_id_tenant_uq UNIQUE (id, tenant_id);
ALTER TABLE plan_version
  ADD CONSTRAINT plan_version_plan_fk
  FOREIGN KEY (plan_id, tenant_id) REFERENCES plan (id, tenant_id);
```

Required pairs (minimum):
- `ProgramVersion (program_template_id, tenant_id)` → `ProgramTemplate (id, tenant_id)` (D-012)
- `StudentProgramEnrollment (program_version_id, tenant_id)` → `ProgramVersion (id, tenant_id)`
- `StudentProgramEnrollment (student_id, tenant_id)` → `Student (id, tenant_id)`
- `PlanVersion (plan_id, tenant_id)` → `Plan (id, tenant_id)`
- `PlanItem (plan_version_id, tenant_id)` → `PlanVersion (id, tenant_id)`
- `PlanVersion (program_version_id, tenant_id)` → `ProgramVersion (id, tenant_id)`, where the referencing column is nullable. NULL semantics are tested (TI-DB-FK-02).
- `CounselorStudent` references to Counselor and Student with `tenant_id`.

Additional requirement: `tenant_id` on a tenant-owned row is immutable after insert (trigger or equivalent; TI-DB-FK-08). Without this, a row could be moved between tenants with a valid key shape.

Composite keys guarantee tenant consistency at the database level for the listed relations, independent of RLS and of the session context. This is a real database-enforced property, not an application convention.

---

## 8. Platform Admin Cross-Tenant Access (revision 2)

### 8.1 Difference between roles
- Counselor: acts only within its own tenant, via relationships and role permissions.
- Student and Parent: act only on their own objects or explicitly linked objects.
- Platform Admin: operates across tenants for support and operations. This is the only role allowed to see data across tenants, and only under §8.2 rules. A Platform Admin is not a counselor with extra permissions.

### 8.2 Required conditions for any cross-tenant read (proposal, Q-015)
1. Named platform-admin principal with a dedicated platform permission.
2. Stated reason from a controlled list, plus free text.
3. Target `tenant_id` and resource scope explicitly stated.
4. Time-bounded grant (expiry enforced at each request, not only at grant time).
5. Read-only by default. Any write requires a separate permission and its own audit record.
6. Audit record written and committed BEFORE data is returned. If the audit write fails, access is refused. The response is not streamed before the audit commit.
7. Audit record contains: actor, grant id, target tenant, resource ids, reason, request_id, timestamp, result (allowed/denied).

### 8.3 Technical path and trust boundary
- Preferred proposal: a narrow set of audited, read-only application query paths that set the transaction context to the explicit target tenant for each query. Platform admin code paths are separate modules, reviewed separately.
- Alternative: a `platform_ops` role with `BYPASSRLS`. This is NOT the default. It is allowed only if Q-015 owner decision chooses it, and then only with §8.2 applied and a separate configuration test (TI-PLAT-06).
- Under T4 (§2), a platform-admin context does not add a new weakness to the context boundary, but it does increase the impact of an arbitrary SQL attacker if a bypass role exists. This is an explicit reason the default is no bypass role.

### 8.4 Platform jobs
Platform aggregate jobs operate on aggregates or on a per-tenant loop with per-iteration context. They never read unscoped tenant rows.

---

## 9. Surface Rules

| Surface | Rule | Failure addressed |
|---|---|---|
| API | Tenant from principal; object-level check for every resource id; list filtering in SQL | IDOR, post-filter leaks |
| Services | Explicit TenantContext parameter; no ambient tenant | Async context bugs |
| Repositories | Signature requires TenantContext; raw SQL only in Infrastructure; bulk writes tenant-scoped | Unscoped update/delete |
| Reports / exports | Generated inside one tenant transaction; file name and metadata contain only that tenant's identifiers | Cross-tenant export |
| Files | Storage key `tenants/{tenant_id}/…` derived from the stored record; access via short-lived signed URLs issued only after authorization; file metadata is tenant-owned with RLS; direct unsigned URLs are denied | Guessable or shared URLs |
| Notifications | Delivery rows carry tenant_id and recipient; adapters receive one recipient and one tenant's content; status updates tenant-scoped | Message to wrong recipient |
| Background jobs | Payload carries exactly one tenant_id (or the explicit platform marker with aggregate-only access); worker sets context per job; failure leaves no context set (see Q-017) | Cross-tenant processing and retries |
| Audit logs | Append-only for `app_runtime` (no UPDATE/DELETE); tenant-scoped reads; platform events carry actor and target | Missing evidence |
| Version history | `ProgramVersion` and `PlanVersion` are tenant- and student-scoped; published versions immutable (D-008); activation atomic | Cross-tenant version read or write; silent mutation |

---

## 10. Failure Behavior

| Condition | Required behavior |
|---|---|
| TenantContext missing in a repository call | Programming error; raise internal error; no unscoped query |
| DB context unset or empty | No rows; no writes |
| DB context invalid UUID | Error; no rows; no tenant data in error |
| Object exists in another tenant | Same response as for a nonexistent object (status and body); exact status is Q-014 |
| Audit write fails during platform access | Access refused |
| Cross-tenant composite FK violation | Database rejects; application maps to validation error without revealing other tenant's data |
| Job retry after tenant failure | Retry under the same tenant only; never under another |

---

## 11. Non-Goals for Phase 1
- No schema, migration, policy, role, or grant is created.
- No pooler mode, managed host, or storage provider is chosen.
- No Parent access design (Q-007 open).
- No claim of runtime security (§2.5).
- No change to D-009.

---

## 12. Open Decisions Raised by This Design
Recorded in `OPEN_QUESTIONS.md` with status, options, and dependency:
- Q-014: response policy for cross-tenant object access (exact status code)
- Q-015: platform-admin mechanism (audited path vs bypass role)
- Q-016: pooler mode and transaction-local context
- Q-017: background job model
- Q-018: tenant file storage and signed URLs
- Q-019: stronger tenant-context boundary against arbitrary SQL (§2.3, §2.3.1); owner decision required before real-data pilot
