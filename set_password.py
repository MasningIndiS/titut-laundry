"""Isi password asli untuk user di database.

Pemakaian:  python set_password.py owner passwordku
            python set_password.py pegawai1 passwordku
"""
import sys

import mysql.connector
from werkzeug.security import generate_password_hash

import config

if len(sys.argv) != 3:
    sys.exit("Pemakaian: python set_password.py <username> <password>")

username, password = sys.argv[1], sys.argv[2]
conn = mysql.connector.connect(**config.DB_CONFIG)
cur = conn.cursor()
cur.execute("UPDATE users SET password_hash = %s WHERE username = %s",
            (generate_password_hash(password), username))
conn.commit()
print("Berhasil." if cur.rowcount else "Username tidak ditemukan (atau password sama).")
conn.close()
