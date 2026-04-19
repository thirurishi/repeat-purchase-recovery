# Metric Definitions

**Dataset:** Olist Brazilian E-Commerce Public Dataset
**Last updated:** 2026-04-13

---

## Purpose

This document defines every metric used in the Repeat Purchase Recovery analysis. Definitions are grounded in the actual Olist data model and cleaned base tables. Each metric specifies its grain, the logic used to compute it, and why it matters to the analysis.

These definitions are the single source of truth for aligning SQL, Python, notebooks, and the Power BI dashboard. If a metric name appears anywhere in this project, it should match exactly what is defined here.

---

## Scope and Business Rules

### Valid Order Definition

A valid order in this analysis is an order with `order_status = 'delivered'` in `olist_orders_dataset`. All metrics operate on this scope unless explicitly stated otherwise.

The following statuses are excluded from all first-pass metrics: `canceled`, `unavailable`, `shipped`, `invoiced`, `processing`, `created`, `approved`. This produces a population of **96,478 valid orders** from the Olist dataset.

### Customer Key Definition

The person-level customer identifier is `customer_unique_id` from `olist_customers_dataset`. It is accessed by joining `olist_orders_dataset` to `olist_customers_dataset` on `customer_id`.

`customer_id` alone is **not a valid customer identifier for lifecycle analysis** — it is order-scoped and generates a new value per order, even for the same person. Using `customer_id` directly will make every customer appear to be a one-time buyer.

All customer-level metrics group by `customer_unique_id`.

### Revenue Definition

The primary revenue field is `payment_value` from `olist_order_payments_dataset`, aggregated as `SUM(payment_value) GROUP BY order_id` to produce `total_payment_value` per order. This is what the customer actually paid, including any voucher application.

A secondary revenue field, `price` from `olist_order_items_dataset`, is used for category-level and item-level analysis only. It represents the listed item price before any payment method effects.

Freight (`freight_value` from `olist_order_items_dataset`) is tracked separately and not automatically included in revenue figures unless explicitly stated.

### Treatment of Recent Customers

The Olist dataset spans September 2016 to October 2018 — approximately 25 months. Customers who placed their first order close to the dataset end date have had little time to make a second purchase, which downward-biases any raw repeat rate calculation.

For time-windowed metrics (repeat within 30/60/90 days, second order conversion rate), the denominator is restricted to customers whose first order was placed at least N days before the dataset end date. Customers who have not yet had enough time to be observed in the window are excluded from the denominator for that metric. This is noted explicitly in each affected metric.

Metrics that do not restrict the denominator by exposure time (e.g. raw repeat purchase rate) are labelled as snapshot rates and interpreted accordingly.

### Delivered-Only Scope

All metrics operate on delivered orders. No canceled, in-transit, or unfulfilled orders contribute to purchase counts, revenue, retention rates, or any derived signals unless a metric explicitly states otherwise.

---

## Volume Metrics

---

### Total Customers

| | |
|---|---|
| **Definition** | Count of distinct persons who have placed at least one valid (delivered) order. |
| **Grain** | Single aggregate value. |
| **Formula** | `COUNT(DISTINCT customer_unique_id)` from `customer_summary`. |
| **Olist baseline** | 96,096 unique customers across 96,478 delivered orders. |
| **Why it matters** | Establishes the denominator for all customer-level rate metrics. Must be computed on `customer_unique_id`, not `customer_id`. |

---

### Total Valid Orders

| | |
|---|---|
| **Definition** | Count of delivered orders in scope. |
| **Grain** | Single aggregate value. |
| **Formula** | `COUNT(order_id)` from `orders_clean`. |
| **Olist baseline** | 96,478 delivered orders. |
| **Why it matters** | Establishes the order-level population for AOV, delay rate, and review score calculations. |

---

## Repeat Purchase Metrics

---

### Repeat Purchase Rate

