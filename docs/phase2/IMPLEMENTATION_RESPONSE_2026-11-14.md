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
  change. **OQ-CRD-1 was RESOLVED by the Product Owner on 2026-11-14 exactly as implemented**: an exact
  168-hour interval with an inclusive boundary. The rule now lives in `credit_reversal_eligible()` and is
  tested to the microsecond by CRD-32..CRD-38, including equality at the deadline.
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

**OQ-CRD-1 is no longer in this table: the Product Owner RESOLVED it on 2026-11-14** as an exact 168-hour
interval with an inclusive boundary, which is what was implemented. See `DECISION_LOG.md` (2026-11-14
clarification) and `OPEN_QUESTIONS.md`. The remaining questions below are still open and none of them is
decided by the implementation.

| ID | Question | Why it matters | Recommended option | Authority |
|---|---|---|---|---|
| OQ-CRD-2 | What happens to a reserved entitlement once its original period ends — released to the wallet, forfeited, or manual adjustment? | Credits currently stay reserved indefinitely (fail-closed, visible in `expired_reserved_entitlements`) | Decide before any pilot billing; do not auto-release | Product Owner / Finance |
| OQ-CRD-3 | Where does the entitlement **duration** come from (plan, product, per-activation)? The database now requires the caller to supply `period_end`. | Without a source, every caller invents one | Attach it to the purchased plan/product in the billing phase | Product Owner |
| OQ-SAGA-1 | Canonical wire format and signing for Saga envelopes across databases/services | `payload_hash` is transport integrity only | Define with PS-1..PS-4 before any cross-service deployment | Platform Security |
| OQ-SAGA-2 | Quarantine resolution: who re-applies a quarantined event once the local projection catches up, and under what authority? | Quarantined events currently stay quarantined | Operator command with audit, designed with OQ-E | Product Owner / Operations |
| OQ-ASM-1 | Item-bank ownership and the meaning of `item_ref` | Membership uniqueness relies on it | Model the item bank when assessment authoring is implemented | Educational domain owner |

Unchanged and still open: Q-007, Q-020, **OQ-CRD-2**, **OQ-CRD-3**, OQ-SAGA-1, OQ-SAGA-2, OQ-ASM-1, OQ-D
numeric objectives, OQ-E thresholds, PS-1..PS-8, the transfer exception authority, M-05 and M-06 (whose
definitions are still not in the repository).

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

## 4b. Remediation of the Supervisor findings on head `8abbbe3` (second pass, same day)

The independent Supervisor reviewed `8abbbe3` and raised one CRITICAL and six HIGH findings. All are
addressed below. **C-01 was a real defect in the work above, not a theoretical risk**, and the entry in
section 1.5 describing per-event delivery is superseded by this section.

| Finding | What was wrong | What changed | Status | Tests |
|---|---|---|---|---|
| **C-01** delivery per recipient | One `outbox_deliveries` row per event. An ownership switch must reach both Workspaces, and the first acknowledgement marked the whole event acknowledged, which could permanently stop retries for the other side. | `outbox_event_recipients` declares the audience (immutable; an event with no recipient is refused at the constraint check). `outbox_deliveries` is keyed `(event_id, workspace_id)` with its own state, lease, attempts, send record and acknowledgement. Claiming never returns an acknowledged recipient. Dead-letter and re-drive act on one recipient. `outbox_event_completion` reports complete only when every required recipient has acknowledged. Both producers declare their audience in the same transaction as the event. | **DONE** (schema) | SAGA-01..11, SAGA-R01..R32 |
| **H-01** archive clock before lock | `clock_timestamp()` was read before the entitlement row was locked, so a command that waited past the remaining window still saw it open. | The clock is read after the lock. | **DONE** | WS-CRD-LOCK-01/02, with sensitivity verified against the pre-fix code |
| **H-02** entitlement period source | The Runtime supplied `p_entitlement_period_end`, so it could extend a student's entitlement with an arbitrary timestamp. | `activate_student_enrollment()` takes no period argument and calls `resolve_student_entitlement_period()`, which raises `feature_not_supported` naming OQ-CRD-3. The caller-supplied-period command is `activate_student_enrollment_synthetic()`, granted only to `ws_<key>_synth_exec` (D-014). The required future source and its immutable-snapshot semantics are documented at the resolver as a recommendation. | **DONE as fail-closed**; the source is **NOT IMPLEMENTED** | CRD-28..31, WS-ROLE-18/19 |
| **H-03** acknowledgement authorization | A Workspace that was not a recipient could acknowledge, and an acknowledgement could precede a send. | The command requires a declared recipient, requires `sent_at`, validates the recipient-specific delivery state, and keeps exact per-recipient replay idempotent. | **DONE** | SAGA-R01..R03, R11, R12 |
| **H-04** activation timestamp and lock order | The clock was read before any lock and the period validated against it. | One authoritative timestamp is read after every required lock and used for the enrollment start, the entitlement row and the audit metadata. | **DONE** | CRD-01/01b |
| **H-05** inbox trust boundary | The worker could apply events whose only integrity evidence was a self-consistent hash. | `payload_hash` is documented as transport integrity, never authentication. `apply_inbox_event()` is the production-intended entry point and refuses via `assert_inbox_transport_verified()` (OQ-SAGA-1, PS-1..PS-4/PS-6). The application logic moved to `apply_inbox_event_synthetic()`, granted only to `ws_<key>_synth_inbox`. No cryptography, key, certificate or trust policy was invented. | **DONE as fail-closed**; verified transport **NOT IMPLEMENTED** | INB-01, INB-02, INB-02a/b/c/d |
| **H-06 / M-01** reactivation counselor | Any active member could be appointed responsible counselor, and the counselor was not part of the idempotency comparison. | The proposed counselor must hold the counselor role; `reactivation_command_log` stores `counselor_membership_id` and the replay comparison includes it. No delegation permission was added. | **DONE** | CRD-07a/b/c, CRD-11b, CRD-12b, WS-REACT-RACE-01 |

### Why the fail-closed shape rather than a working default

Both H-02 and H-05 could have been "fixed" by choosing something — an entitlement duration, or treating the
hash as sufficient. Each would have been a business or security decision this agent is not entitled to make.
Instead the operational identity keeps the production-intended entry point and that entry point refuses, so
the gap is visible and testable rather than papered over. When the Product Owner approves a period source,
`resolve_student_entitlement_period()` is replaced by a lookup and the resolved value is snapshotted into
the already-immutable `student_entitlements.period_end`. When Platform Security approves a transport,
`assert_inbox_transport_verified()` is replaced by a call into it and the application logic does not change.

### Evidence for this pass

- PostgreSQL 16.15, cleared cluster, every database created fresh per step: all 18 runnable workflow steps
  passed (**ALL_STEPS_PASSED**, 504 PASS assertion lines), plus the Python verifier-contract unit tests.
- Commits: `51b3948` (C-01), `bc98b49` (H-01/H-04 + H-02, corrected together because they rewrite the same
  two functions), `cc0db90` (H-05), `106c724` (H-06/M-01), plus the documentation commit.
- The lease-expiry step in SAGA-R13 is a deterministic wait on a one-second lease, not a timing race; the
  credit-boundary test coordinates through the entitlement row lock and waits until the archive command is
  observably blocked before releasing it.
- CI on the final HEAD of this batch is **NOT VERIFIED by the implementation agent** (no Actions access from
  this session). It must be read from GitHub.

### Still NOT implemented after this pass

