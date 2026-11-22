# G-26 — Database migration and rollout acceptance contract

**Status:** Supervisor technical acceptance contract — design requirements, not implementation approval.  
**Date:** 2026-11-22  
**Scope:** Safe evolution of the Phase 2 PostgreSQL schema from reviewed drafts into versioned migrations. Production migration remains prohibited until Phase 2 gate and separate operational/security approvals pass.

## 1. Current verified gap

The Phase 2 SQL files are draft schema/function definitions loaded by CI in a controlled order. The gap matrix records no production migration framework, no complete upgrade/downgrade strategy, no lock-impact measurement, and only a historical migration fixture. A test load order is not a migration history.

## 2. Required migration architecture

1. Select and pin a migration framework/version (Alembic is the current project preference, not yet approved as an implementation fact).
2. Every migration has a unique immutable revision ID, explicit parent revision(s), deterministic ordering, and a human-readable purpose.
3. A clean database must be buildable from zero using only the migration chain; no hidden bootstrap SQL or manual preconditions.
4. An existing supported baseline must upgrade to the target schema with data-preserving transformations.
5. Migration execution must be serialized; concurrent runners must not apply the same revision twice.
6. Migration identity/role must be distinct from runtime application roles; no runtime role may create/alter schema or execute migration commands.
7. Tenant/Workspace ownership, RLS, grants, triggers, constraints, SECURITY DEFINER hardening, and role membership checks must be part of the reproducible migration outcome.
8. Migration scripts must not contain production secrets, synthetic test keys, or environment-specific credentials.
9. Destructive changes require an explicit expand/contract plan, backup/restore precondition, and an approved retention/legal-hold check where applicable.
10. Rollback policy must be explicit per migration. Prefer forward-fix for irreversible/data-bearing changes; a downgrade that silently loses data is prohibited.

## 3. Required rollout pattern

For changes affecting live data or application compatibility:
- **Expand:** add backward-compatible nullable structures/columns/indexes or new tables.
- **Backfill:** use bounded, resumable, idempotent batches with progress checkpoints and tenant-aware predicates.
- **Validate:** compare row counts, constraints, ownership invariants, and checksums/semantic totals.
- **Switch:** deploy application compatibility changes only after the expanded schema is ready.
- **Contract:** remove old structures only after all supported application versions no longer depend on them and a separate approval is recorded.

The exact deployment topology and downtime policy remain Operations decisions.

## 4. Minimum test evidence

- empty database → full migration chain;
- prior supported baseline → target revision;
- migration replay/idempotency and duplicate-run locking;
- interrupted migration and safe resume/recovery;
- failure halfway through transactional and non-transactional DDL;
- upgrade data preservation and invariant validation;
- forward-fix path for irreversible migrations;
- role separation and runtime-role denial of DDL;
- RLS/tenant isolation and grants after migration;
- PostgreSQL versions supported by the project;
- representative-volume lock duration, table rewrite, index build and WAL/replication impact;
- backup/restore drill before destructive migration;
- CI on exact final commit.

## 5. Evidence and approval boundary

A successful schema test load does not satisfy this contract. The Developer must provide migration source, a clean-install transcript, upgrade transcript, failure/recovery evidence, role/grant audit, and measured lock/volume results. Operations must approve rollout/backup constraints. Supervisor independently reviews the exact commit.

This contract does not approve Alembic version selection, production rollout, destructive downgrades, provider/hosting choices, or real student data. D-014 remains synthetic-only.
