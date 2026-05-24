# Olist Repeat Purchase Recovery — Analysis Q&A Reference

A walkthrough of the project's framing, methodology, and findings — structured as Q&A for quick reference.

---

## 1. 30-Second Summary

I analyzed 23 months of Brazilian e-commerce data (93,358 customers, 96,478 orders) to understand why only 3% of customers repeat. I found that 90% of customers bought single items on their first order, and half of eventual repeat buyers returned within 29 days — but there's no evidence the platform was using this window. I built a five-action prioritization framework backed by validated repeat-rate and revenue benchmarks, ranked by customer reach and business impact.

---

## 2. One-to-Two Minute Explanation

**The Setup:**
I worked with the Olist Brazilian e-commerce dataset covering September 2016 through August 2018. The core question was straightforward: Why don't customers come back? With 93,000 customers but only 2,800 repeaters (3%), the platform's revenue model was almost entirely dependent on new customer acquisition rather than retention.

**The Approach:**
I started with exploratory analysis to map repeat rates across different customer segments — cohorts, order sizes, delivery performance, review scores. Then I built retention cohort analysis, CLV (customer lifetime value) segmentation, and churn signal investigation. Rather than building predictive models, I focused on identifying which observable first-order characteristics actually correlated with repeat behavior and by how much.

**Key Discovery:**
90% of customers placed a single-item first order and repeated at 2.15%. Multi-item first-order customers repeated at 3.40% — a 1.25 percentage point gap affecting almost everyone. Meanwhile, customers with low review scores (1–2 stars) and high-value customers with delayed deliveries had measurably higher lifetime revenue than average. This meant some obvious retention assumptions were wrong.

**The Outcome:**
I ranked five independent interventions by reach and impact, grounded in observed repeat-rate gaps and revenue benchmarks. The analysis shifted the framing from "who is at risk of churning" (turns out, low review score is a bad predictor) to "where are the highest-probability return windows and what segments should we invest in first."

---

## 3. Business Problem & Why It Matters

**The Problem:**
Only 3% of Olist customers placed a second order across a 23-month window. Of 93,358 customers, 90,557 were one-time buyers. The platform was not retaining customers; it was acquiring new ones constantly — a high-cost, unsustainable model.

**Why It Matters (Quantified):**
- **Revenue gap:** Repeat buyers spent R$253 over 90 days; one-time buyers spent R$161. That's 58% more from customers who return.
- **Scale:** If you could shift even 5% of the 84,000 single-item first-order customers to repeat, you'd gain ~4,200 incremental repeat buyers — a 150% increase over the current 2,800.
- **Return window:** 50% of all eventual repeat buyers returned within 29 days. If the platform wasn't engaging customers in this window, it was missing the highest-probability return moment.
- **Customer concentration:** The top 11% of customers (by CLV) account for 40% of revenue. No retention program was visible for this segment in the data.

This is a business problem because **retention is operationally cheaper than acquisition** and **has higher margins**, but the platform had no structured intervention system and no way to measure which retention tactics actually worked.

---

## 4. Dataset & Key Constraints

**Dataset Source:**
Olist Brazilian E-commerce (public dataset, 23 months: Sept 2016 – Aug 2018)

**Scope:**
- **93,358 customers**, 96,478 delivered orders (order-centric filtering)
- **Rich features:** order timestamps, delivery dates, review scores, product categories, payment types, geographic location, order-level revenue
- **What's included:** complete order journey, review feedback, delivery performance
- **What's NOT included:** acquisition channel (no way to segment organic vs paid vs referral), customer clickstream or browse behavior, promotional/discount flags, email engagement or loyalty program membership

**Key Constraints & What They Mean:**

