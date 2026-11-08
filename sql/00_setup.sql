-- Run once in the Databricks SQL editor, before the first pipeline run.
-- Free Edition gives you one catalog called `workspace`, so we create schemas inside it.
USE CATALOG workspace;

CREATE SCHEMA IF NOT EXISTS raw    COMMENT 'Landing zone: Olist CSV files from Kaggle';
CREATE SCHEMA IF NOT EXISTS bronze COMMENT 'Raw tables loaded as-is from the CSVs';
CREATE SCHEMA IF NOT EXISTS silver COMMENT 'Cleaned, typed and joined tables with data quality checks';
CREATE SCHEMA IF NOT EXISTS gold   COMMENT 'Business-ready facts and dimensions for the dashboard and Genie';

CREATE VOLUME IF NOT EXISTS raw.olist COMMENT 'One folder per Olist CSV file';
