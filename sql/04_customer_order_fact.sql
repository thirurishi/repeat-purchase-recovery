-- =============================================================================
-- 04_customer_order_fact.sql
-- Project:   Repeat Purchase Recovery
-- Purpose:   Build the unified order-level fact table by joining the cleaned
--            base layer to the aggregated order tables. One row per delivered
--            order, enriched with customer identity, revenue, payment, review,
--            and derived delivery fields.
--
--            This is the central table for all downstream customer-level analysis.
--            Lifecycle sequencing (order_rank, days_since_previous_order) is
--            NOT added here — that belongs in a later sequencing step where
--            window functions operate over the full per-customer order history.
--
-- Output:    customer_order_fact
--            Grain: one row per order_id (all 96,478 delivered orders)
--
-- Depends on:
--   sql/02_data_cleaning.sql     orders_clean, customers_clean, order_reviews_clean
--   sql/03_order_aggregations.sql  order_revenue, order_payment_total
--
-- Dialect:   SQLite 3.25.0+
-- Step:      Step 3 of 5 in the implementation plan.
-- =============================================================================


-- =============================================================================
-- REVENUE FIELD DISAMBIGUATION
-- =============================================================================
--
-- This view carries two distinct views of order revenue.
-- They measure different things and will often differ for the same order.
--
-- total_payment_value    (from order_payment_total)
--   What the customer actually paid — SUM(payment_value) from the payments
--   table.  This is the post-voucher, post-discount collected amount and is
--   the RECOMMENDED revenue field for CLV, RFM monetary scoring, and any
--   customer-level revenue reporting.  NULL for exactly 1 order (order_id
--   bfbd0f9bdef84302105ad712db648a6c, purchased 2016-09-15) that has no
--   corresponding payment row in the source data.
--
-- total_order_revenue_item_view    (from order_revenue)
--   SUM(price) + SUM(freight_value) from the order items table.  This
--   reflects the listed price before any voucher offset.  Use for basket
--   composition analysis (freight ratio, category-level revenue) where
--   item-level granularity matters.  Always present — all 96,478 delivered
--   orders have item rows.
--
-- Do NOT add these two fields together.  Do NOT use them interchangeably.
-- When in doubt, use total_payment_value.
--
-- =============================================================================


-- =============================================================================
-- JOIN STRATEGY
-- =============================================================================
--
-- orders_clean        INNER JOIN customers_clean       — every order has a customer_id;
--                                                        0 unmatched rows confirmed (V9, Step 1)
-- orders_clean        INNER JOIN order_revenue         — every delivered order has item rows;
--                                                        0 gap confirmed (V20, Step 2)
-- orders_clean        LEFT  JOIN order_payment_total   — 1 delivered order has no payment row
--                                                        (confirmed V21, Step 2); payment fields
--                                                        will be NULL for that order
-- orders_clean        LEFT  JOIN order_reviews_clean   — 646 delivered orders have no review
--                                                        (confirmed V14, Step 1); review fields
--                                                        will be NULL for those orders
--
-- No CROSS JOIN risk: order_revenue and order_payment_total are already
-- aggregated to one row per order_id (confirmed V18-V19, Step 2).
-- order_reviews_clean is deduplicated to one row per order_id (confirmed V6, Step 1).
--
-- =============================================================================


-- =============================================================================
-- DERIVED FIELD NOTES
-- =============================================================================
--
-- order_year, order_month
--   Extracted from order_purchase_timestamp using STRFTIME.
--   Cast to INTEGER for numeric sorting and grouping.
--   order_purchase_timestamp has 0 nulls in delivered scope (confirmed V8).
--
-- delivery_days
--   Whole calendar days between order_purchase_timestamp and
--   order_delivered_customer_date (rounded to nearest integer).
--   NULL for the 8 delivered orders where order_delivered_customer_date is
--   missing from the source data (confirmed V8, Step 1).
--   These 8 orders are retained — their purchase and payment data are valid.
--   Expected range: positive integers; values < 0 would indicate a data error.
--
-- delivery_delay_days
--   Signed difference: actual delivery minus estimated delivery.
--   Positive = delivered late.  Negative = delivered early.
--   NULL for the same 8 orders where order_delivered_customer_date is null.
--   order_estimated_delivery_date has 0 nulls (confirmed in inventory).
--
-- delivered_on_time_flag
--   1 = delivered on or before the estimated date.
--   0 = delivered after the estimated date (late).
--   NULL = delivery date unknown (8 orders).
--   String comparison on ISO-8601 "YYYY-MM-DD HH:MM:SS" values is
--   chronologically correct because the format sorts lexicographically.
--
-- freight_ratio
--   total_freight_value / total_item_price.
--   Represents freight as a proportion of listed item price.
--   NULL if total_item_price is zero or NULL (avoids division by zero).
--   A value > 1.0 means the customer paid more in freight than in item price,
--   which is possible for very cheap or light items.
--
-- =============================================================================

