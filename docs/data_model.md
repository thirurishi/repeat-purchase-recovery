# Data Model: Repeat Purchase Recovery

**Dataset:** Olist Brazilian E-Commerce Public Dataset
**Model scope:** 7 of 9 source files (sellers and geolocation excluded from first pass)
**Last updated:** 2026-04-13

---

## Purpose

This document defines the layer structure for transforming Olist raw CSV files into analysis-ready tables. It distinguishes between cleaned base tables (close to source, with filtering and parsing applied) and analytical marts (derived, aggregated, or joined outputs used directly in notebooks and the Power BI dashboard).

All layers are described by grain, purpose, and key fields. No SQL is written here — this document is the reference specification that SQL and Python code will implement.

---

## Key Modelling Principles

1. **`customer_unique_id` is the person-level key.** `customer_id` in `olist_orders_dataset` is order-scoped — a different value per order for the same person. All person-level aggregations (order count, CLV, recency, cohort assignment) must bridge through `olist_customers_dataset` to reach `customer_unique_id`.

2. **Revenue has two valid sources.** `olist_order_payments.payment_value` (aggregated per order) is what the customer actually paid. `olist_order_items.price + freight_value` (aggregated per order) gives item-level breakdown and supports category analysis. Both are legitimate. The primary CLV and retention metrics will use `payment_value`; category-level analysis will use `price` from items.

3. **Payments and order items must be aggregated before joining to order level.** Both tables are multi-row per order. Joining them directly to orders without prior aggregation will fan out rows and corrupt all counts and sums.

4. **Analysis is anchored on `order_purchase_timestamp`.** This is when the customer made the decision to buy — the correct date for cohort assignment, recency calculation, and inter-purchase gap measurement.

5. **No acquisition channel dimension exists.** There is no channel, referrer, or UTM data in this dataset. Segmentation will use geographic state and payment type as the only available transactional dimensions.

6. **Only `review_score` is used analytically from reviews.** Comment title and message fields are 88% and 59% null respectively. Both comment columns are retained in `order_reviews_clean` for completeness, but excluded from all first-pass analytical marts. `review_score` is the only review field carried forward.

---

## Entity Relationship Overview

```
olist_customers_dataset
  customer_id (PK, order-scoped)
  customer_unique_id (person-level key)
        │
        │ customer_id
        ▼
olist_orders_dataset
  order_id (PK)
  customer_id (FK)
        │
        ├──── order_id ────► olist_order_items_dataset
        │                       order_id (FK)
        │                       product_id (FK) ──► olist_products_dataset
        │                                               product_category_name (FK)
        │                                                    │
        │                                                    ▼
        │                               product_category_name_translation
        │
        ├──── order_id ────► olist_order_payments_dataset
        │                       order_id (FK)
        │
        └──── order_id ────► olist_order_reviews_dataset
                                order_id (FK)
```

---

## Cleaned Base Tables

These tables apply only filtering, type casting, and minor standardisation to the raw source files. They do not aggregate or derive business metrics.

---

### `orders_clean`

| Attribute | Detail |
|---|---|
| **Source** | `olist_orders_dataset.csv` |
| **Grain** | One row per `order_id` |
| **Filter applied** | `order_status = 'delivered'` (see Recommended Valid Order Scope) |
| **Purpose** | Clean, parsed order spine for all downstream joins and aggregations |

**Key fields:**

| Field | Source column | Transformation |
|---|---|---|
| `order_id` | `order_id` | As-is (PK) |
| `customer_id` | `customer_id` | As-is (FK → customers) |
| `order_status` | `order_status` | As-is, post-filter |
| `order_purchase_timestamp` | `order_purchase_timestamp` | Parse to datetime |
| `order_delivered_customer_date` | `order_delivered_customer_date` | Parse to datetime |
| `order_estimated_delivery_date` | `order_estimated_delivery_date` | Parse to datetime |

> `order_approved_at` and `order_delivered_carrier_date` are retained but not used in first-pass analysis.

---

### `customers_clean`

| Attribute | Detail |
|---|---|
| **Source** | `olist_customers_dataset.csv` |
| **Grain** | One row per `customer_id` (order-scoped) |
| **Filter applied** | None — zero nulls in source |
| **Purpose** | Bridge between order-scoped `customer_id` and person-level `customer_unique_id`; also supplies geographic dimension |

**Key fields:**

