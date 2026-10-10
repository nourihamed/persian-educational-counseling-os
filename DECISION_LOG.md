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
**وضعیت: RESOLVED / HISTORICAL** (این تصمیم دیگر فعال نیست؛ برای حفظ تاریخچه حذف نشده است.)

**تصمیم اصلی (در زمان ثبت):** در آن Session، فایل‌ها فقط به‌صورت محلی commit شدند؛ Push واقعی به Repository گیت‌هاب انجام نشد چون هیچ ابزار متصل به GitHub یا Credential در دسترس Claude نبود.
**دلیل اصلی:** اصل صداقت عملیاتی — ادعای انجام کاری که واقعاً ممکن نشده، ممنوع است.

**به‌روزرسانی (این Session):** مالک پروژه خودش Repository را متصل کرد، با Personal Access Token شخصی Push را انجام داد، و طبق آخرین Supervisor Review، Commit واقعی زیر در گیت‌هاب تأیید شده است:
```
commit: bd24cf8de6e836eea5602fd504530f34343e80fa
message: docs: establish Phase 0 project foundation
```
بنابراین محدودیت موضوع این تصمیم (نبود دسترسی Push) دیگر برقرار نیست. محدودیت Git/GitHub Access به‌عنوان یک مانع فعال، منتفی شده است؛ ولی اصل حاکم بر این تصمیم (Claude هرگز بدون Credential واقعی ادعای Push/Commit روی Repository واقعی نمی‌کند) همچنان به‌عنوان یک قاعده دائمی کاری معتبر است و در آینده نیز رعایت می‌شود.
**وضعیت نهایی:** Resolved — صرفاً جنبه تاریخی/آرشیوی دارد.

## D-008 — MVP Versioning Policy برای Program Template و Student Plan
**وضعیت: PROPOSED — Pending Product Owner Confirmation. این تصمیم هنوز Accepted نیست و تا تأیید صریح مالک محصول، صرفاً یک پیشنهاد مستندشده است.**

**زمینه:** بازبینی مستقل Supervisor یک تناقض در اسناد فاز ۰ شناسایی کرد: `PROJECT_SCOPE.md` در یک بند می‌گفت «هیچ Versioning کاملی در MVP نیست؛ Versioning رسماً از Phase 15 شروع می‌شود» و در بند دیگری (لیست Out-of-Scope) می‌گفت «نسخه ساده در MVP، نسخه کامل در Phase 15» — این دو با هم همخوان نبودند. هم‌زمان، `ARCHITECTURE.md` و `DATABASE.md` مفهوم Versioning را به‌عنوان یک اصل معماری پایه (بدون قید فاز) توصیف کرده بودند، در حالی که `ROADMAP.md` کلمه «Versioning» را فقط زیر Phase 15 لیست کرده بود.

**تصمیم پیشنهادی (Policy):**

MVP باید حداقل سطح ممکن از Versioning قابل‌ممیزی (Minimum Viable, Auditable Versioning) را برای Student Plan و Program Template داشته باشد؛ ویژگی‌های پیشرفته مدیریت نسخه می‌تواند به بعد از MVP موکول شود.

**Student Plan — الزامی در MVP:**
1. هر Plan منتشرشده یا فعال‌شده باید یک شناسه پایدار (Stable Identity) و یک شناسه نسخه صریح (Version Identifier) داشته باشد.
2. تغییر یک Plan نباید به‌صورت بی‌صدا، نسخه منتشرشده قبلی را بازنویسی کند.
3. تاریخچه کافی باید حفظ شود تا مشخص باشد چه چیزی، چه زمانی، و توسط کدام Actor تغییر کرده است.
4. هر نسخه از Plan باید به Tenant و Student خودش قابل‌انتساب باشد؛ Authorization باید برای هر عملیات Read و Write اعمال شود.
5. مشخص شود کدام وضعیت‌های Plan قابل‌ویرایش مستقیم‌اند و کدام نیازمند ساخت نسخه جدیدند.
6. نسخه‌های قبلی Plan، هنگام فعال‌شدن نسخه جدید، حفظ شوند (نه حذف).
7. مشخص شود وقتی یک Program Template به‌روزرسانی می‌شود، با Planهای موجودی که بر پایه نسخه قبلی Template ساخته شده‌اند چه رفتاری انجام می‌شود.
8. ساخت و فعال‌سازی نسخه Plan باید Transaction-safe باشد و هنگام پیاده‌سازی، با تست خودکار پوشش داده شود.

**Program Template — الزامی در MVP:**
1. هر Template باید شناسه پایدار و شناسه نسخه داشته باشد.
2. به‌روزرسانی یک Template نباید به‌صورت بی‌صدا، یک Plan دانش‌آموزی که از قبل ساخته یا فعال شده را تغییر دهد.
3. مشخص شود ویرایش Template، نسخه منتشرشده غیرقابل‌تغییر جدید می‌سازد یا یک Draft قابل‌ویرایش که بعداً Publish می‌شود.
4. ثبت شود کدام نسخه از Template برای ساخت هر Plan دانش‌آموزی استفاده شده است.
5. تاریخچه کافی برای توضیح منشأ هر Plan موجود حفظ شود.
6. قوانین مالکیت Tenant و Authorization برای Templateها، از جمله هر Template سطح‌پلتفرم احتمالی در آینده، مشخص شود.

**ویژگی‌های پیشرفته — قابل‌موکول‌شدن به بعد از MVP** (مگر این‌که یک نیازمندی تأییدشده دیگر صراحتاً آن‌ها را بخواهد):
- مقایسه بصری نسخه‌به‌نسخه (Visual version-to-version comparison)
- رابط کاربری پیشرفته Rollback/Restoration
- مرور گسترده تاریخچه نسخه‌ها
- Branching یا نسخه‌های موازی Template
- گزارش‌های پیشرفته Diff و تحلیل اثر تغییر

**این موکول‌شدن به معنای حذف الزامات حداقلی قابلیت‌ممیزی و تاریخچه بالا نیست.**

**اثر این تصمیم روی سایر اسناد (در صورت تأیید):** `PROJECT_SCOPE.md`، `ARCHITECTURE.md`، `DATABASE.md`، `ROADMAP.md`، `API.md`، `SECURITY.md`، `TEST_PLAN.md`، `PRODUCT_REQUIREMENTS.md` بر همین اساس به‌روزرسانی شدند (در همین Commit) تا با این Policy هماهنگ باشند؛ ولی این هماهنگ‌سازی مستندی، به‌معنای Accepted شدن خودِ Policy نیست — فقط به این معناست که اسناد دیگر از نظر داخلی با یکدیگر و با همین پیشنهاد سازگارند، تا وقتی مالک محصول آن را تأیید یا اصلاح کند.

**دلیل:** درخواست مستقیم Supervisor Review برای رفع تناقض Template/Plan Versioning؛ اصل کلی‌تر این است که تصمیمات معماری/محصول باید صریحاً ثبت شوند، نه این‌که به‌صورت ضمنی و ناهماهنگ در چند سند مختلف حل شوند.
**وضعیت:** **Proposed — Pending Product Owner Confirmation.**
