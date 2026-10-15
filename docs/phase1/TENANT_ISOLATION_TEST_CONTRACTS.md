# TENANT_ISOLATION_TEST_CONTRACTS.md

Phase: 1 — design-only test contracts. No test code exists yet. Nothing in this document has been run.

Purpose: specify the mandatory tenant-isolation tests (Master Prompt §59, `TEST_PLAN.md`, D-009) precisely enough that a later authorized phase can implement them without re-deciding their intent. Each contract states the layer it targets, so a failure can be attributed to RLS, the application layer, or the integration.

---

## 0. Test Modes (from `TEST_PLAN.md`, D-009)

Every data-access contract below is run in three modes:
- **RLS-only (R):** application/repository tenant filters deliberately disabled in an isolated test harness; only the database policy stands. A pass proves RLS denies the access by itself. A harness that is misconfigured and accidentally returns rows through the app layer must not count as a pass.
- **App-only (A):** RLS deliberately neutralized in an isolated test harness (never in a real environment); only application authorization and repository filters stand.
- **Integrated (I):** both layers enabled, normal configuration.

Test environment rules:
- Isolated Postgres instance per test run (TEST_PLAN). Not SQLite.
- RLS-bypass setups use a dedicated test role with the minimum privileges needed and are never applied to any shared or production-like environment.
- The runtime application role is never made privileged to make tests pass.

---

## 1. Standard Fixture

- Tenant A (Counselor A) with Student A1 (active relationship), Student A2 (archived relationship), a Program Template A with two Versions (v1 published, v2 draft), Plan A1 with PlanVersion v1 and v2, a Credit balance, one stored file, one pending notification, one report.
- Tenant B (Counselor B) with mirror objects: Student B1, Program Template B, Plan B1, file, notification, report.
- Platform admin principal P (no tenant).
- Student principal S1 (linked to A1 only). Student principal S2 (linked to B1 only).
- Parent principal (out of MVP scope for detailed tests; included only as a placeholder for TI-API-09 once Q-007 is decided).

Assertion style: every negative test asserts both the response (or zero rows) **and** that no tenant-B data appears in any response body, log line, or error message.

---

## 2. Test Groups

### TI-ROLE — Database role and catalog configuration (no data-access mode)

| ID | Check | Pass criterion |
|---|---|---|
| TI-ROLE-01 | Runtime role attributes | `app_runtime` has no `BYPASSRLS`, `SUPERUSER`, `CREATEROLE`, `CREATEDB` (checked in `pg_roles`) |
| TI-ROLE-02 | Table ownership | No tenant-owned table is owned by `app_runtime` (`pg_tables.tableowner`) |
| TI-ROLE-03 | RLS enabled and forced | Every tenant-owned table has `relrowsecurity = true` and `relforcerowsecurity = true` (`pg_class`); exceptions must be listed and justified in a reviewed allowlist |
| TI-ROLE-04 | Policies present | Every tenant-owned table has a tenant policy with both `USING` and `WITH CHECK` on `tenant_id` (`pg_policies`) |
| TI-ROLE-05 | Runtime grants are minimal | `app_runtime` has no DDL privilege and no grant on tables outside the tenant-owned allowlist (`information_schema.role_table_grants`) |
| TI-ROLE-06 | Membership | `app_runtime` is not a member of any role that has `BYPASSRLS` or ownership of tenant tables (`pg_auth_members`, recursive) |

### TI-CTX — Tenant context propagation and fail-closed behavior

| ID | Mode | Scenario | Pass criterion |
|---|---|---|---|
| TI-CTX-01 | R | Session with no `app.current_tenant_id` set reads `plan` | Zero rows |
| TI-CTX-02 | R | Session with empty-string `app.current_tenant_id` reads `plan` | Zero rows, no cast error |
| TI-CTX-03 | R | Set context to A; read rows of B directly | Zero rows of B |
| TI-CTX-04 | R | Set context to A; insert row with `tenant_id = B` | Rejected by `WITH CHECK` |
| TI-CTX-05 | R | Set context to A; update row of B to change nothing | Zero rows affected |
| TI-CTX-06 | R | Set context to A; delete row of B | Zero rows affected |
| TI-CTX-07 | I | Pooled connection: request for A sets context, commits; next request for B on the same connection with no set | No A data visible to B request |
| TI-CTX-08 | I | Transaction rollback after `set_config(..., true)` | Context does not persist outside the transaction |
| TI-CTX-09 | I | Session-level `SET` (non-local) is never issued by the application | Static check of repository code path; also detected via `pg_stat_statements` or a query log in integration runs (documented as a static + runtime check, not a DB-enforced guarantee) |

