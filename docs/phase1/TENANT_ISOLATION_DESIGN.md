# TENANT_ISOLATION_DESIGN.md

Phase: 1 — Architecture & Multi-Tenancy (design only)
Status: DRAFT — corrective revision following independent review of commit 4715e3d. Design artifact only. No code, migration, role, policy, grant, or infrastructure exists or was created. No test was run. Nothing here is a security proof. Phase 1 is NOT approved by this document.

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
| T1 | Authenticated user probes IDs in another tenant | Counselor B requests `/students/{A1}` | Application authorization (tenant from principal; object lookup tenant-scoped; §8) | Defense in depth if the request is routed to the correct tenant login; routing mismatch must fail closed |
| T2 | Developer defect: query omits tenant filter | Repository method forgets `WHERE tenant_id` | Repository API requires TenantContext; RLS denies cross-tenant rows | Yes (this is the main intended use) |
| T3 | Developer defect: wrong tenant passed to repository | Service passes B's id while processing A's request | Composite FKs, WITH CHECK on writes, tests TI-REPO | No (context is set to the wrong tenant consistently) |
| T4a | Arbitrary SQL via SQL injection in a request path, executed as the tenant's own runtime connection | Injected SQL runs `set_config('app.current_tenant_id', '<B>', true)` then reads B | Prevent injection (parameterized queries, static checks). Option A: none beyond prevention. Option C: role boundary (TI-CONN). Option D: context token | **No under Option A.** Covered by Option C for the single-tenant-connection case, if TI-CONN passes |
| T4b | Code execution inside the application process (RCE, dependency compromise, debugger access) | Process holds all pools or all credentials and issues queries for any tenant | Not controlled by any database option in this design. Requires process isolation, dependency control, secret management (Phase 3 and Phase 26) | **No, for every option.** Stated explicitly; not claimable |
| T4c | Theft or misuse of database credentials | Stolen runtime credentials used directly from outside the application | Option A: none beyond secret management. Option C: credentials are per tenant, so one theft exposes one tenant; a theft of many tenant credentials exposes many. Option D: token key must be stored in the database and is exposed to the owner role | **Partly.** Option C limits blast radius to credential scope; not a full defense |
| T5 | Misconfigured privileges (owner role, BYPASSRLS, membership, TRUNCATE, views, SECURITY DEFINER) | Runtime role owns tables; TRUNCATE bypasses RLS | Configuration and catalog tests (TI-CFG, TI-BYP) | Depends on config; RLS is not sufficient if misconfigured |
| T6 | Platform operator misuse | Platform admin reads tenant data without permission | Audited access path (§8), no default BYPASSRLS | No |
| T7 | Background job / notification / file pipeline crosses tenants | Job loads tenant B rows while processing A | Job payload tenant binding, per-job context (§9) | Partially |
| T8 | Connection-pool context leakage | Request for B reuses a connection still holding A's setting | Transaction-local context, pooling tests (§6.4) | Yes, if transaction-local settings are used correctly |

### 1.3 What this document asserts
- It mitigates T1, T2, T5 (when configuration tests pass), T7, and T8 (when tests pass).
- It does not mitigate T4 by itself. Mitigation of T4 relies on SQL injection prevention and privilege minimization, and is not a property the session variable provides.
- T3 and T6 are addressed by API/repository design and audited access, not by RLS.

---

### 1.4 T4 decomposition (required by independent review, Revision 4)
Each sub-threat has different attacker assumptions and a different trust boundary. No single claim covers T4 as a whole.

| Sub-threat | Attacker assumption | Boundary crossed | Controls that can address it | Evidence required before any claim |
|---|---|---|---|---|
| T4a SQL injection on tenant connection | Attacker controls SQL text on one request path; no application code change | Query text → database session | Parameterized queries; static ban on string-built SQL; per-tenant database principal (Option C); signed context function (Option D) | TI-ADV-01 run against the chosen mechanism; TI-CONN or TI-CTX-15..18 |
| T4b Application process compromise | Attacker executes code inside the application process | Process → everything the process holds | Process isolation, dependency control, minimal secret exposure, no all-tenant credentials in the request process (Option C reduces, does not remove) | TI-ADV-03 (process isolation evidence, Phase 26); not a database test |
| T4c Credential theft (classes K-L login, K-T token, K-S signing key, K-O owner or migrator; see Q019_MECHANISM_EVALUATION.md §4.4) | Attacker obtains one stolen secret of a named class outside the application | Network → database login; token → verification function; key store → token minting; owner login → schema and policy changes | Per-tenant credentials (Option C); short-lived or rotated credentials; network restriction to the application host (D-011 pilot host) | TI-ADV-02 run against the chosen mechanism; secret-management evidence |

