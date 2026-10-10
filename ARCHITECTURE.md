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

Decision status: the concrete isolation mechanism (Row-Level with Postgres RLS vs. schema-per-tenant vs. database-per-tenant) is **not yet finalized** — see `OPEN_QUESTIONS.md` Q-001 and `DECISION_LOG.md` D-004. This document records the **default working assumption** used for planning Phase 1/2, which is:

- Single shared Postgres database.
- `tenant_id` column (indexed, `NOT NULL`) on every tenant-scoped table.
- Postgres Row-Level Security (RLS) policies as a second, DB-enforced layer beneath the application-level filter — so a bug in the application layer cannot leak data.
- A request-scoped "current tenant" context set once (from the authenticated user) and required by every repository call; repositories must refuse to run an unscoped query against a tenant table.
- Platform Admin is modeled as a cross-tenant role with explicit, audited exceptions — never a default bypass.

This assumption must be re-confirmed (not silently kept) at the start of Phase 1.

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

**MVP status (per `DECISION_LOG.md` D-008, proposed, pending Product Owner confirmation in `OPEN_QUESTIONS.md` Q-012):** the minimum viable, auditable versioning described below is an **MVP requirement**, not a Phase-15-only feature. Only the *advanced* version-management tooling (visual diff, rollback UI, extensive history browsing, branching/parallel versions, change-impact reports) is deferred to Phase 15 and beyond. This resolves an earlier inconsistency where `PROJECT_SCOPE.md` and `ROADMAP.md` could be read as deferring versioning entirely to Phase 15.

- `ProgramTemplate` has many `ProgramVersion`s. A `ProgramVersion` is immutable once published; "editing" a program creates a new version, never a silent overwrite of a published one.
- A `Student`'s active enrollment points at one specific `ProgramVersion`, never "the template" — so template edits never silently change a student's plan. The `ProgramVersion` used to create each student plan is recorded, so the origin of any existing plan is explainable later.
- `Plan` (daily/weekly/etc.) is versioned per student per period (`WeekPlan v1, v2, v3...`); history is retained, never overwritten. Which plan states are directly editable in place versus which require creating a new `PlanVersion` is a Phase 2 schema decision, not decided in this document.
- **Tenant isolation and authorization implications:** every `ProgramVersion` and `PlanVersion` is scoped to exactly one tenant (the owning Counselor) and, for `PlanVersion`, to exactly one student within that tenant. Reading or writing any version — including listing version history — goes through the same tenant-scoped repository pattern described in §2/§3 of this document; there is no version-level exception to tenant isolation. Every version-creating or version-activating action records the acting user (actor attribution), consistent with the Explainability contract in §7 below.
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
- Tenant isolation mechanism, final choice (Q-001)
- Hosting/deployment target (Q-010), which affects whether external SDKs (payment/SMS/Telegram) are reachable
- Payment gateway target (Q-004)

No code, migration, or infrastructure provisioning happens in Phase 0.
