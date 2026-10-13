-- replayed raw_orders copies never disagree on immutable business fields
-- raw_orders is append-only and the March 2026 re-extract replayed 2,957 orders; stg_order keeps the
-- latest ingestion of each order_id. That pick is only safe while every copy agrees on player, title,
-- platform, order timestamp, currency and gross. Fails on any order_id whose copies differ in one of
-- those fields (NULL vs value counts as a difference), so a conflicting replay is investigated
-- instead of silently resolved. A change in order_status alone is a legitimate lifecycle update and
-- is not flagged here (stg_order_duplicates.has_status_change).
SELECT order_id, copies,
       player_id_conflict, title_id_conflict, platform_code_conflict,
       order_ts_conflict, currency_code_conflict, gross_amount_conflict,
       has_status_change, first_ingested_at, last_ingested_at
FROM stg_order_duplicates
WHERE has_immutable_conflict = 1;
