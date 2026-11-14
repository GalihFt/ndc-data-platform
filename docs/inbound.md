# Inbound OLTP

Setelah inbound, lanjutkan ke [outbound](outbound.md). File `03` memperluas
movement agar mendukung sumber GI untuk stok keluar, dan menambahkan view
`oltp.inventory_stock` yang memperhitungkan stok masuk, keluar, serta reservasi.

## Struktur repo

```text
docs/                 Penjelasan desain dan diagram
sql/oltp/             Tabel dan proses transaksi operasional
sql/dwh/              Tempat SQL data warehouse pada tahap berikutnya
etl/                  Tempat pipeline ETL pada tahap berikutnya
```

Desain awal menggunakan delapan tabel: `suppliers`, `products`, `warehouses`,
`purchase_orders`, `purchase_order_items`, `goods_receipts`,
`goods_receipt_items`, dan `inventory_movements`.

## Kamus atribut

Sumber struktur tabel: [01_tables.sql](../sql/oltp/01_tables.sql).
PK adalah identitas unik baris; FK adalah referensi ke tabel lain.
Semua PK dan FK menggunakan `BIGINT`. PK menggunakan
`GENERATED ALWAYS AS IDENTITY`, sehingga angka dibuat otomatis oleh database
dan tidak perlu diisi saat `INSERT`. Setiap tabel memiliki penomoran sendiri;
`supplier_id = 1` dan `product_id = 1` adalah identitas yang berbeda.

Angka ID dapat melompat setelah transaksi gagal; ID tidak harus berurutan
tanpa celah. Kode `warehouse_code`, seperti `WH-SBY`, tetap menjadi kode
lokasi bisnis, sedangkan `warehouse_id` berupa angka untuk referensi relasi.

Contoh membuat supplier dan membaca ID yang dihasilkan:

```sql
INSERT INTO oltp.suppliers (supplier_name)
VALUES ('Supplier Nusantara')
RETURNING supplier_id;
```

Semua kolom wajib diisi (`NOT NULL`), kecuali `goods_receipts.posted_at`.

### suppliers

Master pemasok barang. Satu supplier dapat memiliki banyak PO.

| Atribut | Tipe | Arti dan aturan |
|---|---|---|
| `supplier_id` | BIGINT | PK supplier. |
| `supplier_name` | VARCHAR(150) | Nama pemasok; tidak diberi aturan unik. |

### products

Master barang. Satu produk dapat dipesan dalam banyak PO.

| Atribut | Tipe | Arti dan aturan |
|---|---|---|
| `product_id` | BIGINT | PK produk. |
| `product_name` | VARCHAR(150) | Nama produk. |
| `category` | VARCHAR(100) | Kelompok produk, misalnya minuman. |
| `unit` | VARCHAR(20) | Satuan kuantitas, misalnya PCS atau BOX; konsisten untuk setiap produk. |

### warehouses

Master gudang tujuan pembelian. Satu gudang dapat menjadi tujuan banyak PO.

| Atribut | Tipe | Arti dan aturan |
|---|---|---|
| `warehouse_id` | BIGINT | PK gudang. |
| `warehouse_code` | VARCHAR(20) | Kode unik gudang, misalnya `WH-SBY`. |
| `warehouse_name` | VARCHAR(100) | Nama gudang. |
| `city` | VARCHAR(100) | Kota lokasi gudang. |

### purchase_orders

Header pesanan pembelian: informasi yang berlaku untuk seluruh item pesanan.
Setiap PO memiliki satu supplier dan satu gudang tujuan.

| Atribut | Tipe | Arti dan aturan |
|---|---|---|
| `purchase_order_id` | BIGINT | PK PO; juga digunakan sebagai identitas dokumen pada versi sederhana. |
| `supplier_id` | BIGINT | FK ke `suppliers.supplier_id`. |
| `warehouse_id` | BIGINT | FK ke `warehouses.warehouse_id`. |
| `order_date` | DATE | Tanggal bisnis pemesanan, diisi pengguna. |
| `status` | VARCHAR(25) | Default `DRAFT`; nilai dibatasi oleh CHECK sesuai daftar status di bawah. |

