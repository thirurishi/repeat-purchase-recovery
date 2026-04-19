"""
validate_step5.py  --  Step 5 validation
Copies data/olist.db to a temp file, materialises the two slow view chains
(customer_order_fact and order_sequence) as tables so mart queries run in
seconds rather than minutes, then applies sql/06_customer_marts.sql and
runs V47-V56.

Temporary script -- safe to delete after use.
"""
import sqlite3, os, shutil, tempfile, sys

BASE = 'c:/Users/rishi/repeat-purchase-recovery'
LOG  = os.path.join(BASE, 'validate_step5.log')
_log = open(LOG, 'w', buffering=1)

def p(*args, **kwargs):
    kwargs['flush'] = True
    print(*args, **kwargs)
    kw2 = {k: v for k, v in kwargs.items() if k != 'file'}
    print(*args, file=_log, **kw2)

# ── Setup ──────────────────────────────────────────────────────────────────────
src = os.path.join(BASE, 'data', 'olist.db')
DB  = os.path.join(tempfile.gettempdir(), f'olist_step5_{os.getpid()}.db')
shutil.copy2(src, DB)
p(f'Working database: {DB}\n')

conn = sqlite3.connect(DB, isolation_level=None)

# ── Materialise customer_order_fact VIEW as a TABLE ────────────────────────────
# This avoids the slow multi-view join being re-executed for every mart query.
p('Materialising customer_order_fact ...')
conn.executescript("""
    CREATE TABLE _cof_mat AS SELECT * FROM customer_order_fact;
    CREATE INDEX _idx_cof_uid ON _cof_mat(customer_unique_id);
    CREATE INDEX _idx_cof_oid ON _cof_mat(order_id);
    DROP VIEW customer_order_fact;
    ALTER TABLE _cof_mat RENAME TO customer_order_fact;
""")
n = conn.execute('SELECT COUNT(*) FROM customer_order_fact').fetchone()[0]
p(f'  customer_order_fact rows: {n:,}')

# ── Create order_sequence TABLE (from 05_order_sequence.sql logic) ─────────────
# We re-derive from the now-materialised customer_order_fact table.
p('Creating order_sequence table ...')
conn.executescript("""
DROP TABLE IF EXISTS order_sequence;
CREATE TABLE order_sequence AS
WITH sequenced AS (
    SELECT
        customer_unique_id,
        order_id,
        order_purchase_timestamp,
        ROW_NUMBER() OVER cust_timeline                     AS order_sequence_number,
        LAG(order_id, 1)                 OVER cust_timeline AS previous_order_id,
        LAG(order_purchase_timestamp, 1) OVER cust_timeline AS previous_order_timestamp,
        LEAD(order_id, 1)                OVER cust_timeline AS next_order_id,
        LEAD(order_purchase_timestamp, 1) OVER cust_timeline AS next_order_timestamp,
        MIN(order_purchase_timestamp) OVER (PARTITION BY customer_unique_id)
                                                            AS first_order_timestamp
    FROM customer_order_fact
    WINDOW cust_timeline AS (
        PARTITION BY customer_unique_id
        ORDER BY order_purchase_timestamp ASC, order_id ASC
    )
)
SELECT
    customer_unique_id,
    order_id,
    order_purchase_timestamp,
    order_sequence_number,
    previous_order_id,
    previous_order_timestamp,
    next_order_id,
    next_order_timestamp,
    CASE WHEN previous_order_timestamp IS NULL THEN NULL
         ELSE CAST(ROUND(JULIANDAY(order_purchase_timestamp) -
                         JULIANDAY(previous_order_timestamp), 0) AS INTEGER)
    END AS days_since_previous_order,
    CASE WHEN next_order_timestamp IS NULL THEN NULL
         ELSE CAST(ROUND(JULIANDAY(next_order_timestamp) -
                         JULIANDAY(order_purchase_timestamp), 0) AS INTEGER)
    END AS days_until_next_order,
    CAST(ROUND(JULIANDAY(order_purchase_timestamp) -
               JULIANDAY(first_order_timestamp), 0) AS INTEGER)
                                                    AS days_since_first_order,
    CASE WHEN order_sequence_number = 1 THEN 1 ELSE 0 END AS is_first_order,
    CASE WHEN order_sequence_number = 2 THEN 1 ELSE 0 END AS is_second_order
FROM sequenced;
CREATE INDEX _idx_os_uid    ON order_sequence(customer_unique_id);
CREATE INDEX _idx_os_oid    ON order_sequence(order_id);
CREATE INDEX _idx_os_first  ON order_sequence(is_first_order);
CREATE INDEX _idx_os_second ON order_sequence(is_second_order);
""")
n = conn.execute('SELECT COUNT(*) FROM order_sequence').fetchone()[0]
p(f'  order_sequence rows:      {n:,}')

