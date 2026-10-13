# FINDINGS — FY2026 Q2 net revenue

## 1. Executive summary

**FY2026 Q2 net revenue is $328,697.94** (16,188 orders, 2026-01-01 → 2026-03-31).

The delivered pipeline overstated it. The reconstructed baseline — `SUM(net_usd)` over order dates
Jan–Mar 2026 in the delivered `fact_order` — is **$727,922.09**, i.e. **$399,224.15 too high
(+121.5% vs. correct; the correct figure is 54.8% below the baseline)**. We do not know the exact
query behind leadership's number; this is the most direct reading of the delivered fact.

Ten issues were identified: eight revenue-calculation defects, one fiscal-calendar defect that broke
quarter selection, and one unsupported settlement-date field that created cash-reporting risk. Each
was fixed one at a time. The corrected figure was first derived **independently from the raw landing
tables** (no models), then the pipeline was repaired step by step until it matched, by title, to the
cent.

The original 7 tests could not have caught most of this: after the grain, scope and FX fixes, **all
7 passed at $349,494.13 — still $20,796.19 (6.3%) too high.** Six regression tests (t08–t13) were
added; each validated against the defect it guards. Suite: **13/13 passing.**

Reproduce on a clean checkout: python3 bin/run.py (expected: 13/13 checks passing, exit 0). (Windows: `py bin/run.py`)

## 2. FY2026 Q2 result (USD)

| Title | Orders | Gross | Refunds | Platform fee | **Net** |
|---|---:|---:|---:|---:|---:|
| T-01 Hollow Crown | 5,466 | 210,149.73 | 9,672.39 | 51,954.23 | **148,523.10** |
| T-02 Hollow Crown: Ashen Tide | 3,056 | 68,593.47 | 3,435.76 | 16,852.63 | **48,305.08** |
| T-03 Lantern & Lock | 2,560 | 39,221.18 | 1,510.01 | 9,782.99 | **27,928.18** |
| T-04 Saltmarsh Rally | 2,662 | 64,620.06 | 2,829.06 | 16,018.43 | **45,772.57** |
| T-05 Emberwatch Tactics | 2,444 | 81,650.77 | 3,138.33 | 20,343.43 | **58,169.01** |
| **Total** | **16,188** | **464,235.20** | **20,585.55** | **114,951.71** | **328,697.94** |

Selected through `dim_date` (`fiscal_year = 'FY2026' AND fiscal_quarter_no = 2`); identical by
order date. `gross − refund − fee = net` holds on every fact row (max residual 2.8e-14).

## 3. Defects

**Leave-one-out Q2 sensitivity** = the Q2 error if **only that defect** were reintroduced into the
corrected pipeline (sign = the direction it pushed the reported number). These values overlap and
**are not additive** — see §4–5 for the sequential attribution.

