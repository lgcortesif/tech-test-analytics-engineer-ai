-- platform fee is the contract rate in force on the order's own order_date
-- REVENUE_POLICY.md "Net revenue": each store's cut changes over time and the rate in force on the
-- order date applies. Guards the observed defect where every order took the newest schedule row
-- (XBOX 0.12 from 2026-04-01 applied to Q2 orders contracted at 0.30; STEAM 0.25 applied pre-2026).
-- The applied rate is read back from the fact as fee / (gross - refund), so the check holds both
-- before and after refunds are netted. Fully refunded orders have no fee base and are skipped here.
-- Also fails if an order matches zero or several schedule rows (gap or overlap in the contract).
WITH expected AS (
    SELECT f.order_id,
           f.platform_code,
           f.order_date,
           COUNT(pf.platform_code)          AS n_schedule_rows,
           MAX(CAST(pf.fee_pct AS REAL))    AS expected_fee_pct
    FROM fact_order f
    LEFT JOIN raw_platform_fees pf
           ON pf.platform_code   = f.platform_code
          AND pf.effective_from <= f.order_date
          AND (NULLIF(pf.effective_to, '') IS NULL OR f.order_date <= pf.effective_to)
    GROUP BY f.order_id, f.platform_code, f.order_date
)
SELECT e.order_id, e.platform_code, e.order_date, e.n_schedule_rows, e.expected_fee_pct,
       f.platform_fee_usd / NULLIF(f.gross_usd - f.refund_usd, 0) AS applied_fee_pct
FROM expected e
JOIN fact_order f ON f.order_id = e.order_id
WHERE e.n_schedule_rows <> 1
   OR ABS(f.platform_fee_usd / NULLIF(f.gross_usd - f.refund_usd, 0) - e.expected_fee_pct) > 1e-6;
