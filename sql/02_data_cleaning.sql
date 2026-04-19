-- =============================================================================
-- 02_data_cleaning.sql
-- Project:   Repeat Purchase Recovery
-- Purpose:   Define the six cleaned base views from raw Olist CSV tables.
--            These views are the only layer that touches raw source tables
--            directly. All downstream SQL (marts, cohorts, RFM) reads from
--            these views, never from raw tables.
--
-- Dialect:   SQLite 3.25.0+
--            ROW_NUMBER() (used in order_reviews_clean) requires SQLite >= 3.25.
--            Run:  SELECT sqlite_version();  — confirm before executing.
--
-- Source tables (raw CSV files loaded as-is, snake_case table names):
--   olist_orders_dataset
--   olist_customers_dataset
--   olist_order_items_dataset
--   olist_order_payments_dataset
--   olist_order_reviews_dataset
--   olist_products_dataset
--   product_category_name_translation
--
-- Timestamp handling:
--   All Olist date columns are stored as TEXT in ISO-8601 format
--   ("YYYY-MM-DD HH:MM:SS"). SQLite's date/time functions (DATE, DATETIME,
--   JULIANDAY, STRFTIME) operate directly on these strings without an explicit
--   cast. Wrapping columns in DATETIME() normalises the format and returns NULL
--   for any malformed values, surfacing data quality issues early.
--
-- Step 1 of 5 in the implementation plan.
-- Do not build marts or aggregation views in this file.
-- =============================================================================


-- =============================================================================
-- VIEW 1: orders_clean
-- -----------------------------------------------------------------------------
-- Grain:   One row per order_id
-- Source:  olist_orders_dataset
-- Filter:  order_status = 'delivered' — 96,478 of 99,441 orders
--
-- Why this view exists:
--   The raw orders table contains 8 status values. Only 'delivered' orders
--   represent confirmed, completed transactions and are safe to include in
--   retention, CLV, and revenue analysis. All downstream views INNER JOIN
--   to this view to inherit the delivered-only scope automatically.
--
-- Timestamp columns are wrapped in DATETIME() to normalise to
-- "YYYY-MM-DD HH:MM:SS" and return NULL for any malformed values.
-- order_approved_at and order_delivered_carrier_date have known nulls in source
-- (160 and 1,783 respectively) — these are expected and retained as NULL.
-- =============================================================================

DROP VIEW IF EXISTS orders_clean;

CREATE VIEW orders_clean AS
SELECT
    order_id,
    customer_id,
    order_status,

    -- purchase timestamp: primary date for cohort assignment and recency
    DATETIME(order_purchase_timestamp)    AS order_purchase_timestamp,

    -- approval and carrier handoff: retained, not used in first-pass analysis
    DATETIME(order_approved_at)           AS order_approved_at,
    DATETIME(order_delivered_carrier_date) AS order_delivered_carrier_date,

    -- actual and estimated delivery: used for delivery delay signal
    DATETIME(order_delivered_customer_date)  AS order_delivered_customer_date,
    DATETIME(order_estimated_delivery_date)  AS order_estimated_delivery_date

FROM olist_orders_dataset
WHERE order_status = 'delivered';


-- =============================================================================
-- VIEW 2: customers_clean
-- -----------------------------------------------------------------------------
-- Grain:   One row per customer_id (order-scoped)
-- Source:  olist_customers_dataset
-- Filter:  None — all 99,441 rows retained (zero nulls on any column in source)
--
-- Why this view exists:
--   The central modelling challenge in Olist is that customer_id in the orders
--   table is order-scoped — a new value is generated per order, even for the
--   same person. customer_unique_id is the only person-level key available.
--   This view is the required bridge: orders → customers → customer_unique_id.
--   Every person-level aggregation (repeat rate, CLV, cohort) joins here.
--
-- customer_zip_code_prefix is retained for potential geolocation join later.
-- =============================================================================

DROP VIEW IF EXISTS customers_clean;

CREATE VIEW customers_clean AS
SELECT
    customer_id,           -- order-scoped FK — joins to orders_clean.customer_id
    customer_unique_id,    -- person-level key — use this for all lifecycle analysis
    customer_zip_code_prefix,
    customer_city,
    customer_state
FROM olist_customers_dataset;