| | |
|---|---|
| **Definition** | The percentage of customers who have placed at least two delivered orders. |
| **Grain** | Customer-level (`customer_unique_id`). Single aggregate value. |
| **Formula** | Count of customers where `total_orders > 1` in `customer_summary`, divided by total customer count. Multiply by 100. |
| **Olist baseline** | 3.12% (2,997 of 96,096 customers placed 2+ orders). |
| **Note** | This is a raw snapshot rate — it includes all customers regardless of how recently they were acquired. Customers with very recent first orders pull this figure down. Use Second Order Conversion Rate for a right-censored alternative. |
| **Why it matters** | The headline retention metric for this project. Low values indicate most revenue is driven by first-order acquisition, not loyalty. |

---

### Second Order Conversion Rate

| | |
|---|---|
| **Definition** | The percentage of customers who went on to place a second delivered order, measured only among customers whose first order was placed at least 90 days before the dataset end date. |
| **Grain** | Customer-level. Restricted to the qualifying cohort (first order ≤ dataset end − 90 days). |
| **Formula** | Count of qualifying customers where `total_orders > 1`, divided by count of all qualifying customers. Multiply by 100. |
| **Note** | The 90-day cutoff is the default. This metric should also be computed at 30-day and 60-day cutoffs to align with the repeat-within-N-days metrics. The qualifying cohort denominator will be smaller than the total customer count. |
| **Why it matters** | Removes the right-censoring bias introduced by recently acquired customers. Provides a fairer rate for cohort benchmarking and trend analysis. |

---

### One-Time Buyer Rate

| | |
|---|---|
| **Definition** | The percentage of customers who have placed exactly one delivered order. |
| **Grain** | Customer-level. Single aggregate value. |
| **Formula** | Count of customers where `total_orders = 1` in `customer_summary`, divided by total customer count. Multiply by 100. Equivalent to `100 − Repeat Purchase Rate`. |
| **Olist baseline** | 96.9% (93,099 of 96,096 customers placed exactly one order). |
| **Why it matters** | The complement of repeat purchase rate. In a marketplace with a 96.9% one-time buyer rate, reactivating even a small fraction of this population represents a significant revenue opportunity. |

---

## Time-to-Repeat Metrics

---

### Repeat Within 30 Days

| | |
|---|---|
| **Definition** | The percentage of customers who placed a second delivered order within 30 calendar days of their first order. |
| **Grain** | Customer-level. Denominator restricted to customers whose first order was placed at least 30 days before the dataset end date. |
| **Formula** | Count of customers where `order_rank = 2` and `days_since_previous_order ≤ 30` in `customer_order_fact`, divided by the qualifying customer count. |
| **Source tables** | `customer_order_fact` (for `order_rank` and `days_since_previous_order`), `customer_summary` (for first purchase date filtering). |
| **Why it matters** | Captures the immediate post-purchase window. If most repeats occur within 30 days, this defines the priority re-engagement period. |

---

### Repeat Within 60 Days

| | |
|---|---|
| **Definition** | The percentage of customers who placed a second delivered order within 60 calendar days of their first order. |
| **Grain** | Customer-level. Denominator restricted to customers whose first order was placed at least 60 days before the dataset end date. |
| **Formula** | Same logic as Repeat Within 30 Days, with the threshold changed to 60 days. |
| **Why it matters** | The mid-range window. Compared with the 30-day rate, it reveals how much additional conversion happens in days 31–60. |

---

### Repeat Within 90 Days

| | |
|---|---|
| **Definition** | The percentage of customers who placed a second delivered order within 90 calendar days of their first order. |
| **Grain** | Customer-level. Denominator restricted to customers whose first order was placed at least 90 days before the dataset end date. |
| **Formula** | Same logic as Repeat Within 30 Days, with the threshold changed to 90 days. |
| **Why it matters** | The standard industry window for short-term retention. Defines the boundary of the active intervention window in this project. |

---

### Average Days to Second Purchase

| | |
|---|---|
| **Definition** | The arithmetic mean of days between a customer's first and second delivered order, across all customers who have placed at least two orders. |
| **Grain** | Repeat buyers only (`total_orders > 1`). Single aggregate value. |
| **Formula** | Average of `days_since_previous_order` where `order_rank = 2` in `customer_order_fact`, across all repeat buyers. |
| **Note** | Because the distribution of inter-purchase gaps is right-skewed, the average will be higher than the median. Report both. |
| **Why it matters** | Sets the expected re-engagement timing. If the average is 120 days, a 21-day email trigger is misaligned with observed customer behaviour. |

