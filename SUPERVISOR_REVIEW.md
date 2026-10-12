# SUPERVISOR_REVIEW.md

این فایل برای ثبت **بازبینی خارجی (External Supervisor Review)** پروژه رزرو شده است، طبق بخش ۵۵ Master Prompt.

این سند محل ثبت بازبینی مستقل Supervisor است. گزارش رسمی زیر توسط Supervisor در 2026-10-12 پس از بررسی مستقیم فایل‌های شاخه PR #1 ثبت شده است؛ ثبت این Review به‌خودی‌خود به‌معنای تأیید نهایی Product Owner یا مجوز شروع Phase 1 نیست.

وضعیت‌های ممکن (طبق Master Prompt):
```
NOT READY
CONDITIONAL PASS
APPROVED
```

`CONDITIONAL PASS` هرگز به‌عنوان تأیید نهایی در نظر گرفته نمی‌شود.

---

## الگوی ثبت هر Review

```text
Phase:
<شماره و نام فاز>

Status:
NOT READY / CONDITIONAL PASS / APPROVED

Critical:
<موارد بحرانی یا None>

High:
<موارد با اولویت بالا>

Medium:
<موارد با اولویت متوسط>

Required Fixes:
- [ ] ...

Tests Required:
- [ ] ...

Final Status:
NOT APPROVED / APPROVED
```

---

## تاریخچه Reviewها

گزارش رسمی مورخ 2026-10-12 در ادامه ثبت شده است. وضعیت فاز پس از این Review برابر `CONDITIONAL PASS` است؛ تأیید Product Owner، Merge شدن PR #1 و پاسخ به سؤالات لازم برای شروع فازهای بعدی همچنان مراحل جداگانه‌اند.

## یادداشت واقعیت‌نگار — فعالیت بازبینی تا این لحظه (نه یک Review رسمی، نه یک Verdict)

**این بخش یک Review رسمی با Status نیست؛ صرفاً یک ثبت واقعیت‌نگار از فعالیت‌هایی است که تا این لحظه رخ داده، تا شفافیت حفظ شود.**

