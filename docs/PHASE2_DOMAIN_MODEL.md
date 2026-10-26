# PHASE 2 — Database & Domain Model (v2)

**Status: DESIGN DRAFT — NOT APPROVED. Pending independent review (PR #8).**
This document describes intent. The authoritative *executed* evidence is in
`docs/phase2/evidence/test_run_v2_2026-10-25.txt`, and only for the scope listed in §9.
No runtime security (Alt-5 cells, RLS, hosting) is established by anything here (D-020/D-023, Q-023).
Synthetic data only (D-014).

Sources: Issue #7; `DATABASE.md`; D-008 (version policy), D-012 (tenant-owned templates),
D-014, D-020, D-023; Q-007 (parent access, open); Q-023 (hosting gate, open).

---

## 1. Tenancy

- **Tenant** = one counselor account (`tenants`). Every tenant-owned table has `tenant_id NOT NULL`.
- Cross-tenant references use composite foreign keys `(tenant_id, id)`, so a child cannot point at another tenant's parent. Enforced in the DDL and tested (T2-TI-01..08).
- Platform catalog is out of MVP (D-012): no nullable-tenant template or version rows.
- Tenant identity is resolved server-side (application concern, Phase 4). The DDL does not implement authorization.

## 2. Entities (mapped to DDL tables)

| Group | Tables | Key rules |
|---|---|---|
| Tenancy | `tenants`, `counselors`, `students`, `student_profiles`, `counselor_students` | At most one *active* counselor relationship per student per tenant (partial unique). |
| Curriculum | `subjects`, `curriculum_nodes` | Node level ∈ grade/book/chapter/topic/subtopic; parent must be same tenant. |
| Programs (D-008/D-012) | `program_templates`, `program_versions`, `student_program_enrollments` | Versions immutable once published (§4.1). Enrollments reference a published/superseded version only. |
| Planning (D-008) | `plans`, `plan_versions`, `plan_items` | Activated versions and their items are frozen (§4.2). |
| Activities | `activities` (base) + `study_sessions`, `test_records`, `review_schedules` (type tables), `error_records` | Type tables bind to the base row by `(tenant_id, id, activity_type)`. Test sum rule `correct + wrong + unanswered = question_count`. |
| Exams & school | `exams`, `exam_results`, `class_sessions`, `assignments` | Result uniqueness per (exam, student, subject) including NULL subject. |
| Credit ledger (§45) | `student_credit_accounts`, `credit_transactions`, view `credit_reconciliation` | Single write path `post_credit_transaction()` (§5). |
| Audit | `audit_logs` | `scope` = platform (tenant NULL) or tenant (tenant set) — §6. |

## 3. Reconciliation of domain document and DDL (P2-M03)

Every mismatch found in v1 and how it was resolved. "Contract" means the DDL and this document now agree.

| Item | v1 state | Resolution in v2 | Rationale |
|---|---|---|---|
| `counselors.user_id`, `students.user_id` | Missing in DDL | Added as nullable `uuid`, **no FK** | Users/auth table is Phase 4. Deferred FK is explicit. |
| Subject `category`, `importance`, `sort_order` | Missing | `category` (nullable text) and `sort_order` added. **`importance` deferred** | Values for `importance` are not defined by any requirement; inventing them is out of scope. |
| Template status | Doc said draft/active/archived; DDL said active/archived | **Contract: `active` / `archived`** | A template is not versioned by a draft state; drafts are `program_versions` rows. Doc updated. |
| `created_by`, `published_by`, `enrolled_by` | Missing in DDL | Added to the relevant tables (nullable, no FK until Phase 4) | Actor attribution required by D-008. |
| `payload` vs `payload_json` | Mismatch | **Contract: `payload_json`** | Matches doc. |
| `curriculum_node_id` on plan items | Missing | Added (nullable, composite FK) | Matches §4.4. |
| `rationale` vs `rationale_json` | Mismatch | **Contract: `rationale_json`** | Matches doc; explainability §68. |
| Review schedule fields | Partial | Added `method`, `mastery_before/after`, `result`, `notes` | Matches doc. |
| Credit `order_id`, `actor_id` | Missing | Added as nullable `uuid`, **no FK** | No orders/payments tables in Phase 2 (billing deferred). |
| `activity_type` on plan_items | Free text | CHECK enum including `custom` | Doc §21 lists the types; `custom` is in §21. |
| `counselor_students.access_level` | Documented, missing | **Deferred** | Value set is not defined in the authoritative sources. Adding it would invent a permission model; related to Q-007. |
| `audit_logs.tenant_id` nullable meaning | Implicit | Explicit `scope` column + CHECK (§6) | P2-M04. |
| `activities` types | Doc listed 18 types | DDL base supports `study`, `test`, `review` only | Other activity types become type tables in later phases; Phase 2 covers the entities required by the supervisor list. |

Entities **not** in the DDL and deferred (with reason):

- `users`, `roles`, `permissions`, `parents`, `parent_student_links`: Phase 4 / Q-007.
- `orders`, `payments`, `invoices`, `products`, `subscriptions`, `coupons`, `promotions`: billing and payment phases; D-010 limits MVP billing depth.
- `billing_plans` (D-006 naming): proposal, not accepted.
- `market_segments`, `program_template_segments`: MVP segment model not decided.
- `progress_snapshots`, `risk_assessments`: derived analytics; formulas and inputs require their own decision (Master §35, §38).
- `notifications`, `notification_deliveries`, `telegram_*`, `sms_*`: later phases.
- `coupons`, `promotions`: later billing phase.

## 4. Lifecycle rules (enforced in DDL)

### 4.1 Program versions (P2-H02)

| From → To | Allowed | Notes |
|---|---|---|
| draft → draft | Yes | Payload may change. |
| draft → published | Yes | Requires `published_by` and `published_at` (CHECK). |
| published → superseded | Yes | Status only; payload, publisher, and time frozen. |
| published → draft / published → published (with change) | **No** | Illegal transition / content immutable. |
| draft → superseded | **No** | Skips publication. |
| superseded → any | **No** | Terminal. |
| DELETE | Draft only | Published/superseded rows never deleted. |
| Identity (`id`, `tenant_id`, `program_template_id`, `version_number`, `created_by`, `created_at`) | **Immutable in every state** | Enforced by trigger; no reliance on FK for identity. |
| TRUNCATE | **No** | FK-referenced table: PostgreSQL refuses (0A000). |

New template edits never change existing enrollments (T2-VER-14). Moving a student to a new version is an explicit new enrollment (O-6, still a proposal).

### 4.2 Plan versions and items (P2-H03)

- `plan_versions`: identity and origin (`id, tenant_id, plan_id, version_number, program_version_id, created_by, created_at`) immutable.
- Draft (`activated_at` NULL): items may change; version may be deleted.
- Activated (`activated_at` set): `activated_at` frozen; **items frozen** (no insert/update/delete); no delete.
- Supersession: `superseded_at` may be set once after activation, then frozen.
- At most one active (activated, not superseded) version per plan (partial unique).
- `plan_items`: `(id, tenant_id, plan_version_id)` immutable; writable only while the parent is not activated.

## 5. Credit ledger (P2-H01, P2-H05)

- `credit_transactions` is append-only: UPDATE, DELETE, and TRUNCATE are forbidden by trigger (tested for owner and runtime role).
- `student_credit_accounts.balance` is a **cache** of `SUM(amount)` with `balance >= 0` (CHECK).
- **Single write path:** `post_credit_transaction()` (SECURITY DEFINER). In one transaction it: locks the tenant's account row (`FOR UPDATE`), replays an identical idempotent request with no second effect, rejects a reused key with a different payload, rejects overspend, and writes ledger and balance together. The caller's transaction controls atomicity with other work (e.g., creating a student).
- The runtime role has **no** INSERT/UPDATE/DELETE/TRUNCATE on either table and cannot disable triggers (tested, T2-PRIV-01..05).
- `credit_reconciliation` view exposes `drift = cached − ledger_sum`. It **detects** owner-level tampering (T2-CR-12); it does not **prevent** it.
- **Guarantee boundary:** the owner (superuser/table owner) can still bypass triggers and write directly. Preventing that requires deployment controls (separate owner role, no superuser in the app path) that are **not** implemented or verified here. Marked **UNVERIFIED — deployment-dependent**.
- **O-2 (cached vs derived balance) is NOT decided.** The cache is used because the atomic function keeps it consistent and the reconciliation view checks it. A derived-only design would remove the cache and is an open alternative.

## 6. Audit (P2-M04)

- `audit_logs.scope ∈ {platform, tenant}`.
- CHECK: `(scope = 'platform') = (tenant_id IS NULL)`. A NULL tenant is valid only with platform scope; tenant scope must name its tenant.
- Append-only (UPDATE, DELETE, TRUNCATE forbidden).
- Who may write platform-scope events is an authorization decision (Phase 4). This schema does not expand platform-admin permissions (D-013).

## 7. Indexes (P2-L01)

**Mandatory now (created by constraints):** every tenant-owned unique key `(tenant_id, id)`; uniqueness keys for versions, one-active-version, one-active-counselor, review duplicates, idempotency, and results with NULLS NOT DISTINCT.

**Created now (justified):** `credit_transactions(tenant_id, created_at)` for ledger history reads.

**Deferred until query patterns and measurements exist:** student timelines on `activities(tenant_id, student_id, occurred_on)`, dashboard aggregates, foreign-key child-side indexes for deletes, and any index for counselor list filters (Master §34). Each adds write and storage cost; none is added speculatively.

## 8. Open decisions (all remain PROPOSALS unless stated)

| ID | Question | Status |
|---|---|---|
| Q-007 | Parent access model | **OPEN — Product Owner.** Blocks parent grant table and parent visibility. |
| O-1 | Tenant = counselor account 1:1? | Proposal. |
| O-2 | Cached balance vs derived-only | Open. Current draft uses cache + atomic function + reconciliation. |
| O-3 | Consume immediately vs reserve/confirm | Proposal: consume in the same transaction as student creation. |
| O-4 | Activity base + type tables vs single polymorphic table | Proposal implemented (base + type tables). |
| O-5 | Allow test-record sum override? | Open. Strict in DDL; no override modelled. |
| O-6 | Template update vs existing plans | Proposal: explicit re-enrollment only. |
| O-7 / D-006 | Rename commercial `Plan` → `BillingPlan` | Proposal, not accepted. |
| O-8 / Q-020 | Retention duration and responsible persons | Open; pre-pilot gate. |
| O-9 | One active program enrollment per student | **Proposal, enforced by partial unique index.** A constraint does not prove the business rule is accepted. |
| Q-023 | Hosting topology / provider gate | Open; hard pre-hosting gate. Unchanged. |

## 9. Execution status (P2-M05)

Seven categories, kept separate:

1. **Design specified:** this document, §§1–8.
2. **SQL draft authored:** `phase2_schema_draft.sql` (v2), `phase2_roles_setup.sql` (test-only role).
3. **SQL actually executed:** yes, on local PostgreSQL 16.15 (fresh database), `ON_ERROR_STOP=1`, exit 0.
4. **Tests actually executed:** 87 PASS notices (including 2 fixture lines), 0 FAIL; 3 concurrency checks PASS (two parallel sessions each). Evidence: `docs/phase2/evidence/test_run_v2_2026-10-25.txt`.
5. **Author-reported evidence:** the above, produced by the author in a sandbox. Not independently reproduced.
6. **Independently reproduced evidence:** **none yet.** Pending independent reviewer.
7. **Runtime security not implemented or verified:** cell isolation (D-020/D-023), RLS, hosting, production role provisioning, backups/restore, owner-level prevention, and all application/API authorization.

**Not executed:** RLS; API/app authorization; migrations (Alembic); production roles; backup/restore; concurrent tests beyond the three listed; a mutation/negative control that proves the concurrency test fails when the lock is removed (not run); a property-based test beyond one seeded sequence.

The earlier v1 evidence (32 PASS) is superseded by v2 and is kept only as history; it does not describe the current DDL.

## 10. Phase gates

- Phase 2 is **not approved**. Independent review is pending.
- Phase 3 is **not** started or authorized.
- Real student data remains prohibited (D-014). Q-023 remains a hard pre-hosting gate.

---

## 11. Targeted security remediation P2-R01..R04 (supersedes §5 where they differ)

Full report: `docs/phase2/SECURITY_REMEDIATION_R01_R04.md`.

- **Authorization (P2-R01):** a credit operation requires that `session_user` is bound to the tenant (`tenant_role_bindings`) and holds the permission for the `kind` (`credit_role_permissions`). Both are checked before any lock or write. Caller-supplied `actor_id` and `reason` are audit data only.
- **Idempotency (P2-R02):** the canonical payload is `(kind, amount, student_id, order_id, actor_id, reason)`, compared NULL-safe. Any difference is rejected with `unique_violation`.
- **SECURITY DEFINER (P2-R03):** `search_path = pg_catalog, pg_temp`; all objects schema-qualified; no PUBLIC EXECUTE; EXECUTE only for runtime roles that need it; runtime roles are not superusers. The owner is trusted in the test environment; production owner separation is not verified.
- **Concurrency (P2-R04):** lock removal is detected by the harness, which checks the exact failure reason. Overspend is still prevented by the `CHECK (balance >= 0)` constraint; the lock governs error semantics and idempotent replay.
- **Reads:** runtime roles have no table or view read grants. Cross-tenant read protection beyond this is deferred (RLS or API scoping).
- The statements in §§1–10 above that describe v2 behaviour are superseded for v3.
