# TEST_PLAN.md

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

### دفاع چندلایه PostgreSQL RLS + Application Authorization (D-009 — Mandatory)

این موارد جداگانه و صریحاً در طراحی تست و CI پوشش داده شوند؛ موفقیت یک لایه، جایگزین آزمون لایه دیگر نیست:

- **بررسی پیکربندی نقش runtime (DB security/configuration test):** نقش مورد استفاده برنامه مالک جدول‌های tenant-owned نباشد، عضو نقشی با امتیاز دورزدن RLS نباشد و ویژگی BYPASSRLS نداشته باشد. نتیجه را از کاتالوگ‌های PostgreSQL/مجوزهای واقعی بررسی کن؛ صرفاً نام یا تنظیمات اعلام‌شده نقش کافی نیست.
- **بررسی مالکیت و RLS policyها:** برای همه جدول‌های tenant-owned هدف، فعال‌بودن RLS و در موارد لازم FORCE ROW LEVEL SECURITY، وجود و درستی policyهای مورد انتظار و نقش‌هایی که policyها برایشان اعمال می‌شوند را بررسی کن. استثناها باید مستند و تأییدشده باشند.
- **آزمون RLS به‌تنهایی:** با اتصال/نقش غیرمالکِ فاقد BYPASSRLS و بدون اعمال فیلتر tenant در لایه Application/Repository، تلاش برای خواندن و نوشتن داده Tenant دیگر را آزمایش کن؛ RLS باید دسترسی غیرمجاز را مسدود کند. این تست نباید با فیلتر برنامه نتیجه مثبت کاذب بگیرد.
- **آزمون Application authorization به‌تنهایی:** در تست ایزوله‌ای که عمداً RLS را از مسیر آزمایش حذف یا بی‌اثر می‌کند، ثابت کن فیلترهای Application/Repository و کنترل object-level authorization به‌تنهایی درخواست cross-tenant را رد می‌کنند. این حالت فقط در محیط تست کنترل‌شده مجاز است؛ هرگز تنظیمات امنیتی محیط واقعی را تغییر نده.
- **آزمون یکپارچه:** همان سناریوهای منفی را با هر دو لایه فعال اجرا کن؛ شکست هر لایه باید جداگانه قابل تشخیص باشد. تست‌های دورزدن RLS فقط در محیط تست ایزوله و با نقش/مجوز محدود انجام شوند.

این تست‌ها باید در CI روی هر PR اجرا شوند، نه فقط دستی. اگر یک تست نیازمند امتیاز مدیریتی یا تغییر policy است، آن را به تست پیکربندی/محیط ایزوله محدود کن و هیچ‌گاه برای اجرای تست، نقش runtime را privileged نکن.

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
