-- FY2026 Q2 net revenue by title and total matches the independently derived reference values
-- Reference values come from a separate calculation built directly on the raw_* landing tables (no
-- models, no fact_order) under REVENUE_POLICY.md, and were reconciled defect by defect against the
-- delivered pipeline's $727,922.09. FY2026 Q2 is selected through dim_date, so a broken fiscal
-- calendar fails here too. Expected values are rounded to the cent, so the tolerance is half a cent
-- plus floating-point noise. Each offending row names the title (or TOTAL) and the difference.
-- If landing data legitimately changes (e.g. a late refund on a Q2 order), re-derive the reference
-- independently before updating these values; never copy them from the pipeline.
WITH expected(title_id, expected_net_usd) AS (
    VALUES ('T-01', 148523.10),
           ('T-02',  48305.08),
           ('T-03',  27928.18),
           ('T-04',  45772.57),
           ('T-05',  58169.01),
           ('TOTAL', 328697.94)
),
q2 AS (
    SELECT f.title_id, f.net_usd
    FROM fact_order f
    JOIN dim_date d ON d.date = f.order_date
    WHERE d.fiscal_year = 'FY2026' AND d.fiscal_quarter_no = 2
),
actual AS (
    SELECT title_id, SUM(net_usd) AS actual_net_usd FROM q2 GROUP BY title_id
    UNION ALL
    SELECT 'TOTAL', SUM(net_usd) FROM q2
),
compared AS (
    SELECT e.title_id, e.expected_net_usd, a.actual_net_usd
    FROM expected e LEFT JOIN actual a ON a.title_id = e.title_id
    UNION ALL
    SELECT a.title_id, NULL, a.actual_net_usd          -- a title the reference does not know about
    FROM actual a WHERE a.title_id NOT IN (SELECT title_id FROM expected)
)
SELECT title_id,
       expected_net_usd,
       ROUND(actual_net_usd, 2)                                    AS actual_net_usd,
       ROUND(COALESCE(actual_net_usd, 0) - COALESCE(expected_net_usd, 0), 2) AS diff_usd,
       ROUND(100.0 * (COALESCE(actual_net_usd, 0) - expected_net_usd) / expected_net_usd, 3) AS diff_pct
FROM compared
WHERE actual_net_usd IS NULL
   OR expected_net_usd IS NULL
   OR ABS(actual_net_usd - expected_net_usd) > 0.005 + 1e-6
ORDER BY title_id = 'TOTAL', title_id;
