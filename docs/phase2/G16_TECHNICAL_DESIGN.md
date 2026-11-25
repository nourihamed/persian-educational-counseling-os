# G-16 — DailyRoutine Counters: Technical Design

**Status:** DESIGN ONLY — READY FOR INDEPENDENT SUPERVISOR DESIGN REVIEW — **NOT APPROVED**
**Author role:** primary implementation agent (not a Supervisor review, not a Product Owner decision)
**Base:** Supervisor branch `supervisor/phase2-final-reconciliation-2026-11-22` @ `64fc9b19d97dd460b9a10a7ef964c5568bc8a226`
**Companions:** `G16_UNRESOLVED_DECISIONS.md`, `G16_ACCEPTANCE_TEST_PLAN.md`
**Gate context:** Phase 2 NOT READY. Phase 3 NOT AUTHORIZED. D-014: synthetic data only. PR #14 is a separate branch and is not merged or rebased with this work.

> Nothing in this document is implemented, migrated, granted or tested. No SQL draft was modified, no migration was created, no runtime write privilege was added, no production key was introduced.

---

## 0. How to read this document

Every normative statement carries one of three tags:

| Tag | Meaning |
|---|---|
| **[APPROVED]** | Product Owner semantics from `PO_DECISION_G16_DAILY_ROUTINE_COUNTERS_2026-11-23.md`. Not reinterpreted. Referenced as `A-xx` (§1 table rows) or `N-xx` (§2 invariants). |
| **[PROPOSED]** | Technical implementation detail proposed by this design. Subject to independent Supervisor review. Not a product decision. |
| **[OPEN: id]** | Depends on an unresolved decision in `G16_UNRESOLVED_DECISIONS.md` (`U-xx`, `X-xx`). The design states a fail-closed fallback and the schema shape that survives every option. |

If a proposal below appears to change an approved rule, the approved rule wins and the proposal is a defect.

### 0.1 Approved-rule index used throughout

| ID | Approved rule (PO §1) | ID | Approved rule (PO §1) |
|---|---|---|---|
| A-01 | Multiple named counters per DailyRoutine | A-11 | Archive, never delete; archived counter takes no new events; no reactivation |
| A-02 | Standardized extensible unit vocabulary; no free-text units | A-12 | Simultaneous valid events both retained; atomic concurrency control |
| A-03 | Only Platform adds/changes unit definitions | A-13 | Store user-asserted `occurred_at` and server `recorded_at` |
| A-04 | Student and responsible counselor may append progress events | A-14 | Backdating allowed within a Platform-configured maximum window |
| A-05 | Every event records the authenticated actor from the trusted boundary | A-15 | Late-entry reason only when delay exceeds Platform-configured threshold |
| A-06 | Correction by original author or responsible counselor | A-16 | No generic optional note field |
| A-07 | Correction requires reason and original-event reference; chain preserved | A-17 | Workspace timezone is the basis for local date and delay |
| A-08 | Append-only history; current value derived by aggregation | A-18 | Timezone change applies to future events only; history never recalculated |
| A-09 | Idempotency key per event command; same-key/different-payload rejected | A-19 | Max backdating window is Platform-configurable; no numeric value approved |
| A-10 | Negative values prohibited by default; Platform enables per counter | A-20 | Late-reason threshold is Platform-configurable; no numeric value approved |

PO §2 invariants are referenced as **N-01 … N-15** in the order they appear in the decision record.

---

## 1. Scope and non-goals

**In scope:** logical and relational model, lifecycles, ledger, authorization, idempotency, concurrency, time and timezone, Platform-controlled vocabulary and configuration, negative policy, archive, constraints and indexes, command contracts, security risks, additive changes required of existing objects.

**Out of scope / not claimed:** SQL, migrations, API or UI implementation, workers, completion percentage / mastery / risk derivation (**N-15**), Program-template counter provisioning (Phase 15), reports, notifications, any production verifier or key (PS-1..PS-8 remain open), any acceptance of G-16.

---

## 2. Architecture placement [PROPOSED]

### 2.1 Two data domains

The Workspace model is one PostgreSQL database per Workspace with no cross-database grants (G-04). G-16 therefore splits into:

| Domain | Authority | Lives in | Written by |
|---|---|---|---|
| **Student-scoped counter data** — definitions, versions, event ledger | Workspace | Workspace database | Trusted command boundary only (§8) |
| **Platform reference data** — unit vocabulary, backdating/late-reason configuration, per-counter negative-value policy | Platform | Authoritative in Platform/Control Plane; **read-only projection** in every Workspace database | A dedicated projector identity only (§12) |

**Why a projection:** a foreign key from a Workspace table to a Platform table cannot exist across databases. **A-03 / N-02** require that a counter's unit reference be to the centrally governed vocabulary; the projection is what makes that reference enforceable by an ordinary local foreign key.

**[OPEN: X-03]** The distribution channel (Control Plane → Workspace) is a Platform Security / architecture dependency analogous to OQ-SAGA-1. Until a verified channel exists the projection tables are empty and **every event command fails closed** (§12.4).

### 2.2 Reuse of existing mechanisms (no new trust model)

| Concern | Existing mechanism reused |
|---|---|
| Who is calling | `establish_principal()` → `current_principal_membership()` / `current_principal_student()` (WS-ISO-01; synthetic test mode only, production fail-closed) |
| Responsible counselor | `counselor_is_responsible_for(membership, student)` |
| Counselor boundary | `counselor_may_access_student()` + RLS ENABLE/FORCE + mandatory RESTRICTIVE principal fence |
| Privileged identity | F-05 identity-check pattern (session must BE the NOLOGIN writer identity) |
| Transfer fence | catalog-driven write barrier on every table with a `student_id` column |
| Append-only | row triggers + statement-level TRUNCATE guards (OPS-60..64 pattern) |
| Clock | `clock_timestamp()` read once after locks; CLK-01 catalog scan forbids transaction-start clocks |
| Retention | `retention_entity_types` registry, `legal_holds`, fail-closed disposition gate |
| Rules testable at boundaries | pure functions taking explicit timestamps (CRD-32..38 precedent) |

