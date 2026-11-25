# G-16 — DailyRoutine Counters: Acceptance and Regression Test Plan

**Status:** PLAN ONLY — no test is written, run or passing. READY FOR INDEPENDENT SUPERVISOR DESIGN REVIEW — **NOT APPROVED**
**Base:** `supervisor/phase2-final-reconciliation-2026-11-22` @ `64fc9b19d97dd460b9a10a7ef964c5568bc8a226`
**Companions:** `G16_TECHNICAL_DESIGN.md`, `G16_UNRESOLVED_DECISIONS.md`
**Constraint:** D-014 synthetic data only. No production key. No real student data.

Tags: **[APPROVED]** rule IDs `A-xx`/`N-xx` from the PO decision record. **[PROPOSED]** = derived from the proposed design. **[BLOCKED: id]** = expected value depends on an unresolved decision; the plan states the expectation per option and the test must not be written against a guessed option.

---

## 1. Evidence rules (project conventions applied)

1. A test is evidence only when it **fails against the unguarded code**. Every guard has a **measured negative control** (neutralize the guard, re-run, record the failing assertion). A control that still passes is invalid and must be redesigned (the Batch 4 `COALESCE` and Batch 1 barrier-race lessons).
2. Concurrency tests use **deterministic coordination**: the first session waits on an explicit go-signal that is sent only after the driver has *observed* the second session blocked in `pg_stat_activity`; the first is then told to commit or roll back. "The second session appeared blocked" is **never** the evidence — the outcome assertions are (Batch 3 trap).
3. **Each race runs in its own fresh database**, so one race's rolled-back state cannot be mistaken for a missing lock (Batch 7 trap).
4. Boundary equality is tested through the **pure rule functions** with explicit timestamps (no clock faking); command-level tests use generous margins and assert the command delegates to the pure functions (no second copy of the rule — CRD-38 pattern).
5. Repository checks (secret scan, register check) run **after `git add`**, on the tree that will be committed.
6. Evidence kinds are never merged: local run ≠ GitHub Actions ≠ design-only contract. CI evidence is tied to an **exact commit SHA**; documentation commits after that SHA are not covered.
7. Fixtures are synthetic and marked. No plaintext contact numbers, credentials or real names. The synthetic principal key is test-only and derived from a public string.
8. Absence of a run is not success. A planned ID with no executed assertion is **NOT RUN**, never "pass".

## 2. Environment

* Disposable PostgreSQL 16 cluster per run (cleared roles/databases; zero leftovers asserted); CI uses the `postgres:16` image and prints its exact version.
* Per-Workspace database with the existing role inventory; two Workspace databases for cross-Workspace tests (same counter ids in both).
* Synthetic principal assertions via the test-only HMAC mode; verification mode `disabled` for the fail-closed tests.
* Platform projection rows are inserted by a **test-only projector identity**; no production projector exists.
* Fixtures that must bypass guards (e.g. a prior event with a future `recorded_at`) use a superuser fixture session with `session_replication_role = replica`, documented as fixture-only.
* DST/timezone fixtures: at least one zone that observes DST and Asia/Tehran; verify against the tzdata shipped in the test image before fixing expected values (Iranian rules changed in recent years).

## 3. Catalog by group

Columns: **ID · Scenario · Expected · Source/Decision**. "Control" means a measured negative control is required.

### 3.1 DRC-SCH — schema and ownership (14)