Saga service behaviour in contract section 10 (freeze/drain, in-flight barrier, snapshot consistency,
destination staging, real process crash at each checkpoint, lease expiry under partition, chaos, outage,
restore, failover, projection-drift repair); quarantine resolution (OQ-SAGA-2); a verified transport and
signed wire format (OQ-SAGA-1, PS-1..PS-4/PS-6); the entitlement period source (OQ-CRD-3); per-subject exam
results; curriculum subtopics and PlanItem; retention schema integration (Q-020); contact change concurrency
against HMAC rotation and against an ownership switch (NOT RUN).

## 5. Recommendation

**NOT READY.** The approved P0/P1 decisions and the Supervisor's C-01/H-01..H-06/M-01 findings are
addressed at the database level and covered by executed tests. Phase 2 still cannot exit: two production
paths are deliberately fail-closed because their decisions are open (OQ-CRD-3, OQ-SAGA-1 with
PS-1..PS-4/PS-6), the Saga's service-level behaviour remains specification only, and Q-007, Q-020,
PS-1..PS-8, the transfer exception authority, the OQ-D/OQ-E numeric objectives and the M-05/M-06
definitions are all open. A DONE label in this document is the implementation's assessment of its own work,
not a closed finding. The independent Supervisor makes the gate decision.

---

## 6. Batch 1 — source transfer freeze and database write barrier (same day, fourth pass)

### 6.1 What the baseline inspection found

Two facts decided the shape of this batch, and both are verifiable:

1. **No application code exists.** `backend/`, `frontend/`, `scripts/`, `tests/` and `deployment/` contain
   only `.gitkeep`. Every Batch 1 item phrased as service behaviour — dispatcher crash recovery, partition
   and outage recovery, projection drift detection, quarantine forward recovery — has no process to crash,
   partition or restart. Those items cannot be implemented in Phase 2 and are **not** claimed. Section 6.5
   is the decision packet on that point.
2. **The Workspace database had no freeze enforcement at all.** The Control Plane recorded
   `transfer_cases.source_freeze_token` and `source_frozen_at`, but
   `grep -rn "freeze\|frozen\|drain" docs/phase2/workspace/*.sql` returned **0 matches**. A source Workspace
   could keep writing a student's data straight through cutover, so the final snapshot could miss writes
   taken after it was made. This is the part of Batch 1 that *could* be built in a database-only phase, and
   it is what was built.

### 6.2 What is enforced now

`docs/phase2/workspace/workspace_transfer_freeze.sql`:

- A durable freeze record, unique per freeze token and per `(student_id, case_id, source_generation)`, with
  a partial unique index allowing only one live freeze per student across the `frozen` and `fenced` states.
- A write barrier: a `BEFORE INSERT OR UPDATE OR DELETE` row trigger on every student-scoped table, calling
  `assert_student_not_frozen()`. Because it is a row trigger and not a privilege check, it binds **every**
  writer — the Workspace runtime role, the worker, the exporter, and the project's own SECURITY DEFINER
  commands. FRZ-16/17 assert the refusal **as the table owner**, which is the strongest available claim.
- An in-flight transaction barrier: `assert_student_not_frozen()` takes `FOR SHARE` on the student row, and
  `freeze_student_for_transfer()` takes `FOR UPDATE` on the student and on all its enrollments, so the
  freeze cannot complete while a writer holds those rows. The transaction id at which the barrier closed is
  recorded as `barrier_watermark_txid`.
- Token-bound idempotency: the same token replayed is a no-op; a **different** token for the same case,
  student and generation is refused rather than blindly accepted.
- Unfreeze only before the ownership switch, bound to the same token and case, and refused once an inbox
  event at a newer generation has been applied. After the switch the freeze becomes a permanent **fence**,
  applied by the inbox projection under a transaction-scoped bypass keyed on `txid_current()`.

### 6.3 Two defects found in this project's own work while testing it

**A missing barrier on enrollment-scoped tables.** FRZ-18 failed on the first run: `counselor_assignments`,
`activation_command_log` and `archive_command_log` carry no `student_id` — they are student-scoped only
through `enrollment_id` — and the first version of the barrier keyed exclusively on `student_id`, so all
three were unprotected. The trigger now takes a key-kind argument (`'student'` or `'enrollment'`) and
resolves the student through the enrollment. Coverage went from **23** tables to **26**. FRZ-01 now asserts
the count from `student_write_barrier_coverage` rather than from a list written into the test, so a new
student-scoped table added without a barrier fails the test instead of passing silently.

**A race test that proved nothing.** The first version of `workspace_freeze_barrier_race.sh` had the
in-flight writer insert a `study_sessions` row, and it passed. Running the negative control — replacing
`assert_student_not_frozen()` with a version identical except that the `FOR SHARE` lock is removed — showed
it **still passed**. The reason is that `study_sessions` has a foreign key to `students`, so PostgreSQL
itself takes a `KEY SHARE` lock on the student row and blocks the freeze. The test would have passed against
a project with no barrier at all.

The fix was to find a student-scoped table with no foreign-key path to `students`.
`class_session_participants` is one: it carries `student_id` and is covered by the barrier, but its foreign
keys point at `class_participants` and `class_sessions`. The race now runs in two modes, and the measured
negative-control result is:

| Mode | In-flight write | With the barrier | With `FOR SHARE` removed |
|---|---|---|---|
| `nofk` | `class_session_participants` | PASS (exit 0) | **FAIL (exit 2)** — "the in-flight writer never took the student row lock" |
| `fk` | `study_sessions` | PASS (exit 0) | PASS (exit 0) — masked by the foreign-key lock |

Both modes are wired into CI. Only `nofk` is evidence for the barrier this project added; `fk` is kept
because it is the realistic end-to-end path. This distinction is written into the script's own header so a
later reader cannot mistake the `fk` result for proof.

### 6.4 Evidence

| What | Result |
|---|---|
| `workspace_transfer_freeze_tests.sql` FRZ-01..FRZ-37 | 37 assertions, **36 PASS lines** (FRZ-26 and FRZ-27 share one line), 0 FAIL |
| `workspace_freeze_barrier_race.sh`, modes `nofk` and `fk` | **8 PASS lines**, 0 FAIL |
| Negative control, mode `nofk` | **FAILS as required** (exit 2) when the `FOR SHARE` barrier is removed |
| Negative control, mode `fk` | passes even without the barrier — recorded as *not* evidence |
| Full workflow, cleared PostgreSQL 16.15 cluster (0 leftover databases, 0 leftover roles) | **ALL_STEPS_PASSED** — all **20** runnable steps, **557 PASS assertion lines**, 0 FAIL, plus the Python verifier unit tests (`OK`) |
| GitHub Actions at this HEAD | **NOT RUN.** Two new workflow steps and new SQL mean earlier Actions evidence does not cover this commit. The agent has no Actions access and cannot read job logs. |

### 6.5 Decision packet — Batch 1 items that cannot be built in Phase 2

The Supervisor brief lists these Batch 1 requirements. For each, what is possible in a database-only phase
has been done, and the rest is stated as not done rather than quietly reinterpreted.

