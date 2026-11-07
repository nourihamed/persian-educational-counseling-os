# Architecture reconciliation crosswalk — Phase 2 (DRAFT, not approved)

**Status:** analysis and proposal only. It assigns **no** new decision identifiers, does not approve any schema, and does not claim implementation or test execution.
**Inputs (live GitHub, read on this reconciliation):**
- PR #8 `docs/phase2-database-domain-model` head `7d1ce9f` (DECISION_LOG D-025, D-026, D-027).
- PR #9 `docs/product-owner-decisions-2026-11-05` head `d72c401` (35 confirmed decisions, file `docs/PRODUCT_OWNER_DECISIONS_2026-11-05.md`).
- PR #10 `docs/workspace-centric-canonical-reconciliation` head `30cc32f` (6 canonical documents).
- PR #11 `docs/transfer-control-plane-architecture` head `ce20f5f` (`TRANSFER_CONTROL_PLANE_DECISION.md`, Option A accepted 2026-11-06).
- `main` `ba5e9d8`: DECISION_LOG highest identifier is **D-024**.

## 1. Identifier collision check

| Source | Identifiers present | Collision with main? | Note |
|---|---|---|---|
| main DECISION_LOG | D-001 … D-024 | — | highest = D-024 |
| PR #8 | D-025, D-026, D-027 | none with main | D-025 and D-026 are ACCEPTED; D-027 ACCEPTED 2026-10-31 |
| PR #9 | 35 choices, **no identifiers** | none | assigning numbers now would collide with unmerged work; see §3 |
| PR #11 | identifier **pending** | none | the document itself says so |

**Conclusion:** the first free identifier after the existing PR #8 items is **D-028**. No identifier is assigned here. Assignment requires Product Owner / supervisor approval of §3.

## 2. Precedence and supersession (current state)

| Earlier item | Newer item | Resolution |
|---|---|---|
| PR #8 **D-025** — registry is a database table in the Workspace DDL | PR #11 — the Control Plane registry is authoritative | **Superseded in its enforcement location.** The business rule (one active enrollment per canonical E.164 mobile + grade_10/11/12) stays in force. The local registry in `phase2_schema_draft.sql` must not be treated as a platform-wide guarantee (see §5). |
| PR #8 **D-026** — "admin or registered parent/guardian may initiate" | PR #9 decision 8 — initiators are parent/guardian, current counselor, or destination Workspace | **Partially superseded for the initiator list only.** The fee-confirmation prerequisite and "cannot bypass" rule stay in force. **Open conflict:** platform administrator initiation is in D-026 but not in decision 8. See OQ-A. |
| PR #8 **D-027** — one registered parent/guardian or legal guardian must consent | PR #9 decisions 8, 10 | Consistent. D-027 is a cumulative prerequisite. |
| PR #8 **Counselor-as-Tenant** data model (`tenants`, `counselors`, `counselor_students`) | PR #9 §3 and PR #10 — Workspace is the tenant | **Superseded.** The current DDL still uses `tenants` as the tenant root and must be reconciled (see §4). |
| Public individual ranking with parent opt-out (older preference) | PR #9 decision 33 | Superseded. Aggregate/anonymized only. |
| Optional MFA for high-risk roles (older wording) | PR #9 decision 23 | Superseded. Mandatory under the risk policy. |
| Deletion vs archival (older open choice) | PR #9 decision 1 | Controlled archival chosen. Retention durations still open. |

## 3. Crosswalk of PR #9's 35 confirmed decisions

