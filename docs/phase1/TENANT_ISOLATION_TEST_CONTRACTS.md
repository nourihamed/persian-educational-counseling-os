# TENANT_ISOLATION_TEST_CONTRACTS.md

Phase: 1 — design-only test contracts (corrective revision following independent review of commit 4715e3d).
Status: SPECIFICATIONS ONLY. No test code exists. No test has been run or passed. Nothing in this file is evidence that isolation works.

---

## 0. Modes, Columns and Rules

### 0.1 Modes (each contract lists the modes it needs)
- **C — Configuration:** checks catalog state of the real test database (roles, ownership, privileges, RLS flags, policies, views). Runs against an isolated test DB built from the same migrations.
- **S — Static:** checks source code and migration files (forbidden patterns, signatures, allowlists). No database needed.
- **R — RLS-only:** database session as the runtime role, repository/application filters deliberately absent in the test harness. Pass means RLS alone blocks the access. The harness must first prove a positive control (same query succeeds with the correct tenant), otherwise a broken harness produces a false pass.
- **A — Application-only:** RLS deliberately neutralized in an isolated test database only (never in any shared or real environment). Pass means application authorization and repository filters alone block the access. A dedicated test role is used for the neutralization; the runtime role is never made privileged.
- **I — Integrated:** normal configuration, RLS and application layers both active. Each negative test also checks that a failure in one layer would be visible on its own (see R and A).

A contract lists every mode it needs. A mode absent from a contract is stated as "—" with a reason in the Notes column only where the reason is not obvious.

### 0.2 CI column
- **PR:** runs on every pull request in CI against an isolated Postgres instance.
- **ENV:<name>:** needs a specific environment (for example a pooler container). Runs in that environment's pipeline; must be green before the phase that owns the feature closes.
- **BLOCKED:<Q-id>:** cannot run until the named open question is decided. A BLOCKED contract prevents closing the phase that owns it.

### 0.3 Standard fixture
- Tenant A: Counselor A1 (principal), Student SA1 (active relationship), Student SA2 (archived relationship), ProgramTemplate TA with ProgramVersion TA-v1 (published) and TA-v2 (draft), Plan PA1 with PlanVersion PA1-v1 and PA1-v2, CreditLedger with positive balance, one stored file FA1, one notification NA1, one report RA1, one export EA1, one audit record AA1.
- Tenant B: mirror objects with the same shape (Counselor B1, Student SB1, ProgramTemplate TB, PlanVersion PB1-v1, file FB1, notification NB1, report RB1, export EB1, audit record AB1).
- Platform admin principal P (no tenant), without grant unless stated.
- Student principal SS1 linked to SA1 only; SS2 linked to SB1 only.
- Parent principal: placeholder only, see TI-API-09.

### 0.4 Negative-test rules
- Every negative test asserts: (a) the denial outcome, (b) zero tenant-B data in the response body, log output, and error message, and (c) a positive control for the correct tenant.
- Cross-tenant "not found" checks compare the response with the response for a nonexistent id of the same type. The contract passes if they are identical in status and body, which is independent of the exact status decided in Q-014.

### 0.5 Security consequence of failure
Every contract states the consequence if it fails. Any failure of a PR-column contract blocks merge.

---

### 0.6 Result Vocabulary (required by independent review)
Every contract has exactly one status at any time:
- **PASS:** executed in its stated CI column or environment; the expected protective result was observed; evidence is stored with the run.
- **FAIL:** executed; protection absent or broken. Blocks the phase that owns the contract.
- **KNOWN-RESIDUAL:** executed or analysed; the attack succeeds because the chosen mechanism does not cover it. Recorded as a documented limitation only after an owner decision in DECISION_LOG.md. **Never PASS.** Reports must count it as a residual risk, not as a security success.
- **BLOCKED:** cannot run; the named open question must be decided first.
- **NOT-RUN:** specified, not executed. **This is the status of every contract in this revision.**
- **SPEC-ONLY:** applies only to the mechanism not selected. Not required, and not PASS.

