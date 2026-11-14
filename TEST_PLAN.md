# TEST_PLAN.md
## Phase 2 Control Plane + Workspace acceptance contracts (2026-11-09)

**Latest successful execution:** GitHub Actions Run #336, PostgreSQL 16, exact SQL/test tree at commit `52bd0347b3aba4f816d996065122ed0d362bae5f` (run status SUCCESS). It includes `WS-CAP-RACE-01`. Run #231 remains evidence only for its exact historical tree. Later documentation commits were followed by a new executable capacity-race script and workflow change, so the latest test tree is not covered by Run #231. Run #336 completed SUCCESS on PostgreSQL 16 at exact SHA `52bd0347b3aba4f816d996065122ed0d362bae5f`; log confirms `PASS WS-CAP-RACE-01` for two different enrollments competing for the final slot. Later Workspace role-source schema/fixture/test commits are not covered; fresh CI for current HEAD remains pending. This is synthetic draft-SQL evidence, not API/runtime/production/HA approval.

| ID | Required test | Status |
|---|---|---|
| CP-IDENT-01 | Global mobile+grade uniqueness across Workspaces | EXECUTED / PASS |
| CP-IDENT-02 | Same mobile with different grade follows approved D-025 rule | EXECUTED / PASS |
| CP-IDENT-03 | HMAC rotation gate, alias completeness, active/retiring overlap and retirement lifecycle | EXECUTED / PASS for SQL lifecycle cases; live KMS backfill and crash/recovery NOT RUN |
| CP-IDENT-04 | Rotation gate serializes admission; incomplete/mismatched aliases rejected | EXECUTED / PASS for included synthetic cases; KMS and adversarial operational concurrency NOT RUN |
| CP-ADMIT-01 | Initial claim atomically creates Platform Student, owner, claim, encrypted contact index and every live HMAC alias | EXECUTED / PASS |
| CP-ADMIT-02 | Idempotent replay and same-key/different-payload rejection | EXECUTED / PASS |
| CP-ADMIT-03 | Cross-Workspace duplicate mobile+grade rejected; same mobile/different grade allowed | EXECUTED / PASS |
| CP-ADMIT-04 | Missing/duplicate/malformed aliases, inactive encryption key, inactive Workspace and zero-active-HMAC cases rejected | EXECUTED / PASS |
| CP-ADMIT-05 | New admission fails closed during maintenance; replay remains idempotent | EXECUTED / PASS |
| CP-ADMIT-RACE-01 | Concurrent cross-Workspace claim admission produces one winner and full rollback of loser | EXECUTED / PASS |
| CP-ROLE-01 | Control Plane owner/executor roles, direct-table denial, executor function scope, no PUBLIC EXECUTE | EXECUTED / PASS in ephemeral PostgreSQL; shared function-owner blast radius remains HIGH |
| CP-OWN-01 | Exactly one global owner and one holding claim per student | EXECUTED / PARTIAL: one holding claim per student tested; broader owner-race and lifecycle paths NOT RUN |
| CP-OWN-02 | Switch rejects missing/multiple/stale source claims | EXECUTED / PARTIAL: stale generation/source tested; all cardinality cases NOT RUN |
| CP-OWN-03 | Ownership generation increments exactly once; stale source writes/jobs denied | EXECUTED / PARTIAL: switch generation and stale source/generation tested; stale jobs/writes NOT RUN |
| CP-XFER-01 | All three cumulative approvals required; expired/revoked approvals denied | EXECUTED / PARTIAL: missing fee approval blocks and all three approvals allow switch; expiry/revocation NOT RUN |
| CP-XFER-02 | Approval principal, authn event, relationship/assignment and authority scope bound to exact case | NOT RUN (trusted identity/authority verification service absent) |
| CP-XFER-03 | Source freeze barrier drains in-flight writes before final snapshot | NOT RUN (distributed freeze/drain not implemented) |
| CP-XFER-04 | Destination staging inaccessible until checks and ownership switch | NOT RUN (service-level access gate not implemented) |
| CP-XFER-05 | Post-switch cancellation forbidden; forward recovery only | EXECUTED / PARTIAL: post-switch cancellation rejected; crash/forward recovery NOT RUN |
| CP-IDEM-01 | Same idempotency key + same canonical payload replays original result | EXECUTED / PASS |
| CP-IDEM-02 | Same key + different payload rejected | EXECUTED / PASS for transfer and admission; end-to-end audit integration NOT RUN |
| CP-EVENT-01 | Outbox/inbox duplicate/out-of-order delivery deduplicated and fenced | NOT RUN (database event payload immutability only; worker delivery absent) |
| CP-FAIL-01 | Control Plane outage/ambiguous ownership denies student-data access | NOT RUN (runtime fail-closed integration absent) |
| WS-SCHEMA-01 | Workspace membership, branch/type, assignments, guardian record shape, educational domain, immutable versions, credit ledger, capacity, files, notifications, legal holds and audit | EXECUTED / PASS for included schema fixtures |
| WS-ROLE-01 | Per-Workspace unique role names, object owners, no elevated runtime attributes, least-privilege grants and two-database CONNECT denial | EXECUTED / PASS in two synthetic databases; production credentials and API/data isolation NOT RUN |
| WS-ISO-01 | Workspace A cannot access Workspace B data through API/repository/files/jobs | NOT RUN (database CONNECT ACL only was tested) |
| WS-AUTH-01 | Counselor/manager object and assignment scope enforced | NOT RUN (runtime authorization absent) |
| WS-PARENT-01 | Per-child/per-permission parent isolation; expiry/revocation/legal matrix | NOT RUN |
| WS-VERSION-01 | Published ProgramVersion/StudentPlanVersion immutable | EXECUTED / PASS |
| WS-ACT-01 | Activation, credit debit, capacity reservation and audit event are one transaction | EXECUTED / PASS |
| WS-ACT-02 | Activation idempotency, payload mismatch and duplicate activation | EXECUTED / PASS |
| WS-ACT-03 | Insufficient credit, capacity exhaustion, stale generation, missing responsible counselor and suspended actor rollback | EXECUTED / PASS |
| WS-ACT-RACE-01 | Concurrent activation of the same enrollment yields one debit, capacity reservation and audit event | EXECUTED / PASS |
| WS-CREDIT-01 | Wallet balance cannot go negative; reversals are exact, append-only and single-use | EXECUTED / PASS for included ledger cases; payment/refund/renewal policy NOT RUN |
| WS-CREDIT-UNIT-01 | Student Credit unit is CRD, not a fiat currency code | EXECUTED / PASS |
| WS-CAP-01 | Atomic active-student capacity ceiling and idempotent capacity event | EXECUTED / PASS for included cases; two different students racing for last slot and archived exclusion NOT RUN |
| OPS-RESTORE-01 | Independent encrypted backup restore drill, failover and consistency evidence | NOT RUN |

