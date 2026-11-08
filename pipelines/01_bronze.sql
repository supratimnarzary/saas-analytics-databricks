-- BRONZE: load each CSV as-is, plus two audit columns.
-- Streaming tables remember which files they've already read, so a rerun loads only new files.

CREATE OR REFRESH STREAMING TABLE bronze.orders
COMMENT 'Raw Olist orders. One row per order.'
AS SELECT *, _metadata.file_name AS _source_file, current_timestamp() AS _ingested_at
FROM STREAM read_files('/Volumes/workspace/raw/olist/orders/', format => 'csv', header => true);

CREATE OR REFRESH STREAMING TABLE bronze.customers
COMMENT 'Raw Olist customers. One row per customer_id, which is a new ID for every order, not per person.'
AS SELECT *, _metadata.file_name AS _source_file, current_timestamp() AS _ingested_at
FROM STREAM read_files('/Volumes/workspace/raw/olist/customers/', format => 'csv', header => true,
  schemaHints => 'customer_zip_code_prefix STRING');

CREATE OR REFRESH STREAMING TABLE bronze.order_items
COMMENT 'Raw Olist order items. One row per item in an order.'
AS SELECT *, _metadata.file_name AS _source_file, current_timestamp() AS _ingested_at
FROM STREAM read_files('/Volumes/workspace/raw/olist/order_items/', format => 'csv', header => true);

CREATE OR REFRESH STREAMING TABLE bronze.order_payments
COMMENT 'Raw Olist payments. One row per payment record; an order can have several.'
AS SELECT *, _metadata.file_name AS _source_file, current_timestamp() AS _ingested_at
FROM STREAM read_files('/Volumes/workspace/raw/olist/order_payments/', format => 'csv', header => true);

CREATE OR REFRESH STREAMING TABLE bronze.products
COMMENT 'Raw Olist products. Category names are in Portuguese.'
AS SELECT *, _metadata.file_name AS _source_file, current_timestamp() AS _ingested_at
FROM STREAM read_files('/Volumes/workspace/raw/olist/products/', format => 'csv', header => true);

CREATE OR REFRESH STREAMING TABLE bronze.sellers
COMMENT 'Raw Olist sellers. One row per seller.'
AS SELECT *, _metadata.file_name AS _source_file, current_timestamp() AS _ingested_at
FROM STREAM read_files('/Volumes/workspace/raw/olist/sellers/', format => 'csv', header => true,
  schemaHints => 'seller_zip_code_prefix STRING');
