"""Penelusuran Direktori Putusan: daftar klasifikasi -> overview -> rantai perkara -> PDF.

Alur sama dengan yang dipakai untuk membangun rekap 2020-2026:
1. ambil semua entri pada daftar klasifikasi (default Pidana Khusus > Migas), atau dari
   HTML hasil pencarian yang disimpan manual (pencarian kata kunci memerlukan CAPTCHA),
   atau dari daftar URL;
2. buka halaman overview tiap putusan, catat metadata dan tautan "Putusan Terkait";
3. ikuti tautan terkait (PN -> PT -> MA -> PK) agar seluruh rantai perkara terambil;
4. unduh PDF putusan yang diputus dalam rentang tahun;
5. kelompokkan putusan ke rantai perkara dan tandai relevansi BBM (kandidat).

Hasil mentah disimpan di data_mentah/ (tidak masuk git karena dapat memuat nama
terdakwa). Kolom tujuh-variabel diisi kemudian (manual atau `llm-code`).
"""

from __future__ import annotations

import re
from collections import deque
from pathlib import Path

import pandas as pd

from .directory import (
    canonical_url, max_page, page_url, parse_listing, parse_overview, putusan_id, year_filter_url,
)
from .extract import jenis_bbm, parse_date, relevansi_bbm, tingkat_from_nomor
from .pdftext import cached_text
from .web import CaptchaRequired, PoliteSession, RobotsDisallowed

OVERVIEW_COLUMNS = [
    "id", "url", "nomor", "tingkat_proses", "klasifikasi", "kata_kunci", "tahun", "tanggal_register",
    "lembaga_peradilan", "jenis_lembaga_peradilan", "amar", "amar_lainnya", "catatan_amar",
    "tanggal_musyawarah", "tanggal_dibacakan", "status", "url_pdf", "lampiran_pdf", "file_pdf",
    "tahun_putusan", "dalam_rentang_tahun", "sumber_daftar", "ditemukan_dari", "rantai_perkara",
    "jenis_bbm_disebut", "relevan_bbm_kandidat", "dasar_relevansi",
]

REKAP_DRAFT_COLUMNS = [
    "nomor_putusan", "pengadilan", "tingkat_persidangan", "tingkat_proses", "tanggal_putusan",
    "tahun_putusan", "tahun_kejadian", "hasil_putusan", "rincian_amar", "barang_bbm", "relevan_bbm",
    "nilai_kerugian_uang", "mata_uang", "dasar_nilai_uang", "nilai_kerugian_volume", "satuan_volume",
    "keterangan_volume", "sumber_data", "lampiran_pdf", "file_pdf", "rantai_perkara", "klasifikasi",
    "sumber_daftar", "url_putusan", "bukti_kutipan", "catatan",
]


def safe_filename(nomor: str) -> str:
    name = re.sub(r"[\\/:*?\"<>|]+", "_", nomor.strip())
    return re.sub(r"\s+", "_", name)


def _year(d: dict) -> int | None:
    for key in ("tanggal_dibacakan", "tanggal_musyawarah"):
        dt = parse_date(d.get(key) or "")
        if dt:
            return dt.year
    try:
        return int(str(d.get("tahun", "")).strip()[:4])
    except ValueError:
        return None


def _listing_year(item: dict) -> int | None:
    v = item.get("tanggal_putus")
    m = re.search(r"(\d{4})$", v or "")
    return int(m.group(1)) if m else None


def assign_chains(ids: list[str], edges: list[tuple[str, str]], years: dict[str, int | None]) -> dict[str, str]:
    """Komponen terhubung dari graf 'putusan terkait' -> id rantai R0001, R0002, ... (urut tahun)."""
    parent = {i: i for i in ids}

    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    for a, b in edges:
        if a in parent and b in parent:
            parent[find(a)] = find(b)
    groups: dict[str, list[str]] = {}
    for i in ids:
        groups.setdefault(find(i), []).append(i)
    ordered = sorted(groups.values(), key=lambda g: (min((years.get(x) or 9999) for x in g), min(g)))
    return {x: f"R{n:04d}" for n, g in enumerate(ordered, 1) for x in g}


