# Pre-Pilot Recommendations for Remaining Items (best-option proposals)

Status: RECOMMENDATIONS ONLY. None of the items below is a decision. Decisions belong to the Product Owner (D-013 to D-017 are the decisions on record). Legal, tax and privacy determinations belong to qualified reviewers. Nothing here asserts a legal duration, a legal requirement, or that any control is implemented or tested.

Date: 2026-10-17. Prepared by: technical lead (implementation agent).

---

## 1. Data retention durations (Q-020)

**Recommended approach (best practice, data minimisation):**
- Collect only fields needed for the counseling service; keep no field "in case it is useful later".
- Use a single retention rule per category (R1 to R9 in DATA_RETENTION_SCHEDULE_DRAFT.md), not per record.
- Set the duration for each category as a short, explicit period that counsel can confirm or extend. Extension must be a recorded decision, not a default.
- Where a legal or tax minimum applies to a category (most likely R4 billing), keep only the records the minimum requires, and delete or anonymise the rest.

**Proposed working defaults (for discussion only; replace with legally reviewed values):**
| Category | Working default for discussion | Reason it is only a default |
|---|---|---|
| R1 student records | Keep while the relationship is active; then a short post-relationship window the owner chooses (for example a few months), followed by deletion | Minors' records; the window must be set with counsel |
| R2 credentials | Remove credential material at deactivation; keep identifiers only for R3 | Security practice; no legal number |
| R3 audit records | Keep for a window the owner and security reviewer agree; no deletion during an open incident | Accountability; period set by owner |
| R4 billing | Retain exactly what the tax/accounting rule requires; counsel to state it | Legal; NOT assumed here |
| R5 delivery status | Short operational window; message content not kept beyond delivery need | Operational |
| R6 files and exports | Follow R1 unless counsel says otherwise; delete with the owning record | Derived |
| R7 backups | Bounded rotation; period chosen with the recovery objective (RPO/RTO) | Technical; RPO/RTO not yet defined |
| R8 logs | Short rotation; no secrets or personal identifiers where avoidable | Operational |

**Reviewer and approver (recommended):**
- Legal/privacy review: a qualified lawyer familiar with personal data of minors and the operating jurisdiction. Engaged by the Product Owner before pilot.
- Tax review: a qualified accountant for R4 only.
- Approver for role deletion: the Product Owner, after the checklist in DATA_RETENTION_SCHEDULE_DRAFT.md §4 is complete and recorded. The technical lead prepares the checklist evidence; the approver does not sign off alone on evidence they did not see.

---

## 2. Responsible reviewer for legal, tax and privacy (Q-020)

Recommended: one legal/privacy reviewer with minors' data experience, plus one tax reviewer for R4. Both engaged in writing with a defined scope (the Data Retention Schedule only). Their output is a signed memo, which is recorded in DECISION_LOG when the owner accepts it. Until then, all durations stay NEEDS-DECISION.

---

## 3. Target host (D-011) — recommended profile to test, not a measured host

Recommended for the pilot test environment (a profile to be provisioned and then measured; NOT a measurement):
- Single dedicated Linux VM on the D-011 hosting option, separated from any other workload.
- PostgreSQL 15 or later (supported major version), with `max_connections` set explicitly and documented, not left at a default without a recorded value.
- Application workers and background workers on the same host only if measured; otherwise separate processes with their own limits.
- Storage: encrypted disk; backups stored off the same disk.
- Network: database reachable only from the application host; no public database port.
- Monitoring: host CPU, memory, disk, PostgreSQL connections, and application latency, recorded from the first test run.

The exact CPU, RAM and disk figures should be chosen after the first ramp test (L-01), not before. Choosing them first and calling them "measured" would be wrong.

---

## 4. Security review of the implementation (gate c)

Recommended: an independent reviewer who did not write the code, with access to the repository, the migrations, the role configuration and the test results. Scope: tenant isolation paths (TI contracts), role and grant configuration (TI-CFG), connection routing and lifecycle (TI-CONN), file and export paths, and secret handling. Output: a written report with findings classified as blocking or non-blocking. Blocking findings must be fixed and re-tested before pilot. Not required for Phase 1 design approval.

---

## 5. Emergency stop and rollback (required before pilot)

Recommended procedure is in `EMERGENCY_STOP_AND_ROLLBACK_RUNBOOK.md` (same folder). It is a draft and has not been exercised. Exercising it on the test environment is itself a pre-pilot test (to be added to the load test plan as L-11).

---

## 6. Summary of recommendations

| Item | Recommended option | Still needs |
|---|---|---|
| Retention durations | Short, explicit, per category; counsel confirms | Owner decision after legal review |
| Legal/privacy reviewer | Qualified minors' data lawyer, written scope | Owner engagement |
| Tax reviewer | Accountant, R4 only | Owner engagement |
| Role-deletion approver | Product Owner after checklist evidence | Owner confirmation |
| Target host | Dedicated VM, PostgreSQL 15+, explicit limits, measured before sizing | Host provisioning |
| Security review | Independent reviewer, written, blocking findings fixed | Owner engagement |
| Emergency stop | Runbook drafted; to be exercised | Test environment |
