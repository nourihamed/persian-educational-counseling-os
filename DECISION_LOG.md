# DECISION_LOG.md

هر تصمیم مهم معماری/محصول اینجا با دلیل ثبت می‌شود. تصمیم‌های زیر **پیشنهادی** هستند و تا تأیید صریح، قطعی نیستند.

**نکته مهم برای تفسیر درست وضعیت «Proposed» (طبق Task 5 بازبینی مستقل):** وضعیت `Proposed` روی یک تصمیم، به‌معنای «خودِ الزام زیربنایی اختیاری است» **نیست**. باید بین دو چیز متفاوت تمایز قائل شد:

1. **الزام محصول/امنیتی که از قبل توسط Master Prompt تأیید‌شده تحمیل شده** — مثلاً «Credit Ledger باید Append-only باشد» (بخش ۱۰/۴۵ Master Prompt) یا «Core هرگز نباید به Vendor خاص وابسته شود» (بخش ۱۱/۶۶) یا «هیچ Counselor نباید به داده Tenant دیگر دسترسی داشته باشد» (بخش ۳) — این‌ها از ابتدای پروژه **غیرقابل‌مذاکره و از قبل تحمیل‌شده‌اند**؛ ثبت‌شان در این فایل، تصمیم‌گیری درباره «آیا این الزام برقرار باشد یا نه» نیست.
2. **مکانیزم فنی پیشنهادی برای برآورده‌کردن همان الزام** — مثلاً D-002 درباره «آیا Ledger باید Append-only باشد یا نه» تصمیم نمی‌گیرد (آن از قبل مشخص است)؛ بلکه یک **روش فنی خاص** (محاسبه موجودی از SUM تراکنش‌ها، یا Event Sourcing) را برای برآورده‌کردن آن الزام پیشنهاد می‌دهد. وضعیت `Proposed` این‌جا یعنی: «این روش خاصِ پیاده‌سازی هنوز توسط مالک محصول/Architect نهایی تأیید نشده»، نه این‌که خودِ الزام Append-only بودن مشکوک باشد.

به‌طور خلاصه: **الزامات زیربنایی تثبیت‌شده‌اند؛ مکانیزم‌های فنیِ برآورده‌کردن آن‌ها، تا تأیید صریح، Proposed باقی می‌مانند.** D-001 تا D-005 زیر همگی از این نوع دوم‌اند — مکانیزم پیشنهادی، نه خودِ الزام. هیچ‌کدام بدون تأیید صریح مالک محصول به Accepted تغییر نمی‌کند، و هیچ‌کدام نباید به‌معنای تضعیف الزام زیربنایی (مثلاً Tenant Isolation یا Ledger Auditability) خوانده شود — آن الزامات مستقل از وضعیت Proposed/Accepted این تصمیمات، برقرارند.

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
**وضعیت:** **Accepted — 2026-10-12؛ مکانیزم انتخابی در D-009 ثبت شده است.** الزام Tenant Isolation از ابتدا غیرقابل‌مذاکره بوده؛ این تصمیم فقط مکانیزم MVP را تعیین می‌کند. جزئیات policyها، constraints، runtime role و تست‌ها باید در فازهای مربوطه طراحی و آزمون شوند؛ این ثبت مستندی اثبات امنیت runtime نیست.

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

**به‌روزرسانی (همان Session قدیمی):** مالک پروژه خودش Repository را متصل کرد، با Personal Access Token شخصی Push را انجام داد، و Commit واقعی زیر در گیت‌هاب تأیید شد:
```
commit: bd24cf8de6e836eea5602fd504530f34343e80fa
message: docs: establish Phase 0 project foundation
```

**اصلاح مهم (این Session — طبق یافته Task 4 بازبینی مستقل):** جمله قبلی این بخش («محدودیت Git/GitHub Access به‌عنوان یک مانع فعال، منتفی شده است») **گمراه‌کننده بود و اصلاح می‌شود.** آن جمله صرفاً به این واقعیت محدود اشاره داشت که *یک* Push موفق با Token موقت دستی انجام شد — نه این‌که مشکل دسترسی به‌طور کلی یا به‌صورت پایدار حل شده باشد. بررسی‌های بعدی (مستند در `OPEN_QUESTIONS.md` Q-011) نشان داد **هیچ دسترسی پایدار و قابل‌اتکا (از طریق Connector/GitHub App) هرگز برقرار نشد** — تمام Pushهای بعدی هم، بدون استثنا، از همان مسیر Token موقت دستی انجام شدند، نه یک اتصال دائمی. بنابراین:
- این D-007، از این پس، **فقط یک رکورد تاریخی از یک رویداد مشخص** (نخستین Push موفق، در تاریخ ثبت‌شده بالا) است.
- **سؤال عملیاتی فعلی و واقعی درباره دسترسی پایدار GitHub، منحصراً در `OPEN_QUESTIONS.md` Q-011 دنبال می‌شود** — همان‌جا Open و دقیق (با Read/Write و محیط Claude/Supervisor تفکیک‌شده) نگه داشته شده و باید همان‌جا مرجع قرار گیرد، نه این‌جا.
- این سند **هیچ ادعایی نمی‌کند** که اتصال پایدار اکنون کار می‌کند؛ چنین ادعایی تنها زمانی درست خواهد بود که مستقیماً آزموده و تأیید شود (طبق همان اصل صداقت عملیاتی که در بالای همین تصمیم ثبت شده).

