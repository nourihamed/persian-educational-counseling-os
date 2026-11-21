# CHANGELOG.md

Format: Keep it simple — date, phase, summary. Prefixes per Master Prompt §62 (`feat:`, `fix:`, `refactor:`, `test:`, `docs:`, `security:`, `perf:`, `chore:`).

## [Unreleased]

### 2026-11-20 — WS-ISO-01 caller binding (B, test-only key); WS-PLAN-01 decisions A2/B1/C1/D1/E1 (draft SQL; synthetic)
`security/feat/test/docs:`
- **New `workspace_principal_assertion_draft.sql`:** signed, short-lived principal assertions verified in the
  database.
  - Production is fail-closed: mode `disabled`, and the key table is structurally test-only.
  - The principal is bound to the backend, the transaction and the session role.
- **New `workspace_counselor_rls_draft.sql`:**
  - RLS is ENABLED and FORCED on every student-scoped table, keyed to the verified principal;
  - private notes are author-only;
  - authorship is bound to the principal.
- **Plan guards:** actors and authors must be the verified principal, and A2/B1/C1/D1/E1 are enforced.
  Transitions the decisions do not determine are refused.
- **Tests:**
  - ISO-P00..P30, ISO-RLS-01..09, ISO-RLS-C3, ISO-P-RACE-01..03;
  - PLN-A2a..m, PLN-D1a..g, PLN-E1a..f.
  - The plan, race, migration and F-05 suites now act under verified principals, through the test-only harness.
- **Measured negative controls:** 21.
- **Unchanged:** no runtime write path or new runtime privilege; F-05 intact.
- **Local:** 25 steps, 1155 PASS, 0 FAIL, 0 OPEN. Actions: NOT RUN until pushed.

### 2026-11-20 — Phase 2 gap matrix, decision briefs, WS-ROLE-17 reporting fix
`docs/test:`
- **Gap matrix.** `PHASE2_GAP_MATRIX.md` was built from the SQL, tests and workflow.
- **Decision briefs:**
  - WS-ISO-01 caller binding (Platform Security);
  - WS-PLAN-01 A–E (Product Owner);
  - F-05 production-hardening requirements.
- **Newly registered:** WS-REV-01 (review fields and duplicate prevention) and WS-MIG-01 (no migration framework).
- **Reporting fix:** "PASS WS-ROLE-01..19" no longer includes the separately reported, and sometimes skipped,
  WS-ROLE-17.
- **Status:**
  - PROJECT_STATE now distinguishes the implementation commit, the documentation commit, the PR head and `main`.
  - Statuses are made consistent: F-05 ACCEPTED (architecture review level); WS-PLAN-01 NOT ACCEPTED / BLOCKING;
    WS-ISO-01 CRITICAL / BLOCKING; Phase 2 NOT READY; Phase 3 NOT AUTHORIZED.
- **Local evidence:** fresh-cluster run: 1067 PASS, 0 FAIL, 3 OPEN, 1 SKIP.
- **Not implemented:** WS-ISO-01 and WS-PLAN-01 wait for decisions.

### 2026-11-20 — F-05 accepted at architecture-review level; documentation reconciled (docs only)
`docs:` CI at `fe08a77` (runs 44705627331, 44705633469) success. F-05 accepted by the Supervisor at the current architecture-review level (review of `fe08a77`, 2026-11-20). This is not approval of WS-PLAN-01 as a whole, of WS-ISO-01, of Phase 2, of production runtime plan-item writes, or of production writer or migrator privileges.
- Recorded open: provisioning and assumption of the writer and migrator; a non-superuser provisioning procedure;
  production superuser control and audit; WS-ISO-01 caller binding with ISO-GAP-01..03.
- No SQL, test or workflow change. Phase 2 NOT READY. Phase 3 not authorized. D-014 in force.

### 2026-11-20 — F-05 follow-up on `38f2561`: owner-role chains (draft SQL; synthetic)
`security/test/docs:` GitHub Actions passed at `38f2561` (runs 44693197767, 44693205261; logs verified by the Supervisor). F-05 was not closed: owner roles were checked only for a direct member.
- **Chains.** `plan_identity_boundary_violations()` walks every membership chain from all nine roles, whatever the INHERIT, SET or ADMIN option, and names any path to the table, function or governance owner, or to a privileged identity.
- **Attributes.** Every role is checked against its expected LOGIN/INHERIT and the five privileged attributes.
- **Memberships.** They must be exactly `<x>_login` → `<x>`, without ADMIN.
- **Bootstrap.** It validates every pre-existing application role and aborts on a mismatch; nothing is repaired.
- **Tests:** F05-17..23 and F05-BOOT-15..20. They show real effects through chains, including an ADMIN-only link used to self-grant, and each has a measured negative control.
- **Unchanged:** no runtime privilege and no runtime write path. WS-ISO-01 stays open.
- **Local:** 25 steps, 1067 PASS lines, 0 FAIL. Actions: NOT RUN.

### 2026-11-19 — Supervisor finding F-05 on `8df7d5e` remediated: privileged plan identities and role membership (draft SQL; synthetic)
`security/test/docs:` GitHub Actions passed at `8df7d5e` (runs 44382515348, 44383233656). The Supervisor then raised F-05 (HIGH).
- **The defect.** The privileged identities were checked with `pg_has_role(current_user, role, 'MEMBER')`, which any
  direct or indirect member passes. The bootstrap also trusted a pre-existing role as it found it.
- **Identity check.** `plan_identity_is()` now requires the session to be the role, with no membership in either
  direction and none of LOGIN, SUPERUSER, CREATEROLE, BYPASSRLS, REPLICATION, CREATEDB or INHERIT. It re-checks this on
  every write, and a superuser is refused as itself.
- **Bootstrap.** It aborts on an unsafe existing role and repairs nothing. Then, in the same transaction,
  `plan_identity_boundary_violations()` checks the whole boundary for the file's own nine-role inventory:
  - memberships and paths;
  - attributes;
  - who holds the owners of the security objects;
  - guard triggers enabled;
  - no PUBLIC or application write on the plan tables or the identity record.
- **Fixtures.** Rows previously written by a superuser are now written as the writer.
- **Tests.** F05-00..16 (79 PASS lines) and F05-BOOT-01..14, each with a measured negative control.
- **CI step numbers corrected:** isolation 15, PlanItem 16, secret scan 30, register 31.
- **Unchanged:** no runtime write path and no new runtime privilege. WS-ISO-01 stays open (ISO-GAP-01..03), and
  M-05/M-06 stay MEDIUM technical debt.
- **Open:** who may provision or assume the privileged identities (Platform Security / Operations).
- **Local:** 25 steps, 1031 PASS lines, 0 FAIL. Actions: NOT RUN.

### 2026-11-18 — Supervisor findings F-01..F-04 on `d75d039` remediated; M-05/M-06 recorded (draft SQL; synthetic)
`fix/security/test/docs:` The Supervisor reviewed `d75d039` as NOT ACCEPTED, although CI passed there (runs
44376897878, 44376886372).
- **F-01 (CRITICAL):** the shared runtime could record a plan transition, or create a plan item, naming any student
  or counselor as the actor. The database believed whatever actor it was given.
  - The runtime now holds no INSERT on `plan_items` or `plan_item_status_events`.
  - The triggers accept writes only from the NOLOGIN `ws_<key>_synth_plan_writer`, checked with `pg_has_role`, never
    a session variable.
  - `actor_kind='student'` is refused for every writer.
  - No caller-binding mechanism was invented; WS-ISO-01 stays CRITICAL and BLOCKING.
- **F-02 (HIGH):** the runtime cannot name `content_model` (column-level INSERT). `legacy_json` is accepted only from
  the NOLOGIN `ws_<key>_plan_migrator`. Read compatibility is unchanged.
- **F-03 (MEDIUM):** transitions on a draft version's items, and publishing an empty normalized version, are refused
  pending Product Owner decisions. No transition graph.
- **F-04 (MEDIUM):** the column is added with `DEFAULT 'legacy_json'` and only then switched to `'normalized'`, so
  historical rows stay legacy and unchanged.
  - New synthetic migration fixture and PLN-M01..M08, run in their own database.
  - The `d75d039` form fails that fixture. Notes in `WS_PLAN_01_MIGRATION_NOTES.md`.
- **Tests:** PLN-70..80 added, and every new rule has a measured negative control.
- **M-05 and M-06** are recorded with the Supervisor's definitions as MEDIUM, `NON_BLOCKING_TECHNICAL_DEBT`, and are not
  implemented. The register checker accepts that gate value.
- **Local:** 25 steps, 938 PASS lines, 0 FAIL. Actions at this commit: NOT RUN.
- Phase 2 NOT READY. Phase 3 not authorized. D-014 in force.