-- =============================================================================
-- VIEW 3: order_items_clean
-- -----------------------------------------------------------------------------
-- Grain:   One row per (order_id, order_item_id)
-- Source:  olist_order_items_dataset
-- Filter:  INNER JOIN to orders_clean — retains only items on delivered orders
--
-- Why this view exists:
--   Provides item-level price, freight, and product reference for each
--   delivered order. Required for order-level revenue aggregation (Step 2)
--   and category breadth calculation.
--
-- Important: this view has multiple rows per order_id (one per item).
-- DO NOT join directly to orders_clean without aggregating first.
-- Use Step 2 mart order_revenue for order-level revenue totals.
--
-- seller_id is retained but is not used in first-pass analysis
-- (sellers dataset excluded from this project scope).
-- shipping_limit_date is a TEXT timestamp in the source; retained as-is.
-- =============================================================================

DROP VIEW IF EXISTS order_items_clean;

CREATE VIEW order_items_clean AS
SELECT
    i.order_id,
    i.order_item_id,    -- item sequence within order (1, 2, 3 …); max 21 in dataset
    i.product_id,       -- FK → products_clean
    i.seller_id,        -- FK → sellers (excluded from first pass)
    i.shipping_limit_date,
    i.price,            -- listed item price (BRL); does not reflect voucher discounts
    i.freight_value     -- freight cost for this item (BRL)
FROM olist_order_items_dataset i
INNER JOIN orders_clean o
    ON i.order_id = o.order_id;


-- =============================================================================
-- VIEW 4: order_payments_clean
-- -----------------------------------------------------------------------------
-- Grain:   One row per (order_id, payment_sequential)
-- Source:  olist_order_payments_dataset
-- Filter:  INNER JOIN to orders_clean — retains only payments on delivered orders
--
-- Why this view exists:
--   payment_value is the recommended revenue field for CLV and monetary scoring
--   because it reflects the amount actually collected (post-voucher), not the
--   listed item price. One order can have multiple payment rows (split methods
--   e.g. credit card + voucher). This view preserves the raw split.
--
-- Important: this view has multiple rows per order_id.
-- DO NOT join directly to orders_clean without aggregating first.
-- Use Step 2 mart order_payment_total (SUM per order_id) for order-level totals.
--
-- payment_sequential = 1 identifies the primary payment method.
-- =============================================================================

DROP VIEW IF EXISTS order_payments_clean;

CREATE VIEW order_payments_clean AS
SELECT
    p.order_id,
    p.payment_sequential,   -- 1 = primary method; 2+ = additional split payments
    p.payment_type,         -- credit_card | boleto | voucher | debit_card | not_defined
    p.payment_installments, -- number of installments; 0 = single payment
    p.payment_value         -- amount paid via this method (BRL); aggregate per order_id
FROM olist_order_payments_dataset p
INNER JOIN orders_clean o
    ON p.order_id = o.order_id;


-- =============================================================================
-- VIEW 5: order_reviews_clean
-- -----------------------------------------------------------------------------
-- Grain:   One row per order_id (after deduplication)
-- Source:  olist_order_reviews_dataset
-- Filter:  INNER JOIN to orders_clean; deduplicated to one row per order_id
--
-- Why this view exists:
--   The raw reviews table has 814 duplicate review_id values and multiple
--   review submissions per order_id. Downstream analysis requires exactly one
--   review record per order. review_score is the primary analytical field;
--   comment columns are retained for completeness but are 88% and 59% null.
--
-- Deduplication priority (see ROW_NUMBER below):
--   (1) Latest review_answer_timestamp DESC — the most recent response wins
--   (2) Fewest nulls across comment fields DESC — most complete record wins
--       as tiebreaker when timestamps are equal or both null
--
-- review_id is NOT used as a key — 814 duplicate values confirmed in source.
-- Only review_score is carried forward into downstream analytical marts;
-- comment columns are retained here for potential future text analysis.
-- =============================================================================

DROP VIEW IF EXISTS order_reviews_clean;

CREATE VIEW order_reviews_clean AS
WITH ranked_reviews AS (
    SELECT
        r.review_id,
        r.order_id,
        r.review_score,
        r.review_comment_title,
        r.review_comment_message,
        DATETIME(r.review_creation_date)    AS review_creation_date,
        DATETIME(r.review_answer_timestamp) AS review_answer_timestamp,

        ROW_NUMBER() OVER (
            PARTITION BY r.order_id
            ORDER BY
                -- Priority 1: most recent answer timestamp
                r.review_answer_timestamp DESC,
                -- Priority 2: most complete comment record (tiebreaker)
                (
                    CASE WHEN r.review_comment_title   IS NOT NULL THEN 1 ELSE 0 END +
                    CASE WHEN r.review_comment_message IS NOT NULL THEN 1 ELSE 0 END
                ) DESC
        ) AS row_rank

    FROM olist_order_reviews_dataset r
    INNER JOIN orders_clean o
        ON r.order_id = o.order_id
)
SELECT
    review_id,
    order_id,
    review_score,
    review_comment_title,
    review_comment_message,
    review_creation_date,
    review_answer_timestamp
