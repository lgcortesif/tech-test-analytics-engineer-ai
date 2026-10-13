# Model design

Build: `bin/build.py` loads `data/*.csv` into `raw_*` tables (all `TEXT`, with indexes on the lookup
keys) and runs `models/*.sql` in filename order. Full rebuild ≈ 18 s.

```
raw_orders ─► stg_order ─► stg_order_priced ─► fact_order ◄── raw_refunds (aggregated per order)
     │            ▲              ▲   ▲               │
     └► stg_order_duplicates     │   └ raw_platform_fees (as-of)
        (replay audit)           └ raw_fx_rates (as-of)        dim_date · dim_player · dim_title
                                                               dim_studio · bridge_title_studio · dim_platform
```

## 1. Models

| Object | File | Grain | Purpose |
|---|---|---|---|
| `stg_order` | `02` | One row per business `order_id`, **all** statuses and players (109,018) | Canonical order record; replays collapsed |
| `stg_order_duplicates` | `02` | One row per `order_id` landed more than once (2,957) | Replay audit: per-field conflict flags, `has_immutable_conflict`, `has_status_change`, first/last `ingested_at` |
| `stg_order_priced` | `03` | Same as `stg_order` | Adds `rate_to_usd` and `fee_pct` (both as-of the order date) |
| `fact_order` | `04` | One row per **in-scope** order (106,494) | Revenue fact: `gross_usd`, `refund_usd`, `platform_fee_usd`, `net_usd` |

Scope is applied only in `fact_order`. Staging keeps every order, so excluded rows stay inspectable
and a scope change never requires reprocessing staging.

## 2. Dimensions (`01_dimensions.sql`)

| Dimension | Key | Rows | Notes |
|---|---|---:|---|
| `dim_date` | `date` | 822 | 2024-10-01 → 2026-12-31. Calendar attributes plus `fiscal_year`, `fiscal_quarter_no`, `fiscal_month_no`, `is_weekend`. |
| `dim_player` | `player_id` | 45,000 | Includes `email_domain`, which drives the internal-account exclusion. Internal players are kept in the dimension and excluded only from the fact. |
| `dim_title` | `title_id` | 5 | Includes `lead_studio_id`. |
| `dim_studio` | `studio_id` | 4 | |
| `bridge_title_studio` | `(title_id, studio_id)` | 7 | Many-to-many with `credit_role`; T-02 has two studios. **Joining the fact through the bridge fans out revenue.** For single-studio attribution, `dim_title.lead_studio_id` can be used if that matches the reporting policy; otherwise an explicit allocation rule is required before joining revenue through the bridge. |
| `dim_platform` | `platform_code` | 5 | Stub: distinct codes from orders only. The fee history lives in `raw_platform_fees`, read directly by `03`. |

The dimensions are straight copies of the landing tables. Only `dim_date` contains logic; `dim_platform` is derived from orders.

## 3. Grain and join safety

- **No line-item join into `fact_order`.** Order-level money was previously repeated once per line;
  the fact now reads only from `stg_order_priced`.
- **Refunds are aggregated before joining.** A CTE groups `raw_refunds` to one row per `order_id`,
  then `LEFT JOIN`s it. Today there is one refund per order, but the aggregation keeps the join safe
  if partial refunds ever arrive in several rows.
- **FX and fee are scalar lookups** (`… ORDER BY … LIMIT 1`), so they cannot add rows.
  `stg_order_priced` row count = `stg_order` row count.
- **`UNIQUE` indexes on `stg_order(order_id)` and `fact_order(order_id)`.** A broken grain fails the
  build itself, not just a downstream test.

## 4. Replay handling

- **Latest ingestion wins:** `ROW_NUMBER() OVER (PARTITION BY order_id ORDER BY ingested_at DESC, rowid DESC) = 1`.
- **Immutable-field conflicts are audited, not resolved silently.** `stg_order_duplicates` checks
  player, title, platform, `order_ts`, currency and gross separately: more than one distinct value,
  *or* a mix of NULL and non-NULL, counts as a conflict. t13 fails on any `has_immutable_conflict = 1`.
  Today there are 0.
- **Status-only changes are lifecycle updates** (e.g. pending → completed). They are flagged as
  `has_status_change`; they do not fail t13, and the latest status is used.

## 5. Revenue logic

| Rule | Implementation |
|---|---|
| Scope | `order_status IN ('completed','refunded')`, excluding players with `email_domain = 'twinhearth.test'` (non-correlated `NOT IN` with an `IS NOT NULL` guard) |
| FX | USD → `1.0`. Other currencies → the latest `raw_fx_rates.rate_date <= order_date` (weekend orders take Friday's rate). |
| Platform fee | The `raw_platform_fees` row with `effective_from <= order_date` and `effective_to` empty or `>= order_date` |
| Refunds | `raw_refunds` summed per order (full and partial), converted at the order's own rate, attributed to the order date |
| Measures | `gross_usd = gross × rate`; `refund_usd = refund × rate`; `platform_fee_usd = (gross − refund) × rate × fee`; `net_usd = (gross − refund) × rate × (1 − fee)` |

`gross_usd − refund_usd − platform_fee_usd = net_usd` holds on every row (t10). The fact stores USD
only; local amounts, `currency_code` and the applied `rate_to_usd` / `fee_pct` are in
`stg_order_priced` for audit.

## 6. Fiscal calendar

The fiscal year starts on 1 October: `fiscal_month_no = (calendar_month + 2) % 12 + 1` (Oct = 1 …
Sep = 12) and `fiscal_quarter_no = (calendar_month + 2) % 12 / 3 + 1`. **FY2026 Q2 = 2026-01-01 →
2026-03-31.** The `+ 2` form keeps the operand positive. SQLite's `%` keeps the sign of the dividend,
which made the previous `month − 10` form negative for Jan–Sep.

## 7. Intentionally not modelled

- **`settlement_date`.** The policy says payout delays vary by store (30–60 days), and no landing
  field or lookup holds the terms or dates, so the former `order_date + 30` was removed rather than
  invented. Cash reporting needs per-store payout terms or payout reports.
- **Line-level revenue.** Line items reconcile to order gross, but Finance has no rule for
  allocating fees and refunds to lines. Revenue stays at order grain; nothing currently reads
  `item_type`.
- **Incremental processing.** Every build is a full rebuild, which is adequate at this volume. At
  hourly loads and 50× volume, `stg_order` would become a merge on `order_id` using `ingested_at` as
  the watermark, replay conflicts would block publishing, and `fact_order` would be recomputed only
  for orders with new order or refund rows. The as-of lookups are already index-backed.

## 8. Validation

| Layer | Tests |
|---|---|
| Grain / replays | t01, t13, plus the `UNIQUE` indexes |
| Scope | t03; internal-account exclusion also covered end-to-end by t12 |
| Referential integrity | t02, t04 |
| Measures | t05, t06, t08, t09, t10 |
| Calendar | t07, t11 |
| End-to-end | t12 |

**13/13 tests pass. FY2026 Q2 net revenue = $328,697.94.**
