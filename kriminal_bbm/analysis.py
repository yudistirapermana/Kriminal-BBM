"""Dataset tingkat perkara (rantai PN -> PT -> MA) dan tabel ringkasan.

Satu perkara bisa muncul di beberapa baris rekap (PN, PT, MA) dan direktori kadang
memuat entri ganda untuk putusan yang sama. Untuk analisis ekonomi, unit yang tepat
biasanya PERKARA (rantai), bukan putusan, agar volume BBM tidak terhitung berulang.
"""

from __future__ import annotations

import re
from pathlib import Path

import pandas as pd

from .extract import MODUS_PASAL, PASAL_RE, modus_dari_amar, parse_date
from .regions import _LOOKUP as _COURT_PLACES
from .regions import _key as _place_key
from .regions import provinsi
from .validate import is_na, norm_nomor

LEVEL_ORDER = {"Pertama": 0, "Banding": 1, "Kasasi": 2, "Peninjauan Kembali": 3}
# Urutan sumber fakta perkara (jenis BBM, volume, nilai, tahun kejadian): tingkat pertama dulu.
FACT_PRIORITY = {"PN": 0, "Pengadilan Militer": 1, "PT": 2, "MA": 3}

BBM_DUMMIES = {
    "bbm_solar": r"solar|hsd",
    "bbm_pertalite": r"pertalite",
    "bbm_premium": r"premium",
    "bbm_pertamax": r"pertamax",
    "bbm_dexlite": r"dexlite",
    "bbm_minyak_tanah": r"minyak tanah",
    "bbm_minyak_mentah_olahan": r"minyak mentah|olahan ilegal|kondensat",
    "bbm_tidak_disebut": r"jenis tidak disebut",
}


def status_subsidi(barang: str | None) -> str:
    """'subsidi' / 'non-subsidi' / 'campuran' / 'tidak disebut' dari teks kolom barang_bbm."""
    if is_na(barang):
        return "tidak disebut"
    b = str(barang).lower()
    has_non = bool(re.search(r"non-subsidi|non subsidi|industri", b))
    has_sub = bool(re.search(r"(?<!non-)(?<!non )subsidi(?!\s+tidak)", b)) and "status subsidi tidak disebut" not in b
    # Pertalite & Premium: BBM penugasan (JBKP) yang harganya diatur pemerintah.
    penugasan = bool(re.search(r"pertalite|premium", b))
    if (has_sub or penugasan) and has_non:
        return "campuran"
    if has_sub:
        return "subsidi"
    if penugasan:
        return "penugasan (JBKP)"
    if has_non:
        return "non-subsidi"
    return "tidak disebut"


def add_bbm_columns(df: pd.DataFrame) -> pd.DataFrame:
    b = df["barang_bbm"].fillna("").str.lower()
    for col, pat in BBM_DUMMIES.items():
        df[col] = b.str.contains(pat, regex=True).astype(int)
    df["status_subsidi"] = df["barang_bbm"].map(status_subsidi)
    df["jumlah_jenis_bbm"] = df[list(BBM_DUMMIES)].sum(axis=1)
    return df


def pasal_dari_rekap(row: pd.Series) -> str | None:
    """Pasal UU 22/2001 (53a-d, 54, 55) yang disebut di kolom rincian_amar/catatan,
    ditambah frasa delik di rincian_amar."""
    text = " ".join(str(row.get(c, "")) for c in ("rincian_amar", "catatan"))
    codes: list[str] = []
    for m in PASAL_RE.finditer(text):
        code = m.group(1) + (m.group(2).lower() if m.group(2) and m.group(1) == "53" else "")
        codes.append(code)
    # "Pasal 53 huruf b dan d" -> 53b, 53d
    for m in re.finditer(r"Pasal\s+53\s+huruf\s+([a-d])((?:\s*(?:,|dan|&)\s*[a-d]\b)+)", text, re.IGNORECASE):
        codes.extend("53" + x for x in re.findall(r"\b([a-d])\b", m.group(2)))
    codes.extend(modus_dari_amar(str(row.get("rincian_amar", ""))))
    out = []
    for c in codes:
        if c == "53" and any(x.startswith("53") and len(x) == 3 for x in codes):
            continue
        if c not in out:
            out.append(c)
    return ";".join(sorted(out)) or None


