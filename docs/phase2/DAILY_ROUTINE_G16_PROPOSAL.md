# G-16 — DailyRoutine numeric counters: scope and schema decision

**Status:** Supervisor proposal — NOT APPROVED.  
**Date:** 2026-11-22  
**Source requirement:** Phase 2 gap matrix cites master requirement §29: numeric target and completed values. The current Workspace draft stores `daily_routines.schedule_spec` as JSONB and has no normalized counter rows.

## 1. Verified gap

The current draft does not persist an enforceable numeric target/completed pair for routine execution. A schedule specification is not an execution counter and must not be treated as one. No code or test evidence currently demonstrates numeric target/completed persistence, bounds, unit consistency, or atomic updates.

## 2. Product semantics that must be fixed before schema implementation

A routine may represent one activity or a structured set of daily activities. The requirement does not state whether a routine has one counter or multiple independent counters, nor does it define units or whether partial completion may exceed target.

### Option A — One counter pair per DailyRoutine

- Each DailyRoutine has exactly one numeric target and one numeric completed value.
- The Product Owner must define the unit and whether decimal values are allowed.
- This is simple but cannot naturally represent a routine with multiple independently measured components.

### Option B — Multiple named counter rows per DailyRoutine

- Each DailyRoutine has one or more named counter dimensions.
- Each counter stores target, completed, unit, and ordering/label metadata.
- A stable key prevents duplicate counter dimensions within the same routine.
- This supports heterogeneous routines (for example, duration and question count) without overloading one number.
- The Product Owner must define allowed unit/metric semantics and whether completed may exceed target.

### Option C — Defer numeric counters from Phase 2

- Phase 2 stores only routine identity/scheduling and does not claim numeric execution tracking.
- The requirement must be explicitly assigned to a later phase with a named gate.
- This is not acceptable if master §29 numeric target/completed tracking is required for MVP.

## 3. Supervisor recommendation

Recommend **Option B** only if the product requires more than one independently measured quantity per routine. Otherwise Option A minimizes schema complexity. Do not implement either until the Product Owner confirms the cardinality and unit semantics. Option C is acceptable only with explicit scope deferral and a downstream phase gate.

## 4. Invariants regardless of option

1. Target and completed values must be numeric and non-negative.
2. The unit/measurement meaning must be explicit and consistent; do not compare or aggregate unlike units.
3. Updates must be tenant/student scoped and attributable to the authenticated student or authorized counselor according to the product's execution-authority policy.
4. Concurrent increments/updates must not lose writes; use atomic update or append-only counter events plus a derived total.
5. Historical daily values must not be silently overwritten when a routine definition changes.
6. Timezone and local-day boundaries must follow the approved scheduling/timezone contract.
7. Counter changes must be auditable and idempotent where commands can be retried.
8. Do not infer completion percentage, mastery, or risk from these counters without a separately specified formula.

## 5. Required tests

- target/completed non-negative constraints;
- unit/key uniqueness;
- cross-student and cross-Workspace FK rejection;
- unauthorized actor rejection;
- concurrent update/increment correctness;
- idempotent replay;
- routine-definition edit/version behavior;
- local-day boundary and timezone behavior;
- preservation of historical counter facts.

## 6. Gate

This document is a proposal only. G-16 remains open until the Product Owner selects A/B/C and unresolved unit/update semantics are specified. No runtime write path, production migration, Phase 2 exit, Phase 3, or real-data authorization is implied. D-014 remains synthetic-only.