| ID | Scenario | Expected | Source |
|---|---|---|---|
| SCH-01 | one routine owns ≥2 counters with distinct keys | both persist | A-01 |
| SCH-02 | duplicate `(routine_id, counter_key)` | rejected | A-01, U-10 |
| SCH-03 | counter whose `student_id` ≠ routine's student | rejected (composite FK) | N-01 |
| SCH-04 | `UPDATE daily_routines SET student_id` for a routine with counters | rejected (FK restrict) | N-01 |
| SCH-05 | event referencing counter with mismatched `routine_id`/`student_id` | rejected | N-01 |
| SCH-06 | correction referencing event of another counter | rejected declaratively, no trigger involved | N-05 |
| SCH-07 | correction referencing a **correction** event | rejected (target kind must be progress) | N-05, U-04 |
| SCH-08 | correction whose bucket ≠ original's bucket | rejected | N-05 |
| SCH-09 | `corrects_event_id = event_id` | rejected | N-05 |
| SCH-10 | progress with `corrects_event_id`/`correction_reason`; correction without either | rejected | A-07 |
| SCH-11 | actor columns: both set, none set, student actor ≠ `student_id` | rejected | A-05 |
| SCH-12 | catalog: no `ON DELETE`/`ON UPDATE` action on any new FK; every new table has a PK | pass | CUR-09/SEC pattern |
| SCH-13 | counter `counter_key`, `unit_id`, `routine_id`, `student_id` immutable | UPDATE rejected | N-02 |
| SCH-14 | `daily_routines` additive UNIQUE does not disturb existing rows | existing suite unchanged | regression |

### 3.2 DRC-UNT — unit vocabulary (8)

| ID | Scenario | Expected | Source |
|---|---|---|---|
| UNT-01 | counter with a `unit_id` absent from the projection | rejected (FK) | A-02 |
| UNT-02 | free-text unit column does not exist (catalog) | pass | A-02 |
| UNT-03 | counter creation with a `deprecated` unit | rejected | U-06 |
| UNT-04 | existing counter whose unit becomes `deprecated` still accepts events | accepted | U-06 |
| UNT-05 | unit meaning columns immutable; only `status` moves forward; no backward move | rejected | N-02 |
| UNT-06 | relabel (new label row) leaves stored values and fingerprints unchanged | unchanged | N-02 |
| UNT-07 | unit `status='retired'` insert | rejected unless U-06 approves | **[BLOCKED: U-06]** |
| UNT-08 | unit row lacking `scale` or bounds | rejected at projection insert | U-01 |

### 3.3 DRC-PLT — Platform-only mutation (8)

| ID | Scenario | Expected | Source |
|---|---|---|---|
| PLT-01 | runtime/worker/exporter/synthetic-writer INSERT/UPDATE/DELETE/TRUNCATE on each `platform_*` table | denied | A-03 |
| PLT-02 | catalog audit: only the projector identity holds DML on projections (table, column, PUBLIC, indirect membership) | pass | A-03 |
| PLT-03 | Workspace role flips a counter's negative policy | denied | A-10 |
| PLT-04 | Workspace role creates a local unit | denied | A-03 |
| PLT-05 | projection insert with `effective_from < projected_at` | rejected | U-07 |
| PLT-06 | config with threshold > window, non-positive window, negative skew | rejected | U-07 |
| PLT-07 | projection tables contain no student data (no `student_id` column) | pass | design §17 |
| PLT-08 | maker-checker on unit publish and negative-enable | enforced | **[BLOCKED: X-02]** |

### 3.4 DRC-AUT — actor authorization (24)

