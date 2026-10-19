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

## Phase 1 Design Questions (revision 2, 2026-10-15)

Status legend: **OPEN** = no decision. **RECOMMENDED** = recommendation written, not accepted. Nothing in this block is decided by the assistant. "Blocks Phase 1 approval" means the owner or reviewer cannot approve Phase 1 until the item is resolved or explicitly accepted.

## Q-014 — Response for cross-tenant object access (exact status)
**Deferral condition (Revision 6):** may stay OPEN until Phase 4, provided the Phase 4 entry records this dependency and the contracts remain status-neutral (identical not-found responses).
**Status:** OPEN (recommended: 404 with body identical to a nonexistent object).
**Decision needed from owner:** the exact status code for cross-tenant and nonexistent objects, and whether 403 is ever used for objects the caller can see but may not act on.
**Why it matters:** existence of records in other tenants must not be revealed.
**Dependency:** the test contracts (TI-API-01, TI-API-15, TI-REPO-02, TI-RPT-02, TI-FILE-01, TI-VER-01/05) are written so they pass under any choice, as long as the cross-tenant response equals the nonexistent-object response.
**Must be resolved before:** Phase 4 endpoint implementation.
**Blocks Phase 1 approval:** No.

_Q-015 is resolved; see the Resolved section below and DECISION_LOG D-013._

## Q-016 — PostgreSQL connection pooling mode and transaction-local context
**Status:** OPEN (recommended: transaction pooling only if TI-CTX-11, TI-CTX-12 and TI-PLAT-05 pass in the chosen configuration; otherwise direct connections for the pilot).
**Decision needed from owner:** pooler mode for the pilot. Owner may also choose to defer pooling altogether.
**Why it matters:** a pooled connection carrying one tenant's context into another tenant's request is a direct cross-tenant leak.
**Dependency:** TI-CTX-11, TI-CTX-12, TI-PLAT-05 (ENV:pooler).
**Must be resolved before:** Phase 3 infrastructure configuration.
**Blocks Phase 1 approval:** No.

## Q-017 — Background-job execution model
**Status:** OPEN (recommended: one tenant per job run with payload-bound tenant_id; platform jobs restricted to aggregates; failure leaves no context set).
**Decision needed from owner:** per-tenant job model versus one global job with per-row checks (not recommended).
**Why it matters:** jobs and retries are a common cross-tenant path.
**Dependency:** TI-JOB-01 to TI-JOB-05 (TI-JOB-05 is ENV:worker).
**Must be resolved before:** Phase 3 queue design; Phase 17–18 scheduling.
**Blocks Phase 1 approval:** No.

## Q-018 — Tenant-scoped file storage for the pilot
**Status:** OPEN (recommended: S3-compatible object storage on the pilot host with `tenants/{tenant_id}/` namespacing, server-side authorization before signing, short TTL; no public buckets).
**Decision needed from owner:** storage provider and hosting location (must be checked against D-011 for reachability), and maximum link lifetime.
**Why it matters:** files are a direct cross-tenant read path if keys or links are guessable.
**Dependency:** TI-FILE-01 to TI-FILE-07.
**Must be resolved before:** the first file feature.
**Blocks Phase 1 approval:** No.

## Q-019 — Tenant-context boundary against threat T4 (decomposed)
**Owner direction (decided, D-014, 2026-10-15):** strengthen the boundary before any pilot containing real student data. Pilot rule: no real student data before independent security review, required security tests passing, blocking findings fixed, and written owner approval of the Pilot gate.
**Status:** OPEN for the MECHANISM. Direction is decided; mechanism is not.
**Decomposition (added Revision 4, design §1.4):** T4a (SQL injection on a tenant connection), T4b (application process compromise), T4c (database credential theft). Option C addresses T4a for one tenant connection and partly T4c. No option addresses T4b in the database; T4b requires process isolation (Phase 3/26). Claims must be made per sub-threat.
**Technical candidates for independent review (not decisions):** Option C (per-tenant database principals; proposed candidate for pilot scale, design §2.4 with explicit limits); Option D (signed context token through a SECURITY DEFINER function, design §2.3.1). Option A alone is not a boundary against T4a.
**Required to resolve the mechanism:** independent security review of the selected option; evidence for the matching sub-threat claims (TI-ADV-01, TI-ADV-02; TI-CONN-01..03 for C; TI-CTX-15..18 for D); owner selection recorded in DECISION_LOG.
**Technical evaluation (Revision 6):** `docs/phase1/Q019_MECHANISM_EVALUATION.md` compares A, C and D against attacker models AM1 to AM5 with forging paths, residual risks, cost, testability and evidence required. It recommends Option C as a technical candidate for pilot scale (Option D as alternative; Option A not a boundary). This is a recommendation for review, not a decision.
**Revision 8 (independent review H-01, H-02, M-01):**
- Credential classes K-L-1, K-L-N, K-T, K-S, K-O defined and analysed per option (Q019 §4.4). Option D's no-token case assessed explicitly (§4.4.3).
- Option C capacity: ESTIMATE — NOT MEASURED (Q019 §6.2). Direct connections not feasible under the stated assumptions; per-user pooler feasible in count only under the assumptions. Measurement is a pilot criterion.
- Option D: NOT SELECTION-READY (Q019 §6.3, seven open points).
- **Product Owner decisions needed for Q-019:** (1) choose C, or D after readiness, or residual acceptance; (2) if D: signature algorithm (HMAC or asymmetric) and whether a jti store is acceptable; (3) if C: confirm the pilot tenant count assumption (A1), the pool strategy, the tenant-role retention rule, and that grouping tenants into shared roles is not an allowed fallback without a new decision; (4) capacity rule (§6.2) acceptance.
- Design-selection criteria (D-015) are met for C at design level and not met for D.
**Owner decision still required** after independent review; to be recorded in DECISION_LOG.md.
**Must be resolved before:** any Pilot with real student data; Phase 26.
**Blocks Phase 1 approval:** Yes (reviewer-stated NOT READY depends on it).

## Q-007 — Gate impact (Phase 1 review)
**Status:** Product question OPEN (default parent access level). Gate impact: **CONFIRMED by the independent reviewer** (PR #3 review): TI-API-09 blocks closure of the phase that implements parent access (Phase 23), not Phase 1 architectural approval, provided parent access is not implemented in Phase 1 and TI-API-09 stays BLOCKED.
**Owner acceptance of the gate wording:** pending.

## بخش Resolved / Closed

## C-01 — Gate deadlock between design selection and later test execution (RESOLVED 2026-10-17)
**Decision (owner):** D-015. Design-selection criteria and pilot-validation criteria are separate. Test execution belonging to later phases is not a precondition for design decisions or for starting those phases.
**Effect:** Q-019 can now be decided on design criteria. Pilot real-data rule (D-014) is unchanged.
**Note:** this resolves the process deadlock only. It does not select a Q-019 mechanism and does not approve Phase 1.

## Q-015 — Platform-admin cross-tenant access mechanism (RESOLVED 2026-10-15)
**Decision (owner):** Option A — read-only, audited access through explicit Application paths, no `BYPASSRLS` role, no platform write operations in MVP.
**Record:** DECISION_LOG D-013.
**Effect on documents:** `TENANT_ISOLATION_DESIGN.md` §8 and §5.1; `TENANT_ISOLATION_TEST_CONTRACTS.md` TI-PLAT-06, 08, 09, 10 (TI-PLAT-06 no longer blocked); `TENANT_PATH_INVENTORY.md` P-25, P-26.
**Note:** this resolves the product decision only. Implementation, and the test runs that prove it, are not done.



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
