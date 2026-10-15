# OPEN_QUESTIONS.md

طبق قانون "No Guessing" (بخش ۷۸)، این موارد باید توسط مالک پروژه تعیین‌تکلیف شوند.

این سند دو بخش دارد: **Open (Active)** — سؤالاتی که هنوز پاسخ داده نشده‌اند، و **Resolved / Closed** — سؤالاتی که پاسخ داده شده‌اند یا دیگر موضوعیت ندارند (برای حفظ تاریخچه حذف نمی‌شوند).

---

## بخش Open (Active)

## Q-004 — کدام درگاه پرداخت ایرانی اولویت دارد؟
(زرین‌پال، آیدی‌پی، نکست‌پی، سایر) — برای طراحی `PaymentProvider` Adapter لازم است حداقل یک Target واقعی مشخص باشد، حتی اگر در MVP فعال نشود.
**اولویت:** Low (تا Phase 22)

## Q-005 — Telegram Bot زیرساخت
**سؤال:** آیا Bot Token و حساب رسمی Telegram از قبل موجود است یا باید در Phase 19 ایجاد شود؟
**اولویت:** Low (تا Phase 19)

## Q-006 — SMS Provider ایرانی
**سؤال:** کدام سرویس (کاوه‌نگار، ملی‌پیامک، ...) ترجیح داده می‌شود؟
**اولویت:** Low (تا Phase 20)

## Q-007 — سطح دسترسی پیش‌فرض والد (Parent)
**سؤال:** آیا Parent به‌صورت پیش‌فرض باید حساب داشته باشد یا فقط با دعوت صریح مشاور/دانش‌آموز فعال می‌شود؟ یادداشت‌های خصوصی مشاور دقیقاً چه قوانین نمایشی دارند؟
**اولویت:** Medium — قبل از Phase 23، ولی روی مدل داده Phase 2 اثر دارد (آیا Parent از ابتدا Entity باشد یا بعداً اضافه شود).

## Q-008 — واحد زمانی و تقویم پیش‌فرض کاربر
**سؤال:** آیا همه کاربران فقط جلالی می‌بینند یا امکان سوییچ به میلادی هم لازم است از MVP؟
**پیشنهاد:** جلالی پیش‌فرض و الزامی، میلادی اختیاری (قابل اضافه بعداً چون ماژول تقویم ایزوله طراحی می‌شود).
**اولویت:** Low

## Q-009 — سطح اول Risk Engine
**سؤال:** آیا در MVP یک مدل ریسک قانون‌محور ساده (if/else قابل توضیح) کافی است یا از ابتدا باید وزن‌دهی numeric داشته باشد؟
**پیشنهاد:** قانون‌محور ساده، explainable، در MVP؛ وزن‌دهی پیشرفته در Phase 14 تکمیلی.
**اولویت:** Medium


## Q-011 — دسترسی پایدار به Repository گیت‌هاب (بازبینی‌شده — دیگر صرفاً Closed نیست)
**وضعیت: OPEN — نیازمند تصمیم مالک پروژه درباره روش دسترسی دائمی**

این بخش **فقط مواردی را فهرست می‌کند که واقعاً آزموده شده‌اند**، به تفکیک محیط (Claude در مقابل Supervisor) و به تفکیک Read/Write. هیچ نتیجه‌ای از یک محیط به محیط دیگر تعمیم داده نشده است. ترتیب رویدادها واقعی و به‌ترتیب وقوع در طول همین Session (تاریخ: ۲۰۲۶-۱۰-۰۹) است؛ زمان دقیق ساعت برای هر رویداد ثبت نشده بود، فقط توالی آن‌ها مشخص است.

### محیط ۱ — Claude، از طریق GitHub Connector (OAuth-based App به‌نام «Claude»)
| # | عملیات | وضعیت Repository | نتیجه آزموده‌شده |
|---|---|---|---|
| 1 | Read | Private | شکست — `404 Not Found` |
| 2 | Read | Private (بعد از تغییر تنظیمات App توسط مالک پروژه) | شکست — `404 Not Found` |
| 3 | Read | **Public** (موقتاً) | **موفق** — محتوای Repository و Commit `bd24cf8d...` خوانده شد |
| 4 | Write (Push) | Public | شکست — `403 Resource not accessible by integration` |
| 5 | Read | Private (بعد از بازگشت به Private) | شکست — `404 Not Found` |
| 6 | Write (Push) | Private | شکست — `404 Not Found` (قبل از رسیدن به مرحله نوشتن، چون Read هم شکست خورد) |