Consequence: "Option C closes T4a for one tenant connection" is a claim about T4a only. It does not close T4b and does not close multi-tenant credential theft under T4c.

---

## 2. Trust Boundary: What RLS Does and Does Not Prove

### 2.1 Why the current mechanism is not a boundary against arbitrary SQL
The tenant value lives in a session variable (`app.current_tenant_id`) that the runtime role can set with `set_config`. Any code path that can run arbitrary SQL as `app_runtime` can therefore set any tenant value before querying. RLS then faithfully enforces the wrong tenant. The policy is correct; the input it trusts is not authenticated by the database.

### 2.2 Consequences
- Claims of the form "RLS guarantees tenant isolation" are FALSE for this design and must not appear in any document (see §2.5, NOT CLAIMABLE).
- Claims that are TRUE, once the tests pass: RLS prevents accidental cross-tenant access by application code that does not set the right tenant, and prevents cross-tenant access from ordinary queries issued under a correctly set context.
- Preventing T4 is a separate control set (§2.4) and must be reviewed in Phase 3 and Phase 26 (Security Hardening).

### 2.3 Options for a stronger tenant-context boundary (historical comparison; current direction in §2.4)

| Option | Mechanism | Resists T4? | Advantages | Costs and risks |
|---|---|---|---|---|
| A (current D-009 design) | `set_config` transaction-local; RLS reads it | No | Simple; works with a shared pool; standard Postgres | Injection can choose any tenant |
| B | Per-tenant database roles; RLS on `current_user`; app switches with `SET ROLE` | Partly. Runtime role needs membership in tenant roles, so injected SQL can also `SET ROLE` to any of them | Familiar model | Role explosion; membership is itself an escalation path; does not solve T4 by itself |
| C | Per-tenant database credentials or per-tenant connection pools | Yes for the connection's tenant. Injection can only reach that tenant's role, provided no other role is reachable | Strongest DB-side separation without separate databases | Pool per tenant; credential management per tenant; operational cost; scales poorly |
| D (candidate, NOT proven) | Tenant context is written only by a `SECURITY DEFINER` function that verifies a signed, short-lived token; policies read a context row that only that function can write (§2.3.1). Policies never read a GUC | Yes, if §2.3.1 requirements are met and reviewed. Not yet proven | Injected SQL cannot forge a tenant without a valid token for that tenant | Complex; dedicated security review required; the function is a bypass surface (TI-BYP-03); key management and token design open |
| E | Separate database or schema per tenant (D-009 rejected this for MVP) | Yes | Strongest isolation | Operationally heavy; contradicts accepted D-009 for MVP |

### 2.3.1 Option D — required design points (NOT SELECTION-READY; see Q019 §6.3 for the seven open points and their decision owners)

A `SECURITY DEFINER` function alone does not make Option D work. If a policy still reads `app.current_tenant_id`, `app_runtime` can set that GUC itself and the function adds nothing. Option D therefore requires all of the following:

1. **Token issuance and format.** The application issues the token at authentication. It contains tenant_id, principal_id, issued-at, expiry (short, minutes), audience, and a key identifier. Token issuance and any revocation list are outside application SQL.
2. **Where the signature is verified.** Inside the SECURITY DEFINER function, because a verifier outside the database cannot stop injected SQL from calling a context-writing function with arbitrary values. Consequence: the verification key must be stored in the database, in a table readable only by the function owner role.
3. **What prevents app_runtime from setting context.** Policies do NOT read any GUC. They read a context row. The context row table (`request_tenant_context`) has no INSERT, UPDATE or DELETE grant for `app_runtime`. Only the function owner role can write it, and the function writes it only after successful verification. Rows are keyed by transaction and backend, and are removed at transaction end. A SECURITY DEFINER helper returning the current tenant from that table is a bypass surface and goes on the TI-BYP-03 allowlist.
4. **How the context is validated by policy.** Policy predicate: `tenant_id = current_request_tenant()`, where the helper returns NULL when no valid row exists for the current transaction (fail closed). A static check forbids any policy referencing `current_setting` or any custom GUC.
5. **Key management.** The verification key is generated outside the repository, stored only in the database table readable by the owner role, never logged, never returned by any function, and rotatable with a key identifier in the token. The owner role is not a login role. Residual risk: compromise of the owner role or of a superuser exposes the key; this is recorded, not hidden.
6. **Negative tests (new, only if Option D is chosen):** TI-CTX-15 (runtime cannot write the context table), TI-CTX-16 (runtime cannot obtain a context row for a tenant without a valid token), TI-CTX-17 (valid token for A, then reads of B return zero rows), TI-CTX-18 (setting the GUC changes nothing). Also TI-CFG-13 (no policy references a GUC).

Open points not decided here (classification: NOT SELECTION-READY): token signature (HMAC versus asymmetric; asymmetric keeps no minting key inside the database), key storage and access model, token format and replay control (jti store is database state), context-row lifecycle under pooling, policy helper and migration, the SECURITY DEFINER function contract, and failure behavior. Each is listed in Q019 §6.3 with its decision owner.

### 2.4 Decided direction and technical candidates (D-014, D-016)

**Owner decisions:**
- D-014 (2026-10-15): strengthen the tenant-context boundary before any pilot with real student data. The pilot rule is unchanged.
- D-016 (2026-10-17): **Option C is the preferred design direction**, subject to completing the design review. **Option D is not selected** and remains NOT SELECTION-READY (Q019 §6.3).

**Status of Option C:** design direction only. Not implemented, not test-verified, not proven. It is NOT a runtime security claim.

**Option C design summary:**
- Each tenant has its own database login role with no membership in any other tenant role and no membership in any platform role.
- The application selects the connection (pool) from the authenticated principal's tenant before any SQL is sent (TI-CONN-03).
- Policies identify the tenant from the authenticated PostgreSQL login through an owner-managed mapping table. The allowlisted helper uses `session_user` because `current_user` changes inside SECURITY DEFINER; for direct tenant connections, the authenticated login is the tenant identity. No policy reads a GUC.
- PUBLIC privileges on tenant objects are revoked (TI-CFG-14).
- Pools are bounded, lazily created per tenant, and closed when idle (§5.5).
- Tenant role lifecycle, including suspension and offboarding, is specified in §5.5.

**Limitations (explicit, unchanged):** Option C addresses only T4a for a single tenant connection, and partly T4c. It does NOT address T4b (code execution in the application process, which holds routing to many tenant connections). It does NOT address theft of credentials for many tenants (K-L-N). It does NOT address owner-role compromise (K-O). Any claim beyond T4a for a single tenant requires the controls of §1.4 and their evidence.

**Option D:** not selected. NOT SELECTION-READY (Q019 §6.3). Re-consideration requires that its seven design-critical points be resolved and independently reviewed; if reconsidered, asymmetric signatures are evaluated first, and the one-time versus reusable token decision and the `jti` replay policy must be explicitly decided (D-016 point 3).

**Documents that must not change without a new decision:** D-009 (shared database and schema; RLS as defense in depth). Option C changes how the runtime authenticates per tenant but keeps the shared database and schema.

### 2.5 Claims ledger

Status vocabulary (each claim has exactly one current status):
- **DESIGNED:** a requirement or mechanism is written down in this repository.
- **REVIEWED (document-level):** an independent reviewer has examined the written statement. This is not a security test.
- **IMPLEMENTED:** code, roles, policies or constraints exist in an environment. None exists yet.
- **TEST-VERIFIED:** a contract was executed and passed, with evidence. None has been executed.
- **NOT CLAIMABLE:** must not be stated as true under the current design.

