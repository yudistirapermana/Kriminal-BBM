"""Pemeriksaan konsistensi berkas rekap putusan.

Setiap temuan punya tingkat:
- galat      : hampir pasti salah dan perlu diperbaiki;
- peringatan : kemungkinan salah, perlu dibaca ulang;
- info       : catatan (mis. duplikat entri direktori yang sudah diberi keterangan).
Modul ini TIDAK mengubah data; keputusan koreksi tetap pada tim.
"""

from __future__ import annotations

import re
from dataclasses import asdict, dataclass
from pathlib import Path

import pandas as pd

from .extract import parse_date, tingkat_from_nomor

REQUIRED_COLUMNS = [
    "no", "nomor_putusan", "pengadilan", "tingkat_persidangan", "tingkat_proses", "tanggal_putusan",
    "tahun_putusan", "tahun_kejadian", "hasil_putusan", "rincian_amar", "barang_bbm", "relevan_bbm",
    "nilai_kerugian_uang", "mata_uang", "dasar_nilai_uang", "nilai_kerugian_volume", "satuan_volume",
    "keterangan_volume", "sumber_data", "lampiran_pdf", "file_pdf", "rantai_perkara", "klasifikasi",
    "sumber_daftar", "url_putusan", "bukti_kutipan", "catatan",
]

TINGKAT_PROSES = {
    "PN": {"Pertama"},
    "PT": {"Banding"},
    "MA": {"Kasasi", "Peninjauan Kembali"},
    "Pengadilan Militer": {"Pertama", "Banding"},
}
HASIL_VALID = {"Bersalah", "Tidak bersalah"}
URL_RE = re.compile(r"^https://putusan3\.mahkamahagung\.go\.id/direktori/putusan/[0-9a-z]+\.html$")
LEVEL_ORDER = {"Pertama": 0, "Banding": 1, "Kasasi": 2, "Peninjauan Kembali": 3}

# Kata kunci per jenis BBM di kolom barang_bbm -> pola di teks putusan.
BBM_TEXT_CHECK = {
    "solar": r"solar|hsd|high speed diesel",
    "pertalite": r"pertalit",
    "premium": r"premium",
    "pertamax": r"pertamax",
    "dexlite": r"dexlite",
    "minyak tanah": r"minyak\s*tanah|kerosin",
    "minyak mentah": r"minyak\s*mentah|crude|kondensat",
}


@dataclass
class Issue:
    no: int | None
    nomor_putusan: str | None
    kolom: str
    tingkat: str
    pesan: str


def is_na(v) -> bool:
    if v is None:
        return True
    if isinstance(v, str):
        return v.strip() in {"", "NA"}
    try:
        return bool(pd.isna(v))
    except (TypeError, ValueError):
        return False


def norm_nomor(n: str | None) -> str:
    """Bentuk baku nomor perkara untuk perbandingan ('PN.Pli' == 'PN Pli')."""
    if is_na(n):
        return ""
    return re.sub(r"[^A-Z0-9/]", "", str(n).upper())


def load_rekap(path: str | Path) -> pd.DataFrame:
    return pd.read_csv(path, dtype={"tahun_kejadian": "string"}, keep_default_na=True, na_values=["NA"])


