# PROJECT_STATE.md
## Operational Memory — Single Source of Truth for "Where are we now"

Last Updated: 2026-10-11

---

### Current Phase
**PHASE 0 — Product & Business Model Foundation — IN PROGRESS (Pending Supervisor Review)**

Authorized by: project owner.
Scope authorized: documentation foundation only. Explicitly NOT authorized: backend code, frontend code, database migrations, authentication, billing implementation, Telegram, SMS, AI, Planning Engine, or any other application feature.

**Phase 0 is NOT marked APPROVED or DONE.** Final status is set only by the Supervisor Review process (see `SUPERVISOR_REVIEW.md`), not by this file.

### Current Milestone
Open Pull Request **#1** (branch `docs/phase0-correction-pass-3` → `main`), carrying multiple successive rounds of Supervisor-requested documentation corrections (see `CHANGELOG.md` for the dated, itemized list of every round), is awaiting independent Supervisor re-review before merge. No milestone work is pending creation of the PR — it already exists and has been updated in place across every round so far.

### Phase 0 Documentation-Readiness Checklist
This is the checklist `DEVELOPMENT_GUIDE.md` refers to as Phase 0's Definition of Done. **Completing every item below means the documentation is ready for review — it is explicitly NOT the same as independent Supervisor approval, which is a separate, not-yet-occurred event tracked in `SUPERVISOR_REVIEW.md`.** Each checked item states the evidence for it; nothing is checked without one.

- [x] All 15 foundation documents present in the repository (14 core + `SUPERVISOR_REVIEW.md`) — verified by repeated `git`/GitHub API file listings across correction rounds (see `CHANGELOG.md`).
- [x] No internal contradiction currently known to Claude across the 15 documents — true as of the most recent consistency pass recorded in `CHANGELOG.md`; this is a claim about what has been checked and found resolved so far, not a guarantee that no issue will ever be found (several real contradictions *were* found and fixed across prior rounds — see `CHANGELOG.md` for each).
- [x] No application code, database migration, API endpoint, or automated test exists anywhere in the repository — verified by directory listing (`backend/frontend/tests/scripts/deployment` contain only `.gitkeep`) each round.
- [x] All documentation changes are on branch `docs/phase0-correction-pass-3`, attached to open Pull Request #1 — not pushed directly to `main` — verified via GitHub API each round.
- [ ] Independent Supervisor Review recorded in `SUPERVISOR_REVIEW.md` with an explicit Status (`NOT READY` / `CONDITIONAL PASS` / `APPROVED`) — **not done.** This is the one item that is not Claude's to check off.
- [ ] Explicit Product Owner confirmation that Phase 0 documentation is ready to close — **not done**, distinct from individual Q-### resolutions (e.g., Q-012 being Resolved answers one question; it is not a statement that Phase 0 as a whole is ready).
- [ ] PR #1 merged into `main` — **deliberately not done**; merging is withheld pending the two items above.

### Overall Progress
Documentation foundation: present on `main` (commit `994d4529c20c4a330bd843bd3ca1a7c9ed1f75ec`) and being further corrected on a separate branch (see below) pending review/merge.
Implementation: 0% (by design — no application code exists).

### Three distinct things this file tracks separately (do not conflate them)
1. **Latest commit actually in the GitHub repository (`main`)** — directly verified by Claude just before this update: `994d4529c20c4a330bd843bd3ca1a7c9ed1f75ec` ("docs: Phase 0 correction pass — align docs with actual repo state, add SUPERVISOR_REVIEW.md placeholder"). This is a fact about the repository, not a judgment about its quality.
2. **Latest commit whose document content has been read/authored by Claude** — the same commit above; its content was written in this working process. This is not an independent review.
3. **Supervisor final approval** — NOT given. No Supervisor Review has been recorded in `SUPERVISOR_REVIEW.md`. Nothing in this repository should be read as Supervisor-approved.

### Repository Status (GitHub)
- Repository: `https://github.com/nourihamed/persian-educational-counseling-os` — currently **private**. Visibility was toggled public→private during this session by the project owner; treat current visibility as private unless re-verified.
- This correction pass is being made on branch `docs/phase0-correction-pass-3`, not directly on `main`, and is attached to open Pull Request **#1**, pending review (see Next Actions).
- A detailed, tested-only, environment-separated breakdown of GitHub access is maintained in `OPEN_QUESTIONS.md` Q-011. Summary only (see that file for the full breakdown and caveats):
  - **Claude's environment, this session, via the connected OAuth-based GitHub connector ("Claude" App):** Read tested — succeeded once while the repository was temporarily public, failed (`404`) while private. Write tested — failed once while public (`403 Resource not accessible by integration`); not re-tested while private.
  - **Claude's environment, this session, via a manually supplied, short-lived Personal Access Token pasted into the conversation by the project owner:** Read tested — succeeded (repeatedly). Write tested — succeeded (two pushes to `main`, one push to this branch, one Pull Request created via the GitHub REST API). The project owner was asked to revoke this token after use each time it was supplied.
  - **The Supervisor's own environment/GitHub tooling:** Not tested, not observed, and not inferred by Claude in this session. Nothing here implies the Supervisor's access works or does not work — that is a separate, untested system. Do not read Claude's connector results as evidence about the Supervisor's tooling, or vice versa.
