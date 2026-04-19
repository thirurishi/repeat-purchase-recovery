-- =============================================================================
-- 06_customer_marts.sql
-- Project:   Repeat Purchase Recovery
-- Purpose:   Build six customer-level analytical marts on top of the validated
--            order-sequencing layer (Step 4).  Each mart targets a distinct
--            business question:
--
--              1. customer_first_purchase_mart  — first-order profile
--              2. customer_repeat_status_mart   — repeat / window flags
--              3. customer_clv                  — observed historical value
--              4. retention_cohorts             — cohort x period retention grid
--              5. segment_performance_mart      — segment-level aggregates
--              6. churn_signal_mart             — rule-based early-risk flags
--
-- Depends on:  sql/05_order_sequence.sql  (order_sequence VIEW)
--              sql/04_customer_order_fact.sql  (customer_order_fact VIEW)
-- Step:        Step 5 of 5 in the implementation plan.
--
-- Observation window (Olist dataset):
--   First order:  2016-09-15
--   Last order:   2018-08-29   ← used as the right-censoring boundary
--
-- Right-censoring policy (all time-window marts):
--   A customer with first_purchase_date + N days > max_obs_date has NOT had
--   full exposure to the N-day repeat window.  These customers are assigned
--   NULL (not 0) for that window flag / metric so they do not deflate rates.
--   Only customers with confirmed full exposure are scored 0 (did not repeat)
--   or 1 (repeated).
--
-- Performance note:
--   order_sequence is a VIEW that chains through four other views.  Each mart
--   query re-executes the full window-function pipeline.  For production use
--   or large-dataset validation, materialise order_sequence first:
--     CREATE TABLE order_sequence_mat AS SELECT * FROM order_sequence;
--   then replace order_sequence references in this file with order_sequence_mat.
--
-- Dialect:   SQLite 3.28.0+  (same constraints as upstream layers)
-- =============================================================================


-- =============================================================================
-- 1. CUSTOMER FIRST PURCHASE MART
-- =============================================================================
-- Grain:   one row per customer_unique_id
-- Source:  order_sequence (is_first_order = 1) JOIN customer_order_fact
-- Purpose: Snapshot of every customer's first delivered order — category,
--          payment type, delivery experience, review score, and geography.
--          Drives segment analysis, churn signals, and first-order profiling.
-- =============================================================================

DROP VIEW IF EXISTS customer_first_purchase_mart;

CREATE VIEW customer_first_purchase_mart AS
SELECT
    os.customer_unique_id,

    -- ── ORDER IDENTITY ────────────────────────────────────────────────────────
    os.order_id                                              AS first_order_id,
    DATE(os.order_purchase_timestamp)                        AS first_purchase_date,

    -- ── ORDER VALUE ───────────────────────────────────────────────────────────
    -- total_payment_value: actual collected amount (NULL for 1 missing-payment order)
    cof.total_payment_value                                  AS first_order_value,
    cof.total_item_price                                     AS first_item_price,
    cof.total_freight_value                                  AS first_freight_value,
    -- freight_ratio = freight / item_price; NULL when item_price = 0
    cof.freight_ratio                                        AS first_freight_ratio,

    -- ── BASKET ────────────────────────────────────────────────────────────────
    cof.total_items                                          AS first_total_items,
    cof.unique_products_count                                AS first_unique_products_count,
    cof.unique_categories_count                              AS first_unique_categories_count,
    cof.primary_category_resolved                            AS first_primary_category,

    -- ── PAYMENT ───────────────────────────────────────────────────────────────
    cof.primary_payment_type                                 AS first_payment_type,
    cof.max_installments                                     AS first_installments,

    -- ── REVIEW ────────────────────────────────────────────────────────────────
    -- NULL = no review submitted (646 orders lack a review row)
    cof.review_score                                         AS first_review_score,

    -- ── DELIVERY ──────────────────────────────────────────────────────────────
    -- delivery_days: purchase → actual delivery (NULL for 8 orders with no delivery date)
    cof.delivery_days                                        AS first_delivery_days,
    -- delivery_delay_days: actual − estimated; negative = early, positive = late
    cof.delivery_delay_days                                  AS first_delivery_delay_days,

    -- ── GEOGRAPHY ─────────────────────────────────────────────────────────────
    cof.customer_state                                       AS first_customer_state,
    cof.customer_city                                        AS first_customer_city

FROM order_sequence        os
JOIN customer_order_fact   cof  ON os.order_id = cof.order_id
WHERE os.is_first_order = 1;


-- =============================================================================
-- 2. CUSTOMER REPEAT STATUS MART
-- =============================================================================
-- Grain:   one row per customer_unique_id
-- Source:  order_sequence (first, second, and all rows)
-- Purpose: Defines whether a customer is a repeat buyer and whether they
--          repeated within standard marketing re-engagement windows.
--
-- Right-censoring:
--   repeat_within_Nd = 1   → customer repeated within N days of first purchase
--   repeat_within_Nd = 0   → customer had >= N days of exposure but did NOT repeat
--   repeat_within_Nd = NULL → customer's first purchase was within N days of the
--                             dataset's last recorded order (max_obs_date).
--                             We cannot observe whether they would have repeated;
--                             this customer is excluded from rate calculations.
--
-- max_obs_date = DATE(MAX(order_purchase_timestamp)) across customer_order_fact
-- =============================================================================

DROP VIEW IF EXISTS customer_repeat_status_mart;

CREATE VIEW customer_repeat_status_mart AS
WITH

