-- Jalankan SEKALI pada database ndc_dwh, setelah 00_create_database.sql.
-- Bentuk kolom mengikuti OLTP; seleksi BARIS dijelaskan di docs/dwh.md.
-- ID berasal dari sumber: tidak menggunakan IDENTITY atau sequence baru.
-- Tanpa FK dan aturan bisnis OLTP, agar tabel bisa dimuat secara terpisah.
-- PK menjaga satu baris per ID sumber. Belum ada proses extract/load di file ini.
BEGIN;
CREATE SCHEMA staging;

CREATE TABLE staging.suppliers (
    supplier_id BIGINT PRIMARY KEY,
    supplier_name VARCHAR(150) NOT NULL
);

CREATE TABLE staging.products (
    product_id BIGINT PRIMARY KEY,
    product_name VARCHAR(150) NOT NULL,
    category VARCHAR(100) NOT NULL,
    unit VARCHAR(20) NOT NULL
);

CREATE TABLE staging.warehouses (
    warehouse_id BIGINT PRIMARY KEY,
    warehouse_code VARCHAR(20) NOT NULL,
    warehouse_name VARCHAR(100) NOT NULL,
    city VARCHAR(100) NOT NULL
);

CREATE TABLE staging.customers (
    customer_id BIGINT PRIMARY KEY,
    customer_name VARCHAR(150) NOT NULL,
    address TEXT NOT NULL
);

CREATE TABLE staging.purchase_orders (
    purchase_order_id BIGINT PRIMARY KEY,
    supplier_id BIGINT NOT NULL,
    warehouse_id BIGINT NOT NULL,
    order_date DATE NOT NULL,
    status VARCHAR(25) NOT NULL
);

CREATE TABLE staging.purchase_order_items (
    purchase_order_item_id BIGINT PRIMARY KEY,
    purchase_order_id BIGINT NOT NULL,
    product_id BIGINT NOT NULL,
    ordered_quantity INTEGER NOT NULL,
    unit_price NUMERIC(18, 2) NOT NULL
);

CREATE TABLE staging.goods_receipts (
    goods_receipt_id BIGINT PRIMARY KEY,
    purchase_order_id BIGINT NOT NULL,
    received_at TIMESTAMPTZ NOT NULL,
    posted_at TIMESTAMPTZ
);

CREATE TABLE staging.goods_receipt_items (
    goods_receipt_item_id BIGINT PRIMARY KEY,
    goods_receipt_id BIGINT NOT NULL,
    purchase_order_item_id BIGINT NOT NULL,
    received_quantity INTEGER NOT NULL
);

CREATE TABLE staging.sales_orders (
    sales_order_id BIGINT PRIMARY KEY,
    customer_id BIGINT NOT NULL,
    warehouse_id BIGINT NOT NULL,
    order_date DATE NOT NULL,
    status VARCHAR(20) NOT NULL,
    confirmed_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ
);

CREATE TABLE staging.sales_order_items (
    sales_order_item_id BIGINT PRIMARY KEY,
    sales_order_id BIGINT NOT NULL,
    product_id BIGINT NOT NULL,
    ordered_quantity INTEGER NOT NULL,
    unit_price NUMERIC(18, 2) NOT NULL
);

CREATE TABLE staging.goods_issues (
    goods_issue_id BIGINT PRIMARY KEY,
    sales_order_id BIGINT NOT NULL,
    issued_at TIMESTAMPTZ NOT NULL,
    posted_at TIMESTAMPTZ
);

CREATE TABLE staging.goods_issue_items (
    goods_issue_item_id BIGINT PRIMARY KEY,
    goods_issue_id BIGINT NOT NULL,
    sales_order_item_id BIGINT NOT NULL,
    issued_quantity INTEGER NOT NULL
);

CREATE TABLE staging.inventory_movements (
    inventory_movement_id BIGINT PRIMARY KEY,
    goods_receipt_item_id BIGINT,
    movement_type VARCHAR(3) NOT NULL,
    quantity INTEGER NOT NULL,
    goods_issue_item_id BIGINT
);
COMMIT;