A test may be marked IMPLEMENTED only when an executable test exists, EXECUTED only with reproducible logs on the exact reviewed SQL/test tree, and PASS only after successful execution. Static review is not execution. Phase 2 cannot pass while required critical security/integrity tests remain NOT RUN.


Status: Phase 0 documentation baseline approved/closed by Product Owner on 2026-10-14; this is a planned test strategy, not evidence that tests have run or passed.

## فلسفه تست
هیچ فازی بدون تست تمام نمی‌شود. تست‌های Tenant Isolation و Billing **mandatory** هستند و رد نمی‌شوند.

## لایه‌های تست

### Unit
- Calendar conversion (Jalali ⇄ Gregorian)
- Percentage/Score calculation (Test: Correct+Wrong+Unanswered=Total)
- Review rule generator (1-3-7، duplicate prevention)
- Planning Engine (conflict detection)
- Progress formula
- Risk Engine (explainability output)
- Credit Ledger math (no negative balance)
- Billing state transitions
- Notification scheduling (quiet hours, retry/backoff logic)
- **Program/Plan Versioning** (طبق D-008 — Accepted؛ این موارد تست پوشش آینده‌اند، هنوز اجرا نشده‌اند چون کدی وجود ندارد): شماره نسخه به‌درستی افزایش می‌یابد؛ ساخت نسخه جدید هرگز نسخه منتشرشده قبلی را Mutate نمی‌کند؛ کدام وضعیت‌های Plan قابل‌ویرایش مستقیم‌اند طبق قانون تعریف‌شده رفتار می‌کنند

### Integration
- API endpoints (auth required, RBAC enforced)
- Database constraints/migrations
- Authentication flows
- Authorization (policy evaluation)
- **Tenant Isolation** (جزئیات در بخش زیر)
- Billing (order→payment→credit flow)
- Notification delivery pipeline
- Telegram adapter (mock bot API)
- SMS adapter (mock provider)
- **Program/Plan Versioning — Transaction Safety** (طبق D-008 — Accepted): ساخت + فعال‌سازی یک نسخه جدید Atomic است (هیچ حالت نیمه‌کاره‌ای که Enrollment/Plan را به وضعیت ناسازگار اشاره‌گر کند)؛ به‌روزرسانی یک Template هرگز یک Plan دانش‌آموزی موجود/فعال را بی‌صدا تغییر نمی‌دهد؛ دسترسی Read/Write به تاریخچه نسخه‌ها هم مشمول تست‌های Tenant Isolation زیر است (نه یک مسیر جدا)

### E2E
سناریوی کامل بخش ۵۸ Master Prompt، از ثبت‌نام Counselor تا تولید Report، باید حداقل یک‌بار به‌صورت خودکار (Playwright/pytest) اجرا شود.

## Tenant Isolation Tests (Mandatory — بخش ۵۹)

**معماری فعال Phase 1:** D-020 Alt-5 isolation cells با اهداف امنیتی D-023 (Level 3 استقلال زیرساختی/اداری cell و Level 4 استقلال مدیریتی backupهای حیاتی)؛ قراردادهای پذیرش جاری در `docs/phase1/TENANT_ISOLATION_TEST_CONTRACTS.md` تعریف شده‌اند و تا زمان اجرا NOT-RUN هستند. چک‌لیست عمومی زیر مکمل است و به‌تنهایی اثبات جداسازی cell یا پذیرش فاز نیست.

سناریوی پایه:
```
Counselor A → Student A
Counselor B → Student B
```
باید تأیید شود:
- A نمی‌تواند از طریق API به داده B دسترسی پیدا کند (حتی با آزمایش دستکاری ID در URL/Body)
- Query سطح DB داده B را برای A برنمی‌گرداند (تست مستقیم روی Repository layer)
- گزارش‌های A حاوی داده B نیست
- فایل‌های آپلودی B برای A قابل‌دسترس نیست (حتی با URL مستقیم)
- نوتیفیکیشن‌های A/B به‌اشتباه قاطی نمی‌شوند
- Background Job های اجراشده برای Tenant A داده B را پردازش نمی‌کنند
- تاریخچه نسخه (`ProgramVersion`/`PlanVersion`) متعلق به B، از طریق API یا Repository، برای A قابل‌خواندن نیست؛ A نمی‌تواند روی `PlanVersion` دانش‌آموزی از Tenant B نسخه جدید بسازد یا نسخه‌ای را فعال کند (پیوست به D-008 — Accepted)

### آزمون‌های تاریخی/تکمیلی D-009 — PostgreSQL RLS + Application Authorization

D-009/Q-001 مکانیزم Phase 0 بوده است و دیگر معماری مرزی فعال Phase 1 نیست. اگر RLS درون یک cell استفاده شود، موارد زیر همچنان برای همان لایه‌های پیاده‌سازی‌شده لازم‌اند؛ اما RLS یا Application filter به‌تنهایی جایگزین مرز شبکه/host/credential در Alt-5 نمی‌شوند. موارد مربوط به RLS نباید به‌عنوان اثبات Level 3 یا Level 4 گزارش شوند. موفقیت یک لایه، جایگزین آزمون لایه دیگر نیست:

- **بررسی پیکربندی نقش runtime (DB security/configuration test):** نقش مورد استفاده برنامه مالک جدول‌های tenant-owned نباشد، عضو نقشی با امتیاز دورزدن RLS نباشد و ویژگی BYPASSRLS نداشته باشد. نتیجه را از کاتالوگ‌های PostgreSQL/مجوزهای واقعی بررسی کن؛ صرفاً نام یا تنظیمات اعلام‌شده نقش کافی نیست.
- **بررسی مالکیت و RLS policyها:** برای همه جدول‌های tenant-owned هدف، فعال‌بودن RLS و در موارد لازم FORCE ROW LEVEL SECURITY، وجود و درستی policyهای مورد انتظار و نقش‌هایی که policyها برایشان اعمال می‌شوند را بررسی کن. استثناها باید مستند و تأییدشده باشند.
- **آزمون RLS به‌تنهایی:** با اتصال/نقش غیرمالکِ فاقد BYPASSRLS و بدون اعمال فیلتر tenant در لایه Application/Repository، تلاش برای خواندن و نوشتن داده Tenant دیگر را آزمایش کن؛ RLS باید دسترسی غیرمجاز را مسدود کند. این تست نباید با فیلتر برنامه نتیجه مثبت کاذب بگیرد.
- **آزمون Application authorization به‌تنهایی:** در تست ایزوله‌ای که عمداً RLS را از مسیر آزمایش حذف یا بی‌اثر می‌کند، ثابت کن فیلترهای Application/Repository و کنترل object-level authorization به‌تنهایی درخواست cross-tenant را رد می‌کنند. این حالت فقط در محیط تست کنترل‌شده مجاز است؛ هرگز تنظیمات امنیتی محیط واقعی را تغییر نده.
- **آزمون یکپارچه:** همان سناریوهای منفی را با هر دو لایه فعال اجرا کن؛ شکست هر لایه باید جداگانه قابل تشخیص باشد. تست‌های دورزدن RLS فقط در محیط تست ایزوله و با نقش/مجوز محدود انجام شوند.

