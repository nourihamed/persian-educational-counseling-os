# PROJECT_SCOPE.md

Status: Phase 0 scope baseline approved; Product Owner formally closed Phase 0 on 2026-10-14. Scope changes still require explicit Product Owner approval.

## هدف این سند

مرز دقیق MVP را مشخص می‌کند تا توسعه بدون Scope Creep پیش برود. "MVP" یعنی کوچک‌ترین نسخه‌ای که **کل حلقه ارزش** (Counselor Strategy → ... → Plan Adjustment) را واقعی و قابل‌استفاده می‌کند — نه یک محصول ناقص یک‌طرفه.

## MVP IN-SCOPE (تأییدشده توسط مالک محصول در 2026-10-12؛ مرجع تصمیم: Q-002 و D-010)

**تصمیم محدوده MVP — 2026-10-12:** این فهرست مرز کنترل‌شده MVP است و هدف آن تکمیل حلقه آموزشی «برنامه‌ریزی → اجرا و ثبت → تحلیل → اصلاح برنامه» است، نه افزودن همه قابلیت‌های محصول نهایی. Auth/RBAC پایه، مدیریت مشاور/دانش‌آموز، برنامه روزانه/هفتگی با حداقل versioning قابل‌ممیزی طبق D-008، فعالیت‌های اولیه، تحلیل پایه، کارهای عقب‌افتاده، اعلان درون‌برنامه‌ای و ledger اعتبار قابل‌ممیزی در محدوده می‌مانند. درگاه واقعی، Telegram/SMS عملیاتی، AI/planning black box، اپ native، analytics/risk پیشرفته و پنل کامل والد خارج از MVP هستند. هر تغییر دامنه به تصمیم صریح و ثبت‌شده مالک محصول نیاز دارد؛ Q-007 درباره دسترسی والد همچنان باز است.


1. Multi-tenant foundation (Counselor = Tenant) + Auth + RBAC پایه (Admin, Counselor, Student)
2. Counselor–Student relationship (Add/Edit/Deactivate/Archive, status lifecycle)
3. Student Profile + Default Subjects (3 رشته) + Curriculum ساده (Subject→Grade→Book→Chapter→Topic)
4. Program Template با Versioning حداقلی/قابل‌ممیزی (Minimum Viable Versioning — طبق `DECISION_LOG.md` D-008، **Accepted، تأیید صریح مالک محصول در تاریخ ۲۰۲۶-۱۰-۱۰، `OPEN_QUESTIONS.md` Q-012 Resolved**): شناسه پایدار Template + ProgramVersion غیرقابل‌تغییر هنگام انتشار؛ ویرایش Template نسخه جدید می‌سازد نه بازنویسی نسخه فعال؛ ثبت می‌شود کدام ProgramVersion برای ساخت هر Plan استفاده شده. ویژگی‌های پیشرفته (مقایسه بصری، Rollback UI، Branching، گزارش Diff پیشرفته) خارج از MVP است — نگاه کنید به بند Out-of-Scope. جزئیات دقیق سطح Schema (کدام وضعیت‌ها مستقیماً قابل‌ویرایش‌اند، رفتار دقیق هنگام به‌روزرسانی Template) همچنان به فاز طراحی Phase 2 تعلق دارد — این بخش توسط خودِ تأیید Q-012 بسته نشده است.
5. Planning Engine نسخه اول: Daily/Weekly Plan دستی توسط مشاور + قوانین پایه تداخل‌زمانی + Versioning حداقلی/قابل‌ممیزی برای Student Plan (طبق D-008، Accepted): شناسه پایدار Plan + شماره نسخه صریح؛ تغییرات نسخه منتشرشده قبلی را بی‌صدا بازنویسی نمی‌کنند؛ نسخه‌های قبلی حفظ می‌شوند؛ هر نسخه به Tenant و Student قابل‌انتساب است و Authorization روی هر Read/Write اعمال می‌شود.
6. Activity execution: Study Session, Test, Review (فقط همین سه نوع در ابتدا)
7. Error Analysis پایه (Error types ثابت + Custom)
8. Review Engine با الگوی ثابت 1-3-7 (Configurable بعداً)
9. Student Dashboard (Today / Overdue / Progress ساده)
10. Counselor Dashboard (لیست دانش‌آموزان + فیلتر پایه + شاخص‌های ساده)
11. Billing حداقلی: StudentCredit + CreditTransaction (ledger) + Student Activation blocking روی کمبود اعتبار — بدون Payment Gateway واقعی (MockPaymentProvider)
12. Notification: فقط In-App (Telegram/SMS به‌عنوان Adapter آماده ولی فعال‌سازی در فازهای 19/20)
13. Reports: حداقل یک خروجی PDF ساده RTL برای دانش‌آموز

## MVP OUT-OF-SCOPE (فازهای بعدی؛ خارج از MVP تأییدشده)

- Telegram Bot عملیاتی (Phase 19)
- SMS عملیاتی (Phase 20)
- Payment Gateway واقعی (Phase 22)
- Parent Panel کامل (Phase 23)
- AI Assistance (Phase 24)
- PWA (Phase 25)
- ویژگی‌های **پیشرفته** مدیریت نسخه Program/Plan (طبق D-008؛ خودِ Versioning حداقلی/قابل‌ممیزی IN-SCOPE است، فقط موارد زیر موکول می‌شوند): مقایسه بصری نسخه‌به‌نسخه، رابط کاربری پیشرفته Rollback/Restoration، مرور گسترده تاریخچه نسخه‌ها، Branching یا نسخه‌های موازی Template، گزارش‌های پیشرفته Diff و تحلیل اثر تغییر — این‌ها در Phase 15 و بعد از آن ساخته می‌شوند (§71، §72 Master Prompt)
- Risk Engine پیشرفته با مدل امتیازدهی چندبعدی (نسخه ساده قانون‌محور در MVP)
- Marketplace عمومی

## معیار "Done بودن" MVP

تمام مراحل حلقه در بخش ۱ Vision باید حداقل یک‌بار به‌صورت End-to-End واقعی (نه دمو ساختگی) قابل اجرا باشد، با تست E2E مطابق بخش ۵۸.

## وابستگی به تأیید

**وضعیت تأیید:** مرز MVP در این سند طبق تصمیم صریح مالک محصول درباره Q-002 / D-010 در 2026-10-12 تعیین شده است؛ این سند دیگر placeholderِ منتظر تعیین محدوده نیست. Q-001 / D-009 (Tenant Isolation)، Q-002 / D-010 (MVP scope) و Q-010 / D-011 (Pilot hosting) حل شده‌اند. پرسش‌های باز دیگر فقط در دامنه خودشان باقی می‌مانند؛ از جمله Q-007 درباره دسترسی والد و Q-011 درباره پایداری روش دسترسی GitHub. طبق D-012 / Q-013، قالب‌ها و نسخه‌های متعلق به سطح‌پلتفرم خارج از MVP هستند و در MVP فقط رکوردهای Tenant-owned پشتیبانی می‌شوند. جزئیات اجرایی Schema، RLS، Authorization و تست‌ها همچنان در فازهای فنی مربوطه طراحی و پیاده‌سازی می‌شوند. این وضعیت Phase 0 را نمی‌بندد و مجوز شروع Phase 1 نیست.
