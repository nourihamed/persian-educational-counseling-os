# WS-PLAN-01 — migration notes for the normalized PlanItem model

**Status:** draft design notes. **This is not a production migration**, and the draft SQL is not Alembic.
These notes say what a real migration must preserve and which synthetic test shows it. Synthetic data only (D-014).
**Scope:** Supervisor finding F-04 on `d75d039`.

## 1. The defect this replaces

At `d75d039`, `workspace_plan_items_draft.sql` added the column like this:

```sql
ADD COLUMN content_model text NOT NULL DEFAULT 'normalized'
```

It also added a CHECK requiring a normalized version's `plan_content` to be `'{}'`.

PostgreSQL fills the new column for existing rows from that DEFAULT, then validates the CHECK in the same
statement. That breaks in two ways on a database that already has plan versions:

- a historical row with real JSON content makes the statement **fail** — measured:
  `check constraint "normalized_version_has_no_json_content" ... is violated by some row`;
- a historical row whose JSON happened to be `'{}'` would **silently become** a "normalized" plan with no
  items.

An empty test database shows neither problem, which is why this was missed.

## 2. The rule now

1. **Every row that exists when the migration runs is historical.** It is classified `legacy_json`
   (`ADD COLUMN ... DEFAULT 'legacy_json'`).
2. **Only rows created afterwards default to `normalized`** (`ALTER COLUMN ... SET DEFAULT 'normalized'`).
3. **A historical row's content, status and publication time are not modified.** It stays readable
   through `plan_version_rendered`, which returns the stored JSON for legacy versions.
4. **A legacy row is never relabelled in place.** `content_model` is fixed at creation. Converting a
   historical plan into items means creating a **new normalized version** that supersedes the legacy one,
   with a reason. History is then preserved, and "what was planned, what changed and why" stays answerable.
5. **No new `legacy_json` version can be created by the runtime.** The runtime cannot name
   `content_model` at all (column-level privilege). The trigger accepts `legacy_json` only from the
   dedicated NOLOGIN migration identity `ws_<key>_plan_migrator`. That identity is checked by role
   membership, never by a session variable.
6. **A plan that already has a normalized version cannot regress to `legacy_json`**, not even through
   the migration identity.

## 3. Evidence (synthetic)

`tests/workspace_plan_items_migration_fixture.sql` loads three historical versions **before** the plan
draft is applied:

- one published version with JSON content;
- one draft version whose JSON is `'{}'`;
- one draft version with JSON content.

`tests/workspace_plan_items_migration_tests.sql` (PLN-M01..M08) then asserts:

- all three are `legacy_json`, including the `'{}'` case;
- nothing stored changed;
- each still renders its own JSON;
- the default for new rows is `normalized`;
- a new normalized version can supersede a historical one with a reason;
- a legacy row cannot be relabelled;
- a published historical row stays immutable.

**Control:** applying the `d75d039` form of the column to the same fixture makes the migration itself fail
with the constraint violation quoted above.

## 4. What a production migration still needs (not done here, and not claimed)

- **A real migration framework.** The project names Alembic. These drafts have an implicit load order
  encoded only in the CI workflow.
- **Behaviour at volume.** Lock duration and rewrite cost of `ADD COLUMN ... NOT NULL DEFAULT` on a large
  table, and the backfill plan for it. On PostgreSQL 11 and later, a constant default is stored as metadata
  and does not rewrite the table, but the CHECK still scans every row.
- **Rollback.** Dropping the added columns and constraints is the reverse step, and it is untested.
- **Whether historical JSON should ever be converted into items.** If it should, then by which rules and
  with what provenance. This is a Product Owner question. The data model only guarantees that a
  conversion would be a new, attributed, reasoned version, and never an in-place rewrite.
- **Authority to operate `ws_<key>_plan_migrator`.** Who may assume it, when, and with what audit is an
  operational decision. No application role is a member of it.