اصل حاکم بر این تصمیم (Claude هرگز بدون Credential واقعی ادعای Push/Commit روی Repository واقعی نمی‌کند) همچنان به‌عنوان یک قاعده دائمی کاری معتبر است.
**وضعیت نهایی:** Resolved/Historical — صرفاً رکورد یک رویداد گذشته مشخص است؛ **برای وضعیت فعلی و باز دسترسی GitHub، به `OPEN_QUESTIONS.md` Q-011 مراجعه کنید، نه به این بخش.**

## D-008 — MVP Versioning Policy برای Program Template و Student Plan
**وضعیت: ACCEPTED — تأیید صریح مالک محصول در گفتگو در تاریخ 2026-10-10.**

**زمینه:** بازبینی مستقل Supervisor یک تناقض در اسناد فاز ۰ شناسایی کرد: `PROJECT_SCOPE.md` در یک بند می‌گفت «هیچ Versioning کاملی در MVP نیست؛ Versioning رسماً از Phase 15 شروع می‌شود» و در بند دیگری (لیست Out-of-Scope) می‌گفت «نسخه ساده در MVP، نسخه کامل در Phase 15» — این دو با هم همخوان نبودند. هم‌زمان، `ARCHITECTURE.md` و `DATABASE.md` مفهوم Versioning را به‌عنوان یک اصل معماری پایه (بدون قید فاز) توصیف کرده بودند، در حالی که `ROADMAP.md` کلمه «Versioning» را فقط زیر Phase 15 لیست کرده بود.

**تصمیم مصوب مالک محصول (Policy):**

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
6. در MVP، قوانین مالکیت Tenant و Authorization برای Templateها و نسخه‌های Tenant-owned مشخص و اجراپذیر طراحی شوند؛ هر Template یا Version سطح‌پلتفرم در آینده خارج از MVP است و به تصمیم معماری جداگانه نیاز دارد (D-012 / Q-013).

**ویژگی‌های پیشرفته — قابل‌موکول‌شدن به بعد از MVP** (مگر این‌که یک نیازمندی تأییدشده دیگر صراحتاً آن‌ها را بخواهد):
- مقایسه بصری نسخه‌به‌نسخه (Visual version-to-version comparison)
- رابط کاربری پیشرفته Rollback/Restoration
- مرور گسترده تاریخچه نسخه‌ها
- Branching یا نسخه‌های موازی Template
- گزارش‌های پیشرفته Diff و تحلیل اثر تغییر

**این موکول‌شدن به معنای حذف الزامات حداقلی قابلیت‌ممیزی و تاریخچه بالا نیست.**

**اثر این تصمیم روی سایر اسناد:** `PROJECT_SCOPE.md`، `ARCHITECTURE.md`، `DATABASE.md`، `ROADMAP.md`، `API.md`، `SECURITY.md`، `TEST_PLAN.md`، `PRODUCT_REQUIREMENTS.md` بر همین اساس به‌روزرسانی شده‌اند تا با این Policy هماهنگ باشند. مالک محصول این Policy را صریحاً تأیید کرده است؛ این تأیید فقط D-008/Q-012 را تعیین تکلیف می‌کند و هیچ سؤال باز دیگری را نمی‌بندد.

**دلیل:** درخواست مستقیم Supervisor Review برای رفع تناقض Template/Plan Versioning؛ اصل کلی‌تر این است که تصمیمات معماری/محصول باید صریحاً ثبت شوند، نه این‌که به‌صورت ضمنی و ناهماهنگ در چند سند مختلف حل شوند.
**وضعیت:** **Accepted — صریحاً توسط Product Owner در گفتگو تأیید شد؛ 2026-10-10.**


## Product Owner decisions recorded on 2026-10-12
See `OPEN_QUESTIONS.md` Q-001, Q-002, and Q-010 for the accepted decisions.


## D-009 — Tenant Isolation برای MVP
**وضعیت: ACCEPTED در 2026-10-12؛ مکانیزم قبلی با D-019 در 2026-10-23 برای بازطراحی مجدداً OPEN شد.** الزام Tenant Isolation همچنان غیرقابل‌مذاکره است؛ D-009 قبلاً مکانیزم MVP را تعیین می‌کرد، اما D-019 آن مکانیزم را برای ارزیابی مجدد باز کرده است. تا حل Q-022، این بخش سابقه تصمیم قبلی است و مجوز اجرای shared-database/Option C نیست.

**تصمیم:** یک PostgreSQL database/schema مشترک؛ ستون مستقیم، indexed و `NOT NULL` به نام `tenant_id` روی همه ردیف‌های tenant-scoped؛ authorization در Application/API layer و PostgreSQL RLS به‌عنوان defense in depth. قیدها و روابط composite یا سازوکار معادل باید سازگاری tenant والد/فرزند را enforce کنند. دسترسی cross-tenant برای Platform Admin فقط با مجوز صریح، محدود و audit‌شده مجاز است.