def dedupe(df: pd.DataFrame) -> pd.DataFrame:
    """Buang entri direktori ganda (nomor & tanggal sama); simpan yang ber-PDF."""
    df = df.copy()
    df["_key"] = df["nomor_putusan"].map(norm_nomor) + "|" + df["tanggal_putusan"].astype(str)
    df["_haspdf"] = df["file_pdf"].notna().astype(int)
    df = df.sort_values(["_key", "_haspdf", "no"], ascending=[True, False, True])
    dup = df["_key"].duplicated(keep="first")
    removed = df[dup]
    df = df[~dup].sort_values("no").drop(columns=["_key", "_haspdf"])
    df.attrs["duplikat_dibuang"] = removed["no"].tolist()
    return df


def prepare(df: pd.DataFrame) -> pd.DataFrame:
    df = df.copy()
    df["tanggal"] = df["tanggal_putusan"].map(lambda s: parse_date(str(s)))
    df["level"] = df["tingkat_proses"].map(LEVEL_ORDER).fillna(0).astype(int)
    df["prioritas_fakta"] = df["tingkat_persidangan"].map(FACT_PRIORITY).fillna(9).astype(int)
    df["pengadilan"] = df["pengadilan"].str.upper().str.strip()
    df["provinsi_pengadilan"] = df["pengadilan"].map(provinsi)
    df["pasal_uu_migas"] = df.apply(pasal_dari_rekap, axis=1)
    return add_bbm_columns(df)


def _merge_pasal(values: pd.Series) -> str | None:
    codes = {p for v in values.dropna() for p in v.split(";")}
    if any(c.startswith("53") and len(c) == 3 for c in codes):
        codes.discard("53")
    return ";".join(sorted(codes)) or None


def _first(rows: pd.DataFrame, col: str):
    for v in rows[col]:
        if not is_na(v):
            return v
    return None