| ID | Scenario | Expected | Source |
|---|---|---|---|
| AUT-01 | student appends to own counter | accepted, actor = student | A-04 |
| AUT-02 | student appends to another student's counter | uniform not-found | A-04 |
| AUT-03 | responsible counselor appends for assigned student | accepted, actor = counselor | A-04 |
| AUT-04 | assigned but **non-responsible** counselor | denied | A-04, N-03 |
| AUT-05 | counselor of another student / another counselor's student | uniform not-found | WS-ISO-01 |
| AUT-06 | assignment ended or not accepted | denied | N-03 |
| AUT-07 | membership suspended or ended | denied | N-03 |
| AUT-08 | student `archived` | principal not establishable; denied | N-03 |
| AUT-09 | parent/guardian, teacher, Platform Admin principals | denied | A-04 |
| AUT-10 | catalog: no command parameter named `actor*`, `role*`, `responsible*`, `membership*` | pass | N-03 |
| AUT-11 | forged GUC/claim attempting to set actor | ignored/denied | N-03 |
| AUT-12 | no established principal in the transaction | denied | A-05 |
| AUT-13 | principal established in a previous transaction | denied | A-05 |
| AUT-14 | replayed assertion nonce; expired; wrong Workspace; bad signature | denied | WS-ISO-01 |
| AUT-15 | verification mode `disabled` | every command refused (fail-closed) | PS-1..PS-4 |
| AUT-16 | event row's `authn_event_ref` equals the verified principal's, never caller text | pass | A-05 |
| AUT-17 | correction by the original author student | accepted | A-06 |
| AUT-18 | correction by the responsible counselor of a student's event | accepted | A-06 |
| AUT-19 | correction by a different student / non-responsible counselor | `forbidden` | A-06 |
| AUT-20 | student corrects a counselor-authored event | `forbidden` | A-06, I-1 |
| AUT-21 | former author counselor (no longer responsible) corrects own old event | denied (live authority) | I-1 |
| AUT-22 | direct INSERT on the ledger by runtime/worker/exporter | denied | N-03 |
| AUT-23 | EXECUTE on command functions held only by the synthetic writer identity; none by PUBLIC or runtime | pass | design §8 |
| AUT-24 | counter creation/revision/archive by student | denied | **[BLOCKED: U-10]** (expected per P-A) |

### 3.5 DRC-LED — immutable ledger (12)

| ID | Scenario | Expected | Source |
|---|---|---|---|
| LED-01 | UPDATE on an event, any column, any application role | rejected | A-08 |
| LED-02 | DELETE on an event | rejected | A-08 |
| LED-03 | TRUNCATE (plain and CASCADE) on ledger, versions | rejected; only owner holds the privilege | N-04 |
| LED-04 | privileged INSERT supplying `recorded_at`, `event_seq`, derived dates, fingerprint | values overwritten/verified | N-11 |
| LED-05 | `event_seq` per counter gapless and unique | pass | N-08 |
| LED-06 | failed command leaves no row and no `event_seq` gap | pass | N-09 |
| LED-07 | owner can disable triggers — documented residual asserted | pass (limitation recorded) | SEC-08 |
| LED-08 | versions table: UPDATE/DELETE/TRUNCATE rejected | rejected | design §4.2 |
| LED-09 | correction does not modify its original | original row byte-identical | N-04 |
| LED-10 | no generic note column exists on the ledger | catalog pass | A-16 |
| LED-11 | catalog: every new immutable table has a statement-level TRUNCATE guard | pass, zero holes | OPS-60 pattern |
| LED-12 | row-lock (`FOR UPDATE`) on a ledger row does not alter data or system columns observed by the app | no change | design §7 |

### 3.6 DRC-IDM — idempotency (14)

| ID | Scenario | Expected | Source |
|---|---|---|---|
| IDM-01 | same key + same payload twice | one row; second returns `replayed` with the original event | A-09 |
| IDM-02 | same key + different `delta` | `idempotency_key_reuse` | N-06 |
| IDM-03 | same key + different `occurred_at` / `late_reason` / counter | rejected | N-06 |
| IDM-04 | same key by a different actor | independent (two events) | N-06 |
| IDM-05 | same key reused across progress and correction | rejected | N-06 |
| IDM-06 | `5` vs `5.0` at scale 0 | same fingerprint if scale permits, otherwise scale error | design §9.2 |
| IDM-07 | no function accepts a caller-supplied fingerprint (catalog) | pass | design §9.2 |
| IDM-08 | rejected command stores nothing; retry with same key after the cause is fixed | accepted | design §9.1 |
| IDM-09 | key format validation (UUID form), empty, oversized | rejected | **[BLOCKED: U-05, T-01]** |
| IDM-10 | replay after the counter is archived | original event returned | design §9.4 |
| IDM-11 | replay after the actor lost read authority | uniform not-found | **[BLOCKED: U-05/I-2]** |
| IDM-12 | no deletion path for keys; no TTL job | catalog pass | U-05 |
| IDM-13 | fingerprint version stored; a different version never equals | pass | design §9.2 |
| IDM-14 | 2 concurrent same-key same-payload requests | exactly one event (see RACE-08) | N-06, N-08 |

