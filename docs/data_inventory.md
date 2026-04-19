# Data Inventory

**Dataset:** Olist Brazilian E-Commerce Public Dataset
**Source:** Kaggle / Olist (public dataset)
**First-pass files:** 7 of 9 available CSV files
**Excluded from first pass:** `olist_sellers_dataset.csv`, `olist_geolocation_dataset.csv`
**Last updated:** 2026-04-13

---

## Source Files

### 1. `olist_customers_dataset.csv`

**Business Purpose:** Maps order-scoped customer records to a person-level unique identifier and geographic metadata. This is the bridge table required for any repeat purchase or retention analysis.

**Row Count:** 99,441
**Grain:** One row per `customer_id` (order-scoped)

| Column | Type | Nulls | Unique | Notes |
|---|---|---|---|---|
| `customer_id` | string | 0 | 99,441 | **Likely PK.** Order-scoped — one value per order. Do NOT use for person-level repeat analysis. |
| `customer_unique_id` | string | 0 | 96,096 | **Person-level identifier.** Use this for retention, CLV, and churn analysis. 96,096 unique persons across 99,441 orders. |
| `customer_zip_code_prefix` | int64 | 0 | 14,994 | 5-digit zip prefix. Join to geolocation (excluded from first pass). |
| `customer_city` | string | 0 | 4,119 | Customer city (free text, not normalised). |
| `customer_state` | string | 0 | 27 | Brazilian state abbreviation. |

**Primary Key:** `customer_id`
**Key Join:** `customer_id` → `olist_orders_dataset.customer_id`

---

### 2. `olist_orders_dataset.csv`

**Business Purpose:** Central fact table. One row per order with status and all timestamp milestones. The spine of all order-level analysis.

**Row Count:** 99,441
**Grain:** One row per `order_id`
**Date Range:** 2016-09-04 to 2018-10-17 (approximately 25 months)

| Column | Type | Nulls | Unique | Notes |
|---|---|---|---|---|
| `order_id` | string | 0 | 99,441 | **PK.** |
| `customer_id` | string | 0 | 99,441 | **FK → customers.** Unique per order — confirms 1:1 mapping with customers table. |
| `order_status` | string | 0 | 8 | See distribution below. |
| `order_purchase_timestamp` | string | 0 | 98,875 | **Primary analysis date.** Parse as datetime before use. |
| `order_approved_at` | string | 160 | 90,733 | 160 nulls — likely unapproved / canceled orders. |
| `order_delivered_carrier_date` | string | 1,783 | 81,018 | 1,783 nulls — undelivered orders. |
| `order_delivered_customer_date` | string | 2,965 | 95,664 | 2,965 nulls — undelivered orders. |
| `order_estimated_delivery_date` | string | 0 | 459 | Always present. |

**Order Status Distribution:**

| Status | Count | Notes |
|---|---|---|
| `delivered` | 96,478 | Primary analysis population |
| `shipped` | 1,107 | In transit at snapshot date |
| `canceled` | 625 | Exclude from revenue and retention analysis |
| `unavailable` | 609 | Exclude from revenue analysis |
| `invoiced` | 314 | |
| `processing` | 301 | |
| `created` | 5 | |
| `approved` | 2 | |

**Primary Key:** `order_id`
**Key Joins:** `customer_id` → `olist_customers_dataset.customer_id`

> **All date columns are stored as strings.** Parse with `pd.to_datetime()` before any date arithmetic.

---

### 3. `olist_order_items_dataset.csv`

**Business Purpose:** Line-item detail per order. One row per item within an order. Required for revenue calculation at product and category level.

**Row Count:** 112,650
**Grain:** One row per `order_id` × `order_item_id` (item sequence within the order)

| Column | Type | Nulls | Unique | Notes |
|---|---|---|---|---|
| `order_id` | string | 0 | 98,666 | **FK → orders.** Not the PK here — multiple rows per order. |
| `order_item_id` | int64 | 0 | 21 | Item sequence number within the order (1, 2, 3…). Max sequence seen: 21. |
| `product_id` | string | 0 | 32,951 | **FK → products.** |
| `seller_id` | string | 0 | 3,095 | FK → sellers (excluded from first pass). |
| `shipping_limit_date` | string | 0 | 93,318 | Parse as datetime if needed. |
| `price` | float64 | 0 | 5,968 | Item price (BRL). Mean: 120.65, Median: 74.99, Max: 6,735. |
| `freight_value` | float64 | 0 | 6,999 | Freight cost per item (BRL). Mean: 19.99, Median: 16.26, Max: 409.68. |

