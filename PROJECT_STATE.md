# PROJECT_STATE.md
## Operational Memory — Single Source of Truth for "Where are we now"

Last Updated: 2026-10-09

---

### Current Phase
**PHASE 0 — Product & Business Model Foundation — IN PROGRESS (Pending Supervisor Review)**

Authorized by: project owner.
Scope authorized: documentation foundation only. Explicitly NOT authorized: backend code, frontend code, database migrations, authentication, billing implementation, Telegram, SMS, AI, Planning Engine, or any other application feature.

**Phase 0 is NOT marked APPROVED or DONE.** Final status is set only by the Supervisor Review process (see `SUPERVISOR_REVIEW.md`), not by this file.

### Current Milestone
Open Pull Request **#1** (branch `docs/phase0-correction-pass-3` → `main`), carrying multiple successive rounds of Supervisor-requested documentation corrections (see `CHANGELOG.md` for the dated, itemized list of every round), is awaiting independent Supervisor re-review before merge. No milestone work is pending creation of the PR — it already exists and has been updated in place across every round so far.

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
- All commits currently on `main` (`bd24cf8d...`, `994d4529...`) and all commits on this branch so far (`3b7c2dd3...`, superseded by the current branch HEAD `46563bec73dd965d392949be0dd5318d95edd087`) were made via the manual-token path described above, not via the connector.

### Completed
- [x] 14 foundation documents authored (PRODUCT_REQUIREMENTS, PROJECT_SCOPE, ARCHITECTURE, DATABASE, API, ROADMAP, PROJECT_STATE, DECISION_LOG, OPEN_QUESTIONS, TEST_PLAN, SECURITY, CHANGELOG, DEVELOPMENT_GUIDE, README)
- [x] `SUPERVISOR_REVIEW.md` placeholder added (15th document)
- [x] Two commits landed on `main` via manual token-based push: `bd24cf8d...` (initial foundation) and `994d4529...` (first correction pass)
- [x] Internal consistency review across documents (naming collision found and recorded: "Plan" — see `DECISION_LOG.md` D-006)
- [x] Confirmed no production feature implemented in any commit so far

### In Progress
- **Pull Request #1 is open** (`docs/phase0-correction-pass-3` → `main`, not merged) and awaiting independent Supervisor re-review. It is not "being opened" — it already exists; this update is one more commit pushed to the same branch, added to the same open PR. See `CHANGELOG.md` for the exact count and content of every round.
- No other work is in progress. `main` has not been touched by any of the three correction rounds.

### Blocked
- **PR #1 should not be merged yet**, per the latest Supervisor review round's explicit recommendation. This is a recommendation to hold, not a technical block — but it is treated as binding until a Supervisor explicitly says otherwise.
- Phase 0 final sign-off is blocked on **Supervisor Review**, not yet performed. See `SUPERVISOR_REVIEW.md` (placeholder only).
- Reliable, persistent repository access (read and write) via a proper connector/App installation is still not established — current access depends on manually supplied, temporary tokens. This is an operational risk for future phases, not just a Phase 0 cosmetic issue.
- Phase 1 (Architecture & Multi-Tenancy deep design + implementation) is explicitly **not started and not authorized**. It cannot start until: (a) a Supervisor Review of Phase 0 is actually recorded in `SUPERVISOR_REVIEW.md`, and (b) Q-001 (tenant isolation mechanism), Q-002 (MVP boundary), and Q-010 (hosting target) are answered by the project owner. None of these has been answered yet.

### Known Bugs
— None (no application code exists)

### Failed Tests
— None (no tests exist yet; Phase 0 is documentation-only)

### Open Questions
See `OPEN_QUESTIONS.md` for full detail. All of the following remain open and unanswered by the project owner: **Q-001** (tenant isolation mechanism), **Q-002** (MVP boundary), **Q-003** (depth of Billing in MVP — real Payment Gateway vs. Mock-only), **Q-004** (which Iranian payment gateway), **Q-005** (Telegram Bot setup), **Q-006** (which Iranian SMS provider), **Q-007** (Parent default access level), **Q-008** (default calendar/timezone handling), **Q-009** (initial Risk Engine sophistication), **Q-010** (hosting/deployment target). **Q-011** (GitHub repository access) is open/qualified, not simply resolved — see the "Repository Status (GitHub)" section above and `OPEN_QUESTIONS.md` Q-011 for the precise, tested-only, environment-separated breakdown.

### Last Verified Commit

**Structural note — read this before trusting any SHA below:** this file is itself part of every commit it describes, so it can never truthfully state "the current HEAD of this branch is `<SHA>`" — the act of committing this very edit creates a new commit whose SHA cannot be known while writing the file, which immediately makes any such claim stale. To stop this file from repeatedly going stale on a long-running branch, from this point on it records only: (a) the commit immediately **prior** to the edit being made (a fact that is true and checkable), and (b) a pointer to the authoritative live source. It does not claim to name "the current HEAD."

- **On `main`:** `994d4529c20c4a330bd843bd3ca1a7c9ed1f75ec` — directly confirmed by Claude via `git log`/`git ls-remote` against the real repository. `main` has not changed since this commit; none of the correction passes so far have touched `main`.
- **On branch `docs/phase0-correction-pass-3` (the branch backing open PR #1):** immediately before this edit, the branch's HEAD was `54eaa3d99510d12beb53eb310346700ff7893b24`. This edit adds one more commit on top of it, so by the time this text is read, the true HEAD is one commit newer than the SHA above. Full commit history on this branch so far, oldest to newest: `3b7c2dd3849ccc4f9f64d9baf0b0570487fecbb4` → `46563bec73dd965d392949be0dd5318d95edd087` → `54eaa3d99510d12beb53eb310346700ff7893b24` → (this edit's commit, SHA not yet known while writing this line). **Authoritative source for the actual current HEAD: run `git log -1` on the branch, or check the PR #1 page on GitHub — not this file.**

In all cases, Claude confirming that a commit exists on a ref is not a Supervisor content review and is not an approval of any kind.

### Last Test Result
— N/A (Phase 0 is documentation-only; `TEST_PLAN.md` defines future test strategy, nothing to run yet)

### Next Actions
1. **Pull Request #1 (`docs/phase0-correction-pass-3` → `main`) already exists and is open, carrying several rounds of Supervisor-requested documentation corrections so far (see `CHANGELOG.md` for the full, dated list).** It has not been merged. Current explicit recommendation from the latest Supervisor review round: **do not merge PR #1 yet** — further independent re-review is expected before any merge decision. The next action here is independent Supervisor re-review of the latest commit on this branch, not PR creation (already done) and not a merge decision (not authorized).
2. Project owner/Supervisor establishes a reliable, persistent repository connection (proper GitHub App installation scoped to this repo) so future work doesn't depend on manually pasted, temporary tokens — see `OPEN_QUESTIONS.md` Q-011.
3. Project owner/Supervisor performs and records an actual Phase 0 review in `SUPERVISOR_REVIEW.md`.
4. Project owner answers Q-001 (tenant isolation mechanism), confirms or amends Q-002 (MVP boundary), and answers Q-010 (hosting target).
5. Phase 1 begins only after all of the above are complete, PR #1 is merged, and explicit authorization is given — not automatically.