**الزامات اجرا:** tenant context از هویت احراز‌شده مشتق شود؛ IDهای path/body به‌تنهایی مجوز نیستند؛ هر resource و عملیات object-level بررسی شود؛ نقش runtime نباید مالک جدول‌های tenant یا دارای دسترسی privileged برای bypass کردن RLS باشد؛ policyها و رفتار owner/privileged roles بررسی شوند و در صورت اقتضا RLS اجباری یا کنترل معادل اعمال شود. تست‌های منفی cross-tenant برای API، repository، background jobs، reports/exports، files و notifications الزامی‌اند. RLS به‌تنهایی کافی نیست.

**دلیل:** سادگی عملیاتی برای MVP همراه با دفاع چندلایه در برابر نشت tenant. Schema-per-tenant و database-per-tenant برای MVP انتخاب نشدند. این تصمیم مستندی، پیاده‌سازی یا اثبات امنیت runtime نیست.

## D-010 — محدوده کنترل‌شده MVP
**وضعیت: ACCEPTED — تصمیم صریح مالک محصول در 2026-10-12؛ پاسخ Q-002.**

**تصمیم:** `PROJECT_SCOPE.md` مرجع محدوده MVP است. MVP باید حلقه ارزش «برنامه‌ریزی → اجرا و ثبت → تحلیل → اصلاح برنامه» را با امکانات پایه واقعی پوشش دهد: Auth/RBAC پایه؛ رابطه مشاور–دانش‌آموز و پروفایل/دروس؛ برنامه روزانه/هفتگی و حداقل versioning قابل‌ممیزی برای Program Template و Student Plan طبق D-008؛ فعالیت‌های اولیه Study Session/Test/Review، تکالیف و کلاس‌های لازم؛ تحلیل خطا و عملکرد پایه، کارهای عقب‌افتاده، اعلان درون‌برنامه‌ای و StudentCredit/CreditTransaction ledger قابل‌ممیزی. Billing MVP به Mock/manual flow محدود است.

**خارج از MVP:** native mobile app؛ Telegram/SMS عملیاتی؛ درگاه واقعی پرداخت؛ AI/planning black box؛ analytics و risk engine پیشرفته؛ ابزارهای پیشرفته versioning؛ پنل کامل والد. گسترش محدوده فقط با تصمیم صریح و ثبت‌شده Product Owner مجاز است. Q-007 درباره دسترسی والد همچنان باز می‌ماند.

## D-011 — هدف میزبانی Pilot و قابلیت انتقال
**وضعیت: ACCEPTED — تصمیم صریح مالک محصول در 2026-10-12؛ پاسخ Q-010.**

**تصمیم:** هدف اولیه Pilot یک VPS داخل ایران با استقرار قابل‌انتقال مبتنی بر Docker Compose است. هنوز هیچ Vendor یا پلن مشخصی انتخاب نشده است. PostgreSQL باید در شبکه خصوصی باشد؛ HTTPS، مدیریت امن secrets، لاگ بدون secrets/اطلاعات حساس، backup رمزگذاری‌شده خارج از سرور و آزمون restore الزامی‌اند. Redis فقط در صورت توجیه فنی/عملکردی وارد پیکربندی می‌شود.

**قید:** Core/Domain نباید به Vendor وابسته شود. Docker Compose انتخاب شروع و Pilot است، نه تضمین High Availability یا Production Readiness. دسترسی به سرویس‌های خارجی باید برای هر Adapter جداگانه بررسی شود.

**دلیل:** کاهش پیچیدگی و هزینه آغازین در کنار قابلیت انتقال و محافظت از داده.

## D-012 — مالکیت Tenant-only برای ProgramTemplate و ProgramVersion در MVP
**وضعیت: ACCEPTED — تصمیم صریح مالک محصول در 2026-10-13؛ Q-013 حل شد.**

**تصمیم مصوب (گزینه A):**
1. در MVP، هر `ProgramTemplate` متعلق به یک Tenant است و `tenant_id` آن `NOT NULL` خواهد بود.
2. در MVP، هر `ProgramVersion` نیز متعلق به همان Tenant صاحب Template منبع است. روابط و constraints دیتابیس باید مانع اتصال Version به Template متعلق به Tenant دیگر شوند.
3. قالب‌های عمومی/سطح‌پلتفرم و `ProgramVersion`های وابسته به آن‌ها خارج از MVP هستند. هیچ مدل nullable-tenant، جدول مشترک با مالکیت مختلط، یا دسترسی عمومی read-only برای این قابلیت در MVP انتخاب نشده است.
4. افزودن کتابخانه قالب‌های سطح‌پلتفرم در آینده نیازمند تصمیم معماری و تعریف جداگانه مالکیت، انتشار، کپی/مصرف، نسخه‌بندی و Authorization پیش از پیاده‌سازی است.
5. این تصمیم فقط به catalog قالب‌ها و نسخه‌هایشان مربوط است. `StudentProgramEnrollment`، `Plan` و `PlanVersion` همیشه tenant- و student-scoped باقی می‌مانند. هر عملیات خواندن/نوشتن/انتشار/فعال‌سازی روی Template یا Version باید Authorization را اعمال کند.