**Item Count Distribution per Order:**

| Items per Order | Orders |
|---|---|
| 1 | 88,863 |
| 2 | 7,516 |
| 3+ | 2,287 |

**Primary Key:** `(order_id, order_item_id)`
**Key Joins:** `order_id` → `olist_orders_dataset.order_id` | `product_id` → `olist_products_dataset.product_id`

> **Aggregate before joining to order level.** SUM(`price`) and SUM(`freight_value`) per `order_id` to produce order-level revenue.

> **775 orders in olist_orders_dataset have no rows here.** These are likely canceled or unavailable orders. Investigate before excluding.

---

### 4. `olist_products_dataset.csv`

**Business Purpose:** Product catalog. Required for category-level segmentation and category breadth calculation.

**Row Count:** 32,951
**Grain:** One row per `product_id`

| Column | Type | Nulls | Unique | Notes |
|---|---|---|---|---|
| `product_id` | string | 0 | 32,951 | **PK.** |
| `product_category_name` | string | 610 | 73 | Portuguese category name. 610 nulls (1.85% of products). Join to translation file for English names. |
| `product_name_lenght` | float64 | 610 | 66 | Character count of product name. Nulls match category nulls. |
| `product_description_lenght` | float64 | 610 | 2,960 | Character count of description. |
| `product_photos_qty` | float64 | 610 | 19 | Number of product photos listed. |
| `product_weight_g` | float64 | 2 | 2,204 | Product weight in grams. 2 nulls. |
| `product_length_cm` | float64 | 2 | 99 | |
| `product_height_cm` | float64 | 2 | 102 | |
| `product_width_cm` | float64 | 2 | 95 | |

**Primary Key:** `product_id`
**Key Joins:** `product_id` → `olist_order_items_dataset.product_id` | `product_category_name` → `product_category_name_translation.product_category_name`

> **Note on column name typos:** `product_name_lenght` and `product_description_lenght` are misspelled in the source file. Do not rename — reference exactly as shown.

---

### 5. `product_category_name_translation.csv`

**Business Purpose:** Maps Portuguese product category names to English equivalents.

**Row Count:** 71
**Grain:** One row per `product_category_name`

| Column | Type | Nulls | Unique | Notes |
|---|---|---|---|---|
| `product_category_name` | string | 0 | 71 | Portuguese name. **FK → products.** |
| `product_category_name_english` | string | 0 | 71 | English equivalent. |

**Primary Key:** `product_category_name`

**Coverage Gap:**
- Products file contains 73 distinct category names; translation file contains 71.
- 2 categories have no English translation: `pc_gamer`, `portateis_cozinha_e_preparadores_de_alimentos`
- 610 products have a null `product_category_name` and will not join to this file.

> Use a LEFT JOIN from products to this file. Products without a translation will retain their Portuguese name or be labeled `unknown`.

---

### 6. `olist_order_payments_dataset.csv`

**Business Purpose:** Records payment methods and values per order. One order can have multiple payment rows (e.g. voucher + credit card split). Aggregate per order to get total order payment value.

**Row Count:** 103,886
**Grain:** One row per `order_id` × `payment_sequential`

| Column | Type | Nulls | Unique | Notes |
|---|---|---|---|---|
| `order_id` | string | 0 | 99,440 | **FK → orders.** Not PK — multiple rows per order possible. |
| `payment_sequential` | int64 | 0 | 29 | Payment method sequence (1 = primary). |
| `payment_type` | string | 0 | 5 | See distribution below. |
| `payment_installments` | int64 | 0 | 24 | Number of installments. 0 = single payment. |
| `payment_value` | float64 | 0 | 29,077 | Amount paid via this method (BRL). |

**Payment Rows per Order:**

| Payment Rows | Orders |
|---|---|
| 1 | 96,479 |
| 2 | 2,382 |
| 3+ | 579 |

**Payment Type Distribution:**

| Type | Rows |
|---|---|
| `credit_card` | 76,795 |
| `boleto` | 19,784 |
| `voucher` | 5,775 |
| `debit_card` | 1,529 |
| `not_defined` | 3 |

**Primary Key:** `(order_id, payment_sequential)`
**Key Joins:** `order_id` → `olist_orders_dataset.order_id`

> **Aggregate before joining to order level:** `SUM(payment_value) GROUP BY order_id` gives total order revenue. This is the recommended revenue field for CLV and repeat purchase analysis.

