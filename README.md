# Repeat Purchase Recovery
### A Product Analytics Case Study | Olist Brazilian E-Commerce

**Why don't customers come back — and what would it take to change that?**

An end-to-end product analytics project investigating repeat purchase behavior, customer retention, lifetime value, and churn signals using the Olist Brazilian E-Commerce dataset. The objective is to translate transactional data into actionable retention strategies and quantify their potential business impact.

---

## Executive Snapshot

| 93,358 | 96,478 | 3.0% | 2,801 |
|:---:|:---:|:---:|:---:|
| Unique customers | Delivered orders | Lifetime repeat rate | Repeat buyers |

| 29 days | 2.28% | 58% | ~928 |
|:---:|:---:|:---:|:---:|
| Median time to return | 90-day repeat rate | Higher 90-day spend among repeat buyers | Potential incremental repeat buyers |

<sub>Metrics are based on the historical dataset and the project's analytical definitions. Scenario results are directional estimates, not forecasts.</sub>

---

## 01 — The Business Challenge

Only around **3% of customers placed a second order** during the observed period. Approximately 90,557 customers purchased once and did not return within the observed dataset.

This creates a fundamental retention challenge: the business relies heavily on acquiring new customers rather than generating subsequent purchases from existing ones.

The analysis investigates three questions:

- **When** are customers most likely to return?
- **Which behavioral and operational signals** are associated with repeat purchasing?
- **Where should the business focus** its retention efforts to maximize reach and potential value?

## 02 — Why Retention Matters

| Business signal | Observed result | Implication |
|---|---|---|
| Customer value | R$253 vs. R$161 in 90-day revenue | Repeat buyers generate more observed revenue |
| Return timing | 29-day median time to second order | Early post-purchase engagement deserves attention |
| First-order basket | 2.15% repeat rate for single-item buyers | A large customer segment has low observed repeat purchasing |
| Basket-size comparison | 5.38% repeat rate for 6+ item buyers | Larger baskets are associated with higher repeat rates |
| Seasonal cohorts | 1.55% vs. 2.42% retention | Holiday-acquired cohorts show a measurable retention gap |
| Delivery experience | 2.05% repeat rate for late deliveries vs. 2.30% for early deliveries | Delivery recovery is a potential retention opportunity |

*These are observational findings. They identify associations, not proven causal effects.*

---

## 03 — Data & Technology

**Dataset:** [Olist Brazilian E-Commerce Public Dataset — Kaggle](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce)

- **Period:** September 2016 – August 2018
- **Source files:** 9 CSVs available; 7 used in this analytical pass
- **Order scope:** Delivered orders only
- **Customer identity:** `customer_unique_id`, rather than order-scoped `customer_id`

### Technology stack

`SQLite` · `SQL` · `Python` · `pandas` · `NumPy` · `Matplotlib` · `Jupyter Notebook` · `Power BI`

---

## 04 — Analytical Architecture

The project uses a six-layer SQL pipeline to transform raw source data into validated analytical views for customer-level analysis and dashboard reporting.

```text
                    RAW OLIST CSV FILES
                            │
                            ▼
               LAYER 1 — CLEANED BASE VIEWS
                    6 SQL views
                            │
                            ▼
               LAYER 2 — ORDER AGGREGATIONS
                    2 SQL views
                            │
                            ▼
               LAYER 3 — CUSTOMER-ORDER FACT
                    1 SQL view
                            │
                            ▼
               LAYER 4 — ORDER SEQUENCING
                    1 SQL view
                            │
                            ▼
               LAYER 5 — CUSTOMER-LEVEL MARTS
                    6 SQL views
                            │
                            ▼
               LAYER 6 — DASHBOARD VIEWS
                    7 SQL views
                            │
                            ▼
                  POWER BI REPORTING
```

**Pipeline at a glance**

- 6 analytical layers
- 20 SQLite views
- 63 read-only validation queries, labelled V1–V63
- Customer-level repeat status, retention cohorts, CLV, behavioral segments, and churn signals

The SQL pipeline separates data preparation, order-level calculations, customer-level metrics, and dashboard-ready outputs for easier validation and maintenance.

---

## 05 — Key Findings

### 01. Repeat purchasing is consistently low

The lifetime repeat rate is approximately 3.0%, with a 90-day repeat rate of 2.28%. The low return rate persists across multiple observation windows.

### 02. The first 30 days are an important intervention window

The median time to second purchase is 29 days. Approximately 50% of eventual repeat buyers return within 30 days, and 68% return within 90 days.

### 03. Single-item first orders represent the largest opportunity

