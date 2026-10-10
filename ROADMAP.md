# ROADMAP.md

Status: DRAFT — Phase 0 — Pending Approval

قانون: هر فاز طبق `Mandatory Development Workflow` (بخش ۷۶ Master Prompt) اجرا می‌شود و بعد از اتمام، **خودکار به فاز بعد نمی‌رویم** — منتظر تأیید می‌مانیم.

| # | فاز | خروجی کلیدی |
|---|---|---|
| 0 | Product & Business Model | این مجموعه اسناد (در حال انجام) |
| 1 | Architecture & Multi-Tenancy | ARCHITECTURE.md، تصمیم نهایی استراتژی Tenant Isolation |
| 2 | Database & Domain Model | ERD کامل، مدل‌های Core (Counselor, Student, Program, Activity...) |
| 3 | Infrastructure | FastAPI skeleton، Alembic، Docker، CI اولیه، Redis |
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
| 21 | Billing / Subscription / Credits | Full ledger، Plan/Order/Invoice |
| 22 | Payment Gateway | RealPaymentProvider، Webhook idempotency |
| 23 | Parent Panel | دسترسی سطح‌بالا، Privacy rules |
| 24 | AI Assistance | Explain/Summarize/Recommend (غیر منبع حقیقت) |
| 25 | PWA | Offline-ready shell |
| 26 | Security Hardening | Pen-test checklist، Audit log review |
| 27 | Performance | Query profiling، N+1، caching |
| 28 | Production Readiness | چک‌لیست بخش ۷۵ |

## یادداشت — جایگاه Versioning در این Roadmap (پیشنهادی، پیوست به D-008)
کلمه «Versioning» فقط زیر Phase 15 در جدول بالا ظاهر می‌شد، که قبلاً می‌توانست این‌طور خوانده شود که Program Template/Plan Versioning اصلاً تا Phase 15 وجود ندارد — این خوانش با `ARCHITECTURE.md`/`DATABASE.md` (که Versioning را یک اصل پایه توصیف می‌کنند) و با Policy جدید `DECISION_LOG.md` D-008 (که حداقل Versioning را جزو MVP می‌داند) همخوان نیست. برای رفع این تناقض، بدون تغییر شماره یا ترتیب فازها:
- **حداقل Versioning قابل‌ممیزی** (شناسه پایدار + شماره نسخه + عدم بازنویسی بی‌صدا + تاریخچه + Attribution) بخشی از **مدل داده پایه** است که در Phase 2 (Database & Domain Model) طراحی می‌شود و هرجا Program Template یا Plan در فازهای زودتر از ۱۵ ساخته/استفاده شود (مثلاً Phase 12 Planning Engine به یک ساختار Plan نیاز دارد)، همان حداقل Versioning را دارد.
- **Phase 15** مشخصاً به معنای معرفی اصل Versioning نیست، بلکه شامل منطق Personalization (Baseline→Personalized Plan) و ابزارهای **پیشرفته** مدیریت نسخه (مقایسه بصری، Rollback UI، Branching، گزارش Diff) است که در بالای همان حداقل MVP ساخته می‌شوند.
- این یادداشت یک توضیح/هماهنگ‌سازی مستندی است، نه تصمیم تجاری یا معماری جدید؛ تصمیم اصلی در D-008 ثبت شده و هنوز Pending Product Owner Confirmation است (`OPEN_QUESTIONS.md` Q-012).

## وضعیت فعلی
**Phase 0 — IN PROGRESS — Pending Supervisor Review.**

آخرین Commit واقعی و مستقیماً تأییدشده (توسط `git log`/`git ls-remote` روی خود Repository) روی شاخه `main`:
```
994d4529c20c4a330bd843bd3ca1a7c9ed1f75ec
docs: Phase 0 correction pass — align docs with actual repo state, add SUPERVISOR_REVIEW.md placeholder
```
این تأیید صرفاً به این معنی است که این Commit واقعاً در Repository وجود دارد — **نه** این‌که محتوای آن از نظر معماری یا کسب‌وکار توسط یک Supervisor مستقل بازبینی یا تأیید شده باشد. تأیید نهایی فاز ۰ فقط از طریق فرآیند رسمی Supervisor Review (`SUPERVISOR_REVIEW.md`) ثبت می‌شود و هنوز ثبت نشده است.

اصلاحات مستندات Phase 0 روی شاخه `docs/phase0-correction-pass-3` (نه مستقیم روی `main`) در حال انجام است تا اسناد برای همان بازبینی مستقل آماده شوند؛ برای فهرست کامل و تاریخ‌دار هر دور اصلاح، به `CHANGELOG.md` مراجعه شود.

**Phase 1 شروع نشده و مجاز اعلام نشده است. هیچ فاز، قابلیت یا دامنه جدیدی به این Roadmap اضافه نشده است.** هیچ کاری از فاز ۱ تا دریافت تأیید صریح مالک پروژه/Supervisor آغاز نمی‌شود.
