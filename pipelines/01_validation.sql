-- Validation checks for the olist_lakehouse pipeline.
-- Run in the SQL editor after a pipeline run. Expected values are from the 2026-11-08 run.

-- 1. Bronze row counts match the Kaggle CSVs
--    expected: orders 99,441 | customers 99,441 | order_items 112,650
--              order_payments 103,886 | products 32,951 | sellers 3,095
SELECT 'orders' AS tbl, count(*) AS row_count FROM workspace.bronze.orders
UNION ALL SELECT 'customers',      count(*) FROM workspace.bronze.customers
UNION ALL SELECT 'order_items',    count(*) FROM workspace.bronze.order_items
UNION ALL SELECT 'order_payments', count(*) FROM workspace.bronze.order_payments
UNION ALL SELECT 'products',       count(*) FROM workspace.bronze.products
UNION ALL SELECT 'sellers',        count(*) FROM workspace.bronze.sellers;

-- 2. Rows dropped by the positive_payment expectation (zero-value payments)
--    expected: 9
SELECT (SELECT count(*) FROM workspace.bronze.order_payments)
     - (SELECT count(*) FROM workspace.silver.stg_order_payments) AS dropped_zero_payments;

-- 3. Customer grain: order-level IDs vs real people
--    expected: 99,441 customer_ids, 96,096 real customers
SELECT count(DISTINCT customer_id)        AS customer_ids,
       count(DISTINCT customer_unique_id) AS real_customers
FROM workspace.silver.stg_customers;

-- 4. No duplicate primary keys in silver or gold
--    expected: every duplicate_keys value is 0
SELECT 'silver' AS layer, * FROM workspace.silver.dq_primary_keys
UNION ALL
SELECT 'gold', * FROM workspace.gold.dq_primary_keys;

-- 5. Customer segments
--    expected: one_time 90,557 | repeat 2,782 | no_orders 2,738 | vip 19
SELECT customer_segment, count(*) AS customers
FROM workspace.gold.dim_customers
GROUP BY 1 ORDER BY 2 DESC;

-- 6. Headline delivered-order numbers
--    expected: 96,478 orders | revenue 15,422,462 | AOV 159.85 | on time 93.2%
--              12.5 days to deliver vs 24.4 estimated
SELECT count(*)                                                AS delivered_orders,
       round(sum(total_payment_amount), 0)                     AS revenue,
       round(avg(total_payment_amount), 2)                     AS avg_order_value,
       round(100 * count_if(delivered_on_time) / count(delivered_on_time), 1) AS pct_on_time,
       round(avg(days_to_deliver), 1)                          AS avg_days_to_deliver,
       round(avg(estimated_delivery_days), 1)                  AS avg_days_estimated
FROM workspace.gold.fact_orders
WHERE order_status = 'delivered';

-- 7. Revenue share by state
--    expected: SP 37.4% | RJ 13.3% | MG 11.8% | RS 5.6% | PR 5.1%
SELECT customer_state,
       round(sum(total_payment_amount), 0) AS revenue,
       round(100 * sum(total_payment_amount) / sum(sum(total_payment_amount)) OVER (), 1) AS pct
FROM workspace.gold.fact_orders
WHERE order_status = 'delivered'
GROUP BY 1 ORDER BY 2 DESC LIMIT 5;

-- 8. Average lifetime value of customers with a delivered order
--    expected: 165.20
SELECT round(avg(lifetime_value), 2) AS avg_ltv
FROM workspace.gold.dim_customers
WHERE total_orders > 0;