def case_level(df: pd.DataFrame, candidates: pd.DataFrame | None = None) -> pd.DataFrame:
    """Satu baris per rantai_perkara."""
    asal = {}
    if candidates is not None and "pengadilan_asal_teks" in candidates:
        asal = dict(zip(candidates["file_pdf"], candidates["pengadilan_asal_teks"]))
    out = []
    for chain, g in df.groupby("rantai_perkara", sort=True):
        by_fact = g.assign(_pdf=g["file_pdf"].isna().astype(int)).sort_values(["prioritas_fakta", "_pdf", "no"])
        by_time = g.assign(_t=g["tanggal"].map(lambda d: d.toordinal() if d else 0)).sort_values(["_t", "level", "no"])
        first_inst = g[g["tingkat_persidangan"].isin(["PN", "Pengadilan Militer"])]
        last = by_time.iloc[-1]
        hasil_akhir = last["hasil_putusan"]
        if is_na(hasil_akhir):
            hasil_akhir = None

        prov = _first(by_fact, "provinsi_pengadilan")
        sumber_prov = "pengadilan dalam rantai" if prov else None
        if not prov:
            for fp in by_fact["file_pdf"].dropna():
                p = provinsi(asal.get(fp))
                if p:
                    prov, sumber_prov = p, "pengadilan asal disebut di teks PDF"
                    break

        barang = _first(by_fact, "barang_bbm")
        vol_row = by_fact[by_fact["nilai_kerugian_volume"].notna()]
        uang_row = by_fact[by_fact["nilai_kerugian_uang"].notna()]
        rec = {
            "rantai_perkara": chain,
            "jumlah_putusan": len(g),
            "tingkat_tercakup": "+".join(sorted(set(g["tingkat_persidangan"]), key=lambda t: FACT_PRIORITY.get(t, 9))),
            "nomor_putusan_pertama": _first(first_inst, "nomor_putusan") if len(first_inst) else None,
            "pengadilan_pertama": _first(first_inst, "pengadilan") if len(first_inst) else None,
            "provinsi": prov,
            "sumber_provinsi": sumber_prov,
            "tahun_kejadian": _first(by_fact, "tahun_kejadian"),
            "tahun_putusan_awal": int(g["tahun_putusan"].min()),
            "tahun_putusan_akhir": int(g["tahun_putusan"].max()),
            "nomor_putusan_terakhir": last["nomor_putusan"],
            "tingkat_terakhir": last["tingkat_proses"],
            "tanggal_putusan_terakhir": last["tanggal_putusan"],
            "hasil_tingkat_pertama": _first(first_inst, "hasil_putusan") if len(first_inst) else None,
            "hasil_akhir": hasil_akhir,
            "hasil_berubah_antartingkat": int(g["hasil_putusan"].dropna().nunique() > 1),
            "barang_bbm": barang,
            "status_subsidi": status_subsidi(barang),
            "volume": vol_row["nilai_kerugian_volume"].iloc[0] if len(vol_row) else None,
            "satuan_volume": vol_row["satuan_volume"].iloc[0] if len(vol_row) else None,
            "volume_dari": vol_row["nomor_putusan"].iloc[0] if len(vol_row) else None,
            "nilai_uang_rp": uang_row["nilai_kerugian_uang"].iloc[0] if len(uang_row) else None,
            "dasar_nilai_uang": uang_row["dasar_nilai_uang"].iloc[0] if len(uang_row) else None,
            "pasal_uu_migas": _merge_pasal(g["pasal_uu_migas"]),
            "sumber_daftar": "; ".join(sorted(set(g["sumber_daftar"].dropna()))),
            "ada_pdf": int(g["file_pdf"].notna().any()),
            "nomor_putusan_semua": "; ".join(by_time["nomor_putusan"]),
        }
        b = str(barang or "").lower()
        for col, pat in BBM_DUMMIES.items():
            rec[col] = int(bool(re.search(pat, b)))
        out.append(rec)
    cases = pd.DataFrame(out)
    cases["volume_liter"] = cases.apply(lambda r: r["volume"] if r["satuan_volume"] == "liter" else None, axis=1)
    entities = {ch: _entities(g) for ch, g in df.groupby("rantai_perkara")}
    return group_incidents(cases, entities)


# ----------------------------------------------------------------------------- kejadian yang sama

_SHIP_RE = re.compile(r"\b(?:KM|KMP|KLM|MT|TB|LCT)\.?\s+([A-Z][A-Za-z0-9]*(?:\s+[A-Z0-9][A-Za-z0-9]*){0,3})")
_COMPANY_RE = re.compile(r"\b(?:PT|CV)\.?\s+([A-Z][A-Za-z]+(?:\s+[A-Z][A-Za-z]+){0,3})")


def _entities(g: pd.DataFrame) -> set[str]:
    """Nama kapal/perusahaan yang disebut di kolom teks rekap (untuk mengenali berkas terpisah)."""
    text = " ".join(
        str(v) for c in ("catatan", "keterangan_volume", "rincian_amar", "bukti_kutipan", "dasar_nilai_uang")
        for v in g.get(c, pd.Series(dtype=str)).dropna()
    )
    # Buang kode pengadilan di nomor perkara ("411/PID.SUS/2023/PT MDN") agar tidak terbaca sebagai PT/perusahaan.
    text = re.sub(r"/\s*P[TN]\.?\s*[A-Za-z.]+", "/", text)
    found = {"KAPAL " + m.group(1).upper() for m in _SHIP_RE.finditer(text)}
    for m in _COMPANY_RE.finditer(text):
        name = m.group(1).upper()
        # "PT Semarang" = Pengadilan Tinggi, bukan perusahaan; Pertamina disebut di banyak perkara.
        if _place_key(name.split()[0]) in _COURT_PLACES or _place_key(name) in _COURT_PLACES or "PERTAMINA" in name:
            continue
        found.add("PERUSAHAAN " + name)
    return found


