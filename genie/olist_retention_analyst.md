# Genie agent: Olist Retention Analyst

Text2SQL agent on the gold tables, built with AI/BI Genie on Databricks Free Edition.

- **Tables:** workspace.gold.fact_orders, fact_monthly_revenue, dim_customers, dim_products
- **Warehouse:** Serverless Starter Warehouse
- **Description:** Ask questions about Olist customers, orders, revenue and delivery. Amounts are in Brazilian reais (R$). Data covers 2016–2018.

## General instructions
```
Currency
- All money columns are Brazilian reais (BRL). Always show amounts as R$ (for example R$15,422,462). Never use $ or USD.

Business definitions
- A customer is one customer_unique_id (one row in dim_customers). Never count customer_id: Olist creates a new customer_id for every order.
- Buyers are customers with total_orders > 0.
- Repeat customers have total_orders >= 2. This includes both the 'repeat' (2-4 orders) and 'vip' (5+ orders) segments.
- Revenue is SUM(total_payment_amount) from fact_orders where order_status = 'delivered', unless the user asks for another status.
- On-time rate is the share of delivered orders where delivered_on_time is true.

Dates
- Data covers Sep 2016 to Oct 2018. Monthly trends should use Jan 2017 to Aug 2018; the months outside that range have only a handful of orders.
- "Recent", "last month" or "this year" mean relative to the latest date in the data (2018), not today's date.

Other
- Product categories are in Portuguese. Show the English translation next to the original name.
- customer_state is a two-letter Brazilian state code (SP = São Paulo, RJ = Rio de Janeiro, MG = Minas Gerais).
```

## Trusted SQL queries

**What is the average customer lifetime value?**
```sql
SELECT round(avg(lifetime_value), 2) AS avg_ltv
FROM workspace.gold.dim_customers
WHERE total_orders > 0;
```

**What is the repeat customer rate?**
```sql
SELECT
  count_if(total_orders >= 2)                            AS repeat_customers,
  count(*)                                               AS buyers,
  round(100 * count_if(total_orders >= 2) / count(*), 1) AS repeat_rate_pct
FROM workspace.gold.dim_customers
WHERE total_orders > 0;
```

**What is the total revenue from delivered orders?**
```sql
SELECT
  sum(total_payment_amount)           AS revenue_brl,
  count(*)                            AS delivered_orders,
  round(avg(total_payment_amount), 2) AS avg_order_value_brl
FROM workspace.gold.fact_orders
WHERE order_status = 'delivered';
```

**What is the on-time delivery rate?**
```sql
SELECT round(100 * count_if(delivered_on_time) / count(delivered_on_time), 1) AS on_time_pct
FROM workspace.gold.fact_orders
WHERE order_status = 'delivered';
```

**Show the monthly revenue trend**
```sql
SELECT
  order_month,
  sum(total_revenue) AS revenue_brl,
  sum(total_orders)  AS orders
FROM workspace.gold.fact_monthly_revenue
WHERE order_month BETWEEN '2017-01-01' AND '2018-08-01'
GROUP BY order_month
ORDER BY order_month;
```

## Sample questions
- What percentage of buyers are repeat customers?
- Which states bring in the most revenue?
- How does delivery time differ between on-time and late orders?
- Which product categories have the highest revenue?

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
