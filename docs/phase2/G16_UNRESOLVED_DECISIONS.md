# G-16 — Unresolved Decisions: Options, Consequences, Recommendations

**Status:** DESIGN INPUT — recommendations are **not** decisions. READY FOR INDEPENDENT SUPERVISOR DESIGN REVIEW — **NOT APPROVED**
**Base:** `supervisor/phase2-final-reconciliation-2026-11-22` @ `64fc9b19d97dd460b9a10a7ef964c5568bc8a226`
**Companions:** `G16_TECHNICAL_DESIGN.md`, `G16_ACCEPTANCE_TEST_PLAN.md`
**Rule applied:** no numeric value, unit of measure, default, or product semantic is invented here. Where a safe fallback is needed it is the **strictest fail-closed behavior**, and it is labelled a fallback, not an approved default.

Tags: **[APPROVED]** = PO decision record `PO_DECISION_G16_DAILY_ROUTINE_COUNTERS_2026-11-23.md` (referenced as `A-xx` / `N-xx`). **[PROPOSED]** = this design. **[OPEN]** = unresolved.

---

## 1. Index

The eleven requested items are **U-01 … U-11**. While analysing them, four further gaps surfaced that the eleven cannot be answered without; they are **X-01 … X-04**. They are listed first where they gate other items.

| ID | Topic | PO approval needed? | Recommendation (short) | Blocks |
|---|---|---|---|---|
| **X-01** | Aggregation bucket: per local day vs cumulative; scope of target and floor | **Yes** | Per local day; cumulative as non-target reporting view | U-02, U-03, U-04, U-09 tests |
| U-01 | Numeric precision, scale, bounds | **Yes** (policy shape) | Per-unit scale decimal; scale 0 = integer; bounds per unit set by Platform | NUM tests, unit onboarding |
| U-02 | Target changes after events exist | **Yes** | Versioned, prospective only | versions table, AGG tests |
| U-03 | Event taxonomy, delta sign, meaning of "negative values" | **Yes** | `progress`/`correction`; sign rule driven by policy | NEG, COR tests |
| U-04 | Partial/multiple/over-correction, chain, age, bucket | **Yes** | Partial + multiple, opposite sign, cumulative bound, flat chain, no age limit | COR, RACE tests |
| U-05 | Idempotency scope, key format, retention, replay authorization | Clarification (I-2) | Per-actor scope, UUID key, permanent on ledger, replay re-authorizes | IDM tests |
| U-06 | Unit lifecycle, deprecation, retirement, localization | **Yes** (retirement, labels) | New id on any change; deprecate only; no retirement path | UNT tests |
| U-07 | Platform config versioning, effective time, missing/invalid/changed behavior | **Yes** | Version in force at `recorded_at`; never retroactive; refuse events when unconfigured | CFG, TIM tests |
| U-08 | Future timestamps, clock skew, precision | **Yes** (new parameter) | Skew is a Platform config field; reject future beyond it; reject excess precision | TIM tests |
| U-09 | Local midnight, DST, timezone-change edge | **Yes** (edge semantics) | Absolute-instant input; half-open days; tz at `recorded_at`; elapsed-second windows | TZ tests |
| U-10 | Counter creation/edit/archive authority, versioning, key uniqueness | **Yes** | Responsible counselor creates/edits/archives; keys never reused; append-only versions | AUT, ARC, SCH tests |
| U-11 | Aggregate caching and read consistency | No (unless eventual consistency is user-visible as authoritative) | No stored aggregate in v1; rebuildable totals table pre-designed | AGG tests |
| **X-02** | Platform governance workflow for units and per-counter negative policy | **Yes** | Maker-checker + signed projection; forbid prohibiting policy while a bucket is negative | PLT tests |
| **X-03** | Distribution of Platform reference data into Workspace databases | No (Platform Security / architecture); PO informed | Dedicated verified, versioned, one-way projection channel | everything (fail-closed until present) |
| **X-04** | Workspace timezone storage/authority; `daily_routines.timezone_name`; routine lifecycle vs counters | **Yes** (authority, default) | Append-only Workspace tz versions; leave routine column untouched; refuse events on inactive routine | TZ, AUT tests |

### 1.1 Recommended decision order

