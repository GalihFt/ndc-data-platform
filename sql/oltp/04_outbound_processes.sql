-- Semua procedure mengikuti transaksi pemanggil, tanpa COMMIT internal.
-- Gunakan READ COMMITTED. Kunci per gudang menyederhanakan pengamanan stok
-- antar-procedure; semua konfirmasi/pengiriman gudang yang sama bergantian.
BEGIN;

CREATE OR REPLACE PROCEDURE oltp.confirm_sales_order(p_sales_order_id BIGINT)
LANGUAGE plpgsql
SET search_path TO oltp, pg_temp
AS $$
DECLARE
    v_so oltp.sales_orders%ROWTYPE;
BEGIN
    SELECT * INTO v_so FROM sales_orders
    WHERE sales_order_id = p_sales_order_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'SO % tidak ditemukan', p_sales_order_id;
    END IF;
    IF v_so.status <> 'PENDING' THEN
        RAISE EXCEPTION 'Hanya SO PENDING yang dapat dikonfirmasi';
    END IF;

    PERFORM 1 FROM warehouses WHERE warehouse_id = v_so.warehouse_id FOR UPDATE;

    IF NOT EXISTS (SELECT 1 FROM sales_order_items WHERE sales_order_id = p_sales_order_id) THEN
        RAISE EXCEPTION 'SO harus memiliki minimal satu item';
    END IF;
    IF EXISTS (
        SELECT 1 FROM sales_order_items soi
        JOIN inventory_stock s ON s.product_id = soi.product_id
                              AND s.warehouse_id = v_so.warehouse_id
        WHERE soi.sales_order_id = p_sales_order_id
          AND soi.ordered_quantity > s.available_stock
    ) THEN
        RAISE EXCEPTION 'Stok tersedia tidak cukup untuk seluruh item SO';
    END IF;

    UPDATE sales_orders SET status = 'CONFIRMED', confirmed_at = clock_timestamp()
    WHERE sales_order_id = p_sales_order_id;
END;
$$;

CREATE OR REPLACE PROCEDURE oltp.post_goods_issue(p_goods_issue_id BIGINT)
LANGUAGE plpgsql
SET search_path TO oltp, pg_temp
AS $$
DECLARE
    v_gi oltp.goods_issues%ROWTYPE;
    v_so oltp.sales_orders%ROWTYPE;
BEGIN
    SELECT * INTO v_gi FROM goods_issues
    WHERE goods_issue_id = p_goods_issue_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'GI % tidak ditemukan', p_goods_issue_id;
    END IF;
    IF v_gi.posted_at IS NOT NULL THEN
        RAISE EXCEPTION 'GI % sudah diposting', p_goods_issue_id;
    END IF;

    SELECT * INTO v_so FROM sales_orders
    WHERE sales_order_id = v_gi.sales_order_id FOR UPDATE;
    IF v_so.status <> 'CONFIRMED' THEN
        RAISE EXCEPTION 'Posting GI hanya diperbolehkan untuk SO CONFIRMED';
    END IF;

    PERFORM 1 FROM warehouses WHERE warehouse_id = v_so.warehouse_id FOR UPDATE;

    IF NOT EXISTS (SELECT 1 FROM sales_order_items WHERE sales_order_id = v_so.sales_order_id) THEN
        RAISE EXCEPTION 'SO harus memiliki minimal satu item';
    END IF;
    IF EXISTS (
        SELECT 1 FROM goods_issue_items gii
        JOIN sales_order_items soi USING (sales_order_item_id)
        WHERE gii.goods_issue_id = p_goods_issue_id
          AND soi.sales_order_id <> v_so.sales_order_id
    ) THEN
        RAISE EXCEPTION 'Item GI harus berasal dari SO yang sama';
    END IF;
    IF EXISTS (
        SELECT 1 FROM sales_order_items soi
        LEFT JOIN goods_issue_items gii
          ON gii.sales_order_item_id = soi.sales_order_item_id
         AND gii.goods_issue_id = p_goods_issue_id
        WHERE soi.sales_order_id = v_so.sales_order_id
          AND (gii.goods_issue_item_id IS NULL OR gii.issued_quantity <> soi.ordered_quantity)
    ) THEN
        RAISE EXCEPTION 'GI harus mencakup seluruh item dan jumlah SO; partial shipment tidak diperbolehkan';
    END IF;
    IF EXISTS (
        SELECT 1 FROM sales_order_items soi
        JOIN inventory_stock s ON s.product_id = soi.product_id
                              AND s.warehouse_id = v_so.warehouse_id
        WHERE soi.sales_order_id = v_so.sales_order_id
          AND (s.physical_stock < soi.ordered_quantity OR s.available_stock < 0)
    ) THEN
        RAISE EXCEPTION 'Stok fisik atau saldo reservasi tidak mencukupi';
    END IF;

    INSERT INTO inventory_movements (goods_issue_item_id, movement_type, quantity)
    SELECT goods_issue_item_id, 'OUT', issued_quantity
    FROM goods_issue_items WHERE goods_issue_id = p_goods_issue_id;

    UPDATE goods_issues SET posted_at = clock_timestamp()
    WHERE goods_issue_id = p_goods_issue_id;
    -- Perubahan status sekaligus melepas reservasi yang dihitung oleh view.
    UPDATE sales_orders SET status = 'SHIPPED'
    WHERE sales_order_id = v_so.sales_order_id;
END;
$$;

CREATE OR REPLACE PROCEDURE oltp.cancel_sales_order(p_sales_order_id BIGINT)
LANGUAGE plpgsql
SET search_path TO oltp, pg_temp
AS $$
DECLARE
    v_so oltp.sales_orders%ROWTYPE;
BEGIN
    SELECT * INTO v_so FROM sales_orders
    WHERE sales_order_id = p_sales_order_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'SO % tidak ditemukan', p_sales_order_id;
    END IF;
    IF v_so.status NOT IN ('PENDING', 'CONFIRMED') THEN
        RAISE EXCEPTION 'Pembatalan hanya untuk SO PENDING atau CONFIRMED';
    END IF;
    IF EXISTS (SELECT 1 FROM goods_issues
               WHERE sales_order_id = p_sales_order_id AND posted_at IS NOT NULL) THEN
        RAISE EXCEPTION 'SO yang sudah memiliki GI posted tidak dapat dibatalkan';
    END IF;
    UPDATE sales_orders SET status = 'CANCELLED'
    WHERE sales_order_id = p_sales_order_id;
END;
$$;

CREATE OR REPLACE PROCEDURE oltp.complete_sales_order(p_sales_order_id BIGINT)
LANGUAGE plpgsql
SET search_path TO oltp, pg_temp
AS $$
DECLARE
    v_so oltp.sales_orders%ROWTYPE;
BEGIN
    SELECT * INTO v_so FROM sales_orders
    WHERE sales_order_id = p_sales_order_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'SO % tidak ditemukan', p_sales_order_id;
    END IF;
    IF v_so.status <> 'SHIPPED' THEN
        RAISE EXCEPTION 'Hanya SO SHIPPED yang dapat diselesaikan';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM goods_issues
                   WHERE sales_order_id = p_sales_order_id AND posted_at IS NOT NULL) THEN
        RAISE EXCEPTION 'SO harus memiliki GI yang sudah diposting';
    END IF;
    UPDATE sales_orders SET status = 'COMPLETED', completed_at = clock_timestamp()
    WHERE sales_order_id = p_sales_order_id;
END;
$$;

COMMIT;
