# ROADMAP.md

Status: DRAFT — Phase 0 — Pending Approval

قانون: هر فاز طبق `Mandatory Development Workflow` (بخش ۷۶ Master Prompt) اجرا می‌شود و بعد از اتمام، **خودکار به فاز بعد نمی‌رویم** — منتظر تأیید می‌مانیم.

| # | فاز | خروجی کلیدی |
|---|---|---|
| 0 | Product & Business Model | این مجموعه اسناد (در حال انجام) |
| 1 | Architecture & Multi-Tenancy (design only) | اسناد طراحی اجرای shared PostgreSQL + tenant_id + RLS، قراردادهای authorization و طراحی تست‌های tenant isolation؛ بدون کد برنامه، migration یا پیاده‌سازی infrastructure. هر تغییر این مرز نیازمند تصمیم صریح Product Owner پیش از شروع است. |
| 2 | Database & Domain Model | ERD کامل، مدل‌های Core (Counselor, Student, Program, Activity...) |
| 3 | Infrastructure | FastAPI skeleton، Alembic، Docker Compose برای Pilot روی VPS داخل ایران، CI اولیه؛ Redis فقط در صورت توجیه |
| 4 | Authentication & RBAC | Register/Login/Refresh/Reset، Policy engine |
| 5 | Counselor/Student Relationship | CounselorStudent entity + lifecycle |
| 6 | Student Profile & Subjects | Profile fields، Default subjects قابل ویرایش |
| 7 | Curriculum | Subject→Grade→Book→Chapter→Topic→SubTopic |
| 8 | Activities & Study Sessions | Activity types، Study Session CRUD |
| 9 | Tests & Error Analysis | Test validation، Error taxonomy، Pattern detection |
| 10 | Exams, Quizzes & Classes | Exam multi-subject، Class scheduling |
| 11 | Review Engine | 1-3-7 rule، duplicate prevention |
| 12 | Planning Engine | Conflict detection، workload realism |
| 13 | Student Dashboard | Today/Overdue/Progress |
| 14 | Counselor Dashboard | شاخص‌های جمعی، فیلتر/سورت |
| 15 | Program Templates & Personalization | Advanced version-management tooling (visual diff، rollback UI، گسترده‌تر از حداقلِ MVP)، Baseline→Personalized Plan — *نه* معرفی اصل Versioning، که طبق D-008 جزو حداقل MVP است؛ نگاه کنید به یادداشت زیر جدول |
| 16 | Progress & Analytics | فرمول مستندشده Progress، نمودارها |
| 17 | Reports & Exports | PDF/Excel/CSV RTL/A4 |
| 18 | Notification Engine | Core + InAppAdapter، صف تحویل |
| 19 | Telegram | Linking، دستورات، Adapter |
| 20 | SMS | Adapter، Retry/Backoff |
| 21 | Billing / Subscription / Credits | توسعه تکمیلی Billing (Subscription/Plan/Order/Invoice و قابلیت‌های فراتر از ledger حداقلی MVP)؛ ledger حداقلی StudentCredit/CreditTransaction باید در محدوده MVP و همراه با جریان فعال‌سازی دانش‌آموز پیاده‌سازی شود، نه اینکه تا Phase 21 به تعویق بیفتد |
| 22 | Payment Gateway | RealPaymentProvider، Webhook idempotency |
| 23 | Parent Panel | دسترسی سطح‌بالا، Privacy rules |
| 24 | AI Assistance | Explain/Summarize/Recommend (غیر منبع حقیقت) |
| 25 | PWA | Offline-ready shell |
| 26 | Security Hardening | Pen-test checklist، Audit log review |
| 27 | Performance | Query profiling، N+1، caching |
| 28 | Production Readiness | چک‌لیست بخش ۷۵ |