این تست‌های مربوط به پیاده‌سازی RLS/Application باید در CI روی هر PR اجرا شوند، نه فقط دستی. تست‌های Alt-5 شامل دسترسی واقعی شبکه/credential، مرز اداری cell، استقلال backupهای حیاتی، restore و revocation در `TENANT_ISOLATION_TEST_CONTRACTS.md` هستند و بعضی از آن‌ها به محیط نماینده نیاز دارند. اگر یک تست نیازمند امتیاز مدیریتی یا تغییر policy است، آن را به تست پیکربندی/محیط ایزوله محدود کن و هیچ‌گاه برای اجرای تست، نقش runtime را privileged نکن.

## Billing Tests (بخش ۶۰)
- Purchase Credit → موجودی درست
- Consume Credit → کسر صحیح، جلوگیری از موجودی منفی
- Refund Credit
- Cancel Student → بازگشت Credit طبق قانون کسب‌وکار
- Duplicate Payment → idempotent (دوبار پردازش نشود)
- Failed Payment → وضعیت صحیح، بدون کسر Credit
- Webhook Replay → idempotency key الزامی

## Notification Tests (بخش ۶۱)
- جلوگیری از ارسال تکراری
- Retry/Backoff
- رفتار هنگام Failure provider و Recovery
- Quiet Hours (عدم ارسال پیامک در ساعات غیرمجاز)

## معیار پوشش (پیشنهادی)
- Domain/Business logic: حداقل ۸۰٪ coverage
- Tenant Isolation paths: ۱۰۰٪ coverage الزامی
- Billing paths: ۱۰۰٪ coverage الزامی

## ابزار پیشنهادی
- Backend: Pytest + pytest-asyncio + httpx AsyncClient + factory fixtures
- DB تست: دیتابیس Postgres ایزوله per test-run (نه SQLite، به دلیل RLS و قابلیت‌های خاص Postgres)
- CI: GitHub Actions

---

## Target-environment load and connection tests (pre-pilot, added 2026-10-17)

Plan: `docs/phase1/TARGET_ENV_LOAD_TEST_PLAN.md`. Status: PLAN ONLY; all scenarios NOT-RUN or BLOCKED. No measurement exists. These tests are pilot-validation criteria (D-015, D-014), not prerequisites for Phase 1 design approval.


## Phase 2 security-contract extensions (2026-11-09)

The following are **specified / NOT IMPLEMENTED / NOT RUN**. They are not covered by the existing PostgreSQL SQL CI runs.

| ID | Required test | Status |
|---|---|---|
| CP-CONTACT-01 | Contact change requires step-up and verified new-contact proof bound to exact student/case-equivalent operation, Workspace and generation | NOT RUN — verifier/API absent |
| CP-CONTACT-02 | Contact change updates ciphertext and all active/retiring aliases atomically; duplicate mobile+grade fully rolls back | NOT RUN — SQL function absent |
| CP-CONTACT-03 | Proof replay, expiry, revocation, wrong subject/purpose/contact/generation and idempotency mismatch reject | NOT RUN — proof verifier absent |
| CP-CONTACT-04 | Concurrent contact change vs HMAC rotation and ownership transfer serializes safely | NOT RUN |
| CP-APPROVAL-01 | Signed approval assertion validates issuer, audience, signature, algorithm, nonce, expiry and exact case/student/Workspace/generation/kind | NOT RUN — trusted verifier absent |
| CP-APPROVAL-02 | Guardian per-child legal authority, current counselor assignment + explicit fee-received attestation, and destination delegated permission are verified | NOT RUN — policy/identity services absent |
| CP-APPROVAL-03 | Revocation and replacement approval are append-only; one current valid event per approval kind is selected | NOT RUN — schema requires redesign |
| CP-APPROVAL-04 | Revocation racing ownership switch serializes; authority is revalidated at cutover | NOT RUN |
| CP-APPROVAL-05 | Platform Admin cannot initiate, substitute for, or approve any required approval | NOT RUN — service/API tests absent |
| CP-SAGA-01 | Outbox publisher lease, crash-before/after-publish, duplicate publish and retry are safe | NOT RUN — worker absent |
| CP-SAGA-02 | Inbox receipt and projection mutation are atomic/idempotent; duplicate ID/hash mismatch and stale generation reject | NOT RUN — consumer absent |
| CP-SAGA-03 | Source freeze blocks all mutation paths and drains in-flight writes before snapshot | NOT RUN — freeze controller absent |
| CP-SAGA-04 | Destination staging is isolated; manifest/checksum/attachment/exclusion mismatch prevents cutover | NOT RUN — staging importer absent |
| CP-SAGA-05 | Crash injection at each Saga boundary recovers pre-switch safely and post-switch forward-only | NOT RUN — orchestrator absent |
| API-AUTH-01 | Student, counselor, manager, branch, parent per-child, file/export, notification and job authorization matrix | NOT RUN — runtime API absent |
| API-AUTH-02 | Cross-Workspace hidden resource and nonexistent resource return indistinguishable 404; visible-but-forbidden returns 403 | NOT RUN — runtime API absent |

**Schema reconciliation blocker:** `transfer_approvals UNIQUE(case_id, approval_kind)` with mutable `revoked_at` cannot preserve a revoked approval and a replacement approval as separate immutable events. Replace it with append-only approval/revocation events or a versioned equivalent before marking CP-APPROVAL-03 implemented.

A design document or static SQL assertion does not change any of the statuses above. Existing CI success is limited to the exact SQL/test tree and SHA named in the run evidence.


## Workspace domain schema review follow-up (2026-11-09)

See `docs/phase2/workspace/WORKSPACE_DOMAIN_SCHEMA_REVIEW.md`. The following design findings are not yet covered by executable acceptance tests:
- WS-DOM-01: test definition total/version, response-to-attempt count reconciliation, score recomputation from scoring snapshot, negative-marking ON/OFF and finalization immutability.
- WS-DOM-02: one canonical membership-role source, grant/revoke audit and no role/permission divergence.
- WS-DOM-03: append-only guardian relationship/permission verification, grant/revoke and authority revalidation; Q-007 legal matrix remains open.
- WS-DOM-04..09: per-subject exam results, custom error reasons, subtopics, planning input snapshots/PlanItems, activity taxonomy, class participants/recurrence, capacity last-slot race/reconciliation, credit purchase/refund/renewal, file scanning and notification ownership/permission fencing.

