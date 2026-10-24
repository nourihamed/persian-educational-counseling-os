# ROADMAP.md

Status (updated 2026-10-24): Phase 0 closed by Product Owner on 2026-10-14; PR #1 merged. Phase 1 provider-neutral design/documentation gate APPROVED under D-024; PR #3 was squash-merged into main on 2026-10-24 (b9c7a7f1f67ae7c11058c36d41beb3a32f76f0fa). D-020 selects Alt-5 hybrid isolation cells; D-023's Level 3 production-cell and Level 4 independent critical-backup targets remain mandatory. Q-023 remains OPEN as a hard pre-hosting deployment gate, not a Phase 1 design blocker: provider/account topology, capability evidence, cost/capacity, and environment-only security/backup tests must be completed before hosted deployment. Active Alt-5 catalog: 51 specifications, 0 implemented, 0 executed, 0 passing. Phase 2 remains NOT STARTED / NOT AUTHORIZED pending a separate Product Owner decision; real student data remains prohibited under D-014. Local setup is not an isolation boundary.

قانون: هر فاز طبق `Mandatory Development Workflow` (بخش ۷۶ Master Prompt) اجرا می‌شود و بعد از اتمام، **خودکار به فاز بعد نمی‌رویم** — منتظر تأیید می‌مانیم.

| # | فاز | خروجی کلیدی |
|---|---|---|
| 0 | Product & Business Model | مجموعه اسناد پایه — تکمیل و تأیید شده؛ Phase 0 در 2026-10-14 بسته شد |
| 1 | Architecture & Multi-Tenancy (design only) | انتخاب معماری جداسازی تنانت طبق Q-022؛ تعیین trust boundaries و residual risks؛ قراردادهای authorization و تست متناسب با معماری انتخاب‌شده. معماری shared PostgreSQL + tenant_id + RLS قبلی صرفاً سابقه است؛ Q-022 با D-020 حل شده و معماری فعال، Alt-5 isolation cells با دیتابیس و اعتبارنامه مجزا برای هر تنانت درون سلول است. بدون کد برنامه، migration یا زیرساخت در این فاز. |
| 2 | Database & Domain Model | ERD کامل، مدل‌های Core (Counselor, Student, Program, Activity...) |
| 3 | Infrastructure | FastAPI skeleton، Alembic، زیرساخت مطابق توپولوژی cell مصوب در Q-023 (انتخاب نشده؛ Docker Compose فقط ابزار استقرار است، نه مرز امنیتی)، CI اولیه؛ Redis فقط در صورت توجیه |
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

## سابقه وضعیت Phase 0 (snapshot تاریخی — نه وضعیت جاری فاز 1)

Phase 0 توسط Product Owner در 2026-10-14 بسته شد و PR #1 در همان تاریخ در `main` ادغام شد (squash commit `d68fde54b4e4c86642b74c3bf1ef20fe18edf12b`). این بخش فقط سابقه بسته‌شدن Phase 0 را حفظ می‌کند و مرجع وضعیت جاری Phase 1 نیست.

**وضعیت جاری پروژه فقط از ابتدای این فایل و `PROJECT_STATE.md`، `docs/phase1/PHASE1_REPORT.md` و `SUPERVISOR_REVIEW.md` خوانده شود.** طبق وضعیت ثبت‌شده در 2026-10-24 تحت D-024، گیت مستندات/طراحی Phase 1 تأیید شده است؛ Q-023 همچنان گیت اجباری پیش از استقرار میزبانی‌شده است؛ Phase 2 هنوز شروع نشده و مجوز ندارد. تأیید طراحی به معنی تأیید امنیت زمان اجرا نیست.