FROM ranked_reviews
WHERE row_rank = 1;


-- =============================================================================
-- VIEW 6: products_clean
-- -----------------------------------------------------------------------------
-- Grain:   One row per product_id
-- Source:  olist_products_dataset LEFT JOIN product_category_name_translation
-- Filter:  None — all 32,951 products retained
--
-- Why this view exists:
--   The products table uses Portuguese category names. The translation file
--   maps 71 of 73 Portuguese names to English. This view resolves a usable
--   category label via a three-tier COALESCE fallback:
--     Tier 1 — English translation (preferred; covers 71/73 categories)
--     Tier 2 — Original Portuguese name (covers 2 untranslated categories:
--               pc_gamer, portateis_cozinha_e_preparadores_de_alimentos)
--     Tier 3 — 'unknown' (covers 610 products with null product_category_name)
--
-- Column name typos from source are preserved exactly as documented:
--   product_name_lenght, product_description_lenght  (intentional misspellings)
--
-- Dimensional columns (weight, dimensions, photo count) are retained but
-- are not used in first-pass analytical marts.
-- =============================================================================

DROP VIEW IF EXISTS products_clean;

CREATE VIEW products_clean AS
SELECT
    p.product_id,
    p.product_category_name,                -- original Portuguese name (may be null)
    t.product_category_name_english,        -- English translation (null if untranslated)

    -- Resolved category: use English → Portuguese fallback → 'unknown'
    COALESCE(
        t.product_category_name_english,    -- Tier 1: English translation
        p.product_category_name,            -- Tier 2: Portuguese name (untranslated categories)
        'unknown'                           -- Tier 3: null category products
    ) AS product_category_resolved,

    -- Dimension columns (typos preserved to match source column names exactly)
    p.product_name_lenght,
    p.product_description_lenght,
    p.product_photos_qty,
    p.product_weight_g,
    p.product_length_cm,
    p.product_height_cm,
    p.product_width_cm

FROM olist_products_dataset p
LEFT JOIN product_category_name_translation t
    ON p.product_category_name = t.product_category_name;


-- =============================================================================
-- VALIDATION QUERIES
-- =============================================================================
-- Run these queries after creating all views.
-- They do not modify data — read-only checks only.
-- Expected values come from the confirmed data inventory.
-- All checks should return 0 in the "problem_count" columns.
-- =============================================================================


-- ----------------------------------------------------------------------------
-- V1: Row count summary
-- Expected: orders_clean ≈ 96,478 | customers_clean = 99,441
--           products_clean = 32,951 | items/payments/reviews are subsets
--           of their originals (inner join to orders_clean filters to delivered)
-- ----------------------------------------------------------------------------

SELECT 'orders_clean'         AS view_name, COUNT(*) AS row_count FROM orders_clean
UNION ALL
SELECT 'customers_clean'      AS view_name, COUNT(*) AS row_count FROM customers_clean
UNION ALL
SELECT 'order_items_clean'    AS view_name, COUNT(*) AS row_count FROM order_items_clean
UNION ALL
SELECT 'order_payments_clean' AS view_name, COUNT(*) AS row_count FROM order_payments_clean
UNION ALL
SELECT 'order_reviews_clean'  AS view_name, COUNT(*) AS row_count FROM order_reviews_clean
UNION ALL
SELECT 'products_clean'       AS view_name, COUNT(*) AS row_count FROM products_clean;


-- ----------------------------------------------------------------------------
-- V2: Duplicate check — orders_clean
-- Expected: 0 rows (order_id is PK; delivered orders have no duplicates in source)
-- ----------------------------------------------------------------------------

SELECT
    'orders_clean'              AS view_name,
    'duplicate order_id'        AS check_description,
    COUNT(*)                    AS problem_count
FROM (
    SELECT order_id
    FROM orders_clean
    GROUP BY order_id
    HAVING COUNT(*) > 1
);


-- ----------------------------------------------------------------------------
-- V3: Duplicate check — customers_clean
-- Expected: 0 rows (customer_id is order-scoped; confirmed unique in source)
-- ----------------------------------------------------------------------------

SELECT
    'customers_clean'           AS view_name,
    'duplicate customer_id'     AS check_description,
    COUNT(*)                    AS problem_count
