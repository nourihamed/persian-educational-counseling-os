# ARCHITECTURE.md

Status: DRAFT — Phase 0 — Foundation (no implementation yet)

## 1. Layering

```
API Layer         (FastAPI routers, request/response schemas, no business logic)
Application Layer (use-cases / services, orchestration, transactions)
Domain Layer       (entities, value objects, domain rules, invariants)
Infrastructure Layer (SQLAlchemy models/repositories, adapters: Payment, Telegram, SMS, AI, Storage)
```

Rule (non-negotiable, Master Prompt §50, §66): business logic never lives in routes; routes only validate input, call an application service, and shape output.

## 2. Multi-Tenancy Strategy

**Tenant = Counselor.** Every tenant-scoped row carries a `tenant_id` (= owning Counselor's id, even when the row is logically a Student's — the Student belongs to exactly one tenant via `CounselorStudent`).

**Decision accepted by the Product Owner on 2026-10-12:** use one shared PostgreSQL database/schema with direct, indexed, `NOT NULL` `tenant_id` on every tenant-scoped row; application/API authorization and PostgreSQL Row-Level Security (RLS) are both required layers. See `DECISION_LOG.md` D-009 and resolved `OPEN_QUESTIONS.md` Q-001. This is the selected MVP mechanism, not proof of implemented or tested runtime security.

- Derive the request-scoped tenant context from the authenticated principal; never trust a path/body tenant identifier by itself.
- Require explicit tenant context for every tenant repository operation and object-level authorization for each resource/action.
- Enforce parent/child tenant consistency using composite foreign keys/constraints or an equivalent database-enforced mechanism.
- Keep Platform Admin cross-tenant access explicit, least-privileged, and audited.
- Database runtime roles must not own tenant tables or have privileged RLS-bypass capabilities; review table-owner behavior and use forced RLS or equivalent safeguards where appropriate.
- Add negative isolation tests for API/repositories and for background jobs, reports/exports, files, and notifications.

Schema-per-tenant and database-per-tenant are not selected for the MVP because of their operational/migration/backup overhead. Reconsideration requires a documented architecture decision; the choice must not weaken the non-negotiable tenant-isolation requirement.

## 3. Isolation applies to every surface (Master Prompt §3)

| Surface | Isolation mechanism (planned) |
|---|---|
| Database | `tenant_id` + RLS |
| API | Authorization middleware resolves tenant from the authenticated principal; path/body IDs are never trusted alone (IDOR protection) |
| Services | Application services require an explicit tenant context object, no ambient global |
| Queries | Repository layer injects `tenant_id` filter automatically; raw queries forbidden outside Infrastructure layer |
| Reports | Report generation runs inside the same tenant-scoped repository calls |
| Files | Storage paths are namespaced by `tenant_id`; signed, time-limited URLs only |
| Notifications | Delivery queue entries carry `tenant_id`; adapters never fan out across tenants |
| Background Jobs | Each job run is bound to a single `tenant_id` (or explicitly marked platform-level) |

## 4. Adapter Boundaries (Master Prompt §66)

Core domain depends only on interfaces it owns:

```
Core
 ├── NotificationService → NotificationAdapter (InApp | Telegram | SMS)
 ├── PaymentService       → PaymentProvider (Mock | Real gateway, chosen later — Q-004)
 └── AIService             → AIProvider
```

Rules:
- Core modules never import a vendor SDK directly.
- Adapter failures are caught at the Infrastructure boundary and surfaced as domain-level outcomes (e.g. `DeliveryFailed`), never as unhandled exceptions that crash a request or job.
- Each adapter has a `Mock`/`Fake` implementation usable in tests and local dev without network access.

## 5. Billing/Domain Separation (Master Prompt §9, §45)

`CounselorAccount`, `CounselorSubscription`, and `StudentCredit` are distinct aggregates. A `StudentCredit` balance is never stored as a mutable counter — it is derived from an append-only `CreditTransaction` ledger (see DATABASE.md, DECISION_LOG.md D-002).

## 6. Versioning (Master Prompt §71, §72)

