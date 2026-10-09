# Persian Educational Counseling & Study OS

Multi-tenant SaaS platform for the Iranian educational-counseling market, connecting **Counselors** (B2B2C sellers of counseling service) with **Students** (end learners), **Parents**, **Teachers**, and a **Platform Admin**.

This is **not** a Todo List / Calendar / Study Timer. It is an Educational Counseling & Student Study Operating System built around one loop:

```
Counselor Strategy → Student Baseline → Personalized Plan → Execute → Record →
Analyze → Identify Weakness → Review/Correct → Progress →
Counselor Feedback → Plan Adjustment → Repeat
```

## Project Status

**Phase 0 — Product & Business Model Foundation — IN PROGRESS.**
No backend, frontend, database, authentication, billing, Telegram, SMS, or AI functionality exists yet. This repository currently contains documentation only. See `PROJECT_STATE.md` for the authoritative current status.

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
| `SUPERVISOR_REVIEW.md` | External review log (placeholder until a real review is recorded) |

## Core Principles

- **Multi-tenant, strictly isolated**: every Counselor is an independent tenant; cross-tenant data access is a security incident, not a bug.
- **B2B2C billing**: Platform → Counselor → Student, via Student Credits / Subscriptions, with an append-only credit ledger.
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