| Field | Source column | Transformation |
|---|---|---|
| `customer_id` | `customer_id` | As-is (PK) |
| `customer_unique_id` | `customer_unique_id` | As-is (person-level key) |
| `customer_state` | `customer_state` | As-is |
| `customer_city` | `customer_city` | As-is |

> `customer_zip_code_prefix` retained for potential later join to geolocation.

---

### `order_items_clean`

| Attribute | Detail |
|---|---|
| **Source** | `olist_order_items_dataset.csv` |
| **Grain** | One row per `order_id` × `order_item_id` |
| **Filter applied** | Inner join to `orders_clean` — retains only items belonging to valid delivered orders |
| **Purpose** | Item-level revenue and product data; required for category breadth calculation |

**Key fields:**

| Field | Source column | Transformation |
|---|---|---|
| `order_id` | `order_id` | As-is (FK) |
| `order_item_id` | `order_item_id` | As-is (sequence within order) |
| `product_id` | `product_id` | As-is (FK → products) |
| `price` | `price` | As-is (BRL) |
| `freight_value` | `freight_value` | As-is (BRL) |

> `seller_id` is retained but not used in first-pass analysis (sellers excluded).

---

### `order_payments_clean`

| Attribute | Detail |
|---|---|
| **Source** | `olist_order_payments_dataset.csv` |
| **Grain** | One row per `order_id` × `payment_sequential` |
| **Filter applied** | Inner join to `orders_clean` |
| **Purpose** | Payment method and value; aggregated to order level for revenue metrics |

**Key fields:**

| Field | Source column | Transformation |
|---|---|---|
| `order_id` | `order_id` | As-is (FK) |
| `payment_sequential` | `payment_sequential` | As-is |
| `payment_type` | `payment_type` | As-is |
| `payment_installments` | `payment_installments` | As-is |
| `payment_value` | `payment_value` | As-is (BRL) |

---

### `order_reviews_clean`

| Attribute | Detail |
|---|---|
| **Source** | `olist_order_reviews_dataset.csv` |
| **Grain** | One row per `order_id` (after deduplication) |
| **Filter applied** | Deduplicate to one row per `order_id` using the following priority rule: (1) retain the row with the latest `review_answer_timestamp`; (2) if timestamps are equal or missing, retain the row with the fewest nulls across `review_comment_title` and `review_comment_message` (most complete record). |
| **Purpose** | Order-level satisfaction signal via `review_score`; comment text retained in the clean table for completeness |

**Key fields:**

| Field | Source column | Transformation |
|---|---|---|
| `order_id` | `order_id` | As-is (FK); deduplicated to one row per order |
| `review_score` | `review_score` | As-is (1–5) |
| `review_comment_title` | `review_comment_title` | Retained as-is; 88.3% null — not used in first-pass marts |
| `review_comment_message` | `review_comment_message` | Retained as-is; 58.7% null — not used in first-pass marts |
| `review_creation_date` | `review_creation_date` | Parse to datetime if needed |
| `review_answer_timestamp` | `review_answer_timestamp` | Parse to datetime; used in deduplication priority rule |

> `review_id` is not used as a key — 814 duplicate values confirmed in source.
> Comment columns are retained here for potential future use (text analysis, NLP) but are excluded from all first-pass analytical marts due to high null rates. Only `review_score` is carried into downstream marts.

---

### `products_clean`

| Attribute | Detail |
|---|---|
| **Source** | `olist_products_dataset.csv` + `product_category_name_translation.csv` |
| **Grain** | One row per `product_id` |
| **Filter applied** | None — all 32,951 products retained |
| **Purpose** | Product dimension with English category name for segmentation |

**Key fields:**

| Field | Source column | Transformation |
|---|---|---|
| `product_id` | `product_id` | As-is (PK) |
| `product_category_name` | `product_category_name` | As-is |
| `product_category_name_english` | `product_category_name_translation.product_category_name_english` | Left join on `product_category_name`; null if untranslated |
| `product_category_resolved` | Derived | `product_category_name_english` if available; else `product_category_name`; else `'unknown'` |

> Column name typos from source are preserved exactly: `product_name_lenght`, `product_description_lenght`.
> Dimensional columns (weight, dimensions, photo count) are available but not used in first-pass analysis.

---

## Analytical Marts

These tables are derived from the cleaned base tables. They aggregate, join, and compute business metrics. Each mart has a specific analytical purpose.

