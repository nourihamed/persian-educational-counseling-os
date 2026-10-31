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
**وضعیت: ACCEPTED به‌عنوان هدف محصولی/قابلیت انتقال (2026-10-12); TOPOLOGY COMPATIBILITY OPEN تحت Q-023 پس از D-020 (2026-10-23).**

**تصمیم اصلی مالک محصول:** هدف اولیه Pilot، میزبانی داخل ایران، قابلیت انتقال و هزینه/پیچیدگی آغازین پایین است؛ Docker Compose گزینه اولیه برای بسته‌بندی و استقرار بوده است. هنوز Vendor یا پلن مشخصی انتخاب نشده است. PostgreSQL باید در شبکه خصوصی باشد؛ HTTPS، مدیریت امن secrets، لاگ بدون secrets/اطلاعات حساس، backup رمزگذاری‌شده خارج از دامنه خرابی اصلی و آزمون restore الزامی‌اند. Redis فقط در صورت توجیه فنی/عملکردی وارد پیکربندی می‌شود.

**اثر D-020:** هدف محصولیِ میزبانی و قابلیت انتقال حفظ می‌شود، اما فرض قبلی «یک VPS برای کل سامانه» را نمی‌توان بدون بازبینی با Alt-5 سازگار دانست. Alt-5 نیازمند مرز شبکه و PostgreSQL cluster/instance مستقل برای هر cell است. چند container، چند database یا چند PostgreSQL container روی یک host مشترک، مرز امنیتی در برابر compromise میزبان/root محسوب نمی‌شود. Docker Compose می‌تواند ابزار بسته‌بندی/استقرار باشد، اما به‌خودی‌خود مرز جداسازی cell نیست.

**وضعیت فعلی:** هیچ Vendor، توپولوژی میزبان/VM، جداسازی حساب ابری، یا مدل استقرار نهایی برای cellها انتخاب نشده است. گزینه‌ها و پیشنهاد فنی در docs/phase1/HOSTING_CELL_COMPATIBILITY_REVIEW.md آمده‌اند. تصمیم مالک محصول درباره توپولوژی استقرار و مرزهای اشتراک زیر Q-023 باز است. تا زمان تصمیم، نباید «یک VPS مشترک» را معماری پذیرفته‌شده Alt-5 فرض کرد.

**قید:** Core/Domain نباید به Vendor وابسته شود. Docker Compose انتخاب اولیه برای قابلیت انتقال است، نه تضمین High Availability، جداسازی tenant یا Production Readiness. دسترسی به سرویس‌های خارجی باید برای هر Adapter جداگانه بررسی شود.

**دلیل:** حفظ هدف هزینه/قابلیت انتقال بدون ادعای امنیتی فراتر از مرز واقعی زیرساخت. این به‌روزرسانی تصمیم جدیدی به‌جای Product Owner نمی‌گیرد و Phase 1 یا پایلوت را تأیید نمی‌کند.

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
2. اندازه‌ی pool هر تنانت در هر فرایند **۱** است (ESTIMATE تاریخیِ topology قبلی: با ۱۰ تنانت، ۶ فرایند و pool ۱، حدود ۷۰ اتصال؛ با pool ۲ حدود ۱۳۰ اتصال که از سقف پیش‌فرض ۱۰۰ بیشتر است). این اعداد **ظرفیت Alt-5 نیستند** و نباید برای هر cell یا کل سامانه به‌عنوان ظرفیت تأییدشده استفاده شوند. پس از انتخاب topology در Q-023، تعداد worker/process و poolها، اتصال‌های migration/admin/monitoring/recovery و سقف حافظه/اتصال باید برای هر PostgreSQL instance جداگانه محاسبه و در محیط هدف اندازه‌گیری شود. افزایش pool فقط پس از اندازه‌گیری و تأیید جداگانه مجاز است.
3. **Transaction Pooling** (مثلاً PgBouncer) فعلاً پیش‌شرط پایلوت نیست. پذیرش آن بعداً فقط پس از تعریف و قبولی آزمون‌های سازگاریِ مخصوص transaction pooling و تصمیم جداگانه‌ی مالک محصول ممکن است. شناسه‌های قدیمی TI-CONN-04 و TI-CTX-11/12 متعلق به کاتالوگ پیش از Alt-5 هستند و معیار پذیرش فعال محسوب نمی‌شوند؛ قرارداد فعال TI-CELL-15 فقط لغو اعتبارنامه و پایان نشست/اتصال‌های pool را پوشش می‌دهد و سازگاری transaction pooling را اثبات نمی‌کند.
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
4. **Historical gate status (superseded by D-024, 2026-10-24):** when D-019 was recorded, Phase 1 remained NOT READY pending independent review of the revised design. D-020 subsequently selected Alt-5, and D-024 later approved the provider-neutral design/documentation gate only.

