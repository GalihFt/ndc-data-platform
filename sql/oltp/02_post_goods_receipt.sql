-- Stored procedure ini merupakan jalur pembukuan penerimaan untuk latihan inbound.
-- Jangan mengisi posted_at atau membuat movement inbound secara manual.
-- Panggil dengan CALL oltp.post_goods_receipt(1).
-- Seluruh operasi mengikuti transaksi pemanggil, tanpa COMMIT di tengah proses.
CREATE OR REPLACE PROCEDURE oltp.post_goods_receipt(p_goods_receipt_id BIGINT)
LANGUAGE plpgsql
SET search_path TO oltp, pg_temp
AS $$
DECLARE
    v_receipt oltp.goods_receipts%ROWTYPE;
    v_po oltp.purchase_orders%ROWTYPE;
    v_posted_at TIMESTAMPTZ;
BEGIN
    SELECT * INTO v_receipt
    FROM goods_receipts
    WHERE goods_receipt_id = p_goods_receipt_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Penerimaan % tidak ditemukan', p_goods_receipt_id;
    END IF;

    IF v_receipt.posted_at IS NOT NULL THEN
        RAISE EXCEPTION 'Penerimaan % sudah diposting', p_goods_receipt_id;
    END IF;

    -- Posting untuk PO yang sama diproses bergantian agar tidak over-receive.
    SELECT * INTO v_po
    FROM purchase_orders
    WHERE purchase_order_id = v_receipt.purchase_order_id
    FOR UPDATE;

    IF v_po.status NOT IN ('ORDERED', 'PARTIALLY_RECEIVED') THEN
        RAISE EXCEPTION 'PO dengan status % tidak dapat menerima barang', v_po.status;
    END IF;

    IF (SELECT COUNT(*) FROM goods_receipts
        WHERE purchase_order_id = v_po.purchase_order_id
          AND posted_at IS NOT NULL) >= 2 THEN
        RAISE EXCEPTION 'Maksimal dua penerimaan yang diposting per PO';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM goods_receipt_items
                   WHERE goods_receipt_id = p_goods_receipt_id) THEN
        RAISE EXCEPTION 'Penerimaan harus memiliki minimal satu item';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM goods_receipt_items gri
        JOIN purchase_order_items poi USING (purchase_order_item_id)
        WHERE gri.goods_receipt_id = p_goods_receipt_id
          AND poi.purchase_order_id <> v_po.purchase_order_id
    ) THEN
        RAISE EXCEPTION 'Item penerimaan harus berasal dari PO yang sama';
    END IF;

    -- Hitung hanya penerimaan yang sudah diposting dan dokumen saat ini.
    IF EXISTS (
        SELECT 1
        FROM purchase_order_items poi
        JOIN goods_receipt_items gri USING (purchase_order_item_id)
        JOIN goods_receipts gr USING (goods_receipt_id)
        WHERE poi.purchase_order_id = v_po.purchase_order_id
          AND (gr.posted_at IS NOT NULL OR gr.goods_receipt_id = p_goods_receipt_id)
        GROUP BY poi.purchase_order_item_id, poi.ordered_quantity
        HAVING SUM(gri.received_quantity) > poi.ordered_quantity
    ) THEN
        RAISE EXCEPTION 'Jumlah diterima melebihi jumlah yang dipesan';
    END IF;

    INSERT INTO inventory_movements (goods_receipt_item_id, movement_type, quantity)
    SELECT goods_receipt_item_id, 'IN', received_quantity
    FROM goods_receipt_items
    WHERE goods_receipt_id = p_goods_receipt_id;

    v_posted_at := clock_timestamp();
    UPDATE goods_receipts
    SET posted_at = v_posted_at
    WHERE goods_receipt_id = p_goods_receipt_id;

    UPDATE purchase_orders
    SET status = CASE WHEN EXISTS (
        SELECT 1
        FROM purchase_order_items poi
        WHERE poi.purchase_order_id = v_po.purchase_order_id
          AND poi.ordered_quantity > (
              SELECT COALESCE(SUM(gri.received_quantity), 0)
              FROM goods_receipt_items gri
              JOIN goods_receipts gr USING (goods_receipt_id)
              WHERE gri.purchase_order_item_id = poi.purchase_order_item_id
                AND gr.posted_at IS NOT NULL
          )
    ) THEN 'PARTIALLY_RECEIVED' ELSE 'RECEIVED' END
    WHERE purchase_order_id = v_po.purchase_order_id;

END;
$$;