| Batch 1 requirement | Status | Why |
|---|---|---|
| Source Workspace freeze and write drain | **DONE for the database**, NOT IMPLEMENTED beyond it | API, worker, import, export and file surfaces do not exist. Any surface that reaches this database is refused. |
| In-flight transaction barrier | **DONE** | Enforced by row locks and tested with a sensitivity-verified race. |
| Stale-owner rejection | **DONE** | Generation fencing in the inbox projection plus the freeze's stale-generation refusal. INB-01..22, FRZ-12. |
| No simultaneous source and destination ownership | **DONE at the database level** | The ownership switch is a single Control Plane transaction; the source is fenced on observing it. Not a distributed atomicity claim. |
| Auditability of every transition | **DONE** | Freeze, unfreeze and fence are audited, with `('signed_receipt', false)` recorded so no authenticity is implied. |
| Lease expiry and retry | **DONE** (earlier batch) | Per-recipient delivery leases, attempts, dead-letter and re-drive. SAGA-R01..R32. |
| Crash recovery at checkpoints | **NOT IMPLEMENTED** | Requires a dispatcher process. None exists. Lease expiry is the database-side precondition for it and is tested. |
| Partition and outage recovery | **NOT IMPLEMENTED** | Requires two deployed databases and a network between them. |
| Projection drift detection and repair | **NOT IMPLEMENTED** | Requires a comparison process across two databases. |
| Quarantine forward recovery | **NOT IMPLEMENTED, and deliberately so** | OQ-SAGA-2 is open. A release path invented here would be an authenticated-transport bypass. |
| Fault-injection tests | **PARTIAL** | Database-level fault injection is done (negative controls, lock contention, stale generations, bad hashes). Process-level fault injection has no process to kill. |

**What this needs from the Product Owner and Supervisor:** a decision on whether a minimal service layer is
in scope for Phase 2, or whether these items move to a later phase with the database preconditions
(implemented and tested here) accepted as Phase 2's deliverable. The implementation has **not** assumed
either answer. Building a service layer now would expand Phase 2's scope beyond "Database & Domain Model";
not building it leaves the listed items open. Recommendation: **move them to a later phase**, because the
brief's own phase boundary puts services after the data model, and accept the database preconditions as the
Phase 2 deliverable — with the register entry for OQ-E stating plainly what remains.

### 6.6 What is still not claimed

- No production readiness for anything here. All of it is synthetic-only under D-014.
- No freeze duration, drain timeout or acceptance threshold. OQ-E leaves them to measured design.
- No correctness of the caller-reported outstanding-work count. The database only refuses to record a final
  barrier when it is non-zero; it cannot see an application job queue.
- No authenticity for the freeze receipt. Signing is OQ-SAGA-1 and PS-1..PS-4.
- No distributed atomicity between the Control Plane and a Workspace database.
- **Phase 2 is not self-approved.** This section is an implementation report, not a review.

---

## 7. Batch 2 — clock discipline at security decision points (same day, fifth pass)

### 7.1 What Batch 2 asked for, and what already existed

The brief lists eight items for the Trusted Governance Authorization Adapter. Checking them against the
repository before writing anything:

| Brief item | Status before this batch |
|---|---|
| Separate verifier process/service boundary | Implemented as a boundary: `verifier_rt` may INSERT receipts and nothing else (RC-01, RC-05, RC-31); `verifier_interface/verifier_contract.py` is the interface. The *deployment* topology is PS-7, deferred. |
| Authenticated private service channel | **NOT IMPLEMENTED** (PS-6). Correctly so, and stated as such. |
| Signed assertion verification interface | Interface exists; `verify_production` always refuses, `verify_test_double` is test-only. |
| Narrow proof-receipt registration through `verifier_rt` | Implemented and tested. |
| Independent receipt verification at the command boundary | Implemented: the command revalidates every binding against the recorded receipt (RC-13..19). It does not recheck a signature, which is PS-1. |
| Atomic consumption, revalidation, event append, projection update | Implemented in one transaction (RC-20..29); the projection update happens inside `append_workspace_governance_event`. |
| Replay protection and idempotency | Implemented (RC-24..27, RR-01..03). |
| Negative, tampering, claim mismatch, freshness, revocation, concurrency tests | All present **except freshness**, which had no test at all. |

So the honest work for this batch was the one gap: freshness. Rebuilding what already worked would have
produced a large diff and no new assurance.

### 7.2 The gap was not empty — it was hiding a live defect

`consume_governance_receipt_and_apply()` checked `not_before` / `expires_at` with `now()`. In PostgreSQL
`now()` is the **transaction start** time and does not advance.

This was demonstrated, not argued. A receipt with a two-second lifetime, consumed from a transaction that
opened while it was valid and slept four seconds:

```
consumed | expires_at < clock_timestamp() = t | consumed_event_id IS NOT NULL = t
```

The receipt was consumed and the governance event applied, four seconds after the receipt had expired.

Why the existing tests did not catch it: RC-21 (not-yet-valid) and RC-22 (expired) both use receipts that
are already outside the window when their transaction begins, and `now()` evaluates those correctly. The
defect only appears when the window closes *during* the transaction — the one case nothing tested.

Why it mattered more than an ordinary off-by-one: the expiry window is the **only** freshness control this
database has. Revocation propagation across API, export, worker and notification handoffs is PS-8 and
deferred, so there was nothing else to fall back on.

### 7.3 The same defect existed in two more places

Grepping the project for the pattern rather than stopping at the first instance:

| Site | What it decides | Severity |
|---|---|---|
| `change_student_mobile_contact()` (`cp_08`) | the one-time contact-change proof window — this proof authorizes changing a student's **global** contact identity, so its expiry is the whole point of it being one-time | HIGH |
| `guardian_permissions_effective` (view) | its own comment states it is "the ONLY read shape that may be used for a guardian access decision". With `now()`, a permission that expired mid-transaction still read as effective — and that stale read *was* the access decision | HIGH |
| `expired_reserved_entitlements` (view) | a report, not a decision — but whatever implements OQ-CRD-2 will read it | LOW, fixed for uniformity |

All were fixed the same way: `clock_timestamp()`, read after the relevant row lock. `v_now` is also now
used for the stored timestamps those commands write (`ended_at`, `archived_at`, `consumed_at`,
`updated_at`), so the recorded time equals the decision time. Those assignments were never defects; making
them uniform is what lets the static guards stay strict and simple.

**No clock-skew tolerance was introduced anywhere.** PS-5 is deferred and inventing a tolerance would be
inventing a security policy.

### 7.4 Fixing three instances is not the same as preventing a fourth

Three independent instances of one mistake is evidence about the project, not about three files. So the
batch also adds a guard that scans the catalog rather than a list of files:

- **CLK-01** walks every SECURITY DEFINER function and every view, strips comments, and fails **by name**
  on `now()`, `transaction_timestamp()` or `CURRENT_TIMESTAMP`. It carries exactly one reviewed allowlist
  entry — `append_workspace_governance_event`, whose `granted_at=now()` writes a stored value and decides
  nothing — and the allowlist requires a stated reason. A new function or view that decides from a stale
  clock fails the suite.
- **CLK-02** separately pins the specific windows that were defective, so an over-broad edit to CLK-01's
  allowlist does not silently re-open the hole.
- **CLK-03** is behavioural, because a static scan would miss a view rewritten to compare against a column
  holding a transaction-start value.

### 7.5 Evidence, including what the tests were measured against

