# Workspace DB Role & Credential Contract

**Status:** DRAFT / NOT APPROVED. A provisioning template and catalog tests now exist, but production credentials and target-environment verification do not. A Workspace DB is one Workspace's isolated data boundary; a DB role is not a counselor identity.

## 1. Cluster-wide role naming is mandatory

PostgreSQL roles are cluster-wide, not database-local. Generic role names such as ws_runtime must never be reused across Workspace databases in the same PostgreSQL cluster.

The draft provisioning script requires workspace_key to be the canonical 32-character lowercase hexadecimal Workspace UUID (UUID without hyphens). It creates unique roles:

- ws_<workspace_key>_table_owner — NOLOGIN, owns Workspace tables/sequences.
- ws_<workspace_key>_function_owner — NOLOGIN, owns SECURITY DEFINER functions.
- ws_<workspace_key>_runtime — NOLOGIN group role for the trusted application runtime.
- ws_<workspace_key>_worker — NOLOGIN group role for notification workers.
- ws_<workspace_key>_exporter — NOLOGIN group role; no base-table access until approved views exist.
- Corresponding _runtime_login, _worker_login, _exporter_login login identities, each a member only of its Workspace-specific group role.

All roles must be NO SUPERUSER, NO CREATEDB, NO CREATEROLE and NO BYPASSRLS. Owner/function-owner roles are NOLOGIN. Login roles are placeholders created with no password; production secrets must be injected and rotated through the approved secret-management system, never stored in SQL or Git.

## 2. Database connection boundary

- Every Workspace DB receives its own runtime/worker/exporter login identities and secret references.
- CONNECT and TEMPORARY are revoked from PUBLIC on each Workspace database; only that Workspace's login identities and the controlled migration operator receive CONNECT.
- A login identity for Workspace A must not be able to connect to Workspace B's database, even when both databases share a PostgreSQL cluster.
- A service may connect only to the database(s) assigned to its authorized Workspace/cell scope.
- Connection-pool routing must bind an authenticated request to a validated Workspace ID. A caller-supplied Workspace ID is a selector, not proof of membership.
- The Control Plane owner/generation check occurs before student-data access. Unavailable or ambiguous ownership fails closed.
- No direct database credentials are issued to counselors, parents, students, exports or client applications.
- Credential rotation, revocation and pool eviction must be Workspace-scoped and auditable.

## 3. Role privilege boundaries

| Role | Allowed scope | Explicitly denied |
|---|---|---|
| table_owner | Owns schema tables/sequences; migration-only | Login and application membership |
| function_owner | Owns SECURITY DEFINER activation/capacity functions; only required DML | Login, table ownership, broad runtime membership |
| runtime | CRUD on approved Workspace domain tables; INSERT audit; SELECT wallet/capacity; execute atomic activation | Direct enrollment UPDATE, student lifecycle/grade UPDATE, physical DELETE, direct credit/capacity ledger writes, direct low-level capacity function |
| worker | SELECT/UPDATE In-App notifications; SELECT notification preferences | Student-domain, guardian, credit, file and audit base-table access |
| exporter | No base-table access; future explicitly reviewed views only | Unscoped student, guardian, financial, note or audit tables |
| migration_operator | Time-bound, approved schema/role changes with audit | Persistent runtime use |

The current draft runtime grants deliberately omit physical DELETE. Student lifecycle and enrollment state transitions must use controlled operations. students.display_name is the only student column with a runtime UPDATE grant; platform_student_id, grade_key and lifecycle_state are not runtime-updatable. enrollments may be inserted only in requested or awaiting_consent; a trigger rejects direct insertion in active, and runtime has no UPDATE privilege on the table.

Credit/capacity rules:
- Runtime cannot INSERT/UPDATE/DELETE credit_transactions, capacity_events, workspace_capacity_counters or activation_command_log.
- activate_student_enrollment(...) is the controlled operation exposed to runtime. It validates local generation and prerequisites, then atomically writes the activation debit, capacity event and enrollment state.
- adjust_workspace_capacity(...) is callable only by the non-login function owner.
- Wallet balance is derived from the ledger. The MVP wallet uses unit_code `CRD`, never a fiat currency. A wallet-row lock serializes ledger inserts and rejects any transaction that would make the balance negative.
- Exporter remains deny-by-default until scope-safe views are designed and explicitly granted.