**دلیل:** این مدل برای MVP ساده‌تر است، با قاعده `tenant_id NOT NULL` برای ردیف‌های tenant-owned سازگار می‌ماند و از معرفی زودهنگام الگوی مالکیت مختلط یا استثنای دسترسی جلوگیری می‌کند. این تصمیم به‌تنهایی پیاده‌سازی یا امنیت runtime را اثبات نمی‌کند.

---

## D-013 — دسترسی مدیر پلتفرم به داده Tenantها (پاسخ Q-015): Option A
**وضعیت: ACCEPTED — تصمیم صریح مالک محصول، 2026-10-15؛ پاسخ Q-015.**

**تصمیم:** دسترسی بین‌مستأجری مدیر پلتفرم فقط‌خواندنی است، فقط از مسیرهای مشخص و محدود Application انجام می‌شود، مستأجر هدف و دلیل را صراحتاً دارد، زمان‌بندی انقضا دارد، و قبل از ارائه داده ثبت حسابرسی الزامی است. دسترسی‌های موفق و ناموفق هر دو ثبت می‌شوند؛ اگر ثبت حسابرسی شکست بخورد، درخواست رد می‌شود.

**ممنوعیت‌ها:**
- ایجاد نقش `platform_ops` با `BYPASSRLS` برای این قابلیت در MVP ممنوع است.
- هیچ عملیات نوشتن، ویرایش یا حذف داده توسط مدیر پلتفرم در MVP مجاز نیست.
- هیچ دسترسی نامحدود، خروجی انبوه یا دورزدن کنترل‌های عادی مجاز نیست.
- نقش runtime نباید مالک جدول‌های tenant یا دارای `BYPASSRLS` باشد.

**دلیل:** کمترین سطح دسترسی برای پشتیبانی و عملیات، و جلوگیری از ایجاد مسیر دورزدن RLS که اثر آن در برابر خطای برنامه و ریسک T4 بزرگ‌تر است.

**محدوده این تصمیم:** این تصمیم محصول است. پیاده‌سازی و اجرای آزمون‌های TI-PLAT مربوط هنوز انجام نشده و تأیید فاز ۱ را به‌تنهایی نتیجه نمی‌دهد.

**اثر بر اسناد:** `docs/phase1/TENANT_ISOLATION_DESIGN.md` (§5.1، §8)، `docs/phase1/TENANT_ISOLATION_TEST_CONTRACTS.md` (TI-PLAT-06، 08، 09، 10)، `docs/phase1/TENANT_PATH_INVENTORY.md` (P-25، P-26)، `OPEN_QUESTIONS.md` (Resolved).

---

## D-014 — جهت‌گیری امنیتی Tenant Context و سیاست داده Pilot (پاسخ Q-019)
**وضعیت: جهت‌گیری ACCEPTED — تصمیم صریح مالک محصول، 2026-10-15. سازوکار فنی: OPEN.**

**تصمیم جهت‌گیری:** مرز امنیتی Tenant Context باید پیش از هر Pilot دارای داده واقعی دانش‌آموزان تقویت شود. صرف پذیرش ریسک T4 در چارچوب D-009 کافی شمرده نمی‌شود.

**سیاست داده (الزامی):** تا تکمیل همه‌ی موارد زیر، ورود داده واقعی دانش‌آموزان به Pilot ممنوع است:
1. بازبینی امنیتی مستقل انجام شده باشد؛
2. آزمون‌های امنیتی لازم برای سازوکار انتخابی اجرا و موفق شده باشند؛
3. موارد مسدودکننده رفع شده باشند؛
4. مالک محصول دروازه Pilot را صریحاً و کتباً تأیید کرده باشد.

**آنچه این تصمیم نیست:**
- انتخاب خودکار Option C یا Option D نیست.
- تأیید `SECURITY DEFINER` نیست.
- اثبات رفع T4 نیست.
- تغییر D-009 نیست؛ D-009 بدون تغییر باقی می‌ماند.

**گزینه‌های فنی پیشنهادی برای بازبینی مستقل (غیرقطعی):** Option C (هویت پایگاه‌داده جدا برای هر Tenant، بدون عضویت متقابل یا عضویت در نقش پلتفرم) به‌عنوان کاندیدای فنی برای مقیاس Pilot؛ Option D (توکن امضاشده و تابع SECURITY DEFINER با جدول context، بدون اتکا به GUC در policy) به‌عنوان گزینه جایگزین. هر دو طبق `docs/phase1/TENANT_ISOLATION_DESIGN.md` §2.3.1 و §2.4 بررسی می‌شوند.

**وضعیت Phase 1:** با Q-019 در حالت mechanism-open، Phase 1 نمی‌تواند به‌عنوان دارای مرز امنیتی در برابر T4 تأیید شود.

**اثر بر اسناد:** `OPEN_QUESTIONS.md` (Q-019)، `docs/phase1/TENANT_ISOLATION_DESIGN.md`، `docs/phase1/TENANT_ISOLATION_TEST_CONTRACTS.md` (TI-CONN-01..03، TI-CTX-15..18)، `docs/phase1/TENANT_PATH_INVENTORY.md` (P-32، P-33)، `SUPERVISOR_REVIEW.md`.

---

## D-015 — پذیرش تفکیک معیار انتخاب طراحی و معیار اعتبارسنجی پایلوت (پاسخ بن‌بست C-01)
**وضعیت: ACCEPTED — تصمیم صریح مالک محصول، 2026-10-17.**

