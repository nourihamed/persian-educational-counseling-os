# SECURITY.md

Status: DRAFT — Phase 0 — Pending Approval

## اصول پایه
1. **Tenant Isolation امنیتی است، نه فقط معماری.** هر نشتی داده بین Counselorها یک Security Incident محسوب می‌شود.
2. **Defense in Depth**: Authorization در Application layer + محدودیت در DB layer (RLS) هم‌زمان، نه فقط یکی.
3. **Least Privilege**: هر Role فقط به چیزی که لازم دارد دسترسی دارد؛ Parent و Student هرگز به یادداشت خصوصی مشاور دسترسی پیش‌فرض ندارند.

## الزامات امنیتی (بخش ۴۸)
- Password Hashing با Argon2id یا bcrypt (cost مناسب)
- RBAC با Policy-based authorization (نه فقط if role==admin پراکنده در کد)
- Tenant Isolation در تمام لایه‌ها (API، DB، Reports، Files، Notifications، Jobs)
- Input Validation با Pydantic v2 در مرز API
- SQL Injection Protection: فقط از طریق SQLAlchemy ORM/Core پارامتریزه، هیچ raw string interpolation
- XSS Protection: sanitize ورودی‌های آزاد متن، CSP در Frontend
- CSRF: برای session-based endpointها (در صورت استفاده از Cookie)
- Rate Limiting: روی Login، Password Reset، API عمومی (Redis-based)
- Secure File Upload: محدودیت نوع/حجم فایل، اسکن قبل از ذخیره، نام‌گذاری غیرقابل‌حدس، جداسازی فایل بر اساس tenant_id در مسیر Storage
- Audit Logs: برای عملیات حساس (تغییر Credit، تغییر Role، حذف دانش‌آموز، ورود Admin به حساب دیگران)
- Secrets Management: هیچ secret در کد/Git؛ از `.env` + Secret Manager (Vault/Cloud secret store) در Production

## موارد ممنوع در Log (بخش ۴۸)
Passwords, Tokens, API Keys, SMS provider secrets, Telegram Bot Token, Payment secrets — **هرگز** در لاگ، Error Trace، یا پیام خطای کاربر نمایش داده نشوند.

## نقاط حساس خاص این پروژه
- **Credit/Billing endpoints**: نیاز به audit log کامل + idempotency key روی تمام عملیات مالی.
- **Payment Webhooks**: امضا/signature verification الزامی؛ idempotent processing.
- **Admin impersonation (در صورت وجود)**: باید audit-logged و قابل محدودسازی باشد.
- **Parent access**: پیش از نمایش هر داده، بررسی صریح Consent/Permission سطح دانش‌آموز+مشاور.
- **File access (گزارش‌ها، PDF)**: لینک‌های دانلود باید Scoped و زمان‌دار (signed URL) باشند، نه public permanent link.
- **Program/Plan Versioning** (طبق `DECISION_LOG.md` D-008 — Accepted، تأیید مالک محصول در تاریخ ۲۰۲۶-۱۰-۱۰): این بند بین سه مورد مالکیت تمایز صریح قائل می‌شود (جزئیات کامل در `DATABASE.md` بخش Programs):
  1. `ProgramTemplate` متعلق به یک Tenant — همان مسیر Tenant-scoped معمول.
  2. `ProgramTemplate` سطح‌پلتفرم (احتمالی، آینده) — مدل مالکیت و Authorization آن **هنوز تصمیم‌گیری نشده** (`OPEN_QUESTIONS.md` Q-013)؛ این یک کار طراحی باز است، نه تصمیم‌گرفته‌شده و نه چیزی که این‌جا حدس زده شود.
  3. **`StudentProgramEnrollment` و `PlanVersion` — همیشه و بدون استثنا به یک Tenant و یک Student خاص محدودند**، مستقل از این‌که Template منشأ آن‌ها Tenant-owned بوده یا (در آینده) Platform-owned. Read و Write روی این دو، دقیقاً همان مسیر Tenant/Student-scoped Repository را طی می‌کند که بقیه جداول Tenant طی می‌کنند — هیچ استثنای سطح-نسخه یا سطح-Template برای Tenant Isolation روی داده واقعی دانش‌آموز وجود ندارد و نمی‌تواند وجود داشته باشد؛ Template سطح‌پلتفرم هرگز به معنای اشتراک‌گذاری داده دانش‌آموز بین Tenantها نیست.
  ساخت/فعال‌سازی هر نسخه باید Actor انجام‌دهنده را ثبت کند (Audit Log) تا هر تغییر قابل‌انتساب باشد. این بند مفهومی است؛ Policy اصل Versioning تأیید شده (D-008)، ولی تا پیاده‌سازی واقعی در فازهای بعد، هیچ کنترل فنی موجود نیست.

## Threat Model اولیه (خلاصه)
| تهدید | ریسک | کنترل |
|---|---|---|
| نشت داده بین Tenantها | بحرانی | RLS + Application-level filter + تست اجباری |
| دستکاری ID در API برای دسترسی به داده دیگران (IDOR) | بالا | Authorization check روی هر resource، نه فقط authentication |
| پرداخت تکراری/Webhook replay | بالا | Idempotency key + unique constraint |
| نشت Token/Secret در لاگ | متوسط-بالا | Log scrubbing، review قبل از هر PR |
| Brute-force روی Login | متوسط | Rate limiting + lockout موقت |
| آپلود فایل مخرب | متوسط | محدودیت نوع/حجم، اسکن، ذخیره خارج از مسیر اجرایی |
| بازنویسی بی‌صدای نسخه منتشرشده Plan/Template، یا دسترسی به نسخه‌های Tenant/Student دیگر | بالا | عدم UPDATE روی نسخه منتشرشده (فقط ساخت نسخه جدید) + همان Tenant/Student-scoped Repository pattern + Actor attribution (D-008 — Accepted) |

## فرآیند قبل از Production (بخش ۷۵)
چک‌لیست کامل در Master Prompt بخش ۷۵ باید قبل از هر انتشار Production تیک بخورد؛ Security Review و Tenant Isolation test جزو موارد غیرقابل‌حذف هستند.
