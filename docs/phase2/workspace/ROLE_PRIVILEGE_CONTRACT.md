# Workspace DB Role & Credential Contract

**Status:** DESIGN CONTRACT / NOT IMPLEMENTED OR EXECUTED. This contract complements the Control Plane role contract. A Workspace DB is one Workspace's isolated data boundary; a DB role is not a counselor identity.

## 1. Role separation

| Role | Login | Table owner | Privileges |
|---|---:|---:|---|
| `ws_table_owner` | NO | Yes | Owns schema/tables; migration-only, never granted to application identities |
| `ws_runtime` | service login | No | Required CRUD on approved domain tables; no DDL, TRUNCATE, role administration or schema CREATE |
| `ws_worker` | service login | No | Narrowly scoped reads/writes for notification, scheduled work and projection handlers |
| `ws_exporter` | service login | No | SELECT only on approved export views; no direct access to unscoped base tables |
| `ws_migration_operator` | time-bound/approved | No persistent runtime use | Applies reviewed migrations and records audit evidence |

All runtime roles must be NO SUPERUSER, NO CREATEDB, NO CREATEROLE, NO BYPASSRLS. No runtime identity may own the schema, tables, functions or sequences. Public schema CREATE and unnecessary PUBLIC privileges are revoked.

## 2. Credentials and isolation

- Each Workspace DB has a distinct credential set and secret reference. Do not use one shared database login across multiple Workspace databases.
- A service may connect only to the database(s) assigned to its authorized Workspace/cell scope.
- Connection-pool routing must bind an authenticated request to a validated Workspace ID. A caller-supplied Workspace ID is a selector, not proof of membership.
- The Control Plane owner/generation check occurs before student-data access. Unavailable or ambiguous ownership fails closed.
- No direct database credentials are issued to counselors, parents, students, exports or client applications.
- Workspace membership in one DB cannot be used to connect to another Workspace DB.
- Credential rotation, revocation and pool eviction must be Workspace-scoped and auditable.

## 3. Object-level authorization remains mandatory

Because the database is Workspace-local and pooled application connections do not inherently represent an individual counselor or guardian, database separation alone does not enforce within-Workspace access. Every API/service query must apply:
- authenticated Platform User and active Workspace membership;
- role plus explicit permission/scope;
- student-to-counselor active assignment for counselor access;
- manager permission for the exact action and scope;
- verified guardian-to-student relationship and per-child permission;
- private-to-author counselor-note visibility;
- file/export authorization at access time.

Do not trust client-supplied student, membership, branch, guardian or Workspace IDs without relationship checks. Cross-Workspace denial is mandatory even when IDs are guessed.

## 4. RLS policy

The MVP's primary tenant boundary is a distinct Workspace database/credential, not a shared tenant table filtered only by RLS. RLS may be added as defense-in-depth for sensitive subdomains, but:
- no runtime role may have BYPASSRLS;
- policies must use trusted server-side identity context, never client-settable session variables as proof;
- table owners must not be used by the application;
- integration tests must prove both database-level and API-level denial.

## 5. Verification required

Before a real Workspace is provisioned:
1. Inspect roles, memberships, grants, table/function/sequence owners and default privileges in a fresh DB.
2. Assert all runtime roles are not SUPERUSER/BYPASSRLS/CREATEROLE/CREATEDB and own no objects.
3. Assert runtime cannot CREATE, ALTER, DROP, TRUNCATE, DISABLE TRIGGER or SET ROLE to an owner.
4. Assert exporter is limited to approved views and worker grants are scoped.
5. Attempt direct access to another Workspace DB using the first Workspace credential; connection must fail.
6. Test object-level counselor, manager and guardian access, including guessed IDs and 404 concealment.
7. Test pool reuse across different Workspace requests for stale session/context leakage.
8. Test credential rotation/revocation, connection termination and fail-closed behavior.

No Workspace runtime role provisioning, per-Workspace credentials, grants or catalog tests have been performed. These remain Phase 2 blockers.
