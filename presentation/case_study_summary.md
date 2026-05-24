# Repeat Purchase Recovery — Case Study Summary

**Domain:** Brazilian e-commerce (Olist marketplace)
**Window:** September 2016 – August 2018 (~23 months)
**Scope:** 93,358 customers · 96,478 delivered orders
**Stack:** SQLite · Python · Jupyter · Power BI

---

## The Problem

Only **3.0%** of Olist's customers ever placed a second order. 90,557 customers bought exactly once and were never seen again. The platform's revenue model rested almost entirely on acquiring new customers, not retaining existing ones — exposing it to rising acquisition costs and capped lifetime value.

The question was straightforward: **why don't customers come back, and what would it take to change that?**

---

## Approach

A 6-layer SQLite pipeline (raw CSVs → cleaned views → fact table → sequencing → customer marts → dashboard views), validated end-to-end with 63 read-only checks. Notebook analysis on top of the marts to surface patterns; scenario modeling to translate findings into directional revenue impact.

- **Notebook 02:** Exploratory analysis — repeat vs one-time split, time-to-second-purchase distribution
- **Notebook 03:** Cohort retention heatmap, decay curve, best/worst cohort identification
- **Notebook 04:** Segmentation across 7 dimensions (basket, value, review, delivery, payment, category, geography)
- **Notebook 05:** CLV bands and 7 rule-based churn signals
- **Notebook 06:** Scenario modeling against validated per-buyer revenue benchmarks

---

## Key Findings

1. **The return window is narrow.** Median time to second order is 29 days; 50% of repeat buyers return inside 30 days. After that, return probability collapses.
2. **Single-item first orders are the structural bottleneck.** 90% of customers (84,151) bought a single item on first order; they repeat at 2.15% vs 3.15% for 2-item buyers and 5.38% for 6+ item buyers — a 2.5× lift.
3. **Holiday cohorts retain worst.** Nov 2017 – Jan 2018 cohorts retained at 1.55% vs 2.42% for mid-2017 — a calendrically predictable 0.87pp gap.
4. **Late delivery suppresses repeat — but late-delivery customers are higher value.** Repeat rate 2.05% vs 2.30% for early delivery, but lifetime revenue R$178 vs R$164. Worth recovering, not writing off.
5. **The revenue gap between repeat and one-time buyers is 58%.** Repeat buyers spent R$253 over 90 days vs R$161 for one-time buyers — a R$92 per-buyer uplift.

---

## Recommendations

Three ranked plays, by reach × validated lift × feasibility:

| Priority | Play | Target | Why |
|---|---|---|---|
| 1 | Cross-sell program for single-item buyers | 84,151 customers (90% of base) | Largest reach; validated 1pp gap to 2-item behavior |
| 2 | Holiday-cohort re-engagement | ~19,000 customers/year | Predictable, plannable, 0.87pp retention gap to close |
| 3 | Delivery-delay recovery touchpoint | 7,428 customers/year | Highest per-customer value, real-time addressable |

Full reasoning: [docs/business_recommendations.md](../docs/business_recommendations.md).

---

## Scenario Analysis (What-If, Not Forecast)

Per-buyer revenue grounded in validated CLV benchmarks — not aggregate × buyer count.

| Scenario | Assumption | Incremental Repeat Buyers | Per-Buyer | Horizon |
|---|---|---|---|---|
| Cross-Sell | +1.0pp lift on single-item buyers | ~841 | R$92.34 | 90-day |
| Delivery Recovery | 50% closure of late-delivery gap | ~9 | R$178.10 | Lifetime |
| Holiday Cohort | 50% closure of holiday gap | ~78 | R$253.10 | 90-day |

**Combined medium-case:** ~928 incremental repeat buyers — a **33% uplift** against the current base of 2,801.

---

## Limitations

- Observational study, not causal. No experimental design implied.
- No marketing, session, or ad-spend data — only transactional features.
- Right-censored windows mean recent customers are excluded from long-window denominators.
- 2016–2018 Brazilian e-commerce; generalization to other markets/years is unverified.

---

## What I'd Do Next

- Design an A/B test for the cross-sell play (treatment + holdout).
- Build a time-to-second-purchase survival model (Kaplan-Meier or Cox) to replace windowed flags.
- Integrate cost-of-intervention so scenarios translate into ROI, not just revenue uplift.
- Refresh against current-year data to confirm 2017-era patterns still hold.
