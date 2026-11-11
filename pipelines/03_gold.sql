-- GOLD: business-ready facts and dimensions for the dashboard and Genie.

---------------------------------------------------------------- facts

CREATE OR REFRESH MATERIALIZED VIEW gold.fact_orders (
  CONSTRAINT order_id_not_null           EXPECT (order_id IS NOT NULL)           ON VIOLATION FAIL UPDATE,
  CONSTRAINT customer_id_not_null        EXPECT (customer_id IS NOT NULL)        ON VIOLATION FAIL UPDATE,
  CONSTRAINT customer_unique_id_not_null EXPECT (customer_unique_id IS NOT NULL) ON VIOLATION FAIL UPDATE,
  CONSTRAINT order_status_not_null       EXPECT (order_status IS NOT NULL)       ON VIOLATION FAIL UPDATE,
  CONSTRAINT non_negative_payment        EXPECT (total_payment_amount >= 0)      ON VIOLATION FAIL UPDATE,
  -- Warn only: keep the row, but count how many orders were "delivered" before they were placed.
  CONSTRAINT delivered_after_ordered     EXPECT (delivered_at IS NULL OR delivered_at >= ordered_at)
)
COMMENT 'One row per order (all statuses). Main fact table for revenue, delivery and customer analysis. Use order_status = ''delivered'' for revenue figures.'
AS
WITH items AS (
  SELECT
    order_id,
    count(DISTINCT order_item_id)    AS total_items,
    sum(item_price)                  AS total_items_price,
    sum(freight_price)               AS total_freight_price,
    sum(total_item_amount)           AS total_order_amount,
    count(DISTINCT product_category) AS distinct_categories
  FROM silver.int_order_items_enriched
  GROUP BY order_id
)
SELECT
  o.order_id,
  o.customer_id,
  o.customer_unique_id,
  o.customer_city,
  o.customer_state,
  o.order_status,
  o.ordered_at,
  o.approved_at,
  o.shipped_at,
  o.delivered_at,
  o.estimated_delivery_at,
  coalesce(o.total_payment_amount, 0) AS total_payment_amount,
  o.primary_payment_type,
  o.payment_count,
  o.days_to_deliver,
  o.estimated_delivery_days,
  o.delivered_on_time,
  i.total_items,
  i.total_items_price,
  i.total_freight_price,
  i.total_order_amount,
  i.distinct_categories
FROM silver.int_orders_enriched o
LEFT JOIN items i ON o.order_id = i.order_id;

CREATE OR REFRESH MATERIALIZED VIEW gold.fact_monthly_revenue (
  CONSTRAINT order_month_not_null   EXPECT (order_month IS NOT NULL)   ON VIOLATION FAIL UPDATE,
  CONSTRAINT total_revenue_not_null EXPECT (total_revenue IS NOT NULL) ON VIOLATION FAIL UPDATE,
  CONSTRAINT total_orders_not_null  EXPECT (total_orders IS NOT NULL)  ON VIOLATION FAIL UPDATE
)
COMMENT 'Delivered-order revenue per month, customer state and primary payment type, with month-over-month growth.'
AS
WITH with_prev AS (
  SELECT
    *,
    -- FIX: the dbt model partitioned lag() by state only, but there is one row per
    -- state + month + payment type, so "previous row" was often another payment type
    -- in the same month. Also only treat it as growth if the previous row is the previous calendar month.
    CASE
      WHEN lag(order_month) OVER w = add_months(order_month, -1)
      THEN lag(total_revenue) OVER w
    END AS prev_month_revenue
  FROM silver.int_monthly_orders
  WINDOW w AS (PARTITION BY customer_state, primary_payment_type ORDER BY order_month)
)
SELECT
  order_month,
  customer_state,
  primary_payment_type,
  total_orders,
  unique_customers,
  coalesce(total_revenue, 0) AS total_revenue,
  avg_order_value,
  avg_delivery_days,
  orders_on_time,
  orders_late,
  prev_month_revenue,
  total_revenue - prev_month_revenue                                           AS revenue_growth,
  round((total_revenue - prev_month_revenue) / nullif(prev_month_revenue, 0) * 100, 2) AS revenue_growth_pct
FROM with_prev;

CREATE OR REFRESH MATERIALIZED VIEW gold.fact_order_items (
  CONSTRAINT order_id_not_null      EXPECT (order_id IS NOT NULL)      ON VIOLATION FAIL UPDATE,
  CONSTRAINT order_item_id_not_null EXPECT (order_item_id IS NOT NULL) ON VIOLATION FAIL UPDATE,
  CONSTRAINT product_id_not_null    EXPECT (product_id IS NOT NULL)    ON VIOLATION FAIL UPDATE,
  -- Fails if an item has no matching order (the LEFT JOIN would leave status empty).
  CONSTRAINT order_status_not_null  EXPECT (order_status IS NOT NULL)  ON VIOLATION FAIL UPDATE
)
COMMENT 'One row per order item (order_id + order_item_id), with product category, seller, and the order''s status, date and customer. Use for any product, category or seller question. Item revenue is item_price (excludes freight); filter order_status = ''delivered'' for delivered revenue. Count orders with count(DISTINCT order_id), not rows. Added after Genie answered a category question from dim_products, which mixes all order statuses.'
AS SELECT
  i.order_id,
  i.order_item_id,
  i.product_id,
  i.product_category,
  i.seller_id,
  i.seller_city,
  i.seller_state,
  o.customer_unique_id,
  o.customer_state,
  o.order_status,
  o.ordered_at,
  CAST(date_trunc('MONTH', o.ordered_at) AS DATE) AS order_month,
  i.item_price,
  i.freight_price,
  i.total_item_amount