Status for all: SPECIFIED AS GAPS / NOT IMPLEMENTED / NOT RUN. Do not mark domain-schema completeness based only on the current skeleton's schema fixtures.


## Operational resilience acceptance contracts (2026-11-09)

See `docs/phase2/operations/OPERATIONAL_RESILIENCE_BACKUP_RECOVERY_CONTRACT.md`. OPS-HA-01..05, OPS-BACKUP-01..02, OPS-RESTORE-01..04 and OPS-CAP-01..03 are **NOT RUN** and require a representative isolated target environment. No CI result or local SQL test may be substituted for backup independence, restore, fencing, failover, split-brain, pool isolation or measured capacity evidence.



## Additional Phase 2 contracts added — 2026-11-10

The following test groups are now specified in companion contracts but are **NOT IMPLEMENTED / NOT RUN**:
- CP-APPROVAL-06..10: exact case/student/direction/generation/payload binding; signed issuer/audience/nonce verification; append-only revocation/supersession; authority revalidation at cutover; revocation-vs-switch concurrency.
- CP-SAGA-06..12: source freeze/write barrier; consistent snapshot and destination quarantine; transactional outbox crash/retry; inbox hash/generation fencing; crash recovery at each checkpoint; post-switch forward-only recovery; reconciliation without changing CP owner.
- CP-CONTACT-05..09: trusted proof binding and single-use; all active/retiring aliases; conflict rollback; rotation/transfer lock-order race; outbox recovery.
- WS-GOV-01..10: append-only membership role/permission grant/revoke events; role projection direct-DML denial; scope escalation/self-grant denial; guardian relationship/permission event history; revocation/expiry/dispute invalidation; concurrent grant/revoke/access linearization; event/projection drift detection.
- WS-DOM-01..09 remain open per `WORKSPACE_DOMAIN_SCHEMA_REVIEW.md`; contracts do not constitute schema or executable test completion.

CI status must be verified on the exact latest branch SHA before any PASS is reported. No historical run is transferable to later SQL/test changes.

## Q-007, retention and operational policy acceptance (2026-11-09)

- Parent/guardian authority: `docs/phase2/api/PARENT_GUARDIAN_AUTHORITY_MATRIX_Q007.md`; Q-007 remains OPEN pending Iran legal review and PO approval. All parent scope/age/dispute tests are NOT RUN.
- Retention/legal hold: `docs/phase2/operations/DATA_RETENTION_IMPLEMENTATION_CONTRACT.md`; policy-version, unresolved-duration fail-closed, legal-hold, restore-suppression and deletion verification tests are NOT RUN.
- Backup/failover/restore: `docs/phase2/operations/OPERATIONAL_RESILIENCE_BACKUP_RECOVERY_CONTRACT.md`; OPS-HA/BACKUP/RESTORE/CAP tests remain NOT RUN pending target environment.


## Capacity last-slot concurrency regression (2026-11-09)

Added executable synthetic test `docs/phase2/workspace/tests/workspace_capacity_last_slot_race.sh` and wired it into `.github/workflows/phase2-schema-tests.yml`. It races two different enrollments for one remaining active-student slot while keeping credit sufficient, and asserts one activation/debit/capacity/audit winner plus full rollback for the loser. **Status: IMPLEMENTED IN BRANCH / CI EXECUTION NOT YET VERIFIED.**


## Phase 2 exit criteria reference

The design/schema vs later implementation evidence boundary and gate requirements are centralized in `docs/phase2/PHASE2_EXIT_CRITERIA.md`. No test may be marked PASS without exact-SHA execution evidence; design specifications and static review remain separate statuses.


## Open decision dependencies

See `docs/phase2/PHASE2_OPEN_DECISIONS.md` for policy decisions that gate the corresponding executable tests/features. Tests depending on unapproved legal, retention, scoring, credit, capacity or operational values must remain blocked rather than inventing expected values.


## Membership role source-of-truth remediation (2026-11-09)

Removed scalar `workspace_memberships.role_key`; `membership_roles` is the sole role-assignment relation. Added synthetic schema assertion `WS-ROLE-SOURCE-01` to prove the scalar column is absent and canonical relation exists. Role grant/revocation event history and direct-DML authorization tests remain open. The test is wired into the current Workspace schema suite; fresh CI result pending.


## Educational domain contract test references (2026-11-09)

- Assessment: `docs/phase2/workspace/ASSESSMENT_DOMAIN_CONTRACT.md` — immutable definition versions, delivered question sets, submit-time count reconciliation, deterministic score recomputation, custom error reason and exam-subject aggregation tests. NOT IMPLEMENTED / NOT RUN.
- Planning: `docs/phase2/workspace/DETERMINISTIC_PLANNING_DOMAIN_CONTRACT.md` — deterministic replay, hard constraints, non-overlap, explanation, version immutability, carry-forward and timezone/Jalali boundary tests. NOT IMPLEMENTED / NOT RUN.
- Curriculum: `docs/phase2/workspace/CURRICULUM_DOMAIN_CONTRACT.md` — Book/Edition/Subtopic hierarchy, ownership, immutable reference curriculum and mastery mapping tests. NOT IMPLEMENTED / NOT RUN.


## Activity, credit and capacity lifecycle tests

- Activity/class: `docs/phase2/workspace/ACTIVITY_CLASS_DOMAIN_CONTRACT.md` — controlled taxonomy, recurrence idempotency, participant scope, attendance and carry-forward tests. NOT RUN.
- Student Credit commercial lifecycle: `docs/phase2/workspace/STUDENT_CREDIT_COMMERCIAL_LIFECYCLE_CONTRACT.md` — verified payment webhook, grant idempotency, refund/reversal and wallet reconciliation tests. NOT RUN beyond existing synthetic ledger/activation checks.
- Capacity lifecycle: `docs/phase2/workspace/CAPACITY_LIFECYCLE_CONTRACT.md` — archive/re-activation, suspension policy, destination transfer reservation and counter reconciliation tests. NOT RUN beyond activation and final-slot race tests.


## Authorization-table least-privilege regression tests (2026-11-09)

Workspace role privilege tests now assert runtime and activation function owner cannot INSERT/UPDATE/DELETE membership, role, permission, branch, counselor-assignment or guardian authorization tables; runtime retains required SELECT. They also assert the activation function owner's column-level grants for state transitions and row-lock-only columns. Added wallet identity immutability test WS-CREDIT-WALLET-01. Status: IMPLEMENTED IN BRANCH / NOT RUN on latest SHA.


## Workspace governance projection regression tests — 2026-11-10