> **1 order in olist_orders_dataset has no payment row** (99,440 unique order_ids here vs 99,441 orders).

---

### 7. `olist_order_reviews_dataset.csv`

**Business Purpose:** Customer satisfaction scores (1–5 stars) and optional text reviews per order. Useful as a churn signal — low scores on early orders may predict non-repeat behaviour.

**Row Count:** 99,224
**Grain:** One row per review submission (not strictly 1:1 with orders)

| Column | Type | Nulls | Unique | Notes |
|---|---|---|---|---|
| `review_id` | string | 0 | 98,410 | Not a reliable PK — 814 duplicate values present. |
| `order_id` | string | 0 | 98,673 | **FK → orders.** 98,673 of 99,441 orders have a review (99.2% coverage). |
| `review_score` | int64 | 0 | 5 | 1–5 stars. See distribution below. |
| `review_comment_title` | string | 87,656 | 4,527 | 88.3% null. Do not rely on for analysis. |
| `review_comment_message` | string | 58,247 | 36,159 | 58.7% null. Text signal only where present. |
| `review_creation_date` | string | 0 | 636 | Date review was created (not score date). Parse as datetime if needed. |
| `review_answer_timestamp` | string | 0 | 98,248 | When the review was answered. |

**Review Score Distribution:**

| Score | Count |
|---|---|
| 1 | 11,424 |
| 2 | 3,151 |
| 3 | 8,179 |
| 4 | 19,142 |
| 5 | 57,328 |

**Primary Key:** Use `(order_id, review_id)` with deduplication — `review_id` alone is not reliable.
**Key Joins:** `order_id` → `olist_orders_dataset.order_id`

> **Join as LEFT JOIN from orders** — 768 orders have no review row.

> **review_id is not unique** — 814 duplicate values exist. Do not use `review_id` as a standalone key.

---

## Volume Summary

| File | Rows | Grain |
|---|---|---|
| `olist_customers_dataset.csv` | 99,441 | 1 per customer_id (order-scoped) |
| `olist_orders_dataset.csv` | 99,441 | 1 per order |
| `olist_order_items_dataset.csv` | 112,650 | 1 per order × item |
| `olist_products_dataset.csv` | 32,951 | 1 per product |
| `product_category_name_translation.csv` | 71 | 1 per category name |
| `olist_order_payments_dataset.csv` | 103,886 | 1 per order × payment method |
| `olist_order_reviews_dataset.csv` | 99,224 | 1 per review submission |

---

## Important Modelling Notes

### `customer_unique_id` is the correct key for retention and repeat purchase analysis

The Olist dataset has a deliberate design choice that is easy to get wrong:

- `customer_id` in `olist_orders_dataset` is **order-scoped** — a new `customer_id` is generated for each order, even if the same person placed multiple orders.
- `customer_id` is confirmed unique per order: 0 orders share the same `customer_id`.
- **`customer_unique_id`** in `olist_customers_dataset` is the **person-level identifier**. This is the field to use for counting repeat buyers, computing CLV, and building churn signals.
- To use `customer_unique_id`, always bridge through the customers table: `orders → customers → customer_unique_id`.

**Measured baseline (delivered orders only — to be refined):**

| Metric | Value |
|---|---|
| Unique persons (`customer_unique_id`) | 96,096 |
| Persons with exactly 1 order | 93,099 (96.9%) |
| Persons with exactly 2 orders | 2,745 (2.9%) |
| Persons with 3+ orders | 252 (0.3%) |
| Overall repeat rate (2+ orders) | **3.12%** |

> This is an extremely low repeat rate relative to typical e-commerce benchmarks. This may reflect the nature of the marketplace (large, one-off purchases), the 25-month observation window, or customer acquisition dynamics. The repeat rate calculation above includes all order statuses — filter to `delivered` only before finalising.

### This dataset does not contain acquisition channel or clickstream data

- There is no `acquisition_channel`, `utm_source`, `referrer`, or session-level data in any of the 9 Olist files.
- Channel-level repeat rate analysis (as planned in some project templates) is **not possible** with this dataset.
- The `payment_type` field (credit_card, boleto, voucher, debit_card) is a proxy for payment behaviour — not acquisition channel.
- Geographic variables (`customer_state`, `customer_city`) are available as a segmentation dimension.

### Sellers and geolocation are intentionally excluded from the first pass

