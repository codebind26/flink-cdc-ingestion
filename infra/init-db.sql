-- ============================================================
-- E-Commerce Database Schema
-- This is your equivalent of the NED "programs" schema
-- ============================================================

-- Create schema (like ned.programs in your company repo)
CREATE SCHEMA IF NOT EXISTS ecommerce;

-- ============================================================
-- DIMENSION TABLES (slowly changing - like program_type, program_subtype)
-- These are the tables you'll do temporal joins against
-- ============================================================

CREATE TABLE ecommerce.customers (
    customer_id SERIAL PRIMARY KEY,
    email VARCHAR(255) NOT NULL,
    first_name VARCHAR(100),
    last_name VARCHAR(100),
    tier VARCHAR(20) DEFAULT 'STANDARD',   -- STANDARD, PREMIUM, VIP
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE ecommerce.products (
    product_id SERIAL PRIMARY KEY,
    product_name VARCHAR(255) NOT NULL,
    category VARCHAR(100),
    subcategory VARCHAR(100),
    price DECIMAL(10,2) NOT NULL,
    stock_quantity INTEGER DEFAULT 0,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE ecommerce.categories (
    category_id SERIAL PRIMARY KEY,
    category_name VARCHAR(100) NOT NULL,
    parent_category_id INTEGER REFERENCES ecommerce.categories(category_id),
    description TEXT
);

CREATE TABLE ecommerce.warehouses (
    warehouse_id SERIAL PRIMARY KEY,
    warehouse_name VARCHAR(100) NOT NULL,
    city VARCHAR(100),
    state VARCHAR(50),
    country VARCHAR(50) DEFAULT 'US'
);

-- ============================================================
-- FACT / EVENT TABLES (high velocity - like program_update)
-- These are the tables that generate the CDC stream
-- ============================================================

CREATE TABLE ecommerce.orders (
    order_id SERIAL PRIMARY KEY,
    customer_id INTEGER REFERENCES ecommerce.customers(customer_id),
    order_status VARCHAR(30) DEFAULT 'PENDING',  -- PENDING, CONFIRMED, SHIPPED, DELIVERED, CANCELLED
    total_amount DECIMAL(12,2),
    currency VARCHAR(3) DEFAULT 'USD',
    shipping_address TEXT,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE ecommerce.order_items (
    order_item_id SERIAL PRIMARY KEY,
    order_id INTEGER REFERENCES ecommerce.orders(order_id),
    product_id INTEGER REFERENCES ecommerce.products(product_id),
    quantity INTEGER NOT NULL,
    unit_price DECIMAL(10,2) NOT NULL,
    discount_pct DECIMAL(5,2) DEFAULT 0,
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE ecommerce.payments (
    payment_id SERIAL PRIMARY KEY,
    order_id INTEGER REFERENCES ecommerce.orders(order_id),
    payment_method VARCHAR(30),   -- CREDIT_CARD, DEBIT_CARD, PAYPAL, BANK_TRANSFER
    payment_status VARCHAR(20),   -- PENDING, COMPLETED, FAILED, REFUNDED
    amount DECIMAL(12,2) NOT NULL,
    processed_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE ecommerce.inventory_events (
    event_id SERIAL PRIMARY KEY,
    product_id INTEGER REFERENCES ecommerce.products(product_id),
    warehouse_id INTEGER REFERENCES ecommerce.warehouses(warehouse_id),
    event_type VARCHAR(20),       -- RESTOCK, SALE, RETURN, ADJUSTMENT
    quantity_change INTEGER NOT NULL,
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE ecommerce.shipments (
    shipment_id SERIAL PRIMARY KEY,
    order_id INTEGER REFERENCES ecommerce.orders(order_id),
    warehouse_id INTEGER REFERENCES ecommerce.warehouses(warehouse_id),
    carrier VARCHAR(50),
    tracking_number VARCHAR(100),
    shipment_status VARCHAR(20),  -- PREPARING, SHIPPED, IN_TRANSIT, DELIVERED
    shipped_at TIMESTAMP,
    delivered_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT NOW()
);

-- ============================================================
-- CREATE PUBLICATION FOR CDC
-- This is the equivalent of debezium.publication.name in your company YAML
-- Flink CDC uses this to subscribe to changes
-- ============================================================

-- Publication for all ecommerce tables
CREATE PUBLICATION ecommerce_cdc_publication FOR TABLES IN SCHEMA ecommerce;

-- ============================================================
-- SEED DATA - gives you something to work with immediately
-- ============================================================

INSERT INTO ecommerce.categories (category_name, description) VALUES
('Electronics', 'Electronic devices and accessories'),
('Clothing', 'Apparel and fashion'),
('Books', 'Physical and digital books'),
('Home & Garden', 'Home improvement and garden supplies');

INSERT INTO ecommerce.warehouses (warehouse_name, city, state) VALUES
('East Coast Hub', 'Newark', 'NJ'),
('West Coast Hub', 'Los Angeles', 'CA'),
('Central Hub', 'Dallas', 'TX');

INSERT INTO ecommerce.customers (email, first_name, last_name, tier) VALUES
('alice@example.com', 'Alice', 'Johnson', 'VIP'),
('bob@example.com', 'Bob', 'Smith', 'PREMIUM'),
('charlie@example.com', 'Charlie', 'Brown', 'STANDARD'),
('diana@example.com', 'Diana', 'Prince', 'VIP'),
('eve@example.com', 'Eve', 'Wilson', 'STANDARD');

INSERT INTO ecommerce.products (product_name, category, subcategory, price, stock_quantity) VALUES
('Laptop Pro 15', 'Electronics', 'Laptops', 1299.99, 50),
('Wireless Mouse', 'Electronics', 'Accessories', 29.99, 200),
('Java in Action', 'Books', 'Programming', 49.99, 100),
('Running Shoes', 'Clothing', 'Footwear', 89.99, 75),
('Coffee Maker', 'Home & Garden', 'Kitchen', 149.99, 30),
('USB-C Hub', 'Electronics', 'Accessories', 59.99, 150),
('Data Engineering Guide', 'Books', 'Programming', 54.99, 80),
('Winter Jacket', 'Clothing', 'Outerwear', 199.99, 40);

-- Seed orders so snapshot phase has fact data
INSERT INTO ecommerce.orders (customer_id, order_status, total_amount, shipping_address) VALUES
(1, 'DELIVERED', 1329.98, '123 Main St, Newark, NJ'),
(2, 'SHIPPED',    89.99, '456 Oak Ave, Dallas, TX'),
(3, 'CONFIRMED', 109.98, '789 Pine Rd, LA, CA'),
(4, 'PENDING',   199.99, '321 Elm St, Newark, NJ'),
(5, 'DELIVERED',  59.99, '654 Maple Dr, Dallas, TX');

INSERT INTO ecommerce.order_items (order_id, product_id, quantity, unit_price) VALUES
(1, 1, 1, 1299.99),
(1, 2, 1,   29.99),
(2, 4, 1,   89.99),
(3, 3, 1,   49.99),
(3, 6, 1,   59.99),
(4, 8, 1,  199.99),
(5, 6, 1,   59.99);

INSERT INTO ecommerce.payments (order_id, payment_method, payment_status, amount) VALUES
(1, 'CREDIT_CARD',   'COMPLETED', 1329.98),
(2, 'PAYPAL',        'COMPLETED',   89.99),
(3, 'DEBIT_CARD',    'COMPLETED',  109.98),
(4, 'BANK_TRANSFER', 'PENDING',    199.99),
(5, 'CREDIT_CARD',   'COMPLETED',   59.99);

INSERT INTO ecommerce.inventory_events (product_id, warehouse_id, event_type, quantity_change) VALUES
(1, 1, 'SALE', -1),
(2, 1, 'SALE', -1),
(4, 3, 'SALE', -1),
(8, 1, 'SALE', -1),
(1, 1, 'RESTOCK', 20);

INSERT INTO ecommerce.shipments (order_id, warehouse_id, carrier, tracking_number, shipment_status, shipped_at, delivered_at) VALUES
(1, 1, 'UPS',   'TRK10001', 'DELIVERED',  NOW() - INTERVAL '5 days', NOW() - INTERVAL '2 days'),
(2, 3, 'FEDEX', 'TRK10002', 'IN_TRANSIT', NOW() - INTERVAL '1 day', NULL),
(5, 2, 'USPS',  'TRK10003', 'DELIVERED',  NOW() - INTERVAL '3 days', NOW() - INTERVAL '1 day');
