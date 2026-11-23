"""Setup database Putra Laundry dari Python (pengganti impor lewat phpMyAdmin).

Pemakaian (venv aktif, MySQL XAMPP menyala):
    python setup_db.py            # buat database + tabel + trigger + view + data contoh
    python setup_db.py --reset    # HAPUS database lama lalu buat ulang dari nol

Setelah selesai, skrip menawarkan mengisi password owner dan pegawai1.
"""
import argparse
import getpass
import sys
from pathlib import Path

import mysql.connector
from werkzeug.security import generate_password_hash

import config

BASE = Path(__file__).parent
KANDIDAT_SQL = [BASE / "database" / "putra_laundry_import.sql",
                BASE / "putra_laundry_import.sql"]


def cari_file_sql():
    for p in KANDIDAT_SQL:
        if p.exists():
            return p
    sys.exit("File putra_laundry_import.sql tidak ditemukan. Taruh di salah satu lokasi ini:\n  "
             + "\n  ".join(str(p) for p in KANDIDAT_SQL))


SQL_FILE = KANDIDAT_SQL[0]   # diganti oleh cari_file_sql() saat dijalankan


def split_statements(text):
    """Pecah isi file .sql menjadi pernyataan satu per satu.

    Mendukung perintah klien `DELIMITER` (dipakai untuk trigger & procedure),
    yang tidak dikenal oleh mysql-connector.
    """
    delimiter = ";"
    buf = []
    for line in text.splitlines():
        stripped = line.strip()

        if stripped.upper().startswith("DELIMITER "):
            delimiter = stripped.split(None, 1)[1].strip()
            continue

        # baris komentar / kosong di luar badan pernyataan dilewati
        if not buf and (not stripped or stripped.startswith("--")):
            continue

        buf.append(line)
        if stripped.endswith(delimiter):
            stmt = "\n".join(buf).rstrip()
            stmt = stmt[: -len(delimiter)].rstrip()
            if stmt:
                yield stmt
            buf = []

    rest = "\n".join(buf).strip()
    if rest:
        yield rest


def jalankan_sql(conn, sql_file):
    text = sql_file.read_text(encoding="utf-8")
    cur = conn.cursor()
    jumlah = 0
    for stmt in split_statements(text):
        try:
            cur.execute(stmt)
            if cur.with_rows:
                cur.fetchall()
        except mysql.connector.Error as err:
            ringkas = " ".join(stmt.split())[:110]
            sys.exit(f"\nGAGAL pada pernyataan ke-{jumlah + 1}:\n  {ringkas}...\n"
                     f"Pesan MySQL: {err}")
        jumlah += 1
    conn.commit()
    cur.close()
    return jumlah


def isi_password(conn, username, password):
    cur = conn.cursor()
    cur.execute("UPDATE putra_laundry.users SET password_hash = %s WHERE username = %s",
                (generate_password_hash(password), username))
    conn.commit()
    cur.close()


def main():
    parser = argparse.ArgumentParser(description="Setup database Putra Laundry")
    parser.add_argument("--reset", action="store_true",
                        help="hapus database lama (SEMUA DATA HILANG) lalu buat ulang")
    args = parser.parse_args()

    sql_file = cari_file_sql()          # cek file SQL dulu sebelum menyentuh database
    cfg = {k: v for k, v in config.DB_CONFIG.items() if k != "database"}
    nama_db = config.DB_CONFIG["database"]

    try:
        conn = mysql.connector.connect(**cfg)
    except mysql.connector.Error as err:
        sys.exit(f"Tidak bisa terhubung ke MySQL: {err}\n"
                 "Pastikan MySQL di XAMPP sudah Start dan cek DB_CONFIG di config.py.")

    if args.reset:
        if input(f"Database '{nama_db}' akan DIHAPUS beserta seluruh datanya. Ketik 'ya' untuk lanjut: ").strip().lower() != "ya":
            sys.exit("Dibatalkan.")
        cur = conn.cursor()
        cur.execute(f"DROP DATABASE IF EXISTS `{nama_db}`")
        cur.close()

    print(f"Membaca {sql_file} ...")
    n = jalankan_sql(conn, sql_file)
    print(f"Selesai: {n} pernyataan SQL dijalankan. Database '{nama_db}' siap.")

    print("\nIsi password login (kosongkan lalu Enter untuk melewati):")
    for username in ("owner", "pegawai1"):
        pw = getpass.getpass(f"  Password untuk {username}: ")
        if pw:
            isi_password(conn, username, pw)
            print(f"  -> password {username} disimpan.")
    conn.close()
    print("\nSelanjutnya: python app.py lalu buka http://localhost:5000")


if __name__ == "__main__":
    main()
