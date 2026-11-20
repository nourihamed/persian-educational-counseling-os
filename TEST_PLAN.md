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
| M-05, M-06 | residual findings | OPEN — defined by the Supervisor on 2026-11-18 as MEDIUM technical debt (see the 2026-11-18 F-01..F-04 section) |

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

## Batch 1 — source transfer freeze and database write barrier (2026-11-14)

`docs/phase2/workspace/tests/workspace_transfer_freeze_tests.sql` — FRZ-01..FRZ-37, run on a fresh database
by workflow step "Workspace source transfer freeze and database write barrier". 37 assertions, 36 PASS lines
(FRZ-26 and FRZ-27 share one line). Coverage:

- FRZ-01 asserts from the catalog, not from a list in the test, that **all 26** student-scoped tables carry
  the barrier trigger. The count comes from `student_write_barrier_coverage`, so a new student-scoped table
  added without a barrier makes this test fail rather than silently passing.
- FRZ-02..FRZ-09 authority: the Workspace runtime, worker and exporter roles cannot freeze or unfreeze; only
  the transfer-controller identity can.
- FRZ-10..FRZ-15 freeze record integrity: uniqueness per token and per (student, case, source generation),
  one live freeze per student, stale source generation refused, a different token for the same case refused,
  non-zero outstanding work refused.
- FRZ-16..FRZ-22 the write barrier: INSERT, UPDATE and DELETE on student-scoped tables are refused while
  frozen, including **as the table owner**, which is a stronger claim than refusing the runtime role —
  FRZ-16/17 originally reported a privilege error (42501) rather than the barrier's own check violation
  (23514), and were moved to run as the owner so they test the barrier and not the grant.
- FRZ-23..FRZ-29 unfreeze: pre-switch only, token-bound and case-bound, idempotent on replay, writes resume
  after an abort, an unfrozen record cannot be reactivated.
- FRZ-30..FRZ-37 the fence: after the source observes the switch the freeze becomes permanent, unfreeze is
  refused with a distinct message, the bypass row is transaction-scoped and keyed on `txid_current()`, and
  the freeze audit records `('signed_receipt', false)` so no authenticity is implied.

`docs/phase2/workspace/tests/workspace_freeze_barrier_race.sh` — WS-FRZ-BARRIER-01..04, run in **two modes**
by workflow step "Workspace in-flight transaction barrier race (both modes)". 8 PASS lines.

- The coordination is deterministic, not timing-based: the in-flight writer waits for an explicit go signal,
  and the driver sends it only after observing the freeze blocked on a lock in `pg_stat_activity`.
- BARRIER-01 the freeze blocks until the in-flight transaction settles; BARRIER-02 the in-flight write
  **survives** (a barrier drains, it does not discard); BARRIER-03 `barrier_watermark_txid` is strictly later
  than the drained writer's transaction id; BARRIER-04 no write is accepted after the barrier closed.
- **Sensitivity was verified and the first version of this test was not sensitive.** With the `FOR SHARE`
  lock removed from `assert_student_not_frozen`, mode `fk` (a `study_sessions` write) still passes, because
  PostgreSQL's own foreign-key row lock blocks the freeze for any table with a foreign key to `students`.
  Mode `nofk` writes `class_session_participants`, which is student-scoped but references
  `class_participants` rather than `students`, and that mode **fails** (exit 2) without the barrier. Both
  modes run; only `nofk` is evidence for the barrier this project added.

Still NOT RUN / NOT IMPLEMENTED after this batch: the freeze of API, worker, import, export and file
surfaces (those surfaces do not exist in this repository); correctness of the caller-reported outstanding-work
count; freeze duration, drain timeout and acceptance thresholds (OQ-E, deliberately not invented); snapshot
consistency, destination staging, real process crash, partition, chaos, outage/restore/failover and
projection-drift repair (Saga contract section 10); quarantine resolution (OQ-SAGA-2); verified transport and
signed wire format (OQ-SAGA-1, PS-1..PS-4/PS-6); the entitlement period source (OQ-CRD-3); disposition of an
expired reserved entitlement (OQ-CRD-2); per-subject exam results; curriculum subtopics and PlanItem;
retention schema integration (Q-020); and contact change concurrency against HMAC rotation and against an
ownership switch.

## Batch 2 — clock discipline at security decision points (2026-11-14)

Three independent instances of one defect were found: a security decision made from a **transaction-start**
clock. In PostgreSQL `now()`, `transaction_timestamp()` and `CURRENT_TIMESTAMP` all return the time the
transaction began and do not advance, so any expiry, freshness or authorization decision made from them can
be defeated by holding a transaction open. Each instance was **demonstrated before being fixed**, and each
test below was **shown to fail against the pre-fix code**.

### `receipt_60_freshness_tests.sql` — RC-FRESH-01..04 (5 PASS lines)
The governance proof-receipt validity window. Demonstrated defect: a receipt with a two-second lifetime was
consumed and applied four seconds after expiry, ending up `consumed` with a governance event attached.

- RC-FRESH-01 a receipt that expires while the consuming transaction is open is refused.
- RC-FRESH-02 the refusal leaves the receipt `registered`, with no consumption metadata and no event.
- RC-FRESH-03/03b the mirror case — a receipt whose `not_before` passes *during* the open transaction is
  accepted, and `consumed_at` is at or after `not_before`. This catches a "fix" that froze a different
  clock or compared in the wrong direction.
- RC-FRESH-04 static guard on the function body.

Why RC-21/RC-22 did not catch it: their receipts were already outside the window when the transaction
began, which `now()` evaluates correctly. The defect only appears when the window closes *during* the
transaction, which is the case nothing tested.

**Sensitivity:** against the pre-fix function (identical but `v_now := now()`), RC-FRESH-01 fails with the
diagnostic naming the cause. Measured, not assumed.

### `cp_47_freshness_tests.sql` — CC-FRESH-01..03 (3 PASS lines)
The one-time contact-change proof window, which authorizes changing a student's **global** contact identity.
Same defect shape. Runs after `cp_40_contact_change_tests.sql` in the same database and reuses its helpers.

- CC-FRESH-01 a proof that expires during the open transaction is refused.
- CC-FRESH-02 the refusal leaves the proof `registered`, with no command reservation and no audit row.
- CC-FRESH-03 static guard on the command body.