Expanded `workspace_governance_event_tests.sql` to cover:
- role grant and revoke projection changes;
- permission grant, scope change and revoke projection changes;
- membership suspension invalidating role/permission projections;
- idempotent replay after the original actor is suspended;
- existing sequence, duplicate-key/payload mismatch, missing authority reference, inactive actor and append-only assertions.

Expanded `workspace_role_privilege_tests.sql` to verify the dedicated per-Workspace non-login `governance_owner`, ownership of the materializer, its narrowly scoped projection grants, no persistent schema CREATE, and no execute/event-table access for runtime, worker, exporter or activation function owner.

Status: IMPLEMENTED IN WORK BRANCH / FRESH CI PENDING. Guardian projection tests and trusted authorization/API tests remain NOT IMPLEMENTED / NOT RUN. CI #474 passed only the previous ledger-only revision; do not carry that pass forward to these new changes.


## Workspace governance projection tests — verification update (2026-11-10)

Latest CI #519 passed all 13 workflow steps on `d45753924513f9920f714b966361b9697e8264d5`. The governance suite covers event sequence/idempotency, role and permission projection updates, scope changes, revocation, membership suspension/end/reactivation, invalid lifecycle transitions, inactive target grants, replay after actor suspension and append-only enforcement. Role tests verify dedicated governance-owner separation and deny application-role execution.

Status: IMPLEMENTED IN BRANCH / CI PASS for SQL draft tests. This does not mean end-to-end authorization is implemented. Trusted assertion verification, role-grantability policy, API/RBAC/object authorization and guardian legal authority remain NOT IMPLEMENTED / NOT RUN.


## Trusted governance assertion acceptance tests — 2026-11-10

New design target: `docs/phase2/workspace/WORKSPACE_GOVERNANCE_AUTHORIZATION_ASSERTION_CONTRACT.md`. Required but NOT IMPLEMENTED / NOT RUN: signature/key/issuer/audience validation, exact actor-target-action-scope binding, role-grantability and anti-escalation, one-use proof receipt and concurrent replay, atomic receipt consumption + event/projection rollback, revoke-vs-read freshness, and verifier/adapter privilege isolation. No application role may receive EXECUTE until these tests pass.


## Accepted Workspace role grantability regression matrix — 2026-11-10

Product Owner decision: `docs/phase2/workspace/PO_DECISION_ROLE_GRANTABILITY_MATRIX_2026-11-10.md`.

Required implementation tests (all NOT IMPLEMENTED / NOT RUN unless separately evidenced on an exact SHA):
- Organization Manager invite/activate/revoke of counselor membership succeeds only within its own Workspace.
- Organization Manager cannot appoint/approve another Organization Manager, self-grant, cross-Workspace grant or access every student's private records by role alone.
- Platform Admin may approve initial/replacement Organization Manager appointment through a narrow Governance capability only; tests must deny general Workspace DML and student-data access through that capability.
- Counselor role/permission delegation is denied; student reads are limited to assigned students.
- Branch Manager is limited to operational actions within assigned Branch and cannot grant organization-level roles.
- Other Workspace staff cannot delegate roles or permissions.
- Deny-by-default, no self-grant, no equal/higher privilege escalation, no scope expansion, audit binding, replay rejection and revocation freshness are enforced.
- Revocation must block subsequent API access, exports, background jobs and notifications; test cache/queue revalidation and the authorization linearization point.
- Cross-Workspace/nonexistent targets preserve uniform 404 behavior; visible objects with forbidden actions return 403.

Guardian/parent and student legal authority tests remain blocked by Q-007 and must fail closed. Transfer approval conflict-of-interest policy is separate and remains unresolved. These accepted role-policy tests do not constitute implementation or phase approval.

## Issue #13 — governance proof receipts (synthetic)
- `receipts/tests/receipt_10_tests.sql`: role boundary (RC-01..05), adapter boundary (RC-06), storage constraints (RC-07..12), binding mismatches (RC-13..19), cross-Workspace and validity (RC-20..23), exactly-once consume and idempotency (RC-24..27), rollback and fail-closed (RC-28..30), catalog privileges (RC-31). Status: PASS in the local run recorded in the evidence file.
- `receipts/tests/receipt_20_race.sh`: RR-01 (same assertion registered twice), RR-02 (same receipt and key consumed by two sessions). Status: PASS (5 of 5 local repeats).
- `receipts/verifier_interface/tests/test_verifier_contract.py`: 10 verifier-boundary tests. Status: PASS (test double only).
- Not run: GitHub Actions run for the commit; full RBAC matrix beyond receipt privileges; revocation freshness across service handoffs (NOT IMPLEMENTED).

## Issue #13 corrective patch — test status (local author runs; NOT CI, NOT independently reproduced)
| ID | What it checks | Where | Status |
|---|---|---|---|
| receipt_10 (RC-01..RC-31) | Role boundary, storage, binding, validity, single use, rollback, catalog | tests/receipt_10_tests.sql | PASS (44 notices, exit 0) |
| M01-1..M01-7b | Retry before and after expiry, binding changes on retry, unconsumed expiry fail-closed | tests/receipt_30_integrity_tests.sql | PASS (exit 0) |
| M02-1..M02-12 | State machine, metadata integrity, NULL bypass attempts, FK, immutable version | tests/receipt_30_integrity_tests.sql | PASS (exit 0) |
| M03-V1..V10, M03-D1..D4, M03-R1..R3 | Canonical vectors, digests, fail-closed inputs | tests/receipt_40_canonical_vectors_tests.sql | PASS (exit 0) |
| RR-01 | One winner for the same assertion | tests/receipt_20_race.sh | PASS |
| RR-02 | Exactly one effect for two concurrent consumptions | tests/receipt_20_race.sh | PASS |
| RR-03 | Concurrent identical retries after consumption return the original event | tests/receipt_20_race.sh | PASS |
| verifier unit tests (15) | Rule checks, canonical version, digest binding (test double only) | verifier_interface/tests | PASS |
| canonical unit tests (6) | Reference rules and vectors | verifier_interface/canonical | PASS |
| CI for the corrective commit | Full workflow | GitHub Actions | NOT RUN until the commit is pushed |
| Production verifier | — | — | NOT IMPLEMENTED (deferred) |
| Revocation freshness across services | — | — | NOT IMPLEMENTED |

