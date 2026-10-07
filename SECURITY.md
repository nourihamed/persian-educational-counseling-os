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

## Threat Model اولیه (خلاصه)
| تهدید | ریسک | کنترل |
|---|---|---|
| نشت داده بین Tenantها | بحرانی | RLS + Application-level filter + تست اجباری |
| دستکاری ID در API برای دسترسی به داده دیگران (IDOR) | بالا | Authorization check روی هر resource، نه فقط authentication |
| پرداخت تکراری/Webhook replay | بالا | Idempotency key + unique constraint |
| نشت Token/Secret در لاگ | متوسط-بالا | Log scrubbing، review قبل از هر PR |
| Brute-force روی Login | متوسط | Rate limiting + lockout موقت |
| آپلود فایل مخرب | متوسط | محدودیت نوع/حجم، اسکن، ذخیره خارج از مسیر اجرایی |

## فرآیند قبل از Production (بخش ۷۵)
چک‌لیست کامل در Master Prompt بخش ۷۵ باید قبل از هر انتشار Production تیک بخورد؛ Security Review و Tenant Isolation test جزو موارد غیرقابل‌حذف هستند.
