-- Dimensions. These were the last thing I got working and I think they're fine. -- R.C.

DROP TABLE IF EXISTS dim_title;
CREATE TABLE dim_title AS
SELECT title_id, title_name, genre, launch_date, lead_studio_id, base_price_usd
FROM raw_titles;

DROP TABLE IF EXISTS dim_studio;
CREATE TABLE dim_studio AS
SELECT studio_id, studio_name, region, founded_year FROM raw_studios;

DROP TABLE IF EXISTS bridge_title_studio;
CREATE TABLE bridge_title_studio AS
SELECT title_id, studio_id, credit_role FROM raw_title_studio_credits;

DROP TABLE IF EXISTS dim_player;
CREATE TABLE dim_player AS
SELECT player_id, country_code, currency_code, signup_date, acquisition_channel, email_domain
FROM raw_players;

DROP TABLE IF EXISTS dim_platform;
CREATE TABLE dim_platform AS
SELECT DISTINCT platform_code FROM raw_orders;

-- Fiscal year starts on 1 October: FY2026 = 2025-10-01 .. 2026-09-30.
-- Fiscal month: Oct = 1 .. Sep = 12, i.e. (calendar_month + 2) % 12 + 1. The +2 keeps the operand
-- positive: SQLite's % and integer / truncate toward zero, so (month - 10) went negative for Jan-Sep.
-- Fiscal quarter: Q1 Oct-Dec, Q2 Jan-Mar, Q3 Apr-Jun, Q4 Jul-Sep.
DROP TABLE IF EXISTS dim_date;
CREATE TABLE dim_date AS
WITH RECURSIVE d(dt) AS (
    SELECT '2024-10-01'
    UNION ALL
    SELECT date(dt, '+1 day') FROM d WHERE dt < '2026-12-31'
)
SELECT dt                                                              AS date,
       CAST(strftime('%Y', dt) AS INTEGER)                             AS calendar_year,
       CAST(strftime('%m', dt) AS INTEGER)                             AS calendar_month,
       substr(dt, 1, 7)                                                AS year_month,
       (CAST(strftime('%m', dt) AS INTEGER) - 1) / 3 + 1               AS calendar_quarter,
       'FY' || CASE WHEN CAST(strftime('%m', dt) AS INTEGER) >= 10
                    THEN CAST(strftime('%Y', dt) AS INTEGER) + 1
                    ELSE CAST(strftime('%Y', dt) AS INTEGER) END       AS fiscal_year,
       ((CAST(strftime('%m', dt) AS INTEGER) + 2) % 12) / 3 + 1        AS fiscal_quarter_no,
       ((CAST(strftime('%m', dt) AS INTEGER) + 2) % 12) + 1            AS fiscal_month_no,
       CASE WHEN strftime('%w', dt) IN ('0','6') THEN 1 ELSE 0 END     AS is_weekend
FROM d;