| Status | Arti | Pengelolaan pada implementasi saat ini |
|---|---|---|
| `DRAFT` | Pesanan sedang disusun. | Nilai awal otomatis. |
| `ORDERED` | Pesanan siap menerima barang. | Diubah manual setelah PO dan item diperiksa. |
| `PARTIALLY_RECEIVED` | Sebagian kuantitas sudah diterima. | Diisi procedure setelah posting jika masih ada sisa pesanan. |
| `RECEIVED` | Semua kuantitas pesanan sudah diterima. | Diisi procedure setelah posting jika tidak ada sisa pesanan. |
| `CANCELLED` | Pesanan dibatalkan sebelum penerimaan pertama diposting. | Diubah manual dengan mematuhi aturan penggunaan. |

CHECK hanya membatasi daftar nilai status. Urutan perpindahan status dan syarat
minimal satu item saat menjadi `ORDERED` belum dipaksakan oleh tabel.

### purchase_order_items

Detail produk yang dipesan. Satu PO memiliki banyak item; satu produk hanya
boleh muncul sekali dalam PO yang sama.

| Atribut | Tipe | Arti dan aturan |
|---|---|---|
| `purchase_order_item_id` | BIGINT | PK baris pesanan; menjadi referensi detail penerimaan. |
| `purchase_order_id` | BIGINT | FK ke `purchase_orders.purchase_order_id`. |
| `product_id` | BIGINT | FK ke `products.product_id`. |
| `ordered_quantity` | INTEGER | Jumlah dipesan; harus lebih dari nol. |
| `unit_price` | NUMERIC(18,2) | Harga beli per unit pada transaksi tersebut; harus nol atau positif. |

Pasangan `(purchase_order_id, product_id)` memiliki constraint UNIQUE.
Nilai baris dihitung sebagai `ordered_quantity * unit_price` dan tidak disimpan
sebagai kolom tambahan. Perubahan harga pada pembelian berikutnya tidak
mengubah harga transaksi sebelumnya.

### goods_receipts

Header kejadian penerimaan barang (GR). Satu PO dapat memiliki beberapa GR;
procedure membatasi maksimal dua GR yang sudah diposting.

| Atribut | Tipe | Arti dan aturan |
|---|---|---|
| `goods_receipt_id` | BIGINT | PK penerimaan. |
| `purchase_order_id` | BIGINT | FK ke `purchase_orders.purchase_order_id`. |
| `received_at` | TIMESTAMPTZ | Waktu barang diterima secara fisik, diisi pengguna. |
| `posted_at` | TIMESTAMPTZ | Waktu pembukuan; NULL sebelum posting dan diisi procedure menggunakan `clock_timestamp()`. |

Tidak ada kolom status GR terpisah: `posted_at IS NULL` berarti belum
diposting. Supplier dan gudang ditelusuri melalui PO. `TIMESTAMPTZ` menyimpan
suatu titik waktu; tampilannya mengikuti pengaturan zona waktu sesi database.
Saat memasukkan waktu, gunakan offset yang jelas, misalnya
`2026-11-14 09:00:00+07`.

### goods_receipt_items

Detail jumlah barang yang benar-benar diterima. Satu item PO dapat dipenuhi
oleh item GR pertama dan item GR kedua.

| Atribut | Tipe | Arti dan aturan |
|---|---|---|
| `goods_receipt_item_id` | BIGINT | PK baris penerimaan. |
| `goods_receipt_id` | BIGINT | FK ke `goods_receipts.goods_receipt_id`. |
| `purchase_order_item_id` | BIGINT | FK ke `purchase_order_items.purchase_order_item_id`; menunjukkan baris pesanan yang dipenuhi. |
| `received_quantity` | INTEGER | Jumlah aktual diterima; harus lebih dari nol. |

Pasangan `(goods_receipt_id, purchase_order_item_id)` memiliki constraint
UNIQUE. Barang yang tidak datang tidak perlu dibuatkan baris dengan jumlah nol.
Produk ditelusuri melalui item PO. Procedure memeriksa kecocokan PO pada
header dan detail, serta akumulasi penerimaan agar tidak melebihi pesanan.

