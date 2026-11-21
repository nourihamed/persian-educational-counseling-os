# API and Authorization Contract — Phase 2 design

**Status:** DRAFT / NOT APPROVED. Contracts only; no runtime endpoints are implemented here. D-014 synthetic data only.

## 1. Trust model

- Authentication resolves a stable Platform User principal. Mobile is mutable contact/login data, not an authorization key.
- Workspace context is derived from the authenticated session/token and validated membership; caller-supplied `workspace_id` never grants access.
- Authorization combines role, relationship, resource scope, assignment, consent and current Control Plane ownership/generation.
- Cross-Workspace membership never implies access. Each Workspace DB uses its own credential boundary.
- If Control Plane ownership cannot be verified, student-data operations fail closed.
- Cross-tenant and nonexistent resources return indistinguishable 404. Return 403 only after proving the object is visible but the action is forbidden.

## 2. Transfer API contract (logical operations; paths are illustrative, not implemented)

| Operation | Authorized actor | Preconditions | Idempotency / audit |
|---|---|---|---|
| Create transfer request | verified guardian, current counselor, destination Workspace | current owner and destination resolved; no open transfer | required idempotency key + canonical payload hash |
| Guardian consent | verified guardian with legal authority for child and scope | active relationship; exact student/case; consent not expired/revoked | principal-bound immutable approval record |
| Prior counselor fee confirmation | authenticated prior responsible counselor | source assignment and prior enrollment verified | exact case/enrollment, timestamp, principal; assertion not payment proof |
| Destination acceptance | authorized destination owner/manager and required counselor | destination active; capacity/contract preflight | principal-bound approval |
| Freeze source | transfer orchestrator | approvals and preflight valid | durable freeze token, generation, audit |
| Stage snapshot | transfer orchestrator / isolated worker | source freeze barrier established | immutable snapshot manifest and checksums |
| Ownership switch | Control Plane workflow service only | final revalidation; three approvals; frozen and staged verified; expected generation matches | atomic transaction, command idempotency, history + outbox |
| Finalize projections | scoped Workspace worker | current owner and new generation match | inbox dedupe, retries, stale-generation rejection |

## 2A. Initial student identity admission (logical operation; not an implemented endpoint)

- The API authenticates the Platform User and resolves an active Workspace membership plus explicit student.create permission. Do not infer permission from a role label alone.
- The service verifies control of the submitted mobile number, normalizes it to canonical E.164, validates the grade and resolves an active Workspace.
- The trusted service computes the canonical payload hash, encrypts E.164 using the active Platform Security encryption key and computes one HMAC alias for every active/retiring HMAC key version. Plaintext, keys and caller-supplied HMAC/ciphertext values are never accepted as authoritative.
- The service invokes Control Plane admit_student_identity_claim(...) using a server-generated student/claim ID and idempotency key. The database function atomically creates the global student reference, initial Workspace owner, claim, encrypted contact index and all versioned aliases.
- Global mobile+grade uniqueness is enforced by the Control Plane. A duplicate claim returns a non-disclosing conflict; no Workspace-local record may be created on failure.
- The database function verifies alias count/version coverage and uniqueness, but cannot prove the HMACs came from the same canonical E.164. The trusted service/KMS boundary is responsible for that guarantee.
- The operation is a draft DB capability only. No HTTP endpoint, OTP verification service, KMS integration or production authorization path is implemented.

## 2B. Mobile contact change / reverification (NOT IMPLEMENTED)

- Require re-authentication/step-up and verification of the new mobile number before changing the canonical contact.
- Keep the old identity claim authoritative until the new number is verified and the complete active/retiring alias set can be committed.
- Update ciphertext, contact-index rows and all aliases under the same Control Plane maintenance gate; preserve global mobile+grade uniqueness and idempotency.
- Reject duplicate claims without revealing another student's existence. Audit old/new key-version references and actor, but never log plaintext or HMAC keys.
- A contact-change function and executable tests are still missing; do not implement by direct table UPDATE.

## 2C. Workspace enrollment activation (logical operation; not an implemented endpoint)

- Before activation, validate current Control Plane owner and ownership_generation; fail closed if Control Plane is unavailable or generation differs.
- Verify actor's exact student.activate permission, active Workspace membership, accepted responsible counselor, required guardian/consent state, product entitlement and configured capacity.
- Determine debit amount from server-side entitlement/pricing policy; never accept a client-supplied debit amount.
- Invoke activate_student_enrollment(...) with server-derived actor, wallet, generation and idempotency context. The draft DB function atomically debits Student Credit, reserves active-student capacity, changes enrollment to active and writes an audit event.
- The database function checks active membership and one accepted responsible counselor as defense-in-depth; it does not replace exact API authorization or Control Plane ownership validation.
- Activation SQL and concurrency tests pass synthetically; the HTTP/API authorization and end-to-end service are not implemented.

## 3. Parent/guardian authorization

- Verify relationship and legal authority according to age and applicable Iran MVP legal review. Do not infer legal authority from phone number or self-assertion.
- Permission is per child and per scope/action; scopes include progress, plans, attendance, test results, financial information and communication, with sensitive scopes separately granted.
- Every grant has issuer, verified authority reference, effective interval, expiry if applicable, revocation and audit.
- Counselor-private notes and confidential communications are denied by default.
- Student rights and applicable law override ordinary parent settings.
- Q-007 remains open until legal matrix, age bands, evidence, exceptions and executable tests are approved.

## 4. Organization Manager and Counselor authorization

