 > **HISTORICAL / NON-NORMATIVE:** D-020 resolved Q-022 by selecting Alt-5 hybrid isolation cells. This Q-019 mechanism evaluation is historical comparison material only; Option C/Option D language and the review-time gate statements below are not current acceptance criteria. D-024 approved the provider-neutral Phase 1 design/documentation gate on 2026-10-24. Q-023 remains a pre-hosting gate; Phase 2 remains unauthorized and real student data remains prohibited under D-014. The active design is `TENANT_ISOLATION_DESIGN.md`; the active test catalog is `TENANT_ISOLATION_TEST_CONTRACTS.md`.

---

# Q-019 — Technical Evaluation of Tenant-Context Mechanisms (Options A, C, D)

Phase: 1 (design). Status: TECHNICAL EVALUATION FOR INDEPENDENT REVIEW. Owner decision D-016 (2026-10-17) records Option C as the preferred design direction, subject to independent design review, and records Option D as NOT selected. This document does not itself approve the design or the runtime mechanism. Q-021 separately tracks the Product Owner's explicit disposition of the K-L-N and K-O residual risks. Nothing here is tested; every statement about PostgreSQL behavior must be verified on the target PostgreSQL version (15 or later) in a later phase.

---

## 1. Question Being Answered

Under which conditions can an attacker obtain data of tenant B while the system is operating on behalf of tenant A, and which mechanism removes or reduces each of these paths?

Scope: threat T4 decomposed into T4a (SQL injection on a tenant connection), T4b (application process compromise), T4c (database credential theft), as defined in `TENANT_ISOLATION_DESIGN.md` §1.4. Also T4d (compromise of the owner or migration role) is included for completeness, since no option is complete without it.

---

## 2. Attacker Models

| Model | Capability | Typical source |
|---|---|---|
| AM1 | Arbitrary SQL as the tenant's runtime connection (no code execution in the application) | SQL injection in one request path |
| AM2 | Code execution inside the application process | RCE, dependency compromise, debugger access |
| AM3 | Runtime database credentials of one tenant, used from outside the application | Leaked config, backup, log |
| AM4 | Runtime database credentials of many tenants | Compromise of secret store or of the process that holds all credentials |
| AM5 | Owner or migration role credentials | Compromise of the migration pipeline |

Assumed NOT available to attacker in any model: superuser credentials. If superuser is compromised, no option in this document provides isolation.

---

## 3. Mechanisms Compared

- **Option A (D-009 as is):** RLS policies read `current_setting('app.current_tenant_id')`, set per transaction by the application with `set_config(..., true)`. The runtime role can set this value freely.
- **Option C (per-tenant database principals):** Each tenant has its own login role. Policies identify the tenant from `current_user` through a mapping table that only the owner role can write. The application selects the connection for a request from the authenticated principal before sending any SQL. No policy reads a GUC.
- **Option D (signed context token through a SECURITY DEFINER function):** Only a verification function owned by a non-runtime role can write a context row, after verifying a short-lived signed token. Policies read the context row through a helper. The verification key is stored in the database and readable only by the owner role.

---

## 4. Forging Paths Per Option

### 4.1 Option A

| Attack | Path | Result |
|---|---|---|
| AM1 | `SELECT set_config('app.current_tenant_id', '<B>', true); SELECT * FROM student;` | **Succeeds.** The policy trusts a value the attacker controls. |
| AM2 | Same as AM1 from application code | **Succeeds.** |
| AM3 | Connect with runtime credentials, set the variable, query | **Succeeds** for every tenant, because one login reaches all tenants. |
| AM4 | Same | **Succeeds**. |
| AM5 | Owner role bypasses RLS unless FORCE is set; with FORCE, owner queries are still subject to the same GUC | Depends on FORCE and on owner not being used for runtime (R-DB-02). |

Conclusion: Option A provides defense against application defects only (T1, T2, T3 under §1.2 of the design). It provides no boundary against AM1 to AM4.

### 4.2 Option C