```text
X-01 ─▶ U-03 ─▶ U-04 ─▶ U-02 ─▶ U-01        (what the numbers mean)
          └────────────▶ X-02                 (who may enable negative values)
U-07 ─▶ U-08 ─▶ U-09 ─▶ X-04                  (time and configuration)
U-10 ─▶ U-06                                  (who defines counters; unit lifecycle)
U-05, U-11                                    (mechanism; can follow)
X-03                                          (parallel, Platform Security)
```

### 1.2 Per-item layout

Each item gives: **What is unresolved** · **Options** · **Consequences** · **Security / data-integrity implications** · **Recommendation** · **PO approval required** · **Fail-closed behavior until decided** · **Tests affected**.

---

## 2. Gating items

### X-01 — Aggregation bucket and the scope of "current value"

**What is unresolved.** PO §1 says the current value is derived by aggregating events and §2 N-12 requires local-date metadata, but the record never states *over which window* the aggregate is taken, nor what a target spans. Master §29 (`Math Tests: Target = 5, Completed = 4`) describes a **daily** routine.

**Options**
| | Description |
|---|---|
| A | **Per local-date bucket.** Value, target and non-negative floor apply to `(counter, bucket_local_date)`. |
| B | **Cumulative per counter.** One running total; target is cumulative. |
| C | **Per routine period** (week/month) — requires a period definition nobody has approved. |
| D | **Hybrid:** ledger identical; A for target/floor, B as a reporting-only sum. |

**Consequences.** A: daily semantics preserved, target is naturally per day, midnight/DST precision matters (U-09), corrections inherit the original's bucket, floor is per day. B: simple, but a "daily" routine loses its daily meaning and local-date metadata becomes audit-only. C: needs new product definition.

**Security / integrity.** The bucket must be server-derived and immutable (a client-supplied bucket would let an actor move an event between days). A correction must stay in the original's bucket or its bound check is meaningless.

**Recommendation.** **D** (A as the authoritative reading, B as a derived non-target view). The ledger is bucket-agnostic, so a PO choice of B or C changes read models and floor scope only — no ledger change.

**PO approval required: Yes** (business semantics).
**Fail-closed until decided:** ledger records `bucket_local_date`; no target comparison view is exposed.
**Tests affected:** AGG, NEG, COR, TZ (expectations are conditional on the chosen option).

---

### X-02 — Platform governance workflow for the unit catalog and per-counter negative policy

**What is unresolved.** PO §3 lists "Platform permission/RBAC and audit workflow for changing unit catalog and per-counter negative-value policy". A-03 and A-10 say *only Platform* may do this; they do not say how.

**Options**
| | Description |
|---|---|
| A | Single Platform Admin role may publish. |
| B | **Maker-checker:** two distinct Platform identities (propose, approve) for units and for any policy that *enables* negative values. |
| C | Reuse the governance proof-receipt boundary (signed, single-use, exact-scope claims) for the publish command. |
| D | B + C. |

**Consequences.** A is fastest and has a single point of misuse. B/D add friction for rare changes. C needs the receipt verifier (PS-1..PS-8 open).

**Security / integrity.** A unit's semantics underlie every historical counter; a negative-enable alters data meaning. These are high-impact, low-frequency changes — the right place for maker-checker. Every change must be append-only and attributable.

**Sub-question — tightening a policy while data is negative.** If Platform *prohibits* negatives for a counter that already has a negative bucket:
| | Behavior |
|---|---|
| T1 | Forbid publishing a prohibiting policy while any bucket of that counter is negative (checked under the counter lock). |
| T2 | Allow; existing negatives remain historical; new events must not worsen. |
| T3 | Allow; reject only events that would leave a bucket negative (blocks a repairing positive event). |

Recommendation **T1**: keeps "prohibited ⇒ no negative bucket" a universal invariant and avoids T3's trap (a positive repairing event rejected because the bucket is still negative).

**Recommendation.** **D** for approval/audit shape (Platform Security to define signing); **T1** for tightening.
**PO approval required: Yes** (who may change, whether maker-checker applies, tightening behavior).
**Fail-closed until decided:** projections writable only by the projector; no publish path exists in the Workspace API; no policy rows ⇒ prohibited.
**Tests affected:** PLT, NEG, RACE (policy vs insert).

---

### X-03 — Distribution of Platform reference data into Workspace databases

