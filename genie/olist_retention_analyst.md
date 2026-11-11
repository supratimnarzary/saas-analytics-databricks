# Genie agent: Olist Retention Analyst

Text2SQL agent on the gold tables, built with AI/BI Genie on Databricks Free Edition.

**Tables:** workspace.gold.fact_orders, fact_monthly_revenue, dim_customers, dim_products
**Warehouse:** Serverless Starter Warehouse
**Description:** Ask questions about Olist customers, orders, revenue and delivery. Amounts are in Brazilian reais (R$). Data covers 2016–2018.

## General instructions
```
[paste the instruction text from Step 1]
```

## Trusted SQL queries
[paste the 4 question titles and SQL blocks from Step 2]

## Sample questions
[paste the 4 questions from Step 3]

## Evaluation log

### Baseline: no instructions, table comments only (2026-11-11)
| Question | Expected | Genie | Result |
|---|---|---|---|
| Customers with more than one delivered order | 2,801 | 2,801 | Pass |
| % of buyers who are repeat customers | 3.0% | 3.0% | Pass |
| Revenue from delivered orders | R$15,422,462 | $15,422,461.77 | Number right, currency wrong |
| % of delivered orders on time | 93.2% | 93.2% | Pass |

**What worked:** the Unity Catalog table comments in pipelines/03_gold.sql were enough for correct SQL with no setup.
**What failed:** the data has no currency column, so Genie assumed USD. Fixed with a currency rule in the general instructions.