-- Single-row table: the latest purchase date in the dataset
obs AS (
    SELECT DATE(MAX(order_purchase_timestamp)) AS max_obs_date
    FROM customer_order_fact
),

-- One row per customer: their first delivered order
first_orders AS (
    SELECT
        customer_unique_id,
        order_id                                        AS first_order_id,
        DATE(order_purchase_timestamp)                  AS first_purchase_date
    FROM order_sequence
    WHERE is_first_order = 1
),

-- One row per customer who placed a second delivered order
second_orders AS (
    SELECT
        customer_unique_id,
        DATE(order_purchase_timestamp)                  AS second_purchase_date,
        -- days_since_previous_order already computed upstream via JULIANDAY arithmetic
        days_since_previous_order                       AS days_to_second_order
    FROM order_sequence
    WHERE is_second_order = 1
),

-- Total delivered orders per customer (for lifetime count and is_repeat_buyer)
order_counts AS (
    SELECT
        customer_unique_id,
        COUNT(*)                                        AS total_orders_lifetime
    FROM order_sequence
    GROUP BY customer_unique_id
)

SELECT
    fo.customer_unique_id,
    fo.first_purchase_date,
    so.second_purchase_date,

    -- ── REPEAT BINARY ─────────────────────────────────────────────────────────
    CASE WHEN so.second_purchase_date IS NOT NULL THEN 1 ELSE 0 END
                                                        AS has_second_order,

    -- Days between first and second order (NULL for single-order customers)
    so.days_to_second_order,

    -- ── RIGHT-CENSORED REPEAT WINDOWS ─────────────────────────────────────────
    -- NULL  = insufficient observation time; excluded from rate calculations
    -- 1     = repeated within window
    -- 0     = full observation time elapsed, no repeat

    -- 30-day window
    CASE
        WHEN DATE(fo.first_purchase_date, '+30 days') > obs.max_obs_date  THEN NULL
        WHEN so.days_to_second_order IS NOT NULL
             AND so.days_to_second_order <= 30                            THEN 1
        ELSE 0
    END                                                 AS repeat_within_30d,

    -- 60-day window
    CASE
        WHEN DATE(fo.first_purchase_date, '+60 days') > obs.max_obs_date  THEN NULL
        WHEN so.days_to_second_order IS NOT NULL
             AND so.days_to_second_order <= 60                            THEN 1
        ELSE 0
    END                                                 AS repeat_within_60d,

    -- 90-day window
    CASE
        WHEN DATE(fo.first_purchase_date, '+90 days') > obs.max_obs_date  THEN NULL
        WHEN so.days_to_second_order IS NOT NULL
             AND so.days_to_second_order <= 90                            THEN 1
        ELSE 0
    END                                                 AS repeat_within_90d,

    -- ── LIFETIME SUMMARY ──────────────────────────────────────────────────────
    oc.total_orders_lifetime,
    CASE WHEN oc.total_orders_lifetime > 1 THEN 1 ELSE 0 END
                                                        AS is_repeat_buyer

FROM       first_orders  fo
LEFT JOIN  second_orders so  ON fo.customer_unique_id = so.customer_unique_id
LEFT JOIN  order_counts  oc  ON fo.customer_unique_id = oc.customer_unique_id
CROSS JOIN obs;


-- =============================================================================
-- 3. CUSTOMER CLV  (Observed Historical Value)
-- =============================================================================
-- Grain:   one row per customer_unique_id
-- Source:  order_sequence (for first_purchase_date) + customer_order_fact
-- Purpose: Cumulative revenue and order count in standard time windows measured
--          from the customer's first purchase date.  Windows are inclusive on
--          both ends (day 0 = first purchase, day N = first_purchase_date + N).
--
-- Value field:  total_payment_value  (actual collected amount, post-voucher).
--   The one order with no payment row contributes 0 via COALESCE, not NULL,
--   so lifetime_observed_revenue is never NULL.
--
-- No projected / modelled CLV — all figures are purely observed history.
--
-- CLV band thresholds (documented; adjust if distribution shifts):
--   no_revenue : lifetime_observed_revenue = 0  (missing-payment edge case)
--   low        : > 0  and < 100   (below-average single order)
--   mid        : 100 – < 300      (around-average single order; ≈ p40–p80)
--   high       : 300 – < 700      (high-value order or 2 repeat orders)
--   top        : >= 700            (multiple orders or exceptionally large order)
--
-- avg_order_value_180d uses only the 180-day window orders as the denominator.
-- Since every customer has at least their first order within 180 days of itself,
-- this is never division-by-zero.
-- =============================================================================

DROP VIEW IF EXISTS customer_clv;

CREATE VIEW customer_clv AS
WITH

-- First purchase date per customer (anchor for all windows)
first_purchase AS (
    SELECT
        customer_unique_id,
        DATE(order_purchase_timestamp)                  AS first_purchase_date
    FROM order_sequence
    WHERE is_first_order = 1
),

-- Order-level revenue with purchase date (flattened for window aggregation)
order_revenue_by_customer AS (
    SELECT
        customer_unique_id,
        DATE(order_purchase_timestamp)                  AS purchase_date,
        COALESCE(total_payment_value, 0)                AS payment_value
    FROM customer_order_fact
)

