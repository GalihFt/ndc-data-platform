-- Jalankan sekali pada ndc_oltp setelah file 01 dan 02.
BEGIN;

CREATE TABLE oltp.customers (
    customer_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_name VARCHAR(150) NOT NULL,
    address TEXT NOT NULL
);

CREATE TABLE oltp.sales_orders (
    sales_order_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id BIGINT NOT NULL REFERENCES oltp.customers (customer_id),
    warehouse_id BIGINT NOT NULL REFERENCES oltp.warehouses (warehouse_id),
    order_date DATE NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'PENDING'
        CHECK (status IN ('PENDING', 'CONFIRMED', 'SHIPPED', 'COMPLETED', 'CANCELLED')),
    confirmed_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ
);

CREATE TABLE oltp.sales_order_items (
    sales_order_item_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    sales_order_id BIGINT NOT NULL REFERENCES oltp.sales_orders (sales_order_id),
    product_id BIGINT NOT NULL REFERENCES oltp.products (product_id),
    ordered_quantity INTEGER NOT NULL CHECK (ordered_quantity > 0),
    unit_price NUMERIC(18, 2) NOT NULL CHECK (unit_price >= 0),
    UNIQUE (sales_order_id, product_id)
);

CREATE TABLE oltp.goods_issues (
    goods_issue_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    sales_order_id BIGINT NOT NULL UNIQUE REFERENCES oltp.sales_orders (sales_order_id),
    issued_at TIMESTAMPTZ NOT NULL,
    -- Diisi oleh post_goods_issue(), bukan saat konfirmasi SO.
    posted_at TIMESTAMPTZ
);

CREATE TABLE oltp.goods_issue_items (
    goods_issue_item_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    goods_issue_id BIGINT NOT NULL REFERENCES oltp.goods_issues (goods_issue_id),
    sales_order_item_id BIGINT NOT NULL REFERENCES oltp.sales_order_items (sales_order_item_id),
    issued_quantity INTEGER NOT NULL CHECK (issued_quantity > 0),
    UNIQUE (goods_issue_id, sales_order_item_id)
);

-- Perluasan tabel inbound; data IN yang valid tetap dipertahankan.
ALTER TABLE oltp.inventory_movements
    ALTER COLUMN goods_receipt_item_id DROP NOT NULL,
    ADD COLUMN goods_issue_item_id BIGINT UNIQUE
        REFERENCES oltp.goods_issue_items (goods_issue_item_id),
    ADD CONSTRAINT inventory_movements_source_check CHECK (
        (movement_type = 'IN' AND goods_receipt_item_id IS NOT NULL
                             AND goods_issue_item_id IS NULL)
        OR
        (movement_type = 'OUT' AND goods_issue_item_id IS NOT NULL
                              AND goods_receipt_item_id IS NULL)
    );

CREATE INDEX sales_orders_warehouse_status_idx
    ON oltp.sales_orders (warehouse_id, status);
CREATE INDEX goods_issue_items_sales_order_item_idx
    ON oltp.goods_issue_items (sales_order_item_id);

-- Normalisasi lokasi dan produk movement dari dua jenis dokumen sumber.
CREATE VIEW oltp.stock_movements AS
SELECT im.inventory_movement_id, poi.product_id, po.warehouse_id,
       im.quantity::BIGINT AS quantity_change
FROM oltp.inventory_movements im
JOIN oltp.goods_receipt_items gri USING (goods_receipt_item_id)
JOIN oltp.purchase_order_items poi USING (purchase_order_item_id)
JOIN oltp.goods_receipts gr USING (goods_receipt_id)
JOIN oltp.purchase_orders po ON po.purchase_order_id = gr.purchase_order_id
WHERE im.movement_type = 'IN'
UNION ALL
SELECT im.inventory_movement_id, soi.product_id, so.warehouse_id,
       -im.quantity::BIGINT AS quantity_change
FROM oltp.inventory_movements im
JOIN oltp.goods_issue_items gii USING (goods_issue_item_id)
JOIN oltp.sales_order_items soi USING (sales_order_item_id)
JOIN oltp.goods_issues gi USING (goods_issue_id)
JOIN oltp.sales_orders so ON so.sales_order_id = gi.sales_order_id
WHERE im.movement_type = 'OUT';

-- Saldo awal nol. Pasangan tanpa movement tetap menghasilkan stok nol.
CREATE VIEW oltp.inventory_stock AS
WITH physical AS (
    SELECT product_id, warehouse_id, SUM(quantity_change) AS physical_stock
    FROM oltp.stock_movements
    GROUP BY product_id, warehouse_id
), reserved AS (
    SELECT soi.product_id, so.warehouse_id, SUM(soi.ordered_quantity) AS reserved_stock
    FROM oltp.sales_order_items soi
    JOIN oltp.sales_orders so USING (sales_order_id)
    WHERE so.status = 'CONFIRMED'
    GROUP BY soi.product_id, so.warehouse_id
)
SELECT p.product_id, w.warehouse_id,
       COALESCE(ph.physical_stock, 0) AS physical_stock,
       COALESCE(r.reserved_stock, 0) AS reserved_stock,
       COALESCE(ph.physical_stock, 0) - COALESCE(r.reserved_stock, 0) AS available_stock
FROM oltp.products p
CROSS JOIN oltp.warehouses w
LEFT JOIN physical ph ON ph.product_id = p.product_id AND ph.warehouse_id = w.warehouse_id
LEFT JOIN reserved r ON r.product_id = p.product_id AND r.warehouse_id = w.warehouse_id;

COMMIT;
