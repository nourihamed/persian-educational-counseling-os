# TEST_PLAN.md
## Phase 2 Control Plane + Workspace acceptance contracts (2026-11-09)

**Execution evidence:** GitHub Actions workflow run [#10](https://github.com/nourihamed/persian-educational-counseling-os/actions/runs/42643344236) completed SUCCESS on PostgreSQL 16.15 at commit `4720cc3ed12b766c941337fe240a9d240e203522`: 21 Control Plane assertions, 1 concurrent global-identity race, and 13 Workspace schema assertions passed. This is draft-schema evidence only, not runtime/API/security/HA approval. Earlier failed runs exposed and led to correction of two test-fixture defects; the final run is the successful run above.

| ID | Required test | Status |
|---|---|---|
| CP-IDENT-01 | Global mobile+grade uniqueness across Workspaces | EXECUTED / PASS |
| CP-IDENT-02 | Same mobile with different grade follows approved D-025 rule | EXECUTED / PASS |
| CP-IDENT-03 | HMAC rotation gate, alias completeness, key-version overlap and retirement lifecycle | EXECUTED / PASS for SQL lifecycle cases; crash/recovery and live KMS backfill NOT RUN |
| CP-IDENT-04 | Rotation gate blocks claim mutations; deferred triggers reject missing/mismatched aliases; complete/retire lifecycle remains safe under retries | EXECUTED / PASS for covered cases; adversarial concurrency/retry NOT RUN |
| CP-ROLE-01 | Runtime/function/table-owner role separation, no SUPERUSER/BYPASSRLS, no direct protected-table writes, no PUBLIC EXECUTE and safe SECURITY DEFINER ownership | NOT RUN |
| CP-OWN-01 | Exactly one global owner and one holding claim per student | EXECUTED / PARTIAL: one holding claim per student tested; duplicate owner row and DB role path NOT RUN |
| CP-OWN-02 | Switch rejects missing/multiple/stale source claims | EXECUTED / PARTIAL: stale generation/source tested; missing/multiple source-claim cases NOT RUN |
| CP-OWN-03 | Ownership generation increments exactly once; stale source writes/jobs denied | EXECUTED / PARTIAL: switch generation increment and stale source/generation tested; stale jobs/writes NOT RUN |
| CP-XFER-01 | All three cumulative approvals required; expired/revoked approvals denied | EXECUTED / PARTIAL: missing fee approval blocks and three approvals allow switch; expiry/revocation NOT RUN |
| CP-XFER-02 | Approval principal, authn event, relationship/assignment and authority scope bound to exact case | NOT RUN (schema stores references/snapshots; trusted verification service absent) |
| CP-XFER-03 | Source freeze barrier drains in-flight writes before final snapshot | NOT RUN (metadata guards only; distributed freeze/drain not implemented) |
| CP-XFER-04 | Destination staging remains inaccessible until checks and ownership switch | NOT RUN (service-level access gate not implemented) |
| CP-XFER-05 | Post-switch cancellation/rollback forbidden; forward recovery only | EXECUTED / PARTIAL: post-switch cancellation rejected; crash/forward-recovery NOT RUN |
| CP-IDEM-01 | Same idempotency key + same canonical payload replays original result | EXECUTED / PASS |
| CP-IDEM-02 | Same key + different payload rejected and audited | EXECUTED / PASS for rejection/payload immutability; audit integration NOT RUN |
| CP-EVENT-01 | Outbox/inbox duplicate and out-of-order delivery deduplicated/fenced | NOT RUN (outbox payload immutability only tested) |
| CP-FAIL-01 | Control Plane outage/ambiguous ownership denies student-data access | NOT RUN (runtime fail-closed integration absent) |
| WS-SCHEMA-01 | Workspace membership, branch/type, counselor assignment, guardian permission, educational domain relations, immutable published versions, credit reversals, capacity counters, private file metadata, in-app notification idempotency, legal holds and append-only audit/ledger | EXECUTED / PASS for included schema fixtures |
| WS-ISO-01 | Workspace A credential cannot access Workspace B database/data | NOT RUN (requires separate credentials/DB service integration) |
| WS-AUTH-01 | Counselor/manager object and assignment scope enforced | NOT RUN (runtime authorization absent) |
| WS-PARENT-01 | Per-child/per-permission parent isolation; expiry/revocation | NOT RUN (legal/age matrix and authorization service absent) |
| WS-VERSION-01 | Published ProgramVersion/StudentPlanVersion immutable | EXECUTED / PASS |
| WS-CREDIT-01 | Activation + debit atomic/idempotent; reversal append-only | EXECUTED / PARTIAL: ledger immutability, exact reversal and duplicate reversal tested; activation/debit atomicity NOT RUN |
| WS-CAP-01 | Concurrent capacity checks cannot exceed configured limits; archived students excluded | EXECUTED / PARTIAL: atomic counter ceiling/idempotency/underflow tested; concurrent activation and archived exclusion NOT RUN |
| OPS-RESTORE-01 | Independent encrypted backup restore drill, failover and consistency evidence | NOT RUN |

A test may be marked IMPLEMENTED only when an executable test exists, EXECUTED only with reproducible logs on the exact reviewed SHA, and PASS only after successful execution. Static review is not execution. Phase 2 cannot pass while required critical security/integrity tests remain NOT RUN.


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
