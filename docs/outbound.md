# Outbound OLTP

[Diagram proses inbound dan outbound](transaction-flow.md)

Outbound memisahkan pesanan pelanggan (SO) dari pengeluaran barang gudang (GI).
Satu SO dipenuhi satu gudang melalui satu GI penuh. Posting GI dianggap sebagai
konfirmasi pengiriman pada v1. Tidak ada partial shipment atau backorder.

## Menjalankan SQL

Gunakan koneksi ke `ndc_oltp` yang sudah memiliki tabel dan procedure inbound
dari file `01` dan `02`. Jalankan seluruh isi file berikut secara berurutan:

```powershell
psql -U postgres -d ndc_oltp -v ON_ERROR_STOP=1 -f sql/oltp/03_outbound_tables.sql
psql -U postgres -d ndc_oltp -v ON_ERROR_STOP=1 -f sql/oltp/04_outbound_processes.sql
```

File `03` dijalankan sekali: membuat lima tabel baru, memperluas movement,
dan membuat dua view. Tabel dan data inbound yang valid dipertahankan.
Jika ada movement lama dengan sumber atau arah yang tidak sesuai, penambahan
constraint gagal dan seluruh file `03` dibatalkan. Perbaiki data sumber dulu.
File `04` membuat atau memperbarui empat procedure. File tidak menjalankan
transaksi bisnis secara otomatis. Tabel lama di schema `public` tidak digunakan.

## Kamus atribut

Semua PK menggunakan `BIGINT GENERATED ALWAYS AS IDENTITY`. Jangan mengisi PK
secara manual; ambil ID hasil `INSERT ... RETURNING`. Semua FK bertipe `BIGINT`.
Semua kolom wajib diisi kecuali timestamp proses yang disebut boleh kosong.

### customers

| Atribut | Tipe | Fungsi |
|---|---|---|
| `customer_id` | BIGINT | PK pelanggan. |
| `customer_name` | VARCHAR(150) | Nama pelanggan. |
| `address` | TEXT | Alamat pelanggan; diasumsikan sekaligus alamat pengiriman v1. |

### sales_orders

| Atribut | Tipe | Fungsi |
|---|---|---|
| `sales_order_id` | BIGINT | PK dokumen pesanan. |
| `customer_id` | BIGINT | FK ke `customers`. |
| `warehouse_id` | BIGINT | FK ke `warehouses`, gudang asal seluruh item SO. |
| `order_date` | DATE | Tanggal bisnis pesanan. |
| `status` | VARCHAR(20) | Default `PENDING`; CHECK membatasi daftar status. |
| `confirmed_at` | TIMESTAMPTZ | Boleh kosong; diisi saat konfirmasi berhasil. Tetap disimpan jika kemudian dibatalkan. |
| `completed_at` | TIMESTAMPTZ | Boleh kosong; diisi setelah pengiriman dinyatakan selesai. |

Status mengikuti `PENDING → CONFIRMED → SHIPPED → COMPLETED`.
`PENDING` dan `CONFIRMED` boleh menjadi `CANCELLED`.

### sales_order_items

| Atribut | Tipe | Fungsi |
|---|---|---|
| `sales_order_item_id` | BIGINT | PK baris pesanan, sumber referensi item GI. |
| `sales_order_id` | BIGINT | FK ke `sales_orders`. |
| `product_id` | BIGINT | FK ke `products`. |
| `ordered_quantity` | INTEGER | Jumlah dipesan, harus positif. |
| `unit_price` | NUMERIC(18,2) | Harga jual transaksi per unit, harus nol atau positif. |

UNIQUE `(sales_order_id, product_id)` mencegah produk berulang pada satu SO.
Nilai baris dihitung dari `ordered_quantity * unit_price`.

### goods_issues

| Atribut | Tipe | Fungsi |
|---|---|---|
| `goods_issue_id` | BIGINT | PK dokumen pengeluaran barang. |
| `sales_order_id` | BIGINT | FK ke `sales_orders`, UNIQUE: maksimal satu GI per SO, termasuk draft. |
| `issued_at` | TIMESTAMPTZ | Waktu barang secara fisik dikeluarkan/dikirim, diisi pengguna. |
| `posted_at` | TIMESTAMPTZ | Boleh kosong; waktu pembukuan sistem oleh procedure posting. |

