# G-16 — DailyRoutine Counters: Technical Design

**Status:** DESIGN ONLY — READY FOR ANOTHER INDEPENDENT SUPERVISOR REVIEW — **NOT APPROVED**
**Revision:** 2 — addresses Supervisor finding **H-01** (responsible-counselor authorization and concurrency) raised on review of commit `49c5b48207c34d77ccd7d221eb270e7ccb6b997c`; change summary in §25
**Author role:** primary implementation agent (not a Supervisor review, not a Product Owner decision)
**Base (revision 1):** branch `design/g16-daily-routine-counters-2026-11-24` @ `49c5b48207c34d77ccd7d221eb270e7ccb6b997c`, whose parent is `64fc9b19d97dd460b9a10a7ef964c5568bc8a226` on Supervisor branch `supervisor/phase2-final-reconciliation-2026-11-22`
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
| Responsible counselor | `counselor_is_responsible_for(membership, student)` — **present**, defined in `workspace_principal_assertion_draft.sql`; exact body and omissions in §8.0 |
| Counselor boundary | `counselor_may_access_student()` + RLS ENABLE/FORCE + mandatory RESTRICTIVE principal fence |
| Privileged identity | F-05 identity-check pattern (session must BE the NOLOGIN writer identity) |
| Transfer fence | catalog-driven write barrier on every table with a `student_id` column |
| Append-only | row triggers + statement-level TRUNCATE guards (OPS-60..64 pattern) |
| Clock | `clock_timestamp()` read once after locks; CLK-01 catalog scan forbids transaction-start clocks |
| Retention | `retention_entity_types` registry, `legal_holds`, fail-closed disposition gate |
| Rules testable at boundaries | pure functions taking explicit timestamps (CRD-32..38 precedent) |

**Status of every mechanism in this table:** each exists only as draft SQL under `docs/phase2/workspace/`. None is a migration (no migration chain exists, G-26), and none was executed in preparing this revision. Revision 1 listed them as "existing mechanisms" without saying so; that wording is corrected here (§25).

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

**Guard trigger (BEFORE INSERT, §7):** refuses any insert made outside a command transaction (the transaction-scoped command marker, §10.7) and recomputes and validates everything that depends on state: verified principal equals actor, authority predicate re-asserted (the *locks* that make it race-free are taken only by the command, §8.3), counter active, unit status, scale and bounds, sign rule, time classification, configuration lookup, negative floor, correction bound.

**Indexes:** `(counter_id, event_seq)` unique (PK-like order scan); `(counter_id, bucket_local_date) INCLUDE (delta)` (bucket sums, floor check); `(corrects_event_id)` (correction bound); `(student_id, bucket_local_date)` (student/day listing); the idempotency unique index above; `(counter_id, recorded_at)` for audit scans. Every index has an owning query in §16.

### 4.4 Platform reference projections (Workspace, read-only to every application role)

**`platform_counter_units`** — `unit_id` PK · `unit_key` UNIQUE · `scale smallint` · `max_abs_event_delta numeric` · `max_abs_bucket_value numeric` · `status` (`active`,`deprecated`; `retired` only if **U-06** approves) · `catalog_epoch bigint` · `source_ref` · `projected_at`. Meaning columns (`unit_key`, `scale`, bounds) are immutable; only `status` moves forward. Labels live in `platform_counter_unit_labels(unit_id, locale, label, label_version)` — append-only, presentation only, never semantic (**N-02**).

**`platform_routine_config_versions`** — `config_version_id` PK · `version_no` UNIQUE · `max_backdate_seconds bigint` (>0) · `late_reason_threshold_seconds bigint` (≥0, ≤ window) · `max_future_skew_seconds bigint` (≥0) **[OPEN: U-08]** · `effective_from timestamptz` (≥ `projected_at`: never retroactive) · `source_ref` · `projected_at`. **No row is seeded and no default value exists** (**N-13**). Seconds are a *storage normalization*, not a statement about the operator-facing unit **[OPEN: U-07]**.

**`platform_counter_negative_policy_versions`** — `policy_version_id` PK · `counter_id` (→ `routine_counters`) · `version_no` · `allow_negative boolean` · `effective_from` (≥ `projected_at`) · `source_ref` · `projected_at`. Absence of a row **means prohibited** (**A-10** default). No Workspace role holds any privilege here.

**`workspace_timezone_versions`** (Workspace; **[OPEN: X-04]** authority) — `tz_version_id` PK · `version_no` · `tz_name` (validated against `pg_timezone_names` at insert) · `effective_from` (never retroactive) · actor columns · `recorded_at`. Append-only. No row ⇒ no events (§11.5).

**`platform_reference_gate`** — singleton row, the lock anchor for global Platform changes (§10).

**`platform_projection_config`** (singleton) — `mode IN ('disabled','synthetic_test')`, default `'disabled'`. Every projection table above refuses every write while `mode = 'disabled'`; see §12.6. **No production projector identity exists in this design.**

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

| Command | Actor kinds (recommended) | Writes | Locks (§10.2, acquired in this order) |
|---|---|---|---|
| `CreateRoutineCounter` | responsible counselor, P-RC (§8.2) **[OPEN: U-10]** | counter + version 1 | K1, K2, K3, K4, K5, K7(S) |
| `ReviseRoutineCounter` | responsible counselor **[OPEN: U-10, U-02]** | new version row | K1, K2, K3, K4, K6 |
| `ArchiveRoutineCounter` | responsible counselor **[OPEN: U-10]** | counter state | K1, K2, K3, K4, K6 |
| `AppendProgressEvent` | student (own, P-STU) · responsible counselor (**A-04**, P-RC) | event | K0, K1 (+ K2–K4 for a counselor), K5, K6, K7(S) |
| `AppendCorrectionEvent` | original author · responsible counselor (**A-06**), both under live authority (§8.2) | event | same as `AppendProgressEvent` |

Assigned-but-not-responsible counselors, other counselors, parents/guardians, teachers and Platform Admin hold **no** write authority on any command above (§8.5).