SELECT
    fp.customer_unique_id,

    -- ── REVENUE WINDOWS ───────────────────────────────────────────────────────
    -- Cumulative payment value from first purchase through day N.
    -- Includes the first purchase itself (window is [day 0, day N]).

    ROUND(SUM(CASE
        WHEN orv.purchase_date <= DATE(fp.first_purchase_date, '+30 days')
        THEN orv.payment_value ELSE 0
    END), 2)                                            AS revenue_30d,

    ROUND(SUM(CASE
        WHEN orv.purchase_date <= DATE(fp.first_purchase_date, '+90 days')
        THEN orv.payment_value ELSE 0
    END), 2)                                            AS revenue_90d,

    ROUND(SUM(CASE
        WHEN orv.purchase_date <= DATE(fp.first_purchase_date, '+180 days')
        THEN orv.payment_value ELSE 0
    END), 2)                                            AS revenue_180d,

    ROUND(SUM(orv.payment_value), 2)                    AS lifetime_observed_revenue,

    -- ── ORDER COUNT WINDOWS ───────────────────────────────────────────────────
    COUNT(CASE
        WHEN orv.purchase_date <= DATE(fp.first_purchase_date, '+30 days')
        THEN 1 END)                                     AS orders_30d,

    COUNT(CASE
        WHEN orv.purchase_date <= DATE(fp.first_purchase_date, '+90 days')
        THEN 1 END)                                     AS orders_90d,

    COUNT(CASE
        WHEN orv.purchase_date <= DATE(fp.first_purchase_date, '+180 days')
        THEN 1 END)                                     AS orders_180d,

    COUNT(*)                                            AS lifetime_orders,

    -- ── AVERAGE ORDER VALUE (180-DAY WINDOW) ──────────────────────────────────
    -- Denominator = count of 180-day-window orders; always >= 1.
    ROUND(
        SUM(CASE
            WHEN orv.purchase_date <= DATE(fp.first_purchase_date, '+180 days')
            THEN orv.payment_value ELSE 0
        END)
        /
        CAST(COUNT(CASE
            WHEN orv.purchase_date <= DATE(fp.first_purchase_date, '+180 days')
            THEN 1 END) AS REAL)
    , 2)                                                AS avg_order_value_180d,

    -- ── CLV BAND ──────────────────────────────────────────────────────────────
    -- Rule-of-thumb tiers based on observed lifetime payment totals.
    -- Thresholds reflect the Olist dataset (avg order ≈ R$160).
    -- Revise if data scope or currency changes.
    CASE
        WHEN SUM(orv.payment_value) = 0         THEN 'no_revenue'
        WHEN SUM(orv.payment_value) <  100      THEN 'low'
        WHEN SUM(orv.payment_value) <  300      THEN 'mid'
        WHEN SUM(orv.payment_value) <  700      THEN 'high'
        ELSE                                         'top'
    END                                             AS clv_band

FROM first_purchase                     fp
JOIN order_revenue_by_customer          orv  ON fp.customer_unique_id = orv.customer_unique_id
GROUP BY fp.customer_unique_id, fp.first_purchase_date;


-- =============================================================================
-- 4. RETENTION COHORTS
-- =============================================================================
-- Grain:   one row per (cohort_month, retention_period_number)
-- Source:  order_sequence (first orders) + customer_order_fact (all orders)
-- Purpose: Cohort retention grid suitable for Power BI heatmaps.
--          Each cell answers: "Of the customers who first purchased in
--          cohort_month, how many placed at least one order exactly
--          retention_period_number calendar months later?"
--
-- Definitions:
--   cohort_month            : YYYY-MM of the customer's first delivered order.
--   retention_period_number : integer months elapsed since cohort_month.
--                             0 = same calendar month as first purchase.
--                             1 = the calendar month immediately after, etc.
--   retained_customers      : count of cohort members who placed >= 1 delivered
--                             order during the target calendar month.
--   customers_in_cohort     : all customers in that cohort_month (denominator).
--   retention_rate          : retained_customers / customers_in_cohort.
--
-- Right-censoring:
--   Only (cohort_month, period) pairs where the target calendar month falls
--   within the dataset's observation window are included.  This prevents
--   artificially low retention rates for recent cohorts.
--   Filter:  DATE(cohort_month || '-01', '+N months') <= last observed month.
--
-- Note on period 0:
--   Every customer has exactly one order in period 0 (their first purchase),
--   so retained_customers = customers_in_cohort and retention_rate = 1.0 for
--   all cohort months.  This row is included for completeness — Power BI
--   can hide it or use it as the baseline.
-- =============================================================================

DROP VIEW IF EXISTS retention_cohorts;

CREATE VIEW retention_cohorts AS
WITH

-- Last observed calendar month across the full dataset
obs AS (
    SELECT STRFTIME('%Y-%m', MAX(order_purchase_timestamp)) AS max_obs_month
    FROM customer_order_fact
),

-- Assign each customer to their first-purchase cohort month
customer_cohorts AS (
    SELECT
        customer_unique_id,
        STRFTIME('%Y-%m', order_purchase_timestamp)     AS cohort_month
    FROM order_sequence
    WHERE is_first_order = 1
),

-- Cohort sizes (denominator for all retention rates in this cohort)
cohort_sizes AS (
    SELECT
        cohort_month,
        COUNT(DISTINCT customer_unique_id)              AS customers_in_cohort
    FROM customer_cohorts
    GROUP BY cohort_month
),

-- All delivered orders tagged with the customer's cohort and period offset
orders_with_period AS (
    SELECT
        cc.customer_unique_id,
        cc.cohort_month,
        -- Calendar months elapsed from cohort month to this order's month.
        -- Uses integer arithmetic on STRFTIME year/month components.
        (CAST(STRFTIME('%Y', cof.order_purchase_timestamp) AS INTEGER) -
         CAST(STRFTIME('%Y', cc.cohort_month || '-01')     AS INTEGER)) * 12
        +
        (CAST(STRFTIME('%m', cof.order_purchase_timestamp) AS INTEGER) -
         CAST(STRFTIME('%m', cc.cohort_month || '-01')     AS INTEGER))
                                                        AS retention_period_number
    FROM customer_order_fact  cof
    JOIN customer_cohorts     cc   ON cof.customer_unique_id = cc.customer_unique_id
),