### inventory_movements

Histori perubahan stok fisik. Setiap item GR yang diposting menghasilkan
satu movement `IN`.

| Atribut | Tipe | Arti dan aturan |
|---|---|---|
| `inventory_movement_id` | BIGINT | PK movement. |
| `goods_receipt_item_id` | BIGINT | FK ke `goods_receipt_items.goods_receipt_item_id`, sekaligus UNIQUE untuk mencegah dua movement pada item GR yang sama. |
| `movement_type` | VARCHAR(3) | Arah perubahan stok; CHECK mengizinkan `IN` atau `OUT`. |
| `quantity` | INTEGER | Jumlah positif; diisi procedure dari `received_quantity`. |

`IN` menambah saldo dan `OUT` mengurangi saldo. Pada tahap file `01`, sumber
movement masih khusus GR. File `03` menambahkan sumber item GI untuk OUT
dan mengizinkan sumber GR kosong hanya pada movement OUT.
Produk ditelusuri melalui item PO, gudang melalui header PO, waktu fisik
melalui `received_at`, dan waktu pembukuan melalui `posted_at`.

## Proses bisnis dan posting GR

### Menyiapkan pesanan dan penerimaan

1. Catat supplier, produk, dan gudang sebagai master data.
2. Buat header PO dengan status `DRAFT`, lalu tambahkan produk, kuantitas,
   dan harga pada item PO.
3. Periksa bahwa PO memiliki item yang benar, lalu ubah status menjadi
   `ORDERED`. Tahap ini belum memiliki procedure tersendiri.
4. Ketika barang datang, buat header GR dengan `received_at`, tanpa mengisi
   `posted_at`. Tambahkan item GR yang mengacu pada baris PO terkait.
5. Periksa jumlah aktual barang, lalu panggil procedure posting.

Menyimpan PO atau GR yang belum diposting belum menambah stok. Posting GR
adalah tahap yang membukukan penerimaan menjadi movement stok.

### Isi procedure post_goods_receipt

Sumber proses: [02_post_goods_receipt.sql](../sql/oltp/02_post_goods_receipt.sql).
Parameter `p_goods_receipt_id` bertipe BIGINT adalah ID GR yang ingin dibukukan.
Procedure tidak mengembalikan nilai; hasilnya dibaca dari tabel.

Variabel `v_receipt` dan `v_po` menyimpan satu baris GR dan PO menggunakan
`%ROWTYPE`, sehingga bentuknya mengikuti struktur tabel. `v_posted_at`
menyimpan waktu pembukuan yang akan ditulis ke GR.

| Tahap | Operasi | Tujuan / kondisi penolakan |
|---|---|---|
| 1 | Baca GR dengan `SELECT ... FOR UPDATE`. | Kunci baris GR sampai transaksi selesai; tolak jika ID tidak ditemukan atau sudah diposting. |
| 2 | Baca PO terkait dengan `FOR UPDATE`. | Posting lain pada PO yang sama harus menunggu; tolak jika status bukan `ORDERED` atau `PARTIALLY_RECEIVED`. |
| 3 | Hitung GR yang memiliki `posted_at`. | Tolak jika PO sudah memiliki dua penerimaan yang diposting. |
| 4 | Periksa detail GR. | Tolak jika GR tidak memiliki item. |
| 5 | Cocokkan item PO dengan header GR. | Tolak jika ada item yang berasal dari PO lain. |
| 6 | Jumlahkan penerimaan per item PO. | Hitung GR yang sudah diposting ditambah GR saat ini; tolak jika total melebihi `ordered_quantity`. GR draft lain tidak dihitung. |
| 7 | `INSERT` ke `inventory_movements`. | Buat satu movement `IN` per item GR, dengan `quantity = received_quantity`. |
| 8 | `UPDATE goods_receipts`. | Isi `posted_at` dengan waktu sistem saat pembukuan. |
| 9 | Hitung sisa seluruh item PO dan `UPDATE purchase_orders`. | Jika masih ada item yang kurang, status `PARTIALLY_RECEIVED`; jika semuanya terpenuhi, `RECEIVED`. |