def validate_rekap(
    df: pd.DataFrame,
    data_dir: str | Path,
    excluded: pd.DataFrame | None = None,
    candidates: pd.DataFrame | None = None,
) -> list[Issue]:
    data_dir = Path(data_dir)
    issues: list[Issue] = []

    def add(row, kolom, tingkat, pesan):
        no = None if row is None else int(row["no"]) if not is_na(row.get("no")) else None
        nomor = None if row is None else row.get("nomor_putusan")
        issues.append(Issue(no, nomor, kolom, tingkat, pesan))

    missing = [c for c in REQUIRED_COLUMNS if c not in df.columns]
    if missing:
        add(None, ",".join(missing), "galat", "kolom wajib tidak ada")
        return issues

    expected = list(range(1, len(df) + 1))
    if list(df["no"]) != expected:
        add(None, "no", "peringatan", "kolom no tidak berurutan 1..n")

    for _, r in df.iterrows():
        tingkat, proses = r["tingkat_persidangan"], r["tingkat_proses"]
        if tingkat not in TINGKAT_PROSES:
            add(r, "tingkat_persidangan", "galat", f"nilai tidak dikenal: {tingkat!r}")
        elif proses not in TINGKAT_PROSES[tingkat]:
            add(r, "tingkat_proses", "galat", f"{proses!r} tidak cocok dengan tingkat {tingkat}")

        dari_nomor = tingkat_from_nomor(r["nomor_putusan"])
        if dari_nomor and tingkat in TINGKAT_PROSES:
            expected_tingkat = "MA" if dari_nomor.startswith("MA") else dari_nomor
            if expected_tingkat != tingkat:
                add(r, "nomor_putusan", "peringatan", f"pola nomor menunjukkan {dari_nomor}, tercatat {tingkat}")
        if dari_nomor == "MA (PK)" and proses != "Peninjauan Kembali":
            add(r, "tingkat_proses", "peringatan", "nomor PK tetapi tingkat_proses bukan Peninjauan Kembali")

        hasil = r["hasil_putusan"]
        if is_na(hasil):
            add(r, "hasil_putusan", "peringatan", "hasil putusan kosong/NA")
        elif hasil not in HASIL_VALID:
            add(r, "hasil_putusan", "galat", f"nilai tidak dikenal: {hasil!r}")

        tgl = parse_date(str(r["tanggal_putusan"]))
        th = r["tahun_putusan"]
        if tgl is None:
            add(r, "tanggal_putusan", "info", f"tanggal tidak dalam format baku: {r['tanggal_putusan']!r}")
        elif not is_na(th) and int(th) != tgl.year:
            add(r, "tahun_putusan", "galat", f"tahun_putusan {th} berbeda dengan tanggal {r['tanggal_putusan']}")
        if not is_na(th) and not 2020 <= int(th) <= 2026:
            add(r, "tahun_putusan", "peringatan", f"di luar cakupan 2020-2026: {th}")

        kej = r["tahun_kejadian"]
        if not is_na(kej):
            m = re.fullmatch(r"(\d{4})(?:-(\d{4}))?", str(kej))
            if not m:
                add(r, "tahun_kejadian", "galat", f"format tidak dikenal: {kej!r}")
            elif not is_na(th) and int(m.group(2) or m.group(1)) > int(th):
                add(r, "tahun_kejadian", "galat", f"tahun kejadian {kej} sesudah tahun putusan {th}")
            elif m.group(2) and int(m.group(2)) < int(m.group(1)):
                add(r, "tahun_kejadian", "galat", f"rentang terbalik: {kej}")

        uang, mu, dasar = r["nilai_kerugian_uang"], r["mata_uang"], r["dasar_nilai_uang"]
        if not is_na(uang):
            if float(uang) < 0:
                add(r, "nilai_kerugian_uang", "galat", "nilai negatif")
            if is_na(mu) or is_na(dasar):
                add(r, "mata_uang/dasar_nilai_uang", "galat", "nilai uang terisi tetapi mata_uang/dasar kosong")
        elif not is_na(mu):
            add(r, "mata_uang", "peringatan", "mata_uang terisi tetapi nilai uang NA")

        vol, sat = r["nilai_kerugian_volume"], r["satuan_volume"]
        if not is_na(vol):
            if float(vol) <= 0:
                add(r, "nilai_kerugian_volume", "galat", "volume <= 0")
            if is_na(sat):
                add(r, "satuan_volume", "galat", "volume terisi tetapi satuan kosong")
            elif sat not in {"liter", "ton", "kiloliter"}:
                add(r, "satuan_volume", "peringatan", f"satuan tidak baku: {sat!r}")
        elif not is_na(sat):
            add(r, "satuan_volume", "peringatan", "satuan terisi tetapi volume NA")

        if r["relevan_bbm"] != "Ya":
            add(r, "relevan_bbm", "peringatan", f"relevan_bbm = {r['relevan_bbm']!r} (rekap seharusnya hanya 'Ya')")

        fp, lamp = r["file_pdf"], r["lampiran_pdf"]
        if not is_na(fp):
            if not (data_dir / str(fp)).exists():
                add(r, "file_pdf", "galat", f"berkas tidak ditemukan: {fp}")
            if not is_na(lamp) and lamp != "Ada":
                add(r, "lampiran_pdf", "peringatan", f"file_pdf terisi tetapi lampiran_pdf = {lamp!r}")
        elif lamp == "Ada" and "duplikat" not in str(r["catatan"]).lower():
            add(r, "file_pdf", "peringatan", "lampiran_pdf = 'Ada' tetapi file_pdf kosong")

        url = r["url_putusan"]
        if is_na(url):
            add(r, "url_putusan", "info", "tanpa URL direktori (baris dari tabulasi tim)")
        elif not URL_RE.match(str(url)):
            add(r, "url_putusan", "peringatan", f"format URL tidak baku: {url}")

    # Duplikat
    for col, lvl in (("url_putusan", "galat"),):
        dup = df[df[col].notna() & df[col].duplicated(keep=False)]
        for _, r in dup.iterrows():
            add(r, col, lvl, f"{col} sama dengan baris lain")
    key = df["nomor_putusan"].map(norm_nomor)
    for k, grp in df[key.duplicated(keep=False)].groupby(key[key.duplicated(keep=False)]):
        nos = ", ".join(str(n) for n in grp["no"])
        noted = grp["catatan"].fillna("").str.lower().str.contains("duplikat").any()
        tingkat = "info" if noted else "peringatan"
        for _, r in grp.iterrows():
            add(r, "nomor_putusan", tingkat,
                f"nomor sama dengan baris {nos}" + (" (sudah ditandai duplikat di catatan)" if noted else ""))

    # Konsistensi dalam rantai perkara
    for chain, grp in df.groupby("rantai_perkara"):
        dated = [(LEVEL_ORDER.get(r["tingkat_proses"], 0), parse_date(str(r["tanggal_putusan"])), r)
                 for _, r in grp.iterrows()]
        dated = [d for d in dated if d[1]]
        for lvl_a, d_a, r_a in dated:
            for lvl_b, d_b, r_b in dated:
                if lvl_a < lvl_b and d_a > d_b:
                    add(r_b, "tanggal_putusan", "peringatan",
                        f"rantai {chain}: putusan {r_b['tingkat_proses']} ({d_b}) lebih awal dari "
                        f"{r_a['tingkat_proses']} {r_a['nomor_putusan']} ({d_a})")
        kej = {str(v) for v in grp["tahun_kejadian"] if not is_na(v)}
        if len(kej) > 1:
            add(grp.iloc[0], "tahun_kejadian", "info", f"rantai {chain}: tahun kejadian berbeda antartingkat {sorted(kej)}")

    # Berkas PDF yang tidak dirujuk
    referenced = set(df["file_pdf"].dropna())
    pdf_dir = data_dir / "pdf"
    excluded_nomor = set()
    if excluded is not None:
        excluded_nomor = {norm_nomor(n) for n in excluded["nomor_putusan"]}
        both = set(key) & excluded_nomor
        for _, r in df[key.isin(both)].iterrows():
            add(r, "nomor_putusan", "galat", "nomor juga tercantum di daftar putusan yang dikeluarkan")
    if pdf_dir.exists():
        for p in sorted(pdf_dir.glob("*.pdf")):
            rel = f"pdf/{p.name}"
            if rel not in referenced:
                issues.append(Issue(None, None, "file_pdf", "info",
                                    f"{rel} tidak dirujuk rekap (kemungkinan milik putusan yang dikeluarkan)"))

    if candidates is not None:
        issues.extend(compare_with_text(df, candidates))
    return issues