Rules:
1. A contract that is NOT-RUN or SPEC-ONLY must not be reported as passing, in any document.
2. A known vulnerability must not be recorded as a security PASS.
3. Contracts whose expected result depends on the mechanism state the expected result per option (see TI-ADV-01 and 02).

## 1. Group Index and Counts

| Group | Scope | Count |
|---|---|---|
| TI-CFG | Runtime role and catalog configuration | 14 |
| TI-CTX | Tenant context behavior and pooling | 18 |
| TI-FK | Composite constraints and immutability | 8 |
| TI-BYP | Bypass surfaces: views, functions, TRUNCATE, materialized views, rules | 6 |
| TI-API | API and object-level authorization | 17 |
| TI-REPO | Repository layer used directly | 6 |
| TI-RPT | Reports | 3 |
| TI-EXP | Exports | 3 |
| TI-FILE | Files and storage links | 7 |
| TI-NOTIF | Notifications | 5 |
| TI-JOB | Background jobs | 5 |
| TI-VER | Program and Plan version history | 7 |
| TI-AUD | Audit logs | 3 |
| TI-PLAT | Platform admin cross-tenant access | 10 |
| TI-CONN | Per-tenant connection principals (Option C, selected D-016) | 6 |
| TI-ADV | Adversarial threat-based contracts (T4a, T4b, T4c; credential classes K-L, K-T, K-S, K-O) | 5 |
| **Total** | | **123** |

The total is recomputed from the contract rows below; the verification command is in PHASE1_REPORT.md §3. Mechanism status after D-016: Option C is the preferred design direction, subject to design review. TI-CONN-01 to 06 and TI-CFG-14 apply to Option C; implementation-dependent contracts are BLOCKED until implementation exists. Option D is not selected: TI-CTX-15 to 18 and TI-ADV-04 are SPEC-ONLY. TI-CTX-01 to 10 and TI-CTX-13 to 14 describe the superseded Option A GUC mechanism and are also SPEC-ONLY, not acceptance criteria for Option C. TI-CTX-11 and 12 are retained as future pool-lifecycle checks but their test setup must be revised for direct per-tenant pools, not tenant GUC context. TI-ADV-03 and TI-ADV-05 are evidence, not database tests. No contract is PASS.

---

## 2. Contracts

### 2.1 TI-CFG — Runtime role and catalog configuration

| ID | Modes | Operation | Expected | Failure consequence | CI |
|---|---|---|---|---|---|
| TI-CFG-01 | C | Read `pg_roles` for app_runtime | Not superuser; no BYPASSRLS, CREATEROLE, CREATEDB, REPLICATION | Runtime can bypass RLS | PR |
| TI-CFG-02 | C | Check `pg_tables.tableowner` and view owners for all tenant tables | app_runtime owns none | Owner bypass path | PR |
| TI-CFG-03 | C | Check `pg_class.relrowsecurity` and `relforcerowsecurity` for every tenant table in the allowlist | Both true for every tenant table; exceptions only if listed in a reviewed allowlist | Policies not enforced | PR |
| TI-CFG-04 | C | Check `pg_policies` for each tenant table | Exact expected policy-name set per table; the tenant policy has both USING and WITH CHECK on tenant_id and applies to app_runtime or PUBLIC; no extra policy with a different role scope | Missing policy means unprotected table; an extra permissive policy widens access | PR |
| TI-CFG-05 | C | Recursive `pg_auth_members` from app_runtime | No reachable role with BYPASSRLS, superuser, or ownership of tenant tables | Bypass through membership | PR |
| TI-CFG-06 | C | `has_table_privilege` for app_runtime on each tenant table for each privilege type | Only the DML set in the allowlist (SELECT, INSERT, UPDATE, DELETE as specified per table); nothing else | Excess privileges | PR |
| TI-CFG-07 | C | `has_table_privilege(..., 'TRUNCATE')` for app_runtime on tenant tables | False for all tenant tables | TRUNCATE is not subject to RLS | PR |
| TI-CFG-08 | C | `has_schema_privilege(app_runtime, schema, 'CREATE')` and DDL attempt in test | False; DDL attempt is denied | Runtime can alter schema or policies | PR |
| TI-CFG-09 | C | List EXECUTE grants of app_runtime on functions; check SECURITY DEFINER flag | No SECURITY DEFINER function touching tenant tables is executable, except allowlisted and reviewed ones | Privilege escalation through function owner | PR |
| TI-CFG-10 | S | Scan runtime configuration templates and environment examples for app_migrator credentials | None present | Runtime can run migrations and bypass policy | PR |
| TI-CFG-11 | C | Compare default privileges (`pg_default_acl`) for schemas holding tenant tables | No default privilege grants new tables to app_runtime unless listed | New tables silently exposed | PR |
| TI-CFG-12 | C | Evaluate effective policy set for app_runtime per tenant table, combining permissive policies with OR and restrictive policies with AND | Effective predicate equals tenant_id = context on every table; no permissive policy outside the expected set; each restrictive policy listed and reviewed | Effective access wider than the single policy reviewed | PR |
| TI-CFG-13 | S + C | Scan all policy expressions (`pg_policies.qual`, `with_check`) for references to `current_setting` or custom GUCs | No policy references a GUC (required by §2.3.1 if Option D is chosen; enforced now as a guard) | Policy trusts a forgeable value | PR |
| TI-CFG-14 | C | Check PUBLIC privileges on the database schemas and on all tenant-owned tables and sequences | No PUBLIC privilege on tenant objects; PUBLIC CREATE on schemas revoked | Any role reaches objects through PUBLIC, bypassing role mapping | PR |

