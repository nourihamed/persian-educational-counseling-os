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

## Q-007 — ماتریس تفصیلی دسترسی والد (HIGH-LEVEL POLICY ACCEPTED; DETAILS OPEN)
**سیاست سطح‌بالا:** گزینه A طبق OQ-G و تصمیمات PO در 2026-11-07 پذیرفته شده است. دسترسی والد به‌صورت مستقل برای هر فرزند و هر permission/scope تنظیم می‌شود. رابطه و اختیار قانونی باید بر اساس سن و قانون قابل‌اعمال احراز شود؛ scope، expiry، تغییر، revocation و audit لازم‌اند. یادداشت خصوصی مشاور و مکالمات محرمانه به‌صورت پیش‌فرض مخفی هستند. اطلاعات حساس، مالی و آزمون مجوز مستقل می‌خواهند. حقوق دانش‌آموز و قانون بر تنظیمات عادی مقدم‌اند.

**مواردی که همچنان باز هستند و باید قبل از پیاده‌سازی مربوطه تعیین شوند:**
- ماتریس دقیق دسترسی بر اساس سن/وضعیت تحصیلی و اختیار قانونی در ایران؛
- مدارک/شواهد قابل قبول و فرآیند احراز رابطه و سرپرستی، پس از بررسی حقوقی؛
- قواعد استثنا، تعارض والدین/سرپرستان، تغییر وضعیت قانونی و revocation؛
- scopeهای دقیق read/action برای برنامه، پیشرفت، آزمون، مالی، حضور و ارتباطات؛
- تست‌های executable برای parent-child isolation و دسترسی‌های ممنوع.

**اولویت:** HIGH برای نهایی‌سازی قراردادهای Authorization پیش از فعال‌سازی Parent APIs. Q-007 نباید بسته شود تا ماتریس حقوقی/فنی و تست‌ها تصویب شوند.

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
**Active contract dependency:** TI-API-01 requires cross-tenant and nonexistent-object responses to be indistinguishable without fixing the final numeric status code; TI-API-03 covers forged referenced-object IDs, TI-FILE-01 covers cross-tenant file access, and TI-VER-01 covers version-linkage boundaries. These specifications remain NOT-RUN until implemented. Historical TI-API-15/TI-REPO/TI-RPT identifiers are not active acceptance contracts.
**Must be resolved before:** Phase 4 endpoint implementation.
**Blocks Phase 1 approval:** No.

_Q-015 is resolved; see the Resolved section below and DECISION_LOG D-013._

## Q-016 — PostgreSQL connection pooling mode and transaction-local context
**CURRENT STATUS (authoritative, D-017, 2026-10-17): DECIDED for the pilot.** Direct PostgreSQL connections with a bounded per-tenant pool of size 1 per tenant per process. No pooler for the pilot. Transaction pooling is deferred and requires passing compatibility tests and a separate decision. **Everything below this status block that describes the pooler mode as open, or proposes a choice, is HISTORICAL and superseded.**
**Status (2026-10-17): DECIDED by Product Owner — D-017.** Pilot uses direct PostgreSQL connections with bounded per-tenant pool (size 1 per tenant per process). Transaction pooling (PgBouncer) is deferred and requires passing compatibility tests and a separate decision. Earlier proposal text follows for history: Proposal: PgBouncer in transaction pooling mode, with explicit per-mode limits, conditional on validation. Conditions proposed: (1) tenant identity and per-request security context are not carried over from a previous request on a recycled connection; (2) prepared statements, session variables and RLS (where still used) are tested explicitly under the chosen mode; (3) if compatibility is not demonstrated, the transaction mode is not used and pooling is limited until the issue is resolved; security is not traded for connection savings. Owner acceptance required; recorded in DECISION_LOG only after acceptance.
**HISTORICAL (Revision 9; superseded by D-017):** the earlier draft said pooler mode remained OPEN and proposed transaction pooling. Current rule: direct PostgreSQL connections with pool size 1 per tenant per process; transaction pooling is deferred.
**HISTORICAL (superseded by D-017; not current):** Status was OPEN (recommended: transaction pooling only if TI-CTX-11, TI-CTX-12 and TI-PLAT-05 pass in the chosen configuration; otherwise direct connections for the pilot).
**Decision needed from owner:** no change is needed for the current D-017 pilot baseline. If transaction pooling or a different pool size is proposed, obtain a separate Product Owner decision after topology-specific compatibility and capacity evidence.
**Why it matters:** a pooled connection carrying one tenant's context into another tenant's request is a direct cross-tenant leak.
**Active dependency:** TI-CELL-15 covers revocation and termination of active sessions/pools; it does not test transaction-pooling compatibility. Before any transaction-pooling proposal is accepted, define and execute separate mode-specific compatibility contracts in the implementation phase. Historical TI-CTX/TI-PLAT identifiers are not current acceptance evidence.
**Must be resolved before:** Phase 3 infrastructure configuration.
**Blocks Phase 1 approval:** No.

