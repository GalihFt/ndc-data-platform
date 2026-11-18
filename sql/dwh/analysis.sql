SELECT * FROM dwh.fact_sales;


-- NUMBER 1
SELECT 
    SUM(fs.sales_amount) AS total_penjualan,
    SUM(fs.qty_sold) AS total_penjualan,
    COUNT(DISTINCT fs.sales_order_id) AS jumlah_so
FROM dwh.fact_sales fs;

-- NUMBER 2
SELECT 
    fs.warehouse_key AS warehouse_code,
    dw.warehouse_name AS warehouse_name,
    SUM(fs.sales_amount) AS total_penjualan,
    SUM(fs.qty_sold) AS total_penjualan,
    COUNT(DISTINCT fs.sales_order_id) AS jumlah_so
FROM dwh.fact_sales fs 
LEFT JOIN dwh.dim_warehouse dw ON fs.warehouse_key = dw.warehouse_key
GROUP BY fs.warehouse_key, dw.warehouse_name
ORDER BY SUM(fs.sales_amount) DESC, fs.warehouse_key;


-- NUMBER 3
SELECT 
    fs.product_key AS product_id,
    dp.product_name,
    dp.category,
    SUM(fs.qty_sold) AS total_unit_terjual,
    SUM(fs.sales_amount) AS total_penjualan
FROM dwh.fact_sales fs
LEFT JOIN dwh.dim_product dp ON dp.product_key = fs.product_key
WHERE extract(MONTH FROM fs.posted_at) = 11
GROUP BY fs.product_key, dp.product_name, dp.category
ORDER BY SUM(fs.qty_sold) DESC, fs.product_key ASC
LIMIT 5;


-- NUMBER 4
-- Satu GR bisa memiliki banyak item, jadi hitung dokumen dengan DISTINCT.
SELECT
    ds.supplier_id,
    ds.supplier_name,
    SUM(fr.qty_received) AS total_unit_diterima,
    SUM(fr.receiving_amount) AS total_nilai_penerimaan,
    COUNT(DISTINCT fr.goods_receipt_id) AS jumlah_gr
FROM dwh.fact_receiving fr
JOIN dwh.dim_supplier ds ON ds.supplier_key = fr.supplier_key
GROUP BY ds.supplier_id, ds.supplier_name
ORDER BY total_nilai_penerimaan DESC, ds.supplier_id ASC;


-- NUMBER 5
-- CASE memisahkan quantity IN dan OUT. Stok fisik = total IN - total OUT.
SELECT
    dw.warehouse_code,
    dp.product_id,
    dp.product_name,
    SUM(CASE WHEN fi.movement_type = 'IN' THEN fi.qty_movement ELSE 0 END) AS total_masuk,
    SUM(CASE WHEN fi.movement_type = 'OUT' THEN fi.qty_movement ELSE 0 END) AS total_keluar,
    SUM(CASE WHEN fi.movement_type = 'IN' THEN fi.qty_movement
             ELSE -fi.qty_movement END) AS stok_fisik
FROM dwh.fact_inventory fi
JOIN dwh.dim_product dp ON dp.product_key = fi.product_key
JOIN dwh.dim_warehouse dw ON dw.warehouse_key = fi.warehouse_key
WHERE dw.warehouse_code = 'WH-SBY'
GROUP BY dw.warehouse_code, dp.product_id, dp.product_name
ORDER BY stok_fisik ASC, dp.product_id ASC;