### 3.7 DRC-NUM — numeric rules (12)

| ID | Scenario | Expected | Source |
|---|---|---|---|
| NUM-01 | `delta = 0` | rejected | design §4.3 |
| NUM-02 | `NaN`, `Infinity`, `-Infinity` | rejected | R-11 |
| NUM-03 | more fractional digits than unit scale | rejected, not rounded | U-01 |
| NUM-04 | `|delta|` equal to / above `max_abs_event_delta` | accepted / rejected | **[BLOCKED: U-01]** |
| NUM-05 | bucket total would exceed `max_abs_bucket_value` | rejected atomically | **[BLOCKED: U-01]** |
| NUM-06 | text forms `1e3`, `+5`, ` 5`, `5.`, `.5`, `0x10` | rejected | design §18 |
| NUM-07 | Persian/Arabic-Indic digits in input | rejected (client converts) | design §18 |
| NUM-08 | JSON-number (float) transport form | rejected at the contract boundary | API phase |
| NUM-09 | scale-0 unit: integer-only behavior identical to option A | pass | U-01 |
| NUM-10 | target outside unit bounds / negative with negatives prohibited | rejected | U-02 |
| NUM-11 | no floating-point type used (catalog: no `float4/float8/real/double`) | pass | U-01 |
| NUM-12 | sum of many deltas equals exact decimal sum | exact | N-07 |

### 3.8 DRC-TIM — time (14)

| ID | Scenario | Expected | Source |
|---|---|---|---|
| TIM-01 | both timestamps stored | pass | A-13 |
| TIM-02 | client cannot set `recorded_at` | ignored | N-11 |
| TIM-03 | `drc_classify_delay` just inside the window | accepted | A-14 |
| TIM-04 | exactly equal to the window | accepted | A-14 (boundary defined §11.3) |
| TIM-05 | one microsecond beyond the window | rejected | A-14 |
| TIM-06 | delay exactly equal to threshold | no reason required | A-15 |
| TIM-07 | one microsecond beyond threshold, no reason | `late_reason_required` | A-15 |
| TIM-08 | one microsecond beyond threshold, with reason | accepted, reason stored | A-15 |
| TIM-09 | reason supplied when not required | rejected | A-16, I-7 |
| TIM-10 | blank/whitespace-only reason when required | rejected | A-15 |
| TIM-11 | `occurred_at` in the future within / beyond skew | accepted / rejected | **[BLOCKED: U-08]** |
| TIM-12 | timestamp with > 6 fractional digits | rejected | **[BLOCKED: U-08]** |
| TIM-13 | prior event with future `recorded_at` (clock-regression fixture) | refused and alerted | **[BLOCKED: U-08, Ops]** |
| TIM-14 | window/threshold use elapsed seconds across a DST change | identical | I-6 |

### 3.9 DRC-CFG — Platform configuration (8)

| ID | Scenario | Expected | Source |
|---|---|---|---|
| CFG-01 | no configuration version | event commands refused (fail-closed) | N-13 |
| CFG-02 | no seeded numeric default exists (catalog + data) | pass | N-13 |
| CFG-03 | version published; events before its `effective_from` use the previous one | pass | U-07 |
| CFG-04 | event exactly at `effective_from` | uses the new version | U-07 |
| CFG-05 | event stores `backdating_config_version_id` | pass | N-12 |
| CFG-06 | new version does not alter any stored event | rows unchanged | N-12 |
| CFG-07 | configuration missing for one Workspace only | only that Workspace fails closed | X-03 |
| CFG-08 | alternative missing-config behavior (same-day entries allowed) | **[BLOCKED: U-07 F-C]** | U-07 |

