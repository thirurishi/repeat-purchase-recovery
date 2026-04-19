-- =============================================================================
-- 05_order_sequence.sql
-- Project:   Repeat Purchase Recovery
-- Purpose:   Add purchase-order sequencing to every delivered order so that
--            downstream customer-level marts can answer:
--              - Which order was this for the customer? (1st, 2nd, 3rd …)
--              - How many days between consecutive orders?
--              - How long since the customer's very first purchase?
--              - Is this a first-order or second-order conversion?
--
--            This table is NOT aggregated to customer level. One row per
--            customer × order. Aggregation happens in the next step
--            (customer_summary) which reads from this view.
--
-- Output:    order_sequence
--            Grain: one row per customer_unique_id × order_id
--                   Exactly matches customer_order_fact row count.
--
-- Depends on:  sql/04_customer_order_fact.sql  (customer_order_fact)
--
-- Dialect:   SQLite 3.28.0+  (named WINDOW clause requires 3.28; LAG/LEAD
--            require 3.25.  Current environment: 3.50.4.)
-- Step:      Step 4 of 5 in the implementation plan.
-- =============================================================================


-- =============================================================================
-- SEQUENCING LOGIC
-- =============================================================================
--
-- All window functions are partitioned by customer_unique_id and ordered by
-- (order_purchase_timestamp ASC, order_id ASC).
--
-- ORDER BY choice:
--   Primary:   order_purchase_timestamp ASC  — chronological purchase order
--   Tie-break: order_id ASC                  — deterministic for same-timestamp
--              orders; order_id is a stable UUID string so alphabetical sort
--              is arbitrary but fully reproducible.
--
-- Timestamp note:
--   order_purchase_timestamp is stored as ISO-8601 "YYYY-MM-DD HH:MM:SS" TEXT.
--   SQLite orders TEXT correctly for this format (lexicographic = chronological).
--   JULIANDAY() converts to a fractional day number for arithmetic.
--   CAST(ROUND(..., 0) AS INTEGER) rounds to the nearest whole day.
--
-- Null handling:
--   LAG() on the first row within a partition returns NULL  → first order has
--         no previous_order_id, previous_order_timestamp, or days_since_previous_order.
--   LEAD() on the last row within a partition returns NULL  → last observed order
--         has no next_order_id, next_order_timestamp, or days_until_next_order.
--   MIN()  is computed over the full partition (no ORDER BY, no frame) so it
--         always returns the earliest timestamp regardless of current row.
--
-- Single-order customers:
--   All three of the above are NULL simultaneously. order_sequence_number = 1,
--   is_first_order = 1, is_second_order = 0, days_since_previous_order = NULL,
--   days_until_next_order = NULL, days_since_first_order = 0.
--   This is correct — a customer with one order is simultaneously first and last.
--
-- days_since_previous_order = 0 is valid for the rare case where two orders by
-- the same customer share the same date, distinguished only by order_id.
--
-- =============================================================================

DROP VIEW IF EXISTS order_sequence;

CREATE VIEW order_sequence AS
WITH sequenced AS (
    SELECT
        customer_unique_id,
        order_id,
        order_purchase_timestamp,

        -- Sequence number within this customer's purchase history.
        -- 1 = first delivered order, 2 = second, etc.
        ROW_NUMBER()                        OVER cust_timeline  AS order_sequence_number,

        -- Previous order for this customer (NULL for first order)
        LAG(order_id, 1)                    OVER cust_timeline  AS previous_order_id,
        LAG(order_purchase_timestamp, 1)    OVER cust_timeline  AS previous_order_timestamp,

        -- Next order for this customer (NULL for most-recent/last order)
        LEAD(order_id, 1)                   OVER cust_timeline  AS next_order_id,
        LEAD(order_purchase_timestamp, 1)   OVER cust_timeline  AS next_order_timestamp,

        -- First-ever order timestamp for this customer (same for all rows
        -- of a customer; 0 days from itself; used to compute tenure)
        MIN(order_purchase_timestamp) OVER (PARTITION BY customer_unique_id)
                                                                AS first_order_timestamp

    FROM customer_order_fact

    -- Named window shared by ROW_NUMBER, LAG, and LEAD.
    -- Requires SQLite >= 3.28.  Controls the within-customer ordering.
    WINDOW cust_timeline AS (
        PARTITION BY customer_unique_id
        ORDER BY order_purchase_timestamp ASC,
                 order_id                 ASC   -- deterministic tie-break
    )
)

