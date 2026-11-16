-- Jalankan SEKALI pada database ndc_dwh, setelah 01_staging_tables.sql.
-- Schema dwh berisi dimension dan fact.
BEGIN;
CREATE SCHEMA dwh;

-- Key adalah ID di DWH; kolom *_id adalah ID asal dari OLTP.
CREATE TABLE dwh.dim_product (
    product_key BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    product_id BIGINT NOT NULL UNIQUE,
    product_name VARCHAR(150) NOT NULL,
    category VARCHAR(100) NOT NULL,
    unit VARCHAR(20) NOT NULL
);

CREATE TABLE dwh.dim_warehouse (
    warehouse_key BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    warehouse_id BIGINT NOT NULL UNIQUE,
    warehouse_code VARCHAR(20) NOT NULL UNIQUE,
    warehouse_name VARCHAR(100) NOT NULL,
    city VARCHAR(100) NOT NULL
);

CREATE TABLE dwh.dim_supplier (
    supplier_key BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    supplier_id BIGINT NOT NULL UNIQUE,
    supplier_name VARCHAR(150) NOT NULL
);

CREATE TABLE dwh.dim_customer (
    customer_key BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id BIGINT NOT NULL UNIQUE,
    customer_name VARCHAR(150) NOT NULL,
    address TEXT NOT NULL
);

CREATE TABLE dwh.dim_date (
    date_key INTEGER PRIMARY KEY, -- YYYYMMDD, misalnya 20261114
    full_date DATE NOT NULL UNIQUE,
    year_number INTEGER NOT NULL,
    month_number INTEGER NOT NULL CHECK (month_number BETWEEN 1 AND 12),
    day_number INTEGER NOT NULL CHECK (day_number BETWEEN 1 AND 31)
);

-- Grain: satu item GR yang sudah posted. Penerimaan parsial menjadi baris terpisah.
CREATE TABLE dwh.fact_receiving (
    goods_receipt_item_id BIGINT PRIMARY KEY,
    goods_receipt_id BIGINT NOT NULL,
    purchase_order_id BIGINT NOT NULL,
    product_key BIGINT NOT NULL REFERENCES dwh.dim_product,
    warehouse_key BIGINT NOT NULL REFERENCES dwh.dim_warehouse,
    supplier_key BIGINT NOT NULL REFERENCES dwh.dim_supplier,
    date_key INTEGER NOT NULL REFERENCES dwh.dim_date,
    posted_at TIMESTAMPTZ NOT NULL,
    qty_received INTEGER NOT NULL CHECK (qty_received > 0),
    unit_cost NUMERIC(18, 2) NOT NULL CHECK (unit_cost >= 0),
    receiving_amount NUMERIC(28, 2) NOT NULL CHECK (receiving_amount >= 0)
);

-- Grain: satu item GI yang sudah posted. Completion tidak membuat penjualan baru.
CREATE TABLE dwh.fact_sales (
    goods_issue_item_id BIGINT PRIMARY KEY,
    goods_issue_id BIGINT NOT NULL,
    sales_order_id BIGINT NOT NULL,
    product_key BIGINT NOT NULL REFERENCES dwh.dim_product,
    warehouse_key BIGINT NOT NULL REFERENCES dwh.dim_warehouse,
    customer_key BIGINT NOT NULL REFERENCES dwh.dim_customer,
    date_key INTEGER NOT NULL REFERENCES dwh.dim_date,
    posted_at TIMESTAMPTZ NOT NULL,
    qty_sold INTEGER NOT NULL CHECK (qty_sold > 0),
    unit_price NUMERIC(18, 2) NOT NULL CHECK (unit_price >= 0),
    sales_amount NUMERIC(28, 2) NOT NULL CHECK (sales_amount >= 0)
);

-- Grain: satu movement, bukan snapshot harian. Jumlah selalu positif.
CREATE TABLE dwh.fact_inventory (
    movement_id BIGINT PRIMARY KEY, -- inventory_movement_id dari OLTP
    product_key BIGINT NOT NULL REFERENCES dwh.dim_product,
    warehouse_key BIGINT NOT NULL REFERENCES dwh.dim_warehouse,
    date_key INTEGER NOT NULL REFERENCES dwh.dim_date,
    posted_at TIMESTAMPTZ NOT NULL,
    movement_type VARCHAR(3) NOT NULL CHECK (movement_type IN ('IN', 'OUT')),
    qty_movement INTEGER NOT NULL CHECK (qty_movement > 0),
    goods_receipt_id BIGINT,
    goods_issue_id BIGINT,
    CHECK (
        (movement_type = 'IN' AND goods_receipt_id IS NOT NULL AND goods_issue_id IS NULL)
        OR (movement_type = 'OUT' AND goods_issue_id IS NOT NULL AND goods_receipt_id IS NULL)
    )
);

CREATE INDEX fact_receiving_date_idx ON dwh.fact_receiving (date_key);
CREATE INDEX fact_sales_date_idx ON dwh.fact_sales (date_key);
CREATE INDEX fact_inventory_product_warehouse_date_idx
    ON dwh.fact_inventory (product_key, warehouse_key, date_key);
COMMIT;