**Reason:** The Product Owner prefers not to accept a design whose stated compromise paths can expose multiple tenants. Stronger isolation must be assessed honestly against process, credential, privileged-role, operational, and cost boundaries; merely splitting databases without addressing shared credentials/administrators is not sufficient.


## D-020 — Q-022 architecture selection: Alt-5 hybrid isolation cells
**Status: ACCEPTED — explicit Product Owner decision, 2026-10-23.** This records the Product Owner's explicit selection of Q-022 option A.

**Decision:** Select **Alt-5 hybrid isolation cells** as the target architecture for the revised Phase 1 design. Use Alt-4 (dedicated operational isolation per tenant) as the security comparison/reference architecture. For the initial pilot proposal capped at 10 tenants, set a **maximum of two tenants per cell** (up to five cells) as a provisional blast-radius limit, subject to documented cost and capacity evaluation. This is not a measured capacity result and does not authorize a pilot.

**Minimum design requirements:**
1. Each cell has its own PostgreSQL cluster/instance and network boundary. A different database/schema or container on one shared host is not equivalent to this boundary.
2. Each tenant has a separate database and tenant-specific runtime credential within its cell. Runtime workers and secret access are scoped to one tenant or one cell under an explicitly documented boundary; no ordinary worker may hold reusable credentials for both tenants, and no ordinary worker or secret policy can enumerate credentials for other cells.
3. Each cell has cell-scoped migration identities. No routine standing global owner/migrator may read or write all tenant data.
4. Backup access and encryption keys are scoped by cell; restore controls must preserve tenant suspension/offboarding state.
5. Deployment authority is separated from routine data-read authority. Global host/cloud/root compromise remains an explicit high-trust residual and must be mitigated, monitored, and disclosed.
6. Cross-cell break-glass requires dual approval, a ticket/reason, short-lived access, immutable audit evidence, session termination, and post-incident review.
7. The two-tenant cell limit and provisional ten-tenant pilot cap may not be raised without measured capacity/cost evidence and a separate explicit Product Owner decision.
8. The revised design, authorization contract, test catalog, hosting assumption D-011, and pool/capacity assumptions D-017 must be reconciled and independently reviewed before Phase 1 approval.

**Within-cell boundary:** the two tenants in a cell must not share a tenant-content database or routine runtime credential. A normal tenant credential must not access the other tenant in the same cell. A shared cluster/host/root compromise may affect both tenants and is a separate residual.

**Residual-risk statement:** If all valid tenant credentials are independently stolen and usable from an attacker-controlled network, or a global host/cloud administrator controlling every cell and key is compromised, the architecture cannot guarantee zero broad exposure. Controls must prevent a single routine worker, secret-distribution policy, or migration identity from becoming a universal access path. Global-root risk remains subject to explicit pre-pilot risk review; this decision does not silently accept it.

**Historical gate status (superseded by D-024, 2026-10-24):** at the time D-020 was recorded, Q-022 was resolved as an architecture direction, not as proof of implementation or capacity, and Phase 1 remained NOT READY pending independent review. D-024 later approved the provider-neutral Phase 1 design/documentation gate only. No code, migration, infrastructure, Phase 2 work, or real-data pilot is authorized by D-020; D-014 remains in force.

**Affected artifacts:** `OPEN_QUESTIONS.md`, `docs/phase1/TENANT_ISOLATION_DESIGN.md`, `docs/phase1/AUTHORIZATION_CONTRACT.md`, `docs/phase1/TENANT_ISOLATION_TEST_CONTRACTS.md`, `PROJECT_STATE.md`, `ROADMAP.md`, `docs/phase1/PHASE1_REPORT.md`.