def group_incidents(cases: pd.DataFrame, entities: dict[str, set[str]]) -> pd.DataFrame:
    """Tandai rantai perkara yang kemungkinan berasal dari SATU kejadian (berkas terpisah/splitsing
    untuk beberapa terdakwa): pengadilan asal sama, selisih tahun putusan <= 2, dan volume sama
    atau menyebut kapal/perusahaan yang sama. Ini heuristik - periksa kolom dasar_kelompok."""
    cases = cases.copy()
    loc = cases["pengadilan_pertama"].fillna(cases["provinsi"].fillna("?") + "|" + cases["tingkat_tercakup"])
    parent = list(range(len(cases)))
    reason: dict[int, set[str]] = {i: set() for i in range(len(cases))}

    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    rows = cases.to_dict("records")
    for i in range(len(rows)):
        for j in range(i + 1, len(rows)):
            a, b = rows[i], rows[j]
            if loc.iloc[i] != loc.iloc[j] or abs(a["tahun_putusan_awal"] - b["tahun_putusan_awal"]) > 2:
                continue
            ka, kb = a["tahun_kejadian"], b["tahun_kejadian"]
            if not is_na(ka) and not is_na(kb) and str(ka)[:4] != str(kb)[:4]:
                continue
            why = []
            if not is_na(a["volume_liter"]) and a["volume_liter"] == b["volume_liter"]:
                why.append(f"volume sama {a['volume_liter']:g} L")
            shared = entities.get(a["rantai_perkara"], set()) & entities.get(b["rantai_perkara"], set())
            if shared:
                why.append("menyebut " + ", ".join(sorted(shared)))
            if why:
                parent[find(j)] = find(i)
                reason[i].update(why)
                reason[j].update(why)

    roots = [find(i) for i in range(len(rows))]
    sizes = pd.Series(roots).value_counts()
    labels, n = {}, 0
    for r in sorted(set(roots), key=lambda r: rows[r]["rantai_perkara"]):
        if sizes[r] > 1:
            n += 1
            labels[r] = f"K{n:02d}"
    cases["kelompok_kejadian"] = [labels.get(r, rows[i]["rantai_perkara"]) for i, r in enumerate(roots)]
    cases["jumlah_rantai_sekelompok"] = [int(sizes[r]) for r in roots]
    cases["dasar_kelompok"] = ["; ".join(sorted(reason[i])) if sizes[roots[i]] > 1 else None for i in range(len(rows))]
    # Volume per kelompok dihitung sekali: ambil volume terbesar dalam kelompok.
    vmax = cases.groupby("kelompok_kejadian")["volume_liter"].transform("max")
    first = ~cases.duplicated("kelompok_kejadian")
    cases["volume_liter_kelompok"] = vmax.where(first)
    return cases


# ----------------------------------------------------------------------------- ringkasan

def _crosstab(a: pd.Series, b: pd.Series) -> pd.DataFrame:
    t = pd.crosstab(a.fillna("NA"), b.fillna("NA"), margins=True, margins_name="Total")
    t.index.name = a.name
    return t


def _vol_stats(g: pd.DataFrame) -> pd.Series:
    v = g["volume_liter"].dropna().astype(float)
    return pd.Series({
        "perkara": len(g),
        "perkara_dengan_volume": len(v),
        "total_liter": v.sum(),
        "median_liter": v.median() if len(v) else None,
        "rata2_liter": v.mean() if len(v) else None,
        "p90_liter": v.quantile(0.9) if len(v) else None,
        "maks_liter": v.max() if len(v) else None,
    })


