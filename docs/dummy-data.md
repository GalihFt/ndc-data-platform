# Data dummy NDC

Data awal tersedia sebagai **13 file CSV**, satu file untuk setiap tabel,
di [data/dummy](../data/dummy). CSV merupakan snapshot lengkap: master,
dokumen, status, timestamp, dan inventory movement sudah saling sesuai.
Tidak ada data sengaja rusak atau skenario error yang dimasukkan.

## Cara memasukkan

1. Hubungkan ke database `ndc_oltp`.
2. Pastikan file `01` sampai `04` sudah dijalankan dan seluruh 13 tabel OLTP kosong.
3. Buka terminal PowerShell di root repo, lalu jalankan:

```powershell
psql -U postgres -d ndc_oltp -f sql/oltp/05_import_dummy.sql
```

Jika `psql` belum ada di PATH, contoh untuk PostgreSQL 18:

```powershell
& 'C:\Program Files\PostgreSQL\18\bin\psql.exe' -U postgres -d ndc_oltp -f sql/oltp/05_import_dummy.sql
```

Sesuaikan versi instalasi, user, host, dan port. Password dimasukkan melalui
prompt psql jika diminta; tidak disimpan di repo.

[05_import_dummy.sql](../sql/oltp/05_import_dummy.sql) menggunakan perintah
client psql `\copy`. Script ini **bukan SQL biasa untuk tombol Execute
Query** di editor database. Path CSV relatif terhadap working directory,
sehingga perintah terminal harus dijalankan dari root repo. `\copy` membaca
file dari komputer client dan tidak memerlukan akses file pada server database.

Urutan import mengikuti FK: master, PO/detail, GR/detail, SO/detail,
GI/detail, lalu movement. ID eksplisit pada CSV diterima oleh COPY meskipun PK
menggunakan `GENERATED ALWAYS AS IDENTITY`. Setelah CSV diimpor,
sequence pada seluruh 13 tabel disesuaikan dengan ID maksimum. INSERT berikutnya
bisa kembali memakai ID otomatis tanpa bentrok.

Import ini menganggap CSV sudah valid. Script hanya memuat data dan
menyesuaikan sequence ID; tidak ada loop validasi, pemeriksaan jumlah baris,
atau pemanggilan file validasi tambahan. PK, FK, UNIQUE, dan CHECK pada tabel
tetap berlaku sebagai aturan database.

Gunakan tabel kosong dan jalankan sekali. Import ulang akan bentrok dengan ID
yang sudah ada. Script tidak menghapus atau memperbarui data lama. `BEGIN` dan
`COMMIT` menyimpan seluruh import dalam satu transaksi; psql berhenti saat ada
error. Penyesuaian sequence tetap diperlukan agar INSERT berikutnya bisa
menghasilkan ID otomatis tanpa bentrok. Sequence dapat memiliki celah nomor.

## Format CSV

- UTF-8, delimiter koma, baris pertama berisi nama kolom.
- Urutan kolom sesuai daftar eksplisit pada script import.
- Teks yang mengandung koma diberi tanda kutip sesuai format CSV.
- Field kosong tanpa kutip berarti SQL NULL, misalnya `posted_at` draft.
- Tanggal memakai `YYYY-MM-DD`; timestamp menyertakan offset `+07`.
- ID adalah angka; FK merujuk angka yang ada di CSV tabel asal.

Jangan mengubah urutan atau nama kolom tanpa menyesuaikan script import.
CSV bukan spreadsheet dengan formula; nilainya langsung menjadi data database.

## Isi dataset

| Tabel | Jumlah baris |
|---|---:|
| suppliers | 8 |
| products | 50 |
| warehouses | 3 |
| customers | 100 |
| purchase_orders | 30 |
| purchase_order_items | 150 |
| goods_receipts | 45 |
| goods_receipt_items | 225 |
| sales_orders | 120 |
| sales_order_items | 360 |
| goods_issues | 108 |
| goods_issue_items | 324 |
| inventory_movements | 513 |

Gudang menggunakan kode `WH-SBY`, `WH-JKT`, dan `WH-SMG`. Setiap gudang
menyimpan seluruh 50 produk, dengan stok masuk awal 500 PCS per produk.
Untuk produk kemasan, satu PCS berarti satu kemasan sesuai nama produk.
Harga bersifat simulasi, bukan harga pasar: harga beli ditentukan dari urutan
produk dan harga jual sebesar 125% harga beli.

