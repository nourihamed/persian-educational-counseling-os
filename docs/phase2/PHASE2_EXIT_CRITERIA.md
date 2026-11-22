# Phase 2 Exit Criteria & Evidence Matrix

**Phase:** Database & Domain Model  
**Current Gate:** NOT READY — independent Supervisor assessment (2026-11-22). H-01..H-04 technical remediations pass CI; unresolved Product Owner, Platform Security and domain-model gates still prevent exit.  
**Scope:** Architecture/domain model, draft schema, constraints, API/service contracts and executable synthetic database tests. This phase does not authorize production deployment or real student data.

## 1. Gate interpretation

Phase 2 must finish the database/domain architecture and define testable contracts before implementation phases. It must not silently absorb full production infrastructure, API service delivery, KMS deployment, distributed worker deployment or live backup/failover drills if those belong to later authorized phases.

However, a later implementation may not begin with an undefined security/domain contract. Phase 2 must define the trust boundaries, data model, invariants, state transitions, failure behavior, acceptance tests and explicit dependencies for those later implementations.

A design contract is not implementation evidence. A draft SQL test is not runtime/API/operational evidence. Each evidence type must be reported separately.

## 2. Phase 2 exit checklist

| Area | Phase 2 design/schema exit requirement | Current status |
|---|---|---|
| Canonical architecture | Workspace-centric Control Plane / Workspace DB ERD and authority boundaries, no false cross-DB atomicity | PARTIAL — baseline exists; reconcile all artifacts |
| Product decisions | Collision-free decision crosswalk; no unapproved D-number allocation; all accepted PO choices traced | PARTIAL — crosswalk exists; PR #8–#11 cleanup remains |
| Global identity | Initial admission, mobile+grade uniqueness, HMAC rotation and contact-change data contract | PARTIAL — initial admission/rotation SQL tested; contact-change contract only |
| Approval evidence | Three cumulative approval types, principal/authority binding, revocation/reapproval event model and cutover revalidation | PARTIAL — append-only approval and revocation/reapproval event schema is DONE (APR-01..13, APR-RACE-01, SEP-01..29); authority/legal binding and cutover revalidation remain open (Q-007, transfer contract). §3 schema evidence is not full approval authority. G-33 wording reconciled 2026-11-22. |
| Transfer | Freeze/snapshot/staging/Saga state model, event envelope, outbox/inbox semantics, recovery matrix | PARTIAL — contracts and switch draft exist; schema/runtime boundary needs reconciliation |
| Tenant authorization | Principal, membership, role, permission, assignment, guardian relationship and object scope model | PARTIAL — test-only signed principal assertion and RLS ENABLE+FORCE with mandatory RESTRICTIVE fence verified on every student-scoped table; exact bypass allowlist; unknown/indirect/column/PUBLIC and pg_read/write-all-data controls pass ISO-RLS-C3..C16, Actions run 45030847506 step 15. Production verification remains disabled pending PS-1..PS-5 and M-01 trusted deployment/test-mode separation; student read scope, background identity and manager permission vocabulary remain open. |
| Workspace lifecycle | Activation, suspension, archive/reactivation, transfer projection and capacity invariants | PARTIAL — activation tested; lifecycle closure incomplete |
| Educational domain | Curriculum, planning inputs/items, execution, assessments, analysis, classes, reviews and history | NOT READY — skeleton exists; WS-DOM findings open |
| Versioning | Program/Plan version ownership, immutability, provenance, publication and edit rules | PARTIAL — WS-PLAN-01 A2/B1/C1/D1/E1 enforced; direct published INSERT rejected; item/publication row-lock protocol and rollback races pass Actions run 45030847506 step 16. Exact actor × from_status × to_status graph remains PO-open; base rule table empty and fail-closed; production runtime writes remain closed. |
| Student Credit | Wallet/ledger, debit, reversal, purchase/refund/renewal boundaries and idempotency | PARTIAL — activation/debit/reversal draft; commercial lifecycle incomplete |
| Capacity | Dimension model, atomic counters, archive adjustment, final-slot races and reconciliation | PARTIAL — same-enrollment race tested; final-slot test added, fresh CI pending; archive lifecycle open |
| Files/notifications | Private object metadata, quarantine/scan, authorization, transfer fencing, recipient isolation | PARTIAL — Batch 8: file facts immutable and state forward-only; notification recipient isolation (member / the student / a verified guardian **of that student**), payload contact hygiene and immutability enforced and tested; the transfer barrier now covers notifications (32 tables, 0 holes). Still missing: quarantine-clearing scan service, delivery-time re-authorization (OPS-NOTIF-DELIVERY), and any API/worker |
| Retention/legal hold | Category-based versioned policy model, legal-hold and restore-suppression contract | PARTIAL — Batch 8: immutable category-scoped policy versions (nine categories, all `needs_decision`, nothing approved), enforceable integrity for the legal-hold polymorphic reference, immutable placement with one-way release, and one fail-closed disposition gate with five named refusals, tested to ALLOW only under a synthetic approved policy. Still open: durations (Q-020), hold and disposition authority (OPS-HOLD-AUTH, OPS-DISP-AUTH), and all completeness beyond the primary row — objects, exports, caches, indexes, replicas, backups and restore suppression (OPS-RETENTION-SCOPE) |
| Operations | HA/backup/restore/failover/capacity boundaries and acceptance evidence requirements | PARTIAL — contract only; environment execution belongs to later gate |
| SQL quality | Fresh PostgreSQL 16 CI on exact final tree, role catalog tests, constraints, races, regression | PASS for remediation head `cad2c099` — GitHub Actions [45030847506](https://github.com/nourihamed/persian-educational-counseling-os/actions/runs/45030847506), PostgreSQL 16.16; steps 15/16/17 and repository secret/register checks 30/31 successful. CI success on draft SQL is not gate approval. |
| Gap matrix | Authoritative requirement-by-requirement matrix built from code and tests | `PHASE2_GAP_MATRIX.md` reconciled 2026-11-22; H-01..H-04 evidence and current blockers recorded; G-15/G-16/G-17/G-26 remain open |
| Documentation | Root canonical docs, Project State, Roadmap, Test Plan, Changelog and Supervisor Review agree | PARTIAL — gap matrix, exit package and open-decision register reconciled 2026-11-22; PROJECT_STATE/TEST_PLAN and PR descriptions still require final baseline update; root ARCHITECTURE/DATABASE/API/ROADMAP/SECURITY current override blocks reconciled 2026-11-22; detailed body-level traceability remains partial. |
| PR integration | PR #8–#11 disposition, PR #12 base/head consistency, no accidental main changes | NOT READY — PR #8–#12 and stacked PR #14 remain open/draft; PR #12 head `78155b6`, base `ba5e9d8`, current main `5bb8e4e`; PR #14 head `3049a2a` is stacked on PR #12. No main change or merge performed. |
| Independent review | Final review against exact SHA and evidence; PO accepts gate separately | PARTIAL — H-01..H-04 independently reviewed and verified on synthetic schema/CI evidence; remaining domain, migration, production-security and integration findings have not received final review. Product Owner acceptance remains separate. |

## 3. Findings that block design/schema exit

Status vocabulary, applied to every item: **DONE** (implemented at the schema level and covered by executed
tests), **PARTIAL** (some of the item is implemented, the rest is named below), **NOT IMPLEMENTED**,
**DEFERRED** (allocated to a later phase by an approved decision). A DONE label is the implementation's
assessment of its own work at the database level. It is not a gate decision and does not close a finding:
closure is the independent Supervisor's call. Nothing here claims Phase 2 is approved.

### Supervisor remediation review — 2026-11-22

| Finding | Status | Evidence | Remaining boundary |
|---|---|---|---|
| H-01 — RLS fail-open for unclassified roles | **REMEDIATED / VERIFIED** | Restrictive fence, exact bypass/principal-required catalogs, table+column+PUBLIC+indirect grant audit, `pg_read_all_data` / `pg_write_all_data` controls, ISO-RLS-C3..C16; Actions 45030847506 step 15 | Superuser/Platform Security trust root and production verifier PS-1..PS-5 remain separate gates |
| H-02 — direct published PlanVersion INSERT | **REMEDIATED / VERIFIED** | PLN-H2-01..03; normalized and legacy direct published inserts rejected; publication only guarded normalized draft→published; Actions 45030847506 step 16 | No production runtime write path |
| H-03 — PlanItem/publication race | **REMEDIATED / VERIFIED** | WS-PLN-PUB-RACE-01..11; item-first/publisher-first commit and rollback cases, bounded lock/statement timeouts; Actions 45030847506 step 16 | Applies to draft SQL and synthetic DB only |
| H-04 — actor/target checks without complete transition graph | **REMEDIATED AS FAIL-CLOSED / VERIFIED** | Empty base `plan_item_transition_rules`; exact edge check; test-only synthetic rules; PLN-H4-01..04; Actions 45030847506 step 16 | Exact production transition graph requires Product Owner decision |

### HIGH
| Item | Status | Evidence / what remains |
|---|---|---|
| WS-DOM-01 assessment total/response/score integrity | **DONE** (schema) | Version question membership and order are authoritative; responses bound by composite FKs; attempt policy = published policy. AVQ-01..22, ASM-01..30, ASM-RACE-01, WS-ROLE-16/17. The database still does not compute or validate a score — that is by design, per the assessment contract. |
| WS-DOM-02 competing membership role sources of truth | **PARTIAL** | Governance event ledger, receipt command boundary and role catalog tests exist (offered as evidence 2026-11-13). No new work in this batch. The Supervisor has not judged this sufficient. |
| WS-DOM-03 guardian relationship/permission auditability | **DONE** (schema) | Append-only link/permission events, projection change refused without its event, effective view. GDN-01..18. Guardian legal authority remains Q-007 and is not encoded. |
| Transfer approval revoked/replacement approvals as immutable events | **DONE** (schema) | Immutable approval events plus separate revocation events, one current per kind, serialized on the case row. APR-01..13, APR-RACE-01, SEP-01..29. |
| Contact-change schema/function/tests | **DONE** (schema) | One-time proof, atomic command, audit, outbox, separate owner/executor/verifier roles. CC-01..42, CC-RACE-01. Concurrency against HMAC rotation and against an ownership switch is **NOT RUN**. |
| Durable Saga event schema and command/outbox/inbox boundaries | **PARTIAL** | Schema reconciled and per-recipient delivery implemented after C-01: `cp_12_saga_outbox_delivery.sql`, `workspace_inbox_projection.sql`, SAGA-01..11, SAGA-R01..R32, INB-01..22. The **service-level** behaviour of contract section 10 is still **NOT IMPLEMENTED** (snapshot consistency, destination staging, real process crash, partition, chaos, outage/restore/failover, projection-drift repair, quarantine resolution). The inbox application path is **fail-closed** pending a verified transport (H-05). |
| Source Workspace write freeze and in-flight write drain (database half) | **DONE** (schema), **corrected twice** | `workspace_transfer_freeze.sql`: durable freeze record, write-barrier trigger on all **32** student-scoped tables, in-flight transaction barrier with a recorded `barrier_watermark_txid`, token-bound idempotency, pre-switch-only unfreeze, and a permanent fence applied by the inbox projection after the switch. FRZ-01..FRZ-43 and WS-FRZ-BARRIER-01..04 in two modes; the race test's sensitivity was verified (without the barrier the `nofk` mode fails). **Two corrections are part of this row's history and must not be read out of it:** Batch 5 found five per-student tables reached only indirectly and unprotected (26 → 31 tables), and **Batch 8 found the barrier read only the NEW side of an `UPDATE`**, so a frozen student's rows could be moved to another student or orphaned with `student_id = NULL` — demonstrated as accepted, now refused on both sides with a forward-only ownership key (FRZ-38..FRZ-43; the pre-fix function fails FRZ-38). |
| Source Workspace write freeze beyond the database (API, workers, imports, exports, file mutations) | **NOT IMPLEMENTED** | Those surfaces do not exist in this repository (`backend/`, `frontend/`, `scripts/`, `tests/` contain only `.gitkeep`), so they cannot be frozen by Phase 2 work and are not claimed. What is claimed is that any surface reaching this database is refused. The outstanding-work count is reported by the caller, not observed by the database. |
| Freeze duration, drain timeout and acceptance thresholds | **DEFERRED** | OQ-E leaves these to measured design. Nothing is invented or enforced; the freeze has no timeout. |
| Freshness of every time-bounded security decision | **DONE** (schema) | A defect of this class was found three times and each instance was demonstrated before being fixed: the proof-receipt validity window (a receipt was consumed and applied four seconds after expiry), the one-time contact-change proof window, and `guardian_permissions_effective`, which is the guardian authorization read shape. All now read `clock_timestamp()` after the relevant row lock. RC-FRESH-01..04, CC-FRESH-01..03, CLK-01..03, each shown to fail against the pre-fix code. |
| Guard against reintroducing a transaction-start clock | **DONE** (schema) | CLK-01 scans the catalog — every SECURITY DEFINER function and every view — and fails by name, with one reviewed allowlist entry that writes a stored value and decides nothing. CLK-02 separately pins the previously defective windows. |
| Clock-skew tolerance for time-bounded decisions | **DEFERRED** | PS-5. No tolerance is implemented anywhere; comparisons are exact. |
| Authenticated private service channel for the verifier/adapter | **NOT IMPLEMENTED** | PS-6. No transport exists. `verifier_rt` was tested to hold no receipt-consumption and no governance-command privilege. |
| End-to-end revocation freshness across service handoffs | **NOT IMPLEMENTED** | PS-8. The database records revocation; there are no API, export, worker or notification services to propagate it to, so no freshness claim is made. |
| Student Credit ledger: non-negative spendable balance | **DONE** (schema) | Previously **untested** despite the guard existing — CRD-27 covered the balance identity, which is a different claim. Now CRD-39/40/41 serially (including a control that exactly the available balance IS accepted) and WS-CRD-LAST-01..05 concurrently. The no-lock control measures `debits=2 ledger=-1 available=-1`. |
| Student Credit ledger: compensating reversal tied to the original debit, student and entitlement | **DONE** (schema) | A defect was found and fixed: a reversal naming a different student was accepted. CRD-42/43. Bounded in severity by CRD-46c/46d, which prove no application role can write the ledger directly. |
| Student Credit ledger: one authoritative insert guard | **DONE** (schema) | The guard was defined twice, the weak copy reachable by loading the schema draft alone. Consolidated into the file that creates the table; CRD-47 asserts from the catalog that exactly one exists and still carries the balance check, student binding and row lock. |
| Student Credit ledger: append-only on UPDATE as well as DELETE | **DONE** (schema) | CRD-05 covered DELETE only. Now CRD-44/45. |
| OQ-CRD-2 disposition of a reserved entitlement after its period ends | **DEFERRED** | Undecided. No expiry, extension, forfeiture or automatic return is implemented; `expired_reserved_entitlements` only shows the affected rows. Decision request in `UNRESOLVED_ITEM_REGISTER.md`. |
| Workspace lifecycle and capacity archive/reactivation transitions | **DONE** (schema) | Archive with atomic capacity release and the reactivation command with counselor validation. ARC-01..17, CRD-01..31, WS-REACT-RACE-01, WS-CRD-LOCK-01/02. Suspension capacity treatment remains an open policy question. |
| Final-capacity-slot concurrency test | **DONE (schema/test)** | `workspace_capacity_last_slot_race.sh`; WS-CAP-RACE-01 passed in fresh GitHub Actions run 45030847506 on PostgreSQL 16.16; exactly one enrollment wins the final active-student slot. |

### MEDIUM
| Item | Status | Evidence / what remains |
|---|---|---|
| Assessment definition/versioning | **DONE** (schema) | AVQ-01..22. |
| Per-subject exam results | **DONE** (schema) | **This row previously said NOT IMPLEMENTED and that was stale**, which understated the project to a reviewer. `workspace_assessment_exam_draft.sql` implements `exam_definition_versions`, `exam_definition_version_subjects` and `exam_subject_results`, with composite foreign keys refusing cross-exam and cross-student subject rows declaratively, and a DEFERRABLE INITIALLY DEFERRED reconciliation trigger between the subject rows and the aggregate. EXM-01..42. |
| Immutable published exam blueprint | **DONE** (schema) | A published `exam_definition_version` is immutable and undeletable, and publication is refused unless the per-subject counts add up to the exam's own count. EXM-08..15. |
| Test analysis versions | **DONE** (schema) | `test_analysis_versions` and `test_analysis_response_findings` are append-only, so a reclassification is a new version rather than a mutation of an immutable submitted response. EXM-36..41. |
| Scoring algorithm and version recorded in every policy snapshot | **DONE** (schema) | Previously a snapshot only had to be a JSON object, and `{}` published successfully, so a historical score was unattributable. Every snapshot must now name an `algorithm` and a positive integer `algorithm_version`. EXM-42 additionally asserts the predicate is never NULL, because a CHECK constraint passes on NULL and the first version of it did return NULL for `{}`. |
| Which scoring algorithm names are permitted | **DEFERRED** | OQ-ASM-2, raised by this work. The shape is enforced; the value set is deliberately not. |
| Custom error taxonomy (counselor-defined error types) | **NOT IMPLEMENTED** | `test_responses.error_reason` carries a fixed enum plus a free-text `custom_error_reason`. There is no taxonomy table, so custom reasons are not reusable, countable across responses, or reportable as categories. Named in the assessment contract; still absent. |
| Rank, percentile and cohort comparison of exam results | **NOT IMPLEMENTED** | They need a cohort this Workspace may not hold, and no rule for it exists. Not claimed. |
| Scoring formulas, rounding and score validation | **NOT IMPLEMENTED, by design** | The database stores and compares snapshots. It never computes or validates a score, and no row in this table should be read as saying otherwise. |
| Curriculum Subtopic level | **DONE** (schema) | `subtopics` under `topics`, ordered within the parent, archivable rather than deletable. CUR-01..CUR-10. Scope decided by the Product Owner on 2026-11-15: subtopics only. |
| Curriculum Book/Edition, successor mapping, content ownership, subtopic mastery | **DEFERRED to Phase 7** (Product Owner, 2026-11-18, Option A; `LATER_PHASE`) — NOT IMPLEMENTED by decision; four governance questions still open. Earlier text: | WS-DOM-05. The contract is DRAFT / NOT APPROVED and its own open decisions cover these. Consequently the contract's isolation tests (platform content read-only to Workspace runtime; Workspace A cannot reach Workspace B's custom curriculum) **cannot** be run and are not claimed. |
| Deletion behaviour preserves educational history | **DONE** (schema) | There is no `ON DELETE` action anywhere in the Workspace schema, so every foreign key restricts. CUR-09 now asserts this from the catalog; previously it held by convention with nothing checking it. |
| Normalized PlanItem | **PARTIAL — schema/guard mechanics implemented and CI-verified; WS-PLAN-01 not approved as a whole.** Six typed sources, immutable published versions, append-only status events, actor authorization and audit remain. A2/B1/C1/D1/E1 enforced; H-02 direct published inserts and H-03 publication/item races (both lock orders + both rollbacks) pass Actions run 45030847506 step 16. H-04 now requires exact `(actor_kind, from_status, to_status)` rule; base `plan_item_transition_rules` is EMPTY and fail-closed. Disposable tests seed synthetic edges only; exact graph is a Product Owner open decision. Runtime status-write path remains closed; no scheduling logic. |
| Transfer write barrier is asserted on BOTH SIDES of an UPDATE | **DONE** (schema) | **Batch 8 defect, measured before it was fixed.** The barrier resolved the owner from `NEW` on `UPDATE`, so an `UPDATE` rewriting the ownership column was judged by its destination: with the student frozen, moving a file or a study session to another student, and setting the owner to `NULL`, were all **accepted**. Rows could therefore leave a frozen student's dataset after the barrier watermark, which is the property the Saga contract depends on. Now both sides are asserted and the ownership key is forward-only for every writer (`NULL → value` only). FRZ-38..FRZ-43; reverting the function fails FRZ-38. |
| Transfer write barrier covers per-student tables reached INDIRECTLY | **DONE** (schema) | Five tables were unprotected because the barrier's table list came from a column scan: `student_plan_versions`, `test_responses`, `guardian_permissions`, `guardian_link_events`, `guardian_permission_events`. Coverage 26 → 31. FRZ-01b audits indirect reachability from the catalog and fails by name; FRZ-18b/18c test the new paths behaviourally. |
| No SECURITY DEFINER function owned by a superuser | **DONE** (schema) | `receipt_consume_grant_guard()` **was** owned by `postgres` because it is created before the role that should own it exists. Reassigned; search_path tightened to `pg_catalog, pg_temp`. SEC-01 asserts it for every definer function and fails naming any offender. |
| SECURITY DEFINER hygiene: pinned search_path, NOLOGIN owners, no PUBLIC execute | **DONE** (schema) | SEC-02, SEC-03, SEC-07. Two functions still carry `public` on their path; SEC-02b measures that no application role can `CREATE` there, so it is not exploitable, and SEC-02c tracks it as hardening rather than claiming it fixed. |
| Role and grant hardening | **DONE** (schema) | No application role owns a table (SEC-04); no Workspace role holds superuser/createrole/createdb/bypassrls (SEC-05); `PUBLIC` holds no table privilege (SEC-06); every table has a primary key (SEC-09). |
| Counselor-to-counselor isolation within one Workspace | **PARTIAL — schema-level fence verified; production authorization not approved.** Test-only principal assertion; RLS ENABLE+FORCE; mandatory RESTRICTIVE principal fence; exact bypass allowlist; unknown roles and PostgreSQL broad-data roles remain constrained. ISO-RLS-C3..C16 and Actions run 45030847506 step 15 pass. PS-1..PS-5, M-01 deployment separation, student read scope, worker identity and manager permission vocabulary remain open. |
| Object-level authorization, IDOR, uniform 404 | **NOT IMPLEMENTED** | API properties; no API exists in this repository. Not testable here and not claimed. |
| Background-job tenant context; file and notification ownership | **PARTIAL** (ownership only) | No background jobs, no file subsystem, no notification subsystem exist; the worker role's grants are tested but nothing runs as it. What Batch 8 did add is **ownership integrity** for the two tables: a file or notification row is bound to its student, that binding is forward-only, and both are inside the transfer write barrier. Job tenant context remains NOT IMPLEMENTED. |
| Trigger-based guards versus the table owner and superuser | **LIMITATION, RECORDED** | Every guard is a trigger or a CHECK, and a table owner can disable triggers. SEC-08 asserts the limitation is real rather than claiming containment, so the threat model stays honest. Containing these identities is operational credential control, outside the database. |
| Contact change serialized against HMAC rotation | **DONE** (schema) | Designed in and documented, but never executed until Batch 7. CID-RACE-A1/A2/A3: the contact change's `FOR SHARE` on `identity_write_gate` blocks `begin_identity_hmac_rotation()`, and a contact change during maintenance mode is refused. Removing the gate lock fails the race. |
| Contact change serialized against the ownership switch | **DONE** (schema) | CID-RACE-B1/B2/B3: the contact change's `FOR UPDATE` on `student_ownership` blocks `switch_student_ownership()`; the generation then advances, ownership moves, and a contact change citing the pre-switch generation is refused. Removing the ownership lock fails the race. |
| No plaintext contact and no key material in the database | **DONE** (schema) | CID-01..CID-03: no text column can hold a plaintext contact; fingerprints are pinned to 32 bytes and the contact is bytea ciphertext; the key-version tables carry no bytea and text only as an opaque `*_ref` or a CHECK-pinned enum. `key_manager_ref` is a non-secret KMS identifier, the external-custody shape PS-3 should use. |
| Key-version transitions and contact collision handling | **DONE** (schema) | CID-04 exactly one active HMAC key version, a second refused. CID-05 global identity unique per `(key_version, fingerprint, grade)` across `active` and `transfer_pending` claims — so two students may share a fingerprint in `student_contact_index`, but not live claims on it in the same grade under one key. |
| No secret material in the repository | **PARTIAL** (repository check, NOT implementation evidence) | **Failed in CI at `fc3416ed`** (two fixture findings, the local run having been made before `git add`). Corrected: fixtures replaced and marked under a per-line, contact-only exception; history **content** scanning implemented (1,361 blobs; 110 contact-shaped fixture strings excepted individually by hash; no credential, key or PEM block in history); a Batch 7 allowlist defect fixed ("synthetic" anywhere on a line exempted every pattern); shallow clone fails closed; CI checkout `fetch-depth: 0`. Local PASS and GitHub Actions success at `467a029`. Historical fixtures remain in history (REPO-HIST-CONTACTS, Product Owner). A pattern scan proves the absence of shapes, not of secrets. |
| Production key management: algorithm, key policy, rotation schedule, revocation source | **DEFERRED** | PS-1..PS-4. Rotation is tested as a mechanism only. No algorithm, policy, schedule or revocation source is invented, and no cryptographic strength is claimed. |
| Rotation recovery across a process crash | **NOT IMPLEMENTED** | Needs a process; none exists. What is covered is that a refused contact change leaves the proof unconsumed with no command reservation and no audit row. |
| Curriculum subtopics, normalized planning constraints, explicit PlanItem relation | **PARTIAL** (draft schema, synthetic) | Subtopics: CUR-01..10. PlanItem: `workspace_plan_items_draft.sql` per decision WS-PLAN-01/B — implemented at `d75d039`, reviewed NOT ACCEPTED, F-01..F-04 remediated at `8df7d5e`; F-05 ACCEPTED — ARCHITECTURE REVIEW LEVEL at `fe08a77`; PLN-C1..C4, PLN-01..80, WS-PLN-RACE-01..03, PLN-M01..M08, F05-00..23, F05-BOOT-01..20. PO decisions A2/B1/C1/D1/E1 (2026-11-20) implemented under verified principals (PLN-A2*, PLN-D1*, PLN-E1*); WS-PLAN-01 NOT ACCEPTED pending independent review. No planning constraints or scheduling exist. |
| Activity taxonomy and class participants | **DONE** (schema) | Typed FK-backed sources, `class_participants`, `class_session_participants`. ACT-01..26. Class recurrence rules remain open. |
| Credit lifecycle: archive return, reserved entitlement, reactivation | **DONE** (schema) | CRD-01..38, WS-CRD-LOCK-01/02. The reversal window rule is approved and tested to the microsecond including equality at the deadline (OQ-CRD-1 RESOLVED 2026-11-14). The entitlement **period source** is **NOT IMPLEMENTED** and the production path is fail-closed (H-02, OQ-CRD-3 OPEN). What happens to a reserved entitlement after its period ends is **NOT IMPLEMENTED** (OQ-CRD-2 OPEN). |
| Credit purchase, renewal, refund execution and payment reconciliation | **DEFERRED** | Phase 21/22 per PD-2026-11-13-F. |
| File scan/quarantine, notification generation and permission fencing | **PARTIAL** (schema) | Batch 8, OPS-01..OPS-24, OPS-45/46. Enforced: file facts immutable, `quarantined → available → archived` forward-only with `archived` terminal, no file or notification deletion; notification recipient restricted to an active member, the student the notification is about, or a verified guardian **of that student**; no plaintext contact in a payload at any depth; recipient/subject/payload immutable after writing; the transfer write barrier now covers notifications, which was impossible before the table named a student. **Not implemented:** the scan service that clears a quarantine, notification generation itself, and delivery-time re-authorization (OPS-NOTIF-DELIVERY). |
| Retention policy schema integration | **PARTIAL** (schema, fail-closed) | Batch 8, OPS-30..OPS-51. `retention_categories` + immutable `retention_policy_versions` (nine phase 1 categories, every one `needs_decision` with a NULL duration; `approved` impossible without duration, action, approval reference and effective date; status cannot be flipped by UPDATE), `retention_entity_types` giving the legal-hold polymorphic reference enforceable integrity, hardened holds, and `assert_destructive_disposition_allowed()` refusing on non-destructive action / unregistered type / missing target / live hold / no approved policy. **Q-020 is still what blocks everything destructive**, which is the contract's required behaviour rather than a workaround; no role may execute the gate or write a hold (OPS-DISP-AUTH, OPS-HOLD-AUTH). |