-- Unique (cohort, customer, period) tuples — a customer counts only once per period
-- even if they placed multiple orders in the same calendar month
retained_per_period AS (
    SELECT
        cohort_month,
        retention_period_number,
        COUNT(DISTINCT customer_unique_id)              AS retained_customers
    FROM orders_with_period
    GROUP BY cohort_month, retention_period_number
)

SELECT
    rp.cohort_month,
    rp.retention_period_number,
    cs.customers_in_cohort,
    rp.retained_customers,
    ROUND(rp.retained_customers * 1.0 / cs.customers_in_cohort, 4)
                                                        AS retention_rate

FROM retained_per_period  rp
JOIN cohort_sizes          cs   ON rp.cohort_month = cs.cohort_month
CROSS JOIN obs

-- Right-censoring: exclude periods whose target month is beyond last observation
WHERE DATE(rp.cohort_month || '-01', '+' || rp.retention_period_number || ' months')
      <= DATE(obs.max_obs_month || '-01')

ORDER BY rp.cohort_month, rp.retention_period_number;


-- =============================================================================
-- 5. SEGMENT PERFORMANCE MART
-- =============================================================================
-- Grain:   one row per (segment_dimension, segment_value)
-- Source:  customer_first_purchase_mart JOIN customer_repeat_status_mart
--          JOIN customer_clv
-- Purpose: Compare repeat purchase rates and revenue across meaningful
--          first-order segmentation cuts.  One mart, multiple dimensions via
--          UNION ALL — each block groups by a single dimension.
--
-- Segment dimensions included:
--   first_primary_category    — product category of first order
--   first_order_value_bucket  — payment value tier of first order
--   first_total_items_bucket  — basket size of first order
--   first_review_score_bucket — post-purchase satisfaction signal
--   first_delivery_speed_bucket — delivery days tier (first order)
--   first_payment_type        — payment method of first order
--   first_customer_state      — Brazilian state of customer
--
-- Bucket definitions (documented; adjust thresholds if distribution shifts):
--   first_order_value_bucket:
--     low    = < R$50   (below ~p20; micro purchases)
--     mid    = R$50–149 (around average single item)
--     high   = R$150–399 (large single order)
--     top    = >= R$400  (premium or bundled order)
--     null_payment = first_order_value IS NULL (1 missing-payment order)
--
--   first_total_items_bucket:
--     1 item / 2 items / 3-5 items / 6+ items
--
--   first_review_score_bucket:
--     low (1-2) / mid (3) / high (4-5) / no_review
--
--   first_delivery_speed_bucket (based on delivery_days):
--     fast     = <= 7 days   (below-average; ≈ p25)
--     standard = 8–14 days  (around median ≈ 12.5 days)
--     slow     = 15–30 days (above average)
--     very_slow= > 30 days  (outlier; includes up to 210 days)
--     unknown  = NULL delivery_days (8 orders)
--
-- Metrics:
--   repeat_rate_30d / repeat_rate_90d:
--     AVG of the right-censored repeat flags (NULLs excluded automatically).
--     Rates are only computed over customers with sufficient observation time.
--   avg_days_to_second_order:
--     AVG of days_to_second_order (NULLs = single-order customers, excluded).
--   avg_revenue_90d / avg_revenue_180d:
--     Average cumulative payment value over the respective window.
-- =============================================================================

DROP VIEW IF EXISTS segment_performance_mart;

CREATE VIEW segment_performance_mart AS
WITH

-- Combine all customer-level fields needed for segmentation in one pass
customer_data AS (
    SELECT
        fpm.customer_unique_id,

        -- ── Raw dimension values ───────────────────────────────────────────────
        fpm.first_primary_category,
        fpm.first_payment_type,
        fpm.first_customer_state,

        -- ── Derived bucket columns ─────────────────────────────────────────────

        -- Order value bucket (based on first_order_value = total_payment_value)
        CASE
            WHEN fpm.first_order_value IS NULL      THEN 'null_payment'
            WHEN fpm.first_order_value <   50       THEN 'low (<50)'
            WHEN fpm.first_order_value <  150       THEN 'mid (50-149)'
            WHEN fpm.first_order_value <  400       THEN 'high (150-399)'
            ELSE                                         'top (400+)'
        END                                         AS first_order_value_bucket,

        -- Basket size bucket
        CASE
            WHEN fpm.first_total_items = 1          THEN '1 item'
            WHEN fpm.first_total_items = 2          THEN '2 items'
            WHEN fpm.first_total_items <= 5         THEN '3-5 items'
            ELSE                                         '6+ items'
        END                                         AS first_total_items_bucket,

        -- Review score bucket
        CASE
            WHEN fpm.first_review_score IS NULL     THEN 'no_review'
            WHEN fpm.first_review_score <= 2        THEN 'low (1-2)'
            WHEN fpm.first_review_score  = 3        THEN 'mid (3)'
            ELSE                                         'high (4-5)'
        END                                         AS first_review_score_bucket,

        -- Delivery speed bucket
        CASE
            WHEN fpm.first_delivery_days IS NULL    THEN 'unknown'
            WHEN fpm.first_delivery_days <=  7      THEN 'fast (<=7d)'
            WHEN fpm.first_delivery_days <= 14      THEN 'standard (8-14d)'
            WHEN fpm.first_delivery_days <= 30      THEN 'slow (15-30d)'
            ELSE                                         'very_slow (>30d)'
        END                                         AS first_delivery_speed_bucket,

        -- ── Performance metrics ────────────────────────────────────────────────
        rsm.repeat_within_30d,   -- NULL for right-censored; excluded from AVG
        rsm.repeat_within_90d,   -- NULL for right-censored; excluded from AVG
        rsm.days_to_second_order, -- NULL for single-order customers
        clv.revenue_90d,
        clv.revenue_180d

    FROM customer_first_purchase_mart   fpm
    JOIN customer_repeat_status_mart    rsm  ON fpm.customer_unique_id = rsm.customer_unique_id
    JOIN customer_clv                   clv  ON fpm.customer_unique_id = clv.customer_unique_id
)