class Crawler:
    def __init__(self, session: PoliteSession, out_dir: str | Path, pdf_dir: str | Path,
                 text_cache: str | Path, years: tuple[int, int] = (2020, 2026),
                 follow_related: bool = True, download_pdf: bool = True, log=print):
        self.s = session
        self.out_dir = Path(out_dir)
        self.pdf_dir = Path(pdf_dir)
        self.text_cache = Path(text_cache)
        self.years = years
        self.follow_related = follow_related
        self.download_pdf = download_pdf
        self.log = log
        self.queue: deque[tuple[str, str, str | None]] = deque()
        self.rows: dict[str, dict] = {}
        self.edges: list[tuple[str, str, str | None]] = []
        self.failures: list[tuple[str, str]] = []
        self._queued: set[str] = set()

    # ------------------------------------------------------------------ benih
    def enqueue(self, url: str, sumber: str, parent: str | None = None):
        pid = putusan_id(url)
        if pid and pid not in self._queued:
            self._queued.add(pid)
            self.queue.append((canonical_url(url), sumber, parent))

    def _seed_items(self, items: list[dict], sumber: str) -> int:
        n = 0
        for it in items:
            y = _listing_year(it)
            if y is not None and not self.years[0] <= y <= self.years[1]:
                continue
            self.enqueue(it["url"], sumber)
            n += 1
        return n

    def seed_listing(self, listing_url: str, max_pages: int | None = None, per_year: bool = False):
        urls = [year_filter_url(listing_url, y) for y in range(self.years[0], self.years[1] + 1)] if per_year else [listing_url]
        label = "daftar " + re.sub(r"^.*/kategori/", "", listing_url).removesuffix(".html")
        for lu in urls:
            first = self.s.get_html(page_url(lu, 1))
            last = max_page(first, lu)
            if max_pages:
                last = min(last, max_pages)
            self.log(f"{lu}: {last} halaman")
            for p in range(1, last + 1):
                html = first if p == 1 else self.s.get_html(page_url(lu, p))
                n = self._seed_items(parse_listing(html, page_url(lu, p)), label)
                self.log(f"  halaman {p}/{last}: {n} entri dalam rentang tahun")

    def seed_html_files(self, files: list[Path]):
        for f in files:
            items = parse_listing(Path(f).read_text(encoding="utf-8", errors="replace"))
            n = self._seed_items(items, "pencarian (HTML tersimpan)")
            self.log(f"{f.name}: {n} entri")

    def seed_urls(self, urls: list[str]):
        for u in urls:
            self.enqueue(u.strip(), "daftar URL")

    # ------------------------------------------------------------------ jalan
    def run(self, limit: int | None = None, save_every: int = 25):
        done = 0
        while self.queue:
            url, sumber, parent = self.queue.popleft()
            pid = putusan_id(url)
            if pid in self.rows:
                continue
            try:
                d = parse_overview(self.s.get_html(url), url)
            except (CaptchaRequired, RobotsDisallowed):
                self.queue.appendleft((url, sumber, parent))
                self.save()
                raise
            except Exception as e:  # 404, halaman rusak, dll.: catat lalu lanjut
                self.log(f"  gagal membuka {url}: {e}")
                self.failures.append((url, str(e)))
                continue
            year = _year(d)
            d["tahun_putusan"] = year
            d["dalam_rentang_tahun"] = bool(year and self.years[0] <= year <= self.years[1])
            d["sumber_daftar"] = sumber
            d["ditemukan_dari"] = parent
            for rel in d.pop("terkait"):
                self.edges.append((pid, rel["id"], rel.get("label")))
                if self.follow_related:
                    self.enqueue(rel["url"], "putusan terkait", pid)
            if self.download_pdf and d["dalam_rentang_tahun"] and d.get("url_pdf"):
                dest = self.pdf_dir / f"{safe_filename(d.get('nomor') or pid)}.pdf"
                try:
                    self.s.download(d["url_pdf"], dest)
                    d["file_pdf"] = f"pdf/{dest.name}"
                    d["_pdf_path"] = str(dest)
                except (CaptchaRequired, RobotsDisallowed):
                    raise
                except Exception as e:
                    self.log(f"  gagal mengunduh PDF {d['url_pdf']}: {e}")
                    self.failures.append((d["url_pdf"], str(e)))
            self._relevance(d)
            self.rows[pid] = d
            done += 1
            self.log(f"[{done}] {d.get('nomor')} ({year}) {'' if d['dalam_rentang_tahun'] else '[di luar rentang]'} "
                     f"terkait={sum(1 for e in self.edges if e[0] == pid)} antrean={len(self.queue)}")
            if done % save_every == 0:
                self.save()
            if limit and done >= limit:
                self.log("batas --limit tercapai; antrean tersisa disimpan di berkas log")
                break
        self.save()

    def _relevance(self, d: dict):
        text = " ".join(str(d.get(k) or "") for k in ("kata_kunci", "catatan_amar", "amar_lainnya", "abstrak", "judul"))
        basis = "overview"
        if d.get("_pdf_path"):
            try:
                text = cached_text(d["_pdf_path"], self.text_cache)
                basis = "teks PDF"
            except Exception as e:  # PDF rusak/terenkripsi: tetap pakai overview
                self.log(f"  gagal membaca PDF {d['file_pdf']}: {e}")
        counts = jenis_bbm(text)
        d["jenis_bbm_disebut"] = "; ".join(f"{k} ({v})" for k, v in counts.items()) or None
        d["relevan_bbm_kandidat"] = relevansi_bbm(counts, text)
        d["dasar_relevansi"] = basis

    # ------------------------------------------------------------------ simpan
    def save(self):
        self.out_dir.mkdir(parents=True, exist_ok=True)
        ids = list(self.rows)
        chains = assign_chains(ids, [(a, b) for a, b, _ in self.edges], {i: self.rows[i]["tahun_putusan"] for i in ids})
        for i in ids:
            self.rows[i]["rantai_perkara"] = chains[i]
        df = pd.DataFrame(self.rows.values())
        for c in OVERVIEW_COLUMNS:
            if c not in df:
                df[c] = None
        df = df[OVERVIEW_COLUMNS + [c for c in df.columns if c not in OVERVIEW_COLUMNS and not c.startswith("_")]]
        df.to_csv(self.out_dir / "putusan_overview.csv", index=False, encoding="utf-8-sig")
        pd.DataFrame(self.edges, columns=["dari_id", "ke_id", "label"]).drop_duplicates().to_csv(
            self.out_dir / "putusan_terkait.csv", index=False, encoding="utf-8-sig")
        (self.out_dir / "antrean_tersisa.txt").write_text("\n".join(u for u, _, _ in self.queue), encoding="utf-8")
        pd.DataFrame(self.failures, columns=["url", "galat"]).to_csv(
            self.out_dir / "gagal.csv", index=False, encoding="utf-8-sig")
        draft_rekap(df).to_csv(self.out_dir / "draf_rekap_untuk_dikoding.csv", index=False, encoding="utf-8-sig")


