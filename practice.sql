-- SQL Practice: E-commerce Schema and Complex Queries
-- Designed by an SQL Expert

-- 1. Schema Design
-- Using proper constraints, data types, and indexing strategies.

CREATE TABLE users (
    user_id SERIAL PRIMARY KEY,
    username VARCHAR(50) NOT NULL UNIQUE,
    email VARCHAR(100) NOT NULL UNIQUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    last_login TIMESTAMP WITH TIME ZONE
);

CREATE INDEX idx_users_email ON users(email);

CREATE TABLE products (
    product_id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    category VARCHAR(50) NOT NULL,
    price DECIMAL(10, 2) NOT NULL CHECK (price >= 0),
    stock_quantity INTEGER NOT NULL DEFAULT 0 CHECK (stock_quantity >= 0),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_products_category ON products(category);

CREATE TABLE orders (
    order_id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(user_id),
    order_date TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    status VARCHAR(20) CHECK (status IN ('pending', 'shipped', 'delivered', 'cancelled')),
    total_amount DECIMAL(12, 2) NOT NULL DEFAULT 0
);

CREATE INDEX idx_orders_user_date ON orders(user_id, order_date);

CREATE TABLE order_items (
    item_id SERIAL PRIMARY KEY,
    order_id INTEGER NOT NULL REFERENCES orders(order_id) ON DELETE CASCADE,
    product_id INTEGER NOT NULL REFERENCES products(product_id),
    quantity INTEGER NOT NULL CHECK (quantity > 0),
    unit_price DECIMAL(10, 2) NOT NULL
);

-- 2. Advanced Queries

-- Query 1: Customer Lifetime Value (CLV) Analysis using CTEs and Window Functions
-- Calculate total spend per user, their rank by spend, and their contribution to total revenue.

WITH UserSpend AS (
    SELECT 
        u.user_id,
        u.username,
        COUNT(o.order_id) as total_orders,
        COALESCE(SUM(o.total_amount), 0) as total_spent
    FROM users u
    LEFT JOIN orders o ON u.user_id = o.user_id AND o.status != 'cancelled'
    GROUP BY u.user_id, u.username
),
RankedUsers AS (
    SELECT 
        *,
        DENSE_RANK() OVER (ORDER BY total_spent DESC) as spend_rank,
        SUM(total_spent) OVER () as grand_total_revenue
    FROM UserSpend
)
SELECT 
    username,
    total_orders,
    total_spent,
    spend_rank,
    ROUND((total_spent / NULLIF(grand_total_revenue, 0)) * 100, 2) as revenue_percentage
FROM RankedUsers
ORDER BY spend_rank
LIMIT 10;

-- Query 2: Moving Average of Daily Sales (Time Series Analysis)
-- Calculate 7-day moving average of sales to smooth out daily fluctuations.

WITH DailySales AS (
    SELECT 
        DATE(order_date) as sale_date,
        SUM(total_amount) as daily_revenue
    FROM orders
    WHERE status != 'cancelled'
    GROUP BY DATE(order_date)
)
SELECT 
    sale_date,
    daily_revenue,
    AVG(daily_revenue) OVER (
        ORDER BY sale_date 
        ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    ) as moving_avg_7_days
FROM DailySales
ORDER BY sale_date DESC;

-- Query 3: Product Performance: Finding top products in each category
-- Using PARTITION BY to rank items within their categories.

WITH ProductSales AS (
    SELECT 
        p.category,
        p.name,
        SUM(oi.quantity) as total_sold
    FROM products p
    JOIN order_items oi ON p.product_id = oi.product_id
    JOIN orders o ON oi.order_id = o.order_id
    WHERE o.status != 'cancelled'
    GROUP BY p.category, p.name
)
SELECT * FROM (
    SELECT 
        category,
        name,
        total_sold,
        RANK() OVER (PARTITION BY category ORDER BY total_sold DESC) as rank_in_category
    FROM ProductSales
) ranked
WHERE rank_in_category <= 3;