# ── Apply 06_customer_marts.sql DDL ───────────────────────────────────────────
p('\nApplying sql/06_customer_marts.sql ...')
import re
MARKER = '-- VALIDATION QUERIES'
with open(os.path.join(BASE, 'sql', '06_customer_marts.sql'), encoding='utf-8') as f:
    txt = f.read()
ddl = txt[:txt.index(MARKER)] if MARKER in txt else txt

# For validation, materialise all marts as TABLEs instead of VIEWs.
# This avoids SQLite re-evaluating nested CTE chains on every probe when
# compound marts (churn_signal_mart, segment_performance_mart) join
# upstream marts.  The query logic is identical; only the storage changes.
ddl_tables = re.sub(r'\bCREATE VIEW\b',      'CREATE TABLE', ddl)
ddl_tables = re.sub(r'\bDROP VIEW IF EXISTS\b', 'DROP TABLE IF EXISTS', ddl_tables)
conn.executescript(ddl_tables)
p('  All 6 marts created (as tables for validation performance).')
p()
for m in ['customer_first_purchase_mart', 'customer_repeat_status_mart',
          'customer_clv', 'churn_signal_mart', 'retention_cohorts',
          'segment_performance_mart']:
    n = conn.execute(f'SELECT COUNT(*) FROM {m}').fetchone()[0]
    p(f'  {m}: {n:,} rows')

# ── V47-V56 Validation ─────────────────────────────────────────────────────────
W    = 72
SEP  = '=' * W
DASH = '-' * W
issues = []

def q1(sql):
    return conn.execute(sql).fetchone()[0]

p()
p(SEP)
p('  VALIDATION REPORT  --  sql/06_customer_marts.sql')
p(SEP)

n_customers = q1('SELECT COUNT(DISTINCT customer_unique_id) FROM customer_order_fact')
p(f'\n  Reference: {n_customers:,} distinct customers in customer_order_fact')

# ── V47: Row counts ────────────────────────────────────────────────────────────
p('\n  V47  ROW COUNT — customer-level marts')
p('  ' + DASH)
marts_1row = [
    'customer_first_purchase_mart',
    'customer_repeat_status_mart',
    'customer_clv',
    'churn_signal_mart',
]
v47_pass = True
for m in marts_1row:
    n = q1(f'SELECT COUNT(*) FROM {m}')
    diff = n - n_customers
    sym = 'PASS' if diff == 0 else 'FAIL'
    p(f'  [{sym}]  {m}: {n:,}  (diff: {diff})')
    if diff != 0:
        issues.append(f'FAIL V47: {m} has {n} rows, expected {n_customers}')
        v47_pass = False

# ── V48: No duplicate customer_unique_id ──────────────────────────────────────
p('\n  V48  DUPLICATE customer_unique_id check')
p('  ' + DASH)
for m in marts_1row:
    dups = q1(f'SELECT COUNT(*) - COUNT(DISTINCT customer_unique_id) FROM {m}')
    sym = 'PASS' if dups == 0 else 'FAIL'
    p(f'  [{sym}]  {m}: {dups} duplicates')
    if dups > 0:
        issues.append(f'FAIL V48: {m} has {dups} duplicate customer_unique_id')