### Supervisor findings on head `8abbbe3` (remediation batch 2026-11-14)
| Finding | Status | Evidence |
|---|---|---|
| C-01 Saga delivery per recipient | **DONE** (schema) | `outbox_event_recipients`, delivery keyed `(event_id, workspace_id)`, completion only when all recipients acknowledge. SAGA-R01..R32. |
| H-01 archive clock read before the entitlement lock | **DONE** | Clock read after the lock; WS-CRD-LOCK-01/02, sensitivity verified against the pre-fix code. |
| OQ-CRD-1 exact boundary (Supervisor correction, 2026-11-14) | **DONE** | The approved rule is extracted into `credit_reversal_window_end()` / `credit_reversal_eligible()` and tested with explicit timestamps: deadline minus one microsecond eligible, the exact deadline eligible, plus one microsecond ineligible, monotonic across the window, identical in four time zones, and no second copy of the interval inside the command. CRD-32..CRD-38. The command's post-lock `clock_timestamp()` read and WS-CRD-LOCK-01/02 are unchanged. |
| H-02 entitlement period source | **DONE as fail-closed**; the source itself is **NOT IMPLEMENTED** | Production path refuses (OQ-CRD-3); caller-supplied period is synthetic-only and role-gated. CRD-28..31, WS-ROLE-18/19. |
| H-03 outbox acknowledgement authorization | **DONE** | Declared-recipient check, send-before-acknowledge check, per-recipient idempotency and conflict refusal. SAGA-R01..R03, R11, R12. |
| H-04 activation timestamp and lock order | **DONE** | One authoritative timestamp read after the locks, used for enrollment start, entitlement and audit. CRD-01/01b. |
| H-05 inbox trust boundary | **DONE as fail-closed**; verified transport is **NOT IMPLEMENTED** | Production entry point refuses (OQ-SAGA-1, PS-1..PS-4/PS-6); synthetic path role-gated. INB-02a/b/c/d. |
| H-06 / M-01 reactivation counselor and idempotency | **DONE** | Counselor role required, counselor bound to the command and compared on replay. CRD-07a/b/c, CRD-11b, CRD-12b. |