### 3.10 DRC-TZ — timezone (12)

| ID | Scenario | Expected | Source |
|---|---|---|---|
| TZ-01 | event stores tz name, version, offsets, local dates | pass | N-12 |
| TZ-02 | tz change: later events use the new zone | pass | A-18 |
| TZ-03 | tz change: all earlier rows byte-identical | pass | A-18 |
| TZ-04 | bucket totals of earlier events unchanged after a tz change | pass | A-18 |
| TZ-05 | no timezone version | `timezone_unavailable` | design §11.5 |
| TZ-06 | invalid zone name | rejected | design §4.4 |
| TZ-07 | session `TimeZone` set to varied values | stored dates identical | R-10 |
| TZ-08 | `23:59:59.999999` vs `00:00:00` local | previous day / new day | **[BLOCKED: U-09 M7]** |
| TZ-09 | DST spring-forward and fall-back days: local dates, 23/25-hour days | correct | **[BLOCKED: U-09]** |
| TZ-10 | event recorded after a tz change but occurring before it | zone at `recorded_at` | **[BLOCKED: U-09 M5]** |
| TZ-11 | tzdata change after the fact: stored offsets/dates unchanged | pass | U-09 M6 |
| TZ-12 | `daily_routines.timezone_name` is not consulted | changing it alters nothing | **[BLOCKED: X-04]** |

### 3.11 DRC-NEG — negative-value policy (10)

| ID | Scenario | Expected | Source |
|---|---|---|---|
| NEG-01 | no policy row | negatives prohibited | A-10 |
| NEG-02 | negative progress delta on a default counter | rejected | **[BLOCKED: U-03 S2]** |
| NEG-03 | correction pushing bucket below zero on a default counter | rejected atomically (no row, no seq, no key) | N-09 |
| NEG-04 | policy version enabling negatives for counter A | A accepts, counter B still refuses | A-10 |
| NEG-05 | negative bucket allowed on enabled counter | accepted | A-10 |
| NEG-06 | event records `negative_policy_version_id` used | pass | design §13 |
| NEG-07 | policy change not retroactive; earlier events unchanged | pass | N-12 |
| NEG-08 | prohibiting policy while a bucket is negative | refused (T1) | **[BLOCKED: X-02]** |
| NEG-09 | positive repairing event on a negative bucket under an enabled policy | accepted | A-10 |
| NEG-10 | Workspace role cannot change policy (see PLT-03) | denied | A-10 |

### 3.12 DRC-COR — correction rules (14)

| ID | Scenario | Expected | Source |
|---|---|---|---|
| COR-01 | correction without reason | rejected | A-07 |
| COR-02 | correction without original reference | rejected | A-07 |
| COR-03 | reason of whitespace only | rejected | A-07 |
| COR-04 | correction references an unknown id | uniform error, no key echo | R-07 |
| COR-05 | partial correction within bound | accepted | **[BLOCKED: U-04]** |
| COR-06 | multiple corrections, cumulative within bound | accepted | **[BLOCKED: U-04]** |
| COR-07 | cumulative corrections exceed original | `correction_bound_exceeded` | **[BLOCKED: U-04]** |
| COR-08 | correction with the same sign as original | rejected | **[BLOCKED: U-04]** |
| COR-09 | correction inherits original's bucket; `occurred_at = recorded_at` | pass | **[BLOCKED: U-04, X-01]** |
| COR-10 | correction after the original's backdating window has passed | accepted; no age limit | **[BLOCKED: U-04]** |
| COR-11 | correction of an event on an archived counter | rejected | N-10 |
| COR-12 | correction chain readable in `event_seq` order; every link intact | pass | A-07 |
| COR-13 | correction idempotency (same key / different payload) | per IDM | A-09 |
| COR-14 | correction-of-correction | rejected (flat chain) | **[BLOCKED: U-04/I-3]** |