**Sensitivity:** against the pre-fix command, CC-FRESH-01 fails. Measured.

### `workspace_clock_discipline_tests.sql` — CLK-01..03 (3 PASS lines)
The guard that protects against a fourth instance, plus the `guardian_permissions_effective` fix.

- CLK-01 **catalog-driven**: scans every SECURITY DEFINER function and every view for a transaction-start
  clock and fails **by name**. It carries one reviewed allowlist entry
  (`append_workspace_governance_event`, whose `granted_at=now()` writes a stored value and decides
  nothing). A new site must be fixed or explicitly reviewed into the allowlist with a reason.
- CLK-02 narrower: the specific windows that were defective must still read `clock_timestamp()`. This
  survives an over-broad edit to CLK-01's allowlist.
- CLK-03 **behavioural**: a guardian permission that expires mid-transaction stops being effective. A
  static check alone would miss a view rewritten to compare against a column holding a stale value.

`guardian_permissions_effective` is the Workspace's guardian authorization read shape — its own comment says
so — and with `now()` a permission that expired during a transaction still read as effective, which *was*
the access decision.

**Sensitivity:** against the pre-fix view, CLK-01 fails naming `view guardian_permissions_effective`.
Measured.

CLK-03 deliberately leaves its fixture behind: the guardian event tables are append-only (WS-DOM-03) and
cannot be cleaned up, as an earlier version of the test discovered when its DELETE was refused with
"guardian_permission_events is append-only". The suite therefore runs in its own database in CI.

### Recorded timestamps aligned with the decision clock
`archive_student_enrollment()` and `change_student_mobile_contact()` now write their stored timestamps
(`ended_at`, `archived_at`, `consumed_at`, `updated_at`) from the same post-lock `v_now` they decide from,
so the audit time equals the decision time. These were never decisions and were not defects; the change
makes the rule uniform and lets the static guards stay strict.

Still NOT RUN / NOT IMPLEMENTED after this batch: everything listed at the end of the Batch 1 section, plus
clock-skew tolerance (PS-5, deliberately none), end-to-end revocation freshness across service handoffs
(PS-8, no services exist), and signature verification (PS-1..PS-4, the verifier stays fail-closed).

## Batch 3 — Student Credit ledger invariants (2026-11-14)

Batch 3 was a **verification** task, so the method was to check each required property against what the
tests actually assert. Three properties had **no test at all**, and two real defects were found through
them. The full verification matrix is in `docs/phase2/IMPLEMENTATION_RESPONSE_2026-11-14.md` section 8.

### `workspace_credit_ledger_invariant_tests.sql` — CRD-39..47 (12 PASS lines)
Runs after `workspace_credit_entitlement_tests.sql` in the same database and reuses its fixtures.

- **CRD-39/40/41 — the central invariant, previously untested.** "No negative or inconsistent spendable
  balance" had no test. CRD-27 checked the balance *identity*
  (`available = ledger − reserved − recommitted`), which is a different claim — an identity can hold
  perfectly while the balance is negative. CRD-39 refuses a debit larger than the whole ledger; CRD-40
  refuses exactly `available + 1`; **CRD-41 is the control** — exactly `available` must be accepted and
  leave 0, otherwise CRD-39/40 would also pass against a guard that refuses everything.
- **CRD-42/43 — the defect.** A reversal with the correct wallet, exact opposite amount and an unreversed
  debit, but naming a **different student**, was accepted before the fix (`student_matches_debit = f`).
  CRD-43 closes the NULL loophole.
- **CRD-44/45 — append-only for UPDATE.** CRD-05 covered DELETE only; amending a row or re-pointing it at
  another student was untested.
- **CRD-46/46b** — a negative grant and an unknown wallet are refused.
- **CRD-46c/46d** — neither the Workspace runtime nor the worker can insert a ledger row directly. This
  also bounds the severity of CRD-42: the misattribution was never reachable from an application role.
- **CRD-47 — the anti-regression guard.** Asserts from the catalog that exactly one
  `validate_credit_reversal()` and exactly one guard trigger exist, and that the body still carries the
  balance check, the student binding and the row lock.

### `workspace_credit_last_unit_race.sh` — WS-CRD-LAST-01..05 (5 PASS lines)
The concurrency half of the same invariant, which the existing races did not cover:
`workspace_activation_race.sh` has both sessions activate the **same** enrollment and the wallet is never
scarce there. Here two **different** students race for a wallet holding exactly one unit.

Deterministic: session A activates and holds the wallet lock, the driver waits until that lock is held,
starts B, confirms B is blocked, and only then **signals A to COMMIT** — A is never killed, because
terminating it would abort its transaction, release the credit and let B succeed legitimately. An earlier
version of this script did exactly that and produced a misleading pass.

Asserts: B blocked rather than reading a stale balance; exactly one debit; available balance 0 and never
negative; exactly one enrollment, entitlement and capacity slot; the loser refused for insufficient credit
with nothing partial left behind.

### Sensitivity, measured for every new test
| Control | Result |
|---|---|
| Student binding removed from the guard | CRD-42 fails (exit 3) |
| A weak duplicate guard replaces the strong one | CRD-39 fails (exit 3) |
| Wallet row lock removed from the guard | WS-CRD-LAST-02/03/04/05 fail; measured `debits=2 ledger=-1 available=-1 entitlements=2 capacity=2` |
| Pre-existing credit suite after the guard consolidation | unchanged: 43 PASS lines, exit 0 |

One nuance recorded in the race script itself: in the no-lock control the "second activation is blocked"
observation **still appears**, because the activation command takes other row locks and B blocks on those
regardless. That observation proves only that the sessions overlapped; the outcome assertions are the
evidence. This is the same trap that made the first version of the Batch 1 barrier race worthless.

Still NOT RUN / NOT IMPLEMENTED after this batch: OQ-CRD-2 (no expiry, extension, forfeiture or automatic
return of a reserved entitlement is implemented), OQ-CRD-3 (the production activation path stays
fail-closed on the entitlement period), and everything listed at the end of the Batch 1 and Batch 2
sections.

## Batch 4 — Assessment, exam and analysis model (2026-11-14, re-verified 2026-11-15)