---

### Mart 1: `order_revenue`

| Attribute | Detail |
|---|---|
| **Source** | `order_items_clean` |
| **Grain** | One row per `order_id` |
| **Purpose** | Aggregated order-level revenue and product summary; used as input to all customer-level marts |

**Key derived fields:**

| Field | Derived from | Description |
|---|---|---|
| `order_id` | `order_items_clean.order_id` | FK to orders |
| `total_price` | `SUM(price)` | Sum of item prices for the order (BRL) |
| `total_freight` | `SUM(freight_value)` | Sum of freight for the order (BRL) |
| `total_items` | `COUNT(order_item_id)` | Number of line items in the order |
| `distinct_products` | `COUNT(DISTINCT product_id)` | Number of distinct products ordered |
| `distinct_categories` | `COUNT(DISTINCT product_category_resolved)` | Number of distinct product categories — key input for category breadth churn signal |

---

### Mart 2: `order_payment_total`

| Attribute | Detail |
|---|---|
| **Source** | `order_payments_clean` |
| **Grain** | One row per `order_id` |
| **Purpose** | Aggregated order-level payment value; primary revenue field for CLV and monetary scoring |

**Key derived fields:**

| Field | Derived from | Description |
|---|---|---|
| `order_id` | `order_payments_clean.order_id` | FK to orders |
| `total_payment_value` | `SUM(payment_value)` | Total amount paid by the customer for this order (BRL) |
| `primary_payment_type` | `payment_type WHERE payment_sequential = 1` | Payment method used for the primary (or only) payment |
| `payment_row_count` | `COUNT(payment_sequential)` | Number of payment methods used (1 = single; 2+ = split payment) |

> `total_payment_value` is the recommended revenue field for CLV and monetary scoring. It reflects what the customer actually paid, including any voucher application.

---

### Mart 3: `customer_summary`

| Attribute | Detail |
|---|---|
| **Source** | `orders_clean` + `customers_clean` + `order_payment_total` |
| **Grain** | One row per `customer_unique_id` |
| **Supports** | Retention analysis, repeat purchase rate, CLV, RFM scoring, churn signal labelling |

**Key derived fields:**

| Field | Derived from | Description |
|---|---|---|
| `customer_unique_id` | `customers_clean.customer_unique_id` | Person-level key |
| `total_orders` | `COUNT(order_id)` | Lifetime order count (delivered only) |
| `first_purchase_date` | `MIN(order_purchase_timestamp)` | Date of first delivered order |
| `last_purchase_date` | `MAX(order_purchase_timestamp)` | Date of most recent delivered order |
| `total_revenue` | `SUM(total_payment_value)` | Lifetime payment value (BRL) |
| `avg_order_value` | `total_revenue / total_orders` | Average payment per order |
| `customer_tenure_days` | `last_purchase_date − first_purchase_date` | Days between first and last order |
| `days_since_last_purchase` | `snapshot_date − last_purchase_date` | Recency in days |
| `is_repeat_buyer` | `total_orders > 1` | Boolean flag |
| `cohort_month` | `DATE_TRUNC('month', first_purchase_date)` | Month of first purchase — used for cohort assignment |
| `customer_state` | `customers_clean.customer_state` | Geographic dimension |

---

### Mart 4: `customer_order_fact`

| Attribute | Detail |
|---|---|
| **Source** | `orders_clean` + `customers_clean` + `order_payment_total` |
| **Grain** | One row per `customer_unique_id` × `order_id` |
| **Supports** | Time-to-second-purchase, inter-purchase gap, funnel stage analysis, cohort period attribution |

**Key derived fields:**

| Field | Derived from | Description |
|---|---|---|
| `customer_unique_id` | `customers_clean.customer_unique_id` | Person-level key |
| `order_id` | `orders_clean.order_id` | Order identifier |
| `order_purchase_timestamp` | `orders_clean.order_purchase_timestamp` | Purchase date (parsed) |
| `order_rank` | `ROW_NUMBER() OVER (PARTITION BY customer_unique_id ORDER BY order_purchase_timestamp)` | 1 = first order, 2 = second, etc. |
| `total_payment_value` | `order_payment_total.total_payment_value` | Revenue for this specific order (BRL) |
| `days_since_previous_order` | `order_purchase_timestamp − previous order's timestamp` | Inter-purchase gap in days; null for first order |