- `olist_sellers_dataset.csv` contains seller-level metadata. `seller_id` exists in `olist_order_items_dataset` but is not needed for customer-level retention analysis.
- `olist_geolocation_dataset.csv` maps zip codes to lat/lng. Useful for geographic visualisation but not required for repeat purchase, CLV, or churn analysis.
- Both files will be assessed in a later pass if seller-level or geographic analysis is added.

---

## Join Risks

| Risk | Detail | Mitigation |
|---|---|---|
| **customer_id vs customer_unique_id confusion** | `customer_id` is order-scoped — using it as a person identifier will make every customer appear to be a one-time buyer. | Always join `orders → customers` and group by `customer_unique_id`. |
| **Payments grain (not 1:1 with orders)** | 103,886 payment rows for 99,440 orders. Joining payments directly to orders without aggregation creates row duplication. | `SUM(payment_value) GROUP BY order_id` first. |
| **Order items grain (not 1:1 with orders)** | 112,650 item rows for 98,666 orders. Same fan-out risk. | `SUM(price), SUM(freight_value) GROUP BY order_id` first. |
| **775 orders with no items** | These orders exist in the orders table but have no rows in order_items. Their status is not uniformly canceled. | Investigate status distribution for these 775 orders before deciding to include or exclude. |
| **1 order with no payment row** | 99,440 unique `order_id` values in payments vs 99,441 in orders. | Use LEFT JOIN when attaching payment data to orders. |
| **768 orders with no review** | 98,673 of 99,441 orders have a review row. | Use LEFT JOIN when attaching review data to orders. |
| **review_id not unique** | 814 duplicate `review_id` values. Can produce duplicate rows if joined on `review_id`. | Deduplicate reviews before joining; use `order_id` as the join key. |
| **All timestamps stored as strings** | All date columns in orders (and items, reviews) are `object` dtype. | Parse with `pd.to_datetime()` before any date arithmetic. |
| **610 products with null category_name** | 1.85% of products cannot be assigned to a category or translated. | Label as `'unknown'` after join. |
| **2 categories untranslated** | `pc_gamer` and `portateis_cozinha_e_preparadores_de_alimentos` have no English mapping. | Keep original Portuguese name or add manual mapping. |

---

## Null Risks

| Column | File | Null Count | Impact |
|---|---|---|---|
| `order_approved_at` | orders | 160 | Minor. Affects approval-to-delivery time calculations only. |
| `order_delivered_carrier_date` | orders | 1,783 | Affects delivery time metrics. Likely canceled/unavailable orders. |
| `order_delivered_customer_date` | orders | 2,965 | Key field for actual delivery analysis. Use `order_status = 'delivered'` filter first. |
| `product_category_name` | products | 610 | Affects category-level segmentation for 1.85% of products. |
| `review_comment_title` | reviews | 87,656 (88.3%) | Text analysis not viable. Use `review_score` only. |
| `review_comment_message` | reviews | 58,247 (58.7%) | Text analysis on a partial population only. |
| `product_weight_g` / dimensions | products | 2 each | Negligible. Only relevant if shipping cost modelling is added. |

---

## Most Useful Fields for Core Analysis

### Retention and Repeat Purchase

| Field | File | Role |
|---|---|---|
| `customer_unique_id` | customers | Person-level identifier — GROUP BY this for cohort and retention analysis |
| `order_id` | orders | Order identifier |
| `order_purchase_timestamp` | orders | Purchase date — use for cohort assignment and time-between-purchases |
| `order_status` | orders | Filter to `delivered` for clean retention analysis |

### CLV

| Field | File | Role |
|---|---|---|
| `customer_unique_id` | customers | Person-level grouping |
| `payment_value` | payments | Revenue per payment row — aggregate to order level |
| `price` | order_items | Item-level revenue — alternative revenue source |
| `freight_value` | order_items | Freight — include or exclude depending on CLV definition |
| `order_purchase_timestamp` | orders | Required for tenure and frequency calculations |

### Churn Signals

| Field | File | Role |
|---|---|---|
| `order_purchase_timestamp` | orders | Recency — days since last purchase |
| `order_id` count per `customer_unique_id` | orders + customers | Frequency |
| `payment_value` aggregate per `customer_unique_id` | payments + orders + customers | Monetary value |
| `product_category_name_english` | products + translation | Category breadth (distinct categories per customer) |
| `review_score` | reviews | Satisfaction signal — low scores on prior orders may correlate with non-return |
| `order_status` | orders | Negative experience signal — canceled or unavailable orders |