**تصمیم:** معیار بررسی و تصمیم‌گیری درباره‌ی طراحی Phase 1 با معیار اعتبارسنجی پایلوت جدا است، طبق `docs/phase1/Q019_MECHANISM_EVALUATION.md` §۶.۱:

1. **معیار انتخاب طراحی** (قابل بررسی و تصمیم‌گیری بدون اجرای آزمون): مکانیزم به‌اندازه‌ی کافی دقیق تعریف شده باشد؛ پیامد هر مدل مهاجم و هر کلاس اعتبارنامه (K-L، K-T، K-S، K-O) ثبت شده باشد؛ باقی‌مانده‌ی ریسک‌ها با کنترل پیشنهادی ثبت شده باشند؛ و قراردادهای آزمون با نتیجه‌ی مورد انتظار برای هر گزینه، در وضعیت NOT-RUN نوشته شده باشند.
2. **معیار اعتبارسنجی پایلوت** (پیش‌شرط ورود داده‌ی واقعی طبق D-014، نه پیش‌شرط تصمیم طراحی): اجرای آزمون‌های خصمانه روی مکانیزم پیاده‌سازی‌شده، اندازه‌گیری ظرفیت، بازبینی مستقل پیاده‌سازی، و تأیید کتبی دروازه‌ی پایلوت.

**پیامد:** اجرای آزمون‌هایی که متعلق به مراحل بعد هستند، پیش‌شرط تصمیم‌گیری درباره‌ی طراحی Phase 1 یا پیش‌شرط شروع Phase 2 نیست.

**آنچه این تصمیم نیست:**
- تأیید Phase 1 نیست. تأیید نیازمند بازبینی مستقل روی commit جدید و تصمیم شما در گیت فاز است.
- انتخاب Q-019 نیست. سازوکار C، D یا پذیرش ریسک هنوز تصمیم داده نشده است.
- تغییر D-009 یا D-014 نیست. D-014 بدون تغییر است: داده‌ی واقعی دانش‌آموزان همچنان تا تکمیل معیار اعتبارسنجی پایلوت ممنوع است.
- تأیید قاعده‌ی ظرفیت (§۶.۲) نیست؛ آن موضوع جدا است و هنوز پذیرفته نشده است.

**اثر بر اسناد:** `OPEN_QUESTIONS.md` (بن‌بست C-01 بسته‌شده به‌عنوان تصمیم؛ Q-019 همچنان باز)، `SUPERVISOR_REVIEW.md` (پذیرش مالک محصول ثبت شد)، `docs/phase1/PHASE1_REPORT.md` (§۱۸).

---

## D-016 — تصمیم مالک محصول درباره‌ی سازوکار Q-019 و شرایط Option C
**وضعیت: ACCEPTED — تصمیم صریح مالک محصول، 2026-10-17. این تصمیم امنیت runtime را اثبات نمی‌کند و مجوز استفاده از داده‌ی واقعی پایلوت نیست.**

1. **Q-019 (جهت طراحی):** Option C به‌عنوان جهت ترجیحی طراحی انتخاب شد، مشروط به تکمیل بازبینی طراحی.
2. **Option D:** فعلاً انتخاب نشده و وضعیت NOT SELECTION-READY دارد تا هر هفت نکته‌ی طراحی‌کلیدی حل و به‌طور مستقل بازبینی شوند.
3. **امضا و کنترل بازپخش در D (در صورت بازگشت به آن):** ابتدا امضای نامتقارن (asymmetric) ارزیابی شود. سیاست توکن یک‌بارمصرف یا قابل‌استفاده‌ی مجدد و سیاست `jti` باید صراحتاً تصمیم گرفته شوند. انتخاب نهایی فعلاً به تعویق افتاده است.
4. **A1، اندازه‌ی پایلوت:** سقف موقت ۱۰ تنانت، مشروط به تحلیل ظرفیت و تأیید مالک محصول پیش از پایلوت.
5. **استراتژی Pool در C:** pool/اتصال **محدود، تنبل (lazy) و هر تنانت** استفاده شود. حالت pooler باید مستند شود و رفتار تراکنش/زمینه، محدودیت اتصال و مدیریت خطا پیش از پایلوت اعتبارسنجی شوند. **یادداشت:** مالک محصول حالت pooler را مشخص نکرده است؛ این موضوع زیر Q-016 باز می‌ماند.
6. **چرخه‌ی عمر نقش تنانت:** با تعلیق یا خروج تنانت، ورود نقش فوراً غیرفعال شود؛ دسترسی‌های مرتبط لغو شوند؛ نشست‌ها و اتصال‌های فعال pool پایان یابند یا پاک شوند؛ شواهد حسابرسی نگه داشته شوند؛ و نقش فقط پس از بررسی مالکیت، وابستگی‌ها و الزامات نگهداری داده حذف شود. نقش‌های تنانت نباید مالک هیچ شیء مشترک اپلیکیشن باشند.
7. **Fallback با نقش مشترک:** صراحتاً ممنوع است. گروه‌بندی چند تنانت زیر یک هویت runtime مشترک به‌عنوان راهکار ظرفیت مجاز نیست.
8. **قاعده‌ی ظرفیت (§6.2):** به‌عنوان محدودیت طراحی پذیرفته شد. برآورد، اندازه‌گیری نیست؛ ظرفیت باید پیش از هر پایلوت با داده‌ی واقعی در محیط هدف اندازه‌گیری شود. اگر ظرفیت کافی نبود، دامنه‌ی پایلوت کاهش یابد یا طراحی بازبینی شود.
9. **دروازه‌ی امنیتی (D-014):** بدون تغییر. داده‌ی واقعی دانش‌آموزان تا اجرای واقعی آزمون‌های امنیتی لازم و موفقیت آن‌ها، تکمیل بازبینی مستقل پیاده‌سازی، رفع موارد مسدودکننده و تأیید کتبی مالک محصول مجاز نیست.
10. **وضعیت فاز:** Phase 1 تأیید نشده می‌ماند تا یافته‌های باز بازبین اصلاح و تصمیم طراحی به‌طور یکسان ثبت شود. Phase 2 تا تحقق گیت بازبین شروع نمی‌شود.

