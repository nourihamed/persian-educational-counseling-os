# CURRENT PROJECT STATE — PHASE 2 (updated 2026-11-18)

**Current phase:** Phase 2 — Database & Domain Model. **Milestone:** all eight implementation batches of the
Supervisor brief attempted, plus the 2026-11-18 Supervisor corrections; a **PROVISIONAL** exit evidence package
prepared for independent review (`docs/phase2/PHASE2_EXIT_PACKAGE_PROVISIONAL.md`).
**Phase 2 gate: NOT READY. Phase 3: NOT AUTHORIZED. D-014 synthetic-only remains in force.**
**Attempting a batch is not acceptance of it.** No batch has been accepted by the Supervisor; this file reports
what was implemented and what the evidence is, not what was approved.

**Branch:** `docs/product-owner-decisions-consolidation-2026-11-07` (PR #12, **Draft, open, unmerged**).
**Commits, kept distinct (verified 2026-11-20 by `git fetch`):**

| Role | SHA |
|---|---|
| Latest implementation / security-reviewed commit | `fe08a77336557a51aca36313230b5e082e5ed3ad` (F-05 follow-up); CI success, runs 44705627331 and 44705633469 |
| Latest documentation commit before this one | `bba728193d8d044bb65c4efe3c33662e8ad686c2` (docs only, no implementation change); CI success, runs [44724614335](https://github.com/nourihamed/persian-educational-counseling-os/actions/runs/44724614335) (job 136248754264) and [44724622970](https://github.com/nourihamed/persian-educational-counseling-os/actions/runs/44724622970) (job 136248780337) |
| PR #12 head before this commit | `926c061` (gap matrix, decision briefs); CI success, runs 44764360492 and 44764375914. This commit implements the 2026-11-20 decisions on top of it |
| `main` | `5bb8e4ed07a7c770ecba7c506a1d2c278e36b6d6` |

| Item | Status |
|---|---|
| F-05 | **ACCEPTED — ARCHITECTURE REVIEW LEVEL** (`fe08a77`) |
| WS-PLAN-01 | **NOT ACCEPTED / BLOCKING** — decisions A2/B1/C1/D1/E1 implemented 2026-11-20; pending independent review |
| WS-ISO-01 | **CRITICAL / BLOCKING** — decision B (test-only key) implemented 2026-11-20; pending independent review; production fail-closed |
| Phase 2 | **NOT READY** |
| Phase 3 | **NOT AUTHORIZED** |

F-05 acceptance is not approval of WS-PLAN-01 as a whole, of WS-ISO-01, of Phase 2, of production runtime plan-item
writes, or of production writer or migrator privileges.
**Behind `main`:** yes, by two commits — `4004360` (adds `cp_30_role_privilege_tests.sql`, 89 lines) and
`5bb8e4e` (reverts it). Net content difference from the merge base `ba5e9d8` to `main` `5bb8e4e`: **zero
files**. Re-verified 2026-11-18 with `git fetch`. Not rebased, merged or force-pushed (BRANCH-SYNC).

## Evidence at a glance — five kinds, never merged into one

| Kind | What it is | Status |
|---|---|---|
| **GitHub Actions** (independent of the agent) | runs at `fc3416ed`: **43725323633** and **43725318826** (push and pull_request) | **FAILED.** Reported by the Supervisor: every SQL/database step passed; **step 28, the repository secret scan, failed**; step 29, the register consistency check, was **skipped** because it followed a failed step. The agent has no Actions access and did not read those logs. |
| **Actions failure, reproduced locally** | the `fc3416ed` scanner run on the exact `fc3416ed` tree | two findings, both in `docs/phase2/workspace/tests/workspace_operations_tests.sql`: line **165** `[iranian-mobile]` and line **171** `[e164]` — the OPS-17/OPS-18 refusal-test fixtures. Neither is a credential. The Supervisor is asked to confirm these against the CI log. |
| **Local verification** (agent-executed, **not independently reproduced**) | full workflow on a cleared PostgreSQL 16.15 cluster, after `git add`, on the tree of the F-05 follow-up commit (parent `38f2561`) | **25 implementation steps passed, 1067 PASS assertion lines, 0 FAIL** (852 before WS-PLAN-01; the plan step now prints 215: 75 PLN, 3 WS-PLN-RACE, 8 PLN-M migration, 109 F-05 membership, 20 F-05 bootstrap), plus Python verifier tests (15 + 6, OK); secret scan PASS (incl. history content); register check PASS incl. REG-09. Local evidence is **not** CI evidence. |
| **GitHub Actions at `467a0294b03f9ffc494509509f9c0ece595b2bd3`** (independent of the agent) | `postgres-draft-tests`, runs [44362679187](https://github.com/nourihamed/persian-educational-counseling-os/actions/runs/44362679187) (job 135008003418) and [44362668276](https://github.com/nourihamed/persian-educational-counseling-os/actions/runs/44362668276) (job 135007959995) | **success, both** (2026-11-18 17:50 UTC). Read by the agent from the PR's check-run conclusions; the agent did **not** read the step logs, so per-step PASS counts in CI are not reported here. This is the first Actions success on any SQL change since `ad3bf28`. It is CI evidence for the draft SQL and synthetic suites only — **not** approval of anything. |
| **GitHub Actions at `b51908011404eb79ee01021916ceb2ad34d12200`** | runs 44365217344, 44365200112 | **success, both** (documentation-only commit) |
| **GitHub Actions at `b7d4b2826036a41c05d46dd3f98b4c92c3f769b9`** (the three Supervisor/Product-Owner decision-recording commits) | runs 44369152676, 44369143862 | **FAILED, both.** Reproduced locally as the register check **REG-08**: the §6 classification row for WS-DOM-05 still read `BLOCKING` while the JSON read `LATER_PHASE`. Realigned in the WS-PLAN-01 commit. The check worked as designed. |
| **GitHub Actions at `d75d039919c806a27a7d5b50021af6920fdd5f0c`** (WS-PLAN-01 data model) | runs 44376897878, 44376886372 | **passed**, as reported by the Supervisor. CI passing did not make it acceptable: the Supervisor's review found F-01..F-04, which the tests did not cover. |
| **GitHub Actions at `8df7d5eea03a3712afed00e4e4ef3028ce01c09e`** (F-01..F-04 remediation) | runs [44382515348](https://github.com/nourihamed/persian-educational-counseling-os/actions/runs/44382515348) (job 135078318581) and [44383233656](https://github.com/nourihamed/persian-educational-counseling-os/actions/runs/44383233656) (job 135080826317) | **success, both.** The Supervisor's review then found F-05. |
| **GitHub Actions at `38f2561412540da15626f2aca2b2f1b6802a2c56`** (F-05 remediation) | runs [44693197767](https://github.com/nourihamed/persian-educational-counseling-os/actions/runs/44693197767) (job 136143681714) and [44693205261](https://github.com/nourihamed/persian-educational-counseling-os/actions/runs/44693205261) (job 136143703579) | **success, both.** The Supervisor verified the logs; F-05 not closed (owner-role chains). |
| **GitHub Actions at `fe08a77336557a51aca36313230b5e082e5ed3ad`** (F-05 follow-up) | runs [44705627331](https://github.com/nourihamed/persian-educational-counseling-os/actions/runs/44705627331) (job 136184380490) and [44705633469](https://github.com/nourihamed/persian-educational-counseling-os/actions/runs/44705633469) (job 136184402186) | **success, both.** F-05 accepted by the Supervisor at architecture-review level. |
| **GitHub Actions at this documentation commit** | — | not reported here; it changes no SQL, test or workflow file. |
| **Design-only contracts** | documents under `docs/phase2/**` with no executable test | are **not** implementation evidence anywhere in this file |

**CI step numbers.** GitHub numbering (YAML step + 2, for "Set up job" and "Initialize containers"): counselor isolation is step **15**, PlanItem with its race, migration and F-05 suites step **16**, secret scan step **30**, register check step **31**. The 2026-11-18 handoff said 13 and 14 for the first two; that was wrong (YAML numbering), and the Supervisor's correction is adopted.

### Why the Batch 8 local result was wrong
Batch 8 was reported as passing the secret scan locally. It did not pass in CI. Cause: **the agent ran the
scanner before `git add`**, while the new test file was untracked, and `git ls-files` lists only tracked files —
so the two fixtures were never scanned. The scanner now prints a `WARN SEC-REPO-04` line naming every untracked
file it did not scan, and the operating rule is: repository checks run after `git add`, on the tree that will be
committed. This is recorded as an error in the agent's own verification, not as a scanner defect.

## Completed (implemented, with local evidence; none accepted yet)
Batches 1–8 as recorded in the dated entries below, and on 2026-11-18:
- **Secret scan repaired, not weakened.** The two CI findings were replaced by marked all-zero fixtures under a
  per-line, contact-patterns-only exception. **History CONTENT scanning implemented** (the old docstring claimed
  history coverage it did not have): 1,361 blobs read, 110 contact-shaped fixture strings found and excepted one
  by one by (blob SHA, pattern, SHA-256 of the value) — no credential, key or PEM block anywhere in the history.
  A **Batch 7 scanner defect** was found by its own self-test: the word "synthetic" anywhere on a line exempted
  every pattern on it, including a PEM header. Fixed; regression cases added. CI checkout now uses
  `fetch-depth: 0`, and a shallow clone fails closed.
- **Register check runs on its own.** Both repository checks use `if: !cancelled()`, so a failure in one no
  longer hides the other, while any failed step still fails the job.
- **WS-ISO-01 classified CRITICAL and BLOCKING; its boundary half implemented** (see Blocked).
- **Every register item classified** (32 items): kind, whether code can resolve it, recommended gate impact,
  closure evidence; the checker now requires those fields and that the Markdown table agrees row by row.

## In progress
- The PROVISIONAL exit evidence package, for independent review.

## Blocked — recommended BLOCKING for the Phase 2 gate
- **WS-ISO-01 — CRITICAL, fails open.** The boundary (which students a counselor may reach) is implemented and
  tested (ISO-C1..ISO-54); the caller is **not** bound to a membership, and the shared runtime role still reads
  every student-scoped table in full (ISO-GAP-01..03, printed as OPEN, not PASS). Needs a Platform Security
  decision on caller binding (`docs/phase2/workspace/WS_ISO_01_COUNSELOR_ISOLATION_PROPOSAL.md`).
- **WS-PLAN-01 — decided (Option B, Product Owner, 2026-11-18); data model implemented at `d75d039` and reviewed
  NOT ACCEPTED by the Supervisor; F-01..F-04 remediated at `8df7d5e`; F-05 raised against that and remediated in the
  following commit; still BLOCKING** until CI on that SHA and the Supervisor's independent review confirm it
  (`workspace_plan_items_draft.sql`; PLN-C1..C4, PLN-01..80, WS-PLN-RACE-01..03, PLN-M01..M08, F05-00..16,
  F05-BOOT-01..14; `WS_PLAN_01_MIGRATION_NOTES.md`). No scheduling logic exists.
  - F-05: the privileged identities are checked by **identity**, not membership. The session must BE the role, and the
    role must be unheld, hold nothing and carry no LOGIN/SUPERUSER/CREATEROLE/BYPASSRLS/REPLICATION/CREATEDB/INHERIT.
    This is re-checked on every write. The bootstrap aborts, without repairing, on an unsafe existing role, then
    verifies the whole boundary for its nine-role inventory. A superuser is not accepted as either identity.
    **Open:** who may provision, hold or assume them outside the synthetic test harness (Platform Security /
    Operations).
  - F-05 follow-up: owner roles (table, function, governance) are checked for **transitive** reach from every
    application role, whatever the INHERIT/SET/ADMIN options; all nine roles must match their expected attributes,
    and their memberships must be exactly the three login → service grants (F05-17..23, F05-BOOT-15..20).
  - F-01: the shared runtime can no longer create plan items or status transitions, so it cannot write one in a
    student's or another counselor's name. Writes need a dedicated NOLOGIN synthetic-writer identity, checked by role
    membership. `actor_kind='student'` is refused outright. **No caller binding was invented** — that stays WS-ISO-01.
  - F-02: the runtime cannot name `content_model`; `legacy_json` is accepted only from a NOLOGIN migration identity.
  - F-03: transitions on a draft version's items, and publishing an empty normalized version, are refused pending
    Product Owner decisions. No transition graph is defined.
  - F-04: historical rows are backfilled as `legacy_json`; only new rows default to `normalized`.
- **WS-DOM-05 — decided (Option A): deferred to Phase 7, `LATER_PHASE`, no longer a Phase 2 blocker.** Its four
  governance questions remain open.
- **PR-8-11-DISPOSITION** — four open draft PRs; PR integration NOT READY.
- **M-05, M-06 — now defined by the Supervisor (2026-11-18), MEDIUM Technical Debt / Security Hardening,
  `NON_BLOCKING_TECHNICAL_DEBT`, not implemented.** M-05: reject duplicate JSON object keys at raw ingress, before
  JSONB. M-06: one shared machine-readable canonicalization vector source for SQL and Python.

## Known bugs / defects found and their state
| Defect | Found | State |
|---|---|---|
| Transfer write barrier did not cover five per-student tables reached only indirectly | Batch 5 | fixed (26 → 31 tables), FRZ-01b/01c/18b/18c |
| Transfer write barrier read only the NEW side of an UPDATE — a frozen student's rows could be moved to another student or orphaned with NULL | Batch 8 | fixed (both sides, forward-only owner key), FRZ-38..43; pre-fix function fails FRZ-38 |
| Notification recipient rule accepted ANY active member for a notification about ANY student | 2026-11-18 (introduced in Batch 8) | fixed, OPS-13c / ISO-43 |
| Secret-scan allowlist exempted whole lines containing "synthetic" | 2026-11-18 (introduced in Batch 7) | fixed, SEC-REPO-05 regression cases |
| Secret scan claimed history coverage it did not have | 2026-11-18 (Supervisor) | implemented SEC-REPO-03 |
| Batch 8 reported a local scan PASS that CI failed | 2026-11-18 (CI) | root cause recorded above |
| Counselor-to-counselor isolation not enforced at the database | Batch 6 (measured), reclassified 2026-11-18 | **OPEN, CRITICAL** |
| Runtime could record a plan transition as the student or as another counselor (F-01) | 2026-11-18 (Supervisor, `d75d039`) | fixed for plan tables, PLN-70..76; other runtime write paths naming an actor remain under WS-ISO-01 |
| Runtime could create new `legacy_json` versions (F-02) | 2026-11-18 (Supervisor) | fixed, PLN-28, PLN-75 |
| Privileged plan identities checked by membership; any direct or indirect member passed; bootstrap trusted a pre-existing role (F-05) | 2026-11-19 (Supervisor, `8df7d5e`) | fixed, F05-00..16, F05-BOOT-01..14 |
| `ADD COLUMN ... DEFAULT 'normalized'` would fail or relabel historical rows (F-04) | 2026-11-18 (Supervisor) | fixed, PLN-M01..M08; the old form fails the migration fixture |

## Failed tests
- At `fc3416ed` in GitHub Actions: the repository secret scan (step 28). Register check skipped (step 29).
- At `467a029`: none, locally or in GitHub Actions (both runs succeeded).
- At `b7d4b28`: register check REG-08 (both runs failed), fixed in `d75d039`.
- At `d75d039`: none in GitHub Actions (passed per the Supervisor); the Supervisor's review found F-01..F-04 instead.
- At `8df7d5e`: none in GitHub Actions (both runs succeeded); the Supervisor's review found F-05 instead.
- At `38f2561`: none in GitHub Actions (both runs succeeded); the Supervisor found F-05 not closed (owner-role chains).

## Open questions
32 register items, all classified in `docs/phase2/UNRESOLVED_ITEM_REGISTER.md` §6. 13 can be resolved partly or
wholly by code once their named decision is made; 19 are decisions, Supervisor definitions or operational
dependencies that code cannot close.

## Next actions
1. The Supervisor confirms the CI failure lines above against the log of runs 43725323633/43725318826.
2. ~~F-05~~ — accepted by the Supervisor at architecture-review level (`fe08a77`). WS-PLAN-01 remains BLOCKING.
3. Platform Security decision on WS-ISO-01 caller binding (option B recommended, A fallback).
4. Supervisor independent review of the PROVISIONAL exit package. **The implementation agent does not approve
   the phase.**

---

### Update 2026-11-20 — WS-ISO-01 caller binding (B, test-only key) and WS-PLAN-01 decisions A2/B1/C1/D1/E1 implemented (draft SQL; synthetic)
- **WS-ISO-01** (`workspace_principal_assertion_draft.sql`, `workspace_counselor_rls_draft.sql`):
  - `establish_principal()` verifies inside the database:
    - an HMAC over the exact assertion bytes;
    - the Workspace;
    - not-before, expiry and lifetime;
    - one-time nonce;
    - that the actor is current.
  - The principal lives for one backend, one transaction and one session role.
  - Verification is `disabled` by default, and the key table can hold only synthetic test keys.
  - Row-level security is ENABLED and FORCED on every student-scoped table. Application roles see and write only
    rows of students the verified counselor may reach. Private notes are author-only, and authorship is bound to the
    principal.
  - ISO-GAP-01..03 are now hard assertions.
- **WS-PLAN-01:** guards enforce A2/B1/C1/D1/E1. Every actor and author is the verified principal. The runtime
  transition and item write path is still closed. Refused as undecided (open):
  - a transition to `planned`;
  - a counselor recording a student status;
  - a student recording a counselor status.
- **Controls:** 21 measured negative controls.
- **Local:** 25 steps, 1155 PASS lines, 0 FAIL, 0 OPEN.
- **Open:**
  - PS-1..PS-4 (production verification);
  - PS-5;
  - student read scope;
  - background-job identity;
  - manager vocabulary;
  - Workspace-level notifications, now invisible to application roles.

### Update 2026-11-20 — Phase 2 gap matrix and decision briefs (docs, plus one test-reporting fix)
- **New:**
  - `docs/phase2/PHASE2_GAP_MATRIX.md`: 33 rows, built from the SQL, tests and workflow.
  - `docs/phase2/decisions/WS_ISO_01_PLATFORM_SECURITY_DECISION_BRIEF.md`
  - `docs/phase2/decisions/WS_PLAN_01_PO_DECISION_BRIEF.md` (A–E)
  - `docs/phase2/F05_PRODUCTION_HARDENING_REQUIREMENTS.md`
- **Newly found and registered:**
  - **WS-REV-01:** review records lack the master-prompt §28 fields and duplicate prevention.
  - **WS-MIG-01:** there is no migration framework.
  - Both are recommended `UNKNOWN_UNTIL_DEFINED`, pending the Supervisor's scope call.
- **Test-reporting fix.**
  - The defect: the group line "PASS WS-ROLE-01..19" included WS-ROLE-17, which is reported separately and is SKIPPED
    in the mirror run of step 22.
  - The fix: the line now reads "01..16,18,19", and the skip says it is not counted.
  - No assertion changed.
- **Fresh disposable cluster** (new PostgreSQL 16.15 cluster, local):
  - 25 steps, 1067 PASS lines, 0 FAIL;
  - 3 OPEN (ISO-GAP-01..03);
  - 1 SKIP (WS-ROLE-17 mirror run).
- **Nothing implemented for WS-ISO-01 or WS-PLAN-01.** Both wait for decisions, which have been requested.

### Update 2026-11-20 — F-05 accepted at architecture-review level; documentation reconciled (docs only)
- CI at `fe08a77336557a51aca36313230b5e082e5ed3ad`: runs [44705627331](https://github.com/nourihamed/persian-educational-counseling-os/actions/runs/44705627331) (job 136184380490) and [44705633469](https://github.com/nourihamed/persian-educational-counseling-os/actions/runs/44705633469) (job 136184402186), both success.
- F-05 accepted by the Supervisor at the current architecture-review level (review of `fe08a77`, 2026-11-20). This is not approval of WS-PLAN-01 as a whole, of WS-ISO-01, of Phase 2, of production runtime plan-item writes, or of production writer or migrator privileges.
- Phase 2: **NOT READY**. WS-ISO-01: **OPEN, CRITICAL**. WS-PLAN-01: **BLOCKING**.
- Open decisions (not made by the implementation agent):
  - who may provision or assume `ws_<key>_synth_plan_writer` and `ws_<key>_plan_migrator` (Platform Security / Operations);
  - a non-superuser provisioning procedure (Platform Security / Operations);
  - production superuser control and audit (Operations / Platform Security);
  - WS-ISO-01 caller binding, with ISO-GAP-01, ISO-GAP-02 and ISO-GAP-03 (Platform Security).
- No SQL, test or workflow file changed in this commit; the F-05 implementation is unchanged.

### Update 2026-11-20 — F-05 follow-up on `38f2561`: owner-role chains (draft SQL; synthetic)
- **Found by the Supervisor:** owner roles were checked only for a direct member, not for a chain.
- **Boundary check.** `plan_identity_boundary_violations()` now:
  - walks every membership chain upward from all nine roles and names any path to an owner or privileged identity;
  - checks expected LOGIN/INHERIT and the five privileged attributes for every role;
  - accepts exactly three memberships: `<x>_login` → `<x>`, without ADMIN.
- **Bootstrap.** It validates every pre-existing application role and aborts on a mismatch; nothing is repaired.
- **Tests:** F05-17..23 and F05-BOOT-15..20. Each shows the real effect of the chain first, for example:
  - replacing `plan_identity_is()`;
  - disabling the guard;
  - an ADMIN-only link used to grant oneself the owner.
- **Measured negative controls:** listed in TEST_PLAN.md.
- **Local:** 25 steps, 1067 PASS lines, 0 FAIL.

### Update 2026-11-19 — Supervisor finding F-05 on `8df7d5e` remediated (draft SQL; synthetic)
- **Scope.** Limited to F-05:
  - No runtime write path enabled and no privilege granted to any runtime role.
  - No caller binding.
  - No Product Owner or Platform Security decision.
  - `SUPERVISOR_REVIEW.md` and `main` untouched. PR #12 not merged, rebased or force-pushed.
- **Mechanism.**
  - `plan_identity_is()` now requires `current_user` to be the recorded role, and the role to have no
    `pg_auth_members` row as role or member and none of the seven attributes.
  - `plan_identity_boundary_violations(inventory)` lists every breach. The bootstrap calls it inside the block that
    writes the identity records.
  - Both functions pin `search_path`.
- **Consequences, stated plainly:**
  - Fixture rows that were written by a superuser are now written as the writer (a superuser is refused).
  - The only way to act as either identity is a superuser session assuming it.
- **Tested on:** PostgreSQL 16.15 locally; CI uses the `postgres:16` image and F05-00 prints its exact version into the log.
- **Local:** 25 steps, 1031 PASS lines, 0 FAIL. Negative controls are listed in TEST_PLAN.md.

### Update 2026-11-18 — Supervisor findings F-01..F-04 on `d75d039` remediated (draft SQL; synthetic)
- Scope limited to the findings, as instructed. No Product Owner or Platform Security decision taken.
  `SUPERVISOR_REVIEW.md` not edited. PR #12 not merged, rebased or force-pushed. `main` untouched. Phase 3 not started.
- Identities: `ws_<key>_synth_plan_writer` (synthetic test writer) and `ws_<key>_plan_migrator` (migration only), both
  NOLOGIN, recorded in `plan_privileged_identities` and checked with `pg_has_role` (superseded by F-05, 2026-11-19: an identity check). No application role is a member.
  An identity holding INSERT but not membership is refused by the triggers (PLN-73..75).
- **Consequence stated plainly:** at schema level no application role can create plan items or transitions now. That
  is the fail-closed outcome F-01 asked for, and it lasts until caller binding exists (WS-ISO-01).
- Local: 25 steps, 938 PASS lines, 0 FAIL. Every new rule has a measured negative control (TEST_PLAN.md).

## Historical reconciliation notes (2026-11-09 onward)

- **Phase 0:** CLOSED; historical documentation foundation.
- **Phase 1:** APPROVED for design/documentation only under D-024. This is not runtime security approval.
- **Phase 2:** **NOT READY.** The Workspace-centric domain model, Control Plane/Workspace split, draft DB functions, per-Workspace roles and synthetic SQL tests are substantially more complete, but important authorization, distributed workflow, operational and independent verification gates remain open.
- **Source of truth:** GitHub. Current work is on PR #12 branch \`docs/product-owner-decisions-consolidation-2026-11-07\`. PR #12 remains OPEN / DRAFT / UNMERGED. No branch changes are in main.
- **PR #8–#11:** Separate open draft PRs; re-fetch and reconcile before any merge. PR #12 does not merge or automatically supersede their Git history. Do not merge any PR without explicit Product Owner instruction.
- **Workspace model:** Organization Workspace or Independent Counselor Workspace is the tenant boundary. Branch is a child of Organization Workspace. Counselor is a Platform User with Workspace membership/assignment, not a tenant root.
- **Control Plane:** owns global student reference, current Workspace owner, ownership generation, global mobile+grade claims, transfer approvals/state and ownership history. Draft SQL includes initial claim admission, HMAC rotation gate and ownership switch.
- **Workspace DB:** owns only Workspace-local educational and operational records, local enrollment projections, capacity and Student Credit ledger. Student Credit uses unit_code CRD; fiat payments/invoices/fees are separate financial records. Draft SQL includes atomic activation + credit debit + capacity reservation + audit event.
- **Security:** Control Plane executor roles and Workspace per-database role/CONNECT boundaries have catalog tests. Production login identities, KMS/HSM, real secret binding, API authorization, object-level access, connection-pool isolation and target-environment verification remain unimplemented/unverified. The previous shared non-login Control Plane function-owner role has been split into transfer, rotation and identity-admission owners; the draft SQL and catalog assertions passed PostgreSQL 16 GitHub Actions run #222 at exact branch HEAD `2f605051440b4198794e710283f0a6d852983316`. Production credentials, KMS/HSM and target-environment verification remain open.
- **Transfer:** MVP direction remains source write-freeze + final snapshot + destination staging/validation + atomic Control Plane ownership switch. Three cumulative approvals remain mandatory. Approval identity/authority and distributed Saga contracts are now documented in `docs/phase2/control_plane/TRANSFER_APPROVAL_IDENTITY_AUTHORITY_CONTRACT.md` and `docs/phase2/transfer/CROSS_WORKSPACE_TRANSFER_SAGA_CONTRACT.md`. The DB switch is not a cross-database atomic transaction; trusted verifier, append-only re-approval schema, durable publisher/consumer, freeze/drain, staging importer and crash recovery remain unimplemented.
- **Initial identity admission:** cp_07 defines atomic student/ownership/claim/contact-index/alias admission, idempotency and active/retiring HMAC alias coverage. Contact-change/reverification design contract is now documented in `docs/phase2/control_plane/CONTACT_CHANGE_REVERIFICATION_CONTRACT.md`; SQL function, proof verifier, API and executable tests remain unimplemented. Database tests cannot prove that trusted service HMAC values derive from the same canonical E.164.
- **Tests:** superseded by the "Verification status at this HEAD" table above. For history: run #231 covered PR #12 HEAD `2104eea56806a6f82b405090bc9cbfbd675d2aec` and run #336 covered SHA `52bd0347b3aba4f816d996065122ed0d362bae5f`; both predate the Control Plane executor-identity fix, the per-recipient Saga delivery redesign and the credit entitlement work, so neither covers the current schema. Do not cite them as evidence for this HEAD. All draft-SQL evidence is synthetic (D-014) and is not API, runtime or production approval.
- **Crosswalk:** D-028 onward are NOT assigned. Any proposed D-028…D-062 sequence remains withdrawn pending collision-free crosswalk and individual PO approval. OQ-A through OQ-G/OQ-F1..F3 are accepted at policy/direction level; Q-007 remains open for detailed legal/age-based authorization.
- **Real data:** Prohibited under D-014. Synthetic data only until independent tenant isolation/auth/RLS/migration/backup/restore/file/API tests pass and the Product Owner gives explicit written approval.
- **Phase 3:** Not authorized. Do not start Phase 3 or merge PRs based on documentation or draft SQL creation alone.

### Update 2026-11-14 — approved Product Owner decisions implemented (draft SQL)

- **Decisions implemented:** PD-2026-11-13-A (fixed assessment question set), B (specialized entities plus a shared Activity layer), C (approval separation with the exception disabled and fail-closed), D (7-day credit return window, student-bound reserved credit, reactivation only inside the original period), F (MEDIUM scope allocation). See `docs/phase2/IMPLEMENTATION_RESPONSE_2026-11-14.md`.
- **Last open HIGH closed at the schema level:** the Saga outbox envelope, delivery state/lease/dead-letter/re-drive, and the Workspace inbox with generation fencing are now reconciled with the Control Plane DDL and tested. The **service-level** Saga behaviour (freeze/drain, snapshot, staging, dispatcher crash, chaos, drift repair) remains SPEC-ONLY.
- **Signature change:** `activate_student_enrollment()` takes a seventh parameter, the entitlement period end. Every call site, grant and role assertion was updated. The database chooses no entitlement duration.
- **New open questions:** OQ-CRD-1 (window semantics — **RESOLVED by the Product Owner on 2026-11-14**: exact 168-hour interval, inclusive boundary), OQ-CRD-2 (reserved credit after the period ends — OPEN), OQ-CRD-3 (source of the entitlement duration — OPEN), OQ-SAGA-1 (signed wire format — OPEN), OQ-SAGA-2 (quarantine resolution — OPEN), OQ-ASM-1 (item bank — OPEN). None was decided by the implementation.
- **Still open, unchanged:** Q-007, Q-020, PS-1..PS-8, the transfer exception approval authority, OQ-D/OQ-E numeric objectives, M-05 and M-06 definitions, disposition of PR #8–#11, and bringing PR #12 up to date with `main`.
- **Last local verification:** PostgreSQL 16.15, cleared cluster, all 18 runnable workflow steps passed (476 PASS assertion lines) plus the Python verifier unit tests. **CI for the pushed commit is NOT verified by the implementation agent** — this session has no GitHub Actions access.

### Update 2026-11-14 (second) — Supervisor findings C-01 and H-01..H-06/M-01 remediated on head `8abbbe3`

- **C-01 was a real defect, not a theoretical one.** One delivery row per event meant the first recipient's acknowledgement stopped retries for the other Workspace. Delivery is now per declared recipient and an event is complete only when every required recipient has acknowledged. See `cp_12_saga_outbox_delivery.sql` and SAGA-R01..R32.
- **Two paths are now deliberately fail-closed, and both are tested as such:** activation cannot establish an entitlement period (OQ-CRD-3) and the inbox cannot apply an event without a verified transport (OQ-SAGA-1, PS-1..PS-4/PS-6). The operational identities hold those entry points and are refused by them. The working application logic lives behind dedicated synthetic identities (`ws_<key>_synth_exec`, `ws_<key>_synth_inbox`) used only by the synthetic suites under D-014.
- **Reactivation** now requires a real counselor role and binds the counselor to the idempotent command.
- **The credit reversal window** is decided from a wall clock read after the entitlement lock; the regression test's sensitivity was verified against the pre-fix code.
- **Status per exit item** is now labelled DONE / PARTIAL / NOT IMPLEMENTED / DEFERRED in `docs/phase2/PHASE2_EXIT_CRITERIA.md` section 3. Saga service behaviour is PARTIAL with the section-10 items NOT IMPLEMENTED; nothing in the lifecycle or Saga work is described as complete.
- **Last local verification:** PostgreSQL 16.15, cleared cluster, all 18 runnable workflow steps passed (504 PASS assertion lines) plus the Python verifier unit tests. **CI on the final HEAD of this batch is NOT verified by the implementation agent.**
- **Still open, unchanged:** Q-007, Q-020, OQ-CRD-1/2/3, OQ-SAGA-1/2, OQ-ASM-1, PS-1..PS-8, OQ-D and OQ-E numeric objectives, the transfer exception approval authority, M-05 and M-06 definitions, disposition of PR #8–#11, and bringing PR #12 up to date with `main`.

### Update 2026-11-14 (third) — OQ-CRD-1 resolved, exact boundary under test

- **OQ-CRD-1 is RESOLVED** (Product Owner, 2026-11-14): the credit reversal window is an exact 168-hour interval from the stored activation timestamp, boundary **inclusive**. Recorded in `DECISION_LOG.md` as a 2026-11-14 clarification without a new D-number, and in `OPEN_QUESTIONS.md` as RESOLVED.
- The rule now lives in `credit_reversal_window_end()` / `credit_reversal_eligible()`. CRD-32..CRD-38 test it with explicit timestamps, including **equality at the deadline**, four time zones, and the absence of a second copy of the interval inside the command. The command's post-lock `clock_timestamp()` read and WS-CRD-LOCK-01/02 are unchanged.
- **OQ-CRD-2 and OQ-CRD-3 remain OPEN.** The production-intended activation path remains fail-closed, and nothing about an expired reserved entitlement was decided or implemented.
- Previous reviewed HEAD `14c76fd` had two successful PostgreSQL 16 CI runs (`43502040401`, `43502032586`). CI for the HEAD produced by this batch is **NOT VERIFIED by the implementation agent**.
- No security boundary was weakened: per-recipient outbox delivery and acknowledgement, fresh timestamp reads after row locks, the fail-closed activation and inbox paths, and D-014 synthetic-only all remain in force.

**Current Gate: NOT READY.** This PR is a draft design/schema delivery vehicle, not phase approval.

---


---

# CURRENT SUPERVISOR WORK ADDENDUM — 2026-11-10

The following design contracts were added on the Phase 2 work branch:
- `docs/phase2/control_plane/CONTACT_CHANGE_REVERIFICATION_CONTRACT.md` — mobile change proof, idempotency, HMAC alias coverage and atomicity.
- `docs/phase2/transfer/TRANSFER_APPROVAL_IDENTITY_AUTHORITY_CONTRACT.md` — trusted principal, authority evidence, exact-case binding, revocation and cutover revalidation.
- `docs/phase2/transfer/TRANSFER_SAGA_OUTBOX_INBOX_RECOVERY_CONTRACT.md` — cross-DB freeze/barrier, snapshot/staging, outbox/inbox, retries and forward-only recovery.
- `docs/phase2/workspace/WORKSPACE_GOVERNANCE_EVENT_CONTRACT.md` — append-only membership/guardian governance events and projection controls.

These are design/acceptance contracts only. No mobile-change SQL/API/verifier, transfer approval verifier/event-schema replacement, distributed Saga workers/controllers, or Workspace governance event schema/command functions have been implemented by these documentation commits. The latest CI for the new branch HEAD is not verified. The latest known successful CI evidence remains limited to its exact earlier SHA and test tree.

The transfer SQL currently accepts three distinct approval kinds when reference strings are non-empty and timestamps valid; this does not prove identity/authority. The Workspace role scalar has been removed, but role grant/revoke event audit and direct-DML controls remain open. Guardian relationship/permission evidence remains mutable and Q-007 remains open.

**Gate remains NOT READY.** D-014 synthetic-only remains in force. PR #12 remains unmerged; no main writes, no Phase 3.

# HISTORICAL ADDENDUM
 — D-023 PRODUCTION / BACKUP INDEPENDENCE TARGET (superseded by D-024) (2026-10-23)

- **Product Owner decision:** target Level 3 infrastructure and administrative independence for production cells, plus Level 4 independent administrative/control boundary for critical backups and recovery. See DECISION_LOG.md D-023.
- **Meaning:** the levels are project-specific targets, not evidence that any provider or deployment meets them. A shared host/account with multiple VMs or Compose stacks is not by itself sufficient. Backup data, keys and deletion/retention controls must be outside ordinary production-account control.
- **Remaining work:** Q-023 remains OPEN until a real hosting candidate is shown to meet this target and the architecture-level host/network/admin trust boundary and provider-global residual are independently reviewed. Vendor, price and capacity measurements may be deferred; the security target may not.
- **Unchanged:** D-020 Alt-5, D-014 prohibition on real student data, Phase 1 NOT READY / NOT APPROVED, Phase 2 NOT STARTED / NOT AUTHORIZED. No code, infrastructure or tests are claimed as created or run.

---

# HISTORICAL SUPERVISOR ADDENDUM (superseded by D-024) — D-022 Q-023 DEFERRAL (2026-10-23)

- **Product Owner decision:** final hosted topology/provider selection is deferred until hosted deployment planning. Continue local-first development only under D-021's restrictions (synthetic data, local-only services, no production secrets).
- **Independent gate impact:** this deferral is not a security waiver. Q-023 remains OPEN and remains a Phase 1 blocker because the Alt-5 cell hosting and administrative compromise boundaries are not yet sufficiently resolved and independently accepted. The exact vendor/pricing/capacity may be deferred; the architecture-level trust boundary may not be silently dropped.
- **Unchanged:** D-020 Alt-5 cell requirements; D-014 real-student-data prohibition; Phase 1 NOT READY / NOT APPROVED; Phase 2 NOT STARTED / NOT AUTHORIZED. No code, infrastructure, or tests are claimed as created or run by this decision.

---

# HISTORICAL PROJECT-STATE SNAPSHOT — superseded by the current status at the top of this file
## Operational Memory — historical snapshot; not authoritative current status

Last Updated: 2026-10-23 (D-021 local-first development direction recorded; Q-023 server topology remains open)
### Current development strategy — D-021

The Product Owner has chosen local development on their own laptop first, with server deployment to be considered when the product reaches an agreed demonstrable stage. See `docs/phase1/LOCAL_DEVELOPMENT_AND_LATER_DEPLOYMENT.md`. Local development should use synthetic data, keep services local-only, protect secrets, and must not be treated as proof of Alt-5 tenant isolation or production readiness.

This does **not** waive phase gates: Phase 1 remains NOT APPROVED / NOT READY, Phase 2 is not authorized until Phase 1 is approved, and real student data remains prohibited under D-014. Q-023 remains open for the eventual server topology; it need not be prematurely chosen just to document the local development workflow, but it remains a target-architecture gap for Phase 1/pilot readiness.

### Current hosting/cell compatibility finding (Q-023)

D-011's original hosting objective remains a product objective, but a single shared VPS must not be treated as an adequate Alt-5 cell boundary against host/root compromise. D-020 requires a separate PostgreSQL cluster/instance and network boundary per cell; D-023 additionally requires Level 3 administrative independence and Level 4 independently controlled critical backups. Provider comparison/selection is deferred until hosted deployment planning as directed by the Product Owner. Q-023 remains OPEN under D-023; see `docs/phase1/HOSTING_CELL_COMPATIBILITY_REVIEW.md`.

D-017's previous global connection arithmetic is an estimate from the earlier topology, not capacity evidence for Alt-5. Per-cell connection and cost budgets remain unmeasured. No vendor, price, host topology, capacity, implementation, infrastructure, or test execution is claimed. Phase 1 remains NOT READY / NOT APPROVED; Phase 2 and real student data remain prohibited.


### HISTORICAL SNAPSHOT — SUPERSEDED BY CURRENT SUMMARY ABOVE (2026-10-24)

**Phase 0 — Product & Business Model Foundation:** recorded as approved by the Product Owner on 2026-10-14 and merged via PR #1. This is a historical project decision; this update does not re-audit the full Phase 0 history.

**Phase 1 — Architecture & Multi-Tenancy:** **NOT APPROVED; supervisor re-review required.** PR #3 (`docs/phase1-tenant-isolation-design` → `main`) remains the delivery vehicle and must be checked live for current head/status. The prior independent review snapshots are historical; current live HEAD must be re-fetched for each review. D-020 has since changed the design, test contracts, and status documentation. No approval is implied by those edits.

- **Current gate:** NOT READY / NOT APPROVED. Q-022 is RESOLVED by D-020: Alt-5 hybrid isolation cells selected, with proposed max two tenants/cell for initial pilot, subject to measured capacity/cost. The normative design, authorization contract, and active test catalog have been rewritten for Alt-5 and require independent re-review. The design now requires a separate database and tenant-specific credential per tenant within each cell; shared cell-level compromise remains a distinct residual. Do not merge PR #3 as if approved.
- **Scope:** design/documentation only. No Phase 1 application code, migrations, database roles, grants, RLS policies, infrastructure, or tests have been created or executed.
- **Prior Option C design:** no longer accepted as sufficient for the selected risk tolerance. D-019 requires a stronger architecture; Q-022 is resolved by D-020 (Alt-5 hybrid cells; maximum two tenants/cell proposed, capacity/cost unmeasured). The prior design is retained for comparison only and must not be implemented unless superseded by a new explicit decision.
- **Prior Option A/GUC and Option C mechanisms:** historical comparison only; neither is the current selected architecture. Q-022 is resolved; the new Alt-5 normative design supersedes the old mechanism.
- **Option D:** not selected and NOT SELECTION-READY.
- **D-017 / Q-016:** pilot uses direct PostgreSQL connections, bounded pool size 1 per tenant per application process; transaction pooling deferred pending a separate decision and compatibility validation.
- **A1 cap:** 10 tenants is provisional, not capacity evidence. Capacity remains ESTIMATE — NOT MEASURED.
- **Q-020:** retention duration and named responsible persons remain unresolved; no automatic tenant-role deletion.
- **Q-021 / D-019:** Product Owner selected option B on 2026-10-23: require stronger architecture; no acceptance of K-L-N/K-O residual risks. Q-022 was subsequently resolved by D-020 (Alt-5). D-009's shared-database mechanism is historical and not the active topology, while the tenant-isolation requirement remains mandatory.
- **Active Alt-5 test contracts:** 46 specifications; 0 implemented; 0 executed; 0 passing. The prior 123-contract catalog is archived for historical traceability and is not current acceptance evidence. All active contracts remain NOT-RUN; environment-only evidence remains unavailable until the relevant implementation/target environment exists.
- **CI:** no successful run has been established as evidence for the current corrected head. Absence of a run is not success.
- **D-014 real-data gate:** real student data remains PROHIBITED until required implementation security tests pass, blocking findings are fixed, capacity and pool limits are measured on the target host, independent implementation review is complete, and the Product Owner gives written approval.
- **Phase 2:** NOT STARTED and NOT AUTHORIZED.

### Decisions affecting Phase 1

- D-013: platform-admin access in MVP is limited, audited, read-only; no BYPASSRLS role and no platform writes.
- D-014: no real student data until the full pilot gate is met.
- D-015: design-selection and pilot-validation criteria are separate; later-phase execution evidence is not a substitute for design review.
- D-016: historical prior direction was Option C; D-019 required stronger architecture and D-020 selected Alt-5. Option D remains unselected; no shared-role fallback is authorized.
- D-017: direct per-tenant connections and size-1 pools for pilot; 10-tenant cap provisional.
- D-018: emergency stop/rollback runbook remains draft and must be exercised before pilot.

### Historical next-action snapshot (superseded by the current Phase 1 gate above)

The former pending action was to independently review the Alt-5 design and test catalog. That design-only review was subsequently completed and recorded under D-024; the current active catalog contains 51 specifications. Q-023 remains a pre-hosting gate, Phase 2 requires separate Product Owner authorization, and real student data remains prohibited under D-014.

---

> **Historical-record boundary:** Sections below this point preserve earlier phase snapshots, checklists and process notes. They are not the live project status and may contain statements that were accurate at the time but are now superseded. Use the current summary at the top of this file for present status.

### Historical phase snapshot (Phase 0, as recorded at the time)
**PHASE 0 — Product & Business Model Foundation — FORMALLY CLOSED by Product Owner on 2026-10-14; PR #1 merged on 2026-10-14**

Authorized by: project owner.
Scope authorized: documentation foundation only. Explicitly NOT authorized: backend code, frontend code, database migrations, authentication, billing implementation, Telegram, SMS, AI, Planning Engine, or any other application feature.

**Phase 0 was formally approved/closed by the Product Owner on 2026-10-14**, following the Supervisor's `APPROVED` documentation/architecture gate. This closure applies to the Phase 0 documentation foundation only; it does not imply runtime security approval or Phase 1 authorization. PR #1 was subsequently merged on 2026-10-14.

### Current Milestone
Pull Request **#1** (`docs/phase0-correction-pass-3` → `main`) was merged on 2026-10-14 using squash merge. GitHub reports merge commit `d68fde54b4e4c86642b74c3bf1ef20fe18edf12b`. Its scope was documentation-only (15 foundation documents); the Supervisor gate was `APPROVED` for documentation/architecture readiness and the Product Owner closed Phase 0 on 2026-10-14. Phase 1 remains not started and not authorized.

### Phase 0 Documentation-Readiness Checklist
This is the checklist `DEVELOPMENT_GUIDE.md` refers to as Phase 0's Definition of Done. Documentation readiness, Supervisor gate status, Product Owner closure, and PR merge are distinct states. Each checked item states the evidence for it; nothing is checked without one.

- [x] All 15 foundation documents present in the repository (14 core + `SUPERVISOR_REVIEW.md`) — verified by repeated `git`/GitHub API file listings across correction rounds (see `CHANGELOG.md`).
- [x] Full cross-document contradiction check after the latest review findings — completed in the 2026-10-13 Supervisor pass across all 15 foundation documents. Six current-state inconsistencies were corrected in `PRODUCT_REQUIREMENTS.md`, `PROJECT_SCOPE.md`, `OPEN_QUESTIONS.md`, `README.md`, `ROADMAP.md`, and this document / `SUPERVISOR_REVIEW.md`. Historical `CHANGELOG.md` entries remain as historical records and are not treated as current operational instructions. This check covers documentation consistency only, not runtime implementation or security.
- [x] No application code, database migration, API endpoint, or automated test exists anywhere in the repository — verified by directory listing (`backend/frontend/tests/scripts/deployment` contain only `.gitkeep`) each round.
- [x] All 15 foundation-document changes from `docs/phase0-correction-pass-3` were merged into `main` through PR #1 on 2026-10-14 (squash merge commit `d68fde54b4e4c86642b74c3bf1ef20fe18edf12b`).
- [x] Independent Supervisor Review and final live follow-up through 2026-10-14 recorded in `SUPERVISOR_REVIEW.md`; the documentation gate is `APPROVED`, limited to Phase 0 documentation/architecture readiness, and does not authorize Phase 1.
- [x] Explicit Product Owner confirmation that Phase 0 documentation is ready to close — **confirmed on 2026-10-14** in the conversation. PR #1 was merged separately; neither action establishes runtime implementation or security verification.
- [x] PR #1 merged into `main` on 2026-10-14; verified live via GitHub PR metadata (`merged: true`, state `closed`).

### Overall Progress
Documentation foundation: present on `main`; PR #1 corrections were merged in squash commit `d68fde54b4e4c86642b74c3bf1ef20fe18edf12b`.
Implementation: 0% (by design — no application code exists).

### Commit and review tracking — keep these states separate
1. **PR #1 merge commit:** `d68fde54b4e4c86642b74c3bf1ef20fe18edf12b` (verified from live PR metadata). This is the PR's squash-merge commit; it is not a claim that `main` has not advanced since then. Verify the live `main` HEAD before relying on a current branch tip.
2. **PR #1 status:** closed and merged. Its historical head was `b2b7f67c7024292c9357617482d16b69b0091b09`; its changes were incorporated into `main` by the squash-merge commit above. Use GitHub for current refs and full history.
3. **Claude authorship/read history:** do not infer that Claude read or authored the `main` HEAD merely because that SHA was verified. Attribute authorship/review only from commit metadata and recorded session evidence; when the precise latest Claude-reviewed/authored commit is not verified, state that it is not established.
4. **Supervisor review and gate:** the documentation gate is `APPROVED`, and the Product Owner formally closed Phase 0 on 2026-10-14. PR #1 is merged; authorization of Phase 1 remains a separate decision.

### Repository Status (GitHub)
- Repository: `https://github.com/nourihamed/persian-educational-counseling-os` — currently **private**. Visibility was toggled public→private during this session by the project owner; treat current visibility as private unless re-verified.
- PR #1 (`docs/phase0-correction-pass-3` → `main`) was merged on 2026-10-14. The merged changes are now part of `main`; the PR is closed. Phase 0 is formally closed. Phase 1 remains unauthorized.
- A detailed, tested-only, environment-separated breakdown of GitHub access is maintained in `OPEN_QUESTIONS.md` Q-011. Summary only (see that file for the full breakdown and caveats):
  - **Claude's environment, this session, via the connected OAuth-based GitHub connector ("Claude" App):** Read tested — succeeded once while the repository was temporarily public, failed (`404`) while private. Write tested — failed once while public (`403 Resource not accessible by integration`); not re-tested while private.
  - **Claude's environment, this session, via a manually supplied, short-lived Personal Access Token pasted into the conversation by the project owner:** Read tested — succeeded (repeatedly). Write tested — succeeded (two pushes to `main`, one push to this branch, one Pull Request created via the GitHub REST API). The project owner was asked to revoke this token after use each time it was supplied.
  - **The Supervisor's connected GitHub tooling (this environment, tested 2026-10-12):** Read and write both succeeded against this private repository. The Supervisor created an isolated test branch from the PR #1 head, created a test file, read it back, deleted it, and verified the file was absent afterward. No application code was added and neither `main` nor PR #1 was modified by that test. The test branch inherits the PR's documentation commits plus test commits and must not be merged or used as a delivery branch. This confirms access in this session only; persistence and reliability across future sessions remain unproven. These results do not change the historical results recorded for Claude's separate environment.
- The two commits currently on `main` (`bd24cf8d...`, `994d4529...`) and branch commits made before the Supervisor's 2026-10-12 write test were recorded as using the manual-token path in the prior session. This correction round is being committed through the Supervisor's connected GitHub tooling. Do not rely on a specific SHA in this file as the latest branch commit; use the live PR #1 head.

### Completed
- [x] 14 foundation documents authored (PRODUCT_REQUIREMENTS, PROJECT_SCOPE, ARCHITECTURE, DATABASE, API, ROADMAP, PROJECT_STATE, DECISION_LOG, OPEN_QUESTIONS, TEST_PLAN, SECURITY, CHANGELOG, DEVELOPMENT_GUIDE, README)
- [x] `SUPERVISOR_REVIEW.md` established as the review record (15th document); formal Supervisor Review with `CONDITIONAL PASS` recorded on 2026-10-12
- [x] Two commits landed on `main` via manual token-based push: `bd24cf8d...` (initial foundation) and `994d4529...` (first correction pass)
- [x] Internal consistency review across documents (naming collision found and recorded: "Plan" — see `DECISION_LOG.md` D-006)
- [x] A second internal consistency issue found and resolved: `PROJECT_SCOPE.md` contained two self-contradictory statements about whether Program Template/Student Plan versioning exists in MVP at all or is deferred entirely to Phase 15, while `ARCHITECTURE.md`/`DATABASE.md` described versioning as a standing architectural principle with no phase qualifier, and `ROADMAP.md` only mentioned "Versioning" under Phase 15. Resolved by proposing a documented MVP Versioning Policy (`DECISION_LOG.md` D-008: minimum viable, auditable versioning is in MVP; only advanced version-management tooling is deferred to Phase 15+) and updating `PROJECT_SCOPE.md`, `ARCHITECTURE.md`, `DATABASE.md`, `ROADMAP.md`, `API.md`, `SECURITY.md`, `TEST_PLAN.md`, `PRODUCT_REQUIREMENTS.md` to be internally consistent with that proposal. **D-008 was initially Proposed and is now Accepted by explicit Product Owner confirmation on 2026-10-10** — see `OPEN_QUESTIONS.md` Resolved / Closed, Q-012.
- [x] Confirmed no production feature implemented in any commit so far

### In Progress
- No application implementation is currently authorized or recorded as in progress.
- PR #1's documentation corrections have been merged into `main`; the follow-up post-merge reconciliation is tracked separately in its own branch/PR.
- Phase 1 has not started and remains unauthorized.

### Blocked
- No active merge blocker remains for PR #1; GitHub confirms it is merged and closed.
- Phase 0 was formally closed by the Product Owner on 2026-10-14. The merge does not authorize Phase 1.
- Cross-session reliability of the Supervisor's connected GitHub access is not yet established. Read/Write succeeded in the 2026-10-12 session; verify access at the start of future sessions until repeated success establishes reliability. Historical Claude-environment results remain separate (see Q-011).
- Historical Phase 1 record: Phase 1 remains NOT APPROVED until the independent review of the actual pushed PR head and Product Owner acceptance. No later document-readiness statement overrides the current gate above. Phase 2 is not started or authorized. Q-001, Q-002, Q-010, and Q-012 decisions remain recorded in `DECISION_LOG.md` / `OPEN_QUESTIONS.md`.

### Known Bugs
— None (no application code exists)

### Failed Tests
— None (no tests exist yet; Phase 0 is documentation-only)

### Open Questions
See `OPEN_QUESTIONS.md` for full detail. The following remain open: **Q-004** (which Iranian payment gateway for the future Phase 22 integration), **Q-005** (Telegram Bot setup), **Q-006** (SMS provider), **Q-007** (Parent default access level), **Q-008** (default calendar/timezone handling), and **Q-009** (initial Risk Engine sophistication). Q-001 (tenant isolation mechanism), Q-002 (MVP boundary), Q-003 (MVP billing depth, resolved under D-010), and Q-010 (Pilot hosting approach) were resolved by explicit Product Owner decisions on 2026-10-12. **Q-011** (GitHub repository access) remains open/qualified, not resolved. **Q-013** was resolved by Product Owner decision D-012 on 2026-10-13: platform-owned `ProgramTemplate` and `ProgramVersion` rows are out of MVP; MVP supports tenant-owned templates and versions only. **Q-012** (MVP Versioning Policy, D-008) is resolved and recorded in the Resolved / Closed section of `OPEN_QUESTIONS.md`.

### Last Verified Commit

**Live source of truth — read this first:** repeatedly re-embedding a "complete" branch commit list in this file has gone stale multiple times on this long-running branch, because the list is necessarily one commit behind the moment it is written (see structural note below). This section no longer attempts to maintain that list. Instead:
- **For the current `main` HEAD, right now:** check the repository's `main` ref or run `git log -1` against the real repository. PR #1 is closed/merged; its URL is retained for historical review: `https://github.com/nourihamed/persian-educational-counseling-os/pull/1`.
- **For the complete, per-commit history of what changed and when:** see `CHANGELOG.md` for dated, human-readable summaries of correction passes (append-only, but some entries group multiple commits and are not a one-entry-per-commit ledger). For the authoritative per-commit history, authorship, timestamps, and exact diffs, use the live GitHub commit history / `git log`.
- `main` (`https://github.com/nourihamed/persian-educational-counseling-os/tree/main`) now contains the PR #1 changes through squash merge. The source branch and PR remain part of the historical record.

**Last independently verified snapshot** (a historical fact about one specific point in time — not a claim about the current state; it goes stale the moment any new commit lands on either ref, exactly like the list it replaces would have, but it does not pretend otherwise):
- **Historical note:** the values below are preserved from an earlier version of this file as a prior snapshot. They were not re-verified as current during the 2026-10-12 Supervisor review; consult the live PR and `main` refs for current values.
- `main` HEAD at that moment: `994d4529c20c4a330bd843bd3ca1a7c9ed1f75ec`.
- This branch's HEAD at that moment: `119b18dacd099ade26c349b4d6bf4d7cf12f058f`.
- Branch-vs-`main` relationship at that moment: **18 commits ahead, 0 behind** — `main` a clean ancestor of the branch, no divergence.
- **This commit's own SHA is not recorded here and will not be**, for the structural reason below — check GitHub for the actual current value.

**Structural note — why no SHA for "this commit" ever appears here:** this file is part of every commit that edits it, so it can never truthfully state "the current HEAD is `<SHA>`" while being written — the SHA depends on this file's final content, which doesn't exist as a hash until after the commit is made. Any attempt to name it would be a guess presented as a fact.

**What is and isn't established by any of the above:** commit existence and current refs must be verified against GitHub. The Supervisor's final documentation gate is `APPROVED`, the Product Owner formally closed Phase 0 on 2026-10-14, and PR #1 was merged on that date. Phase 1 has not been authorized; it does not follow automatically from phase closure or PR merge.

### Last Test Result
— N/A (Phase 0 is documentation-only; `TEST_PLAN.md` defines future test strategy, nothing to run yet)

### Next Actions
1. **PR #1 (`docs/phase0-correction-pass-3` → `main`) was merged on 2026-10-14** by squash merge, commit `d68fde54b4e4c86642b74c3bf1ef20fe18edf12b`. The live PR state is closed and merged; no further merge action is pending for PR #1.
2. Q-011 remains open only for the operational decision and repeatability across sessions: the Supervisor's connected GitHub integration passed a read/write test on 2026-10-12, but persistence has not yet been established. Keep future work on isolated branches and verify access at the start of each session until reliability is demonstrated — see `OPEN_QUESTIONS.md` Q-011.
3. The Product Owner confirmed formal Phase 0 closure on 2026-10-14. PR #1 is now merged; neither closure nor merge authorizes Phase 1.
4. Q-001 (tenant isolation), Q-002 (MVP scope), Q-003 (MVP billing depth under D-010), and Q-010 (Pilot hosting) were decided by the Product Owner on 2026-10-12 and moved to Resolved/Closed. Those earlier product decisions were separate from phase closure; Phase 0 was subsequently formally closed on 2026-10-14. They do not authorize Phase 1.
5. Phase 1 may begin only after the Product Owner separately authorizes it and its required workflow/gates are satisfied. PR #1 is already merged and is no longer a pending prerequisite.


## Phase 2 policy and operational contract updates (2026-11-09)

- Added provider-neutral operational resilience/backup/restore contract; RPO/RTO, replication mode, retention durations, failover mode, provider and measured capacity remain unresolved.
- Added category-based retention/legal-hold implementation contract; no numeric periods or legal compliance are claimed.
- Added Q-007 parent/guardian authority matrix template; high-level per-child/per-permission policy is accepted, but Iran-specific age/legal evidence and dispute rules remain open.
- Added independent Workspace domain schema review; HIGH findings WS-DOM-01..03 and MEDIUM WS-DOM-04..09 remain unresolved.
- All new contracts are design-only. No runtime API, proof verifier, Saga worker, deletion job, KMS/HSM, backup/restore or failover control is implemented by these commits. Phase 2 remains NOT READY.


## Phase 2 exit gate matrix (2026-11-09)

The authoritative Phase 2 design/schema exit criteria and evidence matrix is now `docs/phase2/PHASE2_EXIT_CRITERIA.md`. It separates Phase 2 design/schema obligations from later runtime/production gates, lists current HIGH/MEDIUM blockers, preserves unresolved PO/legal decisions and prohibits treating draft contracts as implementation evidence. Current gate remains NOT READY.


## Phase 2 unresolved decision register (2026-11-09)

`docs/phase2/PHASE2_OPEN_DECISIONS.md` consolidates remaining PO/legal/security/operations inputs, recommended safe defaults and sequencing. It explicitly preserves Q-007, Q-020/OQ-F2, OQ-D/OQ-E and other policy values as unresolved; no numbers or legal rules are inferred.


## Educational domain design contracts (2026-11-09)

Added assessment, deterministic planning and curriculum domain contracts under `docs/phase2/workspace/`. These define versioned assessment/score integrity, normalized planning inputs and explicit PlanItems, and Grade → Subject → Book/Edition → Chapter → Topic → Subtopic ownership/versioning. The current SQL skeleton remains incomplete relative to these contracts; no implementation or test pass is claimed.


## Activity, Student Credit and capacity design contracts (2026-11-09)

Added `ACTIVITY_CLASS_DOMAIN_CONTRACT.md`, `STUDENT_CREDIT_COMMERCIAL_LIFECYCLE_CONTRACT.md` and `CAPACITY_LIFECYCLE_CONTRACT.md`. These specify typed activity/class relationships, the CRD-vs-fiat commercial ledger boundary and lifecycle-safe capacity reservations. Product decisions on refund policy, suspension capacity, class scope and numeric limits remain open; SQL/service implementation and associated tests remain incomplete.


## Workspace authorization privilege correction (2026-11-09)

The Workspace provisioning draft now grants runtime SELECT-only access to membership, role, permission, branch, counselor assignment and guardian relationship/permission tables. The activation function owner is also read-only on these authorization sources. Its DML grants are narrowed to activation needs and column-level lock-only grants; wallet identity is immutable. Catalog tests assert these boundaries. A dedicated audited authorization-management workflow and append-only grant/revoke events remain absent, so authorization changes are fail-closed/unavailable through runtime. Fresh CI for the current branch tree is not verified.


## Workspace governance projection materializer — 2026-11-10

Extended the Workspace governance event draft so supported role, permission and membership lifecycle events update their current-state projections in the same transaction as the append-only event. Membership suspension/end removes active role and permission projections. Idempotent replay is stable even after the original actor becomes suspended; mismatched replay intent is rejected. Guardian changes fail closed pending Q-007 and trusted legal verification.

Provisioning now creates a dedicated non-login per-Workspace `governance_owner`, transfers the projection materializer to it, and grants only the required ledger/role/permission/membership DML. Runtime, worker, exporter and activation function owner have no execute/event-ledger access. No application role is granted execute.

CI run #474 passed the previous event-ledger-only revision. The new projection/owner changes have been committed to the work branch and require a fresh CI run before they are considered verified. The materializer is not a trusted authorization service: authentication/authority references are not cryptographically verified, role-grantability/self-escalation policy is not enforced, and no API adapter exists. WS-DOM-02 remains HIGH/partially remediated; WS-DOM-03 remains HIGH. Phase 2 remains NOT READY. D-014 synthetic-only remains in force.


## Workspace governance projection verification — 2026-11-10

Latest CI run #519 passed all 13 steps on commit `d45753924513f9920f714b966361b9697e8264d5`:
- Control Plane regression and global identity race tests;
- Workspace schema and governance event/projection tests;
- atomic activation, credit and capacity rollback;
- concurrent activation and final-capacity-slot race;
- per-Workspace role provisioning and cross-database denial.

Governance SQL tests now verify transactional role/permission projections, membership lifecycle transition constraints, no stale grants after reactivation, end timestamp, idempotent replay after actor suspension, and denial of application-role access to the materializer. The dedicated governance owner is non-login and least-privileged.

This remains a tested draft, not an approved production implementation. No application role has EXECUTE; cryptographic authority verification, role grantability/self-escalation policy, API adapter/object authorization, guardian legal policy (Q-007), and service-level concurrency tests remain open. Phase 2 remains NOT READY; D-014 synthetic-only remains in force.


## Trusted governance assertion contract — 2026-11-10

Added `docs/phase2/workspace/WORKSPACE_GOVERNANCE_AUTHORIZATION_ASSERTION_CONTRACT.md` as the next design target. It specifies signed assertion claims, exact actor/Workspace/target/action/scope/policy/payload binding, single-use replay prevention, verifier receipt, atomic command handoff, anti-escalation controls and privilege boundaries. No verifier, receipt schema, adapter credential, API or application EXECUTE grant has been implemented.

Product Owner approved the MVP role grantability matrix on 2026-11-10; see `docs/phase2/workspace/PO_DECISION_ROLE_GRANTABILITY_MATRIX_2026-11-10.md`. Organization Manager may invite/activate/revoke counselor memberships only in its own Workspace; Counselor has no delegation; Branch Manager is operational-only within assigned Branch; other staff are operational-only with no delegation; Platform Admin has narrow Governance authority only, including the previously accepted Organization Manager appointment approval, with no general Workspace write or student-data access. Deny-by-default, no self-grant, no privilege escalation, exact-scope enforcement and revocation freshness are mandatory. This closes the Product Owner policy decision only: trusted verifier/adapter, receipt schema, API authorization and executable tests remain unimplemented. Q-007 remains open. WS-DOM-02/03 remain HIGH; Phase 2 NOT READY.

## Issue #13 status (2026-11-10, implementation agent; not a supervisor review)
- Implemented as synthetic drafts: governance proof receipts, verifier and adapter identities, atomic consume-and-apply, verifier interface contract with fail-closed production path.
- Executed locally: receipt suite, concurrency checks, verifier unit tests, governance suite (see evidence). Not executed: GitHub Actions for the commit; full RBAC matrix; revocation freshness (not implemented).
- Open: Platform Security questions PS-1..PS-8 in OPEN_QUESTIONS.md. Phase 2 gate: NOT READY pending independent Supervisor review. Phase 3: not started. Real student data: prohibited (D-014).

## Issue #13 corrective patch (2026-11-11, implementation agent; not a supervisor review)
- Scope: review findings M-01 (retry after expiry), M-02 (state and metadata integrity), M-03 (canonical payload contract v1), M-04 (evidence reconciliation).
- Local draft results for the exact patch: receipt suites, integrity suite, canonical vectors, concurrency (RR-01, RR-02, RR-03), verifier unit tests and canonical unit tests passed in local runs. See TEST_PLAN.md for per-test status and the evidence reference.
- Not implemented: production cryptographic verifier and policy (deferred, PS-1..PS-8), mTLS, revocation freshness across services, production migrations.
- Phase 2 gate: NOT READY pending independent supervisor review. Phase 3: not started. Real student data: prohibited (D-014). PR #12: Draft, open, not merged.

## H-03 status (head 70e37d7, implementation agent; not a supervisor review)
- Implemented as draft: insert guard, consume-only transition, audited revocation, consistent consumed retry, verifier_rt negative tests.
- Executed: full workflow steps 02 to 12 locally on PostgreSQL 16.15 (all pass); GitHub Actions postgres-draft-tests success for 70e37d7 (runs 43158838826, 43158833101).
- Not implemented: production verifier and cryptography (PS-1 to PS-8 deferred), mTLS, revocation policy and propagation, owner/superuser controls.
- Phase 2 gate: NOT READY pending independent Supervisor review. Phase 3: not started. Real data: prohibited (D-014). PR #12: Draft, open, unmerged.

## H-03 corrective status (implementation agent; not a supervisor review)
- Supervisor HIGH finding addressed: consume-only transition no longer depends on the custom session setting. Authorisation is a transaction-scoped grant writable only by the consume definer role.
- Executed locally: receipt_10 (44), receipt_30 (21), receipt_40 (17), receipt_50 (21), race RR-01..RR-03, verifier (15) and canonical (6) unit tests; full workflow steps 02 to 12 on a fresh PostgreSQL 16.15 database: ALL PASS.
- Pending: push, GitHub Actions run for the corrective commit, independent Supervisor review.
- Open: M-05 and M-06 (residual; definitions not in the implementation record). Revocation policy and propagation: deferred. Production verifier and cryptography (PS-1 to PS-8): deferred.
- Phase 2 gate: NOT READY. Phase 3: unauthorized. Real data: prohibited (D-014). PR #12: Draft, open, unmerged.

## Exit-findings batch status (2026-11-13, implementation agent; not a supervisor review)
- Implemented as drafts with executable tests: WS-DOM-01 (assessment reconciliation), WS-DOM-03 (guardian event history), Control Plane approval/revocation events. WS-DOM-02: evidence offered, no new code.
- Details and limits: `docs/phase2/IMPLEMENTATION_RESPONSE_2026-11-13.md`; per-test status: `TEST_PLAN.md`.
- Still open against `docs/phase2/PHASE2_EXIT_CRITERIA.md`: approval-recording command, contact-change schema, Saga event schema reconciliation, Workspace lifecycle/capacity transitions, WS-DOM-04 remainder, MEDIUM items, PR #8–#11 disposition, PR #12 behind main, M-05/M-06 definitions, all Product Owner / Platform Security decisions.
- Phase 2 gate: NOT READY. Phase 3: unauthorized. Real data: prohibited (D-014). PR #12: Draft, open, unmerged.

## Exit-findings second batch (2026-11-13, implementation agent; not a supervisor review)
- Fixed a HIGH defect: Control Plane commands were unusable under their executor roles (deferred triggers ran as the caller). Now covered by `cp_45`.
- Implemented as drafts with tests: contact change (`cp_08`, `cp_09`, `cp_40`, `cp_46`), Workspace archive with capacity release.
- Open: Saga outbox/inbox reconciliation, approval-recording command, reactivation and policy-dependent capacity rows, WS-DOM-04 remainder, MEDIUM items, M-05/M-06, PR #8–#11, PR #12 behind main, all Product Owner / Platform Security decisions.
- Phase 2 gate: NOT READY. Phase 3: unauthorized. Real data: prohibited (D-014). PR #12: Draft, open, unmerged.

## Update 2026-11-14 (fourth) — Batch 1: source transfer freeze and database write barrier

- **A real enforcement gap was found and closed.** Before this commit the Control Plane recorded that a
  source freeze had happened (`transfer_cases.source_freeze_token`, `source_frozen_at`) and the Workspace
  database enforced **nothing**: `grep -rn "freeze\|frozen\|drain" docs/phase2/workspace/*.sql` returned 0
  matches. A source Workspace could keep writing a student's data straight through cutover, so the final
  snapshot could miss writes taken after it. The database half of the OQ-E freeze boundary is now
  implemented in `docs/phase2/workspace/workspace_transfer_freeze.sql`.
- **What is enforced:** a durable freeze record (unique per token and per student/case/source generation);
  a write barrier trigger on **all 26** student-scoped tables, which binds every writer including the
  Workspace runtime role and the SECURITY DEFINER commands because it is a row trigger and not a privilege
  check; an **in-flight transaction barrier** (`FOR SHARE` on the student row inside
  `assert_student_not_frozen`, plus `FOR UPDATE` on the student and all its enrollments in the freeze
  command) with the closing transaction id recorded as `barrier_watermark_txid`; token-bound idempotency;
  unfreeze only before the ownership switch; and a **permanent fence** once the source has observed the
  switch, applied by the inbox projection under a transaction-scoped bypass.
- **A second gap was found while testing it.** `counselor_assignments`, `activation_command_log` and
  `archive_command_log` are student-scoped only through `enrollment_id` and were therefore unprotected by
  the first version of the barrier. The barrier trigger now takes a key-kind argument and resolves the
  student through the enrollment. Coverage went from 23 tables to 26; FRZ-01 asserts the count from the
  catalog rather than from a list in the test.
- **Test evidence:** `workspace_transfer_freeze_tests.sql` FRZ-01..FRZ-37 (37 assertions, 36 PASS lines —
  FRZ-26 and FRZ-27 share one line) and `workspace_freeze_barrier_race.sh` WS-FRZ-BARRIER-01..04 in two
  modes (8 PASS lines). Both are wired into `.github/workflows/phase2-schema-tests.yml` as two new steps,
  taking the workflow from 18 to 20 runnable steps.
- **The race test's sensitivity was verified, and the first version of it was not sensitive.** Removing the
  `FOR SHARE` lock from `assert_student_not_frozen` leaves the `fk` mode passing, because PostgreSQL's own
  foreign-key row lock blocks the freeze for any table with a foreign key to `students`. The `nofk` mode
  writes `class_session_participants`, which is student-scoped but references `class_participants` instead
  of `students`, and that mode **fails** without the barrier. Both modes are run; only `nofk` is evidence.
- **What is NOT claimed.** "Reject new writes, background jobs, file mutations, imports" also covers API,
  worker, import and export surfaces that **do not exist in this repository** (`backend/`, `frontend/`,
  `scripts/`, `tests/` contain only `.gitkeep`). What is claimed is that any surface which reaches this
  database is refused. The outstanding-work count is reported *by the caller*; the database only refuses to
  record a final barrier when it is non-zero, which is not evidence that the controller counted correctly.
  No freeze duration, drain timeout or acceptance threshold is invented. The freeze receipt is not signed
  (OQ-SAGA-1, PS-1..PS-4).
- **A standing claim in this document was false and has been corrected.** "PR #12 behind main" was repeated
  in several entries above and in earlier implementation reports. Measured on 2026-11-14: `main` is at
  `ba5e9d8a9577e5b87e2fc27caaf0bfb07f929114` and `git merge-base --is-ancestor ba5e9d8 HEAD` exits 0, so the
  PR #12 branch already contains all of `main` and there is nothing to synchronize. The historical entries
  above are left unedited as a record; this entry supersedes them on that point. See
  `docs/phase2/UNRESOLVED_ITEM_REGISTER.md`, item BRANCH-SYNC.
- **New:** `docs/phase2/UNRESOLVED_ITEM_REGISTER.md` and `docs/phase2/unresolved_items.json` are the
  mandatory unresolved-item register covering Q-007, Q-020, OQ-CRD-2/3, OQ-SAGA-1/2, OQ-ASM-1, OQ-D, OQ-E,
  PS-1..PS-8, M-05, M-06, WS-DOM-02, the transfer exception approval authority, the PR #8–#11 disposition and
  branch synchronization. Nothing in it is decided by the implementation.
- **Local verification:** PostgreSQL 16.15, cleared cluster (0 leftover databases, 0 leftover roles), all 20
  runnable workflow steps passed, 557 PASS assertion lines, 0 FAIL, plus the Python verifier unit tests.
  **GitHub Actions at this HEAD: NOT RUN.** The agent has no Actions access and cannot read job logs.
- **Still open, unchanged:** Q-007, Q-020, OQ-CRD-2/3, OQ-SAGA-1/2, OQ-ASM-1, PS-1..PS-8, OQ-D and OQ-E
  numeric objectives, the transfer exception approval authority, M-05 and M-06 definitions, and the
  disposition of PR #8–#11.
- Phase 2 gate: **NOT READY** pending independent Supervisor review. Phase 3: unauthorized. Real data:
  prohibited (D-014). PR #12: Draft, open, unmerged. **This entry is not approval of anything.**

## Update 2026-11-14 (fifth) — Batch 2: clock discipline at security decision points

Batch 1 was pushed as `cc8cd6449223943cbc6e360e677f4cb2ba37090f` (verified against the repository:
15 files, +1874/−11, parent `ad3bf28`, PR #12 still Draft/open/unmerged). Its GitHub Actions result has
**not** been reported to the implementation agent.

- **One defect found three times, each instance demonstrated before being fixed.** In PostgreSQL `now()`,
  `transaction_timestamp()` and `CURRENT_TIMESTAMP` return the **transaction start** time and do not
  advance. Any expiry, freshness or authorization decision made from them can be defeated simply by
  holding a transaction open.
  1. **`consume_governance_receipt_and_apply()`** — the governance proof-receipt validity window. A receipt
     with a two-second lifetime was **consumed and applied four seconds after expiry**, ending up
     `consumed` with a governance event attached. This mattered more than an ordinary off-by-one: the
     expiry window is the **only** freshness control this database has, because revocation propagation
     across service handoffs is PS-8 and deferred. The existing RC-21/RC-22 missed it because their
     receipts were already outside the window when the transaction began, which `now()` handles correctly.
  2. **`change_student_mobile_contact()`** — the one-time contact-change proof window. Same shape. This
     proof authorizes changing a student's **global** contact identity, so its expiry is the whole point
     of it being one-time.
  3. **`guardian_permissions_effective`** — the view whose own comment states it is "the ONLY read shape
     that may be used for a guardian access decision". With `now()`, a permission that expired during a
     transaction still read as effective, and that stale read *was* the access decision.
- **Fix:** each site reads `clock_timestamp()` once, after the relevant row lock — the pattern the H-01
  remediation established for the credit reversal window. `archive_student_enrollment()` and
  `change_student_mobile_contact()` now also write their stored timestamps from that same `v_now`, so the
  audit time equals the decision time. **No clock-skew tolerance was introduced:** PS-5 is deferred and
  none is invented.
- **A guard against a fourth instance.** Because three independent instances existed, fixing them is not
  enough. `docs/phase2/workspace/tests/workspace_clock_discipline_tests.sql` CLK-01 scans the **catalog** —
  every SECURITY DEFINER function and every view — and fails **by name** on any transaction-start clock,
  with one reviewed allowlist entry (`append_workspace_governance_event`, which writes a stored value and
  decides nothing). CLK-02 narrowly pins the previously defective windows so an over-broad allowlist edit
  still fails. CLK-03 is behavioural, because a static check alone would miss a view rewritten to compare
  against a column holding a stale value.
- **Every new test was shown to FAIL against the pre-fix code.** RC-FRESH-01 fails with `v_now := now()`;
  CC-FRESH-01 fails with the pre-fix contact-change command; CLK-01 fails naming
  `view guardian_permissions_effective` with the pre-fix view. Sensitivity is measured, not assumed.
- **New tests:** `receipt_60_freshness_tests.sql` RC-FRESH-01..04 (5 PASS lines),
  `cp_47_freshness_tests.sql` CC-FRESH-01..03 (3), `workspace_clock_discipline_tests.sql` CLK-01..03 (3).
  The workflow goes from 20 to 21 implementation test steps plus the documentation check.
- **Batch 2 status against the Supervisor brief:** the proof-receipt boundary, `verifier_rt` narrow
  registration, independent binding revalidation at the command boundary, atomic consumption with event
  append and projection update, replay protection and idempotency, and the negative/tampering/claim
  mismatch/revocation/concurrency tests were **already implemented** in earlier work (RC-01..31, M01/M02
  series, RR-01..03). This batch adds the freshness dimension that was missing and fixes what it found.
  **Still NOT IMPLEMENTED and not claimed:** the authenticated private service channel (PS-6), production
  signature verification (PS-1..PS-4, verifier stays fail-closed), and end-to-end revocation freshness
  (PS-8, no services exist).
- **Local verification:** PostgreSQL 16.15, cleared cluster (0 leftover databases, 0 leftover roles), all
  21 implementation test steps passed, **568 PASS assertion lines**, 0 FAIL, plus the Python verifier unit
  tests, plus the documentation consistency check reported separately. **GitHub Actions at this HEAD:
  NOT RUN.**
- **Still open, unchanged:** Q-007, Q-020, OQ-CRD-2/3, OQ-SAGA-1/2, OQ-ASM-1, PS-1..PS-8, OQ-D and OQ-E
  numeric objectives, the transfer exception approval authority, M-05 and M-06 definitions, and the
  disposition of PR #8–#11. See `docs/phase2/UNRESOLVED_ITEM_REGISTER.md`.
- Phase 2 gate: **NOT READY** pending independent Supervisor review. Phase 3: unauthorized. Real data:
  prohibited (D-014). PR #12: Draft, open, unmerged. **This entry is not approval of anything.**

## Update 2026-11-14 (sixth) — Batch 3: Student Credit lifecycle verified item by item

Batch 2 was pushed as `7da927dea352f290dbe1583be51c723b1d228363` (verified: 14 files, +858/−14, parent
`cc8cd64`). Its GitHub Actions result has **not** been reported to the implementation agent.

Batch 3 asked for **verification** of thirteen credit-ledger properties rather than new features. Each was
checked against what the tests actually assert. Full matrix:
`docs/phase2/IMPLEMENTATION_RESPONSE_2026-11-14.md` section 8.

- **Three properties had no test at all**, including the most important one: *"no negative or inconsistent
  spendable balance."* The guard enforcing it existed and worked — a probe confirmed it refuses an
  over-debit — but **nothing in the suite ever exercised that branch.** CRD-27 tested the balance
  *identity*, which is a different claim: an identity can hold perfectly while the balance is negative.
  Now covered serially (CRD-39/40/41, including a control that exactly the available balance *is*
  accepted) and concurrently (WS-CRD-LAST-01..05).
- **Defect 1 — a compensating reversal could name the wrong student.** The guard checked the wallet, the
  amount and single use, but not the student. Demonstrated: a reversal naming a different student was
  accepted (`student_matches_debit = f`). Severity **MEDIUM**, stated precisely: no application role holds
  INSERT on the ledger — CRD-46c/46d now prove it — so it was not reachable from the runtime. It still
  mattered because the brief requires the tie to the student explicitly, the balance arithmetic reads
  `student_entitlements` so the numbers would have agreed while the attribution was wrong, the ledger is
  **append-only** so a wrong attribution could never be corrected, and OQ-CRD-2 will read that attribution.
  Fixed; CRD-42/43.
- **Defect 2 — the ledger guard existed twice and the weak copy was reachable.** A weak copy sat beside the
  table in `workspace_schema_draft.sql` (no wallet lock, **no balance check**) and a strong
  `CREATE OR REPLACE` copy in `workspace_activation_transactions.sql`. The strong copy won in the normal
  load order, so no previous credit result was wrong — but one CI step loads the schema draft **without**
  the activation file, so the weak path was live, and a maintainer hardening the obvious copy would have
  edited dead code. Consolidated into one definition in the file that creates the table; CRD-47 asserts
  from the catalog that exactly one guard exists and still carries the balance check, the student binding
  and the row lock.
- **Also newly covered:** append-only on UPDATE as well as DELETE (CRD-44/45 — CRD-05 covered DELETE only),
  negative grants and unknown wallets (CRD-46/46b), and direct ledger writes by the runtime and worker
  roles (CRD-46c/46d).
- **Every new test was measured against a control.** Student binding removed → CRD-42 fails. Weak duplicate
  guard restored → CRD-39 fails. Wallet row lock removed → WS-CRD-LAST-02/03/04/05 fail with measured
  `debits=2 ledger=-1 available=-1 entitlements=2 capacity=2`. The pre-existing credit suite is unchanged
  at 43 PASS lines, exit 0.
- **A trap is recorded in the race script**, because it had already cost this project once: in the no-lock
  control the "second activation is blocked" observation **still appears**, since the activation command
  takes other row locks and B blocks on those regardless. That observation proves only that the sessions
  overlapped; the outcome assertions are the evidence. The first version of the Batch 1 barrier race was
  worthless for exactly this reason.
- **OQ-CRD-1 was not reopened** (resolved; CRD-32..38 unchanged). **OQ-CRD-2 and OQ-CRD-3 were not
  decided:** nothing expires, extends, forfeits or automatically returns a reserved entitlement, and the
  production activation path stays fail-closed on the entitlement period.
- **Local verification:** PostgreSQL 16.15, cleared cluster (0 leftover databases, 0 leftover roles), all
  21 implementation test steps passed, **585 PASS assertion lines**, 0 FAIL, plus the Python verifier unit
  tests, plus the documentation consistency check reported separately. **GitHub Actions at this HEAD:
  NOT RUN.**
- Phase 2 gate: **NOT READY** pending independent Supervisor review. Phase 3: unauthorized. Real data:
  prohibited (D-014). PR #12: Draft, open, unmerged. **This entry is not approval of anything.**

## Update 2026-11-15 — Batch 4: assessment, exam and analysis model (re-verified before commit)

Batch 3 was pushed as `db94176f588ef1fed5de26360fa9399eeac21efd` (verified: 11 files, +751/−70, parent
`7da927d`). Its GitHub Actions result has **not** been reported to the implementation agent.

**A process note that belongs in the record.** The Batch 4 schema, tests and section 9 of
`IMPLEMENTATION_RESPONSE_2026-11-14.md` were written on 2026-11-14 at 22:46 but were **never committed**
before the session paused. They were found as uncommitted working-tree changes on 2026-11-15. Rather than
trusting those notes, the entire workflow was re-run from a cleared cluster and the documented controls
were re-executed. That re-verification reproduced the main evidence and **found one claim in those notes to
be false** (below), which is the reason for not taking them at face value.

- **Four of the brief's eight items were already implemented**, and each was verified by probe rather than
  by reading documentation: the immutable published question set and order, normalized membership and
  ordering, responses bound to the exact version by two composite foreign keys (declaratively, with no
  trigger), and the attempt's scoring snapshot equalling the published version's. Probing also confirmed
  that **publishing a `per_attempt` version is refused**, so adaptive delivery is genuinely disabled for
  MVP rather than merely discouraged by a comment — and that a submitted attempt's responses are immutable,
  which is what makes a score's inputs unable to drift.
- **Four things were missing and were built:** an explicit scoring `algorithm` and positive integer
  `algorithm_version` required in every policy snapshot (previously `{}` published successfully, so a
  historical score was unattributable); `exam_definition_versions` with per-subject question counts;
  `exam_subject_results` reconciled against the aggregate by a deferred constraint trigger; and append-only
  `test_analysis_versions`, which gives a reclassification somewhere to go now that submitted responses are
  immutable.
- **A false claim in the 22:46 notes, corrected.** They stated that removing `COALESCE(..., false)` from
  `scoring_policy_is_well_formed()` made the suite fail. It does **not**: with the
  `length(btrim(COALESCE(p->>'algorithm','')))>0` conjunct still present the chain evaluates to `false`
  rather than NULL, because `NULL AND false` is `false`. Measured: the predicate returned `false` for `{}`
  and the suite passed. The control that actually isolates the trap is a **type-comparison-only** predicate,
  against which EXM-42 fails naming "empty object, no algorithm_version, no algorithm" and EXM-01 fires
  first in the full suite. Both the narrative and the evidence table now say this.
- **A second control was also invalid and is recorded as such.** Dropping the reconciliation trigger breaks
  EXM-26's own setup, because the test runs `SET CONSTRAINTS exam_results_reconcile_trg IMMEDIATE` to
  observe the deferred check. Neutralising the trigger **body** instead is the valid control, and EXM-26
  then fails with the exact expected message.
- **The two facts the predicate defends against were measured, not recalled:**
  `jsonb_typeof('{}'::jsonb -> 'algorithm') = 'string'` is **NULL**, and a `CHECK` constraint whose
  expression is NULL **accepts** the row.
- **A stale exit-criteria row was corrected.** `PHASE2_EXIT_CRITERIA.md` said "Per-subject exam results and
  the custom error taxonomy — **NOT IMPLEMENTED**". Per-subject exam results **are** implemented, so that
  row understated the project to a reviewer. It is now split into what is done and what genuinely is not:
  the custom error taxonomy table, rank/percentile/cohort comparison, and scoring formulas (absent by
  design).
- **OQ-ASM-2 was added to the unresolved-item register** (which algorithm names are permitted, and how
  versions are governed). The shape is enforced; the value set deliberately is not. Nothing about scoring
  behaviour was decided.
- **Local verification:** PostgreSQL 16.15, cleared cluster (0 leftover databases, 0 leftover roles), all
  21 implementation test steps passed, **627 PASS assertion lines** (step 11 rose from 116 to 158, which is
  exactly the 42 EXM assertions), 0 FAIL, plus the Python verifier unit tests, plus the documentation
  consistency check reported separately. **GitHub Actions at this HEAD: NOT RUN.**
- **Still open, unchanged:** Q-007, Q-020, OQ-CRD-2/3, OQ-SAGA-1/2, OQ-ASM-1, OQ-ASM-2, PS-1..PS-8, OQ-D and
  OQ-E numeric objectives, the transfer exception approval authority, M-05 and M-06 definitions, and the
  disposition of PR #8–#11. The register now carries 24 items.
- Phase 2 gate: **NOT READY** pending independent Supervisor review. Phase 3: unauthorized. Real data:
  prohibited (D-014). PR #12: Draft, open, unmerged. **This entry is not approval of anything.**

## Update 2026-11-15 (second) — Batch 5: curriculum, plan and activity domain

Batch 4 was pushed as `0b5a6443f883f8dfe056248f1d3741cd36e244d6` (verified, parent `db94176`). Its GitHub
Actions result has **not** been reported to the implementation agent.

- **Five per-student tables had no transfer write barrier.** The Batch 1 barrier derived its table list
  from a **column scan** — anything carrying `student_id` or `enrollment_id` — which by construction cannot
  see a table whose ownership runs through another table. Batch 1 was already caught by this once
  (`counselor_assignments` and the two command logs, FRZ-18) and the fix then added an `enrollment`
  resolution path **without asking what else the scan was blind to**. Auditing reachability from the
  catalog found: `student_plan_versions` (via `student_plans`), `test_responses` (via `test_attempts`),
  and `guardian_permissions`, `guardian_link_events` and `guardian_permission_events` (via the guardian
  link, the last of those two hops out). While a student was frozen, their plan versions, test responses
  and **guardian authority** could all still be written through cutover — so the destination Workspace
  would import a different authority set than the source froze. Coverage went from **26 tables to 31**.
- **The audit is now a test, which is the part that matters.** FRZ-01 asks "does every table in the
  coverage view have a trigger?", which cannot catch a table missing from the view. **FRZ-01b** asks the
  opposite question from the catalog — which tables have a foreign key into a per-student table and carry
  no barrier — and fails **by name**. Its eleven reviewed exclusions each state one of only two valid
  reasons: the table is **shared** between students, or it must be writable **while** frozen because it is
  part of the freeze machinery (`workspace_inbox_events` is in that group, and not as a technicality: the
  inbox projection is what *applies* the fence). FRZ-01b found the three guardian tables as soon as it was
  written, after the first two had been fixed by hand.
- **FRZ-18b/18c test the new paths behaviourally**, because a two-hop lookup that silently returned NULL
  would leave the barrier open while still reporting as covered — `assert_student_not_frozen()` returns
  early for a NULL student.
- **Subtopics built; the rest scoped out by the Product Owner.** Both `CURRICULUM_DOMAIN_CONTRACT.md` and
  `DETERMINISTIC_PLANNING_DOMAIN_CONTRACT.md` are marked **DRAFT / NOT APPROVED**, and the brief says to
  resolve them "only to the extent already approved". The scope question was **put to the Product Owner
  rather than decided**, and the answer on 2026-11-15 was **subtopics only**. `subtopics` is built, ordered
  within its parent, archivable rather than deletable, and tested (CUR-01..CUR-10).
- **Deletion behaviour is now asserted rather than assumed.** There is **no `ON DELETE` action anywhere**
  in the Workspace schema, so every foreign key restricts — but nothing checked it. CUR-09 fails if any
  foreign key in the schema has a non-default delete action, because a cascade or set-null would destroy
  the educational history the curriculum contract requires be preserved.
- **Verified without change:** ProgramTemplate and plan versioning with publication immutability on both
  UPDATE and DELETE; Activity's typed source columns with composite foreign keys and the kind/source
  agreement CHECK (no polymorphic reference anywhere); and the Class/ClassSession/ClassParticipant chain,
  where `class_session_participants` carries composite foreign keys to both the session's class and the
  class participant, so cross-class and cross-student rows are refused declaratively.
- **Two register items added, with options and recommendations, decided by nobody here:** **WS-DOM-05**
  (Book/Edition, curriculum successor mapping, content ownership, subtopic mastery — recommendation: Phase 7)
  and **WS-PLAN-01** (normalized `plan_items` instead of the opaque `plan_content` blob, which is the exact
  shape the planning contract rejects — recommendation: data model in Phase 2, engine in Phase 12, the
  split that already worked for Activity). The register now carries **26 items**. CUR-10 asserts the
  Book/Edition tables are absent so the gap stays explicit and dated.
- **Local verification:** PostgreSQL 16.15, cleared cluster (0 leftover databases, 0 leftover roles), all
  **22** implementation test steps passed, **641 PASS assertion lines**, 0 FAIL (curriculum 10 new; the
  freeze step rose from 36 to 40), plus the Python verifier unit tests, plus the documentation consistency
  check reported separately. **GitHub Actions at this HEAD: NOT RUN.**
- **Still open, unchanged:** Q-007, Q-020, OQ-CRD-2/3, OQ-SAGA-1/2, OQ-ASM-1/2, WS-DOM-05, WS-PLAN-01,
  PS-1..PS-8, OQ-D and OQ-E numeric objectives, the transfer exception approval authority, M-05 and M-06
  definitions, and the disposition of PR #8–#11.
- Phase 2 gate: **NOT READY** pending independent Supervisor review. Phase 3: unauthorized. Real data:
  prohibited (D-014). PR #12: Draft, open, unmerged. **This entry is not approval of anything.**

## Update 2026-11-15 (third) — Batch 6: adversarial privilege review

Batch 5 was pushed as `4306d5660647bc71fcb947081d4d94e008b95fed` (parent `0b5a644`). Its GitHub Actions
result has **not** been reported to the implementation agent.

Batch 6 is an adversarial review. The assertions in `workspace_privilege_hardening_tests.sql` interrogate
the **catalog** and state properties that must hold for **every** SECURITY DEFINER function and **every**
role, rather than checking a list of remembered names — because reading the SQL is exactly how the first
finding below survived several previous passes.

- **Finding 1, fixed: a SECURITY DEFINER function was owned by a superuser.**
  `receipt_consume_grant_guard()` is created in `receipt_01_schema_draft.sql`, **before**
  `receipt_02_roles_draft.sql` creates the role that should own it, so it inherited the loader's identity —
  `postgres` — and nothing reassigned it. A SECURITY DEFINER function owned by a superuser executes **as
  superuser**.
  **Severity MEDIUM, measured not asserted:** it returns `trigger` and PostgreSQL refuses to call a trigger
  function directly; its body reads one schema-qualified table and raises; and shadowing an unqualified
  name would need `CREATE` on a schema on its path, which the review **measured** that neither `PUBLIC`
  nor any application role has. It was unnecessary privilege and a deviation from this project's own rule
  that every definer function is owned by a dedicated NOLOGIN role. Ownership is now reassigned and its
  search_path tightened from `pg_catalog, public` to `pg_catalog, pg_temp`.
- **A finding deliberately not inflated.** Two definer functions still carry `public` on their search_path.
  The first instinct was to call that a vulnerability; the measurement says it is not exploitable here,
  because no application role can `CREATE` in `public`. So SEC-02 was split: SEC-02 requires a pinned
  search_path, **SEC-02b asserts the precondition that actually carries the weight** (no `PUBLIC` and no
  application role may `CREATE` in `public`, which if it ever changed would make every such function
  exploitable at once), and SEC-02c reports the remaining two as a NOTICE tracked as hardening and
  explicitly **not** claimed as fixed. Claiming a vulnerability that cannot be exercised would mislead a
  reviewer as much as hiding one that can.
- **Finding 2, NOT fixable in a batch: counselor-to-counselor isolation is not enforced.** The brief
  requires that no counselor may access another counselor's students, even within the same Organization.
  **Measured:** no row-level security on any table, and the Workspace runtime role holds `SELECT` on **47
  tables in full**. Isolation in this design is **per-Workspace** — one database per Workspace with no
  cross-database grants, which the cross-database denial step does test — so every counselor inside a
  Workspace shares one runtime identity. This is an architecture decision nobody has made, so it is
  recorded as **WS-ISO-01** with four options and a recommendation (row-level security keyed to the
  responsible counselor assignment — noting the session identity must **not** come from a GUC the
  application sets, because this project already rejected session GUCs as an authorization mechanism in
  finding H-03). **SEC-10 asserts the negative result as a test rather than prose** and fails if the
  situation changes in either direction, so the record cannot silently rot.
- **No further defects found.** No unpinned definer search_path; no definer owner that can log in; no table
  owned by an application role; no Workspace role with superuser/createrole/createdb/bypassrls; no table
  privilege held by `PUBLIC`; no unexpected PUBLIC execute; every table has a primary key; no foreign key
  with a cascade or set-null; no polymorphic reference without integrity.
- **SEC-08 records a limitation instead of hiding it.** Every guard here is a trigger or a CHECK, and a
  table owner can disable triggers. SEC-08 asserts the owner **can** do so, so nobody later mistakes the
  write barrier for something that binds the owner. Containing that identity is operational credential
  control, outside the database.
- **Not claimed:** object-level authorization, IDOR and uniform-404 behaviour (API properties, no API
  exists); background-job tenant context (nothing runs as the worker role); file and notification
  ownership (neither subsystem exists); RLS policies and therefore RLS bypass testing — the absence is the
  finding.
- **Local verification:** PostgreSQL 16.15, cleared cluster (0 leftover databases, 0 leftover roles), all
  22 implementation test steps passed, **653 PASS assertion lines**, 0 FAIL (the governance receipt step
  rose from 111 to 123, which is exactly the 12 SEC assertions), plus the Python verifier unit tests,
  plus the documentation consistency check reported separately. **GitHub Actions at this HEAD: NOT RUN.**
- **Sensitivity measured:** with the `ALTER FUNCTION ... OWNER TO` line removed, the owner is `postgres`
  again and **SEC-01 fails** naming the function (exit 3).
- The register now carries **27 items** (WS-ISO-01 added).
- Phase 2 gate: **NOT READY** pending independent Supervisor review. Phase 3: unauthorized. Real data:
  prohibited (D-014). PR #12: Draft, open, unmerged. **This entry is not approval of anything.**

## Correction 2026-11-15 — "PR #12 is not behind main" was WRONG and is retracted

An earlier entry in this document, and the BRANCH-SYNC item in
`docs/phase2/UNRESOLVED_ITEM_REGISTER.md`, stated that the PR #12 branch was **not** behind `main` and
marked the original claim as "factually corrected". **That retraction was itself wrong.** The original
claim was right: the branch **is** behind `main`.

**The error.** `main`'s tip was read from the `base.sha` field of the open pull request objects. That field
records the base commit **as it stood when each PR was created** (`ba5e9d8`), not `main`'s current tip.
Four PRs all reporting the same value looked like corroboration; it was one stale value four times.

**Measured correctly on 2026-11-15:**

```
main tip:                                    5bb8e4ed07a7c770ecba7c506a1d2c278e36b6d6
merge base with the PR #12 branch:           ba5e9d8a9577e5b87e2fc27caaf0bfb07f929114
git merge-base --is-ancestor 5bb8e4e HEAD -> fails (the branch does NOT contain main)

on main, not on the branch:
  4004360  test(phase2): verify claim admission executor is isolated  (added cp_30_role_privilege_tests.sql)
  5bb8e4e  revert: remove accidental malformed Phase 2 test from main (removed it again)

git diff ba5e9d8 5bb8e4e  ->  0 changed files
```

**Both halves matter.** The branch is behind by **two commits**, and the **net content difference is zero**,
because `main` added a file and then reverted it. Nothing from `main` is missing from the branch, and
merging `main` would bring no file changes. The branch's own
`docs/phase2/control_plane/tests/cp_30_role_privilege_tests.sql` was written independently here and is
unaffected by either commit.

No rebase, merge or force-push has been performed. The recommendation is to resolve this together with the
PR #8–#11 disposition, which will move `main` anyway. **Every earlier statement in this document that the
branch is "not behind main" is superseded by this entry.**

## Update 2026-11-15 (fourth) — Batch 7: contact identity, HMAC rotation and concurrency

Batch 6 and the branch-synchronization retraction were pushed as `b095dbc7` and `65b5f735`. Their GitHub
Actions results have **not** been reported to the implementation agent.

- **The two races the brief listed as NOT RUN are now run, and they pass.** Both serializations were
  designed in and documented in comments, and neither had ever been executed — a comment claiming mutual
  exclusion is not evidence of it.
  - **Race A:** a contact change holding `FOR SHARE` on `identity_write_gate` blocks
    `begin_identity_hmac_rotation()`, which takes `FOR UPDATE` on the same row. Without it, a contact
    change could write an identity alias at a key version the rotation is retiring.
  - **Race B:** a contact change holding `FOR UPDATE` on the student's `student_ownership` row blocks
    `switch_student_ownership()`. Afterwards the generation advances 1 → 2, ownership moves to the
    destination, and a contact change citing the pre-switch generation is refused. Without it, the
    globally unique contact identity could be written against an owner and generation that no longer hold.
  - Coordination is deterministic: the first session waits for an explicit go signal, sent only after the
    driver has **observed** the second blocked in `pg_stat_activity`, and the first is signalled to commit
    rather than killed. **Sensitivity measured:** removing the gate lock fails race A; removing the
    ownership lock fails race B.
- **A defect I nearly reported that was my own test's fault.** The first version of race B shared a
  database with race A and reported that the ownership switch **did not block** — which reads exactly like
  a missing lock. Diagnosing before reporting showed race B had reused a proof bound to a *different*
  student; the command correctly refused it, the transaction aborted, its locks were released, and the
  switch then ran unblocked. `change_student_mobile_contact()` does take `FOR UPDATE` on
  `student_ownership`. The fix was **isolation, not a weaker assertion**: each race now runs in its own
  fresh database, and the reason is written into the script.
- **Two confidentiality tests were wrong first and the schema was right.** CID-03 initially banned every
  text column on the key-version tables and flagged `mobile_encryption_key_versions.key_manager_ref` —
  which is a non-secret KMS/HSM identifier, exactly the external-custody shape the register recommends for
  PS-3. CID-05 initially looked for fingerprint uniqueness on `student_contact_index`, which deliberately
  has none: it answers what a student's contact is, not who owns a contact. The real rule is a partial
  unique index on `enrollment_claim_identity_aliases` over `(key_version, mobile_hmac, grade_key)` across
  `active` **and** `transfer_pending` claims — so two students **can** share a fingerprint in the contact
  index, and what they cannot do is hold live claims on it in the same grade under the same key. Both
  tests were corrected to assert the real design, and that design is now stated in the test rather than
  left to be inferred.
- **No key material and no plaintext contact in the database** (CID-01..CID-04), and **no secret material
  in the repository**: the new `check_no_secret_material.py` scanned 147 tracked files and 186 paths ever
  added in Git history with no findings, and was verified sensitive by planting a fake Iranian mobile
  number and a fake API key (all three expected findings fired). It is reported as a **repository check,
  never as implementation evidence**, and states its own limit: a pattern scan proves the absence of known
  shapes, not the absence of secrets.
- **Local verification:** PostgreSQL 16.15, cleared cluster, all 22 implementation test steps passed,
  **749 PASS assertion lines**, 0 FAIL. **Read that number carefully:** only **12** of the increase from
  653 are new assertions (6 CID-RACE + 6 CID). The rest of the contact step's rise from 51 to 147 is
  `cp_30` and `cp_40` **re-running** in the two isolated race databases, which is repeated execution of
  existing coverage and not new coverage. Plus the Python verifier unit tests, and two checks reported
  separately and explicitly not counted as implementation evidence (the register consistency check, 6
  lines, and the repository secret scan, 2 lines).
- **A local harness limitation, recorded.** The repository secret scan initially reported FAILED in the
  local runner, because that runner executes every step as the `postgres` user and Git refuses a
  root-owned repository to another user (`dubious ownership`). The check itself is correct — it
  **fails closed** when it cannot scan, rather than passing silently — and it passes when run as the
  repository owner, which is how CI runs it. The local runner now runs database-free steps as the owner.
- **GitHub Actions at this HEAD: NOT RUN.**
- Phase 2 gate: **NOT READY** pending independent Supervisor review. Phase 3: unauthorized. Real data:
  prohibited (D-014). PR #12: Draft, open, unmerged. **This entry is not approval of anything.**

## Update 2026-11-15 (fifth) — Batch 8: files, notifications, retention and operational contracts

Batch 7 was pushed as `d6d81f8b32719a0f9f3d8316c866e4625d361f8e` (verified against the local commit: same
message, 9 files, +894/−1). Its GitHub Actions result has **not** been reported to the implementation agent.

- **The most important finding of this batch is a defect in Batch 1's own work: the transfer write barrier
  only looked at ONE SIDE of an `UPDATE`.** It resolved the student from `NEW` on `INSERT` and `UPDATE` and
  from `OLD` only on `DELETE`, so an `UPDATE` that **rewrote the ownership column** was checked against its
  destination. With a student frozen, all three of these were **ACCEPTED** on a loaded database: moving the
  frozen student's file to another student, moving their study session, and setting the file's owner to
  `NULL` (which worked because `assert_student_not_frozen(NULL)` returns, making a NULL destination a
  universal escape). `DELETE` was refused throughout, which is why the gap survived two audits.
  **What it cost:** rows could **leave** a frozen student's dataset after the barrier watermark, so the
  snapshot the destination Workspace imports is not the snapshot the source froze — and nothing downstream
  would notice, because the source's own tables remain self-consistent. It applied to all 31 guarded tables.
  **Fixed in one function**, so all of them are covered at once: an `UPDATE` is asserted against the OLD
  owner as well as the NEW one, and the ownership key is **forward-only** (`NULL → value` allowed;
  `value → other value` and `value → NULL` refused for every writer, frozen or not — nothing in the
  repository re-points a guarded row, which was grepped before the decision). **Measured:** reverting to
  the old shape drops the freeze suite from 46 to 40 PASS and fails at FRZ-38.
- **Notifications could not be fenced at all, because the table had no reference to a student.** Four
  contracts require the opposite. `student_id` is now on `in_app_notifications`, declared in the schema
  draft rather than the new operations draft **so the catalog-driven barrier installation picks it up
  automatically** — barrier coverage is now **32 tables, zero holes**. Recipient isolation is enforced at
  insert: an **active** member of this Workspace, the student the notification is about, or a **verified,
  unrevoked guardian of that student**. The case that matters: the same guardian, verified for student A,
  is **refused** as a recipient for student B. A plaintext contact number is refused anywhere in the
  payload at any depth. Recipient, subject and payload are immutable once written; only `read_at` may be
  set, once. **Delivery-time re-authorization is NOT implemented** — it needs a worker, and none exists
  (OPS-NOTIF-DELIVERY).
- **`legal_holds` failed OPEN and was inert.** An unrestricted polymorphic `(entity_type, entity_id)` with
  no integrity, mutable, deletable, no grants to any application role, and consulted by nothing: a hold on
  a mistyped id silently protected nothing while the register said the data was held. Now the polymorphic
  reference is enforceable through a reviewed `retention_entity_types` registry whose entries must name a
  real table and a real **uuid** key (checked against the catalog), a hold whose target does not resolve is
  refused, placement is immutable, release is one-way, and the record can be neither deleted nor truncated.
- **A retention policy model existed only in prose.** Built: the nine categories transcribed from
  `docs/phase1/DATA_RETENTION_SCHEDULE_DRAFT.md` §1, each with one immutable `needs_decision` version and
  a **NULL duration**, because not one period in that document is approved (Q-020). A policy cannot become
  `approved` by an `UPDATE`, only as a new version, and never without a duration, an action, an approval
  reference and an effective date. One gate, `assert_destructive_disposition_allowed()`, refuses with five
  distinct named reasons — non-destructive action, unregistered entity type, missing target, **any** live
  legal hold, no approved policy effective — and reads `clock_timestamp()`, not a transaction-start clock.
  **Today the last reason alone refuses everything, which is exactly what the contract requires** while the
  period is undecided: an unresolved duration must block destructive disposition and must mean neither
  "delete now" nor "keep forever".
- **The gate is shown to discriminate, not merely to raise.** A gate that always failed would pass every
  refusal test and be worthless, so OPS-48 inserts a **synthetic** approved policy (its `approval_ref` reads
  `SYNTHETIC-TEST-FIXTURE-NOT-A-PRODUCT-OWNER-DECISION`), shows the gate then **allows**, then shows a hold
  override it, then shows two conflicting approved policies fail closed on ambiguity. OPS-40 asserts that
  **the drafts themselves approve nothing**, so the fixture cannot drift in.
- **No authority was invented.** No application role can write `legal_holds`, and **nobody** — not `PUBLIC`,
  runtime, worker or exporter — may execute the gate. OPS-50 and OPS-51 assert both from the catalog, so a
  later grant fails the suite rather than passing silently. Registered as **OPS-HOLD-AUTH** and
  **OPS-DISP-AUTH**; completeness of erasure beyond the primary row is **OPS-RETENTION-SCOPE**.
- **A finding deliberately not inflated.** 23 tables claim append-only or immutable semantics through row
  triggers and **none refused `TRUNCATE`**, which a row trigger never sees. Statement-level guards are
  installed, catalog-driven, 31 tables covered with zero holes. **But it was not reachable:** measured,
  `TRUNCATE` is held only by the NOLOGIN table owner — runtime, worker and exporter hold none on any table.
  So this is **hardening, not a fixed vulnerability**, and OPS-64 asserts that measurement so the claim
  cannot quietly become wrong. Two of the three behavioural TRUNCATE tests are also partially **masked** and
  say so: a plain `TRUNCATE` of a referenced table is refused by PostgreSQL before any trigger runs, so
  `CASCADE` is used where a foreign key exists; `audit_events` is referenced by nothing, which makes OPS-61
  the sensitive one.
- **Local verification:** PostgreSQL 16.15, cleared cluster, **23 implementation test steps, all passed,
  808 PASS assertion lines, 0 FAIL**, plus the Python verifier tests (15 and 6, `OK`). **All 59 new lines
  are new assertions** — the new operations step contributes 53 and the freeze suite rises from 40 to 46,
  and nothing else moved, so there is no re-run inflation in this number. Two checks are reported
  separately and are **not** implementation evidence: the register consistency check (31 items) and the
  repository secret scan.
- **Sensitivity measured for every new guard**, by neutralising it and re-running: the pre-Batch-8 barrier
  fails FRZ-38; stubbing the recipient check fails OPS-13; stubbing the payload scan fails OPS-17; stubbing
  the hold resolver fails OPS-30; dropping the audit TRUNCATE guard fails OPS-60; removing the gate's hold
  check fails OPS-47.4.
- **GitHub Actions at this HEAD: NOT RUN.** The agent has no Actions access; `b095dbc7` and `d6d81f8b` still
  have no reported result.
- Phase 2 gate: **NOT READY** pending independent Supervisor review. Phase 3: unauthorized. Real data:
  prohibited (D-014). PR #12: Draft, open, unmerged. **This entry is not approval of anything.**

## Correction 2026-11-18 — the Batch 8 entry above overstated its repository-check result

The Batch 8 entry says two repository checks were "reported separately" alongside an all-passing local run.
The secret scan **did not pass in CI**: GitHub Actions runs **43725323633** and **43725318826** at `fc3416ed`
failed at step 28 (reported by the Supervisor), with the register check skipped at step 29. Reproduced
locally on the exact tree: `workspace_operations_tests.sql` lines 165 and 171, the OPS-17/OPS-18 fixtures.
The local "pass" came from running the scanner before `git add`. The entry above is left as written, because
rewriting a dated record to agree with later evidence is exactly what this file must not do; the current
status is at the top of the file. The Batch 8 SQL/database results were not affected: every database step
passed in both Actions runs.
