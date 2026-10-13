-- net_usd equals gross_usd - refund_usd - platform_fee_usd on every fact row
-- REVENUE_POLICY.md "Net revenue": net = (gross - refunds) net of the platform fee, and the platform
-- refunds its fee with the refund. The four measures must therefore tie out on each order. Guards the
-- observed defect where fully refunded orders kept the whole platform fee while net was forced to 0,
-- and any future change that updates one measure without the others. NULL in any measure also fails,
-- since a NULL would silently drop out of the identity (t05 does not cover refund_usd).
SELECT order_id, order_status, gross_usd, refund_usd, platform_fee_usd, net_usd,
       gross_usd - refund_usd - platform_fee_usd - net_usd AS residual_usd
FROM fact_order
WHERE gross_usd IS NULL OR refund_usd IS NULL OR platform_fee_usd IS NULL OR net_usd IS NULL
   OR ABS(gross_usd - refund_usd - platform_fee_usd - net_usd) > 1e-6;