## Q-017 — Background-job execution model
**Status:** OPEN (recommended: one tenant per job run with payload-bound tenant_id; platform jobs restricted to aggregates; failure leaves no context set).
**Decision needed from owner:** per-tenant job model versus one global job with per-row checks (not recommended).
**Why it matters:** jobs and retries are a common cross-tenant path.
**Active contract dependency:** TI-JOB-01, TI-JOB-02, TI-JOB-03 and TI-JOB-04 cover forged/stale tenant context, delayed jobs, cross-cell exports, and platform aggregate-job scope. The exact queue/worker model remains open; TI-JOB-05 is a retired identifier, not an active contract.
**Must be resolved before:** Phase 3 queue design; Phase 17–18 scheduling.
**Blocks Phase 1 approval:** No.

## Q-018 — Tenant-scoped file storage for the pilot
**Status:** OPEN (recommended: S3-compatible object storage on the pilot host with `tenants/{tenant_id}/` namespacing, server-side authorization before signing, short TTL; no public buckets).
**Decision needed from owner:** storage provider and hosting location (must be checked against D-011 for reachability), and maximum link lifetime.
**Why it matters:** files are a direct cross-tenant read path if keys or links are guessable.
**Active contract dependency:** TI-FILE-01, TI-FILE-02 and TI-FILE-03 cover tenant-scoped file access, URL revocation, and upload ownership/routing. Storage provider, URL lifetime and provider-specific controls remain open for the first file feature; retired TI-FILE-04..07 identifiers are not active contracts.
**Must be resolved before:** the first file feature.
**Blocks Phase 1 approval:** No.

## Q-019 — Tenant-context boundary against threat T4 (decomposed)
**CURRENT STATUS (updated 2026-10-23 by D-020): RESOLVED as a design direction, not as security evidence.** D-020 selects Alt-5 hybrid isolation cells; the active normative design is `docs/phase1/TENANT_ISOLATION_DESIGN.md`. The prior Option A/C/D mechanism analysis is historical only and is retained in `docs/phase1/Q019_MECHANISM_EVALUATION.md` for traceability.

**Current requirements:**
- Each cell has a separate PostgreSQL cluster/instance and network boundary.
- Each tenant within a cell has its own database and tenant-specific runtime credential; an ordinary tenant credential must not access the other tenant in the same cell.
- Worker/secret access, migration identities, backup permissions/keys, and recovery actions are scoped and audited; no routine global data-capable migrator/owner is allowed.
- The active authorization contract and active 51-contract catalog define the current planned controls. All tests remain NOT-RUN; no security property is verified.
- The initial pilot proposal remains capped at 10 tenants and at most two tenants per cell, subject to measured capacity/cost and separate written pilot approval.

**Residual risks:** independent theft of all usable credentials and global host/cloud/root compromise can still create broad exposure. Topology alone does not eliminate these risks. D-014 continues to prohibit real student data until all pilot gates pass.

**Historical decision trace:** D-014 established the pre-pilot security gate; D-016 preferred Option C at that time; D-019 rejected that prior residual-risk posture as sufficient; D-020 subsequently selected Alt-5. D-016's Option C mechanism is no longer normative.

**Historical gate note (superseded by D-024, 2026-10-24):** this requirement described the pre-approval state. The Phase 1 provider-neutral design/documentation gate is now APPROVED; this does not verify runtime controls. Q-023 remains a mandatory pre-hosting deployment gate, and D-014 continues to prohibit real student data until all required implementation, security, operational, capacity, incident-drill, independent-review and written Product Owner approval conditions pass.