**آنچه این تصمیم نیست:**
- اثبات امنیت runtime نیست.
- اجازه‌ی پایلوت با داده‌ی واقعی نیست.
- تأیید Phase 1 نیست.
- انتخاب C به‌عنوان راهکار پیاده‌سازی‌شده یا آزمون‌شده نیست.

**اثر بر اسناد:** `docs/phase1/Q019_MECHANISM_EVALUATION.md` (§6.2، §6.3)، `docs/phase1/TENANT_ISOLATION_DESIGN.md` (§2.4، §5.5)، `docs/phase1/TENANT_ISOLATION_TEST_CONTRACTS.md`، `OPEN_QUESTIONS.md` (Q-016، Q-019، Q-020)، `SUPERVISOR_REVIEW.md`، `PROJECT_STATE.md`.

---

## D-017 — تصمیم مالک محصول: حالت pooler (Q-016)، سیاست نگهداری و حذف نقش تنانت (Q-020)، و سقف اولیه‌ی پایلوت (A1)
**وضعیت: ACCEPTED — تصمیم صریح مالک محصول، 2026-10-17.**
**این تصمیم امنیت runtime را اثبات نمی‌کند، شرط‌های D-014 را کامل نمی‌کند و مجوز ورود داده‌ی واقعی دانش‌آموزان نیست.**

### بند ۱ — حالت اتصال (Q-016)
1. برای پایلوت از **اتصال مستقیم PostgreSQL با pool محدود** استفاده می‌شود.
2. اندازه‌ی pool هر تنانت در هر فرایند **۱** است (ESTIMATE: با ۱۰ تنانت، ۶ فرایند و pool ۱، حدود ۷۰ اتصال؛ با pool ۲ حدود ۱۳۰ اتصال که از سقف پیش‌فرض ۱۰۰ بیشتر است). افزایش pool فقط پس از اندازه‌گیری و تأیید جداگانه مجاز است.
3. **Transaction Pooling** (مثلاً PgBouncer) فعلاً پیش‌شرط پایلوت نیست. پذیرش آن بعداً فقط پس از تعریف و قبولی آزمون‌های سازگاریِ مخصوص transaction pooling و تصمیم جداگانه‌ی مالک محصول ممکن است. قراردادهای TI-CONN-04 و TI-CTX-11/12 پس از اصلاح، بررسی چرخه‌ی اتصال مستقیم در پایلوت هستند و به‌تنهایی سازگاری transaction pooling را اثبات نمی‌کنند.
4. اگر prepared statements در حالت Transaction استفاده شوند، باید صراحتاً آزموده شوند؛ در غیر این صورت غیرفعال هستند.

### بند ۲ — نگهداری داده و حذف نقش (Q-020)
1. **اصل سیاست پذیرفته شد:** حذف خودکار نقش تنانت هنگام پایان اشتراک یا غیرفعال‌شدن مشاور ممنوع است. چرخه‌ی اجرایی: (الف) غیرفعال‌سازی فوری ورود و دسترسی؛ (ب) لغو مجوزها و پایان نشست‌ها و اتصال‌های pool؛ (ج) نگهداری شواهد حسابرسی و اطلاعات لازم برای بررسی رخدادها؛ (د) بررسی مالکیت اشیا، وابستگی‌ها، نسخه‌های پشتیبان و تعهدات نگهداری؛ (ه) حذف نقش فقط پس از تأیید چک‌لیست.
2. **مدت نگهداری دقیق تعیین نشد.** تعیین آن پیش از پایلوت الزامی است و به تعهدات حقوقی، مالیاتی و حریم خصوصی وابسته است.
3. **پیش از پایلوت** باید یک جدول سیاست نگهداری شامل داده‌ی دانش‌آموز، سوابق حسابرسی، صورت‌حساب‌ها و نسخه‌های پشتیبان تهیه شود، و سیاست حذف در نسخه‌های پشتیبان نیز مشخص باشد.
4. **مسئول تهیه‌ی جدول و مشاور حقوقی/حریم خصوصی:** [مالک محصول تعیین می‌کند؛ هنوز تعیین نشده است].

