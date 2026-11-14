# Nusantara Distribution Center (NDC)

## File Implementasi

- [Panduan inbound dan cara menjalankan SQL](docs/inbound.md)
- [Pembuatan database OLTP](sql/oltp/00_create_database.sql)
- [Tabel OLTP inbound](sql/oltp/01_tables.sql)
- [Stored procedure posting penerimaan](sql/oltp/02_post_goods_receipt.sql)
- [Panduan tabel dan proses outbound](docs/outbound.md)
- [Tabel outbound dan view stok](sql/oltp/03_outbound_tables.sql)
- [Stored procedure outbound](sql/oltp/04_outbound_processes.sql)
- [Data awal CSV](data/dummy)
- [Import data awal CSV](sql/oltp/05_import_dummy.sql)
- [Panduan dan ringkasan data dummy](docs/dummy-data.md)

Folder `sql/dwh/` dan `etl/` disiapkan untuk tahap selanjutnya.

**Project:** Warehouse Inventory & Order Fulfillment Data Platform  
**Level:** Intermediate  
**Architecture:** OLTP → ETL → OLAP → Dashboard  
**Environment:** Local (no cloud)

## 1. Business Case

PT Nusantara Distribution Center (NDC) adalah perusahaan distribusi fiktif yang membeli produk dari supplier, menyimpan stok di gudang, lalu memenuhi pesanan pelanggan bisnis.

**Asumsi skala:**
- 3 gudang: Surabaya (`WH-SBY`), Jakarta (`WH-JKT`), Semarang (`WH-SMG`).
- ±50 produk, 8 supplier, dan 100 customer.
- Setiap sales order (SO) dipenuhi dari satu gudang.

**Masalah bisnis:** Data transaksi tersedia, tetapi manajemen kesulitan memantau penjualan, ketersediaan stok, dan efektivitas pemenuhan pesanan secara terpusat.

**Tujuan project:** Membangun database operasional (OLTP), pipeline ETL, data warehouse (OLAP), dan dashboard analitik secara lokal.

## 2. Scope

### In Scope
- Master data produk, supplier, customer, dan gudang.
- Purchase order (PO) dan detail produk.
- Penerimaan barang, termasuk penerimaan parsial.
- Sales order (SO) dan detail produk.
- Pengecekan dan reservasi stok saat konfirmasi SO.
- Pengiriman satu kali untuk seluruh item SO.
- Histori pergerakan stok masuk dan keluar.
- ETL batch, validasi kualitas data, serta incremental load pada fase lanjutan.
- Data warehouse dan dashboard analitik.

### Out of Scope (v1)
- Pembayaran dan invoice.
- Retur pembelian/penjualan.
- Transfer stok antar-gudang.
- Partial shipment, multi-warehouse fulfillment, dan backorder.
- Tracking kendaraan/GPS, pengelolaan rak/bin gudang, dan cloud deployment.

## 3. Business Flow

### Inbound (Purchase to Stock)
1. Staff membuat PO untuk satu supplier dan satu gudang tujuan.
2. PO berisi satu atau lebih produk beserta kuantitas dan harga beli.
3. Supplier mengirim barang.
4. Gudang mencatat kuantitas barang yang benar-benar diterima; penerimaan boleh berlangsung maksimal dua kali per PO.
5. Penerimaan valid menambah stok fisik dan tercatat dalam histori inventory movement.
6. PO berstatus `RECEIVED` setelah semua kuantitas yang dipesan terpenuhi.

### Outbound (Order to Fulfillment)
1. Customer membuat SO dari satu gudang.
2. SO berisi satu atau lebih produk beserta kuantitas dan harga jual transaksi.
3. Sistem memeriksa stok tersedia sebelum konfirmasi.
4. Konfirmasi SO mereservasi stok; stok fisik belum berkurang.
5. Saat seluruh item dikirim sekaligus, reservasi dilepas, stok fisik berkurang, dan movement dicatat.
6. SO menjadi `COMPLETED` setelah penyelesaian pengiriman dikonfirmasi.
7. SO yang belum dikirim dapat dibatalkan; reservasi yang ada harus dilepas.

## 4. Functional Requirements

### Master Data
| ID | Requirement |
|---|---|
| FR-01 | Mengelola produk (kode, nama, kategori, satuan). |
| FR-02 | Mengelola supplier. |
| FR-03 | Mengelola customer. |
| FR-04 | Mengelola gudang dan lokasi. |
| FR-05 | Mendukung produk yang sama di lebih dari satu gudang. |

