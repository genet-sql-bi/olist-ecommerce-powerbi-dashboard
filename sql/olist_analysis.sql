-- =============================================================
-- Olist E-Commerce Analysis (PostgreSQL)
-- Author: Genet Tesfamichael
-- Database: Brazilian_Ecom  |  Schema: public
-- These queries reproduce the key findings of the Power BI dashboard.
-- =============================================================


-- 1. Business overview KPIs
--    Revenue uses payment value (includes freight), matching the dashboard.
SELECT
    (SELECT ROUND(SUM(payment_value)::numeric, 2) FROM order_payments)       AS total_revenue,
    (SELECT COUNT(DISTINCT order_id) FROM orders)                            AS total_orders,
    (SELECT COUNT(DISTINCT customer_unique_id) FROM customers)               AS total_customers,
    ROUND(
        (SELECT SUM(payment_value) FROM order_payments)::numeric
        / (SELECT COUNT(DISTINCT order_id) FROM orders), 2)                  AS avg_order_value
		
--    Result: revenue R$ 16,008,872.12 | orders 99,441 | customers 96,096 | AOV R$ 160.99

-- 2. Monthly revenue trend (Jan 2017 - Aug 2018, full months only)
SELECT
    DATE_TRUNC('month', o.order_purchase_timestamp::timestamp)::date AS month,
    ROUND(SUM(p.payment_value)::numeric, 2)                          AS revenue
FROM orders o
JOIN order_payments p ON p.order_id = o.order_id
WHERE o.order_purchase_timestamp::timestamp >= '2017-01-01'
  AND o.order_purchase_timestamp::timestamp <  '2018-09-01'
GROUP BY 1
ORDER BY 1;
--    Result: 20 months | peak Nov 2017 R$ 1.19M (Black Friday) | 2018 steady at R$ 0.99M-1.16M per month

-- 3. Top 10 product categories by revenue (English names)
SELECT
    COALESCE(t.product_category_name_english, p.product_category_name, 'unknown') AS category,
    ROUND(SUM(oi.price)::numeric, 2)                                               AS product_revenue
FROM order_items oi
JOIN products p                   ON p.product_id = oi.product_id
LEFT JOIN category_translation t  ON t.product_category_name = p.product_category_name
GROUP BY 1
ORDER BY product_revenue DESC
LIMIT 10;

-- Result: Health Beauty R$ 1.26M | Watches Gifts R$ 1.21M | Bed Bath Table R$ 1.04M ... #10 Garden Tools R$ 0.49M

-- 4. Customer retention: how many customers ever came back?
WITH orders_per_customer AS (
    SELECT c.customer_unique_id, COUNT(DISTINCT o.order_id) AS order_count
    FROM customers c
    JOIN orders o ON o.customer_id = c.customer_id
    GROUP BY c.customer_unique_id
)
SELECT
    COUNT(*)                                                     AS customers,
    ROUND(AVG(order_count), 2)                                   AS orders_per_customer,
    SUM(CASE WHEN order_count > 1 THEN 1 ELSE 0 END)             AS repeat_customers,
    ROUND(100.0 * SUM(CASE WHEN order_count > 1 THEN 1 ELSE 0 END)
          / COUNT(*), 1)                                         AS repeat_customer_pct
FROM orders_per_customer;

-- Result: 96,096 customers | 1.03 orders each | only 2,997 repeat customers (3.1%), so ~97% never return

-- 5. Delivery performance: 10 slowest states
SELECT
    c.customer_state                                                      AS state,
    COUNT(*)                                                              AS delivered_orders,
    ROUND(AVG(o.order_delivered_customer_date::date
              - o.order_purchase_timestamp::date), 1)                     AS avg_delivery_days,
    ROUND(100.0 * AVG(CASE WHEN o.order_delivered_customer_date::timestamp
                                <= o.order_estimated_delivery_date::timestamp
                           THEN 1 ELSE 0 END), 1)                         AS on_time_pct
FROM orders o
JOIN customers c ON c.customer_id = o.customer_id
WHERE o.order_delivered_customer_date IS NOT NULL
GROUP BY c.customer_state
ORDER BY avg_delivery_days DESC
LIMIT 10;

-- Result: slowest RR 29.3 days, AP 27.2, AM 26.4 | remote states are slow but mostly on time (AP 95.5%) | worst on-time rate AL 76.1%


-- 6. Headline insight: do late deliveries hurt review scores?
SELECT
    CASE
        WHEN o.order_delivered_customer_date IS NULL THEN 'Not Delivered'
        WHEN o.order_delivered_customer_date::timestamp
             > o.order_estimated_delivery_date::timestamp THEN 'Late'
        ELSE 'On Time'
    END                                   AS delivery_status,
    COUNT(*)                              AS reviews,
    ROUND(AVG(r.review_score), 2)         AS avg_review_score
FROM order_reviews r
JOIN orders o ON o.order_id = r.order_id
GROUP BY 1
ORDER BY avg_review_score DESC;

-- Result: On Time 4.29 (88,658 reviews) | Late 2.57 (7,701) | Not Delivered 1.76 (2,865), so late delivery cuts scores by ~40%

-- 7. Top-rated categories (minimum 100 reviews, so small samples can't win by luck)
SELECT
    COALESCE(t.product_category_name_english, p.product_category_name) AS category,
    COUNT(*)                                                             AS reviews,
    ROUND(AVG(r.review_score), 2)                                        AS avg_review_score
FROM order_reviews r
JOIN order_items oi               ON oi.order_id = r.order_id
JOIN products p                   ON p.product_id = oi.product_id
LEFT JOIN category_translation t  ON t.product_category_name = p.product_category_name
WHERE p.product_category_name IS NOT NULL
GROUP BY 1
HAVING COUNT(*) >= 100
ORDER BY avg_review_score DESC
LIMIT 10;

-- Result: Books General Interest 4.45 (549 reviews) | Books Technical 4.37 | Luggage Accessories 4.32 (1,088 reviews)