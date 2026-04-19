-- =============================================================================
-- 99_dashboard_views.sql
-- Project:   Repeat Purchase Recovery
-- Purpose:   Dashboard-ready summary views for Power BI.
--            Each view reads only from validated upstream marts (Step 5 and below).
--            No new business logic is introduced here — these views aggregate,
--            rename, and reshape existing mart outputs for direct Power BI use.
--
-- Depends on (all validated through Step 5):
--   customer_first_purchase_mart
--   customer_repeat_status_mart
--   customer_clv
--   retention_cohorts
--   segment_performance_mart
--   churn_signal_mart
--   order_sequence          (for monthly trend only)
--
-- Dialect:   SQLite 3.28.0+
-- Step:      Step 6 of 6  (dashboard export layer)
--
-- Views created:
--   1. executive_kpi_summary
--   2. repeat_purchase_trend_monthly
--   3. cohort_heatmap_source
--   4. segment_summary_dashboard
--   5. clv_distribution_summary
--   6. churn_signal_summary
--   7. repeat_vs_one_time_summary
-- =============================================================================


-- =============================================================================
-- 1. EXECUTIVE KPI SUMMARY
-- =============================================================================
-- Grain:   Single row — one headline number per KPI.
-- Source:  customer_repeat_status_mart, customer_clv
-- Purpose: Top-level scorecard for the Power BI executive overview page.
--
-- Right-censoring notes:
--   raw_repeat_purchase_rate   — uses all customers as denominator (no censoring).
--                                This is the naive rate; use repeat_rate_Nd for
--                                properly adjusted window rates.
--   eligible_customers_Nd      — customers whose first purchase was at least N days
--                                before the dataset's last observed order.  These are
--                                the only customers scored for that window.
--   repeat_rate_Nd             — SUM(flag=1) / COUNT(flag IS NOT NULL); NULLs excluded.
--
-- Median note:
--   SQLite has no native MEDIAN() aggregate.  median_days_to_second_purchase is
--   computed via a ROW_NUMBER window workaround (requires SQLite >= 3.25, confirmed
--   3.50.4 in this environment).  The subquery returns the middle value(s) for
--   odd/even counts using the standard (N+1)/2 and (N+2)/2 index approach.
-- =============================================================================

DROP VIEW IF EXISTS executive_kpi_summary;

CREATE VIEW executive_kpi_summary AS
WITH

base AS (
    SELECT
        COUNT(*)                                                    AS total_customers,
        SUM(has_second_order)                                       AS repeat_buyers,

        -- Raw rate: repeat_buyers / all customers (no window censoring)
        ROUND(SUM(has_second_order) * 1.0 / COUNT(*), 4)           AS raw_repeat_purchase_rate,

        -- Eligible counts per window (customers with full observation exposure)
        SUM(CASE WHEN repeat_within_30d IS NOT NULL THEN 1 ELSE 0 END) AS eligible_customers_30d,
        SUM(CASE WHEN repeat_within_60d IS NOT NULL THEN 1 ELSE 0 END) AS eligible_customers_60d,
        SUM(CASE WHEN repeat_within_90d IS NOT NULL THEN 1 ELSE 0 END) AS eligible_customers_90d,

        -- Window-adjusted repeat rates (NULLs excluded from AVG automatically)
        ROUND(AVG(CAST(repeat_within_30d AS REAL)), 4)              AS repeat_rate_30d,
        ROUND(AVG(CAST(repeat_within_60d AS REAL)), 4)              AS repeat_rate_60d,
        ROUND(AVG(CAST(repeat_within_90d AS REAL)), 4)              AS repeat_rate_90d,

        -- Average days between first and second order (repeat buyers only)
        ROUND(AVG(days_to_second_order), 1)                         AS avg_days_to_second_purchase

    FROM customer_repeat_status_mart
),

-- Total delivered orders (used for total_valid_orders in the output row)
order_count AS (
    SELECT COUNT(*) AS total_valid_orders
    FROM customer_clv   -- one row per customer; lifetime_orders sums their orders
    -- Note: total delivered orders = SUM(lifetime_orders) across all customers
    -- We derive it here to avoid re-scanning customer_order_fact
),

