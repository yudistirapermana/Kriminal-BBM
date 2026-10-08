from datetime import date

import pytest

from conftest import DATA
from kriminal_bbm.extract import (
    amar, extract_all, hasil_putusan, jenis_bbm, modus_dari_amar, parse_date, parse_number,
    pengadilan_asal, relevansi_bbm, rupiah_mentions, tingkat_from_nomor, volume_mentions,
)
from kriminal_bbm.pdftext import clean_text, extract_text


def test_parse_number():
    assert parse_number("5.353") == 5353
    assert parse_number("19.930.365,00") == 19930365
    assert parse_number("1.234,5") == 1234.5
    assert parse_number("92") == 92
    assert parse_number("3,5") == 3.5


def test_parse_date():
    assert parse_date("pada hari Rabu, tanggal 5 Pebruari 2020 oleh") == date(2020, 2, 5)
    assert parse_date("tanggal 12 Nopember 2021") == date(2021, 11, 12)
    assert parse_date("tidak ada tanggal") is None


@pytest.mark.parametrize("nomor,expected", [
    ("266/Pid.Sus/2019/PN.Pli", "PN"),
    ("11/PID.SUS-LH/2021/PTJMB", "PT"),
    ("4922 K/Pid.Sus/2022", "MA (Kasasi)"),
    ("580 PK/Pid.Sus/2023", "MA (PK)"),
    ("43-K/PM.II-11/AD/IX/2025", "Pengadilan Militer"),
])
def test_tingkat_from_nomor(nomor, expected):
    assert tingkat_from_nomor(nomor) == expected


@pytest.mark.parametrize("text,expected", [
    ("MENGADILI: 1. Menyatakan Terdakwa X telah terbukti secara sah dan meyakinkan bersalah melakukan "
     "tindak pidana ...; 2. Menjatuhkan pidana penjara selama 6 bulan", "Bersalah"),
    ("MENGADILI: 1. Menyatakan Terdakwa tidak terbukti secara sah dan meyakinkan bersalah; "
     "2. Membebaskan Terdakwa oleh karena itu dari semua dakwaan Penuntut Umum", "Tidak bersalah"),
    ("MENGADILI: Menyatakan perbuatan terdakwa terbukti tetapi bukan tindak pidana; "
     "Melepaskan Terdakwa oleh karena itu dari segala tuntutan hukum", "Tidak bersalah"),
    # bebas dari dakwaan primair, terbukti dakwaan subsidair -> Bersalah
    ("MENGADILI: 1. Menyatakan Terdakwa tidak terbukti ... dalam Primair; 2. Membebaskan terdakwa dari "
     "dakwaan Primair tersebut; 3. Menyatakan terdakwa terbukti secara sah dan menyakinkan bersalah", "Bersalah"),
    ("M E N G A D I L I: Menolak permohonan kasasi dari Pemohon Kasasi/Terdakwa X tersebut", "Bersalah"),
    ("M E N G A D I L I: Menolak permohonan kasasi dari Pemohon Kasasi/Penuntut Umum tersebut", None),
    ("MENGADILI: Mengabulkan kasasi; Membatalkan putusan PN yang membebaskan Terdakwa dari dakwaan; "
     "MENGADILI SENDIRI: Menyatakan Terdakwa terbukti secara sah dan meyakinkan bersalah", "Bersalah"),
])
def test_hasil_putusan(text, expected):
    assert hasil_putusan(text)[0] == expected


def test_amar_takes_last_heading_and_stops_at_demikian():
    t = ("Membaca putusan PN yang amarnya:\nMENGADILI:\n1. lama\n"
         "Menimbang ...\nM E N G A D I L I:\n- Menolak permohonan kasasi\nMENGADILI SENDIRI:\n1. baru\n"
         "Demikianlah diputuskan pada hari Senin, tanggal 5 September 2022\n")
    a = amar(t)
    assert a.startswith("M E N G A D I L I") and "baru" in a and "lama" not in a and "Demikian" not in a


def test_volume_and_rupiah():
    t = ("barang bukti solar sebanyak 5.353 (lima ribu tiga ratus lima puluh tiga) liter dalam drum "
         "kapasitas 200 (dua ratus) liter; dan 2 KL solar; hasil lelang sebesar Rp19.930.365,00; "
         "dijual Rp8.000/liter; denda sebesar Rp1.000.000,00")
    vols = {(m.value, m.kind) for m in volume_mentions(t)}
    assert (5353, "jumlah") in vols and (200, "kapasitas") in vols and (2000, "jumlah") in vols
    kinds = {m.kind: m.value for m in rupiah_mentions(t)}
    assert kinds["hasil_lelang"] == 19930365
    assert kinds["harga_per_liter"] == 8000
    assert kinds["denda"] == 1000000


def test_jenis_bbm_and_relevance():
    c = jenis_bbm("BBM jenis Bio Solar bersubsidi dan pertalite; bio solar lagi")
    assert c["Solar/Biosolar"] == 2 and c["Pertalite"] == 1
    assert relevansi_bbm(jenis_bbm("tabung LPG 3 kg"), "tabung LPG 3 kg") == "Tidak"
    assert relevansi_bbm(jenis_bbm("minyak mentah"), "minyak mentah") == "Sebagian"


def test_modus_and_pengadilan_asal():
    assert modus_dari_amar("terbukti melakukan kegiatan usaha hilir tanpa izin usaha penyimpanan") == ["53c"]
    assert "55" in modus_dari_amar("menyalahgunakan pengangkutan dan niaga BBM yang disubsidi pemerintah")
    assert pengadilan_asal("membatalkan Putusan Pengadilan Negeri Nanga Bulik Nomor 34/Pid.Sus") == "PN NANGA BULIK"
    assert pengadilan_asal("Pengadilan Negeri Martapura dibawah Register Nomor 1") == "PN MARTAPURA"


def test_clean_text_removes_boilerplate():
    raw = ("Mahkamah Agung Republik Indonesia\nDirektori Putusan Mahkamah Agung Republik Indonesia\n"
           "putusan.mahkamahagung.go.id\nHalaman 1 dari 17 Putusan Nomor 1/Pid.Sus/2020/PN X\n"
           "T erdakwa dipidana\nDisclaimer\nEmail : kepaniteraan@mahkamahagung.go.id Telp : 021\n")
    assert clean_text(raw).strip() == "Terdakwa dipidana"


PDF = DATA / "pdf" / "266_Pid.Sus_2019_PN Pli.pdf"


@pytest.mark.skipif(not PDF.exists(), reason="PDF contoh tidak tersedia")
def test_real_pdf_extraction():
    text = extract_text(PDF)
    assert "Disclaimer" not in text and "Nomor 266/Pid.Sus/2019/PN.Pli" in text
    r = extract_all(text)
    assert r["nomor_teks"] == "266/Pid.Sus/2019/PN.Pli"
    assert r["tanggal_putusan_teks"] == "5 Februari 2020"
    assert r["hasil_kandidat"] == "Bersalah"
    assert r["tahun_kejadian_kandidat"] == "2019"
    assert r["relevan_bbm_kandidat"] == "Ya"
    assert "92" in r["volume_liter_di_amar"].split(";")
    assert r["modus_dari_amar"] == "53c"