def _num_set(s) -> set[float]:
    if is_na(s):
        return set()
    return {float(x) for x in str(s).split(";") if x}


def _nomor_core(n: str) -> tuple[str, str, str]:
    """(nomor urut, tahun, kode pengadilan) - mengabaikan kode jenis perkara (Pid.Sus / Pid.B/LH)."""
    parts = [p.strip() for p in str(n).split("/") if p.strip()]
    first = re.sub(r"\D.*$", "", parts[0]) if parts else ""
    year = next((p for p in parts if re.fullmatch(r"\d{4}", p)), "")
    court = re.sub(r"[^A-Z]", "", parts[-1].upper()) if len(parts) > 1 else ""
    return first, year, court


def compare_with_text(df: pd.DataFrame, cand: pd.DataFrame) -> list[Issue]:
    """Bandingkan isi rekap dengan kandidat dari teks PDF (kolom file_pdf sebagai kunci)."""
    out: list[Issue] = []
    c = cand.set_index("file_pdf")
    for _, r in df[df["file_pdf"].notna()].iterrows():
        fp = r["file_pdf"]
        if fp not in c.index:
            continue
        k = c.loc[fp]
        no, nomor = int(r["no"]), r["nomor_putusan"]

        def add(kolom, tingkat, pesan):
            out.append(Issue(no, nomor, kolom, tingkat, f"[cek teks PDF] {pesan}"))

        if not is_na(k["nomor_teks"]) and norm_nomor(k["nomor_teks"]) != norm_nomor(nomor):
            catatan = str(r["catatan"])
            if _nomor_core(k["nomor_teks"]) == _nomor_core(nomor):
                add("file_pdf", "info", f"nomor di PDF {k['nomor_teks']!r} beda penulisan kode perkara dengan {nomor!r}")
            elif _nomor_core(k["nomor_teks"])[0] in catatan:
                add("file_pdf", "info", f"PDF berisi putusan {k['nomor_teks']!r} (sudah dijelaskan di catatan)")
                continue
            else:
                add("file_pdf", "galat", f"PDF berisi putusan bernomor {k['nomor_teks']!r}, bukan {nomor!r}")
                continue
        if not is_na(k["tahun_putusan_teks"]) and int(k["tahun_putusan_teks"]) != int(r["tahun_putusan"]):
            add("tahun_putusan", "peringatan",
                f"tanggal di teks {k['tanggal_putusan_teks']} vs tahun_putusan {r['tahun_putusan']}")
        if not is_na(k["hasil_kandidat"]) and not is_na(r["hasil_putusan"]) and k["hasil_kandidat"] != r["hasil_putusan"]:
            add("hasil_putusan", "peringatan",
                f"pola amar menunjukkan {k['hasil_kandidat']!r} ({k['dasar_hasil_kandidat']})")
        teks_bbm = str(k["jenis_bbm_disebut"]).lower() if not is_na(k["jenis_bbm_disebut"]) else ""
        barang = str(r["barang_bbm"]).lower()
        for nama, pola in BBM_TEXT_CHECK.items():
            if nama in barang and not re.search(pola, teks_bbm):
                add("barang_bbm", "peringatan", f"'{nama}' di rekap tetapi tidak disebut di teks PDF")
        vol = r["nilai_kerugian_volume"]
        if not is_na(vol) and r["satuan_volume"] == "liter":
            cands = _num_set(k["volume_liter_di_amar"])
            others = {k["volume_liter_di_amar_jumlah"], k["volume_liter_maks_teks"]}
            if cands and float(vol) not in cands and float(vol) not in others:
                add("nilai_kerugian_volume", "info",
                    f"volume {vol:g} liter tidak sama dengan angka liter di amar ({k['volume_liter_di_amar']})")
    return out