Proposed identifiers are **proposals only** (D-028 … D-062, in the order of PR #9 numbering). They are not assigned. "Phase" is the phase in which the item is *designed*, not implemented.

| PR#9 | Choice | Subject | Proposed ID | Relation to PR #8 / #11 | Phase impact |
|---|---|---|---|---|---|
| 1 | C | Controlled archival of students | D-028 | — | Phase 2 domain (archival state, history) |
| 2 | C | Per-child parent access scope | D-029 | Q-007 remains open for the general matrix | Phase 2 design, Phase 4 enforcement |
| 3 | C | Multi-level capacity, independent of credit | D-030 | — | Phase 2 design; values open |
| 4 | C | One responsible counselor; ≤1 primary branch | D-031 | Enforced inside a Workspace (local) | Phase 2 local constraints |
| 5 | C | Organization owner + managers, permission-scoped | D-032 | Phase 2 membership design | Phase 2 design |
| 6 | B | Stable user ID; mobile is a mutable attribute | D-033 | Changes the D-025 key from identity to attribute | Phase 2 + Phase 4 |
| 7 | B | Enrollment state machine | D-034 | Replaces the active/ended-only model | Phase 2 domain |
| 8 | C | Initiators; cumulative approvals; atomic transfer | D-035 | **Partially supersedes D-026 initiator list** (OQ-A) | Phase 2 design; Control Plane |
| 9 | C | Manager access permission-scoped | D-036 | — | Phase 2 design, Phase 4 |
| 10 | C | Verified, proportionate guardian relationship | D-037 | Extends D-027 | Phase 4 (identity) |
| 11 | B | Counselor/branch changes need owner/manager + acceptance | D-038 | — | Phase 2 design |
| 12 | B | Reactivation requires checks; prefer new enrollment | D-039 | — | Phase 2 design |
| 13 | C | Category-based retention; no invented durations | D-040 | — | Open (retention) |
| 14 | C | Entitlements, credit, capacity are separate | D-041 | — | Phase 2 design |
| 15 | B | Debit after activation; atomic; reversal entries | D-042 | Credit ledger in PR #8 must add reversal semantics | Phase 2 |
| 16 | C | Content ownership classes; D-012 kept | D-043 | D-012 unchanged | Phase 2 design |
| 17 | B | Versioning for ProgramTemplate and StudentPlan | D-044 | Already in PR #8 DDL (partly) | Phase 2 |
| 18 | A | 404 vs 403 for cross-tenant objects | D-045 | — | Phase 4 API |
| 19 | A | Scoped, idempotent background jobs | D-046 | — | Phase 2/4 |
| 20 | B | Private object storage, signed URLs | D-047 | — | Later phase |
| 21 | B | UTC storage; Jalali display | D-048 | Calendar module | Later phase |
| 22 | B | Deterministic, versioned Risk Engine | D-049 | — | Later phase |
| 23 | C | Risk-based MFA; sessions inventoried | D-050 | Supersedes optional-MFA wording | Phase 4 |
| 24 | B | Auditing of security/finance/transfer events | D-051 | Audit table in PR #8 must be extended | Phase 2 |
| 25 | B | Provider-neutral notification core | D-052 | — | Later phase |
| 26 | B | Staged imports; separately authorized exports | D-053 | — | Later phase |
| 27 | B | Deterministic planning; counselor approval | D-054 | — | Later phase |
| 28 | B | Incremental test-analysis model | D-055 | — | Later phase |
| 29 | B | Explicit backlog; no unbounded carry-over | D-056 | — | Later phase |
| 30 | B | Provider-neutral hosting; Alt-5 kept | D-057 | D-020 kept | Pre-hosting |
| 31 | B | Layered backups; restore drills | D-058 | Q-023 gate | Pre-hosting |
| 32 | B | Platform admin least privilege, read-only MVP | D-059 | — | Phase 4 |
| 33 | C | Public statistics aggregated only | D-060 | Supersedes older ranking preference | Product rule |
| 34 | C | Configurable negative marking, snapshot kept | D-061 | Scoring snapshot is a Phase 2 table | Phase 2 |
| 35 | B | Real-data prohibition until gates + written PO authorization | D-062 | D-014 kept | Standing |

**Duplicates / overlap to resolve:** decision 6 changes the meaning of the D-025 key (identity → attribute). Decision 8 and PR #11 both define transfer; PR #11 is the mechanism. Decision 17 is the same requirement recorded in PR #9 §13.

## 4. Control Plane vs Workspace database responsibilities (proposal)

**Control Plane database (single, platform-level):**
- Stable Platform Student reference (identity, not mobile).
- Workspace registry (id, type, status).
- Current owner per student (Workspace id, ownership generation, lifecycle state).
- Global active-enrollment claim: unique on (canonical mobile, academic grade) where the claim is active. **Enforced here**, because only this database can see all Workspaces.
- Transfer cases, approval evidence references, state, idempotency keys, outbox/inbox.
- Audit references (not copies of educational data).

**Workspace database (one per Workspace, separate credential):**
- Local student profile and educational records.
- Local enrollment projection, carrying the ownership generation it was written against.
- Counselor responsibility, branches, membership, scoped roles.
- Program templates/versions, plans, credit wallet and append-only ledger.
- Staging area for incoming transfers.

**Constraint enforcement classes (to be used in every future document):**
1. *Control Plane DB constraint* — global uniqueness, single owner, generation compare-and-swap.
2. *Workspace DB constraint* — local integrity only (FKs within the Workspace, one responsible counselor per active enrollment within the Workspace, ledger append-only).
3. *Application authorization* — membership, scoped permissions, consent validity, identity from the authenticated session (Phase 4).
4. *Operational control* — backups, restore drills, key rotation, monitoring.

No invariant may be described as database-enforced if it exists only in classes 3 or 4.

## 5. Consequences for the existing PR #8 DDL (must be reconciled before review)

- `active_student_counselor_registry` in the Workspace DDL **cannot** enforce D-025 across Workspaces. It must be marked as a *local* guard only, and the global claim moved to the Control Plane draft.
- `tenants` / `counselors` / `counselor_students` must be reconciled to Workspace / Membership / CounselorAssignment (PR #9 §3, §4, §6).
- The fee-confirmation table (D-026) binds to a prior enrollment and a counselor account; it does not yet bind to a Control Plane transfer case. It must reference the transfer case when that exists.
- Credit ledger needs reversal entries (PR #9 decision 15) and must not use `actor_id` as authority.
- Audit log must cover transfers and permission changes (decision 24).

## 6. Mobile-number storage in the Control Plane (decision required)

The global uniqueness claim needs a mobile key. Two options, with consequences:

| Option | How | Pros | Cons |
|---|---|---|---|
| **P — plaintext E.164 central column** | Store canonical E.164; unique index on (mobile, grade) | Simple; enforceable uniqueness; easy audit | Central plaintext personal data; a single breach exposes every number; retention/deletion must cover it |
| **K — keyed deterministic pseudonym** | Store HMAC-SHA-256(key_version, E.164) plus encrypted E.164 for contact; unique on (hmac, grade) | Uniqueness still enforced by index; plaintext not present in the lookup index | Key management and rotation; rotation needs re-keying the index; key compromise enables offline guessing of the small phone space unless the key is held separately; more moving parts |

**Recommendation (not chosen):** K, with the HMAC key held outside the database (KMS/HSM class), versioned, and a documented rotation procedure. Re-keying cost and the threat model must be reviewed before selection. **Product Owner / security decision required.** Until then the Control Plane draft keeps both columns out of production use.

## 7. Transfer state machine (summary of PR #11, to be detailed in the draft)

States proposed: `requested` → `approvals_pending` → `approved` → `preflight_ok` → `staging` → `staged_verified` → `cutover_frozen` → `ownership_switched` → `projections_finalizing` → `completed`; plus `cancelled`, `failed_recoverable`, `manual_intervention`.
Only the `ownership_switched` transition is a single Control Plane transaction (compare-and-swap of source workspace and generation). After it, recovery proceeds forward; reversal requires a separately authorized transfer.

## 8. Required test contracts (not executed)

Listed in the mission document, section 10. Each is `SPEC-ONLY` until implemented and run against the exact reviewed commit:
concurrent mobile+grade claims across Workspaces; single owner; concurrent transfer requests; stale generation rejection; registry unavailable → fail closed; crash before/after switch; duplicate/out-of-order events; idempotency key reuse with different payload; staging failure; source writes racing cutover; delayed source jobs; missing/revoked/expired guardian consent; missing fee confirmation; missing destination acceptance; former counselor and unrelated Workspace denial; parent isolation across children and Workspaces; no automatic transfer of private notes; no duplicate credit debit; capacity under concurrency; audit completeness and stuck-workflow recovery.

## 9. Open questions requiring a Product Owner decision

- **OQ-A:** Is platform administrator initiation of a transfer permitted? (D-026 says yes; decision 8 does not list it.)
- **OQ-B:** Mobile-number storage option P or K (§6), and the key-management owner.
- **OQ-C:** Approve the proposed identifiers D-028…D-062 (§3) and the supersession rules (§2).
- **OQ-D:** Registry topology, HA and recovery objectives (PR #11 open list).
- **OQ-E:** Snapshot-plus-final-delta vs freeze-based cutover (PR #11 §5 step 5).
- **OQ-F:** Legal parameters: guardian verification evidence by age and jurisdiction; retention durations; capacity values.
- **OQ-G:** Q-007 general parent permission matrix (still open).

## 10. What is NOT done by this document

- No schema changes. No Control Plane DDL. No tests run.
- No decision identifiers assigned.
- No canonical document (DECISION_LOG, OPEN_QUESTIONS, PROJECT_STATE, TEST_PLAN, SUPERVISOR_REVIEW) edited.
- Phase 2 Gate remains **NOT READY**. Phase 3 not started. Real student data not authorized.

## 11. Update 2026-11-07 — status after PR #12 product decisions

Source: PR #12 `docs/PRODUCT_OWNER_DECISIONS_2026-11-07.md` (head `b017ef6`).

| Item | Status now | Note |
|---|---|---|
| OQ-A Platform Admin initiation | **ACCEPTED (Option A)** | Admin cannot initiate. Admin may only file a support/administrative review request, which does not bypass approvals. Supersedes only the D-026 initiator statement. |
| OQ-B mobile protection | **ACCEPTED (Option K)** | E.164; encrypted recoverable value in Control Plane; keyed HMAC index. Keys held by Platform Security, never in DB/code/Git. |
| OQ-C numbering | **ACCEPTED (Option A)** | Crosswalk before assignment. D-028 onward are still NOT assigned. |
| OQ-D topology | **ACCEPTED (Option A)** | Independent Control Plane, primary + replica, independent encrypted backups, restore drills, fail-closed. RPO/RTO open. |
| OQ-E cutover | **ACCEPTED (Option B)** | Controlled freeze + final snapshot; snapshot+final-delta NOT selected for MVP. Freeze duration open. |
| OQ-F1 legal | **ACCEPTED (Option A)** | Iran-only MVP legal workflow; architecture extensible. Evidence requirements pending legal review. |
| OQ-F2 retention | **ACCEPTED (Option A)** | Category-based, versioned; no numeric durations approved. |
| OQ-F3 capacity | **ACCEPTED (Option A)** | Independently configurable; provisional pilot cap ≤10 Workspaces, ≤2 per cell — not capacity evidence. |
| OQ-G / Q-007 parent access | **HIGH-LEVEL POLICY ACCEPTED; Q-007 remains OPEN** | Detailed age-based matrix and legal exceptions still open. |

Crosswalk status of PR #8 items:
- D-025 — business rule in force; enforcement location moves to the Control Plane (`docs/phase2/control_plane/`).
- D-026 — in force except the initiator list, superseded by OQ-A.
- D-027 — in force (cumulative guardian consent).

No new decision identifier is assigned by this update.
