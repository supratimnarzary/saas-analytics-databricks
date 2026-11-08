-- SILVER: clean, type and join the bronze tables.
-- Expectations replace the dbt tests:
--   ON VIOLATION FAIL UPDATE = stop the run, like a failing dbt test
--   ON VIOLATION DROP ROW    = remove bad rows and count them in the pipeline UI
--   (no ON VIOLATION)        = keep the row, just record the failure (warn)

---------------------------------------------------------------- staging

CREATE OR REFRESH MATERIALIZED VIEW silver.stg_orders (
  CONSTRAINT order_id_not_null     EXPECT (order_id IS NOT NULL)     ON VIOLATION FAIL UPDATE,
  CONSTRAINT customer_id_not_null  EXPECT (customer_id IS NOT NULL)  ON VIOLATION FAIL UPDATE,
  CONSTRAINT order_status_not_null EXPECT (order_status IS NOT NULL) ON VIOLATION FAIL UPDATE,
  CONSTRAINT valid_order_status    EXPECT (order_status IN ('delivered', 'shipped', 'canceled', 'unavailable',
                                                           'invoiced', 'processing', 'created', 'approved'))
                                   ON VIOLATION FAIL UPDATE
)
COMMENT 'One row per order, with typed timestamps.'
AS SELECT
  order_id,
  customer_id,
  lower(order_status)                             AS order_status,
  CAST(order_purchase_timestamp      AS TIMESTAMP) AS ordered_at,
  CAST(order_approved_at             AS TIMESTAMP) AS approved_at,
  CAST(order_delivered_carrier_date  AS TIMESTAMP) AS shipped_at,
  CAST(order_delivered_customer_date AS TIMESTAMP) AS delivered_at,
  CAST(order_estimated_delivery_date AS TIMESTAMP) AS estimated_delivery_at
FROM bronze.orders;

CREATE OR REFRESH MATERIALIZED VIEW silver.stg_customers (
  CONSTRAINT customer_id_not_null        EXPECT (customer_id IS NOT NULL)        ON VIOLATION FAIL UPDATE,
  CONSTRAINT customer_unique_id_not_null EXPECT (customer_unique_id IS NOT NULL) ON VIOLATION FAIL UPDATE
)
COMMENT 'One row per customer_id. customer_id is a new ID for every order; the real person is customer_unique_id.'
AS SELECT
  customer_id,
  customer_unique_id,
  lower(customer_city)     AS customer_city,
  upper(customer_state)    AS customer_state,
  customer_zip_code_prefix AS zip_code
FROM bronze.customers;

CREATE OR REFRESH MATERIALIZED VIEW silver.stg_order_items (
  CONSTRAINT order_id_not_null   EXPECT (order_id IS NOT NULL)   ON VIOLATION FAIL UPDATE,
  CONSTRAINT product_id_not_null EXPECT (product_id IS NOT NULL) ON VIOLATION FAIL UPDATE,
  CONSTRAINT item_price_not_null EXPECT (item_price IS NOT NULL) ON VIOLATION FAIL UPDATE
)
COMMENT 'One row per item in an order. Money columns are DECIMAL to avoid floating-point rounding.'
AS SELECT
  order_id,
  CAST(order_item_id AS INT)             AS order_item_id,
  product_id,
  seller_id,
  CAST(shipping_limit_date AS TIMESTAMP) AS shipping_limit_at,
  CAST(price AS DECIMAL(10, 2))          AS item_price,
  CAST(freight_value AS DECIMAL(10, 2))  AS freight_price
FROM bronze.order_items;

CREATE OR REFRESH MATERIALIZED VIEW silver.stg_order_payments (
  CONSTRAINT order_id_not_null       EXPECT (order_id IS NOT NULL)       ON VIOLATION FAIL UPDATE,
  CONSTRAINT payment_amount_not_null EXPECT (payment_amount IS NOT NULL) ON VIOLATION FAIL UPDATE,
  CONSTRAINT positive_payment        EXPECT (payment_amount > 0)         ON VIOLATION DROP ROW
)
COMMENT 'One row per payment record. Zero-value payments are dropped (the dbt model filtered them out too).'
AS SELECT
  order_id,
  CAST(payment_sequential AS INT)       AS payment_sequential,
  lower(payment_type)                   AS payment_type,
  CAST(payment_installments AS INT)     AS payment_installments,
  CAST(payment_value AS DECIMAL(10, 2)) AS payment_amount
FROM bronze.order_payments;

CREATE OR REFRESH MATERIALIZED VIEW silver.stg_products (
  CONSTRAINT product_id_not_null EXPECT (product_id IS NOT NULL) ON VIOLATION FAIL UPDATE
)
COMMENT 'One row per product. Category names are in Portuguese.'
AS SELECT
  product_id,
  lower(product_category_name)   AS product_category,
  CAST(product_weight_g  AS INT) AS weight_grams,
  CAST(product_length_cm AS INT) AS length_cm,
  CAST(product_height_cm AS INT) AS height_cm,
  CAST(product_width_cm  AS INT) AS width_cm
FROM bronze.products;