### 2.2 TI-CTX — Legacy GUC context contracts and connection-pool lifecycle

**Option A-only contracts:** TI-CTX-01..10 and TI-CTX-13..14 depend on `app.current_tenant_id` / `set_config`, which is NOT the selected Option C mechanism. They are retained for traceability only and must not be implemented or counted as Option C acceptance evidence. TI-CTX-11..12 remain future pool-lifecycle checks but must use per-tenant direct connections for the pilot; transaction-pooler-specific variants are deferred.

| ID | Modes | Operation | Expected | Failure consequence | CI |
|---|---|---|---|---|---|
| TI-CTX-01 | R | Session as app_runtime, context unset, SELECT from tenant table | Zero rows | Fail-open on missing context | SPEC-ONLY (Option A not selected) |
| TI-CTX-02 | R | Context set to empty string, SELECT | Zero rows; no unhandled exception | Fail-open or crash that leaks details | SPEC-ONLY (Option A not selected) |
| TI-CTX-03 | R | Context set to 'not-a-uuid', SELECT | Error raised; zero rows; error text contains no tenant data | Data returned, or tenant data in error | SPEC-ONLY (Option A not selected) |
| TI-CTX-04 | R | Context = A; SELECT rows of tenant B | Zero rows of B; positive control: rows of A visible | Cross-tenant read | SPEC-ONLY (Option A not selected) |
| TI-CTX-05 | R | Context = A; INSERT row with tenant_id = B | Rejected by WITH CHECK; zero rows written | Cross-tenant write | SPEC-ONLY (Option A not selected) |
| TI-CTX-06 | R | Context = A; UPDATE row of tenant B | Zero rows affected; row unchanged | Cross-tenant update | SPEC-ONLY (Option A not selected) |
| TI-CTX-07 | R | Context = A; DELETE row of tenant B | Zero rows affected; row remains | Cross-tenant delete | SPEC-ONLY (Option A not selected) |
| TI-CTX-08 | R | Context = A; UPDATE an A row setting tenant_id = B | Rejected by WITH CHECK; row unchanged | Row moved to another tenant | SPEC-ONLY (Option A not selected) |
| TI-CTX-09 | I | Repository attempts a second context set within one transaction | Repository API refuses; a static check forbids the pattern | Context switch mid-transaction | SPEC-ONLY (Option A not selected) |
| TI-CTX-10 | I | Set context in transaction, then ROLLBACK; new transaction without set | No rows visible; context not carried | Context leaks across transactions | SPEC-ONLY (Option A not selected) |
| TI-CTX-11 | I | Router attempts to return a tenant-A connection to tenant-B pool after A commits | Router refuses reuse; B request can only acquire a B-authenticated connection | Cross-tenant connection reuse | ENV:direct-pool (D-017) |
| TI-CTX-12 | I | Tenant-A request raises an exception mid-transaction; pool cleanup and subsequent tenant-B acquisition are observed | A connection is rolled back/reset and remains exclusively bound to A; B gets only a B-authenticated connection | Cross-tenant connection reuse after failure | ENV:direct-pool (D-017) |
| TI-CTX-13 | S | Static scan: no `set_config(..., false)` and no session-level `SET` for app.current_tenant_id in application code | None present | Context outlives transaction | SPEC-ONLY (Option A not selected) |
| TI-CTX-14 | A | Repository call outside a transaction attempts a tenant query | Repository refuses (no implicit context); no query executed | Query run without context | SPEC-ONLY (Option A not selected) |
| TI-CTX-15 | R | (Option D only) app_runtime INSERT into `request_tenant_context` | Denied | Context forged directly | SPEC-ONLY (Option D not selected, D-016) |
| TI-CTX-16 | R | (Option D only) app_runtime calls the context function with a forged or foreign token | Refused; no context row; zero rows | Forged tenant context | SPEC-ONLY (Option D not selected, D-016) |
| TI-CTX-17 | I | (Option D only) valid token for A, then read rows of B in same session | Zero B rows | Context switch by reuse | SPEC-ONLY (Option D not selected, D-016) |
| TI-CTX-18 | R | (Option D only) set_config of a custom GUC to B while context is A | Policy outcome unchanged; zero B rows | GUC trusted by policy | SPEC-ONLY (Option D not selected, D-016) |

