# API.md

Status: DRAFT — Phase 0 — Strategy only. No endpoints implemented yet.

## 1. Style
- FastAPI, Pydantic v2 schemas for request/response (never expose ORM models directly).
- REST-ish resource structure, versioned from day one: `/api/v1/...`
- JSON only; errors follow a consistent envelope (`error.code`, `error.message`, `error.details`), no leaking of stack traces or internal identifiers in production.

## 2. AuthN/AuthZ on every request
- Every non-public endpoint requires a valid access token (Master Prompt §47).
- Authorization is resolved from the authenticated principal's role + tenant membership — **never** from a `tenant_id`/`counselor_id` passed in the request body or query string. Client-supplied tenant IDs are, at most, validated against the resolved identity, never trusted as the source of truth (IDOR prevention, ties to ARCHITECTURE.md §3).
- Platform Admin endpoints are a separate router group with mandatory audit logging.

## 3. Planned Resource Groups (names indicative, not final)

```
/auth            register, login, logout, refresh, password-reset
/admin/*         platform admin operations (counselors, plans, programs catalog, reports, audit)
/counselor/*     counselor-scoped: students, programs, plans, analytics, notes
/student/*       student-scoped: today, plan, activities, tests, errors, progress
/parent/*        parent-scoped: high-level progress views
/billing/*        orders, subscriptions, credits (read + purchase-intent; real payment flow deferred)
/notifications/* in-app notification feed, preferences
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
Per D-012 / resolved Q-013, MVP endpoints for program versions handle only tenant-owned `ProgramTemplate` and `ProgramVersion` rows; a version must belong to the same Tenant as its source template. Platform-owned/shared catalog endpoints are out of MVP and require a separate future decision. Student plan-version endpoints remain tenant- and student-scoped without exception. No endpoint bypasses authorization. No endpoint is designed in detail or implemented yet. D-008 confirms minimum versioning is in MVP scope; D-012 resolves MVP ownership but does not design endpoints in detail.

## 9. Deferred
- OpenAPI schema generation conventions, error code catalog, and concrete DTOs → Phase 3/4 onward, per domain as each phase is implemented.
- Detailed design of versioning endpoints (§8) → Phase 2 schema finalization. (Not pending a Product Owner decision anymore — D-008/Q-012 already settled the policy question; this is ordinary design work.)