| Attack | Path | Result |
|---|---|---|
| AM1 | Injected SQL on tenant A's connection runs `SET ROLE tenant_b_role` | **Denied** when no membership exists. PostgreSQL requires the session role to be a member of the target role, or a superuser, for SET ROLE. Verify by TI-CONN-01. |
| AM1 | Injected SQL runs `SET SESSION AUTHORIZATION tenant_b_role` | **Denied** for a non-superuser (PostgreSQL requirement). Verify by TI-CONN-01. |
| AM1 | Injected SQL reads the mapping table to find other tenants, or writes to it to remap itself | **Denied** if the mapping table has no write privilege for tenant roles and its read policy returns only the caller's row. Verify by TI-CONN-02 (membership) and TI-CFG-04 (policy set on the mapping table). |
| AM1 | Injected SQL reads shared tables without tenant filter | **Filtered** by policies keyed on `current_user`. Verify by TI-CFG-12 and TI-CONN-01. |
| AM1 | Injected SQL uses PUBLIC privileges to reach objects of other roles | **Denied** only if PUBLIC privileges on schemas and tables are revoked. This is verified by TI-CFG-14 (added in Revision 6). |
| AM2 | Application process holds connections or credentials for many tenants and issues queries for a forged tenant | **Not prevented.** Routing is in the application. Option C reduces the damage of a single compromised request path, not of the process. |
| AM3 | Use tenant A's login from outside | **Limited to tenant A.** |
| AM4 | Use credentials of many tenant logins | **Not prevented.** |
| AM5 | Owner role changes the mapping table or grants membership | **Not prevented by Option C.** Owner-role protection is an operational control (R-DB-02, separation of migration pipeline). |

Conclusion: Option C turns the tenant identity into a database authentication fact (`current_user`) that SQL inside a session cannot change without membership or superuser. It removes the value the attacker needs to forge in AM1. It does not cover AM2, AM4 or AM5.

Specific design requirements that come with Option C:
1. Mapping table `tenant_role_map(role_name, tenant_id)` owned by the owner role; `app_*` roles have SELECT only, filtered to the row whose `role_name = current_user`.
2. Policy predicate: `tenant_id = (SELECT tenant_id FROM tenant_role_map WHERE role_name = current_user)`, reviewed for performance (index on role_name).
3. No tenant role is a member of another tenant role or of any platform role (TI-CONN-02).
4. PUBLIC privileges revoked on the schema and all tenant objects (configuration requirement, verified by TI-CFG-14).
5. Pool routing: the connection is chosen by the authenticated principal's tenant before SQL (TI-CONN-03).

### 4.3 Option D

| Attack | Path | Result |
|---|---|---|
| AM1 | Injected SQL writes the context table directly | **Denied** if the runtime role has no INSERT, UPDATE or DELETE on it. Verify by TI-CTX-15. |
| AM1 | Injected SQL calls the verification function with a forged token | **Denied** if the signature check is correct and the key is not readable by the runtime role. Verify by TI-CTX-16. |
| AM1 | Injected SQL calls the function with a valid token for tenant A, then reads B | **Denied**; the context row binds to A. Verify by TI-CTX-17. |
| AM1 | Injected SQL obtains a valid token of tenant B from the database | **Denied** only if tokens are never stored in the database. This is a requirement, not a property of the mechanism. |
| AM1 | Injected SQL exploits the verification function (search_path hijack, dynamic SQL, unvalidated input, error messages revealing key material) | **Possible if the function has any defect.** The function is the single high-impact surface of this option. |
| AM1 | Token replay within its lifetime | **Possible** for the token holder. TTL limits the window. |
| AM2 | Process holds signing material or valid tokens for many tenants | **Not prevented**, same as Option C. |
| AM3 | Token of tenant A leaked (log, cache, browser) | **Possible** within TTL. Option D does not authenticate the database login to a tenant. |
| AM4 | Process obtains the key | **Not prevented.** |
| AM5 | Owner role reads the key or rewrites the function | **Not prevented by Option D.** Owner compromise defeats the option completely. |

Conclusion: Option D provides a boundary against AM1 only if the verification function is correct, the key is protected from the runtime role, and tokens are not leaked. The function is a SECURITY DEFINER surface (TI-BYP-03), and the key is stored in the same database that the attacker reaches under AM1. The boundary therefore depends on code correctness inside the database, which is harder to review and test than Option C's catalog and membership checks.

