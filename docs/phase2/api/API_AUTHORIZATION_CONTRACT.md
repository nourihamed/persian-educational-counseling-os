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
- High-risk actions enforce MFA/step-up and audit.
