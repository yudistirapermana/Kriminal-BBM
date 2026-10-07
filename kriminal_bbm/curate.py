"""Kurasi rekap berdasarkan kata kunci: BBM / solar / biosolar / minyak tanah / pertalite.

Untuk setiap putusan dicari kata kunci di sumber terkuat yang tersedia:
1. teks PDF putusan itu sendiri (diunduh dari Direktori Putusan MA);
2. kutipan verbatim di kolom bukti_kutipan (kecuali baris tabulasi tim, yang kolomnya berisi sel spreadsheet);
3. teks PDF putusan lain dalam rantai perkara yang sama (fakta perkara sama);
4. kolom yang ditulis pengode (barang_bbm, rincian_amar, catatan) - bukti terlemah.
Dengan --online, halaman overview dan PDF di situs MA diambil ulang lewat url_putusan.

Ada tidaknya kata kunci belum cukup: putusan tambang emas yang menyebut "solar" sebagai bahan
bakar ekskavator tidak berhubungan dengan BBM sebagai objek perkara. Karena itu keputusan akhir
memakai berkas tinjauan (kolom `final`: yes/no/uncertain) hasil pembacaan teks; modul ini
menghitung bukti kata kunci dan menerapkan keputusan tersebut ke rekap.
"""

from __future__ import annotations

import re
from pathlib import Path

import pandas as pd

from .pdftext import cached_text
from .validate import is_na

KEYWORDS = {
    "BBM": r"\bB\.?B\.?M\b",
    "bahan bakar minyak": r"bahan\s+bakar\s+minyak",
    "solar": r"(?<!bio)(?<!bio )(?<!bio-)\bsolar\b",
    "biosolar": r"bio\s*-?\s*solar",
    "minyak tanah": r"minyak\s+tanah",
    "pertalite": r"pertalit",
}
_KEYWORD_RES = {k: re.compile(p, re.IGNORECASE) for k, p in KEYWORDS.items()}
CODER_FIELDS = ["barang_bbm", "rincian_amar", "catatan", "keterangan_volume", "dasar_nilai_uang"]


def keyword_hits(text: str | None) -> dict[str, int]:
    if not text:
        return {}
    return {k: len(r.findall(text)) for k, r in _KEYWORD_RES.items() if r.search(text)}


def _fmt(h: dict[str, int] | None) -> str | None:
    return "; ".join(f"{k} ({v})" for k, v in h.items()) if h else None


def evidence_table(rekap: pd.DataFrame, data_dir: str | Path, text_cache: str | Path) -> pd.DataFrame:
    """Bukti kata kunci per baris rekap, menurut sumber."""
    data_dir = Path(data_dir)
    texts: dict[str, str] = {}

    def text_of(fp):
        if fp not in texts:
            texts[fp] = cached_text(data_dir / fp, text_cache)
        return texts[fp]

    rows = []
    for _, r in rekap.iterrows():
        own = r["file_pdf"] if not is_na(r["file_pdf"]) and (data_dir / str(r["file_pdf"])).exists() else None
        pdf_h = keyword_hits(text_of(own)) if own else None
        quotes = str(r["bukti_kutipan"]) if not is_na(r["bukti_kutipan"]) else ""
        # Baris tabulasi tim: bukti_kutipan berisi sel spreadsheet tim, bukan kutipan teks putusan.
        is_tab = str(r.get("sumber_daftar", "")).startswith("Tabulasi")
        quote_h = {} if is_tab else keyword_hits(quotes)
        sib_h: dict[str, int] = {}
        sibs = rekap[(rekap["rantai_perkara"] == r["rantai_perkara"]) & (rekap["no"] != r["no"])]
        for fp in sibs["file_pdf"].dropna():
            if (data_dir / fp).exists():
                for k, v in keyword_hits(text_of(fp)).items():
                    sib_h[k] = sib_h.get(k, 0) + v
        coder_text = " ".join(str(r[c]) for c in CODER_FIELDS if c in r and not is_na(r[c]))
        coder_h = keyword_hits(coder_text + (" " + quotes if is_tab else ""))
        if pdf_h is not None:
            basis, hits = "teks PDF putusan", pdf_h
        elif quote_h:
            basis, hits = "kutipan verbatim (bukti_kutipan)", quote_h
        elif sib_h:
            basis, hits = "teks PDF putusan lain dalam rantai", sib_h
        elif coder_h and is_tab:
            basis, hits = "tabulasi tim (bukan teks putusan)", coder_h
        elif coder_h:
            basis, hits = "kolom isian pengode saja", coder_h
        else:
            basis, hits = "tidak ada", {}
        rows.append({
            "no": r["no"],
            "nomor_putusan": r["nomor_putusan"],
            "dasar_bukti_kata_kunci": basis,
            "kata_kunci_ditemukan": ", ".join(hits) or None,
            "token_BBM_literal": "BBM" in hits,
            "kata_kunci_di_pdf": _fmt(pdf_h),
            "kata_kunci_di_kutipan": _fmt(quote_h),
            "kata_kunci_di_pdf_rantai": _fmt(sib_h),
            "kata_kunci_di_isian_pengode": _fmt(coder_h),
        })
    return pd.DataFrame(rows)


