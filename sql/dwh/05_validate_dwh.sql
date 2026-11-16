-- FULL JOIN memeriksa baris hilang, tambahan, serta nilai yang berbeda.
-- Bandingkan dengan snapshot staging, bukan OLTP yang bisa terus berubah.
SELECT 'receiving sesuai staging' AS check_name, COUNT(*) AS failures
FROM dwh.fact_receiving f
FULL JOIN staging.goods_receipt_items gri USING (goods_receipt_item_id)
LEFT JOIN staging.goods_receipts gr ON gr.goods_receipt_id = gri.goods_receipt_id
LEFT JOIN staging.purchase_order_items poi USING (purchase_order_item_id)
LEFT JOIN staging.purchase_orders po ON po.purchase_order_id = gr.purchase_order_id
LEFT JOIN dwh.dim_product p ON p.product_key = f.product_key
LEFT JOIN dwh.dim_warehouse w ON w.warehouse_key = f.warehouse_key
LEFT JOIN dwh.dim_supplier s ON s.supplier_key = f.supplier_key
LEFT JOIN dwh.dim_date d ON d.date_key = f.date_key
WHERE f.goods_receipt_item_id IS NULL OR gri.goods_receipt_item_id IS NULL
   OR ROW(f.goods_receipt_id, f.purchase_order_id, p.product_id, w.warehouse_id,
          s.supplier_id, f.posted_at, d.full_date, f.qty_received, f.unit_cost, f.receiving_amount)
      IS DISTINCT FROM
      ROW(gr.goods_receipt_id, po.purchase_order_id, poi.product_id, po.warehouse_id,
          po.supplier_id, gr.posted_at, (gr.posted_at AT TIME ZONE 'Asia/Jakarta')::DATE,
          gri.received_quantity, poi.unit_price, gri.received_quantity * poi.unit_price)
UNION ALL
SELECT 'sales sesuai staging', COUNT(*)
FROM dwh.fact_sales f
FULL JOIN staging.goods_issue_items gii USING (goods_issue_item_id)
LEFT JOIN staging.goods_issues gi ON gi.goods_issue_id = gii.goods_issue_id
LEFT JOIN staging.sales_order_items soi USING (sales_order_item_id)
LEFT JOIN staging.sales_orders so ON so.sales_order_id = gi.sales_order_id
LEFT JOIN dwh.dim_product p ON p.product_key = f.product_key
LEFT JOIN dwh.dim_warehouse w ON w.warehouse_key = f.warehouse_key
LEFT JOIN dwh.dim_customer c ON c.customer_key = f.customer_key
LEFT JOIN dwh.dim_date d ON d.date_key = f.date_key
WHERE f.goods_issue_item_id IS NULL OR gii.goods_issue_item_id IS NULL
   OR ROW(f.goods_issue_id, f.sales_order_id, p.product_id, w.warehouse_id,
          c.customer_id, f.posted_at, d.full_date, f.qty_sold, f.unit_price, f.sales_amount)
      IS DISTINCT FROM
      ROW(gi.goods_issue_id, so.sales_order_id, soi.product_id, so.warehouse_id,
          so.customer_id, gi.posted_at, (gi.posted_at AT TIME ZONE 'Asia/Jakarta')::DATE,
          gii.issued_quantity, soi.unit_price, gii.issued_quantity * soi.unit_price)
UNION ALL
SELECT 'inventory sesuai movement dan konteks sumber', COUNT(*)
FROM dwh.fact_inventory f
FULL JOIN staging.inventory_movements im ON im.inventory_movement_id = f.movement_id
LEFT JOIN staging.goods_receipt_items gri ON gri.goods_receipt_item_id = im.goods_receipt_item_id
LEFT JOIN staging.goods_receipts gr ON gr.goods_receipt_id = gri.goods_receipt_id
LEFT JOIN staging.purchase_order_items poi ON poi.purchase_order_item_id = gri.purchase_order_item_id
LEFT JOIN staging.purchase_orders po ON po.purchase_order_id = gr.purchase_order_id
LEFT JOIN staging.goods_issue_items gii ON gii.goods_issue_item_id = im.goods_issue_item_id
LEFT JOIN staging.goods_issues gi ON gi.goods_issue_id = gii.goods_issue_id
LEFT JOIN staging.sales_order_items soi ON soi.sales_order_item_id = gii.sales_order_item_id
LEFT JOIN staging.sales_orders so ON so.sales_order_id = gi.sales_order_id
LEFT JOIN dwh.dim_product p ON p.product_key = f.product_key
LEFT JOIN dwh.dim_warehouse w ON w.warehouse_key = f.warehouse_key
LEFT JOIN dwh.dim_date d ON d.date_key = f.date_key
WHERE f.movement_id IS NULL OR im.inventory_movement_id IS NULL
   OR ROW(p.product_id, w.warehouse_id, f.movement_type, f.qty_movement,
          f.goods_receipt_id, f.goods_issue_id, f.posted_at, d.full_date)
      IS DISTINCT FROM
      ROW(COALESCE(poi.product_id, soi.product_id), COALESCE(po.warehouse_id, so.warehouse_id),
          im.movement_type, im.quantity, gr.goods_receipt_id, gi.goods_issue_id,
          COALESCE(gr.posted_at, gi.posted_at),
          (COALESCE(gr.posted_at, gi.posted_at) AT TIME ZONE 'Asia/Jakarta')::DATE);
