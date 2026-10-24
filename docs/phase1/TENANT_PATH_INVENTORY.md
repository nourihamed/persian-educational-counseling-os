# TENANT_PATH_INVENTORY.md — Active Alt-5 Category-Level Inventory

**Phase:** 1 — architecture/design only.  
**Architecture:** D-020 Alt-5 hybrid isolation cells; D-023 Level 3 production-cell and Level 4 independent critical-backup targets.  
**Status:** Category-level traceability only. No endpoints, runtime code, or implementation-level coverage are claimed. The active contract IDs below must exist in `docs/phase1/TENANT_ISOLATION_TEST_CONTRACTS.md`; historical TI-CTX/TI-CONN/TI-REPO/TI-RPT/TI-EXP/TI-PLAT/TI-FK/TI-BYP/TI-CFG identifiers are not current acceptance evidence unless explicitly mapped in a documented migration table.

This inventory is a denominator for category-level paths, not proof that endpoint-level coverage is complete. Every active path must map to at least one active contract or be explicitly BLOCKED by an owner decision. A mapped specification is not a passed test.

## Path Table

| Path ID | Surface | Access | Trusted tenant/cell source | Active contract mapping | Status |
|---|---|---|---|---|---|
| P-01 | Student read (profile, list, detail) | Read | Authenticated principal → server-verified relationship and tenant registry | TI-API-01, TI-API-02, TI-API-12 | Mapped (category-level) |
| P-02 | Student write (profile, relationship) | Write | Authenticated principal → authorized student relationship; trusted cell registry | TI-API-03, TI-API-04, TI-API-13 | Mapped (category-level) |
| P-03 | Plan read | Read | Plan ownership plus authenticated principal relationship | TI-API-01, TI-API-10, TI-VER-01 | Mapped (representative) |
| P-04 | Plan write (create, edit, submit) | Write | Plan ownership plus authenticated principal; trusted cell registry | TI-API-03, TI-API-10, TI-API-13, TI-VER-01 | Mapped (representative) |
| P-05 | PlanVersion create and activate | Write | Parent Plan ownership; version lineage must remain within tenant/cell | TI-API-10, TI-VER-01, TI-CELL-19 | Mapped |
| P-06 | ProgramTemplate / ProgramVersion read | Read | Tenant-owned template and authorized principal | TI-API-01, TI-API-10, TI-VER-01 | Mapped (representative) |
| P-07 | ProgramTemplate / ProgramVersion write | Write | Tenant-owned template; version and referenced objects remain within tenant/cell | TI-API-03, TI-API-10, TI-VER-01, TI-CELL-19 | Mapped |
| P-08 | StudentProgramEnrollment | Read/Write | Authorized student relationship and trusted tenant/cell mapping | TI-API-03, TI-API-04, TI-CELL-19 | Mapped (representative) |
| P-09 | Study, test, error, review and assignment records | Read/Write | Student ownership and authenticated principal relationship | TI-API-01, TI-API-03, TI-API-04, TI-API-13 | Mapped (representative only; endpoint/record-level inventory is deferred) |
| P-10 | StudentCredit / CreditTransaction ledger | Read/Write | Counselor/tenant ownership; atomic ledger rules | TI-API-11, TI-AUD-01 | Mapped |
| P-11 | Tenant-scoped audit log read | Read | Authenticated actor and explicit tenant authorization; D-013 Platform Admin exception only | TI-API-14 | Mapped |
| P-12 | Audit event creation and integrity | Write | Trusted actor/action/tenant context; no secret or student-content payloads in audit evidence | TI-AUD-01 | Mapped |
| P-13 | Dashboards and aggregates | Read | Server-derived tenant scope; aggregation must not include unauthorized records | TI-API-05 | Mapped |
| P-14 | Search | Read | Tenant/cell-scoped query and namespace | TI-API-08 | Mapped (category-level) |
| P-15 | Pagination, counts and cursors | Read | Tenant-scoped query and cursor | TI-API-02 | Mapped |
| P-16 | Reports (student and multi-student) | Read | Authorized tenant-scoped report query | TI-API-05, TI-JOB-03 | Mapped |
| P-17 | Exports (CSV, Excel, PDF) | Read | Authorized tenant-scoped query and tenant-bound output artifact | TI-API-05, TI-JOB-03 | Mapped |
| P-18 | File upload | Write | Server-authorized owning record; server-derived cell and object key | TI-FILE-03 | Mapped |
| P-19 | File download and signed URL | Read | Record ownership, server authorization and scoped storage access | TI-API-06, TI-FILE-01, TI-FILE-02 | Mapped |
| P-20 | Notification creation | Write | Server-validated recipient and recipient tenant | TI-NOTIF-01 | Mapped |
| P-21 | Notification delivery, retry and dead-letter handling | Read/Write | Trusted delivery row; revalidate tenant and recipient at send time | TI-API-07, TI-NOTIF-01, TI-JOB-01, TI-JOB-02 | Mapped |
| P-22 | Telegram/SMS adapter calls (outbound) | Outbound | Authorized notification row and validated recipient; provider credentials never exposed to tenant | TI-NOTIF-01 | Mapped (tenant scope only; provider-specific controls are later work) |
| P-23 | Tenant-bound background jobs | Read/Write | Job identity is re-resolved from trusted registry/lifecycle state; payload identifiers are not authority | TI-JOB-01, TI-JOB-02, TI-JOB-03 | Mapped |
| P-24 | Platform aggregate jobs | Read (approved aggregates only) | Explicit platform job identity and aggregate-only allowlist | TI-JOB-04 | Mapped |
| P-25 | Platform Admin read | Read | D-013 approved, read-only, audited support path; explicit scope | TI-API-09, TI-API-14 | Mapped |
| P-26 | Platform Admin write | Write | Prohibited in MVP under D-013 | TI-API-09 | PROHIBITED; mapped as a denial/guard requirement |
| P-27 | Parent read | Read | Parent-to-student relationship and Product Owner-approved access policy | TI-API-04 | BLOCKED by Q-007; not counted as covered until the owner decision and implementation-phase contract are resolved |
| P-28 | Authentication and tenant/cell derivation | Read/routing | Authenticated principal → server-verified membership → trusted tenant registry | TI-CELL-01, TI-CELL-02, TI-API-12 | Mapped |
| P-29 | Database migrations and schema administration | Privileged write | Named cell-scoped migration identity; separately approved orchestration | TI-CELL-09, TI-CELL-10 | Mapped |
| P-30 | Operational scripts under `scripts/` | Privileged | Explicit reviewed purpose and cell scope; no universal runtime credential | TI-CODE-01, TI-CELL-09, TI-CELL-10 | Mapped by planned static/privilege guard; no scripts currently exist and test is NOT-RUN |
| P-31 | Database access/raw SQL outside reviewed Infrastructure/repository boundary | Read/Write | Reviewed access boundary and trusted cell routing; no caller-controlled tenant/cell selection | TI-CODE-01 | Mapped by planned static guard; no runtime implementation exists and test is NOT-RUN |
| P-32 | Option D signed-token/context-function mechanism | Privileged | None — Option D is not selected and is not part of the active architecture | None | EXCLUDED from active Alt-5 inventory; historical reference only |
| P-33 | Alt-5 cell routing, tenant database/credential boundary and lifecycle/revocation | Connection/routing | Authenticated membership plus trusted registry; tenant-specific DB credential; cell network boundary | TI-CELL-01, TI-CELL-02, TI-CELL-03, TI-CELL-08, TI-CELL-15, TI-CELL-16 | Mapped |