## H-03 — receipt INSERT bypass and consumed-retry consistency (head 70e37d7; author-executed draft tests)
| ID | Check | Status |
|---|---|---|
| H03-1 | verifier_rt INSERT with status=consumed and complete metadata is refused | PASS (SQLSTATE 23514) |
| H03-2 | verifier_rt INSERT with status=revoked is refused | PASS (23514) |
| H03-3 | verifier_rt ordinary registered INSERT is accepted | PASS |
| H03-4 | owner-level registered→consumed outside the consume command is refused | PASS (23514) |
| H03-5 | revocation is recorded with revoked_by and time | PASS |
| H03-5b | revocation audit is append-only | PASS (23514) |
| H03-6 | verifier_rt cannot revoke (no UPDATE) | PASS (42501) |
| H03-7 | verifier_rt cannot write the revocation audit | PASS (42501) |
| H03-8 | normal consume and exact retry return the same event | PASS |
| H03-9 | consumed receipt pointing at an existing unrelated event is refused on retry (rolled back) | PASS (23514) |
| H03-10 | inconsistent stored consumption idempotency key is refused on retry (rolled back) | PASS (23514) |
| H03-R | rollbacks restored stored state and the guard trigger | PASS |
| Workflow | Steps 02 to 12 on a fresh PostgreSQL 16.15 database | ALL PASS (local run) |
| GitHub Actions | postgres-draft-tests on 70e37d7 | success, runs 43158838826 and 43158833101 |
| Not tested | Production verifier, signature, key lifecycle, mTLS, revocation propagation, owner/superuser bypass controls | NOT IMPLEMENTED or DEFERRED |

## H-03 corrective — GUC replaced by privilege-backed grant (Supervisor finding; author-executed)
| ID | Check | Status |
|---|---|---|
| H03-11 | governance owner (has UPDATE) sets receipt.consume_active to the target id, then direct registered→consumed is refused | PASS (23514, only the consume command) |
| H03-12 | consume definer role sets receipt.consume_active, then direct transition is refused without a grant | PASS (23514) |
| H03-13a/b/c | governance owner, verifier_rt and adapter cannot forge a consume grant | PASS (42501) |
| H03-13d | adapter cannot read consume grants | PASS (42501) |
| H03-14 | narrow privileges: grants writable only by the definer; definer owns the consume function; no role membership | PASS |
| H03-15 / 15b | legitimate consume succeeds and releases its grant | PASS |
| M02-2, M02-10 | metadata and foreign-key checks, now exercised with a same-transaction grant | PASS |
| receipt_10, receipt_30, receipt_40 | regression | PASS (44, 21, 17 notices) |
| receipt_50 | H-03 suite | PASS (21 notices) |
| Full workflow steps 02 to 12 | fresh PostgreSQL 16.15 database | ALL PASS (local run) |
| GitHub Actions | corrective commit | NOT YET RUN (pending push) |
| M-05, M-06 | residual findings | OPEN (definitions not in implementation record) |

## Phase 2 exit findings — implementation batch (2026-11-13; author-executed, NOT independently reproduced)
| ID | Check | Where | Status |
|---|---|---|---|
| ASM-01..03 | Definition version: created as draft; published version immutable and undeletable | workspace/tests/workspace_assessment_guardian_tests.sql | PASS |
| ASM-04..08 | Attempt needs a published version; starts as `started`; fixed-delivery denominator; attempt/version/test linkage; publishing a new version does not change existing attempts | same | PASS |
| ASM-09..14 | Duplicate response, out-of-range question, custom error reason rules, counters frozen while started | same | PASS |
| ASM-15..22 | Submission: missing response, counter mismatch, direct UPDATE path, missing score, accepted submission, idempotent replay, key reuse with different payload | same | PASS |
| ASM-23..30 | Submitted attempt and responses immutable; analysis cannot rewrite; no cancel or delete after submission | same | PASS |
| ASM-RACE-01 | Response change racing with submission: stale submission waits, then is rejected | workspace/tests/workspace_assessment_submit_race.sh | PASS; sensitivity checked once (with the attempt row lock removed in a scratch copy the test FAILS) |
| GDN-01..04 | Guardian events append-only; verified needs evidence; event bound to its own transaction | workspace/tests/workspace_assessment_guardian_tests.sql | PASS |
| GDN-05,07,13,14 | Link/permission change without its event rejected at constraint check | same | PASS |
| GDN-06,08..11,17,18 | revoked ⇔ revoked_at; permission immutable; no deletes; identity immutable; revoked link terminal; permission needs a verified link | same | PASS |
| GDN-12,15,16 | Effective view follows link state; history preserved after revocation | same | PASS |
| WS-ROLE-14,15 | Runtime has no privilege on guardian history; expected privileges on assessment tables | workspace/tests/workspace_role_privilege_tests.sql | PASS |
| APR-01..13 | One current approval per kind; assertion and nonce replay rejected; approvals and revocations append-only; revoked or expired approval does not satisfy the switch; replacement keeps history | control_plane/tests/cp_35_approval_event_tests.sql | PASS |
| APR-RACE-01 | Revocation racing with the ownership switch: switch waits, then is rejected | control_plane/tests/cp_36_approval_revocation_race.sh | PASS (no lock-removal sensitivity run was done for this race) |
| APR-SWITCH-01 | Switch succeeds with three current approvals; all historical approval events kept | same | PASS |
| Full workflow, steps 02–12 | Fresh PostgreSQL 16.15 cluster, local socket | .github/workflows/phase2-schema-tests.yml | ALL PASS (local run) |
| GitHub Actions for this commit | — | — | NOT RUN until pushed |
| Score formula recomputation, guardian legal authority, approval signature verification | — | — | NOT IMPLEMENTED (service / Phase 4 / verifier) |
| Approval-recording command, contact-change, Saga schema, Workspace lifecycle, WS-DOM-04 remainder | — | — | NOT IMPLEMENTED (open exit findings) |

## Phase 2 exit findings — second batch (2026-11-13; author-executed, NOT independently reproduced)
| ID | Check | Where | Status |
|---|---|---|---|
| EXE-01 | Initial admission commits when called by `cp_identity_admission_executor` | control_plane/tests/cp_45_executor_identity_tests.sql | PASS (failed before the fix: permission denied at commit) |
| EXE-02 | Ownership switch commits when called by `cp_transfer_executor` | same | PASS |
| EXE-03, EXE-04 | HMAC rotation completion and version retirement commit when called by `cp_rotation_executor` | same | PASS |
| EXE-05 | Duplicate mobile+grade still rejected for the executor | same | PASS |
| CC-01..08 | Proof registration boundary, purpose, nonce replay, immutability, no delete | control_plane/tests/cp_40_contact_change_tests.sql | PASS |
| CC-09..13 | Runtime, verifier and executor role boundary | same | PASS |
| CC-14..25 | Stale generation, wrong owner, wrong contact, wrong student, alias coverage, cipher key, unknown proof, maintenance gate; nothing written | same | PASS |
| CC-26, CC-27 | Duplicate number in the same grade across Workspaces: rejected with full rollback | same | PASS |
| CC-28..37 | Valid change, replay, key reuse, consumed proof, atomic replacement, audit, outbox, no plaintext column, append-only | same | PASS |
| CC-38..40 | Same number in another grade allowed; expired and revoked proofs rejected | same | PASS |
| CC-41/42 | Catalog isolation of the contact-change role family | same | PASS |
| CC-RACE-01 | Two students change to the same number concurrently: one winner | control_plane/tests/cp_46_contact_change_race.sh | PASS (3 local repeats) |
| ARC-01..17 | Archive: preconditions, role boundary, one slot released, replay, no underflow, history kept, no credit movement, audit, ledger reconciliation, slot reusable | workspace/tests/workspace_archive_tests.sql | PASS |
| Contact change vs HMAC rotation / vs ownership switch, concurrent | — | — | NOT RUN |
| Reactivation, suspension capacity, transfer reservations | — | — | NOT IMPLEMENTED (policy open) |
| Saga outbox/inbox reconciliation | — | — | NOT IMPLEMENTED |
| GitHub Actions for this commit | — | — | NOT RUN until pushed |

