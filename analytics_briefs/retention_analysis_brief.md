# Olist Lakehouse on Databricks: Project Brief

## What this project does

This project takes raw sales data from Olist, a Brazilian online marketplace,
and turns it into clean, reliable tables that a business can report on and ask
questions of. The data covers about 100,000 orders placed between 2016 and 2018.
Everything is built on Databricks.

---

## Steps taken in Databricks

1. **Set up storage.** Created a space for the project in Unity Catalog
   (Databricks' system for organising and securing data), with four sections:
   `raw`, `bronze`, `silver` and `gold`. Also created a *volume*, a folder for
   storing the original files.

2. **Uploaded the data.** Downloaded 6 CSV files from Kaggle (orders,
   customers, order items, payments, products and sellers) and uploaded each
   one into its own folder in the volume.

3. **Connected GitHub.** Linked this GitHub repository to Databricks, so the
   pipeline always runs the latest version of the code.

4. **Built the pipeline.** Created a Lakeflow Declarative Pipeline from three
   SQL files, one for each layer. Each file describes what a table should
   contain, and Databricks works out the order to build them in.

5. **Added data quality checks.** Wrote rules into the pipeline that check the
   data every time it runs (see below).

6. **Checked the results.** Ran the queries in `sql/01_validation.sql` to
   confirm row counts and key numbers.

---

## The three layers

The data moves through three layers. Each one makes it cleaner and more useful.

| Layer | What it does | Tables |
|-------|--------------|--------|
| **Bronze** (raw) | An exact copy of the CSV files, loaded as they are. Each row also records which file it came from and when it was loaded. Nothing is changed, so we can always go back to the original. | 6 |
| **Silver** (clean) | Fixes and joins the data: turns text into proper dates and money amounts, tidies up names, removes bad rows, and links orders to their customers, payments and products. | 10 |
| **Gold** (business-ready) | Final tables built for reporting and questions. | 5 |

**The main gold tables:**
- `fact_orders`: one row per order, with its value, payment type and delivery times
- `fact_monthly_revenue`: revenue per month, state and payment type, with growth versus the previous month
- `dim_customers`: one row per real customer, with their order count, total spend and segment (one-time, repeat or VIP)
- `dim_products`: one row per product, with how often it sold and how much it earned

---

## Data quality checks

The pipeline checks the data at every run, using three kinds of rule:

| Rule | What happens | Example |
|------|--------------|---------|
| **Stop** | The run fails, so bad data never reaches the reports | Every order must have an order ID |
| **Remove** | The bad row is dropped and counted | Payments of $0 are removed (9 rows) |
| **Flag** | The row is kept, but the problem is recorded | Orders delivered before they were placed |

Every table is also checked for duplicate IDs.

---

## What the data shows

- **97% of customers buy only once.** Of 93,358 customers who received an
  order, only 2,801 came back.
- **Three states bring in 62.5% of revenue.** São Paulo alone is 37.4%.
- **Deliveries are fast.** 93.2% arrive on time, taking 12.5 days on average
  against a promised 24.4 days.

---

## Tools used

Databricks Free Edition · Unity Catalog · Lakeflow Declarative Pipelines (SQL) · GitHub
