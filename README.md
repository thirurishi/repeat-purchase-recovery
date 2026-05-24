# Repeat Purchase Recovery

A product analytics case study on a Brazilian e-commerce dataset (Olist, Sep 2016 – Aug 2018) that answers a single question: **why don't customers come back, and what would it take to change that?**

---

## Business Problem

Across **93,358 customers** and **96,478 delivered orders**, only **3.0%** of customers ever placed a second order. 90,557 customers bought once and were never seen again.

A platform whose revenue model rests almost entirely on new-customer acquisition — rather than retention of existing ones — is exposed to rising acquisition costs and capped lifetime value. This project identifies the structural drivers of that gap and quantifies what closing it would be worth.

---

## Why It Matters

- **Repeat buyers spent 58% more over 90 days** than one-time buyers (R$253 vs R$161).
- **50% of all eventual repeat buyers returned within 29 days** of their first order — meaning the intervention window is narrow and currently unused.
- Even modest improvements (a 1pp lift in single-item repeat rate, partial closure of the holiday-cohort retention gap) translate into hundreds of incremental repeat buyers per year against a base of only 2,801.

---

## Dataset

Olist Brazilian E-Commerce Public Dataset (Kaggle): 9 CSVs covering orders, customers, items, payments, reviews, products, sellers, and geolocation.

- **Scope used:** 7 of 9 files (sellers and geolocation excluded from this pass).
- **Filter:** Only `order_status = 'delivered'` orders (96,478 of 99,441).
- **Person key:** `customer_unique_id` (the raw `customer_id` is order-scoped and would make every customer look one-time).
- **Date range:** September 2016 – August 2018 (~23 months).

---

## Tools

- **SQLite** — full analytical pipeline lives here
- **Python** — pandas, numpy, matplotlib (in notebooks)
- **Jupyter** — exploratory and visual analysis (NB01–NB06)
- **Power BI** — interactive dashboard (`.pbix` file)

---

## Architecture

A 6-layer SQL pipeline that turns raw CSVs into Power BI-ready views. Every layer ships with read-only validation queries (63 total, V1–V63).

```
Raw CSVs (data/raw/)
        │
        ▼
Layer 1  Cleaned base views (6)         02_data_cleaning.sql
        │   orders_clean, customers_clean, order_items_clean,
        │   order_payments_clean, order_reviews_clean, products_clean
        ▼
Layer 2  Order aggregations (2)         03_order_aggregations.sql
        │   order_revenue, order_payment_total
        ▼
Layer 3  Central fact (1)               04_customer_order_fact.sql
        │   customer_order_fact (one row per delivered order)
        ▼
Layer 4  Sequencing (1)                 05_order_sequence.sql
        │   order_sequence (first/next order metadata via window fns)
        ▼
Layer 5  Customer-level marts (6)       06_customer_marts.sql
        │   first_purchase_mart, repeat_status_mart, customer_clv,
        │   retention_cohorts, segment_performance_mart, churn_signal_mart
        ▼
Layer 6  Dashboard views (7)            99_dashboard_views.sql
            executive_kpi_summary, repeat_purchase_trend_monthly,
            cohort_heatmap_source, segment_summary_dashboard,
            clv_distribution_summary, churn_signal_summary,
            repeat_vs_one_time_summary
```

20 SQLite views in total, all validated end-to-end.

---

## Key Findings

1. **Extremely low repeat rate across every window.** Lifetime 3.0% · 90-day 2.28% · 60-day 1.96% · 30-day 1.59%. All windows right-censored to avoid inflating the denominator with recent customers.

2. **The return window is short and front-loaded.** Median time to second order is 29 days; 50% of repeat buyers return inside 30 days, 68% inside 90 days. After 30 days the probability of return drops sharply.

3. **Single-item first orders are the structural bottleneck.** 90.1% of customers (84,151) place a single-item first order; they repeat at 2.15%. 2-item buyers repeat at 3.15%, 6+ item buyers at 5.38% — a 2.5× lift.

4. **Holiday-acquired cohorts retain worst.** November 2017 – January 2018 cohorts (~19,000 customers) retained at 1.55% vs 2.42% for mid-2017 cohorts — a 0.87pp gap that is calendrically predictable.

