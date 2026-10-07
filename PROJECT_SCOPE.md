# PROJECT_SCOPE.md

Status: DRAFT — Phase 0 — Pending Approval

## هدف این سند

مرز دقیق MVP را مشخص می‌کند تا توسعه بدون Scope Creep پیش برود. "MVP" یعنی کوچک‌ترین نسخه‌ای که **کل حلقه ارزش** (Counselor Strategy → ... → Plan Adjustment) را واقعی و قابل‌استفاده می‌کند — نه یک محصول ناقص یک‌طرفه.

## MVP IN-SCOPE (پیشنهادی — نیازمند تأیید)

1. Multi-tenant foundation (Counselor = Tenant) + Auth + RBAC پایه (Admin, Counselor, Student)
2. Counselor–Student relationship (Add/Edit/Deactivate/Archive, status lifecycle)
3. Student Profile + Default Subjects (3 رشته) + Curriculum ساده (Subject→Grade→Book→Chapter→Topic)
4. Program Template (بدون Versioning کامل در MVP اول؛ Versioning از Phase 15 به‌صورت رسمی)
5. Planning Engine نسخه اول: Daily/Weekly Plan دستی توسط مشاور + قوانین پایه تداخل‌زمانی
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
- Program/Plan Versioning کامل با تاریخچه مقایسه (نسخه ساده در MVP، کامل در Phase 15/71/72)
- Risk Engine پیشرفته با مدل امتیازدهی چندبعدی (نسخه ساده قانون‌محور در MVP)
- Marketplace عمومی

## معیار "Done بودن" MVP

تمام مراحل حلقه در بخش ۱ Vision باید حداقل یک‌بار به‌صورت End-to-End واقعی (نه دمو ساختگی) قابل اجرا باشد، با تست E2E مطابق بخش ۵۸.

## وابستگی به تأیید

این سند placeholder است؛ قطعی‌شدن محدوده MVP منوط به پاسخ به سؤالات ثبت‌شده در `OPEN_QUESTIONS.md` (به‌خصوص دامنه فاز اول، استراتژی Tenant Isolation، و عمق Billing در MVP) است.