**نتیجه‌گیری محدود به همین محیط:** تا این لحظه، GitHub Connector هیچ‌گاه هم‌زمان هم Read و هم Write موفق روی این Repository (در حالت Private، که وضعیت واقعی و مطلوب Repository است) نداشته است. تنها حالت موفق Read، زمانی بود که Repository موقتاً Public شده بود — که وضعیت امنیتی مطلوبی برای نگهداری دائمی نیست.

### محیط ۲ — Claude، از طریق Personal Access Token موقت (ارسال‌شده مستقیم توسط مالک پروژه در چت)
| # | عملیات | نتیجه آزموده‌شده |
|---|---|---|
| 1 | Read (`git clone`) | **موفق** |
| 2 | Write (`git push` به `main`) | **موفق** — ۲ بار (Commitهای `bd24cf8d...` و `994d4529...`) |
| 3 | Write (`git push` به شاخه `docs/phase0-correction-pass-3`) | **موفق** |
| 4 | Write (ساخت Pull Request از طریق GitHub REST API) | **موفق** — PR #1 |

**نتیجه‌گیری محدود به همین محیط:** این روش تا این لحظه همیشه کار کرده، اما یک راه‌حل موقت و دستی است (Token باید هر بار توسط مالک پروژه تهیه، ارسال، و بعد Revoke شود)، نه یک اتصال پایدار از نوع Connector/App.

### محیط ۳ — ابزار GitHub متصل به محیط Supervisor (آزمایش مستقیم در 2026-10-12)
| # | عملیات | وضعیت Repository | نتیجه آزموده‌شده |
|---|---|---|---|
| 1 | Read | Private | **موفق** — اطلاعات مخزن، فایل `README.md` و فایل‌های شاخه PR #1 خوانده شدند |
| 2 | Write | Private | **موفق** — یک شاخه آزمایشی مجزا از HEAD مربوط به PR #1 ساخته شد؛ فایل آزمایشی ایجاد و خوانده شد، سپس حذف شد و نبودن آن دوباره تأیید شد |

**محدودیت نتیجه:** این آزمایش فقط عملکرد Read/Write را در همین Session ثابت می‌کند؛ پایداری اتصال در Sessionهای بعدی هنوز آزموده نشده است. شاخه آزمایشی `test/github-write-access-20261012` از HEAD شاخه PR #1 منشعب شد و به همین دلیل تاریخچه مستندات PR را به ارث برده و شامل Commitهای آزمایشی نیز هست؛ **نباید Merge یا به‌عنوان شاخه تحویل استفاده شود**. هیچ فایل برنامه‌ای ایجاد نشد و `main` و PR #1 در این آزمایش تغییر نکردند.

**چرا این سؤال هنوز Open است:** دسترسی Read/Write در محیط Supervisor اکنون در این Session تأیید شده، اما قابلیت اتکای پایدار بین Sessionها و سیاست عملیاتی بلندمدت هنوز اثبات یا تصمیم‌گیری نشده است. نتایج محیط Supervisor را نباید به محیط Claude تعمیم داد؛ نتایج تاریخی محیط Claude نیز نباید وضعیت فعلی ابزار Supervisor را تعیین کنند.

**سؤال برای مالک پروژه:** آیا استفاده از اتصال Supervisor پس از آزمون دسترسی در ابتدای هر Session، تا زمانی که پایداری آن در چند Session تأیید شود، روش عملیاتی موقت قابل قبول است؟
**اولویت:** Medium — مانع کار مستندسازی فاز ۰ نیست (چون محیط ۲ تا این لحظه جواب داده)، ولی قبل از شروع فازهای عملیاتی (Phase 3 به بعد، با نیاز به Commitهای مکرر) باید تصمیم‌گیری شود.

---

---

## Phase 1 Design Questions (opened 2026-10-15)

Raised by `docs/phase1/TENANT_ISOLATION_DESIGN.md` §11. Each lists a recommended option; none is decided. Affected implementation must not start until answered.