| What | Result |
|---|---|
| `receipt_60_freshness_tests.sql` RC-FRESH-01..04 | **5 PASS lines**, 0 FAIL |
| `cp_47_freshness_tests.sql` CC-FRESH-01..03 | **3 PASS lines**, 0 FAIL |
| `workspace_clock_discipline_tests.sql` CLK-01..03 | **3 PASS lines**, 0 FAIL |
| Negative control: consume function with `v_now := now()` | **RC-FRESH-01 FAILS** (exit 3) with the diagnostic naming the cause |
| Negative control: pre-fix contact-change command | **CC-FRESH-01 FAILS** (exit 3) |
| Negative control: pre-fix guardian view | **CLK-01 FAILS** (exit 3), naming `view guardian_permissions_effective` |
| Pre-existing suites unaffected | receipt_10 still 44 PASS, cp_40 still 41 PASS |
| Full workflow, cleared PostgreSQL 16.15 cluster (0 leftover databases, 0 leftover roles) | **ALL_STEPS_PASSED** — 21 implementation test steps, **568 PASS assertion lines**, 0 FAIL, plus the Python verifier unit tests (15 and 6 tests, `OK`) |
| Documentation consistency check (register) | 6 PASS lines, reported separately and **not** counted as implementation evidence |
| GitHub Actions at this HEAD | **NOT RUN.** New SQL, three new suites and a new workflow step. The agent has no Actions access and cannot read job logs. Batch 1 was pushed as `cc8cd64`; its Actions result has not been reported to the agent. |

### 7.6 What is still not claimed after Batch 2

- No signature is verified anywhere. `verifier_outcome='verified'` remains a **recorded input** from an
  external verifier, never proof. The production verifier refuses (PS-1..PS-4).
- No authenticated private service channel exists (PS-6). `authn_event_ref` and `authority_ref` stay
  opaque references.
- No end-to-end revocation freshness (PS-8). The database records revocation; propagation to API, export,
  worker and notification handoffs has no services to propagate to.
- No clock-skew tolerance (PS-5).
- The static guards are static. They prove no transaction-start clock is read; the behavioural proof is
  RC-FRESH-01..03, CC-FRESH-01..02 and CLK-03, each measured against pre-fix code.
- **Phase 2 is not self-approved.** This is an implementation report, not a review.

---

## 8. Batch 3 — Student Credit lifecycle, verified item by item (same day, sixth pass)

Batch 3 asks for **verification** of thirteen properties rather than new features. The method was to check
each one against what the tests actually assert, not against what the documentation claims. That found
three properties with **no test at all** and, through them, two real defects.

### 8.1 The verification matrix

| # | Required property | Verdict | Evidence |
|---|---|---|---|
| 1 | Append-only ledger | **VERIFIED** | CRD-05 (DELETE refused). **UPDATE was untested** — now CRD-44/45. |
| 2 | Atomic debit and idempotency | **VERIFIED** | CRD-02, CRD-10, CRD-31 (fail-closed activation leaves no partial state). |
| 3 | No negative or inconsistent spendable balance | **WAS NOT TESTED AT ALL** → now verified | The guard existed and worked, but nothing exercised it. CRD-27 tested the balance *identity*, which is a different claim: an identity can hold perfectly while the balance is negative. Now CRD-39/40/41 serially and WS-CRD-LAST-01..05 concurrently. |
| 4 | Student-bound reserved credit | **VERIFIED** | CRD-06 (reserved credit cannot fund another student), CRD-07. |
| 5 | Original debit retained after reversal | **VERIFIED** | CRD-03, CRD-05. |
| 6 | Compensating transaction tied to original debit, **student** and entitlement | **DEFECT FOUND** → fixed | Tied to the debit (CRD-03/04) and the entitlement (`reversal_transaction_id`), but **not to the student**. Demonstrated below. Now CRD-42/43. |
| 7 | Exact 168-hour inclusive reversal boundary | **VERIFIED** | CRD-32..38 (OQ-CRD-1, already resolved; not reopened). |
| 8 | Lock ordering and post-lock timestamp acquisition | **VERIFIED** | WS-CRD-LOCK-01/02, whose own sensitivity was verified earlier by reverting the clock/lock order. CRD-47 now also asserts the guard still takes its row lock. |
| 9 | Free reactivation only within the original period | **VERIFIED** | CRD-08, CRD-18. |
| 10 | No period extension on archive/reactivation | **VERIFIED** | CRD-09. |
| 11 | Expired entitlement cannot be reactivated for free | **VERIFIED** | CRD-18 (and the disposition of such an entitlement stays OQ-CRD-2, undecided). |
| 12 | Concurrent archive / reactivation / debit behaviour | **PARTIAL → now fuller** | Reactivation: WS-REACT-RACE-01. Archive vs the reversal window: WS-CRD-LOCK-01/02. **Two students racing for the last credit was untested** — now WS-CRD-LAST-01..05. |
| 13 | Correct authorization and Workspace isolation | **VERIFIED** | Role and cross-database tests already exist; direct ledger writes by the runtime and worker roles were untested and are now CRD-46c/46d. |

### 8.2 Defect 1 — a compensating reversal could name the wrong student

The ledger guard validated that a reversal referenced one unreversed transaction, in the same wallet, with
the exact opposite amount. It did **not** check the student. Demonstrated: an insert with the correct
wallet and amount but a different `student_id` was accepted, and the row landed with

```
idempotency_key      | student_matches_debit
probe-wrongstudent-2 | f
```

**Severity, stated honestly.** Only `function_owner` (NOLOGIN, used by the SECURITY DEFINER commands) and
`table_owner` hold INSERT on `credit_transactions`; no application role does, and CRD-46c/46d now prove
that. So this was not reachable from the Workspace runtime. It still mattered: the brief requires the tie
to the student explicitly, the balance arithmetic reads `student_entitlements` rather than the reversal row
so the numbers would have agreed while the attribution was wrong, the ledger is **append-only** and a wrong
attribution could therefore never be corrected, and whatever eventually implements OQ-CRD-2 reads exactly
this attribution. Classified MEDIUM: defence in depth on an audit record, not a live exploit.

**Fix:** the guard requires `NEW.student_id IS DISTINCT FROM` the related transaction's student to fail.
`IS DISTINCT FROM` so that reversing a debit with no student requires no student here either, which keeps
non-student transactions reversible.

### 8.3 Defect 2 — the ledger guard existed twice, and the weak copy was reachable

`validate_credit_reversal()` was defined in **two** files: a weak copy in `workspace_schema_draft.sql`
beside the table, and a strong `CREATE OR REPLACE` copy in `workspace_activation_transactions.sql`. The
weak copy had no wallet row lock and **no balance check at all**.

In the normal load order the strong copy won, so every credit suite was testing the right function and no
previous result was wrong. Two things were still broken:

- **The weak path was reachable, not hypothetical.** One CI step — the governance event ledger step — loads
  `workspace_schema_draft.sql` without the activation file. That database had a credit ledger with no
  negative-balance prevention. Nothing claimed otherwise, but the trap was live.
- **Editing the obvious copy would have had no effect.** A maintainer hardening the guard next to the table
  would have changed dead code, silently.

**Fix:** one definition, in the file that creates the table and the trigger, carrying the strong body. The
activation file keeps a comment explaining where the guard lives and why. CRD-47 asserts from the catalog
that exactly one `validate_credit_reversal()` and exactly one guard trigger exist, and that the body still
contains the balance check, the student binding and the row lock — so a second definition cannot silently
win again.

### 8.4 Evidence, and what each test was measured against

| What | Result |
|---|---|
| `workspace_credit_ledger_invariant_tests.sql` CRD-39..47 | **12 PASS lines**, 0 FAIL |
| `workspace_credit_last_unit_race.sh` WS-CRD-LAST-01..05 | **5 PASS lines**, 0 FAIL |
| Pre-existing credit suite after the guard consolidation | **unchanged: 43 PASS lines, exit 0** |
| Negative control: student binding removed from the guard | **CRD-42 FAILS** (exit 3) — the misattributed reversal is accepted |
| Negative control: a weak duplicate guard replaces the strong one | **CRD-39 FAILS** (exit 3) — the over-debit succeeds |
| Negative control: wallet row lock removed from the guard | **WS-CRD-LAST-02/03/04/05 FAIL** — measured `debits=2 ledger=-1 available=-1 entitlements=2 capacity=2` |