## Q-007 — Gate impact (Phase 1 review)
**Status:** Product question OPEN (default parent access level). Gate impact: **CONFIRMED by the independent reviewer** (PR #3 review): TI-API-09 blocks closure of the phase that implements parent access (Phase 23), not Phase 1 architectural approval, provided parent access is not implemented in Phase 1 and TI-API-09 stays BLOCKED.
**Owner acceptance of the gate wording:** pending.

## Q-021 — Product Owner disposition of Option C credential-compromise residuals
**Status: RESOLVED — Product Owner selected option B, 2026-10-23; see DECISION_LOG.md D-019.**

**Decision:** Require stronger architecture before Phase 1 approval. The Product Owner does not accept the current Option C residual risks for theft of many/all tenant login credentials (K-L-N) or compromise of the owner/migrator boundary (K-O) as an acceptable basis for approval.

**Important boundary:** This decision selects the requirement to redesign, not a final topology. It does not accept the residual risks, approve Option C, or select database-per-tenant/shared cluster, separate clusters, or a hybrid. See Q-022 and `docs/phase1/STRONGER_TENANT_ISOLATION_OPTIONS.md`.

**Historical consequence at decision time (2026-10-23; superseded for the design-only gate by D-024 on 2026-10-24):** Phase 1 was NOT READY pending architecture selection and review. The current provider-neutral Phase 1 design/documentation gate is now APPROVED under D-024; this does not authorize Phase 2, hosting, implementation, or real student data. Q-023 remains a hard pre-hosting gate, and D-014 remains in force.

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
**Effect on documents:** `TENANT_ISOLATION_DESIGN.md` §8 and §5.1; `TENANT_ISOLATION_TEST_CONTRACTS.md` TI-API-09 and TI-API-14; `TENANT_PATH_INVENTORY.md` P-25, P-26.
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


---

## Product Owner decisions confirmed 2026-11-07 — resolved direction, remaining details open

The following decision topics have received explicit Product Owner choices. They are recorded here to preserve the distinction between resolved direction and unresolved implementation/legal parameters. See `DECISION_LOG.md` and `docs/PRODUCT_OWNER_DECISIONS_2026-11-07.md` for the full decision record.

- **OQ-A — Platform Admin transfer initiation: RESOLVED (Option A).** Platform Admin cannot initiate transfers; may submit a support/review request only. Eligible initiators: verified parent/legal guardian, current counselor, destination Workspace.
- **OQ-B — Control Plane mobile storage: RESOLVED (Option K).** Encrypted E.164 mobile plus keyed deterministic HMAC index; Platform Security infrastructure manages keys. Key rotation, recovery, dual-index migration, and operational controls remain open design work.
- **OQ-C — Decision numbering: RESOLVED (Option A).** Collision-free crosswalk before D-number assignment; individual PO approval; superseded history retained. The crosswalk itself remains a required repository task.
- **OQ-D — Control Plane topology: RESOLVED (Option A).** Independent infrastructure, primary plus replica, independent encrypted backups and restore drills. RPO/RTO, failover consistency, split-brain prevention, retention, and measured capacity/cost remain OPEN.
- **OQ-E — Transfer cutover: RESOLVED (Option B).** Controlled source write-freeze plus final snapshot for MVP. Freeze boundary/duration, recovery and acceptance criteria remain OPEN.
- **OQ-F1 — Legal jurisdiction: RESOLVED (Option A).** Iran-only legal workflow for MVP; extensible architecture. Exact Iranian legal evidence rules remain OPEN pending legal review.
- **OQ-F2 — Retention: RESOLVED (Option A).** Category-based, versioned retention; durations after legal/contractual/operational review; legal hold and deletion/anonymization. Numeric durations remain OPEN.
- **OQ-F3 — Capacity: RESOLVED (Option A).** Multi-level configurable capacity; atomic checks; active-only student consumption; separate from credits. Provisional cap of 10 Workspaces total and 2 per cell; actual capacity values remain OPEN pending benchmarks.
- **Q-007 / OQ-G — Parent access: HIGH-LEVEL POLICY RESOLVED (Option A), DETAILS OPEN.** Per-child/per-permission access; verified relationship and legal authority; scope/expiry/revocation/audit; private counselor notes and confidential communications hidden by default; student rights and law prevail. Detailed age-based matrix, legal evidence, exceptions, and tests remain OPEN.

### Transfer decision reconciliation required

- D-025's global mobile+grade uniqueness rule remains a business rule, but its enforcement must move from any Workspace-local registry to the central Control Plane.
- D-026's previous-counselor authenticated fee confirmation remains cumulative. Its former Platform Admin initiator allowance is superseded by OQ-A.
- D-027 guardian consent remains cumulative; destination Workspace acceptance is also required.
- PR #11's Control Plane registry + durable recoverable Saga direction is accepted; schema, APIs, implementation, and tests remain unapproved.

### Unresolved items deliberately retained

- Control Plane RPO/RTO, failover/split-brain controls, backup retention and restore objectives; independent backup/restore drills remain unexecuted.
- HMAC/encryption rotation has a draft database gate and alias-completeness protocol, but KMS/HSM integration, trusted cryptographic backfill, role grants, crash recovery and execution evidence remain open.
- Transfer state machine, Freeze + Final Snapshot workflow, and cutover evidence fields are specified in draft contracts/SQL; exact freeze boundary, drain timeout, retry/backoff, manual-intervention thresholds, outbox/inbox runtime and crash recovery remain open.
- Iranian legal evidence requirements by student age/guardian status.
- Numeric retention durations and named operational owners.
- Capacity schema/counters are drafted; benchmarked Workspace/counselor/branch/concurrency/cell limits and measured capacity remain open.
- Detailed Q-007 parent permission matrix, legal exceptions and executable tests.
- The collision-free decision crosswalk is documented; no D-028+ identifiers are assigned. PR #8's old Counselor/Organization tenant schema and PR #9/#10/#11 must be reconciled/rebased or superseded before merge.
- Control Plane and Workspace schemas, role/privilege contracts, API/authorization contracts and regression suites now exist as drafts; SQL execution, role verification, runtime services and independent acceptance evidence remain open.

## Phase 2 Product Owner decision status — 2026-11-09

The following high-level choices are ACCEPTED and must not be re-asked as undecided. Detailed technical/legal parameters remain open where noted:

- OQ-A: Platform Admin cannot initiate a transfer; support review only.
- OQ-B: encrypted recoverable canonical E.164 plus keyed deterministic HMAC; Platform Security owns key management. Rotation and recovery implementation remain open.
- OQ-C: collision-free D-number crosswalk before any new identifier; individual PO approval; preserve superseded history. D-028 onward are not assigned.
- OQ-D: independent Control Plane primary/replica plus independent encrypted backups and restore drills. RPO/RTO, failover, split-brain, backup retention and capacity evidence remain open.
- OQ-E: MVP transfer uses source write freeze + final snapshot, staging and validation before atomic ownership switch. Freeze boundary, timeout and recovery thresholds remain open.
- OQ-F1: Iran-only legal workflow in MVP; exact evidence rules require legal review.
- OQ-F2: category-based, versioned retention; no numeric retention duration approved.
- OQ-F3: independently configurable Workspace/counselor/branch/concurrency/cell capacity; atomic checks; active students consume capacity; provisional 10 Workspace / 2 per cell limits are not measured capacity or pilot authorization.
- OQ-G/Q-007: per-child/per-permission parent access policy accepted at high level; Q-007 remains OPEN for detailed legal/age matrix and executable tests.
- PO decision 18: cross-Workspace and nonexistent resources return indistinguishable 404; 403 only for visible object/action forbidden.
- PO decision 19: background jobs are scoped to one Workspace with immutable ownership context and idempotent retry.
- PO decision 20: private S3-compatible storage, tenant namespace, server-side authorization before short-lived signed URL; provider remains open.
- PO decision 21: UTC canonical timestamps; Jalali default display; Gregorian optional; scheduled events retain local date/time/timezone.
- PO decision 22: deterministic, explainable, versioned/configurable Risk Engine; AI assistive; counselor override audited.

These accepted directions do not mean implementation or tests exist. Phase 2 remains NOT READY and D-014 prohibits real data.


### Q-007 technical contract reference (2026-11-09)

The high-level OQ-G Option A decision remains accepted: parent access is per child and per permission. The implementation-facing unresolved matrix is now captured in `docs/phase2/api/PARENT_GUARDIAN_AUTHORITY_MATRIX_Q007.md`. It deliberately does not invent Iranian age thresholds, legal evidence, custody/dispute rules or student-objection rights. Qualified Iran legal review and explicit Product Owner approval remain required before Parent APIs or guardian transfer approval are enabled. Q-007 remains OPEN.

## Platform Security open questions (Issue #13, Decision C — deferred; no answer assumed)
- PS-1 Signature algorithm for assertions. Owner: Platform Security / Product Owner. Blocks production verification.
- PS-2 Algorithm allowlist values. Owner: Platform Security. Blocks production verification.
- PS-3 Issuer-key registry design and implementation. Owner: Platform Security.
- PS-4 Key provisioning, storage, rotation and revocation procedures. Owner: Platform Security.
- PS-5 Clock-skew allowance for not_before / expires_at. Owner: Product Owner with Platform Security.
- PS-6 Certificate authority, trust store and mTLS identity model for the verifier-to-adapter channel. Owner: Platform Security.
- PS-7 Deployment topology of the verifier service and the adapter. Owner: Platform Security / Product Owner.
- PS-8 Revocation source for receipts and membership-revocation propagation across API, export, worker and notification handoffs. Owner: Product Owner / Platform Security. Blocks any end-to-end freshness claim.

## Phase 2 decision clarification — 2026-11-13 (no new D-number)

The Product Owner has now selected fixed immutable assessment question sets (MVP), specialized Activity-linked domain entities, the narrow transfer conflict exception case, and the 7-day Student Credit archive-return window with original-period-only reactivation. See the 2026-11-13 supplement in DECISION_LOG.md.

- **Transfer approval conflict:** the only exception case under consideration is when the source counselor and destination Workspace owner are the same person. The exception remains disabled until an independent approval authority and its exact scope are separately approved. No Platform Admin authority is implied. Fail closed when the exception would be needed.
- **Student Credit:** the 7-calendar-day window is measured from original activation. Free reactivation is limited to the original entitlement period and does not renew it. Returned credit must be reserved for the same student and unavailable for another student's activation.
- **OQ-D:** prior Option A remains controlling. Manual promotion is a possible pilot runbook procedure only; primary/replica and independent encrypted backup direction remains. RPO/RTO, replication mode/lag, fencing and split-brain controls remain open.
- **Assessment:** fixed version-level question membership/order is MVP. Adaptive/per-attempt delivery is not enabled; immutable version-question rows and response FK integrity are required.
- **Activity:** specialized entities remain authoritative; Activity is shared scheduling/tracking, not a generic replacement.

Q-007 and Q-020 remain open. PS-1..PS-8 remain deferred to Platform Security. No unresolved legal, cryptographic, key-lifecycle or production authority question is closed by this supplement.

## New open questions raised by the 2026-11-14 implementation (none decided by the implementation)

### OQ-CRD-1 — semantics of the 7-day credit-return window
**Question:** is the window an exact 168-hour interval from the stored activation timestamp (as implemented), or local calendar-day boundaries in Asia/Tehran? Is the boundary inclusive (as implemented)?
**Why it matters:** it decides whether an archive near the edge returns credit.
**Recommended option:** keep the 168-hour inclusive interval — it is timezone-independent and matches "7 calendar days from the original activation timestamp".
**Alternatives:** local midnight boundaries in Asia/Tehran; exclusive boundary.
**Impact:** one comparison in `archive_student_enrollment()` plus CRD-14/15.
**Authority:** Product Owner.

### OQ-CRD-2 — disposition of a reserved entitlement after its original period ends
**Question:** released to the wallet, forfeited, or resolved by a manual adjustment?
**Why it matters:** today such credits stay reserved indefinitely (fail-closed). They are visible in `expired_reserved_entitlements` but nothing releases them.
**Recommended option:** decide before any pilot billing; do not auto-release.
**Impact:** billing reconciliation and counselor trust.
**Authority:** Product Owner with Finance.

### OQ-CRD-3 — source of the entitlement duration
**Question:** where does `period_end` come from — the purchased plan, the product, or each activation?
**Why it matters:** `activate_student_enrollment()` now requires the caller to supply it, so without a decided source every caller invents one.
**Recommended option:** attach it to the purchased plan/product in the billing phase.
**Authority:** Product Owner.

### OQ-SAGA-1 — canonical wire format and signing for Saga envelopes
**Question:** what canonical form and signature protect an envelope between the Control Plane and a Workspace?
**Why it matters:** `payload_hash` is a transport integrity check over the stored jsonb rendering only. It is not `receipt-canon-v1`, not cross-language canonical, and not proof of authenticity.
**Recommended option:** define together with PS-1..PS-4 before any cross-service deployment.
**Authority:** Platform Security.

### OQ-SAGA-2 — resolution of a quarantined inbox event
**Question:** who re-applies an event that was quarantined as too far ahead, once the local projection catches up, and under what authority and audit?
**Why it matters:** quarantined events currently stay quarantined; they are visible but never applied.
**Recommended option:** an operator command with audit, designed together with the OQ-E thresholds.
**Authority:** Product Owner with Operations.

### OQ-ASM-1 — item-bank ownership and the meaning of `item_ref`
**Question:** what is the authoritative question/item source, and what identifier does `item_ref` carry?
**Why it matters:** uniqueness of question membership within a version relies on it; no item bank is modelled in Phase 2.
**Recommended option:** model the item bank when assessment authoring is implemented.
**Authority:** Educational domain owner.