def online_check(rekap: pd.DataFrame, session, pdf_dir: str | Path, text_cache: str | Path, log=print) -> pd.DataFrame:
    """Ambil ulang overview (dan PDF bila ada) dari situs MA untuk baris yang punya url_putusan."""
    from .crawler import safe_filename
    from .directory import parse_overview

    rows = []
    for _, r in rekap.iterrows():
        url = r["url_putusan"]
        rec = {"no": r["no"], "nomor_putusan": r["nomor_putusan"], "kata_kunci_overview_situs": None,
               "kata_kunci_pdf_situs": None, "galat_situs": None}
        if is_na(url):
            rec["galat_situs"] = "tanpa url_putusan"
            rows.append(rec)
            continue
        try:
            ov = parse_overview(session.get_html(url), url)
            meta_text = " ".join(str(ov.get(k) or "") for k in ("kata_kunci", "catatan_amar", "amar_lainnya", "abstrak", "klasifikasi"))
            rec["kata_kunci_overview_situs"] = _fmt(keyword_hits(meta_text))
            if ov.get("url_pdf"):
                dest = Path(pdf_dir) / f"{safe_filename(ov.get('nomor') or r['nomor_putusan'])}.pdf"
                session.download(ov["url_pdf"], dest)
                rec["kata_kunci_pdf_situs"] = _fmt(keyword_hits(cached_text(dest, text_cache)))
        except Exception as e:  # CAPTCHA/robots dihentikan oleh pemanggil; lainnya dicatat
            from .web import CaptchaRequired, RobotsDisallowed
            if isinstance(e, (CaptchaRequired, RobotsDisallowed)):
                raise
            rec["galat_situs"] = str(e)
        log(f"  {r['nomor_putusan']}: overview={rec['kata_kunci_overview_situs']} pdf={rec['kata_kunci_pdf_situs']}")
        rows.append(rec)
    return pd.DataFrame(rows)


ALASAN_PREFIX = "Kurasi kata kunci (BBM/solar/biosolar/minyak tanah/pertalite)"


def apply_review(rekap: pd.DataFrame, excluded: pd.DataFrame, review: pd.DataFrame,
                 tanggal: str) -> tuple[pd.DataFrame, pd.DataFrame, pd.DataFrame]:
    """Keluarkan baris rekap yang hasil tinjauannya `final == "no"`.

    rekap/excluded dibaca sebagai teks (lihat read_raw) agar penulisan ulang tidak mengubah format sel lain.
    review: kolom no, final, alasan. Baris 'uncertain' TIDAK dihapus (ditandai di laporan).
    Mengembalikan (rekap_baru, dikeluarkan_baru, baris_yang_dikeluarkan). Kolom `no` diurutkan ulang.
    """
    review = review[review["no"].notna()]
    drop_no = set(review.loc[review["final"] == "no", "no"].astype(int))
    removed = rekap[rekap["no"].astype(int).isin(drop_no)].copy()
    kept = rekap[~rekap["no"].astype(int).isin(drop_no)].copy()
    kept["no"] = [str(i) for i in range(1, len(kept) + 1)]

    alasan = review.set_index(review["no"].astype(int))["alasan"]
    add = pd.DataFrame({
        "nomor_putusan": removed["nomor_putusan"],
        "pengadilan": removed["pengadilan"],
        "tingkat_persidangan": removed["tingkat_persidangan"],
        "tahun_putusan": removed["tahun_putusan"],
        "barang_bbm": removed["barang_bbm"],
        "klasifikasi": removed["klasifikasi"],
        "url_putusan": removed["url_putusan"],
        "alasan_dikeluarkan": [f"{ALASAN_PREFIX}, {tanggal}: {alasan.get(int(n), '')}" for n in removed["no"]],
    })
    excluded_new = pd.concat([excluded, add[excluded.columns]], ignore_index=True)
    return kept, excluded_new, removed


def read_raw(path: str | Path) -> pd.DataFrame:
    """Baca CSV sebagai teks apa adanya ("NA" tetap "NA", angka tidak diubah)."""
    return pd.read_csv(path, dtype=str, keep_default_na=False, encoding="utf-8-sig")


def write_raw(df: pd.DataFrame, path: str | Path) -> None:
    df.to_csv(path, index=False, encoding="utf-8-sig", lineterminator="\n")