Around 84,151 customers — approximately 90.1% of the customer base — placed a single-item first order. Their observed repeat rate was 2.15%, compared with 5.38% for customers whose first order contained six or more items.

### 04. Holiday-acquired cohorts show weaker retention

November 2017–January 2018 cohorts retained at approximately 1.55%, compared with 2.42% for mid-2017 cohorts. This represents a 0.87 percentage-point gap.

### 05. Late delivery is associated with lower repeat purchasing

Customers receiving orders late had a 2.05% repeat rate, compared with 2.30% for early deliveries. However, the late-delivery segment showed average lifetime revenue of approximately R$178, suggesting a potentially valuable recovery audience.

### 06. Review scores offer a useful diagnostic signal

Approximately 14.7% of orders received one- or two-star reviews. Review behavior provides an additional way to investigate customer experience alongside delivery performance and purchasing patterns.

---

## 06 — From Analysis to Action

The recommendations prioritize the size of the addressable audience, the observed retention gap, and practical feasibility.

| Priority | Recommended play | Target audience | Strategic rationale |
|:---:|---|---:|---|
| 01 | Cross-sell after single-item purchases | 84,151 customers | Address the largest identified customer segment |
| 02 | Holiday-cohort re-engagement | ~19,000 customers | Target cohorts with weaker observed retention |
| 03 | Delivery-delay recovery | 7,428 customers | Investigate and recover customers affected by late deliveries |

**Proposed activation window:** Focus early retention interventions around the first 30 days after the initial purchase, informed by the observed timing of second orders.

Detailed rationale: [`docs/business_recommendations.md`](docs/business_recommendations.md)

---

## 07 — Scenario Analysis

The scenario model estimates the potential impact of three retention initiatives under explicitly stated assumptions.

| Scenario | Assumption | Incremental repeat buyers | Revenue benchmark |
|---|---|---:|---|
| Cross-sell | +1 percentage-point lift among single-item buyers | ~841 | R$92.34 per incremental buyer |
| Delivery recovery | 50% closure of the late-delivery retention gap | ~9 | R$178.10 lifetime revenue benchmark |
| Holiday re-engagement | 50% closure of the holiday-cohort retention gap | ~78 | R$253.10 90-day revenue benchmark |
| **Combined medium case** | **All three scenarios** | **~928** | **Directional estimate** |

The combined scenario represents approximately a **33% increase over the current base of 2,801 repeat buyers**.

These scenarios are sensitivity analyses, not forecasts. The revenue benchmarks use different definitions and time horizons, so they should not be added together as a single revenue estimate without further modelling.

Methodology: [`notebooks/06_scenario_analysis.ipynb`](notebooks/06_scenario_analysis.ipynb)

---

## 08 — Repository Guide

```text
repeat-purchase-recovery/
├── data/
│   ├── raw/                 Source Olist CSVs
│   └── olist.db             Local analytical database
├── docs/
│   ├── project_brief.md
│   ├── data_inventory.md
│   ├── data_model.md
│   ├── metric_definitions.md
│   ├── business_recommendations.md
│   └── dashboard_plan.md
├── sql/                     SQL pipeline and validation
├── notebooks/               NB01–NB06 analytical workflow
├── images/                  Charts and visual outputs
├── powerbi/                 Power BI report
└── presentation/            Case study summary
```

*The structure above describes the intended project organization. Check the actual repository contents before treating every listed file as present.*

---

## 09 — Limitations & Assumptions

- **Observational analysis:** Associations do not establish causality.
- **No marketing attribution:** Traffic, advertising spend, email engagement, and website session data are unavailable.
- **Right-censoring:** Customers near the end of the dataset have less time to place a subsequent order. Windowed repeat rates account for this exposure limitation.
- **Historical context:** The dataset covers 2016–2018 and may not represent current customer behavior.
- **Scenario uncertainty:** Estimated lifts are assumptions used to explore potential impact, not validated intervention outcomes.

---

## 10 — Next Steps

- Use Kaplan–Meier or Cox survival analysis to model time to second purchase.
- Design an A/B test with treatment and holdout groups for the cross-sell initiative.
- Incorporate seller and geolocation data to investigate supply-side drivers.
- Estimate intervention costs and incremental contribution margin to quantify ROI.
- Validate the findings against more recent e-commerce data.

---

## Project Takeaway

**The central opportunity is to move from acquisition-led growth toward measurable customer retention.**

By combining SQL-based data modelling, customer-level behavioral analysis, cohort retention, lifetime-value benchmarks, and scenario modelling, this project translates a low repeat-purchase rate into a prioritized set of testable business initiatives.

*Built with SQL, Python, Jupyter, SQLite, and Power BI.*
