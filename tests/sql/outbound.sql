-- Jalankan pada database latihan setelah SQL 01-04. Tidak menyimpan fixture.
BEGIN;
SET LOCAL search_path TO oltp;

DO $$
DECLARE
    v_supplier BIGINT;
    v_customer BIGINT;
    v_warehouse BIGINT;
    v_other_warehouse BIGINT;
    v_a BIGINT;
    v_b BIGINT;
    v_po BIGINT;
    v_poi_a BIGINT;
    v_poi_b BIGINT;
    v_gr BIGINT;
    v_so BIGINT;
    v_other_so BIGINT;
    v_soi_a BIGINT;
    v_soi_b BIGINT;
    v_other_item BIGINT;
    v_gi BIGINT;
    v_rejected BOOLEAN;
BEGIN
    INSERT INTO suppliers (supplier_name) VALUES ('Test inbound') RETURNING supplier_id INTO v_supplier;
    INSERT INTO customers (customer_name, address) VALUES ('Test outbound', 'Alamat test') RETURNING customer_id INTO v_customer;
    INSERT INTO warehouses (warehouse_code, warehouse_name, city)
    VALUES ('T-' || substr(md5(random()::TEXT), 1, 12), 'Test', 'Test') RETURNING warehouse_id INTO v_warehouse;
    INSERT INTO warehouses (warehouse_code, warehouse_name, city)
    VALUES ('T-' || substr(md5(random()::TEXT), 1, 12), 'Test lain', 'Test') RETURNING warehouse_id INTO v_other_warehouse;
    INSERT INTO products (product_name, category, unit) VALUES ('Test A', 'Test', 'PCS') RETURNING product_id INTO v_a;
    INSERT INTO products (product_name, category, unit) VALUES ('Test B', 'Test', 'PCS') RETURNING product_id INTO v_b;
    INSERT INTO purchase_orders (supplier_id, warehouse_id, order_date, status)
    VALUES (v_supplier, v_warehouse, CURRENT_DATE, 'ORDERED') RETURNING purchase_order_id INTO v_po;
    INSERT INTO purchase_order_items (purchase_order_id, product_id, ordered_quantity, unit_price)
    VALUES (v_po, v_a, 100, 10) RETURNING purchase_order_item_id INTO v_poi_a;
    INSERT INTO purchase_order_items (purchase_order_id, product_id, ordered_quantity, unit_price)
    VALUES (v_po, v_b, 50, 10) RETURNING purchase_order_item_id INTO v_poi_b;
    INSERT INTO goods_receipts (purchase_order_id, received_at)
    VALUES (v_po, clock_timestamp()) RETURNING goods_receipt_id INTO v_gr;
    INSERT INTO goods_receipt_items (goods_receipt_id, purchase_order_item_id, received_quantity)
    VALUES (v_gr, v_poi_a, 100), (v_gr, v_poi_b, 50);
    CALL post_goods_receipt(v_gr);

    INSERT INTO sales_orders (customer_id, warehouse_id, order_date)
    VALUES (v_customer, v_warehouse, CURRENT_DATE) RETURNING sales_order_id INTO v_so;
    INSERT INTO sales_order_items (sales_order_id, product_id, ordered_quantity, unit_price)
    VALUES (v_so, v_a, 30, 20) RETURNING sales_order_item_id INTO v_soi_a;
    INSERT INTO sales_order_items (sales_order_id, product_id, ordered_quantity, unit_price)
    VALUES (v_so, v_b, 10, 20) RETURNING sales_order_item_id INTO v_soi_b;
    CALL confirm_sales_order(v_so);
    IF NOT EXISTS (SELECT 1 FROM inventory_stock WHERE product_id = v_a AND warehouse_id = v_warehouse
                   AND physical_stock = 100 AND reserved_stock = 30 AND available_stock = 70) THEN
        RAISE EXCEPTION 'FAIL: saldo setelah konfirmasi';
    END IF;

    -- SO lain tidak boleh mengambil stok yang sudah direservasi.
    INSERT INTO sales_orders (customer_id, warehouse_id, order_date)
    VALUES (v_customer, v_warehouse, CURRENT_DATE) RETURNING sales_order_id INTO v_other_so;
    INSERT INTO sales_order_items (sales_order_id, product_id, ordered_quantity, unit_price)
    VALUES (v_other_so, v_a, 80, 20) RETURNING sales_order_item_id INTO v_other_item;
    v_rejected := FALSE;
    BEGIN
        CALL confirm_sales_order(v_other_so);
    EXCEPTION WHEN raise_exception THEN v_rejected := TRUE;
    END;
    IF NOT v_rejected OR (SELECT status FROM sales_orders WHERE sales_order_id = v_other_so) <> 'PENDING' THEN
        RAISE EXCEPTION 'FAIL: konfirmasi stok kurang harus ditolak tanpa perubahan status';
    END IF;

    INSERT INTO goods_issues (sales_order_id, issued_at)
    VALUES (v_so, clock_timestamp()) RETURNING goods_issue_id INTO v_gi;
    INSERT INTO goods_issue_items (goods_issue_id, sales_order_item_id, issued_quantity)
    VALUES (v_gi, v_soi_a, 30);
    v_rejected := FALSE;
    BEGIN
        CALL post_goods_issue(v_gi);
    EXCEPTION WHEN raise_exception THEN v_rejected := TRUE;
    END;
    IF NOT v_rejected OR EXISTS (SELECT 1 FROM goods_issues WHERE goods_issue_id = v_gi AND posted_at IS NOT NULL)
       OR EXISTS (SELECT 1 FROM inventory_movements im JOIN goods_issue_items gii USING (goods_issue_item_id)
                  WHERE gii.goods_issue_id = v_gi) THEN
        RAISE EXCEPTION 'FAIL: partial shipment harus ditolak tanpa movement';
    END IF;

    -- Tambahan item dari SO lain harus ditolak.
    INSERT INTO goods_issue_items (goods_issue_id, sales_order_item_id, issued_quantity)
    VALUES (v_gi, v_other_item, 80), (v_gi, v_soi_b, 10);
    v_rejected := FALSE;
    BEGIN
        CALL post_goods_issue(v_gi);
    EXCEPTION WHEN raise_exception THEN v_rejected := TRUE;
    END;
    IF NOT v_rejected THEN RAISE EXCEPTION 'FAIL: item dari SO lain'; END IF;
    DELETE FROM goods_issue_items WHERE goods_issue_id = v_gi AND sales_order_item_id = v_other_item;

    CALL post_goods_issue(v_gi);
    IF (SELECT status FROM sales_orders WHERE sales_order_id = v_so) <> 'SHIPPED'
       OR NOT EXISTS (SELECT 1 FROM goods_issues WHERE goods_issue_id = v_gi AND posted_at IS NOT NULL)
       OR NOT EXISTS (SELECT 1 FROM inventory_stock WHERE product_id = v_a AND warehouse_id = v_warehouse
                      AND physical_stock = 70 AND reserved_stock = 0 AND available_stock = 70)
       OR NOT EXISTS (SELECT 1 FROM inventory_stock WHERE product_id = v_b AND warehouse_id = v_warehouse
                      AND physical_stock = 40 AND reserved_stock = 0) THEN
        RAISE EXCEPTION 'FAIL: saldo/status setelah posting GI';
    END IF;

    v_rejected := FALSE;
    BEGIN
        CALL post_goods_issue(v_gi);
    EXCEPTION WHEN raise_exception THEN v_rejected := TRUE;
    END;
    IF NOT v_rejected OR (SELECT COUNT(*) FROM inventory_movements im
                          JOIN goods_issue_items gii USING (goods_issue_item_id)
                          WHERE gii.goods_issue_id = v_gi) <> 2 THEN
        RAISE EXCEPTION 'FAIL: posting ulang menghasilkan duplikasi';
    END IF;
    v_rejected := FALSE;
    BEGIN
        CALL cancel_sales_order(v_so);
    EXCEPTION WHEN raise_exception THEN v_rejected := TRUE;
    END;
    IF NOT v_rejected THEN RAISE EXCEPTION 'FAIL: pembatalan setelah pengiriman'; END IF;
    CALL complete_sales_order(v_so);
    IF NOT EXISTS (SELECT 1 FROM sales_orders WHERE sales_order_id = v_so
                   AND status = 'COMPLETED' AND completed_at IS NOT NULL) THEN
        RAISE EXCEPTION 'FAIL: penyelesaian SO';
    END IF;

    -- Pembatalan SO confirmed melepas reservasi tanpa mengurangi fisik.
    UPDATE sales_order_items SET ordered_quantity = 20 WHERE sales_order_item_id = v_other_item;
    CALL confirm_sales_order(v_other_so);
    CALL cancel_sales_order(v_other_so);
    IF NOT EXISTS (SELECT 1 FROM inventory_stock WHERE product_id = v_a AND warehouse_id = v_warehouse
                   AND physical_stock = 70 AND reserved_stock = 0 AND available_stock = 70) THEN
        RAISE EXCEPTION 'FAIL: saldo setelah pembatalan';
    END IF;

    -- Gudang lain tidak boleh memakai stok gudang asal.
    INSERT INTO sales_orders (customer_id, warehouse_id, order_date)
    VALUES (v_customer, v_other_warehouse, CURRENT_DATE) RETURNING sales_order_id INTO v_other_so;
    INSERT INTO sales_order_items (sales_order_id, product_id, ordered_quantity, unit_price)
    VALUES (v_other_so, v_a, 1, 20);
    v_rejected := FALSE;
    BEGIN
        CALL confirm_sales_order(v_other_so);
    EXCEPTION WHEN raise_exception THEN v_rejected := TRUE;
    END;
    IF NOT v_rejected THEN RAISE EXCEPTION 'FAIL: stok antar-gudang tercampur'; END IF;
    RAISE NOTICE 'PASS: inbound, reservasi, penolakan stok/partial/salah SO, posting, duplikasi, pembatalan, completion, dan isolasi gudang';
END;
$$;

ROLLBACK;
