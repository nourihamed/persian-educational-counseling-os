# WS-ISO-01 — Counselor-to-counselor isolation: finding, boundary and proposed correction

**Status:** OPEN · **Severity:** CRITICAL (design finding) · **Gate impact:** BLOCKING for Phase 2
**Date:** 2026-11-18 · **Author:** implementation agent · **This is a proposal, not a decision.** The
caller-binding choice in §5 belongs to Platform Security with the Product Owner.

## 1. The requirement (approved, not in doubt)

| Source | Text |
|---|---|
| Master prompt §3 | Counselor A *"must not have any access to"* Counselor B's information, in the database, API, queries, reports, files, notifications and background jobs |
| `docs/phase2/api/API_AUTHORIZATION_CONTRACT.md` §4 | *"Counselor reads/writes are restricted to students with active counselor assignment and action permission."* |
| same, §6 | *"Counselor cannot read another counselor's student absent explicit scope."* *"Manager without specific permission cannot access restricted records."* |
| `PO_DECISION_ROLE_GRANTABILITY_MATRIX_2026-11-10.md` | *"a Counselor is confined to assigned students"*; *"role assignment alone never grants access to all student records"* |

## 2. The finding, measured

The database **fails open**. Inside one Workspace, every counselor's code path would run as the same
Workspace runtime role, and that role:

- holds `SELECT` on 47 tables in full (SEC-10);
- reads counselor B's study session directly (ISO-GAP-01);
- reads every author's `private_to_author` counselor note (ISO-GAP-02);
- is subject to row-level security on **0 of 32** student-scoped tables (ISO-GAP-03).

It is the only register item whose current state fails open rather than closed. Exposure today is nil only
because no API, worker or deployment exists. The first code path built on this schema would inherit
cross-counselor access by default, which is why it is classified CRITICAL rather than HIGH.

## 3. The exact missing boundary

It has two halves.

1. **Which students a counselor membership may reach.** The schema *recorded* this —
   `counselor_assignments(enrollment_id, counselor_membership_id, state, accepted_at, …)` — and nothing
   *consumed* it: no policy, view, function or grant was keyed to the assignment.
2. **Which membership is calling.** The database has no notion of the caller beyond the shared runtime
   role. Session GUCs cannot fill this gap: finding H-03 already rejected them as an authorization
   mechanism, because the application sets them and can therefore forge them.

## 4. What is implemented now (half 1), and how it is evidenced

`docs/phase2/workspace/workspace_counselor_scope_draft.sql`, tested by
`docs/phase2/workspace/tests/workspace_counselor_isolation_tests.sql` (ISO-C1..ISO-54; 42 PASS lines and 3
OPEN lines, local; GitHub Actions: NOT RUN at the time of writing).

| Function / guard | Rule | Tests |
|---|---|---|
| `counselor_may_access_student(membership, student)` | an assignment that is `active` **and accepted**, held by an `active` membership carrying the `counselor` role | ISO-01..09 |
| `counselor_visible_students(membership)` | the list is exactly the predicate's true set | ISO-30..32 |
| `counselor_may_access_row(membership, table, pk)` | any row of any of the 32 student-scoped tables, by **its own** id, owner resolved exactly as the transfer write barrier resolves it; `private_to_author` notes only for their author; a non-existent id answers exactly like another counselor's id | ISO-10..23, ISO-C1, ISO-C2 |
| `counselor_caseload_report(membership)` | an unreachable student contributes no row and nothing to any total | ISO-33, ISO-34 |
| `counselor_notes` trigger | author must reach the student; author/student immutable; a private note cannot be widened | ISO-40..42 |
| notification recipient rule | a member recipient of a notification about a student must reach that student — **closing a path Batch 8 had left open to any active member** | ISO-43, OPS-13c |
| revocation | ending an assignment or suspending a membership removes access at once, through every surface above | ISO-50..54 |

Managers are **denied**: the explicit permission the contract requires has no defined vocabulary yet, and
denial is the contract's own default.

Negative controls, each measured by neutralising one rule and re-running: dropping the acceptance
condition fails ISO-04; dropping the role condition fails ISO-06; dropping the note-visibility rule fails
ISO-21; a report over all students fails ISO-33; removing the note trigger fails ISO-40; restoring the
Batch 8 recipient rule fails OPS-13c.

**What this does not establish:** that counselor A is prevented from reading counselor B's students at the
database. Every function takes the membership as an argument and cannot verify it.

## 5. Proposed correction for half 2 (decision required)

| Option | Mechanism | For | Against |
|---|---|---|---|
| **A** | Per-membership database login roles, mapped to memberships by a reviewed table; RLS reads `session_user` | PostgreSQL itself verifies identity; no cryptography to decide | one role per staff member; pooling must not share sessions across members |
| **B** (recommended) | A short-lived signed principal assertion verified **inside** the database by a SECURITY DEFINER function (the receipt-verifier pattern this project already has), which records the verified membership for the current transaction only; RLS reads that | works with pooling; reuses designed and tested infrastructure | depends on PS-1..PS-4 (algorithm, allowlist, key registry, key procedures) |
| C | API-only enforcement; database functions as defence in depth | cheapest | the database keeps failing open — the finding itself |
| D | One Workspace per counselor | removes the problem by construction | contradicts the approved Organization model |

**Recommendation: B, with A as the fallback** if PS-1..PS-4 cannot be decided in time.

## 6. Minimum safe schema change once half 2 is decided

1. `current_verified_membership()` — returns the membership established by the chosen mechanism, or NULL.
   It must never read a client-settable value.
2. `ALTER TABLE … ENABLE ROW LEVEL SECURITY` and `FORCE ROW LEVEL SECURITY` on every table in
   `student_scoped_tables`, generated from that view so a new table cannot be missed, with one policy shape:
   `USING (counselor_may_access_student(current_verified_membership(), <owner resolved as the barrier resolves it>))`
   and the same `WITH CHECK` for writes.
3. No `BYPASSRLS` for the runtime, worker or exporter roles; a catalog test asserting that.
4. Every legitimate cross-student operation — transfer export, the capacity and credit ledgers, a manager
   report under an explicit permission — routed through reviewed SECURITY DEFINER functions with their own
   tests, instead of a role that bypasses policy.
5. ISO-GAP-01..03 converted from OPEN lines into assertions that the runtime **cannot** read another
   counselor's rows, and the ISO suite re-run **as each counselor's own identity**.

## 7. Migration and delivery risks

- **Blast radius.** Enabling RLS on 32 tables changes the result of every existing query run as the runtime
  role. Every current test suite that writes or reads as that role would need a verified principal, so this
  is a coordinated change, not a patch.
- **Performance.** The predicate joins four tables per row check; the policy needs supporting indexes on
  `counselor_assignments(counselor_membership_id, state)` and `enrollments(student_id)`, and plans must be
  checked for per-row function calls on large scans.
- **Silent denial.** RLS hides rows rather than raising; a defect in the principal function would look like
  "no data", so the principal function needs its own fail-loud tests.
- **Operations that must cross the boundary** (transfer snapshot, ledgers, reconciliation) are where a
  bypass is most tempting; each needs an explicit, reviewed path.

## 8. What closes WS-ISO-01

A recorded caller-binding decision; the §6 changes implemented; ISO-GAP-01..03 failing if another
counselor's rows are reachable; the ISO suite passing as each counselor's own identity; GitHub Actions
evidence at the exact commit; independent Supervisor review.
