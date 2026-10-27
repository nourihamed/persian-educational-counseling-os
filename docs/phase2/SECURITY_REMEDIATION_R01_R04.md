# Phase 2 — Targeted Security Remediation (P2-R01 to P2-R04)

Status: **remediation candidate for independent re-review. NOT approved. Phase 2 remains PENDING independent review.**
Base: PR #8, reviewed HEAD `5e78384`. Branch `docs/phase2-database-domain-model`.
Scope: Phase 2 database design and its tests only. No application/API authentication, RLS, production roles,
migrations, hosting, Alt-5 cell isolation, or backup/restore is implemented or claimed here.
Data: **synthetic only** (D-014). No real student or customer data was used.

---

## 1. Finding-by-finding status

| Finding | Verified condition (before) | Fix (after) | Regression tests | Execution |
|---|---|---|---|---|
| **P2-R01** authorization for credit operations | Any role with EXECUTE on `post_credit_transaction()` could post any kind for any tenant; no notion of actor authority. | Authorization data (`tenant_role_bindings`, `credit_role_permissions`) checked first, against `session_user`. Matrix in §2. Runtime roles: no table privileges, no cross-tenant reads, cannot self-grant. | T2-R01-01..18 | EXECUTED, PASS |
| **P2-R02** idempotency payload | Replay compared only `kind`, `amount`, `student_id`. `order_id`, `actor_id`, `reason` ignored, so a replay with different order/reason returned the old ID. | Canonical payload = (`kind`, `amount`, `student_id`, `order_id`, `actor_id`, `reason`), NULL-safe, all-or-nothing. §3. | T2-R02-00..08, T2-CR-04b, T2-CR-04c | EXECUTED, PASS |
| **P2-R03** SECURITY DEFINER boundary | `search_path = public, pg_temp` (resolvable by a caller-controlled schema placed first); PUBLIC could execute by default; unqualified object names. | `search_path = pg_catalog, pg_temp`; all objects schema-qualified; PUBLIC has no EXECUTE and no schema CREATE; EXECUTE only to the four roles that need it; runtime roles are NOSUPERUSER. §4. | T2-R03-01..08 (incl. hostile `search_path` + hostile `gen_random_uuid()`) | EXECUTED, PASS |
| **P2-R04** mutation testing for concurrency | No mutation test; v2 harness did not check *why* the losing session failed, so a broken lock could still pass. | Lock removed in a disposable mutant DB. Harness now checks the exact failure reason. Mutation detected. §5. | `run_mutation.sh`; T2-CR-04/04b/04c | EXECUTED, mutation DETECTED |

Known consequence (honest): with the lock removed, **balance integrity is still held by the `CHECK (balance >= 0)` constraint**, not by the function's logic. The lock is required for the deterministic business error, for correct idempotent replay, and to avoid relying on a constraint for correctness. The mutation test shows the difference in behaviour, not a silent overspend.

---

## 2. Authorization matrix and trust boundary (P2-R01)

Authorization data (tables, owner-writable only):

| Role (session identity) | Tenant binding | Permitted `kind` values | Intended holder |
|---|---|---|---|
| `app_t1` | tenant 1 | `activation_consume` | ordinary runtime, tenant 1 |
| `app_t2` | tenant 2 | `activation_consume` | ordinary runtime, tenant 2 |
| `issuer_rt` | tenant 1 | `purchase` | verified-payment handler (stand-in) |
| `adjuster_rt` | tenant 1 | `refund`, `cancellation_release`, `adjustment` | privileged support/finance path (stand-in) |
| `nogrant_rt` | none | none, no EXECUTE | default-deny control |
| `postgres` (owner) | tenants 1, 2 (and 9–11 in concurrency runs) | all five | **trusted** owner, explicit seed rows (not a bypass) |

Rules enforced in `post_credit_transaction()` **before** any lock or write:
1. `session_user` must be bound to `p_tenant`. Otherwise `insufficient_privilege` (42501, "is not bound to tenant").
2. `session_user` must hold permission for `p_kind`. Otherwise 42501, "may not perform ...".

