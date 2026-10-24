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
**CURRENT STATUS (authoritative, D-017, 2026-10-17): DECIDED for the pilot.** Direct PostgreSQL connections with a bounded per-tenant pool of size 1 per tenant per process. No pooler for the pilot. Transaction pooling is deferred and requires passing compatibility tests and a separate decision. **Everything below this status block that describes the pooler mode as open, or proposes a choice, is HISTORICAL and superseded.**
**Status (2026-10-17): DECIDED by Product Owner — D-017.** Pilot uses direct PostgreSQL connections with bounded per-tenant pool (size 1 per tenant per process). Transaction pooling (PgBouncer) is deferred and requires passing compatibility tests and a separate decision. Earlier proposal text follows for history: Proposal: PgBouncer in transaction pooling mode, with explicit per-mode limits, conditional on validation. Conditions proposed: (1) tenant identity and per-request security context are not carried over from a previous request on a recycled connection; (2) prepared statements, session variables and RLS (where still used) are tested explicitly under the chosen mode; (3) if compatibility is not demonstrated, the transaction mode is not used and pooling is limited until the issue is resolved; security is not traded for connection savings. Owner acceptance required; recorded in DECISION_LOG only after acceptance.
**HISTORICAL (Revision 9; superseded by D-017):** the earlier draft said pooler mode remained OPEN and proposed transaction pooling. Current rule: direct PostgreSQL connections with pool size 1 per tenant per process; transaction pooling is deferred.
**HISTORICAL (superseded by D-017; not current):** Status was OPEN (recommended: transaction pooling only if TI-CTX-11, TI-CTX-12 and TI-PLAT-05 pass in the chosen configuration; otherwise direct connections for the pilot).
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
**CURRENT STATUS (updated 2026-10-23 by D-020): RESOLVED as a design direction, not as security evidence.** D-020 selects Alt-5 hybrid isolation cells; the active normative design is `docs/phase1/TENANT_ISOLATION_DESIGN.md`. The prior Option A/C/D mechanism analysis is historical only and is retained in `docs/phase1/Q019_MECHANISM_EVALUATION.md` for traceability.

**Current requirements:**
- Each cell has a separate PostgreSQL cluster/instance and network boundary.
- Each tenant within a cell has its own database and tenant-specific runtime credential; an ordinary tenant credential must not access the other tenant in the same cell.
- Worker/secret access, migration identities, backup permissions/keys, and recovery actions are scoped and audited; no routine global data-capable migrator/owner is allowed.
- The active authorization contract and active 47-contract catalog define the current planned controls. All tests remain NOT-RUN; no security property is verified.
- The initial pilot proposal remains capped at 10 tenants and at most two tenants per cell, subject to measured capacity/cost and separate written pilot approval.

**Residual risks:** independent theft of all usable credentials and global host/cloud/root compromise can still create broad exposure. Topology alone does not eliminate these risks. D-014 continues to prohibit real student data until all pilot gates pass.

**Historical decision trace:** D-014 established the pre-pilot security gate; D-016 preferred Option C at that time; D-019 rejected that prior residual-risk posture as sufficient; D-020 subsequently selected Alt-5. D-016's Option C mechanism is no longer normative.

**Blocks Phase 1 approval:** independent review of the current Alt-5 design/contracts, reconciliation of D-011/D-017, and explicit evidence for the design's trust boundaries are still required.