## 4. Object-level authorization remains mandatory

Database separation does not enforce within-Workspace access. Every API/service query must apply:
- authenticated Platform User and active Workspace membership;
- role plus explicit permission/scope for the exact action;
- student-to-counselor active assignment for counselor access;
- manager permission for the exact action and scope;
- verified guardian-to-student relationship and per-child permission;
- private-to-author counselor-note visibility;
- file/export authorization at access time;
- current Control Plane owner and generation validation.

Do not trust client-supplied student, membership, branch, guardian or Workspace IDs without relationship checks. Cross-Workspace denial is mandatory even when IDs are guessed. The SECURITY DEFINER activation function receives actor context from a trusted server-side service; caller-supplied actor IDs are not proof of authentication or authorization. The API must authorize the actor before calling it.

## 5. RLS policy

The MVP's primary tenant boundary is a distinct Workspace database and distinct credentials, not a shared tenant table filtered only by RLS. RLS may be added as defense-in-depth for sensitive subdomains, but:
- no runtime role may have BYPASSRLS;
- policies must use trusted server-side identity context, never client-settable session variables as proof;
- table owners must not be used by the application;
- integration tests must prove both database-level and API-level denial.

## 6. Draft artifacts and execution

- Provisioning template: workspace_roles_setup_draft.sql.
- Atomic activation/ledger function: workspace_activation_transactions.sql.
- Catalog and cross-database tests: tests/workspace_role_privilege_tests.sql.
- Activation/credit/capacity tests: tests/workspace_activation_tests.sql.
- Concurrent activation test: tests/workspace_activation_race.sh.
- GitHub Actions applies two synthetic Workspace databases with distinct 32-hex role prefixes and checks CONNECT denial in both directions.

The script requires a privileged migration operator and is not a production migration. It must be reviewed for the exact target PostgreSQL version and deployment model. Production login identities, secret binding, KMS integration, credential rotation, connection revocation, pool eviction and independent target-environment verification remain NOT IMPLEMENTED / NOT RUN.

## 7. Required verification before real Workspace provisioning

1. Inspect pg_roles, pg_auth_members, grants, table/function/sequence owners and default privileges in a fresh DB.
2. Assert all runtime roles are not SUPERUSER/BYPASSRLS/CREATEROLE/CREATEDB and own no objects.
3. Assert runtime cannot CREATE, ALTER, DROP, TRUNCATE, DISABLE TRIGGER or SET ROLE to an owner.
4. Assert exporter is limited to approved views and worker grants are scoped.
5. Attempt direct access to another Workspace DB using the first Workspace credential; connection must fail.
6. Test object-level counselor, manager and guardian access, including guessed IDs and 404 concealment.
7. Test pool reuse across different Workspace requests for stale session/context leakage.
8. Test credential rotation/revocation, connection termination and fail-closed behavior.
9. Test activation concurrency, insufficient credit, capacity exhaustion and exact rollback.


## 8. Authorization-table write boundary — 2026-11-09 correction

The Workspace provisioning draft now grants the general runtime role **SELECT only** on:
- workspace_memberships;
- membership_roles and membership_permissions;
- branches and counselor_assignments;
- student_guardian_links and guardian_permissions.

The activation function owner also receives read-only access to those authorization source tables. It has no INSERT/UPDATE/DELETE privileges on membership, role, permission, branch, counselor-assignment or guardian authorization records. This prevents a compromised general runtime or activation function from self-assigning roles, changing counselor responsibility or granting guardian access.

The activation function owner has been narrowed to required reads/inserts and column-level UPDATE grants for enrollment state/start time, capacity counter values, and lock-only columns on wallet/ledger/idempotency rows. Immutable triggers reject mutation through the lock-only columns. A dedicated authorization-management command/function owner and audited grant/revoke event model are not yet implemented; until then, authorization-table changes are intentionally unavailable through runtime.

Catalog test additions assert the runtime and activation function owner cannot write authorization tables, while the required read access and narrowly scoped activation column grants remain available. Fresh CI is required before this correction is marked PASS.