Platform-side commands (`PublishCounterUnit`, `PublishRoutineConfigVersion`, `SetCounterNegativePolicy`) are **not Workspace commands** and are **not executable** in any production path (§12.6); see also **[OPEN: X-02, X-03]**.
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

### 8.0 What exists in the repository (verified for revision 2)

Supervisor finding H-01 asked whether `counselor_is_responsible_for(membership, student)` actually exists. **It does — as draft SQL.** Everything in this table was read from the files at `49c5b48…` (parent `64fc9b1…`); nothing was executed.

| Object | Present | File | Exact behavior | Status |
|---|---|---|---|---|
| `counselor_is_responsible_for(p_membership uuid, p_student uuid)` | yes | `docs/phase2/workspace/workspace_principal_assertion_draft.sql` (last object) | `LANGUAGE sql STABLE`, SECURITY INVOKER. `counselor_may_access_student(p_membership, p_student)` **AND** an `EXISTS` over `counselor_assignments ca JOIN enrollments e` with `ca.counselor_membership_id = p_membership AND e.student_id = p_student AND ca.state = 'active' AND ca.accepted_at IS NOT NULL AND ca.is_responsible` | draft; not a migration |
| `counselor_may_access_student(p_membership uuid, p_student uuid)` | yes | `workspace_counselor_scope_draft.sql` §1 | `LANGUAGE sql STABLE`, SECURITY INVOKER. `EXISTS` over `counselor_assignments ⋈ enrollments ⋈ workspace_memberships ⋈ membership_roles(role_key='counselor')` with `ca.counselor_membership_id = p_membership AND e.student_id = p_student AND ca.state = 'active' AND ca.accepted_at IS NOT NULL AND m.status = 'active'`. **Does not test `is_responsible`.** | draft |
| `establish_principal`, `current_principal_membership()`, `current_principal_student()` | yes | `workspace_principal_assertion_draft.sql` | signed assertion verified in the database; the principal lives for one transaction, one backend, one session role; production verification is fail-closed (`mode = 'disabled'`) | draft; PS-1..PS-4 open |
| `one_responsible_counselor_per_enrollment` | yes | `workspace_schema_draft.sql` | partial unique index: at most one row with `state='active' AND is_responsible` per enrollment | draft |
| `one_active_local_enrollment_per_student` | yes | same | partial unique index: at most one enrollment in (`active`,`suspended`,`awaiting_consent`) per student | draft |

What the existing responsible-counselor predicate does **not** test: the enrollment's `state`; the student's `lifecycle_state`; `ownership_generation`; and it takes **no lock**. Whether a suspended or awaiting-consent enrollment narrows a counselor's access is recorded in the counselor-scope draft as **undecided** under WS-ISO-01. This document does not decide it (**[OPEN: X-05]**).

**Corrections to revision 1.**
(a) Revision 1 presented `counselor_is_responsible_for` as an existing mechanism without saying it is draft SQL, without stating what it omits, and with a one-lock protocol (a `FOR SHARE` on the assignment row only).
(b) Revision 1 said student principals "see own rows". The RLS draft denies a student principal every row (fail-closed, student read scope undecided). Corrected in §8.6 and §17.
(c) Revision 1 did not state that the **only consumer found in the drafts read for this revision** (§25.1), `guard_plan_item_status_event`, evaluates the predicate with **no row lock** (§10.5, OBS-2). G-16 does not inherit that behavior.

### 8.1 Trust boundary

* Command functions take **no** actor, role or responsibility parameter. A catalog test fails if any parameter name matches `actor*`, `role*`, `responsible*`, `membership*`, `student_principal*`.
* Identity is read only from `current_principal_membership()` / `current_principal_student()`. They return NULL outside the establishing transaction, backend and session role; NULL reaches nothing (fail-closed). `authn_event_ref` is copied from the verified principal by the database.
* `establish_principal` verifies *at establishment time*, without any row lock, that the membership is active and holds the counselor role (or that the student is active). **G-16 never relies on that check for the write decision**; the decision is taken under locks (§8.3 step 6). A revocation that commits after establishment is therefore still caught.
* Production verification is **disabled** (PS-1..PS-4 open). EXECUTE on the command functions goes only to a dedicated NOLOGIN synthetic writer identity checked with the F-05 identity pattern (`current_user` must BE the role; no members; no login). The existing registry `plan_privileged_identities` admits only two purposes by CHECK, so G-16 needs its own registry (§21). **No production role is granted EXECUTE and no runtime write path is added.**

### 8.2 Exact predicates [PROPOSED composition of canonical rules; the X-05 conjunct is provisional]

Notation: `m` = counselor membership id, `s` = the student of the counter's routine. All reads below happen **after** the locks of §8.3 are held.

**P-RC(m, s) — responsible counselor (canonical; identical to `counselor_is_responsible_for(m, s)`).** All of:

1. `workspace_memberships.status = 'active'` for `m`;
2. a `membership_roles` row `(m, 'counselor')` exists;
3. a `counselor_assignments` row `ca` exists with `ca.counselor_membership_id = m`, `ca.state = 'active'`, `ca.accepted_at IS NOT NULL`, `ca.is_responsible = true`, whose `enrollment_id` references an `enrollments` row `e` with `e.student_id = s`.

No other role key, permission, branch or manager status contributes. This matches the counselor-scope draft, which denies managers until a permission vocabulary is approved.

**P-OWN(s) — student / enrollment / Workspace ownership.**