### 3.13 DRC-ARC — archive (10)

| ID | Scenario | Expected | Source |
|---|---|---|---|
| ARC-01 | archive preserves all events and versions | row counts and checksums equal | A-11 |
| ARC-02 | progress and correction on archived counter | rejected | A-11 |
| ARC-03 | reads and totals still work after archive | pass | N-10 |
| ARC-04 | `archived → active` by any application role, owner functions | impossible | A-11 |
| ARC-05 | catalog: no function body/route sets `lifecycle_state='active'` | pass | A-11 |
| ARC-06 | archive by an unauthorized actor | denied | **[BLOCKED: U-10]** |
| ARC-07 | archive twice | state-idempotent, no new row | design §14 |
| ARC-08 | revision of an archived counter | rejected | I-5 |
| ARC-09 | archived key cannot be reused for a new counter | rejected | **[BLOCKED: U-10 K1]** |
| ARC-10 | counter deletion path | does not exist | A-11 |

### 3.14 DRC-AGG — derived values (10)

| ID | Scenario | Expected | Source |
|---|---|---|---|
| AGG-01 | bucket total equals sum of ledger deltas | pass | N-07 |
| AGG-02 | totals per bucket are independent | pass | **[BLOCKED: X-01]** |
| AGG-03 | correction changes only the original's bucket | pass | **[BLOCKED: X-01, U-04]** |
| AGG-04 | views are `security_invoker`; another student's totals invisible through the view | pass | R-15 |
| AGG-05 | no percentage/ratio/"met"/mastery/risk columns or functions (catalog scan) | pass | N-15 |
| AGG-06 | target for a bucket date resolved by version rule | pass | **[BLOCKED: U-02]** |
| AGG-07 | rebuilding totals from the ledger reproduces the view | pass | N-07 |
| AGG-08 | reader sees whole events only, never partial | pass | N-08 |
| AGG-09 | stored totals table (if adopted) reconciles under random workloads | pass | **[BLOCKED: U-11 B]** |
| AGG-10 | query shape uses the intended indexes (plan shape, not timing) | pass | design §16 |

### 3.15 DRC-RACE — concurrency (14) — each in a fresh database, both lock orders, commit and rollback where relevant

| ID | Scenario | Expected | Control |
|---|---|---|---|
| RACE-01 | two distinct valid progress events on one counter | both retained; gapless seq; correct total | remove counter lock → fails |
| RACE-02 | archive vs append, both orders, commit and rollback variants (4 cases) | append-first: retained, archive waits; archive-first: append refused | remove lock → fails |
| RACE-03 | negative-policy publish vs append | deterministic; event records the policy version it saw | remove lock → fails |
| RACE-04 | config publish vs append (gate) | deterministic outcome by commit order | remove gate → fails |
| RACE-05 | two concurrent corrections of one original | total bounded; second sees first | remove bound re-check → fails |
| RACE-06 | corrections of different originals | both succeed | — |
| RACE-07 | correction vs progress on the same counter | both retained | — |
| RACE-08 | same key, same payload, two sessions | exactly one event | remove advisory lock → duplicate/error observed |
| RACE-09 | same key, different payload / counter, two sessions | one wins, other rejected, deterministic | — |
| RACE-10 | revision (target) vs append | serialized | remove lock → fails |
| RACE-11 | assignment end vs append | event valid iff it serialized first | remove `FOR SHARE` → fails |
| RACE-12 | transfer freeze vs append, **both** FK and non-FK-path modes | no event after the barrier watermark | remove barrier lock → `nofk` mode fails |
| RACE-13 | two sessions racing one principal nonce | one succeeds | existing |
| RACE-14 | randomized interleavings of RACE-01..11 pairs | no `deadlock_detected`; lock order holds | lock-order inversion fixture → deadlock observed |

