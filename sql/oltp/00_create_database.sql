-- Jalankan sekali melalui koneksi ke database postgres.
-- CREATE DATABASE harus dijalankan di luar transaction block / auto-commit aktif.
-- Setelah selesai, buka koneksi baru ke ndc_oltp untuk file 01 dan 02.
CREATE DATABASE ndc_oltp;