**What is unresolved.** A Workspace database cannot hold a foreign key to a Platform table (one database per Workspace, no cross-database grants). Units, configuration and negative policy therefore need a projection, and the channel is undefined.

**Options**
| | Description |
|---|---|
| A | One-way signed, versioned projection from Control Plane via a dedicated reference-data channel (outbox/inbox pattern, generation-fenced). |
| B | Reuse the ownership-transfer Saga channel. |
| C | Pull-on-demand with a local cache. |
| D | Seed once at provisioning and edit by hand. |
| E | Cross-database read. |

**Consequences / integrity.** E is prohibited (G-04). D guarantees drift and invites a Workspace-writable path (violates A-03). B couples unrelated lifecycles. C introduces unbounded staleness and a pull trust path. **A** keeps exactly one write path (the projector), supports versioned append-only rows, and lets each event record the epoch it used.

**Staleness.** A Platform revocation (e.g. deprecating a unit) reaches a Workspace after a delay. The tolerated maximum staleness is a Platform Security parameter **not chosen here**; the design records the version used on every event so any window of staleness is auditable.

**Recommendation.** **A.**
**PO approval required: No** (Platform Security + Supervisor architecture decision; PO informed).
**Fail-closed until decided:** projections stay empty ⇒ every event command is refused (`config_unavailable` / `unit_unavailable`).
**Tests affected:** PLT, CFG (all event tests need synthetic projection fixtures; the projector is a test-only identity).

---

### X-04 — Workspace timezone storage and authority; `daily_routines.timezone_name`; routine lifecycle

**What is unresolved.**
1. The current schema has **no Workspace timezone**; `workspace_profile` lacks one. `daily_routines.timezone_name NOT NULL` exists per routine, but the PO approved the **Workspace** timezone as the basis (A-17).
2. Who may set/change the Workspace timezone, and the initial value.
3. `daily_routines.active` exists; whether counters accept events while the routine is inactive is unspecified.

**Options**
| Sub | Option |
|---|---|
| tz store | A: new append-only `workspace_timezone_versions` · B: add a mutable column to `workspace_profile` (loses history, conflicts with A-18) |
| routine column | A: leave untouched, not used as a basis · B: deprecate/migrate away later · C: treat as a copy of the Workspace zone (drift risk) |
| authority | Workspace owner / Organization Manager (per the approved grantability matrix) · Platform |
| initial value | none until set (fail-closed) · master §52 default `Asia/Tehran` |
| inactive routine | refuse events · accept events |

**Security / integrity.** A mutable timezone column would let the basis of historical interpretation move, contradicting A-18. A per-routine zone allows two counters of one student to bucket the same instant on different dates. A stale routine-level zone silently disagreeing with the Workspace zone is a data-integrity hazard.

**Recommendation.** Append-only Workspace tz versions; leave the routine column untouched and unused for G-16 (record the conflict for later cleanup); authority per the approved role matrix (Organization Manager / Independent Counselor owner) — **PO to confirm**; no timezone ⇒ no events; refuse events on an inactive routine.
**PO approval required: Yes** (authority, whether `Asia/Tehran` is the initial value, inactive-routine behavior).
**Fail-closed until decided:** no timezone version ⇒ `timezone_unavailable`; inactive routine ⇒ `routine_inactive`.
**Tests affected:** TZ, AUT, TIM.

---

## 3. The eleven requested items

### U-01 — Numeric precision, scale and maximum bounds

**What is unresolved.** Integer vs decimal; precision/scale; maximum event delta, bucket value and target (PO §3).

**Options**
| | Description |
|---|---|
| A | Integer only (`bigint`) for all counters. |
| B | **Per-unit scale:** `numeric` storage; the unit declares `scale` (0 for counts) and `max_abs_event_delta`, `max_abs_bucket_value`; target obeys the same unit rules. |
| C | One global fixed `numeric(p,s)` for every counter. |
| D | Floating point. |

**Consequences.** A: exact and simple; cannot represent fractional quantities (they would have to be modelled as a smaller unit, e.g. minutes). B: expresses every unit; adds catalog fields, decimal canonicalization and a scale check. C: wastes precision for counts and constrains future units; one number serves nobody. **D is invalid**: float sums are non-associative, so a ledger could not reconcile with its aggregate (N-07).

