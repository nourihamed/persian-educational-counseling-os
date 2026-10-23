# Emergency Stop and Rollback Runbook — DRAFT (pilot, not yet exercised)

Status: DRAFT. NOT EXERCISED. Every step is a plan. No step has been run in any environment. Exercising this runbook on the test environment is a pre-pilot requirement (load test plan L-11).

Purpose: stop all tenant access quickly and safely when a suspected cross-tenant exposure, data integrity failure, or capacity collapse occurs; preserve evidence; restore service only after isolation is verified.

## 1. Triggers (any one starts the runbook)
- Any report or observation that data of one tenant appeared in another tenant's response, export, file, notification or log.
- Connection exhaustion or sustained error rate above the threshold set in the load test plan.
- Failure of a tenant isolation test in the target environment.
- Loss of audit log writes.
- Suspected credential compromise (any tenant login, token, signing key, or owner/migrator credential).

Severity: S1 = cross-tenant exposure suspected; S2 = integrity or availability failure; S3 = suspected credential compromise.

## 2. Roles
- Incident lead: Product Owner, or a delegate named in writing before pilot.
- Technical lead: executes the technical steps.
- Recorder: keeps a timeline with timestamps (can be the technical lead's second person).

## 3. Steps — stop (target: minutes)
1. **Stop new access.** Put the application in maintenance mode at the edge (reverse proxy returns a static maintenance response). Do not delete anything yet.
2. **Disable tenant logins.** For S1 and S3: disable the login of every affected tenant role (for suspected exposure of a specific tenant, that tenant's role; for S1 with unknown scope, all tenant roles). Record the time.
3. **Terminate sessions.** Terminate backend sessions for the affected roles and the application role. Clear pooled connections on the application side (restart the application workers).
4. **Freeze background jobs.** Stop scheduled jobs and notification senders so no further messages are sent.
5. **Revoke active tokens and sessions** in the application store (where tokens exist). If the signing key is suspected (Option D only, not selected), treat as S3 and rotate; not applicable to the current pilot direction.
6. **Stop writes if integrity is in doubt.** For S2 with corrupted data, make the database read-only (revoke write privileges on tenant tables from the application role) rather than dropping anything.

## 4. Steps — preserve evidence (before any restore)
1. Take a logical and physical snapshot of the database and the file store, with checksums, labelled with the incident id.
2. Copy audit logs, application logs and host metrics for the incident window. Logs must not contain secrets; if they do, record it as a finding.
3. Record the current role list, grants, policies and mapping table state.
4. Do not modify evidence. Work from copies.

## 5. Steps — assess
1. Determine scope: which tenants, which records, which time window, which access paths (from audit logs).
2. Determine whether any personal data left the system (responses, exports, notifications). If yes, follow the data-incident procedure of the Product Owner and counsel (the procedure must be defined before pilot; it is a pre-pilot gap, see §8).
3. Classify the incident and record it.

## 6. Steps — rollback / restore (only after assessment)
1. Select a recovery copy from the approved D-023 Level 4 backup boundary. Verify the backup identity, administrative boundary, key custody, retention/deletion controls and audit evidence; production credentials must not be able to destroy all recovery copies or control all keys.
2. Choose the restore point: the last verified snapshot before the first known bad event; validate integrity/checksums before use.
3. Restore to an isolated environment first; verify row counts and checksums against the evidence copy.
4. Re-apply every tenant suspension and deletion decided after the restore point (a restore must never reactivate a suspended tenant). This is a requirement; the mechanism must be built and tested before pilot.
5. Rotate all tenant and runtime credentials that were in scope of the incident.
6. Re-run the tenant isolation tests (TI contracts that apply to the implemented mechanism) on the restored environment. Results must be recorded. A failing test blocks reopening.
7. Reopen to one tenant first, then to the full pilot cap, only after the Product Owner approves in writing.

## 7. Reopen criteria (all required)
- Root cause identified and fixed, or explicitly accepted by the Product Owner as a residual risk with a record.
- Isolation tests pass on the restored environment (results recorded, not assumed).
- Credentials in scope rotated.
- Monitoring shows normal connection and error levels for a defined observation period.
- Written approval by the Product Owner.

## 8. Known gaps (must be closed before pilot)
- Data-incident notification procedure (legal and privacy input required).
- Mechanism that re-applies suspensions after restore (not yet built).
- D-023 Level 4 backup provider/account/admin boundary, key custody, deletion/retention controls and restore evidence are not yet verified; provider selection is deferred.
- Named incident lead and delegate, in writing.
- Exercise of this runbook on the test environment (L-11), with recorded timing.

## 9. Not in this runbook
- No claim that any step has been executed or timed.
- No legal or notification deadline is stated; these are for counsel to define.