* (a) *Workspace:* the principal was verified for **this** database (the assertion's Workspace equals `workspace_profile.workspace_id`, enforced by `establish_principal`), and the student row `s` exists locally. [canonical]
* (b) *Transfer fence:* `assert_student_not_frozen(s)` passes, i.e. there is no `frozen` or `fenced` row in `student_transfer_freezes`. [canonical; enforced again by the write barrier trigger at insert]
* (c) *Provisional fail-closed fallback — **[OPEN: X-05]**:* `students.lifecycle_state = 'active'` **and** the enrollment `e` of P-RC(3) has `e.state = 'active'`.

(c) is stricter than the canonical read predicate. It applies to **writes only**; reads keep the WS-ISO-01 predicate. It is a fallback pending X-05, not an approved rule, and it removes no authority that A-04 grants (A-04 does not mention enrollment state).

**P-STU(s) — student actor.** `current_principal_student() = s` and P-OWN(a, b, c).

| Command | Counselor actor | Student actor |
|---|---|---|
| Append progress | P-RC(m, s) ∧ P-OWN(s) | P-STU(s) |
| Append correction | P-RC(m, s) ∧ P-OWN(s) | P-STU(s) ∧ original event authored by this student (**I-1**) |
| Create / revise / archive counter **[OPEN: U-10]** | P-RC(m, s) ∧ P-OWN(s) | denied |

### 8.3 Concurrency-safe authorization protocol [PROPOSED]

**Principle: lock, then evaluate.** Every row that can change the outcome of P-RC or P-OWN is locked first; the predicate is evaluated in a **later statement** (a fresh READ COMMITTED snapshot), so it reads exactly what the locks froze. The mode is `FOR SHARE`: `FOR KEY SHARE` does **not** conflict with a non-key `UPDATE` (status, state, `is_responsible`), so it would not stop a revoker, and `FOR UPDATE` would needlessly serialize every concurrent append by one counselor on the shared membership row.

Steps for a counselor actor, in this order and no other:

0. Require a verified principal (`current_principal_membership()` not NULL) and `transaction_isolation = 'read committed'`; otherwise refuse (§8.7).
1. Resolve `s` **without a lock** from the counter's routine. `routine_counters.student_id` and `daily_routines.student_id` are immutable (counter identity trigger; the write barrier's forward-only ownership rule), so this read cannot race.
2. **K1** — lock the `students` row `s` `FOR SHARE`.
3. **K2** — lock every `counselor_assignments` row with `counselor_membership_id = m` whose enrollment belongs to `s`, in ascending `assignment_id`, `FOR SHARE OF ca`. History rows are included; the set is small, and the two partial unique indexes bound the active ones.
4. **K3** — lock the `workspace_memberships` row `m` `FOR SHARE`.
5. **K4** — lock the `membership_roles` row `(m, 'counselor')` `FOR SHARE`. Zero rows means the role is absent: deny.
6. In a **new statement**, evaluate `counselor_is_responsible_for(m, s)` together with the P-OWN(c) reads. False ⇒ uniform not-found; nothing further is read or locked.

Student actor: steps 0, 1, 2, then evaluate P-STU(s).

From step 6 until commit the authority outcome is **frozen**: any transaction that tries to change `m`'s status or role, the assignment, or the student's lifecycle (archive, transfer freeze or fence) waits for this transaction.

### 8.4 How each authority-removing change serializes with an append

| Change that removes authority | Existing implementation (read-only analysis) | Row operation | Our conflicting lock |
|---|---|---|---|
| Membership suspended | `append_workspace_governance_event`, `membership_suspended` | `workspace_memberships … FOR UPDATE`; `UPDATE status`; `DELETE` every `membership_roles` and `membership_permissions` row of the member | K3, K4 |
| Membership terminated | same, `membership_ended` | same, plus `ended_at` | K3, K4 |
| Counselor role revoked | same, `role_revoked` (aggregate `membership_role` also takes the membership row `FOR UPDATE`) | `DELETE` the role row | K3, K4 |
| Assignment ended | **no single-assignment command was found in the drafts read (§25.1)**; `archive_student_enrollment` ends **all** active assignments of the enrollment | `UPDATE counselor_assignments SET state='ended'` | K2 (and K1, because archive locks the student first) |
| Responsibility changed or transferred | **no command was found in the drafts read (§25.1)**; the partial unique index forces demote-or-end before promote | `UPDATE … is_responsible / state` | K2 |
| Student archived | `archive_student_enrollment` | `FOR UPDATE OF e, s`; `UPDATE` enrollment, assignments, student | K1 |
| Transfer freeze / fence | `freeze_student_for_transfer` | `students … FOR UPDATE`, enrollment rows `FOR UPDATE` | K1 |
| Enrollment activated / archived / reactivated | activation, archive, reactivation | each takes the `students` row exclusively | K1 |