### Purchasing & Receiving
| ID | Requirement |
|---|---|
| FR-06 | Membuat PO dengan satu supplier dan satu gudang tujuan. |
| FR-07 | Menyimpan beberapa item produk dalam satu PO. |
| FR-08 | Menyimpan kuantitas dan harga beli per item PO. |
| FR-09 | Mencatat penerimaan barang dengan referensi ke PO. |
| FR-10 | Menambah stok berdasarkan jumlah diterima, bukan jumlah dipesan. |
| FR-11 | Mendukung penerimaan bertahap dan menghitung sisa kuantitas PO. |

### Sales & Fulfillment
| ID | Requirement |
|---|---|
| FR-12 | Membuat SO dengan satu customer dan satu gudang asal. |
| FR-13 | Menyimpan beberapa item produk dalam satu SO. |
| FR-14 | Menyimpan kuantitas dan harga jual per item SO. |
| FR-15 | Memvalidasi stok tersedia sebelum konfirmasi SO. |
| FR-16 | Mereservasi stok saat konfirmasi SO. |
| FR-17 | Mengurangi stok fisik saat SO dikirim. |
| FR-18 | Mendukung pembatalan SO sebelum pengiriman dan pelepasan reservasi. |

### Inventory
| ID | Requirement |
|---|---|
| FR-19 | Mencatat histori pergerakan stok masuk/keluar beserta waktu, produk, gudang, kuantitas, dan referensi transaksi. |
| FR-20 | Menentukan stok fisik, stok direservasi, dan stok tersedia per produk/gudang. |
| FR-21 | Mencegah stok fisik dan stok tersedia menjadi negatif. |
| FR-22 | Menelusuri sumber tiap perubahan stok. |

## 5. Business Rules

| ID | Rule |
|---|---|
| BR-01 | Satu PO hanya untuk satu supplier dan satu gudang. |
| BR-02 | Satu SO hanya untuk satu customer dan satu gudang. |
| BR-03 | Satu PO/SO dapat berisi banyak produk; kuantitas setiap item harus bilangan bulat positif. |
| BR-04 | Total penerimaan per item PO tidak boleh melebihi kuantitas yang dipesan. |
| BR-05 | Maksimal dua transaksi penerimaan per PO pada v1. |
| BR-06 | Stok fisik hanya bertambah saat penerimaan valid. |
| BR-07 | Konfirmasi SO hanya boleh jika seluruh item mempunyai stok tersedia yang cukup. |
| BR-08 | Konfirmasi SO mereservasi stok, bukan langsung mengurangi stok fisik. |
| BR-09 | Pengiriman SO dilakukan sekaligus untuk seluruh item; tidak ada partial shipment pada v1. |
| BR-10 | Pengiriman mengurangi stok fisik dan melepas reservasi untuk item terkait. |
| BR-11 | Pembatalan SO diperbolehkan sebelum `SHIPPED`; reservasi dilepas dan stok fisik tidak berubah. |
| BR-12 | Stok fisik dan stok tersedia tidak boleh negatif. |
| BR-13 | Harga beli/jual pada detail transaksi tidak berubah ketika harga master produk berubah. |
| BR-14 | Perubahan stok harus mempunyai jejak transaksi; operasi yang gagal tidak boleh menghasilkan perubahan stok sebagian. |

**Definisi stok:** `available_stock = physical_stock - reserved_stock`. Cara menyimpan/menghitung ketiga nilai ini menjadi keputusan desain database.

## 6. Transaction Status

### Purchase Order
`DRAFT → ORDERED → PARTIALLY_RECEIVED → RECEIVED`

- `PARTIALLY_RECEIVED` hanya muncul jika belum seluruh kuantitas diterima.
- Jika semua item terpenuhi dalam satu penerimaan, `ORDERED → RECEIVED` diperbolehkan.
- `CANCELLED` diperbolehkan sebelum penerimaan pertama.

### Sales Order
`PENDING → CONFIRMED → SHIPPED → COMPLETED`

- `CONFIRMED`: seluruh kebutuhan stok sudah direservasi.
- `SHIPPED`: seluruh item dikirim; stok fisik berkurang.
- `COMPLETED`: pengiriman dikonfirmasi selesai.
- `CANCELLED` diperbolehkan dari `PENDING` atau `CONFIRMED`, bukan setelah `SHIPPED`.

## 7. Test Scenarios