---

## 3. Logical model [PROPOSED shape, A-01..A-20 semantics]

```text
DailyRoutine (existing)  1 ──< N  Counter                       (A-01)
Counter                  N ──> 1  Unit            [Platform]    (A-02, A-03)
Counter                  1 ──< N  CounterVersion                (name, order, target; append-only)  [OPEN: U-02, U-10]
Counter                  1 ──< N  CounterEvent                  (the ledger; A-08)
CounterEvent(correction) N ──> 1  CounterEvent(progress)        (A-07)
Counter                  1 ──< N  NegativePolicyVersion [Platform]  (A-10)
CounterEvent             N ──> 1  BackdatingConfigVersion [Platform] (A-14..A-20, when delay > 0)
CounterEvent             N ──> 1  WorkspaceTimezoneVersion      (A-17, A-18)
```

Derived (never stored as authority, **N-07**): bucket totals per `(counter, local date)`; see §15.

**[OPEN: X-01]** The ledger is **bucket-agnostic**: it records `bucket_local_date` on every event. Whether the product value is "per local day" (recommended reading of master §29, `Target=5, Completed=4`) or "cumulative" only changes read models and the scope of the non-negative floor — not the ledger shape.

---

## 4. Relational schema [PROPOSED]

The following is a column-level specification, **not an executable draft**. Names are proposals. Types marked `numeric*` depend on **[OPEN: U-01]**.

### 4.1 `routine_counters` (Workspace) — immutable core

| Column | Type | Constraint / note |
|---|---|---|
| `counter_id` | uuid | PK |
| `routine_id` | uuid | NOT NULL |
| `student_id` | uuid | NOT NULL |
| `counter_key` | text | NOT NULL; ASCII slug CHECK; immutable; length bound is a review parameter (T-02) |
| `unit_id` | uuid | NOT NULL → `platform_counter_units` (local projection); immutable (**N-02**) |
| `lifecycle_state` | text | CHECK IN (`active`,`archived`); default `active` |
| `created_at` | timestamptz | NOT NULL (trigger-set from `clock_timestamp()`) |
| `created_by_actor_kind` / `_membership_id` / `_student_id` | text/uuid/uuid | exactly-one actor CHECK; **[OPEN: U-10]** which kinds may create |
| `authn_event_ref` | text | NOT NULL; set from verified principal, never from caller |
| `archived_at` | timestamptz | `(lifecycle_state='archived') = (archived_at IS NOT NULL)` |
| `archived_by_*` | as above | actor of the archive |

Constraints: `FOREIGN KEY (routine_id, student_id) REFERENCES daily_routines(routine_id, student_id)` (requires an additive `UNIQUE(routine_id, student_id)` on `daily_routines`, §21); `UNIQUE (routine_id, counter_key)` (key never reused, including after archive — **[OPEN: U-10]**); `UNIQUE (counter_id, routine_id, student_id)` (composite FK target). **No `ON DELETE` action anywhere** (CUR-09 pattern). Trigger: identity columns immutable; `lifecycle_state` may only move `active → archived`; archived rows immutable (**A-11**).

### 4.2 `routine_counter_versions` (Workspace) — append-only definition history

`version_id` PK · `counter_id`,`routine_id`,`student_id` (composite FK to counters) · `version_no` (≥1, `UNIQUE(counter_id, version_no)`) · `display_name` (non-empty) · `display_order` (≥1) · `target_value numeric*` (**[OPEN: U-02]** mandatory vs optional; recommended mandatory) · `effective_from_local_date date` · actor columns · `authn_event_ref` · `recorded_at`. Row triggers refuse UPDATE/DELETE; TRUNCATE guarded. Lookup rule: the target for bucket date `d` is the row with the greatest `version_no` whose `effective_from_local_date ≤ d`. Retroactive effect is governed by **U-02**.

### 4.3 `routine_counter_events` (Workspace) — the ledger

| Column | Type | Constraint / note |
|---|---|---|
| `event_id` | uuid | PK; server-generated |
| `counter_id`,`routine_id`,`student_id` | uuid | composite FK → `routine_counters(counter_id, routine_id, student_id)` (N-01, N-05) |
| `event_seq` | bigint | ≥1; `UNIQUE(counter_id, event_seq)`; assigned `max+1` **under the counter lock**; gives a clock-independent total order |
| `event_kind` | text | CHECK IN (`progress`,`correction`) **[OPEN: U-03]** |
| `delta` | numeric* | `<> 0`; **explicit rejection of `NaN`, `Infinity`, `-Infinity`** (PostgreSQL `numeric` accepts them); never float |
| `bucket_local_date` | date | NOT NULL; server-derived; progress: = `occurred_local_date`; correction: = original's bucket (**[OPEN: X-01, U-04]**) |
| `occurred_at` | timestamptz | user-asserted for progress (**A-13**); for corrections = `recorded_at` (system-asserted) **[OPEN: U-04]** |
| `recorded_at` | timestamptz | NOT NULL; **BEFORE INSERT trigger overwrites with `clock_timestamp()` unconditionally** — a supplied value is ignored even for privileged writers (**N-11**) |
| `tz_version_id` | uuid | → `workspace_timezone_versions`; tz in force at `recorded_at` (**N-12**) |
| `tz_name` | text | denormalized copy; immutable evidence |
| `occurred_utc_offset_seconds`, `recorded_utc_offset_seconds` | integer | resolved offsets at write time; survive later tzdata changes **[OPEN: U-09]** |
| `occurred_local_date`, `recorded_local_date` | date | derived with an **explicit zone** (never the session `TimeZone`) |
| `late_reason` | text | NULL unless the delay exceeded the threshold (**A-15**); no other note column exists (**A-16**) |
| `backdating_config_version_id` | uuid NULL | → Platform config projection; required when the entry is classified backdated |
| `negative_policy_version_id` | uuid NULL | evidence of the policy applied; NULL = default (prohibited) |
| `corrects_event_id` | uuid NULL | required iff `event_kind='correction'` |
| `corrects_event_kind` | text | `GENERATED ALWAYS AS (CASE WHEN event_kind='correction' THEN 'progress' END) STORED` |
| `correction_reason` | text NULL | required (non-empty after trim) iff correction (**A-07**) |
| `actor_kind` | text | CHECK IN (`student`,`counselor`) |
| `actor_student_id` / `actor_membership_id` | uuid | exactly one set; FK to `students` / `workspace_memberships`; student actor must equal `student_id` |
| `actor_ref` | uuid | `GENERATED ALWAYS AS (COALESCE(actor_student_id, actor_membership_id)) STORED` |
| `authn_event_ref` | text | NOT NULL; copied from the verified principal context (**A-05**) |
| `idempotency_key` | text | NOT NULL; format **[OPEN: U-05]** |
| `request_fingerprint` | bytea | NOT NULL, 32 bytes; **computed by the database**, never accepted from the caller |
| `fingerprint_version` | smallint | NOT NULL; versions the canonicalization |