| Constraint | Impact |
|-----------|--------|
| **No acquisition channel data** | Can't separate customer quality effects (paid channels bring cheaper but lower-intent buyers) from retention performance. Cohort differences could reflect acquisition mix rather than platform behavior. |
| **Right-censored observation window** | Customers acquired near end of observation window (e.g., July 2018) won't have a full 90-day window to make a second purchase. Repeat-rate windows (30d, 60d, 90d) exclude these customers to avoid understating the true rate. Lifetime rates (3.0%) include everyone. |
| **No discount/promo field** | Can't determine if customers were price-driven or category-driven. One payment type (voucher) had slightly higher repeat (3.07%), but causality is unclear. |
| **Observational, not experimental** | All associations are correlational. The higher repeat rate for multi-item first orders doesn't prove that basket size *causes* repeat purchases — it's possible customers with strong underlying intent buy multiple items. **True causal claims would require A/B testing.** |
| **Single market, single platform** | Olist is a Brazilian marketplace with specific competitive dynamics, logistics, and customer base. Findings should not be extrapolated to other geographies or platforms without validation. |

**How I Worked Within These Constraints:**
- Focused on **descriptive patterns and segmentation** rather than predictive modeling
- Framed all recommendations as **hypotheses to validate**, not proven levers
- Used cohort analysis and rate comparison to isolate observable patterns
- Acknowledged direction and magnitude, not causality
- Built scenario analysis as "what-if" not "forecast"

---

## 5. Technical Pipeline Summary

**Architecture:**
- **Raw data:** Olist dataset (7 CSV files: customers, orders, order items, payments, reviews, products, seller data)
- **Storage:** SQLite (single-file, portable)
- **Notebooks:** 6 Jupyter notebooks + 1 Python execution script
- **Output:** SQL materialized views (analytics tables), visualizations, scenario analysis

**Pipeline Flow:**

```
NB01: Data Audit
├─ Load raw CSVs, check row counts, validate keys
├─ Identify delivered-only orders (exclude cancellations)
└─ Output: cleaned base tables + quality report

NB02: Exploratory Analysis
├─ Repeat rate by time window (30d, 60d, 90d, lifetime)
├─ Customer segmentation (repeat vs one-time)
├─ First-order characteristics: basket size, value, delivery days, review score
└─ Output: executive KPI summary, initial patterns

NB03: Retention & Cohort Analysis
├─ Cohort performance (acquisition month → retention at 90d, 180d)
├─ Return timing distribution (days to second purchase)
├─ Cumulative retention curves
└─ Output: cohort_performance_summary table

NB04: Segmentation & Behavior Analysis
├─ CLV band definition (low/mid/high/top)
├─ Revenue concentration by band
├─ Repeat rate by category, delivery status, review score
└─ Output: clv_distribution, churn signal flags, behavior analysis

NB05: CLV & Churn Signals
├─ Repeat buyer vs one-time buyer economics
├─ 6 churn signal evaluation (single-item, low value, freight ratio, late delivery, low review, missing review)
├─ Repeat rate + revenue impact per signal
├─ Priority matrix (prevalence × repeat-rate gap × revenue context)
└─ Output: repeat_vs_one_time_summary, churn_signal tables

NB06: Scenario Analysis (CORRECTED)
├─ Validated revenue benchmarks from NB05
├─ 3 what-if scenarios: cross-sell, delivery recovery, holiday cohort
├─ Sanity-check tables (revenue per buyer vs benchmark)
└─ Output: scenario impact estimates, plausibility validation
```

**Key Technical Decisions:**
- **Right-censored repeat rates:** Excluded customers without sufficient tenure at observation window end (e.g., customers acquired in Aug 2018 excluded from 90d rate to avoid understating the rate)
- **Materialized analytics tables:** Pre-computed repeating joins and aggregations in SQL to avoid recalculating during analysis
- **Signal flags as binary columns:** Made churn signals queryable and filterable without recalculating each time
- **Corrected scenario analysis:** Moved from aggregate revenue multipliers to per-buyer benchmarks with validation checks

**Tools & Languages:**
- **Python:** pandas, numpy, matplotlib, sqlite3 (data processing, analysis, visualization)
- **SQL:** Complex joins, window functions, CTEs (analytics layer)
- **Jupyter:** Documentation + reproducible code + inline results
- **Git:** Version control, branch-per-analysis workflow

---

## 6. Key Findings with Real Numbers

### 6.1 Repeat Rate is Extremely Low Across All Windows

