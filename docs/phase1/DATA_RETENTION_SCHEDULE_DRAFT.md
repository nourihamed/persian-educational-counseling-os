# Data Retention Schedule — DRAFT (pre-pilot deliverable, Q-020)

Status: DRAFT prepared by the technical lead (implementation agent). NOT APPROVED. Not a legal opinion.
Owner: Product Owner (approval). Legal, tax and privacy review: REQUIRED before approval; responsible reviewer NOT YET ASSIGNED by the Product Owner.
Decision context: D-017 accepted the principle (no automatic role deletion; five-step lifecycle). The retention durations below are NOT set. Every duration marked NEEDS-DECISION must be decided by the Product Owner after review. No legal or tax duration is assumed in this draft.

Legend for durations:
- NEEDS-DECISION: no valid basis yet; owner and reviewers must set it.
- LEGAL-REVIEW: a legal or tax obligation may apply; the duration must come from the review, not from this draft.
- PROPOSAL: technical proposal for discussion; not a legal requirement.

## 1. Data categories

| # | Category | Examples | Data subject | Primary purpose | Data owner (role) |
|---|---|---|---|---|---|
| R1 | Student profile and educational records | name, birth date, grade, field, school, goals, plans, study records, tests, errors, reviews, classes, assignments, exams | Student (often a minor), parent | Counseling service | Counselor of record; Product Owner for policy |
| R2 | Accounts and authentication | counselor, student, parent accounts; credentials (hashed); sessions; password reset records | All users | Access control | Platform operator |
| R3 | Audit records | actor, action, target tenant, request id, timestamp, platform-admin access records (D-013) | Users; platform operators | Security, incident review, accountability | Platform operator |
| R4 | Orders, subscriptions and payments | orders, invoices, payment references, credit ledger (append-only) | Counselor | Billing, accounting, dispute handling | Product Owner; finance |
| R5 | Notifications and delivery logs | in-app messages, Telegram/SMS delivery status | Students, parents, counselors | Delivery, support | Platform operator |
| R6 | Files and exports | uploaded files, generated reports and exports | Student, counselor | Service delivery | Counselor of record |
| R7 | Backups and snapshots | full database backups, file backups, point-in-time logs | All of the above | Disaster recovery | Platform operator |
| R8 | Operational logs | application and infrastructure logs (must exclude secrets, tokens, passwords) | Users (indirect) | Operations, incident review | Platform operator |
| R9 | Tenant database roles and grants | role metadata, grant and mapping records (Option C) | Counselor (indirect) | Access isolation | Platform operator |

## 2. Retention schedule per category

| # | Retention objective | Proposed period | Basis for the period | Status of the period | Deletion or anonymisation method | Backups |
|---|---|---|---|---|---|---|
| R1 | Service delivery while the counseling relationship is active; then a defined post-relationship period | NEEDS-DECISION (post-relationship period); LEGAL-REVIEW for minors' records | No valid basis yet | NEEDS-DECISION / LEGAL-REVIEW | Hard delete for identifiable records after period; anonymise aggregate analytics only if the purpose allows | See §3 |
| R2 | While the account is active; then short period for security events | PROPOSAL: deactivate immediately on offboarding; remove credential material after deactivation period | Security practice | PROPOSAL (period NEEDS-DECISION) | Delete credential hashes and tokens; keep identifiers only if needed for R3 | See §3 |
| R3 | Incident review and accountability | NEEDS-DECISION; LEGAL-REVIEW if audit records fall under an obligation | No valid basis yet | NEEDS-DECISION / LEGAL-REVIEW | Append-only; deletion only by an approved procedure after period | See §3 |
| R4 | Billing and accounting | LEGAL-REVIEW (tax and accounting obligations of the operating jurisdiction) | Legal/tax; not assumed here | LEGAL-REVIEW | Retain required financial records; delete or anonymise others after review | See §3 |
| R5 | Delivery status and support | PROPOSAL: short operational period; content not kept longer than needed | Operational necessity | PROPOSAL (period NEEDS-DECISION) | Delete message content; keep minimal status | See §3 |
| R6 | Service delivery | Same as R1 unless reviewed | Derived from R1 | NEEDS-DECISION | Delete with the owning record; delete storage objects too | See §3 |
| R7 | Disaster recovery | PROPOSAL: bounded backup rotation; period NEEDS-DECISION | Recovery objectives (not yet defined) | PROPOSAL / NEEDS-DECISION | Expired backups destroyed by rotation; restore must not resurrect deleted data without a documented procedure | Defined here |
| R8 | Operations | PROPOSAL: short rotation; no secrets in logs | Operational necessity | PROPOSAL (period NEEDS-DECISION) | Rotate and delete | See §3 |
| R9 | Access isolation | Lifecycle of the tenant role (see §4) | Access control | Defined by D-017 lifecycle | Drop only after the checklist in §4 | See §3 |

## 3. Backups

- Backup retention period: NEEDS-DECISION; retention/immutability controls must be documented and approved before pilot.
- A deleted record may remain in backups until those backups expire. This must be disclosed to the Product Owner and reflected in the approved policy; this draft does not claim immediate erasure from backups.
- Restore procedure must re-apply deletion and tenant-suspension decisions taken after the backup was made, or it must be blocked. This is a requirement, not yet implemented.
- **D-023 Level 4:** critical backups, backup administration, encryption keys and deletion/retention controls must be outside ordinary production-account administrative control. A separate bucket/service name alone is not evidence of independence; production compromise alone must not destroy all critical recovery copies.
- Backup integrity, key custody, access control, retention/immutability and restore behavior must be tested on the selected target; current status NOT-RUN / NOT-VERIFIED.

## 4. Tenant role deletion checklist (aligned with D-017 and Q-020)

Roles are deleted only when every item is complete and recorded:
1. Login disabled immediately on suspension or offboarding (done and verified on the target environment; NOT-RUN).
2. Privileges on tenant objects revoked.
3. Sessions terminated and pooled connections cleared (TI-CONN-04 scope; NOT-RUN).
4. Ownership check: role owns no shared application object (TI-CONN-05; NOT-RUN).
5. Dependency check: no grants, policies or mapping rows reference the role, except those being removed in the same step.
6. Audit records retained per R3 (NEEDS-DECISION).
7. Retention obligations for R1, R4 and R7 confirmed (NEEDS-DECISION / LEGAL-REVIEW).
8. Written approval recorded (role of approver to be defined by the Product Owner).

## 5. Items requiring Product Owner decision (Q-020 stays OPEN)

1. Post-relationship retention period for student records (R1).
2. Retention period for audit records (R3).
3. Financial record retention (R4), after legal and tax review.
4. Backup rotation period (R7).
5. Operational log and delivery-status periods (R5, R8).
6. Responsible reviewer for legal, tax and privacy obligations.
7. Approver for role deletion.

## 6. Not in this draft
- No legal duration is asserted.
- No deletion has been implemented or tested.
- Nothing here is evidence that any deletion or anonymisation works.
