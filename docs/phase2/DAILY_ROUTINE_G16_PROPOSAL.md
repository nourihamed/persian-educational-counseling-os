# G-16 — DailyRoutine counters: approved domain and acceptance contract

**Status:** Product Owner semantics APPROVED on 2026-11-23; schema/runtime implementation NOT VERIFIED.  
**Decision record:** [PO_DECISION_G16_DAILY_ROUTINE_COUNTERS_2026-11-23.md](PO_DECISION_G16_DAILY_ROUTINE_COUNTERS_2026-11-23.md)  
**Source requirement:** Phase 2 gap matrix, master requirement §29 (numeric target and completed values).

## 1. Verified current gap

The current Workspace draft stores `daily_routines.schedule_spec` as JSONB and has no normalized counter/event facts. A schedule specification is not an execution counter. No existing evidence establishes enforceable numeric target/completed persistence, unit consistency, actor authorization, event immutability, idempotency, concurrency safety, or backdating controls.

## 2. Approved domain contract

- Multiple named counters may belong to one DailyRoutine; each is an independent measurement dimension.
- Units reference a standardized, extensible vocabulary governed centrally by Platform. Workspace-local unit definitions and free-text units are not approved.
- Both the student and responsible counselor may append progress events, with authenticated actor attribution.
- Corrections are compensating append-only events. Only the original event author or responsible counselor may append one; a reason and reference to the original event are mandatory.
- Original events and correction history are immutable. Current values are derived by aggregating events.
- Every event command has an idempotency key. Same-key/same-payload retry returns the original result; same-key/different-payload is rejected.
- Simultaneous valid events must both persist through atomic transactions and concurrency control.
- Store both `occurred_at` (user-asserted) and `recorded_at` (server-authoritative).
- Negative values are prohibited by default; Platform may explicitly enable them per counter.
- Counters are archived, not deleted. Archived counters retain history and reject new events. Reactivation is not approved.
- Backdated entry is permitted within a Platform-configured maximum window. A reason is required only when delay exceeds a Platform-configured threshold.
- Workspace timezone governs local-date/delay interpretation. Each event preserves its timezone/local-date basis; timezone changes apply only to future events.
- No generic optional event-note field is required.

See the PO decision record for the complete normative invariants and open decisions.

## 3. Required normalized model — design guidance, not a pre-approved physical schema

The implementation should provide equivalent integrity-bearing structures for:

1. **Counter definition** — parent DailyRoutine, stable identity, display name/key, controlled unit reference, numeric target/value policy, archive state, ownership/tenant keys.
2. **Unit vocabulary** — Platform-owned stable unit identity and controlled lifecycle; no Workspace mutation path.
3. **Counter event ledger** — immutable event identity, counter reference, event kind, signed/typed amount or delta, actor identity/kind, `occurred_at`, `recorded_at`, timezone/local-date basis, idempotency identity, and correction linkage/reason where applicable.
4. **Configuration provenance** — versioned/effective Platform settings for maximum backdating and late-reason threshold; do not seed invented numeric defaults.
5. **Derived current value** — computed from the authoritative event ledger. Any optimization must be rebuildable and transactionally consistent.

This is logical guidance only. Exact table names, columns, precision, event taxonomy, idempotency scope, and materialization design remain implementation decisions subject to independent review and the open questions in the PO decision record.

## 4. Mandatory integrity and security requirements

- Composite foreign keys or equivalent constraints must prevent cross-Workspace, cross-student, cross-routine, cross-counter, and invalid correction references.
- Actor authority must be verified at the trusted command boundary using live membership/assignment and object ownership. Never trust caller-supplied actor IDs, roles, or responsibility flags.
- Enforce append-only behavior against UPDATE/DELETE and unauthorized TRUNCATE paths for the event ledger.
- Enforce idempotency under concurrency; same key with different canonical payload must fail.
- Ensure transaction isolation/locking prevents lost events and prevents archive/policy changes racing with event insertion.
- A correction must be atomic, attributable, reasoned, and bounded by a defined correction policy; unresolved over-correction semantics must not be guessed.
- Reject negative aggregate values unless that counter's explicit Platform policy enables them.
- Archived counters must reject new events while preserving historical reads.
- Server sets `recorded_at`; clients cannot override it.
- Validate backdating against the applicable Platform configuration and event's preserved Workspace timezone basis. Missing/invalid configuration must not silently allow unbounded backdating.
- No production runtime write privileges or real student data are implied by this contract.

## 5. Acceptance test matrix

### Schema and ownership
- Multiple counters per routine; stable counter identity/uniqueness.
- Unit FK accepts only Platform vocabulary and rejects arbitrary/free-text/local units.
- Cross-Workspace, cross-student, cross-routine, and cross-counter references are rejected.
- Platform-only unit/config mutation; Workspace roles cannot add/change units or negative-value policy.
- Numeric precision, bounds, target mutation and event semantics tested after PO decisions close those details.

### Authorization and audit
- Student can append only for own authorized routine/counter.
- Responsible counselor can append only for currently assigned student/routine.
- Unassigned counselor, other student, other Workspace, revoked/inactive membership/assignment, and forged actor claims are rejected.
- Correction accepted only from original event author or responsible counselor.
- Correction without reason, without original-event reference, or referencing another counter/tenant is rejected.
- Event UPDATE/DELETE/TRUNCATE and history rewrite are denied for application roles.

### Idempotency and concurrency
- Same key + same payload returns original outcome and creates exactly one event.
- Same key + different payload is rejected.
- Concurrent same-key requests create one event.
- Concurrent distinct valid increments/events are both retained; no lost update.
- Event insertion racing with archive or policy change has deterministic, tested serialization.
- Correction races cannot double-compensate beyond the approved correction policy.

### Time and configuration
- Both timestamps are stored; server controls `recorded_at`.
- Backdating inside/outside configured maximum is tested.
- Late reason is required strictly when delay exceeds configured threshold; equality boundary is tested.
- Missing/invalid configuration fails closed.
- Workspace timezone change does not rewrite existing event interpretation; new events use the new timezone.
- Local midnight and DST boundaries are tested once their exact semantics are decided.
- Future timestamps/client clock skew are tested once their validation contract is decided.

### Lifecycle and derived values
- Archive preserves all events and rejects all new events.
- No reactivation route exists without a new PO decision.
- Derived totals reconcile with the immutable ledger and can be rebuilt.
- Negative aggregate rejected by default; explicit per-counter Platform enablement permits only the approved behavior.
- No unapproved completion %, mastery, risk, or recommendation formula is introduced.

## 6. Open decisions — implementation must not invent

Refer to §3 of the PO decision record. In particular: numeric precision/bounds, target mutation, event taxonomy/delta semantics, partial/multiple corrections and over-correction, idempotency scope/retention, configuration values/effective-time behavior, clock skew/future timestamps, local-midnight/DST edge semantics, unit lifecycle/localization, counter creation/edit/version authority, and aggregate caching consistency.

## 7. Gate

G-16 Product Owner semantic decisions are closed for the choices explicitly listed in the decision record. G-16 implementation is **OPEN / BLOCKING** until the normalized model, trusted actor enforcement, ledger constraints, idempotency/concurrency, Platform configuration, timezone handling, and acceptance suites are implemented and independently reviewed.

No Phase 2 approval, Phase 3 authorization, production runtime write path, production migration, or real-data authorization is granted. D-014 remains synthetic-only.