A nuance recorded in the race script itself, because it would otherwise invite a wrong reading: in the
no-lock control the "second activation is blocked" observation **still appears**, because the activation
command takes other row locks (the enrollment, the capacity counter) and B blocks on those regardless. The
blocking observation proves only that the sessions overlapped. The outcome assertions are the evidence.
This is the same trap that made the first version of the Batch 1 barrier race worthless, and it is called
out here so a reader does not repeat it.

### 8.5 What Batch 3 did not do

- **OQ-CRD-1 was not reopened.** It is resolved; CRD-32..38 stand as they were.
- **OQ-CRD-2 and OQ-CRD-3 were not decided.** No expiry, extension, forfeiture or automatic return of a
  reserved entitlement is implemented, and the production activation path stays fail-closed on the
  entitlement period. `expired_reserved_entitlements` still only *shows* the affected rows. The decision
  requests for both are in `docs/phase2/UNRESOLVED_ITEM_REGISTER.md` with options and a recommendation.
- **No service-layer behaviour is claimed.** All of this is database-level; there is no service layer.
- **Phase 2 is not self-approved.** This is an implementation report, not a review.

---

## 9. Batch 4 — Assessment, Exam and result model (same day, seventh pass)

### 9.1 What was already correct, verified rather than assumed

Four of the eight brief items turned out to be already implemented. Each was checked by probe, not by
reading the documentation:

| Brief item | Verdict | How it was checked |
|---|---|---|
| Published `TestDefinitionVersion` has a fixed immutable question set and order | **VERIFIED** | `test_definition_version_guard` plus `UNIQUE(version_id, question_no)` and `UNIQUE(version_id, item_ref)`. AVQ-01..22. |
| Question membership and ordering normalized and constrained | **VERIFIED** | `test_definition_version_questions` is the authoritative list; `question_count` is only a consistency check. |
| Attempt responses reference questions of that exact version | **VERIFIED** | Two composite foreign keys make cross-version substitution impossible **declaratively**, with no trigger. |
| Scoring policy snapshot equals the published version's policy | **VERIFIED** | The attempt guard refuses with "attempt scoring policy snapshot differs from the published version policy". |
| Adaptive per-attempt delivery remains disabled for MVP | **VERIFIED** | Probed: publishing a `per_attempt` version is refused — "per-attempt delivery requires a separate Product Owner decision". The file comment alone had read as if it were merely discouraged; the guard enforces it. `test_attempt_questions` from the contract is therefore **not needed** for MVP and was deliberately not built. |
| Invalid, incomplete, duplicate and cross-version responses rejected | **VERIFIED** | Table constraints plus `test_attempt_guard`, which recounts the stored responses at submission so the invariant holds for any writer. |

Also probed and confirmed, because it is the foundation of reproducibility: **a submitted attempt's
responses are immutable.** Change, delete and insert are all refused with "responses are immutable once the
attempt is submitted". So the inputs to a score cannot drift after the fact.

### 9.2 What was missing, and was built

`docs/phase2/workspace/ASSESSMENT_DOMAIN_CONTRACT.md` section 7 names the required structures. Three did
not exist at all, and one requirement had no enforcement:

**1. An explicit scoring algorithm version.** `scoring_policy_snapshot` only had to be a JSON object.
Demonstrated: a test definition version stored `{}` and published successfully. Nothing recorded *which*
algorithm produced a score, so a historical number was unattributable. Every snapshot must now name an
`algorithm` (non-empty string) and an `algorithm_version` (positive integer), on `test_definitions`,
`test_definition_versions`, `test_attempts`, `exams`, `exam_results` and the new per-subject results.

**The trap this had to avoid, stated as measured facts rather than as recollection.** A validation
predicate built from type comparisons alone is NULL for a missing key, and **a CHECK constraint passes
when its expression is NULL**, so the malformed value is accepted. Both halves were measured:

```
SELECT jsonb_typeof('{}'::jsonb -> 'algorithm') = 'string';     -> NULL
CREATE TEMP TABLE t(p jsonb, CHECK (jsonb_typeof(p->'algorithm') = 'string'));
INSERT INTO t VALUES ('{}'::jsonb);                             -> INSERT 0 1   (accepted)
```

This is the same trap recorded in `receipts/README.md` for `workspace_governance_events_draft.sql`, where
payload validations used `jsonb_typeof(...) <> 'string'` with no NULL handling. The predicate therefore
ends in `COALESCE(..., false)` and mixes in value checks that return false rather than NULL, and **EXM-42**
asserts directly that the predicate is never NULL for any of twelve malformed inputs — a better defence
than remembering the rule.

**2. `exam_definition_versions`** — an immutable published exam blueprint, with per-subject question counts
(`exam_definition_version_subjects`). Published is immutable and undeletable, and publication is refused
unless the subject counts add up to the exam's own count.

**3. `exam_subject_results`** — per-subject results keyed to the exact exam, student and subject, with
composite foreign keys so a cross-exam or cross-student subject result is refused declaratively.
Reconciliation with the aggregate is a `DEFERRABLE INITIALLY DEFERRED` constraint trigger, because the
aggregate and the subject rows arrive in whatever order the writer chooses and neither is wrong on its own
mid-transaction.

**4. `test_analysis_versions`** and `test_analysis_response_findings` — append-only, so that a later
reclassification is a new version rather than a silent mutation. Submitted responses were already
immutable, so a reclassification previously had nowhere to go. EXM-40 is the point of the structure: after
a second analysis version reclassifies a response, the submitted response itself is unchanged.

### 9.3 Open questions respected rather than quietly answered

Contract section 9 lists open policy inputs. None was decided:

- **Whether every exam requires per-subject results** → it is per-blueprint data
  (`requires_subject_results`), so the blueprint says it and this schema does not. EXM-31 proves an exam
  with no blueprint may still hold an aggregate alone.
- **Whether analysis can be rerun, and how a version is selected** → analysis versions are append-only with
  monotonic numbering and carry **no** active/current flag and no selection rule.
- **Scoring formulas and rounding** → nothing is computed or validated. The database stores and compares
  snapshots.
- **Which algorithm names are permitted** → not constrained. Raised as the new **OQ-ASM-2**, with options
  and a recommendation, in `docs/phase2/UNRESOLVED_ITEM_REGISTER.md`.
- **Rank, percentile and cohort comparison** → not modelled. They need a cohort this Workspace may not
  hold and no rule exists for it.
- **Whether an exam must cite a blueprint** → `definition_version_id` is nullable, because requiring one
  would be a product decision and the existing ad-hoc exam rows have none.

### 9.4 Evidence