FROM (
    SELECT customer_id
    FROM customers_clean
    GROUP BY customer_id
    HAVING COUNT(*) > 1
);


-- ----------------------------------------------------------------------------
-- V4: Duplicate check — order_items_clean
-- Expected: 0 rows (PK is composite: order_id + order_item_id)
-- ----------------------------------------------------------------------------

SELECT
    'order_items_clean'                         AS view_name,
    'duplicate (order_id, order_item_id)'       AS check_description,
    COUNT(*)                                    AS problem_count
FROM (
    SELECT order_id, order_item_id
    FROM order_items_clean
    GROUP BY order_id, order_item_id
    HAVING COUNT(*) > 1
);


-- ----------------------------------------------------------------------------
-- V5: Duplicate check — order_payments_clean
-- Expected: 0 rows (PK is composite: order_id + payment_sequential)
-- ----------------------------------------------------------------------------

SELECT
    'order_payments_clean'                          AS view_name,
    'duplicate (order_id, payment_sequential)'      AS check_description,
    COUNT(*)                                        AS problem_count
FROM (
    SELECT order_id, payment_sequential
    FROM order_payments_clean
    GROUP BY order_id, payment_sequential
    HAVING COUNT(*) > 1
);


-- ----------------------------------------------------------------------------
-- V6: Duplicate check — order_reviews_clean
-- Expected: 0 rows (dedup CTE reduces to one row per order_id)
-- A non-zero result means the ROW_NUMBER() dedup logic did not work correctly.
-- ----------------------------------------------------------------------------

SELECT
    'order_reviews_clean'           AS view_name,
    'duplicate order_id after dedup' AS check_description,
    COUNT(*)                        AS problem_count
FROM (
    SELECT order_id
    FROM order_reviews_clean
    GROUP BY order_id
    HAVING COUNT(*) > 1
);


-- ----------------------------------------------------------------------------
-- V7: Duplicate check — products_clean
-- Expected: 0 rows (product_id is PK in source)
-- ----------------------------------------------------------------------------

SELECT
    'products_clean'            AS view_name,
    'duplicate product_id'      AS check_description,
    COUNT(*)                    AS problem_count
FROM (
    SELECT product_id
    FROM products_clean
    GROUP BY product_id
    HAVING COUNT(*) > 1
);


-- ----------------------------------------------------------------------------
-- V8: Null check — orders_clean critical fields
-- order_id, customer_id, order_purchase_timestamp must all be 0.
-- order_delivered_customer_date: expect 0 nulls (filtered to delivered).
-- order_approved_at: expect ~0 nulls (a few may still exist in delivered scope).
-- ----------------------------------------------------------------------------

SELECT
    SUM(CASE WHEN order_id                       IS NULL THEN 1 ELSE 0 END) AS null_order_id,
    SUM(CASE WHEN customer_id                    IS NULL THEN 1 ELSE 0 END) AS null_customer_id,
    SUM(CASE WHEN order_purchase_timestamp       IS NULL THEN 1 ELSE 0 END) AS null_purchase_ts,
    SUM(CASE WHEN order_delivered_customer_date  IS NULL THEN 1 ELSE 0 END) AS null_delivered_date,
    SUM(CASE WHEN order_approved_at              IS NULL THEN 1 ELSE 0 END) AS null_approved_at
FROM orders_clean;


-- ----------------------------------------------------------------------------
-- V9: Null check — customers_clean
-- customer_id and customer_unique_id must be 0 (confirmed no nulls in source).
-- ----------------------------------------------------------------------------

SELECT
    SUM(CASE WHEN customer_id        IS NULL THEN 1 ELSE 0 END) AS null_customer_id,
    SUM(CASE WHEN customer_unique_id IS NULL THEN 1 ELSE 0 END) AS null_unique_id,
    SUM(CASE WHEN customer_state     IS NULL THEN 1 ELSE 0 END) AS null_state
FROM customers_clean;


-- ----------------------------------------------------------------------------
-- V10: Null check — order_items_clean
-- order_id, order_item_id, product_id, price, freight_value must be 0.
-- ----------------------------------------------------------------------------

SELECT
    SUM(CASE WHEN order_id      IS NULL THEN 1 ELSE 0 END) AS null_order_id,
    SUM(CASE WHEN order_item_id IS NULL THEN 1 ELSE 0 END) AS null_order_item_id,
    SUM(CASE WHEN product_id    IS NULL THEN 1 ELSE 0 END) AS null_product_id,
    SUM(CASE WHEN price         IS NULL THEN 1 ELSE 0 END) AS null_price,
    SUM(CASE WHEN freight_value IS NULL THEN 1 ELSE 0 END) AS null_freight_value
