# Control Plane Role & Privilege Contract

**Status:** DRAFT / NOT APPROVED. Catalog-level tests exist and passed in synthetic PostgreSQL 16 CI. No production credentials or deployment are authorized.

## 1. Roles

The current draft creates six cluster-wide roles:

- cp_table_owner — NOLOGIN; owns Control Plane tables and sequences.
- cp_function_owner — NOLOGIN; owns SECURITY DEFINER functions.
- cp_runtime — NOLOGIN; read-only registry access for trusted runtime.
- cp_transfer_executor — NOLOGIN; may execute the two transfer commands.
- cp_rotation_executor — NOLOGIN; may execute HMAC rotation lifecycle functions.
- cp_identity_admission_executor — NOLOGIN; may execute only admit_student_identity_claim(...).

All roles are NO SUPERUSER, NO CREATEDB, NO CREATEROLE, NO REPLICATION and NO BYPASSRLS. No application service receives owner-role membership. No role has a password or login in the draft.

## 2. Object ownership and direct access

- cp_table_owner owns all Control Plane tables and sequences.
- cp_function_owner owns the privileged functions.
- cp_runtime cannot directly mutate ownership, claims, transfer cases, approvals, key versions, HMAC aliases, contact index, idempotency logs or outbox/inbox.
- Transfer, rotation and identity-admission executors have no direct table privileges; they are function-only capabilities.
- PUBLIC has no EXECUTE on privileged functions.
- No executor is a member of cp_table_owner or cp_function_owner.

## 3. Executor scope

| Executor | Permitted functions | Forbidden capabilities |
|---|---|---|
| cp_transfer_executor | request_transfer_case_idempotent(...), switch_student_ownership(...) | HMAC rotation, initial identity admission, direct table DML |
| cp_rotation_executor | begin_identity_hmac_rotation(), complete_identity_hmac_rotation(...), retire_identity_hmac_version(...) | Transfer switch, initial identity admission, direct table DML |
| cp_identity_admission_executor | admit_student_identity_claim(...) | Transfer, rotation, direct table DML |
| cp_runtime | Registry SELECT | Ownership/claim/approval/key/alias mutations |

The exact function signatures and grants are enforced by cp_06_role_privileges_draft.sql and asserted by tests/cp_30_role_privilege_tests.sql.

## 4. Function owner blast radius — HIGH

The current draft uses one non-login cp_function_owner for the transfer, rotation and initial-admission SECURITY DEFINER functions. It has broad DML grants across Control Plane tables so that each function can perform its transaction. This role cannot log in and no executor can SET ROLE to it, but a vulnerability in any SECURITY DEFINER function could exercise a larger data surface than that function needs.

Before production, split this role into narrowly scoped owners, at minimum:
- cp_transfer_function_owner
- cp_rotation_function_owner
- cp_identity_admission_function_owner

Each function owner should receive only the table/column privileges and helper-function EXECUTE rights required by its own function family. Add catalog tests proving the separation and that no owner role is assumable by service executors. This is a HIGH blocker, not an approved exception.

## 5. Identity admission capability

The initial claim admission function:
- locks the identity maintenance gate for the transaction;
- requires exactly one active HMAC key and a unique alias for every active/retiring key version;
- requires an active encryption key version and non-empty ciphertext;
- creates platform student, initial ownership, claim, contact-index rows, versioned aliases and an append-only idempotency command in one transaction;
- rejects duplicate global mobile+grade claims through the versioned alias unique index;
- rejects same idempotency key with different payload;
- never stores plaintext E.164 or key material.

The trusted service must still prove that every HMAC alias was computed from the same normalized canonical E.164 value and must authenticate/authorize the caller. Database checks validate coverage and uniqueness, not cryptographic correctness or human identity.

Mobile contact change/reverification is not yet implemented. It must update all active/retiring aliases and ciphertext atomically under the same maintenance gate and uniqueness rules.

## 6. RLS and application authorization

Control Plane database roles do not replace application authorization. Every transfer initiator and approver must be bound to an authenticated Platform User and a verified relationship/authority record. A caller-supplied UUID or evidence reference is not authentication.

The runtime must fail closed when the Control Plane is unavailable, ownership is ambiguous, the generation is stale, or the Workspace projection does not match the registry. No shared application role may access another Workspace database.

## 7. Verification and remaining work

GitHub Actions run #148 executed the role catalog suite on synthetic PostgreSQL 16 databases. It checked role count/attributes, ownership, PUBLIC EXECUTE revocation, direct table denial, executor scope and non-assumability.

Not yet implemented or verified:
- split function-owner blast radius;
- mobile contact change/reverification;
- production login identities, secret binding, KMS/HSM, rotation and revocation;
- transfer outbox/inbox worker credentials, durable delivery and recovery;
- API-level authentication/authorization and IDOR tests;
- target-environment verification, connection-pool isolation and production failover.