Specific requirements that come with Option D: see TENANT_ISOLATION_DESIGN.md §2.3.1 (six points), plus: `search_path` fixed inside the function; no dynamic SQL; input type and length checks; generic error messages; TTL in minutes; key rotation with key identifier; and the function owner is a non-login role.

---

## 4.4 Credential Classes (revision 8; independent review H-01)

### 4.4.1 Common scenario definitions
- **K-L-1:** one database login credential used by the application is stolen and used from outside the application.
- **K-L-N:** all database login credentials used by the application are stolen.
- **K-T:** a tenant-context token (Option D only) is stolen or replayed.
- **K-S:** the token signing key (Option D only) is compromised.
- **K-O:** an owner, migrator or equivalent privileged role credential is compromised.

The stolen secret differs by design, and this is stated explicitly:
- Option A: one shared runtime login. K-L-1 and K-L-N both mean that login.
- Option C: one login per tenant. K-L-1 means one tenant's login; K-L-N means all tenant logins.
- Option D: one shared runtime login (as in A) plus tokens. K-L-1 and K-L-N mean the same login, and no tokens are included in the theft.

### 4.4.2 K-L: what a stolen login grants, per option

| Option | Stolen credential | Identity the credential grants | What the attacker can do | Reaches tenant B data? | Conditions the conclusion depends on | Status |
|---|---|---|---|---|---|---|
| A | Runtime login (K-L-1 = K-L-N) | Runtime role | Arbitrary SQL; sets `app.current_tenant_id` to any tenant; reads any tenant | **Yes** | None beyond the mechanism itself | **Expected residual in an unselected comparison; not owner-accepted** |
| C | Login of tenant A (K-L-1) | Tenant A role | Reads and writes tenant A rows only; cannot change its own role | **No** (for tenant B) | No membership to any other tenant or platform role (TI-CONN-02); no PUBLIC privileges on tenant objects (TI-CFG-14); mapping table not writable by tenant roles (TI-CFG-06, TI-CONN-02); no BYPASSRLS (TI-CFG-01) | Pass criterion (NOT-RUN): denied |
| C | Login of tenant A, attacker targets tenant B (K-L-1) | Tenant A role | Same as above; cannot reach B | **No** | Same | Pass criterion (NOT-RUN): denied |
| C | All tenant logins (K-L-N) | Every tenant role | Reads every tenant | **Yes** | Not preventable by this mechanism | **Expected residual; owner disposition pending Q-021; not accepted** |
| D | Shared runtime login, **without a valid token** (K-L-1 = K-L-N) | Runtime role | See 4.4.3 | **No** (zero rows) | Runtime role has no table privilege that bypasses the helper (TI-CFG-05, 06, 14); helper and verification function are correct (TI-BYP-03, function review); runtime role cannot read the key table; no tokens are stored in the database | Pass criterion (NOT-RUN): zero rows |

### 4.4.3 Option D: stolen shared login without a valid token (explicit assessment)
The attacker holds the runtime login and no tenant token. The assessment considers each route to tenant data:
- **Mint or obtain a valid token:** requires the signing key (K-S) or a token issued to a tenant (K-T). Neither is available from the runtime login, provided the key is not readable by the runtime role and tokens are not stored in the database. **Not reachable by K-L alone.**
- **Write a context row directly:** requires INSERT, UPDATE or DELETE on the context table. The runtime role has none (TI-CTX-15). **Denied.**
- **Read the signing key:** requires SELECT on the key table. The runtime role has none (TI-CFG-06). **Denied, conditional on that grant.**
- **Impersonate another tenant:** requires a context row for that tenant, which requires a valid token for it. **Denied.**
- **Call the verification function with forged input:** the function must reject it (TI-CTX-16). **Denied, conditional on the function being correct.** A function defect is a separate threat, not K-L.
- **Read policy-protected tables without a context row:** the helper returns NULL, so policies return zero rows (TI-CTX-01). **Zero rows.**

Conclusion: a stolen shared login under Option D does not reach tenant data by itself. The conclusion depends on the conditions listed in 4.4.2 and on the correctness of the verification function, which is not yet verified.

