-- Dijalankan Python di dalam transaksi tujuan. Jangan tambahkan COMMIT di sini.
-- Bila dijalankan manual, gunakan BEGIN, validasi, lalu COMMIT/ROLLBACK sendiri.

-- 1. Perbarui dimension tanpa mengganti key yang sudah ada (SCD Type 1).
INSERT INTO dwh.dim_product (product_id, product_name, category, unit)
SELECT product_id, product_name, category, unit FROM staging.products
ON CONFLICT (product_id) DO UPDATE
SET product_name = EXCLUDED.product_name, category = EXCLUDED.category, unit = EXCLUDED.unit;

INSERT INTO dwh.dim_warehouse (warehouse_id, warehouse_code, warehouse_name, city)
SELECT warehouse_id, warehouse_code, warehouse_name, city FROM staging.warehouses
ON CONFLICT (warehouse_id) DO UPDATE
SET warehouse_code = EXCLUDED.warehouse_code,
    warehouse_name = EXCLUDED.warehouse_name, city = EXCLUDED.city;

INSERT INTO dwh.dim_supplier (supplier_id, supplier_name)
SELECT supplier_id, supplier_name FROM staging.suppliers
ON CONFLICT (supplier_id) DO UPDATE SET supplier_name = EXCLUDED.supplier_name;

INSERT INTO dwh.dim_customer (customer_id, customer_name, address)
SELECT customer_id, customer_name, address FROM staging.customers
ON CONFLICT (customer_id) DO UPDATE
SET customer_name = EXCLUDED.customer_name, address = EXCLUDED.address;

-- 2. Kalender lengkap dari tanggal posting pertama sampai terakhir di Jakarta.
WITH posting_dates AS (
    SELECT (posted_at AT TIME ZONE 'Asia/Jakarta')::DATE AS posting_date FROM staging.goods_receipts
    UNION ALL
    SELECT (posted_at AT TIME ZONE 'Asia/Jakarta')::DATE FROM staging.goods_issues
), bounds AS (
    SELECT MIN(posting_date) AS first_date, MAX(posting_date) AS last_date FROM posting_dates
), calendar AS (
    SELECT first_date + n AS full_date
    FROM bounds CROSS JOIN LATERAL generate_series(0, last_date - first_date) AS g(n)
)
INSERT INTO dwh.dim_date (date_key, full_date, year_number, month_number, day_number)
SELECT TO_CHAR(full_date, 'YYYYMMDD')::INTEGER, full_date,
       EXTRACT(YEAR FROM full_date)::INTEGER, EXTRACT(MONTH FROM full_date)::INTEGER,
       EXTRACT(DAY FROM full_date)::INTEGER
FROM calendar ON CONFLICT (date_key) DO NOTHING;

-- 3. Full refresh fact. Sumber sudah ada di staging, bukan membaca OLTP langsung.
TRUNCATE dwh.fact_receiving, dwh.fact_sales, dwh.fact_inventory;

INSERT INTO dwh.fact_receiving (
    goods_receipt_item_id, goods_receipt_id, purchase_order_id,
    product_key, warehouse_key, supplier_key, date_key, posted_at,
    qty_received, unit_cost, receiving_amount
)
SELECT gri.goods_receipt_item_id, gr.goods_receipt_id, po.purchase_order_id,
       p.product_key, w.warehouse_key, s.supplier_key, d.date_key, gr.posted_at,
       gri.received_quantity, poi.unit_price, gri.received_quantity * poi.unit_price
FROM staging.goods_receipt_items gri
JOIN staging.goods_receipts gr USING (goods_receipt_id)
JOIN staging.purchase_order_items poi USING (purchase_order_item_id)
JOIN staging.purchase_orders po ON po.purchase_order_id = gr.purchase_order_id
JOIN dwh.dim_product p ON p.product_id = poi.product_id
JOIN dwh.dim_warehouse w ON w.warehouse_id = po.warehouse_id
JOIN dwh.dim_supplier s ON s.supplier_id = po.supplier_id
JOIN dwh.dim_date d ON d.full_date = (gr.posted_at AT TIME ZONE 'Asia/Jakarta')::DATE;

INSERT INTO dwh.fact_sales (
    goods_issue_item_id, goods_issue_id, sales_order_id,
    product_key, warehouse_key, customer_key, date_key, posted_at,
    qty_sold, unit_price, sales_amount
)
SELECT gii.goods_issue_item_id, gi.goods_issue_id, so.sales_order_id,
       p.product_key, w.warehouse_key, c.customer_key, d.date_key, gi.posted_at,
       gii.issued_quantity, soi.unit_price, gii.issued_quantity * soi.unit_price
FROM staging.goods_issue_items gii
JOIN staging.goods_issues gi USING (goods_issue_id)
JOIN staging.sales_order_items soi USING (sales_order_item_id)
JOIN staging.sales_orders so ON so.sales_order_id = gi.sales_order_id
JOIN dwh.dim_product p ON p.product_id = soi.product_id
JOIN dwh.dim_warehouse w ON w.warehouse_id = so.warehouse_id
JOIN dwh.dim_customer c ON c.customer_id = so.customer_id
JOIN dwh.dim_date d ON d.full_date = (gi.posted_at AT TIME ZONE 'Asia/Jakarta')::DATE;

INSERT INTO dwh.fact_inventory (
    movement_id, product_key, warehouse_key, date_key, posted_at,
    movement_type, qty_movement, goods_receipt_id, goods_issue_id
)
SELECT im.inventory_movement_id, f.product_key, f.warehouse_key, f.date_key,
       f.posted_at, im.movement_type, im.quantity, f.goods_receipt_id, NULL
FROM staging.inventory_movements im
JOIN dwh.fact_receiving f ON f.goods_receipt_item_id = im.goods_receipt_item_id
WHERE im.movement_type = 'IN'
UNION ALL
SELECT im.inventory_movement_id, f.product_key, f.warehouse_key, f.date_key,
       f.posted_at, im.movement_type, im.quantity, NULL, f.goods_issue_id
FROM staging.inventory_movements im
JOIN dwh.fact_sales f ON f.goods_issue_item_id = im.goods_issue_item_id
WHERE im.movement_type = 'OUT';
