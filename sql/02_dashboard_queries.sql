-- Datasets for the "Olist Retention & Revenue" AI/BI dashboard.
-- Each query below is pasted into the dashboard's Data tab as one dataset.

-- Dataset: kpis  (one row, feeds the 4 counter tiles)
SELECT
  (SELECT count(*)
     FROM workspace.gold.dim_customers
    WHERE total_orders > 0)                                        AS customers,
  (SELECT round(100 * count_if(total_orders >= 2) / count(*), 1)
     FROM workspace.gold.dim_customers
    WHERE total_orders > 0)                                        AS repeat_rate_pct,
  (SELECT sum(total_payment_amount)
     FROM workspace.gold.fact_orders
    WHERE order_status = 'delivered')                              AS revenue,
  (SELECT round(100 * count_if(delivered_on_time) / count(delivered_on_time), 1)
     FROM workspace.gold.fact_orders
    WHERE order_status = 'delivered')                              AS on_time_pct;

-- Dataset: monthly_revenue
-- Starts Jan 2017 and ends Aug 2018: the months before and after have only a
-- handful of delivered orders and would make the trend look like a crash.
SELECT
  order_month,
  sum(total_revenue) AS revenue,
  sum(total_orders)  AS orders
FROM workspace.gold.fact_monthly_revenue
WHERE order_month BETWEEN '2017-01-01' AND '2018-08-01'
GROUP BY order_month;

-- Dataset: revenue_by_state
SELECT
  customer_state,
  sum(total_payment_amount) AS revenue
FROM workspace.gold.fact_orders
WHERE order_status = 'delivered'
GROUP BY customer_state
ORDER BY revenue DESC
LIMIT 10;

-- Dataset: customer_segments  (customers with at least one delivered order)
SELECT
  customer_segment,
  count(*) AS customers
FROM workspace.gold.dim_customers
WHERE total_orders > 0
GROUP BY customer_segment;