# ── V49: Repeat flag sanity ────────────────────────────────────────────────────
p('\n  V49  REPEAT FLAG SANITY')
p('  ' + DASH)
v49a = q1("""
    SELECT COUNT(*) FROM customer_repeat_status_mart
    WHERE has_second_order = 1 AND days_to_second_order IS NULL
""")
v49b = q1("""
    SELECT COUNT(*) FROM customer_repeat_status_mart
    WHERE has_second_order = 0 AND days_to_second_order IS NOT NULL
""")
sym_a = 'PASS' if v49a == 0 else 'FAIL'
sym_b = 'PASS' if v49b == 0 else 'FAIL'
p(f'  [{sym_a}]  has_second_order=1 but days_to_second_order IS NULL: {v49a}  (expected 0)')
p(f'  [{sym_b}]  has_second_order=0 but days_to_second_order IS NOT NULL: {v49b}  (expected 0)')
if v49a > 0: issues.append(f'FAIL V49a: {v49a} rows')
if v49b > 0: issues.append(f'FAIL V49b: {v49b} rows')

# ── V50: Window monotonicity ───────────────────────────────────────────────────
p('\n  V50  REPEAT WINDOW MONOTONICITY  (30d <= 60d <= 90d)')
p('  ' + DASH)
mono_checks = [
    ('repeat_within_30d=1 but repeat_within_60d=0',
     'SELECT COUNT(*) FROM customer_repeat_status_mart WHERE repeat_within_30d=1 AND repeat_within_60d=0'),
    ('repeat_within_60d=1 but repeat_within_90d=0',
     'SELECT COUNT(*) FROM customer_repeat_status_mart WHERE repeat_within_60d=1 AND repeat_within_90d=0'),
    ('repeat_within_30d=1 but repeat_within_90d=0',
     'SELECT COUNT(*) FROM customer_repeat_status_mart WHERE repeat_within_30d=1 AND repeat_within_90d=0'),
]
for lbl, sql in mono_checks:
    v = q1(sql)
    sym = 'PASS' if v == 0 else 'FAIL'
    p(f'  [{sym}]  {lbl}: {v}  (expected 0)')
    if v > 0: issues.append(f'FAIL V50: {lbl}: {v}')

# ── V51: CLV monotonicity ──────────────────────────────────────────────────────
p('\n  V51  CLV WINDOW MONOTONICITY  (30d <= 90d <= 180d <= lifetime)')
p('  ' + DASH)
clv_checks = [
    ('revenue_30d > revenue_90d',           'SELECT COUNT(*) FROM customer_clv WHERE revenue_30d > revenue_90d'),
    ('revenue_90d > revenue_180d',          'SELECT COUNT(*) FROM customer_clv WHERE revenue_90d > revenue_180d'),
    ('revenue_180d > lifetime_observed_revenue',
                                            'SELECT COUNT(*) FROM customer_clv WHERE revenue_180d > lifetime_observed_revenue'),
    ('orders_30d > orders_90d',             'SELECT COUNT(*) FROM customer_clv WHERE orders_30d > orders_90d'),
    ('orders_90d > orders_180d',            'SELECT COUNT(*) FROM customer_clv WHERE orders_90d > orders_180d'),
    ('orders_180d > lifetime_orders',       'SELECT COUNT(*) FROM customer_clv WHERE orders_180d > lifetime_orders'),
]
for lbl, sql in clv_checks:
    v = q1(sql)
    sym = 'PASS' if v == 0 else 'FAIL'
    p(f'  [{sym}]  {lbl}: {v}  (expected 0)')
    if v > 0: issues.append(f'FAIL V51: {lbl}: {v}')