### 2026-11-18 — WS-PLAN-01 normalized PlanItem data model (Product Owner decision B; draft SQL; synthetic)
`feat/test/docs:` Implements exactly what the recorded decision covers. `workspace_plan_items_draft.sql`: `plan_items` with six typed, student-bound source foreign keys (topic, subtopic, activity, exam, review, assignment) and an exactly-one-source CHECK — no `source_type/source_id`; item definitions insert-only and added only to a draft version; a change is a new plan version that names the earlier version of the same plan it supersedes, with a reason and an author; status transitions in an append-only, sequence-numbered table with actor, timestamp and reason, using exactly the seven approved statuses and ten deferral reasons (`deferred` requires a reason, `other`'s note optional); current status derived; normalized versions carry no JSON and output JSON is derived (`plan_version_rendered`); legacy JSON only on explicit `legacy_json` versions, which cannot follow a normalized one; UTC projection derived from local date, time and a validated zone; both tables inside the transfer write barrier and the counselor boundary; runtime holds no UPDATE/DELETE. Tests: PLN-C1..C4, PLN-01..63 (61 PASS lines) and the WS-PLN-RACE-01..03 concurrent-transition race; negative controls for exactly-one-source, JSON exclusivity, counselor check, insert-only, stale transitions, supersession and the sequence key each fail their named test. **The catalog assertion PLN-C3 initially passed with its own constraint dropped** (a NULL comparison) — found by the control and fixed. REG-09 now checks that the vocabularies recorded in the register are exactly those the SQL enforces. **Also:** GitHub Actions at `b7d4b28` (runs 44369152676, 44369143862) failed; reproduced locally as REG-08, the §6 classification row for WS-DOM-05 not updated with the decision — realigned. No scheduling logic, transition graph, priority, dependencies, provenance or carry-forward is built: the decision does not cover them. WS-PLAN-01 stays BLOCKING until independently verified; Phase 2 NOT READY.

### 2026-11-18 — GitHub Actions success recorded at `467a029` (documentation only)
`docs:` The Supervisor-corrections commit `467a0294b03f9ffc494509509f9c0ece595b2bd3` passed GitHub Actions: runs 44362679187 (job 135008003418) and 44362668276 (job 135007959995), both `success`. Conclusions were read from the PR check runs; step logs were not read by the agent. It is the first Actions success on an SQL change since `ad3bf28`, and it is evidence for draft SQL and synthetic suites only — the Phase 2 gate remains NOT READY, with WS-ISO-01 CRITICAL and blocking. This commit changes no SQL, test or workflow file.

### 2026-11-18 — Phase 2 Supervisor corrections: CI secret-scan failure, history scanning, WS-ISO-01 boundary, register classification (draft SQL; synthetic)
`fix/security/test/docs:` **GitHub Actions at `fc3416ed` failed** (runs 43725323633 and 43725318826, reported by the Supervisor): every database step passed; the repository secret scan (step 28) failed and the register check (step 29) was skipped. Reproduced on the exact tree: `workspace_operations_tests.sql` lines 165 `[iranian-mobile]` and 171 `[e164]`, the OPS-17/OPS-18 refusal fixtures — not credentials. **The Batch 8 local "pass" was the agent's error**: the scan was run before `git add`, and `git ls-files` does not list untracked files. Fixtures replaced with marked all-zero bodies under a per-line exception that covers the two contact patterns only and requires a stated reason. **History content scanning implemented** (the docstring had claimed history coverage while only file names were checked): 1,361 historical blobs, 110 contact-shaped fixture strings, each excepted by (blob SHA, pattern, SHA-256 of the value) in `secret_scan_history_exceptions.json` — no credential, key or PEM block anywhere in history; the values are not claimed unassigned (REPO-HIST-CONTACTS). **Batch 7 scanner defect fixed:** the allowlist was matched against the whole line, so the word "synthetic" exempted every pattern on it, PEM headers included. Shallow clones fail closed; CI checkout uses `fetch-depth: 0`; detected numbers are masked in output; both repository checks run with `if: !cancelled()` so one cannot hide the other, while the job still fails. **WS-ISO-01 reclassified CRITICAL and BLOCKING** — it fails open: the shared runtime role reads every student-scoped table, including other counselors' private notes. The boundary half is implemented (`workspace_counselor_scope_draft.sql`; ISO-C1..ISO-54, 42 PASS lines, six negative controls) — assignment-scoped predicate, list, any related row by its own id, a report, note visibility, revocation, and two write paths; **a Batch 8 defect was closed on the way: the notification recipient rule accepted any active member for any student** (OPS-13c). The caller is not bound to a membership, so ISO-GAP-01..03 print the residual as OPEN, not PASS; proposal in `WS_ISO_01_COUNSELOR_ISOLATION_PROPOSAL.md`. **All 32 register items classified** (kind, code-resolvable, gate impact, closure evidence), with REG-07/REG-08 requiring the fields and row-by-row Markdown/JSON agreement. Local: 24 implementation steps, 852 PASS lines, 0 FAIL; Actions at the new HEAD NOT RUN. A PROVISIONAL exit evidence package is added; it is not a completion declaration. Phase 2 NOT READY; Phase 3 not authorized; D-014 in force.

### 2026-11-15 — Phase 2 Batch 8: files, notifications, retention and operational contracts (draft SQL; synthetic)
`security/fix/feat/test/docs:` **The headline is a defect in this project's own Batch 1 work: the transfer write barrier only looked at ONE SIDE of an `UPDATE`.** `student_write_barrier()` resolved the student from `NEW` on `INSERT` and `UPDATE` and from `OLD` only on `DELETE`, so an `UPDATE` that **rewrote the ownership column** was evaluated against its destination. With a student frozen, all three of these were **ACCEPTED** on a loaded database: moving the frozen student's file to another student, moving their study session, and setting the file's owner to `NULL` — the last because `assert_student_not_frozen(NULL)` returns, making a NULL destination a universal escape hatch. `DELETE` was refused throughout, which is exactly why the gap survived two audits: the obvious destructive verb was covered. **What it cost:** rows could **leave** a frozen student's dataset after the barrier watermark, so the snapshot the destination Workspace imports is not the snapshot the source froze, and nothing downstream would notice because the source's own tables stay self-consistent. It applied to all 31 guarded tables. **Fixed in one function** so every table is covered at once: an `UPDATE` is asserted against the OLD owner as well as the NEW one (freeze first, so the refusal names the freeze rather than the weaker ownership rule), and the ownership key is **forward-only** — `NULL → value` allowed, `value → other value` and `value → NULL` refused for every writer, frozen or not. Nothing in the repository re-points a guarded row at another student (grepped before deciding), so this forbids no existing path and removes the class rather than the three demonstrated instances. **Measured:** reverting to the old shape drops the freeze suite from 46 to 40 PASS and fails at FRZ-38.
**Notifications could not be fenced at all**, because `in_app_notifications` had no reference to a student — while the Saga recovery contract requires the source to be rejected for "writes, jobs, files, exports and notifications", the API authorization contract names "recipient substitution; child/Workspace mismatch; stale queued notification after transfer; sensitive data in event payload" as threats, and the guardian authority matrix forbids child A's authority being used for child B. `student_id` is now on the table, declared in `workspace_schema_draft.sql` rather than the new operations draft **so the catalog-driven barrier installation picks it up automatically**; coverage went from 31 tables to **32, zero holes**. Recipient isolation is enforced at insert — an **active** member of this Workspace, the student the notification is about, or a **verified, unrevoked guardian of that student**; the same guardian verified for student A is **refused** for student B. A plaintext contact number is refused anywhere in the payload at any depth, which is the contact-change contract's own rule. Recipient, subject and payload are immutable once written; only `read_at` may be set, once. **Delivery-time re-authorization is NOT implemented** — it needs a worker, and none exists (OPS-NOTIF-DELIVERY).
**`legal_holds` failed OPEN and was inert:** an unrestricted polymorphic `(entity_type, entity_id)` with no integrity, mutable, deletable, no grants to any application role, and consulted by nothing — a hold on a mistyped id silently protected nothing while the register said the data was held. Now the polymorphic reference is enforceable through a reviewed `retention_entity_types` registry whose entries must name a real table and a real **uuid** key, checked against the catalog; an unresolvable hold is refused; placement is immutable; release is one-way; the record can be neither deleted nor truncated.
**A retention policy model existed only in prose.** Built: the nine categories transcribed from `docs/phase1/DATA_RETENTION_SCHEDULE_DRAFT.md` §1, each with one immutable `needs_decision` version and a **NULL duration**, because not one period in that document is approved (Q-020). A version cannot become `approved` by `UPDATE`, only as a new version, and never without a duration, an action, an approval reference and an effective date. One gate, `assert_destructive_disposition_allowed()`, refuses with five distinct named reasons — non-destructive action, unregistered entity type, missing target, **any** live legal hold, no approved policy effective — and reads `clock_timestamp()`. Today the last reason alone refuses everything, which is **what the contract requires**: an unresolved duration must block destructive disposition and mean neither "delete now" nor "keep forever". **The gate is shown to discriminate rather than merely raise:** OPS-48 inserts a synthetic approved policy (its own `approval_ref` reads `SYNTHETIC-TEST-FIXTURE-NOT-A-PRODUCT-OWNER-DECISION`), the gate then **allows**, a hold overrides it, and two conflicting approved policies fail closed on ambiguity — while OPS-40 asserts the drafts themselves approve nothing. **No authority invented:** no application role may write `legal_holds` and **nobody** may execute the gate; OPS-50/51 assert both from the catalog so a later grant fails the suite (OPS-HOLD-AUTH, OPS-DISP-AUTH; completeness of erasure is OPS-RETENTION-SCOPE).
**A finding deliberately not inflated:** 23 tables claim append-only or immutable semantics through row triggers and **none refused `TRUNCATE`**, which a row trigger never sees. Statement-level guards are installed, catalog-driven, 31 tables covered with zero holes — **but it was not reachable**: measured, `TRUNCATE` is held only by the NOLOGIN table owner, and runtime, worker and exporter hold none on any table. So this is **hardening, not a fixed vulnerability**, and OPS-64 asserts the measurement so the claim cannot quietly become wrong. Two of the three behavioural TRUNCATE tests are also partially **masked** and say so: a plain `TRUNCATE` of a referenced table is refused by PostgreSQL before any trigger runs, so `CASCADE` is used where a foreign key exists; `audit_events` is referenced by nothing, which makes OPS-61 the sensitive one.
Local evidence: PostgreSQL 16.15, cleared cluster, **23 implementation test steps, all passed, 808 PASS assertion lines, 0 FAIL**, plus the Python verifier tests (15 and 6, `OK`). **All 59 new lines are new assertions** — 53 from the new operations step and 6 from the freeze suite (40 → 46), with nothing else moving, so there is no re-run inflation this time. Two checks are reported separately and are not implementation evidence (register consistency, now 31 items; repository secret scan). **Sensitivity measured for every new guard** by neutralising it: pre-Batch-8 barrier fails FRZ-38; stubbed recipient check fails OPS-13; stubbed payload scan fails OPS-17; stubbed hold resolver fails OPS-30; dropped audit TRUNCATE guard fails OPS-60; removed hold check in the gate fails OPS-47.4. **GitHub Actions at the resulting HEAD: NOT RUN**; Batch 7 was pushed as `d6d81f8b` and has no reported result. Phase 2 Gate remains **NOT READY**; Phase 3 is not authorized; D-014 synthetic-only stays in force.

### 2026-11-15 — Phase 2 Batch 7: contact identity concurrency, confidentiality and a repository secret scan (draft SQL; synthetic)
`test/security/docs:` **The two races the brief listed as NOT RUN are now run, and they pass.** Both serializations were designed in and documented in comments, and neither had ever been executed — a comment claiming mutual exclusion is not evidence of it. **Race A:** a contact change holding `FOR SHARE` on `identity_write_gate` blocks `begin_identity_hmac_rotation()`, which takes `FOR UPDATE` on the same row; without it a contact change could write an identity alias at a key version the rotation is retiring, while the deferred coverage check was evaluated against a set changing underneath it. **Race B:** a contact change holding `FOR UPDATE` on the student's `student_ownership` row blocks `switch_student_ownership()`; afterwards the generation advances 1 → 2, ownership moves to the destination, and a contact change citing the pre-switch generation is refused — without it the globally unique contact identity could be written against an owner and generation that no longer hold. Coordination is deterministic: the first session waits for an explicit go signal sent only after the driver has **observed** the second blocked in `pg_stat_activity`, and the first is signalled to commit rather than killed. **Sensitivity measured:** removing the gate lock fails race A; removing the ownership lock fails race B.
**A defect nearly reported that was the test's own fault.** The first version of race B shared a database with race A and reported that the ownership switch **did not block** — which reads exactly like a missing lock. Diagnosing before reporting showed race B had reused a proof bound to a *different* student; the command correctly refused it, the transaction aborted, its locks released, and the switch then ran unblocked. `change_student_mobile_contact()` does take `FOR UPDATE` on `student_ownership`. The fix was **isolation, not a weaker assertion**: each race now runs in its own fresh database and the reason is written into the script.
**Two confidentiality tests were wrong first and the schema was right.** CID-03 initially banned every text column on the key-version tables and flagged `mobile_encryption_key_versions.key_manager_ref` — a non-secret KMS/HSM identifier, exactly the external-custody shape the register recommends for PS-3; it now bans `bytea` and unconstrained text instead. CID-05 initially looked for fingerprint uniqueness on `student_contact_index`, which deliberately has none: it answers what a student's contact is, not who owns a contact. The real rule is a partial unique index on `enrollment_claim_identity_aliases` over `(key_version, mobile_hmac, grade_key)` across `active` **and** `transfer_pending` claims — so two students **can** share a fingerprint in the contact index, and what they cannot do is hold live claims on it in the same grade under one key. Both now assert the real design, stated in the test rather than left to be inferred.
**Confidentiality asserted from the catalog** (CID-01..CID-05b): no text column can hold a plaintext contact; every fingerprint is pinned to 32 bytes so its length leaks nothing; the contact is bytea ciphertext; the key-version tables hold no key material; exactly one active HMAC key version with a second refused.
**New repository check, explicitly NOT implementation evidence:** `check_no_secret_material.py` scans tracked files for plaintext contacts (Iranian mobile and generic E.164), long literals assigned to secret-shaped names, PEM private-key blocks and tracked credential files, and checks every path ever **added** in Git history for credential-file names. Result: 147 tracked files, 186 historical paths, no findings; verified sensitive by planting a fake Iranian number and a fake API key (all three expected findings fired). It does not flag this project's synthetic shapes, because flagging fixtures trains a reader to ignore the check, and it states its own limit: a pattern scan proves the absence of known shapes, not of secrets.
Local evidence: PostgreSQL 16.15, cleared cluster, all 22 implementation test steps passed, 749 PASS assertion lines, 0 FAIL. **Read that number carefully:** only **12** of the rise from 653 are new assertions (6 CID-RACE + 6 CID); the rest of the contact step's 51 → 147 is `cp_30` and `cp_40` **re-running** in the two isolated race databases — repeated execution of existing coverage, not new coverage. Plus the Python verifier unit tests, and two checks reported separately (register consistency, 6 lines; repository secret scan, 2 lines). **A local harness limitation is recorded too:** the secret scan first reported FAILED locally because the runner executes every step as `postgres` and Git refuses a root-owned repository to another user; the check is correct — it fails closed when it cannot scan — and passes when run as the repository owner, as CI does. **GitHub Actions at the resulting HEAD: NOT RUN.** Batch 6 was pushed as `b095dbc7`. Phase 2 Gate remains **NOT READY**; Phase 3 is not authorized; D-014 synthetic-only stays in force.

### 2026-11-15 — Phase 2 Batch 6: adversarial privilege review (draft SQL; synthetic)
`security/fix/test/docs:` Batch 6 is an adversarial review, and the assertions in `workspace_privilege_hardening_tests.sql` interrogate the **catalog** rather than the SQL text — they state properties that must hold for **every** SECURITY DEFINER function and **every** role, not for a list of remembered names. Reading the SQL is exactly how the first finding survived several previous passes.
**Finding 1, fixed — a SECURITY DEFINER function owned by a superuser.** `receipt_consume_grant_guard()` is created in `receipt_01_schema_draft.sql`, **before** `receipt_02_roles_draft.sql` creates the role that should own it, so it inherited the loader's identity (`postgres`) and nothing reassigned it. A SECURITY DEFINER function owned by a superuser executes **as superuser**. **Severity MEDIUM, measured rather than asserted:** it returns `trigger` and PostgreSQL refuses to invoke a trigger function directly; its body reads one schema-qualified table and raises; and shadowing an unqualified name needs `CREATE` on a schema on its path, which neither `PUBLIC` nor any application role has. It was unnecessary privilege and a deviation from this project's own rule that every definer function is owned by a dedicated NOLOGIN role. Ownership reassigned to `ws_<key>_receipt_consume_definer`; search_path tightened from `pg_catalog, public` to `pg_catalog, pg_temp`.
**A finding deliberately not inflated.** Two definer functions still carry `public` on their search_path. The first instinct was to call that a vulnerability and mass-edit it; the measurement says it is not exploitable here. So SEC-02 was split: **SEC-02** requires a pinned search_path (an unpinned one resolves through the *caller's*, which is the real classic vector), **SEC-02b** asserts the precondition that actually carries the weight — neither `PUBLIC` nor any application role may `CREATE` in `public`, which if it ever changed would make every such function exploitable at once — and **SEC-02c** reports the remaining two as a NOTICE, tracked as hardening and **not** claimed as fixed. Claiming a vulnerability that cannot be exercised misleads a reviewer as much as hiding one that can.
**Finding 2, not fixable in a batch — counselor-to-counselor isolation is not enforced.** The brief requires that no counselor may access another counselor's students, even within the same Organization. **Measured:** no row-level security on any table, and the Workspace runtime role holds `SELECT` on **47 tables in full**. Isolation here is **per-Workspace** — one database per Workspace with no cross-database grants, which the cross-database denial step does test — so every counselor inside a Workspace shares one runtime identity. That is an architecture decision nobody has made, so it is recorded as **WS-ISO-01** with four options and a recommendation (RLS keyed to the responsible counselor assignment, noting the session identity must **not** come from a GUC the application sets, because this project already rejected session GUCs as an authorization mechanism in H-03). **SEC-10 asserts the negative result as a test rather than prose** and fails if the situation changes in either direction, so the record cannot silently rot.
**No further defects found:** no unpinned definer search_path; no definer owner that can log in; no table owned by an application role; no Workspace role with superuser/createrole/createdb/bypassrls; no table privilege held by `PUBLIC`; no unexpected PUBLIC execute; every table has a primary key.
**SEC-08 records a limitation instead of hiding it:** every guard here is a trigger or a CHECK and a table owner can disable triggers, so SEC-08 asserts that the owner **can** disable one — nobody should later mistake the write barrier for something that binds the owner. Containing that identity is operational credential control, outside the database.
**Not claimed:** object-level authorization, IDOR and uniform-404 behaviour (API properties, no API exists); background-job tenant context (nothing runs as the worker role); file and notification ownership (neither subsystem exists); RLS policies and therefore RLS bypass testing — the absence is the finding.
Sensitivity measured: with the `ALTER FUNCTION ... OWNER TO` line removed, SEC-01 fails naming the function (exit 3). Local evidence: PostgreSQL 16.15, cleared cluster, all 22 implementation test steps passed, 653 PASS assertion lines, 0 FAIL (the governance receipt step rose from 111 to 123, exactly the 12 SEC assertions), plus the Python verifier unit tests, plus a documentation consistency check reported separately and not counted as implementation evidence. **GitHub Actions at the resulting HEAD: NOT RUN.** Batch 5 was pushed as `4306d56` and its Actions result has not been reported. The register now carries 27 items. Phase 2 Gate remains **NOT READY**; Phase 3 is not authorized; D-014 synthetic-only stays in force.

### 2026-11-15 — Phase 2 Batch 5: curriculum subtopics, and five per-student tables that had no write barrier (draft SQL; synthetic)
`fix/security/feat/test/docs:` **Five per-student tables could be written while their student was frozen for transfer.** The Batch 1 write barrier derived its table list from a **column scan** — anything carrying `student_id` or `enrollment_id` — which by construction cannot see a table whose ownership runs through another table. Batch 1 had already been caught by this once (`counselor_assignments` and the two command logs, FRZ-18) and the fix then added an `enrollment` resolution path **without asking what else the scan was blind to**. Auditing reachability from the catalog found `student_plan_versions` (via `student_plans`), `test_responses` (via `test_attempts`), and `guardian_permissions`, `guardian_link_events` and `guardian_permission_events` (via the guardian link, the last two hops out). So a frozen student's plan versions, test responses and **guardian authority** could all change through cutover — meaning the destination Workspace would import a different authority set than the source froze. `student_write_barrier()` gained `plan`, `attempt`, `guardian_link` and `guardian_permission` resolution paths; coverage went from **26 tables to 31**.
**The audit is now a test, which is the part that matters.** FRZ-01 asks "does every table in the coverage view have a trigger?", which cannot catch a table missing from the view. **FRZ-01b** asks the opposite question from the catalog and fails **by name**, with eleven reviewed exclusions each stating one of only two valid reasons: the table is **shared** between students (barring it would let one frozen student block writes other students depend on), or it must be writable **while** frozen because it is part of the freeze machinery — `workspace_inbox_events` is in that group, and not as a technicality, since the inbox projection is what *applies* the fence. FRZ-01b found the three guardian tables **as soon as it was written**, after the first two had been fixed by hand. **FRZ-01c** pins the five so an over-broad exclusion edit cannot drop them again, and **FRZ-18b/18c** test the new paths behaviourally, because a two-hop lookup that silently returned NULL would leave the barrier open while still reporting as covered (`assert_student_not_frozen()` returns early for a NULL student).
**Curriculum subtopics built; the rest scoped out by the Product Owner.** Both `CURRICULUM_DOMAIN_CONTRACT.md` and `DETERMINISTIC_PLANNING_DOMAIN_CONTRACT.md` are marked **DRAFT / NOT APPROVED**, and the brief says to resolve them "only to the extent already approved", so the scope question was **put to the Product Owner rather than decided**; the answer was **subtopics only**. `subtopics` sits under `topics`, ordered within its parent, archivable rather than deletable. CUR-01..CUR-10.
**Deletion behaviour is now asserted rather than assumed.** There is no `ON DELETE` action anywhere in the Workspace schema, so every foreign key restricts — but nothing checked it. CUR-09 fails if any foreign key has a non-default delete action, because a cascade or set-null would destroy the educational history the curriculum contract requires be preserved. CUR-10 asserts the Book/Edition tables are **absent**, so that gap stays explicit and dated.
**Verified without change:** ProgramTemplate and plan versioning with publication immutability on UPDATE and DELETE; Activity's typed source columns with composite foreign keys and the kind/source agreement CHECK — no polymorphic reference anywhere; and the Class/ClassSession/ClassParticipant chain, where `class_session_participants` carries composite foreign keys to both the session's class and the class participant, refusing cross-class and cross-student rows declaratively.
**Two register items added with options and recommendations, decided by nobody here:** **WS-DOM-05** (Book/Edition, successor mapping, content ownership, subtopic mastery — recommendation: Phase 7, where the roadmap puts curriculum) and **WS-PLAN-01** (normalized `plan_items` instead of the opaque `plan_content` blob, the exact shape the planning contract rejects — recommendation: data model in Phase 2, engine in Phase 12, the split that already worked for Activity). The register now carries **26 items**.
Local evidence: PostgreSQL 16.15, cleared cluster, all **22** implementation test steps passed, **641 PASS assertion lines**, 0 FAIL (curriculum 10 new; the freeze step rose from 36 to 40), plus the Python verifier unit tests, plus a documentation consistency check reported separately and not counted as implementation evidence. **GitHub Actions at the resulting HEAD: NOT RUN.** Batch 4 was pushed as `0b5a644` and its Actions result has not been reported. Phase 2 Gate remains **NOT READY**; Phase 3 is not authorized; D-014 synthetic-only stays in force.

### 2026-11-14/15 — Phase 2 Batch 4: assessment, exam and analysis model (draft SQL; synthetic)
`feat/fix/test/docs:` Batch 4 asked for verification of eight assessment properties. **Four were already implemented** and each was confirmed by probe rather than by reading documentation: the immutable published question set and order; normalized, constrained membership and ordering; responses bound to the exact version by two composite foreign keys, **declaratively with no trigger**; and the attempt's scoring snapshot equalling the published version's. Probing also confirmed that publishing a `per_attempt` version is **refused**, so adaptive delivery is genuinely disabled for MVP rather than merely discouraged by a comment — `test_attempt_questions` is therefore correctly absent — and that a submitted attempt's responses are immutable, which is what keeps a score's inputs from drifting.
**Four things were missing and were built.** (1) An explicit scoring `algorithm` and positive integer `algorithm_version` are now required in every policy snapshot on `test_definitions`, `test_definition_versions`, `test_attempts`, `exams`, `exam_results` and the per-subject results; previously a snapshot only had to be a JSON object and `{}` published successfully, so a historical score was unattributable. (2) `exam_definition_versions` with `exam_definition_version_subjects` — an immutable published blueprint, undeletable, refused at publication unless the per-subject counts add up. (3) `exam_subject_results` — per-subject results keyed to the exact exam, student and subject, with composite foreign keys refusing cross-exam and cross-student rows declaratively, reconciled with the aggregate by a `DEFERRABLE INITIALLY DEFERRED` constraint trigger because the aggregate and the subject rows arrive in whichever order the writer chooses. (4) `test_analysis_versions` and `test_analysis_response_findings`, append-only, so a reclassification is a new version rather than a mutation — submitted responses were already immutable, so a reclassification previously had nowhere to go.
**Two facts the policy predicate defends against, measured rather than recalled:** `jsonb_typeof('{}'::jsonb -> 'algorithm') = 'string'` is **NULL**, and a `CHECK` constraint whose expression is NULL **accepts** the row. EXM-42 asserts directly that the predicate is never NULL for any of twelve malformed inputs.
**A false claim in the first draft of these notes has been corrected.** They said that removing `COALESCE(..., false)` made the suite fail. It does not: with the `length(btrim(COALESCE(p->>'algorithm','')))>0` conjunct present the chain evaluates to `false` rather than NULL, since `NULL AND false` is `false`. Measured — the predicate returned `false` for `{}` and the suite passed. The control that isolates the trap is a **type-comparison-only** predicate, against which EXM-42 fails naming "empty object, no algorithm_version, no algorithm". A second claimed control was also invalid: dropping the reconciliation trigger breaks EXM-26's own setup, because the test runs `SET CONSTRAINTS ... IMMEDIATE` to observe the deferred check; neutralising the trigger **body** is the valid control and EXM-26 then fails with the exact expected message.
**A stale exit-criteria row was corrected:** `PHASE2_EXIT_CRITERIA.md` claimed per-subject exam results were NOT IMPLEMENTED when they are, which **understated** the project to a reviewer. It is now split into what is done and what genuinely is not — the custom error taxonomy table, rank/percentile/cohort comparison, and scoring formulas (absent by design: the database stores and compares snapshots and never computes or validates a score).
**OQ-ASM-2 added to the unresolved-item register** (which algorithm names are permitted, and how versions are governed): the shape is enforced, the value set deliberately is not. Nothing about scoring behaviour was decided. The register now carries 24 items.
**Process note:** this work was written on 2026-11-14 at 22:46 but never committed before the session paused. It was found as uncommitted working-tree changes on 2026-11-15. The full workflow was re-run from a cleared cluster and the documented controls re-executed rather than trusting those notes — which is how the false claim above was caught.
Local evidence: PostgreSQL 16.15, cleared cluster, all 21 implementation test steps passed, 627 PASS assertion lines (step 11 rose from 116 to 158, exactly the 42 EXM assertions), 0 FAIL, plus the Python verifier unit tests, plus a documentation consistency check reported separately and not counted as implementation evidence. **GitHub Actions at the resulting HEAD: NOT RUN.** Batch 3 was pushed as `db94176` and its Actions result has not been reported. Phase 2 Gate remains **NOT READY**; Phase 3 is not authorized; D-014 synthetic-only stays in force.

### 2026-11-14 — Phase 2 Batch 3: Student Credit ledger invariants verified, two defects fixed (draft SQL; synthetic)
`fix/security/test/docs:` Batch 3 asked for **verification** of thirteen credit-ledger properties rather than new features, so each was checked against what the tests actually assert. **Three had no test at all**, and two real defects were found through them. Full matrix in `docs/phase2/IMPLEMENTATION_RESPONSE_2026-11-14.md` section 8.
**The untested central invariant.** "No negative or inconsistent spendable balance" had no test. The guard existed and worked — a probe confirmed it refuses an over-debit — but nothing exercised that branch. CRD-27 tested the balance *identity* (`available = ledger − reserved − recommitted`), which is a different claim: an identity can hold perfectly while the balance is negative. Now CRD-39 (debit larger than the ledger refused), CRD-40 (exactly `available + 1` refused) and CRD-41 (the control: exactly `available` IS accepted and leaves 0, so the first two cannot pass against a guard that refuses everything), plus WS-CRD-LAST-01..05 for the concurrency half — two different students racing for a wallet holding one unit, coordinated deterministically through lock observation with session A **signalled to commit, never killed**.
**Defect 1 — a compensating reversal could name the wrong student.** The guard validated the wallet, the exact opposite amount and single use, but not the student. Demonstrated: a reversal naming a different student was accepted (`student_matches_debit = f`). Severity MEDIUM, stated precisely: no application role holds INSERT on the ledger — CRD-46c/46d now prove it — so it was unreachable from the runtime. It still mattered: the brief requires the tie to the student, the balance arithmetic reads `student_entitlements` so the numbers would have agreed while the attribution was wrong, the ledger is append-only so the attribution could never be corrected, and OQ-CRD-2 will read it. Fixed with `IS DISTINCT FROM`, so reversing a debit that names no student still works. CRD-42/43.
**Defect 2 — the ledger guard existed twice and the weak copy was reachable.** A weak copy sat beside the table in `workspace_schema_draft.sql` (no wallet row lock, **no balance check at all**) and a strong `CREATE OR REPLACE` copy in `workspace_activation_transactions.sql`. The strong copy won in the normal load order, so no previous credit result was wrong — but one CI step loads the schema draft **without** the activation file, so the weak path was live rather than hypothetical, and a maintainer hardening the copy next to the table would have edited dead code. Consolidated into one definition in the file that creates the table and trigger. CRD-47 asserts from the catalog that exactly one `validate_credit_reversal()` and one guard trigger exist and that the body still carries the balance check, the student binding and the row lock.
**Also newly covered:** append-only on UPDATE as well as DELETE (CRD-44/45; CRD-05 covered DELETE only), negative grants and unknown wallets (CRD-46/46b), direct ledger writes by the runtime and worker roles (CRD-46c/46d).
**Sensitivity measured for every new test:** student binding removed → CRD-42 fails; weak duplicate guard restored → CRD-39 fails; wallet row lock removed → WS-CRD-LAST-02/03/04/05 fail with `debits=2 ledger=-1 available=-1 entitlements=2 capacity=2`. The pre-existing credit suite is unchanged at 43 PASS lines, exit 0. A trap is recorded in the race script because it had already cost this project once: in the no-lock control the "second activation is blocked" observation still appears, since the activation command takes other row locks — that observation proves only that the sessions overlapped, and the outcome assertions are the evidence.
**OQ-CRD-1 was not reopened** (resolved; CRD-32..38 unchanged). **OQ-CRD-2 and OQ-CRD-3 were not decided:** nothing expires, extends, forfeits or automatically returns a reserved entitlement, and the production activation path stays fail-closed on the entitlement period.
Local evidence: PostgreSQL 16.15, cleared cluster, all 21 implementation test steps passed, 585 PASS assertion lines, 0 FAIL, plus the Python verifier unit tests, plus a documentation consistency check reported separately and not counted as implementation evidence. **GitHub Actions at the resulting HEAD: NOT RUN.** Batch 2 was pushed as `7da927d` and its Actions result has not been reported. Phase 2 Gate remains **NOT READY**; Phase 3 is not authorized; D-014 synthetic-only stays in force.

### 2026-11-14 — Phase 2 Batch 2: clock discipline at security decision points (draft SQL; synthetic)
`fix/security/test/docs:` **One defect, found three times, each instance demonstrated before being fixed.** In PostgreSQL `now()`, `transaction_timestamp()` and `CURRENT_TIMESTAMP` return the TRANSACTION START time and do not advance, so any expiry, freshness or authorization decision made from them can be defeated by holding a transaction open.
1. **`consume_governance_receipt_and_apply()`** validated the proof-receipt window with `now()`. A receipt with a two-second lifetime was **consumed and applied four seconds after expiry**, ending up `consumed` with a governance event attached. This was worse than an ordinary off-by-one because the expiry window is the **only** freshness control the database has — revocation propagation across service handoffs is PS-8 and deferred. The pre-existing RC-21/RC-22 missed it: their receipts were already outside the window at transaction start, which `now()` evaluates correctly.
2. **`change_student_mobile_contact()`** had the same defect in the one-time contact-change proof window. That proof authorizes changing a student's **global** contact identity, so its expiry is the entire point of it being one-time.
3. **`guardian_permissions_effective`** — the view whose own comment states it is "the ONLY read shape that may be used for a guardian access decision" — kept reporting a permission as effective after it had expired mid-transaction. That stale read *was* the access decision.
**Fix:** each site reads `clock_timestamp()` once, after the relevant row lock, which is the pattern the H-01 remediation established for the credit reversal window. `archive_student_enrollment()` and `change_student_mobile_contact()` now also write their stored timestamps (`ended_at`, `archived_at`, `consumed_at`, `updated_at`) from that same post-lock `v_now`, so audit time equals decision time. **No clock-skew tolerance was introduced:** PS-5 is deferred and none is invented.
**A guard against a fourth instance**, because fixing three is not the same as preventing a fourth: `workspace_clock_discipline_tests.sql` CLK-01 scans the **catalog** — every SECURITY DEFINER function and every view — and fails **by name** on any transaction-start clock, carrying one reviewed allowlist entry (`append_workspace_governance_event`, which writes a stored value and decides nothing). CLK-02 narrowly pins the previously defective windows so an over-broad allowlist edit still fails. CLK-03 is behavioural, because a static check alone would miss a view rewritten to compare against a column holding a stale value.
**Every new test was shown to FAIL against the pre-fix code:** RC-FRESH-01 with `v_now := now()`, CC-FRESH-01 with the pre-fix command, CLK-01 naming `view guardian_permissions_effective` with the pre-fix view. New suites: `receipt_60_freshness_tests.sql` RC-FRESH-01..04, `cp_47_freshness_tests.sql` CC-FRESH-01..03, `workspace_clock_discipline_tests.sql` CLK-01..03.
**Batch 2 scope note:** the proof-receipt boundary, narrow `verifier_rt` registration, independent binding revalidation at the command boundary, atomic consumption with event append and projection update, replay protection, idempotency and the negative/tampering/claim-mismatch/revocation/concurrency tests were **already implemented** in earlier work. This batch adds the missing freshness dimension. **Still NOT IMPLEMENTED and not claimed:** the authenticated private service channel (PS-6), production signature verification (PS-1..PS-4, the verifier stays fail-closed), end-to-end revocation freshness (PS-8).
Local evidence: PostgreSQL 16.15, cleared cluster (0 leftover databases, 0 leftover roles), all 21 implementation test steps passed, 568 PASS assertion lines, 0 FAIL, plus the Python verifier unit tests, plus a documentation consistency check reported separately and explicitly not counted as implementation evidence. **GitHub Actions at the resulting HEAD: NOT RUN**; the agent has no Actions access. Batch 1 was pushed as `cc8cd64` and its Actions result has not been reported. Phase 2 Gate remains **NOT READY**; Phase 3 is not authorized; D-014 synthetic-only stays in force.

### 2026-11-14 — Phase 2 Batch 1: source transfer freeze and database write barrier (draft SQL; synthetic)
`feat/security/test/docs:` **A real enforcement gap was found and closed.** The Control Plane recorded that a source freeze had happened (`transfer_cases.source_freeze_token`, `source_frozen_at`) while the Workspace database enforced nothing — `grep -rn "freeze\|frozen\|drain" docs/phase2/workspace/*.sql` returned 0 matches — so a source Workspace could keep writing a student's data straight through cutover and the final snapshot could miss writes taken after it. `docs/phase2/workspace/workspace_transfer_freeze.sql` now implements the database half of the OQ-E freeze boundary: a durable freeze record unique per token and per (student, case, source generation); a write-barrier row trigger on **all 26** student-scoped tables, which binds every writer including the Workspace runtime role and the SECURITY DEFINER commands because it is a trigger and not a privilege check; an **in-flight transaction barrier** (`FOR SHARE` on the student row inside `assert_student_not_frozen`, `FOR UPDATE` on the student and all its enrollments in the freeze command) recording the closing transaction id as `barrier_watermark_txid`; token-bound idempotency with a different token for the same case refused rather than accepted; unfreeze only before the ownership switch; and a **permanent fence** applied by the inbox projection once the source observes the switch, under a transaction-scoped bypass keyed on `txid_current()`.
**A second gap surfaced while testing it:** `counselor_assignments`, `activation_command_log` and `archive_command_log` are student-scoped only through `enrollment_id` and were unprotected by the first version of the barrier. The trigger now takes a key-kind argument and resolves the student through the enrollment; coverage went from 23 tables to 26, and FRZ-01 asserts the count from the catalog so a new student-scoped table added without a barrier fails the test.
**Evidence:** FRZ-01..FRZ-37 (37 assertions, 36 PASS lines) and WS-FRZ-BARRIER-01..04 in two modes (8 PASS lines), wired into `.github/workflows/phase2-schema-tests.yml` as two new steps — 18 runnable steps to 20. **The race test's sensitivity was verified and its first version was not sensitive:** without the `FOR SHARE` lock the `fk` mode still passes, because PostgreSQL's foreign-key row lock blocks the freeze for any table with a foreign key to `students`; the `nofk` mode writes `class_session_participants` (student-scoped, but referencing `class_participants`) and **fails** without the barrier.
**Not claimed:** the freeze of API, worker, import, export and file surfaces — those do not exist in this repository (`backend/`, `frontend/`, `scripts/`, `tests/` hold only `.gitkeep`); what is claimed is that any surface reaching this database is refused. The outstanding-work count is reported by the caller, not observed by the database. No freeze duration, drain timeout or acceptance threshold is invented. The freeze receipt is not signed (OQ-SAGA-1, PS-1..PS-4).
**Also in this commit:** `docs/phase2/UNRESOLVED_ITEM_REGISTER.md` and `docs/phase2/unresolved_items.json`, the mandatory unresolved-item register for Q-007, Q-020, OQ-CRD-2/3, OQ-SAGA-1/2, OQ-ASM-1, OQ-D, OQ-E, PS-1..PS-8, M-05, M-06, WS-DOM-02, the transfer exception approval authority, the PR #8-#11 disposition and branch synchronization. Nothing in it is decided by the implementation. **One standing claim was false and is corrected there and in `PROJECT_STATE.md`:** "PR #12 behind main" is not true — `main` is at `ba5e9d8` and `git merge-base --is-ancestor ba5e9d8 HEAD` exits 0, so the branch already contains all of `main`.
Local evidence: PostgreSQL 16.15, cleared cluster (0 leftover databases, 0 leftover roles), all 20 runnable workflow steps passed, 557 PASS assertion lines, 0 FAIL, plus the Python verifier unit tests. **GitHub Actions at the resulting HEAD: NOT RUN**; the implementation agent has no Actions access. Phase 2 Gate remains **NOT READY**; Phase 3 is not authorized; D-014 synthetic-only stays in force.

### 2026-11-14 — Phase 2: OQ-CRD-1 resolved and its exact boundary tested (draft SQL; synthetic)
`feat/test/docs:` The Product Owner resolved OQ-CRD-1 on 2026-11-14: the credit reversal window is an exact 168-hour interval from the stored activation timestamp with an **inclusive** boundary. The rule is extracted from `archive_student_enrollment()` into `credit_reversal_window_end()` and `credit_reversal_eligible()` — IMMUTABLE, side-effect free, taking explicit timestamps — so the boundary can be tested exactly instead of bracketed. New tests CRD-32..CRD-38 cover the deadline minus one microsecond (eligible), the **exact** deadline (eligible), the deadline plus one microsecond (ineligible), monotonicity across the window, identical verdicts in four time zones, and that the command keeps no second copy of the interval. The command still reads its own `clock_timestamp()` **after** acquiring the entitlement row lock, and WS-CRD-LOCK-01/02 is unchanged and still passing. Canonical documents reconciled: OQ-CRD-1 is recorded RESOLVED in `OPEN_QUESTIONS.md`, a 2026-11-14 Product Owner clarification is recorded in `DECISION_LOG.md` without a new D-number, and the stale "open clarification" wording is removed from the archive draft, the credit contract and `IMPLEMENTATION_RESPONSE_2026-11-14.md`. **OQ-CRD-2 and OQ-CRD-3 remain OPEN** and the production-intended activation path stays fail-closed. No security boundary was weakened: per-recipient outbox delivery and acknowledgement, post-lock timestamp reads, the fail-closed activation and inbox paths and the D-014 synthetic-only restriction are all intact. Local evidence: PostgreSQL 16.15, cleared cluster, all 18 runnable workflow steps passed plus the Python verifier unit tests. Phase 2 Gate remains **NOT READY**; Phase 3 is not authorized; CI on the resulting HEAD is not verified by the implementation agent.


### 2026-11-14 — Phase 2: remediation of Supervisor findings C-01 and H-01..H-06/M-01 on head `8abbbe3` (draft SQL; synthetic)
`fix/security/test/docs:` **C-01 (critical, real defect):** Saga delivery kept one row per event, so the first recipient's acknowledgement marked the whole event done and retries stopped for the other Workspace. Delivery is now tracked per declared recipient — `outbox_event_recipients` states the audience and is immutable, `outbox_deliveries` is keyed `(event_id, workspace_id)` with its own state, lease, attempts, send record and acknowledgement, acknowledgement requires a declared recipient and a successful send first, and `outbox_event_completion` reports an event complete only when every required recipient has acknowledged. Dead-letter and re-drive act on one recipient and are audited per recipient.
**H-01/H-04:** the credit wall clock is read only after the required row locks; activation resolves one authoritative timestamp and uses it for the enrollment start, the entitlement row and the audit. Regression `WS-CRD-LOCK-01/02` is deterministic and its sensitivity was verified against the pre-fix code.
**H-02:** the production-intended activation path takes no period argument and fails closed (`feature_not_supported`, OQ-CRD-3); the caller-supplied-period command is renamed `activate_student_enrollment_synthetic` and granted only to `ws_<key>_synth_exec`. No entitlement duration source was invented.
**H-03:** acknowledgement is bound to the exact event and recipient, refuses a non-recipient, refuses an acknowledgement before send, and is idempotent per recipient.
**H-05:** `payload_hash` is transport integrity, not authentication; the production-intended inbox path fails closed pending an approved verified transport (OQ-SAGA-1, PS-1..PS-4/PS-6) and the application logic moved to a role-gated synthetic command. No cryptography was invented.
**H-06/M-01:** reactivation requires the proposed counselor to actually hold the counselor role, and the counselor is bound to the idempotent command and compared on replay.
Local evidence: PostgreSQL 16.15, cleared cluster, all 18 runnable workflow steps passed (504 PASS assertion lines) plus the Python verifier unit tests. Draft SQL and synthetic data only (D-014). Saga service behaviour, a verified transport, the entitlement period source, retry/lease thresholds and quarantine resolution remain unimplemented or open. Phase 2 Gate remains **NOT READY**; D-014 remains in force; Phase 3 is not authorized; CI on the final HEAD is not verified by the implementation agent.


### 2026-11-14 — Phase 2: Product Owner decisions PD-2026-11-13-A..F implemented (draft SQL; synthetic)
`feat/security/test/docs:` Implemented the approved decisions as database contracts with executable tests.
**Assessment (A):** `test_definition_version_questions` makes question membership and order the authority; publication requires a complete contiguous set; a response is bound by composite foreign keys to a question of its own attempt's version; the attempt scoring snapshot must equal the published version's; adaptive (`per_attempt`) publication is refused in MVP.
**Activity (B):** five typed, FK-backed source columns replace any polymorphic reference, each carrying `student_id`; `class_participants` and `class_session_participants` added; one activity per source record; student and kind immutable.
**Transfer approvals (C):** separation of duties enforced, the `source_destination_owner` exception stored disabled and unstorable-if-enabled, approval side bound to the case's source/destination Workspace, a dedicated `record_transfer_approval`/`revoke_transfer_approval` command and executor identity, and post-lock expiry moved to `clock_timestamp()`.
**Student Credit (D):** `student_entitlements`, a 168-hour inclusive compensating-return window, student-bound reserved credit excluded from the spendable balance, free reactivation only inside the original period with no new debit and no period extension, and `credit_wallet_balances`. `activate_student_enrollment()` now requires an entitlement period end (signature change).
**Saga (last open HIGH):** the outbox envelope gained schema version, payload hash, student, both Workspaces, generation and correlation/causation ids and became fully immutable; delivery state, dispatcher leases, attempts, dead-letter and audited re-drive moved to `outbox_deliveries`/`outbox_delivery_audit`; the Workspace gained `workspace_inbox_events` and `apply_inbox_event()` with stale rejection, future quarantine and atomic inbox+projection under generation fencing.
Local evidence: PostgreSQL 16.15, cleared cluster, all 18 runnable workflow steps passed (476 PASS assertion lines) plus the Python verifier unit tests. This validates draft SQL and synthetic tests only. No distributed atomicity is claimed; Saga service behaviour, signed wire format, retry/lease thresholds and quarantine resolution remain unimplemented or open. Phase 2 Gate remains **NOT READY**; D-014 remains in force; Phase 3 is not authorized; CI for this commit is not verified by the implementation agent.


### 2026-11-09 — Phase 2 Control Plane function-owner split (draft; synthetic CI)
`security/test/docs:` Replaced the shared Control Plane SECURITY DEFINER owner with three non-login function-family owners for transfer, HMAC rotation and initial identity admission. Narrowed grants by table/function family; added column-scoped row-lock privileges for identity-gate, immutable Workspace UUID and append-only admission-command rows; added a Workspace UUID immutability trigger; expanded role catalog assertions and aligned the privilege contract, project state and Supervisor review. GitHub Actions run #222 passed on PostgreSQL 16 at exact branch HEAD `2f605051440b4198794e710283f0a6d852983316`. This validates only the draft SQL and synthetic tests; production credentials, KMS/HSM, API authorization, distributed transfer Saga and operational resilience remain unverified. Phase 2 Gate remains NOT READY; D-014 synthetic-only restriction remains in force; Phase 3 is not authorized.


### 2026-10-24 — Merge of Phase 1 traceability follow-up (PR #6)
`docs:` PR #6 was squash-merged into `main` at `fb16219d506998c9e074971927b55e322f32c21d`. Post-merge verification confirmed 51 unique active Alt-5 acceptance specifications with no duplicates and 41 path-inventory rows; all active contract IDs are mapped to at least one active path row and all active row references exist in the catalog. No code, migration, infrastructure, or executable test was added or run. Phase 1 remains approved for design/documentation only under D-024; Q-023 remains a pre-hosting gate, Phase 2 remains unauthorized, and real student data remains prohibited under D-014.


### 2026-10-24 — Final Alt-5 traceability and consistency follow-up
`docs(security/test):` Independent follow-up review found that the category-level tenant-path inventory still referenced retired Option C/legacy TI-CTX/TI-CONN/TI-REPO/TI-RPT/TI-EXP/TI-PLAT/TI-FK/TI-BYP/TI-CFG contracts. Aligned the inventory with active Alt-5 contracts; updated the retention draft and target-environment load plan to use current cell/lifecycle contracts; corrected active Q-014/Q-016/Q-017/Q-018 dependencies; clarified D-017's recorded pool-size-1 baseline as unmeasured under Alt-5; and marked pre-D-020/D-024 architecture recommendations/reviews as historical.

Added four explicit specifications: TI-API-14 (tenant-scoped audit-log reads), TI-FILE-03 (tenant-safe uploads), TI-JOB-04 (platform aggregate-job boundaries), and TI-CODE-01 (static guard for unreviewed privileged/raw-SQL access paths). The active catalog now has 51 unique specifications; the 41-row inventory covers 40 active Alt-5 paths (39 mapped, one blocked by Q-007) and explicitly excludes the historical Option D row; 0 specifications implemented, 0 executed, 0 passing. This is documentation and contract work only. No runtime code, migration, infrastructure, or executable test was created or run. Phase 1 remains APPROVED for design/documentation only under D-024; Q-023 remains a hard pre-hosting gate, Phase 2 remains unauthorized, and real student data remains prohibited under D-014.


### 2026-10-23 — Phase 1 corrective alignment (design only)
`docs:` Corrected the Option A / Option C contradiction: Option C's normative contract now uses per-tenant PostgreSQL login roles, a narrowly allowlisted tenant-mapping helper, and direct per-tenant pools. Marked legacy GUC-dependent TI-CTX contracts as SPEC-ONLY, revised direct-pool lifecycle contracts, defined tenant-by-tenant data-migration rules under FORCE RLS, aligned Q-016 with D-017, and added Q-021 for explicit Product Owner disposition of broad-credential/owner-role compromise residuals.

Verification boundary: documentation only. The 123 contracts remain specifications: 0 implemented, 0 executed, 0 passing. PR #3 remains unmerged and Phase 1 remains NOT APPROVED pending independent review. Phase 2 is not authorized and real student data remains prohibited by D-014.


### 2026-10-17 — Phase 1 Corrective Pass and Owner Decisions (design only)
`docs:` Reconciled Q-019 gates (design direction, implementation validation, pilot authorization) in Q019 evaluation §6 and §8. Recorded owner decisions D-016 (Option C preferred design direction, subject to design review; Option D not selected; pool, lifecycle, shared-role prohibition; provisional cap of 10 tenants). Added TI-CONN-04/05/06; contracts recounted to 123. Updated PROJECT_STATE and ROADMAP status to separate Phase 0 (approved, closed), Phase 1 (submitted for review, not approved) and real-data pilot (prohibited).

Verification boundary: documentation only. No application code, migrations, roles, RLS policies, or infrastructure were created. No test was executed. Phase 1 is not approved. Phase 2 not started.

### 2026-10-08 — Phase 0 Foundation
`docs:` Establish Phase 0 project foundation.

Added:
- `PRODUCT_REQUIREMENTS.md` — product vision, roles, business model, domains
- `PROJECT_SCOPE.md` — MVP boundary vs. deferred features
- `ARCHITECTURE.md` — layering, multi-tenancy strategy, adapter boundaries, versioning, explainability
- `DATABASE.md` — conceptual domain/entity model (no migrations yet)
- `API.md` — API strategy, authz principles, resource groups (no endpoints yet)
- `ROADMAP.md` — 28-phase roadmap (unchanged from Master Prompt)
- `PROJECT_STATE.md` — operational state tracker, Phase 0 marked IN PROGRESS
- `DECISION_LOG.md` — initial architectural decisions and proposals
- `OPEN_QUESTIONS.md` — unresolved requirements needing a human decision
- `TEST_PLAN.md` — testing strategy incl. mandatory tenant-isolation and billing tests
- `SECURITY.md` — security requirements and threat model
- `DEVELOPMENT_GUIDE.md` — mandatory per-phase workflow, repo conventions
- `README.md` — project overview and entry point
- `CHANGELOG.md` — this file

No backend, frontend, database migration, authentication, billing, Telegram, SMS, or AI code was written in this phase, by design (Master Prompt §77, explicit instruction in this session).

### 2026-10-08 — Phase 0 Documentation Correction Pass
`docs:` Align Phase 0 documents with the actual GitHub repository state, per project owner instruction following the latest Supervisor Review.

Changed:
- `PROJECT_STATE.md` — replaced stale "GitHub push blocked / no access" language with the confirmed repository state (commit `bd24cf8de6e836eea5602fd504530f34343e80fa`, message `docs: establish Phase 0 project foundation`); clarified Phase 0 remains IN PROGRESS pending Supervisor Approval; clarified Phase 1 is not started/not authorized.
- `DECISION_LOG.md` — D-007 marked RESOLVED/HISTORICAL (kept, not deleted); noted the original access limitation no longer applies.
- `OPEN_QUESTIONS.md` — restructured into "Open (Active)" and "Resolved/Closed" sections; Q-011 moved to Resolved/Closed with the confirmed commit reference; Q-001/Q-002/Q-010 left unchanged (still unanswered, not guessed).
- `ROADMAP.md` — current-status note updated to reflect the repository state without declaring Phase 0 Approved or Phase 1 started.
- `DEVELOPMENT_GUIDE.md` — softened the Phase 0 repo-skeleton language: `backend/ frontend/ tests/ scripts/ deployment/` are no longer described as required in Phase 0; a documentation-only repository is explicitly allowed until the phase that needs a given folder begins.
- `README.md` — added `SUPERVISOR_REVIEW.md` to the document index table for consistency.

Added:
- `SUPERVISOR_REVIEW.md` — structural placeholder only, per Master Prompt §55; no review content invented, awaiting the actual Supervisor Review text.

No architecture, feature, or scope decisions were introduced in this pass beyond what is recorded above in `DECISION_LOG.md`.

### 2026-10-08 — GitHub Connector Access Confirmed (Read-Only); Correction Pass Pushed via Manual Token
`chore:` A GitHub connector was connected for this session and briefly able to read the repository while it was made temporarily public, confirming the then-current commit (`bd24cf8de6e836eea5602fd504530f34343e80fa`, "docs: establish Phase 0 project foundation") and its 14 files. The connector was never able to write to the repository (write attempts failed with `403 Resource not accessible by integration` while public, and `404 Not Found` once the repository was returned to private). The correction pass described in the "Phase 0 Documentation Correction Pass" entry above was ultimately pushed to `main` as commit `994d4529c20c4a330bd843bd3ca1a7c9ed1f75ec` using a manually supplied, short-lived Personal Access Token pasted into the conversation by the project owner, not via the connector. The project owner was asked to revoke that token after use.

**Note for anyone reading history out of order:** the commit hash `bd24cf8de6e836eea5602fd504530f34343e80fa` referenced throughout the two entries above is the *first* Phase 0 commit (initial foundation). It was superseded by `994d4529c20c4a330bd843bd3ca1a7c9ed1f75ec` (the correction pass itself) as the actual latest commit on `main`. Do not read `bd24cf8d...` as the current state of the repository.

### 2026-10-09 — Third Documentation Correction Pass (Commit-Reference Cleanup)
`docs:` Fix remaining stale commit references and re-examine Q-011, per a direct Supervisor Review instruction. Work done on branch `docs/phase0-correction-pass-3`, not directly on `main`.

Changed:
- `PROJECT_STATE.md` — corrected "Last Updated" date and "Last Verified Commit" to the actual current `main` HEAD (`994d4529c20c4a330bd843bd3ca1a7c9ed1f75ec`), which the previous correction pass had left pointing at the superseded `bd24cf8d...` commit; added an explicit three-way distinction (latest commit in GitHub vs. content reviewed by Claude vs. Supervisor approval); rewrote "Repository Status" to accurately state the connector has no working persistent access and that all pushes so far used manually supplied, temporary tokens; updated Completed/In Progress/Blocked/Next Actions accordingly.
- `ROADMAP.md` — updated the "وضعیت فعلی" section to reference the correct latest commit (`994d4529...`) instead of the superseded one; made explicit that commit-existence verification is not the same as Supervisor content approval; noted this is the third correction pass, on a separate branch.
- `OPEN_QUESTIONS.md` — Q-011 re-examined: since the connector does not currently have reliable, persistent access to the repository (only manual, temporary tokens have worked), Q-011 is no longer presented as simply resolved/closed; see the updated entry for the precise, non-guessed status.
- `CHANGELOG.md` — this entry; prior entries preserved unchanged, with one clarifying note added (see above) rather than rewritten, to avoid losing history.

No backend/frontend/API/DB/auth/billing/Telegram/SMS/AI/Planning-Engine code was created. No new phases, features, or scope were added. No open question was answered or guessed. No secret, password, token, or credential is included in this file or in any commit message.

### 2026-10-09 — Fourth Correction: Q-003 Restored; GitHub Access Reported Precisely
`docs:` Commit `46563bec73dd965d392949be0dd5318d95edd087` on branch `docs/phase0-correction-pass-3` (added to open PR #1), per project owner's two requested fixes after reviewing commit `3b7c2dd3849ccc4f9f64d9baf0b0570487fecbb4`.

Changed:
- `PROJECT_STATE.md` — the "Open Questions" summary line had silently dropped Q-003 (depth of Billing in MVP) when previously written as "Q-001, Q-002, Q-004 through Q-010"; restored to explicitly name Q-001 through Q-011. Replaced the general claim about connector access with a precise, event-by-event, tested-only log, separated by environment (Claude's GitHub connector / Claude's manually-supplied temporary token / the Supervisor's own tooling — explicitly marked untested and not inferred from the other two) and by operation (Read vs. Write reported independently).
- `OPEN_QUESTIONS.md` — Q-011 rewritten in the same tested-only, environment-separated, Read/Write-separated format as above, replacing the earlier narrative-style summary with a chronological table per environment.

No backend/frontend/API/DB/auth/billing/Telegram/SMS/AI/Planning-Engine code. No new phases, features, or scope. No open question answered or closed on the project owner's behalf. `main` was not touched; all work stayed on `docs/phase0-correction-pass-3`.

### 2026-10-09 — Fifth Correction: Sync Branch-Commit Reference, Correct PR Status Wording
`docs:` Commit `54eaa3d99510d12beb53eb310346700ff7893b24` on `docs/phase0-correction-pass-3` (added to open PR #1), per project owner's three requested fixes after reviewing commit `46563bec73dd965d392949be0dd5318d95edd087`. Diff stat: `CHANGELOG.md | 9 ++++++++`, `PROJECT_STATE.md | 14 +++++++++-----` (2 files changed, 18 insertions(+), 5 deletions(-)).

Changed:
- `PROJECT_STATE.md` — corrected the branch's latest-commit reference from the then-superseded `3b7c2dd3...` to the then-current branch HEAD `46563bec73dd965d392949be0dd5318d95edd087`, while keeping the `main`-branch commit (`994d4529c2...`) reported separately in its own line rather than merged into one statement.
- `PROJECT_STATE.md` — "Current Milestone" and "In Progress" rewritten to state that PR #1 was already open (not "being opened").
- `CHANGELOG.md` — added the "Fourth Correction: Q-003 Restored..." entry documenting what commit `46563bec...` had changed (this was itself the change made by `54eaa3d`, now being recorded here as its own entry since the CHANGELOG did not previously have a dedicated entry for `54eaa3d`'s own diff).

### 2026-10-09 — Sixth Correction: Remove Self-Referential Stale-HEAD Claims; Correct Next Actions; Record Do-Not-Merge
`docs:` Commit `926eb81c6cc1f401235d367dea8c89825ca24dec` on `docs/phase0-correction-pass-3` (added to open PR #1), per Supervisor review requesting three fixes after reviewing commit `54eaa3d99510d12beb53eb310346700ff7893b24`. Diff stat: `PROJECT_STATE.md | 21 ++++++++++++---------` (1 file changed, 12 insertions(+), 9 deletions(-)).

Changed:
- `PROJECT_STATE.md`, "Last Verified Commit" — removed the structurally-impossible claim that a specific SHA is "the current HEAD of this branch" (a file cannot truthfully state the hash of the commit it is itself part of, since the hash is only known after the commit is made). Rewrote to record only the branch HEAD immediately prior to each edit, plus the full commit history known at that point, with `git log`/GitHub named as the authoritative source for the true current HEAD.
- `PROJECT_STATE.md`, "Next Actions" — removed stale "Pull Request if one could be created" language (PR #1 had already existed and been open since an earlier round); replaced with its actual status and the explicit "do not merge yet" recommendation from that review round.
- `PROJECT_STATE.md`, "Blocked" — added the same do-not-merge recommendation for consistency; removed hardcoded round-counts ("three rounds", "the third commit", "four rounds") since those also go stale on every subsequent commit, pointing to `CHANGELOG.md`'s dated list as the authoritative count instead.

### 2026-10-10 — Seventh Correction: Remove Remaining Hardcoded Round-Count
`docs:` Commit `74be46e6d9e512f271e0f172621c0b6064a741ef` on `docs/phase0-correction-pass-3` (added to open PR #1), per Supervisor review requesting one fix after reviewing commit `926eb81c6cc1f401235d367dea8c89825ca24dec`. Diff stat: `PROJECT_STATE.md | 2 +-` (1 file changed, 1 insertion(+), 1 deletion(-)).

Changed:
- `PROJECT_STATE.md`, "In Progress" — replaced "main has not been touched by any of the three correction rounds" (a hardcoded, self-staling count) with "main has not been touched by the documentation correction work on this branch."
No backend/frontend/API/DB/auth/billing/Telegram/SMS/AI/Planning-Engine code in any of the three commits above. No new phases, features, or scope. No open question answered or closed on the project owner's behalf. `main` was not touched by any of them; all work stayed on `docs/phase0-correction-pass-3` / PR #1. Diff stats and commit messages above were read directly from `git show --stat`/`git log` against the real repository, not reconstructed from memory.

### 2026-10-10 — Eighth Correction: Sync PROJECT_STATE.md "Last Updated" Date
`docs:` Commit on `docs/phase0-correction-pass-3` (added to open PR #1), following commit `a616f4841b525d1c8e658d1247448c2d68416bdc`, per Supervisor review flagging one remaining issue. **This entry intentionally does not state this commit's own SHA**, since that hash is not known until after the commit is made — stating it here would be the same self-referential, structurally-impossible claim that earlier correction rounds removed elsewhere in these documents (see the "Sixth Correction" entry above). The actual SHA is reported separately, outside this file, in the session's commit/report output.

Purpose of this change: `PROJECT_STATE.md`'s top-of-file `Last Updated` field still read `2026-10-09`, even though the most recent documentation edit on this branch (commit `a616f4841b525d1c8e658d1247448c2d68416bdc`) was made on `2026-10-10` (confirmed via that commit's actual author/committer date on GitHub). The field is purely a human-readable freshness indicator at the top of the file and does not feed into or get read by any other section, so updating it carries no architectural, scope, or open-question implication.

Changed:
- `PROJECT_STATE.md` — `Last Updated: 2026-10-09` → `Last Updated: 2026-10-10`.

No backend/frontend/API/DB/auth/billing/Telegram/SMS/AI/Planning-Engine code. No new phases, features, or scope. No open question answered or closed on the project owner's behalf. No architecture or business decision made. `main` was not touched; all work stayed on `docs/phase0-correction-pass-3` / PR #1. Only `PROJECT_STATE.md` and this `CHANGELOG.md` entry were changed in this round — no unrelated edits were made.

**Known gap, reported rather than silently fixed (out of scope for this round):** commit `a616f4841b525d1c8e658d1247448c2d68416bdc` itself also has no dedicated CHANGELOG entry describing its own diff (it was the commit that backfilled entries for three earlier commits, but never got one for itself). This was not in the scope of the two fixes requested for this round, so it was left as-is rather than fixed without being asked. Flagging it here for the Supervisor's awareness in case a future round should address it.

### 2026-10-10 — Ninth Correction: Backfill CHANGELOG Entry for Commit a616f484
`docs:` New entry on `docs/phase0-correction-pass-3` (added to open PR #1), closing the gap flagged in the "Known gap" note above. Content below was written after re-reading the real diff of commit `a616f4841b525d1c8e658d1247448c2d68416bdc` directly from the repository (`git show --stat` and full `git show` on that SHA) in this session, not from any earlier report.

`docs:` Commit `a616f4841b525d1c8e658d1247448c2d68416bdc` on `docs/phase0-correction-pass-3` (added to open PR #1, authored 2026-10-10T05:47:20Z), per Supervisor review requesting three fixes after reviewing commit `74be46e6d9e512f271e0f172621c0b6064a741ef`. Diff stat (verified): `CHANGELOG.md | 24 ++++++++++++++++++++++++`, `PROJECT_STATE.md | 4 ++--`, `ROADMAP.md | 2 +-` (3 files changed, 27 insertions(+), 3 deletions(-)).

Changed:
- `PROJECT_STATE.md`, "Repository Status" section — the line summarizing where commits came from previously named `3b7c2dd3...` as "all commits on this branch so far" and separately claimed `46563bec73dd965d392949be0dd5318d95edd087` was "the current branch HEAD," which was by then stale (three more commits had landed since `46563bec`). Reworded to stop naming a specific "latest branch commit" SHA in this section at all, and instead point to the "Last Verified Commit" section as the single place tracking branch history.
- `PROJECT_STATE.md`, "Last Verified Commit" section — the branch commit-history list had stopped at `54eaa3d99510d12beb53eb310346700ff7893b24` (accurate when originally written, inside commit `926eb81`), but two further commits (`926eb81` itself and `74be46e`) had since landed without the list being updated. Updated the list to include all five branch commits known at that point (`3b7c2dd3` → `46563bec` → `54eaa3d` → `926eb81` → `74be46e`), and corrected the "branch HEAD immediately before this edit" pointer from `54eaa3d...` to `74be46e...` (the real pre-edit HEAD, confirmed via `git log origin/main..HEAD` against the live repository).
- `CHANGELOG.md` — added three new dated entries backfilling commits `54eaa3d`, `926eb81`, and `74be46e`, none of which had a dedicated entry describing their own diff at the time. Content and diff stats for all three were read directly from `git show --stat`/`git log` against the real repository. All prior entries were left untouched (append-only).
- `ROADMAP.md` — replaced the hardcoded ordinal phrase "این سومین دور اصلاح مستندات" ("this third round of documentation correction") with a count-free description, and added a pointer to `CHANGELOG.md` for the full dated list of correction rounds — since a fixed ordinal in this file goes stale on every subsequent round in the same way SHA references go stale on every subsequent commit.

No backend/frontend/API/DB/auth/billing/Telegram/SMS/AI/Planning-Engine code. No new phases, features, or scope. No open question answered or closed on the project owner's behalf. No architecture or business decision made. `main` was not touched by commit `a616f484...`; all of its changes stayed on `docs/phase0-correction-pass-3` / PR #1. This entry was written from the commit's actual diff re-fetched from the repository in this session, not from memory of a prior report.

### 2026-10-10 — Tenth Correction: Resolve Template/Plan Versioning Contradiction (Supervisor-Directed)
`docs:` New commit on `docs/phase0-correction-pass-3` (added to open PR #1), per a Supervisor-directed correction task identifying a genuine contradiction in Phase 0 documentation about whether Program Template/Student Plan versioning exists in MVP.

**The contradiction (confirmed by searching all 14+1 documents before making any change):** `PROJECT_SCOPE.md` contained two statements that could not both be true at once — one said Program Templates have "no full Versioning in the first MVP; Versioning formally from Phase 15," the other (in the Out-of-Scope list) said "simple version in MVP, full in Phase 15." Separately, `ARCHITECTURE.md` §6 and `DATABASE.md` described `ProgramVersion`/`PlanVersion` as a standing architectural principle with no phase qualifier (implying it exists from the start), while `ROADMAP.md` mentioned the word "Versioning" only under Phase 15 — readable as versioning not existing at all before Phase 15.

**Resolution — proposed, not unilaterally decided:** added `DECISION_LOG.md` **D-008**, a proposed (not Accepted) MVP Versioning Policy: minimum viable, auditable versioning (stable identity + explicit version id + no silent overwrite + sufficient history + actor/tenant/student attribution + enforced authorization on every read/write + transaction-safe version creation/activation, tested when implemented) is in MVP scope for both Program Template and Student Plan; only *advanced* version-management tooling (visual diff, rollback UI, extensive history browsing, branching/parallel versions, change-impact reports) is deferred to Phase 15+. Added `OPEN_QUESTIONS.md` **Q-012** requesting the Product Owner's explicit confirmation or amendment of D-008 — D-008 is explicitly marked "Proposed — Pending Product Owner Confirmation," not Accepted, anywhere it appears.

Changed, to make every document internally consistent with the D-008 proposal (all still describing concepts only — no migration, table, or endpoint implemented):
- `PROJECT_SCOPE.md` — rewrote the self-contradictory Program Template bullet and the Out-of-Scope Versioning bullet to agree with each other: minimum viable versioning in-scope, only the named advanced features out-of-scope; added an explicit Student Plan versioning bullet (previously the Planning Engine MVP bullet didn't mention versioning at all).
- `ARCHITECTURE.md` §6 — added explicit "this is MVP scope, not Phase-15-only" framing, plus new tenant-isolation/authorization and transaction-safety notes for versions, plus a "conceptual only, nothing implemented" caveat.
- `DATABASE.md` — added attribution fields (`created_by`, `created_at`/`published_at`/`activated_at`) and a `program_version_id` link on `PlanVersion` to `ProgramVersion`, satisfying D-008's "record which template version produced each plan" requirement; added open-schema-decision notes (editable-vs-new-version states, template-update-vs-existing-plan behavior) pointing at Q-012; cross-referenced D-006 (the pre-existing `Plan`-naming-collision decision) to make clear D-008 does not silently resolve or touch that separate naming question.
- `ROADMAP.md` — added a note (without renumbering or reordering any phase) clarifying that minimum viable versioning is part of the Phase 2 foundational data model wherever Program Templates/Plans are used, and that Phase 15 specifically means *advanced* tooling plus personalization logic, not the introduction of versioning itself.
- `API.md` — added a conceptual (not designed, not implemented) placeholder section for version-related endpoints, under the same tenant/student-scoped AuthZ rule as everything else.
- `SECURITY.md` — added a "Program/Plan Versioning" entry to the project-specific sensitive-points list and a new row to the Threat Model table (silent overwrite / cross-tenant version access → no-UPDATE-on-published + tenant/student-scoped repository pattern + actor attribution).
- `TEST_PLAN.md` — added proposed (not-yet-run) Unit, Integration, and Tenant-Isolation test items for version numbering, no-mutation-of-published-versions, transaction safety, and cross-tenant version access.
- `PRODUCT_REQUIREMENTS.md` — updated the "Program Template و Plan باید Versioned باشند" principle to state this is an MVP requirement (proposed, D-008) and to explicitly re-affirm that "Plan" here means the educational student plan, not the commercial billing Plan (D-006).
- `PROJECT_STATE.md` — recorded this round's work in Completed/In Progress, added Q-012 to the Open Questions list and to the Phase-1 blocker list, and updated the branch commit-history pointer in "Last Verified Commit" to the real pre-edit HEAD (`fd128f74ae9fd60537c718829cb8afd66ea7f5b3`), per the now-established pattern of never asserting a commit's own SHA inside the commit that creates it.
- `DECISION_LOG.md` — added D-008 (Proposed).
- `OPEN_QUESTIONS.md` — added Q-012 (Open).

No backend/frontend/API/DB migration/auth/billing/Telegram/SMS/AI/Planning-Engine code anywhere in this change. No existing open question (Q-001 through Q-011) was answered or closed on the project owner's behalf. No architecture or business decision was finalized — D-008 is explicitly Proposed, pending confirmation. `main` was not touched; all work stayed on `docs/phase0-correction-pass-3` / PR #1. Phase 0 not declared Approved by this entry; only an independent Supervisor may make that assessment.


### 2026-10-10 — Product Owner Decision: Accept MVP Versioning Policy (D-008 / Q-012)
`docs:` Recorded the Product Owner's explicit decision to accept option B: minimum viable, auditable versioning for Program Template and Student Plan is mandatory in MVP; advanced version-management tooling remains deferred. Updated `DECISION_LOG.md` to mark D-008 Accepted, moved Q-012 from Open to Resolved/Closed in `OPEN_QUESTIONS.md`, and synchronized `PROJECT_STATE.md`. No other open question was closed. No implementation code, migrations, endpoints, or tests were added. No merge or Phase 1 authorization was granted.

### 2026-10-10 — Propagate D-008 Acceptance to the Remaining Eight Documents
`docs:` The commit above (and the four preceding it, made directly by the project owner) correctly updated `DECISION_LOG.md`, `OPEN_QUESTIONS.md`, `PROJECT_STATE.md`, and the original `CHANGELOG.md` entry recording D-008's Proposed status. It did not touch the eight other documents that, in an earlier correction pass, had described D-008 as "Proposed" / "pending Product Owner confirmation" in their own words. A repository-wide search (`grep -rn "D-008|Q-012|MVP Versioning Policy|ProgramVersion|PlanVersion|Pending Product Owner Confirmation|Proposed versioning policy"`) found these stale references and this commit updates them for consistency with the now-Accepted decision.

Changed (each a wording update only — no new requirement, no schema finalized, nothing marked implemented):
- `PROJECT_SCOPE.md` — items 4 and 5 (Program Template / Student Plan versioning) and the "وابستگی به تأیید" paragraph updated from "پیشنهادی، نیازمند تأیید" to reflect D-008 Accepted / Q-012 Resolved; explicitly kept the note that exact Phase 2 schema details remain open design work, not a Product Owner blocker.
- `PRODUCT_REQUIREMENTS.md` — the Core Principles versioning bullet updated the same way; clarified D-006 (Plan naming) remains Proposed and separate from D-008.
- `ARCHITECTURE.md` §6 — "proposed, pending Product Owner confirmation" → "Accepted, 2026-10-10"; added a sentence clarifying the acceptance settles the policy, not the final schema.
- `DATABASE.md` — updated both the "Programs" and "Planning" section headers, the `ProgramTemplate` platform-ownership note, the `PlanVersion` open-schema-decisions note, the D-006 cross-reference (explicitly reaffirming D-006 is still Proposed and independent of D-008), and the "Explicitly Deferred" list entry.
- `ROADMAP.md` — the versioning clarification note's header and closing sentence updated from "Pending Product Owner Confirmation" to "Accepted."
- `API.md` §8/§9 — "MVP scope pending confirmation" → "MVP scope confirmed by D-008, detailed design still pending"; clarified that only the endpoint *design* (ordinary Phase 2 work) remains open, not a policy decision.
- `SECURITY.md` — the "Program/Plan Versioning" sensitive-point entry and the Threat Model table row updated from "D-008، پیشنهادی" to "D-008 — Accepted."
- `TEST_PLAN.md` — three versioning-related test items updated from "پیشنهادی، پیوست به D-008" to "طبق D-008 — Accepted"; kept explicit that these are future, not-yet-run test items (no code exists to test).
- `PROJECT_STATE.md` — removed the now-stale Q-012 confirmation request from "Next Actions" item 4 (Q-012 is answered, not something to ask the project owner about anymore); updated the branch commit-history list in "Last Verified Commit," which had gone stale (last updated by Claude at `fd128f74...`, six commits behind the real `main`-ward branch tip at `0648c3c5...`) — the list now includes all thirteen commits on this branch and notes explicitly that commits `765617f8...` through `0648c3c5...` were authored directly by the project owner, not by Claude; fixed a missing blank line before the "Last Verified Commit" heading.

No backend/frontend/API/DB-migration/auth/billing/Telegram/SMS/AI/Planning-Engine code. No open question other than Q-012 (already closed by the project owner before this commit, not by this commit) was touched. D-006 and all other pending decisions were explicitly re-affirmed as still Proposed/unresolved, not silently resolved. `main` untouched; all work confined to `docs/phase0-correction-pass-3` / PR #1. Phase 0 not declared Approved by this entry; Phase 1 not started; PR #1 not merged.

### 2026-10-11 — Phase 0 Finalization: Commit-History Accuracy, Template Ownership/Tenant-Security Clarity, SUPERVISOR_REVIEW.md Honesty
`docs:` New commit on `docs/phase0-correction-pass-3` (added to open PR #1), per a Supervisor-directed finalization task with three parts.

**A. `PROJECT_STATE.md` commit-history accuracy.** The "Last Verified Commit" branch history had again gone stale — it stopped at `0648c3c5...` and could not account for the commit that itself added that stale list (`b2babcfef12f308b843fe0b94c118d9375845fe9`), which had since become a completed, known fact. Re-verified the full history directly against GitHub (`git log --format=... origin/main..HEAD`, `git rev-list --count` both directions, `git merge-base --is-ancestor`) and rewrote the section with: all 16 real commits from `main` to the pre-edit HEAD, explicit labeling of which were authored by the project owner vs. Claude, a new "branch-vs-main relationship" fact (16 ahead, 0 behind, clean ancestor, independently verified), and an explicit "what could not be verified" note (the private reasoning behind the project owner's own commits, as opposed to their public content). As before, this commit's own SHA is deliberately not recorded in the file it creates.

**B. Template ownership and tenant security (`DATABASE.md`, `SECURITY.md`).** Found and fixed a genuine inconsistency: `DATABASE.md`'s `ProgramTemplate` row listed `tenant_id` as if unconditionally present, while the same line's prose said a template might be "owned by a tenant or, later, platform-provided" — implying nullable/absent `tenant_id` in the platform case. Rewrote the "Programs" section to explicitly separate three cases: (1) tenant-owned `ProgramTemplate` (`tenant_id NOT NULL`, normal tenant-scoped rules), (2) potential platform-owned/shared `ProgramTemplate` (ownership model and authorization rule **explicitly marked unresolved**, not decided here or anywhere — added `OPEN_QUESTIONS.md` **Q-013** to track it), and (3) `StudentProgramEnrollment`/`PlanVersion` — stated to be **always** tenant-and-student-scoped with **no exception**, regardless of whether the underlying template is tenant- or platform-owned, explicitly preserving "no counselor can access or modify another tenant's students or data." Mirrored the same three-way distinction in `SECURITY.md`'s "Program/Plan Versioning" entry.

**C. Consistency review.** Re-verified across all 13 authoritative documents (including `SUPERVISOR_REVIEW.md`) that: D-008 remains Accepted; Q-012 remains Resolved; Q-001–Q-011 untouched; D-006 remains Proposed and independent of D-008; minimum auditable versioning remains MVP scope; advanced features remain deferred; nothing is represented as implemented; Phase 0 remains pending Supervisor review; Phase 1 remains unauthorized. Updated `SUPERVISOR_REVIEW.md` with a factual, clearly-labeled "not a formal review, not a verdict" activity log of what correction rounds occurred, per the task's explicit instruction not to represent Claude's own corrections as an independent Supervisor approval — no `Status` field was filled in, and the existing placeholder structure was preserved, not overwritten.

Changed: `PROJECT_STATE.md`, `DATABASE.md`, `SECURITY.md`, `OPEN_QUESTIONS.md` (new Q-013), `SUPERVISOR_REVIEW.md`, `CHANGELOG.md` (this entry).

No backend/frontend/API/DB-migration/auth/billing/Telegram/SMS/AI/Planning-Engine code or test anywhere in this change. No existing open question was closed or altered — Q-013 is new and Open, not a reclassification of an existing one. D-006 and D-008's statuses unchanged from this commit's perspective (D-008 was already Accepted before this commit; this commit did not touch that status). `main` untouched. PR #1 not merged. Phase 0 not declared complete or Approved — explicitly, finishing this task is not itself Phase 0 completion. Phase 1 not started.

### 2026-10-11 — Pass 4: Clarify ProgramVersion Ownership/Authorization (M-01), Add Q-013 to PROJECT_STATE Summary (M-02)
`docs:` New commit on `docs/phase0-correction-pass-3` (added to open PR #1), per two findings (M-01, M-02) from the latest independent Supervisor Review.

**M-01.** Q-013 and `DATABASE.md`/`SECURITY.md` previously distinguished tenant-owned vs. potential platform-owned `ProgramTemplate`, and separately stated `StudentProgramEnrollment`/`PlanVersion` are always tenant-and-student-scoped — but never explicitly addressed `ProgramVersion`'s own ownership/authorization model when its source template is platform-owned. Fixed by splitting Q-013 into two explicit parts (Template ownership; `ProgramVersion` ownership, independently) and updating `DATABASE.md`'s case-2 description and the `ProgramVersion` field entry, and `SECURITY.md`'s matching list, to state plainly that no model has been chosen for either part — not nullable `tenant_id`, not a separate flag, not a separate table, not copy-on-use, not read-only sharing, nor any other option. The tenant/student-scoping invariant for `StudentProgramEnrollment`/`Plan`/`PlanVersion` was reaffirmed as unaffected by either open question.

**M-02.** `PROJECT_STATE.md`'s Open Questions summary line listed Q-001–Q-003 through Q-011 but omitted Q-013 entirely. Added it, phrased to match its actual (two-part, still-Open, Low-priority) status in `OPEN_QUESTIONS.md`.
Changed: `DATABASE.md`, `SECURITY.md`, `OPEN_QUESTIONS.md`, `PROJECT_STATE.md`. This `CHANGELOG.md` entry was added as a directly-necessary consistency step consistent with `DEVELOPMENT_GUIDE.md`'s per-change-record workflow, not as unrelated scope expansion — no other document was touched.

No backend/frontend/API/DB-migration/auth/billing/Telegram/SMS/AI/Planning-Engine code or test. D-008 remains Accepted (unchanged). Q-012 remains Resolved (unchanged). D-006 remains Proposed, independent of D-008 (unchanged). Q-013 remains Open (expanded in detail, not closed). No other open question touched. `main` untouched. PR #1 not merged. Phase 0 not declared Approved; Phase 1 not started.

**Known, out-of-scope item observed but intentionally not fixed this round:** `PROJECT_STATE.md`'s "Last Verified Commit" branch-history list still names `b2babcfef12...` as the pre-edit HEAD, which is now one commit behind the real history (the commit that added that list, `d75d425fad929b7142cb2180f2ba172aa8c9b77f`, has since become a completed, known fact). This task's scope was limited to M-01 and M-02 specifically; per the instruction not to expand scope without first explaining why, this staleness is flagged here rather than silently fixed.

### 2026-10-12 — Consolidated Correction Pass: ProgramVersion Ownership Wording, Maintainable Commit-History Section, Phase 0 Checklist, D-007/Q-011 Reconciliation, Decision-Status Semantics, Repository-Wide Sweep
`docs:` New commit on `docs/phase0-correction-pass-3` (added to open PR #1), addressing seven findings from one consolidated independent Supervisor Review task.

**1. ProgramVersion ownership contradiction (`ARCHITECTURE.md` §6, `API.md` §8, `DATABASE.md`).** Each of these three previously made a blanket claim that every `ProgramVersion` (or its endpoints) is unconditionally tenant-scoped — contradicting Q-013 part 2, which leaves `ProgramVersion` ownership undecided for the possible platform-owned-template case. Rewrote all three to state precisely: `PlanVersion` is unconditionally tenant-and-student-scoped (no exception, ever); `ProgramVersion`'s tenant-scoping is unconditional only for the designed tenant-owned-template case, and explicitly undecided (not nullable `tenant_id`, not a flag, not a separate table, not copy-on-use, not global read-only — none selected) for the platform-owned case; and, regardless of how that's eventually resolved, every version operation must be authorized — "platform-owned" never means "unauthenticated." Also removed a stray, incorrect `ProgramTemplate` reference from `DATABASE.md`'s Plan/PlanVersion/PlanItem tenant-scoping line (that line's "every row above" never included `ProgramTemplate` in the first place). Q-013 left Open, Low priority, unchanged.

**2. `PROJECT_STATE.md` commit-history maintainability.** The repeatedly-regenerated "complete" branch commit list (which has gone stale on three separate prior rounds) was replaced with: a pointer to PR #1 and `git log -1` as the live source of truth for the current HEAD; a pointer to this `CHANGELOG.md` as the authoritative per-commit history (append-only, so it doesn't share the staleness problem); and exactly one clearly-dated "last verified snapshot" (`main` HEAD, branch HEAD, ahead/behind counts, as verified at the start of this session) explicitly labeled as a historical point-in-time fact, not a current-state claim. The structural note explaining why a commit's own SHA is never recorded in the commit that creates it was kept, trimmed. The three-way distinction (commit existence vs. document review vs. Supervisor approval) was preserved and restated.

**3. Phase 0 checklist reference.** `DEVELOPMENT_GUIDE.md` referenced a "Phase 0 Checklist in PROJECT_STATE.md" that didn't exist under that name. Added a concise "Phase 0 Documentation-Readiness Checklist" section to `PROJECT_STATE.md` (Option A), with each item's evidence stated and nothing checked without it; explicitly distinguished from Supervisor approval (one unchecked item on the list, not something this checklist can self-certify). Updated `DEVELOPMENT_GUIDE.md`'s cross-reference to the exact new heading name.

**4. D-007 / Q-011 reconciliation.** `DECISION_LOG.md` D-007 previously said "the GitHub access limitation is no longer an active obstacle" — true only for the one historical Push event it described, but misleading when read as a general statement, since no persistent/reliable connector access was ever established (documented in detail in `OPEN_QUESTIONS.md` Q-011). Added a correction directly inside D-007 clarifying it is now a historical record of one specific event only, and that the current, accurate, operational status lives exclusively in Q-011. Q-011 itself was not touched/closed. No secret, token, or credential appears anywhere in this change.

**5. Decision-status semantics for D-001–D-005.** Added an explanatory note at the top of `DECISION_LOG.md` distinguishing (a) product/security requirements already imposed by the approved Master Prompt — non-negotiable regardless of any decision's status — from (b) proposed technical mechanisms for satisfying those requirements, which is what "Proposed" actually refers to for D-001 through D-005. None of their statuses were changed to Accepted. D-004 got one additional sentence making explicit that tenant isolation *as a requirement* is already settled (Master Prompt §3) and only the *mechanism* awaits `OPEN_QUESTIONS.md` Q-001.

**6. Repository-wide consistency sweep.** Reviewed all 15 documents. Found and fixed one minor heading-level inconsistency (Q-012 was `###` instead of `##` like every other entry in `OPEN_QUESTIONS.md`). Verified: D-008 Accepted, Q-012 Resolved, D-006 Proposed/independent, Q-001/Q-002/Q-010/Q-011/Q-013 open, no false CI/test-passed claims anywhere, no stale commit references outside the two files meant to carry them, `ROADMAP.md`'s `main`-SHA reference still accurate (verified independently — `main` has not moved), `README.md` accurate, `SUPERVISOR_REVIEW.md` still carries no filled-in verdict, no Phase 0 Approved or Phase 1 started claim anywhere.

**7. Scope discipline.** No backend/frontend code, migration, endpoint, automated test, CI workflow, or deployment configuration was added anywhere in this pass.

Changed: `ARCHITECTURE.md`, `API.md`, `DATABASE.md`, `PROJECT_STATE.md`, `DEVELOPMENT_GUIDE.md`, `DECISION_LOG.md`, `OPEN_QUESTIONS.md`, `CHANGELOG.md` (this entry). `main` untouched. PR #1 not merged. Phase 0 not declared Approved by this entry — only an independent Supervisor may make that call. Phase 1 not started.


### 2026-10-12 — Fourth Supervisor Documentation Correction Pass
`docs:` Resolve the remaining documented inconsistencies found in the independent Phase 0 re-review; all changes remain on the existing PR #1 branch, not `main`.

Changed:
- `DATABASE.md` — aligned the planning model with `ARCHITECTURE.md`: the working conceptual assumption is a direct, indexed, non-null `tenant_id` on `Plan`, `PlanVersion`, and `PlanItem`; explicitly kept Q-001 open and required parent/child tenant consistency safeguards at schema design time.
- `PROJECT_STATE.md` — updated the date; removed the stale claim that the main commit was also the latest content reviewed; recorded the Supervisor's actual read/write test in this session; clarified that cross-session persistence is not yet proven.
- `OPEN_QUESTIONS.md` — updated Q-011 with the Supervisor environment's successful private-repository read/write test and the limitations of that test; Q-011 remains open only for repeatability/persistent operating policy, and historical Claude-environment results remain separate.

Scope and safeguards:
- No application code, migrations, endpoints, automated tests, or infrastructure were added; Phase 0 remains documentation-only.
- Q-001, Q-002, Q-010, and Q-013 were not silently resolved. Q-012 remains Resolved and D-008 remains Accepted.
- No merge was performed; `main` remains unchanged by this correction pass. Formal Supervisor review is recorded in `SUPERVISOR_REVIEW.md` after verification of these corrections.


### 2026-10-12 — Product Owner Decisions for Q-001, Q-002, Q-010
`docs:` Record the Product Owner's explicit acceptance of the recommended tenant-isolation mechanism, controlled MVP boundary, and initial Pilot hosting approach.

- Q-001: shared PostgreSQL with direct `tenant_id`, application authorization, and RLS defense in depth; schema-per-tenant and database-per-tenant were not selected for MVP.
- Q-002: `PROJECT_SCOPE.md` is the controlled MVP boundary, centered on the full educational loop and minimum auditable versioning; real payment gateway, operational Telegram/SMS, native app, AI/planning black box, advanced analytics/risk, and full parent portal remain out of scope.
- Q-010: initial Pilot target is an Iran-based VPS with portable Docker Compose deployment; no provider or plan selected. Secure secrets, private database networking, HTTPS, off-host encrypted backups, and restore tests remain required.
- Updated `OPEN_QUESTIONS.md`, `PROJECT_SCOPE.md`, `ARCHITECTURE.md`, `DATABASE.md`, `SECURITY.md`, `ROADMAP.md`, and `PROJECT_STATE.md` to reflect these decisions.
- No application code, migrations, endpoints, automated tests, or deployment configuration were added. Q-007, Q-011, and Q-013 remain open. Phase 0 closure is still pending, PR #1 remains unmerged, and Phase 1 is not authorized.


### 2026-10-12 — Tenant Ownership and Commit-Tracking Consistency Fix
`docs:` Corrected a newly identified ambiguity between the universal tenant-column rule and the unresolved Q-013 platform-owned `ProgramTemplate`/`ProgramVersion` cases. The cross-cutting rule now applies to tenant-owned rows and explicitly does not decide the representation of platform-owned catalog rows; `ARCHITECTURE.md` carries the matching qualification. Updated `PROJECT_STATE.md` to distinguish `main` from the PR branch and from verified Claude authorship/review evidence. Unchecked the contradiction-free checklist item pending a fresh full-document consistency pass. `Last Updated` was already `2026-10-12` in the current branch and remains current.

No code, migrations, endpoints, automated tests, merge, or Phase 1 work was performed. Q-013 remains open; Phase 0 remains `CONDITIONAL PASS`.

### 2026-10-13 — Align Tenant-Isolation Test Plan with D-009
`docs(test-plan):` Updated `TEST_PLAN.md` after the independent Phase 0 review found that its tenant-isolation checklist had not caught up with accepted decision D-009.

Added mandatory, distinct checks for: runtime DB-role ownership and effective BYPASSRLS privileges; RLS enablement/policies and applicable roles; RLS-only negative tests without application filtering; application-authorization-only tests in a controlled isolated test setup; and integrated tests with both layers enabled. The plan explicitly prohibits weakening production security or making the runtime role privileged just to run tests.

This is a test-plan/documentation change only. No runtime tests, application code, migrations, CI workflows, or deployment settings were created. Q-013 remains open; Phase 0 remains CONDITIONAL PASS; PR #1 remains unmerged and Phase 1 is not authorized.


### 2026-10-13 — Final Phase 0 Documentation Consistency Corrections
`docs:` Corrected six current-state inconsistencies identified by the independent Supervisor's live review of all 15 foundation documents.

- `PRODUCT_REQUIREMENTS.md` — replaced stale wording that left the tenant-isolation mechanism undecided with the accepted D-009/Q-001 mechanism and explicit implementation/testing caveat.
- `PROJECT_SCOPE.md` — removed the stale placeholder/approval-dependency paragraph; the controlled MVP boundary is already decided under D-010, while future technical design work remains.
- `OPEN_QUESTIONS.md` — moved Q-003 (MVP billing depth) to Resolved under D-010. The minimum StudentCredit/CreditTransaction ledger and manual/mock flow are MVP; a real gateway is out of MVP. Q-004 remains open for future provider selection.
- `README.md` — updated the SUPERVISOR_REVIEW.md description to reflect the actual recorded CONDITIONAL PASS review.
- `ROADMAP.md` — clarified that the minimum auditable credit ledger is an MVP deliverable; Phase 21 is for complementary/expanded Billing work, not for postponing the MVP ledger.
- `PROJECT_STATE.md` and `SUPERVISOR_REVIEW.md` — reconciled the open-question summary, marked the full 15-document semantic consistency check complete for this bounded documentation pass, and recorded the current follow-up review. The 2026-10-12 review is retained as historical context and labeled accordingly.


- PR #1 description — updated the live pull-request summary so it no longer incorrectly lists Q-001/Q-002/Q-010 as open, and accurately lists resolved Q-003, still-open questions, the current CONDITIONAL PASS gate, and the no-runtime-implementation verification boundary.
- `PROJECT_STATE.md` — refreshed the current milestone/checklist wording to point to the 2026-10-13 follow-up review; this remains separate from Product Owner closure, PR merge, and Phase 1 authorization.

Verification boundary: documentation-only. No application code, database migrations, API endpoints, executable tests, CI workflows, or deployment configuration were added. No runtime security claim is made. Q-011 remains open; Q-013 remains open; Phase 0 remains CONDITIONAL PASS; PR #1 remains unmerged and Phase 1 is not authorized.


### 2026-10-13 — Resolve Q-013: Tenant-Owned Program Templates Only in MVP
`docs(decision):` Recorded the Product Owner's explicit Option A decision for Q-013 as D-012.

- `OPEN_QUESTIONS.md` marks Q-013 Resolved.
- In MVP, `ProgramTemplate` and `ProgramVersion` are tenant-owned only; each `ProgramVersion` must reference a template from the same Tenant.
- Platform-owned/shared catalog templates and versions are out of MVP and require a separate future decision before implementation.
- `ARCHITECTURE.md`, `DATABASE.md`, `API.md`, `PRODUCT_REQUIREMENTS.md`, `PROJECT_SCOPE.md`, and `SECURITY.md` reflect the decision and its authorization boundary.
- The supervisor follow-up review and PR #1 description are aligned to the current decision and review status.

This is documentation-only. No application code, migrations, endpoints, executable tests, CI, or deployment changes were made. PR #1 remains open and unmerged; Phase 0 remains CONDITIONAL PASS pending post-edit verification and Product Owner closure; Phase 1 is not authorized.


### 2026-10-14 — Phase 0 Follow-up: PR Review Metadata and Phase 1 Boundary
`docs:` Corrected two verified process/documentation ambiguities during the live final review of PR #1.

- PR #1 description now accurately states that a `COMMENTED` GitHub review exists and was submitted by repository owner `nourihamed`; it does not imply a separate review from a distinct Supervisor GitHub account.
- `PROJECT_STATE.md` and `ROADMAP.md` now consistently define Phase 1 as design artifacts and tenant-isolation test contracts only. Application code, database migrations, and infrastructure implementation remain unauthorized in Phase 1 unless the Product Owner explicitly changes and records that scope before work starts.

`SUPERVISOR_REVIEW.md` records the 2026-10-14 live recheck as CONDITIONAL PASS, including the unresolved GitHub `mergeable: false` discrepancy. `PROJECT_STATE.md` now points to that latest review.

No application code, migration, endpoint, executable test, CI workflow, or deployment configuration was added. `main` was not changed; PR #1 remains open and unmerged. Phase 0 closure, merge, and Phase 1 authorization remain separate Product Owner decisions.


### 2026-10-14 — Final Live Recheck and Phase 0 Documentation Gate
`docs(review):` A fresh live read after the latest documentation commits reported PR #1 as `mergeable: true` and the compare as 0 commits behind `main`; the earlier `mergeable: false` result was observed at an earlier HEAD and is superseded for the current checked state. The supervisor review now records **APPROVED for Phase 0 documentation/architecture readiness only**. Product Owner phase closure and PR merge remain separate decisions; Phase 1 remains unauthorized. No runtime implementation or security approval is implied.


### 2026-10-14 — Clarify Gate Approval Versus Phase Closure
`docs:` Clarified in `PROJECT_STATE.md` that the Supervisor's APPROVED status applies to Phase 0 documentation readiness only. Formal Phase 0 closure remains a separate Product Owner decision, and neither status implies PR merge or Phase 1 authorization.


### 2026-10-14 — Mergeability Metadata Recheck
`docs(review):` Subsequent live reads returned both `mergeable: true` and `mergeable: false` across recent PR heads; the latest reviewed value was false. The compare still reports 0 commits behind `main`, but the connector does not expose enough detail to explain the discrepancy. The Supervisor documentation gate remains APPROVED; merging is held until the live GitHub conflict/status view is reconciled. No code or runtime configuration was changed.


### 2026-10-14 — Product Owner Formally Closes Phase 0
`docs:` Record the Product Owner's explicit approval of Phase 0 after the Supervisor's `APPROVED` documentation/architecture gate.

- `PROJECT_STATE.md` — mark Phase 0 formally closed by the Product Owner on 2026-10-14; update the closure checklist and next actions. PR #1 remains open/unmerged and requires a separate merge decision.
- `SUPERVISOR_REVIEW.md` — add a dated record distinguishing Product Owner phase closure from PR merge and Phase 1 authorization.
- Scope remains documentation foundation only. No application code, migrations, executable tests, runtime security verification, or Phase 1 authorization is implied.


### 2026-10-14 — Post-Merge State Reconciliation (PR #1)
`docs:` After the Product Owner explicitly requested merging PR #1, GitHub confirmed that PR #1 was squash-merged into main at d68fde54b4e4c86642b74c3bf1ef20fe18edf12b and closed at 2026-10-14T10:21:09Z.

Changed on the follow-up branch docs/post-merge-state-reconciliation:
- PROJECT_STATE.md — corrected the current milestone, completion checklist, merge commit record, repository status, blockers, and next actions.
- README.md — marked Phase 0 closed, recorded the merge, and aligned the current Supervisor gate summary.
- ROADMAP.md — marked Phase 0 deliverables complete, recorded the merge commit, and aligned the current gate status.
- PRODUCT_REQUIREMENTS.md, SECURITY.md, and TEST_PLAN.md — removed stale “Pending Approval” status labels while explicitly preserving the boundary between approved documentation, unimplemented requirements, and unrun tests.
- SUPERVISOR_REVIEW.md — added a dated post-merge review that separates current state from historical review snapshots.
- PR #1 description — updated after merge to show the final closed/merged state, merge commit, unresolved questions, and runtime-verification boundary.

Verification boundary: PR #1 changed 15 documentation files only. GitHub returned no workflow runs or commit statuses for its head. No application code, database migrations, endpoints, executable tests, CI workflows, deployment configuration, or runtime security proof were added. Phase 1 remains not started and not authorized. These corrections are on a separate follow-up branch and have not yet been merged into main.


## 2026-10-23 — Product Owner selects stronger-architecture requirement (D-019)
- Recorded Q-021 option B: current Option C residual risks (K-L-N and K-O) are not accepted as sufficient for Phase 1 approval.
- Added Q-022 for explicit selection of a revised architecture after independent comparison.
- Added `docs/phase1/STRONGER_TENANT_ISOLATION_OPTIONS.md` (design study only; no final topology selected).
- Updated `DECISION_LOG.md`, `OPEN_QUESTIONS.md`, `PROJECT_STATE.md`, `ROADMAP.md`, and `SUPERVISOR_REVIEW.md`.
- No code, migrations, infrastructure, runtime tests, Phase 2 work, or real-data authorization was created or implied.


## 2026-10-23 — Product Owner selects Alt-5 and Q-022 documents aligned (D-020)
- Recorded explicit Q-022 option A selection in DECISION_LOG.md D-020 and resolved Q-022 in OPEN_QUESTIONS.md.
- Replaced the normative Phase 1 tenant-isolation design with an Alt-5 hybrid isolation-cell design; Alt-4 remains the security reference.
- Replaced AUTHORIZATION_CONTRACT.md with trusted tenant-to-cell routing and cell-scoped authorization rules.
- Archived the 123-contract pre-Q-022 test catalog and replaced the active catalog with 46 Alt-5-specific contracts plus a mapping of historical IDs.
- Tightened within-cell isolation: each tenant has a separate database and tenant-specific runtime credential within its cell; shared cell/host/root compromise remains a distinct residual.
- Aligned PROJECT_STATE.md, ROADMAP.md, PHASE1_REPORT.md, SUPERVISOR_REVIEW.md and the Q-022 review record.
- No application code, migration, infrastructure, runtime test, Phase 2 work, or real-data pilot was created or authorized. Active tests remain NOT-RUN; capacity and cost are unmeasured.

### 2026-10-23 — Hosting compatibility review for Alt-5 (Q-023)
`docs:` Reconciled D-011's hosting objective with D-020's cell requirements without silently selecting a new topology. Added `docs/phase1/HOSTING_CELL_COMPATIBILITY_REVIEW.md` comparing a single shared VPS, separate host/VM per cell, separate cloud accounts/projects per cell, and Alt-4 dedicated tenant isolation. Recorded Q-023 as OPEN for Product Owner decision; recommendation is separate host/VM and network boundary per cell for further cost/capacity evaluation, with account/project separation as a stronger alternative.

D-017's prior connection estimate is explicitly treated as historical estimate, not Alt-5 capacity evidence; per-cell connection budgets must be recalculated from the actual worker/pool topology. No vendor, price, capacity measurement, implementation, infrastructure, or executable test is claimed. PR #3 remains open/unmerged; Phase 1 NOT READY; Phase 2 and real-data use remain prohibited.

### 2026-10-23 — Local-first development direction (D-021)
Product Owner selected local laptop development now, with server deployment to be evaluated when the product reaches an agreed demonstrable stage. Added `docs/phase1/LOCAL_DEVELOPMENT_AND_LATER_DEPLOYMENT.md`; recorded D-021; clarified Q-023 remains open for the eventual hosted topology. Local development is to use synthetic data and local-only services, and does not prove Alt-5 isolation or waive phase gates. Phase 1 remains NOT READY, Phase 2 remains unauthorized pending Phase 1 approval, and real student data remains prohibited. No code, infrastructure or executable tests were created by this documentation update.

## 2026-10-23 — Q-023 deferral (D-022)
- Recorded the Product Owner's decision to defer the final hosted topology/provider until hosted deployment planning while retaining local-first development under D-021.
- Independent gate impact recorded: Q-023 remains a Phase 1 blocker for the unresolved architecture-level host/network/admin trust boundary. No security condition was removed; D-020 and D-014 remain unchanged.
- Documentation-only update. No code, infrastructure, migrations or executable tests added or run.

## 2026-10-23 — Production Level 3 / independent Level 4 backup target (D-023)
- Recorded the Product Owner's explicit security-target decision: Level 3 infrastructure/administrative independence for production cells, with Level 4 independent control of critical backups and recovery.
- Defined the target in project terms, including separate cell host/network boundaries, scoped credentials, independent backup administration/keys, and explicit residual risk from provider/global control-plane compromise.
- Q-023 remains OPEN pending evidence that a real hosting candidate can meet the target and independent review of the architecture-level trust boundary. Vendor, pricing and measured capacity are not claimed as selected or validated.
- D-020 Alt-5 and D-014's real-student-data prohibition remain unchanged. Phase 1 remains NOT READY; Phase 2 remains unauthorized. Documentation-only; no code, infrastructure, migrations or executable tests added or run.

## 2026-10-23 — Independent Phase 1 correction and consistency pass (D-023)

- Updated the normative Alt-5 design to explicitly define D-023 Level 3 cell infrastructure/administrative independence and Level 4 independent administration of critical backups, keys, deletion/retention controls and recovery.
- Updated the authorization contract and active TI-CELL-11 acceptance contract to require independent backup administration evidence; a separate bucket/service name alone is not accepted as proof.
- Reconciled SECURITY.md and TEST_PLAN.md so the earlier D-009 shared-database mechanism is not confused with the active Alt-5 architecture; linked D-023 to the affected artifacts.
- Updated PROJECT_STATE.md, PHASE1_REPORT.md and ROADMAP.md with the current active contract count and review boundary.
- Provider comparison/selection remains deferred until hosted deployment planning per Product Owner direction. Q-023 remains OPEN and Phase 1 gate-blocking under D-023; no provider, price, capacity or runtime security result is claimed.
- Active Alt-5 test catalog remains 46 specifications, 0 implemented, 0 executed, 0 passing. No application code, migration, infrastructure or executable test was created/run. PR #3 remains open/unmerged; Phase 1 NOT READY; Phase 2 unauthorized; real student data prohibited.

## 2026-10-23 — Second Phase 1 consistency sweep

- Reconciled ARCHITECTURE.md, DATABASE.md, PRODUCT_REQUIREMENTS.md and PROJECT_SCOPE.md so the historical D-009/Q-001 shared-database mechanism is not misrepresented as the active Alt-5 topology.
- Replaced the pre-pilot single-VM recommendation with provider-neutral D-020/D-023 acceptance requirements; aligned the target-environment test plan, emergency-stop restore steps and retention draft with independent critical-backup administration and lifecycle preservation.
- Recounted the active catalog: 46 unique IDs, 0 implemented, 0 executed, 0 passing. A consistency scan passed for the active D-020/D-023 references and restore step ordering.
- Provider comparison remains deferred by the Product Owner; Q-023 remains OPEN and Phase 1 NOT READY under the current D-023 gate. PR #3 remains open/unmerged. The connector summary reported mergeable: false, while a fresh direct GitHub API read reported mergeable: true / clean; no merge, code, migration, infrastructure or executable test was performed.

### 2026-10-24 — Phase 1 design gate finalized; hosting validation deferred (D-024)

Recorded D-024 to separate the provider-neutral Phase 1 design gate from provider-specific hosted-deployment validation, following the Product Owner's direction to compare hosting providers later. Reclassified Q-023 as OPEN and mandatory before hosted deployment, but not a blocker to the documentation-only Phase 1 design gate. Updated the active design, authorization contract, test-contract gate wording, project state, phase report, roadmap and hosting compatibility review.

Independent review outcome: Phase 1 design/documentation gate APPROVED only. Active Alt-5 catalog remains 46 specifications, 0 implemented, 0 executed, 0 passing. PR #3 remains open/unmerged at the time of this entry; Phase 2 remains unauthorized; D-014's real-student-data prohibition remains in force. No provider, cost, capacity, implementation, infrastructure or runtime test is claimed selected, measured, created or passed.

### 2026-10-24 — Post-merge state reconciliation

Updated current-state, roadmap, phase report and supervisor review after PR #3 was squash-merged into main at b9c7a7f1f67ae7c11058c36d41beb3a32f76f0fa. Phase 1 remains approved for design/documentation only; Q-023 remains a hard pre-hosting gate, Phase 2 is not authorized, and D-014 continues to prohibit real student data until all pilot gates and explicit written Product Owner approval are complete.

### 2026-10-24 — Post-merge independent consistency recheck

- Corrected the stale Phase 0 status block in `ROADMAP.md` so it is explicitly historical and cannot contradict the current Phase 1 gate.
- Marked the pre-D-024 Q-019 Phase 1-blocker wording in `OPEN_QUESTIONS.md` as historical/superseded; Q-023 remains the actual pre-hosting gate.
- Aligned `SECURITY.md` with D-020/Alt-5: application/object authorization plus tenant-specific database/credentials and cell host/network boundaries are the required layers; RLS is supplemental if implemented, not the primary cell boundary.
- Added active contract `TI-CELL-23` for the K-L-N all-tenant-credentials-compromised tabletop/containment scenario. It records the catastrophic residual and requires evidence for detection, bulk revocation/rotation, session termination, containment and recovery without claiming topology guarantees prevention.
- Recounted the active catalog at 47 unique contracts; 0 implemented, 0 executed, 0 passing. No runtime code, migration, infrastructure or executable test was created or run.


## 2026-10-24 — Final Phase 1 status-consistency follow-up (D-024)

`docs(review):` Corrected stale status language found during the post-merge supervisor recheck so the repository's visible current state matches D-024 without rewriting historical decisions.

- `README.md` now reports Phase 1 APPROVED for design/documentation only, PR #3 merged, and Phase 2 / hosting / real-data use still gated.
- `PROJECT_STATE.md` labels the older pending-review snapshot and subsequent legacy phase notes as historical; the top current-state summary remains authoritative.
- `OPEN_QUESTIONS.md` Q-021 and `DECISION_LOG.md` D-022/D-023 label their at-the-time NOT READY consequences as historical and superseded by D-024 for the design-only gate.
- `SUPERVISOR_REVIEW.md` records this follow-up finding and correction.

Verification boundary: documentation-only. Alt-5 acceptance catalog remains 47 specifications, 0 implemented, 0 executed, 0 passing. Q-023 remains a mandatory pre-hosting deployment gate; D-014's real-student-data prohibition remains unchanged. No application code, migrations, infrastructure, executable tests, Phase 2 work, or hosting approval was added or implied.

## 2026-11-09 — Phase 2 Workspace / Control Plane reconciliation (PR #12 branch; unmerged)

Added Workspace DB design and schema skeleton, transfer workflow contract, API/authorization contract, HMAC rotation protocol, idempotent transfer-command draft, and updated Control Plane schema/function/state-machine/test drafts. Corrected the decision crosswalk and added current-state authority notes to canonical product/architecture/security documents.

This work remains documentation and draft-schema only. Revised SQL/race tests have NOT RUN against the current HEAD. Earlier Control Plane test counts are superseded. No runtime implementation, production migration, merge, Phase 3 authorization, or real-data permission is claimed. Phase 2 Gate remains NOT READY; D-014 remains in force.


## 2026-11-09 — PostgreSQL 16 draft schema verification

Added a PostgreSQL 16 GitHub Actions workflow. Latest successful run #53 executed at branch commit `3c50f0be27ebad6c159d20d2447b763868e6bc86` and passed 22 Control Plane PASS notices (including a role-catalog notice covering eight privilege sub-checks), 1 concurrent global-identity race and 13 Workspace schema PASS notices. Earlier failed runs exposed test-fixture defects and a missing sequence grant to the non-login function owner; these were corrected before run #35.

This evidence applies only to the synthetic SQL/schema cases in the workflow. Production service-role binding, trusted approval identity service, cross-Workspace DB authorization, transfer freeze/drain and crash recovery, outbox/inbox delivery, activation+credit atomicity, full capacity concurrency, backup/restore and HA tests remain NOT RUN. Phase 2 Gate remains NOT READY; D-014 remains in force.


### 2026-11-09 — Phase 2 claim admission, Workspace activation and role verification
`feat:` Added a Control Plane initial identity-claim admission draft (cp_07) with a database maintenance gate, exact active/retiring HMAC alias coverage, global mobile+grade uniqueness, encrypted contact-index insertion, atomic ownership/claim creation and idempotency. Added dedicated identity-admission executor scope and regression/race tests.

`feat:` Added Workspace atomic activation draft: enrollment activation, Student Credit debit (unit_code CRD), active-student capacity reservation and minimal audit event occur in one transaction. Added wallet-row serialization/negative-balance guard, append-only command log and idempotent replay. Added per-Workspace PostgreSQL role naming from canonical Workspace UUID, database CONNECT isolation, worker/exporter limits and role catalog tests.

`test:` GitHub Actions run #148 passed on PostgreSQL 16 at SQL/test tree SHA e97056b44ebfdbfce5344a9c524ba8af1e72055b. It covered Control Plane transfer/rotation/claim admission, concurrent global identity and claim-admission races, Workspace schema/activation/credit/capacity/audit, concurrent activation and two-Workspace role/CONNECT assertions. This is synthetic draft-SQL evidence only.

`docs/security:` Updated Control Plane/Workspace role contracts, HMAC rotation protocol, Workspace database design, canonical architecture/database/API/security overrides, project state, roadmap, test plan and supervisor review. Phase 2 remains NOT READY; PR #12 remains Draft/Open/Unmerged; Phase 3 and real data remain prohibited under D-014.



## 2026-11-09 — Phase 2 identity, approval and transfer contracts
- Added `docs/phase2/control_plane/CONTACT_CHANGE_REVERIFICATION_CONTRACT.md` for secure mobile contact change, proof binding, all-live-key alias coverage, idempotency and audit.
- Added `docs/phase2/control_plane/TRANSFER_APPROVAL_IDENTITY_AUTHORITY_CONTRACT.md` for verified guardian, prior counselor fee-receipt and destination acceptance authorities, signed one-time assertions, revocation and re-approval.
- Added `docs/phase2/transfer/CROSS_WORKSPACE_TRANSFER_SAGA_CONTRACT.md` for durable outbox/inbox, source freeze/drain, destination staging, cutover and forward recovery.
- Bound the contracts into the Control Plane README, transfer workflow contract, API authorization contract, TEST_PLAN and Supervisor Review.
- Identified approval-schema reconciliation: current unique (case_id, approval_kind) plus mutable revoked_at cannot retain a revoked approval and replacement as separate immutable events.
- Documentation/design only. No proof verifier, API, Saga worker, contact-change SQL, approval event schema or new executable tests were implemented. Phase 2 remains NOT READY; D-014 synthetic-only rule unchanged.


## 2026-11-09 — Phase 2 domain, legal-policy and operations review
- Added `docs/phase2/workspace/WORKSPACE_DOMAIN_SCHEMA_REVIEW.md` with HIGH/MEDIUM findings from actual Workspace SQL schema.
- Added `docs/phase2/api/PARENT_GUARDIAN_AUTHORITY_MATRIX_Q007.md`; Q-007 remains open pending qualified Iran legal review and Product Owner approval.
- Added `docs/phase2/operations/DATA_RETENTION_IMPLEMENTATION_CONTRACT.md` for category-based versioned retention and legal-hold/disposition behavior without unapproved numeric durations.
- Added `docs/phase2/operations/OPERATIONAL_RESILIENCE_BACKUP_RECOVERY_CONTRACT.md` for failover, independent backup, restore, pool isolation and capacity acceptance criteria.
- Updated OPEN_QUESTIONS, PROJECT_STATE, ROADMAP, SECURITY and TEST_PLAN references. Documentation only; no runtime or operational tests are claimed.


## 2026-11-09 — Workspace capacity race coverage
- Added a PostgreSQL 16 CI race test for two different student enrollments competing for the final active-student capacity slot.
- The fixture intentionally provides sufficient Student Credit so the losing transaction exercises capacity serialization, not wallet insufficiency.
- Test is wired into the Phase 2 workflow; execution status awaits fresh CI on the latest branch head.


## 2026-11-09 — Phase 2 exit criteria baseline
- Added `docs/phase2/PHASE2_EXIT_CRITERIA.md` to distinguish Phase 2 design/schema completion from later runtime/production gates and centralize evidence, blockers, unresolved PO decisions and gate rules.


## 2026-11-09 — Phase 2 open decision register
- Added `docs/phase2/PHASE2_OPEN_DECISIONS.md` to consolidate remaining Product Owner/legal/security/operations decisions and technical closure work without assigning unapproved values.


## 2026-11-09 — Workspace membership role source-of-truth correction
- Removed redundant scalar `workspace_memberships.role_key`; `membership_roles` is the sole role-assignment relation in the draft schema.
- Updated Workspace schema/activation/race fixtures and added `WS-ROLE-SOURCE-01` schema assertion.
- Role grant/revocation event audit and direct-DML privilege tests remain open; fresh CI pending.


## 2026-11-09 — Educational domain contracts
- Added assessment domain contract for immutable definitions/attempts, response-count integrity, scoring-policy snapshots, custom error analysis and per-subject exam results.
- Added deterministic planning domain contract for normalized schedule/availability inputs, explicit PlanItems, reproducibility and explainability.
- Added curriculum domain contract for Grade → Subject → Book/Edition → Chapter → Topic → Subtopic, ownership, versioning and mastery evidence.
- Linked all three contracts from Workspace design, exit criteria, Project State, Roadmap, Test Plan and Supervisor Review. SQL reconciliation and tests remain open.


## 2026-11-09 — Activity, credit and capacity lifecycle contracts
- Added Activity/Class/Assignment domain contract with recurrence, participation, attendance and provenance rules.
- Added Student Credit commercial lifecycle contract separating CRD from fiat billing and specifying verified payment, grants, refunds and reconciliation.
- Added Capacity lifecycle contract for multi-dimensional reservations, activation/archive/reactivation and transfer coordination.
- Linked contracts into Workspace design, Phase 2 exit criteria, Project State, Roadmap, Test Plan and Supervisor Review.


## 2026-11-09 — Workspace authorization-table privilege hardening
- Removed runtime write grants from Workspace membership, role, permission, branch, counselor-assignment and guardian relationship/permission tables; runtime is SELECT-only on these authorization sources.
- Made the activation function owner read-only on authorization tables and narrowed its activation grants to column-level state/counter changes and lock-only columns.
- Added immutable wallet identity trigger/test and expanded per-Workspace role privilege assertions.
- Dedicated audited authorization-management functions and append-only grant/revocation event history remain open; latest changes await fresh CI.


## 2026-11-10 — Product Owner approved Workspace role grantability matrix
- Recorded the accepted MVP role matrix in `docs/phase2/workspace/PO_DECISION_ROLE_GRANTABILITY_MATRIX_2026-11-10.md`.
- Organization Manager may invite, activate and revoke counselor memberships only within its own Workspace; Counselor cannot delegate; Branch Manager is operational-only within assigned Branch; other staff cannot delegate; Platform Admin is limited to narrow Governance authority, including Organization Manager appointment approval, without general Workspace write or student-data access.
- Added deny-by-default, no-self-grant, no-privilege-escalation, strict scope, audit and revocation-freshness invariants to the trusted governance contract and linked the decision from Phase 2 exit tracking.
- This closes the Product Owner policy decision only. Trusted verifier/adapter, proof receipt, API enforcement and executable acceptance tests remain unimplemented; Q-007 remains open; Phase 2 remains NOT READY; D-014 synthetic-only remains in force.

### Phase 2 — Governance proof receipts and verifier boundary (Issue #13, synthetic draft)
- Added `docs/phase2/workspace/receipts/`: receipt table with binding and single-use controls, verifier and adapter identities with narrow grants, atomic consume-and-apply command, verifier interface contract (production fail-closed; test double only), executable tests and concurrency checks.
- Fixed NULL-unsafe payload validation in the governance event draft (six comparisons, COALESCE).
- Not production implementation, not a migration, not a cryptographic verification, not an approval. Phase 2 gate: NOT READY pending independent Supervisor review.

### Issue #13 corrective patch (2026-11-11)
- Retry of a consumed receipt returns the original result after expiry when the full binding matches; unconsumed expired receipts fail closed.
- Receipt state machine made terminal for consumed and revoked; NULL-safe metadata checks; consumption event reference enforced by foreign key.
- Canonical payload contract `receipt-canon-v1` added (contract, draft SQL, test-only reference, vectors).
- Verifier test double checks the canonicalization version and the payload digest (not a signature check).
- Workflow updated for the canonical contract and the new suites. Not production implementation; not an approval.

### Issue #13 H-03 correction (head 70e37d7)
- Receipt INSERT accepts only initially registered receipts with no consumption metadata; consumed and revoked cannot be inserted directly.
- registered→consumed only through the consume command for that receipt; direct owner-level UPDATE refused.
- Revocation recorded in an append-only audit (revoked_by, revoked_at). No revocation policy or service introduced.
- Consumed retry checks the referenced event against the receipt binding; inconsistent events are refused.
- Regression suite receipt_50_h03_tests.sql (12 PASS). CI success on 70e37d7 is execution evidence only, not production approval.

### H-03 corrective — privilege-backed consume boundary (Supervisor finding)
- Replaced the session-setting authorisation (receipt.consume_active) with a transaction-scoped consume grant row, writable only by a dedicated consume definer role that owns the consume function.
- Trigger governance_proof_receipts_a_consume_grant refuses registered→consumed without a grant from the same transaction, including for identities that hold UPDATE.
- Added negative tests with setting-based attempts, grant forgery refusals for governance owner, verifier_rt and adapter, a catalog privilege check, and a legitimate consume that releases its grant.
- Revocation unchanged and still deferred; M-05 and M-06 remain open residual findings.

### Phase 2 exit findings — implementation batch (2026-11-13)
- WS-DOM-01: immutable published test definition versions, attempt/response reconciliation at submission, immutable submitted attempts, idempotent `submit_test_attempt()`, custom error reason with description.
- WS-DOM-03: append-only guardian link and permission events; projection changes require their event in the same transaction; effective-permission view.
- Control Plane: transfer approvals are immutable events; revocation is a separate append-only event; replacement approvals keep history; one current approval per kind; revocation and switch serialise on the transfer case.
- Drafts and tests only. No scoring formula, no guardian legal matrix, no approval-recording command, no production migration. Not an approval.

### Phase 2 exit findings — second batch (2026-11-13)
- Fixed: Control Plane commands failed under their own executor roles because deferred alias-coverage triggers ran at commit as the caller. Each command now runs them in its own security context. New suite calls every command as its real executor.
- Added: contact-change draft (one-time proof, atomic command, audit, outbox, separate role family) with tests and a race test.
- Added: Workspace archive command with atomic capacity release, idempotency and a counter-reconciliation view, with tests under the runtime role.
- Drafts and synthetic data only. No credit policy on archive, no reactivation, no production verifier. Not an approval.
