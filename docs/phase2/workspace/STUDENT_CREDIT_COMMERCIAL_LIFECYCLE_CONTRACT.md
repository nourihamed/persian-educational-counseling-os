# Student Credit Commercial Lifecycle Contract — Phase 2

**Status:** DRAFT / NOT APPROVED. Domain and ledger boundary only. No price, refund entitlement, payment provider or financial retention period is selected. Synthetic data only (D-014).

## 1. Separation of money and Student Credit

- Fiat money, orders, subscriptions, invoices, payment attempts and provider webhooks belong to the billing/commercial domain.
- Student Credit is a non-fiat Workspace-owned entitlement unit with unit_code='CRD'.
- Each Workspace has its own wallet. Credits never move between Workspaces, including during student transfer.
- Payment success does not directly grant credits from a client request. A trusted billing service verifies the signed provider event and creates an idempotent, auditable credit-grant command.
- Wallet balance is derived from the append-only ledger; a cached balance projection must be reconcilable to the ledger.

## 2. Required commercial entities

- Product and product version;
- Plan and plan version;
- Workspace subscription and entitlement snapshot;
- Order and immutable order lines;
- Payment attempt/provider reference and verified webhook event;
- Invoice/credit note or other jurisdiction-required financial document;
- Coupon/promotion with eligibility and usage ledger;
- Workspace Student Credit wallet;
- append-only CreditTransaction ledger;
- credit purchase/grant/debit/reversal/refund/expiry adjustment command records.

The current Workspace wallet/transaction schema covers only part of this lifecycle. It must not be treated as a complete billing model.

## 3. Ledger invariants

- Every transaction is immutable and uniquely idempotent.
- Every transaction references exactly one Workspace wallet and CRD unit; no fiat amount is stored as CRD.
- Debits cannot make balance negative.
- Reversal is a compensating ledger entry referencing the exact original transaction; it never edits/deletes the original.
- An original transaction can be reversed at most once unless a separately approved partial-reversal model is designed.
- Purchase/grant credits only after verified billing evidence; manual grants require authorized actor, reason, approval and audit.
- Activation debit, capacity reservation and enrollment activation remain one Workspace DB transaction.
- A student transfer never transfers or refunds the source Workspace's credit balance automatically.
- All commercial and credit commands use idempotency keys bound to canonical payload hashes.

## 4. Reconciliation and refunds

- Provider webhook signature, merchant/account, amount, currency, order, event ID and replay window are verified by the billing service.
- Payment and credit grant are separate states connected by a durable command/outbox; a delayed grant is retried idempotently.
- Refund, chargeback, cancellation and subscription expiry do not silently edit credit history.
- Refund eligibility, timing, fees, partial refunds, credit clawback and treatment of already-consumed credits require Product Owner/finance/legal policy before implementation.
- If a refund requires credit removal, use a compensating transaction; if the debit would make balance negative, route to an explicit receivable/adjustment policy rather than violating ledger invariants.
- Invoices and tax/accounting artifacts follow the approved jurisdictional retention policy; no numeric duration is invented.

## 5. Required tests

1. Verified payment event grants credits once; webhook replay does not duplicate.
2. Invalid signature, wrong amount/currency/merchant/order or reused provider event is rejected.
3. Same idempotency key/same payload replays; changed payload rejects.
4. Workspace A payment cannot grant Workspace B wallet credits.
5. Credit transaction cannot be updated/deleted; reversals are exact, same-wallet and single-use.
6. Debit cannot create negative balance under concurrent transactions.
7. Activation debit/capacity/enrollment failure rolls back together.
8. Refund/chargeback follows approved policy and uses compensating entries.
9. Subscription/entitlement expiry does not rewrite historical wallet transactions.
10. Wallet projection reconciles exactly to append-only ledger.
11. Transfer does not move wallet balance or source financial records across Workspaces.
12. Finance exports enforce Workspace scope and audit.

All tests remain NOT IMPLEMENTED / NOT RUN beyond the current synthetic wallet/activation tests.

## 6. Open decisions

- Product pricing, credit package sizes, expiry policy and purchase conversion.
- Refund/cancellation/chargeback and consumed-credit treatment.
- Manual credit grant authority and dual-approval thresholds.
- Subscription entitlements and renewal/failed-payment grace behavior.
- Invoice/tax requirements and responsible legal/finance reviewer.

**Gate impact:** Credit activation/debit foundation exists in draft SQL, but commercial lifecycle remains incomplete. Phase 2 remains NOT READY.

## Product Owner decision overlay — 2026-11-13: archive and reactivation

- Archive within **7 calendar days from the original activation timestamp** qualifies for a compensating credit-return entry.
- After that 7-day window, no automatic credit return is allowed.
- Free reactivation of the same student is allowed only until the end of the **original entitlement period**. Archiving/reactivating does not restart or extend that period.
- A returned credit backing free reactivation must be recorded as a student-bound reserved entitlement. It must not simultaneously increase generally spendable wallet balance or be usable for another student's activation.
- The ledger remains append-only. The original activation debit is never edited/deleted; return is a separate idempotent compensating entry bound to the original debit, student and entitlement.
- If the original entitlement period has ended, reactivation requires a new credit debit under the applicable policy.

The exact entitlement representation and atomic archive/reactivation/debit/capacity transaction remain implementation requirements and must be tested for concurrency and double-use. This does not approve checkout, payment provider, or full refund/chargeback implementation.

## Implementation status — 2026-11-14 (draft SQL, synthetic; not an approval)

Implemented: `student_entitlements` (student, original debit, amount, activation time, period end, state,
compensating reversal) with an immutability guard that makes the period impossible to restart or extend;
`credit_wallet_balances` where `available = ledger − reserved − recommitted`; a reserved-aware debit guard so
a returned credit can never fund another student; archive inside the window writing exactly one compensating
reversal; `reactivate_student_enrollment()` consuming the SAME returned credit with no new debit, one
capacity slot and full rollback on failure; `expired_reserved_entitlements` for visibility.

Window semantics as implemented: an exact 168-hour interval from the stored activation timestamptz, boundary
inclusive, independent of the session time zone. This is recorded as OQ-CRD-1, not assumed to be final.

The entitlement duration is NOT chosen by the database: `activate_student_enrollment()` requires the caller
to supply `p_entitlement_period_end` and refuses an activation without a future period (OQ-CRD-3).

Still open: what happens to a reserved entitlement once its period ends (OQ-CRD-2); purchase, renewal,
refund and chargeback execution; the payment reconciliation boundary. None of these is implemented.

Tests: CRD-01..CRD-27, WS-REACT-RACE-01, ARC-01..17 (executed).
