# Unresolved-item register — Phase 2

**Date:** 2026-11-14
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
| WS-DOM-05 | Curriculum Book/Edition, successor mapping, content ownership | OPEN | MEDIUM (correctness, isolation later) | Yes, subtopics built | Product Owner + content licensing owner |
| WS-PLAN-01 | Normalized PlanItem versus opaque `plan_content` JSON | OPEN | HIGH for the product promise | Yes, versioning built | Product Owner |
| WS-ISO-01 | Counselor-to-counselor isolation inside one Workspace | OPEN | HIGH | Yes, negative result asserted | Product Owner + architecture owner |
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
| M-05 | Supervisor finding — text never supplied | OPEN | UNKNOWN | Yes, not claimed addressed | Supervisor |
| M-06 | Supervisor finding — text never supplied | OPEN | UNKNOWN | Yes, not claimed addressed | Supervisor |
| WS-DOM-02 | Role source of truth and trusted authorization | PARTIALLY DECIDED | HIGH | Yes, fail-closed | Platform Security + Product Owner (Issue #13) |
| TRANSFER-EXC-AUTH | Who may authorize an approval-conflict exception | OPEN | HIGH | Yes, exception impossible to enable | Product Owner |
| PR-8-11-DISPOSITION | Disposition of PR #8–#11 | OPEN | Process only | Yes, no PR touched | Product Owner on Supervisor advice |
| BRANCH-SYNC | Is the PR #12 branch behind main? | **FACTUALLY CORRECTED** | None | Yes | Product Owner |

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

### WS-ISO-01 — Counselor-to-counselor isolation inside one Workspace
**Status:** OPEN. The Supervisor brief requires: *"No counselor may access another counselor's students,
even within the same Organization."* **The database does not enforce this, and cannot today.**
**Measured on 2026-11-15:** there is **no row-level security on any table** in the Workspace database, and
the Workspace runtime role holds `SELECT` on **47 tables in full**. Isolation in this design is
**per-Workspace** — one database per Workspace with no cross-database grants, which the cross-database
denial step does test — so every counselor inside a Workspace shares one runtime identity.
**Impact:** HIGH. It is an explicit requirement of the brief and the one isolation claim this database
cannot currently support. Until it is decided and built, any statement that counselors are isolated from
one another rests entirely on application code that does not exist in this repository.
**Held how:** **SEC-10 records the negative result as a test, not as prose**, and fails if the situation
changes in either direction, so the record cannot silently rot. Per-Workspace isolation is implemented and
tested. Counselor-to-counselor isolation is claimed nowhere, and `PHASE2_EXIT_CRITERIA.md` records it as
NOT IMPLEMENTED.
**Options:** (A) row-level security on the student-scoped tables, keyed to the responsible counselor
assignment; (B) one database role per counselor, so the boundary is a grant rather than a policy;
(C) enforce it only in the application authorization layer and say so plainly; (D) allow shared visibility
inside a Workspace by policy and narrow the requirement to the Organization boundary.
**Recommendation: A.** It keeps the boundary inside the database, where a new query path cannot forget it,
and it matches how this project already treats authorization — the write barrier and the ledger guard are
triggers precisely because a check in application code binds only the callers that remember it. The hard
part of (A) is the session identity: the database must **not** take the counselor's identity from a GUC the
application sets, because this project already rejected session GUCs as an authorization mechanism in
finding H-03. It would need the same privilege-backed, transaction-scoped grant pattern used for receipt
consumption. (B) does not scale to many counselors per Workspace. (C) is the current de facto state and is
acceptable only if written down as such. (D) changes the requirement, which is the Product Owner's call and
not the implementation's.

### OQ-D — Control Plane topology and recovery
**Status:** PARTIALLY DECIDED (Option A accepted): independent infrastructure, primary plus replica, independently controlled encrypted backups with restore drills, and student access fail-closed when ownership cannot be validated.
**Still open:** RPO, RTO, retention, failover consistency, split-brain prevention, and measured capacity and cost.
**Impact:** HIGH at operation, not at schema. With no split-brain rule, two Control Plane primaries could each grant ownership.
**Held how:** Phase 2 produces schema and commands only — no deployment, no replication configuration, no availability claim. The fail-closed ownership rule is implemented.
**Options:** (A) set RPO/RTO now from business tolerance; (B) measure a representative workload first; (C) defer to Phase 28.
**Recommendation: B for the numbers, but decide split-brain prevention earlier.** Inventing SLOs is forbidden and numbers set without measurement are either unachievable or meaningless — but split-brain prevention constrains the design, so it should not wait for Phase 28.

### OQ-E — Transfer cutover: freeze boundary, duration, recovery, thresholds
**Status:** PARTIALLY DECIDED (Option B accepted): controlled source write freeze, final snapshot, destination staging and import, integrity validation, then the atomic Control Plane ownership switch. Freeze duration, the precise freeze boundary, failure recovery and acceptance thresholds were explicitly left to detailed design and tests.
**What changed on 2026-11-14:** the **database half of the freeze boundary is now implemented and tested** — `docs/phase2/workspace/workspace_transfer_freeze.sql` adds a durable freeze record, a write barrier on all 27 student-scoped tables, an in-flight transaction barrier with a recorded watermark, and a permanent fence once the source observes the switch. Before this, the Control Plane recorded that a freeze had happened and the Workspace database enforced nothing, so a source Workspace could keep writing a student straight through cutover.
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

### M-05 and M-06
**Status:** OPEN, and **not actionable by the implementation.** Both are referenced in the Supervisor review material, but their text was never supplied. One reference associates M-06 with load-scenario order and an L-10 dependency; that is not a definition to implement against, and `SUPERVISOR_REVIEW.md` is Supervisor-owned and must not be edited here.
**Why they are not guessed:** inventing a finding's content would be inventing the finding. Neither is claimed as addressed anywhere in this project's documentation.
**Impact:** UNKNOWN — it cannot be assessed without the definitions.
**Options:** (A) supply the finding text; (B) withdraw if superseded; (C) restate against the current head.
**Recommendation: C.** The head has moved substantially since they were raised, so a restatement is both actionable and avoids work on something that may already be fixed.

---

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

### BRANCH-SYNC — Is the PR #12 branch behind `main`?
**Status: FACTUALLY CORRECTED.** The claim carried in `PROJECT_STATE.md` and in earlier implementation reports — that PR #12 is behind `main` and needs to be brought up to date — **is not true at the current head.**

Measured on 2026-11-14:

```
main tip:                 ba5e9d8a9577e5b87e2fc27caaf0bfb07f929114
PR #12 head:              ad3bf2888cae567d8a6eca7d4bd7f3dc100aa979
git merge-base --is-ancestor ba5e9d8 HEAD   -> exit 0 (ancestor)
```

So the PR #12 branch already contains all of `main`, and there is nothing to synchronize. The item stays in the register rather than being closed, because the decision on PR #8–#11 may move `main`, and a rebase would then need an explicit instruction (rebasing and force-pushing are otherwise forbidden).

**Recommendation: A — leave the branch as it is;** revisit only if `main` moves.

---

## What this register deliberately does not do

- It does not close any item. Every status above is the status as found, not as wished.
- It does not convert a recommendation into an implementation. Where the code had to behave somehow in the absence of a decision, it refuses — and the refusal names the open question.
- It does not claim production readiness for anything held fail-closed or restricted to synthetic data under D-014.
- It does not treat a CONDITIONAL PASS, a green CI run, or this document as approval of Phase 2.
