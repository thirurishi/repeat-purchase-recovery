# Business Recommendations: Repeat Purchase Recovery
**Dataset:** Olist Brazilian E-commerce (Sept 2016 – Aug 2018, 23 months)
**Scope:** 93,358 customers, 96,478 delivered orders
**Status:** Complete — all findings sourced from validated SQL layers and notebooks NB02–NB05

---

## 1. Executive Summary

Only 3.0% of Olist customers placed a second order across a 23-month observation window. Of 93,358 customers, 90,557 bought exactly once and were never seen again. This is not a marginal problem — it means the platform's revenue model is almost entirely dependent on acquiring new customers rather than retaining existing ones.

The business impact is direct: customers who did repeat spent 58% more over 90 days (R$253 vs R$161 for one-time buyers). Scaling that gap across the full customer base represents a substantial and recoverable revenue gap. Because the data shows half of all eventual repeat buyers return within 29 days of their first order, the window for intervention is narrow and the need for a structured post-purchase program is clear.

This document translates the analysis findings into ranked, actionable recommendations. It does not overstate the data: all findings are observational, and recommendations are grounded in what the numbers actually show.

---

## 2. Key Findings

### 2.1 Repeat Rate Is Extremely Low Across All Windows
- **Lifetime raw repeat rate:** 3.0% (2,801 of 93,358 customers)
- **90-day right-censored repeat rate:** 2.28% (1,716 of 75,387 eligible customers)
- **60-day repeat rate:** 1.96% (1,590 of 81,265 eligible)
- **30-day repeat rate:** 1.59% (1,380 of 86,909 eligible)

These windows are right-censored, meaning customers without enough tenure are excluded to avoid understating rates. Even with this correction, rates remain well below any published e-commerce retention benchmark.

### 2.2 The Return Window Is Short and Front-Loaded
Among the 2,801 customers who did return:
- **Median days to second order:** 29 days
- **Mean days to second order:** 81.2 days (heavily right-skewed)
- **50% of repeat buyers returned within 30 days**
- **68% returned within 90 days**
- **79% returned within 180 days**

The distribution is bimodal: a cluster of fast returners (within 30 days) and a long tail. If no outreach happens in the first 30 days post-purchase, the highest-probability return window is missed.

### 2.3 Single-Item First Orders Dominate and Suppress Repeat Rates
- **84,151 customers (90.1%)** placed a single-item first order
- Repeat rate for single-item buyers: **2.15%**
- Repeat rate for 2-item buyers: **3.15%**
- Repeat rate for 3–5 item buyers: **4.10%**
- Repeat rate for 6+ item buyers: **5.38%**
- Lift from 1 item to 6+ items: **+3.23 percentage points (2.5× higher)**
- Single-item buyers generated R$154 average 90-day revenue vs R$216–707 for multi-item buyers (weighted avg ~R$257; **−R$103 gap at the 2-item tier**)

This is the strongest behavioral predictor in the dataset. The single-item first order is not just common — it is the structural bottleneck.