## Q-014 — Response for cross-tenant object access (404 vs 403)
**Why it matters:** determines whether a probing client can learn that an ID exists in another tenant.
**Recommended option:** 404 (not found) for any object not visible within the caller's tenant, with identical bodies for "other tenant" and "nonexistent" (`AUTHORIZATION_CONTRACT.md` §4, §6).
**Alternatives:** 403 for all cross-tenant access (leaks existence).
**Impact:** API contract, TI-API-01/15 expectations, client error handling.
**Priority:** High before Phase 4 (Auth/RBAC endpoints).

## Q-015 — Platform-admin cross-tenant access mechanism
**Why it matters:** the only legitimate path for cross-tenant reads (support, billing reconciliation) and a high-risk one.
**Recommended option:** no bypass role in MVP; cross-tenant reads only through a narrow, audited, read-only application path requiring a named grant, a reason, and an audit write before the response (`TENANT_ISOLATION_DESIGN.md` §6).
**Alternatives:** a `platform_ops` role with `BYPASSRLS` plus the same audit requirement (simpler queries, larger blast radius).
**Impact:** whether `platform_ops` exists; TI-PLAT group; Phase 4 and Phase 21 planning.
**Priority:** High before Phase 4.

## Q-016 — PostgreSQL connection pooling mode
**Why it matters:** transaction-local tenant context is safe only if the pooler and the application never carry session state between requests.
**Recommended option:** transaction pooling is acceptable only with transaction-local `set_config(..., true)` and the TI-CTX-07 test passing; otherwise use direct connections for the pilot.
**Alternatives:** session pooling (simpler, more connections); no pooler in pilot (fewest moving parts, lower concurrency ceiling).
**Impact:** Infrastructure phase (Phase 3) configuration and TI-CTX tests.
**Priority:** Medium, needed before Phase 3.

## Q-017 — Background-job execution model
**Why it matters:** jobs are a common cross-tenant leak path and retries can cross contexts.
**Recommended option:** one tenant per job run (payload-bound `tenant_id`), plus explicitly marked platform jobs restricted to aggregates (`TENANT_ISOLATION_DESIGN.md` §8, §6.3).
**Alternatives:** a single global job processing all tenants with per-row checks (higher risk, harder to audit).
**Impact:** Phase 3 queue design; notification and report scheduling (Phase 17-18).
**Priority:** Medium, needed before Phase 3.

## Q-018 — Tenant-scoped file storage for the pilot
**Why it matters:** file access must be tenant-namespaced and use expiring signed URLs; the storage provider determines how this is enforced.
**Recommended option:** object storage on the pilot VPS (S3-compatible, self-hosted or local) with `tenants/{tenant_id}/` namespacing, server-side authorization before URL signing, and TTL-limited URLs.
**Alternatives:** database BLOB storage (simpler RLS coverage, poor scaling); a third-party object store (requires a provider decision and Iran-reachability check per D-011).
**Impact:** Files section of Phase 3 and Phase 17 exports.
**Priority:** Medium, needed before the first file feature.

---

## بخش Resolved / Closed

## Q-013 — مالکیت و Authorization برای ProgramTemplate و ProgramVersion سطح‌پلتفرم
**وضعیت: RESOLVED — تصمیم صریح مالک محصول در 2026-10-13؛ ثبت‌شده در `DECISION_LOG.md` D-012.**

