-- CERITA LATIHAN: barang masuk 100 PCS, lalu dijual 10 PCS.
-- Produk 1 = Beras Premium 5 kg, gudang 1 = WH-SBY.
-- Jalankan SATU LANGKAH setiap kali pada database ndc_oltp, dengan auto-commit aktif.
-- ID contoh di bawah berlaku jika data masih snapshot dummy dan sequence sesuai import.
-- Selalu lihat hasil RETURNING. Jika berbeda, ganti ID pada langkah berikutnya.
-- Jika latihan sebelumnya sudah dijalankan, gunakan ID dan saldo aktual; jangan hapus data lama.

-- 1. Sebelum mulai, berapa stok beras di Surabaya?
-- Dari dummy: fisik 484, reservasi 9, tersedia 475.
SELECT * FROM oltp.inventory_stock
WHERE product_id = 1 AND warehouse_id = 1;

-- INBOUND: kita membeli 100 PCS beras dari supplier 1.

-- 2. Buat pesanan pembelian (PO). Catat purchase_order_id dari RETURNING.
-- Contoh hasil: 31, status DRAFT.
SELECT * FROM oltp.purchase_orders;

INSERT INTO oltp.purchase_orders (supplier_id, warehouse_id, order_date)
VALUES (1, 1, CURRENT_DATE)
RETURNING purchase_order_id, status;

-- 3. Isi pesanan: produk 1, sebanyak 100 PCS, harga beli Rp10.000/PCS.
-- Ganti 31 dengan ID PO hasil langkah 2.
-- Catat purchase_order_item_id. Contoh hasil: 151.
INSERT INTO oltp.purchase_order_items
    (purchase_order_id, product_id, ordered_quantity, unit_price)
VALUES (31, 1, 100, 10000)
RETURNING purchase_order_item_id;

SELECT * FROM oltp.purchase_order_items;

-- 4. Pesanan sudah diperiksa dan dikirim ke supplier: jadikan ORDERED.
UPDATE oltp.purchase_orders
SET status = 'ORDERED'
WHERE purchase_order_id = 31 AND status = 'DRAFT'
RETURNING purchase_order_id, status;

SELECT * FROM oltp.purchase_orders;

-- 5. Barang datang. Buat dokumen penerimaan (GR).
-- Catat goods_receipt_id. Contoh hasil: 46. posted_at masih NULL (draft).
INSERT INTO oltp.goods_receipts (purchase_order_id, received_at)
VALUES (31, CURRENT_TIMESTAMP)
RETURNING goods_receipt_id, posted_at;

-- 6. Catat barang yang benar-benar diterima: 100 PCS dari item PO 151.
INSERT INTO oltp.goods_receipt_items
    (goods_receipt_id, purchase_order_item_id, received_quantity)
VALUES (46, 151, 100);

SELECT * FROM oltp.goods_receipt_items;
SELECT * FROM oltp.goods_receipts;

-- 7. Cek sebelum posting: stok masih sama! GR draft belum menambah stok.
SELECT * FROM oltp.inventory_stock
WHERE product_id = 1 AND warehouse_id = 1;

-- 8. Bukukan penerimaan. Jangan UPDATE posted_at secara manual.
CALL oltp.post_goods_receipt(46);

-- 9. Lihat hasil posting: GR punya posted_at, PO menjadi RECEIVED.
SELECT * FROM oltp.goods_receipts WHERE goods_receipt_id = 46;
SELECT * FROM oltp.purchase_orders WHERE purchase_order_id = 31;

-- Stok: fisik 584, reservasi 9, tersedia 575 (bertambah 100).
SELECT * FROM oltp.inventory_stock
WHERE product_id = 1 AND warehouse_id = 1;

-- Bukti asal stok masuk: GR 46 -> item GR -> movement IN sebanyak 100.
SELECT gri.goods_receipt_id, gri.purchase_order_item_id,
       im.inventory_movement_id, im.movement_type, im.quantity
