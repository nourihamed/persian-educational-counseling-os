# API.md

Status: DRAFT — Phase 0 — Strategy only. No endpoints implemented yet.

## 1. Style
- FastAPI, Pydantic v2 schemas for request/response (never expose ORM models directly).
- REST-ish resource structure, versioned from day one: `/api/v1/...`
- JSON only; errors follow a consistent envelope (`error.code`, `error.message`, `error.details`), no leaking of stack traces or internal identifiers in production.

## 2. AuthN/AuthZ on every request
- Every non-public endpoint requires a valid access token (Master Prompt §47).
- Authorization is resolved from the authenticated principal's Workspace membership, role, resource relationship and scoped permissions — never from a workspace_id, tenant_id, counselor_id or branch_id supplied by the client as proof of access. A client-supplied Workspace identifier may select a requested context only after the server verifies active membership and resolves the trusted Workspace/cell/database mapping. Object-level checks must also verify counselor assignment, branch scope, student enrollment and action permission (IDOR prevention; see ARCHITECTURE.md §2–3).
- Platform Admin endpoints are a separate router group with mandatory audit logging.

## 3. Planned Resource Groups (names indicative, not final)

```
/auth                         register, login, logout, refresh, password-reset
/workspaces                   list only the authenticated user's Workspace memberships and select context
/workspaces/{workspace_id}/*  Workspace-scoped resources after server-side membership/context validation
/admin/*                      platform-admin operations; explicit, least-privileged and audited
/counselors/*                 counselor resources constrained by Workspace membership and student assignment
/students/*                   student resources constrained by active Workspace enrollment and relationship
/parents/*                    parent resources constrained by verified relationship, consent and per-child permissions
/billing/*                    Workspace orders, subscriptions and Student Credit ledger
/notifications/*              in-app feed and preferences, scoped to recipient and Workspace
```

Exact routes/payloads are designed in the phase that implements each domain (Phase 4+), not in Phase 0.

## 4. Rate Limiting
Applied at minimum to `/auth/login`, `/auth/password-reset`, and any public-facing endpoint, per SECURITY.md.

## 5. Idempotency
Billing-affecting endpoints (order creation, payment webhook handlers) must accept/require an idempotency key — documented here as a hard requirement for Phase 21/22 design, not yet implemented.

## 6. Pagination & Filtering
List endpoints (e.g., counselor's student list) use cursor- or offset-based pagination (final choice deferred) and support the filters named in Master Prompt §34 (grade, field, program, level, performance, overdue, exam, risk, last activity).

## 7. Explainability in Responses
Any endpoint returning a risk flag, auto-generated plan item, or auto-generated review must include the `reasons[]` structure defined in ARCHITECTURE.md §7 — this is a response-contract rule, not optional metadata.

## 8. Versioning Endpoints (conceptual — MVP scope confirmed by D-008, detailed design still pending)
Per D-012 / resolved Q-013, MVP endpoints for program versions handle only Workspace-owned `ProgramTemplate` and `ProgramVersion` rows; a version must belong to a template in the same Workspace. Legacy tenant terminology means Workspace only. Platform-owned/shared catalog endpoints are out of MVP and require a separate future decision. Student plan-version endpoints remain tenant- and student-scoped without exception. No endpoint bypasses authorization. No endpoint is designed in detail or implemented yet. D-008 confirms minimum versioning is in MVP scope; D-012 resolves MVP ownership but does not design endpoints in detail.

## 9. Deferred
- OpenAPI schema generation conventions, error code catalog, and concrete DTOs → Phase 3/4 onward, per domain as each phase is implemented.
- Detailed design of versioning endpoints (§8) → Phase 2 schema finalization. (Not pending a Product Owner decision anymore — D-008/Q-012 already settled the policy question; this is ordinary design work.)