-- Revenue averages from CLV mart
revenue_avgs AS (
    SELECT
        ROUND(AVG(revenue_90d), 2)                                  AS avg_revenue_90d,
        ROUND(AVG(revenue_180d), 2)                                 AS avg_revenue_180d,
        SUM(lifetime_orders)                                        AS total_valid_orders
    FROM customer_clv
),

-- Median days to second purchase (SQLite window function workaround)
-- Operates only over repeat buyers (days_to_second_order IS NOT NULL).
median_calc AS (
    SELECT AVG(CAST(days_to_second_order AS REAL)) AS median_days_to_second_purchase
    FROM (
        SELECT
            days_to_second_order,
            ROW_NUMBER() OVER (ORDER BY days_to_second_order)  AS rn,
            COUNT(*)     OVER ()                               AS cnt
        FROM customer_repeat_status_mart
        WHERE days_to_second_order IS NOT NULL
    )
    WHERE rn IN (
        (cnt + 1) / 2,   -- lower-middle for even counts; middle for odd counts
        (cnt + 2) / 2    -- upper-middle for even counts; same as above for odd
    )
)

SELECT
    ra.total_valid_orders,
    b.total_customers,
    b.repeat_buyers,
    b.raw_repeat_purchase_rate,
    b.eligible_customers_30d,
    b.eligible_customers_60d,
    b.eligible_customers_90d,
    b.repeat_rate_30d,
    b.repeat_rate_60d,
    b.repeat_rate_90d,
    b.avg_days_to_second_purchase,
    mc.median_days_to_second_purchase,
    ra.avg_revenue_90d,
    ra.avg_revenue_180d

FROM base b
CROSS JOIN revenue_avgs ra
CROSS JOIN median_calc  mc;


-- =============================================================================
-- 2. REPEAT PURCHASE TREND MONTHLY
-- =============================================================================
-- Grain:   One row per calendar month (YYYY-MM).
-- Source:  order_sequence, customer_repeat_status_mart
-- Purpose: Monthly trend line for first orders, second orders, and cohort-based
--          repeat outcomes.  Suitable for line/bar charts in Power BI.
--
-- Column definitions:
--   order_month                       — calendar month of the event
--   first_orders                      — customers whose first delivered order was
--                                       placed in this month
--   second_orders                     — customers whose second delivered order was
--                                       placed in this month (placed date, not
--                                       cohort date — may differ from first_orders month)
--   repeat_buyers_identified          — of those who first purchased in this month,
--                                       how many eventually became repeat buyers
--                                       (lifetime flag; not window-censored)
--   cohort_repeat_rate                — repeat_buyers_identified / first_orders
--   avg_days_to_second_purchase       — average days from first to second order for
--                                       customers who first purchased in this month
--                                       and later repeated (NULL months = no repeats)
-- =============================================================================

DROP VIEW IF EXISTS repeat_purchase_trend_monthly;

CREATE VIEW repeat_purchase_trend_monthly AS
WITH

-- Count of first orders placed per calendar month
monthly_first_orders AS (
    SELECT
        STRFTIME('%Y-%m', order_purchase_timestamp)     AS order_month,
        COUNT(*)                                        AS first_orders
    FROM order_sequence
    WHERE is_first_order = 1
    GROUP BY STRFTIME('%Y-%m', order_purchase_timestamp)
),

-- Count of second orders placed per calendar month (by placed date)
monthly_second_orders AS (
    SELECT
        STRFTIME('%Y-%m', order_purchase_timestamp)     AS order_month,
        COUNT(*)                                        AS second_orders
    FROM order_sequence
    WHERE is_second_order = 1
    GROUP BY STRFTIME('%Y-%m', order_purchase_timestamp)
),

-- Cohort-based repeat metrics: anchored on the first purchase month
cohort_repeat AS (
    SELECT
        STRFTIME('%Y-%m', os.order_purchase_timestamp)      AS order_month,
        SUM(rsm.has_second_order)                           AS repeat_buyers_identified,
        ROUND(AVG(CAST(rsm.has_second_order AS REAL)), 4)   AS cohort_repeat_rate,
        ROUND(AVG(rsm.days_to_second_order), 1)             AS avg_days_to_second_purchase
    FROM order_sequence              os
    JOIN customer_repeat_status_mart rsm
        ON os.customer_unique_id = rsm.customer_unique_id
    WHERE os.is_first_order = 1
    GROUP BY STRFTIME('%Y-%m', os.order_purchase_timestamp)
)