def draft_rekap(overview: pd.DataFrame) -> pd.DataFrame:
    """Baris dalam rentang tahun, dalam format kolom rekap; tujuh kolom utama dibiarkan kosong."""
    if overview.empty:
        return pd.DataFrame(columns=REKAP_DRAFT_COLUMNS)
    df = overview[overview["dalam_rentang_tahun"].astype(bool)].copy()

    def tingkat(row):
        t = tingkat_from_nomor(row.get("nomor"))
        if t and t.startswith("MA"):
            return "MA"
        if t:
            return t
        j = str(row.get("jenis_lembaga_peradilan") or "").upper()
        return {"PN": "PN", "PT": "PT", "MA": "MA"}.get(j, j or None)

    out = pd.DataFrame({
        "nomor_putusan": df["nomor"],
        "pengadilan": df["lembaga_peradilan"],
        "tingkat_persidangan": df.apply(tingkat, axis=1),
        "tingkat_proses": df["tingkat_proses"],
        "tanggal_putusan": df["tanggal_dibacakan"],
        "tahun_putusan": df["tahun_putusan"],
        "relevan_bbm": df["relevan_bbm_kandidat"],
        "sumber_data": df["file_pdf"].map(lambda f: "PDF putusan" if isinstance(f, str) else "Overview direktori"),
        "lampiran_pdf": df["lampiran_pdf"],
        "file_pdf": df["file_pdf"],
        "rantai_perkara": df["rantai_perkara"],
        "klasifikasi": df["klasifikasi"],
        "sumber_daftar": df["sumber_daftar"],
        "url_putusan": df["url"],
        "catatan": df["jenis_bbm_disebut"].map(lambda s: f"Jenis BBM disebut (otomatis): {s}" if isinstance(s, str) else None),
    })
    for c in REKAP_DRAFT_COLUMNS:
        if c not in out:
            out[c] = None
    return out[REKAP_DRAFT_COLUMNS].sort_values(["rantai_perkara", "tahun_putusan"]).reset_index(drop=True)
