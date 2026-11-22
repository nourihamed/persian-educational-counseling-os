# G-15 — Review domain completeness and duplicate-generation policy

**Status:** Supervisor proposal — NOT APPROVED.  
**Date:** 2026-11-22  
**Authority:** Product Owner decisions required for product semantics not fixed by the repository's master requirements.

## 1. Verified requirement and current gap

The Phase 2 gap matrix identifies master requirement §28 as requiring each Review record to retain:
- the original activity being reviewed;
- review method;
- mastery before and after;
- review result; and
- prevention of duplicate review generation.

The current `reviews` table in `workspace_schema_draft.sql` contains only:
`review_id`, `student_id`, optional `topic_id`, `scheduled_at`, optional `cadence_days`,
`state`, and `completed_at`. It has no original-activity link, method, mastery-before/after,
result, or duplicate-generation constraint.

The product requirements also identify spaced repetition as 1-3-7 and configurable. This document
does not invent method/result vocabularies, mastery scales, or generation lifecycle rules.

## 2. Required design invariants (not optional)

1. A Review must be attributable to exactly one student and one original activity.
2. Review method, mastery before/after, and result must be persisted as structured, queryable facts.
3. Duplicate generation must be prevented transactionally, not only by application-side pre-checks.
4. Tenant/Workspace and student ownership must be enforced through relational constraints and authorization.
5. Review history must remain auditable; a completed review must not be silently overwritten by regeneration.
6. Cadence and scheduled time must preserve the configured spaced-repetition policy and the relevant timezone/date semantics.
7. Unknown method/result vocabularies and mastery scale semantics remain open; do not invent enum values or numeric ranges.

## 3. Duplicate-generation policy — Product Owner decision required

The critical unresolved question is whether one original activity may intentionally start more than one
independent review sequence over time.

### Option A — One sequence per original activity (simplest)

- Each original activity may have at most one review sequence.
- Each cadence offset (for example, day 1, day 3, day 7) may have at most one Review in that sequence.
- A retry/replay or regeneration request returns the existing Review records; it never creates duplicates.
- A new sequence for the same original activity is prohibited. If a new learning event occurs, it must be represented as a new original activity.

**Database direction:** unique key on `(student_id, original_activity_id, cadence_offset)`, with a typed FK
to the original Activity and an idempotent generation command.

### Option B — Multiple explicit sequences per original activity (more flexible)

- One original activity may have multiple review sequences only when a counselor/system command explicitly
  starts a new sequence with a distinct `review_series_id`.
- Within one sequence, each cadence offset may exist only once.
- Replay/regeneration of the same sequence is idempotent and returns the existing records.
- A new sequence must retain its own creation actor, timestamp, reason and generation-policy version.

**Database direction:** a ReviewSeries entity linked to the original Activity; unique key on
`(student_id, review_series_id, cadence_offset)`. This avoids ambiguous duplicate detection while allowing
an explicitly authorized new learning/review cycle.

### Option C — Command-level idempotency only (not recommended)

- Each generation request has a unique idempotency key.
- Replaying the same request is blocked, but two different requests can still create semantically duplicate
  Reviews for the same activity/cadence.

**Supervisor assessment:** Option C does not fully satisfy the requirement "no duplicate generation" because
it prevents request replay but not duplicate semantic schedules. It should not be accepted as the only guard.

## 4. Additional Product Owner inputs still required

These are independent from the duplicate-generation choice and must not be inferred from conventional practice:

1. **Review method vocabulary:** controlled list, free text, or hybrid; exact allowed values.
2. **Review result vocabulary:** exact outcomes and whether partial/failed outcomes are distinct.
3. **Mastery measurement:** scale/type, valid range, and whether before/after values are required for every method/result.
4. **New sequence trigger:** if Option B is chosen, which actor may start it and what reason/evidence is mandatory.
5. **Cadence semantics:** whether configured 1-3-7 values are offsets from original activity completion or from the prior review completion; timezone/date-boundary behavior.

## 5. Supervisor recommendation

Prefer **Option B** if the product must support deliberate re-learning or a new review cycle for the same
original activity without falsifying history. Prefer **Option A** only if Product Owner confirms that a
single original activity can never legitimately have a second review sequence. Do not implement the
uniqueness key until this choice is explicit.

## 6. Scope and gate

This is a proposal, not a product decision or implementation approval. G-15 remains blocking until the
original-activity relationship, required fields, duplicate-generation semantics, constraints, and tests are
complete. No Phase 3 authorization or production data authorization is implied. D-014 remains synthetic-only.