SELECT
    mf.order_month,
    mf.first_orders,
    COALESCE(ms.second_orders, 0)               AS second_orders,
    cr.repeat_buyers_identified,
    cr.cohort_repeat_rate,
    cr.avg_days_to_second_purchase

FROM monthly_first_orders   mf
LEFT JOIN monthly_second_orders ms  ON mf.order_month = ms.order_month
LEFT JOIN cohort_repeat         cr  ON mf.order_month = cr.order_month

ORDER BY mf.order_month;


-- =============================================================================
-- 3. COHORT HEATMAP SOURCE
-- =============================================================================
-- Grain:   One row per (cohort_month, retention_period_number).
-- Source:  retention_cohorts (direct passthrough)
-- Purpose: Data source for Power BI cohort retention heatmap.
--          Right-censoring is already applied in retention_cohorts — only
--          observable (cohort_month, period) pairs are included.
--          Period 0 (first purchase month) is included; retention_rate = 1.0.
-- =============================================================================

DROP VIEW IF EXISTS cohort_heatmap_source;

CREATE VIEW cohort_heatmap_source AS
SELECT
    cohort_month,
    retention_period_number,
    customers_in_cohort,
    retained_customers,
    retention_rate
FROM retention_cohorts
ORDER BY cohort_month, retention_period_number;


-- =============================================================================
-- 4. SEGMENT SUMMARY DASHBOARD
-- =============================================================================
-- Grain:   One row per (segment_dimension, segment_bucket).
-- Source:  segment_performance_mart (rename segment_value → segment_bucket)
-- Purpose: Segment comparison table for Power BI slicers and bar charts.
--          All 7 dimensions included (category, order value, basket size,
--          review score, delivery speed, payment type, customer state).
--          Sorted by dimension then by customers descending to surface the
--          largest buckets first in Power BI default view.
-- =============================================================================

DROP VIEW IF EXISTS segment_summary_dashboard;

CREATE VIEW segment_summary_dashboard AS
SELECT
    segment_dimension,
    segment_value                                   AS segment_bucket,
    customers,
    repeat_rate_30d,
    repeat_rate_90d,
    avg_days_to_second_order,
    avg_revenue_90d,
    avg_revenue_180d
FROM segment_performance_mart
ORDER BY segment_dimension, customers DESC;


-- =============================================================================
-- 5. CLV DISTRIBUTION SUMMARY
-- =============================================================================
-- Grain:   One row per clv_band (5 bands: no_revenue, low, mid, high, top).
-- Source:  customer_clv
-- Purpose: Customer value distribution for Power BI waterfall or donut chart.
--          clv_band_order added for correct sorting in Power BI visuals
--          (alphabetical sort on 'high'/'low'/'mid' gives wrong order).
-- =============================================================================

DROP VIEW IF EXISTS clv_distribution_summary;

CREATE VIEW clv_distribution_summary AS
SELECT
    clv_band,
    -- Numeric sort key so Power BI can sort bands correctly low → top
    CASE clv_band
        WHEN 'no_revenue' THEN 0
        WHEN 'low'        THEN 1
        WHEN 'mid'        THEN 2
        WHEN 'high'       THEN 3
        WHEN 'top'        THEN 4
    END                                             AS clv_band_order,
    COUNT(*)                                        AS customers,
    ROUND(AVG(revenue_180d),            2)          AS avg_revenue_180d,
    ROUND(SUM(lifetime_observed_revenue), 2)        AS total_lifetime_observed_revenue
FROM customer_clv
GROUP BY clv_band
ORDER BY clv_band_order;