### Inbound

Setiap gudang memiliki 10 PO, masing-masing dengan lima produk. Lima PO
diterima dua kali (300 lalu 200 PCS per item), lima PO diterima penuh sekali
(500 PCS per item). Seluruh PO berakhir `RECEIVED`.

Snapshot menyimpan hasil posting penerimaan: 225 movement IN dengan total
75.000 PCS. Movement tersebut diimpor bersama dokumen sumber, tanpa memanggil
ulang procedure posting.

### Outbound

Setiap SO memiliki tiga produk berbeda, masing-masing 5 sampai 10 PCS.
Status konfirmasi, posting, pembatalan, dan completion sudah tersedia dalam CSV.
Import tidak menjalankan aksi bisnis tersebut lagi.

| Status SO | Jumlah | Kondisi |
|---|---:|---|
| COMPLETED | 72 | GI posted dan pengiriman telah diselesaikan. |
| SHIPPED | 24 | GI posted, belum dikonfirmasi selesai. |
| CONFIRMED | 12 | Stok direservasi, GI masih draft. |
| PENDING | 6 | Belum ada reservasi atau GI. |
| CANCELLED | 6 | Dikonfirmasi lalu dibatalkan, reservasi sudah dilepas, tanpa GI. |

SO pending, confirmed, dan cancelled adalah kondisi bisnis yang valid, bukan
data cacat. Dari 108 GI, sebanyak 96 diposting dan 12 masih draft.
Seluruh GI memuat item lengkap sesuai SO. Ada 288 movement OUT, total 2.142 PCS.

### Saldo akhir yang diharapkan

| Gudang | Stok fisik | Reservasi | Tersedia |
|---|---:|---:|---:|
| WH-SBY | 24.286 | 96 | 24.190 |
| WH-JKT | 24.286 | 96 | 24.190 |
| WH-SMG | 24.286 | 96 | 24.190 |

Ringkasan tersebut menjumlahkan seluruh produk dalam satuan PCS. Untuk analisis
operasional, tetap baca stok per produk/gudang, bukan hanya total gudang.

## Tanggal dan kualitas data

Dataset merupakan snapshot satu hari operasional pada **14 November 2026**,
dengan offset waktu `+07` (Asia/Jakarta). Tanggal tidak berubah saat CSV diimpor
pada hari lain. Snapshot berasal dari transaksi valid pada database uji,
dengan timestamp proses yang dihasilkan oleh procedure. Durasi fulfillment
sangat pendek karena proses simulasi; data ini belum ditujukan untuk analisis
tren penjualan bulanan.

CSV sudah diuji pada PostgreSQL 18 saat disiapkan. Pemeriksaan tambahan
tersebut tidak menjadi bagian dari proses import pengguna.

## Latihan setelah import

Dokumen yang sudah posted **tidak diposting ulang**. Untuk data awal ini,
contoh aksi yang bisa dicoba dengan ID berbeda:

```sql
-- GI 33 masih draft; posting akan membuat SO 33 menjadi SHIPPED.
CALL oltp.post_goods_issue(33);

-- SO 25 sudah SHIPPED; konfirmasi penyelesaian pengiriman.
CALL oltp.complete_sales_order(25);

-- SO 34 masih CONFIRMED; pembatalan melepas reservasinya.
CALL oltp.cancel_sales_order(34);
```

Contoh di atas untuk dicoba sekali pada snapshot awal. Kondisi data akan
berubah setelah dijalankan. Untuk transaksi baru, buat header/detail tanpa
mengisi ID otomatis, lalu panggil procedure yang sesuai. Procedure untuk
mengedit detail dokumen draft belum ditambahkan, sesuai scope saat ini.

## Query awal

```sql
SELECT status, COUNT(*) FROM oltp.sales_orders GROUP BY status;

SELECT w.warehouse_code, p.product_name,
       s.physical_stock, s.reserved_stock, s.available_stock
FROM oltp.inventory_stock s
JOIN oltp.warehouses w USING (warehouse_id)
JOIN oltp.products p USING (product_id)
ORDER BY w.warehouse_code, p.product_name;
```