---

### Median Days to Second Purchase

| | |
|---|---|
| **Definition** | The median number of days between a customer's first and second delivered order, across all customers who have placed at least two orders. |
| **Grain** | Repeat buyers only. Single aggregate value. |
| **Formula** | Median of `days_since_previous_order` where `order_rank = 2` in `customer_order_fact`, across all repeat buyers. |
| **Note** | Preferred over the mean for this metric. A small number of customers who wait very long will inflate the mean without reflecting typical behaviour. |
| **Why it matters** | The more representative central tendency for re-engagement timing strategy. |

---

## Revenue and CLV Metrics

---

### Revenue Per Customer — First 30 Days

| | |
|---|---|
| **Definition** | The average total payment value recorded per customer within 30 calendar days of their first order date. |
| **Grain** | Customer-level (`customer_unique_id`). Average across all qualifying customers. |
| **Formula** | For each customer: sum `total_payment_value` from `customer_order_fact` where `order_purchase_timestamp ≤ first_purchase_date + 30 days`. Average this across all customers. Customers with tenure under 30 days contribute their full observed spend. |
| **Source** | `customer_clv.clv_30d` averaged across all customers in `customer_summary`. |
| **Why it matters** | Measures how much revenue the average customer generates immediately after acquisition. Useful for early-stage cohort value comparisons. |

---

### Revenue Per Customer — First 90 Days

| | |
|---|---|
| **Definition** | The average total payment value recorded per customer within 90 calendar days of their first order date. |
| **Grain** | Customer-level. Average across all qualifying customers. |
| **Formula** | Same logic as 30-day version, with window extended to 90 days. |
| **Source** | `customer_clv.clv_90d` averaged. |
| **Why it matters** | The 90-day revenue window is a standard short-term CLV proxy and maps directly to the repeat purchase window. |

---

### Observed CLV — First 180 Days

| | |
|---|---|
| **Definition** | The average total payment value recorded per customer within 180 calendar days of their first order date, using only observed historical transactions. No projection or modelling is applied. |
| **Grain** | Customer-level. Average across all qualifying customers. |
| **Formula** | For each customer: sum `total_payment_value` from `customer_order_fact` where `order_purchase_timestamp ≤ first_purchase_date + 180 days`. Average this across all customers. |
| **Source** | `customer_clv.clv_180d` averaged. |
| **Note** | This is a backward-looking metric only. It reflects what customers actually spent, not what they might spend. The label "CLV" here refers to observed lifetime value within the observation window — not a forward model. |
| **Why it matters** | The 180-day window provides enough history to capture most repeat purchases in this dataset while still representing a meaningful early-lifecycle period. |

---

### Average Order Value (AOV)

| | |
|---|---|
| **Definition** | Total payment value across all valid orders divided by the number of valid orders. |
| **Grain** | Order-level (`order_id`). Single aggregate value. |
| **Formula** | `SUM(total_payment_value)` from `order_payment_total` divided by `COUNT(order_id)` from `orders_clean`. |
| **Note** | AOV is an order-level metric — the denominator is orders, not customers. Do not divide by customer count. |
| **Why it matters** | Baseline revenue-per-transaction figure. Compared across segments, categories, and buyer types to understand value concentration. |

---

### Average Freight Value

| | |
|---|---|
| **Definition** | Average freight cost per delivered order. |
| **Grain** | Order-level. Single aggregate value. |
| **Formula** | `SUM(total_freight)` from `order_revenue` divided by `COUNT(order_id)`. |
| **Note** | Freight is tracked separately from item price. In Olist, freight mean is ~20 BRL vs item price mean of ~121 BRL — freight represents roughly 14% of item price on average. |
| **Why it matters** | High freight relative to order value may discourage repeat purchases. Freight ratio is also used as a churn signal for first-order analysis. |

---

## Experience and Delivery Metrics

---

### Average Review Score