### 3.16 DRC-ISO — tenant and counselor isolation (12)

| ID | Scenario | Expected | Source |
|---|---|---|---|
| ISO-01 | Workspace A role/credential connecting to Workspace B database | denied | G-04 |
| ISO-02 | identical counter ids in two Workspaces never cross | pass | N-01 |
| ISO-03 | student A reads B's counters/events/versions (direct, via view, via correction link) | none | WS-ISO-01 |
| ISO-04 | counselor A reads counselor B's student's counters | none | WS-ISO-01 |
| ISO-05 | catalog: RLS ENABLE+FORCE and restrictive principal fence on all three tables | pass | ISO-RLS pattern |
| ISO-06 | unknown/unclassified role | fails closed | H-01 |
| ISO-07 | no PUBLIC table or column privilege | pass | ISO-RLS-C16 |
| ISO-08 | `pg_read_all_data`/`pg_write_all_data` remain RLS-bound | pass | H-01 |
| ISO-09 | command error text never contains key values (FK `DETAIL`) | pass | R-07 |
| ISO-10 | notification/report/background-job paths for counters | none exist (asserted) | G-19, G-28 |
| ISO-11 | student read scope for counters | pass | **[BLOCKED: WS-ISO-01 student read scope]** |
| ISO-12 | existing ISO suites unchanged | pass | regression |

### 3.17 DRC-FRZ — transfer fence (6)

| ID | Scenario | Expected | Source |
|---|---|---|---|
| FRZ-G16-01 | FRZ-01/01b catalog audit lists all three tables with a barrier, no hole | pass | R-17 |
| FRZ-G16-02 | frozen student: append, correction refused | refused | FRZ |
| FRZ-G16-03 | frozen student: counter create/revise/archive refused | refused | FRZ |
| FRZ-G16-04 | after ownership switch observed: permanent fence | refused | FRZ |
| FRZ-G16-05 | unfreeze before switch restores writes | accepted | FRZ |
| FRZ-G16-06 | existing FRZ suite counts unchanged except the new tables | pass | regression |

### 3.18 DRC-PRV — privilege, clock and function hygiene (10)

| ID | Scenario | Expected | Source |
|---|---|---|---|
| PRV-01 | CLK-01 catalog scan: no `now()`/`CURRENT_TIMESTAMP`/`transaction_timestamp()` in new functions or views | pass | CLK |
| PRV-02 | clock read once after locks; stored timestamps equal decision time | pass | CLK-02 |
| PRV-03 | every definer function: owner NOLOGIN non-superuser; pinned `search_path` | pass | SEC-01..03 |
| PRV-04 | no PUBLIC EXECUTE except the documented allowlist | pass | SEC-07 |
| PRV-05 | no table owned by an application role | pass | SEC |
| PRV-06 | owner roles have no transitive reach from any application role | pass | F05-17..23 |
| PRV-07 | no application role holds INSERT/UPDATE/DELETE on any new table | pass | design §17 |
| PRV-08 | lock-only grants are column-level and the guard triggers still refuse real change | pass | design §17 |
| PRV-09 | `search_path` shadowing attempt against command functions | no effect | SEC-02 |
| PRV-10 | no `public` CREATE for PUBLIC/application roles | pass | SEC-02b |

### 3.19 DRC-RET — retention (4)

| ID | Scenario | Expected | Source |
|---|---|---|---|
| RET-01 | new tables registered in `retention_entity_types` with uuid keys | pass | OPS |
| RET-02 | legal hold can be placed on an event / counter | pass | OPS |
| RET-03 | destructive disposition gate refuses (no approved policy) | refused | Q-020 |
| RET-04 | no code path deletes or rewrites ledger rows | pass | R-14 |

