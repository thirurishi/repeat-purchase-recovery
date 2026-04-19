-- =============================================================================
-- 03_order_aggregations.sql
-- Project:   Repeat Purchase Recovery
-- Purpose:   Aggregate item-level and payment-level records to one row per
--            order_id. These two views are the safe join targets for all
--            downstream customer-level marts.
--
--            Without this aggregation step, joining order_items_clean or
--            order_payments_clean directly to customer-level tables would
--            produce a fan-out that inflates every count and sum.
--
-- Outputs:
--   order_revenue       — item-price view of order value + basket composition
--   order_payment_total — collected payment view of order value + method
--
-- Depends on:  sql/02_data_cleaning.sql  (order_items_clean, order_payments_clean,
--                                         products_clean must exist as views)
-- Dialect:     SQLite 3.25.0+  (ROW_NUMBER() used in order_revenue)
-- Step:        Step 2 of 5 in the implementation plan.
-- =============================================================================


-- =============================================================================
-- REVENUE NOTE — two views, two different revenue numbers
-- =============================================================================
--
-- This file produces TWO distinct views of order revenue. They measure
-- different things and will often differ in value for the same order:
--
--   order_revenue.total_order_revenue_item_view
--     = SUM(price) + SUM(freight_value)  from order_items_clean
--     The listed price of each item plus freight.
--     This is what the seller invoiced before any payment method adjustment.
--     Use for: basket analysis, category revenue, freight ratio analysis.
--
--   order_payment_total.total_payment_value
--     = SUM(payment_value)  from order_payments_clean
--     The amount actually collected from the customer, including voucher
--     offsets and split payment methods.
--     Use for: CLV, monetary scoring (RFM), revenue reporting.
--
-- The two will differ when vouchers are applied, when there are rounding
-- differences, or when payment records capture amounts not fully explained
-- by item rows. Never add them together or use them interchangeably.
-- The primary revenue field for customer-level analysis is total_payment_value.
--
-- =============================================================================


-- =============================================================================
-- VIEW 1: order_revenue
-- -----------------------------------------------------------------------------
-- Grain:   One row per order_id
-- Source:  order_items_clean LEFT JOIN products_clean
-- Purpose: Order-level basket summary — item count, product breadth, category
--          composition, and item-price-based revenue.
--
-- primary_category_resolved selection rule:
--   The category with the highest number of line items in the order.
--   Tiebreaker: alphabetical ASC on product_category_resolved (deterministic).
--   For single-item orders (88,863 of 96,478), the rule is trivially the only
--   category present.
--   The resolved value comes from products_clean.product_category_resolved,
--   which is already the COALESCE(english, portuguese, 'unknown') output.
--   Therefore primary_category_resolved is never NULL — it is 'unknown' at
--   worst if all items in the order belong to null-category products.
--
-- Note: total_order_revenue_item_view = total_item_price + total_freight_value.
--   This is the item-price view. See revenue note above before using it
--   as a revenue field in customer-level analysis.
-- =============================================================================

DROP VIEW IF EXISTS order_revenue;

CREATE VIEW order_revenue AS
WITH

-- Step 1: Attach product_category_resolved to every item row.
--   Left join ensures items without a products_clean match are not lost.
--   In practice V15 confirmed zero orphaned items, but LEFT JOIN is defensive.
items_with_category AS (
    SELECT
        i.order_id,
        i.order_item_id,
        i.product_id,
        i.price,
        i.freight_value,
        p.product_category_resolved          -- 'unknown' if product has null category
    FROM order_items_clean i
    LEFT JOIN products_clean p
        ON i.product_id = p.product_id
),

-- Step 2: Aggregate monetary and composition fields at order level.
order_agg AS (
    SELECT
        order_id,
        ROUND(SUM(price), 2)                           AS total_item_price,
        ROUND(SUM(freight_value), 2)                   AS total_freight_value,
        ROUND(SUM(price) + SUM(freight_value), 2)      AS total_order_revenue_item_view,
        COUNT(order_item_id)                           AS total_items,
        COUNT(DISTINCT product_id)                     AS unique_products_count,
        COUNT(DISTINCT product_category_resolved)      AS unique_categories_count
    FROM items_with_category
    GROUP BY order_id
),

-- Step 3: Count items per (order, category) to support primary category ranking.
category_counts AS (
    SELECT
        order_id,
        product_category_resolved,
        COUNT(*) AS items_in_category
    FROM items_with_category
    GROUP BY order_id, product_category_resolved
),

-- Step 4: Rank categories within each order.
--   ROW_NUMBER() guarantees exactly one primary category per order.
--   Order: most items first; alphabetical ASC as the tiebreaker.
category_ranked AS (
    SELECT
        order_id,
        product_category_resolved,
        items_in_category,
        ROW_NUMBER() OVER (
            PARTITION BY order_id
            ORDER BY items_in_category DESC,
                     product_category_resolved ASC
        ) AS rn
    FROM category_counts
)

SELECT
    a.order_id,
    a.total_item_price,
    a.total_freight_value,
    a.total_order_revenue_item_view,
    a.total_items,
    a.unique_products_count,
    a.unique_categories_count,
    r.product_category_resolved              AS primary_category_resolved
