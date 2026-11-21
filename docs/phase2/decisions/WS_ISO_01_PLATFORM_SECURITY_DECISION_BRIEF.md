# WS-ISO-01 — Platform Security decision brief: caller binding

**Status:** DECIDED 2026-11-20 by the Product Owner — **"B with a test-only key"**; production verification fail-closed until PS-1..PS-4 are approved by Platform Security. Implemented in draft SQL (`workspace_principal_assertion_draft.sql`, `workspace_counselor_rls_draft.sql`); BLOCKING until independent review.

**Original status:** DECISION REQUIRED (Platform Security, with the Product Owner). **CRITICAL / BLOCKING.**
**Prepared:** 2026-11-20 by the implementation agent. The decision is not made here.
**Detail:** this brief supersedes nothing in `../workspace/WS_ISO_01_COUNSELOR_ISOLATION_PROPOSAL.md` and adds the
execution-path analysis the Supervisor asked for.

## 1. Measured state (fresh PostgreSQL 16.15 cluster, 2026-11-20)

**What is implemented and tested** (ISO-C1..54, 42 PASS lines):
- the counselor boundary predicate;
- the list, row, report and note functions;
- revocation;
- the guards on two write paths.

**What is not.** The caller is not bound, and the suite prints three lines as **OPEN**, not PASS:

| Gap | Measured result |
|---|---|
| ISO-GAP-01 | the shared runtime role reads counselor B's study session directly |
| ISO-GAP-02 | the runtime reads every `private_to_author` note |
| ISO-GAP-03 | 0 of 32 student-scoped tables have row-level security |

**Already enforced elsewhere:** cross-Workspace isolation is enforced by separate databases and roles (WS-ROLE
cross-database denial, step 22).

## 2. Why no safe implementation is possible without a decision

The database knows the role (`session_user`, `current_user`), not the person. Every candidate source of "the person"
was checked:

| Candidate | Can a caller forge it? | Usable as proof? |
|---|---|---|
| A membership id passed as a function argument | yes | **no** (that is the current gap) |
| A custom GUC (`SET app.membership = …`) | yes; the application sets it | **no** (finding H-03) |
| `current_user` after `SET ROLE` from a shared pool login | yes; a pool login holding many member roles can SET ROLE to any of them | **no** |
| `session_user` of a per-member database login | no; PostgreSQL authenticates it | **yes**, if pooling keeps sessions per member (option A) |
| A signed assertion verified **inside** the database by a SECURITY DEFINER function, bound to the current transaction | no, if the key and algorithm are trusted | **yes**, once PS-1..PS-4 are decided (option B) |

**Further constraints**
- **A SECURITY DEFINER function** runs as its owner (`current_user` = owner), so it cannot read the caller from
  `current_user`. It must use `session_user` or a verified transaction-bound record.
- **Row-level security:**
  - it does not apply to a table's owner unless `FORCE ROW LEVEL SECURITY` is set;
  - it never applies to a superuser or to a `BYPASSRLS` role.
  - No Workspace role holds BYPASSRLS (SEC-05), and no application role owns a table (SEC-04).
- **Connection pools reuse sessions.** Any per-session identity must be re-established per transaction, or the pool
  must never share a session between members.

## 3. Options

| | Mechanism | Pooling | Background jobs | Depends on | Risk |
|---|---|---|---|---|---|
| **A** | One database login per staff membership, mapped by a reviewed table; RLS reads `session_user` | pool keyed by user (session-per-member) | worker runs as a worker login; acts for a member only through reviewed definer functions with the member id captured at enqueue | role-lifecycle procedure (create, revoke, rotate) — Operations | role sprawl; a credential per staff member |
| **B** (recommended) | Short-lived signed principal assertion (member, workspace, expiry, nonce) verified in-DB by a definer function. It writes the verified member to a row keyed by `(backend pid, transaction id)`, and `current_verified_membership()` returns it only for the same transaction | safe: identity dies with the transaction | job carries the assertion captured at enqueue, re-verified at run, immutable | PS-1..PS-4 (algorithm, allowlist, key registry, key procedures) | verifier and key management must exist first |
| C | API-only enforcement | — | — | — | the database keeps failing open; **does not close WS-ISO-01** |
| D | One Workspace per counselor | — | — | contradicts the approved Organization model | — |

**Recommendation: B. Fallback A** if PS-1..PS-4 cannot be decided in time. C and D do not satisfy the requirement.

## 4. What either A or B must deliver (acceptance criteria)

| # | Contract | Test that must pass, with a negative control |
|---|---|---|
| 1 | Counselor A reads and writes only assigned students | ISO suite re-run **as A's own identity**: B's rows invisible, writes refused |
| 2 | Changing an object id does not help | read B's row by its id as A → no row (uniform with a non-existent id) |
| 3 | Supplying B's membership id does not help | every function ignores the argument, or rejects it if it differs from the verified member |
| 4 | Student A cannot act as student B, nor as a counselor | per-student identity, under the same mechanism (also required by WS-PLAN-01 decision A) |
| 5 | Cross-Workspace fails closed | existing cross-database denial, plus a foreign-workspace assertion → refused (B) |
| 6 | Missing, stale, expired or revoked identity → refused | B: expired assertion, replayed nonce, revoked membership. A: disabled login, ended assignment |
| 7 | No leak across pooled requests | B: transaction 2 on the same session sees no member. A: pool keyed by user, tested |
| 8 | A background job cannot change its Workspace or actor | job row immutable after enqueue; the worker cannot set the member |
| 9 | Exports, files and notifications use the same boundary | RLS on `private_file_objects` and `in_app_notifications` (already student-scoped), plus export functions going through `current_verified_membership()` |
| 10 | Direct SQL as the runtime cannot bypass | RLS **FORCE** on all 32 tables, generated from `student_scoped_tables`; catalog test that no table is missed |
| 11 | Cross-student operations (transfer export, ledgers, capacity) | only through reviewed definer functions, each with its own tests; no BYPASSRLS anywhere |

Implementation plan once decided:
- `current_verified_membership()`;
- RLS ENABLE + FORCE on the 32 tables, from one generator;
- the ISO-GAP lines turned into hard assertions;
- every existing suite that runs as the runtime given a verified principal;
- indexes `counselor_assignments(counselor_membership_id, state)` and `enrollments(student_id)`.

## 5. Decisions requested

1. Option **A or B** (or another mechanism meeting §4).
2. If B: PS-1 (algorithm), PS-2 (allowlist), PS-3 (key registry), PS-4 (key procedures) — or approval to build B
   against a **synthetic test key** only, with production fail-closed until PS-1..PS-4 are decided.
3. The manager permission vocabulary. Until it exists, managers stay denied.
4. Whether the student identity (needed by WS-PLAN-01 decision A) uses the same mechanism.

Until these are answered, nothing in this area is implemented beyond what exists, and WS-ISO-01 stays CRITICAL /
BLOCKING.