- All commits currently on `main` (`bd24cf8d...`, `994d4529...`) and every commit made on this branch so far were made via the manual-token path described above, not via the connector. See the "Last Verified Commit" section below for the full, up-to-date branch commit history — do not rely on a specific SHA named here as "the latest branch commit," since that claim goes stale on every new commit (see the structural note below).

### Completed
- [x] 14 foundation documents authored (PRODUCT_REQUIREMENTS, PROJECT_SCOPE, ARCHITECTURE, DATABASE, API, ROADMAP, PROJECT_STATE, DECISION_LOG, OPEN_QUESTIONS, TEST_PLAN, SECURITY, CHANGELOG, DEVELOPMENT_GUIDE, README)
- [x] `SUPERVISOR_REVIEW.md` placeholder added (15th document)
- [x] Two commits landed on `main` via manual token-based push: `bd24cf8d...` (initial foundation) and `994d4529...` (first correction pass)
- [x] Internal consistency review across documents (naming collision found and recorded: "Plan" — see `DECISION_LOG.md` D-006)
- [x] A second internal consistency issue found and resolved: `PROJECT_SCOPE.md` contained two self-contradictory statements about whether Program Template/Student Plan versioning exists in MVP at all or is deferred entirely to Phase 15, while `ARCHITECTURE.md`/`DATABASE.md` described versioning as a standing architectural principle with no phase qualifier, and `ROADMAP.md` only mentioned "Versioning" under Phase 15. Resolved by proposing a documented MVP Versioning Policy (`DECISION_LOG.md` D-008: minimum viable, auditable versioning is in MVP; only advanced version-management tooling is deferred to Phase 15+) and updating `PROJECT_SCOPE.md`, `ARCHITECTURE.md`, `DATABASE.md`, `ROADMAP.md`, `API.md`, `SECURITY.md`, `TEST_PLAN.md`, `PRODUCT_REQUIREMENTS.md` to be internally consistent with that proposal. **D-008 was initially Proposed and is now Accepted by explicit Product Owner confirmation on 2026-10-10** — see `OPEN_QUESTIONS.md` Resolved / Closed, Q-012.
- [x] Confirmed no production feature implemented in any commit so far

### In Progress
- **Pull Request #1 is open** (`docs/phase0-correction-pass-3` → `main`, not merged) and awaiting independent Supervisor re-review. It is not "being opened" — it already exists; this update is one more commit pushed to the same branch, added to the same open PR. See `CHANGELOG.md` for the exact count and content of every round.
- This round's work: resolved a Supervisor-identified contradiction about Program Template/Student Plan versioning across `PROJECT_SCOPE.md`, `ARCHITECTURE.md`, `DATABASE.md`, `ROADMAP.md`, `API.md`, `SECURITY.md`, `TEST_PLAN.md`, `PRODUCT_REQUIREMENTS.md`, `DECISION_LOG.md` (D-008, now Accepted by explicit Product Owner confirmation), and `OPEN_QUESTIONS.md` (new Q-012). See "Completed" above for what the contradiction was and how it was resolved.
- No other work is in progress. `main` has not been touched by the documentation correction work on this branch.

### Blocked
- **PR #1 should not be merged yet**, per the latest Supervisor review round's explicit recommendation. This is a recommendation to hold, not a technical block — but it is treated as binding until a Supervisor explicitly says otherwise.
- Phase 0 final sign-off is blocked on **Supervisor Review**, not yet performed. See `SUPERVISOR_REVIEW.md` (placeholder only).
- Reliable, persistent repository access (read and write) via a proper connector/App installation is still not established — current access depends on manually supplied, temporary tokens. This is an operational risk for future phases, not just a Phase 0 cosmetic issue.
- Phase 1 (Architecture & Multi-Tenancy deep design + implementation) is explicitly **not started and not authorized**. It cannot start until: (a) a Supervisor Review of Phase 0 is actually recorded in `SUPERVISOR_REVIEW.md`, and (b) the project owner answers Q-001 (tenant isolation mechanism), confirms or amends Q-002 (MVP boundary), and answers Q-010 (hosting target). Q-012 (MVP Versioning Policy, D-008) has been answered and closed.

### Known Bugs
— None (no application code exists)

### Failed Tests
— None (no tests exist yet; Phase 0 is documentation-only)

