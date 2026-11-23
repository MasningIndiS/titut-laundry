"""Putra Laundry - Sistem Informasi Manajemen Laundry (Flask)."""
from functools import wraps

from flask import (Flask, abort, flash, redirect, render_template, request,
                   session, url_for)
from werkzeug.security import check_password_hash

from db import close_db, execute, query_all, query_one

app = Flask(__name__)
app.config.from_object("config")
app.teardown_appcontext(close_db)


# ---------------------------------------------------------------- util
@app.template_filter("rupiah")
def rupiah(value):
    try:
        return "Rp {:,.0f}".format(float(value or 0)).replace(",", ".")
    except (TypeError, ValueError):
        return "Rp 0"


def login_required(view):
    @wraps(view)
    def wrapped(*args, **kwargs):
        if "user_id" not in session:
            return redirect(url_for("login"))
        return view(*args, **kwargs)
    return wrapped


def owner_required(view):
    @wraps(view)
    def wrapped(*args, **kwargs):
        if session.get("role") != "owner":
            abort(403)
        return view(*args, **kwargs)
    return login_required(wrapped)


# ---------------------------------------------------------------- auth (US-01)
@app.route("/login", methods=["GET", "POST"])
def login():
    if request.method == "POST":
        username = request.form.get("username", "").strip()
        password = request.form.get("password", "")
        user = query_one(
            "SELECT id, nama, username, password_hash, role "
            "FROM users WHERE username = %s AND aktif = 1", (username,))
        try:
            ok = bool(user) and check_password_hash(user["password_hash"], password)
        except ValueError:          # hash belum diisi (masih placeholder)
            ok = False
        if ok:
            session.clear()
            session["user_id"] = user["id"]
            session["nama"] = user["nama"]
            session["role"] = user["role"]
            return redirect(url_for("dashboard"))
        flash("Username atau password salah.", "danger")
    return render_template("login.html")


@app.route("/logout")
def logout():
    session.clear()
    return redirect(url_for("login"))


# ---------------------------------------------------------------- dashboard (US-13, US-10)
@app.route("/")
@login_required
def dashboard():
    ringkasan = query_one("SELECT * FROM v_dashboard") if session["role"] == "owner" else None
    antrian = query_all("SELECT * FROM v_antrian_pekerjaan LIMIT 20")
    reminder = query_all("SELECT * FROM v_reminder_selesai ORDER BY tanggal_selesai")
    return render_template("dashboard.html", ringkasan=ringkasan,
                           antrian=antrian, reminder=reminder)


# ---------------------------------------------------------------- pelanggan (US-02)
@app.route("/pelanggan")
@login_required
def pelanggan_list():
    q = request.args.get("q", "").strip()
    rows = query_all(
        "SELECT id, nama, no_whatsapp, alamat, is_member FROM pelanggan "
        "WHERE nama LIKE %s OR no_whatsapp LIKE %s ORDER BY nama LIMIT 100",
        (f"%{q}%", f"%{q}%"))
    return render_template("pelanggan_list.html", rows=rows, q=q)


@app.route("/pelanggan/tambah", methods=["GET", "POST"])
@login_required
def pelanggan_tambah():
    if request.method == "POST":
        nama = request.form.get("nama", "").strip()
        wa = request.form.get("no_whatsapp", "").strip()
        if not nama or not wa:
            flash("Nama dan nomor WhatsApp wajib diisi.", "danger")
        else:
            execute(
                "INSERT INTO pelanggan (nama, no_whatsapp, alamat, is_member) "
                "VALUES (%s, %s, %s, %s)",
                (nama, wa, request.form.get("alamat", "").strip() or None,
                 1 if request.form.get("is_member") else 0))
            flash("Pelanggan berhasil ditambahkan.", "success")
            return redirect(url_for("pelanggan_list"))
    return render_template("pelanggan_form.html", p=None)


@app.route("/pelanggan/<int:pid>/ubah", methods=["GET", "POST"])
@login_required
def pelanggan_ubah(pid):
    p = query_one("SELECT * FROM pelanggan WHERE id = %s", (pid,))
    if not p:
        abort(404)
    if request.method == "POST":
        nama = request.form.get("nama", "").strip()
        wa = request.form.get("no_whatsapp", "").strip()
        if not nama or not wa:
            flash("Nama dan nomor WhatsApp wajib diisi.", "danger")
        else:
            execute(
                "UPDATE pelanggan SET nama=%s, no_whatsapp=%s, alamat=%s, is_member=%s "
                "WHERE id=%s",
                (nama, wa, request.form.get("alamat", "").strip() or None,
                 1 if request.form.get("is_member") else 0, pid))
            flash("Data pelanggan diperbarui.", "success")
            return redirect(url_for("pelanggan_list"))
    return render_template("pelanggan_form.html", p=p)


# ---------------------------------------------------------------- layanan & tarif (US-03, owner)
@app.route("/layanan")
@owner_required
def layanan_list():
    rows = query_all("SELECT * FROM layanan ORDER BY nama_layanan")
    return render_template("layanan_list.html", rows=rows)


@app.route("/layanan/tambah", methods=["GET", "POST"])
@owner_required
def layanan_tambah():
    if request.method == "POST":
        try:
            nama = request.form["nama_layanan"].strip()
            tarif = float(request.form["tarif_per_kg"])
            jam = int(request.form["estimasi_jam"])
            if not nama or tarif < 0 or jam < 0:
                raise ValueError
        except (KeyError, ValueError):
            flash("Isi nama, tarif, dan estimasi jam dengan benar.", "danger")
        else:
            execute("INSERT INTO layanan (nama_layanan, tarif_per_kg, estimasi_jam) "
                    "VALUES (%s, %s, %s)", (nama, tarif, jam))
            flash("Layanan ditambahkan.", "success")
            return redirect(url_for("layanan_list"))
    return render_template("layanan_form.html", l=None)


@app.route("/layanan/<int:lid>/ubah", methods=["GET", "POST"])
@owner_required
def layanan_ubah(lid):
    l = query_one("SELECT * FROM layanan WHERE id = %s", (lid,))
    if not l:
        abort(404)
    if request.method == "POST":
        try:
            nama = request.form["nama_layanan"].strip()
            tarif = float(request.form["tarif_per_kg"])
            jam = int(request.form["estimasi_jam"])
            if not nama or tarif < 0 or jam < 0:
                raise ValueError
        except (KeyError, ValueError):
            flash("Isi nama, tarif, dan estimasi jam dengan benar.", "danger")
        else:
            execute("UPDATE layanan SET nama_layanan=%s, tarif_per_kg=%s, estimasi_jam=%s, "
                    "aktif=%s WHERE id=%s",
                    (nama, tarif, jam, 1 if request.form.get("aktif") else 0, lid))
            flash("Layanan diperbarui.", "success")
            return redirect(url_for("layanan_list"))
    return render_template("layanan_form.html", l=l)


@app.errorhandler(403)
def forbidden(e):
    return render_template("error.html", kode=403, pesan="Halaman ini khusus owner."), 403


@app.errorhandler(404)
def not_found(e):
    return render_template("error.html", kode=404, pesan="Halaman tidak ditemukan."), 404


if __name__ == "__main__":
    app.run(debug=True)
