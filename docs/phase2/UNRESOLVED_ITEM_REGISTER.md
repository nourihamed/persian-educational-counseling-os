# Unresolved-item register — Phase 2

**Date:** 2026-11-18
**Written by:** the implementation agent. This is **not** a Supervisor review and **not** a Product Owner decision.
**Machine-readable twin:** `docs/phase2/unresolved_items.json` (same items, same fields; the JSON is authoritative for tooling, this file for reading).

## How to read this register

Three rules govern it, and they are the reason it exists:

1. **Documenting an item does not close it.** Every item below is closed only by its named decision owner.
2. **Nothing here has been decided by the implementation.** Where a recommendation appears, it is a recommendation *to* the decision owner and nothing in the code assumes it.
3. **"Implementation may continue" is not "the question is answered."** It means the undecided part is held fail-closed and only the safe, unrelated part of the work proceeds. The fail-closed behaviour of each item is stated under *Held how*.

One item below is marked **FACTUALLY CORRECTED** rather than open or resolved: a claim this project had been repeating turned out to be false when measured. It is flagged rather than quietly fixed.

---

## Summary table

| Item | Title | Status | Impact | May work continue | Decision owner |
|---|---|---|---|---|---|
| Q-007 | Parent/guardian access matrix and legal authority | PARTIALLY DECIDED | HIGH | Yes, fail-closed | Product Owner + Iranian legal counsel |
| Q-020 | Tenant data-retention periods | PARTIALLY DECIDED | MEDIUM now, HIGH at offboarding | Yes | Product Owner + legal/tax/privacy |
| OQ-CRD-2 | Reserved entitlement after its period ends | OPEN | Billing correctness HIGH | Yes, nothing implemented | Product Owner |
| OQ-CRD-3 | Source of the entitlement duration | OPEN | Billing correctness HIGH | Yes, fail-closed | Product Owner |
| OQ-SAGA-1 | Canonical wire format and signing | OPEN | HIGH | Yes, fail-closed | Platform Security + Product Owner |
| OQ-SAGA-2 | Resolution of a quarantined inbox event | OPEN | HIGH | Yes, no release path | Product Owner + Platform Security |
| OQ-ASM-1 | Item-bank ownership and `item_ref` | OPEN | MEDIUM | Yes, no cross-boundary reference | Product Owner |
| OQ-ASM-2 | Which scoring algorithms are permitted | OPEN | MEDIUM (correctness) | Yes, shape enforced, values not | Product Owner |
| WS-DOM-05 | Curriculum Book/Edition, successor mapping, content ownership | PARTIALLY DECIDED | MEDIUM (correctness, isolation later) | Yes — Phase 7 | Product Owner; four governance questions remain |
| WS-PLAN-01 | Normalized PlanItem versus opaque `plan_content` JSON | PARTIALLY DECIDED | HIGH for the product promise | Yes — implementation required in Phase 2 | Product Owner decision recorded; implemented at `d75d039`; F-01..F-04 at `8df7d5e`; F-05 remediated after it, pending independent review |
| WS-ISO-01 | Counselor-to-counselor isolation inside one Workspace | OPEN | **CRITICAL, BLOCKING — fails open** | Other work only; gate may not pass | Product Owner + architecture owner |
| OQ-D | Control Plane topology — numeric objectives | PARTIALLY DECIDED | HIGH at operation | Yes, schema only | Product Owner + operations |
| OQ-E | Transfer cutover — boundary, duration, thresholds | PARTIALLY DECIDED | HIGH | Yes; boundary now implemented | Product Owner + operations |
| PS-1 | Signature algorithm | DEFERRED | HIGH | Yes, fail-closed | Platform Security + Product Owner |
| PS-2 | Algorithm allowlist values | DEFERRED | HIGH | Yes, nothing hard-coded | Platform Security |
| PS-3 | Issuer-key registry | DEFERRED | HIGH | Yes, no key material stored | Platform Security |
| PS-4 | Key provisioning, rotation, revocation | DEFERRED | HIGH | Yes, mechanism only | Platform Security |
| PS-5 | Clock-skew allowance | DEFERRED | MEDIUM | Yes, zero tolerance | Product Owner + Platform Security |
| PS-6 | CA, trust store, mTLS identity | DEFERRED | HIGH | Yes, no transport exists | Platform Security |
| PS-7 | Verifier/adapter deployment topology | DEFERRED | MEDIUM | Yes, nothing to deploy | Platform Security + Product Owner |
| PS-8 | Revocation source and propagation | DEFERRED | HIGH | Yes, no freshness claimed | Product Owner + Platform Security |
| M-05 | Duplicate JSON object keys not rejected at raw ingress before JSONB | OPEN | MEDIUM (technical debt) | Yes, non-blocking | Supervisor (closure review) |
| M-06 | No single canonicalization vector source shared by SQL and Python | OPEN | MEDIUM (technical debt) | Yes, non-blocking | Supervisor (closure review) |
| WS-DOM-02 | Role source of truth and trusted authorization | PARTIALLY DECIDED | HIGH | Yes, fail-closed | Platform Security + Product Owner (Issue #13) |
| TRANSFER-EXC-AUTH | Who may authorize an approval-conflict exception | OPEN | HIGH | Yes, exception impossible to enable | Product Owner |
| PR-8-11-DISPOSITION | Disposition of PR #8–#11 | OPEN | Process only | Yes, no PR touched | Product Owner on Supervisor advice |
| BRANCH-SYNC | PR #12 branch is behind main by 2 commits, zero net content | OPEN | None technical; reporting integrity | Yes | Product Owner |
| OPS-HOLD-AUTH | Who may place and who may release a legal hold | OPEN | HIGH at pilot; zero today | Yes, nobody can write the table | Product Owner + legal |
| OPS-DISP-AUTH | Who authorizes and who executes an irreversible disposition | OPEN | HIGH at pilot; zero today | Yes, the gate is uncallable | Product Owner + operations |
| OPS-RETENTION-SCOPE | Disposition completeness beyond the primary row | OPEN | HIGH at pilot, as incompleteness | Yes, completeness not claimed | Product Owner + operations (after OQ-D) |
| OPS-NOTIF-DELIVERY | Delivery-time re-check of notification authority and generation | OPEN | HIGH once delivery exists | Yes, insert-time rule only | Product Owner + Platform Security |
| REPO-HIST-CONTACTS | Contact-shaped test fixtures remain in Git history | OPEN | LOW; not credentials | Yes, each excepted by hash | Product Owner |

---

## 1. Product Owner decisions

### Q-007 — Parent/guardian access matrix and legal-authority verification
**Status:** PARTIALLY DECIDED. The high-level policy is accepted (Option A, per OQ-G and the 2026-11-07 decisions): access is scoped per child and per permission, with expiry, revocation and audit; private counselor notes are hidden by default; sensitive, financial and assessment data need independent permission.
**Why it is still unresolved:** the detailed matrix by age and legal status under Iranian law, the acceptable evidence of guardianship and the process for verifying it, the conflict and revocation rules, and the exact read/action scopes.
**Impact:** HIGH. Guardian authority is an authorization input. A guessed matrix discloses a minor's educational, financial and assessment data to a third party, and disclosure cannot be undone.
**Held how:** `student_guardian_links` carries no effective permission grant, guardian projections are fail-closed, and no parent-facing surface exists.
**Options:** (A) commission the legal review now and derive the matrix from it; (B) ship a minimum matrix — overall progress, weekly execution, exam trend, critical alerts — under written acceptance of the legal risk; (C) drop the parent panel from the MVP.
**Recommendation: A.** Phase 23 is far away, so nothing is blocked by waiting, and a legally wrong matrix cannot be corrected after the data has been shown.

### Q-020 — Tenant data-retention periods and criteria for dropping tenant roles
**Status:** PARTIALLY DECIDED. D-017/D-018 settled the principle: no automatic role deletion, a five-step lifecycle, data minimisation, per-category rules, extensions only by recorded decision.
**Why it is still unresolved:** every duration is NEEDS-DECISION or LEGAL-REVIEW, the reviewers are not appointed, and the approver of role deletion is not recorded.
**Impact:** MEDIUM for Phase 2; HIGH at first offboarding, where the choice is between destroying audit evidence too early and keeping personal data indefinitely.
**Held how:** no Phase 2 artifact deletes tenant data or drops a tenant role, and no duration is enforced anywhere.
**Options:** (A) set per-category durations now, after legal and tax review; (B) one conservative interim period for everything; (C) wait until the offboarding feature is scheduled.
**Recommendation: A.** The draft schedule already enumerates the categories, so what remains is review, not design — and a single interim number would be wrong for billing and audit records in particular.

### OQ-CRD-2 — Disposition of a reserved entitlement after its original period ends
**Status:** OPEN. Archiving inside the reversal window returns the credit; outside it, the entitlement is held as reserved. What happens when that reserved entitlement's original period elapses is undecided.
**Impact:** low for security, high for billing correctness: the wrong rule silently gives away or silently destroys paid credit.
**Held how:** reactivation against a reserved entitlement is implemented and tested; no expiry, extension or automatic return exists, and nothing reads the elapsed period.
**Options:** (A) expire, no return; (B) expire, return the credit; (C) hold indefinitely until reused or released; (D) extend the period by the archived duration.
**Recommendation: D.** It matches what the counselor paid for — a quantity of service rather than a wall-clock window — it cannot destroy paid credit, and unlike (C) it stays bounded.

### OQ-CRD-3 — Source of the entitlement duration
**Status:** OPEN. Activation must set a period; whether it comes from the product, the counselor's plan, the program, or an explicit parameter is undecided.
**Impact:** low for security, high for billing correctness.
**Held how:** the production entry point `activate_student_enrollment()` is fail-closed — `resolve_student_entitlement_period()` raises `feature_not_supported` and names OQ-CRD-3. The working path exists only as `activate_student_enrollment_synthetic()`, which demands the period explicitly and is restricted to the synthetic executor role under D-014.
**Options:** (A) the purchased product/plan carries it; (B) the counselor sets it per student within plan bounds; (C) the program template carries it; (D) a platform default with per-product override.
**Recommendation: A.** It keeps the billing rule in the billing domain, where the money and the audit trail already live, and leaves (B) available later as a bounded override.

### OQ-SAGA-2 — Resolution of a quarantined inbox event
**Status:** OPEN. An event that fails verification or integrity is quarantined; who may inspect, release or discard it, and on what evidence, is undecided.
**Impact:** HIGH in both directions. A release path is an authenticated-transport bypass if its authority is undefined; with no path at all, one bad event can strand a student's ownership.
**Held how:** quarantine records the outcome and stops the projection. No release or discard command exists. Forward recovery is operator re-drive at the Control Plane, which never alters the event.
**Options:** (A) no release path — the Control Plane re-issues a new event; (B) two-person operator release with recorded evidence; (C) platform-admin release with audit.
**Recommendation: A.** It preserves the immutable-event guarantee and needs no new authority, because re-drive and re-issue already exist. (B) and (C) both create a privileged path that would then have to be defended.

### OQ-ASM-1 — Item-bank ownership and the meaning of `item_ref`
**Status:** OPEN. Whether the item bank is platform-owned, Workspace-owned or external is undecided, and that determines what referential integrity is even possible.
**Impact:** MEDIUM. A Workspace-owned bank referenced without integrity is exactly the unrestricted polymorphic reference the brief forbids; a platform-owned bank crosses the tenant boundary and needs its own authorization rule.
**Held how:** `item_ref` is a constrained text reference inside the Workspace, with no cross-database foreign key and no claim of integrity against an external bank. The immutable question set itself is implemented and tested.
**Options:** (A) Workspace-owned with a real foreign key; (B) platform-owned shared bank with licensing and read authorization; (C) both, distinguished by a reference kind with integrity enforced per kind.
**Recommendation: A.** It is the only option that yields enforceable integrity inside Phase 2's tenancy model, and (C) can be added later without rewriting it.

### OQ-ASM-2 — Which scoring algorithms are permitted, and how their versions are governed
**Status:** OPEN, raised by the Batch 4 work on 2026-11-14. Nothing recorded which algorithm produced a
score: a scoring policy snapshot of `{}` was accepted and published. Every snapshot must now name an
`algorithm` and a positive integer `algorithm_version`.
**Why it is still unresolved:** the database deliberately does not constrain *which* algorithm names are
permitted, who may introduce one, or what a version increment means. Those are product decisions about
scoring behaviour, and the database never computes or validates a score.
**Impact:** low for security, medium for correctness and auditability — without a governed set, two
Workspaces could use one name for different behaviour, and a historical score would stop being
attributable to a known rule.
**Held how:** the shape is enforced (EXM-01..07, EXM-42); the value set is not. No scoring algorithm is
implemented anywhere.
**Options:** (A) a platform-level registry of algorithm names and versions that the snapshot references;
(B) a fixed allowlist in the schema, extended only by migration; (C) free-form names, governed by process.
**Recommendation: A.** It makes a historical score attributable to a named, versioned rule without
freezing the set in the schema, and it is the only option under which a reviewer can later tell what
`algorithm_version: 2` actually meant.

### TRANSFER-EXC-AUTH — Who may authorize a transfer approval-conflict exception
**Status:** OPEN. Separation of duties forbids the same actor from both requesting and approving a transfer. Whether an exception may ever be granted — by whom, on what evidence, with what audit — is undecided.
**Impact:** HIGH. An exception path is a bypass of the one control that stops a single actor moving a student between Workspaces unilaterally.
**Held how:** `transfer_approval_conflict_exceptions` exists with `CHECK (enabled = false)`, so no role can enable an exception. The table exists only to give the decision somewhere to land; today it grants nothing.
**Options:** (A) no exception, ever — a conflict is resolved by involving a second actor; (B) platform-admin exception with recorded justification; (C) two-person platform-admin exception.
**Recommendation: A.** The control exists precisely for the single-actor case. If operations genuinely require an exception, (C) is preferable to (B) because it does not rest on one administrator's judgement.

---

## 2. Architecture decisions with open numbers

### WS-DOM-05 — Curriculum Book/Edition, version successor mapping and content ownership
**Product Owner decision (2026-11-18): Option A — DEFER TO PHASE 7. Gate impact: `LATER_PHASE`.** Book/Edition, explicit curriculum-version successor mapping, and platform-versus-Workspace content-ownership metadata are not to be implemented in Phase 2. This resolves the Phase 2 blocker classification, not the four governance questions below.

**Still requiring explicit Product Owner decisions before Phase 7:** (1) source of reference-content ingestion; (2) whether Workspace may fork reference nodes or only overlay them; (3) who approves curriculum changes; (4) whether subtopic-level mastery is mandatory in MVP. No proposed default is approved by this decision. Until then, retain Topic-level mastery as the MVP requirement and do not invent a content licensing/ownership policy.

**Status:** OPEN. `CURRICULUM_DOMAIN_CONTRACT.md` is marked **DRAFT / NOT APPROVED**. Its canonical
hierarchy is Grade → Subject → Book/Edition → Chapter → Topic → Subtopic, and the contract itself records
that the skeleton had Subject → Chapter → Topic with "no Book/Edition or Subtopic".
**What was built on 2026-11-15, and what was not.** The Product Owner scoped the work to **subtopics only**.
`subtopics` exists, is ordered within its parent topic, is archivable rather than deletable, and is tested
(CUR-01..CUR-10). **Not built:** Book/Edition, explicit curriculum version successor mapping,
platform-versus-Workspace content ownership metadata, and subtopic-level mastery evidence.
**Why the rest is still unresolved:** the contract's own section 7 leaves open whether books/editions are
MVP-managed or imported from a controlled source, whether a Workspace may fork reference nodes or only
overlay them, who approves curriculum changes, and whether subtopic-level mastery is mandatory in MVP.
**Impact:** low for security as it stands; medium for correctness and for tenant isolation once shared
reference curriculum exists, because "platform content is read-only to Workspace runtime roles" and
"Workspace A cannot read or write Workspace B's custom curriculum" cannot be tested while the ownership
structures are absent.
**Held how:** mastery stays at topic level. Every foreign key restricts deletion, so no curriculum node can
be deleted out from under the history referencing it — CUR-09 asserts that from the catalog rather than
trusting it, by failing if any foreign key in the schema has a non-default delete action.
**Options:** (A) approve the contract and build this in **Phase 7 (Curriculum)**, where the roadmap puts it;
(B) build Book/Edition now, deferring only mastery and licensing; (C) drop Book/Edition from MVP.
**Recommendation: A.** Phase 7 is the roadmap's own home for curriculum, and the open items are licensing
and governance questions needing the content owner rather than a schema decision. Building Book/Edition now
would commit to an import model and an ownership model nobody has chosen, and that is hard to reverse once
curriculum rows reference them.

### WS-PLAN-01 — Normalized PlanItem versus today's opaque `plan_content` JSON
**Product Owner decision (2026-11-18): Option B — BUILD THE DATA MODEL IN PHASE 2. Gate impact: `BLOCKING` until implementation and tests pass.** The approved PlanItem source set is `topic`, `subtopic`, `activity`, `exam`, `review`, `assignment`. Each PlanItem must reference exactly one source through a typed nullable FK; unrestricted polymorphic `source_type/source_id` is prohibited.

**Approved item statuses:** `planned`, `in_progress`, `completed`, `partially_completed`, `deferred`, `skipped`, `cancelled`. **Approved deferral reasons:** `insufficient_time`, `schedule_conflict`, `prerequisite_not_mastered`, `difficulty`, `illness_or_absence`, `resource_unavailable`, `higher_priority_task`, `student_requested`, `counselor_adjustment`, `other`. `deferred` requires a reason; `other` may carry an explanatory note. These vocabularies do not authorize scheduling logic in Phase 2.

**Corrected 2026-11-19 for Supervisor finding F-05 (HIGH) on `8df7d5e` — still NOT ACCEPTED, still `BLOCKING`.** The privileged identities were checked with `pg_has_role(current_user, role, 'MEMBER')`, which any direct or indirect member passes, and the bootstrap trusted an existing role as it found it. Now:
- the session must **be** the role, and on every write the role must have no membership in either direction and none of LOGIN, SUPERUSER, CREATEROLE, BYPASSRLS, REPLICATION, CREATEDB or INHERIT;
- the bootstrap aborts on an unsafe existing role and repairs nothing;
- it then checks the whole boundary (`plan_identity_boundary_violations`) in the same transaction, so a violation leaves no identity record.

Tests: F05-00..F05-16 and F05-BOOT-01..14, each with a negative control. **Open (Platform Security / Operations):** who may provision, hold or assume these identities outside the synthetic test harness.

**Corrected 2026-11-18 for Supervisor findings F-01..F-04 on `d75d039` — still NOT ACCEPTED, still `BLOCKING`.** F-01 (CRITICAL, actor impersonation): the runtime could write plan items and transitions and the actor was whatever the row said; now no application identity may write either (a NOLOGIN synthetic identity is the only writer, then checked by role membership — tightened by F-05 to identity), and `actor_kind='student'` is refused outright. F-02 (HIGH): the runtime may no longer name `content_model`, and `legacy_json` is accepted only from the NOLOGIN migration identity. F-03 (MEDIUM): publishing an empty normalized version and recording status on draft items are refused pending Product Owner decisions. F-04 (MEDIUM): historical rows are classified `legacy_json` when the column is added; `WS_PLAN_01_MIGRATION_NOTES.md`, PLN-M01..M08.

**Implemented 2026-11-18 (draft SQL; local evidence only; NOT yet independently verified — the gate impact stays `BLOCKING` until CI on the resulting SHA and the Supervisor's review confirm it).** `workspace_plan_items_draft.sql`: `plan_items` with the six typed, student-bound source foreign keys and an exactly-one-source CHECK; item definitions insert-only, added only to a draft; a change is a new version naming the version it supersedes, with a reason and an author; status transitions append-only, sequence-numbered, with actor, timestamp and reason, and current status derived; normalized versions carry no JSON, output JSON derived (`plan_version_rendered`); legacy JSON only on explicit `legacy_json` versions, which cannot follow a normalized one. Tests: PLN-C1..C4, PLN-01..PLN-63 (61 PASS lines) and WS-PLN-RACE-01..03, each rule with a measured negative control. **Not built, because the decision does not cover it:** scheduling, ranking, conflicts, generation, a transition graph, priority, dependencies, provenance, carry-forward.

**JSON policy:** normalized PlanItem is authoritative for new plan versions. Preserve legacy `plan_content` only for historical compatibility/migration. Do not keep two independently editable sources of truth; any JSON needed for printing/output must be derived. Published PlanVersions remain immutable. Item changes and status transitions must be auditable with actor, timestamp and reason.

**Status:** OPEN. `DETERMINISTIC_PLANNING_DOMAIN_CONTRACT.md` is marked **DRAFT / NOT APPROVED**. Its
section 1 requires that planning inputs and outputs "must be modeled as first-class domain data, not hidden
inside an opaque JSON blob", and section 4 specifies a normalized PlanItem with **typed nullable foreign
keys and exactly-one-source constraints** — explicitly not an unrestricted polymorphic reference. Today
`student_plan_versions.plan_content` is `jsonb`, which is the shape the contract rejects.
**Impact:** low for security; **high for the product's core promise.** With the plan in a blob there is no
referential integrity from a plan item to the topic, activity, exam or review it schedules, no per-item
status, no machine-readable deferral reason, and no way to answer "what was originally planned, what
changed and why" by query — which the master prompt's sections 31, 72 and 81 require.
**Held how:** Plan and PlanVersion identity, version numbering, immutability of a published version and
version history all exist and are tested. `plan_content` is stored but **nothing in the database interprets
it**, so no scheduling behaviour is implied or claimed. `student_plan_versions` is now covered by the
transfer write barrier through its plan (FRZ-01c, FRZ-18b).
**Options:** (A) build normalized `plan_items` in **Phase 12 (Planning Engine)**; (B) build the plan_items
**data model** now in Phase 2 — typed FKs and exactly-one-source constraints, no scheduling logic;
(C) keep `plan_content` as the authority and accept that plan contents have no referential integrity.
**Recommendation: B.** The data model is a Phase 2 concern and the engine is not — the same split already
worked for Activity, whose typed source columns and exactly-one-source CHECK were built in Phase 2 while
nothing generates activities yet. Deferring the shape is what makes it expensive, because by then
`plan_content` blobs exist and must be migrated. (C) is the only option that conflicts with the contract
outright. Nothing is built against this recommendation.

### WS-ISO-01 — Counselor-to-counselor isolation inside one Workspace — CRITICAL, BLOCKING
**Status:** OPEN. **Severity: CRITICAL as a design finding, and BLOCKING for the Phase 2 gate** (Supervisor
instruction of 2026-11-18: it must not be treated as an ordinary future enhancement). The requirement is
approved and unambiguous — master prompt §3; `API_AUTHORIZATION_CONTRACT.md` §4 *"Counselor reads/writes are
restricted to students with active counselor assignment"* and §6 *"Counselor cannot read another counselor's
student absent explicit scope"*; the role-grantability matrix *"a Counselor is confined to assigned students"*.
**What the database does about it, measured:** it **fails OPEN**. The single Workspace runtime role, shared by
every counselor, holds `SELECT` on 47 tables in full; no student-scoped table has row-level security
(ISO-GAP-03: 0 of 32); and that role reads counselor B's study session and every author's
`private_to_author` note directly (ISO-GAP-01, ISO-GAP-02). This is the **only** register item whose current
state fails open rather than closed. Exposure today is nil only because no API or deployment exists; the
first code path built on this schema would inherit cross-counselor access by default.
**The exact missing boundary, in two halves.** (1) *Which* students a counselor membership may reach: the
schema **recorded** the assignment (`counselor_assignments`) and **nothing consumed it** — no policy, view,
function or grant was keyed to it. (2) *Which* membership is calling: the database has no notion of it.
**What was built on 2026-11-18** (`workspace_counselor_scope_draft.sql`, ISO-C1..ISO-54, 42 PASS lines):
half (1), completely — `counselor_may_access_student` (active **and accepted** assignment, active membership,
counselor role; managers denied until an explicit-permission vocabulary exists, which is the contract's own
default), the list (`counselor_visible_students`), any row of any of the 32 student-scoped tables by its own
id (`counselor_may_access_row`, sharing the transfer barrier's owner resolution so the two boundaries cannot
disagree, with `private_to_author` notes visible to their author only), a report
(`counselor_caseload_report`), and two write paths that need no caller identity because the row names the
actor: counselor notes, and the notification recipient rule — which **Batch 8 itself had left open to any
active member** (corrected; OPS-13c). Every one of those has a measured negative control.
**What is NOT built, and why:** half (2). Every boundary function takes the membership as an **argument**, and
nothing stops a caller passing someone else's. Binding the caller is a Platform Security decision.
**Options for half (2):** (A) per-membership database login roles mapped to memberships, with row-level
security reading `session_user` — PostgreSQL verifies the identity, at the cost of one role per staff member
and constraints on pooling; (B) a short-lived signed principal assertion verified **inside** the database by a
SECURITY DEFINER function (the receipt-verifier pattern this project already has), recording the verified
membership for the current transaction only, with row-level security reading that — works with pooling,
depends on PS-1..PS-4; (C) API-only enforcement with the database functions as defence in depth — leaves the
database failing open, which is the finding; (D) one Workspace per counselor — contradicts the Organization
model.
**Recommendation: B, with A as the fallback** if PS-1..PS-4 cannot be decided in time. Session GUCs are **not**
an option: H-03 already rejected them, because the application sets them and can therefore forge them.
**Minimum safe correction once decided:** enable row-level security on every table in `student_scoped_tables`
with one policy shape, `USING (counselor_may_access_student(current_verified_membership(), <owner>))`, the
owner resolved as the barrier resolves it; give the runtime role no `BYPASSRLS`; route any legitimate
cross-student operation (transfer export, reporting to a manager with explicit permission) through reviewed
SECURITY DEFINER functions; then turn ISO-GAP-01..03 into failing-if-reachable assertions and re-run the
ISO suite **as each counselor's own identity**. Full proposal: `docs/phase2/workspace/WS_ISO_01_COUNSELOR_ISOLATION_PROPOSAL.md`.
**Held how:** SEC-10 and ISO-GAP-01..03 assert the residual as OPEN lines (not PASS lines) that fail the suite
if the measurement changes; nothing claims the isolation is enforced.
**Not decided here (sub-questions):** whether a suspended or awaiting-consent enrollment narrows access (the
approved rule names the assignment, so the predicate uses exactly that); the explicit permission that lets a
manager reach a student.

### OQ-D — Control Plane topology and recovery
**Status:** PARTIALLY DECIDED (Option A accepted): independent infrastructure, primary plus replica, independently controlled encrypted backups with restore drills, and student access fail-closed when ownership cannot be validated.
**Still open:** RPO, RTO, retention, failover consistency, split-brain prevention, and measured capacity and cost.
**Impact:** HIGH at operation, not at schema. With no split-brain rule, two Control Plane primaries could each grant ownership.
**Held how:** Phase 2 produces schema and commands only — no deployment, no replication configuration, no availability claim. The fail-closed ownership rule is implemented.
**Options:** (A) set RPO/RTO now from business tolerance; (B) measure a representative workload first; (C) defer to Phase 28.
**Recommendation: B for the numbers, but decide split-brain prevention earlier.** Inventing SLOs is forbidden and numbers set without measurement are either unachievable or meaningless — but split-brain prevention constrains the design, so it should not wait for Phase 28.

### OQ-E — Transfer cutover: freeze boundary, duration, recovery, thresholds
**Status:** PARTIALLY DECIDED (Option B accepted): controlled source write freeze, final snapshot, destination staging and import, integrity validation, then the atomic Control Plane ownership switch. Freeze duration, the precise freeze boundary, failure recovery and acceptance thresholds were explicitly left to detailed design and tests.
**What changed on 2026-11-14:** the **database half of the freeze boundary is now implemented and tested** — `docs/phase2/workspace/workspace_transfer_freeze.sql` adds a durable freeze record, a write barrier on all student-scoped tables (27 at the time; 31 after Batch 5 found five indirectly reached tables unprotected; 32 after Batch 8 gave notifications a student reference), an in-flight transaction barrier with a recorded watermark, and a permanent fence once the source observes the switch. Before this, the Control Plane recorded that a freeze had happened and the Workspace database enforced nothing, so a source Workspace could keep writing a student straight through cutover.
**Still open and NOT implemented:** freeze duration, drain timeout, acceptance thresholds, and the freeze of application, worker, import and export surfaces — those surfaces do not exist in this repository (`backend/`, `frontend/`, `scripts/`, `tests/` contain only `.gitkeep`), so they are not claimed.
**Options:** (A) set a maximum freeze duration and acceptance threshold now as a product promise; (B) derive both from measured transfer runs once a service layer exists; (C) leave the freeze open-ended with manual operator confirmation per transfer.
**Recommendation: B, with C as the interim operating rule.** A duration invented without a measured workload is the kind of number the brief forbids, and the database already supports (C) because the freeze has no timeout.

---

## 3. Platform Security deferrals (Issue #13, Decision C)

None of PS-1..PS-8 is answered, and none is assumed. The production verifier is fail-closed; every test that touches this area uses test doubles and is labelled as such. `verifier_rt` was tested to hold **no** receipt-consumption and **no** governance-command privilege.

| Item | Question | Impact | Recommendation (not a decision) |
|---|---|---|---|
| PS-1 | Signature algorithm for assertions | HIGH — blocks all production verification | Ed25519: small keys, no parameter footguns, wide support |
| PS-2 | Algorithm allowlist values | HIGH — algorithm substitution | A single algorithm with no negotiation; negotiation is where these bugs live |
| PS-3 | Issuer-key registry | HIGH — no issuer-to-key authority | An external KMS/HSM as the authority, with a Control Plane table holding references only |
| PS-4 | Provisioning, storage, rotation, revocation | HIGH — rotation is an outage without a procedure | KMS-managed rotation with overlapping validity, designed before the first key is issued |
| PS-5 | Clock-skew allowance | MEDIUM — too wide extends a revoked assertion's life | A configurable allowance with an upper bound |
| PS-6 | CA, trust store, mTLS identity | HIGH — the authorization channel is unauthenticated | Private CA with mTLS; a bearer token authenticates only one side |
| PS-7 | Verifier/adapter deployment topology | MEDIUM — blast radius of a compromised adapter | A separate verifier service, keeping key access out of application processes |
| PS-8 | Revocation source and propagation | HIGH — blocks any end-to-end freshness claim | Short-lived receipts *and* a revocation list for emergencies |

### OQ-SAGA-1 — Canonical wire format and signing for Saga envelopes
**Status:** OPEN, dependent on PS-1..PS-4. The envelope carries `payload_hash`, `schema_version` and correlation identifiers, but the canonical byte encoding and the hash and signature algorithms are undecided.
**Impact:** HIGH. Without authenticated transport a Workspace cannot distinguish a genuine ownership-switch event from a forged one — a cross-tenant takeover path.
**Held how:** `apply_inbox_event()` is fail-closed through `assert_inbox_transport_verified()`; the working projection exists only as `apply_inbox_event_synthetic()` under the synthetic inbox role (D-014). No signature is invented and no authenticity is claimed.
**Options:** (A) decide PS-1..PS-4 first; (B) define the canonical encoding now and leave the algorithms to PS-1/PS-2; (C) keep the whole item closed until Phase 18/19.
**Recommendation: B.** Canonical encoding is independent of the cipher and is the part that silently breaks compatibility if left late; settling it does not pre-empt Platform Security.

### WS-DOM-02 — Role source of truth and trusted authorization
**Status:** PARTIALLY DECIDED. The competing-role-source half **is closed**: the scalar `workspace_memberships.role_key` is gone and `membership_roles` is the canonical projection.
**Still open:** the trusted authorization adapter. Authenticated actor evidence is not cryptographically verified, no grantability/anti-self-escalation matrix is enforced, and no application role may execute the governance commands. This depends on Issue #13 and PS-1..PS-8.
**Impact:** HIGH. Until it closes, a governance command carries no verifiable authority, so role grants cannot be trusted as an authorization basis.
**Held how:** governance commands are restricted to dedicated owner roles, no application role can append events, and the production verifier refuses.
**Options:** A1/B3 as proposed in Issue #13 (a trusted governance authorization adapter with a fail-closed verifier); a database-only authority model; or deferring governance commands out of Phase 2.
**Recommendation: A1/B3.** It is the option already proposed and reviewed in Issue #13, and the only one under which a role grant carries evidence of who authorized it. A database-only model would make the database its own authority, which is exactly what the current fail-closed design avoids.

---

## 4. Supervisor findings whose text was never supplied

### M-05 and M-06 — defined by the Supervisor on 2026-11-18: MEDIUM technical debt / security hardening
**Status:** OPEN, now **actionable** — the Supervisor supplied both definitions with closure criteria. **Gate impact:
`NON_BLOCKING_TECHNICAL_DEBT`.** Neither is implemented, and neither is claimed as addressed.

- **M-05 — reject duplicate JSON object keys at raw ingress, before JSONB.** PostgreSQL's `jsonb` silently keeps the
  last of duplicate keys, so a document an upstream signer or verifier read one way can be stored another way. The check
  must run on the raw text, where duplicates still exist; a CHECK on a `jsonb` column cannot see them. No raw-ingress
  layer exists in this repository, and the inbox production path is fail-closed. **Closure (Supervisor):** duplicate
  keys rejected at raw ingress before JSONB, shown by a duplicate-key document refused at every ingress path.
  **Recommendation:** one shared strict parser used by every ingress path.
- **M-06 — one shared machine-readable canonicalization vector source for SQL and Python.** The canonical form is
  exercised today by Python vectors (`receipts/verifier_interface/canonical/test_vectors_v1.py`) and by SQL receipt
  tests separately, so the two could drift and each still pass its own vectors. **Closure (Supervisor):** a single
  machine-readable vector source consumed by both suites, with a check that no independent copy exists.
  **Recommendation:** one versioned vector file read by both suites.

The earlier text of this section said both were undefined; that was true until 2026-11-18 and is kept in Git history.

## 5. Repository and process items

### PR-8-11-DISPOSITION — Disposition of pull requests #8, #9, #10, #11
**Status:** OPEN. Verified against the repository on 2026-11-14: all four are open drafts based on `main@ba5e9d8`, and PR #12 neither merges nor supersedes their Git history.

| PR | Branch | Head |
|---|---|---|
| #8 | `docs/phase2-database-domain-model` | `7d1ce9f` |
| #9 | `docs/product-owner-decisions-2026-11-05` | `d72c401` |
| #10 | `docs/workspace-centric-canonical-reconciliation` | `30cc32f` |
| #11 | `docs/transfer-control-plane-architecture` | `ce20f5f` |

**Impact:** no security impact; a process risk, because four open drafts of the same documentation leave it ambiguous which text is current.
**Held how:** no PR has been merged, rebased, force-pushed or closed. Work continues only on the PR #12 branch.
**Options:** (A) close #8–#11 as superseded by #12, after confirming no unique content is lost; (B) merge them in order and then rebase #12; (C) leave all five open until Phase 2 is approved.
**Recommendation: A.** Their content has been consolidated into the #12 branch, and stale drafts invite a reviewer to read superseded text. The "no unique content lost" diff should be produced before closing; the implementation can prepare it on request.

### BRANCH-SYNC — The PR #12 branch is behind `main` by two commits whose net content change is zero
**Status: OPEN. This entry previously claimed the branch was NOT behind `main`, and that claim was wrong.
It is retracted here.**

**The error.** `main`'s tip was read from the `base.sha` field of the open pull request objects. That field
records the base commit **as it stood when each PR was created** (`ba5e9d8`), not `main`'s current tip.
Four PRs all reporting the same `base.sha` looked like confirmation; it was the same stale value four times.

**Measured correctly on 2026-11-15:**

```
main tip:                                      5bb8e4ed07a7c770ecba7c506a1d2c278e36b6d6
merge base with the PR #12 branch:             ba5e9d8a9577e5b87e2fc27caaf0bfb07f929114
git merge-base --is-ancestor 5bb8e4e HEAD   -> fails  (the branch does NOT contain main)

commits on main and not on the branch:
  4004360  test(phase2): verify claim admission executor is isolated   (added cp_30_role_privilege_tests.sql)
  5bb8e4e  revert: remove accidental malformed Phase 2 test from main  (removed it again)

git diff ba5e9d8 5bb8e4e  ->  0 changed files
```

**So both halves of the statement matter.** Formally the branch **is** behind `main` by two commits. But
`main` added a file and then reverted it, so the net content difference is **zero** and nothing from `main`
is missing from the branch. Merging `main` would bring no file changes. The branch's own
`docs/phase2/control_plane/tests/cp_30_role_privilege_tests.sql` was written independently on this branch
and is unaffected by either commit.

**Impact:** none technically. The real damage was to the integrity of this project's own reporting: a false
"corrected" claim sat in this register and in `PROJECT_STATE.md` across several batches, and a reviewer
relying on it would have believed the branch was synchronized when it was not.

**Held how:** no rebase, no merge and no force-push, per the standing constraint. Nothing on this branch
depends on resolving it.

**Options:** (A) leave it — behind only in history, with no missing content; (B) merge `main` so the history
is strictly ahead, once the Product Owner lifts the no-merge constraint for that one operation;
(C) resolve it together with the PR #8–#11 disposition, which will move `main` anyway.

**Recommendation: C.** The divergence is harmless today, so a merge on its own gains nothing, and rebasing
or force-pushing is forbidden. Dispositioning PR #8–#11 moves `main` regardless, so this decision belongs
with that one rather than being taken twice. Whichever option is chosen, the record must now say
"behind by two commits, zero net content difference" and never "not behind".

### OPS-HOLD-AUTH — who may place and who may release a legal hold
**Status:** OPEN. The retention contract §9 still lists *"Legal hold categories, triggers, release authority
and dispute handling"*, and §5 adds that *"a hold cannot be released by the same unrestricted deletion job
that it blocks."* Neither authority has been decided.
**What Batch 8 did build:** the hold *mechanism*. A hold must resolve to an existing row of a registered
entity type — the polymorphic `(entity_type, entity_id)` now has enforceable referential integrity through
`retention_entity_types`, so a hold on a mistyped id is refused instead of silently protecting nothing.
Placement facts are immutable, release is one-way, and the record can be neither deleted nor truncated.
**Impact:** HIGH at pilot, **zero today**. A hold the wrong party can place is a denial of service on lawful
deletion; one the wrong party can release is the removal of a legal control. Neither is possible now.
**Held how:** no application role holds `INSERT`, `UPDATE` or `DELETE` on `legal_holds` — only the NOLOGIN
table owner can write it, which is a synthetic posture and is labelled as one in the roles draft. **OPS-51
asserts this from the catalog** and fails if any application role is granted a write.
**Options:** (A) Platform Admin places and releases, with a second Platform Admin approving the release;
(B) a dedicated compliance role, separate from both the counselor roles and the deletion executor;
(C) the Workspace owner may place, Platform Admin must release; (D) holds placed only by an operational
runbook outside the application.
**Recommendation: B.** The contract's own rule is that the releasing authority must be separable from the
deletion job, which is separation of duties — and this project already has that pattern in the transfer
approval separation, where it is a grant rather than a convention. (A) conflates platform administration
with legal custody. (C) lets the party with an interest in deleting the data also lift the control over it.
(D) leaves no trail inside the system, which contradicts the contract's own requirement to preserve who
placed and released a hold, when, and under what authority reference.

### OPS-DISP-AUTH — who authorizes and who executes an irreversible disposition
**Status:** OPEN. The retention contract §4 requires independent approval for irreversible actions
*"according to the approved authority matrix"* and that *"the requester cannot approve their own
high-impact deletion."* That matrix does not exist, and this repository contains no disposition executor:
no job runner, no object-store client, no worker.
**What Batch 8 did build:** `assert_destructive_disposition_allowed()`, the fail-closed gate that any
future executor must pass. It refuses, with a distinct named reason for each, when the action is not
destructive, the entity type is unregistered, the target row is absent, **any** legal hold is live, or no
approved retention policy version authorizes the action. Today the last condition refuses everything,
because no period is approved anywhere (Q-020).
**Impact:** HIGH at pilot, **zero today**: nothing can call the gate and nothing deletes any registered
entity — the file, notification and hold guards refuse `DELETE` outright and the audit log refuses
`UPDATE`, `DELETE` and now `TRUNCATE`.
**Held how:** `EXECUTE` on the gate is revoked from `PUBLIC` and granted to no role; **OPS-50 asserts
that**. OPS-48 shows the gate *allows* when a synthetic approved policy exists, which is how its refusals
are shown to be decisions rather than an unconditional raise — that synthetic policy is a test fixture,
labelled as such in its own `approval_ref`, and **OPS-40 asserts the schema draft approves nothing**.
**Options:** (A) two-party: compliance requests, Platform Admin approves, a narrow executor identity
performs; (B) single approver with an append-only audit trail; (C) no automated destructive disposition in
the first release — restrict and archive only, erasure by reviewed runbook; (D) the Workspace owner
authorizes disposition of their own data.
**Recommendation: C first, then A.** An executor that cannot verify completeness across objects, exports,
caches, indexes, replicas and backups (OPS-RETENTION-SCOPE) would report deletions it did not complete,
which is worse than not deleting. Then (A), which satisfies the requester-is-not-approver rule as a grant
and keeps the executor's privileges narrow enough to review. (B) relies on detecting an irreversible act
after it happens. (D) puts the decision with the party least likely to know the legal obligations.

### OPS-RETENTION-SCOPE — disposition completeness beyond the primary row
**Status:** OPEN. The contract is explicit that *"deletion from the primary row alone is not complete
disposition"* (§2) and that a restore must re-apply post-backup suppression before recovered data is
served (§7). No object store, export pipeline, cache, search index, replica or backup tooling exists in
this repository, and the mechanics depend on the hosting target, which is itself undecided (OQ-D).
**Impact:** HIGH at pilot, as an **incompleteness** rather than a hole: a deletion reported as done while
copies survive is a false compliance statement. Nothing deletes anything today, so the system makes no
such statement.
**Held how:** Batch 8 claims the **database half only**, and says so in the draft, in the test header and
in `PHASE2_EXIT_CRITERIA.md`. Passing the gate is documented as *not* evidence that a deletion would be
complete, and §7 of the contract is recorded as unimplemented.
**Options:** (A) a durable suppression ledger every restore and derived copy must consult before serving
data; (B) cryptographic erasure, with the key-scope, shared-object and backup dependencies the contract
requires to be proven first; (C) bounded backup rotation with residual copies disclosed until expiry;
(D) defer entirely and document that erasure is partial.
**Recommendation: A with C.** A suppression ledger is the only option that survives a restore, which is
the case the contract names and the one most likely to resurrect deleted data silently. (C) is
complementary and honest about residuals. (B) cannot be relied on until the proofs the contract demands
exist. (D) alone leaves a compliance claim nobody can support.

### OPS-NOTIF-DELIVERY — delivery-time re-check of notification authority and generation
**Status:** OPEN. Four contracts require a notification to be re-authorized **at delivery**, not only when
it is created: the guardian authority matrix, the role-grantability matrix, the Saga recovery contract and
the API authorization contract, which names *"stale queued notification after transfer"* as a threat.
**What Batch 8 did build:** the **insert-time** half, which did not exist. A notification now names the
student it concerns, so the transfer write barrier covers it (that could not even be expressed before:
the table had no reference to a student). Its recipient must be an active member of this Workspace, the
student it is about, or a **verified guardian of that student** — a guardian verified for student A is
refused as a recipient for student B. Its payload may not carry a plaintext contact number, at any depth.
Its recipient, subject and payload are immutable once written; only `read_at` may be set, once.
**Impact:** HIGH once a delivery path exists, zero until then: nothing delivers a notification, so nothing
can deliver a stale one. The specific risk is a notification queued before a guardian's permission was
revoked, or before a student's ownership moved, being delivered afterwards.
**Held how:** the insert-time rule is implemented and tested (OPS-10..OPS-24, OPS-45, OPS-46), and the
draft and test header both state that delivery-time re-authorization is not implemented and not claimed.
It overlaps PS-8, which holds the same gap for revocation freshness generally.
**Options:** (A) the worker re-evaluates recipient authority, student lifecycle and current ownership
generation inside the delivery transaction; (B) notifications carry the generation they were created at
and delivery refuses on a mismatch; (C) queue invalidation on revocation and transfer; (D) a short queue
lifetime so stale entries expire.
**Recommendation: A with B.** (A) is what the contracts require, and this project's repeated lesson is that
a check performed only at creation binds only the creator. (B) makes the transfer case deterministic and
matches the generation fencing the inbox projection already uses, so recording the generation on the row
is worth doing when the worker is built. (C) is a useful optimization but fails open if an invalidation is
missed. (D) narrows the window without closing it.

### REPO-HIST-CONTACTS — contact-shaped test fixtures remain in Git history
**Status:** OPEN. The history content scan added on 2026-11-18 found **110 contact-shaped strings in old blobs
and nothing else** — no credential, no key, no PEM block anywhere in the history. They are six repeated-digit
Iranian-mobile-shaped fixtures from the 2026-10-27..31 constraint tests, two committed test-run logs that
echoed them, and the two Batch 8 OPS-17/OPS-18 fixtures that failed CI. None was taken from data. **They are
not claimed to be unassigned:** the 0912–0917 prefixes are allocated, so a repeated-digit body may belong to a
real subscriber. (One Batch 8 value is in the North American fictional range 555-01xx.)
**Impact:** LOW — not credentials, nothing to rotate or revoke. **Held how:** each finding is excepted
individually by (blob SHA, pattern, SHA-256 of the value) in `secret_scan_history_exceptions.json`, so a
different finding in the same blob still fails; the working tree holds no such literal; the scanner never
prints a detected number in full. **Options:** (A) accept and keep the hashed exceptions; (B) rewrite history
and force-push — prohibited on this branch, so only the Product Owner can lift that; (C) record repository
access restrictions as the compensating control. **Recommendation: A, with C recorded**: a rewrite breaks every
clone and invalidates every SHA cited in this project's evidence trail, for values that are not secrets.

## 6. Classification of every item (2026-11-18)

Requested by the Supervisor: for every item, its kind, whether code can resolve it, and what closes it. The
recommended gate impact is the implementation agent's **recommendation** to the Supervisor, not a ruling.
`BLOCKING` items keep the Phase 2 gate closed; `NON_BLOCKING_FAIL_CLOSED` items are held by a database
behaviour that refuses rather than guesses; `LATER_PHASE` items belong to a phase that has not started;
`NON_BLOCKING_TECHNICAL_DEBT` items are Supervisor-defined hardening that does not block the gate.
**Not every item is a decision only.** `code_can_resolve` is `partly` or `yes` for 13 of the 32: after the
named decision, the remaining work is ordinary implementation with tests.

| ID | Kind | Code can resolve | Recommended gate impact | Closure evidence |
|---|---|---|---|---|
| Q-007 | PRODUCT_OWNER_DECISION | partly | NON_BLOCKING_FAIL_CLOSED | An approved guardian access matrix with Iranian legal review, then one test per scope asserting allow and deny. |
| Q-020 | PRODUCT_OWNER_DECISION | no | NON_BLOCKING_FAIL_CLOSED | Approved period per category R1..R9 recorded as approved policy versions; OPS-40 updated deliberately; the disposition gate's positive path exercised against the real policy. |
| OQ-CRD-2 | PRODUCT_OWNER_DECISION | no | NON_BLOCKING_FAIL_CLOSED | A Product Owner rule for post-period disposition, then implementation and CRD tests for each outcome. |
| OQ-CRD-3 | PRODUCT_OWNER_DECISION | partly | NON_BLOCKING_FAIL_CLOSED | A decided entitlement-duration source, resolve_student_entitlement_period() implemented against it, and the fail-closed test replaced by allow/deny tests. |
| OQ-SAGA-1 | PLATFORM_SECURITY_DECISION, PRODUCT_OWNER_DECISION | partly | NON_BLOCKING_FAIL_CLOSED | Approved canonical format and signature scheme, published test vectors, and verifier tests that reject every malformed or mis-signed envelope. |
| OQ-SAGA-2 | PRODUCT_OWNER_DECISION, PLATFORM_SECURITY_DECISION | no | NON_BLOCKING_FAIL_CLOSED | A decided release authority and procedure, then tests that only that authority can release and that release is audited. |
| OQ-ASM-1 | PRODUCT_OWNER_DECISION | no | NON_BLOCKING_FAIL_CLOSED | Decided ownership and item_ref semantics, then schema constraints and ASM tests. |
| OQ-ASM-2 | PRODUCT_OWNER_DECISION | no | NON_BLOCKING_FAIL_CLOSED | An approved algorithm list with versioning rules, then tests that refuse anything else. |
| WS-DOM-05 | PRODUCT_OWNER_DECISION | partly | LATER_PHASE | Before Phase 7 implementation: explicit Product Owner decisions for the four governance questions and approved Curriculum contract; then Book/Edition and successor-mapping schema, ownership/authorization model, migration notes and CUR tests. This item does not block the Phase 2 gate. |
| WS-PLAN-01 | PRODUCT_OWNER_DECISION | partly | BLOCKING | Normalized PlanItem schema with typed FKs and exactly-one-source constraint; approved status and deferral-reason vocabularies; referential, tenant/authorization, immutability, migration and audit-history tests; evidence that legacy JSON is not a second writable authority. |
| WS-ISO-01 | IMPLEMENTATION_DEFECT, PLATFORM_SECURITY_DECISION | partly | BLOCKING | A decided caller-binding mechanism; row-level security on every student-scoped table keyed to counselor_may_access_student; ISO-GAP-01..03 turned from OPEN into failing-if-reachable assertions; cross-counselor negative tests run AS each counselor's own identity rather than as the shared runtime role; independent review. |
| OQ-D | PRODUCT_OWNER_DECISION, LATER_OPERATIONAL_DEPENDENCY | no | LATER_PHASE | Decided objectives, then an operations phase with measured restore and failover drills. |
| OQ-E | PRODUCT_OWNER_DECISION, LATER_OPERATIONAL_DEPENDENCY | partly | LATER_PHASE | Decided thresholds, a controller implementation, and end-to-end cutover tests including timeout and recovery. |
| PS-1 | PLATFORM_SECURITY_DECISION | no | NON_BLOCKING_FAIL_CLOSED | A recorded Platform Security decision, then verifier tests against the chosen algorithm. |
| PS-2 | PLATFORM_SECURITY_DECISION | no | NON_BLOCKING_FAIL_CLOSED | A recorded allowlist and tests refusing everything outside it. |
| PS-3 | PLATFORM_SECURITY_DECISION | partly | NON_BLOCKING_FAIL_CLOSED | A decided registry design, implementation, and tests that a revoked or unknown key is refused. |
| PS-4 | PLATFORM_SECURITY_DECISION, LATER_OPERATIONAL_DEPENDENCY | no | LATER_PHASE | Documented procedures and a rotation drill. |
| PS-5 | PRODUCT_OWNER_DECISION, PLATFORM_SECURITY_DECISION | no | NON_BLOCKING_FAIL_CLOSED | A decided value and boundary tests at exactly the allowance. |
| PS-6 | PLATFORM_SECURITY_DECISION, LATER_OPERATIONAL_DEPENDENCY | no | LATER_PHASE | Deployed channel with tests that an unauthenticated peer is refused. |
| PS-7 | PLATFORM_SECURITY_DECISION, LATER_OPERATIONAL_DEPENDENCY | no | LATER_PHASE | A decided topology and its threat review. |
| PS-8 | PRODUCT_OWNER_DECISION, PLATFORM_SECURITY_DECISION | partly | NON_BLOCKING_FAIL_CLOSED | A decided revocation source, propagation implementation, and tests that a revoked membership cannot use a receipt or be notified after revocation. |
| M-05 | SUPERVISOR_FINDING | yes | NON_BLOCKING_TECHNICAL_DEBT | Supervisor-defined: duplicate JSON object keys are rejected at raw ingress before JSONB — evidenced by tests that submit a duplicate-key document to every ingress path and observe a refusal before storage. |
| M-06 | SUPERVISOR_FINDING | yes | NON_BLOCKING_TECHNICAL_DEBT | Supervisor-defined: a single machine-readable canonicalization vector source consumed by both SQL and Python tests, with a check that no independent copy exists. |
| WS-DOM-02 | PLATFORM_SECURITY_DECISION, PRODUCT_OWNER_DECISION | partly | NON_BLOCKING_FAIL_CLOSED | A verified authorization adapter, an enforced grantability/anti-self-escalation matrix, and tests that a forged or self-granted role is refused. |
| TRANSFER-EXC-AUTH | PRODUCT_OWNER_DECISION | no | NON_BLOCKING_FAIL_CLOSED | A decided authority, then tests that only it can authorize and that every exception is audited. |
| PR-8-11-DISPOSITION | PRODUCT_OWNER_DECISION | no | BLOCKING | A Product Owner instruction per PR (merge, close as superseded, or rebase) and its execution by the Product Owner. |
| BRANCH-SYNC | PRODUCT_OWNER_DECISION | partly | NON_BLOCKING_FAIL_CLOSED | An authorized merge (or the PR #8-#11 disposition moving main) and a re-verification that the branch contains main. |
| OPS-HOLD-AUTH | PRODUCT_OWNER_DECISION | no | NON_BLOCKING_FAIL_CLOSED | A decided authority, a grant to exactly that role, and tests that every other role is refused. |
| OPS-DISP-AUTH | PRODUCT_OWNER_DECISION, LATER_OPERATIONAL_DEPENDENCY | no | NON_BLOCKING_FAIL_CLOSED | A decided authority matrix with requester != approver, an executor identity, and tests that self-approval is refused. |
| OPS-RETENTION-SCOPE | LATER_OPERATIONAL_DEPENDENCY | partly | LATER_PHASE | An implemented suppression ledger, a restore drill that re-applies suppression, and a verification report per disposition. |
| OPS-NOTIF-DELIVERY | LATER_OPERATIONAL_DEPENDENCY | yes | LATER_PHASE | A notification worker that re-checks authority and ownership generation in the delivery transaction, with tests for revocation and transfer between queueing and delivery. |
| REPO-HIST-CONTACTS | PRODUCT_OWNER_DECISION | no | NON_BLOCKING_FAIL_CLOSED | A recorded Product Owner decision; if B, a post-rewrite scan with zero history exceptions. |

## What this register deliberately does not do

- It does not close any item. Every status above is the status as found, not as wished.
- It does not convert a recommendation into an implementation. Where the code had to behave somehow in the absence of a decision, it refuses — and the refusal names the open question.
- It does not claim production readiness for anything held fail-closed or restricted to synthetic data under D-014.
- It does not treat a CONDITIONAL PASS, a green CI run, or this document as approval of Phase 2.