### بند ۳ — سقف اولیه‌ی پایلوت (A1)
1. سقف **۱۰ تنانت** به‌عنوان سقف شروع پایلوت پذیرفته شد.
2. این سقف **ظرفیت اثبات‌شده نیست**. هر افزایش آن نیازمند شواهد اندازه‌گیری‌شده و تأیید جداگانه‌ی مالک محصول است.
3. **شرط‌های پیش از ورود داده‌ی واقعی:**
   - آزمون بار و اتصال روی محیط هدف (D-011) با نتیجه‌ی ثبت‌شده؛
   - اندازه‌گیری حافظه، CPU، اتصال‌ها و زمان پاسخ؛
   - قبولی آزمون‌های جداسازی تنانت و دسترسی غیرمجاز (مطابق قرارداد مربوط، پس از اجرا)؛
   - آماده‌بودن روش توقف اضطراری و بازگشت از پایلوت؛
   - تأیید کتبی مالک محصول پس از دیدن شواهد.
4. اگر ظرفیت کمتر از انتظار باشد، سقف کاهش می‌یابد.

### آنچه این تصمیم نیست
- اثبات امنیت runtime یا جداسازی تنانت نیست.
- انجام آزمون‌ها یا CI نیست؛ هیچ آزمونی اجرا یا قبول نشده است.
- جایگزین شرط‌های D-014 نیست. D-014 بدون تغییر است.
- انتخاب Option D نیست؛ Option D همچنان NOT SELECTED است.

**اثر بر اسناد:** `OPEN_QUESTIONS.md` (Q-016، Q-020، A1)، `PROJECT_STATE.md`، `docs/phase1/TENANT_ISOLATION_DESIGN.md` (§5.5 pool)، `docs/phase1/Q019_MECHANISM_EVALUATION.md` (§6.2، پیش‌فرض pool).

---

## D-018 — تصمیم مالک محصول: رویکرد پیش از پایلوت (نگهداری داده، بازبینی حقوقی، میزبان، بازبینی امنیتی، توقف اضطراری)
**وضعیت: ACCEPTED — تصمیم صریح مالک محصول، 2026-10-17.**
**این تصمیم فاز ۱ را تأیید نمی‌کند، شرط‌های D-014 را کامل نمی‌کند و مجوز ورود داده‌ی واقعی نیست. تأیید Phase 1 جداگانه و توسط بازبین مستقل انجام می‌شود.**

### بند ۱ — نگهداری داده (Q-020)
1. **رویکرد پذیرفته شد:** حداقل‌سازی داده، یک قاعده‌ی نگهداری برای هر دسته‌ی داده (R1 تا R9 در `DATA_RETENTION_SCHEDULE_DRAFT.md`)، مدت‌های کوتاه و صریح، و تمدید فقط با تصمیم ثبت‌شده.
2. **مدت‌های نگهداری هنوز تعیین نشده‌اند.** هیچ مدت قانونی یا مالیاتی در این تصمیم وجود ندارد. تعیین مدت‌ها پس از بررسی حقوقی و مالیاتی انجام می‌شود.
3. **نقش‌های بررسی (تصمیم برای اقدام):** یک وکیل متخصص داده‌ی کودکان و حریم خصوصی، با دامنه‌ی کتبی فقط برای جدول نگهداری؛ و برای R4 یک حسابدار. خروجی هر کدام یک یادداشت امضاشده است که پس از پذیرش مالک در این گزارش ثبت می‌شود.
4. **تأییدکننده‌ی حذف نقش تنانت:** مالک محصول، پس از دیدن شواهد چک‌لیست. مسئول فنی شواهد را آماده می‌کند.

### بند ۲ — میزبان و آزمون بار (A1 و L-01 تا L-11)
1. **پروفایل میزبان تست:** یک ماشین مجازی اختصاصی لینوکسی، PostgreSQL ۱۵ یا بالاتر، `max_connections` صریح و ثبت‌شده، دیتابیس فقط از میزبان اپلیکیشن قابل دسترس، دیسک رمزگذاری‌شده، و پایش از اولین اجرا.
2. **اندازه‌ی CPU و RAM** پس از اجرای L-01 با اندازه‌گیری تعیین می‌شود، نه پیش از آن.
3. **سقف ۱۰ تنانت** همچنان سقف شروع است و ظرفیت اثبات‌شده نیست (D-017).

### بند ۳ — بازبینی امنیتی پیاده‌سازی (گیت c)
یک بازبین مستقل که کد را ننوشته، با گزارش کتبی. یافته‌های مسدودکننده پیش از پایلوت رفع و دوباره آزمون می‌شوند. این بازبینی برای تأیید طراحی Phase 1 لازم نیست.

### بند ۴ — توقف اضطراری و بازگشت
1. Runbook (`EMERGENCY_STOP_AND_ROLLBACK_RUNBOOK.md`) به‌عنوان **پیش‌نویس پذیرفته شد**.
2. پیش از پایلوت باید تمرین شود (L-11) و زمان‌بندی ثبت شود.
3. بازگردانی نباید تنانت‌های معلق را دوباره فعال کند؛ این مکانیزم پیش از پایلوت ساخته و آزموده شود.
4. **هماهنگ‌کننده‌ی حادثه و جانشین او:** مالک محصول به‌صورت کتبی تعیین می‌کند. این بند تا تعیین نام باز است.
5. **مسئول اعلان داده‌ی شخصی در حادثه:** مالک محصول با مشورت حقوقی تعیین می‌کند. این بند تا تعیین باز است.

