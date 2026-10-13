-- refund_usd reconciles to raw_refunds for every order, including partial refunds on completed orders
-- REVENUE_POLICY.md "Refunds": the refunds table is the system of record; it holds full and partial
-- refunds, and a partially refunded order is still a completed order. Guards the observed defect
-- where refund_usd was derived from order_status = 'refunded' (full gross) and raw_refunds was never
-- read, so partial refunds (goodwill, price adjustments) on completed orders counted as zero.
-- Refunds are attributed to the order and converted at the order's own rate (revenue view).
WITH refunds AS (
    SELECT order_id, SUM(CAST(refund_amount_local AS REAL)) AS refund_local
    FROM raw_refunds
    GROUP BY order_id
)
SELECT f.order_id, f.order_status, p.currency_code,
       COALESCE(r.refund_local, 0)                    AS raw_refund_local,
       f.refund_usd / NULLIF(p.rate_to_usd, 0)        AS fact_refund_local
FROM fact_order f
JOIN stg_order_priced p ON p.order_id = f.order_id
LEFT JOIN refunds r     ON r.order_id = f.order_id
WHERE f.refund_usd IS NULL
   OR ABS(f.refund_usd - COALESCE(r.refund_local, 0) * p.rate_to_usd) > 0.005;
