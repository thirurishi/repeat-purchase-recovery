# Dashboard Plan: Repeat Purchase Recovery

**Tool:** Power BI Desktop
**File:** `powerbi/repeat_purchase_recovery.pbix`
**Data source:** `data/olist.db` (SQLite) — connect via ODBC or import the 7 dashboard views from [sql/99_dashboard_views.sql](../sql/99_dashboard_views.sql).

**Audience:** Product, growth, and retention leadership. Read time per page: 30–60 seconds.

---

## Page 1 — Executive Overview

**Purpose:** Single-screen answer to "where do we stand on repeat purchase?"

**Source views:** `executive_kpi_summary`, `repeat_vs_one_time_summary`

**KPI cards (top row):**
- Total customers (93,358)
- Repeat buyers (2,801)
- Lifetime repeat rate (3.0%)
- 90-day repeat rate (2.28%)
- Median days to second order (29)

**Visuals:**
- Donut: repeat vs one-time buyer split (96.9% / 3.1%)
- Bar pair: avg 90-day revenue — repeat (R$253) vs one-time (R$161)
- KPI strip: 30-day / 60-day / 90-day right-censored repeat rates

**Business questions answered:**
- What's our overall repeat rate?
- How big is the revenue gap between repeat and one-time buyers?
- How quickly do customers come back when they do?

---

## Page 2 — Retention & Cohorts

**Purpose:** Show retention decay over time and identify which acquisition months retain best/worst.

**Source views:** `cohort_heatmap_source`, `repeat_purchase_trend_monthly`

**Visuals:**
- Cohort retention heatmap (cohort month × period since first purchase)
- Line: monthly first-order volume + monthly second-order volume on dual axis
- Bar: best vs worst cohorts by 6-month retention

**Slicers:** Cohort month range, period since first purchase.

**Business questions answered:**
- Which acquisition cohorts retained best — and worst?
- Is retention decaying, stable, or improving over time?
- Which months should re-engagement budget target?

---

## Page 3 — Customer Segmentation

**Purpose:** Compare repeat-rate performance across all 7 behavioral segments.

**Source views:** `segment_summary_dashboard`

**Visuals:**
- Stacked bar matrix: repeat rate by basket size · order value tier · review score · delivery speed · payment type · category · geography
- Single combined table: dimension, segment, customer count, repeat rate, avg 90-day revenue
- Top-5 underperforming segments callout

**Slicers:** Segmentation dimension (filter visuals to one dimension at a time).

**Business questions answered:**
- Which segments under- or over-perform on repeat?
- Where are the structural bottlenecks (e.g. single-item buyers)?
- Which segments are largest by customer count?

---

## Page 4 — CLV Distribution

**Purpose:** Show how customer value is distributed and where the revenue concentration lies.

**Source views:** `clv_distribution_summary`

**KPI cards:** Avg 90-day revenue, avg 180-day revenue, top-band customer count.

**Visuals:**
- Bar: customers per CLV band (no_revenue · low · mid · high · top), sorted via `clv_band_order`
- Bar: total revenue contribution per band
- Side-by-side: customer count vs revenue share per band (Pareto check)

**Business questions answered:**
- Is revenue concentrated in a small top tier?
- What share of customers contribute meaningful revenue?
- Which bands are the priority for retention investment?

---

## Page 5 — Churn Signals

**Purpose:** Show which observable first-order signals predict non-repeat, ranked by reach × severity.

**Source views:** `churn_signal_summary`

**Visuals:**
- Horizontal bar: flagged-customer count per signal
- Horizontal bar: flagged rate (flagged / eligible) per signal
- Scatter/quadrant: prevalence (x) × repeat-rate suppression (y) with each signal as a point
- Table: signal name, flagged customers, eligible customers, flagged rate, repeat rate among flagged

**Business questions answered:**
- Which churn signals are most prevalent?
- Which signals correlate most strongly with non-repeat?
- Which signals are operationally addressable in real time (e.g. late delivery)?

---

## Page 6 — Scenario Analysis

**Purpose:** Translate findings into directional revenue impact under stated uplift assumptions. **Framed as what-if, not forecast.**

**Source:** Numbers come from [notebooks/06_scenario_analysis.ipynb](../notebooks/06_scenario_analysis.ipynb). Either re-export to a CSV in `data/exports/` or hard-code constants in Power BI.

**Visuals:**
- 3 grouped bar charts (one per scenario): low / medium / high uplift × incremental repeat buyers × incremental revenue
- Priority table: scenario, reach, incremental buyers (medium), incremental revenue, effort, feasibility
- Combined-impact card: ~928 incremental repeat buyers under medium-case (33% uplift vs current base)

**Caveats panel (text box):**
- Scenarios are directional estimates, not forecasts
- Per-buyer revenue benchmarks sourced from validated CLV analysis (NB05)
- Horizons differ across scenarios (90-day vs lifetime) and are labeled

**Business questions answered:**
- What is each retention play worth at realistic uplift?
- Which play has the best reach-vs-impact ratio?
- What's the combined opportunity if all three plays are run?

---

## Cross-Page Conventions

- **Color palette:** Blue `#2563EB` for repeat / positive, Orange `#EA580C` for one-time / risk, Grey `#94A3B8` for neutral. Same palette as the saved notebook charts in [images/](../images/).
- **Number formatting:** Currency in BRL (R$), rates to 2 decimal places, customer counts with thousands separator.
- **Global slicer (where applicable):** Cohort month range.
- **Header strip:** Project title, last refresh date, link to README.

---

## Implementation Order

1. Connect Power BI to `data/olist.db` (or import the 7 dashboard views as CSVs from `data/exports/`).
2. Build Page 1 first — it's the highest-impact recruiter view.
3. Apply the color palette and number formats globally.
4. Build Pages 2–5 against the source views (no DAX modeling needed — views are pre-aggregated).
5. Build Page 6 last, using exported NB06 scenario tables.
6. Add page navigation buttons and a one-line caveat footer on every page.
