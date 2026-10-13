-- The revenue fact. Grain: one row per order in stg_order_priced (one per business order_id).
-- Order-level measures only: line items are never joined here, and refunds are joined only after
-- aggregation to one row per order_id, so no measure can be repeated. Line-item detail, if needed,
-- belongs in its own line-grain table.
-- Reporting scope (REVENUE_POLICY.md "Scope"): completed orders from real players. Refunded orders
-- are completed orders that were later refunded, so they stay in. Internal/test/QA accounts are
-- identified by email_domain = 'twinhearth.test'. stg_order keeps every order; scope applies here.
-- Refunds (REVENUE_POLICY.md "Refunds"): raw_refunds is the system of record, full and partial; a
-- partially refunded order stays completed. Refunds are attributed to the order (revenue view) and
-- converted at the order's own rate. The platform refunds its fee with them, so fee and net are
-- computed on gross - refund.
-- Settlement timing is intentionally not modeled: REVENUE_POLICY.md "Settlement" says the payout delay
-- varies by store (30 to 60 days), and no landing field or lookup provides the actual terms or dates.

DROP TABLE IF EXISTS fact_order;
CREATE TABLE fact_order AS
WITH refunds AS (
    SELECT order_id, SUM(CAST(refund_amount_local AS REAL)) AS refund_local
    FROM raw_refunds
    GROUP BY order_id
)
SELECT p.order_id,
       p.order_date,
       p.player_id,
       p.title_id,
       p.platform_code,
       p.order_status,
       p.gross_local * p.rate_to_usd                          AS gross_usd,
       (p.gross_local - COALESCE(r.refund_local, 0)) * p.rate_to_usd * p.fee_pct       AS platform_fee_usd,
       COALESCE(r.refund_local, 0) * p.rate_to_usd                              AS refund_usd,
       (p.gross_local - COALESCE(r.refund_local, 0)) * p.rate_to_usd * (1 - p.fee_pct) AS net_usd
FROM stg_order_priced p
LEFT JOIN refunds r ON r.order_id = p.order_id
WHERE p.order_status IN ('completed', 'refunded')
  AND p.player_id NOT IN (SELECT d.player_id FROM dim_player d
                          WHERE d.email_domain = 'twinhearth.test'
                            AND d.player_id IS NOT NULL);

CREATE UNIQUE INDEX ux_fact_order ON fact_order(order_id);