-- ── DIMENSION 1: first_primary_category ────────────────────────────────────
SELECT
    'first_primary_category'                            AS segment_dimension,
    COALESCE(first_primary_category, 'unknown')         AS segment_value,
    COUNT(*)                                            AS customers,
    ROUND(AVG(CAST(repeat_within_30d AS REAL)), 4)      AS repeat_rate_30d,
    ROUND(AVG(CAST(repeat_within_90d AS REAL)), 4)      AS repeat_rate_90d,
    ROUND(AVG(days_to_second_order), 1)                 AS avg_days_to_second_order,
    ROUND(AVG(revenue_90d), 2)                          AS avg_revenue_90d,
    ROUND(AVG(revenue_180d), 2)                         AS avg_revenue_180d
FROM customer_data
GROUP BY first_primary_category

UNION ALL

-- ── DIMENSION 2: first_order_value_bucket ──────────────────────────────────
SELECT
    'first_order_value_bucket',
    first_order_value_bucket,
    COUNT(*),
    ROUND(AVG(CAST(repeat_within_30d AS REAL)), 4),
    ROUND(AVG(CAST(repeat_within_90d AS REAL)), 4),
    ROUND(AVG(days_to_second_order), 1),
    ROUND(AVG(revenue_90d), 2),
    ROUND(AVG(revenue_180d), 2)
FROM customer_data
GROUP BY first_order_value_bucket

UNION ALL

-- ── DIMENSION 3: first_total_items_bucket ──────────────────────────────────
SELECT
    'first_total_items_bucket',
    first_total_items_bucket,
    COUNT(*),
    ROUND(AVG(CAST(repeat_within_30d AS REAL)), 4),
    ROUND(AVG(CAST(repeat_within_90d AS REAL)), 4),
    ROUND(AVG(days_to_second_order), 1),
    ROUND(AVG(revenue_90d), 2),
    ROUND(AVG(revenue_180d), 2)
FROM customer_data
GROUP BY first_total_items_bucket

UNION ALL

-- ── DIMENSION 4: first_review_score_bucket ─────────────────────────────────
SELECT
    'first_review_score_bucket',
    first_review_score_bucket,
    COUNT(*),
    ROUND(AVG(CAST(repeat_within_30d AS REAL)), 4),
    ROUND(AVG(CAST(repeat_within_90d AS REAL)), 4),
    ROUND(AVG(days_to_second_order), 1),
    ROUND(AVG(revenue_90d), 2),
    ROUND(AVG(revenue_180d), 2)
FROM customer_data
GROUP BY first_review_score_bucket

UNION ALL

-- ── DIMENSION 5: first_delivery_speed_bucket ───────────────────────────────
SELECT
    'first_delivery_speed_bucket',
    first_delivery_speed_bucket,
    COUNT(*),
    ROUND(AVG(CAST(repeat_within_30d AS REAL)), 4),
    ROUND(AVG(CAST(repeat_within_90d AS REAL)), 4),
    ROUND(AVG(days_to_second_order), 1),
    ROUND(AVG(revenue_90d), 2),
    ROUND(AVG(revenue_180d), 2)
FROM customer_data
GROUP BY first_delivery_speed_bucket

UNION ALL

-- ── DIMENSION 6: first_payment_type ────────────────────────────────────────
SELECT
    'first_payment_type',
    COALESCE(first_payment_type, 'unknown'),
    COUNT(*),
    ROUND(AVG(CAST(repeat_within_30d AS REAL)), 4),
    ROUND(AVG(CAST(repeat_within_90d AS REAL)), 4),
    ROUND(AVG(days_to_second_order), 1),
    ROUND(AVG(revenue_90d), 2),
    ROUND(AVG(revenue_180d), 2)
FROM customer_data
GROUP BY first_payment_type

UNION ALL

-- ── DIMENSION 7: first_customer_state ──────────────────────────────────────
SELECT
    'first_customer_state',
    COALESCE(first_customer_state, 'unknown'),
    COUNT(*),
    ROUND(AVG(CAST(repeat_within_30d AS REAL)), 4),
    ROUND(AVG(CAST(repeat_within_90d AS REAL)), 4),
    ROUND(AVG(days_to_second_order), 1),
    ROUND(AVG(revenue_90d), 2),
    ROUND(AVG(revenue_180d), 2)
FROM customer_data
GROUP BY first_customer_state;


