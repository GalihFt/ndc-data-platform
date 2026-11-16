# Menjalankan ELT Pertama

Pipeline ini dijalankan manual. Python memindahkan data antar-database,
sedangkan PostgreSQL SQL memvalidasi dan membentuk dimension/fact.
Mulai dengan membaca file sesuai urutan berikut:

| File | Tugas |
|---|---|
| `etl/run_elt.py` | Konfigurasi koneksi, SELECT sumber, load staging, dan pengatur urutan |
| `sql/dwh/03_validate_staging.sql` | Periksa referensi, quantity, dan movement staging |
| `sql/dwh/04_transform.sql` | Perbarui dimension dan bangun ulang fact |
| `sql/dwh/05_validate_dwh.sql` | Cocokkan setiap baris fact dengan staging |

## 1. Siapkan Database

Pastikan PostgreSQL aktif dan tersedia:

- `ndc_oltp`: schema `oltp`, tabel dan procedure, serta data dummy atau transaksi latihan.
- `ndc_dwh`: schema `staging` dan `dwh`, dari file setup `00`–`02`.

Jika database DWH belum dibuat, ikuti [panduan setup](dwh.md#membuat-tabel).
Script Python tidak membuat database atau tabel secara otomatis.

## 2. Pasang Library

Buka PowerShell dari root repo. Gunakan Python 3.10 atau lebih baru:

```powershell
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
```

Tidak perlu mengaktifkan virtual environment; kita memakai executable-nya langsung.
Library yang digunakan hanya SQLAlchemy, driver PostgreSQL psycopg2, dan dotenv
untuk membaca konfigurasi `.env`. Pandas belum diperlukan.

## 3. Isi Koneksi

Salin konfigurasi contoh sekali saja:

```powershell
Copy-Item .env.example .env
```

Buka `.env`, lalu sesuaikan host, port, user, dan password PostgreSQL.
Kedua database diasumsikan berada di server yang sama. Contoh:

```dotenv
DB_HOST=localhost
DB_PORT=5432
DB_USER=postgres
DB_PASSWORD="password_kamu"
OLTP_DATABASE=ndc_oltp
DWH_DATABASE=ndc_dwh
```

Gunakan tanda kutip jika password berisi karakter seperti `#` atau spasi.
Password dibaca apa adanya oleh pembentuk URL koneksi, sehingga `@` tidak
perlu diubah manual. `.env` sudah masuk `.gitignore`.
Environment variable yang sudah diatur di terminal memiliki prioritas atas `.env`.

## 4. Jalankan Pipeline

```powershell
.\.venv\Scripts\python.exe etl/run_elt.py
```

Urutan yang terlihat di terminal:

```text
1. Extract dari ndc_oltp
   ... jumlah baris setiap tabel ...
2. Load ke ndc_dwh.staging
3. Validasi staging
4. Transform staging ke dwh
5. Validasi DWH
   fact_receiving: 225 baris
   fact_sales: 288 baris
   fact_inventory: 513 baris
Selesai. COMMIT berhasil; staging dan DWH sudah diperbarui.
```

Jumlah tersebut berlaku untuk snapshot dummy awal. Staging hanya berisi
96 SO dan 96 GI yang sudah dikirim, 288 item SO/GI, serta data inbound/master
terkait. SO pending/confirmed/cancelled dan GI draft tidak ikut disalin.
Semua SELECT extract memakai satu snapshot sumber yang konsisten.

## 5. Cek Hasil

Pada koneksi **ndc_dwh**, jalankan:

```sql
SELECT * FROM staging.goods_receipts ORDER BY goods_receipt_id;
SELECT * FROM dwh.fact_receiving ORDER BY goods_receipt_item_id;
SELECT * FROM dwh.fact_sales ORDER BY goods_issue_item_id;
SELECT * FROM dwh.fact_inventory ORDER BY movement_id;
```

Untuk saldo fisik beras di WH-SBY:

```sql
SELECT SUM(CASE WHEN f.movement_type = 'IN' THEN f.qty_movement
                ELSE -f.qty_movement END) AS physical_stock
FROM dwh.fact_inventory f
JOIN dwh.dim_product p USING (product_key)
JOIN dwh.dim_warehouse w USING (warehouse_key)
WHERE p.product_id = 1 AND w.warehouse_code = 'WH-SBY';
```

Dummy awal menghasilkan 484. Jika penerimaan 100 dan pengiriman 10 sudah
diposting di OLTP, hasilnya menjadi 574 setelah pipeline dijalankan kembali.
Fact inventory hanya menyimpan movement fisik, bukan reservasi.

## Apa yang Terjadi Saat Diulang?

Ini **full refresh untuk data terpilih**, belum incremental:

1. Python membaca seluruh baris yang memenuhi seleksi ke memori.
2. Semua tabel staging yang dikelola pipeline dikosongkan lalu dimuat ulang.
3. Atribut dimension diperbarui dari staging; key lama dipertahankan (SCD Type 1).
4. Ketiga fact dikosongkan lalu dibangun ulang dari staging.

Tidak ada baris fact ganda ketika sumber tidak berubah. Dimension/tanggal lama
tetap disimpan, termasuk master yang sudah tidak ada pada snapshot sumber.
Harga pada fact berasal dari item transaksi. Nilai = quantity × harga unit.
Tanggal analisis memakai tanggal posting di Asia/Jakarta.

Staging, dimension, dan fact diperbarui dalam **satu transaksi tujuan**.
Jika validasi gagal atau ada SQL error, refresh dibatalkan otomatis dan data
sebelum refresh tetap tersedia. Sequence identity dapat melompat meskipun
transaksi dibatalkan; hal ini normal. Sumber OLTP hanya dibaca.

Validasi membandingkan hasil dengan snapshot staging, sehingga transaksi OLTP
yang masuk saat pipeline berjalan diproses pada eksekusi berikutnya.
Setiap validasi menghasilkan `check_name` dan `failures`; semua harus nol.

Jalankan satu pipeline pada satu waktu. Ada transaction lock untuk menolak
refresh tujuan yang bertabrakan. Query pembaca staging/fact dapat menunggu
sampai refresh selesai. Data dibaca ke memori agar kode mudah diikuti;
streaming dan incremental bisa ditambahkan saat dataset membesar.

## Jika Gagal

- Gagal koneksi: periksa PostgreSQL aktif, host, port, user, password, dan nama database.
- Tabel tidak ditemukan: jalankan setup DWH `00`–`02` terlebih dahulu.
- Validasi gagal: baca nama pemeriksaan di terminal, periksa data sumber, lalu ulangi pipeline.

File SQL transform sengaja tidak memiliki `BEGIN`/`COMMIT`: transaksi diatur
Python. Untuk pemakaian normal, jalankan melalui `run_elt.py` agar seluruh
validasi dan rollback ikut berjalan.

Pipeline telah diuji pada PostgreSQL 18 di instance sementara: load dummy,
eksekusi ulang tanpa perubahan data/key, perubahan atribut master, posting
inbound/outbound baru, sumber kosong, penolakan movement yang tidak sesuai,
serta rollback setelah transform ketika validasi akhir gagal. Database pengguna
tidak digunakan dalam pengujian tersebut.