**تصمیم مصوب: گزینه A — ساده‌سازی MVP.**
- در MVP فقط `ProgramTemplate`های متعلق به یک Tenant پشتیبانی می‌شوند؛ `tenant_id` برای هر ردیف `ProgramTemplate` برابر `NOT NULL` است.
- در MVP فقط `ProgramVersion`های متعلق به همان Tenant و وابسته به Template متعلق به همان Tenant پشتیبانی می‌شوند؛ `ProgramVersion` نیز باید tenant-scoped باشد و رابطه Template/Version با قیدهای سازگار با Tenant محافظت شود.
- ساخت، انتشار یا استفاده از Template عمومی/سطح‌پلتفرم و نسخه‌های متعلق به آن خارج از MVP است. هیچ مدل `tenant_id = NULL`، جدول مشترک با مالکیت مختلط یا دسترسی عمومی فقط‌خواندنی در MVP مجاز/تأیید نشده است.
- اگر در آینده کتابخانه مرکزی قالب‌ها لازم شود، مالکیت، انتشار، کپی‌کردن، نسخه‌بندی و Authorization آن باید با تصمیم معماری جداگانه پیش از پیاده‌سازی طراحی و ثبت شود.
- این تصمیم هیچ استثنایی برای داده واقعی دانش‌آموز ایجاد نمی‌کند: `StudentProgramEnrollment`، `Plan` و `PlanVersion` همواره به Tenant و Student مشخص محدود می‌مانند. هر عملیات روی `ProgramTemplate` یا `ProgramVersion` نیز نیازمند Authorization است.

این تصمیم هر دو بخش Q-013 را می‌بندد و فقط برای محدوده MVP است؛ پیاده‌سازی و تست امنیتی همچنان در فازهای مجاز بعدی لازم‌اند.


## Q-003 — عمق Billing در MVP
**وضعیت: RESOLVED — طبق تصمیم صریح مالک محصول درباره Q-002 / D-010 در 2026-10-12.**

**تصمیم:** Billing در MVP به `StudentCredit` و `CreditTransaction` با ledger قابل‌ممیزی، کنترل فعال‌سازی دانش‌آموز بر اساس اعتبار، و جریان دستی/آزمایشی محدود می‌شود. درگاه واقعی پرداخت در MVP نیست؛ اتصال واقعی درگاه به Phase 22 موکول شده است. این تصمیم Q-004 (انتخاب ارائه‌دهنده درگاه برای فاز آینده) را حل نمی‌کند و درباره دامنه فاکتور/سفارش فراتر از محدوده مصوب MVP تصمیم تازه‌ای نمی‌سازد. هر تغییر در این مرز به تصمیم صریح و ثبت‌شده مالک محصول نیاز دارد.

---

## Q-001 — استراتژی Tenant Isolation
**وضعیت: RESOLVED — تصمیم صریح مالک محصول، 2026-10-12؛ تصمیم فنی ثبت‌شده در `DECISION_LOG.md` D-009.**

**تصمیم:** دیتابیس و schema مشترک PostgreSQL با ستون مستقیم، indexed و `NOT NULL` به نام `tenant_id` روی هر ردیف tenant-scoped؛ authorization در Application/API layer و PostgreSQL Row-Level Security (RLS) به‌عنوان defense in depth. قیدها و روابط composite یا سازوکار معادل باید تضمین کنند ردیف فرزند نتواند به والد tenant دیگری متصل شود. دسترسی cross-tenant برای Platform Admin فقط با مجوز صریح، محدود و audit‌شده مجاز است.

**شرط‌های اجرایی غیرقابل‌حذف:** context مربوط به tenant از principal احراز هویت‌شده تعیین شود، نه از ID قابل‌اعتماد فرض‌شده در path/body؛ هر عملیات object-level مجوزسنجی شود؛ نقش runtime دیتابیس مالک جدول یا دارای `BYPASSRLS` نباشد؛ policyها و رفتار owner/privileged roles بررسی شوند؛ RLS و application filters با تست‌های منفی cross-tenant، background jobs، reports/exports، files و notifications پوشش داده شوند. فعال‌کردن RLS به‌تنهایی کافی نیست.

**رد گزینه‌های جایگزین برای MVP:** Schema-per-tenant و Database-per-tenant به‌دلیل سربار migration، عملیات، backup/restore و نگهداری، انتخاب نشدند؛ این تصمیم مانع بازبینی آینده برای نیازهای مشخص نمی‌شود، اما مهاجرت به آن‌ها بدون تصمیم معماری جدید مجاز نیست.

---

## Q-002 — محدوده دقیق MVP
**وضعیت: RESOLVED — تصمیم صریح مالک محصول، 2026-10-12؛ مرجع محدوده `PROJECT_SCOPE.md` و تصمیم `DECISION_LOG.md` D-010 است.**

