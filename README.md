# Putra Laundry - Boilerplate Flask

Sistem Informasi Manajemen Laundry (Flask + MySQL + Bootstrap).

## Struktur
```
titut_laundry/
  app.py            <- route / halaman
  config.py         <- pengaturan database & secret key
  db.py             <- koneksi & helper query MySQL
  set_password.py   <- isi password asli user di database
  requirements.txt  <- daftar library
  templates/        <- halaman HTML (Bootstrap 5)
```

## Langkah setup (Windows, PowerShell)
1. Nyalakan **MySQL** di XAMPP, impor `putra_laundry_import.sql` lewat phpMyAdmin.
2. Buka folder ini di terminal:
   ```
   cd D:\titut_laundry
   python -m venv venv
   venv\Scripts\activate
   pip install -r requirements.txt
   ```
3. Isi password login (placeholder di SQL tidak bisa dipakai login):
   ```
   python set_password.py owner passwordku
   python set_password.py pegawai1 passwordku
   ```
4. Jalankan: `python app.py`, lalu buka http://localhost:5000
5. Login dengan `owner` atau `pegawai1` dan password tadi.

Jika password MySQL root Anda tidak kosong, ubah `DB_CONFIG` di `config.py`.

## Sudah ada
- Login + hak akses owner/pegawai (US-01)
- Dashboard owner, antrean pekerjaan, reminder cucian selesai (US-13, US-08, US-10)
- Kelola pelanggan (US-02)
- Kelola layanan & tarif, khusus owner (US-03)

## Berikutnya (query-nya ada di putra_laundry_queries.sql)
Transaksi baru + nota, update status, pembayaran, laporan, rekap keuangan.
