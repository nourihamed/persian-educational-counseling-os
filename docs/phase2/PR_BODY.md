## Phase 2 — Targeted security remediation P2-R01..R04 (draft for independent re-review)

Authorized by Issue #7. **Not approved. Not to be merged by the author.** Phase 3 is not started.
Base HEAD reviewed: `5e78384`. Full report: `docs/phase2/SECURITY_REMEDIATION_R01_R04.md`.

### What changed
- **P2-R01 authorization:** `post_credit_transaction()` checks `session_user` against `tenant_role_bindings` (tenant) and `credit_role_permissions` (kind) before any lock or write. Matrix in the report §2. Runtime roles have no table reads or writes and cannot self-grant.
- **P2-R02 idempotency:** canonical payload `(kind, amount, student_id, order_id, actor_id, reason)`, NULL-safe. Any difference is rejected (`unique_violation`).
- **P2-R03 SECURITY DEFINER:** `search_path = pg_catalog, pg_temp`; schema-qualified objects; no PUBLIC EXECUTE; schema CREATE revoked from PUBLIC; EXECUTE only for the four roles that need it; runtime roles are NOSUPERUSER.
- **P2-R04 mutation test:** lock removed in a disposable mutant DB. The harness checks the exact failure reason and **detects** the mutation. The canonical schema hash is unchanged and the restored run passes.
- Concurrency harness hardened: per-run temp files, fixture failures are not hidden, failure reasons are checked, new scenario T2-CR-04c (same key, different payload).
- Read grants removed from runtime roles (cross-tenant read protection beyond this is deferred to RLS or API scoping).

### Verification actually run (author-reported; not yet independently reproduced)
- PostgreSQL 16.15, fresh databases, synthetic data only (D-014).
- One full run: `docs/phase2/run_all.sh docs/phase2` → **exit 0**. Log: `docs/phase2/evidence/test_run_v3_2026-10-25.txt`.
- Suite: 113 PASS notices (including fixture acceptance lines), 0 FAIL.
- Concurrency (canonical): T2-CR-04, T2-CR-04b, T2-CR-04c, T2-VER-02 PASS.
- Mutation (lock removed): T2-CR-04 FAIL, so the mutation is detected. Restoration PASS.

### Not executed (explicit)
- RLS; application/API authorization and identity; production roles and owner separation; migrations; backup/restore; Alt-5 cells; hosting.
- Mutants for the authorization check and for each idempotency field (not yet built).
- Property tests over several seeds; independent reproduction.

### Boundaries
- The table owner or superuser is trusted and can bypass triggers. Reconciliation detects tampering; it does not prevent it. UNVERIFIED, deployment-dependent.
- The database cannot verify payments or human identity. Those are Phase 22 and Phase 4 work.
- No runtime security claim. Q-023 remains open. D-014 unchanged.

### Open decisions (not decided by this PR)
- Q-007 parent access model (open).
- O-2 cached vs derived balance; O-9 one active enrollment per student; O-10 (new) who may issue purchases, refund-order linkage, adjustment approval.
- D-006 naming; access_level and importance value sets; Q-020/O-8 retention.

Phase 2 gate: **PENDING independent review.** This PR does not declare Phase 2 approved.
