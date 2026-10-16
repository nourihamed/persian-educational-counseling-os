# Q-019 — Technical Evaluation of Tenant-Context Mechanisms (Options A, C, D)

Phase: 1 (design). Status: TECHNICAL EVALUATION FOR INDEPENDENT REVIEW. This document does NOT select a mechanism. Selection is the Product Owner's decision, to be recorded in DECISION_LOG.md after independent review (D-014). Nothing here is tested; every statement about PostgreSQL behavior must be verified on the target PostgreSQL version (15 or later) in a later phase.

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
2. **For the pilot, Option C is the technical candidate** because its boundary is database authentication and catalog membership, which can be checked by configuration tests, and because it removes the attacker-controlled value that Option A and Option D both depend on. Option C's cost is operational and its residual risks (AM2, AM4, AM5) are stated.
3. **Option D is an alternative** if the pool-per-tenant cost is found unacceptable at measured scale. Its residual risk is concentrated in one database function and one key; for MVP this is a larger and less testable surface than Option C.
4. **A combination is not recommended for MVP**, because two boundaries double the review cost without closing AM2, AM4 or AM5.
5. **Required before any selection is final:** measured pool and role limits on the pilot host (D-011); independent review of the chosen option; the adversarial contracts for that option run and their results recorded (see TI-ADV rules).
6. **Required regardless of option:** PUBLIC privileges revoked on tenant objects; migration role separated from runtime; secrets kept out of the application process where possible (T4b controls, Phase 3 and 26).

This recommendation is for the independent reviewer. The Product Owner decides, and the decision is recorded in DECISION_LOG.md.

---

## 7. What Each Option Can Honestly Claim After Verification

| Option | Claim allowed after its tests pass | Claim NOT allowed |
|---|---|---|
| A | Application defects and missing filters are contained by RLS when context is correct (T2 class) | Any protection against AM1 to AM5 |
| C | Cross-tenant SQL from one tenant connection is denied at the role and mapping layer (AM1, AM3 limited) | Protection against AM2, AM4, AM5; general "tenant isolation in production" |
| D | Cross-tenant SQL without a valid token is denied at the function layer (AM1); token-bound context | Protection against token leakage, AM2, AM4, AM5, or any function defect not covered by tests |

---

## 8. Required Evidence Before Selection Is Final

| Item | Evidence |
|---|---|
| Chosen option's sub-threat claims | TI-ADV-01 and 02 run for the chosen option, result recorded |
| Option C only | TI-CONN-01 to 03 run; PUBLIC privilege configuration test added and run |
| Option D only | TI-CTX-15 to 18 run; function review (search_path, dynamic SQL, input handling) recorded; key storage reviewed |
| Independent review | Reviewer's verdict on the selected option recorded in SUPERVISOR_REVIEW.md |
| Owner decision | Entry in DECISION_LOG.md |

None of these is complete at this revision. No test has been run.

---

## 9. Open Items for the Reviewer

1. Is the AM1 analysis of Option C correct for the target PostgreSQL version (SET ROLE and SET SESSION AUTHORIZATION rules, PUBLIC defaults)?
2. Is Option C's pool-per-tenant cost acceptable at pilot scale on the D-011 host? (Requires measurement, not decided here.)
3. Is Option D's function surface acceptable for MVP, given that it is harder to test?
4. Are AM2, AM4 and AM5 accepted as residual risks for the pilot, or does the owner require a control for them before real data (D-014)?