## 4. Later-phase implementation gates (not Phase 2 implementation claims)

The following are required before their corresponding production features/pilot, but Phase 2's responsibility is to define the contract and tests:
- production KMS/HSM, key custody, cryptographic verifier and backfill/revocation drills;
- HTTP API authentication/RBAC/object authorization and E2E IDOR/file/export/notification tests;
- durable Saga workers, the freeze/drain **controller** (the database freeze boundary it drives is implemented; the controller, its outstanding-work accounting and its timeouts are not), snapshot/staging service, crash recovery;
- production Workspace credentials, secret rotation/revocation and pool eviction;
- independent backup/restore, failover, split-brain, RPO/RTO and measured capacity on the selected target;
- legal/tax/privacy approval of numeric retention and Iranian guardian/age rules;
- D-014 written Product Owner authorization before any real student data.

These items must remain visible as downstream gates; their absence must not be described as production readiness.

## 5. Product Owner / legal decisions that must remain explicit

- Q-007: detailed Iran age/guardian/evidence/dispute/student-rights matrix.
- Q-020 / OQ-F2: numeric category retention periods, named legal/privacy reviewer and deletion approver.
- OQ-D: RPO/RTO, replication mode, failover mode and split-brain authority.
- OQ-E: freeze/drain timeout and recovery thresholds.
- OQ-B: production KMS/HSM and key custody implementation details.
- Conflict-of-interest policy if one principal holds multiple transfer approval roles.
- Exact activity/assessment taxonomy where product behavior is not already determined.
- Credit purchase/refund/renewal and cancellation policy values.