## D-021 — Local laptop development first; server deployment later
**Status: ACCEPTED — explicit Product Owner direction (2026-10-23).**

**Decision:** For the current development period, the project is to run on the Product Owner's own laptop so implementation can progress without prematurely selecting or paying for a remote server. When the product reaches an agreed demonstrable stage, server deployment will be planned and reviewed separately.

**Local environment constraints:** Prefer reproducible local setup; keep development services bound to loopback/local interfaces; use synthetic/test data only; do not expose database, cache, debug or admin services to the public internet; do not commit or reuse production secrets. Local containers on one laptop are not a security boundary against compromise of the laptop/host administrator.

**Relationship to Alt-5:** D-020 remains in force as the selected isolation direction for the proposed pilot. D-021 does not replace Alt-5 with a weaker hosted architecture, and does not claim that laptop containers prove tenant isolation. Q-023 remains OPEN for the eventual server topology. The proposed maximum of two tenants per cell remains provisional pending measured cost/capacity.

**Transition gate:** Before server deployment, resolve Q-023, evaluate target hosting and itemized cost/capacity, define operations and recovery controls, rehearse migration/restore with synthetic data, and complete applicable independent security and phase gates. D-014's real-data pilot prohibition remains in force until all required gates and explicit Product Owner approval.

**Scope:** This decision records a development strategy only. It does not authorize Phase 2, create infrastructure or code, approve Phase 1, or authorize real student data. See `docs/phase1/LOCAL_DEVELOPMENT_AND_LATER_DEPLOYMENT.md`.


## D-022 — Q-023 deferral: local development first, hosting decision later (historical gate wording superseded by D-024)
**Status: ACCEPTED — explicit Product Owner decision, 2026-10-23.**

**Decision:** Defer selection of the eventual hosted topology/provider until hosted deployment planning. Continue only the local-development strategy under D-021, using synthetic data and local-only services. Q-023 remains OPEN; this decision does not select Q-023 topology option B/C/Alt-4 and does not amend D-020's Alt-5 security requirements.

**Independent gate disposition:** The deferral is accepted as a scheduling decision, not as a security waiver. The exact provider, instance sizes, pricing and measured capacity need not be selected merely to continue local development. However, Phase 1 approval still requires the Alt-5 target architecture's host/network/admin trust boundaries and global-compromise residual to be sufficiently specified and independently accepted. Since Q-023 currently leaves the cell hosting/administrative compromise boundary unresolved, this reviewer does **not** remove it from the Phase 1 gate. A later explicit, documented Product Owner decision may change the gate only after a review establishes that doing so does not weaken D-020/D-014; this decision does not do so.

**Unchanged constraints:** D-020 remains normative; each cell needs its own PostgreSQL cluster/instance and network boundary; no shared-host container arrangement may be represented as independent against host/root compromise. The proposed maximum of two tenants per cell and ten tenants total remains provisional pending measured cost/capacity. D-014 remains in force: no real student data until all applicable security, implementation, operational, capacity, independent-review and written-approval gates pass.

**Consequences as recorded on 2026-10-23 (historical gate status, superseded by D-024):** local development may proceed only when separately authorized by the phase plan. At that time Phase 1 remained NOT READY / NOT APPROVED. D-024 subsequently approved only the provider-neutral design/documentation gate; Phase 2 remains NOT STARTED / NOT AUTHORIZED, hosting is not approved, and real student data remains prohibited.

**Affected artifacts:** OPEN_QUESTIONS.md (Q-023), PROJECT_STATE.md, docs/phase1/PHASE1_REPORT.md, SUPERVISOR_REVIEW.md, docs/phase1/LOCAL_DEVELOPMENT_AND_LATER_DEPLOYMENT.md.


## D-023 — Production isolation target: Level 3 cells with Level 4 independent critical backups (historical gate status superseded by D-024)
**Status: ACCEPTED — explicit Product Owner decision, 2026-10-23.**

**Decision:** The target for the production architecture is **Level 3 administrative and infrastructure independence for production isolation cells**, combined with **Level 4 independence for critical backups/recovery**. These labels are project-specific security targets, not a claim that a provider or deployment already satisfies them.