- Organization Manager permissions are explicit and separable; broad organization visibility is not implied by manager role.
- Counselor reads/writes are restricted to students with active counselor assignment and action permission.
- Branch scope is checked independently.
- Owner, manager, membership, counselor assignment and resource permissions are distinct relationships.
- Assignment change requires authorized owner/manager permission and destination counselor acceptance.
- Platform Admin is read-only in MVP; no routine student-content access. Support review does not initiate transfer or bypass approvals.

## 5. API safety requirements

- Validate request schema, size, enum, date/timezone and identifiers at boundary.
- Use pagination with bounded page size and stable ordering for list/export endpoints.
- Rate-limit OTP, login, transfer initiation/approval, exports and sensitive lookup.
- Use CSRF protection where cookie sessions are used; secure/HttpOnly/SameSite cookies.
- Step-up/MFA for high-risk roles/actions; high-risk roles require MFA.
- Use request IDs and idempotency keys for mutation endpoints; reject payload mismatch on key reuse.
- Do not expose whether another Workspace contains a student.
- File download/export requires fresh authorization before URL issuance; short-lived URL only.
- Background jobs carry immutable Workspace/student/generation context and revalidate before processing.
- Audit actor principal, action, target, Workspace, decision, timestamp, correlation ID and outcome; never secrets/OTP/tokens.

## 6. Error semantics

- 404: nonexistent or cross-Workspace hidden resource.
- 403: resource is visible in caller's authorized scope but requested action is not permitted.
- 409: state conflict, stale generation, duplicate open transfer, idempotency key reused with different payload.
- 422: structurally valid request violates business validation (e.g. invalid grade or missing required field).
- 429: rate limit.
- 503: Control Plane ownership check unavailable; deny data access and do not fall back to stale cache.

## 7. Acceptance tests (specified, not executed)

- Cross-Workspace object IDs return same 404 as nonexistent IDs.
- Counselor cannot read another counselor's student absent explicit scope.
- Manager without specific permission cannot access restricted records.
- Parent permission for child A never grants access to child B.
- Expired/revoked guardian grant denied immediately.
- Platform Admin cannot initiate or approve transfer as a shortcut.
- Only the designated prior counselor can submit fee confirmation.
- Only authorized destination actor can accept.
- Missing ownership validation denies read/write/export/file/job access.
- Idempotency replay and payload mismatch semantics are stable.
- Initial claim admission creates all active/retiring HMAC aliases; global mobile+grade duplicate and concurrent race are rejected (SQL draft tests PASS; API/KMS verification NOT RUN).
- Workspace activation atomically debits Student Credit, reserves capacity and audits; insufficient credit/capacity and same-enrollment concurrency roll back or replay correctly (SQL draft tests PASS; API authorization NOT RUN).
- Mobile contact-change/reverification updates all aliases atomically and rejects global duplicates (NOT IMPLEMENTED / NOT RUN).
- High-risk actions enforce MFA/step-up and audit.


## 8. Required cross-contract bindings (2026-11-09 review)

- Mobile contact changes must follow `control_plane/CONTACT_CHANGE_REVERIFICATION_CONTRACT.md`; no direct API/table update is permitted. Proof is one-time and bound to student, Workspace, generation, purpose and proposed-contact fingerprint.
- Transfer approvals must follow `control_plane/TRANSFER_APPROVAL_IDENTITY_AUTHORITY_CONTRACT.md`. API actors cannot submit an approver UUID or authority snapshot as proof. The trusted verifier derives the subject and authority from authenticated evidence and emits a case-bound assertion.
- Distributed transfer operations must follow `transfer/CROSS_WORKSPACE_TRANSFER_SAGA_CONTRACT.md`. API handlers cannot directly activate destination projections or unfreeze the source after ownership switch.
- The HTTP service must bind idempotency keys to a canonical, versioned request hash. Same key/same hash returns the original logical result; same key/different hash returns a non-disclosing conflict and creates a security/audit event.
- Approval, revocation and ownership switch must serialize at case scope. The API must not report an approval as effective until its durable event commits, nor report transfer completion until both projections and source fencing are reconciled.

## 9. API authorization acceptance matrix (specified, not executed)

| Surface | Required negative cases |
|---|---|
| Student CRUD / profile | guessed cross-Workspace ID; counselor without active assignment; suspended membership; stale owner/generation |
| Parent portal | child A grant used for child B; expired/revoked grant; wrong scope; guardian authority disputed or absent |
| Manager / branch | manager without explicit permission; branch outside scope; membership revoked between list and detail |
| Transfer request | ineligible initiator; Platform Admin shortcut; stale source owner; duplicate open case; payload mismatch |
| Transfer approval | forged/replayed assertion; wrong principal/case/student/generation/kind; missing legal/assignment/delegation evidence; revoked authority at cutover |
| Transfer Saga | source write during freeze; staging read by normal role; stale source job/file/export after switch; duplicate/out-of-order event |
| Contact change | unverified new contact; proof replay/wrong subject; alias gap; duplicate mobile+grade; concurrent rotation/transfer |
| Files and attachments | guessed object ID; expired signed URL; URL after ownership generation change; wrong Workspace namespace |
| Reports and exports | unauthorized filters; cross-tenant aggregate leakage; background export after permission revocation |
| Notifications | recipient substitution; child/Workspace mismatch; stale queued notification after transfer; sensitive data in event payload |
| Background jobs | caller-controlled Workspace; generation mismatch; retry duplicate side effect; execution after membership/assignment revocation |

Each endpoint and worker must have a traceable test ID, required principal, tenant/relationship context, expected HTTP/result code and audit assertion before API implementation is accepted.