**Declarative integrity (no trigger needed):**

1. `UNIQUE (event_id, counter_id, event_kind, bucket_local_date)`.
2. `FOREIGN KEY (corrects_event_id, counter_id, corrects_event_kind, bucket_local_date) REFERENCES routine_counter_events(event_id, counter_id, event_kind, bucket_local_date)` → a correction can only reference a **progress** event of the **same counter** and **same bucket**; cross-counter, cross-routine, cross-student references are structurally impossible (**N-05**). This is the "cross-version substitution" technique already used for `test_responses`.
3. `CHECK (corrects_event_id IS DISTINCT FROM event_id)` (a self-reference would otherwise satisfy the FK).
4. `CHECK ((event_kind='correction') = (corrects_event_id IS NOT NULL AND correction_reason IS NOT NULL AND length(btrim(correction_reason))>0))`.
5. `CHECK (event_kind='progress' OR late_reason IS NULL)`.
6. `CHECK ((actor_kind='student') = (actor_student_id IS NOT NULL AND actor_membership_id IS NULL))` and its counselor mirror; `CHECK (actor_kind <> 'student' OR actor_student_id = student_id)`.
7. `UNIQUE (actor_kind, actor_ref, idempotency_key)` — the idempotency scope **[OPEN: U-05]**.
8. `CHECK (delta <> 0 AND delta NOT IN ('NaN','Infinity','-Infinity'))` (cast to numeric).
9. `CHECK (recorded_at >= occurred_at - …)` is **not** declared: the relationship depends on skew configuration **[OPEN: U-08]** and is enforced by the guard trigger.

**Guard trigger (BEFORE INSERT, binds every writer, §7):** recomputes and validates everything that depends on state: verified principal equals actor, authority predicate, counter active, unit status, scale and bounds, sign rule, time classification, configuration lookup, negative floor, correction bound. A writer that bypasses the command function faces the same checks.

**Indexes:** `(counter_id, event_seq)` unique (PK-like order scan); `(counter_id, bucket_local_date) INCLUDE (delta)` (bucket sums, floor check); `(corrects_event_id)` (correction bound); `(student_id, bucket_local_date)` (student/day listing); the idempotency unique index above; `(counter_id, recorded_at)` for audit scans. Every index has an owning query in §16.

### 4.4 Platform reference projections (Workspace, read-only to every application role)

**`platform_counter_units`** — `unit_id` PK · `unit_key` UNIQUE · `scale smallint` · `max_abs_event_delta numeric` · `max_abs_bucket_value numeric` · `status` (`active`,`deprecated`; `retired` only if **U-06** approves) · `catalog_epoch bigint` · `source_ref` · `projected_at`. Meaning columns (`unit_key`, `scale`, bounds) are immutable; only `status` moves forward. Labels live in `platform_counter_unit_labels(unit_id, locale, label, label_version)` — append-only, presentation only, never semantic (**N-02**).

**`platform_routine_config_versions`** — `config_version_id` PK · `version_no` UNIQUE · `max_backdate_seconds bigint` (>0) · `late_reason_threshold_seconds bigint` (≥0, ≤ window) · `max_future_skew_seconds bigint` (≥0) **[OPEN: U-08]** · `effective_from timestamptz` (≥ `projected_at`: never retroactive) · `source_ref` · `projected_at`. **No row is seeded and no default value exists** (**N-13**). Seconds are a *storage normalization*, not a statement about the operator-facing unit **[OPEN: U-07]**.

**`platform_counter_negative_policy_versions`** — `policy_version_id` PK · `counter_id` (→ `routine_counters`) · `version_no` · `allow_negative boolean` · `effective_from` (≥ `projected_at`) · `source_ref` · `projected_at`. Absence of a row **means prohibited** (**A-10** default). No Workspace role holds any privilege here.

**`workspace_timezone_versions`** (Workspace; **[OPEN: X-04]** authority) — `tz_version_id` PK · `version_no` · `tz_name` (validated against `pg_timezone_names` at insert) · `effective_from` (never retroactive) · actor columns · `recorded_at`. Append-only. No row ⇒ no events (§11.5).

**`platform_reference_gate`** — singleton row, the lock anchor for global Platform changes (§10).

---

## 5. Lifecycles [PROPOSED unless tagged]

### 5.1 Counter

```text
(create) → active ──archive──▶ archived   (terminal; A-11; no reactivation path exists anywhere)
```

* `active`: accepts progress and correction events, revisions (U-10).
* `archived`: accepts **no** events and **no** revisions; all reads and audit remain available (**N-10**).
* There is no function, trigger branch, role grant or route that moves `archived → active`. A catalog test asserts the absence (DRC-ARC).
* A counter whose parent routine is deactivated: **[OPEN: X-04]**; fail-closed fallback — events refused while `daily_routines.active = false`.

### 5.2 Event

An event has exactly one state: **committed**. There is no draft, pending, voided or deleted state. A mistaken event is never edited; it is compensated by a `correction` (**A-08, N-04**).

### 5.3 Correction chain [OPEN: U-04]

```text
progress E1 (+5)
   ├─ correction C1 (−2)  corrects E1, reason R1        ← flat, cumulative bound Σ|C| ≤ |E1|
   └─ correction C2 (−1)  corrects E1, reason R2
```