Draft berarti `posted_at IS NULL`. Supplier/customer dan gudang tidak diulang
di GI; customer dan gudang ditelusuri melalui SO. Gunakan offset yang jelas
untuk timestamp masukan, misalnya `2026-11-14 10:00:00+07`.

### goods_issue_items

| Atribut | Tipe | Fungsi |
|---|---|---|
| `goods_issue_item_id` | BIGINT | PK baris pengeluaran, sumber movement OUT. |
| `goods_issue_id` | BIGINT | FK ke `goods_issues`. |
| `sales_order_item_id` | BIGINT | FK ke `sales_order_items`, baris pesanan yang dipenuhi. |
| `issued_quantity` | INTEGER | Jumlah aktual keluar, harus positif. |

UNIQUE `(goods_issue_id, sales_order_item_id)` mencegah item SO berulang di GI.
Saat posting, semua item harus berasal dari SO yang dirujuk header, seluruh
item SO harus tercakup, dan jumlah setiap item harus sama dengan pesanan.

### Perluasan inventory_movements

| Atribut | Aturan setelah file 03 |
|---|---|
| `inventory_movement_id` | PK angka otomatis, tetap seperti inbound. |
| `goods_receipt_item_id` | FK item GR, UNIQUE, sekarang boleh kosong. |
| `goods_issue_item_id` | FK item GI baru, UNIQUE, boleh kosong. |
| `movement_type` | `IN` atau `OUT`. |
| `quantity` | Jumlah positif; disalin dari dokumen sumber saat posting. |

CHECK mewajibkan tepat satu sumber: IN hanya memakai item GR, OUT hanya
memakai item GI. UNIQUE pada sumber mencegah posting item yang sama dua kali.
Produk, gudang, dan waktu ditelusuri dari dokumen asalnya.

## Stok dan reservasi

`oltp.stock_movements` menyatukan movement IN dan OUT, menampilkan produk,
gudang, dan `quantity_change` bertanda positif/negatif. Tidak ada data stok
tambahan yang disimpan dalam view.

`oltp.inventory_stock` menampilkan seluruh pasangan produk/gudang beserta:

- `physical_stock`: total IN dikurangi OUT, dengan saldo awal nol.
- `reserved_stock`: total kuantitas item SO berstatus `CONFIRMED`.
- `available_stock`: stok fisik dikurangi reservasi.

```sql
SELECT * FROM oltp.inventory_stock
ORDER BY warehouse_id, product_id;
```

Tidak ada tabel reservasi terpisah pada versi ini. Perubahan dari `CONFIRMED`
ke `SHIPPED` atau `CANCELLED` otomatis mengeluarkan SO dari perhitungan
reservasi view; bukan menghapus histori konfirmasi.

## Proses bisnis

### 1. Membuat dan mengonfirmasi SO

Buat SO `PENDING` dan minimal satu item, lalu panggil dengan ID SO yang benar:

```sql
CALL oltp.confirm_sales_order(1);
```

Procedure mengunci SO, memastikan status `PENDING`, lalu mengunci baris gudang.
Seluruh item diperiksa terhadap stok tersedia gudang tersebut. Jika cukup,
status menjadi `CONFIRMED` dan `confirmed_at` diisi. Tidak ada movement.
Jika satu item kurang, seluruh konfirmasi ditolak tanpa reservasi sebagian.

### 2. Membuat draft GI

Buat header GI untuk SO `CONFIRMED`, tanpa mengisi `posted_at`. Isi detail
berdasarkan item SO. Draft GI belum mengubah stok atau status SO.
Pemeriksaan kelayakan GI dilakukan ulang saat posting.

### 3. Memposting GI dan mengirim barang

```sql
CALL oltp.post_goods_issue(1);
```

Parameter adalah ID GI, bukan ID SO. Procedure:

1. Mengunci GI dan menolak GI yang tidak ditemukan atau sudah diposting.
2. Mengunci SO terkait dan memastikan status masih `CONFIRMED`.
3. Mengunci gudang yang sama dengan proses konfirmasi.
4. Memeriksa asal, kelengkapan, dan kesamaan jumlah seluruh item.
5. Memeriksa stok fisik cukup dan saldo tersedia tidak negatif.
6. Membuat satu movement OUT per item GI.
7. Mengisi `goods_issues.posted_at` menggunakan waktu sistem.
8. Mengubah SO menjadi `SHIPPED`, sehingga reservasi dilepas.

Semua langkah mengikuti satu transaksi. Jangan mengubah SO ke `SHIPPED`
secara manual: status itu adalah hasil posting GI. Posting tidak dipicu oleh
UPDATE timestamp; implementasi ini tetap memakai procedure, tanpa trigger.

### 4. Menyelesaikan pengiriman

```sql
CALL oltp.complete_sales_order(1);
```

Parameter adalah ID SO. Hanya SO `SHIPPED` dengan GI posted yang boleh
diselesaikan. Status menjadi `COMPLETED`, `completed_at` diisi. Tidak ada
movement tambahan atau pengurangan stok kedua kali.

### 5. Membatalkan sebelum pengiriman

```sql
CALL oltp.cancel_sales_order(1);
```

Hanya SO `PENDING` atau `CONFIRMED` tanpa GI posted yang boleh dibatalkan.
Status menjadi `CANCELLED`, reservasi dilepas, stok fisik tetap.
Draft GI yang sudah ada dipertahankan, tetapi tidak dapat diposting karena
status SO tidak lagi `CONFIRMED`.

## Transaksi, penguncian, dan batas implementasi

- Procedure menggunakan PL/pgSQL dan `search_path` sendiri ke `oltp`.
  `RAISE EXCEPTION` membatalkan perubahan pemanggilan yang gagal. Jika memakai
  `BEGIN` eksplisit, pemanggil melakukan `COMMIT` atau `ROLLBACK`.
- Pada `READ COMMITTED`, konfirmasi dan posting GI untuk gudang yang sama
  berjalan bergantian melalui kunci baris gudang. Ini sederhana untuk skala
  NDC; belum memakai penguncian saldo per produk. Posting GR hanya menambah
  stok sehingga penerimaan yang belum commit dapat membuat konfirmasi ditolak
  sementara, tetapi tidak memberikan stok yang belum sah.
- Jangan ubah/hapus item, gudang, atau customer SO setelah konfirmasi.
  Jangan ubah/hapus GI posted, detailnya, atau movement. Jangan mengisi
  timestamp proses atau mengubah status SO secara manual.
- Seperti inbound, pembekuan edit dan larangan manipulasi SQL langsung belum
  dipaksakan dengan trigger atau pembatasan hak akses. Jangan mengedit dokumen
  bersamaan dengan konfirmasi/posting. Jaminan transaksi di atas berlaku untuk
  alur procedure dengan aturan penggunaan tersebut.
- Saldo awal harus berasal dari movement penerimaan. Perubahan alamat customer
  tidak dihistorisasi pada desain sederhana ini.

## Skenario uji

File [outbound.sql](../tests/sql/outbound.sql) membuat fixture di dalam transaksi,
memeriksa alur utama dan penolakan, lalu `ROLLBACK`. Jalankan pada database
latihan setelah file `01` sampai `04`:

```powershell
psql -U postgres -d ndc_oltp -v ON_ERROR_STOP=1 -f tests/sql/outbound.sql
```

Data fixture tidak disimpan, tetapi angka identity yang sudah digunakan dapat
terlewati setelah rollback. Uji ini satu sesi; belum menguji concurrency dua sesi.

Validasi implementasi telah dijalankan pada PostgreSQL 18 di instance sementara:
file `01` sampai `04` berhasil dieksekusi dan skenario uji di atas lulus.
Database NDC yang sudah ada tidak digunakan untuk pengujian tersebut.
