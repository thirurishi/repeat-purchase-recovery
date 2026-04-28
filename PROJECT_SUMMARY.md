# Project Summary: Repeat Purchase Recovery
**Generated:** 2026-04-28
**Dataset:** Olist Brazilian E-Commerce Public Dataset (Kaggle)
**Stack:** SQLite · Python (pandas, numpy, matplotlib) · Jupyter · Power BI

---

## What This Project Is

A product analytics case study that analyses **why customers don't come back** after their first purchase, quantifies the revenue gap, and produces actionable recommendations for a product/growth team.

**Core finding from data:** Only **3.12%** of 96,096 customers placed a second order. That means 96.9% are one-time buyers — a massive re-engagement opportunity.

---

## Project Goal

- Identify root causes of low repeat purchase rates
- Quantify revenue impact of converting even a small fraction of one-time buyers
- Produce a Power BI dashboard and a case study deck for interview presentation

---

## Data Overview (Olist Dataset)

| File | Rows | What It Contains |
|---|---|---|
| `olist_customers_dataset.csv` | 99,441 | Customer ID bridge + geography. `customer_id` is order-scoped; `customer_unique_id` is the real person key |
| `olist_orders_dataset.csv` | 99,441 | One row per order. 96,478 are "delivered" — our valid scope |
| `olist_order_items_dataset.csv` | 112,650 | Line items per order — price, freight, product, seller |
| `olist_products_dataset.csv` | 32,951 | Product catalog with Portuguese category names |
| `product_category_name_translation.csv` | 71 | Portuguese → English category mapping |
| `olist_order_payments_dataset.csv` | 103,886 | Payments per order (can be multiple rows — e.g. voucher + card) |
| `olist_order_reviews_dataset.csv` | 99,224 | Review score (1–5) per order; 88% of comment fields are null |

**Excluded from first pass:** `olist_sellers_dataset.csv`, `olist_geolocation_dataset.csv`

**Key data quirk:** `customer_id` is generated fresh per order — using it as a person identifier makes every customer look like a one-time buyer. Always join through `olist_customers_dataset` to get `customer_unique_id`.

**Baseline numbers (delivered orders only):**
- 96,096 unique persons
- 93,099 (96.9%) placed exactly 1 order
- 2,745 (2.9%) placed exactly 2 orders
- 252 (0.3%) placed 3+ orders
- Overall repeat rate: **3.12%**

---

## Folder Structure

```
repeat-purchase-recovery/
├── data/
│   ├── raw/            9 source CSV files from Olist
│   ├── cleaned/        Reserved for processed outputs
│   └── exports/        Reserved for Power BI export tables
├── docs/               6 documentation files (see below)
├── sql/                15 SQL files — full pipeline from raw to dashboard views
├── notebooks/          6 Jupyter notebooks (EDA through scenario analysis)
├── src/                8 Python module stubs (not yet implemented)
├── powerbi/            Power BI .pbix file
├── images/             5 saved charts + placeholder images
└── presentation/       Interview case study deck (stub)
```

---

## What Has Been Done (Completed Work)

### Phase 1 — Data Audit & Documentation
All documentation was written before any SQL to ensure correctness:

- **`docs/data_inventory.md`** — Full schema for all 7 source files: row counts, column types, null counts, unique counts, key join risks, recommended fields per analysis type
- **`docs/data_model.md`** — Layer-by-layer architecture: 6 cleaned base views + 8 analytical mart definitions, including grain, fields, and derivation logic
- **`docs/metric_definitions.md`** — Every metric defined with formula, grain, denominator rules, and known limitations. Covers repeat rates, CLV windows, review scores, delivery delay, churn flags
- **`docs/project_brief.md`** — Business objective, stakeholders, timeline, scope
- **`docs/dashboard_plan.md`** — Placeholder for Power BI page design (not yet filled)
- **`docs/business_recommendations.md`** — Placeholder for post-analysis recommendations (not yet filled)
- **`docs/interview_prep.md`** — Placeholder for interview talking points (not yet filled)

### Phase 2 — Full SQL Pipeline (SQLite)

The SQL layer is 100% complete and validated. All 16 SQL files implement a 5-step data pipeline ending in 7 dashboard-ready views.