-- =============================================================================
-- 6. CHURN SIGNAL MART
-- =============================================================================
-- Grain:   one row per customer_unique_id
-- Source:  customer_first_purchase_mart JOIN customer_repeat_status_mart
-- Purpose: Rule-based binary flags that identify early risk signals from the
--          customer's first-order experience.  These are OBSERVATION-BASED
--          business rules, not predicted scores or ML outputs.
--
-- Flag values:
--   1    → risk signal is present
--   0    → risk signal is absent
--   NULL → cannot be evaluated (missing data or right-censored; see per-flag notes)
--
-- Threshold documentation (adjust if business rules change):
--
--   low_first_review_score_flag      : review_score IN (1, 2)
--                                      NULL if no review submitted
--
--   delayed_first_delivery_flag      : delivery_delay_days > 0 (arrived after estimated)
--                                      NULL if delivery date is unknown (8 orders)
--
--   single_item_first_order_flag     : total_items = 1
--                                      Always evaluable; no NULLs expected
--
--   low_first_order_value_flag       : first_order_value < R$50
--                                      NULL if payment row is missing (1 order)
--                                      Threshold: ~p15 of order values; "micro purchase"
--
--   high_freight_ratio_flag          : first_freight_ratio > 0.5
--                                      (freight > 50% of item price)
--                                      NULL if freight_ratio IS NULL (zero-price item edge case)
--                                      Dataset average freight_ratio ≈ 0.31
--
--   no_repeat_within_threshold_flag  : threshold = 90 days after first purchase
--                                      1 = had full 90-day exposure but did NOT repeat
--                                      0 = repeated within 90 days
--                                      NULL = right-censored (first_purchase + 90d > max_obs_date)
--                                      Rationale: 90 days covers ~85% of observed repeat buyers
--
--   missing_review_flag              : review_score IS NULL
--                                      A missing review may indicate disengagement
--                                      or a very poor experience
-- =============================================================================

DROP VIEW IF EXISTS churn_signal_mart;

CREATE VIEW churn_signal_mart AS
SELECT
    fpm.customer_unique_id,

    -- ── EXPERIENCE QUALITY FLAGS ───────────────────────────────────────────────

    -- Low first review score (1 or 2 out of 5)
    -- NULL when no review was submitted (review_score IS NULL)
    CASE
        WHEN fpm.first_review_score IS NULL             THEN NULL
        WHEN fpm.first_review_score <= 2                THEN 1
        ELSE                                                 0
    END                                                 AS low_first_review_score_flag,

    -- Delivered after the estimated delivery date (positive delay)
    -- NULL for the 8 orders with unknown actual delivery date
    CASE
        WHEN fpm.first_delivery_delay_days IS NULL      THEN NULL
        WHEN fpm.first_delivery_delay_days > 0          THEN 1
        ELSE                                                 0
    END                                                 AS delayed_first_delivery_flag,

    -- ── ORDER PROFILE FLAGS ───────────────────────────────────────────────────

    -- Single-item first order (no basket depth; no cross-sell exposure)
    -- Always evaluable — total_items is never NULL in customer_order_fact
    CASE
        WHEN fpm.first_total_items = 1                  THEN 1
        ELSE                                                 0
    END                                                 AS single_item_first_order_flag,

    -- First order below R$50 (micro purchase; threshold ≈ p15 of payment values)
    -- NULL when total_payment_value is missing (1 order has no payment row)
    CASE
        WHEN fpm.first_order_value IS NULL              THEN NULL
        WHEN fpm.first_order_value < 50                 THEN 1
        ELSE                                                 0
    END                                                 AS low_first_order_value_flag,

    -- Freight cost exceeds 50% of item price (high shipping burden)
    -- NULL when freight_ratio IS NULL (item price was 0 — denominator undefined)
    CASE
        WHEN fpm.first_freight_ratio IS NULL            THEN NULL
        WHEN fpm.first_freight_ratio > 0.5              THEN 1
        ELSE                                                 0
    END                                                 AS high_freight_ratio_flag,

    -- ── REPEAT BEHAVIOUR FLAG ─────────────────────────────────────────────────

    -- No second order within 90 days of first purchase.
    -- Uses the right-censored repeat_within_90d from customer_repeat_status_mart:
    --   0 in rsm  → customer repeated   → flag = 0 (not a signal)
    --   1 in rsm  → customer repeated   → flag = 0 (not a signal)
    --   0 in rsm (no repeat, full exposure) → flag = 1 (risk present)
    --   NULL in rsm (censored)           → flag = NULL (unknown; do not score)
    CASE
        WHEN rsm.repeat_within_90d IS NULL              THEN NULL
        WHEN rsm.repeat_within_90d = 0                  THEN 1
        ELSE                                                 0
    END                                                 AS no_repeat_within_threshold_flag,

    -- ── REVIEW PRESENCE FLAG ──────────────────────────────────────────────────

    -- Review was never submitted for the first order
    -- (646 orders lack a review; these customers never engaged post-purchase)
    CASE
        WHEN fpm.first_review_score IS NULL             THEN 1
        ELSE                                                 0
    END                                                 AS missing_review_flag

FROM customer_first_purchase_mart   fpm
JOIN customer_repeat_status_mart    rsm  ON fpm.customer_unique_id = rsm.customer_unique_id;


-- =============================================================================
-- VALIDATION QUERIES
-- =============================================================================
-- Continuing V-series from Step 4 (last check was V46).
-- All checks are read-only SELECTs.
-- =============================================================================


-- ----------------------------------------------------------------------------
-- V47: Row counts for all customer-level marts must equal distinct customers
-- Expected: all diffs = 0.  Each mart must have exactly one row per customer.
-- ----------------------------------------------------------------------------

