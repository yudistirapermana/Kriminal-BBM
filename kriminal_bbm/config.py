"""Konstanta proyek: lokasi berkas, URL situs, dan kata kunci BBM."""

from __future__ import annotations

from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
DATA_DIR = REPO_ROOT / "Data Kriminal BBM"
PDF_DIR = DATA_DIR / "pdf"
REKAP_CSV = DATA_DIR / "rekap_putusan_kriminalitas_BBM_2020-2026.csv"
EXCLUDED_CSV = DATA_DIR / "putusan_dikeluarkan_tidak_relevan.csv"
OUTPUT_DIR = DATA_DIR / "hasil_olahan"

# Folder kerja yang tidak masuk git (lihat .gitignore).
CACHE_DIR = REPO_ROOT / "cache"
HTML_CACHE_DIR = CACHE_DIR / "html"
TEXT_CACHE_DIR = CACHE_DIR / "teks"
RAW_DIR = REPO_ROOT / "data_mentah"

BASE_URL = "https://putusan3.mahkamahagung.go.id"

# Halaman daftar klasifikasi Pidana Khusus > Migas. Situs memakai pola
# /direktori/index/kategori/<slug>.html; bila slug berubah, salin URL dari peramban
# lalu berikan lewat opsi --kategori-url.
DEFAULT_CATEGORY_URL = f"{BASE_URL}/direktori/index/kategori/migas-1.html"

USER_AGENT = (
    "Mozilla/5.0 (compatible; KajianBBM-UGM/0.1; riset akademik; "
    "+https://github.com/yudistirapermana/Kriminal-BBM)"
)

TAHUN_AWAL = 2020
TAHUN_AKHIR = 2026

# Kata kunci untuk menyaring putusan yang objeknya BBM (huruf kecil).
# Urutan penting: pola yang lebih spesifik diletakkan lebih dulu.
BBM_KEYWORDS: dict[str, list[str]] = {
    "Solar/Biosolar": [r"bio\s*-?\s*solar", r"\bsolar\b", r"\bhsd\b", r"high speed diesel", r"minyak solar"],
    "Pertalite": [r"pertalite", r"pertalit\b"],
    "Premium": [r"\bpremium\b"],
    "Bensin (jenis tidak disebut)": [r"\bbensin\b"],
    "Pertamax": [r"pertamax"],
    "Dexlite": [r"dexlite"],
    "Pertamina Dex": [r"pertamina\s+dex\b"],
    "Minyak tanah": [r"minyak\s+tanah", r"\bkerosin", r"\bkerosene"],
    "Avtur": [r"\bavtur\b"],
    "MFO/Minyak bakar": [r"\bmfo\b", r"marine fuel oil", r"minyak bakar"],
    "Minyak mentah": [r"minyak\s+mentah", r"crude oil", r"kondensat"],
    "LPG/Gas": [r"\blpg\b", r"elpiji", r"\bgas\s+(?:3|tiga|12|dua belas)\s*kg", r"tabung gas"],
}

# Jenis yang dianggap "BBM" untuk kolom relevan_bbm.
BBM_TYPES_CORE = {
    "Solar/Biosolar",
    "Pertalite",
    "Premium",
    "Bensin (jenis tidak disebut)",
    "Pertamax",
    "Dexlite",
    "Pertamina Dex",
    "Minyak tanah",
    "Avtur",
    "MFO/Minyak bakar",
}

GENERIC_BBM_PATTERNS = [r"\bbbm\b", r"bahan bakar minyak"]