**Level 3 target for production cells:**
1. A compromise of one cell's routine administrative credentials must not automatically grant administrative control over other cells.
2. Each cell must have a distinct host/VM and network boundary, its own PostgreSQL cluster/instance, tenant-specific databases and runtime credentials, and cell-scoped workers, secrets and migration identities.
3. Separate cloud accounts/projects or a demonstrably equivalent independent administrative boundary must be evaluated; multiple VMs or Compose stacks inside one shared administrative/root boundary are not sufficient evidence by themselves.
4. Shared deployment/control-plane access must not become a routine universal path to tenant data or enumerate all usable tenant credentials. Any global/break-glass access must be constrained, time-limited, dual-approved where applicable, and auditable.
5. Provider control-plane compromise and compromise of a genuinely global organization/root identity remain explicit residual risks; no absolute-immunity claim is made.

**Level 4 target for critical backups/recovery:**
1. Critical backups must be held outside the production account's ordinary administrative control, using a separate provider or a demonstrably independent account/administrative boundary.
2. Backup encryption keys and deletion/retention controls must be independent of routine production credentials; production compromise alone should not permit deletion or replacement of all recovery copies.
3. Backup integrity, retention/immutability options, restoration permissions and recovery procedures must be validated, and restore drills must preserve tenant suspension/offboarding state.
4. The backup target and control model must be verified before claiming Level 4; if the selected provider cannot supply the required separation, an alternative provider/account or equivalent control must be evaluated.

**Scope and unresolved work:** This decision sets the required security target, not the final provider, vendor, plan, price, account topology, or implementation. Q-023 remains OPEN until the hosting compatibility review establishes that a real candidate can meet the target and the architecture-level trust boundaries/residuals are independently reviewed. Exact pricing and measured capacity may remain deferred until hosted deployment planning; no security condition is waived.

**Unchanged constraints as recorded on 2026-10-23 (historical gate status, superseded by D-024):** D-020 Alt-5 remains the selected isolation direction; D-014 continues to prohibit real student data until required implementation, security, operations, capacity and independent-review gates pass and the Product Owner gives explicit written approval. At that time Phase 1 remained NOT READY / NOT APPROVED. D-024 later approved the provider-neutral design/documentation gate only; Phase 2 remains NOT STARTED / NOT AUTHORIZED. No code, infrastructure, migration or executable test is authorized or claimed by this decision.

**Affected artifacts:** OPEN_QUESTIONS.md (Q-023), PROJECT_STATE.md, ROADMAP.md, SECURITY.md, TEST_PLAN.md, docs/phase1/PHASE1_REPORT.md, SUPERVISOR_REVIEW.md, docs/phase1/TENANT_ISOLATION_DESIGN.md, docs/phase1/AUTHORIZATION_CONTRACT.md, docs/phase1/TENANT_ISOLATION_TEST_CONTRACTS.md, docs/phase1/HOSTING_CELL_COMPATIBILITY_REVIEW.md, CHANGELOG.md.


## D-024 — Separate Phase 1 design approval from provider-specific deployment validation
**Status: ACCEPTED — Product Owner direction recorded from the explicit instruction to defer hosting-provider comparison, 2026-10-24.**

**Decision:** Phase 1 is a documentation/design phase. Its gate evaluates whether the provider-neutral Alt-5 architecture, trust boundaries, residual risks, authorization contract, and planned acceptance contracts are sufficiently specified and independently reviewed. Selecting a hosting provider, proving a provider's account/admin capabilities, pricing, capacity measurements, and running environment-only tests are deferred to hosted-deployment planning and are not prerequisites to approving the Phase 1 design documentation.

**Hard deployment/pilot gate:** Q-023 remains OPEN. Before any hosted deployment, the selected candidate and topology must be checked against D-020/D-023; Level 3 cell infrastructure/administrative independence and Level 4 independent critical-backup administration must be evidenced; cost/capacity and restore/failure-containment tests must be completed. Before any real student data, all D-014 implementation, security, operational, capacity, incident-drill, independent-review, and written Product Owner approval conditions remain mandatory.

**Security boundary unchanged:** this decision does not select a provider/topology, waive Q-023 for deployment, weaken D-020/D-023, claim that the architecture is implemented, treat planned tests as passed, authorize Phase 2 automatically, or permit real student data. The current phase may receive a design-only APPROVED verdict only after the independent documentation review finds no remaining Phase 1 design blocker.