| Claim | Current status |
|---|---|
| Tenant-owned queries are required to be tenant-scoped (repository and API design) | DESIGNED. REVIEWED (document-level). Not implemented. Not test-verified |
| Option C RLS policies restrict rows by the authenticated tenant login mapping (via reviewed helper; `session_user` inside SECURITY DEFINER) | DESIGNED. Not implemented. Not test-verified (TI-CFG/TI-CONN pending). Legacy GUC contracts TI-CTX-01..10 and 13..14 are SPEC-ONLY for Option A |
| Composite keys prevent cross-tenant parent/child links for the listed relations | DESIGNED. Not implemented. Not test-verified (TI-FK-01..08 pending) |
| Runtime role cannot bypass RLS through privileges | DESIGNED (R-DB-01..08). Not implemented. Not test-verified (TI-CFG-01..14 pending) |
| Platform admin access is read-only, limited and audited | DESIGNED (D-013 decision; §8). Not implemented. Not test-verified (TI-PLAT pending) |
| Tenant isolation holds in production | NOT CLAIMABLE in Phase 1 |
| RLS alone isolates tenants | NOT CLAIMABLE. RLS is a defense against application defects, not a boundary against arbitrary SQL |
| T4a: SQL injection on a tenant connection cannot cross tenants | NOT CLAIMABLE as a verified property. Option C is the preferred design direction and is designed to limit a single tenant connection to that tenant; this remains unimplemented and untested. Claim only after TI-CONN and TI-ADV-01 pass. Evaluation: Q019_MECHANISM_EVALUATION.md |
| T4b: code execution in the application process cannot cross tenants | NOT CLAIMABLE under any option in this design. Requires process isolation (Phase 3/26) |
| T4c-K-L: a stolen tenant login cannot read other tenants | NOT CLAIMABLE as a verified property. Option C is designed to limit a stolen single-tenant login to that tenant, but this remains unimplemented and untested; require TI-ADV-02 plus catalog/credential-scope evidence |
| T4c-K-T / K-S / K-O: tokens, signing key, owner role | NOT CLAIMABLE under any option. Residuals recorded as KNOWN-RESIDUAL (TI-ADV-04, TI-ADV-05) |
| Credential-scope limits of Option C are as stated in §2.4 | DESIGNED (§2.4). REVIEWED (document-level) only if the independent reviewer confirms. Not implemented |

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
| Repositories (Infrastructure) | Require TenantContext in every method signature; inject tenant filter; select the matching tenant-specific database pool before SQL | Expose unscoped methods for tenant-owned tables; use a shared tenant-data login; accept tenant IDs from callers without a context object |
| Database | Option C: RLS policies resolve tenant from the authenticated per-tenant login via a reviewed helper; composite constraints; immutable `tenant_id` | Be the only control (see §2) |

Rule: no tenant-owned repository method exists without a required TenantContext parameter. There is no `get_all()` on a tenant-owned repository.

---

## 5. Database Roles and Required Properties

### 5.1 Roles

| Role | Purpose | Owns tenant tables? | Used by |
|---|---|---|---|
| `app_migrator` | Schema migrations only | Yes (owner) | Migration job only; credentials never present in application runtime configuration |
| `tenant_login_<tenant>` | Tenant-specific database login used by the API/worker only for that tenant's SQL | **No** | Tenant-specific pool selected from authenticated TenantContext |
| `platform_ops` | **Not created in MVP** (D-013 prohibits a `BYPASSRLS` role for platform-admin access) | — | — |

Role names are illustrative; final names are a Phase 2/3 detail.

