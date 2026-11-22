# G-17 — Progress and Risk domain: Phase 2 boundary proposal

**Status:** Supervisor proposal — NOT APPROVED.  
**Date:** 2026-11-22  
**Current gap:** the schema stores `progress_snapshots.metrics` as opaque JSONB and has `risk_assessments`, but the gap matrix assigns the explainable Progress/Risk Engine and formula documentation to later Phase 16.

## 1. Recommended phase boundary

### Phase 2 — persist auditable facts, not the full engine

The database/domain phase should establish only the minimum durable facts needed to avoid future data migration:
- student- and Workspace-bound progress snapshot identity and effective time;
- typed provenance/source references for the underlying observations (where the source domain already exists);
- explicit schema/rule version reference when a computed snapshot is persisted;
- assessment/mastery facts with a documented scale reference rather than an untyped numeric value;
- risk assessment record identity, subject/student scope, evaluation timestamp, rule-set version, and status;
- evidence references and concise explanation payload/provenance sufficient to reproduce why a persisted risk flag was created;
- actor/system attribution and immutable audit history for counselor overrides.

No formula, threshold, risk category, mastery scale, weighting, or automatic intervention policy is invented here.

### Phase 16 — implement the explainable engines

Defer to Phase 16:
- progress aggregation formulas;
- mastery calculation and calibration;
- risk dimensions, thresholds, weighting and severity;
- trend detection and cohort comparisons;
- automated recommendations and intervention rules;
- dashboards and explanatory narratives.

Before Phase 16 implementation, each formula/rule set must be deterministic, versioned, testable, explainable, replayable against retained evidence, and subject to explicit domain-owner/PO approval.

## 2. Why not defer all Progress/Risk schema

Deferring every durable fact until Phase 16 risks losing the provenance needed to reconstruct progress and risk decisions from the underlying educational events. Conversely, implementing formulas in Phase 2 would expand scope and create unapproved educational policy.

The recommended boundary preserves source facts and auditability now while deferring derived intelligence.

## 3. Required Product Owner/domain-owner confirmation

1. Confirm that Phase 2 should persist typed base facts/provenance only and Phase 16 owns all formulas and automated decisions.
2. Confirm which mastery scale(s) are authoritative, or explicitly defer mastery values until a scale is approved.
3. Confirm whether risk assessments may be stored as manual counselor observations before the automated engine exists, or whether risk records should remain absent until Phase 16.

## 4. Gate

This is not an approved product decision. Keep opaque JSONB from becoming an undocumented authoritative contract. Do not ship formula/threshold behavior. G-17 remains open until the Phase 2/Phase 16 boundary and minimum base-fact model are accepted. D-014 synthetic-only restrictions remain.
