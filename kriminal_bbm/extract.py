"""Kandidat nilai kolom dari teks putusan, berbasis aturan (regex).

Hasil modul ini adalah KANDIDAT untuk membantu pemeriksaan, bukan pengganti pembacaan
putusan. Kolom final pada rekap diisi/diverifikasi dengan membaca teks (manual atau
modul llm), lalu dibandingkan dengan kandidat di sini untuk menandai baris yang perlu dicek.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from datetime import date

from .config import BBM_KEYWORDS, BBM_TYPES_CORE, GENERIC_BBM_PATTERNS

MONTHS = {
    "januari": 1, "jan": 1,
    "februari": 2, "pebruari": 2, "feb": 2, "peb": 2,
    "maret": 3, "mar": 3,
    "april": 4, "apr": 4,
    "mei": 5,
    "juni": 6, "jun": 6,
    "juli": 7, "jul": 7,
    "agustus": 8, "agt": 8, "agu": 8, "ags": 8, "agust": 8,
    "september": 9, "sep": 9, "sept": 9,
    "oktober": 10, "okt": 10,
    "november": 11, "nopember": 11, "nov": 11, "nop": 11,
    "desember": 12, "des": 12,
}
_MONTH_ALT = "|".join(sorted(MONTHS, key=len, reverse=True))
DATE_RE = re.compile(rf"\b(\d{{1,2}})\s*(?:-|\s)\s*({_MONTH_ALT})\.?\s*(?:-|\s)\s*(\d{{4}})\b", re.IGNORECASE)

BULAN_NAMA = [
    "", "Januari", "Februari", "Maret", "April", "Mei", "Juni", "Juli",
    "Agustus", "September", "Oktober", "November", "Desember",
]


def _squash(s: str) -> str:
    return re.sub(r"\s+", "", s.lower())


def _norm(s: str) -> str:
    return re.sub(r"\s+", " ", s).strip()


# ----------------------------------------------------------------------------- tanggal

def parse_date(s: str) -> date | None:
    """Tanggal Indonesia pertama dalam string ("5 Pebruari 2020", "05-02-2020" tidak)."""
    m = DATE_RE.search(s or "")
    if not m:
        return None
    d, mon, y = int(m.group(1)), MONTHS[m.group(2).lower()], int(m.group(3))
    try:
        return date(y, mon, d)
    except ValueError:
        return None


def format_date(d: date | None) -> str | None:
    return f"{d.day} {BULAN_NAMA[d.month]} {d.year}" if d else None


# ----------------------------------------------------------------------------- nomor & tingkat

def nomor_putusan(text: str) -> str | None:
    head = "\n".join(text.splitlines()[:40])
    m = re.search(r"^\s*Nomor\s*[.:]?\s*(\d[^\n]{0,60}/[^\n]{2,60})$", head, re.IGNORECASE | re.MULTILINE)
    return _norm(m.group(1)).rstrip(".;,: ") if m else None


def tingkat_from_nomor(nomor: str | None) -> str | None:
    """PN / PT / MA (Kasasi) / MA (PK) / Pengadilan Militer dari pola nomor perkara."""
    if not nomor:
        return None
    n = nomor.upper().replace(" ", "")
    if re.search(r"\d+PK/", n):
        return "MA (PK)"
    if re.search(r"\d+K/", n):
        return "MA (Kasasi)"
    if re.search(r"/PT\.?[A-Z]", n):
        return "PT"
    if re.search(r"/PN\.?[A-Z]", n):
        return "PN"
    if re.search(r"/PM|DILMIL|/AD/|/AL/|/AU/", n):
        return "Pengadilan Militer"
    return None


# ----------------------------------------------------------------------------- amar

_MENGADILI_RE = re.compile(r"^\s*M\s*E\s*N\s*G\s*A\s*D\s*I\s*L\s*I\b(\s*S\s*E\s*N\s*D\s*I\s*R\s*I)?", re.MULTILINE)


def amar_span(text: str) -> tuple[int, int] | None:
    """Posisi amar putusan ini: judul MENGADILI terakhir (bukan 'MENGADILI SENDIRI')
    sampai kalimat penutup 'Demikian ...'."""
    heads = [m for m in _MENGADILI_RE.finditer(text) if not m.group(1)]
    if not heads:
        return None
    start = heads[-1].start()
    end_m = re.search(r"^\s*Demikian", text[start:], re.MULTILINE | re.IGNORECASE)
    end = start + end_m.start() if end_m else len(text)
    return start, end


def amar(text: str) -> str | None:
    span = amar_span(text)
    return text[span[0]:span[1]].strip() if span else None


def tanggal_putusan(text: str) -> date | None:
    """Tanggal ucapan putusan dari paragraf penutup 'Demikian diputuskan ...'."""
    starts = [m.start() for m in re.finditer(r"Demikian", text, re.IGNORECASE)]
    if not starts:
        return None
    closing = text[starts[-1]: starts[-1] + 2500]
    # Bila ada tanggal tersendiri untuk pengucapan, pakai itu.
    m = re.search(r"diucapkan(.{0,250})", closing, re.IGNORECASE | re.DOTALL)
    if m and "itu juga" not in m.group(1).lower():
        d = parse_date(m.group(1))
        if d:
            return d
    return parse_date(closing)


# ----------------------------------------------------------------------------- hasil

def hasil_putusan(amar_text: str | None) -> tuple[str | None, str | None]:
    """(hasil, dasar) dari amar. Hasil: Bersalah / Tidak bersalah / None."""
    if not amar_text:
        return None, "amar tidak ditemukan"
    a = _squash(amar_text)
    if "mengadilisendiri" in a:
        # Putusan PT/MA yang membatalkan dan mengadili sendiri: yang menentukan bagian sesudahnya.
        a = a.split("mengadilisendiri")[-1]
    # Pemidanaan diperiksa lebih dulu: terdakwa bisa dibebaskan dari dakwaan primair
    # tetapi terbukti pada dakwaan subsidair/alternatif.
    if re.search(r"(?<!tidak)terbukti(secara)?(sah)?(dan)?(meyakinkan|menyakinkan)?bersalah", a):
        return "Bersalah", "amar menyatakan terdakwa terbukti bersalah"
    if re.search(r"membebaskan(para)?terdakwa.{0,150}dakwaan", a) or "bebasdarisegaladakwaan" in a:
        return "Tidak bersalah", "amar membebaskan terdakwa (vrijspraak)"
    if re.search(r"melepaskan(para)?terdakwa.{0,150}tuntutanhukum", a):
        return "Tidak bersalah", "amar melepaskan terdakwa dari segala tuntutan hukum (onslag)"
    if re.search(r"menolakpermohonan(kasasi|peninjauankembali)", a):
        if re.search(r"pemohon(kasasi|peninjauankembali)[ivx]*/?(terdakwa|terpidana)", a):
            return "Bersalah", "permohonan kasasi/PK terdakwa ditolak (pemidanaan tetap berlaku)"
        return None, "permohonan kasasi penuntut umum ditolak: ikut putusan sebelumnya"
    if "menguatkanputusan" in a:
        return None, "menguatkan putusan sebelumnya: ikut putusan sebelumnya"
    if re.search(r"pidanapenjaraselama|pidanadendasebesar|pidanadendasejumlah|menjatuhkanpidana", a):
        return "Bersalah", "amar menjatuhkan pidana"
    return None, "pola amar tidak dikenali"


# ----------------------------------------------------------------------------- jenis BBM

_KEYWORD_RES = {k: [re.compile(p, re.IGNORECASE) for p in pats] for k, pats in BBM_KEYWORDS.items()}
_GENERIC_RES = [re.compile(p, re.IGNORECASE) for p in GENERIC_BBM_PATTERNS]


def jenis_bbm(text: str) -> dict[str, int]:
    """Jumlah sebutan tiap jenis bahan bakar. Pola 'bio solar' dihitung sekali (tidak dobel 'solar')."""
    t = text.lower()
    counts: dict[str, int] = {}
    for kind, regs in _KEYWORD_RES.items():
        n = 0
        tt = t
        for r in regs:
            n += len(r.findall(tt))
            tt = r.sub(" ", tt)  # cegah hitung ganda antarpola dalam satu jenis
        if n:
            counts[kind] = n
    return dict(sorted(counts.items(), key=lambda kv: -kv[1]))


def relevansi_bbm(counts: dict[str, int], text: str) -> str:
    """Ya (objek BBM) / Sebagian (minyak mentah/kondensat) / Tidak (LPG/gas) / NA."""
    core = {k: v for k, v in counts.items() if k in BBM_TYPES_CORE}
    if core:
        return "Ya"
    if any(r.search(text) for r in _GENERIC_RES) and "LPG/Gas" not in counts:
        return "Ya"
    if "Minyak mentah" in counts:
        return "Sebagian"
    if "LPG/Gas" in counts:
        return "Tidak"
    return "NA"


# ----------------------------------------------------------------------------- angka

def parse_number(s: str) -> float | None:
    """Angka gaya Indonesia: '5.353' -> 5353, '1.234,5' -> 1234.5, '19.930.365,00' -> 19930365."""
    s = s.strip().strip(".,")
    if not s:
        return None
    if "," in s:
        whole, _, frac = s.rpartition(",")
        whole = whole.replace(".", "")
        try:
            return float(f"{whole}.{frac}") if whole else float(f"0.{frac}")
        except ValueError:
            return None
    if re.fullmatch(r"\d{1,3}(\.\d{3})+", s):
        return float(s.replace(".", ""))
    try:
        return float(s)
    except ValueError:
        return None


@dataclass
class Mention:
    value: float
    unit: str
    context: str
    kind: str


_NUM = r"(\d{1,3}(?:\.\d{3})+(?:,\d+)?|\d+(?:,\d+)?)"
_SPELLED = r"(?:\s*\([^()]{0,120}\))?"
VOLUME_RE = re.compile(
    rf"{_NUM}{_SPELLED}\s*(kilo\s*liter|kiloliter|k\.?l\b|liter|ltr\b|lt\b|l\b|ton\b|m3\b|m³)",
    re.IGNORECASE,
)


def volume_mentions(text: str) -> list[Mention]:
    """Sebutan volume (liter, kiloliter -> liter, ton dibiarkan). Kapasitas wadah ditandai."""
    out: list[Mention] = []
    for m in VOLUME_RE.finditer(text):
        val = parse_number(m.group(1))
        if val is None:
            continue
        unit = m.group(2).lower().replace(" ", "")
        if unit.startswith("kilo") or unit.startswith("k"):
            val, unit = val * 1000, "liter"
        elif unit in {"liter", "ltr", "lt", "l"}:
            unit = "liter"
        elif unit in {"m3", "m³"}:
            val, unit = val * 1000, "liter"
        before = text[max(0, m.start() - 40): m.start()].lower()
        before = re.split(r"[;,\n]|\bdan\b", before)[-1]  # hanya klausa yang sama
        kind = "kapasitas" if re.search(r"kapasitas|@|isi\s*$|ukuran|volume\s*$", before) else "jumlah"
        ctx = _norm(text[max(0, m.start() - 80): m.end() + 40])
        out.append(Mention(val, unit, ctx, kind))
    return out


RUPIAH_RE = re.compile(r"Rp\.?\s*" + r"(\d{1,3}(?:\s?\.\s?\d{3})+(?:,\d{1,2})?|\d+(?:,\d{1,2})?)", re.IGNORECASE)


_RUPIAH_KEYWORDS = [
    ("kerugian_negara", r"kerugian\s+(?:keuangan\s+)?negara"),
    ("hasil_lelang", r"lelang"),
    ("biaya_perkara", r"biaya\s+perkara"),
    ("denda", r"denda"),
    ("keuntungan", r"keuntungan|untung|laba|upah|imbalan"),
    ("nilai_transaksi", r"harga|seharga|dijual|menjual|membeli|dibeli|senilai|nilai|total"),
]


def _rupiah_kind(before: str, after: str) -> str:
    """Jenis nominal menurut kata kunci TERDEKAT di klausa yang sama."""
    a = after.lower()
    # "(delapan ribu rupiah) per liter" juga dihitung harga per liter
    a = re.sub(r"^[\s,.\-]*(?:\([^()]{0,60}\))?", "", a)
    if re.match(r"\s*(?:,-|,00)?\s*(?:/\s*(?:liter|ltr|l\b)|per\s*liter|perliter|setiap\s*liter|tiap\s*liter)", a):
        return "harga_per_liter"
    b = re.split(r"[;\n]", before.lower())[-1]
    best, pos = "lain", -1
    for kind, pat in _RUPIAH_KEYWORDS:
        for m in re.finditer(pat, b):
            if m.start() > pos:
                best, pos = kind, m.start()
    return best


def rupiah_mentions(text: str) -> list[Mention]:
    out: list[Mention] = []
    for m in RUPIAH_RE.finditer(text):
        val = parse_number(re.sub(r"\s", "", m.group(1)))
        if val is None:
            continue
        before = text[max(0, m.start() - 120): m.start()]
        after = text[m.end(): m.end() + 60]
        out.append(Mention(val, "IDR", _norm(before[-80:] + text[m.start():m.end()] + after[:30]),
                           _rupiah_kind(before[-90:], after)))
    return out


# ----------------------------------------------------------------------------- pasal & modus

PASAL_RE = re.compile(
    r"Pasal\s+(5[3-5])\s*(?:huruf\s*[\"“”'‘’]?\s*([a-d])\b)?",
    re.IGNORECASE,
)

MODUS_PASAL = {
    "53a": "Pengolahan tanpa izin usaha",
    "53b": "Pengangkutan tanpa izin usaha",
    "53c": "Penyimpanan tanpa izin usaha",
    "53d": "Niaga tanpa izin usaha",
    "54": "Meniru/memalsukan BBM",
    "55": "Penyalahgunaan pengangkutan/niaga BBM bersubsidi",
}

_MODUS_FRASA = [
    (r"menyalahgunakan\s+(pengangkutan|niaga)|penyalahgunaan\s+(pengangkutan|niaga)|disubsidi\s+pemerintah|bersubsidi", "55"),
    (r"tanpa\s+izin\s+usaha\s+pengolahan", "53a"),
    (r"tanpa\s+izin\s+usaha\s+pengangkutan", "53b"),
    (r"tanpa\s+izin\s+usaha\s+penyimpanan", "53c"),
    (r"tanpa\s+izin\s+usaha\s+niaga", "53d"),
    (r"meniru\s+atau\s+memalsukan|memalsukan\s+bahan\s+bakar", "54"),
    (r"pengolahan\s+tanpa|mengolah.{0,40}tanpa\s+izin", "53a"),
    (r"pengangkutan.{0,80}tanpa\s+izin|mengangkut.{0,80}tanpa\s+izin", "53b"),
    (r"penyimpanan.{0,80}tanpa\s+izin|menyimpan.{0,80}tanpa\s+izin", "53c"),
    (r"niaga.{0,80}tanpa\s+izin", "53d"),
]


def pasal_migas(text: str) -> list[str]:
    """Pasal UU 22/2001 (53 a-d, 54, 55) dari paragraf 'Mengingat' terakhir sebelum amar
    (dasar putusan); bila tidak ada, dari seluruh teks."""
    span = amar_span(text)
    upto = text[: span[0]] if span else text
    idx = [m.start() for m in re.finditer(r"Mengingat", upto)]
    region = upto[idx[-1]: idx[-1] + 1500] if idx else text
    found = []
    for m in PASAL_RE.finditer(region):
        code = m.group(1) + (m.group(2).lower() if m.group(2) and m.group(1) == "53" else "")
        if code not in found:
            found.append(code)
    return found


def modus_dari_amar(amar_text: str | None) -> list[str]:
    if not amar_text:
        return []
    a = _norm(amar_text.lower())
    # Hanya bagian pernyataan kesalahan (sebelum penjatuhan pidana/barang bukti).
    a = re.split(r"menjatuhkan pidana|menghukum terdakwa|barang bukti", a)[0]
    codes = []
    for pat, code in _MODUS_FRASA:
        if re.search(pat, a) and code not in codes:
            codes.append(code)
    return codes


# ----------------------------------------------------------------------------- tahun kejadian

_KEJADIAN_RES = [
    re.compile(rf"pada\s+hari\s+\w+,?\s+tanggal\s+\d{{1,2}}\s+(?:{_MONTH_ALT})\.?\s+(\d{{4}})", re.IGNORECASE),
    re.compile(rf"(?:dalam|pada|sekitar)\s+bulan\s+(?:{_MONTH_ALT})\s+(?:tahun\s+)?(\d{{4}})", re.IGNORECASE),
    re.compile(r"setidak-tidaknya\s+(?:pada\s+)?(?:suatu\s+)?(?:waktu\s+)?(?:dalam\s+)?tahun\s+(\d{4})", re.IGNORECASE),
]


def tahun_kejadian(text: str, tahun_putusan: int | None = None) -> tuple[str | None, list[int]]:
    """Tahun perbuatan dari uraian dakwaan/fakta (sebelum amar). Hasil: ("2019" / "2019-2020", daftar tahun)."""
    span = amar_span(text)
    body = text[: span[0]] if span else text
    years: list[int] = []
    for r in _KEJADIAN_RES:
        for m in r.finditer(body):
            y = int(m.group(1))
            if 1990 <= y <= (tahun_putusan or 2100):
                years.append(y)
    if not years:
        return None, []
    # Ambil tahun yang paling sering muncul beserta rentangnya bila >1 tahun dominan.
    freq = {y: years.count(y) for y in set(years)}
    top = sorted(freq, key=lambda y: (-freq[y], y))
    main = sorted(y for y in top if freq[y] >= max(2, freq[top[0]] // 3)) or [top[0]]
    label = str(main[0]) if main[0] == main[-1] else f"{main[0]}-{main[-1]}"
    return label, sorted(freq)


# ----------------------------------------------------------------------------- pengadilan asal

def pengadilan_asal(text: str) -> str | None:
    """Pengadilan tingkat pertama yang disebut dalam putusan PT/MA ('PN NANGA BULIK')."""
    t = _norm(text)
    stop = {"NOMOR", "NO", "TANGGAL", "REGISTER", "KELAS", "YANG", "KARENA", "DALAM", "PADA",
            "SEJAK", "DI", "DIBAWAH", "TERSEBUT", "DENGAN", "UNTUK", "ATAS", "TELAH"}
    for m in re.finditer(r"Pengadilan Negeri\s+((?:[A-Z][A-Za-z.\-]*\s?){1,5})", t):
        words = []
        for w in m.group(1).split():
            if w.upper().strip(".,") in stop:
                break
            words.append(w.strip(".,"))
        if words:
            return "PN " + " ".join(words).upper()
    return None


# ----------------------------------------------------------------------------- semua

def extract_all(text: str) -> dict:
    nomor = nomor_putusan(text)
    am = amar(text)
    tgl = tanggal_putusan(text)
    hasil, dasar = hasil_putusan(am)
    counts = jenis_bbm(text)
    counts_amar = jenis_bbm(am or "")
    vols = volume_mentions(am or "")
    vols_all = volume_mentions(text)
    rups = rupiah_mentions(text)
    kej, kej_years = tahun_kejadian(text, tgl.year if tgl else None)
    pasal = pasal_migas(text)
    modus = modus_dari_amar(am)

    def _vals(ms, kind=None, unit=None):
        return sorted({m.value for m in ms if (kind is None or m.kind == kind) and (unit is None or m.unit == unit)})

    vol_amar = _vals(vols, "jumlah", "liter")
    return {
        "nomor_teks": nomor,
        "tingkat_teks": tingkat_from_nomor(nomor),
        "tanggal_putusan_teks": format_date(tgl),
        "tahun_putusan_teks": tgl.year if tgl else None,
        "tahun_kejadian_kandidat": kej,
        "tahun_disebut_dakwaan": ";".join(map(str, kej_years)) or None,
        "hasil_kandidat": hasil,
        "dasar_hasil_kandidat": dasar,
        "jenis_bbm_disebut": "; ".join(f"{k} ({v})" for k, v in counts.items()) or None,
        "jenis_bbm_di_amar": "; ".join(counts_amar) or None,
        "relevan_bbm_kandidat": relevansi_bbm(counts, text),
        "volume_liter_di_amar": ";".join(f"{v:g}" for v in vol_amar) or None,
        "volume_liter_di_amar_jumlah": sum(vol_amar) if vol_amar else None,
        "volume_liter_maks_teks": max(_vals(vols_all, "jumlah", "liter"), default=None),
        "volume_ton_di_teks": ";".join(f"{v:g}" for v in _vals(vols_all, "jumlah", "ton")) or None,
        "rp_kerugian_negara": max(_vals(rups, "kerugian_negara"), default=None),
        "rp_hasil_lelang": ";".join(f"{v:.0f}" for v in _vals(rups, "hasil_lelang")) or None,
        "rp_harga_per_liter": ";".join(f"{v:.0f}" for v in _vals(rups, "harga_per_liter")) or None,
        "rp_denda_di_amar": ";".join(f"{v:.0f}" for v in _vals(rupiah_mentions(am or ""), "denda")) or None,
        "pasal_uu_migas": ";".join(pasal) or None,
        "modus_dari_amar": ";".join(modus) or None,
        "pengadilan_asal_teks": pengadilan_asal(text),
        "panjang_teks": len(text),
    }