### آنچه این تصمیم نیست
- تأیید Phase 1.
- اثبات هیچ کنترل امنیتی.
- اجرای هیچ آزمونی.
- تعیین هیچ مدت نگهداری.
- مجوز داده‌ی واقعی دانش‌آموزان (D-014 بدون تغییر).

**اثر بر اسناد:** `OPEN_QUESTIONS.md` (Q-020)، `PROJECT_STATE.md` (جدول موارد پیش از پایلوت)، `docs/phase1/PHASE1_REPORT.md` (§۲۱).



## D-019 — Require stronger tenant-isolation architecture before Phase 1 approval
**Status: ACCEPTED — explicit Product Owner decision, 2026-10-23.**

**Decision:** The Product Owner selected option B under Q-021. The project will not accept the current Option C residual risks for broad compromise of tenant login credentials (K-L-N) and the owner/migrator boundary (K-O) as the basis for Phase 1 approval. A stronger architecture must be designed and independently reviewed before Phase 1 can be approved.

**Scope of this decision:** This selects the requirement to redesign, not a specific database topology. It does not select database-per-tenant, separate clusters, a hybrid, or any other final mechanism. The alternatives must be compared in `docs/phase1/STRONGER_TENANT_ISOLATION_OPTIONS.md`, then the Product Owner must explicitly approve the resulting architecture before implementation.

**Consequences:**
1. Existing Option C remains a historical/preferred prior direction only; it is not approved as sufficient for the newly stated risk tolerance.
2. D-009's shared-database MVP mechanism is reopened for architecture evaluation. Its underlying non-negotiable requirement—no counselor may access another tenant's data—remains unchanged.
3. No implementation, migration, infrastructure change, Phase 2 work, or real-data pilot is authorized by D-019.
4. Phase 1 remains NOT READY until the revised design is independently reviewed and the gate is explicitly changed.

**Reason:** The Product Owner prefers not to accept a design whose stated compromise paths can expose multiple tenants. Stronger isolation must be assessed honestly against process, credential, privileged-role, operational, and cost boundaries; merely splitting databases without addressing shared credentials/administrators is not sufficient.


## D-020 — Q-022 architecture selection: Alt-5 hybrid isolation cells
**Status: ACCEPTED — explicit Product Owner decision, 2026-10-23.** This records the Product Owner's explicit selection of Q-022 option A.

**Decision:** Select **Alt-5 hybrid isolation cells** as the target architecture for the revised Phase 1 design. Use Alt-4 (dedicated operational isolation per tenant) as the security comparison/reference architecture. For the initial pilot proposal capped at 10 tenants, set a **maximum of two tenants per cell** (up to five cells) as a provisional blast-radius limit, subject to documented cost and capacity evaluation. This is not a measured capacity result and does not authorize a pilot.

**Minimum design requirements:**
1. Each cell has its own PostgreSQL cluster/instance and network boundary. A different database/schema or container on one shared host is not equivalent to this boundary.
2. Runtime workers, credentials, and secret access are cell-scoped; an ordinary worker or secret policy cannot enumerate credentials for other cells.
3. Each cell has cell-scoped migration identities. No routine standing global owner/migrator may read or write all tenant data.
4. Backup access and encryption keys are scoped by cell; restore controls must preserve tenant suspension/offboarding state.
5. Deployment authority is separated from routine data-read authority. Global host/cloud/root compromise remains an explicit high-trust residual and must be mitigated, monitored, and disclosed.
6. Cross-cell break-glass requires dual approval, a ticket/reason, short-lived access, immutable audit evidence, session termination, and post-incident review.
7. The two-tenant cell limit and provisional ten-tenant pilot cap may not be raised without measured capacity/cost evidence and a separate explicit Product Owner decision.
8. The revised design, authorization contract, test catalog, hosting assumption D-011, and pool/capacity assumptions D-017 must be reconciled and independently reviewed before Phase 1 approval.

**Residual-risk statement:** If all valid tenant credentials are independently stolen and usable from an attacker-controlled network, or a global host/cloud administrator controlling every cell and key is compromised, the architecture cannot guarantee zero broad exposure. Controls must prevent a single routine worker, secret-distribution policy, or migration identity from becoming a universal access path. Global-root risk remains subject to explicit pre-pilot risk review; this decision does not silently accept it.

**Consequences:** Q-022 is resolved as an architecture direction, not as proof of implementation or capacity. Phase 1 remains NOT READY pending independent review. No code, migration, infrastructure, Phase 2 work, or real-data pilot is authorized. D-014 remains in force.

**Affected artifacts:** `OPEN_QUESTIONS.md`, `docs/phase1/TENANT_ISOLATION_DESIGN.md`, `docs/phase1/AUTHORIZATION_CONTRACT.md`, `docs/phase1/TENANT_ISOLATION_TEST_CONTRACTS.md`, `PROJECT_STATE.md`, `ROADMAP.md`, `docs/phase1/PHASE1_REPORT.md`.