SELECT
    customer_unique_id,
    order_id,
    order_purchase_timestamp,

    -- ── SEQUENCE IDENTIFIERS ──────────────────────────────────────────────────
    order_sequence_number,                -- 1-based; 1 = first delivered order

    -- ── PREVIOUS ORDER CONTEXT ───────────────────────────────────────────────
    previous_order_id,                    -- NULL for first orders
    previous_order_timestamp,            -- NULL for first orders

    -- ── NEXT ORDER CONTEXT ───────────────────────────────────────────────────
    next_order_id,                        -- NULL for most-recent orders
    next_order_timestamp,                 -- NULL for most-recent orders

    -- ── TIME-GAP FIELDS ───────────────────────────────────────────────────────

    -- Days since this customer's previous delivered order.
    -- NULL for first orders (no previous order exists).
    -- 0 is valid when two orders share the same date (rare tie case).
    CASE
        WHEN previous_order_timestamp IS NULL THEN NULL
        ELSE CAST(ROUND(
            JULIANDAY(order_purchase_timestamp) -
            JULIANDAY(previous_order_timestamp)
        , 0) AS INTEGER)
    END                                                         AS days_since_previous_order,

    -- Days until this customer's next delivered order.
    -- NULL for the most-recently observed order (no future order recorded).
    CASE
        WHEN next_order_timestamp IS NULL THEN NULL
        ELSE CAST(ROUND(
            JULIANDAY(next_order_timestamp) -
            JULIANDAY(order_purchase_timestamp)
        , 0) AS INTEGER)
    END                                                         AS days_until_next_order,

    -- Days elapsed since this customer's very first delivered order.
    -- Always 0 for first orders.  Measures customer tenure at time of purchase.
    CAST(ROUND(
        JULIANDAY(order_purchase_timestamp) -
        JULIANDAY(first_order_timestamp)
    , 0) AS INTEGER)                                            AS days_since_first_order,

    -- ── ORDER POSITION FLAGS ──────────────────────────────────────────────────

    -- 1 if this is the customer's first delivered order; 0 otherwise.
    -- Exactly one row per customer has is_first_order = 1.
    CASE WHEN order_sequence_number = 1 THEN 1 ELSE 0 END       AS is_first_order,

    -- 1 if this is the customer's second delivered order; 0 otherwise.
    -- Only repeat buyers (≥2 delivered orders) have any is_second_order = 1 row.
    CASE WHEN order_sequence_number = 2 THEN 1 ELSE 0 END       AS is_second_order

FROM sequenced;


-- =============================================================================
-- VALIDATION QUERIES
-- =============================================================================
-- Continuing the V-series from Step 3 (last check was V36).
-- All checks are read-only SELECTs.  Expected values derived from confirmed
-- row counts in customer_order_fact.
-- =============================================================================


-- ----------------------------------------------------------------------------
-- V37: Row count — must exactly match customer_order_fact
-- Expected: 0 difference.
-- A non-zero difference means the window function approach changed the row
-- count, which should be impossible (no filtering is applied).
-- ----------------------------------------------------------------------------

SELECT
    (SELECT COUNT(*) FROM customer_order_fact)  AS customer_order_fact_rows,
    (SELECT COUNT(*) FROM order_sequence)        AS order_sequence_rows,
    (SELECT COUNT(*) FROM customer_order_fact) -
    (SELECT COUNT(*) FROM order_sequence)        AS row_difference;


-- ----------------------------------------------------------------------------
-- V38: Duplicate check on (customer_unique_id, order_id)
-- Expected: 0 duplicates.
-- A duplicate would mean the same order appears twice for the same customer
-- in the source, which is not possible if customer_order_fact is grain-safe.
-- ----------------------------------------------------------------------------

SELECT
    'order_sequence duplicate (customer_unique_id, order_id)' AS check_name,
    COUNT(*) AS problem_count
FROM (
    SELECT customer_unique_id, order_id
    FROM order_sequence
    GROUP BY customer_unique_id, order_id
    HAVING COUNT(*) > 1
);


-- ----------------------------------------------------------------------------
-- V39: Null checks on identity and sequence fields
-- customer_unique_id, order_id, and order_sequence_number must all be 0.
-- order_purchase_timestamp must be 0 (confirmed no nulls in customer_order_fact).
-- ----------------------------------------------------------------------------

SELECT
    SUM(CASE WHEN customer_unique_id    IS NULL THEN 1 ELSE 0 END)  AS null_customer_uid,
    SUM(CASE WHEN order_id              IS NULL THEN 1 ELSE 0 END)  AS null_order_id,
    SUM(CASE WHEN order_sequence_number IS NULL THEN 1 ELSE 0 END)  AS null_sequence_number,
    SUM(CASE WHEN order_purchase_timestamp IS NULL THEN 1 ELSE 0 END) AS null_purchase_ts
FROM order_sequence;


