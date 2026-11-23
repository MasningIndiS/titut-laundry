"""Helper koneksi MySQL. Satu koneksi per request, otomatis ditutup."""
import mysql.connector
from flask import g, current_app


def get_db():
    if "db" not in g:
        g.db = mysql.connector.connect(**current_app.config["DB_CONFIG"])
    return g.db


def close_db(error=None):
    conn = g.pop("db", None)
    if conn is not None and conn.is_connected():
        conn.close()


def query_all(sql, params=None):
    cur = get_db().cursor(dictionary=True)
    cur.execute(sql, params or ())
    rows = cur.fetchall()
    cur.close()
    return rows


def query_one(sql, params=None):
    rows = query_all(sql, params)
    return rows[0] if rows else None


def execute(sql, params=None):
    """INSERT/UPDATE/DELETE. Mengembalikan id baris terakhir (untuk INSERT)."""
    conn = get_db()
    cur = conn.cursor()
    cur.execute(sql, params or ())
    conn.commit()
    last_id = cur.lastrowid
    cur.close()
    return last_id
