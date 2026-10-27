## Phase 2 — Database & Domain Model: remediation candidate for independent re-review

Authorized for documentation/DDL/test work by Product Owner (Issue #7). **Not approved. Not to be merged by the author.** Phase 3 is not started. Real student data remains prohibited under D-014.

This PR is open and draft. Current branch head is the authoritative GitHub PR head; older commit identifiers in prior reports are historical and must not be interpreted as the reviewed head.

### Current remediation in this branch
- D-025: added canonical mobile and academic-grade keys to student records and a platform-wide registry whose primary key is (normalized mobile, grade), populated transactionally by an enrollment trigger. The database unique constraint is the concurrency-safe final gate. Active enrollments require both canonical keys. Keys cannot change while an active counselor enrollment exists.
- Added D-025 regression cases: cross-tenant duplicate mobile+grade must fail; same mobile with a different grade may succeed.
- Program-version enrollment guard now fires on INSERT and on UPDATE of tenant/version references; regression test attempts to reassign an enrollment to a draft version.
- Existing credit-ledger, version lifecycle, tenant composite-FK, privilege and test-harness work remains in scope.

### Important limits / not yet complete
- **D-026 transfer is not implemented end-to-end.** The product rule is recorded, but this Phase 2 schema does not authenticate the real caller as the prior counselor. Authentication/user identity is deferred to Phase 4. No function may treat a caller-supplied counselor/user UUID as proof of authentication. Transfer requires a later authenticated operation that checks the prior counselor's own confirmation, binds it to the exact prior enrollment, and atomically ends the old enrollment and creates the new one.
- The D-025 / version-guard changes above have **not been executed** against PostgreSQL after editing. Syntax, fixture behavior, cross-tenant uniqueness, and concurrency behavior are unverified.
- Existing v5 logs are author-reported only; they predate these changes and are not evidence that the current branch passes.
- No independent fresh PostgreSQL run of the current branch has been completed. No successful run is claimed here.

### Required verification
1. Run docs/phase2/run_all.sh against a fresh throwaway PostgreSQL 15+ database with ON_ERROR_STOP=1.
2. Add and execute a two-session concurrency test proving only one insert can claim the same normalized mobile+grade key across tenants; verify the losing session fails for the expected unique-constraint reason.
3. Add transfer-specific schema/API contracts and negative tests when the authenticated user/principal mapping is available; do not weaken D-026 to accommodate the current schema boundary.
4. Reconcile the domain document and test evidence with actual outcomes, then request independent review.

### Existing evidence (historical, author-reported)
The v5 report states PostgreSQL 16.15, 111 test PASS notices plus 2 fixture confirmations, 4 concurrency checks PASS, 10/10 targeted authorization/idempotency mutants detected, 12/12 property seeds PASS, controlled faults exiting 1, and overall exit 0. This evidence predates the current D-025 and version-trigger edits and has not been independently reproduced.

### Out of scope / not established
RLS, application/API authorization, runtime tenant isolation, production role provisioning, migrations, owner/superuser bypass prevention, Alt-5 cell isolation, hosting, backup/restore, payment verification, and real-data permission are not established by this PR. Q-007 remains open; Q-023 remains a hard pre-hosting gate.

**Phase 2 gate: NOT READY — fresh execution and D-026 authentication-bound transfer design remain blockers.**