FROM order_items_clean;


-- ----------------------------------------------------------------------------
-- V11: Null check — order_reviews_clean
-- review_score must be 0 (required field in source).
-- Comment nulls are expected and high (88% and 59% respectively).
-- ----------------------------------------------------------------------------

SELECT
    SUM(CASE WHEN review_score           IS NULL THEN 1 ELSE 0 END) AS null_review_score,
    SUM(CASE WHEN review_answer_timestamp IS NULL THEN 1 ELSE 0 END) AS null_answer_ts,
    SUM(CASE WHEN review_comment_title   IS NULL THEN 1 ELSE 0 END) AS null_comment_title,
    SUM(CASE WHEN review_comment_message IS NULL THEN 1 ELSE 0 END) AS null_comment_msg,
    COUNT(*)                                                         AS total_reviews
FROM order_reviews_clean;


-- ----------------------------------------------------------------------------
-- V12: Join coverage — delivered orders with no item rows
-- 775 orders in raw source have no item rows. The INNER JOIN in order_items_clean
-- excludes them automatically. This query confirms the coverage gap.
-- If gap > 775, investigate whether valid delivered orders are being lost.
-- ----------------------------------------------------------------------------

SELECT
    (SELECT COUNT(*)                   FROM orders_clean)                AS delivered_orders,
    (SELECT COUNT(DISTINCT order_id)   FROM order_items_clean)           AS orders_with_items,
    (SELECT COUNT(*) FROM orders_clean)
        - (SELECT COUNT(DISTINCT order_id) FROM order_items_clean)       AS orders_with_no_items;


-- ----------------------------------------------------------------------------
-- V13: Join coverage — delivered orders with no payment row
-- Source data has 1 order with no payment row.
-- Expect: orders_with_no_payments = 0 or 1.
-- ----------------------------------------------------------------------------

SELECT
    (SELECT COUNT(*)                   FROM orders_clean)                AS delivered_orders,
    (SELECT COUNT(DISTINCT order_id)   FROM order_payments_clean)        AS orders_with_payments,
    (SELECT COUNT(*) FROM orders_clean)
        - (SELECT COUNT(DISTINCT order_id) FROM order_payments_clean)    AS orders_with_no_payments;


-- ----------------------------------------------------------------------------
-- V14: Join coverage — delivered orders with no review
-- 768 of all orders have no review; some of those are in delivered scope.
-- This is expected — reviews are optional. Use LEFT JOIN downstream.
-- ----------------------------------------------------------------------------

SELECT
    COUNT(*)                                                               AS delivered_orders,
    SUM(CASE WHEN r.order_id IS NOT NULL THEN 1 ELSE 0 END)               AS orders_with_review,
    SUM(CASE WHEN r.order_id IS     NULL THEN 1 ELSE 0 END)               AS orders_without_review,
    ROUND(
        100.0 * SUM(CASE WHEN r.order_id IS NOT NULL THEN 1 ELSE 0 END)
        / COUNT(*), 2
    )                                                                      AS review_coverage_pct
FROM orders_clean o
LEFT JOIN order_reviews_clean r
    ON o.order_id = r.order_id;


-- ----------------------------------------------------------------------------
-- V15: Join coverage — items with no matching product record
-- Expect: 0. If non-zero, item rows reference a product_id not in products_clean.
-- ----------------------------------------------------------------------------

SELECT
    COUNT(*) AS items_with_missing_product
FROM order_items_clean i
LEFT JOIN products_clean p
    ON i.product_id = p.product_id
WHERE p.product_id IS NULL;


-- ----------------------------------------------------------------------------
-- V16: product_category_resolved tier breakdown
-- Confirms the three-tier COALESCE is working as expected.
--
-- Expected distribution:
--   Tier 1 (English translation) — majority of products
--   Tier 2 (Portuguese fallback)  — small count; 2 untranslated categories
--   Tier 3 ('unknown')            — ~610 products with null category_name
-- ----------------------------------------------------------------------------

SELECT
    CASE
        WHEN product_category_name_english IS NOT NULL THEN '1_english_translation'
        WHEN product_category_name         IS NOT NULL THEN '2_portuguese_fallback'
        ELSE                                                '3_unknown'
    END                     AS resolution_tier,
    COUNT(*)                AS product_count,
    ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM products_clean), 2) AS pct_of_total
FROM products_clean
GROUP BY resolution_tier
ORDER BY resolution_tier;