Trust boundary:
- **Trusted:** the authenticated database session identity (`session_user`) and the authorization tables (writable by owner only).
- **Untrusted, recorded for audit only:** `p_actor`, `p_reason`, `p_student`, `p_order`. None of them grants authority. A caller that supplies another actor's UUID gains nothing; the permission check uses the session identity.
- `current_user` is **not** used for authorization: inside a `SECURITY DEFINER` function it becomes the owner. (Probed on PostgreSQL 16.15: `session_user` stayed `app_t1` while `current_user` became `postgres`.)

What the database **cannot** do (stated as limitations, not as guarantees):
- It cannot verify a payment. `issuer_rt` is a role, not proof of payment. The application or payment adapter must verify the provider event (signature, amount, idempotency) **before** calling the purchase path. This is Phase 22 work.
- It cannot decide who a support user is. The mapping of humans to `adjuster_rt` is application/IAM work (Phase 4).
- The test model binds one role per tenant inside one database. The approved production model (D-020) uses a separate database and credential per tenant inside a cell; that is **not** verified here.

Open product decisions this matrix depends on (not decided here):
- Who may issue purchase credit, and whether refunds must reference an order (proposal O-10, not accepted).
- Whether `adjustment` requires two-person approval.

---

## 3. Canonical idempotency payload (P2-R02)

Canonical payload: **`kind`, `amount`, `student_id`, `order_id`, `actor_id`, `reason`**. Every field is compared with `IS NOT DISTINCT FROM`, so NULL vs value is a difference.

| Field | Included | Reason |
|---|---|---|
| `kind` | yes | changes the business meaning |
| `amount` | yes | changes the balance |
| `student_id` | yes | changes which student is charged |
| `order_id` | yes | links the effect to a commercial event |
| `actor_id` | yes | audit attribution; a replay by a different actor is a different request |
| `reason` | yes | required for adjustments; a different reason is a different request |
| `tenant_id` | implicit | part of the unique key `(tenant_id, idempotency_key)` |
| `created_at` | excluded | server-generated, not part of the request |

Semantics:
- Identical canonical payload → returns the existing transaction ID, **one** ledger row, **no** second balance change.
- Same key, any different canonical field → `unique_violation` (23505), "idempotency_key reused with a different canonical payload". No ID is returned.
- Authorization is checked **before** idempotency, so an unauthorized caller cannot probe existing keys.
- Under concurrency, the account row lock serialises requests, so the second request sees the committed row and takes the replay or rejection path (T2-CR-04b, T2-CR-04c).

---

## 4. SECURITY DEFINER boundary (P2-R03)

Owner: `postgres` in the test environment, **explicitly trusted**. Production requires a dedicated non-superuser owner, separate from every runtime role. That is **deployment work and not verified here**.

| Control | Implementation | Test |
|---|---|---|
| Pinned, safe `search_path` | `SET search_path = pg_catalog, pg_temp` | T2-R03-07 (hostile first-path schema with a fake `gen_random_uuid()` is ignored) |
| Qualified object references | every table, view, and function in the body is `public.`-qualified except `pg_catalog` built-ins | T2-R03-08 (hostile fake table untouched) |
| No PUBLIC execution | `REVOKE ALL ON ALL FUNCTIONS IN SCHEMA public FROM PUBLIC`; `has_function_privilege('public', …)` = false | T2-R03-01 |
| Least EXECUTE | granted to `app_t1, app_t2, issuer_rt, adjuster_rt` only | T2-R01-18 (`nogrant_rt` denied) |
| No schema CREATE for PUBLIC | `REVOKE ALL ON SCHEMA public FROM PUBLIC`; PostgreSQL 15+ default also denies | T2-R03-02, T2-R03-03 |
| Untrusted roles cannot replace the function | `CREATE OR REPLACE` by runtime role | T2-R03-04 |
| Untrusted roles cannot alter/drop authorization or credit tables | ownership check | T2-R03-05, T2-R03-06 |
| Untrusted roles cannot self-grant | no INSERT on authorization tables | T2-R01-11, T2-R01-12 |
| Runtime roles are not superusers | `NOSUPERUSER` by role setup; checked | T2-R03-01b |
| Function still works after hardening | authorized consume and purchase paths | T2-R01-01, T2-R01-14, T2-R01-16 |