| ID | Skenario | Ekspektasi |
|---|---|---|
| S01 | PO diterima penuh sekali pengiriman | Stok bertambah sesuai kuantitas diterima; PO `RECEIVED`. |
| S02 | PO 100 unit diterima 60 lalu 40 | Movement `+60` dan `+40`; PO `RECEIVED` setelah penerimaan kedua. |
| S03 | SO memuat beberapa produk | Detail produk dan nilai transaksi dapat dihitung. |
| S04 | Stok tersedia lebih kecil dari kebutuhan SO | SO tidak dapat dikonfirmasi; tidak ada reservasi. |
| S05 | SO terkonfirmasi lalu dibatalkan | Reservasi dilepas; stok fisik tetap. |
| S06 | SO dikirim lalu diselesaikan | Stok berkurang satu kali; status `SHIPPED → COMPLETED`. |
| S07 | Produk sama tersedia pada dua gudang | Stok dan transaksi masing-masing gudang terpisah. |
| S08 | Harga produk berubah setelah transaksi lama | Harga pada transaksi lama tetap. |
| S09 | ETL dijalankan ulang tanpa data baru | Data warehouse tidak menggandakan record atau nilai KPI. |
| S10 | Ada transaksi baru/berubah setelah ETL terakhir | Incremental load memproses perubahan relevan tanpa duplikasi. |

## 8. Analytical Requirements

| ID | Business Question | KPI |
|---|---|---|
| AR-01 | Berapa nilai penjualan setiap bulan? | Monthly Sales |
| AR-02 | Gudang mana yang menghasilkan penjualan terbesar? | Sales by Warehouse |
| AR-03 | Produk mana yang paling banyak terjual? | Units Sold by Product |
| AR-04 | Berapa proporsi SO yang telah selesai? | Fulfillment Rate |
| AR-05 | Berapa lama proses dari pembuatan SO hingga selesai? | Average Fulfillment Time |
| AR-06 | Produk apa yang memiliki stok tersedia rendah? | Low Stock Items |
| AR-07 | Bagaimana stok berubah menurut waktu dan gudang? | Inventory Trend |
| AR-08 | Berapa banyak barang yang diterima dari supplier? | Received Quantity |

**Catatan definisi KPI sebelum implementasi:** tentukan tanggal pengakuan penjualan (mis. saat `SHIPPED`), denominator fulfillment rate, ambang low stock, dan apakah inventory trend menggunakan snapshot harian atau movement. Jangan menghitung penjualan dua kali akibat join header-detail.

## 9. Local Architecture

```text
PostgreSQL: ndc_oltp
        |
        v
Python ETL (SQLAlchemy / Pandas)
        |
        v
PostgreSQL: ndc_dwh
  ├── staging
  ├── dimensional model (facts & dimensions)
  └── analytics
        |
        v
Power BI / Metabase Dashboard
```

- OLTP dan DWH menggunakan database terpisah, boleh pada server PostgreSQL lokal yang sama.
- ETL v1 dijalankan manual (batch); incremental load dan scheduling ditambahkan setelah alur dasar bekerja.
- Dashboard membaca data analitik dari DWH, bukan tabel OLTP langsung.

## 10. Implementation Milestones

- [ ] **M1 — Conceptual ERD:** tentukan entitas, hubungan, dan cardinality.
- [ ] **M2 — Logical/Physical OLTP:** tentukan atribut, PK/FK, tipe data, constraints, dan normalisasi.
- [ ] **M3 — Simulated Transactions:** buat data master dan jalankan skenario S01–S08.
- [ ] **M4 — ETL Batch:** ekstraksi OLTP, staging, validasi, transformasi, dan load.
- [ ] **M5 — OLAP Model:** tentukan grain, fact, dimension, serta historisasi yang diperlukan.
- [ ] **M6 — Dashboard:** tampilkan KPI AR-01–AR-08.
- [ ] **M7 — Incremental & Reliability:** uji S09–S10, idempotency, logging, dan scheduling lokal.

## 11. Current Assignment — Conceptual ERD

Rancang sendiri conceptual ERD di draw.io berdasarkan requirement. Minimal identifikasi:

- Master data: produk, supplier, customer, gudang.
- Dokumen transaksi pembelian dan detailnya.
- Dokumen penerimaan barang dan detailnya.
- Dokumen transaksi penjualan dan detailnya.
- Histori pergerakan stok serta mekanisme reservasi.

**Output yang harus diserahkan untuk review:** diagram entitas dan relasi/cardinality (1:1, 1:N, N:M). **Belum perlu menulis SQL.**

**Review berikutnya:** periksa apakah rancangan dapat mendukung partial receiving, full shipment, pembatalan SO, reservasi stok, dan histori inventory tanpa redundansi yang tidak perlu.