### 2.3 TI-FK — Composite constraints and immutability

| ID | Modes | Operation | Expected | Failure consequence | CI |
|---|---|---|---|---|---|
| TI-FK-01 | I | Insert plan_version with tenant_id = A referencing plan of tenant B | Foreign key violation | Cross-tenant parent/child link | PR |
| TI-FK-02 | I | Insert plan_version with program_version_id NULL | Accepted; no false FK rejection | Valid rows rejected | PR |
| TI-FK-03 | I | Insert plan_version with tenant A and program_version_id of tenant B | Foreign key violation | Cross-tenant version link | PR |
| TI-FK-04 | I | Insert program_version with tenant A referencing template of tenant B (D-012) | Foreign key violation | Cross-tenant template link | PR |
| TI-FK-05 | I | Insert enrollment with tenant A referencing student of tenant B | Foreign key violation | Cross-tenant enrollment | PR |
| TI-FK-06 | I | Insert plan_item with tenant A referencing plan_version of tenant B | Foreign key violation | Cross-tenant plan item | PR |
| TI-FK-07 | I | Insert full valid same-tenant chain: template, version, enrollment, plan, plan version, item | All accepted | Integrity rules too strict | PR |
| TI-FK-08 | I | Update tenant_id of an existing tenant-owned row | Rejected by immutability rule | Row moved between tenants | PR |

### 2.4 TI-BYP — Bypass surfaces

| ID | Modes | Operation | Expected | Failure consequence | CI |
|---|---|---|---|---|---|
| TI-BYP-01 | C | Check `pg_class.reloptions` for security_invoker on every view touching tenant tables | True for all such views; none without it | View executes with owner rights and bypasses RLS | PR |
| TI-BYP-02 | R | Query each allowed view as app_runtime, context = A | Only A rows | View leaks tenant data | PR |
| TI-BYP-03 | S + C | Inventory SECURITY DEFINER functions; compare with reviewed allowlist | Inventory equals allowlist; allowlist entries have review reference | Unreviewed function bypasses RLS | PR |
| TI-BYP-04 | C | Check grants of app_runtime on materialized views over tenant data | No such grant | Materialized views are not covered by RLS | PR |
| TI-BYP-05 | C | Check `pg_rules` and tenant-table triggers that rewrite or redirect queries | None on tenant tables, or each reviewed | Query rewrite bypass | PR |
| TI-BYP-06 | I | Application code path attempting TRUNCATE on tenant table as app_runtime | Denied | Full-table wipe that ignores RLS | PR |

### 2.5 TI-API — API and object-level authorization