روی شاخه `docs/phase0-correction-pass-3` (PR #1)، چندین دور بازخورد اصلاحی دریافت و پردازش شده است — این بازخوردها طبق چارچوب این پروژه (`ChatGPT به‌عنوان Supervisor مستقل`) از طریق مالک پروژه منتقل شده‌اند، نه این‌که Claude خودش را بازبینی کرده باشد. موضوعاتی که در این دورها مطرح و در Commitهای متوالی روی همان شاخه اصلاح شدند، شامل این موارد بوده (فهرست کامل و دقیق در `CHANGELOG.md`):
- دقت ارجاعات SHA/تاریخچه Commit در `PROJECT_STATE.md` (چندین دور، چون این فایل به‌طور ذاتی مستعد Stale شدن روی یک شاخه طولانی‌مدت است)
- رفع یک تناقض واقعی درباره Versioning بین چند سند (منجر به D-008)
- هماهنگ‌سازی اسناد بعد از تصمیم مالک محصول روی Q-012
- تفکیک دقیق‌تر مالکیت Tenant/Platform برای Program Template (منجر به Q-013)

**این فهرست به‌معنای تأیید یا رد Phase 0 نیست.** هیچ Status رسمی (`NOT READY`/`CONDITIONAL PASS`/`APPROVED`) توسط این فایل یا توسط Claude به Phase 0 نسبت داده نشده و نمی‌شود — این تصمیم منحصراً در اختیار Supervisor مستقل (و برای تأیید نهایی، مالک محصول) است. Claude در این فرآیند نقش عامل پیاده‌سازی و مستندساز را داشته، نه بازبین مستقل.


---

# SUPERVISOR REVIEW — 2026-10-12

## Phase
**Phase 0 — Product & Business Model Foundation**

## Scope Reviewed
بررسی مستندات Phase 0 در شاخه `docs/phase0-correction-pass-3` و PR #1، با تمرکز مجدد بر `ARCHITECTURE.md`، `DATABASE.md`، `PROJECT_STATE.md`، `OPEN_QUESTIONS.md`، `DECISION_LOG.md`، `CHANGELOG.md`، `ROADMAP.md` و این فایل؛ همچنین تطبیق وضعیت PR و شاخه با GitHub. فاز حاضر مستندات‌محور است و هنوز کد اجرایی ندارد.

## Summary
سه ایراد متوسطِ باقی‌مانده از بازبینی قبلی اصلاح شدند: (1) قرارداد مستقیم/غیرمستقیم `tenant_id` در مدل Planning، (2) اطلاعات تاریخ‌گذشته و ادعای نادقیق در `PROJECT_STATE.md`، و (3) گزارش ناقص از وضعیت واقعی دسترسی Supervisor به GitHub. اصلاحات روی شاخه PR #1 ثبت شده‌اند؛ `main` ادیت نشده و PR ادغام نشده است.

**Gate Status: CONDITIONAL PASS.** مستندات اصلاح‌شده برای ادامه فرآیند بررسی/بستن Phase 0 قابل قبول‌اند، اما این وضعیت نه `APPROVED` است و نه مجوز شروع Phase 1. تصمیم‌های محصولی لازم باید توسط Product Owner پاسخ داده شوند.

## Passed
- مرز Phase 0 مستنداتی حفظ شده؛ هیچ کد برنامه، migration، endpoint یا feature جدیدی اضافه نشده است.
- الزام جداسازی Tenant و لزوم Authorization برای تمام عملیات داده‌های دانش‌آموز و نسخه‌ها در اسناد باقی مانده است.
- D-008 / Q-012 همچنان به‌درستی Accepted/Resolved است؛ Q-001، Q-002، Q-010 و Q-013 به‌جای Product Owner بسته نشده‌اند.
- `PROJECT_STATE.md` میان وضعیت `main`، HEAD شاخه PR، محتوای بررسی‌شده و رأی Supervisor تمایز می‌گذارد و دیگر SHA جاری را به‌صورت ادعای ثابت در متن جاری جا نمی‌زند.
- نتیجه آزمایش Read/Write ابزار GitHub در محیط Supervisor دقیقاً ثبت شده و به محیط Claude یا پایداری بین Sessionها تعمیم داده نشده است.

## Findings

### CRITICAL
- موردی در اسناد Phase 0 بررسی‌شده تأیید نشد. این نتیجه صرفاً درباره اسناد است و امنیت runtime را اثبات نمی‌کند، چون کد اجرایی هنوز وجود ندارد.

### HIGH
- موردی در اسناد Phase 0 بررسی‌شده تأیید نشد. کنترل واقعی tenant isolation، IDOR و مجوزهای API تا زمان پیاده‌سازی و تست قابل ارزیابی اجرایی نیست.

### MEDIUM
- **رفع شد:** تناقض قرارداد `tenant_id` برای `PlanVersion` و `PlanItem` بین `ARCHITECTURE.md` و `DATABASE.md`. اکنون فرض مفهومیِ کاری برای هر سه جدول، ستون مستقیم `tenant_id` است؛ Q-001 همچنان باز است و تصمیم نهایی isolation به آن موکول شده است.
- **رفع شد:** تاریخ `PROJECT_STATE.md` و ادعای منسوخ درباره آخرین محتوای بررسی‌شده به‌روزرسانی شد.
- **رفع شد:** وضعیت دسترسی GitHub در `OPEN_QUESTIONS.md` و `PROJECT_STATE.md` با نتیجه واقعی آزمایش Supervisor در 2026-10-12 هماهنگ شد؛ دوام اتصال بین Sessionها هنوز اثبات نشده است.

### LOW
- Q-013 درباره مالکیت و مجوز `ProgramTemplate`/`ProgramVersion` سطح‌پلتفرم باز می‌ماند؛ طبق اولویت ثبت‌شده، تا زمانی که این قابلیت وارد محدوده اجرا نشود مانع Phase 0 نیست.

## Architecture
لایه‌بندی و اصل deterministic/explainable planning در سطح مستندات حفظ شده‌اند. انتخاب نهایی استراتژی جداسازی Tenant هنوز باز است و فرض `tenant_id` مستقیم نباید به‌عنوان تصمیم قطعی Q-001 تفسیر شود.

## Database
مدل مفهومی Planning اکنون با قرارداد عمومی `tenant_id` هماهنگ است. در طراحی Schema باید سازگاری tenant فرزند با والد با constraint یا سازوکار معادل enforce شود. هیچ migration یا schema اجرایی وجود ندارد؛ بنابراین کلیدهای خارجی، indexها، RLS policyها، تراکنش‌ها و concurrency هنوز قابل آزمون اجرایی نیستند.

## API
در این فاز endpoint اجرایی وجود ندارد. قبل از تأیید پیاده‌سازی، باید object-level authorization، فیلتر tenant در همه queryها، pagination/validation/error handling و تست‌های منفی cross-tenant در طراحی و تست‌ها پوشش داده شوند.

## Security
الزامات عدم دسترسی Counselor به داده Tenant دیگر پابرجاست. هیچ ادعای امنیت runtime صادر نمی‌شود. در فازهای اجرایی باید RBAC، IDOR، background jobs، exports، file access، notifications، audit logs و RLS (در صورت انتخاب Q-001) جداگانه تست شوند.

## Testing
Phase 0 کد اجرایی برای unit/integration/API/E2E ندارد؛ نبودن این تست‌ها در این مرحله نقص اجرایی محسوب نمی‌شود. هیچ ادعایی مبنی بر پاس‌شدن CI یا تست خودکار مطرح نیست. `TEST_PLAN.md` باید در مراحل پیاده‌سازی به تست‌های tenant-isolation و regression قابل اجرا تبدیل شود.

## Documentation
سه ناسازگاری شناسایی‌شده در این دور اصلاح شدند و در `CHANGELOG.md` ثبت شدند. تاریخچه قبلی حفظ شده است؛ یادداشت‌های تاریخیِ قدیمی درباره آزمایش‌های Claude به‌عنوان تاریخچه باقی مانده‌اند و با نتایج فعلی Supervisor خلط نشده‌اند.

## Technical Debt
- هیچ کد اجرایی وجود ندارد؛ بدهی runtime هنوز قابل ارزیابی نیست.
- Q-011: موفقیت Read/Write در Session جاری اثبات شده، اما تکرارپذیری در Sessionهای آینده هنوز نیازمند آزمون است.
- Q-001/Q-002/Q-010 پیش‌نیازهای تصمیم‌گیری قبل از Phase 1 هستند.

## Required Changes
1. **انجام شد:** همسان‌سازی قرارداد tenant در `DATABASE.md` با فرض کاری ثبت‌شده در `ARCHITECTURE.md`، بدون بستن Q-001.
2. **انجام شد:** اصلاح تاریخ و ادعاهای stale در `PROJECT_STATE.md`.
3. **انجام شد:** ثبت آزمون واقعی GitHub Supervisor در `OPEN_QUESTIONS.md` و `PROJECT_STATE.md`.
4. Product Owner باید پیش از شروع Phase 1 به Q-001 (استراتژی Tenant Isolation)، Q-002 (مرز MVP) و Q-010 (میزبانی/Deployment) پاسخ دهد یا تصمیمات را صریحاً اصلاح کند.
5. Product Owner باید جداگانه درباره بستن Phase 0 و Merge شدن PR #1 تصمیم بگیرد. این Review خودکار Merge انجام نمی‌دهد.

## Recommendation
**اجازه شروع Phase 1 هنوز صادر نمی‌شود.** ابتدا Product Owner باید تصمیم‌های Q-001، Q-002 و Q-010 را ثبت کند و صریحاً بستن Phase 0 را تأیید کند؛ سپس PR #1 و آخرین diff باید قبل از Merge دوباره بررسی شوند.

## Gate Status
**CONDITIONAL PASS**