No value may be invented to make the checklist appear complete.

## 6. Integration safeguards

- Work only on the Phase 2 draft branch until a separately approved integration plan exists.
- Do not merge PR #12 or close PR #8–#11 without Product Owner authorization.
- Do not force-push/rebase the long-running branch without an explicit history-rewrite plan.
- Verify exact branch HEAD, base HEAD, compare status and CI on the final SHA.
- Keep D-014 synthetic-only; do not start Phase 3.
- A green mergeability flag is not a phase approval.


## 6A. Newly added contract coverage (2026-11-10)

- `control_plane/CONTACT_CHANGE_REVERIFICATION_CONTRACT.md`
- `transfer/TRANSFER_APPROVAL_IDENTITY_AUTHORITY_CONTRACT.md`
- `transfer/TRANSFER_SAGA_OUTBOX_INBOX_RECOVERY_CONTRACT.md`
- `workspace/WORKSPACE_GOVERNANCE_EVENT_CONTRACT.md`

These contracts improve design completeness but do not satisfy schema, executable-test, CI or runtime evidence rows above. The approval SQL's current non-empty-reference checks remain insufficient; the Workspace governance event model is not yet implemented. Exact branch SHA and CI must be refreshed after all later SQL/test changes.

## 7. Gate rule

Phase 2 may be recommended **APPROVED** only when all Phase 2 design/schema requirements are closed, every unresolved decision is either approved or explicitly deferred with a named downstream gate, the draft schema/test tree passes fresh CI on the exact final SHA, PR/canonical-document reconciliation is complete, and the independent Supervisor review has no open HIGH design/schema findings.

