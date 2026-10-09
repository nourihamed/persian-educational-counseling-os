# DEVELOPMENT_GUIDE.md

## Mandatory Workflow Per Phase (Master Prompt §76)

```
1. Read PROJECT_STATE.md
2. Read ROADMAP.md
3. Read DECISION_LOG.md
4. Read OPEN_QUESTIONS.md
5. Inspect existing code
6. Understand current architecture
7. Define tasks
8. Implement smallest logical unit
9. Write tests
10. Run tests
11. Fix failures
12. Run regression
13. Update documentation
14. Update PROJECT_STATE.md
15. Update CHANGELOG.md
16. Commit
17. Produce Phase Report
18. STOP (do not auto-start next phase)
```

## Repository Layout (target, Master Prompt §53)

```
project-root/
├── backend/
├── frontend/
├── tests/
├── docs/
├── scripts/
├── deployment/
├── .github/
├── README.md
├── ARCHITECTURE.md
├── PRODUCT_REQUIREMENTS.md
├── DATABASE.md
├── API.md
├── ROADMAP.md
├── PROJECT_STATE.md
├── DECISION_LOG.md
├── OPEN_QUESTIONS.md
├── CHANGELOG.md
├── TEST_PLAN.md
├── SECURITY.md
└── SUPERVISOR_REVIEW.md
```

`backend/`, `frontend/`, `tests/`, `scripts/`, `deployment/` are **not required to exist in Phase 0**. The repository is allowed to contain documentation only until the phase that actually needs a given folder starts populating it (e.g. `backend/` becomes meaningful starting Phase 3/4, `frontend/` starting the phase that builds UI). Creating these folders early (optionally with a `.gitkeep`) is a convenience some sessions may choose, not a Phase 0 requirement — do not treat an empty-folder skeleton as part of the Definition of Done for Phase 0. No application code goes into any of these folders until its corresponding phase is authorized and in progress.

## Commit Conventions (Master Prompt §62)
Prefixes: `feat:`, `fix:`, `refactor:`, `test:`, `docs:`, `security:`, `perf:`, `chore:`. Small, logical commits preferred over large batched ones.

## Definition of Done (Master Prompt §65)
A feature is Done only when: requirement implemented, backend, frontend, API, DB migration, tests, integration, edge cases, security, documentation, regression, and no blocking issue remain. Phase 0 has no "feature" in this sense — its Definition of Done is the Phase 0 Checklist in `PROJECT_STATE.md`.

## No-Guessing Rule (Master Prompt §78)
If a requirement is unclear, it is **recorded in `OPEN_QUESTIONS.md`** (question, why it matters, recommended option, alternatives, impact) — never silently decided.

## Session Report (Master Prompt §79)
Every working session ends with a structured report: Date, Phase, Milestone, Completed, Files Changed, Tests Run/Passed/Failed, Known Issues, Decisions, Documentation Updated, PROJECT_STATE Updated, Next Step, Blocked (Yes/No).

## Phase Boundaries
Claude/the engineering process does not start the next roadmap phase automatically. Each phase ends with a report and waits for explicit authorization, exactly as this Phase 0 session was explicitly authorized before work began.