| | |
|---|---|
| **Definition** | Mean customer review score (1–5 stars) across all reviewed delivered orders. |
| **Grain** | Order-level. Single aggregate value. |
| **Formula** | `AVG(review_score)` from `order_reviews_clean` joined to `orders_clean`. |
| **Coverage** | 98,673 of 99,441 total orders (99.2%) have a review. Within the delivered-only scope, coverage is similarly high. |
| **Note** | The distribution is skewed toward 5 (57,328 reviews scored 5 out of 99,224 total). Average alone is not sufficient — report distribution by score alongside the mean. |
| **Why it matters** | Satisfaction signal at order level. Low scores on first orders are used as a leading indicator in churn signal analysis. |

---

### Delivery Delay Rate

| | |
|---|---|
| **Definition** | The percentage of delivered orders where the actual customer delivery date exceeded the estimated delivery date. |
| **Grain** | Order-level. Single aggregate value. |
| **Formula** | Count of delivered orders where `order_delivered_customer_date > order_estimated_delivery_date`, divided by count of delivered orders where both date fields are populated. Multiply by 100. |
| **Source** | `orders_clean` (both dates parsed to datetime). |
| **Note** | `order_estimated_delivery_date` is always populated. `order_delivered_customer_date` may have a small number of null values even within the delivered-only scope — these rows are excluded from the denominator of this metric. |
| **Why it matters** | A late delivery on a first order is used as a churn signal. At the portfolio level, the delay rate benchmarks fulfilment quality. |

---

## Cohort and Revenue Mix Metrics

---

### Cohort Retention Rate

| | |
|---|---|
| **Definition** | For a given cohort (defined by the month of first purchase) and a given period number (months since first purchase), the percentage of that cohort who placed at least one delivered order in that period. |
| **Grain** | One value per `cohort_month` × `period_number` combination. Reported as a matrix (rows = cohorts, columns = period numbers). |
| **Formula** | `customers_retained / cohort_size` for each cell, where `customers_retained` is the count of distinct `customer_unique_id` values from that cohort active in the period, and `cohort_size` is the total count of distinct `customer_unique_id` values in that cohort at period 0. |
| **Source** | `retention_cohorts` mart. |
| **Note** | Period 0 always has a retention rate of 100% by definition (the acquisition period). More recent cohorts will have fewer observable periods and their later columns will be empty. |
| **Why it matters** | Reveals how retention decays over time and whether cohorts from different periods behave differently. Identifies whether retention is improving, worsening, or stable across acquisition periods. |

---

### Revenue Concentration — Repeat vs One-Time Buyers

| | |
|---|---|
| **Definition** | The share of total lifetime payment value contributed by repeat buyers compared to one-time buyers. |
| **Grain** | Customer-level aggregated by buyer type (`is_repeat_buyer`). |
| **Formula** | For repeat buyers: `SUM(total_revenue WHERE is_repeat_buyer = 1)` from `customer_summary`, divided by total `SUM(total_revenue)`. For one-time buyers: the same with `is_repeat_buyer = 0`. Multiply each by 100. |
| **Why it matters** | Quantifies the economic gap between the two customer populations. If repeat buyers (3.12% of customers) contribute a disproportionate share of revenue, even a small increase in repeat rate has amplified revenue impact. This metric motivates the entire project. |

---

## Churn Signal Metrics

Churn signals in this project are **rule-based business flags** applied to observed customer data. They are not probability scores, model outputs, or predictions. Each flag is either true or false for a given customer, based on a clear condition applied to their first order and subsequent observed behaviour.

The purpose of these signals is to identify patterns that are consistent with non-repeat behaviour, so that customers matching multiple signals can be prioritised for re-engagement. Thresholds for signals marked "to be set from data" will be defined after inspecting the relevant distributions in the dataset.

---

### Low First Review Score Flag

| | |
|---|---|
| **Definition** | Set to true if the customer's first delivered order received a review score of 1 or 2 (out of 5). |
| **Source** | `order_reviews_clean.review_score` joined to `customer_order_fact` where `order_rank = 1`. |
| **Coverage note** | Not all first orders have a review. Customers with no review on their first order have this flag set to null (not false). |
| **Business rationale** | A poor experience on the first transaction is the earliest observable signal of potential non-return. Scores of 1 or 2 represent explicit dissatisfaction. |