| # | Defect | Evidence (how found) | Leave-one-out Q2 sensitivity | Fix | Regression guard |
|---|---|---|---|---|---|
| 1 | **Item fan-out.** `fact_order` joined order-level money to `raw_order_items`, repeating every measure once per line. | 109,018 orders → 174,089 fact rows. The original grain test's 43,680 offenders = exactly the orders with ≥2 lines. In Q2, 11,172 of 19,480 raw rows had >1 line (+18,140 rows). | **+$350,690.54 (+106.7%)** | Removed the item join; fact is one row per order. | `UNIQUE` index on `fact_order(order_id)` fails the build; t01; t12 |
| 2 | **Replayed orders.** The March 2026 re-extract (HANDOVER: "re-running the extract") landed 2,957 orders twice. | 2,957 `order_id`s × 2 copies, identical except `ingested_at`; every one dated March 2026. Their line items were duplicated too (4,392 pairs). 0 field conflicts, 0 status changes. | **+$59,171.01 (+18.0%)** | `stg_order` keeps one row per `order_id` (latest ingestion). `stg_order_duplicates` records per-field conflicts, NULL-safe, with status changes kept separate from immutable-field conflicts. | `UNIQUE` index on `stg_order(order_id)`; **t13** (immutable replay conflicts); t12 |
| 3 | **Pending orders in revenue.** No status filter. | 1,602 pending orders in the fact (235 in Q2); none has a refund row. | **+$5,017.54 (+1.5%)** | Status allow-list `('completed','refunded')` in `fact_order`. | t03 (existing) |
| 4 | **Internal/test accounts in revenue.** Policy: excluded "from every reported metric". | 10 players on `twinhearth.test`, 922 eligible orders (100 in Q2). They are the 10 heaviest buyers (67–123 orders each); no other player exceeds 20. | **+$24,313.07 (+7.4%)** | Exclude `email_domain = 'twinhearth.test'` in `fact_order`; `stg_order` keeps every order. | t12 (no dedicated test — §12) |
| 5 | **Weekend FX dropped.** Exact-date FX join; the rate file has business days only. | 0 weekend rows in `fx_rates`. Every NULL-rate order was a Saturday or Sunday (6,045 in Q2). `SUM()` silently skipped their NULL net. | **−$66,861.49 (−20.3%)** | Scalar as-of lookup: latest `rate_date <= order_date` (Sat → Fri, 1 day; Sun → Fri, 2 days). Index-backed. | t05 (existing); t12 |
| 6 | **USD "converted".** USD orders took the file's USD rate. | `fx_rates` has USD rows at 0.897–1.031 (Q2 average 0.9316) applied to 7,216 in-scope Q2 USD orders. Policy converts only "Non-USD orders". | **−$10,147.21 (−3.1%)** | `rate_to_usd = 1.0` for USD. | t12 (assumption A2) |
| 7 | **Platform fee not effective-dated.** Took the newest schedule row for every order. | Every STEAM order got 0.25 and every XBOX order 0.12. t08 found 31,106 fact orders wrong (STEAM pre-2026, XBOX through 2026-03-31). In Q2 only XBOX was wrong (0.12 vs 0.30). | **+$14,587.18 (+4.4%)** | `effective_from <= order_date AND (effective_to empty OR >= order_date)`; open-ended rows handled (the loader stores them as `''`). | **t08** |
| 8 | **Refunds not from the system of record.** `raw_refunds` was never read; refunds were inferred from `order_status = 'refunded'`. | 4,793 `completed` fact orders carry partial refunds (goodwill, price adjustments) that counted as 0 (759 in Q2). The 2,838 `refunded` orders kept their full platform fee while net was forced to 0, contradicting "the platform refunds its fee". | **+$5,974.98 (+1.8%)** | Aggregate `raw_refunds` to one row per order before joining; convert at the order's rate; fee and net on `gross − refund`. | **t09**, **t10** |
| 9 | **Fiscal quarter/month wrong in `dim_date`.** | SQLite `%` keeps the sign of the dividend: Jan → Q−2 / M−8; no date had Q2 (§8). | Revenue $0; **Q2 via `dim_date` returned $0** | `(month + 2) % 12` formula. | **t11** |
| 10 | **Invented `settlement_date`.** `order_date + 30` for every store. | Policy: delay "varies by store (30 to 60 days)". No landing field or lookup holds payout terms or dates (§9). | Revenue $0; cash-reporting risk | Column removed; comment explains why. | — (nothing references it) |

## 4. Bridge: reconstructed baseline → correct Q2 (fixed order)

One parameterised calculation; each step turns one fix on. All fixes off reproduces $727,922.09;
all on reproduces $328,697.94.

| Step | Rule changed | Q2 net after | Delta | % of correct | Defect pushed the number |
|---|---|---:|---:|---:|---|
| 0 | Reconstructed baseline (delivered fact, Jan–Mar order dates) | 727,922.09 | | | |
| 1 | Remove item fan-out | 282,437.98 | −445,484.11 | −135.53% | up |
| 2 | Deduplicate replayed orders | 236,197.35 | −46,240.63 | −14.07% | up |
| 3 | Exclude pending | 232,928.87 | −3,268.48 | −0.99% | up |
| 4 | Exclude internal accounts | 213,992.39 | −18,936.48 | −5.76% | up |
| 5 | As-of FX (weekends) | 338,724.07 | +124,731.69 | +37.95% | down |
| 6 | USD = 1.0 | 349,494.13 | +10,770.06 | +3.28% | down |
| 7 | Effective-dated platform fee | 334,672.91 | −14,821.22 | −4.51% | up |
| 8 | Refunds from `raw_refunds` | **328,697.94** | −5,974.98 | −1.82% | up |
| | **Total** | | **−399,224.15** | **−121.46%** | |

