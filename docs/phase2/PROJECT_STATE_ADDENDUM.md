# PROJECT_STATE — Dated addendum: Phase 2 targeted security remediation (2026-10-25)

Paste below the current dated summary in `PROJECT_STATE.md`. Does not change any gate.

- **Phase 2:** P2-R01..R04 remediation candidate on branch `docs/phase2-database-domain-model` (PR #8). Report: `docs/phase2/SECURITY_REMEDIATION_R01_R04.md`.
- **Gate:** PENDING independent review. Not APPROVED. Not merged.
- **Evidence (author-reported):** `docs/phase2/run_all.sh docs/phase2` exit 0 on PostgreSQL 16.15, fresh databases, synthetic data. Suite 113 PASS notices, 0 FAIL. Concurrency PASS. Lock-removal mutation DETECTED. Log: `docs/phase2/evidence/test_run_v3_2026-10-25.txt`.
- **Superseded evidence:** v1 (32 PASS) and v2 logs describe earlier schemas; do not cite as current.
- **Not executed:** RLS, API/app authorization, production roles and owner separation, migrations, backup/restore, Alt-5 cells, hosting, mutants for the authorization check and idempotency fields, multi-seed property tests, independent reproduction.
- **Unverified (deployment-dependent):** superuser/owner cannot bypass triggers; production owner separation.
- **Open decisions:** Q-007; O-2; O-9; O-10 (new proposal); D-006; access_level and importance; Q-020/O-8; Q-023 (open, hard pre-hosting gate).
- **Unchanged:** D-014, D-020/D-023, Q-023.
- **Next action:** independent reviewer reproduces `run_all.sh` and the mutation on a fresh PostgreSQL and inspects the new PR head.
