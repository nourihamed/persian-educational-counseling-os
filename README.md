# Persian Educational Counseling & Study OS

Multi-tenant B2B2C SaaS platform for the Iranian educational-counseling market. The tenancy model is **Platform → Workspace → Students**, where a Workspace is an Organization or an Independent Counselor workspace. Counselors, students and parents are users with Workspace-scoped relationships and permissions.

This is **not** a Todo List / Calendar / Study Timer. It is an Educational Counseling & Student Study Operating System built around one loop:

```
Counselor Strategy → Student Baseline → Personalized Plan → Execute → Record →
Analyze → Identify Weakness → Review/Correct → Progress →
Counselor Feedback → Plan Adjustment → Repeat
```

## Project Status

**Phase 0 — Product & Business Model Foundation — CLOSED (Product Owner, 2026-10-14).** PR #1 was merged into `main` on 2026-10-14.
**Phase 1 — Architecture & Multi-Tenancy — APPROVED for design/documentation only (D-024, 2026-10-24).** This is not runtime-security approval.
**Phase 2 — Database & Domain Model — IN PROGRESS ON PR #12, GATE NOT READY.** PR #12 is Open/Draft/Unmerged. It contains draft Control Plane and Workspace schemas/contracts; none are production migrations or independently verified tests. PRs #8–#11 remain separate Open/Draft/Unmerged branches. See `PROJECT_STATE.md` for current status.
No runtime backend/frontend, production migration, or operational infrastructure is approved by this documentation work. Phase 3 is not authorized. D-014 prohibits real student/customer data until all required gates pass and written Product Owner approval is recorded.

## Phase 2 reconciliation note (2026-11-09)

Control Plane owns global student identity, current Workspace ownership, ownership generation and global mobile+grade claims. Each Workspace DB owns local educational data and enrollment projections. Transfer requires verified guardian consent, previous responsible counselor fee confirmation and destination acceptance; MVP uses source freeze + final snapshot. HMAC rotation, approval verification, full Workspace schema, runtime Saga and tests remain incomplete. Phase 2 is NOT READY; synthetic data only.

## Start Here

| Document | Purpose |
|---|---|
| `PRODUCT_REQUIREMENTS.md` | What the product is, for whom, and why |
| `PROJECT_SCOPE.md` | MVP boundary vs. deferred features |
| `ARCHITECTURE.md` | Layering, multi-tenancy strategy, adapter pattern |
| `DATABASE.md` | Conceptual domain/entity model |
| `API.md` | API design principles |
| `ROADMAP.md` | The 28-phase delivery plan |
| `PROJECT_STATE.md` | **Operational memory** — read this first in every session |
| `DECISION_LOG.md` | Why key architectural choices were made |
| `OPEN_QUESTIONS.md` | Unresolved items awaiting a human decision |
| `TEST_PLAN.md` | Testing strategy, incl. mandatory tenant-isolation tests |
| `SECURITY.md` | Security requirements and threat model |
| `DEVELOPMENT_GUIDE.md` | Required per-phase workflow and repo conventions |
| `CHANGELOG.md` | History of what changed, by phase |
| `SUPERVISOR_REVIEW.md` | Independent Supervisor reviews and findings; current Phase 0 documentation gate is APPROVED (documentation/architecture only; no runtime security approval) |

## Core Principles

- **Multi-tenant, strictly isolated**: Workspace is the tenant boundary (Organization or Independent Counselor). A Counselor is a member/assignment, not a tenant; cross-Workspace access is prohibited unless an explicit scoped permission exists.
- **B2B2C billing**: Platform → Workspace → Student, via Workspace-owned Student Credits / Subscriptions, with an append-only auditable ledger.
- **Adapters, not hardcoding**: Payment, Telegram, SMS, and AI are pluggable behind interfaces — Core domain never depends on a vendor directly.
- **Explainable automation**: risk flags, plan recommendations, and auto-generated reviews must always carry a reason, never an unexplained score.
- **Versioned, not overwritten**: Program Templates, Program Versions, and student Plans preserve full history.
- **No guessing**: unclear requirements go into `OPEN_QUESTIONS.md`, not into silent assumptions baked into code.

## Development Workflow

See `DEVELOPMENT_GUIDE.md`. In short: every phase reads `PROJECT_STATE.md` → `ROADMAP.md` → `DECISION_LOG.md` → `OPEN_QUESTIONS.md` before doing any work, implements the smallest logical unit with tests, updates documentation and `PROJECT_STATE.md`, commits, and **stops** for review — the next phase is never started automatically.

## Tech Stack (planned, not yet implemented)

- Backend: Python 3.12+, FastAPI, Pydantic v2, SQLAlchemy 2, PostgreSQL 15+, Redis, HTTPX, Pytest
- Frontend: React, TypeScript, Vite, Persian RTL, PWA-ready
- Calendar: Jalali default, Gregorian supported, Asia/Tehran timezone, isolated conversion module


### Phase 2 security and data-model review updates (2026-11-09)

Additional draft contracts and independent findings are recorded under `docs/phase2/`: contact-change reverification, transfer approval identity/authority, cross-Workspace Saga, Workspace domain schema review, Q-007 parent/guardian authority, category-based retention/legal hold, and backup/failover/restore. A new final-capacity-slot concurrency test is wired into CI but awaits fresh execution. These additions do not close the HIGH findings; Phase 2 remains NOT READY and real data remains prohibited under D-014.