### 5.2 Required properties of each tenant login role (each becomes a TI-CFG test)
- R-DB-01: each tenant login is not superuser and has no `BYPASSRLS`, `CREATEROLE`, `CREATEDB`, or `REPLICATION`.
- R-DB-02: tenant login roles own no tenant-owned table, view, sequence used for tenant data, or schema containing them.
- R-DB-03: tenant login roles have no direct or transitive membership in another tenant role, platform role, or role with elevated privileges/ownership. Check recursively through `pg_auth_members`.
- R-DB-04: tenant login roles have no `TRUNCATE` privilege on tenant-owned tables. TRUNCATE is not subject to RLS in PostgreSQL, so it is a bypass.
- R-DB-05: tenant login roles have no `CREATE` on schemas containing tenant tables and no DDL privilege.
- R-DB-06: tenant login roles have no `EXECUTE` privilege on any `SECURITY DEFINER` function that touches tenant tables, except the narrowly scoped, reviewed tenant-mapping helper and any separately approved allowlist entry (TI-BYP-03).
- R-DB-07: effective privileges of every tenant login on each tenant table are checked with `has_table_privilege` and `pg_class` ACLs. Only the required DML privileges are granted.
- R-DB-08: no RULE objects or row-security-bypassing triggers on tenant tables (`pg_rules`, `pg_trigger`), reviewed.

### 5.3 `FORCE ROW LEVEL SECURITY`
Decision in this revision: FORCE is REQUIRED on every tenant-owned table. Reason: the owner role must not silently bypass policies if it ever connects through a path other than the migration job. Migration jobs use a separately controlled owner/migrator identity and reviewed migration steps; they do not rely on a tenant GUC. This is a Phase 2 design rule. If the owner later rejects FORCE, that is a change to this rule and must be recorded as a decision, not a silent exception.

### 5.4 `app_migrator` and application-process identity
- Owns schema objects; runs only in the migration pipeline.
- `app_migrator` credentials must not appear in application runtime configuration (static check TI-CFG-10). The application process must not possess a shared database login with tenant-table access; it receives/uses only the tenant-specific credentials needed by its pool router, under the secret-management controls defined for implementation review.
- Migration pipeline is a privileged surface and is listed in Phase 3 review.

---

### 5.5 Option C tenant role lifecycle and pool strategy (recorded direction, D-016; applies if Option C is implemented)

**Pool strategy (D-016 point 5):** bounded, lazy, per-tenant connections or pools. A pool for a tenant is created on first request for that tenant, is bounded in size per process, and is closed after an idle timeout. Pilot decision (D-017): direct PostgreSQL connections with pool size 1 per tenant per process; no pooler for the pilot. Transaction pooling is deferred and requires TI-CONN-04 to 06 and TI-CTX-11 to 12 to pass and a separate decision.

**Suspension and offboarding (D-016 point 6), in order:**
1. Disable the tenant login immediately (no new sessions).
2. Revoke the relevant access of the tenant role on tenant objects.
3. Terminate active sessions of the role and clear its pooled server connections; no new request may be routed to the tenant's connections.
4. Retain audit evidence. Audit records must not depend on the tenant role remaining present.
5. Drop the role only after: ownership check (no owned objects), dependency check (grants, policies and mapping rows referencing it), and the data-retention requirement is met. The retention period is OPEN (Q-020).

**Ownership rule (D-016 point 6):** tenant roles must not own any shared application object. Verified by TI-CONN-05.

**Shared-identity prohibition (D-016 point 7):** no tenant may share a runtime identity with another tenant. Verified by TI-CONN-06. No capacity workaround may group tenants under one identity.

## 6. Tenant Connection Routing and PostgreSQL Row Security — Normative Option C

**This section is the implementation contract for the preferred direction recorded in D-016.** Option C is a design direction only; no database objects or application code exist yet. The Option A GUC mechanism shown in older revisions is historical and MUST NOT be implemented for the selected Option C design.

### 6.1 Tenant connection selection

The authenticated principal is resolved to an immutable server-side `TenantContext`. Before any tenant SQL executes, the connection router selects the database pool associated with that tenant. The selected connection authenticates as that tenant's dedicated login role. The client must not choose a tenant database role, pool key, or connection string.

Normative rules:
- Each tenant login is distinct and has no membership in another tenant role or platform role.
- The tenant role cannot create roles/databases, alter schema, own tenant/shared objects, or access another tenant's credential.
- There is no shared runtime-role fallback and no request-time `SET ROLE` escalation.
- Routing failure, missing tenant mapping, inactive tenant, or pool/credential mismatch fails closed before tenant SQL.
- Connection routing is an authorization-sensitive component and must be covered by unit, integration, negative, and adversarial tests (TI-CONN-01..06; TI-ADV-01..02).