Remaining risks in this area (not verified):
- A superuser owner can disable triggers, replace the function, or read everything. Mitigation is deployment (non-superuser owner, separate roles, audit of DDL), not SQL.
- `SECURITY DEFINER` functions are only as safe as their inputs. The authorization check is the first statement; all inputs are typed and checked.

---

## 5. Mutation test for concurrency guarantees (P2-R04)

Method (`docs/phase2/concurrency/run_mutation.sh`):
1. Read the canonical schema (not modified). Assert exactly one lock site (`WHERE tenant_id = p_tenant FOR UPDATE;`).
2. Generate a mutant copy in a temp directory with the lock removed.
3. Load the mutant into a disposable database `p3_mutant`, using the same roles file.
4. Run the full concurrency harness against it.
5. **Pass condition:** the harness must exit non-zero and report `FAIL T2-CR-04`. Anything else means the test is not sensitive to the lock, and the script exits 1.

Harness improvements made for this (they were needed, not cosmetic):
- Each losing session's failure **reason** is checked (`insufficient credit`, `different canonical payload`, `unique`). Before this, a session failing for an unrelated reason still passed.
- Fixture errors abort with exit 2; no `2>/dev/null` hides failures. Each session's exit code is captured from its own process.
- Logs are per-run `mktemp` files, so runs do not share state.