def issues_frame(issues: list[Issue]) -> pd.DataFrame:
    order = {"galat": 0, "peringatan": 1, "info": 2}
    df = pd.DataFrame([asdict(i) for i in issues], columns=["no", "nomor_putusan", "kolom", "tingkat", "pesan"])
    if df.empty:
        return df
    df["_o"] = df["tingkat"].map(order)
    return df.sort_values(["_o", "no"], na_position="last").drop(columns="_o").reset_index(drop=True)


def summary_counts(df: pd.DataFrame) -> dict:
    """Angka ringkas untuk berkas metodologi."""
    def vc(col):
        return {str(k): int(v) for k, v in df[col].fillna("NA").value_counts().sort_index().items()}

    na_cols = ["barang_bbm", "hasil_putusan", "nilai_kerugian_uang", "nilai_kerugian_volume", "tahun_kejadian"]
    return {
        "baris": len(df),
        "rantai_perkara": int(df["rantai_perkara"].nunique()),
        "per_tahun_putusan": vc("tahun_putusan"),
        "per_tingkat": vc("tingkat_persidangan"),
        "per_sumber_daftar": vc("sumber_daftar"),
        "per_sumber_data": vc("sumber_data"),
        "dengan_pdf": int(df["file_pdf"].notna().sum()),
        "relevan_bbm": vc("relevan_bbm"),
        "jumlah_na": {c: int(df[c].isna().sum()) for c in na_cols},
    }
