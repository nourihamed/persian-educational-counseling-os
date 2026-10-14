# CHANGELOG.md

Format: Keep it simple — date, phase, summary. Prefixes per Master Prompt §62 (`feat:`, `fix:`, `refactor:`, `test:`, `docs:`, `security:`, `perf:`, `chore:`).

## [Unreleased]

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

No application code, migration, endpoint, executable test, CI workflow, or deployment configuration was added. `main` was not changed; PR #1 remains open and unmerged. Phase 0 closure, merge, and Phase 1 authorization remain separate Product Owner decisions.