## Product Owner decisions PD-2026-11-13-A..F — third batch (2026-11-14; author-executed, NOT independently reproduced)

PostgreSQL 16.15, local run on a cleared cluster; every database created fresh for its step. All 18 runnable
workflow steps completed (ALL_STEPS_PASSED, 476 PASS assertion lines) plus the Python verifier unit tests.

| ID | Check | Where | Status |
|---|---|---|---|
| AVQ-01..04 | Membership/order uniqueness, orphan version, empty item reference | workspace/tests/workspace_assessment_version_question_tests.sql | PASS |
| AVQ-05..08 | Publication gates: membership count vs question_count, contiguous order, adaptive delivery refused, valid publish | same | PASS |
| AVQ-09..13 | Published membership immutable (add/change/reorder/remove) and no re-parenting | same | PASS |
| AVQ-14..17 | Attempt policy must equal the published version policy; cross-version, wrong-version and wrong-order responses refused | same | PASS |
| AVQ-18..22 | One answer per question, submission requires full coverage, membership is the authority | same | PASS |
| WS-ROLE-16/17 | Runtime grant shape on version questions; runtime **holds** the grant and is still refused on a published version | workspace/tests/workspace_role_privilege_tests.sql | PASS |
| ACT-01..10 | Typed source per activity kind; source required; only the matching column; no two sources | workspace/tests/workspace_activity_source_tests.sql | PASS |
| ACT-11..16 | Non-existent source, cross-student source, non-participant class session, invalid participation rows | same | PASS |
| ACT-17..21 | No duplicate schedule per source; student and kind immutable; own fields still editable | same | PASS |
| ACT-22..26 | Referenced domain records cannot be deleted; removing the schedule keeps the record; no polymorphic column | same | PASS |
| CRD-01..07 | Entitlement recorded at activation; archive inside the window compensates once; reserved credit is not spendable by another student | workspace/tests/workspace_credit_entitlement_tests.sql | PASS |
| CRD-08..13 | Free reactivation re-consumes the SAME credit with no new debit; period not extended; replay; one capacity slot; no second compensation | same | PASS |
| CRD-14/15 | Window bracketed to one second on both sides of 168 hours | same | PASS |
| CRD-16..18 | Reactivation without a reserved entitlement and after the original period ends are refused, leaving no partial state | same | PASS |
| CRD-19/20 | Reactivation that cannot reserve capacity rolls back enrollment, assignment, capacity, entitlement and log together | same | PASS |
| CRD-21..27 | Entitlement row integrity and the wallet balance identity | same | PASS |
| WS-REACT-RACE-01 | Two concurrent reactivations on one reserved entitlement; deterministic coordination through the student row lock (no timing sleep); exactly one succeeds | workspace/tests/workspace_reactivation_race.sh | PASS |
| SEP-01..05 | Only `cp_transfer_approval_executor` may record approval evidence; superuser, runtime and the switch executor are refused | control_plane/tests/cp_37_approval_separation_tests.sql | PASS |
| SEP-06..13 | Recording, replay, assertion-content conflict, Workspace side binding, expiry and future-verification refusal | same | PASS |
| SEP-12b/14/16/17 | The same person cannot hold two incompatible current approval kinds; three distinct approvers complete the set | same | PASS |
| SEP-18..22 | The `source_destination_owner` exception is present, disabled, and cannot be enabled by any DML | same | PASS |
| SEP-23..29 | Revocation idempotency, post-switch immutability, switch fails closed, ownership unchanged | same | PASS |
| SAGA-01..08 | Switch and envelope are one transaction; refused switch leaves nothing; envelope immutable; hash must describe the payload | control_plane/tests/cp_38_saga_outbox_tests.sql | PASS |
| SAGA-09..16 | Lease exclusion, non-holder refused, explicit lease duration, retry on the SAME event id, attempt count never decreases | same | PASS |
| SAGA-17..22 | Acknowledgement per workspace, idempotent, conflicting outcome refused, terminal | same | PASS |
| SAGA-23..30 | Dead-letter is an operator action, idempotent; re-drive returns the same event id; both attributed; audit append-only | same | PASS |
| SAGA-31..34 | The dispatcher cannot write events, change delivery rows, change ownership or switch ownership | same | PASS |
| INB-01..06 | Consumer identity boundary; bad hash, unsupported schema and not-addressed events recorded without effect | workspace/tests/workspace_inbox_tests.sql | PASS |
| INB-07..15 | Stale ignored, future quarantined, destination applies exactly N+1, duplicate returns the recorded outcome, out-of-order never rewinds | same | PASS |
| INB-16..19 | The fence blocks later local commands; the source projection is ended and its assignments closed | same | PASS |
| INB-20..22 | Inbox append-only; the Workspace database holds no Control Plane ownership table | same | PASS |
| Saga service behaviour: freeze/drain, in-flight barrier, snapshot consistency, destination staging, dispatcher crash at each checkpoint, lease expiry under partition, chaos/outage/restore/failover, projection-drift repair | — | — | NOT IMPLEMENTED (SPEC-ONLY, contract section 10) |
| Signed cross-service wire format for Saga envelopes | — | — | NOT IMPLEMENTED (deferred, PS-1..PS-4) |
| Quarantine resolution and re-application | — | — | NOT IMPLEMENTED (OQ-SAGA-2 open) |
| Contact change vs HMAC rotation / vs ownership switch, concurrent | — | — | NOT RUN |
| GitHub Actions for this commit | — | — | NOT VERIFIED by the implementation agent (no Actions access) |

## Supervisor remediation batch on head 8abbbe3 (2026-11-14; author-executed, NOT independently reproduced)