FROM order_agg a
JOIN category_ranked r
    ON  a.order_id = r.order_id
    AND r.rn = 1;


-- =============================================================================
-- VIEW 2: order_payment_total
-- -----------------------------------------------------------------------------
-- Grain:   One row per order_id
-- Source:  order_payments_clean
-- Purpose: Collapse multi-row payment records to a single order-level row so
--          downstream joins do not multiply customer-level rows.
--
-- primary_payment_type selection rule:
--   The payment_type of the row with the lowest payment_sequential value.
--   Olist uses payment_sequential to order payment methods within an order,
--   conventionally starting at 1. In split-payment orders (e.g. voucher +
--   credit card) sequential = 1 is the first method applied.
--   However, 78 delivered orders in the source data have no sequential = 1
--   row (payments start at sequential = 2 — a source data quality quirk).
--   To handle this correctly, payment rows are ranked by payment_sequential
--   ASC using ROW_NUMBER(), and the row with rank = 1 (lowest sequential)
--   is used as the primary.  This is equivalent to sequential = 1 for the
--   99,920 orders that start at 1, and avoids nulls for the remaining 78.
--
-- payment_type_count: number of distinct payment types used in the order.
--   1 = standard single-method payment.
--   2+ = split payment (e.g. voucher + credit card).
--   This retains the signal that some customers split payments without needing
--   the full multi-row payment detail in every downstream mart.
--
-- max_installments: largest installment count across all payment rows.
--   Captures the longest installment commitment made by the customer.
--   Installments are a common Brazilian payment behaviour (credit card
--   parcelamento); this field is relevant as a credit exposure proxy.
--   payment_installments = 0 means a single lump-sum payment.
--
-- total_payment_value: see revenue note at top of file. This is the collected
--   amount and the recommended revenue field for all customer-level analysis.
-- =============================================================================

DROP VIEW IF EXISTS order_payment_total;

CREATE VIEW order_payment_total AS
WITH payment_rows_ranked AS (
    -- Rank each payment row within its order by payment_sequential ASC.
    -- seq_rank = 1 selects the lowest-sequential row as the primary payment.
    -- This handles 78 source-data orders where sequential starts at 2
    -- instead of 1 (no sequential = 1 row exists for those orders).
    SELECT
        order_id,
        payment_sequential,
        payment_type,
        payment_installments,
        payment_value,
        ROW_NUMBER() OVER (
            PARTITION BY order_id
            ORDER BY payment_sequential ASC
        ) AS seq_rank
    FROM order_payments_clean
)
SELECT
    order_id,

    -- Collected payment amount (post-voucher, all methods combined)
    ROUND(SUM(payment_value), 2)                                       AS total_payment_value,

    -- Number of distinct payment methods used (1 = single; 2+ = split payment)
    COUNT(DISTINCT payment_type)                                       AS payment_type_count,

    -- Primary payment method: type belonging to the lowest payment_sequential row
    MAX(CASE WHEN seq_rank = 1 THEN payment_type END)                  AS primary_payment_type,

    -- Longest installment plan in the order (0 = single payment; N = N installments)
    MAX(payment_installments)                                          AS max_installments,

    -- Total payment rows per order (audit / split-payment identification)
    COUNT(*)                                                           AS total_payment_records

FROM payment_rows_ranked
GROUP BY order_id;


-- =============================================================================
-- VALIDATION QUERIES
-- =============================================================================
-- Run after creating both views. All checks are read-only SELECT statements.
-- Expected values are derived from the confirmed data inventory and V1-V16
-- results from sql/02_data_cleaning.sql.
-- =============================================================================


-- ----------------------------------------------------------------------------
-- V17: Row count summary
-- Expected:
--   order_revenue       = 96,478  (all delivered orders have items — V12 confirmed 0 gap)
--   order_payment_total = 96,477  (1 delivered order has no payment row — V13 confirmed)
-- ----------------------------------------------------------------------------

SELECT 'order_revenue'       AS view_name, COUNT(*) AS row_count FROM order_revenue
UNION ALL
SELECT 'order_payment_total' AS view_name, COUNT(*) AS row_count FROM order_payment_total;


-- ----------------------------------------------------------------------------
-- V18: Duplicate check — order_revenue (expect 0; one row per order_id)
-- A non-zero result means the CTE logic did not reduce to one row per order.
-- ----------------------------------------------------------------------------

SELECT
    'order_revenue duplicate order_id' AS check_name,
    COUNT(*)                           AS problem_count
FROM (
    SELECT order_id
    FROM order_revenue
    GROUP BY order_id
    HAVING COUNT(*) > 1
);


-- ----------------------------------------------------------------------------
-- V19: Duplicate check — order_payment_total (expect 0; one row per order_id)
-- ----------------------------------------------------------------------------

SELECT
    'order_payment_total duplicate order_id' AS check_name,
    COUNT(*)                                 AS problem_count
FROM (
    SELECT order_id
    FROM order_payment_total
    GROUP BY order_id
    HAVING COUNT(*) > 1
);


