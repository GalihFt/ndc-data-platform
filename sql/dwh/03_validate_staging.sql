-- Setiap pemeriksaan harus menghasilkan failures = 0.
-- Python membaca hasil ini dan menghentikan pipeline jika ada masalah.
SELECT 'referensi dan quantity receiving' AS check_name, COUNT(*) AS failures
FROM staging.goods_receipt_items gri
LEFT JOIN staging.goods_receipts gr USING (goods_receipt_id)
LEFT JOIN staging.purchase_order_items poi USING (purchase_order_item_id)
LEFT JOIN staging.purchase_orders po ON po.purchase_order_id = gr.purchase_order_id
LEFT JOIN staging.products p ON p.product_id = poi.product_id
LEFT JOIN staging.warehouses w ON w.warehouse_id = po.warehouse_id
LEFT JOIN staging.suppliers s ON s.supplier_id = po.supplier_id
WHERE gr.goods_receipt_id IS NULL OR gr.posted_at IS NULL
   OR poi.purchase_order_item_id IS NULL OR po.purchase_order_id IS NULL
   OR p.product_id IS NULL OR w.warehouse_id IS NULL OR s.supplier_id IS NULL
   OR poi.purchase_order_id <> gr.purchase_order_id
   OR gri.received_quantity <= 0 OR poi.unit_price < 0
UNION ALL
SELECT 'referensi dan quantity sales', COUNT(*)
FROM staging.goods_issue_items gii
LEFT JOIN staging.goods_issues gi USING (goods_issue_id)
LEFT JOIN staging.sales_order_items soi USING (sales_order_item_id)
LEFT JOIN staging.sales_orders so ON so.sales_order_id = gi.sales_order_id
LEFT JOIN staging.products p ON p.product_id = soi.product_id
LEFT JOIN staging.warehouses w ON w.warehouse_id = so.warehouse_id
LEFT JOIN staging.customers c ON c.customer_id = so.customer_id
WHERE gi.goods_issue_id IS NULL OR gi.posted_at IS NULL
   OR soi.sales_order_item_id IS NULL OR so.sales_order_id IS NULL
   OR p.product_id IS NULL OR w.warehouse_id IS NULL OR c.customer_id IS NULL
   OR soi.sales_order_id <> gi.sales_order_id
   OR gii.issued_quantity <> soi.ordered_quantity OR gii.issued_quantity <= 0 OR soi.unit_price < 0
UNION ALL
SELECT 'header posted memiliki item lengkap', COUNT(*)
FROM (
    SELECT gr.goods_receipt_id FROM staging.goods_receipts gr
    WHERE gr.posted_at IS NULL OR NOT EXISTS (
        SELECT 1 FROM staging.goods_receipt_items gri WHERE gri.goods_receipt_id = gr.goods_receipt_id
    )
    UNION ALL
    SELECT gi.goods_issue_id FROM staging.goods_issues gi
    WHERE gi.posted_at IS NULL OR NOT EXISTS (
        SELECT 1 FROM staging.goods_issue_items gii WHERE gii.goods_issue_id = gi.goods_issue_id
    ) OR EXISTS (
        SELECT 1 FROM staging.sales_order_items soi
        WHERE soi.sales_order_id = gi.sales_order_id AND NOT EXISTS (
            SELECT 1 FROM staging.goods_issue_items gii
            WHERE gii.goods_issue_id = gi.goods_issue_id AND gii.sales_order_item_id = soi.sales_order_item_id
        )
    )
) invalid_headers
UNION ALL
SELECT 'total receiving tidak melebihi pesanan', COUNT(*)
FROM (
    SELECT poi.purchase_order_item_id
    FROM staging.purchase_order_items poi
    JOIN staging.goods_receipt_items gri USING (purchase_order_item_id)
    GROUP BY poi.purchase_order_item_id, poi.ordered_quantity
    HAVING SUM(gri.received_quantity) > poi.ordered_quantity
) over_received
UNION ALL
SELECT 'movement sesuai item sumber', COUNT(*)
FROM staging.inventory_movements im
LEFT JOIN staging.goods_receipt_items gri USING (goods_receipt_item_id)
LEFT JOIN staging.goods_issue_items gii USING (goods_issue_item_id)
WHERE im.quantity <= 0 OR im.movement_type NOT IN ('IN', 'OUT')
   OR (im.movement_type = 'IN' AND (
       gri.goods_receipt_item_id IS NULL OR im.goods_issue_item_id IS NOT NULL
       OR im.quantity <> gri.received_quantity))
   OR (im.movement_type = 'OUT' AND (
       gii.goods_issue_item_id IS NULL OR im.goods_receipt_item_id IS NOT NULL
       OR im.quantity <> gii.issued_quantity))
UNION ALL
SELECT 'setiap item posted memiliki tepat satu movement', COUNT(*)
FROM (
    SELECT gri.goods_receipt_item_id
    FROM staging.goods_receipt_items gri
    LEFT JOIN staging.inventory_movements im USING (goods_receipt_item_id)
    GROUP BY gri.goods_receipt_item_id HAVING COUNT(im.inventory_movement_id) <> 1
    UNION ALL
    SELECT gii.goods_issue_item_id
    FROM staging.goods_issue_items gii
    LEFT JOIN staging.inventory_movements im USING (goods_issue_item_id)
    GROUP BY gii.goods_issue_item_id HAVING COUNT(im.inventory_movement_id) <> 1
) invalid_movement_counts;