| Time Window | Repeat Rate | Eligible Customers | Repeaters |
|------------|-----------|-------------------|-----------|
| 30-day    | 1.59%     | 86,909            | 1,380     |
| 60-day    | 1.96%     | 81,265            | 1,590     |
| 90-day (right-censored) | 2.28% | 75,387 | 1,716 |
| Lifetime (raw) | 3.00% | 93,358 | 2,801 |

→ Even at the 90-day window (most forgiving), the repeat rate is below published e-commerce benchmarks. The 3% lifetime rate includes a long tail; most repeats happen early.

### 6.2 The Return Window Is Short and Front-Loaded

| Metric | Value |
|--------|-------|
| Median days to second purchase | 29 days |
| Mean days to second purchase | 81.2 days (right-skewed) |
| % returning within 30 days | 50% |
| % returning within 90 days | 68% |
| % returning within 180 days | 79% |

→ **Half of repeat buyers return within 30 days.** If no engagement happens in that window, you miss the highest-probability return moment.

### 6.3 Single-Item First Orders Dominate & Suppress Repeat Rates

| First Order Size | Customers | % of Base | Repeat Rate (90d) | Avg 90d Revenue |
|-----------------|-----------|----------|-------------------|-----------------|
| 1 item          | 84,151    | 90.1%    | 2.15%             | R$154          |
| 2 items         | 6,428     | 6.9%     | 3.15%             | R$216          |
| 3-5 items       | 2,011     | 2.2%     | 4.10%             | R$474          |
| 6+ items        | 768       | 0.8%     | 5.38%             | R$707          |

→ **A 1.25pp gap (2.15% → 3.40%) affects 90% of the customer base.** Lift from single to multi-item is 2.5×.

### 6.4 Holiday-Acquired Cohorts Retain Worst

| Cohort Month | Customers | 6m Retention Rate | Notes |
|--------------|-----------|-------------------|-------|
| Nov 2017     | 7,060     | 1.57%             | Largest cohort, worst retention |
| Dec 2017     | 5,338     | 1.46%             | Holiday season / Black Friday |
| Jan 2018     | 6,842     | 1.62%             | Post-holiday buyers |
| **Aug 2017** | **4,057** | **2.46%**         | Best mid-year comparison |
| **Sep 2017** | **4,004** | **2.42%**         | Mid-year baseline |

→ **0.9pp gap**: Nov–Jan cohorts retain at 1.46–1.62% vs 2.37–2.46% for summer. This is a customer composition issue (promo-driven, gift buyers) compounded by lack of targeted re-engagement.

### 6.5 Revenue & Repeat Rates Are Concentrated in a Small Segment

| CLV Band | Customers | % of Total | % of Revenue | 90d Repeat Rate |
|----------|-----------|------------|-------------|-----------------|
| Low (≤R$100) | 43,246 | 46.3% | 16.9% | 0.51% |
| Mid (R$100–249) | 39,774 | 42.6% | 42.8% | 2.98% |
| **High (R$250–800)** | **7,994** | **8.6%** | **22.1%** | **7.05%** |
| **Top (>R$800)** | **2,343** | **2.5%** | **18.2%** | **6.36%** |

→ **Top 11.1% (high + top) generate 40% of revenue and repeat at 3× the baseline rate.** No visible VIP retention program.

### 6.6 Delayed Delivery Has a Modest but Consistent Impact

| Delivery Status | Customers | 90d Repeat Rate | Avg Lifetime Revenue |
|-----------------|-----------|-----------------|---------------------|
| Early (on time or early) | 84,519 | 2.30% | R$164 |
| On-time         | 1,403     | 2.19% | — |
| Late (avg 10 days) | 7,428 | 2.05% | **R$178** |

→ **-0.25pp gap but late-delivery customers are higher-value** (R$178 vs R$164). Worth recovering because the ROI justifies it.

### 6.7 Low Review Scores Do NOT Predict Churn

| Review Score | Customers | 90d Repeat Rate |
|-------------|-----------|-----------------|
| 1–2 stars   | 11,913    | 2.28%           |
| 4–5 stars   | 73,161    | 2.28%           |

→ **Identical repeat rate.** Low scorers even return *faster* on average (62 days vs 86 days). Review score is not a reliable churn signal — don't use it as primary targeting criterion.

### 6.8 Category Has a Large Effect on Repeat Likelihood

