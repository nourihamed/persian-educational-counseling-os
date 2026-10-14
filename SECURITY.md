# SECURITY.md

Status: DRAFT — Phase 0 — Pending Approval

## اصول پایه

**مکانیزم MVP مصوب مالک محصول در 2026-10-12 (D-009 / Q-001; accepted mechanism, implementation not yet tested):** PostgreSQL مشترک با `tenant_id` مستقیم و غیرقابل‌تهی، Application/API authorization و RLS به‌عنوان دفاع چندلایه. این تصمیم هنوز پیاده‌سازی یا آزمون نشده است. نقش runtime نباید مالک جدول‌های tenant یا دارای دسترسی bypass به RLS باشد؛ policyها، رفتار owner/privileged roles و tenant context قابل‌اعتماد باید بررسی شوند. تست‌های منفی cross-tenant برای API، دیتابیس و سطوح جانبی (jobs، exports، files و notifications) شرط پذیرش‌اند.
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
- **Program/Plan Versioning** (طبق D-008 — Accepted و D-012 — Accepted؛ الزامات مفهومی‌اند و تا پیاده‌سازی و تست در فازهای مجاز، کنترل فنی موجود نیست):
  1. در MVP، فقط `ProgramTemplate` و `ProgramVersion` متعلق به یک Tenant پشتیبانی می‌شوند. هر `ProgramVersion` باید به Template همان Tenant تعلق داشته باشد. قالب‌ها و نسخه‌های متعلق به Platform یا کاتالوگ مشترک خارج از MVP هستند (D-012 / Q-013 — Resolved).
  2. `StudentProgramEnrollment`، `Plan` و `PlanVersion` بدون استثنا به Tenant و Student مربوط محدود می‌مانند. Read/Write روی آن‌ها باید از کنترل‌های Tenant/Student-scoped عبور کند؛ استفاده از Template/Version مجوز اشتراک‌گذاری داده دانش‌آموز بین Tenantها نیست.
  3. ساخت/فعال‌سازی نسخه باید Actor را ثبت کند (Audit Log). نسخه منتشرشده نباید بی‌صدا بازنویسی شود؛ تغییرات باید از مسیر نسخه جدید و قواعد وضعیت تعریف‌شده انجام شوند.
  4. این تصمیم‌ها مالکیت و محدوده MVP را مشخص می‌کنند، نه پیاده‌سازی یا اثبات امنیت runtime.
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
