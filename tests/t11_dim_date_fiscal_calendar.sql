-- dim_date fiscal year, quarter and month follow the Finance calendar (FY starts 1 October)
-- REVENUE_POLICY.md "Fiscal calendar": FY2026 = 2025-10-01 .. 2026-09-30; Q1 Oct-Dec, Q2 Jan-Mar,
-- Q3 Apr-Jun, Q4 Jul-Sep. Guards the observed defect where fiscal_quarter_no and fiscal_month_no
-- went negative for Jan-Sep (SQLite % keeps the dividend's sign), so no date had quarter 2 and a
-- report filtering fiscal_quarter_no = 2 returned nothing. The expected values come from an explicit
-- month lookup, not from the formula under test.
WITH expected(calendar_month, fiscal_month_no, fiscal_quarter_no) AS (
    VALUES (10, 1, 1), (11, 2, 1), (12, 3, 1),
           ( 1, 4, 2), ( 2, 5, 2), ( 3, 6, 2),
           ( 4, 7, 3), ( 5, 8, 3), ( 6, 9, 3),
           ( 7, 10, 4), ( 8, 11, 4), ( 9, 12, 4)
)
SELECT d.date, d.fiscal_year, d.fiscal_quarter_no, d.fiscal_month_no,
       'FY' || (d.calendar_year + (d.calendar_month >= 10)) AS expected_fiscal_year,
       e.fiscal_quarter_no AS expected_fiscal_quarter_no,
       e.fiscal_month_no   AS expected_fiscal_month_no
FROM dim_date d
LEFT JOIN expected e ON e.calendar_month = d.calendar_month
WHERE e.calendar_month IS NULL
   OR d.fiscal_quarter_no IS NOT e.fiscal_quarter_no
   OR d.fiscal_month_no   IS NOT e.fiscal_month_no
   OR d.fiscal_year       IS NOT 'FY' || (d.calendar_year + (d.calendar_month >= 10));