| Category | Customers | Repeat Rate (90d) | Type |
|----------|-----------|-------------------|------|
| home_appliances | 675 | **7.69%** | Replenishment/lifestyle |
| bed_bath_table | 8,798 | 4.02% | Replenishment/lifestyle |
| fashion_bags_accessories | 1,699 | 4.58% | Lifestyle building |
| watches_gifts | 5,299 | 1.59% | One-off/gift |
| electronics | 2,466 | 1.08% | One-off |

→ **Replenishment + lifestyle categories (home, bath, fashion) repeat at 4–7×** the rate of one-off or gift categories. Category is actionable for targeting.

---

## 7. Business Recommendations

**Five Actions Ranked by Impact & Feasibility:**

### Priority 1: Multi-Item Cross-Sell Program

**Problem Addressed:** 90% of customers place single-item first orders → repeat at 2.15% vs 3.15% for 2-item buyers (−1.0pp gap)

**Action:**
- At checkout: surface "Frequently bought together" or category bundles for low-basket customers
- Post-purchase (Day 1): send "complete your order" email for single-item buyers in high-affinity categories (bed_bath_table, fashion, home)
- Target bed_bath_table first: 8,798 customers, 4.02% repeat rate, lifestyle category = higher engagement

**Why This:** Largest reach (90% of customers), largest documented gap, lowest behavioral barrier (move 1→2 items).

**Metric to Track:** First-order basket size, 30-day + 90-day repeat rate for treatment group

---

### Priority 2: 30-Day Post-Purchase Win-Back Sequence

**Problem Addressed:** 50% of repeat buyers return within 29 days, but no evidence platform uses this window

**Action:**
- **Day 3:** Delivery confirmation + review request (already happens; link to product recommendations)
- **Day 14:** "You might also like" email based on first-order category
- **Day 25:** Replenishment reminder or category-matched second purchase prompt
- **Day 45:** Final reactivation nudge for non-returners

Sequence differentiated by category: replenishment prompts for consumables, exploration prompts for lifestyle.

**Why This:** Low effort (standard email sequence), lands inside peak return window, 29-day return window is validated

**Metric to Track:** 30-day and 60-day repeat rate, email open rates, click-through, time-to-second-purchase

---

### Priority 3: Holiday Cohort Re-Engagement

**Problem Addressed:** Nov–Jan cohorts retain at 1.46–1.62% vs 2.37–2.46% mid-year (−0.9pp gap affecting ~19,000 customers/year)

**Action:**
- Segment Nov–Jan acquisition cohorts separately
- January/February: "back for yourself" campaign (shift messaging from gift-framing to personal-use categories)
- Offer category-based recommendations in high-repeat categories (home_appliances, fashion_bags, bed_bath)
- Treat as separate cohort to avoid contaminating baseline metrics

**Why This:** Predictable (happens same months annually), customer segment is identifiable, campaign can be planned in advance

**Metric to Track:** Holiday cohort 90-day retention vs non-holiday, campaign engagement, repeat rate lift in target categories

---

### Priority 4: VIP Program for High & Top CLV Customers

**Problem Addressed:** 10,337 customers (high + top bands) generate 40% of revenue but no visible retention investment

**Action:**
- Define VIP tier: High (R$250–800), Top (>R$800) by observed CLV
- Offer operational benefits: priority customer service, free freight on next order, early category access
- Early-warning churn rule: flag VIP customers without purchase in 60 days (vs median 12-day delivery window + 29-day return median = 41-day normal cadence), trigger direct outreach
- **Do not** use discount-only retention — no price sensitivity signal in data

**Why This:** Outsized revenue impact (small retention lift = large $ impact), segment already self-identifies (high natural repeat rate 6–7%), operationally straightforward

**Metric to Track:** VIP retention rate, time-to-churn, revenue per VIP segment, churn reactivation rate

---

### Priority 5: Delivery-Delay Recovery Touchpoint

**Problem Addressed:** 7,428 late-delivery customers repeat at 2.05% vs 2.30% early delivery (−0.25pp gap, but high-value segment: R$178 lifetime)