### 6.2 Policy template (illustrative only; not a migration)

Option C policies derive the tenant from the authenticated PostgreSQL identity through a protected mapping table. They do **not** read a session variable, custom GUC, request parameter, or client-supplied tenant ID.

The normative policy shape is `tenant_id = tenant_id_for_login()`, where the helper has **no tenant-id argument** and resolves the database-authenticated login to exactly one active tenant. Because tenant logins should not receive direct read access to the full mapping table, the helper is a narrowly allowlisted `SECURITY DEFINER` function. It must be owned by a non-login, non-superuser role; use a fixed safe `search_path`; schema-qualify every object; use no dynamic SQL; return NULL when no unique active mapping exists; expose no mapping rows or secrets; and have PUBLIC EXECUTE revoked with EXECUTE granted only to the intended tenant login roles. Its only authority is to read the owner-managed login-to-tenant mapping and return the tenant ID associated with the authenticated connection. The helper must not accept a caller-supplied role or tenant ID.

Illustrative shape only; this is **not executable migration SQL**:

```sql
-- tenant_id_for_login() is a reviewed, fixed-search-path SECURITY DEFINER helper.
-- It resolves session_user (the authenticated login), not a caller-provided identifier.
CREATE POLICY tenant_isolation ON plan
  USING (tenant_id = tenant_id_for_login())
  WITH CHECK (tenant_id = tenant_id_for_login());
```

This is a design sketch, not verified production-ready SQL. The helper is an explicit bypass surface and must be in the TI-BYP-03 allowlist, with negative tests proving it cannot return another tenant's mapping, expose the mapping table, or be repurposed as a cross-tenant read primitive. The map must have a unique constraint on login role; disabled or missing mappings fail closed. PostgreSQL policy behavior, function ownership, grants, owner/bypass paths, and role lifecycle must be proven with migrations and catalog/adversarial tests.

### 6.3 Required behavior for Option C

- A tenant login maps to exactly one active tenant, or no tenant. Missing, duplicate, or inactive mapping fails closed.
- Tenant A's login can read/write only A rows, including when application filters are deliberately omitted (RLS-only positive and negative controls).
- Tenant A's login cannot change its effective tenant by setting a custom GUC, calling `set_config`, supplying a tenant ID, or issuing `SET ROLE`.
- Tenant A cannot assume another tenant role; catalog tests prove no cross-tenant membership path.
- Cross-tenant parent/child references are rejected by composite foreign keys, independent of RLS.
- Platform-admin access follows D-013's separate audited read-only path; it is not granted by tenant-role membership.
- All denial tests include a positive control and verify that no foreign-tenant data appears in response, logs, or errors.

### 6.4 Connection lifecycle and pooling (D-017)

For the pilot, use **direct PostgreSQL connections**, with a bounded per-tenant pool of size **1 per tenant per application process**. No external pooler is used for the pilot. Transaction pooling is deferred and requires a separate decision plus compatibility tests before adoption.

The application must bind each pool to exactly one tenant identity and must not return a connection to a different tenant's pool. On suspension/offboarding, disable login, revoke relevant access, terminate existing sessions and close/remove the tenant pool, preserve required audit evidence, and only drop the role after ownership, dependency and retention review.

Tests TI-CONN-04..06 and the applicable pool lifecycle checks must prove these properties. The capacity arithmetic in Q019 evaluation is an estimate, not measured evidence. The provisional cap of 10 tenants is not a capacity guarantee.

### 6.5 Views, functions, rules
- Views over tenant tables must use `security_invoker = true` (PostgreSQL 15+) or must not exist in MVP (TI-BYP-01).
- `SECURITY DEFINER` functions are forbidden on tenant tables in MVP unless individually reviewed and allowlisted (TI-BYP-03). Note: Option D in §2.3 would require such a function and therefore a dedicated review.
- Materialized views over tenant data must not be readable by tenant login roles, because RLS does not apply to them (TI-BYP-04).

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

Composite keys are designed to guarantee tenant consistency at the database level for the listed relations, independent of RLS and of the session context. This becomes a verified property only when the constraints exist in a migration and TI-FK-01 to 08 pass. Until then it is DESIGNED, not IMPLEMENTED.