FROM silver.int_order_items_enriched i
LEFT JOIN silver.int_orders_enriched o ON i.order_id = o.order_id;

---------------------------------------------------------------- dimensions

CREATE OR REFRESH MATERIALIZED VIEW gold.dim_customers (
  CONSTRAINT customer_unique_id_not_null EXPECT (customer_unique_id IS NOT NULL) ON VIOLATION FAIL UPDATE
)
COMMENT 'One row per real customer (customer_unique_id). FIX: the dbt model had one row per customer_id, which Olist creates fresh for every order, so every customer looked like a one-time buyer by design.'
AS
WITH all_orders AS (
  -- Every person, with their location as of their most recent order
  SELECT
    customer_unique_id,
    count(DISTINCT customer_id)        AS customer_id_count,
    max_by(customer_city,  ordered_at) AS customer_city,
    max_by(customer_state, ordered_at) AS customer_state,
    max_by(zip_code,       ordered_at) AS zip_code
  FROM silver.int_orders_enriched
  GROUP BY customer_unique_id
),
delivered AS (
  -- Purchase history counts delivered orders only
  SELECT
    customer_unique_id,
    min(ordered_at)           AS first_order_at,
    max(ordered_at)           AS most_recent_order_at,
    count(DISTINCT order_id)  AS total_orders,
    sum(total_payment_amount) AS lifetime_value,
    avg(total_payment_amount) AS avg_order_value
  FROM silver.int_orders_enriched
  WHERE order_status = 'delivered'
  GROUP BY customer_unique_id
),
data_end AS (
  SELECT CAST(max(ordered_at) AS DATE) AS last_data_date
  FROM silver.int_orders_enriched
)
SELECT
  a.customer_unique_id,
  a.customer_city,
  a.customer_state,
  a.zip_code,
  a.customer_id_count,
  d.first_order_at,
  d.most_recent_order_at,
  coalesce(d.total_orders, 0)   AS total_orders,
  coalesce(d.lifetime_value, 0) AS lifetime_value,
  d.avg_order_value,
  CASE
    WHEN d.total_orders >= 5 THEN 'vip'
    WHEN d.total_orders >= 2 THEN 'repeat'
    WHEN d.total_orders = 1  THEN 'one_time'
    ELSE 'no_orders'
  END AS customer_segment,
  -- FIX: was measured from today (~2,900 days for everyone); now from the last date in the data.
  datediff(e.last_data_date, CAST(d.most_recent_order_at AS DATE)) AS days_since_last_order
FROM all_orders a
LEFT JOIN delivered d ON a.customer_unique_id = d.customer_unique_id
CROSS JOIN data_end e;

CREATE OR REFRESH MATERIALIZED VIEW gold.dim_products (
  CONSTRAINT product_id_not_null EXPECT (product_id IS NOT NULL) ON VIOLATION FAIL UPDATE
)
COMMENT 'One row per product, with product attributes and sales totals from all order items of ANY status (including canceled). Use for product attributes; for revenue or orders by category, use fact_order_items filtered to delivered orders. Category names are in Portuguese.'
AS
WITH sales AS (
  SELECT
    product_id,
    count(DISTINCT order_id) AS times_ordered,
    sum(item_price)          AS total_revenue,
    avg(item_price)          AS avg_selling_price,
    avg(freight_price)       AS avg_freight_price
  FROM silver.int_order_items_enriched
  GROUP BY product_id
)
SELECT
  p.product_id,
  p.product_category,
  p.weight_grams,
  p.length_cm,
  p.height_cm,
  p.width_cm,
  coalesce(s.times_ordered, 0)     AS times_ordered,
  coalesce(s.total_revenue, 0)     AS total_revenue,
  coalesce(s.avg_selling_price, 0) AS avg_selling_price,
  coalesce(s.avg_freight_price, 0) AS avg_freight_price
FROM silver.stg_products p
LEFT JOIN sales s ON p.product_id = s.product_id;

---------------------------------------------------------------- uniqueness check

CREATE OR REFRESH MATERIALIZED VIEW gold.dq_primary_keys (
  CONSTRAINT no_duplicate_keys EXPECT (duplicate_keys = 0) ON VIOLATION FAIL UPDATE
)
COMMENT 'Data quality check: each gold table has one row per primary key. The run fails if any key is duplicated.'
AS
          SELECT 'fact_orders'   AS table_name, count(*) - count(DISTINCT order_id)           AS duplicate_keys FROM gold.fact_orders
UNION ALL SELECT 'fact_order_items',            count(*) - count(DISTINCT order_id, order_item_id)              FROM gold.fact_order_items
UNION ALL SELECT 'dim_customers',               count(*) - count(DISTINCT customer_unique_id)                   FROM gold.dim_customers
UNION ALL SELECT 'dim_products',                count(*) - count(DISTINCT product_id)                           FROM gold.dim_products;