**Action:**
- Trigger on delivery date miss (carrier flag): send proactive apology + revised ETA before customer complains
- At delivery confirmation: friction-reducing incentive for next order (e.g., reduced freight, not discount — data doesn't support price sensitivity)

**Why This:** Affected group is real-time identifiable from logistics, low operational cost, customers are above-average value

**Metric to Track:** Late-delivery repeat rate, incentive adoption rate, repeat-rate gap closure (target: move 2.05% → 2.15–2.20%)

---

**All Five Actions Are Independent:**
They can run in parallel with no dependencies. Start with Priority 1 (highest reach) and Priority 2 (lowest lift requirement).

---

## 8. Scenario Analysis Summary (Corrected What-If Framing)

**Important Caveat:** These are directional what-if estimates based on observed repeat-rate gaps and validated revenue benchmarks. They show potential impact *if* interventions are executed well and customers respond as observed cohorts do. They are **not forecasts** and should be validated through A/B testing.

### Scenario 1: Cross-Sell Program Success

**Assumption:** +1.0pp repeat-rate uplift on 84,000 single-item buyers (moving them from 2.15% to 3.15%)

**Incremental Impact:**
- Incremental repeat buyers: ~840
- Revenue per buyer: R$92 (90-day incremental uplift: R$253 repeat − R$161 one-time)
- **Estimated 90-day incremental revenue: R$0.08M**

**What This Means:** If 10% of single-item buyers convert to 2-item buyers and 1% of those lift to repeat, you'd gain ~840 repeat buyers at ~R$92 incremental revenue each.

---

### Scenario 2: Delivery-Delay Recovery (50% Gap Closure)

**Assumption:** Recover 50% of the −0.25pp repeat-rate gap via service recovery touchpoint (moving from 2.05% to ~2.125%)

**Incremental Impact:**
- Incremental repeat buyers: ~9
- Revenue per buyer: R$178 (lifetime value of late-delivery customers)
- **Estimated lifetime incremental revenue: R$0.002M**

**What This Means:** Of 7,400 annual late-delivery customers, recovering 50% of the gap yields ~9 repeat buyers. Modest reach but high efficiency (lifetime value justifies outreach cost).

---

### Scenario 3: Holiday Cohort Re-Engagement (50% Gap Recovery)

**Assumption:** 50% gap recovery via targeted re-engagement sequence (moving Nov–Jan cohorts from 1.55% to ~1.96%)

**Incremental Impact:**
- Incremental repeat buyers: ~78
- Revenue per buyer: R$253 (repeat buyer 90-day average)
- **Estimated 90-day incremental revenue: R$0.02M**

**What This Means:** Of ~19,000 annual holiday cohort customers, recovering 50% of the 0.9pp gap yields ~78 repeat buyers at repeat-buyer revenue levels.

---

### Combined Medium-Case View

| Scenario | Incremental Buyers | Revenue | Horizon |
|----------|-------------------|---------|---------|
| Cross-Sell (+1.0pp) | ~840 | R$0.08M | 90-day |
| Holiday Cohort (50% recovery) | ~78 | R$0.02M | 90-day |
| Delivery Recovery (50% recovery) | ~9 | R$0.002M | Lifetime |
| **Total** | **~927** | **~R$0.10M** | Blended |

**This represents a ~33% increase over the current 2,800 repeat buyers** (927 / 2,800 = 33%).

---

**Why These Numbers Are Grounded & Honest:**

1. **Per-buyer benchmarks validated:** Every revenue figure comes directly from observed repeat-buyer data (NB05)
2. **Sanity-checked:** Incremental revenue ÷ incremental buyers = stated benchmark in every scenario
3. **Conservative:** Based on observed gaps, not on assumptions about ideal conversion rates
4. **Labeled:** "90-day" vs "lifetime" clearly distinguished; no mixing of horizons
5. **Not causal:** Framed as "if these rate gaps persist in treatment" not "we'll definitely achieve this"

---

## 9. Common Interview Questions & Strong Answer Points

### Q1: "Walk me through your analysis process. How did you decide what to focus on?"

**Strong Answer:**
"I started with a basic question: why is repeat rate so low? Rather than jump to predictive modeling, I did exploratory analysis to map repeat rates across observable segments — cohorts, basket sizes, categories, delivery status, review scores. This let me identify which segments *actually* had different repeat rates and by how much.

Then I prioritized by business impact: reach × observed gap. For example, single-item first orders affect 90% of customers with a 1.25pp gap, so that's Priority 1. Low review scores affect 12% of customers with 0pp gap, so I deprioritized that as a targeting signal — which was important because it contradicted the intuition that low satisfaction causes churn.

I avoided building a predictive model because:
1. We didn't have treatment/control data, so I couldn't validate any model
2. The business need wasn't 'predict who will churn' but 'where should we intervene and why'
3. Descriptive segmentation + cohort analysis was more immediately actionable

The final output was ranked recommendations backed by observed repeat-rate gaps, not model scores."

---

### Q2: "What was the biggest surprise or counterintuitive finding?"

**Strong Answer:**
"Low review scores didn't predict churn at all. Customers with 1–2 star reviews repeated at the exact same rate (2.28%) as 4–5 star reviewers. Actually, low scorers returned *faster*. 

This changed how I'd approach retention: satisfaction scores alone shouldn't be the primary targeting signal. It turns out these customers were high-value (they bought expensive items that went wrong) and were worth service recovery — but not because they'd churn faster than average. It's a different intervention.

Another one: late-delivery customers had *higher* average lifetime revenue (R$178 vs R$164) than on-time customers. So it wasn't a low-value segment getting what they deserved; it was a high-value segment experiencing friction. That justifies a service recovery investment even though the repeat-rate gap is modest."

---

### Q3: "How did you handle the fact that this is observational data, not experimental?"

**Strong Answer:**
"I was very careful about framing. Everything in my analysis is correlational — I describe what repeat-rate gaps *exist* between segments, not what *causes* those gaps. For example, multi-item first-order customers repeat at a higher rate than single-item buyers, but I can't prove that increasing basket size *causes* repeat purchases. It's possible customers with stronger purchase intent naturally buy multiple items.

That's why I framed all recommendations as hypotheses to validate through A/B testing, not as proven levers. The analysis says 'here are the segments with the biggest observed gaps — test these first.' It doesn't say 'do this and repeat rate will definitely improve.'

I also noted data limitations upfront: no acquisition channel (can't separate channel quality from platform retention), no clickstream (can't validate actual discovery intent), no discount field (can't assume price sensitivity). These constraints mean the conclusions are specific to this dataset and may not generalize to other platforms."

---

### Q4: "What was the technical piece that was most important?"

**Strong Answer:**
"Two things stood out:

First, the right-censored repeat-rate calculations. If you include customers acquired in July–August 2018, their 90-day window extends past the observation end, so you'd understate the true repeat rate. I had to exclude them and recompute rates only on customers with sufficient tenure. That's a small detail but it changed the baseline numbers enough to matter.

Second, I discovered the scenario analysis was using the wrong revenue multipliers — multiplying incremental buyers by aggregate revenue instead of per-buyer benchmarks. I rebuilt that from the ground up using validated benchmarks from the earlier CLV analysis. Every scenario now includes a sanity-check table: incremental buyers × revenue per buyer = total revenue. That one fix made the output directionally plausible rather than inflated.

Neither of those were fancy — they were just careful data hygiene."

---

### Q5: "How would you measure if these recommendations actually worked?"

**Strong Answer:**
"For each recommendation, I'd have a primary metric:

- **Cross-sell:** Track first-order basket size (% of customers buying 2+ items) and 30/90-day repeat rate for the cohort
- **Win-back sequence:** Email engagement (opens, clicks), time-to-second-purchase vs control group, incremental repeat rate at 30d and 60d
- **Holiday cohort:** Compare Nov–Jan 2019 retention to Nov–Jan 2018 (the treated cohort) or to summer 2019 (the baseline)
- **VIP program:** Retention rate in high/top CLV bands, time-to-churn, reactivation rate on the 60-day churn alert
- **Delivery recovery:** Repeat rate for late-delivery customers pre vs post intervention

I'd want to run each as a separate A/B test with enough sample size to detect the documented gap (0.25pp–1.25pp depending on the scenario).

Ideally, I'd also track secondary metrics: email unsubscribe rate, customer satisfaction, brand perception. You want to lift retention without eroding trust."

---

### Q6: "If you had more time or more data, what would you investigate next?"

**Strong Answer:**
"Three things:

1. **Acquisition channel:** Break down repeat rates by how customers arrived (paid search, organic, referral, affiliate). The holiday cohort is weak, but is that because November buyers are inherently lower-intent or because that cohort came through a specific cheap channel? That would change whether the solution is channel mix or post-purchase engagement.

2. **Browsing & discovery behavior:** I had no clickstream data. Do multi-item first-order customers spend more time browsing categories? Do they visit related products? Understanding discovery behavior would make the cross-sell recommendation more precise — you'd know whether to focus on checkout bundles vs post-purchase recommendations.

3. **A/B test learnings:** Build a treatment/control framework and validate that the observed correlations actually predict treatment response. For example, does increasing basket size for single-item buyers in the treatment group actually lift repeat rate? Or is the high repeat rate in natural multi-item buyers due to unobserved customer intent?

Those would require either richer data or the ability to run experiments. The current analysis is as clean as I can get it from the available data."

---

### Q7: "Tell me about a decision you'd do differently in retrospect."

**Strong Answer:**
"Early on, I almost built a churn prediction model using logistic regression. I had the flags (single item, low value, late delivery, etc.), so it was tempting. But I stepped back and asked: 'What would I actually do with a model score?'

The answer was: probably nothing new. The model would say 'this customer has a 40% churn risk,' but without knowing what intervention to apply or how to measure response, the score is just noise. And since I didn't have treatment data, I couldn't validate the model anyway.

So I switched to pure segmentation: describe the repeat-rate gaps, find the highest-leverage segments, recommend specific actions for each, then provide metrics to validate. That was more valuable than a score.

Hindsight: I wish I'd recommended A/B testing earlier in the analysis. Instead of presenting 'here are 5 recommendations,' I could have scoped out a 3-month A/B test plan for the top 2 priorities and gotten buy-in for testing before the analysis ended. That would have shortened the path to validation."

---

### Q8: "How did you communicate your findings to non-technical stakeholders?"

**Strong Answer:**
"I built two versions:

1. **Business recommendation doc:** Prioritized by reach and impact with real customer numbers and observed gaps. For each recommendation, I showed: who it affected, what the current repeat rate was, what the observed gap was, and why that segment was important. No technical details, just business logic.

2. **Detailed findings doc:** For the analytics team, with right-censored rate calculations, cohort survival curves, segment breakdowns. This one included caveats about causality and data limitations.

The key was leading with the business problem (only 3% repeat rate) and tying every finding back to that. For example: 'Single-item buyers are 90% of our customer base and repeat 1.25pp less than multi-item buyers. This is the highest-reach, highest-leverage segment to move.'

I also showed counterintuitive findings explicitly — 'Low review scores don't predict churn; don't target them for retention' — because that changes what the team would test first."

---

## 10. What I'd Improve With More Time or Data

### Immediate Improvements (Same Data, More Time)

**1. Causal Validation**
- Run A/B tests on the top 2 priority recommendations (cross-sell + win-back sequence)
- Measure: does increasing basket-size visibility at checkout actually lift repeat rates?
- Current analysis shows the correlation exists in observed data, but testing would prove causality

**2. CLV Modeling**
- Build a first-order feature model to predict which new customers are likely to become high/top-CLV
- This would enable proactive retention investment before churn, rather than after (reactive)
- Current analysis only identifies high-CLV customers *after* they've already self-selected

**3. Optimal Engagement Timing**
- Map email send time and cadence (days 0, 3, 14, 25) against second-purchase conversion
- Current analysis shows 50% return within 29 days but doesn't optimize when/how often to contact
- This could lift win-back sequence effectiveness significantly

**4. Category-Specific Strategies**
- Tailor recommendations by category (replenishment vs lifestyle vs one-off)
- bed_bath_table repeats at 4.02%, electronics at 1.08% — different interventions likely needed
- Current recommendations are category-agnostic

---

### New Data That Would Change the Analysis

**1. Acquisition Channel**
- **Why:** Repeat-rate gaps could reflect customer quality (e.g., paid ads → lower intent) rather than retention performance
- **Impact:** Would change whether we optimize customer acquisition or post-purchase engagement, or both
- **Use case:** Holiday cohort is weak — is it acquisition-driven or engagement-driven?

**2. Email Engagement & Campaign History**
- **Why:** Can't currently determine if the platform is already sending win-back emails
- **Impact:** Would measure incremental value of our recommendation vs current practice
- **Use case:** If the platform already sends day-3 follow-up emails, a full 30-day sequence might have diminishing returns

**3. Clickstream & Browse Behavior**
- **Why:** Don't know if multi-item buyers actively search related products or if they're just naturally higher-intent
- **Impact:** Would refine cross-sell strategy (checkout bundle vs email recommendation vs in-app notification)
- **Use case:** If multi-item buyers browse many categories, recommendation algorithms would work well. If they go straight to checkout, bundles matter more.

**4. Inventory & Stock-Out Events**
- **Why:** Second purchase might be driven by product availability, not retention efforts
- **Impact:** Would separate legitimate churn (customer abandoned) from unavoidable churn (item out of stock)
- **Use case:** Late-delivery customers might have high lifetime value because they're buying available, popular items; not because they're loyal

**5. Seller-Level Data**
- **Why:** Repeat purchases might cluster by seller (trusted sellers build repeat customers)
- **Impact:** Would identify whether seller quality or platform mechanics drive retention
- **Use case:** Some sellers might have 5% repeat rates; others 0.5% — suggests seller service quality matters more than product recommendations

**6. Discount/Promotional Spend History**
- **Why:** Can't tell if low repeat rate is due to price-driven acquisition (cheaper customers don't return)
- **Impact:** Would inform whether discount-based retention strategies make sense
- **Use case:** Voucher payment type has 3.07% repeat (vs 3% baseline) — but is this causation or are voucher users different?

---

### Operational Improvements (Beyond Data)

**1. Establish an Analytics Feedback Loop**
- Right now, recommendations are made but I have no data on implementation or results
- **Ideal state:** Each recommendation runs as an A/B test with a defined success metric
- **Timeline:** 3-month pilot per priority, then decide scale-up or pivot

**2. Build a Real-Time Churn Monitoring Dashboard**
- Current analysis is retrospective (Sept 2016 – Aug 2018)
- **Ideal state:** Real-time repeat-rate tracking by segment (cohort, category, CLV band) so the team sees if interventions move the needle
- **Benefit:** Faster feedback loops, faster iteration

**3. Segmentation-Based Recommendation Engine**
- Current: generic recommendations for all customers
- **Ideal:** Personalized intervention based on first-order behavior (category, basket size, delivery status, etc.)
- **Example:** A customer who bought a single home-item and received late gets a targeted re-engagement campaign specific to home products. A customer who bought 6 items is enrolled in the VIP funnel.

**4. Supplier/Seller Partnership**
- Current: analysis focuses on customer behavior, not supply-side
- **Ideal:** Understand which sellers/categories drive repeat and build partnerships or incentives around them
- **Example:** If home_appliances repeat at 7.69%, partner with those sellers for exclusive/early-access programs

---

### What Success Looks Like

In 6 months:
- Repeat rate moves from 3% to 3.5–4% for treated segments
- Time-to-second-purchase decreases from median 29 days to <21 days (higher engagement)
- Holiday cohort retention closes 50% of the 0.9pp gap (1.55% → 2.0%)

In 12 months:
- Repeat rate across the platform reaches 4–5% (vs 3% baseline)
- 15–20% of new customers have multi-item first orders (vs 10% today)
- VIP segment retention reaches 8–10% (vs 6–7% natural baseline)
- Incremental annual revenue from retention interventions = R$1–2M (assuming interventions scale)

---

## Final Note

This analysis is grounded in **observed patterns and validated numbers**, not hunches or assumptions. Every recommendation is backed by a specific repeat-rate gap or revenue benchmark. The next step is hypothesis validation through testing — confirm that correlations in historical data predict treatment response in real experiments.

The business problem (3% repeat rate) is real, the opportunity (90% single-item buyers, 29-day return window) is quantified, and the path forward (ranked actions + metrics) is clear.