Recommended shape is a **flat** set of corrections under each original. "Preserve the full chain" (**A-07**) is satisfied by never overwriting and by the reference + reason on every correction. Correction-of-correction is **not** in the recommended design and needs explicit PO confirmation (U-04, interpretation I-3).

### 5.4 Unit

`active → deprecated` (no new counters may select it; existing counters continue). `retired` is **not designed**; it requires a PO decision (U-06). A unit's meaning is never edited; a changed meaning is a **new** `unit_id` (**N-02**).

### 5.5 Platform configuration

Append-only versions. An event is evaluated against the version **in force at its own `recorded_at`** **[OPEN: U-07]** and records that version's id. No recalculation of past events when a new version is published.

---

## 6. Counter and event lifecycle commands — summary table

| Command | Actor kinds (recommended) | Writes | Locks (§10) |
|---|---|---|---|
| `CreateRoutineCounter` | responsible counselor **[OPEN: U-10]** | counter + version 1 | L2(S) |
| `ReviseRoutineCounter` | responsible counselor **[OPEN: U-10, U-02]** | new version row | L3 |
| `ArchiveRoutineCounter` | responsible counselor **[OPEN: U-10]** | counter state | L3 |
| `AppendProgressEvent` | student (own) · responsible counselor (**A-04**) | event | L1, L3, L2(S), L4, L5 |
| `AppendCorrectionEvent` | original author · responsible counselor (**A-06**), both under live authority | event | L1, L3, L2(S), L4, L5 |

Platform-side commands (`PublishCounterUnit`, `PublishRoutineConfigVersion`, `SetCounterNegativePolicy`) are **not Workspace commands**; see §12 and **[OPEN: X-02]**.

---

## 7. Append-only ledger enforcement [APPROVED A-08, N-04; mechanism PROPOSED]

1. **No privilege:** no application role (runtime, worker, exporter, test writer) holds UPDATE, DELETE or TRUNCATE on `routine_counter_events` or `routine_counter_versions`. Verified by a catalog audit (DRC-PRV), not by a list of remembered names.
2. **Row triggers** `BEFORE UPDATE OR DELETE` refuse every change, for every writer.
3. **Statement-level TRUNCATE guard**, installed by the same catalog-driven mechanism as OPS-60..64 (the table is student-scoped, so the existing audit must find it covered with zero holes).
4. **Row locks on ledger rows do not mutate them** and are not used by this design (the counter row is the lock anchor, §10).
5. **Documented residual (as SEC-08):** a table owner or superuser can disable triggers. The design does not claim to bind the owner; containing that identity is the F-05 / operational control. A test asserts the limitation so it cannot silently become a claim.
6. **recorded_at / event_seq / actor / fingerprint / derived dates are overwritten or verified by the trigger**, so a privileged INSERT cannot forge them.

---

## 8. Actor authorization [APPROVED A-04, A-05, A-06, N-03; mechanism PROPOSED]

### 8.1 Trust boundary

* Command functions take **no** actor, role or responsibility parameter. A catalog test fails if any parameter name matches `actor*`, `role*`, `responsible*`, `membership*`, `student_principal*`.
* Identity is read only from `current_principal_membership()` / `current_principal_student()`. These return NULL outside the establishing transaction/backend/session role; NULL reaches nothing (fail-closed).
* `authn_event_ref` is copied from the verified principal context by the database.
* Production verification is **disabled** (PS-1..PS-8 open). The command EXECUTE grant goes only to a dedicated NOLOGIN synthetic writer identity checked with the F-05 identity pattern; **no production role is granted EXECUTE**. This design adds no runtime write path.

### 8.2 Authority predicate (evaluated under locks, at command time — **N-03**)

| Actor | Append progress | Append correction |
|---|---|---|
| **Student** | principal student = counter's `student_id`, student `active`, counter `active` | only for a progress event authored by the **same student** (live authority) |
| **Responsible counselor** | `counselor_is_responsible_for(membership, student)` (active, accepted, `is_responsible`), membership `active` | any progress event of that counter's student |
| Assigned but **not responsible** counselor | denied | denied |
| Unassigned / other-student / other-Workspace actor | denied (uniform not-found) | denied |
| Suspended / ended membership, ended or unaccepted assignment | denied | denied |
| Parent / guardian / teacher / Platform Admin | denied (no write authority) | denied |
| Former author counselor who is no longer responsible | denied | denied — the **author clause requires the author to *currently* hold append authority** (interpretation **I-1**) |

The assignment row is read `FOR SHARE` (L4) so an assignment ending concurrently serializes either before the check or after our commit — never between check and insert.

### 8.3 Error visibility

Object-level denial (not visible / not authorized to even read the counter) returns the **same** result as a missing counter (uniform not-found, G-27). An actor who may read the counter but lacks write or correction authority receives `forbidden`. Raw constraint violation text (PostgreSQL FK `DETAIL` echoes key values) is never returned (R-07).

---

## 9. Idempotency [APPROVED A-09, N-06; details OPEN: U-05]

### 9.1 Scope and storage [PROPOSED]

`UNIQUE (actor_kind, actor_ref, idempotency_key)` on the ledger: one key namespace per authenticated actor, shared by `progress` and `correction`. Keys therefore cannot collide across actors, commands or (by database boundary) Workspaces. The key lives on the event row, so its retention equals the ledger's; **no TTL exists**. Rejected commands store nothing (their outcome is a deterministic function of state), so a rejected request can be retried with the same key after the cause is fixed.

### 9.2 Fingerprint [PROPOSED]

Computed **inside the database** from typed parameters (the existing `submit_test_attempt` accepts a caller-supplied hash; this design does not). Format, no JSON (M-05/M-06 avoided):

```text
drc1;<command_kind>;<counter_id>;<delta normalized to unit scale, ASCII, no exponent>;
<occurred_at as integer µs since epoch UTC | "-" for correction>;<late_reason normalized | "-">;
<corrects_event_id | "-">;<correction_reason normalized | "-">
```