def summaries(decisions: pd.DataFrame, cases: pd.DataFrame) -> dict[str, pd.DataFrame]:
    tabs: dict[str, pd.DataFrame] = {}
    tabs["putusan_tahun_x_tingkat"] = _crosstab(decisions["tahun_putusan"], decisions["tingkat_persidangan"])
    tabs["perkara_tahun_awal_x_hasil_akhir"] = _crosstab(cases["tahun_putusan_awal"], cases["hasil_akhir"])
    tabs["perkara_volume_per_tahun_awal"] = (
        cases.groupby("tahun_putusan_awal")[["volume_liter"]].apply(_vol_stats).reset_index()
    )

    rows = []
    single = cases[cases[list(BBM_DUMMIES)].sum(axis=1) == 1]
    for col in BBM_DUMMIES:
        s = single[single[col] == 1]
        stats = _vol_stats(s)
        rows.append({
            "jenis_bbm": col.removeprefix("bbm_"),
            "perkara_menyebut": int(cases[col].sum()),
            "perkara_satu_jenis": int(len(s)),
            "total_liter_satu_jenis": stats["total_liter"],
            "median_liter_satu_jenis": stats["median_liter"],
        })
    tabs["perkara_per_jenis_bbm"] = pd.DataFrame(rows)
    tabs["perkara_per_status_subsidi"] = (
        cases.groupby("status_subsidi")[["volume_liter"]].apply(_vol_stats).reset_index()
    )
    tabs["perkara_per_provinsi"] = (
        cases.assign(provinsi=cases["provinsi"].fillna("Tidak diketahui"))
        .groupby("provinsi")[["volume_liter"]].apply(_vol_stats).reset_index()
        .sort_values("perkara", ascending=False)
    )
    pasal_rows = []
    for code, label in MODUS_PASAL.items():
        mask = cases["pasal_uu_migas"].fillna("").str.split(";").map(lambda xs, c=code: c in xs)
        pasal_rows.append({"pasal": code, "uraian": label, "perkara": int(mask.sum())})
    none = cases["pasal_uu_migas"].isna().sum()
    pasal_rows.append({"pasal": "-", "uraian": "pasal tidak tercatat di rincian_amar/catatan", "perkara": int(none)})
    tabs["perkara_per_pasal_uu_migas"] = pd.DataFrame(pasal_rows)
    grouped = cases[cases["jumlah_rantai_sekelompok"] > 1]
    tabs["kelompok_kejadian_kemungkinan_sama"] = (
        grouped.groupby("kelompok_kejadian")
        .agg(rantai=("rantai_perkara", ", ".join), pengadilan=("pengadilan_pertama", "first"),
             volume_liter_maks=("volume_liter", "max"), dasar=("dasar_kelompok", "first"))
        .reset_index()
    )
    tabs["perkara_per_sumber_daftar"] = cases["sumber_daftar"].value_counts().rename_axis("sumber_daftar").reset_index(name="perkara")
    return tabs


def _fmt(x) -> str:
    """Angka bulat dengan pemisah ribuan titik (gaya Indonesia)."""
    return "" if x is None or pd.isna(x) else f"{x:,.0f}".replace(",", ".")


def _md_table(df: pd.DataFrame) -> str:
    df = df.copy()
    for c in df.columns:
        if pd.api.types.is_float_dtype(df[c]):
            df[c] = df[c].map(_fmt)
    df = df.reset_index() if df.index.name else df
    cols = [str(c) for c in df.columns]
    lines = ["| " + " | ".join(cols) + " |", "|" + "---|" * len(cols)]
    for _, r in df.iterrows():
        lines.append("| " + " | ".join("" if pd.isna(v) else str(v) for v in r.values) + " |")
    return "\n".join(lines)


TITLES = {
    "putusan_tahun_x_tingkat": "Putusan per tahun putusan dan tingkat (setelah entri ganda dibuang)",
    "perkara_tahun_awal_x_hasil_akhir": "Perkara per tahun putusan paling awal di dataset dan hasil akhir",
    "perkara_volume_per_tahun_awal": "Volume BBM (liter) per perkara menurut tahun putusan awal",
    "perkara_per_jenis_bbm": "Perkara per jenis BBM (volume hanya untuk perkara satu jenis BBM)",
    "perkara_per_status_subsidi": "Perkara menurut status subsidi BBM objek perkara",
    "perkara_per_provinsi": "Perkara per provinsi (dari pengadilan tingkat pertama/banding)",
    "perkara_per_pasal_uu_migas": "Perkara per pasal UU 22/2001 yang disebut (satu perkara bisa >1 pasal)",
    "perkara_per_sumber_daftar": "Perkara menurut jalur penemuan",
    "kelompok_kejadian_kemungkinan_sama": "Rantai perkara yang kemungkinan satu kejadian (heuristik, perlu dicek)",
}


