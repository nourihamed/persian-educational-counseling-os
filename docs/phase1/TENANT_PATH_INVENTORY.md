# TENANT_PATH_INVENTORY.md

Phase: 1 (design). Status: category-level inventory. Endpoint-level inventory is NOT yet possible because no endpoint exists; it is required in Phase 2 (data model) and Phase 4 (API/RBAC).

Purpose: make every data access path traceable to at least one test contract (supervisor review item 3). A path marked UNMAPPED blocks Phase 1 review. Coverage is measured as: paths with at least one mapped contract ÷ all paths in this file. This file defines the denominator. The 100% figure is NOT claimed until endpoint-level inventory exists and every endpoint is listed.

## Path Table

| Path ID | Surface | Access | Tenant source | Mapped contracts | Status |
|---|---|---|---|---|---|
| P-01 | Student read (profile, list, detail) | Read | Principal → relationship | TI-API-01, 08, 12, 13, 15; TI-REPO-02, 03 | Mapped |
| P-02 | Student write (profile, relationship) | Write | Principal → relationship | TI-API-02, 04, 07, 10; TI-REPO-04, 06 | Mapped |
| P-03 | Plan read | Read | Plan.tenant_id; principal relationship | TI-API-01, 08; TI-VER-01, 02 | Mapped |
| P-04 | Plan write (create, edit, submit) | Write | Plan.tenant_id; principal | TI-API-02, 11; TI-VER-03; TI-FK-01 | Mapped |
| P-05 | PlanVersion create and activate | Write | Plan.tenant_id | TI-VER-03, 04, 06, 07; TI-FK-01, 02, 03 | Mapped |
| P-06 | ProgramTemplate / ProgramVersion read | Read | Template.tenant_id | TI-VER-05; TI-API-17; TI-FK-04 | Mapped |
| P-07 | ProgramTemplate / ProgramVersion write | Write | Template.tenant_id | TI-API-03, 16, 17; TI-FK-04 | Mapped |
| P-08 | StudentProgramEnrollment | Read/Write | Student.tenant_id | TI-API-05; TI-FK-05 | Mapped |
| P-09 | Study, test, error, review records | Read/Write | Student.tenant_id | TI-CTX-04 to 08 (representative); TI-REPO-04 | Mapped (representative; see note) |
| P-10 | CreditLedger / CreditTransaction | Read/Write | Counselor.tenant_id | TI-CTX-05, 06; TI-REPO-04; TI-AUD-01 | Mapped |
| P-11 | Audit log read | Read | Tenant (actor) | TI-AUD-02 | Mapped |
| P-12 | Audit log write | Write | Tenant (actor) | TI-AUD-01, 03 | Mapped |
| P-13 | Dashboards and aggregates | Read | Tenant context | TI-API-12; TI-REPO-03 | Mapped |
| P-14 | Search | Read | Tenant context | TI-API-14 | Mapped |
| P-15 | Pagination cursors | Read | Tenant context | TI-API-13 | Mapped |
| P-16 | Reports (student, multi-student) | Read | Tenant context | TI-RPT-01, 02, 03 | Mapped |
| P-17 | Exports (CSV, Excel, PDF) | Read | Tenant context | TI-EXP-01, 02, 03 | Mapped |
| P-18 | File upload | Write | Record tenant; storage key | TI-FILE-05, 07; TI-FILE-04 | Mapped |
| P-19 | File download / signed URL | Read | Record tenant | TI-FILE-01, 02, 03, 06, 07 | Mapped |
| P-20 | Notification creation | Write | Recipient tenant | TI-NOTIF-01, 02, 05 | Mapped |
| P-21 | Notification delivery and retry | Read/Write | Delivery row tenant | TI-NOTIF-03, 04 | Mapped |
| P-22 | Telegram and SMS adapter calls (outbound) | Outbound | Notification row | TI-NOTIF-02, 04 | Mapped |
| P-23 | Background jobs (tenant-bound) | Read/Write | Job payload tenant_id | TI-JOB-01, 02, 03, 05 | Mapped |
| P-24 | Platform aggregate jobs | Read (aggregate) | None (platform) | TI-JOB-04 | Mapped |
| P-25 | Platform admin read | Read | Explicit target tenant | TI-PLAT-01 to 04, 07, 09, 10 | Mapped (decided, D-013) |
| P-26 | Platform admin write | Write | Explicit target tenant | TI-PLAT-08 (static scan + refusal) | PROHIBITED in MVP (D-013); mapped as guard |
| P-27 | Parent read | Read | Parent link | TI-API-09 | BLOCKED (Q-007) |
| P-28 | Authentication and tenant derivation | Read | Principal membership | TI-API-06, 07 | Mapped |
| P-29 | Database migrations | Privileged write | Schema-level, not tenant data | TI-CFG-02, 10 | Mapped |
| P-30 | Operational scripts under `scripts/` | Privileged | Must be explicit | TI-REPO-05 (static scan), TI-CFG-10 | Mapped (scan; no script exists yet) |
| P-31 | Raw SQL outside Infrastructure | Read/Write | Unknown | TI-REPO-05 | Mapped (static guard) |
| P-32 | Option D context function (only if Option D chosen) | Privileged | Token | TI-CTX-15, 16, 17, 18; TI-BYP-03 | BLOCKED (Q-019 mechanism) |
| P-33 | Option C tenant connection routing and role membership (only if Option C chosen) | Connection | Principal tenant | TI-CONN-01, 02, 03 | BLOCKED (Q-019 mechanism) |

## Notes
- P-09 is listed with representative contracts, not one per record type. Endpoint-level inventory in Phase 4 must add one row per record type. Until then, P-09 counts as mapped only in the representative sense.
- P-26 is listed so that the prohibition in D-013 cannot be silently reversed: a static guard (TI-PLAT-08) must fail if a platform write route appears.
- P-27 and P-32 are BLOCKED; a BLOCKED path cannot be counted as covered.

## Summary (at this revision)
- Total paths listed: 33
- Mapped to at least one contract: 30 (P-09 is representative only; P-30 is a static guard with no script yet; P-26 is a prohibition guard)
- BLOCKED: 3 (P-27 by Q-007; P-32 and P-33 by the Q-019 mechanism decision, exactly one of the two applies)
- UNMAPPED: 0
- Endpoint-level coverage: NOT MEASURABLE YET. The 100% claim is not made.

Recount command (run from repository root): `grep -cE "^\| P-[0-9]+ " docs/phase1/TENANT_PATH_INVENTORY.md` should print 33.