---

## 8. Platform Admin Cross-Tenant Access (decided: Q-015 = Option A, D-013)

**Decision (owner, 2026-10-15, D-013):** platform-admin access to tenant data is read-only, limited to explicit Application paths, audited, and does not use a `BYPASSRLS` role. Creating `platform_ops` with `BYPASSRLS` is prohibited for this capability. Write operations by platform admin are prohibited in MVP. This section records the decided design; it is not an implementation and it is not test-verified.

### 8.1 Difference between roles
- Counselor: acts only within its own tenant, via relationships and role permissions.
- Student and Parent: act only on their own objects or explicitly linked objects.
- Platform Admin: operates across tenants for support and operations. This is the only role allowed to see data across tenants, and only under §8.2 rules. A Platform Admin is not a counselor with extra permissions.

### 8.2 Required conditions for any cross-tenant read (decided, D-013)
1. Named platform-admin principal with a dedicated platform permission.
2. Stated reason from a controlled list, plus free text.
3. Target `tenant_id` and resource scope explicitly stated.
4. Time-bounded grant (expiry enforced at each request, not only at grant time).
5. Read-only. Platform-admin write operations are prohibited in MVP (D-013). No write route for platform admin exists; a static check enforces this (TI-PLAT-08).
6. Audit record written and committed BEFORE data is returned. If the audit write fails, access is refused. The response is not streamed before the audit commit.
7. Audit record contains: actor, grant id, target tenant, resource ids, reason, request_id, timestamp, result. Both successful AND denied attempts (no grant, expired grant, invalid request, failed control) are audited, so that denied attempts are visible as evidence.
8. Denied requests fail safely: generic error, no tenant data, no partial result, and the denial is audited when the audit path is available. If the audit path is unavailable, the request is denied.

### 8.3 Technical path and trust boundary (decided)
- Cross-tenant reads only through a narrow set of named, read-only Application query paths. Each path takes an explicit target tenant, sets the transaction context to that tenant, and runs under the grant checks in §8.2.
- Option C has no shared tenant-data runtime login. Every tenant login must satisfy TI-CFG-01 to 08; any application-process role without tenant-table access is outside this tenant-data authorization path.
- `platform_ops` with `BYPASSRLS` is NOT created in MVP. TI-PLAT-06 verifies that no role with `BYPASSRLS` exists for application or platform use.
- Trust boundary: a platform-admin path inherits the same residual risk T4 as all application paths (§2). It does not add a bypass role, so an arbitrary-SQL attacker gains no new cross-tenant capability through this design, beyond what the runtime role already has under D-009.

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
| Background jobs | Payload carries exactly one tenant_id (or the explicit platform marker with aggregate-only access); worker selects only that tenant's connection identity for tenant-owned queries; failure cannot route a connection to another tenant (see Q-017) | Cross-tenant processing and retries |
| Audit logs | Append-only for tenant login roles (no UPDATE/DELETE); tenant-scoped reads; platform events carry actor and target | Missing evidence |
| Version history | `ProgramVersion` and `PlanVersion` are tenant- and student-scoped; published versions immutable (D-008); activation atomic | Cross-tenant version read or write; silent mutation |

---

## 10. Failure Behavior

| Condition | Required behavior |
|---|---|
| TenantContext missing in a repository call | Programming error; raise internal error; no unscoped query |
| Tenant login has no active mapping | No rows; no writes (fail closed) |
| Request tenant and selected database login disagree | Request rejected before tenant SQL; audit event without tenant data leakage |
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
- Q-015: DECIDED (Option A, D-013). Read-only, audited, no bypass role.
- Q-016: direct per-tenant connections for the pilot (D-017); transaction pooling deferred; no GUC-based tenant context in the selected Option C design
- Q-017: background job model
- Q-018: tenant file storage and signed URLs
- Q-019: direction DECIDED (D-014: strengthen before real-data pilot). Mechanism direction DECIDED (D-016): Option C preferred, subject to design review; Option D not selected (NOT SELECTION-READY). Not implemented; not a runtime security claim