The fiscal-calendar defect is not a step: the bridge selects Q2 by order date, so it cannot show it.
Its effect is on selection (§8).

## 5. Why these numbers overlap

The defects interact: fan-out multiplies every other error, and the NULL-FX rows hide the orders
other defects act on. Consequences:

- **Sequential deltas depend on the order.** Running the same eight fixes in reverse moves every
  step — replays go from −46,241 to −206,895, FX from +124,732 to +200,320 — while the total stays
  −399,224.15. §4 is one attribution (grain → scope → pricing), not intrinsic sizes.
- **Leave-one-out sensitivities (§3) are not additive.** They sum to +$382,745.62, not the
  $399,224.15 gap. Fixing a single defect *on the baseline* is worse still (e.g. replays alone:
  −$180,688.63), because fan-out amplifies it about 2–4×.
- The offsetting directions (FX and USD pushed down; everything else up) partly cancelled. That is
  one reason "the numbers don't feel right" was hard to turn into a defect report.

## 6. Gaps in the original test suite

| Test | Gap |
|---|---|
| t01 grain | Compared fact rows to the **raw** row count, which includes the replays, so duplicated orders passed. |
| t02 orphans | True by construction (the fact is built from raw); never checked the reverse (missing orders). |
| t03 pending | Matched only the literal `'pending'`, not an allowed-status list. |
| t04 RI | No platform check; nothing about internal accounts. |
| t05 NULL money | Did catch the weekend-FX symptom (it was failing), but nothing upstream checked rates. |
| t06 | Gross ≥ 0 only; nothing on refund ≤ gross or net. |
| t07 | Checked that dates exist, not that fiscal attributes are right. |
| — | **No test checked money**: fee rate, refunds, measure identity or a reference total. |

Shape checks only. Once the shape was fixed, the money could still be wrong with every test green.

## 7. Regression tests added (t08–t13)

Each guard was validated against the defect it targets; where the source data did not contain a real example, the guard was mutation-tested on a scratch copy.

| Test | Guards | Validation evidence |
|---|---|---|
| **t08** platform fee in force on the order's own date; exactly one schedule row matches | #7 (and schedule gaps/overlaps) | 31,106 rows |
| **t09** `refund_usd` reconciles to `raw_refunds`, including partial refunds on completed orders | #8 | 4,793 rows |
| **t10** `gross − refund − fee = net` on every row; NULL in any measure also fails; tolerance 1e-6 USD | #8 (fee not refunded), and any measure updated alone | 2,838 rows |
| **t11** fiscal year/quarter/month match an explicit month lookup, not the formula under test | #9 | 546 rows (every Jan–Sep date) |
| **t12** FY2026 Q2 net by title and total, selected via `dim_date`, against the independent reference; tolerance half a cent + 1e-6 | Any regression in #1–#9 | Fails with a per-title diff when any fix is reverted, e.g. fee reverted: TOTAL +$14,587.18 (+4.44%); fiscal reverted: every title −100% |
| **t13** replayed `raw_orders` copies never disagree on immutable business fields (player, title, platform, order timestamp, currency, gross; NULL vs value counts as a difference); status-only lifecycle changes remain allowed | #2 (a conflicting replay silently resolved by "latest ingestion wins") | Current data: 0 conflicts, passes. Synthetic validation on a scratch copy: a gross conflict and a NULL-vs-value currency conflict were caught (2 rows); a status-only change and an exact replay were not |

t12 is not circular: the reference was derived from `raw_*` only, with separately written logic
(different dedup choice, FX and fee lookups, date-range Q2), before any model was fixed. It shares
the policy interpretation (§10), so it guards regressions, not interpretation.

Build-time guards: `UNIQUE` indexes on `stg_order(order_id)` and `fact_order(order_id)` stop the build
if the grain ever breaks.

## 8. Fiscal calendar: why Q2 via `dim_date` returned $0