### 4.4.4 Comparison that must not be misread
- Under **C**, a stolen login is tenant-scoped. It reaches one tenant, and all tenants if every login is stolen (K-L-N).
- Under **D**, a stolen login reaches no tenant without a token, including under K-L-N. Its protection therefore depends on the token and key classes below.
- Under **D**, the token and key classes (K-T, K-S) replace the login class as the residual risk. Under **C**, no tokens exist, so K-T and K-S do not apply, and the residual risk stays with the login scope.
Neither option is stronger in all classes. This is a trade-off to be decided, not a ranking.

### 4.4.5 K-T (Option D only)
A stolen token grants the tenant named in the token, until expiry. It does not grant other tenants, because the token is bound to one tenant. Expected residual for the unselected Option D: the token holder can access that tenant within the TTL; this is not owner-accepted. Replay control (jti store, see §6.3) is not yet designed. Not applicable to Options A and C.

### 4.4.6 K-S (Option D only)
A compromised signing key allows minting a token for any tenant, and therefore reads of any tenant. It is not reachable from runtime SQL, but is reachable by anyone who can read the key store. Expected residual for the unselected Option D under HMAC with a database-resident key; not owner-accepted. With an asymmetric signature (§6.3, point 1), the database holds only the public key, so K-S inside the database yields no minting capability; the private key then sits outside the database, with the application-process exposure already recorded as T4b. Not applicable to Options A and C.

### 4.4.7 K-O (all options)
Compromise of the owner or migrator role can change policies, grants, mapping tables and functions, and can read any key stored in the database. This is an expected residual under all options; Product Owner disposition is pending Q-021 and it must not be described as accepted until recorded. This is a process control, not a database mechanism (Phase 3 and Phase 26).

### 4.4.8 Consistency with the adversarial contracts
- TI-ADV-02 covers K-L-1 and K-L-N with the same object (rows of tenant B) for every option (see its row in the contracts file).
- TI-ADV-04 covers K-T (Option D only).
- TI-ADV-05 covers K-S (Option D) and K-O (all options) as evidence contracts.
Each class is tested or reviewed separately. No result for one class is used to claim another.

## 5. Comparison Summary

| Criterion | Option A | Option C | Option D |
|---|---|---|---|
| AM1 SQL injection on tenant connection | Not blocked | Blocked for cross-tenant SQL (membership and mapping rules) | Blocked if function and key are correct |
| AM2 process compromise | Not blocked | Not blocked | Not blocked |
| AM3 one tenant's credentials | Not blocked (one login reaches all) | Limited to that tenant | Not limited (token-based); token leak exposes tenant for TTL |
| AM4 many tenants' credentials | Not blocked | Not blocked | Not blocked |
| AM5 owner compromise | Not blocked | Not blocked | Not blocked |
| Where the trust sits | Application values | Database authentication and catalog membership | Database function code and key |
| Main code surface to review | Repository and policies | Catalog configuration and routing | SECURITY DEFINER function, key handling, token format |
| Operational cost | Low | High: one login and one pool per tenant; provisioning on each tenant creation | Medium: key rotation, token issuance, function lifecycle |
| Testability (no environment-specific behavior) | High | High: catalog and connection tests | Medium: function-level adversarial tests required |
| Scale | Good | Limited by number of roles and pools (suitable for pilot scale; must be measured) | Good |
| Failure behavior | Fail closed on missing value | Fail closed: no matching mapping row returns no rows | Fail closed if function raises; must be tested |

---

## 6. Technical Recommendation (not a decision)

1. **Option A alone is not a boundary against AM1 and must not be described as one.**
2. **Option C is the Product Owner's preferred design direction (D-016), conditional on independent design review.** Reasons for the direction, as analysed above: its boundary is database authentication and catalog membership, which can be checked by configuration tests, and because it removes the attacker-controlled value that Option A and Option D both depend on. Option C's cost is operational and its residual risks (AM2, AM4, AM5) are stated.
3. **Option D is an alternative, but it is NOT SELECTION-READY** (§6.3). It cannot be selected until the design-critical points in §6.3 are decided and written. Its residual risk is concentrated in one database function and one key; for MVP this is a larger and less testable surface than Option C.
4. **A combination is not recommended for MVP**, because two boundaries double the review cost without closing AM2, AM4 or AM5.
5. **Three distinct gates apply, and they must not be conflated:**
   - (a) *Design direction and Phase 1 design approval:* owner decision on the preferred direction (D-016, recorded) plus independent review of the design document. Measured capacity and executed adversarial tests are NOT prerequisites here (D-015).
   - (b) *Implementation validation:* implementation of the chosen mechanism, execution of its contracts, and independent implementation review. Required before any pilot.
   - (c) *Real-data pilot authorization:* every D-014 condition, including measured pool and role limits on the D-011 host and written owner approval of the pilot gate.