### 3.20 DRC-REG — regression and gates (10)

| ID | Scenario | Expected | Source |
|---|---|---|---|
| REG-01 | all existing suites (ISO, FRZ, CLK, SEC, OPS, CRD, PLN, GOV, RC) pass unchanged; counts change only by the new objects | pass | regression |
| REG-02 | no completion %, mastery, risk, recommendation anywhere in G-16 objects | pass | N-15 |
| REG-03 | repository secret/key scan after `git add`, incl. history | pass | G-29 |
| REG-04 | register consistency check with the new U-xx/X-xx items | pass | G-30 |
| REG-05 | clean-install migration chain for all new objects | succeeds | G-26 |
| REG-06 | upgrade migration from the current draft schema (additive UNIQUE on `daily_routines`) | succeeds, data intact | G-26 |
| REG-07 | interruption/recovery of the migration | defined and tested | G-26 |
| REG-08 | exact-head GitHub Actions on the commit under review | success, run id recorded | evidence rule 6 |
| REG-09 | every **[BLOCKED]** test has an executed expectation for the PO-chosen option (none left as placeholder) | pass | gate |
| REG-10 | negative controls recorded for every guard (table of control → failing assertion) | complete | evidence rule 1 |

**Planned IDs:** SCH 14 · UNT 8 · PLT 8 · AUT 24 · LED 12 · IDM 14 · NUM 12 · TIM 14 · CFG 8 · TZ 12 · NEG 10 · COR 14 · ARC 10 · AGG 10 · RACE 14 · ISO 12 · FRZ 6 · PRV 10 · RET 4 · REG 10 = **226**. These are planning IDs; the executed suite will report its own counts and any difference is recorded.

## 4. API-phase contract tests (not Phase 2)

When an API exists (G-27): schema validation; decimals only as strings; RFC 3339 with offset; idempotency-key header semantics; uniform 404 for missing/foreign/unauthorized objects; no raw database error text; rate limiting on event commands; no identity in any request body. These are **not** counted above and carry no evidence now.

## 5. Coverage matrix — approved rules

| Rule | Groups |
|---|---|
| A-01 | SCH |
| A-02, A-03, N-02 | UNT, PLT |
| A-04, A-05, N-03 | AUT |
| A-06, A-07, N-04, N-05 | COR, LED, SCH |
| A-08, N-07 | LED, AGG |
| A-09, N-06 | IDM, RACE |
| A-10, N-09 | NEG |
| A-11, N-10 | ARC |
| A-12, N-08 | RACE |
| A-13, A-14, A-15, A-16, A-19, A-20, N-11, N-13, N-14 | TIM, CFG |
| A-17, A-18, N-12 | TZ |
| N-01 | SCH, ISO |
| N-15 | AGG, REG |

## 6. Decision-dependent tests

Every **[BLOCKED]** row must be resolved before implementation review. For each, the expected result under every candidate option is given in `G16_UNRESOLVED_DECISIONS.md`; the test is written against the **PO-chosen** option only, and REG-09 verifies none remains a placeholder. No test is allowed to encode a guessed option.

## 7. Acceptance criteria for G-16 (all required)

1. Every non-blocked test passes locally and in GitHub Actions at the **exact reviewed head**, run id recorded.
2. Every guard has a recorded negative control (REG-10).
3. All **[BLOCKED]** tests resolved against PO decisions (REG-09).
4. Tenant, actor, constraint, idempotency, concurrency, timezone/configuration and lifecycle suites pass.
5. Independent Supervisor review recorded; PO gate decision recorded.

## 8. What this plan does not claim

No test exists or has run. This plan does not approve G-16, Phase 2, Phase 3, a production write path, a production key or real-data use. D-014 remains in force.

**Final status: READY FOR INDEPENDENT SUPERVISOR DESIGN REVIEW — NOT APPROVED.**
