# Target-Environment Load and Connection Test Plan (pre-pilot)

Status: PLAN ONLY. No test has been run. Alt-5 target cell topology under D-020/D-023: NOT SELECTED / NOT PROVISIONED / NOT CONFIRMED. All results below are NOT-RUN or BLOCKED. This document is NOT a measurement.
Gate: pilot-validation criteria (D-015, D-014 condition 3). Not a prerequisite for Phase 1 design approval.

## 1. Objectives
- Measure, not estimate, tenant count capacity, connection usage, memory, CPU, latency and error behaviour on the target host.
- Verify the D-017 recorded baseline: direct PostgreSQL connections, pool size 1 per tenant per process. This is not capacity evidence for Alt-5 until measured per PostgreSQL instance; any change requires a separate Product Owner decision. Transaction pooling remains deferred and requires separate compatibility contracts/tests and a separate decision.
- Verify the active Alt-5 acceptance catalog under load and in the target environment, including per-tenant database/credential boundaries, cross-cell network denial, trusted routing, revocation, backup independence and restore lifecycle. The active catalog is `TENANT_ISOLATION_TEST_CONTRACTS.md`; historical TI-CONN/TI-CTX identifiers are not current acceptance evidence unless explicitly mapped. TI-CELL-15 covers revocation/session/pool closure; it does not prove transaction-pooling compatibility.
- Verify recovery after failure and the emergency stop procedure.

## 2. Preconditions (each must be recorded; if not met the test is BLOCKED)
| ID | Precondition | Status |
|---|---|---|
| P1 | Target Alt-5 cells provisioned and described (per-cell host/VM, network, PostgreSQL instance, CPU/RAM/disk, max_connections, account/admin boundary) | BLOCKED: provider/candidate deferred; target not confirmed |
| P2 | Implementation of the application and migrations exists on the test branch | BLOCKED: Phase 2 or later |
| P3 | Alt-5 tenant database and tenant-specific runtime credential provisioning implemented and reviewed | BLOCKED: implementation (Phase 2 or later) |
| P4 | Test data generator produces synthetic data only (no real student data) | NOT-RUN |
| P5 | Monitoring of host metrics available | NOT-RUN |
| P6 | Emergency stop and rollback procedure written | NOT-RUN |
| P7 | D-023 Level 4 backup copies, administration, keys and deletion/retention controls are demonstrably outside ordinary production-account control | BLOCKED: no hosted candidate selected/verified |

## 3. Scenarios
| ID | Scenario | Variables | Pass criterion (to be finalised before run) | Status |
|---|---|---|---|---|
| L-01 | Ramp to 1, 5, 10 tenants, one counselor session each | tenant count | No error; p95 latency within threshold set before the run | NOT-RUN |
| L-02 | Concurrent requests across all 10 tenants | concurrency level | Connection count stays within the calculated bound; no connection leak | NOT-RUN |
| L-03 | Background jobs active during L-02 | job count | Job connections counted; total within host limit | NOT-RUN |
| L-04 | Administrative access during L-02 | admin sessions | Reserve respected | NOT-RUN |
| L-05 | Burst test: maximum allowed concurrency for 10 minutes | burst | No crash; graceful queueing or refusal | NOT-RUN |
| L-06 | Failure injection: kill one application process | process failure | Connections released; service recovers; no cross-tenant data | NOT-RUN |
| L-07 | Failure injection: database restart | DB restart | Recovery within documented time; no stale context | NOT-RUN |
| L-08 | Tenant suspension during load | suspension | Login refused immediately; active sessions/pools terminated within the documented target and evidence recorded (TI-CELL-15) | NOT-RUN |
| L-09 | Isolation under load: tenant A requests never return tenant B rows | parallel tenants | Zero cross-tenant rows in all responses | NOT-RUN |
| L-10 | Restore-from-independent-backup test (R7) on SYNTHETIC data: restore must re-apply tenant suspensions/deletions decided after the restore point and demonstrate independent backup administration/key/deletion controls | backup restore | Suspended tenant stays suspended after restore; no cross-tenant data; checksums match the evidence copy; production credentials cannot delete all critical copies or decrypt all backups | BLOCKED: target backup boundary and restore re-application mechanism not implemented/verified (Phase 2 or later). Does NOT depend on Q-020 duration decisions; retention policy is a separate pre-pilot gate |
| L-11 | Exercise the emergency stop and rollback runbook (EMERGENCY_STOP_AND_ROLLBACK_RUNBOOK.md) with recorded timing | incident drill | All steps executed in order; timings recorded; no tenant re-enabled before reopen criteria are met | NOT-RUN |

## 4. Measurements to record
- Connections: total, per tenant role, per process, peak, reserved; PostgreSQL max_connections.
- Memory: PostgreSQL backend memory; application process memory; host free memory.
- CPU: host and database.
- Latency: p50, p95, p99 per endpoint class; error rates.
- Errors: types and counts; any tenant-data leak counts (must be zero).
- Recovery time after L-06 and L-07.

## 5. Evidence to store
- Host description and configuration, exact versions, and the test commit SHA.
- Raw metrics export and the scripts used (to be reproducible).
- Results table with status PASS, FAIL, BLOCKED or NOT-RUN per scenario, with the criterion stated.
- Known limitations and anything not measured.

## 6. Acceptance for pilot (D-014 condition 3 and D-017)
- Measured connection and memory usage within the host limits with margin set by the Product Owner.
- Zero cross-tenant rows in L-09.
- Recovery scenarios pass.
- Written owner approval of the cap (A1) after reviewing the evidence.
If capacity is insufficient, the cap is reduced. No real student data is allowed until this plan is complete and approved.
