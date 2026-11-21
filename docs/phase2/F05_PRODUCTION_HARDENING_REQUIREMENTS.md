# F-05 — production-hardening requirements (not implemented; decisions OPEN)

**Status:** requirements list only. F-05 is accepted at architecture-review level (`fe08a77`).

**What the database controls already do**
- A privileged plan identity must be the session's own identity. It must have no membership, and none of the seven
  attributes.
- The bootstrap validates all nine application roles, their exact memberships and their transitive reach.

**What the database cannot do**
- Prevent a superuser from changing any of this after the bootstrap. The bootstrap check is point-in-time.

| # | Requirement | Owner | Status |
|---|---|---|---|
| H-1 | Name who may provision, hold or assume `ws_<key>_synth_plan_writer` and `ws_<key>_plan_migrator`. The synthetic writer must never exist in production. | Platform Security / Operations | OPEN |
| H-2 | Define a non-superuser provisioning procedure. PostgreSQL 16 gives a CREATEROLE creator ADMIN on each role it creates, which the boundary check rejects as "held by", so such a procedure must drop that grant or use a dedicated provisioner. | Platform Security / Operations | OPEN |
| H-3 | Control and audit production superuser use: who holds it, break-glass, session logging. | Operations / Platform Security | OPEN |
| H-4 | Monitor privileged DDL and role changes after bootstrap (GRANT/REVOKE role, ALTER ROLE, ALTER TABLE … DISABLE TRIGGER, CREATE OR REPLACE on the security functions), and alert. | Operations | OPEN |
| H-5 | Re-run `plan_identity_boundary_violations()` on a schedule and on every deployment, failing the deployment on any row. | Operations | OPEN |
| H-6 | Decide whether the migrator may ever run in production, and if so under what change control. | Operations / Product Owner | OPEN |

None of these is implemented, and no production privilege path is granted.