> This is the order-level fact table with customer context attached. It is the foundation for time-to-second-purchase, funnel stage counts, and inter-purchase time distribution. `customer_summary` (Mart 3) aggregates from this table.

---

### Mart 5: `retention_cohorts`

| Attribute | Detail |
|---|---|
| **Source** | `customer_order_fact` + `customer_summary` |
| **Grain** | One row per `cohort_month` × `period_number` |
| **Supports** | Monthly cohort retention heatmap, N-day retention rates |

**Key derived fields:**

| Field | Derived from | Description |
|---|---|---|
| `cohort_month` | `customer_summary.cohort_month` | Month of first purchase |
| `period_number` | `months between cohort_month and activity month` | 0 = acquisition month, 1 = month 1 post-acquisition, etc. |
| `cohort_size` | `COUNT(DISTINCT customer_unique_id) WHERE period_number = 0` | Number of new customers in that cohort |
| `customers_retained` | `COUNT(DISTINCT customer_unique_id)` | Customers from that cohort who placed an order in this period |
| `retention_rate` | `customers_retained / cohort_size` | Fraction retained in this period |

---

### Mart 6: `customer_rfm`

| Attribute | Detail |
|---|---|
| **Source** | `customer_summary` |
| **Grain** | One row per `customer_unique_id` |
| **Supports** | Customer segmentation, targeting prioritisation |

**Key derived fields:**

| Field | Derived from | Description |
|---|---|---|
| `customer_unique_id` | `customer_summary` | Person-level key |
| `recency_days` | `customer_summary.days_since_last_purchase` | R component |
| `frequency` | `customer_summary.total_orders` | F component |
| `monetary` | `customer_summary.total_revenue` | M component |
| `r_score` | Quintile rank of `recency_days` (inverted — lower days = higher score) | 1–5 |
| `f_score` | Quintile rank of `frequency` | 1–5 |
| `m_score` | Quintile rank of `monetary` | 1–5 |
| `rfm_segment` | Rule-based label from combined scores | Champion, Loyal, At Risk, Lost, etc. |

> Score boundaries and segment label rules will be defined after inspecting the actual distribution of recency, frequency, and monetary values.

---

### Mart 7: `customer_clv`

| Attribute | Detail |
|---|---|
| **Source** | `customer_summary` + `customer_order_fact` |
| **Grain** | One row per `customer_unique_id` |
| **Supports** | Revenue opportunity sizing, segment value comparison, scenario analysis |

**Key derived fields:**

| Field | Derived from | Description |
|---|---|---|
| `customer_unique_id` | `customer_summary` | Person-level key |
| `clv_30d` | `SUM(total_payment_value)` for orders within 30 days of `first_purchase_date` | Observed spend in first 30 days from acquisition (BRL) |
| `clv_90d` | `SUM(total_payment_value)` for orders within 90 days of `first_purchase_date` | Observed spend in first 90 days from acquisition (BRL) |
| `clv_180d` | `SUM(total_payment_value)` for orders within 180 days of `first_purchase_date` | Observed spend in first 180 days from acquisition (BRL) |
| `historical_clv` | `customer_summary.total_revenue` | Total observed lifetime spend across all delivered orders (BRL) |
| `avg_order_value` | `customer_summary.avg_order_value` | Average payment per order |
| `is_repeat_buyer` | `customer_summary.is_repeat_buyer` | Used for one-time vs. repeat buyer value comparison |

> All CLV fields in this mart reflect **observed historical spend only** within defined time windows. No forward projection or modelling is applied at this stage. Windowed fields (`clv_30d`, `clv_90d`, `clv_180d`) are calculated from `first_purchase_date` and require at least that many days of history to be meaningful — customers with shorter tenure will have windowed values equal to `historical_clv`.

---

### Mart 8: `churn_signal_mart`

| Attribute | Detail |
|---|---|
| **Source** | `customer_summary` + `customer_order_fact` + `order_revenue` + `order_reviews_clean` + `customer_rfm` |
| **Grain** | One row per `customer_unique_id` |
| **Supports** | Rule-based churn signal tracking, at-risk customer identification using observed behavioural patterns |

**Key derived fields:**