**Security / integrity.** Reject — never round — a value with more digits than the unit's scale (silent rounding changes the recorded fact and breaks fingerprint equality). Bounds prevent overflow and storage abuse. PostgreSQL `numeric` accepts `NaN` and `Infinity`; both must be refused explicitly. Decimals cross the API as **strings** (JSON numbers are floats in most clients). Only ASCII digits are accepted; Persian/Arabic-Indic digits are converted by the client, otherwise two renderings of one value would fingerprint differently.

**Recommendation.** **B.** Option A is a strict subset of B (all units at scale 0), so choosing B costs nothing if the PO wants integers only for now. Bound *values* are supplied per unit by Platform at onboarding (governed by X-02); this design chooses none.
**PO approval required: Yes** for the policy shape (integer-only vs per-unit decimal; who owns bounds). No approval for individual bound values beyond the X-02 process.
**Fail-closed until decided:** unit rows without `scale` and both bounds are refused at projection insert.
**Tests affected:** NUM, UNT.

---

### U-02 — Target changes after progress events exist

**Options**
| | Description |
|---|---|
| A | Target immutable once any event exists; changing it means a new counter. |
| B | **Versioned, prospective:** a new version takes effect from a future local date. |
| C | Versioned, but may apply to the current or a past date. |
| D | Mutable in place. |

**Consequences.** A: perfectly stable history, but forces counter churn for ordinary target tuning. B: history of "what was the target on day d" stays reproducible. C: retroactively rewrites whether past days were "met" without touching events — a hidden history rewrite. D destroys history and is incompatible with the approved immutability spirit (A-08).

**Security / integrity.** A revision must serialize with events (target lookup is by bucket date; revision takes the counter lock). Revision carries `expected_version_no` so two counselors cannot silently overwrite each other. The target must satisfy the unit's bounds and, if negatives are prohibited, be ≥ 0.

**Recommendation.** **B**, with `effective_from_local_date` strictly after the current Workspace local date once the counter has any event; the first version may take effect on creation day. Optional vs mandatory target: recommend **mandatory** (matches master §29).
**PO approval required: Yes** (whether targets change; retroactivity; mandatory target).
**Fail-closed until decided:** a revision command is not exposed; version 1 only.
**Tests affected:** SCH, AGG, RACE (revision vs append).

---

### U-03 — Event taxonomy, delta sign and the meaning of "negative values"

**What is unresolved.** PO §3: "exact event taxonomy and delta sign/range semantics for increment vs correction". Also, **what "negative values" means** is not stated: the *counter's aggregate*, the *sign of an individual event*, or both.

**Taxonomy options**
| | Description |
|---|---|
| T-A | Two kinds: `progress`, `correction`. |
| T-B | Three kinds: `increment`, `decrement`, `correction`. |
| T-C | One kind with a signed delta and an optional correction link. |

**Sign options**
| | Description |
|---|---|
| S1 | `progress` delta is always > 0; the policy governs aggregates only. |
| S2 | `progress` delta must be > 0 when negatives are prohibited; any non-zero sign when enabled; the policy also governs the bucket floor. |
| S3 | `progress` signed everywhere; policy governs only the floor. |

**Consequences.** Under S1, together with correction bounds (U-04 option B), a bucket can **never** become negative — so a Platform "enable negatives" switch (an explicit PO decision, A-10) would be inert. S1 therefore sits badly with A-10. S3 lets a decrement masquerade as progress, duplicating the correction mechanism and weakening the audit meaning of "correction". **S2** gives A-10 real meaning and keeps decrements on prohibited counters possible *only* through attributed, reasoned corrections.

**Security / integrity.** Sign rules are evaluated by the guard trigger from the policy version in force, under the counter lock; the version id is stored on the event. A zero delta is always refused.

**Recommendation.** **T-A + S2.** Interpretation **I-4**: "negative values" = both event sign and bucket floor.
**PO approval required: Yes** (confirm reading of "negative values" and the taxonomy).
**Fail-closed until decided:** only positive progress deltas accepted; corrections follow U-04 fallback.
**Tests affected:** NEG, COR, NUM.

---

### U-04 — Partial correction, multiple corrections, over-correction, chain

**What is unresolved.** PO §3: whether a correction may partially compensate; whether multiple corrections may reference one original; how over-correction is prevented. Also unstated: correction-of-correction, a maximum correction age, and what `occurred_at`/bucket a correction carries.

