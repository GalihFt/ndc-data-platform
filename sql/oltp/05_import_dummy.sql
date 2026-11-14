-- Jalankan dari root repo melalui psql -f, setelah file 01-04.
-- Gunakan tabel kosong. Data CSV dianggap valid dan siap diimpor.
\set ON_ERROR_STOP on
\encoding UTF8

BEGIN;

-- Import sesuai urutan relasi FK. Path CSV relatif terhadap root repo.
\copy oltp.suppliers (supplier_id, supplier_name) FROM 'data/dummy/suppliers.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy oltp.products (product_id, product_name, category, unit) FROM 'data/dummy/products.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy oltp.warehouses (warehouse_id, warehouse_code, warehouse_name, city) FROM 'data/dummy/warehouses.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy oltp.customers (customer_id, customer_name, address) FROM 'data/dummy/customers.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy oltp.purchase_orders (purchase_order_id, supplier_id, warehouse_id, order_date, status) FROM 'data/dummy/purchase_orders.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy oltp.purchase_order_items (purchase_order_item_id, purchase_order_id, product_id, ordered_quantity, unit_price) FROM 'data/dummy/purchase_order_items.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy oltp.goods_receipts (goods_receipt_id, purchase_order_id, received_at, posted_at) FROM 'data/dummy/goods_receipts.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy oltp.goods_receipt_items (goods_receipt_item_id, goods_receipt_id, purchase_order_item_id, received_quantity) FROM 'data/dummy/goods_receipt_items.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy oltp.sales_orders (sales_order_id, customer_id, warehouse_id, order_date, status, confirmed_at, completed_at) FROM 'data/dummy/sales_orders.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy oltp.sales_order_items (sales_order_item_id, sales_order_id, product_id, ordered_quantity, unit_price) FROM 'data/dummy/sales_order_items.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy oltp.goods_issues (goods_issue_id, sales_order_id, issued_at, posted_at) FROM 'data/dummy/goods_issues.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy oltp.goods_issue_items (goods_issue_item_id, goods_issue_id, sales_order_item_id, issued_quantity) FROM 'data/dummy/goods_issue_items.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy oltp.inventory_movements (inventory_movement_id, goods_receipt_item_id, movement_type, quantity, goods_issue_item_id) FROM 'data/dummy/inventory_movements.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')

-- Lanjutkan ID otomatis setelah ID terakhir dari CSV agar tidak bentrok.
SELECT setval(pg_get_serial_sequence('oltp.suppliers', 'supplier_id'), (SELECT MAX(supplier_id) FROM oltp.suppliers));
SELECT setval(pg_get_serial_sequence('oltp.products', 'product_id'), (SELECT MAX(product_id) FROM oltp.products));
SELECT setval(pg_get_serial_sequence('oltp.warehouses', 'warehouse_id'), (SELECT MAX(warehouse_id) FROM oltp.warehouses));
SELECT setval(pg_get_serial_sequence('oltp.customers', 'customer_id'), (SELECT MAX(customer_id) FROM oltp.customers));
SELECT setval(pg_get_serial_sequence('oltp.purchase_orders', 'purchase_order_id'), (SELECT MAX(purchase_order_id) FROM oltp.purchase_orders));
SELECT setval(pg_get_serial_sequence('oltp.purchase_order_items', 'purchase_order_item_id'), (SELECT MAX(purchase_order_item_id) FROM oltp.purchase_order_items));
SELECT setval(pg_get_serial_sequence('oltp.goods_receipts', 'goods_receipt_id'), (SELECT MAX(goods_receipt_id) FROM oltp.goods_receipts));
SELECT setval(pg_get_serial_sequence('oltp.goods_receipt_items', 'goods_receipt_item_id'), (SELECT MAX(goods_receipt_item_id) FROM oltp.goods_receipt_items));
SELECT setval(pg_get_serial_sequence('oltp.sales_orders', 'sales_order_id'), (SELECT MAX(sales_order_id) FROM oltp.sales_orders));
SELECT setval(pg_get_serial_sequence('oltp.sales_order_items', 'sales_order_item_id'), (SELECT MAX(sales_order_item_id) FROM oltp.sales_order_items));
SELECT setval(pg_get_serial_sequence('oltp.goods_issues', 'goods_issue_id'), (SELECT MAX(goods_issue_id) FROM oltp.goods_issues));
SELECT setval(pg_get_serial_sequence('oltp.goods_issue_items', 'goods_issue_item_id'), (SELECT MAX(goods_issue_item_id) FROM oltp.goods_issue_items));
SELECT setval(pg_get_serial_sequence('oltp.inventory_movements', 'inventory_movement_id'), (SELECT MAX(inventory_movement_id) FROM oltp.inventory_movements));

COMMIT;
