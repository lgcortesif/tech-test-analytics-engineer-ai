-- Staging: exactly one row per business order_id.
--
-- raw_orders is append-only and can contain replays of the same order (the March 2026
-- re-extract landed 2,957 orders twice). Replays are collapsed to the most recently ingested
-- version. Before that pick is trusted, stg_order_duplicates records, per business field,
-- whether the versions disagree:
--   * immutable fields (player, title, platform, timestamp, currency, gross) must never differ;
--     a test fails on any row with has_immutable_conflict = 1;
--   * order_status may legitimately move (e.g. pending -> completed), so it is surfaced
--     separately as has_status_change and the latest ingestion wins.
-- A field counts as conflicting if it has more than one distinct value OR a mix of NULL and
-- non-NULL values (COUNT(DISTINCT ...) alone ignores NULLs).

DROP TABLE IF EXISTS stg_order_duplicates;
CREATE TABLE stg_order_duplicates AS
SELECT order_id,
       copies,
       player_id_conflict, title_id_conflict, platform_code_conflict,
       order_ts_conflict, currency_code_conflict, gross_amount_conflict,
       CASE WHEN player_id_conflict + title_id_conflict + platform_code_conflict
               + order_ts_conflict + currency_code_conflict + gross_amount_conflict > 0
            THEN 1 ELSE 0 END                                              AS has_immutable_conflict,
       order_status_conflict                                               AS has_status_change,
       first_ingested_at,
       last_ingested_at
FROM (
    SELECT order_id,
           COUNT(*)                                                                   AS copies,
           (COUNT(DISTINCT player_id)          > 1 OR COUNT(player_id)          NOT IN (0, COUNT(*))) AS player_id_conflict,
           (COUNT(DISTINCT title_id)           > 1 OR COUNT(title_id)           NOT IN (0, COUNT(*))) AS title_id_conflict,
           (COUNT(DISTINCT platform_code)      > 1 OR COUNT(platform_code)      NOT IN (0, COUNT(*))) AS platform_code_conflict,
           (COUNT(DISTINCT order_ts)           > 1 OR COUNT(order_ts)           NOT IN (0, COUNT(*))) AS order_ts_conflict,
           (COUNT(DISTINCT currency_code)      > 1 OR COUNT(currency_code)      NOT IN (0, COUNT(*))) AS currency_code_conflict,
           (COUNT(DISTINCT gross_amount_local) > 1 OR COUNT(gross_amount_local) NOT IN (0, COUNT(*))) AS gross_amount_conflict,
           (COUNT(DISTINCT order_status)       > 1 OR COUNT(order_status)       NOT IN (0, COUNT(*))) AS order_status_conflict,
           MIN(ingested_at)                                                           AS first_ingested_at,
           MAX(ingested_at)                                                           AS last_ingested_at
    FROM raw_orders
    GROUP BY order_id
    HAVING COUNT(*) > 1
);

DROP TABLE IF EXISTS stg_order;
CREATE TABLE stg_order AS
SELECT order_id, player_id, title_id, platform_code, order_date, order_ts,
       currency_code, gross_local, order_status, ingested_at, source_copies
FROM (
    SELECT o.order_id,
           o.player_id,
           o.title_id,
           o.platform_code,
           substr(o.order_ts, 1, 10)            AS order_date,
           o.order_ts,
           o.currency_code,
           CAST(o.gross_amount_local AS REAL)   AS gross_local,
           o.order_status,
           o.ingested_at,
           COUNT(*)     OVER (PARTITION BY o.order_id)                           AS source_copies,
           ROW_NUMBER() OVER (PARTITION BY o.order_id
                              ORDER BY o.ingested_at DESC, o.rowid DESC)        AS rn
    FROM raw_orders o
)
WHERE rn = 1;

-- UNIQUE: a broken grain fails the build, not the report.
CREATE UNIQUE INDEX ux_stg_order ON stg_order(order_id);