### TI-DB-FK — Composite constraint enforcement

| ID | Mode | Scenario | Pass criterion |
|---|---|---|---|
| TI-DB-FK-01 | I | Insert `plan_version` with `tenant_id = A` pointing at `plan` of tenant B | Foreign key violation |
| TI-DB-FK-02 | I | Insert `plan_version` with `program_version_id` NULL | Accepted (NULL is allowed, composite FK not enforced); verify no false rejection |
| TI-DB-FK-03 | I | Insert `plan_version` with `program_version_id` of tenant B, `tenant_id = A` | FK violation |
| TI-DB-FK-04 | I | `program_version` referencing template of another tenant (D-012) | FK violation |
| TI-DB-FK-05 | I | `student_program_enrollment` referencing a student of another tenant | FK violation |
| TI-DB-FK-06 | I | `plan_item` referencing `plan_version` of another tenant | FK violation |
| TI-DB-FK-07 | I | Same-tenant valid chain (template → version → enrollment → plan → version → item) | Accepted |

### TI-DB-VIEW / TI-DB-FN — Bypass surfaces

| ID | Mode | Scenario | Pass criterion |
|---|---|---|---|
| TI-DB-VIEW-01 | I | Each view over tenant tables is created with `security_invoker = true` (checked in `pg_class.reloptions`) | All views pass; none without the option |
| TI-DB-VIEW-02 | R | Query a view as `app_runtime` with context set to A | Only A rows |
| TI-DB-FN-01 | I | Static inventory: no `SECURITY DEFINER` function touches a tenant table | Empty allowlist (or each entry individually reviewed and listed) |

### TI-API — API and object-level authorization (application layer)

| ID | Mode | Scenario | Pass criterion |
|---|---|---|---|
| TI-API-01 | A | Counselor B GETs Student A1 by ID | 404 (Q-014 recommended); no A1 data in body |
| TI-API-02 | A | Counselor B PATCHes Plan A1 | 404; no change in DB |
| TI-API-03 | A | Counselor B DELETEs Program Version A2 | 404; no change |
| TI-API-04 | A | Counselor A creates Plan referencing Student B1 in body | 422 generic message; no row created |
| TI-API-05 | A | Counselor A enrolls Student A1 into Program Version of tenant B | 422 generic message; no row created |
| TI-API-06 | A | Path tenant ID set to B while token belongs to A | Path value not used for authorization; response reflects tenant A only, or 404; no B data |
| TI-API-07 | A | Body contains `tenant_id = B` on create | Field ignored or rejected; created row's tenant equals A |
| TI-API-08 | A | Student S2 reads Plan A1 | 404 |
| TI-API-09 | A | Parent principal reads Student A1 | Placeholder: pass criterion defined when Q-007 is decided |
| TI-API-10 | A | Counselor A (archived relationship with A2) edits A2 | 403; no change |
| TI-API-11 | A | Student S1 edits its own plan item not in active PlanVersion | 403 or 404 per contract; no change |
| TI-API-12 | I | List endpoint for students as Counselor B | Only B's students; total count equals B's count |
| TI-API-13 | I | Pagination cursor from tenant A reused with tenant B token | Rejected or returns B-only data; never A data |
| TI-API-14 | I | Search as Counselor B for a name that exists only in tenant A | No A results |
| TI-API-15 | I | Validation error responses for a cross-tenant ID vs. a nonexistent ID | Byte-identical error bodies (no enumeration) |
| TI-API-16 | I | Published `ProgramVersion` update attempt | 403 or 409; row unchanged |
| TI-API-17 | I | Versioned plan: counselor edits Program Template A; existing Plan A1 unchanged | Existing `PlanVersion` rows byte-identical after edit (D-008) |