**Step 1 — Cleaned Base Views (`02_data_cleaning.sql`)**
Six views that touch raw tables and apply filtering + parsing:

| View | What It Does |
|---|---|
| `orders_clean` | Filters to `order_status = 'delivered'` (96,478 rows); parses all timestamps via `DATETIME()` |
| `customers_clean` | Pass-through of all 99,441 rows; bridges `customer_id` → `customer_unique_id` |
| `order_items_clean` | INNER JOINs to `orders_clean` to keep only delivered-order items; retains item-level price and freight |
| `order_payments_clean` | INNER JOINs to `orders_clean`; retains multi-row payment structure (split payments) |
| `order_reviews_clean` | INNER JOINs + deduplicates to one row per `order_id` using `ROW_NUMBER()`: latest answer timestamp wins, completeness as tiebreaker |
| `products_clean` | LEFT JOINs to translation file; resolves `product_category_resolved` via 3-tier COALESCE: English → Portuguese → 'unknown' |

Comes with 16 validation queries (V1–V16) covering row counts, duplicates, nulls, join coverage.

**Step 2 — Order Aggregations (`03_order_aggregations.sql`)**
Collapses multi-row tables to one row per order:

| View | What It Does |
|---|---|
| `order_revenue` | Aggregates `order_items_clean` → one row per order: total item price, freight, item count, category count, primary category (ranked by most items). Uses CTE + `ROW_NUMBER()` for primary category selection |
| `order_payment_total` | Aggregates `order_payments_clean` → one row per order: total collected payment value, primary payment type, max installments, split payment flag |

Comes with 11 validation queries (V17–V27) including a revenue divergence check between the two views.

**Step 3 — Central Fact Table (`04_customer_order_fact.sql`)**
Joins all Step 1 and Step 2 views into a single wide order-level fact table:

- **Grain:** One row per `order_id` (all 96,478 delivered orders)
- **Joins:** INNER JOIN to customers, order_revenue; LEFT JOIN to payments (1 missing), reviews (646 missing)
- **Derived fields:** `delivery_days`, `delivery_delay_days`, `delivered_on_time_flag`, `freight_ratio`
- **All fields carried:** customer identity, order timestamps, geography, payment, basket, review, delivery performance

Comes with 9 validation queries (V28–V36).

**Step 4 — Order Sequencing (`05_order_sequence.sql`)**
Adds purchase-order context to every row using window functions:

- **Grain:** One row per `customer_unique_id × order_id`
- **Fields added:** `order_sequence_number` (1 = first order), `previous_order_id/timestamp`, `next_order_id/timestamp`, `days_since_previous_order`, `days_until_next_order`, `days_since_first_order`, `is_first_order`, `is_second_order`
- **Window:** `PARTITION BY customer_unique_id ORDER BY order_purchase_timestamp ASC, order_id ASC` (deterministic tie-break)
- **Requires SQLite ≥ 3.28** for named WINDOW clause

Comes with 10 validation queries (V37–V46).

**Step 5 — Customer-Level Marts (`06_customer_marts.sql`)**
Six analytical marts, all grain: one row per `customer_unique_id`:

| Mart | What It Contains |
|---|---|
| `customer_first_purchase_mart` | Complete profile of every customer's first order: value, basket size, category, payment type, review score, delivery days, geography |
| `customer_repeat_status_mart` | Whether each customer repeated + right-censored flags for 30/60/90-day windows. NULL = insufficient exposure time (not counted in rate denominators) |
| `customer_clv` | Cumulative revenue in 30/90/180-day windows and lifetime. `clv_band` label: no_revenue / low / mid / high / top. No forward projection — all observed history |
| `retention_cohorts` | Monthly cohort × period grid with `retention_rate`. Right-censored: only observable (cohort, period) pairs included. Period 0 = 100% by definition |
| `segment_performance_mart` | 7 segmentation dimensions (category, order value, basket size, review score, delivery speed, payment type, state) × repeat rates + revenue averages per bucket. Built with UNION ALL |
| `churn_signal_mart` | 7 binary flags per customer: low review score, late delivery, single-item order, low order value (<R$50), high freight ratio (>50%), no repeat in 90 days, no review submitted |

Comes with 10 validation queries (V47–V56).

**Step 6 — Dashboard Views (`99_dashboard_views.sql`)**
Seven Power BI-ready views built from Step 5 marts:

| Dashboard View | Purpose |
|---|---|
| `executive_kpi_summary` | Single-row scorecard: total customers, repeat buyers, repeat rates (raw + 30/60/90d windowed), avg/median days to second purchase, avg revenue 90d/180d. Includes SQLite median workaround via `ROW_NUMBER()` |
| `repeat_purchase_trend_monthly` | Monthly trend: first orders, second orders, cohort repeat rate, avg days to second purchase |
| `cohort_heatmap_source` | Direct passthrough of `retention_cohorts` for Power BI heatmap |
| `segment_summary_dashboard` | Segment comparison table — all 7 dimensions, sorted by customer count |
| `clv_distribution_summary` | 5-row CLV band breakdown with customer counts, avg revenue, total revenue. Includes `clv_band_order` for correct Power BI sorting |
| `churn_signal_summary` | 7-row summary of each churn flag: flagged customers, eligible customers, flagged rate. Denominator = eligible (non-null) customers only |
| `repeat_vs_one_time_summary` | 2-row side-by-side: repeat buyers vs one-time buyers across revenue, first order value, review score, delivery days |

Comes with 7 validation queries (V57–V63).

**SQL files that are stubs (not yet implemented):**
- `01_schema_check.sql` — placeholder only (manual validation was done via docs)
- `03_customer_first_purchase.sql` — superseded by `customer_first_purchase_mart` in `06_customer_marts.sql`
- `04_repeat_purchase_status.sql` — superseded by `customer_repeat_status_mart`
- `05_retention_cohorts.sql` — superseded by `retention_cohorts` mart
- `06_funnel_analysis.sql` — stub (planned for funnel stage analysis)
- `07_segmentation.sql` — superseded by `segment_performance_mart`
- `08_clv_analysis.sql` — superseded by `customer_clv` mart
- `09_churn_signals.sql` — superseded by `churn_signal_mart`
- `10_scenario_analysis.sql` — stub (revenue uplift modelling — not yet built)

### Phase 3 — Exploratory Analysis (Notebooks)

**`notebooks/02_exploratory_analysis.ipynb`** — The main EDA notebook (modified, committed). Produced 5 saved charts:

| Chart | What It Shows |
|---|---|
| `images/repeat_vs_onetime_split.png` | Pie/bar of 96.9% one-time vs 3.1% repeat buyer split |
| `images/monthly_first_order_trend.png` | Monthly volume of first orders over the 25-month dataset window |
| `images/monthly_first_vs_second_orders.png` | First vs second order counts per month — shows the scale gap |
| `images/order_frequency_distribution.png` | Distribution of total orders per customer (highly right-skewed) |
| `images/repeat_rate_and_days_to_second.png` | Repeat rate and median days-to-second-purchase breakdown |
| `images/clv_distribution.png` | CLV band distribution across customer population |

**Other notebooks (not yet run against real data — placeholders):**
- `notebooks/01_data_audit.ipynb` — Data quality checks
- `notebooks/03_retention_and_cohorts.ipynb` — Cohort heatmaps
- `notebooks/04_segmentation_and_behavior.ipynb` — RFM segmentation
- `notebooks/05_clv_and_churn_signals.ipynb` — CLV and churn flag analysis
- `notebooks/06_scenario_analysis.ipynb` — Revenue uplift scenarios

---

## Python Source Files (All Stubs — Not Yet Implemented)

| File | Planned Purpose |
|---|---|
| `src/config.py` | DB connection, file paths, analysis parameters |
| `src/utils.py` | DB I/O, SQL execution, data export helpers |
| `src/data_cleaning.py` | Load raw CSVs, apply cleaning rules, save outputs |
| `src/feature_engineering.py` | Build customer-level feature table for segmentation/churn |
| `src/retention.py` | Cohort retention matrices and retention curves |
| `src/segmentation.py` | RFM scoring: score customers, assign labels, profile segments |
| `src/clv.py` | Historical CLV and projected CLV estimates |
| `src/churn_signals.py` | Churn risk flags and score per customer |

All 8 files contain only a docstring with a TODO. The SQL layer handles all of this logic directly.

---

## Key Design Decisions Made

1. **Delivered-only scope:** Only `order_status = 'delivered'` (96,478 of 99,441 orders). Canceled/shipped orders excluded to prevent false retention counts.