**تصمیم:** MVP کنترل‌شده باید حلقه آموزشی واقعی «برنامه‌ریزی → اجرا و ثبت → تحلیل → اصلاح برنامه» را پوشش دهد. محدوده شامل Auth/RBAC پایه، مدیریت مشاور و دانش‌آموز/دروس، برنامه روزانه و هفتگی با minimum auditable versioning برای Program Template و Student Plan، فعالیت‌های اولیه Study Session/Test/Review، تکالیف و کلاس‌های موردنیاز این حلقه، تحلیل خطا و عملکرد پایه، وضعیت عقب‌افتادگی، اعلان درون‌برنامه‌ای، و StudentCredit/CreditTransaction ledger قابل‌ممیزی است. Billing در MVP به Mock/manual flow محدود می‌ماند و درگاه واقعی پرداخت وارد MVP نمی‌شود.

**خارج از MVP:** اپ native موبایل، اتصال عملیاتی Telegram/SMS، درگاه واقعی پرداخت، توصیه‌گر AI به‌عنوان منبع تصمیم یا planning black box، analytics و risk engine پیشرفته، ابزارهای پیشرفته versioning، و پنل کامل والد. هر توسعه خارج از `PROJECT_SCOPE.md` نیازمند تصمیم صریح و ثبت‌شده مالک محصول است. جزئیات دسترسی والد همچنان تابع Q-007 است و با این تصمیم بسته نشده است.

---

## Q-010 — میزبانی و Deployment
**وضعیت: RESOLVED — تصمیم صریح مالک محصول، 2026-10-12؛ تصمیم ثبت‌شده در `DECISION_LOG.md` D-011.**

**تصمیم:** هدف اولیه برای Pilot، یک VPS داخل ایران با استقرار قابل‌انتقال مبتنی بر Docker Compose است. این تصمیم یک رویکرد است، نه انتخاب Vendor یا پلن مشخص؛ انتخاب ارائه‌دهنده، قیمت و SLA بعداً با مقایسه زنده انجام می‌شود. PostgreSQL فقط در شبکه خصوصی در دسترس باشد؛ HTTPS، مدیریت امن secrets، logهای بدون اطلاعات حساس، backup رمزگذاری‌شده خارج از سرور و آزمون دوره‌ای restore الزامی‌اند. Redis فقط در صورت نیاز معماری/عملکردی واقعی اضافه یا فعال شود.

**قید:** وابستگی به ارائه‌دهنده خاص نباید وارد Domain/Core شود. Compose برای شروع و Pilot مناسب است، اما به‌خودی‌خود تضمین High Availability یا آمادگی Production نیست. محدودیت‌های دسترسی سرویس‌های بیرونی باید برای هر Adapter پیش از فعال‌سازی جداگانه ارزیابی شوند.

---



## Q-012 — تأیید MVP Versioning Policy برای Program Template و Student Plan
**وضعیت: RESOLVED — تصمیم صریح مالک محصول در گفتگو، 2026-10-10.**

**تصمیم ثبت‌شده:** گزینه B تأیید شد. حداقل Versioning قابل‌ممیزی برای Program Template و Student Plan جزو MVP است؛ قابلیت‌های پیشرفته مدیریت نسخه (از جمله مقایسه بصری، رابط Rollback، Branching و گزارش‌های Diff/تحلیل اثر) به مراحل بعد موکول می‌شوند. حفظ تاریخچه، شناسه پایدار و نسخه صریح، انتساب تغییرات، و جلوگیری از تغییر بی‌صدای برنامه دانش‌آموز هنگام ویرایش Template همچنان الزامی است.

این تصمیم فقط Q-012 را می‌بندد. Q-001، Q-002 و Q-010 در 2026-10-12 جداگانه با تصمیم صریح مالک محصول بسته شدند؛ Q-011 و سایر پرسش‌های فهرست‌شده در بخش Open همچنان باز می‌مانند. D-008 در `DECISION_LOG.md` وضعیت Accepted دارد؛ جزئیات فنی نهایی Schema همچنان به مراحل طراحی مربوطه تعلق دارد.

_(Q-011 همچنان Open است: دسترسی Read/Write ابزار Supervisor در Session مورخ 2026-10-12 موفق بود، اما پایداری بین Sessionها هنوز تأیید نشده و سیاست عملیاتی بلندمدت نیازمند تعیین تکلیف است.)_
