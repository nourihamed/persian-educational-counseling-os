# Architecture Reconciliation Crosswalk — Phase 2

**Status:** Current reconciliation proposal; not an approval of implementation, schema, tests, production readiness or real-data use.
**Source of truth:** Product Owner decisions in PR #9 and PR #12; technical proposals in PR #8, #10 and #11. All PRs remain independent until explicitly merged.

## 1. Decision-numbering rule (OQ-C)

- Existing D-001 through D-027 identifiers are retained as historical records.
- PR #9's 35 approved Product Owner choices and PR #12's OQ-A through OQ-G decisions do **not** receive new D-numbers in this crosswalk.
- Proposed D-028 through D-062 numbers in the earlier draft were proposals only and are withdrawn as unapproved labels.
- No D-028 or later identifier may be used until a collision-free crosswalk is reviewed and each proposed decision is individually approved by the Product Owner.
- Superseded decisions remain in the log with status, scope of supersession and replacement reference; history is never deleted.

## 2. Canonical precedence

| Earlier model / statement | Controlling decision | Current interpretation |
|---|---|---|
| Counselor is the tenant; `tenants` / `counselors` are tenant roots | Workspace-centric model confirmed in PR #9 and PR #10 | Workspace is tenant boundary. Workspace types: Organization and Independent Counselor. Counselor is a member/assignment, not tenant. |
| D-025 global mobile+grade rule appears in Workspace-local DDL | PR #11 Control Plane direction; OQ-B Option K | Business rule remains; enforcement authority is Control Plane only. Workspace-local registry cannot enforce global uniqueness. |
| D-026 permits Platform Admin to initiate transfer | OQ-A Option A | Only initiator list is superseded. Platform Admin may submit support review only; cannot create transfer or bypass approvals. |
| D-026 prior counselor fee confirmation | PO decision 8 + OQ-A | Still cumulative; authenticated prior responsible counselor must confirm receipt for exact prior enrollment/case. It is an auditable assertion, not proof of payment. |
| D-027 guardian consent | PO decisions 8 and 10 | Still cumulative; verified parent/legal guardian with applicable authority, scoped and auditable consent. |
| Destination acceptance absent from old D-026/D-027 | PO decision 8 | Additional cumulative prerequisite; authorized destination actor must accept. |
| Platform Admin write capability / routine access | PO decision 32 | MVP read-only, least privilege, time-bound, approved and audited; no runtime table owner/BYPASSRLS. |
| Public individual ranking with opt-out | PO decision 33 | Superseded: public output aggregate/anonymized only; no public individual results/rankings. |
| Optional MFA for high-risk roles | PO decision 23 | Superseded: MFA mandatory for high-risk roles. |
| Deletion as ordinary student lifecycle | PO decision 1 and OQ-F2 | Controlled archival, preservation/access restrictions, category-based retention, legal hold and deletion/anonymization after approved durations. |
| Optional platform-owned ProgramTemplate in MVP | D-012 / PO decision 16 | D-012 remains controlling: Platform reference/curriculum, Organization content and counselor-personal content have distinct ownership/licensing. Platform-owned Program Templates remain excluded from MVP unless PO explicitly changes D-012. |
| Shared tenant DB/RLS as primary isolation | D-020/D-023 and Phase 1 design | Alt-5 cell isolation remains the deployment target. RLS/application checks are defense-in-depth, not replacement for cell/database credential boundaries. |

## 3. Product Owner decisions already approved (no new identifiers assigned)

The 35 decisions in `docs/PRODUCT_OWNER_DECISIONS_2026-11-07.md` are accepted at policy level. This crosswalk does not renumber them. Their topics include student lifecycle, parent permissions, capacity, counselor assignment, organization governance, stable user identity, enrollment state machine, transfer, manager scope, guardian authority, reactivation, retention, entitlements/credits, activation debit, content ownership, versioning, 404/403 behavior, background jobs, private storage, time, risk engine, MFA, audit, notifications, import/export, deterministic planning, test analysis, backlog, hosting, backup, Platform Admin, public results, exam scoring and real-data gate.

