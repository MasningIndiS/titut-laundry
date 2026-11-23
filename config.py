"""Konfigurasi aplikasi. Ubah sesuai komputer Anda (default cocok untuk XAMPP)."""
import os

SECRET_KEY = os.environ.get("SECRET_KEY", "ganti-dengan-kunci-rahasia-anda")

DB_CONFIG = {
    "host": "localhost",
    "user": "root",
    "password": "",
    "database": "putra_laundry",
    "use_pure": True
}