| What | Result |
|---|---|
| `workspace_assessment_exam_tests.sql` EXM-01..42 | **42 PASS lines**, 0 FAIL |
| Existing suites with the new draft loaded and fixtures updated | `workspace_schema_tests` 16, `workspace_assessment_guardian_tests` 48, `workspace_assessment_version_question_tests` 23, `workspace_activity_source_tests` 28 — all exit 0 |
| Negative control: predicate replaced by type comparisons only | **FAILS** (exit 3). EXM-42: "the predicate returned NULL for: empty object, no algorithm_version, no algorithm". In the full suite EXM-01 fires first — "an empty scoring policy snapshot is refused: statement unexpectedly succeeded". Against the committed predicate EXM-42 passes. |
| Negative control first attempted: removing only `COALESCE(..., false)` | **DID NOT REPRODUCE**, and the claim that it did has been corrected here. With the `length(btrim(COALESCE(p->>'algorithm','')))>0` conjunct still present the chain evaluates to **false**, not NULL, because `NULL AND false` is `false`. Measured: the predicate returned `false` for `{}` and the suite passed. The control that isolates the trap is the type-comparison-only predicate above. |
| Negative control: reconciliation trigger body replaced by `RETURN NULL` | **FAILS** (exit 3) at EXM-26 — "an aggregate with no per-subject rows committed although the blueprint requires them". The body is neutralised rather than the trigger dropped: EXM-26 runs `SET CONSTRAINTS exam_results_reconcile_trg IMMEDIATE` to observe the deferred check, so dropping the trigger breaks the test's own setup ("constraint does not exist") and would prove nothing about reconciliation. |
| Fixture migration | 14 informal policy literals updated across 6 files to name an algorithm and version; the tightened CHECK would otherwise have broken them, and the tests still assert their original reasons |

### 9.5 What is still not claimed

- No scoring formula, rounding rule or algorithm is implemented or validated.
- Rank, percentile and cohort comparison are absent.
- `test_attempt_questions` is absent, correctly: adaptive delivery cannot be published.
- A deferred constraint trigger runs at COMMIT with the **caller's** privileges, so any future SECURITY
  DEFINER command writing these tables must run `SET CONSTRAINTS ... IMMEDIATE` inside its own security
  context, as the other commands in this project already do. That note is in the draft file itself. No
  such command exists yet.
- **Phase 2 is not self-approved.** This is an implementation report, not a review.

---

## 10. Batch 5 — Curriculum, Plan and Activity domain (2026-11-15)

### 10.1 Verification matrix

| Brief item | Verdict | Evidence |
|---|---|---|
| Curriculum and Subtopic relationships | **PARTIAL → subtopics built** | `subjects → chapters → topics` existed; **`subtopics` did not**. Built and tested (CUR-01..CUR-10). Book/Edition, successor mapping and subtopic-level mastery are **not** built — scoped out by the Product Owner on 2026-11-15 and recorded as **WS-DOM-05**. |
| Base Plan and PlanItem | **Plan/PlanVersion VERIFIED; PlanItem NOT IMPLEMENTED** | `student_plans` and `student_plan_versions` exist with version numbering, publication immutability and retained history. `plan_content` is `jsonb` — the exact shape the planning contract rejects. Recorded as **WS-PLAN-01**, scoped out by the Product Owner. |
| ProgramTemplate and Student Plan versioning | **VERIFIED** | `program_templates`/`program_versions` and `student_plans`/`student_plan_versions`, both guarded by `reject_published_version_mutation()`, which refuses UPDATE **and** DELETE on a published row. |
| Activity linked to specialized authoritative entities | **VERIFIED** | Typed nullable source columns with composite foreign keys carrying `student_id`, plus `activities_source_matches_kind` making kind and source agree. ACT-01..26. No polymorphic reference anywhere. |
| Class, ClassSession, ClassParticipant relationships | **VERIFIED** | `class_session_participants` has composite foreign keys to `class_sessions(class_session_id, class_id)` **and** `class_participants(class_id, student_id)`, so a session participant must already be a participant of that same class and the session must belong to it. Cross-class and cross-student rows are refused declaratively. |
| Student ownership and Workspace boundaries | **FIVE GAPS FOUND AND FIXED** | See 10.2. |
| Immutable published versions | **VERIFIED** | Program and plan versions; plus the published assessment versions from Batch 4. |
| Audit history and safe updates | **VERIFIED** | Plan versions retain history; `source_program_version_id`, `input_snapshot` and `rule_version` are kept per version; guardian and governance tables are append-only. |
| Referential integrity and deletion behaviour | **VERIFIED, and now asserted** | There is **no `ON DELETE` action anywhere** in the Workspace schema, so every foreign key restricts. CUR-09 asserts that from the catalog by failing if any foreign key has a non-default delete action — previously this held by convention and nothing checked it. |

### 10.2 Five tables were per-student and had no write barrier

The Batch 1 write barrier derived its table list from a **column scan**: anything with `student_id` or
`enrollment_id`. That cannot see a table whose ownership runs through another table. Batch 1 had already
been caught by this once (`counselor_assignments` and the two command logs, via `enrollment_id`, FRZ-18),
and the fix then was to add an `enrollment` resolution path — without asking what *else* the scan was
blind to.

Auditing reachability from the catalog instead found five more:

| Table | Reaches its student through | Consequence while frozen |
|---|---|---|
| `student_plan_versions` | `plan_id → student_plans` | a frozen student's plan could gain new versions through cutover |
| `test_responses` | `attempt_id → test_attempts` | responses could be added to a started attempt mid-cutover |
| `guardian_permissions` | `guardian_link_id → student_guardian_links` | guardian authority could change during cutover, so the destination would import a different authority set than the source froze |
| `guardian_link_events` | `link_id → student_guardian_links` | as above |
| `guardian_permission_events` | `permission_id → guardian_permissions → link` | as above, two hops out |

`student_write_barrier()` gained `plan`, `attempt`, `guardian_link` and `guardian_permission` resolution
paths. Barrier coverage went from **26 tables to 31**.

**The audit is now a test, which is the part that matters.** FRZ-01 asks "does every table in the coverage
view have a trigger?", which by construction cannot catch a table missing from the view. **FRZ-01b** asks
the opposite question from the catalog: which tables have a foreign key into a per-student table and yet
carry no barrier? Anything new fails **by name**. Its exclusion list carries eleven reviewed entries, each
with one of only two valid reasons — the table is **shared** between students, so barring it would let one
frozen student block writes other students depend on; or it must be writable **while** frozen because it is
part of the freeze machinery. `workspace_inbox_events` is in the second group, and that is not a
technicality: the inbox projection is what **applies** the fence, so barring it would stop the fence
landing.

FRZ-01b earned its keep immediately — it found the three guardian tables as soon as it was written, after
the first two had been fixed by hand.

**FRZ-18b and FRZ-18c test the new paths behaviourally**, not just structurally, because a two-hop lookup
that silently returned NULL would leave the barrier wide open while still reporting as "covered":
`assert_student_not_frozen()` returns early for a NULL student. FRZ-18c exercises the two-hop guardian
path specifically.

### 10.3 Scope held where the contracts are not approved

Both `CURRICULUM_DOMAIN_CONTRACT.md` and `DETERMINISTIC_PLANNING_DOMAIN_CONTRACT.md` are marked
**DRAFT / NOT APPROVED**, and the brief says to resolve these "only to the extent already approved". The
scope question was put to the Product Owner rather than decided here, and the answer was **subtopics only**.

So `subtopics` is built, and these are recorded with options and recommendations instead:

- **WS-DOM-05** — Book/Edition, curriculum version successor mapping, platform-versus-Workspace content
  ownership metadata, subtopic-level mastery. Recommendation: Phase 7, where the roadmap already puts
  curriculum.
- **WS-PLAN-01** — normalized `plan_items` instead of the opaque `plan_content` blob. Recommendation: build
  the **data model** in Phase 2 and the engine in Phase 12, the same split that already worked for Activity
  — but this is a recommendation and nothing is built against it.

CUR-10 asserts that Book/Edition tables are **absent**, so the gap stays explicit and dated rather than
looking like an oversight, and the assertion fails loudly if someone adds them without updating WS-DOM-05.

### 10.4 What is still not claimed

- No `plan_items`, so plan contents have no referential integrity. `plan_content` is stored and **nothing in
  the database interprets it**; no scheduling behaviour is implied.