| ID | Modes | Operation | Expected | Failure consequence | CI |
|---|---|---|---|---|---|
| TI-API-01 | A | Counselor B1 GET /students/{SA1} | Response identical in status and body to GET of a nonexistent id | Existence of A students revealed | PR |
| TI-API-02 | A | Counselor B1 PATCH plan PA1 | Response identical to nonexistent id; DB unchanged | Cross-tenant write | PR |
| TI-API-03 | A | Counselor B1 DELETE program version TA-v2 | Response identical to nonexistent id; row exists | Cross-tenant delete | PR |
| TI-API-04 | A | Counselor A1 creates plan with student_id of SB1 in body | Generic validation error (same body as nonexistent student); no row created | Cross-tenant link | PR |
| TI-API-05 | A | Counselor A1 enrolls SA1 into program version TB-v1 | Generic validation error; no enrollment row | Cross-tenant enrollment | PR |
| TI-API-06 | A | Token of A1; request path contains tenant B's id in a tenant-scoped route | Path tenant not used for authorization; response contains only A data or same not-found response | Path tenant trusted | PR |
| TI-API-07 | A | Token of A1; create resource with body field tenant_id = B | Field ignored or rejected; stored tenant_id = A | Client-set tenant | PR |
| TI-API-08 | A | Student SS2 GET plan PA1 | Response identical to nonexistent id | Student reads other student's plan | PR |
| TI-API-09 | A | Parent principal GET student SA1 | Pass criterion defined only after Q-007 | Parent over-exposure | BLOCKED:Q-007 |
| TI-API-10 | A | Counselor A1 edits SA2 (archived relationship) | 403; no change | Write after relationship ended | PR |
| TI-API-11 | A | Student SS1 edits plan item not in active PlanVersion | 403 or not-found; no change | Student edits outside active plan | PR |
| TI-API-12 | I | Counselor B1 lists students | Only B students; total equals B count | Count or row leak | PR |
| TI-API-13 | I | Cursor from A's listing used with B's token | Rejected or returns only B; never A rows | Pagination leak | PR |
| TI-API-14 | I | Counselor B1 searches for a name existing only in A | No A results; same response as no-match | Search leak | PR |
| TI-API-15 | I | Error body for cross-tenant id vs nonexistent id, across three endpoint types | Identical status and body in each pair | Enumeration | PR |
| TI-API-16 | I | Update attempt on published ProgramVersion TA-v1 | Rejected (403 or 409, fixed per endpoint); row unchanged | Silent mutation of published version | PR |
| TI-API-17 | I | Counselor A1 edits ProgramTemplate TA; existing PlanVersion PA1-v1 | PA1-v1 byte-identical after edit (D-008) | Existing student plans change silently | PR |

### 2.6 TI-REPO — Repository layer used directly

| ID | Modes | Operation | Expected | Failure consequence | CI |
|---|---|---|---|---|---|
| TI-REPO-01 | S | Inspect repository signatures for tenant-owned entities | Every method takes TenantContext; no method without it | Unscoped access path | PR |
| TI-REPO-02 | A | Repository `get(id)` for SA1 with context B | Returns None (same as nonexistent id) | Cross-tenant read | PR |
| TI-REPO-03 | A | Repository `list()` with context B | Only B rows; positive control with A | Cross-tenant list | PR |
| TI-REPO-04 | A | Repository bulk update with context B on a filter matching A rows | Zero A rows changed | Bulk cross-tenant write | PR |
| TI-REPO-05 | S | Scan code outside Infrastructure for raw SQL touching tenant tables | None present | Filter bypass through raw SQL | PR |
| TI-REPO-06 | A | Repository create with tenant_id of B while context is A | Rejected before write | Write with wrong tenant | PR |

### 2.7 TI-RPT — Reports

| ID | Modes | Operation | Expected | Failure consequence | CI |
|---|---|---|---|---|---|
| TI-RPT-01 | I | Generate report RA1 (student SA1) as A1 | Contains only A data; no B names or ids | Report leak | PR |
| TI-RPT-02 | A | Request report for SB1 as A1 | Response identical to nonexistent id | Cross-tenant report | PR |
| TI-RPT-03 | I | Multi-student report as A1 | Only A students included; totals computed over A only | Aggregate leak | PR |

