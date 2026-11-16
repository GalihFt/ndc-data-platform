-- Jalankan sekali melalui koneksi ke database postgres, dengan auto-commit aktif.
-- CREATE DATABASE tidak dapat dijalankan di dalam BEGIN/COMMIT.
CREATE DATABASE ndc_dwh;
-- Setelah selesai, pindah koneksi ke ndc_dwh untuk 01_staging_tables.sql dan 02_dwh_tables.sql.