PostgreSQL 16.15, cleared cluster, every database created fresh per step. All 18 runnable workflow steps
completed (ALL_STEPS_PASSED, 504 PASS assertion lines) plus the Python verifier unit tests.

| ID | Check | Where | Status |
|---|---|---|---|
| SAGA-01..03 | Switch, envelope and declared audience are one transaction; a refused switch leaves nothing | control_plane/tests/cp_38_saga_outbox_tests.sql | PASS |
| SAGA-04..11 | Event immutable; hash must describe the payload; audience immutable; an event with no recipient is refused at the constraint check | same | PASS |
| SAGA-R01..R03 | Acknowledgement before send refused; a non-recipient Workspace cannot acknowledge or be reported sent | same | PASS |
| SAGA-R04..R06 | One claim returns a delivery per recipient; a second dispatcher claims nothing; only the lease holder for THAT recipient may report | same | PASS |
| SAGA-R07..R10 | Destination acknowledged while the source received nothing: the source delivery is untouched, the event is not complete, the source stays in the backlog | same | PASS (this is the C-01 defect) |
| SAGA-R11/R12 | Duplicate acknowledgement idempotent; conflicting acknowledgement refused | same | PASS |
| SAGA-R13..R15 | Abandoned lease expires, a restarted dispatcher claims ONLY the outstanding recipient, the stale dispatcher is refused, the remaining recipient is delivered | same | PASS (deterministic wait on a one-second lease) |
| SAGA-R16..R18 | The event becomes complete only after both recipients acknowledge; acknowledged is terminal; per-recipient attempt counts | same | PASS |
| SAGA-R19..R27 | Dead-letter is an operator action, per recipient, idempotent; the other recipient stays deliverable; re-drive returns the same event id; audit per recipient, append-only | same | PASS |
| SAGA-R28..R32 | The dispatcher cannot write events, declare an audience, change delivery rows, change ownership or switch ownership | same | PASS |
| CRD-01/01b | Activation whose period already ended is refused by the post-lock check; a missing period is refused | workspace/tests/workspace_credit_entitlement_tests.sql | PASS |
| CRD-07a/b/c | An active non-counselor and a suspended counselor cannot be appointed responsible; neither refusal left state | same | PASS |
| CRD-11b, CRD-12b | Reactivation replay naming a different counselor refused; the command log binds the counselor | same | PASS |
| CRD-28..31 | The production-intended activation path fails closed (OQ-CRD-3); the Runtime cannot reach the synthetic command or the resolver; no partial state | same | PASS |
| WS-CRD-LOCK-01 | The reversal window is decided from the clock read AFTER the entitlement lock: 2 seconds of window, 8-second lock wait, no credit returned | workspace/tests/workspace_credit_lock_boundary_race.sh | PASS |
| WS-CRD-LOCK-02 | Control: 1 hour of window and the same wait still returns credit | same | PASS |
| WS-CRD-LOCK sensitivity | Reverting the archive clock/lock order makes case A return credit (1 reversal instead of 0) | manual re-run of the pre-fix code | VERIFIED (the test fails against the defect) |
| WS-ROLE-18/19 | The Runtime holds neither the synthetic activation command nor the period resolver; the synthetic identity keeps its own grant | workspace/tests/workspace_role_privilege_tests.sql | PASS |
| INB-02a/b/c/d | The worker's production-intended inbox path fails closed; the worker cannot reach the synthetic path or the transport gate; nothing recorded, fence unmoved | workspace/tests/workspace_inbox_tests.sql | PASS |
| Saga service behaviour: freeze/drain, in-flight barrier, snapshot consistency, destination staging, real process crash, partition, chaos, outage/restore/failover, projection-drift repair, quarantine resolution | — | — | NOT IMPLEMENTED (SPEC-ONLY, contract section 10) |
| Verified transport / signed wire format for inbox and outbox envelopes | — | — | NOT IMPLEMENTED (OQ-SAGA-1, PS-1..PS-4/PS-6) |
| Entitlement period source | — | — | NOT IMPLEMENTED (OQ-CRD-3); production path fail-closed |
| Contact change vs HMAC rotation / vs ownership switch, concurrent | — | — | NOT RUN |
| GitHub Actions on the final HEAD of this batch | — | — | NOT VERIFIED by the implementation agent (no Actions access) |

## Supervisor final review corrections (2026-11-14; author-executed, NOT independently reproduced)

Reviewed HEAD before this batch: `14c76fdaf2ae33dc6af4b437a5376cfb5c411412`, whose CI runs
[43502040401](https://github.com/nourihamed/persian-educational-counseling-os/actions/runs/43502040401) and
[43502032586](https://github.com/nourihamed/persian-educational-counseling-os/actions/runs/43502032586)
both completed **success** on PostgreSQL 16. CI for the HEAD produced by this batch must be read from the
Actions tab for that exact SHA and is **NOT VERIFIED** by the implementation agent.

Local run: PostgreSQL 16.15, cleared cluster, every database created fresh per step.

| ID | Check | Where | Status |
|---|---|---|---|
| CRD-32 | The deadline is exactly 168 hours (604800 s) after the activation timestamp | workspace/tests/workspace_credit_entitlement_tests.sql | PASS |
| CRD-33 | One microsecond BEFORE the deadline is eligible | same | PASS |
| CRD-34 | The EXACT deadline is eligible (inclusive boundary, OQ-CRD-1 as approved) | same | PASS |
| CRD-35 | One microsecond AFTER the deadline is ineligible | same | PASS |
| CRD-36 | Eligibility holds from the activation instant through the deadline and not beyond | same | PASS |
| CRD-37 | The deadline and the verdict are identical in UTC, Asia/Tehran, America/Los_Angeles and Pacific/Kiritimati | same | PASS |
| CRD-38 | The archive command evaluates the shared rule and keeps no second copy of the 168-hour interval | same | PASS |
| WS-CRD-LOCK-01/02 | Unchanged and still passing: the command reads its wall clock only AFTER the entitlement row lock, with the control case | workspace/tests/workspace_credit_lock_boundary_race.sh | PASS |

CRD-32..38 drive `credit_reversal_eligible()` with explicit timestamps, so equality at the deadline is
tested exactly rather than bracketed. They do not replace WS-CRD-LOCK-01/02 and that test was not weakened.

Still NOT RUN / NOT IMPLEMENTED after this batch (unchanged): Saga service behaviour in contract section 10,
quarantine resolution (OQ-SAGA-2), verified transport and signed wire format (OQ-SAGA-1, PS-1..PS-4/PS-6),
the entitlement period source (OQ-CRD-3), disposition of an expired reserved entitlement (OQ-CRD-2),
per-subject exam results, curriculum subtopics and PlanItem, retention schema integration (Q-020), and
contact change concurrency against HMAC rotation and against an ownership switch (NOT RUN).