### 2.8 TI-EXP — Exports

| ID | Modes | Operation | Expected | Failure consequence | CI |
|---|---|---|---|---|---|
| TI-EXP-01 | I | CSV export as A1 | Row set equals A's rows; no B rows | Data leak in export | PR |
| TI-EXP-02 | I | File name and metadata of export EA1 | Contain no B identifiers | Identifier leak | PR |
| TI-EXP-03 | I | Concurrent exports by A1 and B1 | Each file contains only its own tenant rows | Mixed-tenant file | PR |

### 2.9 TI-FILE — Files and storage links

| ID | Modes | Operation | Expected | Failure consequence | CI |
|---|---|---|---|---|---|
| TI-FILE-01 | A | A1 requests signed URL for FB1 | Response identical to nonexistent id; no URL issued | Cross-tenant file access | PR |
| TI-FILE-02 | A | A1 requests a storage key beginning tenants/B/ | Refused; no URL | Path traversal across tenants | PR |
| TI-FILE-03 | I | Signed URL for FA1 used after TTL | Access denied after expiry | Indefinite link validity | PR |
| TI-FILE-04 | R | SELECT file metadata rows as app_runtime, context A | Only A rows | Metadata leak | PR |
| TI-FILE-05 | A | Upload request supplies a storage key that does not match the record's tenant | Rejected; nothing stored | Mis-filed tenant data | PR |
| TI-FILE-06 | I | Direct unsigned storage URL for FA1, no token | Denied | Public file exposure | PR |
| TI-FILE-07 | A | Path for download derived from request field instead of record | Request-supplied path ignored or rejected | Arbitrary object read | PR |

### 2.10 TI-NOTIF — Notifications

| ID | Modes | Operation | Expected | Failure consequence | CI |
|---|---|---|---|---|---|
| TI-NOTIF-01 | I | In-app notification for SA1 created | Delivery row has tenant A; not visible under context B | Cross-tenant notification read | PR |
| TI-NOTIF-02 | A | Adapter invoked for one notification | Adapter receives exactly one recipient and one tenant's content | Fan-out to wrong tenant | PR |
| TI-NOTIF-03 | I | Retry of failed delivery for NA1 | Retry uses A's recipient only | Retry to wrong recipient | PR |
| TI-NOTIF-04 | I | Adapter (Telegram or SMS mock) fails | Core flow still completes; failure recorded with tenant A | Channel failure breaks core or leaks | PR |
| TI-NOTIF-05 | I | Notifications for A and B created in parallel | No row mixes A and B data or recipients | Mixed-tenant delivery | PR |

### 2.11 TI-JOB — Background jobs

| ID | Modes | Operation | Expected | Failure consequence | CI |
|---|---|---|---|---|---|
| TI-JOB-01 | I | Job with payload tenant A | Reads and writes only A rows | Cross-tenant processing | PR |
| TI-JOB-02 | I | Job for A fails mid-way and retries | Retry under A only; no B writes | Retry crosses tenants | PR |
| TI-JOB-03 | A | Job enqueued without tenant_id | Rejected before execution | Unscoped job | PR |
| TI-JOB-04 | I | Platform aggregate job | Output contains aggregates only; no tenant row content | Aggregate job leaks rows | PR |
| TI-JOB-05 | I | Job fails with context set; next job runs on same worker | Next job sets its own context; no leftover context | Context leak in worker | ENV:worker (Q-017) |

### 2.12 TI-VER — Program and Plan version history

| ID | Modes | Operation | Expected | Failure consequence | CI |
|---|---|---|---|---|---|
| TI-VER-01 | A | A1 reads PB1-v1 via API | Response identical to nonexistent id | Cross-tenant plan history read | PR |
| TI-VER-02 | A | Repository read of PB1-v1 with context A | None returned | Cross-tenant history read | PR |
| TI-VER-03 | A | A1 creates PlanVersion for SB1 | Refused; no row created | Cross-tenant plan write | PR |
| TI-VER-04 | A | A1 activates PB1-v2 | Refused; state unchanged | Cross-tenant activation | PR |
| TI-VER-05 | A | A1 reads TB-v1 ProgramVersion | Response identical to nonexistent id | Cross-tenant program read | PR |
| TI-VER-06 | I | Attempt to modify published PlanVersion | Rejected; history unchanged (D-008) | Silent mutation | PR |
| TI-VER-07 | I | Activation of a new version fails midway | No partial state: enrollment and plan pointer both old or both new | Inconsistent plan state | PR |

