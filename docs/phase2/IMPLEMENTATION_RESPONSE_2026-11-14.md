# Implementation response — Product Owner decisions PD-2026-11-13-A..F (NOT a supervisor review)

**Author:** implementation agent.
**Base:** PR #12 head `3430816` (the branch had advanced from `db834f7`; this work is on top of `3430816`).
**Status of this document:** an implementation self-assessment. It approves nothing, closes no finding, and
decides no open Product Owner or Platform Security question. Phase 2 remains **NOT READY**; the gate
decision belongs to the independent Supervisor and the Product Owner.
**Data:** synthetic only. D-014 remains in force. No production migration, credential or deployment.

---

## 1. What was implemented

### 1.1 PD-2026-11-13-A — fixed immutable assessment question set (P0)

`question_count` is no longer treated as evidence of question membership. A published
`TestDefinitionVersion` now carries its exact membership and order.

| Object | Purpose |
|---|---|
| `test_definition_version_questions` | the authoritative membership list: `UNIQUE(version_id, question_no)` (order) and `UNIQUE(version_id, item_ref)` (membership) |
| `test_definition_version_guard()` | publishing requires membership count = `question_count` **and** order exactly `1..n`; publishing a `per_attempt` (adaptive) version is refused outright |
| `test_definition_version_question_guard()` | membership and order may change only while the version is a draft; a question cannot be moved to another version |
| `test_responses` composite FKs | `(attempt_id, definition_version_id)` → the attempt's own version, and `(version_question_id, definition_version_id, question_no)` → a question of that same version at its own order |
| `test_attempt_guard()` | the attempt's scoring-policy snapshot must equal the published version's snapshot |

Cross-version substitution is impossible **declaratively**, without a trigger: a response cannot name a
question that does not belong to the version its own attempt was started on.

`item_ref` is the stable identifier of the question in the counselor's own item source. **No item bank is
modelled and no item-bank ownership rule is decided here.**

Field ownership: the topic of a question belongs to `test_definition_version_questions`. `test_responses`
no longer carries its own `topic_id`.

**Tests (executed):** AVQ-01..AVQ-22, WS-ROLE-16, WS-ROLE-17. Negative coverage includes duplicate
membership, duplicate order, response outside the attempted version, attempt policy ≠ version policy,
mutation of published membership (insert/update/reorder/delete), cross-version substitution, and a
runtime role that **holds** the INSERT/UPDATE grant and is still refused by the guard.

### 1.2 PD-2026-11-13-D — Student Credit entitlement lifecycle (P0)

| Object | Purpose |
|---|---|
| `student_entitlements` | one row per activation that spent credit: student, original debit, amount, `activated_at`, `period_end`, state (`consumed`/`reserved`), compensating reversal |
| `student_entitlement_guard()` | identity, amount, activation time and **period end are immutable**; only `consumed → reserved` (with its own reversal) and `reserved → consumed` (reactivation) are legal |
| `credit_wallet_balances` | `available = ledger_balance − reserved_credits − recommitted_credits` |
| `validate_credit_reversal()` (extended) | a debit is refused unless the **spendable** balance covers it, so a returned credit can never fund another student |
| `archive_student_enrollment()` (extended) | inside the window: one compensating reversal + the credit becomes a student-bound reserved entitlement; outside: no credit movement; already compensated: reserved again, never compensated twice |
| `reactivate_student_enrollment()` | free reactivation **only** inside the original period: no new debit, a new enrollment, one capacity slot, the same entitlement re-consumed, `period_end` untouched |
| `expired_reserved_entitlements` | reserved credits whose original period has ended — visible, not acted on |

Window semantics, stated explicitly because the decision text did not fix them:

- The 7 calendar days are evaluated as an **exact 168-hour interval** from the stored activation
  `timestamptz`, so the result does not depend on the session time zone (effectively UTC arithmetic).
- The boundary comparison is `<=` (**inclusive**).
- If the Product Owner means local calendar-day boundaries in Asia/Tehran, that is a one-line policy
  change. It is recorded as an open clarification (OQ-CRD-1), not assumed.
- The entitlement **duration** is NOT chosen by the database. `activate_student_enrollment()` now takes a
  required `p_entitlement_period_end`; an activation without a future entitlement period is refused. This
  changes the function signature (seventh parameter) and every call site and grant was updated.

**Tests (executed):** CRD-01..CRD-27 covering archive inside/outside the window, the boundary bracketed to
one second, reactivation before/after expiry, repeated archive and reactivation, reserved credit offered to
another student, double debit and double compensation, rollback on partial failure, and the ledger/balance
identity. Concurrency: WS-REACT-RACE-01 — two reactivations of one reserved entitlement, coordinated
deterministically through the student row lock (no timing sleep), exactly one succeeds.

