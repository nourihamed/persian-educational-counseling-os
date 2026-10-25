# PROJECT_STATE — Dated addendum: Phase 2 remediation (2026-10-25)

Apply by pasting below the current dated summary in `PROJECT_STATE.md`. This addendum does not change any gate.

- **Phase 2:** remediation of the independent supervisor findings is complete in the draft on branch `docs/phase2-database-domain-model` (PR #8), with the boundaries recorded in `docs/phase2/REMEDIATION_REPORT.md`.
- **Gate:** Phase 2 is **PENDING independent review**. Not APPROVED. Not merged.
- **Evidence (author-reported):** `docs/phase2/run_all.sh` exit 0 on PostgreSQL 16.15, fresh databases, synthetic data. 87 PASS notices (including 2 fixture lines), 0 FAIL; concurrency 3 PASS. Log: `docs/phase2/evidence/test_run_v2_2026-10-25.txt`.
- **Superseded evidence:** `docs/phase2/evidence/test_run_2026-10-25.txt` (v1, 32 PASS) describes an earlier schema and must not be cited as current.
- **Not executed:** lock-removal mutation test, property tests over multiple seeds, RLS, API/app authorization, migrations, production roles, backup/restore, Alt-5 cells, hosting.
- **Unverified (deployment-dependent):** table owner or superuser cannot bypass the ledger and immutability triggers.
- **Open decisions:** Q-007 (open); O-1..O-9 (proposals; O-2 and O-9 need Product Owner decisions); D-006; access_level and importance value sets; Q-020/O-8; Q-023 (open, hard pre-hosting gate).
- **Unchanged:** D-014 (synthetic data only), D-020/D-023 (Alt-5 requirements), Q-023 (open).
- **Next action:** independent reviewer reproduces `run_all.sh` on a fresh PostgreSQL and inspects the new PR head.