### 2.13 TI-AUD — Audit logs

| ID | Modes | Operation | Expected | Failure consequence | CI |
|---|---|---|---|---|---|
| TI-AUD-01 | I | A1 performs a state-changing action | Audit row with actor, tenant A, request_id | Missing evidence | PR |
| TI-AUD-02 | I | A1 reads audit rows | Only A rows; AB1 not visible | Audit leak | PR |
| TI-AUD-03 | C | app_runtime attempts UPDATE and DELETE on audit table | Denied for both | Audit tampering | PR |

### 2.14 TI-PLAT — Platform admin cross-tenant access

| ID | Modes | Operation | Expected | Failure consequence | CI |
|---|---|---|---|---|---|
| TI-PLAT-01 | I | Counselor A1 attempts platform cross-tenant read | Refused; no data | Privilege escalation | PR |
| TI-PLAT-02 | I | Platform admin P without grant attempts cross-tenant read | Refused; no data | Unauthorized operator access | PR |
| TI-PLAT-03 | I | P with grant for tenant A reads SA1 | Succeeds for A only; audit record committed before response | Access without evidence | PR |
| TI-PLAT-04 | I | Audit write fails during P's read | Access refused; no data returned | Unaudited access | PR |
| TI-PLAT-05 | I | P's request followed by a counselor B request on same connection | B request sees no A data | Context leak after platform access | ENV:pooler (Q-016) |
| TI-PLAT-06 | C | Check that no application or platform role has BYPASSRLS, and that no role named `platform_ops` exists | None has BYPASSRLS; no `platform_ops` role (D-013) | Silent bypass path created | PR |
| TI-PLAT-07 | I | P's grant expires; P attempts read | Refused after expiry | Standing access | PR |
| TI-PLAT-08 | I + S | Platform admin attempts any write through any platform path; static scan for platform write routes | Refused; no change; no platform write route exists (D-013, MVP read-only) | Operator write path | PR |
| TI-PLAT-09 | I | Denied requests: no grant; expired grant; invalid reason or unknown target tenant | Each refused with generic error; no tenant data; denial audited with result = denied | Silent denial, no evidence | PR |
| TI-PLAT-10 | I | Audit path unavailable during an otherwise valid platform read | Request denied; no data returned (D-013 point 6) | Unaudited access on audit failure | PR |

---

### 2.15 TI-CONN — Per-tenant connection principals (contracts apply only if Option C is selected for Q-019)

| ID | Modes | Operation | Expected | Failure consequence | CI |
|---|---|---|---|---|---|
| TI-CONN-01 | I | Connection bound to tenant A's role issues SET ROLE to tenant B's role, or reads B rows | Denied; zero B rows | Role switch across tenants | BLOCKED:implementation (Option C, D-016) |
| TI-CONN-02 | C | Check membership graph: no tenant role is a member of, or has membership in, another tenant role or any platform role | Empty set of cross-role memberships | Role lattice escape | BLOCKED:implementation (Option C, D-016) |
| TI-CONN-03 | I | Request for tenant A is routed by application code to a connection bound to tenant B (fixed fixture) | Routing mismatch refused before SQL is sent | Wrong connection used | BLOCKED:implementation (Option C, D-016) |
| TI-CONN-04 | I | Offboarding of tenant A (D-016 point 6): login disabled; active sessions and pooled connections of the role terminated; no request routed to them afterwards; audit records remain | No successful login or query after disable; sessions terminated; audit intact | Access after offboarding | ENV:pooler (Phase 3) |
| TI-CONN-05 | C | Ownership check: no tenant role owns any shared application object (tables, views, functions, sequences, schemas) | None owned by any tenant role | Tenant role controls shared objects | PR (Phase 2-3) |
| TI-CONN-06 | S + C | Identity mapping: every tenant has a distinct login role; no code path or configuration uses one runtime identity for several tenants (D-016 point 7) | One-to-one mapping; no shared identity | Shared-identity capacity workaround | PR (Phase 2-3) |