5. **Late delivery suppresses repeat behavior, but late-delivery customers are higher value.** Late-delivery repeat rate is 2.05% vs 2.30% for early delivery, yet their average lifetime revenue (R$178) exceeds the baseline — they're worth recovering, not writing off.

6. **Review behavior is a clean leading indicator.** 14.7% of orders receive 1–2 star reviews; these customers repeat dramatically less. Review score is recorded on 99.2% of orders, so the signal is reliable.

---

## Business Recommendations

Three plays, ranked by reach × validated lift × feasibility. Full reasoning in [docs/business_recommendations.md](docs/business_recommendations.md).

| Priority | Play | Target | Why |
|---|---|---|---|
| 1 | **Cross-sell program for single-item buyers** | 84,151 customers (90% of base) | Largest reach. 1pp lift to 2-item buyer behavior is a validated, structural gap. |
| 2 | **Holiday-cohort re-engagement** | ~19,000 customers/year (Nov–Jan) | Calendrically predictable, addressable in advance, 0.87pp retention gap to close. |
| 3 | **Delivery-delay recovery touchpoint** | 7,428 customers/year | Smallest reach but highest per-customer value (R$178 lifetime) and real-time identifiable. |

---

## Scenario Analysis

Three what-if scenarios stress-test what each play would be worth at medium-case assumptions. **These are directional estimates, not forecasts.** All per-buyer revenue is grounded in validated benchmarks from the CLV analysis — not aggregate revenue × buyer count.

| Scenario | Assumption | Incremental Repeat Buyers | Revenue Multiplier | Horizon |
|---|---|---|---|---|
| Cross-Sell | +1.0pp lift on single-item buyers | ~841 | R$92.34 (repeat − one-time 90-day uplift) | 90-day |
| Delivery Recovery | 50% closure of late-delivery gap | ~9 | R$178.10 (late-delivery lifetime) | Lifetime |
| Holiday Cohort | 50% closure of holiday retention gap | ~78 | R$253.10 (repeat buyer 90-day) | 90-day |

**Combined medium-case:** ~928 incremental repeat buyers — a 33% uplift against the current base of 2,801. Full methodology in [notebooks/06_scenario_analysis.ipynb](notebooks/06_scenario_analysis.ipynb).

---

## Repository Structure

```
repeat-purchase-recovery/
├── data/
│   ├── raw/           9 source Olist CSVs
│   └── olist.db       SQLite database (pipeline materialised here)
├── docs/
│   ├── project_brief.md
│   ├── data_inventory.md
│   ├── data_model.md
│   ├── metric_definitions.md
│   ├── business_recommendations.md
│   └── dashboard_plan.md
├── sql/               6 SQL files — the full pipeline
├── notebooks/         01–06: data audit → EDA → cohorts → segmentation → CLV/churn → scenarios
├── images/            26 saved charts referenced by docs and dashboard
├── powerbi/           repeat_purchase_recovery.pbix
└── presentation/      case_study_summary.md
```

---

## Limitations

- **Observational, not causal.** All findings describe associations in historical data. No experimental design or A/B test is implied.
- **No marketing or session data.** The dataset has no traffic, email, ad-spend, or on-site behavior — drivers of repeat are inferred from transactional features only.
- **Right-censoring on the trailing edge.** Customers near the dataset end date have insufficient exposure for long-window repeat flags; their counts are excluded from those denominators (not zero-filled).
- **Two-year window.** Brazilian e-commerce in 2016–2018 may not generalize to other markets or to today's competitive context.
- **Scenarios are not forecasts.** They quantify *what would happen if* a stated uplift were achieved — not the probability of achieving it.

---

## Future Improvements

- Time-to-second-purchase survival model (Kaplan-Meier or Cox) instead of windowed flags.
- A/B test design for the cross-sell play (treatment cohort + holdout).
- Incorporate seller-side and geolocation data for supply-side drivers of retention.
- Cost-of-intervention model so revenue uplift can be translated into ROI.
- Refresh against current-year data to confirm 2017-era patterns still hold.
