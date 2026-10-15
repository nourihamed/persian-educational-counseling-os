# AUTHORIZATION_CONTRACT.md

Phase: 1 — Architecture & Multi-Tenancy (design only)
Status: DRAFT (revision 2, corrective pass) for Product Owner review. Contract only; no endpoint exists yet. Endpoint shapes remain in `API.md`. Nothing here is verified by tests.

Scope note: object-level authorization in this contract is the PRIMARY control against authenticated users (threats T1, T3 in `TENANT_ISOLATION_DESIGN.md` §1). It is not a control against arbitrary SQL execution (T4); see `TENANT_ISOLATION_DESIGN.md` §2.

Purpose: define, before any endpoint is built, how every resource and action is authorized. Every future endpoint must declare its entries in this contract. An endpoint without a declared entry is not reviewable and must not be merged.

---

## 1. Authorization Decision Procedure

For every request, in order:

1. **Authenticate.** Resolve the principal. Unauthenticated → 401.
2. **Resolve tenant context** from the principal (`TENANT_ISOLATION_DESIGN.md` §1). Never from path/body.
3. **Check the action permission** against RBAC (table-driven, D-005): does the principal's role grant this action type? Failing → forbidden (403).
4. **Load the target object within the tenant** (tenant-scoped query). Not found within tenant → not-found response. The exact status (404 recommended) is pending Q-014; cross-tenant and nonexistent objects must produce identical responses whichever status is chosen.
5. **Check object-level rules**: relationship and status (§3). Failing → forbidden (403) for an object the principal can see but may not act on.
6. **Check referenced objects in the body** belong to the same tenant (§4). Failing → validation error without disclosing the other tenant's existence.
7. **Execute** in one transaction with tenant context set (`TENANT_ISOLATION_DESIGN.md` §4).
8. **Audit** state-changing actions with actor, action, target, and request_id.

Steps 3 and 5 must not be skipped even when RLS would also deny the operation. RLS is the backstop for application defects, not the check and not a boundary against arbitrary SQL.

---

## 2. Roles and Scope (MVP)

| Principal | Tenant scope | Default capability (Phase 1 design; detailed permission matrix in Phase 4) |
|---|---|---|
| Counselor | Own tenant | Manage own students, programs, plans, activities, notes, credits |
| Student | Tenant of its active relationship | Read/execute own plan and records; cannot read other students |
| Parent | Linked students only, if linked | Limited read; detailed rules open (Q-007) |
| Teacher | Not in MVP | Role reserved (Master Prompt §4); no permissions granted in MVP |
| Platform Admin | Cross-tenant only via audited path | Per Q-015; never implicit |

---

## 3. Object-Level Rules (examples that RLS cannot express)

| Action | Required relationship / status | Notes |
|---|---|---|
| Counselor reads a student | Active `CounselorStudent` (`status = Active`) for this counselor and tenant | Archived/Ended relationships: read-only history, no writes |
| Counselor edits a student's plan | Active relationship; plan not superseded | Edits create a new `PlanVersion` (D-008), never overwrite a published one |
| Student executes plan item | Student is the plan's student; item belongs to the active plan version | Cannot alter the plan itself |
| Student reads another student's plan | Forbidden | Even in the same tenant |
| Any actor writes a published `ProgramVersion` | Forbidden | Publication is immutable; a new version must be created |
| Create a `PlanVersion` from a `ProgramVersion` | Program version in same tenant; student enrolled in that program; actor is the owning counselor | D-008 point 7 governs later template updates; no silent effect on existing plans |
| Activate a student | Available credit ≥ 1, verified against the ledger inside the same transaction | Prevents negative balance; ledger writes are append-only |

---

## 4. Referenced-Object Rule (Body IDs)

Any request that references another object by ID (for example, `student_id` when creating a plan, or `program_version_id` when enrolling) must:
- Verify that the referenced object exists **within the same tenant**;
- Use the composite FK as a second guarantee (`TENANT_ISOLATION_DESIGN.md` §5);
- Return a validation error that does not confirm or deny the existence of the object in another tenant. A single generic message is used for "not found in your tenant" and "does not exist," so responses cannot be used to enumerate other tenants' IDs.

---

## 5. Listing and Search

- Every list endpoint applies the tenant and relationship filter **in the query** (SQL `WHERE`), never by fetching then filtering in memory.
- Pagination is cursor- or keyset-based on tenant-scoped indexes, so counts and page boundaries cannot reveal other tenants' data.
- Aggregates (dashboards, counts) are computed per tenant within the tenant context. Platform-wide aggregates are only for the platform-admin path (Q-015).
- Search endpoints must restrict the search index or query to the tenant; a shared full-text index without a tenant filter is forbidden.

---

## 6. Error Mapping (Uniform)

| Situation | Response |
|---|---|
| Not authenticated | 401 |
| Authenticated, action not granted by role | 403 |
| Object not visible in tenant (includes other tenant's objects) | Not-found response; status 404 recommended, pending Q-014; identical to a nonexistent object |
| Object visible, relationship/status forbids action | 403 |
| Validation or referenced-object failure | 422 with generic message (§4) |
| Conflict (version race, duplicate review) | 409 |
| Internal tenant-context error | 500 with no tenant detail |

Error bodies must never include another tenant's identifiers, names, or counts.

---

## 7. Mandatory Checklist for Every Future Endpoint

A reviewer rejects an endpoint that cannot answer all of these from its contract entry:
- [ ] Authenticated? Which principal types?
- [ ] Action permission (role) declared?
- [ ] Target object type and how it is loaded tenant-scoped?
- [ ] Object-level relationship/status rule declared?
- [ ] Every body/path ID checked for tenant membership?
- [ ] List query filter applied in SQL?
- [ ] Audit event declared for state changes?
- [ ] Negative cross-tenant test IDs (from `TENANT_ISOLATION_TEST_CONTRACTS.md`) linked, with expected response identical to the nonexistent-object response?