## یادداشت — جایگاه Versioning در این Roadmap (پیوست به D-008 — Accepted)
کلمه «Versioning» فقط زیر Phase 15 در جدول بالا ظاهر می‌شد، که قبلاً می‌توانست این‌طور خوانده شود که Program Template/Plan Versioning اصلاً تا Phase 15 وجود ندارد — این خوانش با `ARCHITECTURE.md`/`DATABASE.md` (که Versioning را یک اصل پایه توصیف می‌کنند) و با Policy جدید `DECISION_LOG.md` D-008 (که حداقل Versioning را جزو MVP می‌داند) همخوان نیست. برای رفع این تناقض، بدون تغییر شماره یا ترتیب فازها:
- **حداقل Versioning قابل‌ممیزی** (شناسه پایدار + شماره نسخه + عدم بازنویسی بی‌صدا + تاریخچه + Attribution) بخشی از **مدل داده پایه** است که در Phase 2 (Database & Domain Model) طراحی می‌شود و هرجا Program Template یا Plan در فازهای زودتر از ۱۵ ساخته/استفاده شود (مثلاً Phase 12 Planning Engine به یک ساختار Plan نیاز دارد)، همان حداقل Versioning را دارد.
- **Phase 15** مشخصاً به معنای معرفی اصل Versioning نیست، بلکه شامل منطق Personalization (Baseline→Personalized Plan) و ابزارهای **پیشرفته** مدیریت نسخه (مقایسه بصری، Rollback UI، Branching، گزارش Diff) است که در بالای همان حداقل MVP ساخته می‌شوند.
- این یادداشت یک توضیح/هماهنگ‌سازی مستندی است، نه تصمیم تجاری یا معماری جدید؛ تصمیم اصلی در `DECISION_LOG.md` D-008 ثبت شده و توسط مالک محصول در تاریخ ۲۰۲۶-۱۰-۱۰ تأیید شده است (Accepted؛ `OPEN_QUESTIONS.md` Q-012 Resolved). این تأیید فقط خودِ Policy را تعیین‌تکلیف می‌کند؛ جزئیات دقیق پیاده‌سازی Schema همچنان به فاز طراحی مربوطه (Phase 2) تعلق دارد.

## یادداشت — جایگاه Billing و Credit Ledger در Roadmap (هماهنگ با D-010)

- **MVP:** پیاده‌سازی `StudentCredit` و `CreditTransaction` به‌صورت ledger قابل‌ممیزی و append-only، قواعد مصرف/بازگشت اعتبار، و جلوگیری از فعال‌سازی دانش‌آموز در صورت اعتبار ناکافی. این بخش جزو MVP در `PROJECT_SCOPE.md` است و نباید تا Phase 21 عقب بیفتد.
- **Phase 21:** توسعه تکمیلی Billing شامل مدل‌های تجاری و گردش‌کارهای Subscription/Plan/Order/Invoice و قابلیت‌های پیشرفته‌تر که در محدوده MVP تعریف نشده‌اند. پیش از اجرای آن فاز باید با مدل‌های پایه و تصمیم‌های ثبت‌شده سازگار بماند.
- **Phase 22:** اتصال درگاه واقعی؛ خارج از MVP. `Q-004` درباره انتخاب ارائه‌دهنده واقعی برای زمان مناسب همچنان باز است.
- این یادداشت مرزهای موجود را هماهنگ می‌کند و دامنه جدیدی را تصویب نمی‌کند. هر گسترش MVP نیازمند تصمیم صریح مالک محصول است.

## وضعیت فعلی
**Phase 0 — IN PROGRESS — Supervisor Gate: CONDITIONAL PASS (2026-10-12); Product Owner closure pending.**

آخرین Commit تأییدشده روی `main` که در این سند به‌عنوان snapshot تاریخی ثبت شده، `994d4529c20c4a330bd843bd3ca1a7c9ed1f75ec` است. برای وضعیت زنده `main` و HEAD شاخه اصلاحات، مستقیماً به GitHub مراجعه کنید؛ این فایل مرجع HEAD جاری نیست.

بازبینی رسمی Supervisor در `SUPERVISOR_REVIEW.md` ثبت شده و وضعیت آن `CONDITIONAL PASS` است، نه `APPROVED`. اصلاحات این دور روی شاخه `docs/phase0-correction-pass-3` و در PR #1 قرار دارند؛ PR هنوز Merge نشده است. جزئیات اصلاحات در `CHANGELOG.md` آمده است.

**تصمیم‌های Q-001، Q-002 و Q-010 در 2026-10-12 ثبت و در OPEN_QUESTIONS.md به Resolved منتقل شده‌اند.** این تصمیم‌ها به‌تنهایی Phase 0 را نمی‌بندند و مجوز Phase 1 نیستند. **Phase 1 شروع نشده و همچنان نیازمند تأیید صریح Product Owner برای بستن Phase 0، بررسی نهایی PR #1 و مجوز جداگانه شروع فاز است.**