`SHA-256` over the UTF-8 bytes, stored with `fingerprint_version`. Normalization: NFC, trim, fixed delta text (`5` and `5.00` collapse at scale 0; the API rejects a more precise value than the unit's scale rather than rounding).

### 9.3 Algorithm (within the command, §10)

1. Take the idempotency advisory lock (L1) — makes same-key requests deterministic.
2. Look up `(actor_kind, actor_ref, key)`.
3. Found + equal fingerprint → **replay**: re-authorize read authority, return the original event (no new row). Found + different fingerprint → `idempotency_key_reuse` rejection.
4. Not found → validate, insert with `ON CONFLICT DO NOTHING`; if 0 rows inserted (lost a race on a different counter with the same key), re-read and apply step 3.

### 9.4 Replay authorization [OPEN: U-05, interpretation I-2]

Recommended: a replay requires the actor to **still** hold read authority on the counter; otherwise the answer is the uniform not-found. This avoids leaking event data to a revoked actor but is a reading of "returns the original outcome" that the PO should confirm. A replay after the counter was archived still returns the original event (it creates nothing).

---

## 10. Concurrency and transaction boundaries [APPROVED A-12, N-08; mechanism PROPOSED]

### 10.1 Isolation

`READ COMMITTED` with explicit row locks. Each statement after a lock sees all committed data, so validation after lock acquisition is current. `SERIALIZABLE` was rejected: serialization failures would reject valid concurrent events unless a retry layer exists, which conflicts with **A-12** ("do not reject a valid second event merely because it is concurrent"). Waiting is permitted; rejecting is not.

### 10.2 Lock protocol (total order)

| Order | Lock | Mode | Taken by | Purpose |
|---|---|---|---|---|
| L1 | advisory xact lock on `hashtextextended(actor_kind‖':'‖actor_ref‖':'‖key)` | exclusive | event commands | same-key determinism (a hash collision only adds waiting, never wrongly merges) |
| L3 | `routine_counters` row | `FOR UPDATE` | every command on that counter; per-counter negative-policy projector | serializes events, corrections, archive, revisions, policy changes **per counter** |
| L2 | `platform_reference_gate` | `FOR SHARE` (events, counter creation) / `FOR UPDATE` (global config & unit projector) | | serializes global Platform changes against events |
| L4 | `counselor_assignments` row | `FOR SHARE` | counselor-actor commands | authority stability |
| L5 | `students` row | `FOR SHARE` | existing write barrier on insert | transfer freeze fence |

Acquisition order is **L1 → L3 → L2 → L4 → L5** (counter creation has no L3; it takes L2 then inserts). Global projector takes only L2; per-counter policy projector takes L3 then L2. This yields no cycle among the participants listed. **Review obligation:** the Supervisor must verify against the existing freeze, archive and activation commands that none takes L5 and then reaches L3/L2 (§20, R-04).

Because every command on a counter takes the same exclusive row lock, **both concurrent valid events are retained** (the second waits, then validates against the first's committed result) and **no increment or correction is lost**. Contention is bounded to one counter of one student.

### 10.3 Transaction boundary

One database transaction per command: `establish_principal` → command → commit. A failure at any step rolls back the event, `event_seq` and the idempotency key atomically (**N-09**); no partial correction exists. The pure-rule functions (§11.4) are `IMMUTABLE`/`STABLE` and lock nothing.

### 10.4 Defense in depth

The guard trigger re-takes L3 (`PERFORM 1 FROM routine_counters WHERE counter_id=NEW.counter_id FOR UPDATE` — a no-op re-entry within the same transaction) so a writer that bypasses the command is still serialized. Archive vs. insert, policy change vs. insert and configuration change vs. insert therefore resolve deterministically in both lock orders, with commit and rollback variants (DRC-RACE).

---

## 11. Time, timezone and backdating [APPROVED A-13..A-20, N-11..N-14]

### 11.1 Two timestamps

`occurred_at` is user-asserted, `recorded_at` is server-authoritative and overwritten by the trigger. Both are stored and neither is ever recomputed.

### 11.2 Timezone basis [APPROVED A-17, A-18]

The timezone is the **Workspace** timezone in force at `recorded_at`, from `workspace_timezone_versions`. The event persists `tz_name`, `tz_version_id`, both resolved UTC offsets and both local dates. A later timezone change appends a version and affects only later events; stored columns are never recalculated. **Derivation always uses an explicit zone** (`timestamptz AT TIME ZONE <name>`); a cast to `date` that depends on the session `TimeZone` setting is forbidden and tested with varied session settings.

> Existing `daily_routines.timezone_name` is **not** the basis (the PO approved the *Workspace* timezone). The column is left untouched; its fate is **[OPEN: X-04]**.

### 11.3 Classification [PROPOSED; values OPEN: U-07, U-08]

```text
delay        = recorded_at − occurred_at            (elapsed seconds, not calendar days)
future       = occurred_at > recorded_at + max_future_skew        → reject
backdated    = delay > 0 beyond skew
backdated and delay > max_backdate_seconds           → reject  (outside window)
backdated and delay > late_reason_threshold_seconds  → late_reason REQUIRED (strictly greater)
delay ≤ threshold                                    → late_reason must be NULL  (no note channel, A-16; interpretation I-7)
```

Equality at the window and at the threshold is a defined boundary: equal to the window → accepted; equal to the threshold → no reason required.

### 11.4 Pure rule functions (test seam) [PROPOSED]

`drc_classify_delay(occurred, recorded, window_s, threshold_s, skew_s)` and `drc_local_date(instant, tz_name)` take explicit arguments and read no clock. The command and trigger **call them** (a catalog test asserts no second copy of the rule exists, mirroring CRD-38). This is how exact-equality boundaries are tested without faking `clock_timestamp()`.

### 11.5 Fail-closed behavior [APPROVED N-13; behavior OPEN: U-07]

* No valid configuration version in force → **event commands refuse** (recommended fallback: the feature is disabled until configuration exists; no numeric default is invented).
* No Workspace timezone version → refuse.
* No unit row for the counter's unit → refuse.
* Projection tables are written only by a verified projector; invalid rows (non-positive window, threshold > window, `effective_from < projected_at`) are refused at insert, so an invalid configuration cannot exist.

### 11.6 Input form [OPEN: U-09]

Recommended: the API accepts `occurred_at` only as an **absolute instant** (RFC 3339 with explicit offset or `Z`, ≤ 6 fractional digits; more digits are rejected, not rounded). Wall-clock entry is converted by the client, which removes DST gap/overlap ambiguity from the server contract. Day boundaries are half-open `[00:00:00, next 00:00:00)` in the Workspace zone. Windows and thresholds are elapsed seconds, so 23- or 25-hour days do not change them.

---

## 12. Platform-controlled vocabulary and configuration [APPROVED A-02, A-03, N-02]

### 12.1 Unit identity

Immutable rows; a change of meaning is a **new** `unit_id`. Label/localization changes are separate append-only rows. Counters reference `unit_id`; the counter's `unit_id` is immutable (**N-02**). Recommended lifecycle `active → deprecated` only (**[OPEN: U-06]**).

### 12.2 No Workspace mutation path

A catalog audit asserts that no role other than the projector identity has INSERT/UPDATE/DELETE/TRUNCATE on any `platform_*` projection, and that the runtime/worker/exporter/synthetic-writer have SELECT only. A Workspace role cannot create a local unit, change a unit, or flip a negative policy (**A-03, A-10**).

### 12.3 Per-counter negative-value policy

See §13. The policy lives in a Platform projection, not on the counter row, so no Workspace-writable column can carry it.

### 12.4 Staleness and distribution [OPEN: X-03]

Projection rows carry `catalog_epoch`/`source_ref`/`projected_at`. Events record the config and policy version they were evaluated against. Maximum tolerated staleness is a Platform Security parameter not chosen here; with no verified channel, projections are empty and commands fail closed.

### 12.5 Governance workflow [OPEN: X-02]

Who may publish a unit, a configuration version, or a per-counter negative policy, with what approval and audit, is unresolved (PO §3, last bullet). The design requires only that every change is an append-only, attributable Platform record.

---

## 13. Negative-value policy [APPROVED A-10, N-09]

| Aspect | Design |
|---|---|
| Default | Prohibited. No policy row ⇒ prohibited. |
| Enable | Only via a Platform policy version for that **counter**. |
| Evaluated on | The guard trigger, under the counter lock, using the policy version in force at `recorded_at`; the version id is stored on the event. |
| Scope of "negative" | **[OPEN: U-03]** recommended: the policy governs both the **sign of a progress delta** (positive-only when prohibited) and the **bucket total floor** (≥ 0 when prohibited). |
| Failure | Atomic: the whole command rolls back (no event, no `event_seq` consumed, no idempotency key stored). |
| Tightening while a bucket is already negative | **[OPEN: X-02]** recommended: forbid publishing a prohibiting policy while any bucket of that counter is negative, checked under L3, so "prohibited ⇒ no negative bucket" stays a universal invariant. |

---

## 14. Archive behavior [APPROVED A-11, N-10]

`ArchiveRoutineCounter` locks L3, sets `lifecycle_state='archived'`, `archived_at`, `archived_by_*`. The guard trigger on the ledger reads the counter state under the same lock, so an in-flight event and an archive serialize in both orders (event first → committed and retained, archive waits; archive first → event refused). Archived counters, their versions, events and totals remain readable. No reactivation exists. Re-issuing archive on an archived counter is a no-op returning the existing state (natural idempotency; no key required). A replacement measurement uses a **new** counter with a new key (**U-10**).

---

## 15. Derived values [APPROVED A-08, N-07, N-15; caching OPEN: U-11]

* `routine_counter_bucket_totals_v`: `(counter_id, bucket_local_date, total = sum(delta), event_count, last_event_seq)`.
* `routine_counter_state_v`: totals joined with the target in force for that bucket date.
* Both views are created `WITH (security_invoker = true)` so row-level security applies to the **caller**, not the view owner (a default definer-style view would bypass RLS — R-15).
* The views expose raw values only. **No completion percentage, ratio, "target met" flag, mastery, risk or recommendation** exists anywhere (**N-15**); a catalog scan for such columns/functions is part of the regression suite.
* **Recommended v1: no stored aggregate.** Authoritative checks (floor, correction bound) read the ledger under L3. A transactionally maintained totals table is pre-designed as a rebuildable evolution (needs a verify/rebuild function and reconciliation tests) and requires no PO decision; any eventually consistent read exposed as authoritative does.

---

## 16. Index, key and constraint catalog

| Object | Kind | Purpose | Backs |
|---|---|---|---|
| `routine_counters` PK(`counter_id`) | PK | identity | A-01 |
| `routine_counters` UNIQUE(`routine_id`,`counter_key`) | UNIQUE | stable key per routine | A-01, U-10 |
| `routine_counters` UNIQUE(`counter_id`,`routine_id`,`student_id`) | UNIQUE | composite FK target | N-01, N-05 |
| `routine_counters` FK(`routine_id`,`student_id`) → `daily_routines` | FK | same routine and student | N-01 |
| `routine_counters` FK(`unit_id`) → `platform_counter_units` | FK | controlled vocabulary | A-02, N-02 |
| `routine_counter_versions` UNIQUE(`counter_id`,`version_no`) | UNIQUE | history order | U-02 |
| events PK(`event_id`) | PK | identity | A-08 |
| events FK(`counter_id`,`routine_id`,`student_id`) | FK | ownership | N-01 |
| events UNIQUE(`counter_id`,`event_seq`) | UNIQUE | total order, gaplessness | N-08 |
| events UNIQUE(`actor_kind`,`actor_ref`,`idempotency_key`) | UNIQUE | idempotency | A-09, N-06 |
| events UNIQUE(`event_id`,`counter_id`,`event_kind`,`bucket_local_date`) + self FK | UNIQUE/FK | correction link integrity | A-07, N-05 |
| events FK(`actor_student_id`) / FK(`actor_membership_id`) | FK | actor existence | A-05 |
| events FK(`tz_version_id`), FK(`backdating_config_version_id`), FK(`negative_policy_version_id`) | FK | provenance | A-13..A-20, N-12 |
| events INDEX(`counter_id`,`bucket_local_date`) INCLUDE(`delta`) | INDEX | bucket sums, floor | N-09, §15 |
| events INDEX(`corrects_event_id`) | INDEX | correction bound | U-04 |
| events INDEX(`student_id`,`bucket_local_date`) | INDEX | student/day reads | §15 |
| All tables | rule | **no `ON DELETE`/`ON UPDATE` actions**; every table has a PK | CUR-09, SEC-05 |

---

## 17. Privileges, RLS and integration with existing guards [PROPOSED]

1. **New NOLOGIN owner roles** per Workspace (`…_counter_cmd_owner`, `…_platform_projector`) following the F-05 identity pattern; owners are checked for transitive reach from every application role (F05-17..23 extension).
2. **Lock-only grants:** a command owner needs `UPDATE` to take `FOR UPDATE`/`FOR SHARE`; use column-level lock-only grants on a non-meaningful column (activation-owner precedent), plus guard triggers that refuse any real change.
3. **RLS:** ENABLE + FORCE on counters, versions and events with the mandatory RESTRICTIVE principal fence; SELECT policies: student principal sees own rows; counselor principal where `counselor_may_access_student`. Unknown roles fail closed. **Dependency (R-21):** the *student read scope* in WS-ISO-01 is still open; student reads of counters depend on its closure.
4. **Projection tables** carry no student data; readable by application roles, writable only by the projector.
5. **Transfer freeze:** all three student-scoped tables carry `student_id`, so the catalog-driven write barrier must pick them up; FRZ-01/01b must list them with no hole. Counter creation, revision and archive are also refused for a frozen student.
6. **Clock discipline:** no `now()`/`CURRENT_TIMESTAMP` in any new function or view (CLK-01 will fail by name otherwise).
7. **SECURITY DEFINER hygiene:** pinned `search_path = pg_catalog, pg_temp`, NOLOGIN non-superuser owner, EXECUTE revoked from PUBLIC (SEC-01..10).
8. **Retention:** register the three tables in `retention_entity_types` (uuid keys); legal holds apply; the disposition gate stays fail-closed (Q-020). Immutability and any future erasure obligation are in tension (R-14).
9. **Free text** (`late_reason`, `correction_reason`): bounded length (T-03), no plaintext contact data (reuse the OPS-17 payload pattern — evaluation recommended), never logged.

---

## 18. API command contracts (logical; transport-agnostic) [PROPOSED]

Decimals travel as **strings** (ASCII digits, optional single `.`; no exponent, sign only `-`, no Persian/Arabic-Indic digits — the UI converts). Timestamps are RFC 3339 with offset. Identity is never a field. Error codes are logical names; HTTP mapping is a later-phase (G-27) concern.

### 18.1 `AppendProgressEvent`

| Field | In/derived | Rule |
|---|---|---|
| `counter_id` | in | must be visible and writable by the principal |
| `delta` | in (string) | scale ≤ unit scale; bounds; sign per policy; ≠ 0 |
| `occurred_at` | in | absolute instant; §11 |
| `late_reason` | in, conditional | required iff delay > threshold; otherwise must be absent |
| `idempotency_key` | in | §9; required |
| actor, `authn_event_ref`, `recorded_at`, `event_seq`, tz, offsets, local dates, `bucket_local_date`, versions, fingerprint | **derived** | caller cannot supply |

Success: `{ outcome: "created" | "replayed", event }`. Errors: `unauthenticated`, `not_found` (uniform), `forbidden`, `counter_archived`, `routine_inactive` (X-04), `config_unavailable`, `timezone_unavailable`, `unit_unavailable`, `invalid_delta`, `negative_value_prohibited`, `future_occurred_at`, `backdating_window_exceeded`, `late_reason_required`, `late_reason_not_allowed`, `idempotency_key_reuse`, `frozen_student`.

### 18.2 `AppendCorrectionEvent`

Input: `counter_id`, `corrects_event_id`, `delta` (compensating, sign and bound per U-04), `correction_reason`, `idempotency_key`. Derived as above plus `bucket_local_date` inherited from the original and `occurred_at = recorded_at`. Extra errors: `correction_not_authorized`, `correction_target_invalid`, `correction_bound_exceeded`, `correction_reason_required`.

### 18.3 `CreateRoutineCounter` / `ReviseRoutineCounter` / `ArchiveRoutineCounter` **[OPEN: U-10]**

Definition commands use **natural idempotency**, not keys: create is keyed by `(routine_id, counter_key)` and compares parameters; revise carries `expected_version_no` (stale ⇒ `version_conflict`); archive is state-idempotent. Fields: `routine_id`, `counter_key`, `unit_id` (must be an `active` projected unit), `display_name`, `target_value`, `effective_from_local_date`.

### 18.4 Reads

`GetCounterState(counter_id, bucket_local_date?)`, `ListCounterEvents(counter_id, after_event_seq?, limit)` (ordered by `event_seq`, includes correction links), `ListRoutineCounters(routine_id)`. All through the security-invoker views/RLS; uniform not-found.

### 18.5 Platform commands (not exposed to Workspace API) [OPEN: X-02, X-03]

`PublishCounterUnit`, `DeprecateCounterUnit`, `PublishRoutineConfigVersion`, `SetCounterNegativePolicy`. Their RBAC, maker-checker and signing are unresolved; the design needs only that each produces an append-only attributable record delivered through the verified projector.

---

## 19. Error model and information hygiene [PROPOSED]

* Never return raw SQLSTATE detail, constraint names with key values, or stack traces.
* Uniform not-found for missing, foreign or unreadable objects; no timing difference is promised, but no branch touches ledger rows before authorization.
* Rejections are not stored; there is no "failed attempt" table in v1 (reduces both PII and state-growth risk). Security-relevant denials go to the existing audit path with ids only — never reasons, never payload text.

---

## 20. Security risks

| ID | Risk | Mitigation in this design | Residual / owner |
|---|---|---|---|
| R-01 | Forged or lifted actor identity | no actor parameters; verified principal only; trigger re-checks | PS-1..PS-8 production verifier open — Platform Security |
| R-02 | Forged Platform projection (poisoned unit/config/policy) | projector-only writes; immutable meaning; insert-time validation; version stored on every event | channel signing (X-03) — Platform Security |
| R-03 | Lost update / double correction | exclusive per-counter lock; cumulative bound in trigger | lock-order review vs existing commands |
| R-04 | Archive/policy/config racing with insert; deadlock | single total lock order; defense-in-depth lock in trigger | Supervisor must verify against freeze/archive code |
| R-05 | Idempotency abuse (cross-actor oracle, payload swap) | actor-scoped key; DB-computed fingerprint; advisory lock | — |
| R-06 | Replay leaks data to a revoked actor | replay re-authorizes (I-2) | PO clarification |
| R-07 | Existence oracle via errors / FK detail | uniform not-found; no raw DB text | API-phase tests |
| R-08 | Ledger tampering by owner/superuser | no privilege to apps; triggers; TRUNCATE guards | owner/superuser residual (SEC-08, F05) — Operations |
| R-09 | Client-asserted time abuse; clock regression | window + skew bounds; `recorded_at` forced; per-counter `event_seq` independent of clock | skew values (U-08) |
| R-10 | Timezone pitfalls (session `TimeZone`, tzdata drift) | explicit zone; stored offsets and dates | — |
| R-11 | Numeric abuse (NaN, Infinity, scale, overflow, float) | explicit CHECKs; per-unit bounds; strings on the wire | bounds values (U-01) |
| R-12 | Free-text reasons: PII, log leakage, length DoS | length bound; contact-pattern refusal evaluation; never logged | T-03 value |
| R-13 | Unbounded growth (counters per routine, events) and lock contention | per-counter (not global) locking; counts bounded by review parameters | T-05, T-06 |
| R-14 | Immutable ledger vs erasure/retention | retention registry, legal hold, fail-closed disposition gate | Q-020 — PO/Legal |
| R-15 | RLS bypass through views; cross-reference FKs missing | `security_invoker` views; composite FKs; catalog audits | — |
| R-16 | Stale authority via "author" clause | author clause requires live authority (I-1) | PO clarification |
| R-17 | Freeze coverage gap | catalog-driven barrier; FRZ-01b audit | — |
| R-18 | Aggregate drift if a cache is added | none in v1; rebuild + reconcile if added | U-11 |
| R-19 | Misconfiguration (e.g. enormous window) | threshold ≤ window; positive values; maker-checker | X-02 — PO |
| R-20 | SECURITY DEFINER hygiene | pinned path, NOLOGIN owner, REVOKE PUBLIC | — |
| R-21 | Student read scope for counters not yet defined in WS-ISO-01 | explicit dependency | WS-ISO-01 closure |

---

## 21. Required additive changes to existing objects — **NOT performed**

1. `daily_routines`: add `UNIQUE (routine_id, student_id)` (composite FK target). Existing rows unaffected.
2. New Workspace tables: `routine_counters`, `routine_counter_versions`, `routine_counter_events`, `platform_counter_units`, `platform_counter_unit_labels`, `platform_routine_config_versions`, `platform_counter_negative_policy_versions`, `workspace_timezone_versions`, `platform_reference_gate`.
3. New roles and grants per §17; no application EXECUTE or DML grant.
4. Extend: restrictive RLS fence, write barrier, TRUNCATE guards, retention registry, CLK-01 and SEC catalog scans (they are catalog-driven and will cover the new objects automatically — that is the point).
5. Decide the fate of `daily_routines.timezone_name` (X-04).
6. Update `UNRESOLVED_ITEM_REGISTER` / `unresolved_items.json` with U-xx / X-xx (Supervisor reconciliation; not done here).
7. G-26: a clean-install and upgrade migration fixture for all of the above (no migration chain exists yet).

---

## 22. Dependencies and blockers

| Blocker | Effect on G-16 |
|---|---|
| PS-1..PS-8 (production verifier, keys, channel) | event commands runnable only in synthetic harness |
| WS-ISO-01 student read scope, background-job identity | student reads and any worker use unresolved |
| X-03 reference-data distribution | projections empty ⇒ all event commands fail closed |
| X-01 aggregation bucket | read models and floor scope |
| U-01..U-11, X-02, X-04 | see `G16_UNRESOLVED_DECISIONS.md` |
| G-26 migration framework | no migration chain to add tables to |
| Exact-head CI | none exists for any G-16 object |

---

## 23. Traceability: approved rules → design → tests

| Rule | Design § | Test group (`G16_ACCEPTANCE_TEST_PLAN.md`) |
|---|---|---|
| A-01 | 4.1, 16 | DRC-SCH |
| A-02, A-03, N-02 | 4.4, 12 | DRC-UNT, DRC-PLT |
| A-04, A-05, N-03 | 8 | DRC-AUT |
| A-06, A-07, N-04, N-05 | 4.3, 5.3, 8.2 | DRC-COR, DRC-LED, DRC-SCH |
| A-08, N-07 | 7, 15 | DRC-LED, DRC-AGG |
| A-09, N-06 | 9 | DRC-IDM |
| A-10, N-09 | 13 | DRC-NEG |
| A-11, N-10 | 14 | DRC-ARC |
| A-12, N-08 | 10 | DRC-RACE |
| A-13, A-14, A-15, A-16, A-19, A-20, N-11, N-13, N-14 | 11 | DRC-TIM, DRC-CFG |
| A-17, A-18, N-12 | 11.2 | DRC-TZ |
| N-01 | 4.1, 4.3, 16 | DRC-SCH, DRC-ISO |
| N-15 | 15 | DRC-REG |

---

## 24. Document control

* This document does **not** assert that any schema, function, role, test or CI run exists for G-16.
* It does not decide any item in `G16_UNRESOLVED_DECISIONS.md`; recommendations are not decisions.
* It does not modify `SUPERVISOR_REVIEW.md`, any SQL draft, `main`, PR #12 or PR #14.
* Final status: **READY FOR INDEPENDENT SUPERVISOR DESIGN REVIEW — NOT APPROVED.**
