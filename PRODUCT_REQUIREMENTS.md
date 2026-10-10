# PRODUCT_REQUIREMENTS.md
## Persian Educational Counseling & Study OS

Status: DRAFT — Phase 0 — Pending Approval

---

## 1. چیستی محصول

این محصول یک **Todo/Calendar/Timer** نیست. یک **Educational Counseling & Student Study Operating System** چندمستأجری (Multi-Tenant SaaS) است که دو ذی‌نفع اصلی را به هم متصل می‌کند:

- **مشاور تحصیلی (Counselor)**: استراتژی می‌سازد، برنامه شخصی‌سازی‌شده تولید می‌کند، عملکرد را تحلیل می‌کند، و بر اساس مدل کسب‌وکار خودش به دانش‌آموزان سرویس می‌دهد.
- **دانش‌آموز (Student)**: برنامه را اجرا می‌کند، داده (مطالعه/آزمون/خطا) ثبت می‌کند، و پیشرفت می‌کند.

حلقه ارزش محصول:

```
Counselor Strategy → Student Baseline → Personalized Plan → Execute →
Record → Analyze → Identify Weakness → Review/Correct → Progress →
Counselor Feedback → Plan Adjustment → Repeat
```

معیار موفقیت محصول: **پیشرفت واقعی و قابل اندازه‌گیری دانش‌آموز**، نه صرفاً ساعت مطالعه یا تعداد تست.

---

## 2. ذی‌نفعان و نقش‌ها (Roles)

| Role | توصیف کوتاه |
|---|---|
| Platform Admin | مدیریت کل پلتفرم، مشاوران، Billing، تنظیمات سیستم |
| Counselor | مالک Tenant؛ مدیریت دانش‌آموزان، برنامه، تحلیل، ارتباطات |
| Student | اجرای برنامه، ثبت عملکرد، مشاهده پیشرفت |
| Parent | مشاهده سطح‌بالای پیشرفت فرزند (با مجوز) |
| Teacher | (فاز بعد) مرتبط با کلاس‌ها/تکالیف |

نقش‌های بیشتر می‌توانند بعداً اضافه شوند؛ مدل RBAC باید از ابتدا قابل‌توسعه طراحی شود (نه hardcoded enum بسته).

---

## 3. مدل کسب‌وکار (Business Model)

```
Platform → Counselor → Student
```

مشاور از پلتفرم خرید می‌کند (Subscription / Student Credit / Package / Trial)، سپس برای هر دانش‌آموز که اضافه می‌کند یک واحد ظرفیت (Credit) مصرف می‌شود.

مدل‌های Billing که معماری باید از روز اول اجازه‌ی اضافه‌شدن‌شان را بدهد (نه لزوماً همه در MVP پیاده شوند):

- Subscription (ماهانه/سالانه برای مشاور)
- Student Credit (اعتبار قابل مصرف به‌ازای هر دانش‌آموز)
- Monthly / Annual Student
- Package
- Counselor Plan (Tier مشاور: محدودیت تعداد دانش‌آموز، امکانات)
- Trial
- Promotional Credit

**اصل حیاتی:** `Counselor Account` ≠ `Counselor Subscription` ≠ `Student Credit`. این سه مفهوم باید Entityهای جدا باشند.

---

## 4. اصل Multi-Tenant (غیرقابل مذاکره)

هر Counselor یک Tenant مستقل است. هیچ داده، query، گزارش، فایل، نوتیفیکیشن یا background job نباید بین Tenantها نشت کند. این اصل باید در تمام لایه‌ها اعمال شود: DB، API، Authorization، Services، Reports، Files، Notifications، Jobs.

جزئیات استراتژی Multi-Tenancy در ARCHITECTURE.md (فاز ۱) مشخص می‌شود؛ گزینه‌های ممکن (Row-Level با tenant_id + RLS، Schema-per-tenant، DB-per-tenant) در OPEN_QUESTIONS.md ثبت شده‌اند.

---

## 5. دامنه‌های محصول (Functional Domains)

1. Identity & Access (Auth, RBAC, Tenant)
2. Counselor–Student Relationship
3. Student Profile & Subjects / Curriculum
4. Programs & Program Templates (Versioned)
5. Planning Engine (Daily/Weekly/Monthly/Exam/Review/Recovery)
6. Activity Execution (Study, Test, Exam, Class, Assignment, Review)
7. Error Analysis
8. Review Engine (Spaced repetition: 1-3-7 و configurable)
9. Progress & Risk Engine (Explainable)
10. Dashboards (Student / Counselor / Parent / Admin)
11. Analytics & Reports (PDF/Excel/CSV, RTL, A4)
12. Notification Engine (In-App / Telegram / SMS — Adapter-based)
13. Billing (Product, Plan, Subscription, Order, Payment, Invoice, Credit Ledger)
14. Payment Gateway (Adapter-based, Mock for dev)
15. Market Segments
16. Admin Console
17. AI Assistance (فاز دیرهنگام — explain/recommend only, never source of truth)

---

## 6. اصول معماری کلیدی

- **Core Domain هرگز به Telegram/SMS/Payment/AI وابسته نیست** — از طریق Interface/Adapter.
- **Explainability اجباری** برای: ریسک دانش‌آموز، اولویت‌بندی برنامه، تولید Review، flagging.
- **Program Template و Student Plan باید حداقل Versioning قابل‌ممیزی داشته باشند، همین از MVP** (طبق `DECISION_LOG.md` D-008 — Accepted، تأیید صریح مالک محصول در تاریخ ۲۰۲۶-۱۰-۱۰؛ `OPEN_QUESTIONS.md` Q-012 Resolved)؛ تغییر Template روی Planهای دانش‌آموزان موجود اثر خودکار و بی‌صدا ندارد. ویژگی‌های پیشرفته مدیریت نسخه (مقایسه بصری، Rollback UI، Branching) می‌توانند بعد از MVP بیایند، ولی خودِ شناسه نسخه + تاریخچه + Attribution از MVP الزامی است. توجه: «Plan» اینجا به معنای Plan مطالعاتی دانش‌آموز است، نه Plan تجاری Billing — این دو مفهوم جدا نگه داشته می‌شوند (`DECISION_LOG.md` D-006، که خودش همچنان Proposed و جداگانه از D-008 است).
- **Credit Ledger باید Append-only/Immutable باشد** (نه overwrite موجودی).
- **Business Logic هرگز داخل Route/Controller نیست** (لایه‌بندی API → Application → Domain → Infrastructure).
- **Integration failure (Telegram/SMS/Payment) هرگز نباید Core را متوقف کند.**

---

## 7. خارج از دامنه (فعلاً)

- Public Marketplace برای فروش مستقیم برنامه توسط مشاوران به کاربران ناشناس (معماری نباید مانع آن شود، ولی ساخته نمی‌شود مگر تأیید صریح).
- AI به‌عنوان منبع تصمیم برای تاریخ، محاسبات، مجوزها، Billing، Credits، یکپارچگی DB، Tenant Isolation.

---

## 8. معیار پذیرش نهایی (Final Acceptance)

به بخش `80. Final Acceptance` در Master Prompt رجوع شود؛ همان چک‌لیست بدون تغییر، معیار Production Readiness است.