**Options**
| | Description |
|---|---|
| C-A | One **full reversal** per original (`delta = −original`); no partial, no multiple. |
| C-B | **Partial and multiple** corrections, each of opposite sign, with cumulative `Σ|corrections| ≤ |original|`; reference a **progress** event only. |
| C-C | C-B plus corrections of corrections, with recomputed remaining capacity. |
| C-D | Replacement semantics: any signed delta, bounded only by the negative policy. |

**Consequences.** C-A is rigid: fixing 5 → 3 needs a reversal (−5) plus a new progress event (+3), and the replacement is attributed to whoever appends it. C-B models "I over-reported by 2" directly and bounds over-correction; an *under-report* is fixed by a new progress event. C-C is expressive but makes the effective value of an event a recursive computation, enlarging the surface for double-compensation races. C-D has no real over-correction guard.

**Security / integrity.**
* Over-correction and concurrent double-compensation are prevented by the exclusive per-counter lock plus the cumulative bound re-checked in the guard trigger.
* Correction references are structurally restricted: same counter, same bucket, original kind `progress` (declarative composite FK) — cross-counter and cross-tenant references cannot exist (N-05).
* A correction inherits the original's `bucket_local_date`; its `occurred_at` is system-asserted (`= recorded_at`) so a correction cannot be used to bypass the backdating window or to assert a past time.
* **Author clause** (A-06): the author must currently hold append authority (interpretation **I-1**).
* **Correction age:** a maximum age is *not approved*; adding one invents a rule. Recommended: none in v1 — authority, reason and full audit apply.

**Recommendation.** **C-B**, flat chain (**I-3**: "preserve the full correction chain" = every correction links to its original with a reason and nothing is overwritten; correction-of-correction not supported), no age limit.
**PO approval required: Yes** (partial/multiple, over-correction rule, chain reading, no age limit).
**Fail-closed until decided:** corrections refused (`correction_unavailable`) — an incorrect fallback would invent semantics.
**Tests affected:** COR, RACE, AUT, NEG.

---

### U-05 — Idempotency scope, key format, retention, replay authorization

**Scope options**
| | Scope |
|---|---|
| S-A | per counter |
| S-B | per actor `(actor_kind, actor_ref)` across all event commands |
| S-C | per `(actor, command_kind)` |
| S-D | Workspace-wide |

**Key format options.** (i) opaque bounded string; (ii) canonical lowercase UUID (client-generated v4/v7); (iii) ULID.

**Retention options.** R-A permanent, stored on the ledger row; R-B separate TTL table; R-C permanent for committed commands plus a short in-flight marker.

**Failed commands.** Store a receipt for rejections, or store nothing.

**Replay authorization.** Return the stored outcome unconditionally, or only if the actor still holds read authority.

**Consequences / integrity.**
* S-A allows one actor to reuse a key on two counters with different meanings. S-D lets any actor probe whether a key exists. **S-B** satisfies N-06 (no collision across actors, tenants, commands) with a single unique index; S-C permits the same key for a progress and a correction, which is a confusing reuse.
* R-B is unsafe: after expiry a retry creates a duplicate. A numeric retention would also be an invented value and overlaps Q-020. **R-A** makes the key lifetime equal the ledger lifetime.
* Storing rejection receipts adds a growth and PII surface; rejections are deterministic functions of state (and of configuration versions that may legitimately change), so they need no stored outcome.
* The fingerprint is computed by the database over a versioned canonical line; a caller-supplied hash would let a caller present matching hashes for different payloads.

**Recommendation.** **S-B**; **UUID**; **R-A**; no rejection receipts; database-computed fingerprint; replay **re-authorizes read authority** (uniform not-found otherwise). A replay after the counter was archived still returns the original event.
**PO approval required: Clarification only.** Recommendation depends on reading "retry returns the original outcome" as "for a currently authorized actor" (**I-2**). A TTL would be a new decision (and a Q-020 matter).
**Fail-closed until decided:** commands refuse a missing or malformed key.
**Tests affected:** IDM, RACE.

---

### U-06 — Unit vocabulary lifecycle, deprecation, localization