-- =============================================================================
-- 6. CHURN SIGNAL SUMMARY
-- =============================================================================
-- Grain:   One row per churn signal flag (7 rows total).
-- Source:  churn_signal_mart
-- Purpose: Summary of early-risk signal prevalence.  Suitable for a ranked
--          bar chart showing which signals are most common.
--
-- flagged_rate denominator:
--   For flags with possible NULLs (missing review, delivery unknown, right-
--   censored repeat window), the denominator is eligible customers only
--   (IS NOT NULL), not the full 93,358.  This prevents deflating rates for
--   signals that cannot be evaluated for every customer.
--
-- Flags and their NULL conditions:
--   low_first_review_score_flag      NULL when no review submitted (646 customers)
--   delayed_first_delivery_flag      NULL when delivery date unknown (8 customers)
--   single_item_first_order_flag     Never NULL
--   low_first_order_value_flag       NULL when payment missing (1 customer)
--   high_freight_ratio_flag          NULL when item price = 0 (rare edge case)
--   no_repeat_within_threshold_flag  NULL when right-censored (first_purchase + 90d > max_obs_date)
--   missing_review_flag              Never NULL (1 = no review, 0 = review present)
-- =============================================================================

DROP VIEW IF EXISTS churn_signal_summary;

CREATE VIEW churn_signal_summary AS
SELECT
    signal_name,
    flagged_customers,
    eligible_customers                              AS total_customers,
    ROUND(flagged_customers * 1.0
          / NULLIF(eligible_customers, 0), 4)       AS flagged_rate
FROM (

    SELECT 'low_first_review_score'         AS signal_name,
        SUM(CASE WHEN low_first_review_score_flag = 1     THEN 1 ELSE 0 END) AS flagged_customers,
        SUM(CASE WHEN low_first_review_score_flag IS NOT NULL THEN 1 ELSE 0 END) AS eligible_customers
    FROM churn_signal_mart

    UNION ALL

    SELECT 'delayed_first_delivery',
        SUM(CASE WHEN delayed_first_delivery_flag = 1     THEN 1 ELSE 0 END),
        SUM(CASE WHEN delayed_first_delivery_flag IS NOT NULL THEN 1 ELSE 0 END)
    FROM churn_signal_mart

    UNION ALL

    SELECT 'single_item_first_order',
        SUM(CASE WHEN single_item_first_order_flag = 1    THEN 1 ELSE 0 END),
        SUM(CASE WHEN single_item_first_order_flag IS NOT NULL THEN 1 ELSE 0 END)
    FROM churn_signal_mart

    UNION ALL

    SELECT 'low_first_order_value',
        SUM(CASE WHEN low_first_order_value_flag = 1      THEN 1 ELSE 0 END),
        SUM(CASE WHEN low_first_order_value_flag IS NOT NULL THEN 1 ELSE 0 END)
    FROM churn_signal_mart

    UNION ALL

    SELECT 'high_freight_ratio',
        SUM(CASE WHEN high_freight_ratio_flag = 1         THEN 1 ELSE 0 END),
        SUM(CASE WHEN high_freight_ratio_flag IS NOT NULL THEN 1 ELSE 0 END)
    FROM churn_signal_mart

    UNION ALL

    SELECT 'no_repeat_within_90d',
        SUM(CASE WHEN no_repeat_within_threshold_flag = 1 THEN 1 ELSE 0 END),
        SUM(CASE WHEN no_repeat_within_threshold_flag IS NOT NULL THEN 1 ELSE 0 END)
    FROM churn_signal_mart

    UNION ALL

    SELECT 'missing_review',
        SUM(CASE WHEN missing_review_flag = 1             THEN 1 ELSE 0 END),
        SUM(CASE WHEN missing_review_flag IS NOT NULL     THEN 1 ELSE 0 END)
    FROM churn_signal_mart

)
ORDER BY flagged_rate DESC;


-- =============================================================================
-- 7. REPEAT VS ONE-TIME BUYER SUMMARY
-- =============================================================================
-- Grain:   Two rows — 'repeat_buyer' and 'one_time_buyer'.
-- Source:  customer_repeat_status_mart, customer_first_purchase_mart,
--          customer_clv
-- Purpose: Side-by-side comparison of repeat and one-time buyers across
--          revenue, first-order value, satisfaction, and delivery experience.
--          Drives the "who are our repeat buyers?" narrative in Power BI.
--
-- is_repeat_buyer: 1 = placed >= 2 delivered orders; 0 = exactly 1 order.
--   (Lifetime definition — not window-censored.  A right-censored customer
--    who has not yet had time to repeat is still scored 0 here if they have
--    only one order to date.)
-- avg_first_review_score: NULLs excluded (646 customers with no review).
-- avg_first_delivery_days: NULLs excluded (8 customers with no delivery date).
-- =============================================================================

DROP VIEW IF EXISTS repeat_vs_one_time_summary;