If a bounded set of non-critical design details remains but is explicitly constrained and does not block the next phase, a **CONDITIONAL PASS** may be considered. Any unresolved HIGH security/data-integrity/tenant-boundary defect means **NOT READY**.

**Current status: NOT READY.**


## 8. Open decision register

The consolidated list of unresolved Product Owner and specialist inputs, with recommendations and required authority, is maintained in `PHASE2_OPEN_DECISIONS.md`. This register does not make decisions or assign unapproved values.


## 9. Educational domain contract references

The required educational-domain design targets are now explicit:
- `workspace/ASSESSMENT_DOMAIN_CONTRACT.md` — assessment versioning, response integrity, deterministic scoring and per-subject exam results.
- `workspace/DETERMINISTIC_PLANNING_DOMAIN_CONTRACT.md` — normalized planning inputs, explicit PlanItems, replayability and explainability.
- `workspace/CURRICULUM_DOMAIN_CONTRACT.md` — complete curriculum hierarchy, ownership, versioning and mastery evidence.

The current Workspace SQL skeleton has not yet been reconciled with these contracts; design documents do not close WS-DOM findings.


## 10. Additional Workspace domain contracts

- `workspace/ACTIVITY_CLASS_DOMAIN_CONTRACT.md` — activity taxonomy, class participation, recurrence, attendance and assignment scope.
- `workspace/STUDENT_CREDIT_COMMERCIAL_LIFECYCLE_CONTRACT.md` — CRD vs fiat separation, payment-to-credit reconciliation and commercial lifecycle.
- `workspace/CAPACITY_LIFECYCLE_CONTRACT.md` — capacity dimensions, reservations, archive/reactivation and transfer capacity coordination.