**Identity/versioning options**
| | Description |
|---|---|
| V-A | Immutable unit rows; **any change of meaning is a new `unit_id`**; labels versioned separately. |
| V-B | Stable `unit_key` with versioned definitions; counters pin a version. |
| V-C | Mutable in place. |

**Lifecycle options.** L-A deprecate only (new counters may not select; existing continue) · L-B deprecate and **retire** (retired ⇒ existing counters take no new events) · L-C add-only.

**Localization options.** Labels table keyed by locale with fallback; required locales to be decided (Persian is the product's primary language).

**Consequences / integrity.** V-C violates N-02 (historical counters silently repurposed). V-B works but forces every read to resolve a version. **V-A** is the simplest structure that satisfies N-02 by construction. L-B forces archive-like behavior on live counters when a unit is retired — a data-affecting action needing explicit approval. Labels must never carry meaning (a relabel must not change what a stored number denotes).

**Recommendation.** **V-A + L-A**; **no retirement path is designed**; labels in a separate append-only table, locales per PO.
**PO approval required: Yes** (whether a unit may ever be retired; required locales).
**Fail-closed until decided:** `status` accepts only `active` and `deprecated`.
**Tests affected:** UNT, PLT.

---

### U-07 — Platform configuration versioning, effective time, missing/invalid/changed behavior

**What is unresolved.** Numeric values and the unit of measure (not decided and not chosen here); effective-time semantics; behavior when configuration is missing, invalid or changed; audit detail.

**Which version applies to an event**
| | Rule |
|---|---|
| E-A | Version in force at the event's **`recorded_at`** (decision time). |
| E-B | Version in force at its **`occurred_at`**. |
| E-C | Always the latest version. |

**Missing/invalid configuration — fail-closed behavior**
| | Behavior |
|---|---|
| F-A | **Refuse all event commands** until a valid version exists (feature disabled). |
| F-B | Accept only entries within a strict tolerance — needs a tolerance value nobody approved. |
| F-C | Accept only entries whose `occurred_local_date` equals `recorded_local_date`; refuse earlier days. |

**Consequences.** E-A is evaluated at the moment the system decides, is deterministic under the lock, and each event stores the version id. E-B would let a later, looser window re-legitimize old entries and complicates audit. E-C erases history. For fail-closed: any literal "reject backdated entries" rule needs a definition of *not backdated*; an elapsed-time test with zero tolerance would reject nearly every entry (network latency makes `occurred_at < recorded_at`). F-B invents a number. F-C needs none but leaves the late-reason requirement undefined without a threshold. **F-A** is the only option that invents nothing.

**Config validation rules (technical):** positive window; `0 ≤ threshold ≤ window`; `effective_from ≥ projected_at` (never retroactive, so a publish cannot change the outcome of an event already decided); rows are append-only. Invalid rows cannot be inserted, hence "invalid configuration" cannot exist in the table.

**Changed configuration.** A new version affects only events recorded after it is effective; no recalculation of any past event. Racing a publish against an insert is made deterministic by the gate lock (L2).

**Operator-facing unit.** Seconds are a storage normalization only; the unit in which Platform *expresses* the window (hours, days) is a product/UI choice for the PO.

**Recommendation.** **E-A**, **F-A**, never-retroactive effective time. Interpretation **I-6**: the window and threshold are **elapsed time**, not calendar days.
**PO approval required: Yes** (F-A vs F-C operational behavior; elapsed-time vs calendar-day reading; operator unit).
**Fail-closed until decided:** F-A.
**Tests affected:** CFG, TIM, RACE.

---

### U-08 — Future timestamps, client clock skew, precision

**Options**
| | Rule |
|---|---|
| T-A | Strictly reject `occurred_at > recorded_at`. |
| T-B | Accept `occurred_at` up to a Platform-configured **maximum future skew** `ε`; reject beyond. |
| T-C | Allow future timestamps up to some horizon. |

**Precision options.** Reject more than 6 fractional digits (PostgreSQL microsecond precision) · truncate · round.

**Consequences.** T-A is strict but rejects legitimate entries from devices with fast clocks. T-C makes no sense for *progress that occurred*; it would let a future-dated entry fall into a bucket that has not begun. **T-B** keeps the strictness decision in Platform's hands. Truncating or rounding timestamps changes the asserted fact and the fingerprint; rejecting is explicit.

**Security / integrity.** `occurred_at` is user-asserted and therefore untrusted by nature; its bounds (future skew, backdating window) and the always-stored `recorded_at` are the controls. Server time is the only trusted clock; a per-counter `event_seq` provides ordering independent of any clock step. Optionally refuse an insert whose `recorded_at` would precede the previous event's (clock regression) — an Operations trade-off (it can halt writes during a clock step); recommended as a *refuse and alert*, not silent acceptance.

**Recommendation.** **T-B**: `max_future_skew_seconds` is a field of the configuration version (U-07); absent configuration ⇒ F-A anyway. Reject excess precision.
**PO approval required: Yes** (existence of a new Platform parameter; skew acceptance). Its *value* is a Platform parameter, not chosen here.
**Fail-closed until decided:** refused with the whole feature (F-A).
**Tests affected:** TIM, CFG.

---

### U-09 — Local midnight, DST boundary and timezone-change edge semantics

**Sub-issues and options**

| # | Question | Options | Recommendation |
|---|---|---|---|
| M1 | instant → local date | deterministic function of instant and zone rules (no choice) | use an explicit zone, never the session `TimeZone` |
| M2 | input form | **I-A** absolute instant only · I-B wall time + explicit offset · I-C wall time without offset | **I-A** |
| M3 | DST gap/overlap (only if wall time is accepted) | policy "earlier/later" | avoided by I-A |
| M4 | window measured in | elapsed seconds · calendar days | elapsed (I-6); 23/25-hour days then do not matter |
| M5 | zone for an event **recorded after** a tz change but **occurring before** it | **A:** zone at `recorded_at` · B: zone at `occurred_at` | **A** (matches "applies only to future events", A-18) |
| M6 | tzdata changes after the fact | recompute · **store resolved offsets and dates** | store (N-12) |
| M7 | exactly 00:00:00 local | belongs to the new day (half-open interval) | half-open `[00:00, next 00:00)` |

**Consequences / integrity.** I-A moves ambiguity to the client, which can resolve it with full knowledge of the user's intent. B for M5 gives historically faithful dates but requires zone-history lookup for backdated events and could contradict A-18's "future events only". Because the stored offset and dates are authoritative, a tzdata update (governments change rules) cannot rewrite history. A day that is 23 or 25 hours long is correct by construction (dates come from the zone rules; windows from elapsed seconds). Test fixtures need a zone that observes DST (Workspace zones other than Tehran are possible; verify against the tzdata shipped with the test PostgreSQL image, since rules for Iran changed in recent years).

**Recommendation.** As tabulated (I-A, elapsed windows, M5-A, stored offsets, half-open days).
**PO approval required: Yes** (M5, M4/I-6, and the absolute-instant input contract).
**Fail-closed until decided:** only absolute-instant input accepted.
**Tests affected:** TZ, TIM.

---

### U-10 — Counter creation/edit permissions and versioning

**What is unresolved.** Who creates, edits, orders and archives counters; stable key/name uniqueness; versioning when a routine changes.

**Authority options**
| | Description |
|---|---|
| P-A | **Responsible counselor only** creates, edits and archives; student appends. |
| P-B | Student may create counters for their own routine. |
| P-C | Platform-defined templates only (Phase 15). |
| P-D | Workspace manager role as well as the responsible counselor. |

**Versioning options.** V1: append-only version rows for name, order and target · V2: mutable name with an audit log.

**Key uniqueness options.** K1: unique per routine **across all states** (never reused) · K2: unique among non-archived only.

**Consequences / integrity.** P-A matches counselor-managed plans and keeps a student from weakening their own target. P-B lets a student create unbounded counters (growth, R-13). P-C is a future phase. K2 lets a new counter reuse an archived key, so reports could confuse two different measurements; **K1** keeps identity unambiguous and, since archive is irreversible, a "replacement" simply takes a new key. V1 satisfies the immutable-history spirit; V2 allows silent renaming. A routine change does not alter existing counters; adding a counter is a normal create.

**Recommendation.** **P-A**, **V1**, **K1**; bounded counters per routine (T-05 parameter). Definition commands use natural idempotency (create by key; revise with `expected_version_no`; archive state-idempotent), not event keys.
**PO approval required: Yes** (authority, key reuse, whether students may create).
**Fail-closed until decided:** definition commands are not exposed; fixtures create counters through the synthetic harness only.
**Tests affected:** AUT, SCH, ARC.

---

### U-11 — Aggregate caching and consistency

**Options**
| | Description |
|---|---|
| A | **No stored aggregate;** totals computed from the ledger. |
| B | Transactionally maintained totals table updated under the counter lock, with a verify/rebuild function. |
| C | Asynchronous projection / materialized view. |
| D | Application-level cache (e.g. Redis). |

**Consequences.** A: always correct and cheap to reason about; cost grows with events per bucket (indexed). B: O(1) reads, extra write, drift risk mitigated by a reconciliation test and rebuild function. C: eventually consistent — **violates N-07** if used for any authoritative decision. D: display-only; never for validation.

**Security / integrity.** Floor and correction checks must read the ledger (or B under the lock). Any non-A structure must be rebuildable and reconcilable (N-07); a drifted aggregate is a silent integrity failure. Views must be `security_invoker` so RLS holds.

**Recommendation.** **A** for v1; **B** pre-designed as the evolution; C and D only for explicitly non-authoritative displays.
**PO approval required: No** for A/B. **Yes** if any eventually consistent value is shown to users as authoritative.
**Fail-closed until decided:** A.
**Tests affected:** AGG.

---

## 4. Interpretation notes (readings of approved text — need PO confirmation)

These are not new decisions; they are places where the design had to read approved text. Each is flagged so it cannot be mistaken for something the PO said.

| ID | Approved text | Reading used | Why it matters |
|---|---|---|---|
| I-1 | A-06 "original event author or responsible counselor"; N-03 "live authority" | The author clause also requires the author to **currently** hold append authority | prevents a former counselor from editing a student's data |
| I-2 | A-09 "a retry returns the original outcome" | for an actor who still holds read authority | avoids leaking event data after revocation |
| I-3 | A-07 "preserve the full correction chain" | linked set under each original; correction-of-correction not supported | avoids recursive remaining-capacity logic |
| I-4 | A-10 "negative values" | both the sign of a progress delta and the bucket floor | gives the enable switch real meaning |
| I-5 | A-11 "archived counter accepts no new events" | also accepts no new versions/revisions | archive must freeze the definition |
| I-6 | A-14/A-15 "window", "delay" | elapsed time, not calendar days | DST-safe and numeric-unit neutral |
| I-7 | A-15/A-16 "reason only when threshold exceeded; no generic note" | `late_reason` supplied when not required is **rejected** | otherwise it becomes a de-facto note field |

---

## 5. Technical parameters intentionally left unset

Not product decisions, but values that need setting in implementation review. **None is chosen here.**

| ID | Parameter |
|---|---|
| T-01 | idempotency key regex and length |
| T-02 | `counter_key` charset and length |
| T-03 | maximum length of `late_reason` and `correction_reason` |
| T-04 | maximum unit `scale`; unit label length |
| T-05 | maximum counters per routine |
| T-06 | maximum events per command batch / per counter growth guard and command rate limits |
| T-07 | `display_name` length |
| T-08 | maximum tolerated staleness of Platform projections (Platform Security) |

---

## 6. Summary for the Product Owner

**Yes — decision requested (12):** X-01, U-01 (shape), U-02, U-03, U-04, U-06, U-07, U-08, U-09, U-10, X-02, X-04, plus confirmation of interpretation notes I-1 … I-7.
**Clarification only (1):** U-05 (I-2).
**No PO decision (2):** U-11 (unless eventual consistency becomes user-visible as authoritative), X-03 (Platform Security / architecture).

If the PO wants the smallest first slice, the minimum set that unblocks a coherent v1 is **X-01, U-03, U-04, U-07, U-08, U-09, X-04** (what a value is, how it is corrected, when an entry is valid); the rest can follow with the fallbacks above.

---

## 7. Document control

* No decision is made here; no numeric default, unit of measure or product semantic is invented.
* Where a fallback is stated, it is the strictest fail-closed behavior, not an approved default.
* No file other than the three G-16 design documents is produced; the unresolved-item register and `PHASE2_OPEN_DECISIONS.md` are **not** modified by this document.
* Final status: **READY FOR INDEPENDENT SUPERVISOR DESIGN REVIEW — NOT APPROVED.**