6. **Required regardless of option:** PUBLIC privileges revoked on tenant objects; migration role separated from runtime; secrets kept out of the application process where possible (T4b controls, Phase 3 and 26).

This recommendation is for the independent reviewer. The Product Owner decides, and the decision is recorded in DECISION_LOG.md.

---

### 6.1 Separation of design selection and pilot validation (independent review C-01)

The review found a circular dependency: selection depends on adversarial tests and capacity measurements that are scheduled after Phase 1, while Phase 2 depends on Phase 1 approval. This revision separates the two kinds of criteria.

**Design-selection criteria (needed for Phase 1 approval and for the owner's choice):**
1. The mechanism is defined precisely enough to be implemented (for C: mapping table, membership rules, routing; for D: token format, function contract, key location).
2. Each attacker model (AM1 to AM5, and credential classes K-L, K-T, K-S, K-O) has a stated outcome with a stated reason.
3. Every residual risk is listed with its owner and the control that would reduce it.
4. Test contracts exist for the mechanism, with per-option expected results (TI-ADV-01, 02, 04 and TI-CONN or TI-CTX), in status NOT-RUN.

These criteria are met by documentation and can be reviewed without running any test.

**Pilot-validation criteria (required before any real student data, D-014; not prerequisites for Phase 1 design approval):**
1. Adversarial contracts run against the implemented mechanism, with results recorded.
2. Capacity of roles and connection pools measured on the D-011 host (see 6.2).
3. Independent review of the implementation.
4. Written owner approval of the Pilot gate.

Phase 2 may start after Phase 1 design approval, because Phase 2 implements the chosen mechanism and produces the evidence for the pilot criteria. Phase 2 does not itself authorize pilot use of real data.

**Readiness of each option against these criteria (revision 8):**

| Criterion | Option C | Option D |
|---|---|---|
| 1. Mechanism defined precisely enough to implement | **Met at design level.** Mapping table, membership rules, routing, PUBLIC revocation, provisioning lifecycle defined in §4.2 and §6.2 | **Not met.** Seven design-critical points open (§6.3) |
| 2. Attacker outcomes stated for each model and credential class | **Met** (§4.2, §4.4) | **Met**, but dependent on the open points (§4.3, §4.4.3) |
| 3. Residual risks listed with owner and reducing control | **Met** (§4.2, §5) | **Met** (§4.4.5 to 4.4.7) |
| 4. Contracts written with per-option expected results, status NOT-RUN | **Met** (TI-CONN-01 to 03, TI-ADV-01, 02) | **Met** (TI-CTX-15 to 18, TI-ADV-01, 02, 04) |
| Capacity | **ESTIMATE only, not measured** (§6.2). Pilot criterion, not design criterion | Not assessed (depends on token and function design) |

Result: Option C satisfies the design-selection criteria at design level and may be decided by the Product Owner on that basis, with the capacity estimate labelled as an estimate. Option D does not satisfy criterion 1 and is therefore not selection-ready.

### 6.2 Option C capacity — ESTIMATE — NOT MEASURED (independent review M-01; aligned with D-017, H-05)

**Status of this section:** `ESTIMATE — NOT MEASURED`. Every figure is a calculation from the assumptions listed. None is a measurement, and none establishes feasibility on the D-011 host.

**Adopted pilot configuration (D-017, primary assumptions):** direct PostgreSQL connections; bounded per-tenant pool of size 1 per tenant per application process; no pooler for the pilot.

**Assumptions:**

| ID | Assumption | Value used (primary) | Source |
|---|---|---|---|
| A1 | Pilot tenants (counselors) | 10 | Provisional cap (D-017), subject to capacity analysis and owner confirmation |
| A2 | Application worker processes | 4 | ASSUMPTION |
| A3 | Background worker processes | 2 | ASSUMPTION |
| A4 | Pool size per tenant per process (direct mode) | **1** | D-017 (primary). Size 2 is a sensitivity case only |
| A5 | Reserved administrative and operational connections | 10 | ASSUMPTION |
| A6 | PostgreSQL `max_connections` | 100 | PostgreSQL documented default. Pilot host value UNKNOWN, not measured |
| A7 | Transaction pooler server pool per tenant role | not used for pilot | Sensitivity only; transaction pooling deferred (D-017) |
| A8 | Memory per backend | not estimated | UNKNOWN, must be measured |

**Primary calculation (D-017 configuration):**
- Application pool connections = (A2 + A3) × A1 × A4 = (4 + 2) × 10 × 1 = 60
- Plus A5 = 60 + 10 = **70 connections**
- Against A6 = 100: within the default limit under these assumptions. Result (ESTIMATE — NOT MEASURED): **70 of 100 under these assumptions.** Memory per backend, CPU, and latency are not estimated.

**Sensitivity — pool size 2 (not adopted):**
- (4 + 2) × 10 × 2 + 10 = **130 connections**, which exceeds 100 under these assumptions. Pool size 2 is therefore NOT permitted for the pilot unless a measured limit on the target host shows it is feasible and the owner approves the change (D-017).

**Sensitivity — transaction pooler (not adopted for pilot):**
- A1 × A7 + A5 with A7 = 2: 10 × 2 + 10 = 30 server connections; with A7 = 1: 20. This is an analysis of an option deferred by D-017. It is not a pilot assumption and requires its own compatibility tests (TI-CONN and TI-CTX) before any use.

**Other capacity drivers (not quantified):**
- Roles and credentials: one login per tenant (A1 logins); grant entries scale with tables and privileges; must be measured on the actual schema.
- Background jobs and administrative access consume connections outside A2 to A5 unless reserved.
- Burst concurrency across tenants is not modelled.
- Memory per backend and per process is UNKNOWN and must be measured.

**Provisioning lifecycle (design point, not capacity):** a role is created with the tenant, disabled at suspension, and removed only under the retention checklist (design §5.5; DATA_RETENTION_SCHEDULE_DRAFT.md §4). Retention durations are not set (Q-020).

**Uncertainties and risks:**
- A1 to A5 are assumptions; the connection count scales linearly with A1, A2, A3 and A4.
- The estimate is not evidence that the host can carry the pilot.

**Fallback rule (D-016 point 8, D-017):**
- If measured capacity is below the requirement at the approved tenant cap, reduce the cap first. Do not use shared runtime roles as a workaround (D-016 point 7, prohibited).
- Pool size stays 1 unless a measured increase is approved.
- Transaction pooling requires its own compatibility evidence and a separate decision.
- Otherwise re-review the design (Option D remains NOT SELECTION-READY, §6.3).

**Requirement:** measurement on the target host (see TARGET_ENV_LOAD_TEST_PLAN.md) is a pilot-validation criterion (D-015, D-014 condition 3). No document may claim capacity is measured until a measurement exists.

### 6.3 Option D selection-readiness (revision 8)

**Classification: NOT SELECTION-READY, and NOT SELECTED (D-016).** The mechanism cannot be reconsidered until the points below are decided, written and independently reviewed. Per D-016 point 3, if reconsidered, asymmetric signatures are evaluated first, and the one-time versus reusable token decision and the `jti` policy must be explicitly decided.

| # | Design-critical point | Current state | Decision owner | Recommendation for review |
|---|---|---|---|---|
| 1 | Token signature: HMAC or asymmetric | OPEN | Product Owner, with architecture reviewer input | Asymmetric: the database holds only the public key; K-S inside the database then yields no minting capability. Cost: the private key sits in the issuing component, which is the application process (T4b exposure) |
| 2 | Signing-key storage and access model | OPEN; depends on point 1 | Product Owner and reviewer | Under HMAC, the key must be in the database and unreadable by the runtime role; under asymmetric, the public key only |
| 3 | Token format and replay control (claims, audience, expiry, jti) | OPEN. A jti store needs database state | Product Owner | Short TTL in minutes; a jti store makes replay control stronger but adds database state and must be decided |
| 4 | Context row lifecycle with pooling and transactions | OPEN. Interaction with transaction pooling (Q-016) not designed | Architecture reviewer | Row keyed to transaction and backend; removed at commit and rollback; must be tested under pooling |
| 5 | Policy helper and policy migration | OPEN | Architecture reviewer | Helper reads the context row and returns NULL when absent (fail closed); migration and performance to be written |
| 6 | SECURITY DEFINER function contract (inputs, `search_path`, no dynamic SQL, owner role, EXECUTE grants, error messages) | OPEN; to be written as a contract | Security reviewer | Fixed `search_path`; no dynamic SQL; generic errors; owner is a non-login role |
| 7 | Failure behavior for invalid, expired or unverifiable tokens | Partly defined (refuse, generic error); not contracted | Security reviewer | Refuse; no tenant data; denial audited where the audit path exists |

**Product Owner decisions needed before D can be selection-ready:**
1. Whether Option D is pursued at all, compared with Option C.
2. The signature algorithm (point 1), with the trade-off stated above.
3. Whether a jti store (database state) is acceptable for replay control (point 3).
4. Acceptance of the token replay window within TTL as a KNOWN-RESIDUAL, if no jti store is used.

**Consequence for §6.1:** Option D fails criterion 1. Phase 1 design selection must not treat Option D as selection-ready.

## 7. What Each Option Can Honestly Claim After Verification

| Option | Claim allowed after its tests pass | Claim NOT allowed |
|---|---|---|
| A | Application defects and missing filters are contained by RLS when context is correct (T2 class) | Any protection against AM1 to AM5 |
| C | Cross-tenant SQL from one tenant connection is denied at the role and mapping layer (AM1); a stolen login of one tenant reads only that tenant (K-L) | Protection against AM2, AM4, AM5, K-O, or theft of logins of many tenants; general "tenant isolation in production" |
| D | Cross-tenant SQL without a valid token is denied at the function layer (AM1); a stolen login alone returns no rows (K-L) | Protection against token leakage (K-T), key theft (K-S), owner compromise (K-O), AM2, AM4, or any function defect not covered by tests |

---

## 8. Evidence Required at Each Gate

The evidence below is grouped by the three gates in §6 point 5. Items in gate (a) can be satisfied by documentation and review. Items in gates (b) and (c) cannot be satisfied by this document.

| Gate | Item | Evidence | Status now |
|---|---|---|---|
| (a) Design direction and Phase 1 design approval | Owner decision on preferred direction | Entry in DECISION_LOG.md (D-016) | Recorded (Option C preferred; Option D not selected) |
| (a) | Design precision and internal consistency | Independent design review of this document and the Phase 1 documents | Pending supervisor review |
| (a) | Option D readiness | Seven points in §6.3 resolved and reviewed, if D is ever reconsidered | Not met (NOT SELECTION-READY) |
| (a) | Per-class outcomes stated for each option | §4.4 reviewed | Documented; reviewer confirmation pending |
| (b) Implementation validation | Chosen mechanism implemented and reviewed | Implementation review record | Not started (Phase 2 or later) |
| (b) | Chosen option's contracts executed | TI-CONN-01 to 06, TI-ADV-01 and 02 (Option C); TI-CFG-14; results recorded | NOT-RUN |
| (b) | Option D only, if reconsidered | TI-CTX-15 to 18, TI-ADV-04, function review, key storage review | SPEC-ONLY |
| (c) Real-data pilot | D-014 conditions 1 to 5 | Test evidence, blockers fixed, measured capacity, independent implementation review, written owner approval | Not met |

Statement: no test has been run, no capacity has been measured, and no implementation exists. Phase 1 design approval, if granted, does not satisfy any gate (b) or (c) item.

---

## 9. Open Items for the Reviewer (design review, gate (a))

1. Is the AM1 analysis of Option C correct for the target PostgreSQL version (SET ROLE and SET SESSION AUTHORIZATION rules, PUBLIC defaults)?
2. Is the Option C design (mapping table, membership rules, routing, lifecycle in design §5.5) precise enough to implement, as required by §6.1 criterion 1?
3. Are the residual risks AM2, AM4 and AM5 (and K-S, K-O where applicable) stated accurately and with owners?
4. Is the classification of Option D as NOT SELECTION-READY, with its seven open points, correct?
5. Is the capacity estimate correctly labelled ESTIMATE — NOT MEASURED, and does it avoid claiming feasibility? (Measurement belongs to gate (c), not to this review.)