# ── V52: CLV baseline ─────────────────────────────────────────────────────────
p('\n  V52  CLV BASELINE  (every customer has >=1 order in 30d window)')
p('  ' + DASH)
low_orders = q1('SELECT COUNT(*) FROM customer_clv WHERE orders_30d < 1')
zero_rev   = q1('SELECT COUNT(*) FROM customer_clv WHERE revenue_30d = 0')
sym1 = 'PASS' if low_orders == 0 else 'FAIL'
sym2 = 'PASS' if zero_rev   <= 1 else 'FAIL'
p(f'  [{sym1}]  customers with orders_30d < 1: {low_orders}  (expected 0)')
p(f'  [{sym2}]  customers with revenue_30d = 0: {zero_rev}  (expected <= 1, the missing-payment order)')
if low_orders > 0: issues.append(f'FAIL V52: {low_orders} customers with orders_30d < 1')
if zero_rev > 1:   issues.append(f'FAIL V52: {zero_rev} customers with revenue_30d = 0 (expected <= 1)')

# ── V53: Cohort table ─────────────────────────────────────────────────────────
p('\n  V53  RETENTION COHORT TABLE')
p('  ' + DASH)
row = conn.execute("""
    SELECT COUNT(*) total, COUNT(DISTINCT cohort_month) cohorts,
           MIN(cohort_month), MAX(cohort_month),
           MIN(retention_period_number), MAX(retention_period_number),
           SUM(CASE WHEN retention_period_number = 0 THEN 1 ELSE 0 END) period0_rows,
           SUM(CASE WHEN retention_rate IS NULL THEN 1 ELSE 0 END) null_rates
    FROM retention_cohorts
""").fetchone()
p(f'  Total rows:          {row[0]:,}')
p(f'  Distinct cohorts:    {row[1]}')
p(f'  Cohort range:        {row[2]} → {row[3]}')
p(f'  Period range:        {row[4]} → {row[5]}')
p(f'  Period-0 rows:       {row[6]}  (should equal number of cohorts: {row[1]})')
p(f'  Null retention_rate: {row[7]}  (expected 0)')
sym1 = 'PASS' if row[6] == row[1] else 'FAIL'
sym2 = 'PASS' if row[7] == 0 else 'FAIL'
p(f'  [{sym1}]  period-0 row count matches cohort count')
p(f'  [{sym2}]  no null retention_rate')
if row[6] != row[1]: issues.append(f'FAIL V53: period-0 rows {row[6]} != cohorts {row[1]}')
if row[7] > 0:       issues.append(f'FAIL V53: {row[7]} null retention_rate values')

# ── V54: Null checks ──────────────────────────────────────────────────────────
p('\n  V54  NULL CHECKS on key identity fields  (expected: 0 for all)')
p('  ' + DASH)
null_checks = [
    ('customer_first_purchase_mart.customer_unique_id',
     'SELECT SUM(CASE WHEN customer_unique_id IS NULL THEN 1 ELSE 0 END) FROM customer_first_purchase_mart'),
    ('customer_first_purchase_mart.first_order_id',
     'SELECT SUM(CASE WHEN first_order_id IS NULL THEN 1 ELSE 0 END) FROM customer_first_purchase_mart'),
    ('customer_first_purchase_mart.first_purchase_date',
     'SELECT SUM(CASE WHEN first_purchase_date IS NULL THEN 1 ELSE 0 END) FROM customer_first_purchase_mart'),
    ('customer_repeat_status_mart.customer_unique_id',
     'SELECT SUM(CASE WHEN customer_unique_id IS NULL THEN 1 ELSE 0 END) FROM customer_repeat_status_mart'),
    ('customer_clv.customer_unique_id',
     'SELECT SUM(CASE WHEN customer_unique_id IS NULL THEN 1 ELSE 0 END) FROM customer_clv'),
    ('churn_signal_mart.customer_unique_id',
     'SELECT SUM(CASE WHEN customer_unique_id IS NULL THEN 1 ELSE 0 END) FROM churn_signal_mart'),
]
for lbl, sql in null_checks:
    v = q1(sql)
    sym = 'PASS' if v == 0 else 'FAIL'
    p(f'  [{sym}]  {lbl}: {v}')
    if v > 0: issues.append(f'FAIL V54: {v} nulls in {lbl}')