### 1.3 PD-2026-11-13-C — transfer approval separation, exception fail-closed (P0)

| Object | Purpose |
|---|---|
| `guard_transfer_approval_separation()` | one person may not hold two incompatible **current** approval kinds for the same transfer |
| `transfer_approval_conflict_exceptions` | the single contemplated exception `source_destination_owner`, with `CHECK (enabled = false)` |
| `guard_transfer_approval_side()` | the recorded authority snapshot must name the source Workspace for `fee_confirmation` and the destination Workspace for `destination_acceptance` |
| `record_transfer_approval()` / `revoke_transfer_approval()` | the only way to write approval evidence, restricted to `cp_transfer_approval_executor` |

The exception is **disabled and unstorable**: enabling it is a reviewable schema change, not DML. Even if a
row were enabled, the guard still raises, because no approved independent enforcement authority exists. No
Platform Admin override exists anywhere. The conflict policy and its authority remain OPEN.

Wall-clock correctness: expiry is now evaluated with `clock_timestamp()` after the case row is locked — in
the insert guard, in `transfer_approvals_current`, and in the switch's approval count — instead of the
transaction-start `now()`.

**Tests (executed):** SEP-01..SEP-29. Unauthorized actors (superuser/table owner, `cp_runtime`,
`cp_transfer_executor`) cannot record or write approval evidence; the same person is refused a second
incompatible kind in both directions; the exception cannot be enabled by any DML; revocation is idempotent
and a second different revocation is refused; after revocation the switch fails closed and ownership and
generation are unchanged.

### 1.4 PD-2026-11-13-B — Activity over authoritative specialized entities (P1)

`activities` now has five typed, foreign-key-backed source columns (`test_attempt_id`, `exam_id`,
`class_session_id`, `assignment_id`, `review_id`) and no `source_type`/`source_id` pair. Each foreign key
**carries `student_id`**, so an Activity can only cite a source of its own student. Two CHECK constraints
force exactly the column matching `activity_kind` to be set; partial unique indexes prevent a second
Activity for the same source record; student and kind are immutable after creation.

`class_participants` and `class_session_participants` were added so that a class-follow-up Activity is
referentially valid only for a student who actually takes part in that session's class.

Field ownership is documented in the schema: the specialized entity owns its domain fields; the Activity
owns only title, due date, priority and state.

**Tests (executed):** ACT-01..ACT-26, including invalid and cross-student sources, two sources at once,
kind/column mismatch, duplicate relationships, deletion of a referenced record, and an assertion that no
untyped polymorphic column exists.

### 1.5 Transfer Saga outbox/inbox reconciliation (P1 — the last open HIGH)

**Control Plane.** `outbox_events` now carries the full envelope — `schema_version`, `payload_hash`,
`student_id`, source and destination Workspace, `ownership_generation`, `correlation_id`, `causation_id` —
and is **completely immutable**: `published_at` was removed and delivery state moved out of the row.
`cp_12_saga_outbox_delivery.sql` adds `outbox_deliveries` (state machine, attempts, dispatcher lease),
`outbox_delivery_audit` (append-only), the dispatcher commands (`claim_outbox_events`,
`record_outbox_sent`, `acknowledge_outbox_event`, `release_outbox_lease`), the operator commands
(`dead_letter_outbox_event`, `redrive_outbox_event`), and the `outbox_delivery_backlog` view.
`inbox_events` became the acknowledgement ledger, keyed `(event_id, workspace_id)`, carrying the outcome
the consumer reported.

**Workspace.** `workspace_inbox_projection.sql` adds `workspace_inbox_events` (append-only, keyed by the
Control Plane event id) and `apply_inbox_event()`, which records the inbox row and the projection change in
one local transaction. Fencing follows the contract: the destination accepts exactly N+1, an older or equal
generation is ignored as stale, a further-ahead generation is quarantined, and an event addressed to another
Workspace is rejected. On the source side the local enrollment is fenced at the new generation, its state
set to `ended` and its active counselor assignments closed, so every later local command for that student
fails.

Identities: `cp_saga_dispatcher` can move delivery state and nothing else — it cannot write an event,
change ownership, switch ownership, or dead-letter/re-drive (those are operator actions). The Workspace
consumer is the worker role, which cannot write the inbox table directly.

**Tests (executed):** SAGA-01..SAGA-34 and INB-01..INB-22. Covered: switch and outbox row are one
transaction and a refused switch leaves neither; the envelope hash must describe its own payload; lease
exclusion between two dispatchers; a non-holder cannot report; retry preserves the attempt count on the
**same** event id; acknowledgement is idempotent per workspace and a conflicting outcome is refused;
dead-letter and re-drive are attributed and mint no new event; duplicate, out-of-order, stale, future,
not-addressed and bad-hash events; atomic inbox+projection; replay returns the recorded outcome; the fence
blocks later local commands.

