# TEST_PLAN.md

Status: DRAFT — Phase 0 — Pending Approval

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

این تست‌ها باید در CI روی هر PR اجرا شوند، نه فقط دستی.

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