CREATE VIEW repeat_vs_one_time_summary AS
SELECT
    CASE rsm.is_repeat_buyer
        WHEN 1 THEN 'repeat_buyer'
        ELSE        'one_time_buyer'
    END                                             AS buyer_type,
    COUNT(*)                                        AS customers,
    ROUND(AVG(clv.revenue_90d),          2)         AS avg_revenue_90d,
    ROUND(AVG(clv.revenue_180d),         2)         AS avg_revenue_180d,
    ROUND(AVG(fpm.first_order_value),    2)         AS avg_first_order_value,
    -- avg_first_review_score: NULLs (no-review customers) excluded from AVG
    ROUND(AVG(fpm.first_review_score),   2)         AS avg_first_review_score,
    -- avg_first_delivery_days: NULLs (unknown delivery) excluded from AVG
    ROUND(AVG(fpm.first_delivery_days),  1)         AS avg_first_delivery_days

FROM customer_repeat_status_mart        rsm
JOIN customer_first_purchase_mart       fpm
    ON rsm.customer_unique_id = fpm.customer_unique_id
JOIN customer_clv                       clv
    ON rsm.customer_unique_id = clv.customer_unique_id

GROUP BY rsm.is_repeat_buyer
ORDER BY rsm.is_repeat_buyer DESC;   -- repeat_buyer row first


-- =============================================================================
-- VALIDATION QUERIES
-- =============================================================================
-- Continuing the V-series from Step 5 (last check was V56).
-- All checks are read-only SELECTs.
-- =============================================================================


-- ----------------------------------------------------------------------------
-- V57: Row counts — all dashboard views
-- executive_kpi_summary must have exactly 1 row.
-- cohort_heatmap_source must match retention_cohorts row count.
-- clv_distribution_summary must have exactly 5 rows (one per CLV band).
-- churn_signal_summary must have exactly 7 rows (one per flag).
-- repeat_vs_one_time_summary must have exactly 2 rows.
-- ----------------------------------------------------------------------------

SELECT 'executive_kpi_summary'          AS view_name, COUNT(*) AS row_count, 1  AS expected FROM executive_kpi_summary
UNION ALL
SELECT 'repeat_purchase_trend_monthly',   COUNT(*), NULL FROM repeat_purchase_trend_monthly
UNION ALL
SELECT 'cohort_heatmap_source',
    (SELECT COUNT(*) FROM cohort_heatmap_source),
    (SELECT COUNT(*) FROM retention_cohorts)
UNION ALL
SELECT 'segment_summary_dashboard',
    (SELECT COUNT(*) FROM segment_summary_dashboard),
    (SELECT COUNT(*) FROM segment_performance_mart)
UNION ALL
SELECT 'clv_distribution_summary',       COUNT(*), 5  FROM clv_distribution_summary
UNION ALL
SELECT 'churn_signal_summary',           COUNT(*), 7  FROM churn_signal_summary
UNION ALL
SELECT 'repeat_vs_one_time_summary',     COUNT(*), 2  FROM repeat_vs_one_time_summary;


-- ----------------------------------------------------------------------------
-- V58: executive_kpi_summary — no nulls on core numeric KPIs
-- All fields except median (window function result) should be non-null.
-- Expected: 0 nulls on each listed field.
-- ----------------------------------------------------------------------------

SELECT
    CASE WHEN total_valid_orders              IS NULL THEN 1 ELSE 0 END AS null_total_orders,
    CASE WHEN total_customers                 IS NULL THEN 1 ELSE 0 END AS null_total_customers,
    CASE WHEN repeat_buyers                   IS NULL THEN 1 ELSE 0 END AS null_repeat_buyers,
    CASE WHEN raw_repeat_purchase_rate        IS NULL THEN 1 ELSE 0 END AS null_raw_rate,
    CASE WHEN eligible_customers_30d          IS NULL THEN 1 ELSE 0 END AS null_elig_30d,
    CASE WHEN repeat_rate_30d                 IS NULL THEN 1 ELSE 0 END AS null_rate_30d,
    CASE WHEN repeat_rate_90d                 IS NULL THEN 1 ELSE 0 END AS null_rate_90d,
    CASE WHEN avg_days_to_second_purchase     IS NULL THEN 1 ELSE 0 END AS null_avg_days,
    CASE WHEN avg_revenue_90d                 IS NULL THEN 1 ELSE 0 END AS null_avg_rev_90d,
    CASE WHEN avg_revenue_180d                IS NULL THEN 1 ELSE 0 END AS null_avg_rev_180d