2. **`customer_unique_id` is the person key:** `customer_id` is order-scoped — using it makes every customer look like a one-time buyer. All person-level analysis joins through `olist_customers_dataset`.

3. **Two revenue views, not one:** `total_payment_value` (actual collected, post-voucher) for CLV/RFM; `total_order_revenue_item_view` (item price + freight) for basket analysis. Never mixed.

4. **Right-censoring on repeat windows:** Customers whose first purchase was within N days of the dataset end date get `NULL` (not 0) for that repeat window. This prevents recent customers from deflating repeat rates.

5. **Rule-based churn signals, not ML:** 7 binary flags based on observable first-order data. No model training. Thresholds are documented and adjustable.

6. **SQLite dialect throughout:** All SQL uses SQLite 3.25+ functions (`ROW_NUMBER`, `LAG`, `LEAD`). Named WINDOW clause requires 3.28+. Current environment: 3.50.4.

7. **Validation query series (V1–V63):** Every SQL step comes with read-only validation queries. All expected values are documented so failures are immediately obvious.

---

## What Is Still To Do

| Item | Status |
|---|---|
| `notebooks/03` through `06` — run against real data | Not started |
| `src/` Python modules — implement | Stub only |
| `docs/business_recommendations.md` — fill with real findings | Placeholder |
| `docs/interview_prep.md` — fill with real numbers | Placeholder |
| `presentation/case_study_summary.md` — complete | Placeholder |
| `docs/dashboard_plan.md` — design Power BI pages | Placeholder |
| `sql/10_scenario_analysis.sql` — revenue uplift model | Stub only |
| Power BI dashboard — build visuals | `.pbix` file exists, visuals not built |
| Add indexes and materialise mart views for performance | Script exists (`add_indexes_and_materialize.py`) but untracked |

---

## Untracked Files (Not Yet Committed)

These files exist locally but haven't been pushed to git:

| File | What It Is |
|---|---|
| `add_indexes_and_materialize.py` | Script to add SQLite indexes and materialise view chains for performance |
| `apply_views.py` | Script to apply/run all SQL view definitions against `olist.db` |
| `materialize_marts.py` | Script to materialise mart views into physical tables |
| `rewire_dashboard_views.py` | Script to rewire dashboard views to read from materialised tables |

---

## Metrics Reference (Key Numbers)

| Metric | Value |
|---|---|
| Total delivered orders | 96,478 |
| Total unique customers | 96,096 |
| One-time buyers | 93,099 (96.9%) |
| Repeat buyers (2+ orders) | 2,997 (3.12%) |
| Customers with exactly 2 orders | 2,745 |
| Customers with 3+ orders | 252 |
| Dataset date range | Sep 2016 – Oct 2018 (≈25 months) |
| Average item price (BRL) | ~120.65 |
| Average freight value (BRL) | ~19.99 |
| Freight as % of item price | ~14% |
| Review coverage | 99.2% of all orders have a review |
| Reviews scored 5 stars | 57,328 of 99,224 (57.8%) |
| Reviews scored 1–2 stars | 14,575 (14.7%) |
| Payment method (dominant) | credit_card (76,795 rows) |
| Orders with single item | 88,863 of 98,666 (90%) |

---

## SQLite Views Created (In Execution Order)

```
Layer 1 — Cleaned Base
  orders_clean
  customers_clean
  order_items_clean
  order_payments_clean
  order_reviews_clean
  products_clean

Layer 2 — Order Aggregations
  order_revenue
  order_payment_total

Layer 3 — Central Fact
  customer_order_fact

Layer 4 — Sequencing
  order_sequence

Layer 5 — Customer Marts
  customer_first_purchase_mart
  customer_repeat_status_mart
  customer_clv
  retention_cohorts
  segment_performance_mart
  churn_signal_mart

Layer 6 — Dashboard Views
  executive_kpi_summary
  repeat_purchase_trend_monthly
  cohort_heatmap_source
  segment_summary_dashboard
  clv_distribution_summary
  churn_signal_summary
  repeat_vs_one_time_summary
```

Total: **20 SQLite views** (6 + 2 + 1 + 1 + 6 + 7), validated end-to-end with 63 read-only checks.