FROM oltp.goods_receipt_items gri
JOIN oltp.inventory_movements im USING (goods_receipt_item_id)
WHERE gri.goods_receipt_id = 46;

-- OUTBOUND: customer 1 memesan 10 PCS beras dari gudang yang sama.

-- 10. Buat pesanan penjualan (SO).
-- Catat sales_order_id. Contoh hasil: 121, status PENDING.
INSERT INTO oltp.sales_orders (customer_id, warehouse_id, order_date)
VALUES (1, 1, CURRENT_DATE)
RETURNING sales_order_id, status;

-- 11. Isi pesanan: produk 1, sebanyak 10 PCS, harga jual Rp12.500/PCS.
INSERT INTO oltp.sales_order_items
    (sales_order_id, product_id, ordered_quantity, unit_price)
VALUES (121, 1, 10, 12500);

SELECT * FROM oltp.sales_order_items;
SELECT * FROM oltp.sales_orders;

-- 12. Konfirmasi pesanan: stok direservasi, fisik belum berkurang.
CALL oltp.confirm_sales_order(121);

-- Hasil: CONFIRMED. Fisik 584, reservasi 19, tersedia 565.
SELECT * FROM oltp.sales_orders WHERE sales_order_id = 121;
SELECT * FROM oltp.inventory_stock
WHERE product_id = 1 AND warehouse_id = 1;

-- 13. Siapkan pengiriman: buat dokumen pengeluaran (GI).
-- Catat goods_issue_id. Contoh hasil: 109, posted_at masih NULL.
INSERT INTO oltp.goods_issues (sales_order_id, issued_at)
VALUES (121, CURRENT_TIMESTAMP)
RETURNING goods_issue_id, posted_at;

-- 14. Isi GI dengan seluruh item SO dan jumlah yang sama (pengiriman penuh).
INSERT INTO oltp.goods_issue_items
    (goods_issue_id, sales_order_item_id, issued_quantity)
SELECT 109, sales_order_item_id, ordered_quantity
FROM oltp.sales_order_items
WHERE sales_order_id = 121;

-- Cek sebelum posting: GI masih draft, fisik tetap 584, reservasi 19, tersedia 565.
SELECT * FROM oltp.inventory_stock
WHERE product_id = 1 AND warehouse_id = 1;

-- 15. Barang dikirim: posting GI.
CALL oltp.post_goods_issue(109);

-- Hasil: GI punya posted_at, SO SHIPPED.
SELECT * FROM oltp.goods_issues WHERE goods_issue_id = 109;
SELECT * FROM oltp.sales_orders WHERE sales_order_id = 121;

-- Fisik turun 10 menjadi 574. Reservasi kembali 9, tersedia tetap 565.
SELECT * FROM oltp.inventory_stock
WHERE product_id = 1 AND warehouse_id = 1;

-- Bukti asal stok keluar: GI 109 -> item SO -> movement OUT sebanyak 10.
SELECT gii.goods_issue_id, gii.sales_order_item_id,
       im.inventory_movement_id, im.movement_type, im.quantity
FROM oltp.goods_issue_items gii
JOIN oltp.inventory_movements im USING (goods_issue_item_id)
WHERE gii.goods_issue_id = 109;

-- 16. Pengiriman selesai. Tidak ada pengurangan stok lagi.
CALL oltp.complete_sales_order(121);
SELECT * FROM oltp.sales_orders;

SELECT * FROM oltp.sales_orders WHERE sales_order_id = 121;
SELECT * FROM oltp.inventory_stock
WHERE product_id = 1 AND warehouse_id = 1;

-- Query SELECT di atas bisa dijalankan lagi kapan pun untuk menelusuri dokumen.
-- Dokumen dan movement tersimpan dengan auto-commit aktif.
-- Jangan panggil ulang posting dokumen yang sudah posted.
-- Saldo contoh berlaku jika dimulai dari dummy dan tidak ada transaksi lain.
-- Saldo akhir dibanding awal: fisik +90, reservasi tetap, tersedia +90.
-- Reservasi 9 yang tersisa berasal dari SO 34 pada data dummy.