DROP VIEW IF EXISTS customer_order_fact;

CREATE VIEW customer_order_fact AS
SELECT

    -- ── CUSTOMER IDENTIFIERS ──────────────────────────────────────────────────
    c.customer_unique_id,        -- person-level key — use for all lifecycle analysis
    o.customer_id,               -- order-scoped key — retained for audit / bridge join

    -- ── ORDER IDENTITY ────────────────────────────────────────────────────────
    o.order_id,

    -- ── ORDER TIMESTAMPS (all as ISO-8601 strings, DATETIME-normalised) ───────
    o.order_purchase_timestamp,
    o.order_approved_at,
    o.order_delivered_carrier_date,
    o.order_delivered_customer_date,
    o.order_estimated_delivery_date,

    -- ── TIME DIMENSIONS (derived) ─────────────────────────────────────────────
    -- Calendar year of purchase (integer, e.g. 2017)
    CAST(STRFTIME('%Y', o.order_purchase_timestamp) AS INTEGER)  AS order_year,

    -- Calendar month of purchase (integer 1–12)
    CAST(STRFTIME('%m', o.order_purchase_timestamp) AS INTEGER)  AS order_month,

    -- ── CUSTOMER GEOGRAPHY ────────────────────────────────────────────────────
    c.customer_city,
    c.customer_state,

    -- ── PAYMENT FIELDS ────────────────────────────────────────────────────────
    -- All sourced from order_payment_total (LEFT JOIN — 1 order has no payment row)
    -- NULL for order_id bfbd0f9bdef84302105ad712db648a6c (purchased 2016-09-15).
    -- Use total_payment_value as the primary revenue field for CLV and RFM.
    p.total_payment_value,       -- collected amount; recommended for customer-level revenue
    p.primary_payment_type,      -- payment method of lowest-sequential row
    p.payment_type_count,        -- 1 = single method; 2+ = split payment
    p.max_installments,          -- longest installment plan (0 = single lump sum)
    p.total_payment_records,     -- total payment rows for this order

    -- ── ITEM-PRICE REVENUE AND BASKET FIELDS ─────────────────────────────────
    -- All sourced from order_revenue (INNER JOIN — always present)
    r.total_item_price,          -- SUM(price) across all items (BRL)
    r.total_freight_value,       -- SUM(freight_value) across all items (BRL)
    r.total_order_revenue_item_view, -- total_item_price + total_freight_value (BRL)
    r.total_items,               -- count of line items in the order
    r.unique_products_count,     -- count of distinct product_ids
    r.unique_categories_count,   -- count of distinct product_category_resolved values
    r.primary_category_resolved, -- dominant category by item count; 'unknown' at worst

    -- ── REVIEW FIELDS ─────────────────────────────────────────────────────────
    -- Sourced from order_reviews_clean (LEFT JOIN — 646 orders have no review)
    -- NULL for orders with no review row.
    -- review_score is the only field used in first-pass analytical marts.
    -- Comment columns are retained here for completeness; 88% / 59% null in source.
    rv.review_score,
    rv.review_comment_title,
    rv.review_comment_message,

    -- ── DERIVED: DELIVERY PERFORMANCE ────────────────────────────────────────
    -- NULL for the 8 delivered orders with no order_delivered_customer_date.
    -- These 8 orders are kept; their purchase, payment, and review data are valid.

    -- Whole calendar days from purchase to delivery (rounded, then cast to integer)
    CASE
        WHEN o.order_delivered_customer_date IS NULL THEN NULL
        ELSE CAST(
            ROUND(
                JULIANDAY(o.order_delivered_customer_date) -
                JULIANDAY(o.order_purchase_timestamp)
            , 0) AS INTEGER)
    END                                                          AS delivery_days,

    -- Signed days relative to estimated delivery
    -- Positive = late.  Negative = early.  0 = exact.
    CASE
        WHEN o.order_delivered_customer_date IS NULL THEN NULL
        ELSE CAST(
            ROUND(
                JULIANDAY(o.order_delivered_customer_date) -
                JULIANDAY(o.order_estimated_delivery_date)
            , 0) AS INTEGER)
    END                                                          AS delivery_delay_days,

    -- On-time flag: 1 = on or before estimated date, 0 = late, NULL = unknown
    -- ISO-8601 string comparison is chronologically correct for this format
    CASE
        WHEN o.order_delivered_customer_date IS NULL                            THEN NULL
        WHEN o.order_delivered_customer_date <= o.order_estimated_delivery_date THEN 1
        ELSE 0
    END                                                          AS delivered_on_time_flag,

    -- Freight as a proportion of item price
    -- NULL if total_item_price is zero to avoid division by zero
    -- Values > 1.0 are valid (freight can exceed item price for cheap items)
    CASE
        WHEN r.total_item_price IS NULL OR r.total_item_price = 0 THEN NULL
        ELSE ROUND(r.total_freight_value / r.total_item_price, 4)
    END                                                          AS freight_ratio