SELECT
    'customer_first_purchase_mart'  AS mart,
    (SELECT COUNT(DISTINCT customer_unique_id) FROM customer_order_fact) AS expected,
    (SELECT COUNT(*) FROM customer_first_purchase_mart)                  AS actual,
    (SELECT COUNT(*) FROM customer_first_purchase_mart) -
    (SELECT COUNT(DISTINCT customer_unique_id) FROM customer_order_fact) AS diff
UNION ALL
SELECT
    'customer_repeat_status_mart',
    (SELECT COUNT(DISTINCT customer_unique_id) FROM customer_order_fact),
    (SELECT COUNT(*) FROM customer_repeat_status_mart),
    (SELECT COUNT(*) FROM customer_repeat_status_mart) -
    (SELECT COUNT(DISTINCT customer_unique_id) FROM customer_order_fact)
UNION ALL
SELECT
    'customer_clv',
    (SELECT COUNT(DISTINCT customer_unique_id) FROM customer_order_fact),
    (SELECT COUNT(*) FROM customer_clv),
    (SELECT COUNT(*) FROM customer_clv) -
    (SELECT COUNT(DISTINCT customer_unique_id) FROM customer_order_fact)
UNION ALL
SELECT
    'churn_signal_mart',
    (SELECT COUNT(DISTINCT customer_unique_id) FROM customer_order_fact),
    (SELECT COUNT(*) FROM churn_signal_mart),
    (SELECT COUNT(*) FROM churn_signal_mart) -
    (SELECT COUNT(DISTINCT customer_unique_id) FROM customer_order_fact);


-- ----------------------------------------------------------------------------
-- V48: No duplicate customer_unique_id in the four customer-level marts
-- Expected: 0 duplicates in each mart.
-- ----------------------------------------------------------------------------

SELECT 'customer_first_purchase_mart'  AS mart,
       COUNT(*) - COUNT(DISTINCT customer_unique_id) AS duplicate_customers
FROM customer_first_purchase_mart
UNION ALL
SELECT 'customer_repeat_status_mart',
       COUNT(*) - COUNT(DISTINCT customer_unique_id)
FROM customer_repeat_status_mart
UNION ALL
SELECT 'customer_clv',
       COUNT(*) - COUNT(DISTINCT customer_unique_id)
FROM customer_clv
UNION ALL
SELECT 'churn_signal_mart',
       COUNT(*) - COUNT(DISTINCT customer_unique_id)
FROM churn_signal_mart;


-- ----------------------------------------------------------------------------
-- V49: Repeat flag sanity
-- has_second_order = 1  ←→  days_to_second_order IS NOT NULL
-- has_second_order = 0  ←→  days_to_second_order IS NULL
-- Expected: 0 violations.
-- ----------------------------------------------------------------------------

SELECT
    'has_second_order=1 but days_to_second_order IS NULL' AS check_name,
    COUNT(*) AS violations
FROM customer_repeat_status_mart
WHERE has_second_order = 1 AND days_to_second_order IS NULL
UNION ALL
SELECT
    'has_second_order=0 but days_to_second_order IS NOT NULL',
    COUNT(*)
FROM customer_repeat_status_mart
WHERE has_second_order = 0 AND days_to_second_order IS NOT NULL;


-- ----------------------------------------------------------------------------
-- V50: Repeat window monotonicity
-- repeat_within_30d <= repeat_within_60d <= repeat_within_90d
-- (A customer who repeated within 30d must also count as within 60d and 90d.)
-- Expected: 0 violations.
-- Note: NULLs are excluded from comparisons.
-- ----------------------------------------------------------------------------

SELECT
    'repeat_within_30d=1 but repeat_within_60d=0' AS check_name,
    COUNT(*) AS violations
FROM customer_repeat_status_mart
WHERE repeat_within_30d = 1 AND repeat_within_60d = 0
UNION ALL
SELECT
    'repeat_within_60d=1 but repeat_within_90d=0',
    COUNT(*)
FROM customer_repeat_status_mart
WHERE repeat_within_60d = 1 AND repeat_within_90d = 0
UNION ALL
SELECT
    'repeat_within_30d=1 but repeat_within_90d=0',
    COUNT(*)
FROM customer_repeat_status_mart
WHERE repeat_within_30d = 1 AND repeat_within_90d = 0;


-- ----------------------------------------------------------------------------
-- V51: CLV window monotonicity
-- revenue_30d <= revenue_90d <= revenue_180d <= lifetime_observed_revenue
-- orders_30d  <= orders_90d  <= orders_180d  <= lifetime_orders
-- Expected: 0 violations.
-- (Equality is valid — all additional orders may fall outside 180d window.)
-- ----------------------------------------------------------------------------

SELECT
    'revenue_30d > revenue_90d' AS check_name,
    COUNT(*) AS violations
FROM customer_clv WHERE revenue_30d > revenue_90d
UNION ALL
SELECT 'revenue_90d > revenue_180d',
    COUNT(*) FROM customer_clv WHERE revenue_90d > revenue_180d
UNION ALL
SELECT 'revenue_180d > lifetime_observed_revenue',
    COUNT(*) FROM customer_clv WHERE revenue_180d > lifetime_observed_revenue
UNION ALL
SELECT 'orders_30d > orders_90d',
    COUNT(*) FROM customer_clv WHERE orders_30d > orders_90d
UNION ALL
SELECT 'orders_90d > orders_180d',
    COUNT(*) FROM customer_clv WHERE orders_90d > orders_180d
UNION ALL
SELECT 'orders_180d > lifetime_orders',
    COUNT(*) FROM customer_clv WHERE orders_180d > lifetime_orders;


