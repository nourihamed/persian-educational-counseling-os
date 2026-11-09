# Control Plane Role & Privilege Contract

**Status:** DRAFT / NOT APPROVED. The split-owner SQL and catalog assertions have been added but are pending a fresh PostgreSQL 16 CI run on the exact branch HEAD. No production credentials or deployment are authorized.

## 1. Roles

The draft creates eight cluster-wide NOLOGIN roles:

- `cp_table_owner` — owns Control Plane tables and sequences.
- `cp_transfer_function_owner` — owns transfer SECURITY DEFINER functions only.
- `cp_rotation_function_owner` — owns HMAC rotation SECURITY DEFINER functions only.
- `cp_identity_admission_function_owner` — owns initial identity-admission SECURITY DEFINER function only.
- `cp_runtime` — no direct table privileges in this draft; runtime reads must go through a separately reviewed service/API boundary.
- `cp_transfer_executor` — may execute the two transfer commands.
- `cp_rotation_executor` — may execute HMAC rotation lifecycle functions.
- `cp_identity_admission_executor` — may execute only `admit_student_identity_claim(...)`.

All roles are NOLOGIN, NOSUPERUSER, NOCREATEDB, NOCREATEROLE, NOREPLICATION, NOINHERIT and NOBYPASSRLS. No application service receives owner-role membership. Production login identities must be separate service principals with narrowly scoped membership/SET ROLE arrangements, secret binding and rotation; those are not implemented here.

## 2. Object ownership and direct access

- `cp_table_owner` owns all Control Plane tables and the ownership-history sequence.
- Each SECURITY DEFINER function family is owned by its matching function-owner role.
- Runtime and executor roles have no direct table or sequence privileges.
- PUBLIC has no EXECUTE on privileged functions.
- Function-owner roles are not members of the table-owner role or one another.
- Executor roles are not members of any owner role.
- Temporary schema CREATE is granted only while the privileged provisioning script changes function ownership, then revoked before commit.

## 3. Function-owner privilege intent

| Function owner | Intended table capabilities | Explicitly excluded examples |
|---|---|---|
| `cp_transfer_function_owner` | Read transfer cases/approvals, owner/claim/alias/contact state and transition table; insert/update transfer command records, ownership history and outbox; update ownership/claim/alias state; use ownership-history sequence; lock the identity gate using UPDATE(singleton) only | HMAC key lifecycle updates, identity admission inserts, maintenance_mode/rotation_epoch updates |
| `cp_rotation_function_owner` | Read/update identity write gate and HMAC key versions; read claim/alias/contact state; delete retired aliases/contact-index rows; execute alias-coverage helpers | Transfer cases, ownership switch, initial student/claim admission |
| `cp_identity_admission_function_owner` | Read gate/key/workspace and identity state needed for validation; insert initial platform student, ownership, claim, contact index, aliases and idempotency command; execute alias-coverage helper | Transfer cases/approvals, command log, ownership switch, HMAC key lifecycle updates/deletes |

The SQL grant matrix is in `schema/cp_06_role_privileges_draft.sql`. This table describes intended boundaries; catalog tests and a manual privilege-path review must confirm the exact effective privileges, including trigger/helper execution.

## 4. Executor scope

| Executor | Permitted functions | Forbidden capabilities |
|---|---|---|
| `cp_transfer_executor` | `request_transfer_case_idempotent(...)`, `switch_student_ownership(...)` | HMAC rotation, initial identity admission, direct table DML |
| `cp_rotation_executor` | `begin_identity_hmac_rotation()`, `complete_identity_hmac_rotation(...)`, `retire_identity_hmac_version(...)` | Transfer switch, initial identity admission, direct table DML |
| `cp_identity_admission_executor` | `admit_student_identity_claim(...)` | Transfer, rotation, direct table DML |
| `cp_runtime` | No direct database operation granted in this draft | Direct table/sequence access and privileged function execution |

The exact function signatures, owner assignments and grants are asserted by `tests/cp_30_role_privilege_tests.sql`.

## 5. Verification status and residual risks

The prior GitHub Actions run #148 passed the former shared-owner catalog design on synthetic PostgreSQL 16. It is historical evidence only and does **not** validate this new split-owner revision.

The transfer and identity-admission owners receive only column-level UPDATE on the CHECK-constrained `singleton` field because PostgreSQL requires UPDATE privilege for `SELECT ... FOR SHARE`; they cannot update `maintenance_mode` or `rotation_epoch`. The rotation owner alone receives those state-changing UPDATE privileges. The catalog suite asserts these column-level boundaries.

The new catalog suite checks:
- role count and forbidden role attributes;
- absence of the legacy shared `cp_function_owner`;
- table and function ownership by family;
- direct table denial to runtime/executors;
- representative allowed and denied table privileges for each function owner;
- owner/executor non-membership;
- sequence scope;
- executor function scope; and
- PUBLIC EXECUTE revocation.

**Not yet verified:** fresh CI on the exact new branch HEAD, completeness/minimality of every table privilege, all trigger/helper execution paths, production service identity and secret binding, KMS/HSM, rotation/revocation operations, and target-environment behavior. The new split is a remediation draft, not a closed HIGH finding or production security approval.

## 6. Identity admission and application authorization

The initial claim admission function:
- locks the identity maintenance gate for the transaction;
- requires exactly one active HMAC key and a unique alias for every active/retiring key version;
- requires an active encryption key version and non-empty ciphertext;
- creates platform student, initial ownership, claim, contact-index rows, versioned aliases and an append-only idempotency command in one transaction;
- rejects duplicate global mobile+grade claims through the versioned alias unique index;
- rejects same idempotency key with different payload; and
- never stores plaintext E.164 or key material.

The trusted service must still prove that every HMAC alias was computed from the same normalized canonical E.164 value and must authenticate/authorize the caller. Database checks validate coverage and uniqueness, not cryptographic correctness or human identity.

Mobile contact change/reverification is not yet implemented. It must update all active/retiring aliases and ciphertext atomically under the same maintenance gate and uniqueness rules.

Control Plane database roles do not replace application authorization. Every transfer initiator and approver must be bound to an authenticated Platform User and a verified relationship/authority record. A caller-supplied UUID or evidence reference is not authentication. The runtime must fail closed when the Control Plane is unavailable, ownership is ambiguous, the generation is stale, or the Workspace projection does not match the registry.