`docs/phase2/workspace/tests/workspace_assessment_exam_tests.sql` — EXM-01..42, run by workflow step
"Apply Workspace draft and run schema regression suite", which went from 116 to **158 PASS lines**.
Verification matrix for the brief's eight items: `IMPLEMENTATION_RESPONSE_2026-11-14.md` section 9.

New structures tested: `exam_definition_versions` and `exam_definition_version_subjects` (immutable
published blueprint; publication refused unless per-subject counts add up), `exam_subject_results`
(per-subject results with composite foreign keys refusing cross-exam and cross-student rows
declaratively, reconciled with the aggregate by a `DEFERRABLE INITIALLY DEFERRED` constraint trigger), and
`test_analysis_versions` / `test_analysis_response_findings` (append-only, so a reclassification is a new
version rather than a mutation of an immutable submitted response).

### Sensitivity, measured — and one documented control that turned out to be wrong

| Control | Result |
|---|---|
| Predicate replaced by **type comparisons only** | **FAILS** (exit 3). EXM-42: "the predicate returned NULL for: empty object, no algorithm_version, no algorithm". In the full suite EXM-01 fires first. Against the committed predicate EXM-42 passes. |
| Reconciliation trigger body replaced by `RETURN NULL` | **FAILS** (exit 3) at EXM-26 with the exact expected message. |
| ~~Removing only `COALESCE(..., false)`~~ | **DID NOT REPRODUCE.** This control was claimed in the first draft of the Batch 4 notes and the claim was wrong. With the `length(btrim(COALESCE(p->>'algorithm','')))>0` conjunct still present the chain evaluates to **false**, not NULL, because `NULL AND false` is `false`. Measured: the predicate returned `false` for `{}` and the suite passed. |
| ~~Dropping the reconciliation trigger~~ | **INVALID AS A CONTROL.** EXM-26 runs `SET CONSTRAINTS exam_results_reconcile_trg IMMEDIATE` to observe the deferred check, so dropping the trigger fails the test's own setup ("constraint does not exist") and proves nothing about reconciliation. |

The two underlying facts the predicate defends against were measured directly rather than recalled:
`jsonb_typeof('{}'::jsonb -> 'algorithm') = 'string'` is **NULL**, and a `CHECK` constraint whose
expression is NULL **accepts** the row (`INSERT 0 1` against a temp table carrying exactly that check).

### Still NOT IMPLEMENTED after Batch 4, and not claimed
Scoring formulas, rounding and score validation (by design — the database stores and compares snapshots and
never computes a score); which algorithm **names** are permitted (OQ-ASM-2, raised by this work); rank,
percentile and cohort comparison; a custom error taxonomy table (`test_responses` carries a fixed enum plus
free-text `custom_error_reason`, so custom reasons are not reusable or countable as categories);
`test_attempt_questions` (correctly absent — adaptive delivery cannot be published); and everything listed
at the end of the Batch 1, 2 and 3 sections.

## Batch 5 — curriculum and student-ownership boundaries (2026-11-15)

### `workspace_curriculum_tests.sql` — CUR-01..CUR-10 (10 PASS lines, own database in CI)
Covers the one hierarchy level the Product Owner scoped in: `subtopics`. CUR-01..04 ordered membership and
that order numbers are scoped to the parent topic rather than global; CUR-05/06 shape; CUR-07 a topic with
subtopics cannot be deleted; CUR-08 archiving in place preserves references.

- **CUR-09 asserts deletion behaviour from the catalog.** It fails if **any** foreign key in the Workspace
  schema has a non-default delete action. There is no `ON DELETE` anywhere today, so this held by
  convention and nothing checked it; a cascade or set-null added later would destroy the educational
  history the curriculum contract requires be preserved.
- **CUR-10 asserts an absence.** Book/Edition tables must not exist, so the WS-DOM-05 gap stays explicit
  and dated rather than looking like an oversight — and the assertion fails loudly if someone adds them
  without updating the register.

### Freeze suite extended — FRZ-01b, FRZ-01c, FRZ-18b, FRZ-18c (step rose from 36 to 40 PASS lines)
FRZ-01 asks "does every table in the coverage view have a trigger?" — which **cannot** catch a per-student
table that is missing from the view. That is how five tables were unprotected.

- **FRZ-01b** asks the opposite question from the catalog: which tables have a foreign key into a
  per-student table and yet carry no barrier? Anything new fails **by name**. Eleven reviewed exclusions,
  each stating one of only two valid reasons — the table is **shared** between students (barring it would
  let one frozen student block writes others depend on), or it must be writable **while** frozen because it
  is part of the freeze machinery (`workspace_inbox_events`: the inbox projection *applies* the fence).
- **FRZ-01c** pins the five tables found in Batch 5, so an over-broad edit to FRZ-01b's exclusion list
  cannot quietly drop them again.
- **FRZ-18b/18c are behavioural**, not structural: a two-hop resolution that silently returned NULL would
  leave the barrier open while still reporting as covered, because `assert_student_not_frozen()` returns
  early for a NULL student. FRZ-18c exercises the two-hop guardian path (permission → link → student).

FRZ-01b found the three guardian tables **immediately on being written**, after the first two had been
fixed by hand — which is the argument for writing the audit rather than fixing the instances.

### Still NOT RUN / NOT IMPLEMENTED after Batch 5
`plan_items` and therefore any referential integrity for plan contents (WS-PLAN-01); the planning engine,
determinism/replay and normalized planning inputs (Phase 12); Book/Edition, curriculum successor mapping,
platform-versus-Workspace content ownership and subtopic-level mastery (WS-DOM-05) — so the curriculum
contract's isolation tests cannot be run and are not claimed; plus everything listed at the end of the
Batch 1–4 sections.

## Batch 6 — adversarial privilege review (2026-11-15)

`workspace_privilege_hardening_tests.sql` — SEC-01..SEC-10 (12 PASS lines), run inside the governance
receipt step, which is the only step that has **every** role and **every** SECURITY DEFINER function
loaded — which is what these assertions need.

Every assertion queries the **catalog** and describes a property that must hold for all definer functions
and all roles, rather than checking a list of remembered names. That is the point: reading the SQL is how
the superuser-owned function survived several passes.

