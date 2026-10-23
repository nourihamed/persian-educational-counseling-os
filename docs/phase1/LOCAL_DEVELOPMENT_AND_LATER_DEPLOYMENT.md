# Local Development Now, Server Deployment Later

**Status:** Product Owner direction recorded as D-021 on 2026-10-23. Documentation only.  
**Scope:** Development workflow and future deployment transition; this document does not approve Phase 1, production hosting, or a real-data pilot.

## 1. Product Owner direction

The project should initially run on the Product Owner's own laptop so implementation can progress without paying for or operating a remote server prematurely. When the product is sufficiently developed to be demonstrated and evaluated, a separately planned deployment to a server will be considered.

This direction separates two environments:
- **Development now:** local laptop, local-only services, synthetic/test data.
- **Later pilot/hosted environment:** selected after readiness review, cost/capacity evaluation, security testing and explicit Product Owner approval.

The local development environment is not the final hosting topology and does not resolve Q-023 for the eventual server.

## 2. Local development boundaries

1. Prefer a reproducible local setup (for example, Docker Compose for local services) so dependencies and startup steps can be repeated. Docker Compose is a development convenience here, not a tenant-isolation or host-compromise security boundary.
2. Bind development services to loopback/local interfaces by default. Do not expose PostgreSQL, Redis, API debug ports, admin dashboards or development tools to the public internet or an untrusted LAN.
3. Use synthetic fixtures and clearly fictional student/counselor accounts only. Do not import real student records, production credentials, real phone numbers, or private parent/student data into local development.
4. Keep secrets out of Git, logs, screenshots, fixtures, and commits. Use local environment configuration with restrictive file permissions; never reuse future production secrets.
5. Use separate local development credentials and data from any later server environment.
6. Keep schema changes in version-controlled migrations when implementation is authorized. Local migrations and local tests are not evidence that production migrations or security controls are safe.
7. The local laptop and its administrator account are a shared trust boundary. Multiple local containers/databases do not provide independent protection against compromise of the laptop or host administrator.
8. Local testing may validate domain logic and developer workflows, but must not be described as proof of Alt-5 cross-cell isolation, production capacity, backup recovery, or operational resilience.

## 3. Recommended progression

### Stage A — Local development
- Build the application and data model in the authorized implementation phase.
- Use synthetic data and repeatable setup instructions.
- Add unit, integration, API, authorization and tenant-isolation tests as relevant.
- Keep local services private and maintain a clean separation between application configuration and secrets.

### Stage B — Demonstrable development version
Before calling the product “demonstrable,” verify the agreed core workflow, basic error handling, repeatable setup, backup/export handling where implemented, and test results. A demonstration using synthetic data is not a production or pilot approval.

### Stage C — Server deployment planning
Before moving to a server:
- Resolve Q-023 and select the target topology/provider; do not assume the current laptop setup is the server design.
- Produce itemized cost and capacity estimates and label estimates versus measurements.
- Define deployment, TLS, secrets, access control, monitoring, logging, backup/restore, incident response, credential rotation, rollback and offboarding procedures.
- Rehearse migration and restore with synthetic data in a non-production environment.
- Confirm D-014's pre-pilot gates and obtain explicit Product Owner approval.

### Stage D — Controlled pilot readiness
Real student data remains prohibited until tenant isolation is implemented and independently tested, the relevant security and operational gates have passed, privacy/retention decisions are settled, and the Product Owner explicitly authorizes the pilot. The laptop development stage does not waive any gate.

## 4. Relationship to existing decisions

- **D-011:** hosting in Iran, portability and low initial complexity remain product objectives; the eventual server topology is still unresolved.
- **D-020 / Q-022:** Alt-5 remains the selected isolation direction for the proposed pilot; the initial maximum of two tenants per cell remains provisional and conditional on measured capacity/cost.
- **Q-023:** remains OPEN for the eventual hosted topology. Local development does not select Option B/C or change the Alt-5 security requirements.
- **D-014:** real-data pilot remains prohibited until the documented pre-pilot gates and explicit approval are satisfied.
- **Phase gates:** this document does not approve Phase 1, start Phase 2, or authorize implementation beyond the currently authorized phase.

## 5. Non-claims

No code, infrastructure, cloud resources, migration, runtime role, security control, or executable test is created or verified by this document. No provider, price, capacity, or server topology is selected. The local development environment is a development strategy only.