---

### Delayed First Delivery Flag

| | |
|---|---|
| **Definition** | Set to true if the customer's first delivered order was delivered after its estimated delivery date (`order_delivered_customer_date > order_estimated_delivery_date`). |
| **Source** | `orders_clean` joined to `customer_order_fact` where `order_rank = 1`. Requires both date fields to be non-null. |
| **Business rationale** | A broken delivery promise on the first order may reduce the likelihood of a second. Combined with a low review score, a delayed first delivery strengthens the at-risk signal. |

---

### Single-Item First Order Flag

| | |
|---|---|
| **Definition** | Set to true if the customer's first delivered order contained exactly one line item (`total_items = 1`). |
| **Source** | `order_revenue.total_items` joined to `customer_order_fact` where `order_rank = 1`. |
| **Business rationale** | A single-item first order may indicate a one-off, targeted purchase rather than category exploration. Customers who purchased from multiple items or categories in their first order may show stronger repeat behaviour — this flag identifies the opposite profile. |

---

### Low First Order Value Flag

| | |
|---|---|
| **Definition** | Set to true if the customer's first order `total_payment_value` falls below the 25th percentile of all first-order payment values in the dataset. The exact threshold in BRL is derived from the actual distribution. |
| **Source** | `order_payment_total.total_payment_value` joined to `customer_order_fact` where `order_rank = 1`. Threshold computed from the first-order value distribution. |
| **Business rationale** | Very low first-order values may reflect trial behaviour, minimal category engagement, or a price-sensitive transaction unlikely to recur. |

---

### High Freight Ratio Flag

| | |
|---|---|
| **Definition** | Set to true if freight cost exceeded a defined percentage of item price on the customer's first order — specifically, `total_freight / total_price > threshold`, where the threshold is set after inspecting the freight ratio distribution across first orders. |
| **Source** | `order_revenue.total_freight` and `order_revenue.total_price` joined to `customer_order_fact` where `order_rank = 1`. |
| **Note** | Exclude first orders where `total_price = 0` from this calculation. |
| **Business rationale** | When freight cost is disproportionately high relative to item value, the total cost of the transaction is elevated beyond the item price. This may dampen willingness to repeat, particularly for lower-value product categories. |

---

### No Repeat Within Threshold Flag

| | |
|---|---|
| **Definition** | Set to true if a customer has not placed a second delivered order within N days of their first order, where N is derived from the inter-purchase gap distribution. Applied only to customers whose first order is at least N days old — customers still within the window are excluded from this flag entirely (not flagged as true or false). |
| **Source** | `customer_order_fact`: check whether `order_rank = 2` exists and whether `days_since_previous_order ≤ N` for that row. |
| **Business rationale** | This is the primary at-risk signal. It identifies customers who have passed the point by which most repeat buyers have already returned, but have not done so. Combined with other signals, it defines the core intervention population. |

---

## Known Limitations

### No acquisition channel data

No `acquisition_channel`, referrer, UTM parameter, or marketing source exists in any of the Olist source files. It is not possible to segment repeat rates, CLV, or churn signals by how a customer was acquired. Segmentation in this project is limited to geographic state, first-purchase product category, and payment type.

### No clickstream or session funnel data

The dataset is purely transactional — it records completed orders only. There are no session, page-view, browse, or cart-level events. Funnel analysis in this project refers to order-count stages (1st order, 2nd order, 3rd+ order), not a pre-purchase behavioural funnel.

### No discount field

`total_payment_value` from `olist_order_payments_dataset` reflects what was collected after any voucher application. `price` from `olist_order_items_dataset` reflects the listed item price. The difference between these figures — where it exists — cannot be reliably attributed to a discount without additional data. No discount metrics are defined in this project.

### No causal inference from observational data

All metrics and churn signals in this document are descriptive. A correlation between a churn signal (e.g. low first review score) and non-repeat behaviour does not establish that the signal caused the non-return. The Olist dataset contains no experimental or A/B test data. Recommendations derived from this analysis are hypotheses, not proven interventions.
