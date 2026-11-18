# Latihan Query DWH

Latihan berikut dikerjakan setelah pipeline ELT berhasil dijalankan. Hubungkan
editor SQL ke database `ndc_dwh`, lalu tulis jawaban di
[`sql/dwh/analysis.sql`](../sql/dwh/analysis.sql), dengan komentar nomor soal.
Gunakan tabel schema `dwh` saja. Cukup gunakan query `SELECT`; tidak perlu
mengubah data atau menjalankan transaksi inbound/outbound.

Kerjakan berurutan. Setiap soal menyebutkan bentuk hasil yang diminta,
tanpa menyediakan query jawaban.

### Soal 1 — Berapa total penjualan yang sudah tercatat?

Manajer ingin melihat ringkasan seluruh penjualan yang sudah masuk DWH.
Hitung total nilai penjualan, total unit terjual, dan jumlah SO berbeda
yang menyumbang penjualan tersebut.

- Tabel awal: `dwh.fact_sales`.
- Kolom hasil: `total_penjualan`, `total_unit_terjual`, `jumlah_so`.
- Hasil yang diminta: satu baris ringkasan.
- Ingat: satu baris fact adalah satu item pengiriman. Satu SO dapat muncul
  pada beberapa baris, tetapi harus dihitung sebagai satu pesanan.

### Soal 2 — Gudang mana yang menghasilkan penjualan terbesar?

Buat ringkasan penjualan per gudang, lalu urutkan dari nilai penjualan
terbesar. Jika nilainya sama, urutkan berdasarkan kode gudang secara menaik.

- Tabel awal: `dwh.fact_sales` dan `dwh.dim_warehouse`.
- Kolom hasil: `warehouse_code`, `warehouse_name`, `total_penjualan`,
  `total_unit_terjual`, `jumlah_so`.
- Hasil yang diminta: satu baris untuk setiap gudang yang memiliki penjualan.
- Hubungkan fact dan dimension melalui `warehouse_key`.

### Soal 3 — Apa lima produk paling banyak terjual pada November 2026?

Tim penjualan ingin mengetahui lima produk dengan jumlah unit terjual
tertinggi pada November 2026, dari seluruh gudang.

- Tabel awal: `dwh.fact_sales`, `dwh.dim_product`, dan `dwh.dim_date`.
- Kolom hasil: `product_id`, `product_name`, `category`,
  `total_unit_terjual`, `total_penjualan`.
- Hasil yang diminta: maksimal lima baris, satu baris per produk.
- Gunakan tahun dan bulan dari dimension tanggal untuk memilih periode.
- Urutkan berdasarkan total unit menurun; jika sama, gunakan `product_id`
  menaik agar hasilnya konsisten.

### Soal 4 — Berapa banyak barang diterima dari setiap supplier?

Tim purchasing ingin mengetahui kontribusi setiap supplier terhadap
penerimaan barang di seluruh gudang. Tampilkan jumlah unit diterima,
nilai penerimaan, dan jumlah dokumen GR berbeda untuk tiap supplier.

- Tabel awal: `dwh.fact_receiving` dan `dwh.dim_supplier`.
- Kolom hasil: `supplier_id`, `supplier_name`, `total_unit_diterima`,
  `total_nilai_penerimaan`, `jumlah_gr`.
- Hasil yang diminta: satu baris untuk setiap supplier yang memiliki penerimaan.
- Urutkan berdasarkan nilai penerimaan menurun, lalu `supplier_id` menaik.
- Satu GR dapat memiliki beberapa item; jumlah dokumen berbeda dari jumlah
  baris fact.

### Soal 5 — Berapa stok fisik setiap produk di WH-SBY?

Kepala gudang Surabaya ingin melihat saldo stok fisik dari seluruh movement
yang sudah masuk DWH. Tampilkan total barang masuk, total barang keluar,
dan saldo akhirnya untuk setiap produk yang memiliki movement di `WH-SBY`.

- Tabel awal: `dwh.fact_inventory`, `dwh.dim_product`, dan `dwh.dim_warehouse`.
- Kolom hasil: `warehouse_code`, `product_id`, `product_name`,
  `total_masuk`, `total_keluar`, `stok_fisik`.
- Hasil yang diminta: satu baris per produk di gudang tersebut.
- `qty_movement` selalu positif. Bedakan barang masuk dan keluar menggunakan
  `movement_type`, lalu hitung saldo sebagai total masuk dikurangi total keluar.
- Urutkan berdasarkan stok fisik terkecil, lalu `product_id` menaik.
- Yang dihitung adalah stok fisik. Reservasi belum disimpan dalam fact ini,
  sehingga hasilnya belum merupakan stok tersedia.

**Catatan data latihan:** dummy awal hanya mencakup 14 November 2026.
Soal 3 tetap bisa dikerjakan, tetapi belum menunjukkan variasi antartanggal.
Jika transaksi OLTP berubah, jalankan ELT lagi agar jawaban memakai data terbaru.