### 2.4 Holiday-Acquired Cohorts Retain Worst
Six-month cumulative retention rates for large cohorts (≥1,000 customers):
- **Nov 2017:** 1.57% (7,060 customers — the platform's largest cohort)
- **Dec 2017:** 1.46% (5,338 customers)
- **Jan 2018:** 1.62% (6,842 customers)

Compared to the best-performing cohorts:
- **Aug 2017:** 2.46% (4,057 customers)
- **Sep 2017:** 2.42% (4,004 customers)
- **Jun 2017:** 2.37% (3,037 customers)

The Nov–Jan period brought the platform's highest acquisition volumes but its worst retention. This cohort entered during a promotional period (Brazilian holiday season / Black Friday equivalent) and did not return at comparable rates to organic mid-year cohorts.

### 2.5 Revenue and Repeat Rates Are Concentrated in a Small Customer Segment
CLV band breakdown across 93,358 customers:
| Band | Customers | % of Total | % of Revenue | 90-day Repeat Rate |
|---|---|---|---|---|
| Low (≤R$100) | 43,246 | 46.3% | 16.9% | 0.51% |
| Mid (R$100–249) | 39,774 | 42.6% | 42.8% | 2.98% |
| High (R$250–800) | 7,994 | 8.6% | 22.1% | 7.05% |
| Top (>R$800) | 2,343 | 2.5% | 18.2% | 6.36% |

The top 11.1% of customers (High + Top bands) account for **40.3% of revenue**. They also repeat at 3× the baseline rate. These customers are not being treated differently from the rest — and the data does not show any evidence that they are being retained proactively.

### 2.6 Delayed Delivery Has a Measurable but Modest Impact
- Early delivery repeat rate (90d): **2.30%** (84,519 customers)
- On-time repeat rate: **2.19%** (1,403 customers)
- Late delivery repeat rate: **2.05%** (7,428 customers, avg 10 days late)
- Net impact of late delivery: **−0.25 percentage points**
- Late-delivery customers have **higher average lifetime revenue (R$178) vs the early-delivery group (R$164)** — they are not low-value customers

This is statistically present but small in isolation. At scale (7,428 late-delivery customers), recovering even half of this gap would add ~9 repeat buyers per cohort. The higher lifetime value of affected customers makes the recovery case stronger than the repeat rate gap alone implies.

### 2.7 Low Review Scores Do Not Predict Churn (Contrary to Intuition)
- Repeat rate for 1–2 star reviewers: **2.28%** (11,913 customers)
- Repeat rate for 4–5 star reviewers: **2.28%** (73,161 customers)
- Difference: **0.00 percentage points**
- Low scorers return *faster* on average: 62 days vs 86 days for high scorers

This finding contradicts a common assumption. Satisfaction scores alone are not a reliable churn predictor in this dataset. Using review score as the primary trigger for win-back outreach would be misdirected.

### 2.8 Category Has a Large Effect on Repeat Likelihood
Selected categories with ≥675 customers:
- **home_appliances:** 7.69% repeat rate (675 customers)
- **fashion_bags_accessories:** 4.58% (1,699 customers)
- **bed_bath_table:** 4.02% (8,798 customers) — largest high-repeat category by volume
- **electronics:** 1.08% (2,466 customers)
- **cool_stuff:** 0.92% (3,457 customers)
- **watches_gifts:** 1.59% (5,299 customers)

Categories associated with replenishment or building out a lifestyle (home, fashion accessories, bed/bath) repeat at 3–7× the rate of one-off or gift categories (electronics, watches).

### 2.9 Geographic Variation Is Present but Unexplained
States with ≥300 eligible customers and the highest/lowest 90-day repeat rates:
- **High-repeat states:** MT 3.08%, DF 2.66%, ES 2.64%
- **Low-repeat states:** CE 1.43%, MA 1.52%, SC 1.71%

The spread between best and worst is ~1.65 percentage points. Because there is no acquisition channel or demographic data in the dataset, the driver of this variation (different product mix, shipping reliability, or customer composition) cannot be determined from this analysis alone.

---

## 3. Priority Problem Areas

Ranked by business importance (revenue impact × customer reach):

**1. Single-item first orders (Reach: 90.1% of customers, Impact: −R$103 average 90-day revenue gap at the 2-item tier)**
The dominant structural problem. Nine in ten customers leave their first order with a single item. This directly limits cross-sell familiarity, reduces perceived value, and suppresses repeat rate. No other signal affects as many customers.

**2. No observable post-purchase retention mechanism (Reach: 100% of customers)**
There is no field in the Olist dataset representing email outreach, loyalty program membership, or win-back campaigns. The 29-day median return window implies the optimal intervention point exists — but there is no evidence the platform is using it.

**3. Holiday cohort weakness (Reach: ~19,000 customers Nov–Jan, Impact: ~0.9pp below summer baseline)**
The platform's three largest acquisition months produced its worst-retaining cohorts. This is likely a customer-quality issue (price-driven buyers, one-off gift purchases) compounded by the absence of holiday-specific re-engagement.

**4. CLV concentration without a visible VIP tier (Reach: 10,337 customers in High+Top, Impact: 40% of revenue)**
The customers driving the most revenue repeat at 7.05% (High) and 6.36% (Top) — but without visibility into whether any differentiated service or loyalty program exists, there is no way to know if this natural retention is being reinforced or left to chance.

**5. Late delivery impact at scale (Reach: 7,428 customers / cohort period, Impact: −0.25pp)**
Small per-customer, meaningful in aggregate. The 8% of customers with delayed deliveries are a known, addressable group.

---

## 4. Recommended Actions

### Action 1: Launch a Multi-Item Cross-Sell Program at Checkout and Post-Purchase

**Problem addressed:** Single-item first order trap (90.1% of customers, −1.25pp repeat rate vs 2-item buyers, −R$103 average 90-day revenue gap)

**Evidence from analysis:**
Customers who placed 6+ item first orders repeated at 5.38% vs 2.15% for single-item buyers — a 2.5× difference. The average days to return was also shorter (35 days vs 83 days). This is the largest behavioral gap in the dataset.

**Action recommendation:**
- At checkout: surface "Frequently bought together" or category bundles specifically for low-basket customers
- Immediately post-purchase (email/in-app): send a curated "complete your order" follow-up within 24 hours for single-item buyers in high-affinity categories (bed_bath_table, fashion_bags_accessories)
- Target category selection: focus on bed_bath_table (8,798 customers, 4.02% repeat — the best volume+rate combination) as the primary test category

**Business metric to improve:** First-order basket size (items per order); 90-day repeat rate

**Why this is realistic:** The gap between single-item and multi-item repeat rates is large and consistent. Even a partial shift — converting 5% of single-item buyers to two-item baskets — would produce measurable repeat rate improvement without requiring new customer acquisition. The step from 1 to 2 items carries the largest marginal lift (+1.0pp) and the lowest behavioural barrier.

---

### Action 2: Build a 30-Day Post-Purchase Win-Back Sequence

**Problem addressed:** Missed early return window; 97% of customers never return

**Evidence from analysis:**
50% of all eventual repeat buyers return within 29 days. The repeat rate drops sharply after that first month (monthly retention decays from 0.48% at month 1 to 0.15–0.25% by months 4–12). This is the highest-probability window in the data and there is no evidence it is being used.

**Action recommendation:**
- Day 3: delivery confirmation + review request (already happens on the platform, but can be linked to product recommendation)
- Day 14: "You might also like" email based on first-order category
- Day 25: replenishment reminder or category-matched second purchase prompt
- Day 45: final reactivation nudge for customers who haven't returned

The sequence should be differentiated by category: replenishment prompts for consumable or lifestyle categories (bed_bath_table, health_beauty), and exploration prompts for non-replenishment categories.

**Business metric to improve:** 30-day and 60-day repeat rate (currently 1.59% and 1.96%)

**Why this is realistic:** This is a standard email/CRM intervention. It does not require new product development. Given the 29-day median return window, even modest email engagement at day 14–25 lands inside the highest-probability return cluster.

---

### Action 3: Design a Holiday-Cohort Re-Engagement Campaign

**Problem addressed:** Nov–Jan cohort weakness (1.46–1.62% vs 2.37–2.46% for mid-year cohorts)

**Evidence from analysis:**
The three largest cohorts by volume (Nov 2017: 7,060 customers; Jan 2018: 6,842; Dec 2017: 5,338) had the three lowest 6-month retention rates. This is not a margin issue — it is a customer composition issue. Holiday buyers are likely gift purchasers or promotional-price buyers with lower category affinity.

**Action recommendation:**
- Segment holiday-acquired customers (Nov–Jan acquisition) into a separate re-engagement track
- In January/February (natural post-holiday lull), send a "back for yourself" campaign: shift messaging from gift framing to personal-use categories with strong repeat rates (home_appliances, fashion_bags_accessories, bed_bath_table)
- Test whether a structured onboarding sequence in the first 30 days post-holiday-acquisition lifts retention toward mid-year cohort levels
- Measure separately from organic cohorts to avoid contaminating baseline metrics

**Business metric to improve:** 90-day retention rate for Nov–Jan cohorts; gap vs mid-year cohorts (currently ~0.9pp)

**Why this is realistic:** The holiday cohort problem is well-defined and calendrically predictable. The customer segments are identifiable by acquisition date. This is a campaign that can be planned in advance each year.

---

### Action 4: Introduce a Differentiated VIP Program for High and Top CLV Customers

**Problem addressed:** Revenue concentration without observable retention investment

**Evidence from analysis:**
10,337 customers (High + Top CLV bands) generate 40.3% of all observed revenue. Their natural repeat rates are 6.36–7.05% — already 3× the baseline. However, there is no signal in the dataset of any loyalty tier, priority service, or dedicated outreach for this segment. These customers are repeating despite the platform, not because of it.

**Action recommendation:**
- Define a VIP tier using CLV bands as described (High: R$250–800, Top: >R$800) or equivalent spending thresholds
- Offer meaningful operational benefits: priority customer service response time, free freight on next order, early access to new categories
- Assign a churn early-warning rule: flag any VIP customer who has not ordered in 60 days (vs their median 12.4-day delivery window and 29-day median return), then trigger a direct outreach
- Do not use discount-only retention — there is no discount field in this dataset and price sensitivity is unmeasured

**Business metric to improve:** Retention rate among High+Top CLV bands; revenue at risk per month from that segment

**Why this is realistic:** A small reduction in churn among these 10,337 customers has outsized revenue impact due to their average order values (R$426 and R$1,197 respectively). VIP programs are operationally straightforward and the segment boundary is already defined by the CLV analysis.

---

### Action 5: Trigger a Delivery-Delay Recovery Touchpoint

**Problem addressed:** Late delivery reduces repeat rate by −0.25pp across 7,428 affected customers

**Evidence from analysis:**
Customers who received orders late (7,428 in the observation period, avg 10 days late) repeated at 2.05% vs 2.30% for early-delivery customers. The gap is modest per customer but consistent. Critically, this is a customer group the platform already knows about in real time — delayed delivery is detectable before the customer even receives the order.

**Action recommendation:**
- When a delivery is flagged as running late (carrier update past estimated delivery date), automatically trigger a proactive communication: acknowledge the delay before the customer complains, provide a revised ETA
- Follow up at delivery confirmation with a friction-reducing incentive for the next order (e.g., reduced freight, not necessarily a discount — the data does not support assuming price sensitivity is the driver)
- Track whether post-delay recovery touchpoints close the 0.25pp repeat rate gap

**Business metric to improve:** 90-day repeat rate for late-delivery customers (currently 2.05% vs 2.30% baseline)

**Why this is realistic:** The affected group is identifiable in real time from logistics data. The cost of a proactive communication is low. Late-delivery customers have higher lifetime revenue (R$178) than the average customer — they are worth retaining. The counterfactual (no outreach, customer churns silently) is the current default.

---

## 5. Suggested Priority Order

| Rank | Action | Reach | Estimated Repeat Rate Lift | Effort |
|---|---|---|---|---|
| 1 | Multi-item cross-sell program | 84,151 customers (90% of base) | +1.0–2.0pp if 10–20% convert | Medium |
| 2 | 30-day post-purchase win-back sequence | All customers | +0.3–0.5pp (30-day window) | Low–Medium |
| 3 | Holiday cohort re-engagement | ~19,000 customers/year | +0.5–0.9pp for target cohort | Low |
| 4 | VIP program for High+Top CLV | 10,337 customers | Retention of existing 7% repeaters | Medium |
| 5 | Delivery-delay recovery touchpoint | ~7,400 customers/year | +0.25pp for affected group | Low |

**Rationale for this ranking:**
Action 1 targets the structural bottleneck affecting 90% of customers and has the largest documented performance gap. Action 2 exploits the 29-day return window — a natural timing advantage that costs little to use. Actions 3 and 4 address concentrated, well-defined segments. Action 5 is operationally simple but affects a smaller population.

All five actions are independent and can run in parallel. There is no dependency between them.

---

## 6. Caveats and Data Limitations

**No acquisition channel data.** It is not possible to determine whether customers arrived via paid search, organic, referral, or promotions. This means it is impossible to separate customer quality effects (channel-driven) from platform behavior effects. Some cohort differences may reflect acquisition mix rather than platform retention performance.

**No clickstream or browsing data.** Product discovery paths, search behavior, category browsing, and cart abandonment are not in the dataset. Cross-sell and recommendation suggestions in this document are based on category repeat patterns, not observed browsing intent.

**No discount or promotion field.** There is no field indicating whether an order was placed under a promotional price, coupon, or voucher-triggered discount. The voucher payment type has a slightly higher repeat rate (3.07%), but it is not possible to determine whether that reflects voucher-driven acquisition, price-sensitive segments, or other confounders.

**Observational analysis only.** All associations in this document are correlational. The higher repeat rate among multi-item first orders does not prove that increasing basket size causes repeat purchases — it is equally possible that customers who buy multiple items have stronger underlying purchase intent. Causal inference would require a controlled experiment (A/B test). Recommendations should be treated as hypotheses to validate, not proven levers.

**Right-censoring.** Repeat rate windows (30/60/90-day) exclude customers without sufficient tenure at the end of the observation period. Lifetime rates (3.0%) include all customers but may understate the true eventual repeat rate for recently-acquired cohorts.

**Dataset scope.** The Olist dataset covers a single Brazilian marketplace from 2016–2018. Market conditions, competitive dynamics, and consumer behavior may differ meaningfully from current context or other geographies. Findings should not be extrapolated to other markets without validation.
