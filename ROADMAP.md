# ROADMAP.md

Status (updated 2026-10-23): Phase 0 closed by Product Owner on 2026-10-14; PR #1 merged. Phase 1: design and documentation submitted for independent review (PR #3, branch docs/phase1-tenant-isolation-design); corrective changes made after review of commit 4715e3d are pending independent re-review of the current live PR head. Q-015 resolved (D-013). Q-021 resolved by D-019 (Product Owner selected option B: stronger architecture required; no final topology selected). Q-022 resolved by Product Owner D-020 (Alt-5 hybrid isolation cells; proposed max two tenants/cell for initial pilot, subject to measured cost/capacity; Alt-4 is the reference). Active design/auth/test contracts have been rewritten; independent re-review remains pending. Each tenant must have its own database/credential within its cell; proposed cell size is max two tenants, subject to capacity/cost review. See `docs/phase1/TENANT_ISOLATION_DESIGN.md`. Prior Option C direction is not approved as sufficient. Phase 1 NOT approved / NOT READY; Phase 2 NOT authorized; real-data pilot prohibited (D-014).

قانون: هر فاز طبق `Mandatory Development Workflow` (بخش ۷۶ Master Prompt) اجرا می‌شود و بعد از اتمام، **خودکار به فاز بعد نمی‌رویم** — منتظر تأیید می‌مانیم.

| # | فاز | خروجی کلیدی |
|---|---|---|
| 0 | Product & Business Model | مجموعه اسناد پایه — تکمیل و تأیید شده؛ Phase 0 در 2026-10-14 بسته شد |
| 1 | Architecture & Multi-Tenancy (design only) | انتخاب معماری جداسازی تنانت طبق Q-022؛ تعیین trust boundaries و residual risks؛ قراردادهای authorization و تست متناسب با معماری انتخاب‌شده. معماری shared PostgreSQL + tenant_id + RLS قبلی صرفاً سابقه است؛ Q-022 با D-020 حل شده و معماری فعال، Alt-5 isolation cells با دیتابیس و اعتبارنامه مجزا برای هر تنانت درون سلول است. بدون کد برنامه، migration یا زیرساخت در این فاز. |
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
**Phase 0 — CLOSED by Product Owner (2026-10-14) — Supervisor documentation gate: APPROVED.** PR #1 was merged into `main` on 2026-10-14 (squash commit `d68fde54b4e4c86642b74c3bf1ef20fe18edf12b`). Phase 1 remains unauthorized. Runtime implementation/security has not been verified.

آخرین Commit تأییدشده روی `main` که در این سند به‌عنوان snapshot تاریخی ثبت شده، `994d4529c20c4a330bd843bd3ca1a7c9ed1f75ec` است. برای وضعیت زنده `main` و HEAD شاخه اصلاحات، مستقیماً به GitHub مراجعه کنید؛ این فایل مرجع HEAD جاری نیست.

بازبینی رسمی Supervisor در `SUPERVISOR_REVIEW.md` ثبت شده و Gate فعلی برای مستندات Phase 0 برابر `APPROVED` است؛ این تأیید فقط آمادگی مستندات/معماری را پوشش می‌دهد، نه امنیت زمان اجرا. اصلاحات شاخه `docs/phase0-correction-pass-3` از طریق PR #1 در `main` ادغام شده‌اند. جزئیات تاریخی اصلاحات در `CHANGELOG.md` آمده است.

**تصمیم‌های Q-001، Q-002 و Q-010 در 2026-10-12 ثبت و در `OPEN_QUESTIONS.md` به Resolved منتقل شده‌اند.** Phase 0 در 2026-10-14 توسط Product Owner بسته شد و PR #1 نیز ادغام شده است. **Phase 1 شروع نشده و همچنان نیازمند تأیید صریح و جداگانه Product Owner است.**