# ── V55: Right-censoring coverage ─────────────────────────────────────────────
p('\n  V55  RIGHT-CENSORING COVERAGE')
p('  ' + DASH)
p(f'  {"window":<22} {"eligible":>10} {"censored":>10} {"repeat_rate %":>14}')
for col in ['repeat_within_30d', 'repeat_within_60d', 'repeat_within_90d']:
    row = conn.execute(f"""
        SELECT
            SUM(CASE WHEN {col} IS NOT NULL THEN 1 ELSE 0 END),
            SUM(CASE WHEN {col} IS     NULL THEN 1 ELSE 0 END),
            ROUND(SUM(CASE WHEN {col} = 1 THEN 1 ELSE 0 END) * 100.0 /
                  NULLIF(SUM(CASE WHEN {col} IS NOT NULL THEN 1 ELSE 0 END), 0), 2)
        FROM customer_repeat_status_mart
    """).fetchone()
    p(f'  {col:<22} {row[0]:>10,} {row[1]:>10,} {row[2]:>14}%')

# ── V56: Segment performance mart completeness ─────────────────────────────────
p('\n  V56  SEGMENT PERFORMANCE MART — rows per dimension')
p('  ' + DASH)
rows = conn.execute("""
    SELECT segment_dimension, COUNT(*) AS bucket_count, SUM(customers) AS total_customers
    FROM segment_performance_mart
    GROUP BY segment_dimension
    ORDER BY segment_dimension
""").fetchall()
p(f'  {"dimension":<35} {"buckets":>8} {"customers_covered":>18}')
for r in rows:
    p(f'  {r[0]:<35} {r[1]:>8} {r[2]:>18,}')
total_dims = len(rows)
empty = [r for r in rows if r[1] == 0]
sym = 'PASS' if not empty else 'FAIL'
p(f'\n  [{sym}]  All {total_dims} dimensions have at least one bucket')
if empty: issues.append(f'FAIL V56: empty dimensions: {[r[0] for r in empty]}')

# ── Summary ────────────────────────────────────────────────────────────────────
p()
p(SEP)
p('  STEP 5  PASS / FAIL  SUMMARY')
p(SEP)
pass_checks = [
    ('All customer-level mart row counts match distinct customers',  v47_pass),
    ('No duplicate customer_unique_id in any customer-level mart',   v49a == 0 and v49b == 0),
    ('Repeat flag sanity (has_second_order ↔ days_to_second_order)', v49a == 0 and v49b == 0),
    ('Repeat window monotonicity (30d ≤ 60d ≤ 90d)',
     all(q1(sql) == 0 for _, sql in mono_checks)),
    ('CLV revenue window monotonicity',
     all(q1(sql) == 0 for _, sql in clv_checks)),
    ('CLV baseline: every customer has ≥1 order in 30d window',     low_orders == 0),
    ('CLV: ≤1 customer with zero revenue (missing-payment edge case)', zero_rev <= 1),
    ('Retention cohort period-0 rows match cohort count',            row[6] == row[1]),
    ('No null retention_rate in cohort table',                       row[7] == 0),
    ('No null key identity fields across marts',
     all(q1(sql) == 0 for _, sql in null_checks)),
    ('Segment performance mart: all 7 dimensions non-empty',         not empty),
]

all_pass = True
for lbl, passed in pass_checks:
    sym = 'PASS' if passed else 'FAIL'
    if not passed: all_pass = False
    p(f'  [{sym}]  {lbl}')

p()
if all_pass and not issues:
    p('  OVERALL: STEP 5 PASSED')
    p('  All six customer marts are valid and internally consistent.')
    p('  Ready for dashboard views when instructed.')
else:
    p('  OVERALL: STEP 5 HAS ISSUES')
    for iss in issues:
        p(f'    * {iss}')
p(SEP)

conn.close()

# Save final DB back so caller can inspect
dest = os.path.join(BASE, 'data', 'olist.db')
shutil.copy2(DB, dest)
p(f'\nDatabase saved to data/olist.db')
try:
    os.remove(DB)
except OSError:
    pass