-- ----------------------------------------------------------------------------
-- V20: Coverage — delivered orders missing from order_revenue
-- Expected: 0 missing orders.
-- Any non-zero result means an order in orders_clean has no item rows, which
-- should not occur given V12 confirmed 0 gap in the delivered scope.
-- ----------------------------------------------------------------------------

SELECT
    COUNT(*) AS orders_missing_from_revenue
FROM orders_clean o
LEFT JOIN order_revenue r
    ON o.order_id = r.order_id
WHERE r.order_id IS NULL;


-- ----------------------------------------------------------------------------
-- V21: Coverage — delivered orders missing from order_payment_total
-- Expected: 1 (one order with no payment row, confirmed by V13).
-- Returns the order_id so it can be inspected and excluded where needed.
-- ----------------------------------------------------------------------------

SELECT
    o.order_id,
    o.order_purchase_timestamp,
    o.order_status
FROM orders_clean o
LEFT JOIN order_payment_total p
    ON o.order_id = p.order_id
WHERE p.order_id IS NULL;


-- ----------------------------------------------------------------------------
-- V22: Null check — primary_category_resolved in order_revenue
-- Expected: 0 nulls.
-- product_category_resolved in products_clean already resolves to 'unknown'
-- for null-category products. If this returns non-zero, the LEFT JOIN to
-- products_clean may have produced an unresolved null.
-- ----------------------------------------------------------------------------

SELECT
    SUM(CASE WHEN primary_category_resolved IS NULL THEN 1 ELSE 0 END) AS null_primary_category,
    SUM(CASE WHEN primary_category_resolved = 'unknown' THEN 1 ELSE 0 END) AS unknown_category_orders,
    COUNT(*) AS total_orders
FROM order_revenue;


-- ----------------------------------------------------------------------------
-- V23: Null check — primary_payment_type in order_payment_total
-- Expected: 0 nulls.
-- Null would mean an order has no row with payment_sequential = 1 in the
-- cleaned payments table, which is unexpected.
-- ----------------------------------------------------------------------------

SELECT
    SUM(CASE WHEN primary_payment_type IS NULL THEN 1 ELSE 0 END) AS null_primary_payment_type,
    SUM(CASE WHEN total_payment_value  IS NULL THEN 1 ELSE 0 END) AS null_total_payment_value,
    SUM(CASE WHEN total_payment_value <= 0     THEN 1 ELSE 0 END) AS zero_or_negative_payment,
    COUNT(*) AS total_orders
FROM order_payment_total;


-- ----------------------------------------------------------------------------
-- V24: Revenue divergence — orders where the two revenue views disagree
-- These are expected (vouchers, rounding). This query surfaces the scale of
-- the divergence so it is not invisible when CLV queries are written.
-- Compares rounded values to avoid floating-point noise.
-- ----------------------------------------------------------------------------

SELECT
    COUNT(*)                                                                AS orders_with_divergence,
    ROUND(AVG(ABS(r.total_order_revenue_item_view - p.total_payment_value)), 2) AS avg_abs_difference_brl,
    ROUND(MAX(ABS(r.total_order_revenue_item_view - p.total_payment_value)), 2) AS max_abs_difference_brl,
    ROUND(MIN(ABS(r.total_order_revenue_item_view - p.total_payment_value)), 2) AS min_abs_difference_brl
FROM order_revenue r
JOIN order_payment_total p
    ON r.order_id = p.order_id
WHERE ROUND(r.total_order_revenue_item_view, 2) != ROUND(p.total_payment_value, 2);


-- ----------------------------------------------------------------------------
-- V25: Split payment profile — count of orders by payment complexity
-- Confirms split-payment signal is preserved in payment_type_count.
-- ----------------------------------------------------------------------------

SELECT
    total_payment_records,
    payment_type_count,
    COUNT(*) AS order_count
FROM order_payment_total
GROUP BY total_payment_records, payment_type_count
ORDER BY total_payment_records, payment_type_count;


-- ----------------------------------------------------------------------------
-- V26: Top 10 primary categories by order count
-- Sanity check that primary_category_resolved contains sensible values.
-- ----------------------------------------------------------------------------

SELECT
    primary_category_resolved,
    COUNT(*)                            AS order_count,
    ROUND(AVG(total_item_price), 2)     AS avg_item_price,
    ROUND(AVG(total_items), 2)          AS avg_items_per_order
FROM order_revenue
GROUP BY primary_category_resolved
ORDER BY order_count DESC
LIMIT 10;


-- ----------------------------------------------------------------------------
-- V27: Payment type distribution
-- Sanity check that primary_payment_type values are as expected from inventory.
-- Expected types: credit_card (dominant), boleto, voucher, debit_card, not_defined
-- ----------------------------------------------------------------------------

SELECT
    primary_payment_type,
    COUNT(*)                                AS order_count,
    ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM order_payment_total), 2) AS pct_of_orders,
    ROUND(AVG(total_payment_value), 2)      AS avg_payment_value
FROM order_payment_total
GROUP BY primary_payment_type
ORDER BY order_count DESC;