## Notes and gate boundaries

- The active acceptance catalog is `docs/phase1/TENANT_ISOLATION_TEST_CONTRACTS.md`. Every ID used in the active rows above is required to exist in that catalog. Old TI-CTX/TI-CONN/TI-REPO/TI-RPT/TI-EXP/TI-PLAT/TI-FK/TI-BYP/TI-CFG references are historical and must not be presented as active tests.
- TI-CELL-01/02 cover trusted routing; TI-CELL-03/06/08/22 cover cell/network/database/credential boundaries; TI-CELL-04/05/17 cover worker/secret scope and worker-compromise blast radius; TI-CELL-09/10 cover migration and owner scope; TI-CELL-11/12 cover backup and restore; TI-CELL-13/14 cover deployment and break-glass; TI-CELL-15 covers revocation/session/pool closure; TI-CELL-16/20/21 cover occupancy, moves and lifecycle; TI-CELL-18/23 cover global-root and all-credentials-compromised residual exercises; TI-OPS-01/02/03 cover operations, capacity and break-glass verification.
- TI-API-05 and TI-API-08 are category-level controls for reports/exports/aggregates and search/cache/logging respectively. Phase 2/4 must add endpoint- and record-specific rows; this inventory does not claim such endpoints already exist.
- TI-API-14 is an explicit tenant-scoped audit-read contract. TI-FILE-03 covers upload ownership/routing; it does not replace later file-content validation, malware scanning, size limits, or storage-provider security tests.
- TI-JOB-04 constrains platform aggregate jobs to approved aggregate fields and prohibits routine tenant-content access.
- TI-CODE-01 is a planned static guard; a specification is not evidence that the guard exists or has run.
- P-27 remains BLOCKED by Q-007. P-32 is excluded because Option D is not selected. Neither is counted as covered active functionality.
- Q-014 (exact HTTP status/body for invisible versus nonexistent objects) remains open until Phase 4, but current contract TI-API-01 requires indistinguishable behavior and does not depend on the final numeric status code.
- The direct-connection / pool-size-1 baseline in D-017 remains the recorded pilot default; it is not a capacity result for Alt-5. Transaction pooling is deferred and requires its own compatibility tests and Product Owner decision.

## Summary

- Inventory rows: 41.
- Active Alt-5 paths: 40 (P-01–P-31 and P-33–P-41).
- Mapped active paths: 39; P-09 is representative-only and P-30/P-31 depend on a planned static guard, all NOT-RUN until implementation.
- BLOCKED active paths: 1 (P-27, Q-007); not counted as covered.
- Excluded from active architecture: 1 (P-32, Option D).
- Unmapped active paths: 0 at category level; every active contract ID is mapped to at least one path row. Endpoint/record-level coverage is NOT MEASURABLE until implementation phases.
- Tests implemented/executed/passing: 0 / 0 / 0. This inventory does not claim runtime security.

Recount command (run from repository root): `grep -cE "^\\| P-[0-9]+ " docs/phase1/TENANT_PATH_INVENTORY.md` should print 41.