OQ-A through OQ-F3 and OQ-G/Q-007 are recorded in PR #12. Resolved direction does not mean implementation detail is closed:

- OQ-A Option A: Platform Admin cannot initiate transfer.
- OQ-B Option K: encrypted recoverable E.164 plus keyed deterministic HMAC; Platform Security owns key management.
- OQ-C Option A: collision-free numbering crosswalk; no automatic D-number assignment.
- OQ-D Option A: independent Control Plane, primary + replica, independent encrypted backups and restore drills. RPO/RTO, failover consistency, split-brain, retention and measured capacity remain open.
- OQ-E Option B: source write freeze + final snapshot for MVP. Freeze boundary, timeouts, recovery thresholds and acceptance values remain open.
- OQ-F1 Option A: Iran-only legal workflow in MVP; extensible architecture; exact evidence rules need legal review.
- OQ-F2 Option A: category-based, versioned retention; no numeric durations approved.
- OQ-F3 Option A: configurable Workspace/counselor/branch/concurrency/cell capacity; atomic checks; active students consume capacity; provisional cap 10 Workspaces total / 2 per cell is not measured capacity or pilot authorization.
- OQ-G Option A: high-level per-child/per-permission parent access accepted; Q-007 remains open for age/legal matrix, evidence, exceptions and executable tests.

## 4. Two-database responsibility split

### Control Plane database
- Platform student identity reference.
- Workspace registry and current owner.
- Monotonic ownership generation.
- Global canonical mobile+grade claim and versioned HMAC aliases.
- Transfer cases, authenticated approval evidence references, command idempotency, outbox/inbox coordination and ownership history.
- No educational records, counselor-private notes or Workspace credit ledger.

### Workspace database
- Local student educational profile and enrollment projection.
- Workspace memberships, role/permission scope, branches and counselor assignments.
- Guardian relationship and per-child permission projection.
- Educational domain, curriculum progress, programs, program versions, plans and plan versions.
- Workspace-owned credit wallet and append-only credit ledger.
- Local audit and operational records.

No cross-database foreign keys or cross-database atomic transaction are claimed. Workspace projection rows carry Control Plane student ID and ownership generation. All student-data access fails closed if current ownership cannot be validated.

## 5. Transfer protocol precedence

MVP transfer uses freeze + final snapshot, destination staging, integrity validation, then one atomic Control Plane ownership switch. The switch increments generation exactly once and writes ownership history + outbox in the same Control Plane transaction. After switch, recovery is forward-only. Cancellation or silent rollback after switch is forbidden; a reverse transfer is a new authorized transfer case.

Approvals are cumulative:
1. verified guardian consent;
2. previous responsible counselor's own authenticated fee-receipt confirmation;
3. authorized destination Workspace acceptance.

Initiation is not approval and approval is not finalization.

## 6. Current artifact reconciliation status

| Artifact | Current state |
|---|---|
| PR #12 decision consolidation | Open Draft; not merged |
| Control Plane schema/function drafts | Added/updated; not production-ready |
| HMAC rotation protocol | Specified; implementation and concurrency proof missing |
| Workspace DB design + skeleton SQL | Added; incomplete draft |
| Transfer workflow contract | Added; runtime workflow absent |
| API/authorization contract | Added; no endpoints implemented |
| Control Plane SQL tests | Revised; NOT RUN against current HEAD |
| Canonical root documents | Still require explicit reconciliation and consistency review |
| PR #8 original domain schema | Superseded by `docs/phase2/PHASE2_DOMAIN_MODEL.md` and new Workspace/Control Plane drafts; PR #8 must be reconciled/rebased or superseded and must not be merged as-is |
| Phase 2 Gate | NOT READY |
| Real student/customer data | Prohibited under D-014 |

## 7. Explicit non-claims

This crosswalk does not claim that Control Plane/Workspace schemas are complete, key rotation is safe in runtime, API authorization is implemented, Saga recovery is operational, SQL tests pass, backup/restore is proven, Phase 2 is approved, Phase 3 is authorized, or real data may be used.