The current SQL skeleton does not implement these complete lifecycles; all open product values remain explicit in `PHASE2_OPEN_DECISIONS.md`.


## 11. Governance event/projection status — 2026-11-10

The Workspace event ledger now has a draft transactional projection materializer for membership roles, permissions and lifecycle. Its dedicated non-login owner and least-privilege grants are part of the provisioning draft. This is not a trusted authorization service and no application role is granted execute.

Exit criteria still require:
- cryptographic or otherwise independently verifiable authentication and authority assertions bound to actor, target, action, scope, policy and event;
- explicit role/permission grantability matrix and anti-self-escalation rules; **Product Owner policy decision now accepted 2026-11-10** in `workspace/PO_DECISION_ROLE_GRANTABILITY_MATRIX_2026-11-10.md`; enforcement, trusted adapter and executable tests remain NOT IMPLEMENTED;
- trusted API/service adapter and object-level authorization tests;
- concurrent revoke-vs-read freshness/linearization tests;
- guardian legal authority, per-child permissions and revocation semantics after Q-007 is resolved;
- fresh CI on the latest branch head.

Until these pass, WS-DOM-02/03 remain HIGH and the phase gate remains **NOT READY**.


### 11.1 Latest verification — 2026-11-10

CI run #519 passed all 13 PostgreSQL workflow steps on commit `d45753924513f9920f714b966361b9697e8264d5`. Governance projection and role-privilege assertions passed. This is evidence for the SQL draft only. The remaining exit criteria listed above are still open; WS-DOM-02/03 remain HIGH and the phase gate remains **NOT READY**.


### 11.2 Trusted governance assertion contract

`workspace/WORKSPACE_GOVERNANCE_AUTHORIZATION_ASSERTION_CONTRACT.md` is now the required design target for authenticated governance commands. It does not close the gate: signature/issuer verification, proof receipt storage/consumption, role grantability policy, trusted adapter, API tests and guardian legal policy remain unimplemented. Application EXECUTE remains prohibited.