---

## 2. What is explicitly NOT claimed

- **No distributed atomicity.** The Control Plane and a Workspace are separate databases. The guarantee is:
  the event is durable with its cause, delivery is at-least-once, and the consumer deduplicates by event id.
  Nothing here makes the two databases atomic, and no test claims it does.
- **`payload_hash` is transport integrity only.** It is computed over the stored jsonb rendering. It is NOT
  the signed canonicalization contract (`receipt-canon-v1`), not a cross-language canonical form, and not
  proof of authenticity. A signed wire format stays deferred to Platform Security (PS-1..PS-4).
- **No operational thresholds were invented.** Lease duration, retry count, backoff, dead-letter threshold
  and quarantine resolution are caller arguments or operator actions with no defaults, because OQ-E is open.
- **Not implemented, specification only** (contract section 10): source freeze/drain, in-flight transaction
  barrier, snapshot consistency at the watermark, destination staging visibility, real dispatcher crash at
  each checkpoint, lease expiry under partition, chaos/outage/restore/failover, reconciliation repair of
  projection drift, and staging/import of a student not yet projected at the destination.
- **The database does not verify authority.** Not an assertion signature, not guardian or legal authority
  (Q-007), not that a fee was paid, and not a scoring formula.
- **Owner/superuser can still disable triggers or change grants.** That is a deployment control, not a
  schema guarantee. One test fixture deliberately disables a row guard to back-date a synthetic clock, and
  says so.

---

## 3. New open questions raised by this work

| ID | Question | Why it matters | Recommended option | Authority |
|---|---|---|---|---|
| OQ-CRD-1 | Is the 7-day reversal window an exact 168-hour interval from the activation timestamp (implemented), or local calendar-day boundaries in Asia/Tehran? Is the boundary inclusive (implemented)? | Decides whether an archive near the edge returns credit | Keep the 168-hour inclusive interval: it is timezone-independent and matches "from the original activation timestamp" | Product Owner |
| OQ-CRD-2 | What happens to a reserved entitlement once its original period ends — released to the wallet, forfeited, or manual adjustment? | Credits currently stay reserved indefinitely (fail-closed, visible in `expired_reserved_entitlements`) | Decide before any pilot billing; do not auto-release | Product Owner / Finance |
| OQ-CRD-3 | Where does the entitlement **duration** come from (plan, product, per-activation)? The database now requires the caller to supply `period_end`. | Without a source, every caller invents one | Attach it to the purchased plan/product in the billing phase | Product Owner |
| OQ-SAGA-1 | Canonical wire format and signing for Saga envelopes across databases/services | `payload_hash` is transport integrity only | Define with PS-1..PS-4 before any cross-service deployment | Platform Security |
| OQ-SAGA-2 | Quarantine resolution: who re-applies a quarantined event once the local projection catches up, and under what authority? | Quarantined events currently stay quarantined | Operator command with audit, designed with OQ-E | Product Owner / Operations |
| OQ-ASM-1 | Item-bank ownership and the meaning of `item_ref` | Membership uniqueness relies on it | Model the item bank when assessment authoring is implemented | Educational domain owner |

Unchanged and still open: Q-007, Q-020, OQ-D numeric objectives, OQ-E thresholds, PS-1..PS-8, the transfer
exception authority, M-05 and M-06 (whose definitions are still not in the repository).

---

## 4. Test evidence

- PostgreSQL 16.15 (Ubuntu 16.15-0ubuntu0.24.04.1), local run on a cleared cluster, every database created
  fresh for its step.
- All 18 runnable workflow steps executed in order: **ALL_STEPS_PASSED**, 476 assertion lines reported PASS,
  plus the Python verifier-contract unit tests (`OK`).
- New suites in this batch: AVQ (22), CRD (27), SEP (29), ACT (26), SAGA (34), INB (22), WS-ROLE-16/17, and
  the deterministic WS-REACT-RACE-01.
- CI on the pushed commit is **NOT VERIFIED by the implementation agent** — this session has no GitHub
  Actions access. The CI result for `db834f7`, `3430816` and this commit must be read from GitHub.

**Reporting discipline:** every result above was produced by an actual execution whose output was captured.
Nothing is reported as PASS on the basis of review alone. Items in section 2 are reported as NOT IMPLEMENTED
or SPEC-ONLY, not as passing.

---

## 5. Recommendation

**NOT READY.** The implementation work on the approved P0/P1 decisions is complete and tested at the
database level, but Phase 2 cannot exit while Q-007, Q-020, PS-1..PS-8, the transfer exception authority,
the OQ-D/OQ-E numeric objectives and the M-05/M-06 definitions are open, and while the Saga's service-level
behaviour remains specification only. The independent Supervisor makes the gate decision.