`fiscal_quarter_no = ((month − 10) % 12) / 3 + 1`. In SQLite `%` keeps the sign of the dividend and
integer `/` truncates toward zero, so January gives `(−9 % 12) = −9 → −3 → −2`. Only Oct–Dec were
right; Jan–Sep were negative (Jan Q−2, Feb–Apr Q−1, May–Jul Q0, Aug–Sep Q1). **No date had
quarter 2**, so `fiscal_year = 'FY2026' AND fiscal_quarter_no = 2` returned **0 rows, $0**. Anyone
falling back to calendar Q2 (Apr–Jun) on the delivered fact would have reported $561,002.34.
Fix: `(month + 2) % 12`, which is never negative. FY2026 now maps Q1 Oct–Dec (92 days), Q2 Jan–Mar
(90), Q3 Apr–Jun (91), Q4 Jul–Sep (92), with fiscal months 1–12. Q2 via `dim_date` = $328,697.94.

## 9. `settlement_date` removed

The delivered fact set `settlement_date = order_date + 30` for every order. The policy says stores
"pay out on a delay that varies by store (30 to 60 days)" (REVENUE_POLICY.md, Settlement) and warns
that mixing revenue and cash dates is "the single most common source" of bank escalations. No landing
file contains payout terms, payout dates or settlement reports, and `dim_platform` is a stub. The
column was therefore invented, and as the minimum delay it would bias any cash view towards early
receipt. It was removed rather than nulled (no object in the repo references it). No revenue effect.
Modelling settlement properly needs per-store payout terms (effective-dated, like fees) or store
payout reports.

## 10. Assumptions Finance should confirm

These are interpretations, not confirmed defects. The headline number depends on them.

| # | Assumption | Evidence / sensitivity |
|---|---|---|
| A1 | Internal/test/QA accounts = `email_domain = 'twinhearth.test'` | No staff list in the data. The 10 accounts are clear outliers (67–123 orders vs ≤20). |
| A2 | USD orders are not converted (rate 1.0) | Policy converts "Non-USD orders". Using the file's USD rates instead: **−$10,147.21 (−3.1%)**. Why the file has USD rows should go to its owner. |
| A3 | Refunds convert at the **order-date** rate | Revenue attributes refunds to the order date. Refund-date rate instead: +$9.59. |
| A4 | Partial refunds return the platform fee pro rata: fee = (gross − refund) × fee_pct | Policy: "the platform refunds its fee along with them". |
| A5 | `order_ts` is already in the reporting timezone | No timezone field. 298 in-scope orders fall within 12 h of a Q2 boundary. |
| A6 | Refunds landing after quarter end restate that quarter (revenue view) | 272 Q2 orders were refunded after March. Future refunds on Q2 orders will move Q2. |
| A7 | `refunded` status = a completed order with a full refund (kept in scope, net 0) | All 2,838 have refund = gross. |
| A8 | `effective_to` is inclusive | Boundary days checked: STEAM 2025-12-31 = 0.30, 2026-01-01 = 0.25; XBOX 2026-03-31 = 0.30, 2026-04-01 = 0.12. |
| A9 | Gross = order header `gross_amount_local` | After dedup, Σ line items = header gross for every order. |
| A10 | Replays resolve to the latest ingestion | No conflicting copies today, so the choice does not change the number. |

## 11. Smaller than expected

**Refunds: $5,974.98 (1.8%).** The refunds table was never read, so this looked like a large defect.
But all 2,838 `refunded`-status orders are full refunds, so the status shortcut happened to be right
for them; only the 759 partial refunds on completed Q2 orders mattered. The fee defect was similarly
contained: STEAM's rate change (0.30 → 0.25 on 2026-01-01) has no Q2 effect, so all of its Q2 impact
is XBOX.

## 12. What I did not fix, and why

- **No dedicated tests for scope (internal accounts) or FX policy (USD = 1, rate age).** They are
  covered only by t12. Worth adding before data volume grows.
- **Settlement / cash view.** Needs inputs that do not exist (§9). Refund cash dating (`refund_ts`)
  belongs to that view, not the revenue fact.
- **Line-item analysis.** No `fact_order_line` built: lines reconcile to gross, but Finance has no
  rule for allocating fees and refunds to lines, and nothing reads `item_type`.
- **`dim_platform` remains a stub.** It is the natural home for payout terms once they exist.
- **Incremental, hourly, 50× volume.** Not built (full rebuild still runs in ~18 s). Design: merge
  `stg_order` on `order_id` with `ingested_at` as the watermark; turn `stg_order_duplicates` into a
  quarantine that blocks publishing; keep FX and fee lookups as indexed as-of lookups; recompute
  `fact_order` only for orders touched by new orders or new refunds.