### 2.16 TI-ADV — Adversarial threat-based contracts (added Revision 4 per T4 decomposition)

| ID | Modes | Operation | Expected | Failure consequence | CI |
|---|---|---|---|---|---|
| TI-ADV-01 | I | T4a: attacker-controlled SQL on tenant A's runtime connection sets context to B and reads B rows | Option C pass criterion: denied at the role boundary (NOT-RUN). Option D pass criterion: denied without a valid token (NOT-RUN). Option A: KNOWN-RESIDUAL (attack succeeds; recorded, never PASS). Expected results for the unselected options are SPEC-ONLY | Silent acceptance of cross-tenant read | BLOCKED:implementation (Option C, D-016); Option D part SPEC-ONLY |
| TI-ADV-02 | I | Credential classes K-L-1 (one stolen runtime login) and K-L-N (all runtime logins), used from outside the application to read rows of tenant B. Same object and same attacker assumption for every option (Q019 §4.4.2) | Option A: K-L-1 KNOWN-RESIDUAL; K-L-N KNOWN-RESIDUAL. Option C: K-L-1 pass criterion (NOT-RUN): tenant A's login denied on B rows; K-L-N KNOWN-RESIDUAL. Option D: K-L-1 and K-L-N pass criterion (NOT-RUN): zero rows with no token, conditional on the §4.4.3 conditions being verified. No result is PASS unless executed and observed | Undetected credential-scope failure | BLOCKED:implementation (Option C, D-016) |
| TI-ADV-03 | — | T4b: process-isolation evidence (no single process holds routing to all tenant credentials; secret scope review) | Evidence document reviewed, not a database test | Unrecognized process-level exposure | ENV:security-review (Phase 26) |
| TI-ADV-04 | I | Credential class K-T (Option D only): a valid token of tenant A is captured and replayed against the verification function after expiry, and within TTL (Q019 §4.4.5) | After expiry: pass criterion (NOT-RUN): refused. Within TTL: KNOWN-RESIDUAL for the holder of tenant A's token (reads of A only; B denied). Options A and C: not applicable (no tokens) | Replay beyond TTL or cross-tenant token use | SPEC-ONLY (Option D not selected, D-016) |
| TI-ADV-05 | — | Credential classes K-S (signing key; Option D only, Q019 §4.4.6) and K-O (owner or migrator role; all options, §4.4.7) | Not a database contract. Evidence required: key-storage review for Option D (HMAC versus asymmetric), owner-role separation and access review for all options. Recorded as KNOWN-RESIDUAL until process controls exist | Undetected key or owner exposure | ENV:security-review (Phase 3 and 26) |

## 3. Coverage and Gate Rules
- The path inventory `docs/phase1/TENANT_PATH_INVENTORY.md` maps each data path to contracts. Any path marked UNMAPPED blocks Phase 1 review.
- Tenant isolation paths: 100% of documented paths must have at least one contract; measured by a path inventory (`docs/phase1/` future file), not by line coverage alone.
- Every endpoint contract (`AUTHORIZATION_CONTRACT.md` §7) links at least one TI-API or TI-REPO contract.
- A contract marked BLOCKED prevents closing the phase that owns it. BLOCKED contracts are not counted as passing.
- No contract is considered passing unless it has run and produced its expected result in the stated CI column.

## 4. Remaining Work Before Any Contract Can Count as Passing
1. Implement fixtures and the isolated Postgres harness (Phase 2/3).
2. Implement TI-CFG and TI-CTX first; they validate the foundation for all other groups.
3. Resolve BLOCKED items (Q-007 for Phase 23; Q-019 mechanism before any real-data pilot) and open items Q-016, Q-017 for their owning phases. Q-015 is resolved (D-013).
4. Run the PR-column contracts in CI on a real PR.
