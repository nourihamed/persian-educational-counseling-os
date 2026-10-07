# DECISION_LOG.md

هر تصمیم مهم معماری/محصول اینجا با دلیل ثبت می‌شود. تصمیم‌های زیر **پیشنهادی** هستند و تا تأیید صریح، قطعی نیستند.

---

## D-001 — جداسازی Counselor Account / Subscription / Student Credit
**تصمیم:** این سه مفهوم Entityهای کاملاً مجزا خواهند بود، نه فیلدهایی روی یک جدول.
**دلیل:** بخش ۹ Master Prompt صراحتاً این جداسازی را الزامی کرده؛ تغییر مدل کسب‌وکار (مثلاً اضافه‌شدن Package) نباید نیاز به migration ساختاری داشته باشد.
**وضعیت:** Proposed

## D-002 — Credit Ledger به‌صورت Append-only
**تصمیم:** `CreditTransaction` هرگز UPDATE/DELETE نمی‌شود؛ موجودی از SUM تراکنش‌ها محاسبه می‌شود (یا با snapshot + event sourcing سبک).
**دلیل:** بخش ۱۰ و ۴۵ — تاریخچه مالی باید قابل‌ردیابی و غیرقابل دستکاری باشد.
**وضعیت:** Proposed

## D-003 — Payment/Telegram/SMS/AI به‌صورت Adapter پشت Interface
**تصمیم:** `PaymentProvider`, `NotificationAdapter`, `AIProvider` به‌عنوان Interfaceهای Core تعریف می‌شوند؛ پیاده‌سازی مشخص (Zarinpal، Telegram Bot API، Kavenegar و...) در لایه Infrastructure قرار می‌گیرد.
**دلیل:** بخش ۱۱، ۴۲، ۴۳، ۶۶ — Core نباید به Vendor خاص وابسته شود؛ Integration failure نباید Core را متوقف کند.
**وضعیت:** Proposed

## D-004 — استراتژی Tenant Isolation (نیازمند تصمیم‌گیری در Phase 1)
**گزینه‌های مطرح:**
1. Row-Level: یک دیتابیس مشترک + ستون `counselor_id`/`tenant_id` روی تمام جداول + Postgres Row-Level Security (RLS) به‌عنوان لایه دفاعی دوم.
2. Schema-per-tenant: هر Counselor یک schema در همان DB.
3. Database-per-tenant: کامل‌ترین ایزوله‌سازی، سخت‌ترین عملیات (migration، backup، scaling).

**توصیه اولیه:** گزینه ۱ (Row-Level + RLS) برای MVP، به دلیل سادگی عملیاتی و مقیاس‌پذیری کافی برای تعداد متوسط Counselor؛ امکان Migration به گزینه ۲/۳ در آینده برای Tenantهای بزرگ حفظ می‌شود.
**وضعیت:** Proposed — تصمیم نهایی در Phase 1 با جزئیات فنی بیشتر ثبت می‌شود. ثبت رسمی در OPEN_QUESTIONS.md نیز شده است.

## D-005 — RBAC باز برای افزودن نقش‌های جدید
**تصمیم:** نقش‌ها به‌صورت جدول (نه Enum ثابت در کد) + Policy-based permission، تا Teacher و نقش‌های آینده بدون تغییر Schema اضافه شوند.
**دلیل:** بخش ۴ — "در آینده ممکن است Roleهای دیگری اضافه شوند."
**وضعیت:** Proposed

## D-006 — تداخل نام‌گذاری "Plan" (Commercial vs Study)
**تصمیم پیشنهادی:** در Schema واقعی، Plan تجاری (Billing tier) با نام `BillingPlan` و Plan مطالعاتی (روزانه/هفتگی) با نام `Plan`/`StudyPlan` از هم متمایز شوند، چون Master Prompt هر دو را با همین واژه به کار برده (بخش ۴۵ در مقابل بخش ۷۲) و این ابهام می‌تواند در کد و مستندات باعث خطا شود.
**دلیل:** جلوگیری از ابهام در Domain Model؛ این یک تصمیم نام‌گذاری فنی است، نه تغییر در نیازمندی کسب‌وکار.
**وضعیت:** Proposed — نیازمند تأیید در Phase 2 هنگام نهایی‌شدن DATABASE.md.

## D-007 — عدم Push به GitHub بدون دسترسی/Credential
**تصمیم:** در این Session، فایل‌ها به‌صورت محلی commit می‌شوند؛ Push واقعی به Repository خالی GitHub انجام نمی‌شود چون ابزار متصل به GitHub یا Credential در دسترس نیست.
**دلیل:** اصل صداقت عملیاتی — ادعای انجام کاری که واقعاً ممکن نشده، ممنوع است.
**وضعیت:** Logged — نیازمند اقدام مالک پروژه (ثبت در Q-011).