| Field | Derived from | Description |
|---|---|---|
| `customer_unique_id` | `customer_summary` | Person-level key |
| `days_since_last_purchase` | `customer_summary` | Recency — primary behavioural signal |
| `total_orders` | `customer_summary` | Order frequency across lifetime |
| `total_revenue` | `customer_summary` | Total observed spend (BRL) |
| `avg_inter_purchase_days` | `AVG(days_since_previous_order)` from `customer_order_fact` | Average gap between consecutive orders; null for one-time buyers |
| `std_inter_purchase_days` | `STDDEV(days_since_previous_order)` from `customer_order_fact` | Variability in purchase cadence; null for one-time buyers |
| `distinct_categories` | `order_revenue` aggregated per customer | Number of distinct product categories purchased across lifetime |
| `avg_review_score` | `order_reviews_clean` joined via `orders_clean` + `customers_clean` | Average satisfaction score across reviewed orders; null if no reviews |
| `r_score` / `f_score` / `m_score` | `customer_rfm` | RFM dimension scores |
| `rfm_segment` | `customer_rfm` | Rule-based segment label |
| `is_churned` | `days_since_last_purchase > churn_threshold` | Rule-based flag; threshold defined from observed inter-purchase gap distribution, not hardcoded |
| `is_at_risk` | `days_since_last_purchase BETWEEN lower_bound AND upper_bound` | Rule-based flag identifying customers in the intervention window — active enough to target, not yet fully lapsed |

> `is_churned` and `is_at_risk` are **rule-based business classifications**, not machine learning labels. The threshold and window bounds will be set after inspecting the actual inter-purchase gap distribution in the dataset. The goal of this mart is to surface customers who have gone quiet relative to their own observed purchase cadence — no model training is implied at this stage.

---

## Recommended Valid Order Scope

**First-pass analysis should be scoped to `order_status = 'delivered'` orders only.**

| Status | Count | Include in first pass |
|---|---|---|
| `delivered` | 96,478 | Yes — confirmed completed transactions |
| `shipped` | 1,107 | No — outcome unknown at snapshot date |
| `canceled` | 625 | No — customer did not complete the transaction |
| `unavailable` | 609 | No — item was not fulfilled |
| `invoiced` | 314 | No — payment not confirmed |
| `processing` | 301 | No — not yet complete |
| `created` | 5 | No |
| `approved` | 2 | No |

**Rationale:** Including non-delivered orders in retention and CLV analysis would:
- Count canceled or unfulfilled orders as customer purchases (inflating order counts and revenue).
- Incorrectly assign cohort months to customers whose orders were never completed.
- Distort time-to-second-purchase and inter-purchase gap calculations.

**Future consideration:** A second-pass analysis could include `shipped` orders where the purchase decision is confirmed, or examine the characteristics of customers whose first order was canceled to understand early churn.

> The 775 orders that have no corresponding rows in `olist_order_items_dataset` should be investigated before any scope is finalised. Their status distribution should be checked to confirm they are safely excluded by the delivered-only filter.

---

## Known Dataset Constraints

### No acquisition channel data

The Olist dataset contains no `acquisition_channel`, UTM parameter, referrer, or marketing source field in any of the 9 source files. Channel-level repeat rate analysis (e.g. "email-acquired customers retain better than paid-social customers") is not possible with this dataset.

Available segmentation dimensions are limited to:
- `customer_state` (geographic)
- `primary_payment_type` (payment behaviour proxy)
- `product_category_resolved` (first-purchase category)

### No clickstream or session funnel data

There is no session, page-view, event, or browse data. The dataset is purely transactional — it records completed orders, not the path to purchase. Funnel analysis in this project is defined as order-count stages (1st order, 2nd order, 3rd+ order), not behavioural click funnels.

### No direct discount field

There is no `discount_amount`, `coupon_code`, or `original_price` column in any source file. The `payment_value` in `olist_order_payments_dataset` represents what was actually collected (post any voucher), and `price` in `olist_order_items_dataset` is the listed item price. The difference between these — if any — is not consistently interpretable as a discount without additional data.

### `customer_id` is order-scoped and not suitable for lifecycle analysis

`customer_id` in `olist_orders_dataset` is generated per order. A customer who places three orders will have three different `customer_id` values. Using `customer_id` as a person identifier will make every customer appear to be a one-time buyer and will produce a false repeat rate of 0%.

All person-level analysis must group by `customer_unique_id`, accessed by joining `olist_orders_dataset` → `olist_customers_dataset` on `customer_id`.

This join is required in every mart that operates at the person level.