FROM orders_clean o
INNER JOIN customers_clean c
    ON  o.customer_id = c.customer_id
INNER JOIN order_revenue r
    ON  o.order_id = r.order_id
LEFT JOIN order_payment_total p
    ON  o.order_id = p.order_id
LEFT JOIN order_reviews_clean rv
    ON  o.order_id = rv.order_id;


-- =============================================================================
-- VALIDATION QUERIES
-- =============================================================================
-- Run after creating the view. All checks are read-only SELECT statements.
-- Continuing the V-series numbering from Step 2 (last was V27).
-- =============================================================================


-- ----------------------------------------------------------------------------
-- V28: Row count — must exactly match orders_clean
-- Expected: 96,478
-- A lower count means a join dropped rows (most likely the INNER JOINs).
-- A higher count means a join multiplied rows.
-- ----------------------------------------------------------------------------

SELECT
    (SELECT COUNT(*) FROM orders_clean)        AS orders_clean_rows,
    (SELECT COUNT(*) FROM customer_order_fact) AS fact_rows,
    (SELECT COUNT(*) FROM orders_clean) -
    (SELECT COUNT(*) FROM customer_order_fact) AS row_difference;


-- ----------------------------------------------------------------------------
-- V29: Duplicate check on order_id
-- Expected: 0
-- Any duplicate means one of the LEFT JOIN targets (reviews or payments)
-- has more than one row per order_id despite the earlier dedup step.
-- ----------------------------------------------------------------------------

SELECT
    'customer_order_fact duplicate order_id' AS check_name,
    COUNT(*)                                 AS problem_count
FROM (
    SELECT order_id
    FROM customer_order_fact
    GROUP BY order_id
    HAVING COUNT(*) > 1
);


-- ----------------------------------------------------------------------------
-- V30: Null check on identity fields
-- customer_unique_id and order_id must be 0.
-- customer_unique_id null would mean a customer_id in orders_clean has no
-- corresponding row in customers_clean — confirmed impossible (V9, Step 1).
-- ----------------------------------------------------------------------------

SELECT
    SUM(CASE WHEN customer_unique_id IS NULL THEN 1 ELSE 0 END) AS null_customer_unique_id,
    SUM(CASE WHEN order_id           IS NULL THEN 1 ELSE 0 END) AS null_order_id
FROM customer_order_fact;


-- ----------------------------------------------------------------------------
-- V31: Orders with null payment fields
-- Expected: exactly 1 (the single order with no payment row in source)
-- Returns the order_id for inspection.
-- ----------------------------------------------------------------------------

SELECT
    order_id,
    order_purchase_timestamp,
    total_item_price,
    total_payment_value           -- should be NULL
FROM customer_order_fact
WHERE total_payment_value IS NULL;


-- ----------------------------------------------------------------------------
-- V32: Orders with null review_score
-- Expected: ~646 (delivered orders with no review row)
-- Reviews are optional — this is not an error.
-- ----------------------------------------------------------------------------