-- ----------------------------------------------------------------------------
-- V52: CLV baseline sanity
-- Every customer has at least 1 order and revenue_30d > 0 (their first purchase
-- is always within 30 days of itself).  The one missing-payment customer is the
-- only valid exception: revenue_30d = 0.
-- Expected: orders_30d >= 1 for all customers; <= 1 customer with revenue_30d = 0.
-- ----------------------------------------------------------------------------

SELECT
    'customers with orders_30d < 1'          AS check_name,
    COUNT(*)                                  AS found,
    0                                         AS expected
FROM customer_clv
WHERE orders_30d < 1
UNION ALL
SELECT
    'customers with revenue_30d = 0 (expect 1)',
    COUNT(*),
    1
FROM customer_clv
WHERE revenue_30d = 0;


-- ----------------------------------------------------------------------------
-- V53: Cohort retention row counts
-- Shows how many (cohort_month, period) pairs exist and the period range.
-- Used to confirm the right-censoring filter is working and heatmap will be
-- complete for all observable periods.
-- ----------------------------------------------------------------------------

SELECT
    COUNT(*)                                            AS total_cohort_period_rows,
    COUNT(DISTINCT cohort_month)                        AS distinct_cohorts,
    MIN(cohort_month)                                   AS first_cohort,
    MAX(cohort_month)                                   AS last_cohort,
    MIN(retention_period_number)                        AS min_period,
    MAX(retention_period_number)                        AS max_period,
    SUM(CASE WHEN retention_period_number = 0 THEN 1 ELSE 0 END) AS period_0_rows,
    SUM(CASE WHEN retention_rate IS NULL THEN 1 ELSE 0 END)       AS null_rates
FROM retention_cohorts;


-- ----------------------------------------------------------------------------
-- V54: Null checks on key identity fields
-- Expected: 0 nulls in all listed fields.
-- ----------------------------------------------------------------------------

SELECT
    'customer_first_purchase_mart.customer_unique_id'   AS field,
    SUM(CASE WHEN customer_unique_id IS NULL THEN 1 ELSE 0 END) AS nulls
FROM customer_first_purchase_mart
UNION ALL
SELECT
    'customer_first_purchase_mart.first_order_id',
    SUM(CASE WHEN first_order_id IS NULL THEN 1 ELSE 0 END)
FROM customer_first_purchase_mart
UNION ALL
SELECT
    'customer_first_purchase_mart.first_purchase_date',
    SUM(CASE WHEN first_purchase_date IS NULL THEN 1 ELSE 0 END)
FROM customer_first_purchase_mart
UNION ALL
SELECT
    'customer_repeat_status_mart.customer_unique_id',
    SUM(CASE WHEN customer_unique_id IS NULL THEN 1 ELSE 0 END)
FROM customer_repeat_status_mart
UNION ALL
SELECT
    'customer_clv.customer_unique_id',
    SUM(CASE WHEN customer_unique_id IS NULL THEN 1 ELSE 0 END)
FROM customer_clv
UNION ALL
SELECT
    'churn_signal_mart.customer_unique_id',
    SUM(CASE WHEN customer_unique_id IS NULL THEN 1 ELSE 0 END)
FROM churn_signal_mart;


-- ----------------------------------------------------------------------------
-- V55: Right-censoring coverage summary
-- Shows how many customers are eligible (have full exposure) vs censored
-- for each repeat window.
-- Expected: censored counts decrease as window shrinks (30d censored > 90d censored).
-- ----------------------------------------------------------------------------

SELECT
    'repeat_within_30d' AS window_name,
    SUM(CASE WHEN repeat_within_30d IS NOT NULL THEN 1 ELSE 0 END) AS eligible_customers,
    SUM(CASE WHEN repeat_within_30d IS     NULL THEN 1 ELSE 0 END) AS censored_customers,
    ROUND(SUM(CASE WHEN repeat_within_30d = 1 THEN 1 ELSE 0 END) * 100.0
          / NULLIF(SUM(CASE WHEN repeat_within_30d IS NOT NULL THEN 1 ELSE 0 END), 0), 2) AS repeat_rate_pct
FROM customer_repeat_status_mart
UNION ALL
SELECT
    'repeat_within_60d',
    SUM(CASE WHEN repeat_within_60d IS NOT NULL THEN 1 ELSE 0 END),
    SUM(CASE WHEN repeat_within_60d IS     NULL THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN repeat_within_60d = 1 THEN 1 ELSE 0 END) * 100.0
          / NULLIF(SUM(CASE WHEN repeat_within_60d IS NOT NULL THEN 1 ELSE 0 END), 0), 2)
FROM customer_repeat_status_mart
UNION ALL
SELECT
    'repeat_within_90d',
    SUM(CASE WHEN repeat_within_90d IS NOT NULL THEN 1 ELSE 0 END),
    SUM(CASE WHEN repeat_within_90d IS     NULL THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN repeat_within_90d = 1 THEN 1 ELSE 0 END) * 100.0
          / NULLIF(SUM(CASE WHEN repeat_within_90d IS NOT NULL THEN 1 ELSE 0 END), 0), 2)
FROM customer_repeat_status_mart;


-- ----------------------------------------------------------------------------
-- V56: Segment performance mart completeness
-- Shows the number of rows per dimension — confirms all 7 dimensions produced
-- at least one bucket row and no dimension is empty.
-- ----------------------------------------------------------------------------

SELECT
    segment_dimension,
    COUNT(*)          AS bucket_count,
    SUM(customers)    AS total_customers_covered
FROM segment_performance_mart
GROUP BY segment_dimension
ORDER BY segment_dimension;