- No planning engine, no determinism or replay machinery, no normalized planning inputs (school timetable,
  availability windows, sleep windows). Those are Phase 12.
- No Book/Edition, no curriculum successor mapping, no platform-versus-Workspace content ownership, so the
  curriculum contract's isolation tests (platform content read-only; Workspace A cannot reach Workspace B's
  custom curriculum) **cannot** be run and are not claimed.
- No subtopic-level mastery; mastery stays at topic level.
- **Phase 2 is not self-approved.** This is an implementation report, not a review.

---

## 11. Batch 6 — Tenant isolation, authorization and database hardening (2026-11-15)

### 11.1 Method: interrogate the catalog, not the SQL text

Batch 6 is an adversarial review. Reading the SQL is how the two problems below survived several previous
passes, so the assertions in `workspace_privilege_hardening_tests.sql` query the **catalog** and describe
properties that must hold for **every** SECURITY DEFINER function and **every** role — not for a list of
names somebody remembered to check. SEC-01 is the one that found a real defect.

### 11.2 Finding 1 — a SECURITY DEFINER function owned by a superuser

`receipt_consume_grant_guard()` is `SECURITY DEFINER` and was **owned by `postgres`**, a superuser. A
SECURITY DEFINER function owned by a superuser executes **as superuser** every time it runs.

The cause is ordering, not intent: the function is created in `receipt_01_schema_draft.sql`, which runs
**before** `receipt_02_roles_draft.sql` creates the role that should own it, so it inherited the loader's
identity — and nothing ever reassigned it.

**Severity, measured rather than asserted: MEDIUM, defence-in-depth, not exploitable as configured.**
- It returns `trigger`, and PostgreSQL refuses to invoke a trigger function as an ordinary function, so
  there is no direct call path.
- Its body reads exactly one table, schema-qualified, and raises. Nothing dynamic.
- Shadowing an unqualified name would need `CREATE` on a schema on its path, and the review **measured**
  that `PUBLIC` cannot create in `public`, and neither can `runtime`, `worker`, `exporter`, `verifier_rt`,
  `governance_adapter_rt` or `synth_exec`. Only `table_owner` and `function_owner` can, and both are
  NOLOGIN and already trusted.

It was still unnecessary privilege and a deviation from this project's own rule that every definer function
is owned by a dedicated NOLOGIN role. **Fixed:** `receipt_02_roles_draft.sql` now reassigns ownership to
`ws_<key>_receipt_consume_definer`, which already held the one grant the body needs, and the function's
search_path was tightened from `pg_catalog, public` to `pg_catalog, pg_temp`.

**Sensitivity measured:** with the `ALTER FUNCTION ... OWNER TO` line removed, the owner is `postgres`
again and **SEC-01 fails** naming the function. Exit 3.

### 11.3 A finding deliberately not inflated

Two definer functions — `append_workspace_governance_event` and
`consume_governance_receipt_and_apply` — still carry `public` on their search_path. The first instinct was
to call that a vulnerability and mass-edit it. The measurement above says otherwise: exploiting it requires
`CREATE` on `public`, which no application role has.

