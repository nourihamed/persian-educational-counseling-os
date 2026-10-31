## Phase 2 — Database & Domain Model: remediation candidate for independent re-review

Authorized for documentation/DDL/test work by Product Owner (Issue #7). **Not approved. Not to be merged by the author.** Phase 3 is not started. Real student data remains prohibited under D-014.

This PR is open and draft. Current branch head is the authoritative GitHub PR head; older commit identifiers in prior reports are historical and must not be interpreted as the reviewed head.

### Current remediation in this branch
- D-025: added canonical mobile and academic-grade keys to student records and a platform-wide registry whose primary key is (normalized mobile, grade), populated transactionally by an enrollment trigger. The database unique constraint is the concurrency-safe final gate. Active enrollments require both canonical keys. Keys cannot change while an active counselor enrollment exists.
- Added D-025 regression cases: cross-tenant duplicate mobile+grade must fail; same mobile with a different grade may succeed; noncanonical mobile and unknown grade keys must fail.
- Added a two-session D-025 concurrency scenario to the existing runner. It has **not been executed**.
- Program-version enrollment guard now fires on INSERT and on UPDATE of tenant/version references; regression test attempts to reassign an enrollment to a draft version.
- Existing credit-ledger, version lifecycle, tenant composite-FK, privilege and test-harness work remains in scope.

### Important limits / not yet complete
- **D-026 transfer is not implemented end-to-end.** Draft DDL now has append-only `counselor_fee_confirmations`, bound to the exact prior enrollment, student, counselor and `counselors.user_id`, with negative regression cases. However, this does not prove the real caller is authenticated as that user: authentication/user identity is deferred to Phase 4. No function may treat a caller-supplied counselor/user UUID as proof of authentication. Transfer initiation authorization and the atomic operation that ends the old enrollment and creates the new one remain unimplemented.
- The D-025, D-026 confirmation-event, and version-guard changes above have **not been executed** against PostgreSQL after editing. Syntax, fixture behavior, cross-tenant uniqueness, and concurrency behavior are unverified.
- Existing v5 logs are author-reported only; they predate these changes and are not evidence that the current branch passes.
- No independent fresh PostgreSQL run of the current branch has been completed. No successful run is claimed here.

### Required verification
1. Run docs/phase2/run_all.sh against a fresh throwaway PostgreSQL 15+ database with ON_ERROR_STOP=1.
2. Execute the newly added two-session concurrency test proving only one insert can claim the same normalized mobile+grade key across tenants; verify the losing session fails for the expected unique-constraint reason.
3. Add transfer-specific schema/API contracts and negative tests when the authenticated user/principal mapping is available; do not weaken D-026 to accommodate the current schema boundary.
4. Reconcile the domain document and test evidence with actual outcomes, then request independent review.

### Existing evidence (historical, author-reported)
The v5 report states PostgreSQL 16.15, 111 test PASS notices plus 2 fixture confirmations, 4 concurrency checks PASS, 10/10 targeted authorization/idempotency mutants detected, 12/12 property seeds PASS, controlled faults exiting 1, and overall exit 0. This evidence predates the current D-025, D-026 confirmation-event, version-trigger, and D-025 concurrency-test edits and has not been independently reproduced.

### Out of scope / not established
RLS, application/API authorization, runtime tenant isolation, production role provisioning, migrations, owner/superuser bypass prevention, Alt-5 cell isolation, hosting, backup/restore, payment verification, and real-data permission are not established by this PR. Q-007 remains open; Q-023 remains a hard pre-hosting gate.

**Phase 2 gate: NOT READY — fresh execution and D-026 authentication-bound transfer design remain blockers.**

## Execution status — author run after the 0cbbce3 review (2026-10-27)
- Command: `sudo -u postgres bash docs/phase2/run_all.sh docs/phase2` on a fresh local PostgreSQL 16.15 → **exit 0**. Evidence: `docs/phase2/evidence/test_run_head_after_0cbbce3_<date>.txt`.
- Constraint/authorization/enrollment suite: **133 test cases PASS**, 2 fixture acceptances, **0 FAIL**. This includes D-025 (T2-ENR-025-00a..02), the D-026 event tests (T2-TR-026-01..07, with an accepted control insert), the version-guard UPDATE test (T2-VER-07b), and the registry lifecycle tests (ENR-REG-01..07b).
- Concurrency (fresh DB): T2-CR-04, 04b, 04c, T2-VER-02, **T2-ENR-025-03** (cross-tenant mobile+grade race: loser fails on `active_student_counselor_registry_pkey`; one registry row and one active enrollment remain) and **T2-ENR-025-04** (identity-key change racing an activating enrollment: change rejected with "immutable while counselor enrollment is active"; registry keeps the original key). Both passed.
- Sensitivity checks: disabling the identity guard makes T2-ENR-025-04 FAIL; the pre-fix enrollment trigger (INSERT only) makes T2-VER-07b FAIL; 11 of 11 mutants DETECTED; 12 of 12 property seeds PASS; controlled faults exit 1 with no success summary.
- Not established by this run: independent reproduction; D-026 transfer itself (no transfer function exists; the event table only records an assertion); caller authentication (Phase 4); RLS/API authorization; owner/superuser bypass; migrations; hosting. Gate: NOT READY until independent review.

## Harness self-tests and final author run (2026-10-31; author-executed, NOT independently reproduced)
- Evidence: `docs/phase2/evidence/test_run_final_after_d12b26c_2026-10-31T144259Z.txt`.
- Harness controlled-fault self-tests (each on a copy; canonical files unchanged): S1 failing baseline blocks mutant evaluation; S2 surviving mutant reported NOT DETECTED; S3 invalid mutant not counted as DETECTED; S4 failing concurrency stage fails the whole run; S5 a real cleanup failure (an open session on a disposable database) fails the whole run. All five PASS, each run exit 1 as designed.
- Canonical `run_all.sh` on fresh PostgreSQL 16.15: exit 0; 133 test cases PASS, 2 fixture acceptances, 0 FAIL; 11 of 11 mutants DETECTED; 12 of 12 property seeds PASS; cleanup OK.
- Runner fix in this commit: every mutant database is now dropped on every exit path (previously an invalid mutant's database could be left behind).
- Not established: independent reproduction; D-026 transfer (not implemented); caller authentication (Phase 4); RLS/API authorization; owner/superuser bypass; hosting. Phase 2 gate remains NOT READY pending independent review.