CREATE OR REFRESH MATERIALIZED VIEW silver.stg_sellers (
  CONSTRAINT seller_id_not_null EXPECT (seller_id IS NOT NULL) ON VIOLATION FAIL UPDATE
)
COMMENT 'One row per seller.'
AS SELECT
  seller_id,
  lower(seller_city)     AS seller_city,
  upper(seller_state)    AS seller_state,
  seller_zip_code_prefix AS zip_code
FROM bronze.sellers;

---------------------------------------------------------------- uniqueness check (replaces dbt `unique` tests)

CREATE OR REFRESH MATERIALIZED VIEW silver.dq_primary_keys (
  CONSTRAINT no_duplicate_keys EXPECT (duplicate_keys = 0) ON VIOLATION FAIL UPDATE
)
COMMENT 'Data quality check: each table has one row per primary key. The run fails if any key is duplicated.'
AS
          SELECT 'stg_orders'      AS table_name, count(*) - count(DISTINCT order_id)                 AS duplicate_keys FROM silver.stg_orders
UNION ALL SELECT 'stg_customers',                 count(*) - count(DISTINCT customer_id)                               FROM silver.stg_customers
UNION ALL SELECT 'stg_products',                  count(*) - count(DISTINCT product_id)                                FROM silver.stg_products
UNION ALL SELECT 'stg_sellers',                   count(*) - count(DISTINCT seller_id)                                 FROM silver.stg_sellers
UNION ALL SELECT 'stg_order_items',               count(*) - count(DISTINCT order_id, order_item_id)                   FROM silver.stg_order_items;

---------------------------------------------------------------- intermediate

CREATE OR REFRESH MATERIALIZED VIEW silver.int_orders_enriched
COMMENT 'One row per order, with the customer (incl. customer_unique_id) and payment totals attached.'
AS
WITH payments AS (
  SELECT
    order_id,
    sum(payment_amount)                  AS total_payment_amount,
    count(*)                             AS payment_count,
    -- FIX: was max(payment_type), which picks the alphabetically last type.
    -- max_by picks the type that paid the largest amount.
    max_by(payment_type, payment_amount) AS primary_payment_type
  FROM silver.stg_order_payments
  GROUP BY order_id
)
SELECT
  o.order_id,
  o.customer_id,
  c.customer_unique_id,
  c.customer_city,
  c.customer_state,
  c.zip_code,
  o.order_status,
  o.ordered_at,
  o.approved_at,
  o.shipped_at,
  o.delivered_at,
  o.estimated_delivery_at,
  p.total_payment_amount,
  p.payment_count,
  p.primary_payment_type,

  -- Compare dates, not timestamps, to match Snowflake's datediff('day', ...) (counts calendar days).
  datediff(CAST(o.delivered_at AS DATE),          CAST(o.ordered_at AS DATE)) AS days_to_deliver,
  datediff(CAST(o.estimated_delivery_at AS DATE), CAST(o.ordered_at AS DATE)) AS estimated_delivery_days,

  -- FIX: was false when delivered_at is missing (counted as late), and compared a delivery
  -- timestamp to an estimate stored at midnight (same-day deliveries counted as late).
  CASE
    WHEN o.delivered_at IS NULL OR o.estimated_delivery_at IS NULL THEN NULL
    WHEN CAST(o.delivered_at AS DATE) <= CAST(o.estimated_delivery_at AS DATE) THEN true
    ELSE false
  END AS delivered_on_time

FROM silver.stg_orders o
LEFT JOIN silver.stg_customers c ON o.customer_id = c.customer_id
LEFT JOIN payments p             ON o.order_id    = p.order_id;

CREATE OR REFRESH MATERIALIZED VIEW silver.int_order_items_enriched
COMMENT 'One row per order item, with product category and seller location attached.'
AS SELECT
  oi.order_id,
  oi.order_item_id,
  oi.product_id,
  oi.seller_id,
  oi.item_price,
  oi.freight_price,
  oi.item_price + oi.freight_price AS total_item_amount,
  oi.shipping_limit_at,
  p.product_category,
  p.weight_grams,
  s.seller_city,
  s.seller_state
FROM silver.stg_order_items oi
LEFT JOIN silver.stg_products p ON oi.product_id = p.product_id
LEFT JOIN silver.stg_sellers  s ON oi.seller_id  = s.seller_id;

CREATE OR REFRESH MATERIALIZED VIEW silver.int_monthly_orders
COMMENT 'Delivered orders per month, customer state and primary payment type.'
AS SELECT
  CAST(date_trunc('MONTH', ordered_at) AS DATE) AS order_month,
  customer_state,
  primary_payment_type,
  count(DISTINCT order_id)           AS total_orders,
  count(DISTINCT customer_unique_id) AS unique_customers,
  sum(total_payment_amount)          AS total_revenue,
  avg(total_payment_amount)          AS avg_order_value,
  avg(days_to_deliver)               AS avg_delivery_days,
  count_if(delivered_on_time)        AS orders_on_time,
  count_if(NOT delivered_on_time)    AS orders_late
FROM silver.int_orders_enriched
WHERE order_status = 'delivered'
GROUP BY 1, 2, 3;