FROM executive_kpi_summary;


-- ----------------------------------------------------------------------------
-- V59: Consistency — executive_kpi_summary vs source marts
-- repeat_buyers must equal SUM(has_second_order) in customer_repeat_status_mart.
-- total_customers must equal COUNT(*) in customer_first_purchase_mart.
-- eligible_customers_90d <= total_customers.
-- Expected: all diffs = 0.
-- ----------------------------------------------------------------------------

SELECT
    'repeat_buyers consistency'                 AS check_name,
    (SELECT repeat_buyers FROM executive_kpi_summary) AS from_kpi,
    (SELECT SUM(has_second_order) FROM customer_repeat_status_mart) AS from_mart,
    (SELECT repeat_buyers FROM executive_kpi_summary) -
    (SELECT SUM(has_second_order) FROM customer_repeat_status_mart) AS diff

UNION ALL

SELECT
    'total_customers consistency',
    (SELECT total_customers FROM executive_kpi_summary),
    (SELECT COUNT(*) FROM customer_first_purchase_mart),
    (SELECT total_customers FROM executive_kpi_summary) -
    (SELECT COUNT(*) FROM customer_first_purchase_mart)

UNION ALL

SELECT
    'eligible_90d <= total_customers',
    (SELECT eligible_customers_90d FROM executive_kpi_summary),
    (SELECT total_customers        FROM executive_kpi_summary),
    CASE WHEN
        (SELECT eligible_customers_90d FROM executive_kpi_summary) >
        (SELECT total_customers        FROM executive_kpi_summary)
    THEN 1 ELSE 0 END;


-- ----------------------------------------------------------------------------
-- V60: repeat_purchase_trend_monthly — no duplicate months
-- Each calendar month should appear exactly once.
-- Expected: 0 duplicate months.
-- ----------------------------------------------------------------------------

SELECT
    'duplicate months in repeat_purchase_trend_monthly' AS check_name,
    COUNT(*) AS problem_count
FROM (
    SELECT order_month
    FROM repeat_purchase_trend_monthly
    GROUP BY order_month
    HAVING COUNT(*) > 1
);


-- ----------------------------------------------------------------------------
-- V61: CLV distribution completeness
-- All 5 CLV bands must be present.
-- SUM(customers) across CLV bands must equal total_customers in executive_kpi_summary.
-- Expected: band_count = 5, customer_diff = 0.
-- ----------------------------------------------------------------------------

SELECT
    COUNT(DISTINCT clv_band)                                    AS band_count,
    SUM(customers)                                              AS clv_total_customers,
    (SELECT total_customers FROM executive_kpi_summary)         AS kpi_total_customers,
    SUM(customers) -
    (SELECT total_customers FROM executive_kpi_summary)         AS customer_diff
FROM clv_distribution_summary;


-- ----------------------------------------------------------------------------
-- V62: Churn signal summary — eligible customers plausibility
-- For flags with no NULLs (single_item, missing_review), eligible_customers
-- must equal total_customers from the KPI summary.
-- Expected: diff = 0 for those two flags.
-- ----------------------------------------------------------------------------

SELECT
    signal_name,
    total_customers                                             AS eligible_from_signal,
    (SELECT total_customers FROM executive_kpi_summary)         AS kpi_total,
    total_customers -
    (SELECT total_customers FROM executive_kpi_summary)         AS diff
FROM churn_signal_summary
WHERE signal_name IN ('single_item_first_order', 'missing_review');


-- ----------------------------------------------------------------------------
-- V63: repeat_vs_one_time_summary — customer coverage
-- SUM(customers) across both buyer types must equal total_customers in KPI summary.
-- Expected: diff = 0.
-- ----------------------------------------------------------------------------

SELECT
    SUM(customers)                                              AS summary_total,
    (SELECT total_customers FROM executive_kpi_summary)         AS kpi_total,
    SUM(customers) -
    (SELECT total_customers FROM executive_kpi_summary)         AS diff
FROM repeat_vs_one_time_summary;