def write_outputs(rekap: pd.DataFrame, out_dir: str | Path, candidates: pd.DataFrame | None = None) -> dict:
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    dedup = dedupe(rekap)
    decisions = prepare(dedup)
    cases = case_level(decisions, candidates)

    decision_cols = [c for c in rekap.columns if c not in {"bukti_kutipan"}] + [
        "provinsi_pengadilan", "pasal_uu_migas", "status_subsidi", *BBM_DUMMIES,
    ]
    decisions[decision_cols].to_csv(out_dir / "putusan_bersih_dengan_variabel.csv", index=False, encoding="utf-8-sig")
    cases.to_csv(out_dir / "rekap_perkara_unik.csv", index=False, encoding="utf-8-sig")

    tabs = summaries(decisions, cases)
    for name, t in tabs.items():
        t.to_csv(out_dir / f"ringkasan_{name}.csv", encoding="utf-8-sig", index=t.index.name is not None)

    n_vol = int(cases["volume_liter"].notna().sum())
    md = [
        "# Ringkasan statistik kriminalitas BBM (Direktori Putusan MA)",
        "",
        "Dibuat otomatis oleh `python -m kriminal_bbm analyze` dari "
        "`rekap_putusan_kriminalitas_BBM_2020-2026.csv`. Jangan disunting manual; jalankan ulang perintahnya.",
        "",
        f"- Baris rekap: {len(rekap)}; entri direktori ganda yang dibuang: {len(dedup.attrs['duplikat_dibuang'])} "
        f"(baris no {', '.join(map(str, dedup.attrs['duplikat_dibuang'])) or '-'}).",
        f"- Putusan unik: {len(decisions)}; perkara unik (rantai): {len(cases)}.",
        f"- Perkara dengan volume dalam liter: {n_vol}; total {_fmt(cases['volume_liter'].sum())} liter "
        f"(median {_fmt(cases['volume_liter'].median())} liter).",
        f"- Kelompok kejadian yang kemungkinan sama (berkas terpisah/splitsing): "
        f"{cases.loc[cases['jumlah_rantai_sekelompok'] > 1, 'kelompok_kejadian'].nunique()} kelompok mencakup "
        f"{int((cases['jumlah_rantai_sekelompok'] > 1).sum())} rantai. Bila tiap kelompok dihitung sekali, "
        f"total volume menjadi {_fmt(cases['volume_liter_kelompok'].sum())} liter.",
        "",
        "Catatan tafsir:",
        "",
        "1. Dataset adalah SAMPEL (klasifikasi Migas + rantai perkaranya + tabulasi tim), bukan populasi putusan BBM.",
        "   Perubahan jumlah antartahun mencerminkan jalur penemuan, bukan tren kriminalitas.",
        "   Khususnya, hampir semua putusan 2026 berasal dari tabulasi tim (`sumber_daftar`), bukan dari klasifikasi Migas.",
        "2. Volume diambil dari putusan tingkat pertama bila ada; satu perkara dihitung sekali.",
        "3. `nilai_uang_rp` umumnya nilai BBM barang bukti, bukan kerugian negara; baca `dasar_nilai_uang`.",
        "4. Hasil akhir = status terdakwa menurut putusan paling akhir di dataset; perkara yang upaya hukumnya",
        "   di luar 2020-2026 atau tidak ditemukan berhenti pada tingkat yang tersedia.",
        "",
    ]
    for name, t in tabs.items():
        md += [f"## {TITLES.get(name, name)}", "", _md_table(t), ""]
    (out_dir / "ringkasan_statistik.md").write_text("\n".join(md), encoding="utf-8")
    return {"decisions": decisions, "cases": cases, "tables": tabs}