**Affected artifacts:** OPEN_QUESTIONS.md (Q-023), PROJECT_STATE.md, ROADMAP.md, docs/phase1/TENANT_ISOLATION_DESIGN.md, docs/phase1/AUTHORIZATION_CONTRACT.md, docs/phase1/TENANT_ISOLATION_TEST_CONTRACTS.md, docs/phase1/PHASE1_REPORT.md, docs/phase1/HOSTING_CELL_COMPATIBILITY_REVIEW.md, SUPERVISOR_REVIEW.md, CHANGELOG.md.



## D-025 — یکتایی ثبت‌نام فعال بر اساس موبایل نرمال‌شده و پایه تحصیلی
**تصمیم مالک محصول:** برای هر ترکیب شماره موبایل نرمال‌شده دانش‌آموز و پایه تحصیلی، در کل پلتفرم حداکثر یک ثبت‌نام فعال نزد یک مشاور مجاز است. دانش‌آموز برای داشتن مشاور دوم در همان پایه باید از شماره موبایل دیگری استفاده کند و حساب‌ها را مستقل مدیریت کند. استفاده از همان موبایل در پایه دیگر، تابع سایر قواعد محصول است.

**قرارداد کلید فنی برای MVP:** مقدار ذخیره‌شدهٔ موبایل باید فقط به شکل canonical E.164 باشد (علامت + و ارقام، بدون فاصله/خط‌تیره/قالب محلی). تبدیل ورودی‌های مجاز کاربر به E.164 باید در لایهٔ ورودی/API تعریف و آزمون شود؛ پایگاه داده قالب canonical را رد/قبول می‌کند اما خودش شمارهٔ محلی را حدس یا تبدیل نمی‌کند. کلید پایهٔ MVP یکی از `grade_10`, `grade_11`, `grade_12` است؛ برچسب نمایشی پایه، کلید یکتایی نیست.

**وضعیت اجرا:** DDL اکنون فیلدهای کلید canonical و registry سراسری با کلید اصلی (mobile, grade) و trigger هم‌زمان‌ساز را دارد؛ آزمون‌های رگرسیون و سناریوی رقابت دو session نیز اضافه شده‌اند. این‌ها هنوز روی PostgreSQL اجرا نشده‌اند و موفقیت/رفتار concurrency تأیید نشده است. مرجع: `docs/phase2/schema/phase2_schema_draft.sql`, `docs/phase2/schema/phase2_constraint_tests.sql`, `docs/phase2/concurrency/run_concurrency.sh`.

## D-026 — انتقال دانش‌آموز مشروط به تأیید دریافت حق‌الزحمه مشاور قبلی
**وضعیت: ACCEPTED — تصمیم صریح مالک محصول، 2026-10-27.**

**تصمیم:** مدیر سامانه یا ولی/سرپرست ثبت‌شده دانش‌آموز می‌تواند انتقال دانش‌آموز از مشاور قبلی به مشاور جدید را آغاز کند. انتقال فقط پس از آن مجاز است که مشاور قبلی شخصاً و از حساب احراز هویت‌شده خود تأیید دریافت حق‌الزحمه را ثبت کرده باشد. مدیر و ولی/سرپرست نمی‌توانند این شرط را دور بزنند.

**ثبت قابل‌ممیزی الزامی:** هویت مشاور تأییدکننده، زمان تأیید، شناسه دانش‌آموز و ثبت‌نام قبلی مشخص باید ثبت و در تاریخچه حسابرسی حفظ شود. این تأیید اظهار ثبت‌شده مشاور است، نه تأیید مستقل پرداخت. تأیید نمی‌تواند برای انتقال دانش‌آموز یا ثبت‌نام دیگری استفاده شود.

**یکپارچگی و مجوزها:** سابقه ثبت‌نام قبلی حفظ شود و انتقال با حذف فیزیکی تاریخچه پیاده‌سازی نشود. پایان ثبت‌نام قبلی و ایجاد ثبت‌نام جدید باید اتمیک و در برابر عملیات هم‌زمان ایمن باشد. آغازکننده انتقال باید برای همان دانش‌آموز مجوز داشته باشد.

