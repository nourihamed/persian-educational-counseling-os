# Control Plane Role & Privilege Contract

**Status:** DRAFT / NOT EXECUTED. Deployment/security approval required. This contract implements the D-009/D-013 principle: runtime identities are neither table owners nor BYPASSRLS.

## 1. Required role separation

| Role | Login | Owns tables | BYPASSRLS / SUPERUSER | Permitted responsibility |
|---|---:|---:|---:|---|
| `cp_table_owner` | NO | Yes | NO / NO | Owns Control Plane schema/tables; used only by controlled migrations |
| `cp_function_owner` | NO | No | NO / NO | Owns narrowly scoped SECURITY DEFINER functions; receives only required DML privileges |
| `cp_runtime` | service login/group | No | NO / NO | No direct mutation of ownership, identity, approval, transfer, command, history or outbox tables |
| `cp_transfer_executor` | service login/group | No | NO / NO | EXECUTE only on idempotent transfer admission and ownership switch functions |
| `cp_rotation_executor` | service login/group | No | NO / NO | EXECUTE only on begin/complete/retire HMAC rotation functions |
| `cp_migration_operator` | controlled, time-bound | No persistent runtime use | deployment-specific | Applies reviewed schema changes with approval and audit; not used by application |

The login/service identities must not be members of `cp_table_owner` or `cp_function_owner`. Group-role membership must be granted only to the corresponding service identity. No application process receives superuser, CREATE ROLE, schema ownership, table ownership or trigger-disabling privileges.

## 2. Function ownership and grants

The following functions are SECURITY DEFINER candidates and must be owned by `cp_function_owner`, not the migration operator or table owner:

- `switch_student_ownership(uuid)`
- `request_transfer_case_idempotent(text,bytea,uuid,uuid,uuid,uuid,bigint,text)`
- `begin_identity_hmac_rotation()`
- `complete_identity_hmac_rotation(integer)`
- `retire_identity_hmac_version(integer)`

All must retain a fixed safe `search_path` (`pg_catalog, pg_temp`) and schema-qualify every non-system object. PUBLIC EXECUTE must be revoked. Grant only:
- transfer executor: request-transfer and switch functions;
- rotation executor: begin/complete/retire rotation functions;
- runtime: no execute on privileged mutation functions.

The function owner receives only the table DML/sequence rights needed by those functions. It must not own the tables and must not have SUPERUSER, BYPASSRLS, CREATEROLE or CREATEDB. The table owner is NOLOGIN and not granted to service roles.

## 3. Direct table access

- Revoke all direct INSERT/UPDATE/DELETE/TRUNCATE privileges on ownership, claims, contact index, HMAC aliases/key versions, transfer cases/approvals, command log, ownership history and outbox/inbox from runtime/service roles.
- Claim/contact/alias writes must go through controlled admission/contact-change/rotation functions. Those functions are not yet implemented in this branch; deferred alias-completeness triggers are defense-in-depth, not a replacement for least-privilege grants.
- Transfer approvals must be created only by trusted identity/authorization services after authenticating the principal and verifying guardian authority, prior counselor assignment or destination permission. A DB function cannot infer lawful authority from a text identifier.
- Outbox workers may update only delivery metadata (e.g. published timestamp) through a narrow function; event identity/payload is immutable.
- Inbox consumers may insert/deduplicate events through a narrow function and must reject stale/future generations.

## 4. Security verification required before approval

1. Inspect `pg_roles`, `pg_auth_members`, `information_schema.role_table_grants` and function owners on a fresh database.
2. Assert all runtime/service roles have `rolsuper=false`, `rolbypassrls=false`, `rolcreaterole=false`, `rolcreatedb=false`.
3. Assert no runtime/service role owns Control Plane schema/tables or privileged functions.
4. Assert PUBLIC and runtime roles cannot directly mutate protected tables or execute privileged functions.
5. Assert only designated transfer/rotation executors can execute their corresponding functions.
6. Attempt direct table writes, TRUNCATE, trigger disable, function search_path shadowing, and role escalation; all must fail.
7. Verify SECURITY DEFINER function owner privileges are sufficient but least-privilege and all names are schema-qualified.
8. Preserve SQL output/logs and test the exact reviewed SHA.

## 5. Current status

No role provisioning, ownership transfer, GRANT/REVOKE execution, catalog inspection or privilege test has been performed in this project branch. Therefore D-009/D-013 runtime role guarantees remain **UNVERIFIED**. Phase 2 cannot be APPROVED until the role contract is implemented in a controlled test database and independently verified.