| Test | Asserts |
|---|---|
| SEC-01 | No SECURITY DEFINER function is owned by a superuser. **This one found a real defect.** |
| SEC-02 | Every definer function pins a search_path (an unpinned one resolves through the *caller's*). |
| SEC-02b | Neither `PUBLIC` nor any application role may `CREATE` in `public` — the precondition for shadowing an unqualified name inside a definer function. |
| SEC-02c | Reports definer functions still carrying `public` on their path as a NOTICE: tracked as hardening, **not** claimed fixed, because SEC-02b shows it is not exploitable. |
| SEC-03 | Every definer owner is NOLOGIN. |
| SEC-04 | No application role owns a table (an owner can disable triggers). |
| SEC-05 | No Workspace role holds superuser / createrole / createdb / bypassrls. |
| SEC-06 | `PUBLIC` holds no table privilege — one stray grant would reach every role in the cluster, including other Workspaces'. |
| SEC-07 | No non-trigger definer function is executable by `PUBLIC`, except `assert_student_not_frozen`, which is PUBLIC on purpose. |
| SEC-08 | **A limitation, asserted rather than hidden:** the table owner really *can* disable triggers, so no trigger-based guard contains the owner or a superuser. |
| SEC-09 | Every table has a primary key. |
| SEC-10 | **The headline negative result, asserted as a test:** no row-level security anywhere, and the runtime role holds SELECT on 47 tables in full, so counselor-to-counselor isolation inside a Workspace is **not** enforced here. Fails if the situation changes in either direction, so the record cannot rot. |

### Sensitivity, measured
With the `ALTER FUNCTION public.receipt_consume_grant_guard() OWNER TO ...` line removed from
`receipt_02_roles_draft.sql`, the owner is `postgres` again and **SEC-01 fails** naming the function
(exit 3).

### Still NOT RUN / NOT IMPLEMENTED after Batch 6
Object-level authorization, IDOR and uniform-404 behaviour (API properties; no API exists); background-job
tenant context (no jobs run); file and notification ownership (neither subsystem exists); RLS policies and
therefore RLS bypass testing — the absence is itself the finding (WS-ISO-01); counselor-to-counselor
isolation; and everything listed at the end of the Batch 1–5 sections.

## Batch 7 — contact identity, HMAC rotation and concurrency (2026-11-15)

### `cp_48_contact_identity_race.sh` — the two races the brief listed as NOT RUN (6 PASS lines)
Both serializations were designed in and documented in comments, and neither had ever been executed.

- **Mode `a`** — contact change in flight, HMAC rotation begins. `change_student_mobile_contact()` holds
  `FOR SHARE` on `identity_write_gate`; `begin_identity_hmac_rotation()` takes `FOR UPDATE` on that row
  and must block. CID-RACE-A1 the block, A2 both committing in order, A3 a contact change during
  maintenance mode being refused.
- **Mode `b`** — contact change in flight, ownership switch for the same student. The contact change holds
  `FOR UPDATE` on the student's `student_ownership` row, so `switch_student_ownership()` must block;
  afterwards the generation advances 1 → 2, ownership moves to the destination, and a contact change citing
  the pre-switch generation is refused. CID-RACE-B1/B2/B3.

Deterministic: the first session waits for an explicit go signal, sent only after the driver has
**observed** the second session blocked in `pg_stat_activity`, and the first session is signalled to commit
rather than killed. The older `cp_46_contact_change_race.sh` orders its sessions with `sleep 0.6` plus
`pg_sleep 2`; this one does not.

**Each mode runs in its own fresh database**, and that is load-bearing rather than tidy: race A completes a
rotation (key version 1 `retiring`, 2 `active`) and advances a student's ownership generation. Sharing one
database made race B's contact change abort on preconditions race A had changed, which **looked exactly
like a missing lock in the implementation**. It was not — see the sensitivity table.

| Control | Result |
|---|---|
| `FOR SHARE` on `identity_write_gate` removed | race A **fails** at CID-RACE-A1 |
| `FOR UPDATE` on `student_ownership` removed | race B **fails** at CID-RACE-B1 |

### `cp_49_contact_confidentiality_tests.sql` — CID-01..CID-05b (6 PASS lines)
Catalog assertions, so a column or index added later fails by name: no text column can hold a plaintext
contact (CID-01); every fingerprint is pinned to 32 bytes and the contact is bytea ciphertext (CID-02); the
key-version tables hold no key material — no bytea, text only as an opaque `*_ref` or a CHECK-pinned enum
(CID-03); exactly one active HMAC key version and a second is refused (CID-04); global identity is unique
per `(key_version, mobile_hmac, grade_key)` across `active` **and** `transfer_pending` claims (CID-05).

**Two of these tests were wrong first and the schema was right**, which is recorded in the file itself:
CID-03 initially banned all text and flagged `key_manager_ref`, which is the non-secret KMS identifier the
register recommends for PS-3; CID-05 initially looked for fingerprint uniqueness on `student_contact_index`,
which deliberately has none — it answers what a student's contact is, not who owns a contact. So two
students **can** share a fingerprint in the contact index; they cannot hold live claims on it in the same
grade under the same key.

### `check_no_secret_material.py` — REPOSITORY CHECK, not implementation evidence
Scans tracked files for plaintext contacts (Iranian mobile and generic E.164), long literals assigned to
secret-shaped names, PEM private-key blocks and tracked credential files, and checks every path ever
**added** in Git history for credential-file names. Result: **147 tracked files, 186 historical paths, no
findings.** Verified sensitive by planting a fake Iranian number and a fake API key — all three expected
findings fired. It does not flag this project's synthetic shapes (`repeat('aa',32)`, `decode('…','hex')`),
because flagging fixtures trains a reader to ignore the check. It states its own limit: a pattern scan
proves the absence of known shapes, not the absence of secrets.

### Still NOT RUN / NOT IMPLEMENTED after Batch 7
Production key management (PS-1..PS-4: no algorithm, key policy, rotation schedule or revocation source is
invented; rotation is tested as a mechanism only); any cryptographic strength claim; proof that an opaque
`_ref` holds a non-secret (not establishable in a database); recovery of a partially completed rotation
across a process crash (needs a process, none exists); plus everything listed at the end of the Batch 1–6
sections.

## Batch 8 — files, notifications, retention and operational contracts (2026-11-15)

### `workspace_transfer_freeze_tests.sql` — FRZ-38..FRZ-43, the barrier's blind side (6 new PASS lines)
The barrier resolved the owner from `NEW` on `INSERT` and `UPDATE` and from `OLD` only on `DELETE`, so an
`UPDATE` that **rewrote the ownership column** was checked against its destination. Demonstrated as
accepted on a loaded database, with the student frozen: moving the file to another student, moving the
study session, and setting the owner to `NULL` (a NULL destination short-circuits the assertion). `DELETE`
was refused throughout, which is why two previous audits missed it.

- FRZ-38/39/40 — the three demonstrated moves, now refused with the **freeze** reason (the freeze is
  asserted before the ownership rule so the more specific refusal wins).
- FRZ-41 — the one allowed direction: an **unowned** row may acquire an owner.
- FRZ-42 — re-pointing that row afterwards, with **neither** student frozen, is refused as forward-only.
- FRZ-43 — an **indirect** ownership key behaves the same (`counselor_assignments.enrollment_id`). It runs
  without `SET SESSION AUTHORIZATION` because the runtime role holds no `UPDATE` there and a permission
  denial would mask what the test is for.

| Control | Result |
|---|---|
| `student_write_barrier()` reverted to the pre-Batch-8 `NEW`-only shape | freeze suite **fails at FRZ-38**, 46 → 40 PASS |

### `workspace_operations_tests.sql` — OPS-01..OPS-64 (53 PASS lines)
Runs in its own database: OPS-45 freezes a student and OPS-48 inserts a synthetic approved retention
policy, neither of which may leak into another suite.

- **Files, OPS-01..OPS-08.** Content hash, object key, size, type, key version and uploader are immutable;
  `quarantined → available` is allowed once, `available → quarantined` is not, `archived` is terminal, the
  row cannot be deleted, and an object is not created archived.
- **Notifications, OPS-10..OPS-24.** Three valid recipient classes (active member; the student the
  notification is about; a verified, unrevoked guardian **of that student**) and four refusals that matter:
  **OPS-13** the same guardian for a *different* student, **OPS-14** a suspended membership, OPS-15 a
  stranger, OPS-16 a Workspace-level notice to a stranger. OPS-17/18 refuse a plaintext Iranian mobile
  nested inside the payload and an E.164 number; OPS-19 accepts a masked display. OPS-20..OPS-23:
  recipient, subject and payload immutable, `read_at` set once, no delete. **OPS-24** asserts from the
  coverage view that the transfer write barrier now covers the table at all.
- **Legal holds and the entity registry, OPS-30..OPS-39.** A hold on an unregistered type or on a target
  that does not exist is refused — it would otherwise protect nothing while the register said the data was
  held. Scope and placement immutable, release the only permitted change, no delete. The registry refuses
  an entry naming a missing table or a non-uuid key, and cannot be emptied.
- **Retention policy, OPS-40..OPS-44.** Nine categories, nine `needs_decision` versions, **nothing
  approved** — OPS-40 fails if a draft ever approves a period, because that would be a Product Owner
  decision made in code. A version cannot be flipped to `approved` by `UPDATE`, nor deleted; `approved`
  without duration, action, approval reference and effective date is refused by CHECK, and
  `needs_decision` may not carry a duration.
- **The fence, behaviourally, OPS-45/46.** A notification about a **frozen** student is refused; one about
  an unfrozen student is still accepted. This property could not be expressed before this batch.
- **The gate, OPS-47..OPS-51.** Five distinct refusals, each verified by reason text: non-destructive
  action, unregistered type, missing target, live hold, no approved policy. **OPS-48 is the one that makes
  the rest meaningful:** with a synthetic approved policy (`approval_ref` =
  `SYNTHETIC-TEST-FIXTURE-NOT-A-PRODUCT-OWNER-DECISION`) the gate **allows**; a hold then overrides the
  approved policy; two conflicting approved policies fail **closed** on ambiguity. OPS-49 pins
  `clock_timestamp()` narrowly, surviving an over-broad edit to the CLK-01 allowlist. OPS-50/51 assert that
  **nobody** may execute the gate and **no** application role may write `legal_holds`, so a later grant
  fails the suite instead of passing silently.
- **TRUNCATE, OPS-60..OPS-64.** Coverage from the catalog (31 tables claim immutability, zero holes), three
  behavioural refusals, and **OPS-64, the honesty assertion**: measured, no application role holds
  `TRUNCATE` on any table, so these guards are hardening rather than a fixed vulnerability — and if that
  ever changes, OPS-64 fails and the hardening becomes load-bearing.

**Masking recorded, not hidden:** a plain `TRUNCATE` of a table another table references is refused by
PostgreSQL with `0A000` **before any trigger runs**, so OPS-62/63 would have proved nothing about this
guard — the same class of masking as the foreign-key row lock in the freeze race. `CASCADE` is used where a
foreign key exists; `audit_events` is referenced by nothing, which makes OPS-61 the sensitive one.

| Control | Result |
|---|---|
| `assert_notification_recipient_allowed` stubbed to return | **fails at OPS-13** |
| `jsonb_has_plaintext_contact` stubbed to `false` | **fails at OPS-17** |
| `retention_entity_exists` stubbed to `true` | **fails at OPS-30** |
| TRUNCATE guard dropped from `audit_events` | **fails at OPS-60** (the coverage test, before OPS-61) |
| the gate's legal-hold check removed | **fails at OPS-47.4** |

### Still NOT RUN / NOT IMPLEMENTED after Batch 8
No actual disposition: there is no executor, object-store client, export pipeline, cache, search index,
replica or backup tooling, so **completeness of erasure is not tested and not claimed**
(OPS-RETENTION-SCOPE) and restore-time suppression does not exist. No delivery-time notification
re-authorization, which needs a worker (OPS-NOTIF-DELIVERY, overlapping PS-8). No hold or disposition
**authority** (OPS-HOLD-AUTH, OPS-DISP-AUTH) — the mechanisms are built and uncallable. No retention period
(Q-020). No notification channel adapter, and no anti-virus or content scanning: `quarantined → available`
is enforced as a transition, but what clears a scan is a service that does not exist. Nothing about the
table owner or a superuser, per SEC-08. Plus everything listed at the end of the Batch 1–7 sections.

## 2026-11-18 — Supervisor corrections

### `workspace_counselor_isolation_tests.sql` — ISO-C1..ISO-54 (42 PASS lines, 3 OPEN lines)
The WS-ISO-01 **boundary**, in one Workspace with seven memberships (two counselors with their own students, a
co-assigned counselor, an unaccepted assignment, a suspended counselor, an assistant, a manager). Catalog
coverage of all 32 student-scoped tables (ISO-C1/C2); direct ids (ISO-01..09); guessed ids of related records,
including indirect and two-hop owners and an existence-oracle check (ISO-10..19b); private-note visibility
(ISO-20..23); list (ISO-30..32); report totals (ISO-33/34); write paths (ISO-40..43); revocation through every
surface (ISO-50..54). **ISO-GAP-01..03 are OPEN lines, not PASS lines**: they measure that the shared runtime role
still reads counselor B's rows and that no student-scoped table has RLS, and they fail if that changes.
**They prove the boundary is correct, not that cross-counselor access is prevented at the database.**

| Control | Result |
|---|---|
| acceptance condition removed from the predicate | fails ISO-04 |
| counselor-role condition removed | fails ISO-06 |
| private-note visibility rule removed | fails ISO-21 |
| report computed over all students | fails ISO-33 |
| counselor-note trigger dropped | fails ISO-40 |
| Batch 8 recipient rule restored | fails OPS-13c |

### `check_no_secret_material.py` — SEC-REPO-01..05 (repository check, NOT implementation evidence)
SEC-REPO-03 now scans historical blob **content**; SEC-REPO-04 warns about untracked files it did not scan;
SEC-REPO-05 has nine planted cases including the "synthetic"-on-the-line regression. Controls: a PEM block
committed and then deleted is found in history; a shallow clone fails closed; the pre-2026-11-18 line-level
allowlist fails SEC-REPO-05.

### `check_unresolved_register.py` — REG-07/REG-08 (documentation check, NOT implementation evidence)
REG-07 requires every item's classification; REG-08 requires the Markdown table to agree with the JSON row by
row. Control: changing WS-ISO-01's Markdown gate impact to `NON_BLOCKING_FAIL_CLOSED` fails REG-08.

### Still NOT RUN after 2026-11-18
GitHub Actions at the new HEAD. Any test of counselor isolation as each counselor's own database identity — it
cannot exist until the caller-binding decision. Everything listed at the end of the Batch 1–8 sections.

## 2026-11-18 — WS-PLAN-01 normalized PlanItem data model

### `workspace_plan_items_tests.sql` — PLN-C1..C4, PLN-01..PLN-63 (61 PASS lines)
- **Catalog:** barrier coverage, no UPDATE/DELETE for the runtime, exactly-one-source CHECK with no polymorphic column,
  and the approved vocabularies pinned exactly.
- **Items (PLN-01..17):** one item per approved source kind; zero or two sources refused; another student's exam
  refused; a mismatched student refused; counselor B and a manager refused; unknown time zone refused; UTC derived
  (and a supplied wrong value replaced); UPDATE, DELETE and TRUNCATE refused — both by grants and, for an identity
  holding the privilege, by the trigger.
- **Versions (PLN-20..29b):** normalized version carries no JSON; no items on legacy versions; author required;
  no items after publication; v2 requires predecessor and reason; cross-plan supersession refused; no regression to
  legacy; version metadata fixed; v1 unchanged by v2.
- **Transitions (PLN-30..46):** stale transition refused; deferral rules both ways; out-of-vocabulary status and
  reason refused; `other` without a note accepted; reason required otherwise; skipped sequence refused; cross-counselor
  actor refused; mismatched student refused; full history retained; history immutable.
- **Derived output (PLN-50..52)** and **boundaries (PLN-60..63):** the counselor boundary covers both new tables;
  a frozen student's plan gains no item and records no transition.

### `workspace_plan_item_status_race.sh` — WS-PLN-RACE-01..03
Two sessions transition the same `planned` item. The second blocks on the first one's uncommitted sequence number
and fails with unique_violation. History does not fork. Control: with the unique key dropped, both commit, and
there are two rows with seq_no 1.

| Control | Result |
|---|---|
| exactly-one-source CHECK dropped | fails PLN-C3 (after the NULL fix; before it, PLN-07) |
| JSON-exclusivity CHECK dropped | fails PLN-20 |
| counselor check removed from the item guard | fails PLN-11 |
| item guard lets UPDATE through | fails PLN-15b |
| stale-transition check removed | fails PLN-31 |
| supersession rule removed | fails PLN-25 |
| unique (plan_item_id, seq_no) dropped | fails WS-PLN-RACE-01..03 |

**NOT RUN / NOT BUILT:** scheduling, conflict detection, generation, replay, and the contract §8 acceptance tests that
depend on an engine. There is no transition graph because the decision fixed the states, not the edges.

## 2026-11-18 — Supervisor findings F-01..F-04 on `d75d039`

The Supervisor reviewed `d75d039` as NOT ACCEPTED. The plan suite is now PLN-C1..C4, PLN-01..80 (**75 PASS lines**),
plus WS-PLN-RACE-01..03 and a new migration suite. Plan rows are now written by `ws_<key>_synth_plan_writer`;
historical legacy fixtures by `ws_<key>_plan_migrator`. Both are NOLOGIN and checked by role membership (superseded by F-05 below: identity, not membership).

### F-01 — the runtime cannot write a plan row in anyone's name
- **PLN-C2** (rewritten): the runtime holds no INSERT, UPDATE or DELETE on `plan_items` or `plan_item_status_events`
  and cannot name `content_model`; the writer holds INSERT only.
- **PLN-70** the runtime records a transition claiming to be the student → 42501.
- **PLN-71** the runtime records a transition claiming to be counselor A → 42501.
- **PLN-72** the runtime creates a plan item → 42501.
- **PLN-73 / PLN-74** an intruder role holding INSERT but not the writer identity → refused by the trigger.
- **PLN-76** even the writer cannot record `actor_kind='student'` → refused (no student identity can be verified).
- **PLN-80** no application role is a member of either identity; both are NOLOGIN.

### F-02 — no new `legacy_json` versions from the runtime
- **PLN-28** the runtime naming `content_model` → 42501. **PLN-28b** a runtime-created version is `normalized`.
- **PLN-75** an intruder holding INSERT on the column → refused by the trigger.
- **PLN-79** the migrator can create a legacy v1. **PLN-79b** not after a normalized version exists.
  **PLN-79c** a legacy version reads back unchanged.

### F-03 — open semantics fail closed
- **PLN-77** a transition on an item of a DRAFT version → refused.
- **PLN-78** publishing a normalized version with no items → refused.
- No transition graph is asserted, because none is decided.

### F-04 — `workspace_plan_items_migration_tests.sql`, PLN-M01..M08 (8 PASS lines)
Its own database. `workspace_plan_items_migration_fixture.sql` loads three historical versions **before** the
plan draft: one published with JSON, one draft whose JSON is `'{}'`, one draft with JSON.
- **M01** all three are `legacy_json`. **M02** the `'{}'` draft is not relabelled as normalized.
- **M03** nothing stored changed. **M04** rendered output equals the stored JSON.
- **M05** the default for new rows is `normalized`. **M06** a new normalized version supersedes a historical one.
- **M07** relabelling is refused. **M08** a published historical row stays immutable.

| Negative control (measured) | Result |
|---|---|
| student-actor refusal removed | fails PLN-76 |
| synthetic-writer check removed from the transition guard | fails PLN-73 |
| migrator check removed from the version guard | fails PLN-75 |
| runtime granted INSERT on status events | fails PLN-C2 |
| runtime granted INSERT (content_model) | fails PLN-C2 |
| empty-publication check removed | fails PLN-78 |
| draft-version transition check removed | fails PLN-77 |
| `d75d039` form `ADD COLUMN ... DEFAULT 'normalized'` | the migration itself fails: `check constraint "normalized_version_has_no_json_content" ... is violated by some row` |
| race without the unique key (rerun) | fails WS-PLN-RACE-02/03 (two rows) |

### M-05 and M-06 — recorded, NOT implemented, no tests
- **M-05** closes when duplicate JSON object keys are rejected at raw ingress, before conversion to JSONB, shown by
  tests that submit duplicate-key payloads. JSONB itself keeps the last value silently, so this needs an ingress layer.
- **M-06** closes when one machine-readable canonicalization vector file is consumed by both the SQL and the Python
  tests, with a check that neither keeps a private copy.

**NOT RUN:** plan writes under a real counselor or student identity (needs WS-ISO-01 caller binding); a migration at
volume and its rollback.

## 2026-11-19 — Supervisor finding F-05 on `8df7d5e`: privileged identities and role membership

**The defect.** `plan_identity_is()` used `pg_has_role(current_user, role, 'MEMBER')`. That is true for any direct or
indirect member, whatever the INHERIT/SET options. The bootstrap also created the roles `IF NOT EXISTS` and trusted an
existing one as it was.

**The rule now.**
- The session must **be** the role.
- On every write, the role must have no `pg_auth_members` row in either direction and none of LOGIN, SUPERUSER,
  CREATEROLE, BYPASSRLS, REPLICATION, CREATEDB or INHERIT.
- A superuser is not accepted as itself.

### `workspace_plan_identity_membership_tests.sql` — F05-00..F05-16 (79 PASS lines)
Runs after the plan suite in the same database. Every adversarial state uses real GRANT, SET SESSION AUTHORIZATION and
SET ROLE inside a rolled-back transaction.

| Test | What happens | Result |
|---|---|---|
| F05-00 | records the server version in the log; requires 16+ | PASS |
| F05-01/01b | clean bootstrap: no violation; nobody holds either identity, and neither holds anything | PASS |
| F05-02 | a superuser is not accepted as either identity | PASS |
| F05-13a/b/c | ordinary runtime item / event / legacy writes | refused 42501 by privileges |
| F05-09a..h | runtime, worker and exporter logins `SET ROLE` to the writer, migrator, table owner and function owner | refused 42501 by PostgreSQL |
| F05-10a..d | runtime and worker try to GRANT the writer, migrator or table owner | refused 42501 |
| F05-11a..f | ALTER ROLE LOGIN / SUPERUSER / PASSWORD / CREATEROLE, RENAME, DROP on the privileged roles | refused 42501 |
| F05-12a..k | replace `plan_identity_is()` or a guard; disable or drop a guard trigger; take ownership; `session_replication_role`; rewrite or delete the identity record; create in `public`; create a temp shadow table | refused 42501 |
| F05-12l/m | pinned `search_path`; the identities own nothing | PASS |
| F05-03 | runtime **directly** holds the writer WITH INHERIT; PostgreSQL reports membership | item and event writes still refused; violation named |
| F05-04 | runtime directly holds it WITH SET; the `SET ROLE` **succeeds** and current_user is the writer | writes still refused; violation named |
| F05-05 | **indirect** chain runtime → mid_b → mid_a → writer | inherited and SET ROLE writes refused; path named |
| F05-06 | worker holds the migrator | legacy import refused, both inherited and after SET ROLE |
| F05-07 | nested chain exporter → … → migrator | legacy import refused after SET ROLE; path named |
| F05-08a..h | the writer made a member of a role, or given LOGIN / CREATEROLE (migrator) / BYPASSRLS after bootstrap | refused on the next write; violation named |
| F05-15a..g | an owner role held by an application role; a disabled guard; PUBLIC INSERT; column UPDATE on the identity record; CREATEROLE on a login role; a missing identity record | each named as a violation; missing record → nobody can act |
| F05-14, F05-16b/c | the synthetic writer creates an item and a transition, and the migrator imports a legacy version, as a superuser test session assuming them | accepted — the only trusted path |
| F05-16a | after every rollback | no violation remains |

### `workspace_plan_identity_bootstrap_tests.sh` — F05-BOOT-01..14
The unsafe state is created **before** the real bootstrap runs, each case in its own database and key. Each failing
case also asserts that nothing was repaired (the attribute or membership is still there) and that no identity record
was written.

| Case | Pre-existing state | Result |
|---|---|---|
| 01..04 | writer with LOGIN / SUPERUSER / CREATEROLE / BYPASSRLS | bootstrap aborts |
| 05..08 | migrator with LOGIN / SUPERUSER / CREATEROLE / BYPASSRLS | bootstrap aborts |
| 09 | writer with INHERIT | bootstrap aborts |
| 10 | writer already held by the runtime | bootstrap aborts |
| 11 | migrator held indirectly by the worker | bootstrap aborts |
| 12 | runtime login with CREATEROLE (application role) | aborts at the boundary check; no record kept |
| 13 | clean state | succeeds, both identities recorded, boundary verified |
| 14 | re-run over safe roles it created | accepted |

| Negative control (measured) | Result |
|---|---|
| `plan_identity_is()` reverted to `pg_has_role(..., 'MEMBER')` | fails F05-02 (superuser accepted); with F05-02 removed, fails F05-03b: "statement unexpectedly succeeded" |
| no-members clause removed | fails F05-04c: SET ROLE path write succeeds |
| attribute clauses removed | fails F05-08c: LOGIN writer accepted |
| "held by" clause removed from the boundary check | fails F05-03d |
| existing-role validation removed from the bootstrap | F05-BOOT-01..09 fail (caught later by the boundary check, wrong reason) |
| boundary check disabled | fails F05-BOOT-12: bootstrap succeeded |
| both removed | F05-BOOT-01..12 all fail: bootstrap succeeded with an unsafe role |

**Version.** Tested locally on PostgreSQL 16.15. CI uses `postgres:16`, and F05-00 prints the exact version into the
job log. PostgreSQL 16 semantics relied on:
- the INHERIT, SET and ADMIN options of a membership grant;
- `pg_has_role(..., 'MEMBER')` being true for any of them;
- `SET ROLE` requiring SET on every link of the chain.

The identity rule does not depend on any of these: it refuses as soon as any membership row exists.

## 2026-11-20 — F-05 follow-up on `38f2561`: transitive reach to the owner roles

The Supervisor found that owner roles were checked only for a direct member. Each test first shows what PostgreSQL
actually allows through the chain (inside a rolled-back transaction), then that `plan_identity_boundary_violations()`
names the exact path.

| Test | Chain / state | Real effect shown | Detection |
|---|---|---|---|
| F05-17 | runtime_login → mid_a → function_owner (INHERIT) | runtime login replaces `plan_identity_is()` | path named |
| F05-18 | worker_login → mid_a → table_owner (INHERIT) | worker login disables the plan-item guard | path named |
| F05-19 | exporter → mid_b → mid_a → governance_owner | exporter login SET ROLEs to the governance owner | path named, from exporter and exporter_login |
| F05-20 | runtime_login → mid_a → table_owner (SET TRUE, INHERIT FALSE) | no inherited ownership; SET ROLE then disable works | path named |
| F05-21 | runtime_login → mid_a → function_owner (ADMIN only) | SET ROLE refused, but the login GRANTs itself the owner, then SET ROLE works | path and ADMIN link named |
| F05-22a..g | no chain | grant, ADMIN-grant, revoke, alter, SET ROLE on owners | all refused 42501 |
| F05-23a..f | service with LOGIN; owner with INHERIT; login with NOINHERIT; CREATEDB; login holding another service role; expected grant WITH ADMIN | — | each named |
| F05-23g | after every rollback | — | no violation; exactly 3 inventory memberships exist |
| F05-BOOT-15..18 | pre-existing runtime LOGIN; table_owner INHERIT; worker_login NOLOGIN; governance_owner CREATEDB | bootstrap aborts, nothing repaired, no identity record | — |
| F05-BOOT-19 | pre-existing runtime_login → x_mid → function_owner | bootstrap aborts naming the path | — |
| F05-BOOT-20 | pre-existing exporter → x_a → x_b → governance_owner (ADMIN only) | bootstrap aborts naming the path | — |
| F05-BOOT-13/14 | clean state; re-run | succeed | — |

| Negative control (measured) | Result |
|---|---|
| transitive path check removed | fails F05-05f; bootstrap: BOOT-19/20 fail for the wrong reason (still caught by the direct "held by" checks) |
| owner targets removed from the path check | fails F05-17b |
| the three inventory owners removed from the owner set | fails F05-19b (governance owner unchecked) |
| expected LOGIN/INHERIT check removed | fails F05-23a |
| exact-membership check removed | fails F05-21e |
| existing-role validation in `$roles$` removed | BOOT-12, 15..17 fail (caught later, wrong reason) |
| both of the last two removed | BOOT-15..17: bootstrap **succeeded** with an unsafe role |

Local: plan step 215 PASS lines (109 F05, 20 F05-BOOT); full workflow 1067, 0 FAIL.
CI at `fe08a77`: runs 44705627331 and 44705633469, both success. F-05 accepted by the Supervisor at architecture-review level.

**NOT RUN:**
- a non-superuser provisioner with CREATEROLE (PostgreSQL 16 gives the creator ADMIN on the role it creates, which the
  boundary check reports as "held by", so such a bootstrap fails closed; not exercised);
- GitHub Actions at the F-05 remediation commit.

## Evidence by exact commit (WS-PLAN-01 / F-05 line, 2026-11-18 .. 2026-11-20)

Historical "NOT RUN" statements in the sections above keep their date and scope. This table is the current record.

| Commit | Kind | Local | GitHub Actions |
|---|---|---|---|
| `d75d039` | WS-PLAN-01 data model | 916 PASS | 44376897878, 44376886372: passed (per the Supervisor); NOT ACCEPTED in review (F-01..F-04) |
| `8df7d5e` | F-01..F-04 remediation | 938 PASS | 44382515348, 44383233656: success; F-05 raised |
| `38f2561` | F-05 remediation | 1031 PASS | 44693197767, 44693205261: success; F-05 not closed (owner chains) |
| `fe08a77` | F-05 follow-up | 1067 PASS | 44705627331, 44705633469: success; **F-05 ACCEPTED — ARCHITECTURE REVIEW LEVEL** |
| `bba7281` | documentation only | — | 44724614335, 44724622970: success |
| next | gap matrix, decision briefs, WS-ROLE-17 reporting fix | fresh cluster: 1067 PASS, 0 FAIL, 3 OPEN, 1 SKIP | NOT RUN until pushed |

**Counting rules.**
- A PASS line is an assertion or a named group.
- OPEN lines are fail-open findings printed by design (ISO-GAP-01..03). They are never passes.
- SKIP lines are not passes. The only one is WS-ROLE-17 in the mirror run of step 22; it executes in the first run of
  the same step.