SELECT
    SUM(CASE WHEN review_score IS NULL THEN 1 ELSE 0 END)         AS orders_no_review,
    SUM(CASE WHEN review_score IS NOT NULL THEN 1 ELSE 0 END)     AS orders_with_review,
    ROUND(
        100.0 * SUM(CASE WHEN review_score IS NOT NULL THEN 1 ELSE 0 END)
        / COUNT(*), 2)                                            AS review_coverage_pct
FROM customer_order_fact;


-- ----------------------------------------------------------------------------
-- V33: Orders with null delivery_days
-- Expected: exactly 8 (delivered orders with no order_delivered_customer_date)
-- These orders are retained — their purchase and payment data are valid.
-- ----------------------------------------------------------------------------

SELECT
    SUM(CASE WHEN delivery_days IS NULL THEN 1 ELSE 0 END)        AS null_delivery_days,
    SUM(CASE WHEN delivery_days IS NOT NULL THEN 1 ELSE 0 END)    AS non_null_delivery_days,
    SUM(CASE WHEN delivery_days <= 0 THEN 1 ELSE 0 END)           AS zero_or_negative_days
FROM customer_order_fact;


-- ----------------------------------------------------------------------------
-- V34: Revenue field coverage and aggregate comparison
-- total_order_revenue_item_view: should have 0 nulls (always from order_revenue)
-- total_payment_value: should have exactly 1 null
-- Aggregate totals show the scale of divergence between the two revenue views.
-- ----------------------------------------------------------------------------

SELECT
    SUM(CASE WHEN total_order_revenue_item_view IS NULL THEN 1 ELSE 0 END) AS null_item_revenue,
    SUM(CASE WHEN total_payment_value           IS NULL THEN 1 ELSE 0 END) AS null_payment_value,
    ROUND(SUM(total_order_revenue_item_view), 2)                           AS total_item_revenue_brl,
    ROUND(SUM(total_payment_value), 2)                                     AS total_collected_brl,
    ROUND(
        SUM(total_order_revenue_item_view) - SUM(total_payment_value)
    , 2)                                                                   AS aggregate_divergence_brl
FROM customer_order_fact;


-- ----------------------------------------------------------------------------
-- V35: Delivery performance summary
-- Sanity check on derived delivery fields.
-- ----------------------------------------------------------------------------

SELECT
    SUM(CASE WHEN delivered_on_time_flag = 1 THEN 1 ELSE 0 END)   AS delivered_on_time,
    SUM(CASE WHEN delivered_on_time_flag = 0 THEN 1 ELSE 0 END)   AS delivered_late,
    SUM(CASE WHEN delivered_on_time_flag IS NULL THEN 1 ELSE 0 END) AS delivery_date_unknown,
    ROUND(AVG(CASE WHEN delivery_days IS NOT NULL THEN delivery_days END), 1)
                                                                   AS avg_delivery_days,
    MIN(CASE WHEN delivery_days IS NOT NULL THEN delivery_days END) AS min_delivery_days,
    MAX(CASE WHEN delivery_days IS NOT NULL THEN delivery_days END) AS max_delivery_days,
    ROUND(AVG(CASE WHEN delivery_delay_days IS NOT NULL THEN delivery_delay_days END), 1)
                                                                   AS avg_delay_days
FROM customer_order_fact;


-- ----------------------------------------------------------------------------
-- V36: freight_ratio distribution check
-- Sanity check: ratio should be >= 0.  Values > 1.0 are valid but notable.
-- ----------------------------------------------------------------------------

SELECT
    SUM(CASE WHEN freight_ratio IS NULL  THEN 1 ELSE 0 END)       AS null_freight_ratio,
    SUM(CASE WHEN freight_ratio < 0      THEN 1 ELSE 0 END)       AS negative_ratio,
    SUM(CASE WHEN freight_ratio BETWEEN 0 AND 0.5  THEN 1 ELSE 0 END) AS ratio_low,
    SUM(CASE WHEN freight_ratio BETWEEN 0.5 AND 1  THEN 1 ELSE 0 END) AS ratio_mid,
    SUM(CASE WHEN freight_ratio > 1      THEN 1 ELSE 0 END)       AS ratio_above_one,
    ROUND(AVG(freight_ratio), 4)                                  AS avg_freight_ratio
FROM customer_order_fact;