### Open Questions
See `OPEN_QUESTIONS.md` for full detail. The following remain open: **Q-001** (tenant isolation mechanism), **Q-002** (MVP boundary), **Q-003** (depth of Billing in MVP — real Payment Gateway vs. Mock-only), **Q-004** (which Iranian payment gateway), **Q-005** (Telegram Bot setup), **Q-006** (SMS provider), **Q-007** (Parent default access level), **Q-008** (default calendar/timezone handling), **Q-009** (initial Risk Engine sophistication), and **Q-010** (hosting/deployment target). **Q-011** (GitHub repository access) remains open/qualified, not resolved. **Q-013** (ownership/authorization model for platform-owned `ProgramTemplate` **and**, as a distinct part, platform-owned-template-sourced `ProgramVersion` — see `OPEN_QUESTIONS.md` Q-013 for the two-part breakdown) remains open, low priority, not blocking any current phase. **Q-012** (MVP Versioning Policy, D-008) is resolved and recorded in the Resolved / Closed section of `OPEN_QUESTIONS.md`.

### Last Verified Commit

**Live source of truth — read this first:** repeatedly re-embedding a "complete" branch commit list in this file has gone stale multiple times on this long-running branch, because the list is necessarily one commit behind the moment it is written (see structural note below). This section no longer attempts to maintain that list. Instead:
- **For the current branch HEAD, right now:** check **PR #1** directly — `https://github.com/nourihamed/persian-educational-counseling-os/pull/1` — or run `git log -1` against the real repository. Neither this file nor any other document in this repository is the authoritative source for "what is the current HEAD"; GitHub is.
- **For the complete, per-commit history of what changed and when:** see `CHANGELOG.md`. Unlike this section, `CHANGELOG.md` is append-only and dated — each entry describes a commit that has already happened by the time it's written, so it does not have this section's self-referential staleness problem.
- `main` (`https://github.com/.../tree/main`) and this correction branch (`docs/phase0-correction-pass-3`, backing PR #1) are **two separate refs**. Edits to the branch never affect `main` unless and until PR #1 is merged — which has not happened.

**Last independently verified snapshot** (a historical fact about one specific point in time — not a claim about the current state; it goes stale the moment any new commit lands on either ref, exactly like the list it replaces would have, but it does not pretend otherwise):
- **Verified:** at the start of this editing session (immediately before this round's edits), directly against the real repository via `git log`, `git ls-remote`, `git rev-list --count` (both directions), and `git merge-base --is-ancestor`.
- `main` HEAD at that moment: `994d4529c20c4a330bd843bd3ca1a7c9ed1f75ec`.
- This branch's HEAD at that moment: `119b18dacd099ade26c349b4d6bf4d7cf12f058f`.
- Branch-vs-`main` relationship at that moment: **18 commits ahead, 0 behind** — `main` a clean ancestor of the branch, no divergence.
- **This commit's own SHA is not recorded here and will not be**, for the structural reason below — check GitHub for the actual current value.

**Structural note — why no SHA for "this commit" ever appears here:** this file is part of every commit that edits it, so it can never truthfully state "the current HEAD is `<SHA>`" while being written — the SHA depends on this file's final content, which doesn't exist as a hash until after the commit is made. Any attempt to name it would be a guess presented as a fact.

**What is and isn't established by any of the above:** a commit's existence on a ref (verified directly, as above) is a fact Claude can check. A document's content having been edited and reviewed in this session is Claude's own work, not independent review. **Independent Supervisor approval of Phase 0 is a separate, third thing that has not occurred and is recorded nowhere as having occurred** — see `SUPERVISOR_REVIEW.md`. None of these three substitutes for either of the others.

### Last Test Result
— N/A (Phase 0 is documentation-only; `TEST_PLAN.md` defines future test strategy, nothing to run yet)

### Next Actions
1. **Pull Request #1 (`docs/phase0-correction-pass-3` → `main`) already exists and is open, carrying several rounds of Supervisor-requested documentation corrections so far (see `CHANGELOG.md` for the full, dated list).** It has not been merged. Current explicit recommendation from the latest Supervisor review round: **do not merge PR #1 yet** — further independent re-review is expected before any merge decision. The next action here is independent Supervisor re-review of the latest commit on this branch, not PR creation (already done) and not a merge decision (not authorized).
2. Project owner/Supervisor establishes a reliable, persistent repository connection (proper GitHub App installation scoped to this repo) so future work doesn't depend on manually pasted, temporary tokens — see `OPEN_QUESTIONS.md` Q-011.
3. Project owner/Supervisor performs and records an actual Phase 0 review in `SUPERVISOR_REVIEW.md`.
4. Project owner answers Q-001 (tenant isolation mechanism), confirms or amends Q-002 (MVP boundary), and answers Q-010 (hosting target). Q-012 (MVP Versioning Policy, `DECISION_LOG.md` D-008) is no longer in this list — it was answered by the project owner (Accepted, 2026-10-10) and moved to `OPEN_QUESTIONS.md`'s Resolved/Closed section; see Completed above.
5. Phase 1 begins only after all of the above are complete, PR #1 is merged, and explicit authorization is given — not automatically.
