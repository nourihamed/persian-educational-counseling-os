# ARCHITECTURE.md

Status: conceptual architecture baseline; no implementation yet. Current tenant-isolation topology is governed by D-020/D-023 and Phase 1 design docs.

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

**Current isolation direction (D-020 / Phase 1):** Alt-5 hybrid isolation cells, with Alt-4 as the security reference. Each cell requires a distinct host/VM and network boundary and its own PostgreSQL cluster/instance; each tenant has its own database and tenant-specific runtime credential within that cell. Tenant/cell routing is derived from authenticated, server-verified membership. D-023 adds Level 3 infrastructure/administrative independence for cells and Level 4 independent administrative control of critical backups/recovery. D-009/Q-001 recorded an earlier shared-database mechanism; it is historical and is superseded as the active isolation topology by D-020. This remains design-only, not proof of implementation or runtime security.

**Scope qualification (D-012 accepted; Q-013 resolved):** In the MVP, `ProgramTemplate` and its `ProgramVersion` rows are tenant-owned only, with `tenant_id NOT NULL`; a Version must belong to the same Tenant as its source Template. Platform-owned/shared catalog templates and their versions are out of MVP. Do not implement nullable tenant ownership or mixed-ownership shared rows under the MVP decision. A future platform catalog requires a separate architecture decision before implementation. Student enrollments, plans, and student-facing records remain tenant-owned without exception.

- Derive tenant/cell routing from authenticated, server-verified membership; never trust request-supplied tenant/cell/database identifiers.
- Give each tenant its own database and tenant-specific runtime credential within its assigned cell; enforce host/VM and network boundaries between cells.
- Require object-level authorization for every resource/action and tenant-aware relationship constraints within each tenant database.
- Keep Platform Admin cross-tenant access explicit, least-privileged, read-only where D-013 requires, and audited.
- Scope workers, secrets, migrations, backup/restore identities and privileged operations; routine deployment authority must not imply data-read or backup-key authority.
- Meet D-023 Level 3 cell administrative independence and Level 4 critical-backup independence; provider-global compromise remains an explicit residual.
- RLS may be used as defense in depth within a tenant database, but is not the cell boundary and does not protect against host/root compromise.
- Add adversarial tests for API/object authorization, network and credentials, jobs, reports/exports, files, notifications, backup/restore, revocation and privileged access.

The earlier statement that database-per-tenant was not selected is superseded by D-020 for the active Alt-5 design. Within-cell tenant databases are required; the concrete hosted topology/provider remains open under Q-023 and must meet D-023 before hosted deployment. No capacity or provider claim is established.

## 3. Isolation applies to every surface (Master Prompt §3)

| Surface | Isolation mechanism (planned) |
|---|---|
| Database | Separate PostgreSQL cluster/instance per cell; separate database and credential per tenant; optional RLS as defense in depth |
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
  - **MVP rule (D-012 / Q-013):** `ProgramVersion` is tenant-owned and must belong to the same Tenant as its source `ProgramTemplate`; platform-owned source templates and their versions are out of MVP. Any future platform catalog requires a separate decision before implementation. Every read, write, publish, activation, and history-access operation on a `ProgramVersion` must be authorized.
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
- Alt-5 isolation-cell implementation and adversarial verification (D-020/D-023; design-only in Phase 1; implementation/test gates remain open)
- Concrete hosting candidate, account/admin boundary, backup independence, provider/plan and capacity (Q-023 remains open; provider selection deferred until hosted deployment planning)
- Payment gateway target (Q-004)

No code, migration, or infrastructure provisioning happens in Phase 0.
