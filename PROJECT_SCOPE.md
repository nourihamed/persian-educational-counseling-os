# PROJECT_SCOPE.md

Status: DRAFT — Phase 0 — Pending Approval

## هدف این سند

مرز دقیق MVP را مشخص می‌کند تا توسعه بدون Scope Creep پیش برود. "MVP" یعنی کوچک‌ترین نسخه‌ای که **کل حلقه ارزش** (Counselor Strategy → ... → Plan Adjustment) را واقعی و قابل‌استفاده می‌کند — نه یک محصول ناقص یک‌طرفه.

## MVP IN-SCOPE (پیشنهادی — نیازمند تأیید)

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

## MVP OUT-OF-SCOPE (فازهای بعدی)

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

این سند placeholder است؛ قطعی‌شدن محدوده MVP منوط به پاسخ به سؤالات ثبت‌شده در `OPEN_QUESTIONS.md` (به‌خصوص دامنه فاز اول، استراتژی Tenant Isolation، و عمق Billing در MVP) است. Q-012 (MVP Versioning Policy) دیگر جزو این وابستگی‌ها نیست — مالک محصول آن را در تاریخ ۲۰۲۶-۱۰-۱۰ تأیید کرد (`DECISION_LOG.md` D-008، Accepted).
