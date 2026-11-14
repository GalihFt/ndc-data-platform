-- Hubungkan koneksi ke database ndc_oltp, lalu jalankan seluruh file sampai COMMIT.
-- File ini membuat tabel baru di schema oltp; tabel lama di public tidak dipindahkan.
BEGIN;

CREATE SCHEMA IF NOT EXISTS oltp;

CREATE TABLE oltp.suppliers (
    supplier_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    supplier_name VARCHAR(150) NOT NULL
);

CREATE TABLE oltp.products (
    product_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    product_name VARCHAR(150) NOT NULL,
    category VARCHAR(100) NOT NULL,
    unit VARCHAR(20) NOT NULL
);

CREATE TABLE oltp.warehouses (
    warehouse_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    warehouse_code VARCHAR(20) NOT NULL UNIQUE,
    warehouse_name VARCHAR(100) NOT NULL,
    city VARCHAR(100) NOT NULL
);

CREATE TABLE oltp.purchase_orders (
    purchase_order_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    supplier_id BIGINT NOT NULL REFERENCES oltp.suppliers (supplier_id),
    warehouse_id BIGINT NOT NULL REFERENCES oltp.warehouses (warehouse_id),
    order_date DATE NOT NULL,
    status VARCHAR(25) NOT NULL DEFAULT 'DRAFT',
    CONSTRAINT purchase_orders_status_check CHECK (
        status IN ('DRAFT', 'ORDERED', 'PARTIALLY_RECEIVED', 'RECEIVED', 'CANCELLED')
    )
);

CREATE TABLE oltp.purchase_order_items (
    purchase_order_item_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    purchase_order_id BIGINT NOT NULL REFERENCES oltp.purchase_orders (purchase_order_id),
    product_id BIGINT NOT NULL REFERENCES oltp.products (product_id),
    ordered_quantity INTEGER NOT NULL CHECK (ordered_quantity > 0),
    unit_price NUMERIC(18, 2) NOT NULL CHECK (unit_price >= 0),
    UNIQUE (purchase_order_id, product_id)
);

CREATE TABLE oltp.goods_receipts (
    goods_receipt_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    purchase_order_id BIGINT NOT NULL REFERENCES oltp.purchase_orders (purchase_order_id),
    received_at TIMESTAMPTZ NOT NULL,
    -- NULL berarti belum dibukukan. Diisi melalui post_goods_receipt().
    posted_at TIMESTAMPTZ
);

CREATE TABLE oltp.goods_receipt_items (
    goods_receipt_item_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    goods_receipt_id BIGINT NOT NULL REFERENCES oltp.goods_receipts (goods_receipt_id),
    purchase_order_item_id BIGINT NOT NULL
        REFERENCES oltp.purchase_order_items (purchase_order_item_id),
    received_quantity INTEGER NOT NULL CHECK (received_quantity > 0),
    UNIQUE (goods_receipt_id, purchase_order_item_id)
);

CREATE TABLE oltp.inventory_movements (
    inventory_movement_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    goods_receipt_item_id BIGINT NOT NULL UNIQUE
        REFERENCES oltp.goods_receipt_items (goods_receipt_item_id),
    movement_type VARCHAR(3) NOT NULL CHECK (movement_type IN ('IN', 'OUT')),
    quantity INTEGER NOT NULL CHECK (quantity > 0)
);

-- Pencarian penerimaan berdasarkan PO, termasuk saat validasi posting.
CREATE INDEX goods_receipts_purchase_order_idx
    ON oltp.goods_receipts (purchase_order_id);

CREATE INDEX goods_receipt_items_purchase_order_item_idx
    ON oltp.goods_receipt_items (purchase_order_item_id);

COMMIT;
