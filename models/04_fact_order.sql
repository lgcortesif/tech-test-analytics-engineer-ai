-- The revenue fact. Grain: one row per order in stg_order_priced (one per business order_id).
-- Order-level measures only: no child table (line items, refund rows) is joined here, so no
-- measure can be repeated. Line-item detail, if needed, belongs in its own line-grain table.
-- Reporting scope (REVENUE_POLICY.md "Scope"): completed orders from real players. Refunded orders
-- are completed orders that were later refunded, so they stay in. Internal/test/QA accounts are
-- identified by email_domain = 'twinhearth.test'. stg_order keeps every order; scope applies here.
-- FX, fee, refund, fiscal and settlement rules are intentionally unchanged in this step.

DROP TABLE IF EXISTS fact_order;
CREATE TABLE fact_order AS
SELECT p.order_id,
       p.order_date,
       date(p.order_date, '+30 day')                          AS settlement_date,
       p.player_id,
       p.title_id,
       p.platform_code,
       p.order_status,
       p.gross_local * p.rate_to_usd                          AS gross_usd,
       p.gross_local * p.rate_to_usd * p.fee_pct              AS platform_fee_usd,
       CASE WHEN p.order_status = 'refunded'
            THEN p.gross_local * p.rate_to_usd ELSE 0 END     AS refund_usd,
       CASE WHEN p.order_status = 'refunded' THEN 0
            ELSE p.gross_local * p.rate_to_usd * (1 - p.fee_pct) END AS net_usd
FROM stg_order_priced p
WHERE p.order_status IN ('completed', 'refunded')
  AND p.player_id NOT IN (SELECT d.player_id FROM dim_player d
                          WHERE d.email_domain = 'twinhearth.test'
                            AND d.player_id IS NOT NULL);

CREATE UNIQUE INDEX ux_fact_order ON fact_order(order_id);