Setiap validasi yang gagal menggunakan `RAISE EXCEPTION`. Tidak ada perubahan
parsial dari satu pemanggilan procedure yang gagal. Jika GR yang sama dipanggil
lagi setelah berhasil, procedure menolak dengan pesan sudah diposting;
movement tidak ditambahkan lagi. Constraint UNIQUE pada sumber movement
menjadi pemeriksaan tambahan untuk mencegah duplikasi.

### Contoh penerimaan bertahap

Satu PO memesan produk A sebanyak 100 PCS dan produk B sebanyak 50 PCS.

| Kejadian | Isi penerimaan | Movement baru | Status PO setelah posting |
|---|---|---|---|
| Buat PO dan ubah menjadi `ORDERED` | Belum ada penerimaan | Tidak ada | `ORDERED` |
| Posting GR pertama | A: 60, B: 50 | `IN` A: 60 dan `IN` B: 50 | `PARTIALLY_RECEIVED` |
| Posting GR kedua | A: 40 | `IN` A: 40 | `RECEIVED` |

Setiap GR memiliki `received_at` dan `posted_at` masing-masing. Pada contoh
ini, hasil akhirnya adalah stok A bertambah 100 dan B bertambah 50 di gudang
tujuan PO. B tidak perlu dicantumkan pada GR kedua karena sudah terpenuhi.

Sisa per item dihitung sebagai jumlah dipesan dikurangi total penerimaan
yang sudah diposting. Kolom jumlah diterima, sisa pesanan, dan saldo stok
tidak disimpan ulang pada item PO.

## Menjalankan SQL

Database adalah wadah utama bernama `ndc_oltp`. Di dalamnya, schema `oltp`
mengelompokkan delapan tabel dan procedure transaksi, misalnya
`oltp.goods_receipts` dan `oltp.post_goods_receipt`.

Jalankan file berurutan dari root repo:

```powershell
psql -U postgres -d postgres -v ON_ERROR_STOP=1 -f sql/oltp/00_create_database.sql
psql -U postgres -d ndc_oltp -v ON_ERROR_STOP=1 -f sql/oltp/01_tables.sql
psql -U postgres -d ndc_oltp -v ON_ERROR_STOP=1 -f sql/oltp/02_post_goods_receipt.sql
```

Sesuaikan user, host, dan port dengan instalasi lokal. User perlu izin membuat
database. File `00` dijalankan sekali melalui koneksi ke database `postgres`,
di luar transaction block (auto-commit aktif). Jika `ndc_oltp` sudah ada,
lewati file `00`; jangan menghapus database yang sudah berisi data.

File `01` dan `02` dijalankan melalui koneksi baru ke `ndc_oltp`. File `01`
membuat schema `oltp`, lalu membuat tabel di dalamnya. File tabel dijalankan
sekali pada schema kosong; ini belum merupakan sistem migration. Di GUI
seperti pgAdmin atau DBeaver, ganti koneksi/database secara manual setelah
menjalankan file `00`.

Untuk SQL manual, gunakan nama lengkap seperti `oltp.purchase_orders`, atau
atur schema pada setiap sesi koneksi:

```sql
SET search_path TO oltp;
```

Procedure memiliki pengaturan `search_path` sendiri agar referensi tabelnya
tetap mengarah ke schema `oltp` meskipun dipanggil dari sesi dengan schema lain.

Jika SQL versi lama sudah dijalankan, tabel/procedure di `public` tidak otomatis
dipindahkan. Setup ini ditujukan untuk schema baru; data lama perlu dimigrasikan
secara terpisah sebelum beralih. Jangan mencampur transaksi dari kedua schema.

## Alur penggunaan

1. Buat master data, PO, dan item PO.
2. Setelah item diperiksa, ubah PO dari `DRAFT` menjadi `ORDERED`.
3. Buat `goods_receipts` dengan `posted_at` kosong, lalu isi item penerimaan.
4. Jalankan stored procedure posting dengan ID penerimaan yang sesuai:

```sql
CALL oltp.post_goods_receipt(1);
```

Procedure memvalidasi penerimaan, membuat movement `IN`, mengisi `posted_at`,
dan memperbarui status PO dalam satu transaksi. Jika gagal, semua perubahan
oleh pemanggilan procedure tersebut dibatalkan. Data draft yang sudah disimpan
sebelumnya tetap ada untuk diperbaiki.

Procedure menggunakan PL/pgSQL dan mengikuti transaksi pemanggil; tidak ada
`COMMIT` atau `ROLLBACK` internal. Saat menggunakan transaksi eksplisit,
pemanggil melakukan `COMMIT` setelah berhasil atau `ROLLBACK` setelah error.
Waktu posting dapat dilihat pada `goods_receipts.posted_at` setelah `CALL`.

SQL ini ditujukan untuk setup baru dengan ID angka. Jika versi ID teks
sudah dipasang di database, perubahan file tidak otomatis mengubah tabel.
PK, FK, dan referensi data lama perlu dimigrasikan bersama sebelum memakai
procedure berparameter `BIGINT`. Jangan menjalankan ulang file tabel di atas
tabel lama atau menghapus data yang sudah ada. Procedure lama berparameter
`TEXT` juga perlu ditangani saat migrasi agar tidak tertinggal sebagai overload.

`received_at` adalah waktu barang diterima secara fisik. `posted_at` adalah
waktu penerimaan dibukukan di sistem. Hanya penerimaan yang sudah diposting
dihitung sebagai pemenuhan PO. Maksimal dua penerimaan diposting per PO;
jika penerimaan kedua belum memenuhi pesanan, status tetap `PARTIALLY_RECEIVED`
dan penerimaan ketiga ditolak, sesuai batas v1.

## Batas desain sederhana

- Kuantitas berupa bilangan bulat positif. Setiap produk memakai satu satuan.
- Harga beli disimpan pada item PO, menggunakan `NUMERIC(18,2)`.
- `movement_type` menyediakan nilai `IN` dan `OUT`; `quantity` selalu positif.
  Procedure inbound hanya menghasilkan `IN`. Setelah file `03` dan `04`
  dipasang, procedure outbound menghasilkan `OUT` dengan sumber item GI.
- Produk, gudang, dan waktu movement ditelusuri melalui item penerimaan,
  penerimaan, dan PO. Saldo awal diasumsikan nol.
- Jangan ubah/hapus penerimaan yang sudah diposting atau movement-nya.
  Jangan ubah item, supplier, dan gudang PO setelah `ORDERED`.
  Pembatalan PO hanya sebelum penerimaan pertama diposting.
- Aturan edit dan transisi status tersebut masih berupa aturan penggunaan,
  belum dipaksakan dengan trigger atau pembatasan akses. SQL langsung dapat
  melewatinya. Jangan mengedit dokumen bersamaan dengan proses posting.
  Penguncian dalam procedure mengamankan posting bersamaan untuk PO yang sama
  pada isolation level default PostgreSQL (`READ COMMITTED`).

## Contoh membaca stok inbound

Query berikut hanya menghitung penerimaan (IN). Setelah outbound dipasang,
gunakan `SELECT * FROM oltp.inventory_stock;` untuk saldo stok terkini yang
juga memperhitungkan OUT dan reservasi.

```sql
SET search_path TO oltp;

SELECT poi.product_id,
       po.warehouse_id,
       SUM(CASE WHEN im.movement_type = 'IN'
                THEN im.quantity ELSE -im.quantity END) AS physical_stock
FROM inventory_movements im
JOIN goods_receipt_items gri USING (goods_receipt_item_id)
JOIN purchase_order_items poi USING (purchase_order_item_id)
JOIN goods_receipts gr USING (goods_receipt_id)
JOIN purchase_orders po ON po.purchase_order_id = gr.purchase_order_id
GROUP BY poi.product_id, po.warehouse_id;
```