**محدودیت:** این تصمیم قاعده محصول را تعیین می‌کند، نه اثبات پیاده‌سازی آن را. استفاده از داده واقعی دانش‌آموزان، migration، استقرار تولیدی یا Phase 3 را مجاز نمی‌کند. Q-007 درباره مدل عمومی دسترسی والد همچنان باز است؛ این تصمیم فقط مجوز مشخص انتقال را تعیین می‌کند. PR #8 تا بازبینی مستقل، Draft و ادغام‌نشده باقی می‌ماند.


## D-027 — الزام رضایت والد/سرپرست برای هر انتقال دانش‌آموز بین مشاوران
**وضعیت: ACCEPTED — تصمیم صریح مالک محصول، 2026-10-31.**

**تصمیم:** هرگونه انتقال دانش‌آموز از یک مشاور به مشاور دیگر، چه درون یک سازمان و چه بین دو سازمان، منوط به اخذ رضایت صریح و قابل‌اثبات از **یکی از والدین ثبت‌شده یا سرپرست قانونیِ دارای اختیار معتبر** است (گزینه C، انتخاب‌شده توسط مالک محصول در 2026-10-31). رضایت هر دو والد به‌صورت پیش‌فرض لازم نیست. اگر شخص رضایت‌دهنده سرپرست قانونی است، اختیار قانونی او باید پیش از انتقال احراز و ثبت شود. بدون رضایت معتبر یکی از این اشخاص، انتقال ممنوع است. عضویت دو مشاور در یک سازمان، اختیار انتقال یا دسترسی به دانش‌آموزان یکدیگر ایجاد نمی‌کند.

**تکمیل D-026:** رضایت والد/سرپرست یک شرط مستقل و اضافی است و هیچ‌یک از شروط D-026 را حذف یا تضعیف نمی‌کند. بنابراین انتقال فقط وقتی قابل انجام است که هم رضایت معتبر والد/سرپرست برای انتقال مشخص ثبت شده باشد و هم مشاور قبلی شخصاً از حساب احراز هویت‌شده خود دریافت حق‌الزحمه را برای همان دانش‌آموز و همان ثبت‌نام قبلی تأیید کرده باشد. مدیر سامانه، مدیر سازمان، مشاور جدید یا والد/سرپرست نمی‌توانند تأیید دریافت حق‌الزحمه را به‌جای مشاور قبلی ثبت کنند؛ مشاور قبلی نیز نمی‌تواند رضایت والد/سرپرست را به‌جای او اعلام کند.

**قرارداد ممیزی و امنیت:** رضایت باید به دانش‌آموز، ثبت‌نام قبلی، مشاور مبدأ، مشاور مقصد، والد ثبت‌شده یا سرپرست قانونیِ دارای اختیارِ تأییدکننده، مبنای احراز اختیار در صورت سرپرستی، و زمان ثبت رضایت مقید باشد؛ رضایت کلی یا قابل‌استفاده مجدد برای انتقال‌های دیگر کافی نیست. هویت و اختیار قانونی/ثبت‌شده والد یا سرپرست باید از هویت احراز‌شده سمت سرور به دست آید، نه از UUID ارسالی کاربر. لغو یا تغییر رضایت پیش از commit انتقال باید مانع انتقال شود. رضایت و تأیید حق‌الزحمه باید در یک جریان انتقال اتمیک و concurrency-safe بررسی شوند؛ تاریخچه ثبت‌نام قبلی حفظ و تمام رویدادها audit شوند.

**مرز فاز:** Q-007 درباره مدل عمومی دسترسی والد همچنان باز است. D-027 فقط رضایت لازم برای عملیات انتقال را تعیین می‌کند و به‌خودی‌خود مجوز مشاهده اطلاعات دانش‌آموز یا تعریف دسترسی عمومی والد ایجاد نمی‌کند. پیاده‌سازی به مدل هویت/احراز هویت و ارتباط والد-دانش‌آموز معتبر در Phase 4 وابسته است. تا آن زمان هیچ انتقال واقعی یا استفاده از داده واقعی مجاز نیست.

**اثر:** D-027 به D-026 افزوده می‌شود؛ شروط هر دو تصمیم باید هم‌زمان برقرار باشند. اسناد دامنه، قراردادهای مجوزدهی و تست‌های انتقال در فاز پیاده‌سازی باید بر همین اساس به‌روزرسانی شوند.
