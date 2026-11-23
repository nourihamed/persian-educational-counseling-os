# Product Owner Decision — G-16 DailyRoutine Counters

**Decision date:** 2026-11-23  
**Status:** PRODUCT SEMANTICS APPROVED; IMPLEMENTATION NOT APPROVED  
**Scope:** Phase 2 domain/schema contract for DailyRoutine numeric counters  
**Authority:** Explicit Product Owner selections in the project conversation, 2026-11-22 through 2026-11-23.

## 1. Approved decisions

| Area | Approved decision |
|---|---|
| Counter cardinality | Option B — multiple named counters per DailyRoutine. Each counter is an independent measurement dimension. |
| Unit vocabulary | Option B — standardized, extensible controlled vocabulary; no arbitrary free-text units. |
| Vocabulary governance | Option A — only Platform centrally adds or changes unit definitions. Workspace counselors/managers cannot define local units. |
| Progress-event authority | Option A — both the student and the responsible counselor may append progress events. |
| Event attribution | Every event records the authenticated actor/author. Actor identity must come from the trusted authorization boundary, never caller-supplied identity claims. |
| Correction authority | Option D — the original event author or the responsible counselor may append a compensating correction. |
| Correction reason/linkage | Every correction requires a reason and references the original event. Preserve the full correction chain. |
| History | Append-only immutable event history. Never overwrite/delete an original event or prior correction. Current counter value is derived by aggregating events. |
| Idempotency | Option B — every event command carries a unique idempotency key. A retry returns the original outcome and creates no duplicate. Reuse of the same key with a different payload is rejected. |
| Negative values | Option C with default A — Platform configures the policy per counter; negative values are prohibited by default and may be explicitly enabled for a specific counter. |
| Counter lifecycle | Option B — archive, do not delete. Preserve all history; an archived counter accepts no new events. Reactivation is not approved. |
| Concurrency | Option A — simultaneous valid events are both retained. Use atomic transactions/concurrency control; do not reject a valid second event merely because it is concurrent. |
| Event timestamps | Option B — store both user-asserted `occurred_at` and authoritative server `recorded_at`; preserve both. |
| Backdated entry | Option B — allowed within a maximum window configured by Platform. |
| Late-entry reason | Option B — reason required only when the delay exceeds a Platform-configured threshold. |
| General event notes | Option B — no generic optional note field is required. Reasons remain mandatory for corrections and qualifying late entries. |
| Timezone basis | Option B — Workspace timezone is the basis for local-date and delay interpretation. |
| Workspace timezone changes | Option A — new timezone applies only to future events. Existing events retain their original timezone/local-date basis and are never recalculated. |
| Maximum backdating window | Option D — Platform-configurable; no numeric duration/default is approved in Phase 2. |
| Late-reason threshold | Option B — Platform-configurable; no numeric threshold/default is approved in Phase 2. |

## 2. Normative invariants

1. A counter belongs to exactly one DailyRoutine and remains within the same Workspace/student ownership boundary as its parent routine.
2. Unit identity is a reference to the centrally governed vocabulary. A unit definition used by historical counters must not be silently repurposed; vocabulary changes require stable identity/versioning or a new unit identity.
3. Student and responsible-counselor authority is evaluated at command time against live authenticated membership/assignment and object ownership. No client-supplied actor ID, role, or responsibility flag is trusted.
4. Events are append-only. A correction is a new compensating event, never an UPDATE/DELETE of the event being corrected.
5. Correction chains must be auditable and unambiguous; each correction identifies its original event and mandatory reason. Do not permit cross-counter or cross-tenant correction references.
6. Idempotency scope must be defined so keys cannot collide across actors/tenants/commands. Persist enough request identity/payload fingerprint to reject same-key/different-payload reuse.
7. Counter totals are derived from the event ledger. If a cache/projection is later introduced, it must be rebuildable and transactionally consistent with the authoritative events.
8. Concurrency must not lose increments or corrections. Database transaction boundaries and locking/serialization strategy must be explicit and tested.
9. Negative-value policy is per counter and defaults to prohibited. A correction or aggregate result that would violate the configured policy must fail atomically.
10. Archiving prevents new progress/correction events according to the approved lifecycle; historical reads and audit remain available. No reactivation path is approved.
11. `occurred_at` is user-asserted and must be validated against the Workspace-configured maximum backdating window. `recorded_at` is server-generated and authoritative.
12. Persist the timezone identifier and sufficient local-date/basis metadata with each event so a later Workspace timezone change cannot rewrite prior event interpretation.
13. Maximum backdating duration and late-reason threshold are Platform configuration values. Phase 2 must not invent numeric defaults. Missing/invalid configuration must fail closed for backdated entry; define the operational behavior in the configuration contract before enabling the feature.
14. A late-entry reason is mandatory only when the configured threshold is exceeded. A correction reason is always mandatory. Do not add generic event notes absent a separate PO decision.
15. Do not derive completion percentage, mastery, risk, or educational recommendations from counters without a separately approved formula and versioned semantics.

## 3. Explicitly unresolved — do not invent

- Numeric values, units of measure, and effective-time semantics for the maximum backdating window and late-reason threshold.
- Behavior when either required Platform configuration is missing, invalid, or changed; configuration version/effective-time audit details.
- Exact timestamp precision, accepted client clock skew, and validation of future `occurred_at` values.
- Exact local-midnight and daylight-saving transition handling beyond the approved Workspace-timezone basis and immutable historical interpretation.
- Numeric precision/scale, integer-vs-decimal policy, maximum target/value bounds, and whether target values can change after events exist.
- Exact unit catalog fields, lifecycle/deprecation rules, localization/display labels, and whether a unit can ever be retired.
- Exact event taxonomy and delta sign/range semantics for increment vs correction events.
- Whether a correction may partially compensate an event, whether multiple corrections may reference one original event, and how over-correction is prevented.
- Exact idempotency-key format, retention period, and collision scope.
- Counter creation/edit authority, stable counter key/name uniqueness, ordering, and versioning when a routine changes.
- Whether archived counters can be restored (not approved; implementation must not provide this without a new PO decision).
- Aggregate materialization/caching strategy and read consistency guarantees.
- Platform permission/RBAC and audit workflow for changing unit catalog and per-counter negative-value policy.

## 4. Scope and implementation boundary

- This record closes the Product Owner semantic choices listed in §1 only.
- It does **not** assert that schema, migrations, functions, runtime authorization, API, UI, workers, or tests exist.
- G-16 remains an implementation and independent-review blocker until normalized schema, tenant/actor authorization, constraints, event ledger, idempotency, concurrency, timezone/configuration contracts, and acceptance tests are implemented and independently verified.
- No production migration, production runtime write path, Phase 2 exit, Phase 3 authorization, or real-data authorization is granted.
- D-014 synthetic-only restriction remains in force.