**MVP status (per `DECISION_LOG.md` D-008 — Accepted, explicit Product Owner confirmation on 2026-10-10; `OPEN_QUESTIONS.md` Q-012 Resolved):** the minimum viable, auditable versioning described below is an **MVP requirement**, not a Phase-15-only feature. Only the *advanced* version-management tooling (visual diff, rollback UI, extensive history browsing, branching/parallel versions, change-impact reports) is deferred to Phase 15 and beyond. This resolves an earlier inconsistency where `PROJECT_SCOPE.md` and `ROADMAP.md` could be read as deferring versioning entirely to Phase 15. Detailed state-transition rules and the exact schema are still open design work for Phase 2 — D-008's acceptance settles the *policy*, not the final column-level design.

- `ProgramTemplate` has many `ProgramVersion`s. A `ProgramVersion` is immutable once published; "editing" a program creates a new version, never a silent overwrite of a published one.
- A `Student`'s active enrollment points at one specific `ProgramVersion`, never "the template" — so template edits never silently change a student's plan. The `ProgramVersion` used to create each student plan is recorded, so the origin of any existing plan is explainable later.
- `Plan` (daily/weekly/etc.) is versioned per student per period (`WeekPlan v1, v2, v3...`); history is retained, never overwritten. Which plan states are directly editable in place versus which require creating a new `PlanVersion` is a Phase 2 schema decision, not decided in this document.
- **Tenant isolation and authorization implications — stated precisely, not blanket:**
  - **`PlanVersion` is scoped to exactly one tenant and exactly one student within that tenant, unconditionally, with no exception.** Reading or writing any `PlanVersion` — including listing its history — goes through the same tenant-and-student-scoped repository pattern described in §2/§3; there is no version-level exception to this, regardless of anything else in this section.
  - **`ProgramVersion`'s tenant scoping is unconditional only when its source `ProgramTemplate` is tenant-owned** (today's only designed case). **When the source template is a possible, future platform-owned template, the ownership/authorization model for the resulting `ProgramVersion` is explicitly undecided — see `OPEN_QUESTIONS.md` Q-013 (part 2).** This document does not select or imply nullable `tenant_id`, a separate ownership flag, a separate table, copy-on-use, global read-only access, or any other model for that case. What is **not** open, regardless of how Q-013 is eventually resolved: every read, write, activation, and history-access operation on a `ProgramVersion` **must be authorized** — "platform-owned" is never a synonym for "unauthenticated" or "unrestricted," and no operation is ever exempt from an authorization check.
  - Every version-creating or version-activating action, on either `ProgramVersion` or `PlanVersion`, records the acting user (actor attribution), consistent with the Explainability contract in §7 below — this requirement does not depend on how Q-013 is resolved.
- **Transaction safety:** creating a new version and activating it (making it the current one referenced by an enrollment or an active plan period) must happen atomically — a partially-applied version switch must never leave an enrollment or plan pointing at an inconsistent state. This is a correctness requirement for whichever phase implements it; it is not implemented yet (Phase 0 is documentation-only).
- This section describes conceptual behavior only. No migration, table, or endpoint implementing any of the above exists yet.

## 7. Explainability as an architectural concern (Master Prompt §31, §68)

Any component that produces a recommendation, risk flag, priority, or auto-generated review must return a structured **reason set**, not just a result. Planned shape (illustrative, not final):

```
Decision {
  outcome
  reasons: [ { factor, evidence, weight? } ]
  generated_at
  rule_version
}
```

This is a cross-cutting contract, not a single module — the Planning Engine, Risk Engine, and Review Engine all produce this shape.

## 8. Calendar Isolation (Master Prompt §52)

Jalali⇄Gregorian conversion lives in one isolated module (`domain/calendar` or equivalent), used everywhere dates are displayed/computed. No ad-hoc date math elsewhere.

## 9. Deferred Architectural Decisions

Tracked in `OPEN_QUESTIONS.md`:
- Detailed policy/constraint/test design for the accepted tenant isolation mechanism (Q-001 resolved)
- Concrete VPS provider/plan and adapter-specific external-service reachability (Q-010 approach accepted; vendor remains unselected)
- Payment gateway target (Q-004)

No code, migration, or infrastructure provisioning happens in Phase 0.
