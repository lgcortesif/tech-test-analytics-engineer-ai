-- Convert to USD and attach the platform fee.
-- FX (REVENUE_POLICY.md "Currency"): USD orders need no conversion (rate 1.0). Other currencies use
-- the last rate published on or before the order date; rates exist for business days only, so a
-- weekend order takes Friday's rate. Scalar lookup (LIMIT 1), served by ix_raw_fx: cannot fan out.
-- Fees come from the platform fee schedule.

DROP TABLE IF EXISTS stg_order_priced;
CREATE TABLE stg_order_priced AS
SELECT s.*,
       CASE WHEN s.currency_code = 'USD' THEN 1.0
            ELSE (SELECT CAST(fx.rate_to_usd AS REAL)
                    FROM raw_fx_rates fx
                   WHERE fx.currency_code = s.currency_code
                     AND fx.rate_date    <= s.order_date
                   ORDER BY fx.rate_date DESC
                   LIMIT 1)
       END                                               AS rate_to_usd,
       (SELECT CAST(pf.fee_pct AS REAL)
          FROM raw_platform_fees pf
         WHERE pf.platform_code = s.platform_code
         ORDER BY pf.effective_from DESC
         LIMIT 1)                                        AS fee_pct
FROM stg_order s;

CREATE INDEX ix_stg_order_priced ON stg_order_priced(order_id);