## Q-007 — Gate impact (Phase 1 review)
**Status:** Product question OPEN (default parent access level). Gate impact: **CONFIRMED by the independent reviewer** (PR #3 review): TI-API-09 blocks closure of the phase that implements parent access (Phase 23), not Phase 1 architectural approval, provided parent access is not implemented in Phase 1 and TI-API-09 stays BLOCKED.
**Owner acceptance of the gate wording:** pending.

## Q-021 — Product Owner disposition of Option C credential-compromise residuals
**Status: RESOLVED — Product Owner selected option B, 2026-10-23; see DECISION_LOG.md D-019.**

**Decision:** Require stronger architecture before Phase 1 approval. The Product Owner does not accept the current Option C residual risks for theft of many/all tenant login credentials (K-L-N) or compromise of the owner/migrator boundary (K-O) as an acceptable basis for approval.

**Important boundary:** This decision selects the requirement to redesign, not a final topology. It does not accept the residual risks, approve Option C, or select database-per-tenant/shared cluster, separate clusters, or a hybrid. See Q-022 and `docs/phase1/STRONGER_TENANT_ISOLATION_OPTIONS.md`.

**Consequences:** Phase 1 remains NOT READY; Phase 2 is NOT STARTED and NOT AUTHORIZED; no implementation or real-data pilot is authorized. D-014 remains in force.

**Resolution evidence:** explicit Product Owner instruction in conversation on 2026-10-23; recorded in D-019.

## Q-022 — Select a revised tenant-isolation architecture after independent comparison
**Status: RESOLVED — Product Owner selected option A on 2026-10-23; recorded in DECISION_LOG.md D-020.**

**Decision:** Select Alt-5 hybrid isolation cells, using Alt-4 as the security reference. The initial pilot proposal remains capped at 10 tenants and no more than two tenants per cell (up to five cells), subject to documented capacity and cost evaluation. This is a proposed blast-radius limit, not measured capacity or pilot authorization.

**Mandatory constraints:** separate PostgreSQL cluster/instance and network boundary per cell; cell-scoped workers, runtime credentials, and secret access; cell-scoped migration identities with no routine global data-capable migrator; cell-scoped backup access/keys; deployment authority separated from routine data-read authority; dual-approved, time-limited, audited cross-cell break-glass; preserve suspension/offboarding state through restore. Revisit D-011 hosting and D-017 connection/pool assumptions for compatibility.

**Residual risks:** independent theft of all usable tenant credentials and compromise of global host/cloud/root controlling all cells and keys remain catastrophic scenarios. No claim is made that topology alone prevents them. A single ordinary worker, secret policy, or migrator must not provide a universal path across cells. Global-root residual risk must be explicitly assessed before real-data use.

**Still required:** revise and independently review the normative design, authorization contract, and architecture-specific tests; measure cost/capacity on the actual target environment; pass all D-014 pilot gates. Q-022 resolution does not approve Phase 1, authorize implementation, or permit real student data.

## Q-020 — Tenant data-retention period and criteria for dropping tenant roles (OPEN; principle decided D-017)
**Draft (2026-10-17):** `docs/phase1/DATA_RETENTION_SCHEDULE_DRAFT.md`. **Approach accepted (D-018):** data minimisation, per-category rule, short explicit periods, extensions only by recorded decision, legal/tax/privacy reviewers engaged. **Still OPEN:** all durations (NEEDS-DECISION or LEGAL-REVIEW; none set), the named reviewers, and the approver of role deletion (Product Owner, per D-018).
**Status (2026-10-17): principle DECIDED by Product Owner — D-017; retention duration NOT SET (open pre-pilot deliverable).** Accepted: no automatic role deletion; five-step lifecycle. Earlier proposal text follows for history. Proposed policy: role deletion is NOT automatic on subscription end or counselor deactivation. Proposed lifecycle: (1) disable login and access immediately; (2) revoke privileges and terminate sessions and pooled connections; (3) retain audit evidence and records needed for incident review; (4) check object ownership, dependencies, backups and data-retention obligations; (5) delete the role only after the checklist is approved. Proposed pre-pilot action: a retention policy table covering student data, audit records, billing records and backups, produced with legal, tax and privacy review. The exact retention period is NOT set here because it depends on legal, tax and privacy obligations of the operating jurisdiction and must not be guessed.
**Why it matters:** D-016 point 6 drops tenant roles only after data-retention requirements are checked. No retention period has been decided.
**Decision needed from owner:** retention period for tenant data and audit evidence; criteria for dropping a tenant role after suspension.
**Must be resolved before:** the first tenant offboarding feature (Phase 4 or later).
**Blocks Phase 1 approval:** No.

## Q-023 — سازگاری میزبانی سرور با Alt-5 و هدف استقلال سطح ۳/۴
**Status: OPEN — provider/topology compatibility remains a mandatory pre-hosting deployment gate; it is not a blocker for the Phase 1 design-only gate under D-024.**

**Product Owner decisions:** D-023 (2026-10-23) sets the security target: Level 3 infrastructure/administrative independence for production cells and Level 4 independent administration/control of critical backups/recovery. D-024 (2026-10-24) defers provider-specific comparison and validation until hosted-deployment planning while allowing Phase 1 to be reviewed on provider-neutral design criteria. Neither decision proves that any provider or deployment meets the target.

**Provider-neutral design requirements reviewed in Phase 1:**
- Each production cell requires a distinct host/VM and network boundary, its own PostgreSQL cluster/instance, tenant-specific databases/runtime credentials, and cell-scoped workers, secrets, and migration identities.
- Routine administrators/credentials for one cell must not automatically administer other cells. Separate cloud accounts/projects or a demonstrably equivalent administrative boundary must be evaluated. Multiple VMs/Compose stacks under one unrestricted shared root/admin boundary are not sufficient.
- Critical backups must be outside ordinary production-account administrative control, with independent backup administration, encryption keys, and deletion/retention controls. Production-account compromise alone must not be able to destroy all critical recovery copies.
- Provider-wide control-plane compromise and compromise of a genuinely global organization/root identity remain explicit residual risks; no absolute-immunity claim is made.
- The architecture and active test contracts must explicitly cover these boundaries and residuals. The current Phase 1 documents do so as design requirements only; no runtime proof is claimed.

**Why Q-023 remains OPEN:** no actual hosting candidate, account topology, provider capability, price, or capacity has been selected or verified. These are intentionally deferred and must be resolved before hosted deployment. The open question tracks this future validation; it no longer blocks approval of the provider-neutral Phase 1 design documentation under D-024.

**Deferred until hosted-deployment planning:** select the provider and exact topology; verify organization/account administrators, private networking and scoped identities; itemize cost; recalculate per-cell resource/connection budgets; and validate provisioning, monitoring, credential rotation, failure containment, backup immutability/retention, and restore drills on the actual target environment.

**Hard gates:** Q-023 must be resolved with evidence before any hosted deployment. D-014 remains in force: no real student data until all applicable implementation, security-test, operational, capacity, incident-drill, and independent-review gates pass and the Product Owner gives explicit written approval. The proposed maximum of two tenants per cell and ten tenants total remains provisional, not measured capacity. Local development does not prove Alt-5 isolation. Phase 1 design approval does not authorize Phase 2 automatically or authorize real student data.


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
