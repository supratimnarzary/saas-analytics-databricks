-- Benchmark set for the "Olist Retention Analyst" Genie agent.
-- Each question is paired with the correct (ground-truth) SQL.
-- Several are traps: the note under the question says what a wrong answer would do.

-- Q1: What share of customers bought more than once?
--     Trap: counting only the 'repeat' segment and missing 'vip'. Expected 3.0
SELECT round(100 * count_if(total_orders >= 2) / count(*), 1) AS repeat_rate_pct
FROM workspace.gold.dim_customers
WHERE total_orders > 0;

-- Q2: What is the average order value for delivered orders?
--     Expected 159.85
SELECT round(avg(total_payment_amount), 2) AS avg_order_value_brl
FROM workspace.gold.fact_orders
WHERE order_status = 'delivered';

-- Q3: Which 3 states bring in the most revenue, and what share of the total does each have?
--     Expected SP 37.4, RJ 13.3, MG 11.8
SELECT
  customer_state,
  sum(total_payment_amount) AS revenue_brl,
  round(100 * sum(total_payment_amount) / sum(sum(total_payment_amount)) OVER (), 1) AS share_pct
FROM workspace.gold.fact_orders
WHERE order_status = 'delivered'
GROUP BY customer_state
ORDER BY revenue_brl DESC
LIMIT 3;

-- Q4: How long do on-time orders take to arrive compared with late ones?
SELECT
  delivered_on_time,
  round(avg(days_to_deliver), 1) AS avg_days_to_deliver
FROM workspace.gold.fact_orders
WHERE order_status = 'delivered'
  AND delivered_on_time IS NOT NULL
GROUP BY delivered_on_time;

-- Q5: Which month had the highest revenue?
--     Trap: fact_monthly_revenue has one row per month + state + payment type,
--     so taking the single biggest row gives the wrong month.
SELECT order_month, sum(total_revenue) AS revenue_brl
FROM workspace.gold.fact_monthly_revenue
GROUP BY order_month
ORDER BY revenue_brl DESC
LIMIT 1;

-- Q6: Which 5 seller states sell the most?
--     Trap: using customer_state instead of seller_state.
SELECT seller_state, sum(item_price) AS revenue_brl
FROM workspace.gold.fact_order_items
WHERE order_status = 'delivered'
GROUP BY seller_state
ORDER BY revenue_brl DESC
LIMIT 5;

-- Q7: How many orders were canceled?
--     Trap: applying the default "delivered only" filter.
SELECT count(*) AS canceled_orders
FROM workspace.gold.fact_orders
WHERE order_status = 'canceled';

-- Q8: How did revenue in 2017 compare with 2018?
SELECT year(ordered_at) AS order_year, sum(total_payment_amount) AS revenue_brl
FROM workspace.gold.fact_orders
WHERE order_status = 'delivered'
  AND year(ordered_at) IN (2017, 2018)
GROUP BY year(ordered_at)
ORDER BY order_year;

-- Q9: Which payment method do customers use most?
SELECT primary_payment_type, count(*) AS delivered_orders
FROM workspace.gold.fact_orders
WHERE order_status = 'delivered'
GROUP BY primary_payment_type
ORDER BY delivered_orders DESC;

-- Q10: Do repeat customers spend more over their lifetime than one-time customers?
--      Trap: comparing only the 'repeat' segment and leaving out 'vip'.
SELECT
  CASE WHEN total_orders >= 2 THEN 'repeat' ELSE 'one_time' END AS customer_type,
  count(*)                       AS customers,
  round(avg(lifetime_value), 2)  AS avg_lifetime_value_brl
FROM workspace.gold.dim_customers
WHERE total_orders > 0
GROUP BY 1;
