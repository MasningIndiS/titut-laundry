-- =====================================================================
--  SISTEM INFORMASI MANAJEMEN LAUNDRY - PUTRA LAUNDRY
--  Skema database MySQL 8.x (kompatibel MariaDB 10.5+)
--  Berdasarkan Proposal PPL v1.2 (Tim Insyaallah Titut Lancar)
--
--  Isi file : tabel, trigger, stored procedure, view, dan data awal.
--  Aman dijalankan ulang (IF NOT EXISTS / DROP ... IF EXISTS / INSERT IGNORE).
--  Cara pakai: mysql -u root -p < putra_laundry_schema.sql
-- =====================================================================

CREATE DATABASE IF NOT EXISTS putra_laundry
  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE putra_laundry;

-- ---------------------------------------------------------------------
-- 1. TABEL
-- ---------------------------------------------------------------------

-- Pengguna sistem: owner & pegawai (US-01). Password disimpan sebagai hash.
CREATE TABLE IF NOT EXISTS users (
  id            INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  nama          VARCHAR(100) NOT NULL,
  username      VARCHAR(50)  NOT NULL UNIQUE,
  password_hash VARCHAR(255) NOT NULL,
  role          ENUM('owner','pegawai') NOT NULL DEFAULT 'pegawai',
  aktif         TINYINT(1)   NOT NULL DEFAULT 1,
  created_at    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

-- Data pelanggan, termasuk member (US-02, rev 1.1 poin 2)
CREATE TABLE IF NOT EXISTS pelanggan (
  id            INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  nama          VARCHAR(100) NOT NULL,
  no_whatsapp   VARCHAR(20)  NOT NULL,
  alamat        VARCHAR(255) NULL,
  is_member     TINYINT(1)   NOT NULL DEFAULT 0,
  created_at    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  INDEX idx_pelanggan_nama (nama),
  INDEX idx_pelanggan_wa (no_whatsapp)
) ENGINE=InnoDB;

-- Jenis layanan & tarif per kg (US-03). estimasi_jam dipakai untuk dashboard (US-16)
CREATE TABLE IF NOT EXISTS layanan (
  id            INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  nama_layanan  VARCHAR(100) NOT NULL UNIQUE,
  tarif_per_kg  DECIMAL(12,2) NOT NULL CHECK (tarif_per_kg >= 0),
  estimasi_jam  SMALLINT UNSIGNED NOT NULL DEFAULT 24,
  aktif         TINYINT(1) NOT NULL DEFAULT 1,
  created_at    DATETIME   NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at    DATETIME   NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB;

-- Penghitung nomor transaksi per hari (aman untuk pemakaian bersamaan)
CREATE TABLE IF NOT EXISTS nomor_urut (
  tanggal DATE PRIMARY KEY,
  urutan  INT UNSIGNED NOT NULL DEFAULT 0
) ENGINE=InnoDB;

-- Header transaksi / pesanan (US-04, US-06)
-- Status pengerjaan: Diterima -> Dicuci -> Dikeringkan -> Disetrika -> Selesai -> Diambil
-- Status pembayaran: Belum Lunas / Lunas (dua informasi yang terpisah)
CREATE TABLE IF NOT EXISTS transaksi (
  id                INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  no_transaksi      VARCHAR(20)  NULL UNIQUE,            -- diisi otomatis oleh trigger
  pelanggan_id      INT UNSIGNED NOT NULL,
  user_id           INT UNSIGNED NOT NULL,                -- pegawai yang mencatat
  tanggal_masuk     DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  estimasi_selesai  DATETIME     NULL,
  tanggal_selesai   DATETIME     NULL,
  tanggal_diambil   DATETIME     NULL,
  total_berat       DECIMAL(8,2)  NOT NULL DEFAULT 0,
  total_biaya       DECIMAL(14,2) NOT NULL DEFAULT 0,
  status_pengerjaan ENUM('Diterima','Dicuci','Dikeringkan','Disetrika','Selesai','Diambil')
                    NOT NULL DEFAULT 'Diterima',
  status_pembayaran ENUM('Belum Lunas','Lunas') NOT NULL DEFAULT 'Belum Lunas',
  keterangan        VARCHAR(255) NULL,                    -- mis. jumlah pakaian, noda, dsb.
  created_at        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT fk_trx_pelanggan FOREIGN KEY (pelanggan_id) REFERENCES pelanggan(id),
  CONSTRAINT fk_trx_user      FOREIGN KEY (user_id)      REFERENCES users(id),
  INDEX idx_trx_tanggal (tanggal_masuk),
  INDEX idx_trx_status  (status_pengerjaan, status_pembayaran),
  INDEX idx_trx_pelanggan (pelanggan_id)
) ENGINE=InnoDB;

-- Detail transaksi: layanan + berat + rincian cucian (US-05, rev 1.1 poin 3).
-- tarif disimpan "snapshot" agar laporan lama tidak berubah saat tarif diganti.
CREATE TABLE IF NOT EXISTS detail_transaksi (
  id              INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  transaksi_id    INT UNSIGNED NOT NULL,
  layanan_id      INT UNSIGNED NOT NULL,
  berat_kg        DECIMAL(8,2)  NOT NULL CHECK (berat_kg > 0),
  tarif_per_kg    DECIMAL(12,2) NULL,                     -- diisi trigger dari layanan
  subtotal        DECIMAL(14,2) NULL,                     -- berat x tarif, diisi trigger
  keterangan_cucian VARCHAR(255) NULL,                    -- mis. "5 kemeja, 2 celana, 1 sprei"
  CONSTRAINT fk_dt_trx     FOREIGN KEY (transaksi_id) REFERENCES transaksi(id) ON DELETE CASCADE,
  CONSTRAINT fk_dt_layanan FOREIGN KEY (layanan_id)   REFERENCES layanan(id),
  INDEX idx_dt_trx (transaksi_id)
) ENGINE=InnoDB;

-- Pembayaran (US-11). Boleh dicicil; status lunas dihitung otomatis.
CREATE TABLE IF NOT EXISTS pembayaran (
  id              INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  transaksi_id    INT UNSIGNED NOT NULL,
  user_id         INT UNSIGNED NOT NULL,
  jumlah          DECIMAL(14,2) NOT NULL CHECK (jumlah > 0),
  metode          ENUM('Tunai','Transfer','QRIS') NOT NULL DEFAULT 'Tunai',
  tanggal_bayar   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  catatan         VARCHAR(255) NULL,
  CONSTRAINT fk_bayar_trx  FOREIGN KEY (transaksi_id) REFERENCES transaksi(id),
  CONSTRAINT fk_bayar_user FOREIGN KEY (user_id)      REFERENCES users(id),
  INDEX idx_bayar_tgl (tanggal_bayar),
  INDEX idx_bayar_trx (transaksi_id)
) ENGINE=InnoDB;

-- Riwayat perubahan status pengerjaan -> melacak cucian & rekap kerja pegawai
-- (masalah kehilangan pakaian; rev 1.1 poin 8)
CREATE TABLE IF NOT EXISTS riwayat_status (
  id            INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  transaksi_id  INT UNSIGNED NOT NULL,
  status        ENUM('Diterima','Dicuci','Dikeringkan','Disetrika','Selesai','Diambil') NOT NULL,
  user_id       INT UNSIGNED NULL,
  waktu         DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  catatan       VARCHAR(255) NULL,
  CONSTRAINT fk_rs_trx  FOREIGN KEY (transaksi_id) REFERENCES transaksi(id) ON DELETE CASCADE,
  CONSTRAINT fk_rs_user FOREIGN KEY (user_id)      REFERENCES users(id) ON DELETE SET NULL,
  INDEX idx_rs_trx (transaksi_id),
  INDEX idx_rs_waktu (waktu)
) ENGINE=InnoDB;

-- Antrean notifikasi WhatsApp (US-07, US-10). Aplikasi Flask yang mengirim lalu
-- mengubah status_kirim. Juga dipakai sebagai reminder "cucian selesai belum diinfokan".
CREATE TABLE IF NOT EXISTS notifikasi_whatsapp (
  id            INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  transaksi_id  INT UNSIGNED NOT NULL,
  jenis         ENUM('nota','pembayaran','selesai') NOT NULL,
  no_tujuan     VARCHAR(20) NOT NULL,
  pesan         TEXT NULL,
  status_kirim  ENUM('Menunggu','Terkirim','Gagal') NOT NULL DEFAULT 'Menunggu',
  created_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  sent_at       DATETIME NULL,
  CONSTRAINT fk_wa_trx FOREIGN KEY (transaksi_id) REFERENCES transaksi(id) ON DELETE CASCADE,
  INDEX idx_wa_status (status_kirim),
  INDEX idx_wa_trx (transaksi_id, jenis)
) ENGINE=InnoDB;

-- Rekap keuangan di luar pembayaran pelanggan: modal & pengeluaran (US-14, rev 1.1 poin 7)
-- Pemasukan diambil dari tabel pembayaran, jadi tidak diinput dua kali.
CREATE TABLE IF NOT EXISTS keuangan (
  id          INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  tanggal     DATE NOT NULL,
  jenis       ENUM('Modal','Pengeluaran') NOT NULL,
  kategori    VARCHAR(50) NULL,                    -- mis. Deterjen, Listrik, Air, Gaji, Gas
  jumlah      DECIMAL(14,2) NOT NULL CHECK (jumlah > 0),
  keterangan  VARCHAR(255) NULL,
  user_id     INT UNSIGNED NOT NULL,
  created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_keu_user FOREIGN KEY (user_id) REFERENCES users(id),
  INDEX idx_keu_tgl (tanggal, jenis)
) ENGINE=InnoDB;


-- ---------------------------------------------------------------------
-- 2. STORED PROCEDURE & TRIGGER
-- ---------------------------------------------------------------------
DELIMITER $$

-- Hitung ulang total berat, total biaya, dan estimasi selesai sebuah transaksi
DROP PROCEDURE IF EXISTS sp_hitung_ulang_transaksi $$
CREATE PROCEDURE sp_hitung_ulang_transaksi(IN p_trx_id INT UNSIGNED)
BEGIN
  DECLARE v_berat DECIMAL(8,2);
  DECLARE v_biaya DECIMAL(14,2);
  DECLARE v_jam   INT;

  SELECT COALESCE(SUM(d.berat_kg),0), COALESCE(SUM(d.subtotal),0), COALESCE(MAX(l.estimasi_jam),0)
    INTO v_berat, v_biaya, v_jam
    FROM detail_transaksi d
    JOIN layanan l ON l.id = d.layanan_id
   WHERE d.transaksi_id = p_trx_id;

  UPDATE transaksi
     SET total_berat      = v_berat,
         total_biaya      = v_biaya,
         estimasi_selesai = DATE_ADD(tanggal_masuk, INTERVAL v_jam HOUR)
   WHERE id = p_trx_id;

  CALL sp_update_status_bayar(p_trx_id);
END $$

-- Tentukan status pembayaran: Lunas bila total dibayar >= total biaya
DROP PROCEDURE IF EXISTS sp_update_status_bayar $$
CREATE PROCEDURE sp_update_status_bayar(IN p_trx_id INT UNSIGNED)
BEGIN
  DECLARE v_total DECIMAL(14,2);
  DECLARE v_bayar DECIMAL(14,2);
  DECLARE v_lama  VARCHAR(20);
  DECLARE v_baru  VARCHAR(20);
  DECLARE v_wa    VARCHAR(20);

  SELECT t.total_biaya, t.status_pembayaran, p.no_whatsapp
    INTO v_total, v_lama, v_wa
    FROM transaksi t JOIN pelanggan p ON p.id = t.pelanggan_id
   WHERE t.id = p_trx_id;

  SELECT COALESCE(SUM(jumlah),0) INTO v_bayar FROM pembayaran WHERE transaksi_id = p_trx_id;

  SET v_baru = IF(v_total > 0 AND v_bayar >= v_total, 'Lunas', 'Belum Lunas');

  IF v_baru <> v_lama THEN
    UPDATE transaksi SET status_pembayaran = v_baru WHERE id = p_trx_id;
    -- antre notifikasi WhatsApp saat berubah menjadi Lunas (rev 1.1 poin 4)
    IF v_baru = 'Lunas' THEN
      INSERT INTO notifikasi_whatsapp (transaksi_id, jenis, no_tujuan)
      VALUES (p_trx_id, 'pembayaran', v_wa);
    END IF;
  END IF;
END $$

-- Nomor transaksi otomatis: PL-YYYYMMDD-0001 (US-06)
DROP TRIGGER IF EXISTS trg_transaksi_bi $$
CREATE TRIGGER trg_transaksi_bi BEFORE INSERT ON transaksi
FOR EACH ROW
BEGIN
  DECLARE v_urut INT UNSIGNED;
  IF NEW.no_transaksi IS NULL THEN
    INSERT INTO nomor_urut (tanggal, urutan) VALUES (DATE(NEW.tanggal_masuk), 1)
      ON DUPLICATE KEY UPDATE urutan = urutan + 1;
    SELECT urutan INTO v_urut FROM nomor_urut WHERE tanggal = DATE(NEW.tanggal_masuk);
    SET NEW.no_transaksi = CONCAT('PL-', DATE_FORMAT(NEW.tanggal_masuk,'%Y%m%d'), '-', LPAD(v_urut, 4, '0'));
  END IF;
END $$

-- Catat status awal "Diterima" ke riwayat
DROP TRIGGER IF EXISTS trg_transaksi_ai $$
CREATE TRIGGER trg_transaksi_ai AFTER INSERT ON transaksi
FOR EACH ROW
BEGIN
  INSERT INTO riwayat_status (transaksi_id, status, user_id) VALUES (NEW.id, NEW.status_pengerjaan, NEW.user_id);
END $$

-- Validasi alur status (hanya boleh maju satu tahap) + isi tanggal selesai/diambil
DROP TRIGGER IF EXISTS trg_transaksi_bu $$
CREATE TRIGGER trg_transaksi_bu BEFORE UPDATE ON transaksi
FOR EACH ROW
BEGIN
  IF NEW.status_pengerjaan <> OLD.status_pengerjaan THEN
    IF FIELD(NEW.status_pengerjaan,'Diterima','Dicuci','Dikeringkan','Disetrika','Selesai','Diambil')
       <> FIELD(OLD.status_pengerjaan,'Diterima','Dicuci','Dikeringkan','Disetrika','Selesai','Diambil') + 1 THEN
      SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Status pengerjaan harus berurutan: Diterima > Dicuci > Dikeringkan > Disetrika > Selesai > Diambil';
    END IF;
    IF NEW.status_pengerjaan = 'Selesai' THEN SET NEW.tanggal_selesai = NOW(); END IF;
    IF NEW.status_pengerjaan = 'Diambil' THEN SET NEW.tanggal_diambil = NOW(); END IF;
  END IF;
END $$

-- Catat riwayat status & antre WhatsApp "cucian selesai"
-- Catatan: user_id pada riwayat diisi pegawai pencatat transaksi; jika aplikasi ingin
-- mencatat pegawai yang mengubah status, set variabel sesi dulu: SET @app_user_id = <id>;
DROP TRIGGER IF EXISTS trg_transaksi_au $$
CREATE TRIGGER trg_transaksi_au AFTER UPDATE ON transaksi
FOR EACH ROW
BEGIN
  DECLARE v_wa VARCHAR(20);
  IF NEW.status_pengerjaan <> OLD.status_pengerjaan THEN
    INSERT INTO riwayat_status (transaksi_id, status, user_id)
    VALUES (NEW.id, NEW.status_pengerjaan, COALESCE(@app_user_id, NEW.user_id));

    IF NEW.status_pengerjaan = 'Selesai' THEN
      SELECT no_whatsapp INTO v_wa FROM pelanggan WHERE id = NEW.pelanggan_id;
      INSERT INTO notifikasi_whatsapp (transaksi_id, jenis, no_tujuan) VALUES (NEW.id, 'selesai', v_wa);
    END IF;
  END IF;
END $$

-- Isi tarif & subtotal otomatis dari tabel layanan (US-05)
DROP TRIGGER IF EXISTS trg_detail_bi $$
CREATE TRIGGER trg_detail_bi BEFORE INSERT ON detail_transaksi
FOR EACH ROW
BEGIN
  IF NEW.tarif_per_kg IS NULL THEN
    SET NEW.tarif_per_kg = (SELECT tarif_per_kg FROM layanan WHERE id = NEW.layanan_id);
  END IF;
  SET NEW.subtotal = ROUND(NEW.berat_kg * NEW.tarif_per_kg, 2);
END $$

DROP TRIGGER IF EXISTS trg_detail_bu $$
CREATE TRIGGER trg_detail_bu BEFORE UPDATE ON detail_transaksi
FOR EACH ROW
BEGIN
  SET NEW.subtotal = ROUND(NEW.berat_kg * NEW.tarif_per_kg, 2);
END $$

DROP TRIGGER IF EXISTS trg_detail_ai $$
CREATE TRIGGER trg_detail_ai AFTER INSERT ON detail_transaksi
FOR EACH ROW BEGIN CALL sp_hitung_ulang_transaksi(NEW.transaksi_id); END $$

DROP TRIGGER IF EXISTS trg_detail_au $$
CREATE TRIGGER trg_detail_au AFTER UPDATE ON detail_transaksi
FOR EACH ROW BEGIN CALL sp_hitung_ulang_transaksi(NEW.transaksi_id); END $$

DROP TRIGGER IF EXISTS trg_detail_ad $$
CREATE TRIGGER trg_detail_ad AFTER DELETE ON detail_transaksi
FOR EACH ROW BEGIN CALL sp_hitung_ulang_transaksi(OLD.transaksi_id); END $$

-- Status pembayaran otomatis tiap ada pembayaran baru/diubah/dihapus (US-11)
DROP TRIGGER IF EXISTS trg_bayar_ai $$
CREATE TRIGGER trg_bayar_ai AFTER INSERT ON pembayaran
FOR EACH ROW BEGIN CALL sp_update_status_bayar(NEW.transaksi_id); END $$

DROP TRIGGER IF EXISTS trg_bayar_au $$
CREATE TRIGGER trg_bayar_au AFTER UPDATE ON pembayaran
FOR EACH ROW BEGIN CALL sp_update_status_bayar(NEW.transaksi_id); END $$

DROP TRIGGER IF EXISTS trg_bayar_ad $$
CREATE TRIGGER trg_bayar_ad AFTER DELETE ON pembayaran
FOR EACH ROW BEGIN CALL sp_update_status_bayar(OLD.transaksi_id); END $$

DELIMITER ;


-- ---------------------------------------------------------------------
-- 3. VIEW (dashboard, laporan, reminder)
-- ---------------------------------------------------------------------

-- Daftar pesanan lengkap + sisa tagihan (US-08, pencarian pesanan)
CREATE OR REPLACE VIEW v_daftar_pesanan AS
SELECT t.id, t.no_transaksi, p.nama AS pelanggan, p.no_whatsapp,
       t.tanggal_masuk, t.estimasi_selesai, t.tanggal_selesai, t.tanggal_diambil,
       t.total_berat, t.total_biaya,
       COALESCE(b.dibayar,0)                 AS total_dibayar,
       t.total_biaya - COALESCE(b.dibayar,0) AS sisa_tagihan,
       t.status_pengerjaan, t.status_pembayaran, t.keterangan,
       u.nama AS dicatat_oleh
FROM transaksi t
JOIN pelanggan p ON p.id = t.pelanggan_id
JOIN users u     ON u.id = t.user_id
LEFT JOIN (SELECT transaksi_id, SUM(jumlah) AS dibayar FROM pembayaran GROUP BY transaksi_id) b
       ON b.transaksi_id = t.id;

-- Tabel status laundry / urutan pengerjaan: yang masuk lebih dulu tampil paling atas (rev 1.1 poin 8)
CREATE OR REPLACE VIEW v_antrian_pekerjaan AS
SELECT ROW_NUMBER() OVER (ORDER BY t.tanggal_masuk) AS urutan,
       t.id, t.no_transaksi, p.nama AS pelanggan, t.total_berat,
       t.status_pengerjaan, t.status_pembayaran,
       t.tanggal_masuk, t.estimasi_selesai,
       CASE WHEN t.status_pengerjaan <> 'Selesai' AND t.estimasi_selesai < NOW()
            THEN 1 ELSE 0 END AS terlambat
FROM transaksi t JOIN pelanggan p ON p.id = t.pelanggan_id
WHERE t.status_pengerjaan <> 'Diambil';

-- Reminder: cucian sudah Selesai tetapi belum diambil (US-10, rev 1.1 poin 12),
-- lengkap dengan info apakah WhatsApp "selesai" sudah terkirim.
CREATE OR REPLACE VIEW v_reminder_selesai AS
SELECT t.id, t.no_transaksi, p.nama AS pelanggan, p.no_whatsapp,
       t.tanggal_selesai, TIMESTAMPDIFF(HOUR, t.tanggal_selesai, NOW()) AS jam_menunggu,
       t.status_pembayaran,
       EXISTS (SELECT 1 FROM notifikasi_whatsapp w
                WHERE w.transaksi_id = t.id AND w.jenis = 'selesai'
                  AND w.status_kirim = 'Terkirim') AS sudah_diberi_tahu
FROM transaksi t JOIN pelanggan p ON p.id = t.pelanggan_id
WHERE t.status_pengerjaan = 'Selesai';

-- Pemasukan per hari (dari pembayaran yang benar-benar diterima)
CREATE OR REPLACE VIEW v_pemasukan_harian AS
SELECT DATE(tanggal_bayar) AS tanggal, COUNT(DISTINCT transaksi_id) AS jumlah_transaksi,
       SUM(jumlah) AS pemasukan
FROM pembayaran GROUP BY DATE(tanggal_bayar);

-- Rekap keuangan bulanan: modal, pemasukan, pengeluaran, keuntungan (US-12, US-14)
CREATE OR REPLACE VIEW v_rekap_keuangan_bulanan AS
SELECT bulan,
       SUM(modal)        AS modal,
       SUM(pemasukan)    AS pemasukan,
       SUM(pengeluaran)  AS pengeluaran,
       SUM(pemasukan) - SUM(pengeluaran) AS keuntungan
FROM (
  SELECT DATE_FORMAT(tanggal_bayar,'%Y-%m') AS bulan, 0 AS modal, jumlah AS pemasukan, 0 AS pengeluaran
    FROM pembayaran
  UNION ALL
  SELECT DATE_FORMAT(tanggal,'%Y-%m'),
         IF(jenis='Modal',jumlah,0), 0, IF(jenis='Pengeluaran',jumlah,0)
    FROM keuangan
) x
GROUP BY bulan;

-- Statistik jumlah cucian selesai per hari (US-15)
CREATE OR REPLACE VIEW v_statistik_selesai AS
SELECT DATE(tanggal_selesai) AS tanggal, COUNT(*) AS jumlah_cucian, SUM(total_berat) AS total_kg
FROM transaksi
WHERE tanggal_selesai IS NOT NULL
GROUP BY DATE(tanggal_selesai);

-- Ringkasan dashboard owner (US-13) - satu baris
CREATE OR REPLACE VIEW v_dashboard AS
SELECT
  (SELECT COUNT(*) FROM transaksi WHERE DATE(tanggal_masuk) = CURDATE())                       AS transaksi_hari_ini,
  (SELECT COALESCE(SUM(jumlah),0) FROM pembayaran WHERE DATE(tanggal_bayar) = CURDATE())       AS pemasukan_hari_ini,
  (SELECT COALESCE(SUM(jumlah),0) FROM pembayaran
    WHERE YEAR(tanggal_bayar) = YEAR(CURDATE()) AND MONTH(tanggal_bayar) = MONTH(CURDATE()))   AS pemasukan_bulan_ini,
  (SELECT COUNT(*) FROM transaksi WHERE status_pengerjaan NOT IN ('Selesai','Diambil'))        AS sedang_diproses,
  (SELECT COUNT(*) FROM transaksi WHERE status_pengerjaan = 'Selesai')                         AS siap_diambil,
  (SELECT COUNT(*) FROM transaksi WHERE status_pembayaran = 'Belum Lunas')                     AS belum_lunas,
  (SELECT COALESCE(SUM(total_biaya),0) - COALESCE((SELECT SUM(jumlah) FROM pembayaran),0)
     FROM transaksi)                                                                           AS total_piutang,
  (SELECT COUNT(*) FROM transaksi WHERE DATE(tanggal_selesai) = CURDATE())                     AS selesai_hari_ini;


-- ---------------------------------------------------------------------
-- 4. DATA AWAL (aman dijalankan ulang)
-- ---------------------------------------------------------------------
-- PENTING: password_hash di bawah hanya placeholder. Ganti dengan hash asli dari Flask:
--   from werkzeug.security import generate_password_hash
--   print(generate_password_hash('password_anda'))
INSERT INTO users (id, nama, username, password_hash, role) VALUES
  (1, 'Yuni',    'owner',   'GANTI_DENGAN_HASH', 'owner'),
  (2, 'Pegawai 1','pegawai1','GANTI_DENGAN_HASH', 'pegawai')
ON DUPLICATE KEY UPDATE nama = VALUES(nama);

-- Tarif contoh - sesuaikan dengan tarif asli Putra Laundry
INSERT INTO layanan (id, nama_layanan, tarif_per_kg, estimasi_jam) VALUES
  (1, 'Cuci Kering',            5000, 24),
  (2, 'Cuci Setrika',           7000, 48),
  (3, 'Setrika Saja',           4000, 24),
  (4, 'Cuci Setrika Express',  10000, 12)
ON DUPLICATE KEY UPDATE nama_layanan = VALUES(nama_layanan);


-- ---------------------------------------------------------------------
-- 5. DATA CONTOH (hanya terisi jika tabel transaksi masih kosong; aman diimpor ulang)
--    Hapus bagian ini jika tidak ingin data contoh.
-- ---------------------------------------------------------------------
DELIMITER $$

DROP PROCEDURE IF EXISTS sp_seed_contoh $$
CREATE PROCEDURE sp_seed_contoh()
BEGIN
  DECLARE p1, p2, p3, t1, t2, t3 INT UNSIGNED;

  IF (SELECT COUNT(*) FROM transaksi) = 0 THEN

    INSERT INTO pelanggan (nama, no_whatsapp, alamat, is_member)
    VALUES ('Budi Santoso', '081234567801', 'Kesemen, Gresik', 0);
    SET p1 = LAST_INSERT_ID();
    INSERT INTO pelanggan (nama, no_whatsapp, alamat, is_member)
    VALUES ('Siti Aminah', '081234567802', 'Sukorame, Gresik', 1);
    SET p2 = LAST_INSERT_ID();
    INSERT INTO pelanggan (nama, no_whatsapp, alamat, is_member)
    VALUES ('Rudi Hartono', '081234567803', 'Gresik', 0);
    SET p3 = LAST_INSERT_ID();

    -- Transaksi 1: sudah lunas & sudah diambil
    INSERT INTO transaksi (pelanggan_id, user_id, tanggal_masuk, keterangan)
    VALUES (p1, 2, NOW() - INTERVAL 3 DAY, 'Pakaian harian');
    SET t1 = LAST_INSERT_ID();
    INSERT INTO detail_transaksi (transaksi_id, layanan_id, berat_kg, keterangan_cucian)
    VALUES (t1, 2, 5.0, '4 kemeja, 3 celana');
    INSERT INTO pembayaran (transaksi_id, user_id, jumlah, metode) VALUES (t1, 2, 35000, 'Tunai');
    UPDATE transaksi SET status_pengerjaan = 'Dicuci'      WHERE id = t1;
    UPDATE transaksi SET status_pengerjaan = 'Dikeringkan' WHERE id = t1;
    UPDATE transaksi SET status_pengerjaan = 'Disetrika'   WHERE id = t1;
    UPDATE transaksi SET status_pengerjaan = 'Selesai'     WHERE id = t1;
    UPDATE transaksi SET status_pengerjaan = 'Diambil'     WHERE id = t1;

    -- Transaksi 2: selesai, dibayar sebagian (muncul di reminder & tagihan)
    INSERT INTO transaksi (pelanggan_id, user_id, tanggal_masuk, keterangan)
    VALUES (p2, 2, NOW() - INTERVAL 1 DAY, 'Member');
    SET t2 = LAST_INSERT_ID();
    INSERT INTO detail_transaksi (transaksi_id, layanan_id, berat_kg, keterangan_cucian)
    VALUES (t2, 1, 3.5, 'Sprei & selimut');
    INSERT INTO detail_transaksi (transaksi_id, layanan_id, berat_kg, keterangan_cucian)
    VALUES (t2, 3, 2.0, 'Kemeja');
    INSERT INTO pembayaran (transaksi_id, user_id, jumlah, metode) VALUES (t2, 2, 10000, 'Transfer');
    UPDATE transaksi SET status_pengerjaan = 'Dicuci'      WHERE id = t2;
    UPDATE transaksi SET status_pengerjaan = 'Dikeringkan' WHERE id = t2;
    UPDATE transaksi SET status_pengerjaan = 'Disetrika'   WHERE id = t2;
    UPDATE transaksi SET status_pengerjaan = 'Selesai'     WHERE id = t2;

    -- Transaksi 3: baru masuk, sedang dicuci, belum bayar
    INSERT INTO transaksi (pelanggan_id, user_id, keterangan)
    VALUES (p3, 2, 'Express');
    SET t3 = LAST_INSERT_ID();
    INSERT INTO detail_transaksi (transaksi_id, layanan_id, berat_kg, keterangan_cucian)
    VALUES (t3, 4, 4.0, 'Seragam kerja');
    UPDATE transaksi SET status_pengerjaan = 'Dicuci' WHERE id = t3;

    -- Keuangan
    INSERT INTO keuangan (tanggal, jenis, kategori, jumlah, keterangan, user_id) VALUES
      (CURDATE() - INTERVAL 30 DAY, 'Modal',       'Modal awal', 5000000, 'Modal usaha', 1),
      (CURDATE() - INTERVAL 5 DAY,  'Pengeluaran', 'Deterjen',    150000, 'Beli deterjen & pewangi', 1),
      (CURDATE() - INTERVAL 2 DAY,  'Pengeluaran', 'Listrik',     300000, 'Tagihan listrik', 1);
  END IF;
END $$

DELIMITER ;

CALL sp_seed_contoh();
DROP PROCEDURE IF EXISTS sp_seed_contoh;

-- Cek cepat hasil impor:
-- SELECT * FROM v_daftar_pesanan;
-- SELECT * FROM v_dashboard;