So the test was split rather than overstated:
- **SEC-02** requires every definer function to pin *a* search_path (an unpinned one resolves through the
  **caller's** path, which is the real classic vector).
- **SEC-02b** asserts the precondition that actually carries the weight: neither `PUBLIC` nor any
  application role may `CREATE` in `public`. If that ever changes, every function with `public` on its
  path becomes exploitable **at once**, and this fails.
- **SEC-02c** reports the remaining two as a NOTICE, tracked as hardening, explicitly **not** claimed as
  fixed.

Claiming a vulnerability that cannot be exercised would be as misleading as ignoring one that can.

### 11.4 Finding 2 — counselor-to-counselor isolation is not enforced, and cannot be today

The brief requires: *"No counselor may access another counselor's students, even within the same
Organization."*

Measured: **no row-level security on any table**, and the Workspace runtime role holds `SELECT` on **47
tables in full**. Isolation in this design is **per-Workspace** — one database per Workspace, no
cross-database grants, which the cross-database denial step does test — so every counselor inside a
Workspace shares one runtime identity.

This is not a defect to patch in a batch; it is an **architecture decision that has not been made**, so it
is recorded as **WS-ISO-01** with four options and a recommendation (row-level security keyed to the
responsible counselor assignment — noting that the session identity must **not** come from a GUC the
application sets, because this project already rejected session GUCs as an authorization mechanism in
finding H-03).

**SEC-10 asserts the negative result as a test rather than prose**, and fails if the situation changes in
either direction, so the record cannot silently rot: if RLS is added, the assertion demands it be replaced
with real isolation tests.

### 11.5 What the rest of the review found: no further defects

| Property | Result |
|---|---|
| Definer functions without a pinned search_path | **none** (SEC-02) |
| Definer owners that can log in | **none** — all NOLOGIN (SEC-03) |
| Tables owned by an application role | **none** (SEC-04) |
| Workspace roles with superuser / createrole / createdb / bypassrls | **none** (SEC-05) |
| Table privileges held by `PUBLIC` | **none** (SEC-06) |
| Non-trigger definer functions executable by `PUBLIC` | **none** beyond `assert_student_not_frozen`, which is PUBLIC on purpose (SEC-07) |
| Tables without a primary key | **none** (SEC-09) |
| Foreign keys with a cascade or set-null | **none** (CUR-09, Batch 5) |
| Polymorphic references without integrity | **none** — Activity and the assessment chain use typed columns with composite foreign keys |

### 11.6 SEC-08 records a limitation instead of hiding it

Every guard in this schema is a trigger or a CHECK. A **table owner can disable triggers** and a superuser
can do anything, so neither identity is contained by any of it. SEC-08 does not assert that the owner is
contained — it asserts that the owner **can** disable a trigger, so the threat model stays honest and no
later reader mistakes the write barrier for something that binds the owner. Containing those identities is
operational control of credentials, which is outside the database.

### 11.7 What is NOT claimed for Batch 6

- **No object-level authorization, IDOR or uniform-404 testing.** Those are API properties and there is no
  API in this repository. The brief's "uniform 404 for cross-Workspace or nonexistent resources" cannot be
  implemented or tested here, and is not.
- **No background-job tenant context**, because there are no background jobs. The worker *role* exists and
  its grants are tested; nothing runs as it.
- **No file or notification ownership**, because neither subsystem exists.
- **No RLS policies**, therefore no RLS bypass testing — the absence is the finding (WS-ISO-01).
- **No counselor-to-counselor isolation**, as above.
- **Phase 2 is not self-approved.** This is an implementation report, not a review.


---

## 12. Correction — the branch-synchronization claim was wrong

Section 6 of this document and the BRANCH-SYNC register item both reported that the PR #12 branch was
**not** behind `main`, presenting that as a correction of an earlier claim. **The retraction was wrong and
the original claim was right.**

`main`'s tip was taken from the `base.sha` field of the open pull request objects. That field records the
base commit **as it stood when each PR was created** (`ba5e9d8`), not `main`'s current tip. Four PRs all
reporting the same value read like corroboration; it was one stale value four times. The right source is
the branch listing, which gives `main` at `5bb8e4ed07a7c770ecba7c506a1d2c278e36b6d6`.

Measured on 2026-11-15:

| Check | Result |
|---|---|
| `git merge-base --is-ancestor 5bb8e4e HEAD` | **fails** — the branch does not contain `main` |
| commits on `main` not on the branch | `4004360` (added `cp_30_role_privilege_tests.sql`), `5bb8e4e` (reverted it) |
| `git diff ba5e9d8 5bb8e4e` | **0 changed files** |

So the branch **is** behind `main` by two commits, and the **net content difference is zero**. Nothing from
`main` is missing. Both halves have to be stated together: the first alone understates the branch's
position, the second alone was the error.

No rebase, merge or force-push was performed. The register entry now carries the measurement and recommends
resolving this with the PR #8–#11 disposition, which moves `main` regardless.

**Why this is recorded rather than quietly amended:** a false "corrected" claim sat in the register and in
`PROJECT_STATE.md` across several batches. The error was in the *method* — trusting a convenient field
instead of the authoritative one — and that is worth leaving on the record, because the same method would
produce the same error again.

---

## 13. Batch 7 — Contact identity, HMAC rotation and concurrency (2026-11-15)

### 13.1 The two races the brief listed as NOT RUN

Both serializations were **designed in and documented in comments**, and neither had ever been executed.
A comment claiming mutual exclusion is not evidence of it, which is the whole point of
`cp_48_contact_identity_race.sh`.

| Race | What it proves | Result |
|---|---|---|
| **A** — contact change in flight, HMAC rotation begins | `change_student_mobile_contact()` holds `FOR SHARE` on `identity_write_gate`; `begin_identity_hmac_rotation()` takes `FOR UPDATE` on the same row and therefore **blocks** | CID-RACE-A1/A2/A3 **pass** |
| **B** — contact change in flight, ownership switch for the same student | the contact change holds `FOR UPDATE` on the student's `student_ownership` row, so `switch_student_ownership()` **blocks**; afterwards the generation advances 1 → 2, ownership moves, and a contact change citing the pre-switch generation is refused | CID-RACE-B1/B2/B3 **pass** |

Why each matters. In A, a contact change landing mid-rotation would write an identity alias at a key
version the rotation is retiring, and the deferred coverage check that guarantees every claim has an alias
at every live key version would be evaluated against a set that changed underneath it — and contact lookup
is how a student is found at all. In B, a contact change landing during a switch would write the globally
unique contact identity against an owner and generation that no longer hold: the same stale-owner class as
the transfer fence, but on global identity rather than Workspace-local data.

Coordination is deterministic. The first session does its work and then waits for an explicit go signal;
the driver sends it only after **observing** the second session blocked in `pg_stat_activity`. The first
session is signalled to commit, never killed — terminating it would abort its transaction, release every
lock and let the second succeed legitimately. The existing `cp_46_contact_change_race.sh` orders its
sessions with `sleep 0.6` and `pg_sleep 2`; this file does not.

**Sensitivity measured for both:**

| Control | Result |
|---|---|
| `FOR SHARE` on `identity_write_gate` removed | **race A fails** at CID-RACE-A1 (exit 1) |
| `FOR UPDATE` on `student_ownership` removed | **race B fails** at CID-RACE-B1 (exit 1) |

### 13.2 A defect I nearly reported that was my own test's fault

The first version of race B ran in the same database as race A and reported that **the ownership switch
did not block** — which reads like a missing lock in the implementation, and I was one step from writing
it up that way.

It was not. Diagnosing before reporting showed that race B reused proof `…c2`, which `cc_proof` had bound
to **student 2**, while race B called it for **student 1**. The command correctly refused a proof bound to
a different student, the transaction aborted, its locks were released, and the switch then ran unblocked.
`change_student_mobile_contact()` does take `FOR UPDATE` on `student_ownership`; it is right there at
step 2.

Race A had also left the database in a different state than race B assumed: key version 1 `retiring` and 2
`active`, and a student's ownership generation already advanced. **The fix was isolation, not a weaker
assertion** — each race now runs in its own fresh database, and the reason is written into the script so
the next person does not re-share them. Race B also moved to student 3, untouched by any other suite, and
derives its owner, generation and destination from the database rather than hard-coding them.

This is recorded because the near-miss is the useful part: a race test that fails for a fixture reason
looks exactly like a race test that found a bug.

### 13.3 Confidentiality and key material

`cp_49_contact_confidentiality_tests.sql`, CID-01..CID-05b, asserted from the catalog so a column or index
added later fails by name:

- **CID-01** no text column anywhere can hold a plaintext contact. A contact may exist only as bytea
  ciphertext, a keyed fingerprint, a key version or an opaque `_ref`.
- **CID-02** every fingerprint is pinned to exactly 32 bytes, so its length leaks nothing, and the contact
  itself is bytea.
- **CID-03** the key-version tables hold **no key material**: no bytea at all, and text only as an opaque
  `*_ref` or a CHECK-pinned enum.
- **CID-04** exactly one HMAC key version is active, and a second active version is refused.
- **CID-05/05b** global contact identity is unique per **(key version, fingerprint, grade)** across
  `active` **and** `transfer_pending` claims.

Two of these tests were wrong first and the schema was right, which is worth recording:

- CID-03 initially banned every text column and so flagged
  `mobile_encryption_key_versions.key_manager_ref`. That column is a non-secret KMS/HSM key identifier —
  exactly the external-custody shape the register recommends for PS-3. The test was tightened to ban
  `bytea` and unconstrained text instead.
- CID-05 initially looked for fingerprint uniqueness on `student_contact_index` and failed. That table is
  keyed `(student_id, key_version)` and deliberately carries **no** fingerprint uniqueness: it answers
  "what is this student's contact", not "who owns this contact". The global rule lives on
  `enrollment_claim_identity_aliases` as a partial unique index over `(key_version, mobile_hmac,
  grade_key)` restricted to live claim states. So **two students can share a fingerprint in the contact
  index**; what they cannot do is hold live claims on it in the same grade under the same key. That is
  stated plainly in the test, because a reviewer should not have to infer it.

### 13.4 Repository scan for secrets

`docs/phase2/tests/check_no_secret_material.py` scans tracked files for plaintext contacts (Iranian mobile
and generic E.164), long literals assigned to secret-shaped names, PEM private-key blocks and tracked
credential files, and checks every path ever **added** in the Git history for credential-file names.

Result on this repository: **147 tracked files and 186 historical paths, no findings.** The scan was
verified sensitive by planting a fake Iranian number and a fake API key in a tracked file: all three
expected findings fired.

It deliberately does not flag this project's synthetic shapes — `repeat('aa',32)`, `decode('…','hex')`,
`freeze_token='freeze-1'` — because flagging fixtures trains a reader to ignore the check, which is worse
than not having it. **It is reported as a repository check, never as implementation evidence**, and it
states its own limitation: a pattern scan proves the absence of the shapes it knows, not the absence of
secrets. Real assurance needs a secret-scanning service on the repository, which is operational and
outside it.

### 13.5 What is NOT claimed for Batch 7

- **No production key management.** PS-1..PS-4 are deferred and nothing here invents an algorithm, a key
  policy, a rotation schedule or a revocation source. Rotation is tested as a **mechanism**: the gate
  serializes, the states transition, coverage is asserted.
- **No cryptographic strength claim.** The tests assert shapes and serialization, never that a cipher or
  MAC is sound.
- **No proof that an opaque `_ref` holds a non-secret.** No database assertion can establish that; it is
  an operational property belonging to PS-3/PS-4.
- **No rollback/recovery testing beyond transaction abort.** The brief lists "rollback and recovery"; what
  is covered is that a refused contact change leaves the proof unconsumed with no command reservation and
  no audit row (CC-FRESH-02, and the aborts observed here). Recovery of a partially completed rotation
  across a process crash needs a process, and none exists.
- **Phase 2 is not self-approved.** This is an implementation report, not a review.
