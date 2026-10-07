"""Ekstraksi teks PDF putusan Direktori Mahkamah Agung.

PDF dari Direktori Putusan memuat watermark diagonal "Mahkamah Agung Republik Indonesia",
kop "Direktori Putusan ...", nomor halaman, dan paragraf disclaimer di setiap halaman.
Watermark diagonal disaring dengan mengambil hanya teks tegak (orientasi 0 derajat);
baris kop/disclaimer dibuang dengan pola di bawah.
"""

from __future__ import annotations

import hashlib
import re
from pathlib import Path

from pypdf import PdfReader

BOILERPLATE_PATTERNS = [
    r"^Mahkamah Agung Republik Indonesia$",
    r"^Direktori Putusan Mahkamah Agung Republik Indonesia$",
    r"^putusan\.mahkamahagung\.go\.id$",
    r"^Disclaimer$",
    r"^Kepaniteraan Mahkamah Agung Republik Indonesia berusaha untuk selalu mencantumkan",
    r"^pelaksanaan fungsi peradilan\. Namun dalam hal-hal tertentu",
    r"^Dalam hal Anda menemukan inakurasi informasi",
    r"^Email\s*:\s*kepaniteraan@mahkamahagung\.go\.id",
    # "Halaman 1 dari 17 Putusan Nomor 266/Pid.Sus/2019/PN.Pli." dan variasinya
    r"^Hal(aman|\.)?\s*\d+\s*(dari|dr\.?)\s*\d+",
    r"^Halaman\s*\d+\s*$",
]
# Naikkan bila aturan pembersihan berubah agar cache teks lama tidak dipakai.
CLEAN_VERSION = 2

_BOILERPLATE_RE = re.compile("|".join(f"(?:{p})" for p in BOILERPLATE_PATTERNS), re.IGNORECASE)


def raw_pages(pdf_path: str | Path) -> list[str]:
    """Teks per halaman, hanya karakter tegak (watermark diagonal terbuang)."""
    reader = PdfReader(str(pdf_path))
    return [page.extract_text(orientations=(0,)) or "" for page in reader.pages]


def clean_text(raw: str) -> str:
    """Buang baris kop/disclaimer/nomor halaman dan rapikan spasi."""
    out: list[str] = []
    for line in raw.splitlines():
        line = line.replace(" ", " ").replace("¬", "")
        line = re.sub(r"[ \t]+", " ", line).strip()
        # Kerning pada beberapa PDF memisahkan huruf kapital awal: "T erdakwa" -> "Terdakwa".
        line = re.sub(r"\b([TWYPF]) (?=[a-z]{2,})", r"\1", line)
        if not line:
            if out and out[-1] != "":
                out.append("")
            continue
        if _BOILERPLATE_RE.search(line):
            continue
        out.append(line)
    return "\n".join(out).strip() + "\n"


def extract_text(pdf_path: str | Path) -> str:
    return clean_text("\n".join(raw_pages(pdf_path)))


def _file_digest(path: Path) -> str:
    h = hashlib.sha1()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 16), b""):
            h.update(chunk)
    return h.hexdigest()[:12]


def cached_text(pdf_path: str | Path, cache_dir: str | Path) -> str:
    """Seperti extract_text, tetapi hasilnya disimpan di cache_dir (kunci: isi berkas)."""
    pdf_path = Path(pdf_path)
    cache_dir = Path(cache_dir)
    cache_dir.mkdir(parents=True, exist_ok=True)
    target = cache_dir / f"{pdf_path.stem}.{_file_digest(pdf_path)}.v{CLEAN_VERSION}.txt"
    if target.exists():
        return target.read_text(encoding="utf-8")
    text = extract_text(pdf_path)
    target.write_text(text, encoding="utf-8")
    return text
