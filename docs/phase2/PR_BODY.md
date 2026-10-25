## Phase 2 — Database & Domain Model: remediation of supervisor findings (draft for independent re-review)

Authorized by Issue #7. **Not approved. Not to be merged by the author.** Phase 3 is not started.

### What changed
- Credit ledger: single atomic write path `post_credit_transaction()`; runtime role cannot write ledger or balance directly; reconciliation view; append-only incl. TRUNCATE (P2-H01, P2-H05).
- Program versions: identity immutable in every state; enforced transition table; superseded is terminal (P2-H02).
- Plan versions and items: frozen after activation; ownership immutable (P2-H03).
- Added curriculum_nodes, study_sessions, error_records, exams, exam_results, class_sessions, assignments (P2-H04).
- Domain document reconciled with DDL, with a mismatch table and explicit deferrals (P2-M03).
- Audit scope made explicit: platform vs tenant (P2-M04).
- Corrected test T2-VER-01c and the test helper, which now asserts SQLSTATE and reason (P2-M01).
- Evidence separated into seven categories; v1 evidence marked superseded (P2-M05). Index policy documented (P2-L01). O-9 kept as a proposal (P2-L02).
- Concurrency checks added and executed with parallel sessions: T2-CR-04, T2-CR-04b, T2-VER-02 (plus sequential T2-CR-03).

### Verification actually run (author-reported; not yet independently reproduced)
- Environment: PostgreSQL 16.15, fresh databases, synthetic data only (D-014).
- One full run: `docs/phase2/run_all.sh` → **exit 0**. Log: `docs/phase2/evidence/test_run_v2_2026-10-25.txt`.
- Suite: 87 PASS notices (includes 2 fixture lines), 0 FAIL. Concurrency: 3 PASS.

### Not executed (explicit)
- Lock-removal mutation test for T2-CR-04; property test over more than one seed; owner-level prevention (deployment); RLS; application/API authorization; migrations; production roles; backup/restore; Alt-5 cells; hosting.

### Boundaries
- The table owner or superuser can bypass triggers. Reconciliation **detects** tampering; it does not prevent it. Labelled UNVERIFIED — deployment-dependent.
- No runtime security claim. Q-023 remains open. D-014 unchanged.

### Open decisions (not decided by this PR)
- **Q-007** parent access model: open; parent grant table not modelled.
- **O-1..O-9** are proposals. O-2 (cached vs derived balance) and O-9 (one active enrollment per student) need Product Owner decisions.
- **D-006** naming; **access_level** and **importance** value sets undefined; **Q-020/O-8** retention.

### Review focus
- `phase2_schema_draft.sql`: triggers `program_versions_guard`, `plan_versions_guard`, `plan_items_guard`, `post_credit_transaction`, and the REVOKE/GRANT block.
- `phase2_constraint_tests.sql`: whether each negative test fails for the stated reason.
- `concurrency/`: whether the parallel-session results support T2-CR-04, 04b and T2-VER-02.
- `REMEDIATION_REPORT.md` §1: finding-by-finding status.

Phase 2 gate: **PENDING independent review.**
