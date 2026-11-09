# TEST_PLAN.md
## Phase 2 Control Plane + Workspace acceptance contracts (2026-11-09)

**Latest successful execution:** GitHub Actions run [#231](https://github.com/nourihamed/persian-educational-counseling-os/actions/runs/42653297866), PostgreSQL 16, exact SQL/test tree at commit `2104eea56806a6f82b405090bc9cbfbd675d2aec` (run status SUCCESS). The workflow ran on the exact PR #12 HEAD at that time. Subsequent commits `fde21b8` and `3d88729` changed documentation only; SQL/test files were not changed. This is synthetic draft-SQL evidence, not API/runtime/production/HA approval.

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