### TI-PLAT — Platform admin cross-tenant access

| ID | Mode | Scenario | Pass criterion |
|---|---|---|---|
| TI-PLAT-01 | I | Ordinary Counselor principal attempts platform cross-tenant read | Refused; no data |
| TI-PLAT-02 | I | Platform admin without grant attempts cross-tenant read | Refused |
| TI-PLAT-03 | I | Platform admin with grant reads tenant A | Succeeds only for A; audit record written before response |
| TI-PLAT-04 | I | Audit write fails | Access refused; no data returned |
| TI-PLAT-05 | I | Platform admin access leaves no tenant context set for the next request | Next request isolated (TI-CTX-07 style) |

### TI-JOB — Background jobs

| ID | Mode | Scenario | Pass criterion |
|---|---|---|---|
| TI-JOB-01 | I | Job payload for tenant A processes only tenant A rows | No B rows read or written |
| TI-JOB-02 | I | Job for tenant A fails mid-way and retries | Retry stays in tenant A; no B writes |
| TI-JOB-03 | I | Job payload missing `tenant_id` | Rejected before execution |
| TI-JOB-04 | I | Platform aggregate job | Reads aggregates only; no tenant row content in its output |

### TI-FILE — Files and storage

| ID | Mode | Scenario | Pass criterion |
|---|---|---|---|
| TI-FILE-01 | A | Counselor B requests signed URL for file of tenant A | Refused (404) |
| TI-FILE-02 | A | Storage path manipulation: request for `tenants/A/...` path with B's token | Refused |
| TI-FILE-03 | I | Signed URL expires after its TTL | Access denied after expiry |
| TI-FILE-04 | I | Stored file metadata row for B not visible to A under RLS | Zero rows |
| TI-FILE-05 | I | File path derived from DB record, not request | Request-supplied path ignored or rejected |

### TI-RPT / TI-EXP — Reports and exports

| ID | Mode | Scenario | Pass criterion |
|---|---|---|---|
| TI-RPT-01 | I | Report for Student A1 generated under tenant A | Contains only A1 and A data; no B names or IDs |
| TI-RPT-02 | A | Request report for Student B1 as Counselor A | Refused (404) |
| TI-EXP-01 | I | CSV/Excel export as Counselor A | Row set equals A's rows; no B rows |
| TI-EXP-02 | I | Export filename and metadata | Contains no other tenant identifiers |

### TI-NOTIF — Notifications

| ID | Mode | Scenario | Pass criterion |
|---|---|---|---|
| TI-NOTIF-01 | I | In-app notification created for A's student | Delivery row carries `tenant_id = A`; not visible to B under RLS |
| TI-NOTIF-02 | A | Notification adapter called for one recipient | Adapter receives exactly one recipient and tenant content |
| TI-NOTIF-03 | I | Retry of failed delivery for tenant A | Retry uses A's recipient only |
| TI-NOTIF-04 | I | Adapter (Telegram/SMS mock) failure | Core remains functional; failure recorded tenant-scoped |

### TI-AUDIT — Audit logs

| ID | Mode | Scenario | Pass criterion |
|---|---|---|---|
| TI-AUDIT-01 | I | State-changing action by Counselor A | Audit row with actor, `tenant_id = A`, request_id |
| TI-AUDIT-02 | I | Counselor A reads audit rows | Only A's rows; B's audit invisible |
| TI-AUDIT-03 | I | Audit rows cannot be updated or deleted by `app_runtime` | Permission denied |

---

## 3. Coverage Requirements

- Every test group above must have a runnable implementation before any feature in its area is declared Done (Definition of Done §65).
- Tenant-isolation paths require 100% coverage (`TEST_PLAN.md`); coverage is measured per documented path, not as a line-count proxy alone.
- Each endpoint's contract entry (`AUTHORIZATION_CONTRACT.md` §7) must link at least one TI-API negative test.

## 4. Pass/Fail Policy

- Any failing TI test blocks the phase. There is no "known failure" exception for tenant isolation.
- A test that passes only because a harness silently returns nothing (for example, a wrong credential) is a failure of the test, not a pass. Each negative test must first assert a positive control (the same query succeeds for the correct tenant).