-- ----------------------------------------------------------------------------
-- V40: Exactly one first order per customer
-- Expected: 0 customers with more than one is_first_order = 1 row.
-- This would indicate a sequencing bug — ROW_NUMBER() should produce exactly
-- one sequence_number = 1 per customer_unique_id partition.
-- ----------------------------------------------------------------------------

SELECT
    'customers with more than one first order' AS check_name,
    COUNT(*)                                   AS problem_count
FROM (
    SELECT customer_unique_id
    FROM order_sequence
    WHERE is_first_order = 1
    GROUP BY customer_unique_id
    HAVING COUNT(*) > 1
);


-- ----------------------------------------------------------------------------
-- V41: Order sequence number distribution
-- Shows how many orders exist at each sequence position.
-- Sequence 1 = all unique customers; sequence 2+ = repeat buyers.
-- Sequence numbers above the maximum real value should not appear.
-- ----------------------------------------------------------------------------

SELECT
    order_sequence_number,
    COUNT(*)                                                      AS order_count,
    COUNT(DISTINCT customer_unique_id)                            AS unique_customers
FROM order_sequence
GROUP BY order_sequence_number
ORDER BY order_sequence_number;


-- ----------------------------------------------------------------------------
-- V42: First-order and second-order flag summary
-- is_first_order = 1 count must equal COUNT(DISTINCT customer_unique_id).
-- is_second_order = 1 count = customers with >= 2 delivered orders.
-- ----------------------------------------------------------------------------

SELECT
    SUM(is_first_order)                                           AS total_first_orders,
    SUM(is_second_order)                                          AS total_second_orders,
    COUNT(DISTINCT customer_unique_id)                            AS total_distinct_customers,
    SUM(is_first_order) - COUNT(DISTINCT customer_unique_id)      AS first_order_vs_customer_diff
FROM order_sequence;


-- ----------------------------------------------------------------------------
-- V43: days_since_previous_order must be NULL for all first orders
-- Expected: 0 first orders with a non-null days_since_previous_order.
-- A non-zero result means LAG() is returning a value for sequence_number = 1.
-- ----------------------------------------------------------------------------

SELECT
    SUM(CASE WHEN is_first_order = 1
              AND days_since_previous_order IS NOT NULL
             THEN 1 ELSE 0 END) AS first_orders_with_nonnull_gap
FROM order_sequence;


-- ----------------------------------------------------------------------------
-- V44: days_since_first_order must be 0 for all first orders
-- Expected: 0 first orders with days_since_first_order != 0.
-- ----------------------------------------------------------------------------

SELECT
    SUM(CASE WHEN is_first_order = 1
              AND days_since_first_order != 0
             THEN 1 ELSE 0 END) AS first_orders_with_nonzero_tenure
FROM order_sequence;


-- ----------------------------------------------------------------------------
-- V45: days_until_next_order must be NULL for all sequence-maximum orders
-- (The last observed order per customer has no future order.)
-- Expected: 0 most-recent orders with a non-null days_until_next_order.
-- Most-recent = the row where next_order_id IS NULL.
-- ----------------------------------------------------------------------------

SELECT
    SUM(CASE WHEN next_order_id IS NULL
              AND days_until_next_order IS NOT NULL
             THEN 1 ELSE 0 END) AS last_orders_with_nonnull_next_gap
FROM order_sequence;


-- ----------------------------------------------------------------------------
-- V46: Inter-purchase gap distribution (for repeat buyers only)
-- Sanity check: gaps should be positive integers.
-- days_since_previous_order = 0 is valid (same-day orders, tie-broken by order_id).
-- Negative gaps would indicate a sequencing error.
-- ----------------------------------------------------------------------------

SELECT
    SUM(CASE WHEN days_since_previous_order < 0 THEN 1 ELSE 0 END)      AS negative_gaps,
    SUM(CASE WHEN days_since_previous_order = 0 THEN 1 ELSE 0 END)      AS same_day_orders,
    SUM(CASE WHEN days_since_previous_order BETWEEN 1 AND 30 THEN 1 ELSE 0 END)  AS gap_1_30d,
    SUM(CASE WHEN days_since_previous_order BETWEEN 31 AND 90 THEN 1 ELSE 0 END) AS gap_31_90d,
    SUM(CASE WHEN days_since_previous_order BETWEEN 91 AND 180 THEN 1 ELSE 0 END) AS gap_91_180d,
    SUM(CASE WHEN days_since_previous_order > 180 THEN 1 ELSE 0 END)    AS gap_over_180d,
    ROUND(AVG(days_since_previous_order), 1)                            AS avg_gap_days,
    MIN(days_since_previous_order)                                      AS min_gap_days,
    MAX(days_since_previous_order)                                      AS max_gap_days
FROM order_sequence
WHERE days_since_previous_order IS NOT NULL;
