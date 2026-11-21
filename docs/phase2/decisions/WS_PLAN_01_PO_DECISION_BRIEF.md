# WS-PLAN-01 — Product Owner decision brief (A–E)

**Status:** DECIDED by the Product Owner on 2026-11-20 — **A2, B1, C1, D1, E1** (recorded in `DECISION_LOG.md`). Transitions these decisions do not name stay open and fail-closed. The analysis below is kept as the record of what was weighed.

**Original status:** DECISIONS REQUIRED. **Prepared:** 2026-11-20 by the implementation agent.
**Baseline:** `bba7281` (implementation `fe08a77`; F-05 accepted at architecture-review level).
**Until each decision is recorded,** the affected operation stays **fail-closed** as it is today. WS-PLAN-01 stays
`BLOCKING`.

**What exists now**
- Plan items reference exactly one typed source (topic, subtopic, activity, exam, review or assignment).
- Item definitions are insert-only, and an item can be added only to a draft version.
- Status changes are stored as append-only transitions, each with a sequence number, actor, time and reason.
  The database refuses a stale transition and refuses a concurrent duplicate.

**What is refused now (fail-closed)**
- Every transition by a real application identity. Only a synthetic test identity can write one.
- Any transition whose actor is a student.
- A transition on an item of a draft version.
- Publishing a normalized version with no items.
- Creating a new `legacy_json` version, except by the migration identity.

---

## A. Who may record each status transition?

**Product impact.** This decides whether students report their own progress ("I finished this"), or only the counselor
records it.

**Security and audit.**
- **Any option that lets students write needs a real student identity**, so that one student cannot write as
  another. That is the WS-ISO-01 caller-binding decision, which is still open. Until it exists, no option can be
  enabled for real users.
- **Every transition already stores who made it, when and why**, so audit is the same under all options.

| Option | Rule | What changes |
|---|---|---|
| A1 | Assigned counselor only | Students cannot report progress; counselors carry the data entry |
| A2 | Student self-reports execution (`in_progress`, `completed`, `partially_completed`); the counselor alone may record `deferred`, `skipped`, `cancelled` | Needs a student identity binding; the actor kind `student` is enabled only for those three statuses |
| A3 | Both may record any status; a later counselor transition overrides | Simplest UX; weakest accountability; still needs the student binding |

**Recommendation: A2.** Execution is the student's fact, and dropping work is the counselor's decision.
**Under A2, these change:**
- the refusal of `actor_kind='student'` is replaced by a per-status rule;
- new tests: per-status actor tests, plus a student acting on another student's item → refused.

## B. Can a transition be recorded while the item belongs to a draft version?

**Product impact.** Draft plans are still being edited. Recording progress on them would mix planning with execution.

**Security and audit.** Draft items can still be replaced by a new version, so status history on a draft could refer
to items that are later discarded.

| Option | Rule | What changes |
|---|---|---|
| B1 | No: only items of a **published** version | Nothing (current behaviour) |
| B2 | Yes, and transitions carry over to the published version | Needs an item-identity mapping across versions; harder to audit |

**Recommendation: B1.** It is what the schema does today, and it keeps "what was planned" separate from "what
happened".

## C. Can an empty normalized plan version be published?

**Product impact.** An empty plan might be used deliberately, for example as "a rest week", or might be published by
mistake.

**Security and audit.** There is no security effect. For audit, an empty publication is indistinguishable from an
error unless it has to state a reason.

| Option | Rule | What changes |
|---|---|---|
| C1 | Never | Nothing (current behaviour) |
| C2 | Allowed only with a mandatory reason, such as "rest week" | A reason column or vocabulary on the version; tests for publishing with and without a reason |
| C3 | Always allowed | The refusal is removed |

**Recommendation: C2 if rest weeks are a real use case; otherwise C1.**

## D. Permitted transition graph

**Product impact.** The graph defines what a counselor or student can do with an item, and what counts as finished.

**Security and audit.** A graph limits silent rewriting of history. Without one, any status can follow any other
(apart from the stale-transition check), so `completed → planned` is possible today.

**Proposed graph D1 (recommended):**

| From | Allowed to |
|---|---|
| `planned` | `in_progress`, `completed`, `partially_completed`, `deferred`, `skipped`, `cancelled` |
| `in_progress` | `completed`, `partially_completed`, `deferred`, `cancelled` |
| `partially_completed` | `in_progress`, `completed`, `deferred` |
| `deferred` | `planned` (re-scheduled), `cancelled` |
| `completed`, `skipped`, `cancelled` | terminal; a correction is a new plan version with a reason |

| Option | What changes |
|---|---|
| D1 | One table of allowed edges, enforced by a trigger; a test for every allowed and every forbidden pair (49 pairs) |
| D2: no graph, any transition allowed | Nothing changes; history can be rewritten freely |
| D3: D1, plus counselor-only correction edges out of terminal states (e.g. `completed → planned`) with a mandatory reason | As D1, plus actor-specific edges, which depend on A |

**Recommendation: D1.** Terminal means terminal, and corrections go through versioning, which the model already supports.

## E. Historical JSON plans and migration

**Product impact.** This decides whether old plans become item-level data (so they count in analytics), or stay
read-only documents.

**Security and audit.** Automatic conversion makes up structure that the original plan did not have. Any conversion
must be traceable to its source version.

| Option | Rule | What changes |
|---|---|---|
| E1 | Keep as `legacy_json`, read-only, never converted (current behaviour) | Nothing; analytics ignore legacy plans |
| E2 | Counselor-initiated conversion: the counselor creates a new normalized version that supersedes the legacy one, with a reason | Needs a counselor identity (WS-ISO-01); new tests for the supersession |
| E3 | Automatic bulk conversion by rules | Needs written mapping rules from the Product Owner, plus a provenance column and a dry-run report |

**Recommendation: E1 now, and E2 once WS-ISO-01 is closed.** E3 only with written mapping rules.

**Not covered by any option:** whether a migrator identity may ever run in production. That is an Operations /
Platform Security decision.

---

## How to answer

For each of A–E, reply with the option (for example "A2, B1, C1, D1, E1") or a written alternative. The agent will
then:
- record the decisions in `DECISION_LOG.md` and both registers;
- implement only what was decided;
- add actor, graph, concurrency and stale-state tests, each with a negative control;
- keep A disabled for real identities until WS-ISO-01 is closed, whatever option is chosen.