**Append-first** (our locks are acquired before the revoker's). The revoker blocks at its first conflicting lock until we commit or roll back. On commit the event is retained and attributed to an actor who held authority at this serialization point. On rollback there is no event and the revoker proceeds.

**Revoker-first.** If the revoker has committed, our locking reads return the latest committed row versions (an updated row is re-qualified, a deleted row is not returned), the predicate is false, and the command is denied with a uniform not-found. It writes **no event row, consumes no `event_seq`, and stores no idempotency key**. If the revoker holds uncommitted locks we wait; its commit means denial, its rollback means we proceed.

**Grants cannot cause a false allow.** A new assignment, a role grant or a reactivation is an insert. A concurrent insert that has not committed is invisible to us, so the command is denied, which is a valid serialization (before the grant).

### 8.5 Assigned-but-not-responsible counselors [APPROVED A-04, A-06]

Such a counselor satisfies `counselor_may_access_student` (so may **read**, under WS-ISO-01) but fails P-RC(3) because `is_responsible = false`. They **cannot** append progress events, **cannot** append corrections, and cannot create, revise or archive counters. The predicate for a correction is evaluated independently of who authored the original event, so a counselor who *was* responsible when they authored an event and was later demoted also cannot correct it (**I-1**).

### 8.6 Student actors and student read scope [fail-closed until WS-ISO-01 closes it]

* The RLS draft applies a restrictive principal fence to every student-scoped table. For an application role a row is visible only when the verified principal is a counselor for whom `counselor_may_access_student` holds; **a student principal reads no row** because what a student may read directly is undecided.
* G-16 therefore adds **no student SELECT policy** and decides nothing about student reads. The three G-16 tables inherit the catalog-driven fence automatically (they all carry `student_id`).
* A student **may append** (A-04) because the command is a reviewed definer function owned by a registered bypass role. Until WS-ISO-01 closes student read scope, a student principal receives from any command **only** `outcome` and the `event_id` of the event that command just created or replayed. No counter state, totals, other events or definitions are returned, and `GetCounterState` / `ListCounterEvents` / `ListRoutineCounters` return the uniform not-found to a student principal.
* **Consequence, not a decision:** a student can correct only an event whose `event_id` the client retained from the original response. Listing one's own events requires the student read scope to close first.

### 8.7 Preconditions the protocol depends on, and its limits

* **READ COMMITTED is required.** Each command refuses to run when `current_setting('transaction_isolation')` is not `read committed`. The "fresh snapshot after the lock" property is what makes step 6 sound.
* The locks bind ordinary writers. They do not bind a superuser or a table owner who disables triggers (SEC-08, unchanged); containing those identities is an operational control.
* Shared row locks are not fair: sustained overlapping shared lockers can delay an exclusive waiter such as a governance revoker. This is a liveness property, not a correctness one. Every G-16 command runs under a bounded `lock_timeout` so that a blocked command fails with a retryable error and leaves no row, sequence number or key. The value is a review parameter (**T-09**), not chosen here.
* Production principal verification does not exist (PS-1..PS-4). This protocol is only exercisable in the synthetic harness.

### 8.8 Error visibility

Object-level denial (the counter is not visible or the actor cannot reach it) returns the **same** result as a missing counter (uniform not-found, G-27). An actor who may read the counter but lacks write or correction authority receives `forbidden`. Raw constraint-violation text (PostgreSQL FK `DETAIL` echoes key values) is never returned (R-07).
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

1. Take the idempotency advisory lock (K0) — makes same-key requests deterministic.
2. Acquire K1–K4 and run the authority protocol (§8.3), then K5, K6 and K7(S) in the order of §10.2. A replay is re-authorized under these same locks.
3. Look up `(actor_kind, actor_ref, key)`.
4. Found + equal fingerprint → **replay**: return the original event (no new row) only if the actor still holds authority (§8.3 step 6). Found + different fingerprint → `idempotency_key_reuse` rejection.
5. Not found → validate, insert with `ON CONFLICT DO NOTHING`; if 0 rows inserted (lost a race on a different counter with the same key), re-read and apply step 4.

### 9.4 Replay authorization [OPEN: U-05, interpretation I-2]

Recommended: a replay requires the actor to **still** hold read authority on the counter; otherwise the answer is the uniform not-found. This avoids leaking event data to a revoked actor but is a reading of "returns the original outcome" that the PO should confirm. A replay after the counter was archived still returns the original event (it creates nothing).

---

## 10. Concurrency and transaction boundaries [APPROVED A-12, N-08; mechanism PROPOSED]

### 10.1 Isolation

`READ COMMITTED` with explicit row locks; each command refuses to run under any other level (§8.7). Each statement after a lock sees all committed data, so validation after lock acquisition is current. `SERIALIZABLE` was rejected: serialization failures would reject valid concurrent events unless a retry layer exists, which conflicts with **A-12** ("do not reject a valid second event merely because it is concurrent"). Waiting is permitted; rejecting is not.

### 10.2 Global lock-acquisition order [PROPOSED]

Every G-16 command acquires locks in ascending K-number and never requests a lower number than one it already holds. Rows within one table are locked in ascending primary-key order.

| Order | Lock | Mode | Taken by | Serializes against |
|---|---|---|---|---|
| **K0** | advisory xact lock on `hashtextextended('drc1:'‖actor_kind‖':'‖actor_ref‖':'‖key, 0)` | exclusive | event commands | same-key requests (a hash collision only adds waiting, never wrongly merges) |
| **K1** | `students` row `s` | `FOR SHARE` | every G-16 command | student archive, reactivation, transfer freeze/fence, and — through the anchor rule R-ORD-1 — enrollment lifecycle changes |
| **K2** | `counselor_assignments` rows of `(m, s)` | `FOR SHARE` | counselor-actor commands | assignment end, responsibility change |
| **K3** | `workspace_memberships` row `m` | `FOR SHARE` | counselor-actor commands | membership suspension, termination |
| **K4** | `membership_roles` row `(m,'counselor')` | `FOR SHARE` | counselor-actor commands | counselor role revocation |
| **K5** | `daily_routines` row | `FOR SHARE` | commands that create counters or events | routine deactivation **[OPEN: X-04]** |
| **K6** | `routine_counters` row | `FOR UPDATE` | every command on that counter; the (test-only) per-counter negative-policy projector | events, corrections, archive, revisions, policy changes — **per counter** |
| **K7** | `platform_reference_gate` | `FOR SHARE` (events, counter creation) / `FOR UPDATE` (global config and unit projector, test-only) | | global Platform reference changes |

Rules: a student-actor command skips K2–K4; counter creation has no K6 (no row yet) and instead inserts under K1–K5, K7; a per-counter policy projector takes K6 then K7 and never K1–K5; a global projector takes K7 only. The write barrier's `FOR SHARE` on the student row at insert re-enters K1, which the transaction already holds, so it waits for nothing.

Because every command on a counter takes the same exclusive K6, **both concurrent valid events are retained** (the second waits, then validates against the first's committed result) and **no increment or correction is lost**. Contention is bounded to one counter of one student.

### 10.3 Reconciliation with the existing protocols (read-only analysis of the drafts)

| Existing command | Observed lock sequence | Relation to K0–K7 |
|---|---|---|
| `freeze_student_for_transfer` | `students FOR UPDATE` → every enrollment row of the student `FOR UPDATE` → freeze row by token `FOR UPDATE` → inserts | holds K1 exclusively; never requests K2–K7 |
| write barrier trigger (every student-scoped table) | `students FOR SHARE` at each row write | is K1 |
| `archive_student_enrollment` | archive-log row by key → **one** statement `enrollments e JOIN students s … FOR UPDATE OF e, s` → entitlement row → capacity counter/events → `UPDATE` enrollment → `UPDATE counselor_assignments` (ends all active) → `UPDATE` student | holds K1 exclusively; reaches K2 rows only after K1 |
| `activate_student_enrollment` (wrapper, then inner) | `enrollments … FOR UPDATE` alone → log insert → `FOR UPDATE OF e, s` → wallet, capacity; reads assignments **without** a lock | holds K1 exclusively; never locks K2–K7 |
| `reactivate_student_enrollment` | `students FOR UPDATE` → log row → entitlement row → inserts enrollment and assignment → capacity | K1 first; inserts into K2's table after K1 |
| `append_workspace_governance_event` | advisory lock on `aggregate_type:aggregate_id` → `workspace_memberships … FOR UPDATE` → ledger insert → `UPDATE`/`DELETE` of membership, role and permission rows | holds K3/K4 exclusively; **never requests K1, K2 or K5–K7** |
| plan-item guards (`guard_plan_item`, `guard_plan_item_status_event`) | plan-version row `FOR SHARE` / `FOR NO KEY UPDATE`; authority predicate evaluated **with no lock** (OBS-2) | no overlap with K0–K7 |

**Why no wait-for cycle is introduced.** A deadlock needs a cycle of waits. A G-16 transaction `T` that holds `K0…Kj` waits only for `K(j+1)`. For `T` to be in a cycle, some other transaction `U` must hold `K(j+1)` while waiting for a resource `T` holds (`Ki`, `i ≤ j`).

* Governance holds K3/K4 but never waits for K1, K2 or anything else `T` holds: if governance holds K3 exclusively, `T` waits at K3 (holding only K0–K2 at most) and governance does not wait for K0–K2.
* Freeze, archive, activation and reactivation hold K1 exclusively and request only enrollment, entitlement, wallet and capacity rows; `T` requests none of those. If one of them holds K1, `T` waits at K1 holding nothing else.
* Archive and reactivation reach K2 rows only **after** K1, so no `U` holds K2 while waiting for K1 (obligation **R-ORD-1**).
* Other G-16 commands obey the same order by construction; the test-only projectors never request K1–K5.

Hence no cycle can include a G-16 transaction **provided obligations R-ORD-1..4 hold**.

### 10.4 Obligations on every other command that touches these rows

* **R-ORD-1.** Any command that changes `students.lifecycle_state`, `enrollments.state`, or `counselor_assignments.state / accepted_at / is_responsible` must take the `students` row `FOR UPDATE` **before** touching enrollment or assignment rows. Enrollment rows are deliberately **not** locked by G-16 (locking them would join the pre-existing student/enrollment ordering question, OBS-1); the `students` row is the anchor that serializes every enrollment lifecycle command that exists today. A new command that changes `enrollments.state` without locking the student breaks the guarantee for the P-OWN(c) read.
* **R-ORD-2.** A future "end assignment / change or transfer responsibility / accept assignment" command must take K1 first, then its assignment rows in primary-key order, update them in place, and demote or end before promoting (the partial unique index already forces this).
* **R-ORD-3.** No command may request **K1 or K2** while holding K3 or K4. A G-16 command acquires K5–K7 *after* K3/K4 by design (the order is simply ascending), so K5–K7 are not restricted for G-16; but a non-G-16 command that holds K3 or K4 (governance today) must not request K1, K2 or K5–K7, which is what keeps the cycle argument of §10.3 valid. Governance complies today.
* **R-ORD-4.** No command may request K1–K5 while holding K6 or K7.

A lock-annotation convention makes these checkable: every locking statement in a G-16 function carries a marker comment `-- LOCK Kn`, and a test asserts the markers are non-decreasing within each function body (DRC-LCK).

### 10.5 Observations about the existing drafts (reported, **not** changed, **not** measured)

* **OBS-1 — student/enrollment order is not uniform across existing commands.** The freeze takes the student row and then the enrollment rows. The activation wrapper takes an enrollment row first and then, in the inner function, the enrollment and student rows together. Archive locks enrollment and student in one `FOR UPDATE OF e, s` statement, whose acquisition order is plan-dependent. If those orders can interleave for the same student, PostgreSQL's deadlock detector aborts one transaction (SQLSTATE `40P01`); there is no silent corruption, but retry behavior is undefined. G-16 does not take enrollment locks and so does not join this ordering; it is reported to the Supervisor for reconciliation outside G-16.
* **OBS-2 — unlocked authority evaluation in existing consumers.** `guard_plan_item_status_event` evaluates `counselor_is_responsible_for` inside a `BEFORE INSERT` trigger with no lock on the assignment, membership or role rows. A suspension or revocation that commits after that read but before the writer commits is not observed. The archive, activation, reactivation and governance commands likewise read the actor's membership status without a lock. G-16 does not inherit this; the plan-item behavior is outside G-16 scope.
* **OBS-3 — no authority-lock precedent exists.** Revision 1's reference to the F-05 pattern covers *who may write*, not *race-free authority*; there is no existing protocol to reuse, which is why §8.3 defines one.

### 10.6 Transaction boundary

One database transaction per command: `establish_principal` → command → commit. A failure at any step rolls back the event, `event_seq` and the idempotency key atomically (**N-09**); no partial correction exists. The pure-rule functions (§11.4) are `IMMUTABLE`/`STABLE` and lock nothing.

### 10.7 Defense in depth: the command marker

Revision 1 proposed that the ledger's guard trigger re-take the counter lock so that a bypassing writer is still serialized. Revision 2 replaces that: a trigger that took K6 and then K1–K4 would invert the order of §10.2. Instead each command inserts a **transaction-scoped command marker row** (same technique as `student_write_barrier_bypass`: a `(txid, command)` row only the command's owner can write) **after** acquiring its locks, and the ledger and definition guard triggers refuse any insert that lacks the marker for the current transaction. A writer outside the command therefore cannot write at all, and no trigger ever takes a lock out of order. Archive-versus-insert, policy-change-versus-insert and configuration-change-versus-insert resolve deterministically in both orders, with commit and rollback variants (DRC-RACE, DRC-RAUTH).
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
* Projection tables are **not writable at all in production** (§12.6); in the synthetic harness invalid rows (non-positive window, threshold > window, `effective_from < projected_at`) are refused at insert, so an invalid configuration cannot exist.

### 11.6 Input form [OPEN: U-09]

Recommended: the API accepts `occurred_at` only as an **absolute instant** (RFC 3339 with explicit offset or `Z`, ≤ 6 fractional digits; more digits are rejected, not rounded). Wall-clock entry is converted by the client, which removes DST gap/overlap ambiguity from the server contract. Day boundaries are half-open `[00:00:00, next 00:00:00)` in the Workspace zone. Windows and thresholds are elapsed seconds, so 23- or 25-hour days do not change them.

---

## 12. Platform-controlled vocabulary and configuration [APPROVED A-02, A-03, N-02]

### 12.1 Unit identity

Immutable rows; a change of meaning is a **new** `unit_id`. Label/localization changes are separate append-only rows. Counters reference `unit_id`; the counter's `unit_id` is immutable (**N-02**). Recommended lifecycle `active → deprecated` only (**[OPEN: U-06]**).

### 12.2 No Workspace mutation path

A catalog audit asserts that no role other than the (test-only) projector identity has INSERT/UPDATE/DELETE/TRUNCATE on any `platform_*` projection, and that the runtime/worker/exporter/synthetic-writer have SELECT only. In a production bootstrap **no projector identity exists at all** (§12.6). A Workspace role cannot create a local unit, change a unit, or flip a negative policy (**A-03, A-10**).

### 12.3 Per-counter negative-value policy

See §13. The policy lives in a Platform projection, not on the counter row, so no Workspace-writable column can carry it.

### 12.4 Staleness and distribution [OPEN: X-03]

Projection rows carry `catalog_epoch`/`source_ref`/`projected_at`. Events record the config and policy version they were evaluated against. Maximum tolerated staleness is a Platform Security parameter not chosen here; with no verified channel, projections are empty and commands fail closed.

### 12.5 Governance workflow [OPEN: X-02]

Who may publish a unit, a configuration version, or a per-counter negative policy, with what approval and audit, is unresolved (PO §3, last bullet). The design requires only that every change is an append-only, attributable Platform record.

### 12.6 Projection writes are disabled until X-03 is approved and verified

The Platform projections (`platform_counter_units`, `platform_counter_unit_labels`, `platform_routine_config_versions`, `platform_counter_negative_policy_versions`) are **unusable for writes** in this design:

1. `platform_projection_config.mode` defaults to `'disabled'`. A guard trigger on every projection table refuses INSERT, UPDATE, DELETE and TRUNCATE for **every** role, including the table owner's functions, while the mode is `'disabled'`.
2. `'synthetic_test'` can be set only by a superuser test harness, and then only a NOLOGIN test-only projector identity (F-05 identity check) may write, and only rows whose `source_ref` matches `^synthetic-test-`. A `CHECK` on `source_ref` makes a non-test row **impossible to store** (the technique used for `principal_assertion_keys`), so the flag is not the only barrier.
3. A production bootstrap creates **no** projector role and grants **no** DML on any projection.
4. Enabling any non-synthetic distribution requires a **reviewed schema change** after the X-03 channel is approved and verified. It is not a configuration flip.
5. With empty projections every event command fails closed (`config_unavailable`, `unit_unavailable`).

This is a design statement only: no table, trigger, role or grant is created by this document.
---

## 13. Negative-value policy [APPROVED A-10, N-09]

| Aspect | Design |
|---|---|
| Default | Prohibited. No policy row ⇒ prohibited. |
| Enable | Only via a Platform policy version for that **counter**. |
| Evaluated on | The guard trigger, under the counter lock, using the policy version in force at `recorded_at`; the version id is stored on the event. |
| Scope of "negative" | **[OPEN: U-03]** recommended: the policy governs both the **sign of a progress delta** (positive-only when prohibited) and the **bucket total floor** (≥ 0 when prohibited). |
| Failure | Atomic: the whole command rolls back (no event, no `event_seq` consumed, no idempotency key stored). |
| Tightening while a bucket is already negative | **[OPEN: X-02]** recommended: forbid publishing a prohibiting policy while any bucket of that counter is negative, checked under K6, so "prohibited ⇒ no negative bucket" stays a universal invariant. |

---

## 14. Archive behavior [APPROVED A-11, N-10]

`ArchiveRoutineCounter` takes K1–K4 (authority, §8.3) and then K6 (§10.2), sets `lifecycle_state='archived'`, `archived_at`, `archived_by_*`. The guard trigger on the ledger reads the counter state under the same lock, so an in-flight event and an archive serialize in both orders (event first → committed and retained, archive waits; archive first → event refused). Archived counters, their versions, events and totals remain readable. No reactivation exists. Re-issuing archive on an archived counter is a no-op returning the existing state (natural idempotency; no key required). A replacement measurement uses a **new** counter with a new key (**U-10**).

---

## 15. Derived values [APPROVED A-08, N-07, N-15; caching OPEN: U-11]

* `routine_counter_bucket_totals_v`: `(counter_id, bucket_local_date, total = sum(delta), event_count, last_event_seq)`.
* `routine_counter_state_v`: totals joined with the target in force for that bucket date.
* Both views are created `WITH (security_invoker = true)` so row-level security applies to the **caller**, not the view owner (a default definer-style view would bypass RLS — R-15).
* The views expose raw values only. **No completion percentage, ratio, "target met" flag, mastery, risk or recommendation** exists anywhere (**N-15**); a catalog scan for such columns/functions is part of the regression suite.
* **Recommended v1: no stored aggregate.** Authoritative checks (floor, correction bound) read the ledger under K6. A transactionally maintained totals table is pre-designed as a rebuildable evolution (needs a verify/rebuild function and reconciliation tests) and requires no PO decision; any eventually consistent read exposed as authoritative does.

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

1. **New NOLOGIN owner roles** per Workspace (`…_counter_cmd_owner`, and a test-only `…_platform_projector`) following the F-05 identity pattern, with transitive-reach checks from every application role (F05-17..23 extension). The bootstrap must **register** them as reviewed NOLOGIN owners in `iso_rls_bypass_roles`; otherwise ISO-RLS-C3 fails by name, which is the intended fail-closed behavior. G-16 needs its own privileged-identity registry because `plan_privileged_identities.purpose` admits only two purposes by CHECK.
2. **Lock-only grants:** a command owner needs `UPDATE` to take `FOR UPDATE`/`FOR SHARE`; use column-level lock-only grants on a non-meaningful column (activation-owner precedent), plus guard triggers that refuse any real change. The owner needs lock grants on `students`, `counselor_assignments`, `workspace_memberships`, `membership_roles` and `daily_routines`; these are **lock-only** and add no write capability.
3. **RLS and student read scope (fail-closed).** The catalog-driven generator enables and forces RLS with the mandatory RESTRICTIVE principal fence on the three student-scoped tables automatically. Under that fence an application role reads a row only when the verified principal is a counselor for whom `counselor_may_access_student` holds; a student principal reads **nothing**. G-16 adds **no student SELECT policy** and does not decide what a student may read (**R-21**; WS-ISO-01 student read scope stays open). Reads therefore reach any actively assigned, accepted counselor; **writes** reach only the responsible counselor (§8.2). Unknown roles fail closed.
4. **Projection tables** carry no student data, are readable by application roles, and are **not writable by anyone in production** (§12.6).
5. **Transfer freeze:** all three student-scoped tables carry `student_id`, so the catalog-driven write barrier must pick them up; FRZ-01/01b must list them with no hole. Counter creation, revision and archive are also refused for a frozen student.
6. **Clock discipline:** no `now()`/`CURRENT_TIMESTAMP` in any new function or view (CLK-01 will fail by name otherwise).
7. **SECURITY DEFINER hygiene:** pinned `search_path = pg_catalog, pg_temp`, NOLOGIN non-superuser owner, EXECUTE revoked from PUBLIC (SEC-01..10).
8. **Retention:** register the three tables in `retention_entity_types` (uuid keys); legal holds apply; the disposition gate stays fail-closed (Q-020). Immutability and any future erasure obligation are in tension (R-14).
9. **Free text** (`late_reason`, `correction_reason`): bounded length (T-03), no plaintext contact data (reuse the OPS-17 payload pattern — evaluation recommended), never logged.
---

## 18. API command contracts (logical; transport-agnostic) [PROPOSED]

Decimals travel as **strings** (ASCII digits, optional single `.`; no exponent, sign only `-`, no Persian/Arabic-Indic digits — the UI converts). Timestamps are RFC 3339 with offset. Identity is never a field. Error codes are logical names; HTTP mapping is a later-phase (G-27) concern.

### 18.0 Responses to student principals (until WS-ISO-01 closes student read scope)

A student principal receives only `{ outcome, event_id }` from an append command, and the uniform not-found from every read in §18.4 (§8.6). Counselor principals receive the full event record for counters they may read.

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

`GetCounterState(counter_id, bucket_local_date?)`, `ListCounterEvents(counter_id, after_event_seq?, limit)` (ordered by `event_seq`, includes correction links), `ListRoutineCounters(routine_id)`. All through the security-invoker views/RLS; uniform not-found. For a **student principal** every read returns the uniform not-found until WS-ISO-01 closes student read scope (§8.6).

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
| R-04 | Archive/policy/config racing with insert; deadlock | single total lock order K0–K7 (§10.2); command marker instead of an out-of-order trigger lock (§10.7) | Supervisor to verify against existing commands (OBS-1) |
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
| R-21 | Student read scope not yet defined in WS-ISO-01 | fail-closed: student principals read nothing; no student policy added; student responses minimized (§8.6) | WS-ISO-01 closure |
| R-22 | Authority revoked between the check and the commit (H-01) | lock-then-evaluate under K1–K4 (§8.3); predicate re-evaluated after locks, never trusting establishment time | liveness only: bounded `lock_timeout` (T-09); READ COMMITTED required |
| R-23 | Existing consumers evaluate authority without locks (OBS-2) | G-16 does not inherit it | Supervisor — outside G-16 |
| R-24 | Possible student/enrollment lock-order inversion among existing commands (OBS-1) | G-16 takes no enrollment locks and obeys R-ORD-1..4 | Supervisor — outside G-16; not measured |

---

## 21. Required additive changes to existing objects — **NOT performed**

1. `daily_routines`: add `UNIQUE (routine_id, student_id)` (composite FK target). Existing rows unaffected.
2. New Workspace tables: `routine_counters`, `routine_counter_versions`, `routine_counter_events`, `platform_counter_units`, `platform_counter_unit_labels`, `platform_routine_config_versions`, `platform_counter_negative_policy_versions`, `workspace_timezone_versions`, `platform_reference_gate`.
3. New roles and grants per §17; no application EXECUTE or DML grant.
4. Extend: restrictive RLS fence, write barrier, TRUNCATE guards, retention registry, CLK-01 and SEC catalog scans (they are catalog-driven and will cover the new objects automatically — that is the point).
5. Decide the fate of `daily_routines.timezone_name` (X-04).
6. Update `UNRESOLVED_ITEM_REGISTER` / `unresolved_items.json` with U-xx / X-xx (Supervisor reconciliation; not done here).
7. G-26: a clean-install and upgrade migration fixture for all of the above (no migration chain exists yet).
8. A G-16 privileged-identity registry (the existing `plan_privileged_identities.purpose` CHECK admits only two purposes).
9. Registration of the new NOLOGIN owner roles in `iso_rls_bypass_roles` (ISO-RLS-C3 classification).
10. `drc_command_context` — the transaction-scoped command marker table of §10.7 (owner-only).
11. `platform_projection_config` and the projection write guards of §12.6.
12. Lock-only grants to the command owner on `students`, `counselor_assignments`, `workspace_memberships`, `membership_roles`, `daily_routines` (§17.2).
13. Alignment of the existing commands with R-ORD-1 and the student/enrollment ordering question (OBS-1) — a Supervisor decision about existing drafts, **not** performed or proposed as an edit here.

---

## 22. Dependencies and blockers

| Blocker | Effect on G-16 |
|---|---|
| PS-1..PS-8 (production verifier, keys, channel) | event commands runnable only in synthetic harness |
| WS-ISO-01 student read scope, background-job identity | student reads stay **fail-closed**; any worker use unresolved |
| X-05 enrollment-state narrowing of write authority | P-OWN(c) is a provisional fail-closed fallback (§8.2) |
| OBS-1 / R-ORD-1 alignment of existing commands | G-16 lock-order argument (§10.3) holds only if R-ORD-1..4 hold |
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
| A-04, A-05, N-03 | 8 | DRC-AUT, DRC-PRD, DRC-RAUTH |
| A-06, A-07, N-04, N-05 | 4.3, 5.3, 8.2–8.5 | DRC-COR, DRC-LED, DRC-SCH, DRC-PRD |
| A-08, N-07 | 7, 15 | DRC-LED, DRC-AGG |
| A-09, N-06 | 9 | DRC-IDM |
| A-10, N-09 | 13 | DRC-NEG |
| A-11, N-10 | 14 | DRC-ARC |
| A-12, N-08 | 10 | DRC-RACE, DRC-RAUTH, DRC-LCK |
| A-13, A-14, A-15, A-16, A-19, A-20, N-11, N-13, N-14 | 11 | DRC-TIM, DRC-CFG |
| A-17, A-18, N-12 | 11.2 | DRC-TZ |
| N-01 | 4.1, 4.3, 16 | DRC-SCH, DRC-ISO |
| N-15 | 15 | DRC-REG |

---

## 24. Document control

* This document does **not** assert that any schema, function, role, test or CI run exists for G-16.
* It does not decide any item in `G16_UNRESOLVED_DECISIONS.md`; recommendations are not decisions. Revision 2 adds one open item, **X-05**, and decides nothing.
* It does not modify `SUPERVISOR_REVIEW.md`, any SQL draft, `main`, PR #12 or PR #14, and it was not merged, rebased or force-pushed.
* Final status: **READY FOR ANOTHER INDEPENDENT SUPERVISOR REVIEW — NOT APPROVED.** Neither G-16 nor Phase 2 is approved.

---

## 25. Revision 2 — change summary (Supervisor finding H-01)

| # | Supervisor request | Where addressed | Result |
|---|---|---|---|
| 1 | Verify `counselor_is_responsible_for` exists; do not call it existing unless implemented | §8.0, §2.2 | **Exists** in `workspace_principal_assertion_draft.sql`, as draft SQL only; exact body and omissions stated; revision 1's wording corrected |
| 2 | Define the exact responsible-counselor predicate (membership, role, assignment, `is_responsible`, student/enrollment/Workspace ownership) | §8.2 | P-RC (canonical, three clauses), P-OWN (Workspace, transfer fence, provisional X-05 conjunct), P-STU |
| 3 | Concurrency-safe protocol vs assignment end / responsibility change / suspension / termination / role revocation | §8.3, §8.4 | lock-then-evaluate under K1–K4 `FOR SHARE`; both commit orders specified; grants cannot cause a false allow |
| 4 | Row locks, global acquisition order, reconciliation with freeze, governance, archive; no cycle | §10.2–§10.5 | order K0–K7; per-command reconciliation table; cycle argument with obligations R-ORD-1..4; pre-existing observations OBS-1..3 reported, not changed |
| 5 | Planned regression cases for membership suspension/revocation racing with append, both commit orders | `G16_ACCEPTANCE_TEST_PLAN.md` DRC-RAUTH, DRC-LCK | 14 + 6 new IDs |
| 6 | Assigned-but-not-responsible counselors cannot append progress or corrections | §8.5 | explicit; DRC-PRD-07, AUT-25, AUT-26 |
| 7 | Student read scope stays fail-closed until WS-ISO-01 closes it | §8.6, §17.3, §18.0 | student principals read nothing; no student policy; minimal responses; revision 1 error corrected |
| 8 | Platform projections unusable for writes until X-03 is approved and verified | §4.4, §12.6 | `disabled` by default, test-only synthetic rows, no production projector, reviewed schema change to enable |
| 9 | Preserve unresolved PO decisions | `G16_UNRESOLVED_DECISIONS.md` | U-03, U-04, U-07, U-08, U-09, U-10, X-01, X-02, X-04 untouched; X-05 added as **open** |
| 10 | Recommendations are not decisions | §0, §24 | unchanged |
| 11 | Do not change the meaning of approved rules | §0.1, §23 | A-xx / N-xx untouched; the X-05 conjunct is a labelled fallback that removes no approved authority |
| 12 | No SQL, migrations, runtime privileges, API/UI, production keys, real data, executable write paths | whole document | none added |
| 13 | Do not modify `SUPERVISOR_REVIEW.md`, `main`, PR #12, PR #14 | §24 | none modified |
| 14 | No merge, rebase or force-push | §24 | none performed |

### 25.1 What was read for revision 2, and what was not

**Read in full from `49c5b48…`:** `workspace_principal_assertion_draft.sql`, `workspace_counselor_scope_draft.sql`, `workspace_counselor_rls_draft.sql`, `workspace_schema_draft.sql`, `workspace_transfer_freeze.sql`, `workspace_archive_transactions.sql`, `workspace_activation_transactions.sql`, `workspace_governance_events_draft.sql`, `workspace_plan_items_draft.sql`.

**Not read:** `workspace_operations_draft.sql`, `workspace_roles_setup_draft.sql`, `workspace_inbox_projection.sql`, `workspace_assessment_exam_draft.sql`, the `*_CONTRACT.md` documents, and everything under `docs/phase2/workspace/tests/`. Statements such as "the only consumer found", "no command was found" and the per-command lock sequences in §10.3 are therefore **limited to the files above**. The operations draft is known to call `counselor_may_access_student` (its notification recipient rule), and the roles-setup draft fills `iso_principal_required_roles` and grants EXECUTE on the principal functions; neither was analysed for lock behavior. The Supervisor should treat §10.3 as complete only for the nine files listed.

Code search through the available GitHub connector returned no results and flagged itself incomplete, so no repository-wide search was relied on.