Observed result on the mutant (`docs/phase2/evidence/test_run_v3_2026-10-25.txt`):
- T2-CR-04 **FAIL**. Session B failed with `new row for relation "student_credit_accounts" violates check constraint` (the CHECK, not the function's business check).
- T2-CR-04b **FAIL**. The second identical request failed with a unique violation instead of an idempotent replay.
- T2-CR-04c **FAIL**. The different-payload request failed with a unique violation on the key, not with the canonical-payload message.
- T2-VER-02 PASS (its unique key does not depend on the account lock).
- Canonical schema hash identical before and after the mutation run; the restored canonical run PASSES.

---

## 6. Tests executed, not executed, residual risks

**Executed (one full run of `run_all.sh`, exit 0; PostgreSQL 16.15; fresh databases):**
- **Latest (v5, `evidence/test_run_v5_2026-10-26.txt`):** constraint, privilege and authorization suite: **111 test-case PASS** plus **2 fixture acceptance PASS**, **0 FAIL**, `ON_ERROR_STOP=1`, exit 0. (The earlier "113 PASS notices" figure from v3/v4 is the same run count, not a separate result.)
- Concurrency on canonical schema: T2-CR-04, T2-CR-04b, T2-CR-04c, T2-VER-02 PASS.
- Mutation: lock removal **detected**.
- Restoration: schema hash unchanged; concurrency PASS again.

**Not executed:**
- RLS (not in scope; no row-level policies exist).
- Application/API authorization, identity provider, session management (Phase 4).
- Production roles, credentials, owner separation, backup/restore, Alt-5 cell isolation, hosting (Q-023 remains a hard pre-hosting gate).
- Migrations (Alembic); none exist.
- Mutants for the authorization check and the idempotency fields are built and run (v4, §11); they are not a proof of general security.
- Property-based tests over multiple seeds (one seeded sequence, T2-CR-05).
- Independent reproduction by a reviewer.

**Residual risks (explicit):**
1. Superuser/owner bypass (deployment).
2. Payment verification is not performed by the database (Phase 22).
3. Human-to-role mapping is not performed by the database (Phase 4).
4. No cross-tenant read protection beyond "runtime roles have no table reads". Future read paths need RLS or API scoping.
5. The test tenant binding model (one role per tenant in one database) is not the approved cell model (D-020).
6. Concurrency checks use fixed UUIDs and require a fresh database.

---

## 7. Remaining mismatch between DDL, domain document and tests

- `PHASE2_DOMAIN_MODEL.md` §5 must be read together with this report. §5 describes the v2 single write path; the authorization and canonical-payload rules in §§2–3 above are the v3 contract. The domain document is updated to point here (see its §11).
- `REMEDIATION_REPORT.md` describes v2. It is superseded for P2-R01..R04 by this document. Its history is kept.
- The v2 evidence file `test_run_v2_2026-10-25.txt` shows the earlier schema and must not be cited for v3.

---

## 8. Test data

All test data is **synthetic**: fixed UUIDs (`…0000-0000-…`), names prefixed "Synthetic". No real student, customer, or payment data was used.

---

## 9. Product Owner decisions still required (not decided by this work)

| ID | Decision needed |
|---|---|
| Q-007 | Parent access model (unchanged, open). |
| O-2 | Cached balance vs derived-only balance (open; the current design keeps the cache and checks it). |
| O-9 | One active enrollment per student (proposal). |
| O-10 (new proposal) | Who may issue purchase credit; whether refunds must reference an order; whether adjustments need approval. |
| D-006 | `Plan` vs `BillingPlan` naming. |
| access_level, importance | Value sets undefined. |
| Q-020 / O-8 | Retention duration and responsible persons. |
| Q-023 | Hosting topology and provider gate (unchanged). |

---

## 10. Acceptance criteria — self-review

| Criterion | Met? | Evidence |
|---|---|---|
| P2-R01 authorization matrix defined and enforced | Yes, in the test model | T2-R01-01..18 |
| P2-R01 no trust in caller `tenant_id`/`actor_id`/`kind`/`reason` | Yes | §2; T2-R01-06, -13 |
| P2-R02 all six fields compared, NULL-safe | Yes | T2-R02-01..07 |
| P2-R02 concurrent same key: same payload one effect; different payload rejected | Yes | T2-CR-04b, T2-CR-04c |
| P2-R03 pinned search_path, qualified names, PUBLIC revoked, least EXECUTE | Yes | T2-R03-01..08 |
| P2-R03 runtime roles not superusers; owner trust documented | Yes; production owner separation **not** verified | T2-R03-01b; §4 |
| P2-R04 mutation performed and detected; canonical restored; script exits nonzero on undetected mutation | Yes | `run_mutation.sh`; evidence v3 |
| Synthetic data only | Yes | §8 |
| Phase 2 remains pending; no runtime security claimed | Yes | §§1, 6 |

Self-review of weaknesses: the lock mutation shows the lock matters for error semantics and idempotency, not for the balance invariant (the CHECK covers that). Mutants for the authorization check and for each idempotency field are now run (§11), but a reviewer should confirm that the mutant set is representative. Rejection tests cover only the listed payload fields; the authorization model still depends on the test-role bindings being correct.

---

## 11. Mutation and property evidence (v4 run; re-executed in v5, 2026-10-26)

v5 re-ran every item below via the hardened `run_all.sh` (exit 0). Each mutant result and seed result in v5 matches the table and list below.

Evidence: `docs/phase2/evidence/test_run_v4_2026-10-25.txt` (one full run of `run_all.sh`, exit 0).
Runners: `docs/phase2/mutation/run_mutants.sh`, `docs/phase2/mutation/run_property_seeds.sh`, `docs/phase2/concurrency/run_mutation.sh`.

| Mutant | Weakened invariant | First failing test (suite stops at first failure) | Result |
|---|---|---|---|
| AUTH-1 | tenant binding check disabled | T2-R01-06 | DETECTED |
| AUTH-2 | permission check disabled | T2-R01-02 | DETECTED |
| AUTH-3 | identity uses `current_user` (owner) for tenant binding | T2-R01-06 | DETECTED |
| AUTH-4 | identity uses `current_user` for permission | T2-R01-02 | DETECTED |
| IDEM-kind | replay ignores `kind` | T2-R02-01 | DETECTED |
| IDEM-amount | replay ignores `amount` | T2-CR-10 | DETECTED |
| IDEM-student | replay ignores `student_id` | T2-R02-03 | DETECTED |
| IDEM-order | replay ignores `order_id` | T2-R02-04 | DETECTED |
| IDEM-actor | replay ignores `actor_id` | T2-R02-05 | DETECTED |
| IDEM-reason | replay ignores `reason` | T2-R02-06 | DETECTED |
| LOCK (§5) | account row lock removed | T2-CR-04 | DETECTED (by reason and idempotency, not by balance) |

Restoration: the canonical schema hash is unchanged after every mutation, and the full canonical suite passes again.

Property test, 12 explicit seeds (`setseed` accepts [-1, 1]): 0.11, 0.22, 0.33, 0.44, 0.55, 0.66, 0.77, 0.88, 0.12, 0.23, 0.34, 0.45. Each seed uses its own synthetic tenant and 80 randomized operations. Result: **12 PASS, 0 failures**, balance never negative, drift 0 for every seed. Seed 0.42 (single run, §6) is not part of this list.

Runner reliability: `run_all.sh` aggregates every step, uses per-run temporary files, and exits 1 on any failed step. A controlled fault (an intentionally wrong expected SQLSTATE in a copied suite) produced exit 1.

Not run: independent reproduction by a reviewer; mutants for the constraint-level checks (non-null tenant, transition table); mutants for authorization of `adjuster_rt` and `issuer_rt` bindings; any test on a real PostgreSQL cluster outside this sandbox.

---

## 12. Runner hardening and controlled-fault evidence (v5, 2026-10-26)

- `run_all.sh` checks every required setup step (roles, DDL, concurrency preparation, restoration) and skips dependent stages when a prerequisite fails. Exit 0 only when every stage passed and cleanup succeeded.
- psql exit codes are classified: 2 = ENVIRONMENT, 3 = SCRIPT_OR_TEST_ERROR, other = FATAL_OR_OTHER. Shared helpers: `docs/phase2/verify_lib.sh`.
- The mutant runner fails if any defined mutant is not generated (`GENERATION INCOMPLETE`), so a mutant cannot be dropped silently.
- Cleanup drops only the databases this runner creates, and reports each failure.

Controlled faults (each run on a copy; canonical schema not modified):

| Fault | Logs | Exit | Result |
|---|---|---|---|
| PostgreSQL unreachable (service stopped) | `evidence/controlled_fault_env_down_v5_2026-10-26.txt` | 1 | Stage 0 `ENVIRONMENT`; no success summary; cleanup failures reported for all 16 names. |
| SQLSTATE expectation changed in a copied suite | `evidence/controlled_fault_sqlstate_v5_2026-10-26.txt` | 1 | Suite classified `SCRIPT_OR_TEST_ERROR`; no success summary. |
| Mutant definition target removed (canonical untouched) | `evidence/controlled_fault_mutant_target_v5_2026-10-26.txt` | 1 | `GENERATION INCOMPLETE: 9 of 10`; run fails. |

Note on the first attempt at the third fault: the first copy also altered the canonical function, which broke the suite and muddied the result. That attempt was discarded; the result above is from the corrected fault (only the mutant definition changed).

Note on environment: during this work the sandbox PostgreSQL service was observed stopped between command calls, and once during a run (classified ENVIRONMENT by the runner). Results above come from complete runs after the service was restarted, and are reported as observed.

Not run: a reviewer's independent reproduction; mutants for constraint-level checks (non-null tenant, transition table); mutants specific to `issuer_rt`/`adjuster_rt` bindings beyond the generic AUTH mutants.
