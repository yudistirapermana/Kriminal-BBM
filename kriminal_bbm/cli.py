"""Antarmuka baris perintah: python -m kriminal_bbm <perintah> [opsi]."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import pandas as pd

from . import config


def _pdf_items(pdf_dir: Path, files: list[str] | None) -> list[Path]:
    paths = [Path(f) for f in files] if files else sorted(pdf_dir.glob("*.pdf"))
    return [p for p in paths if p.suffix.lower() == ".pdf"]


# ----------------------------------------------------------------------------- perintah

def cmd_check_site(a):
    from .directory import max_page, parse_listing, parse_overview, page_url
    from .web import PoliteSession

    s = PoliteSession(config.HTML_CACHE_DIR, delay=a.jeda)
    html = s.get_html(page_url(a.kategori_url, 1), use_cache=False)
    items = parse_listing(html, a.kategori_url)
    print(f"Daftar  : {a.kategori_url}")
    print(f"Entri di halaman 1: {len(items)}; halaman terakhir: {max_page(html, a.kategori_url)}")
    if not items:
        print("PERINGATAN: tidak ada tautan /direktori/putusan/ - URL kategori atau tata letak situs berubah.")
        return 1
    for it in items[:3]:
        print(f"  - {it['nomor'] or it['judul'][:70]} | putus {it['tanggal_putus']} | {it['url']}")
    ov = parse_overview(s.get_html(items[0]["url"], use_cache=False), items[0]["url"])
    print(f"\nOverview {items[0]['url']}")
    for k in ("nomor", "tingkat_proses", "klasifikasi", "lembaga_peradilan", "tanggal_dibacakan", "url_pdf"):
        print(f"  {k:20s}: {ov.get(k)}")
    print(f"  putusan terkait     : {len(ov['terkait'])} tautan")
    missing = [k for k in ("nomor", "tanggal_dibacakan", "lembaga_peradilan") if not ov.get(k)]
    if missing:
        print(f"PERINGATAN: kolom tidak terbaca: {missing}. Periksa LABEL_MAP di kriminal_bbm/directory.py.")
        return 1
    print("\nParser cocok dengan situs.")
    return 0


def cmd_crawl(a):
    from .crawler import Crawler
    from .web import PoliteSession

    s = PoliteSession(config.HTML_CACHE_DIR, delay=a.jeda, respect_robots=not a.abaikan_robots)
    c = Crawler(s, a.out, a.pdf_dir, config.TEXT_CACHE_DIR, years=(a.tahun_awal, a.tahun_akhir),
                follow_related=not a.tanpa_terkait, download_pdf=not a.tanpa_pdf)
    if a.html_dir:
        c.seed_html_files(sorted(Path(a.html_dir).glob("*.htm*")))
    if a.url_list:
        c.seed_urls([u for u in Path(a.url_list).read_text(encoding="utf-8").splitlines() if u.strip()])
    if a.kategori_url or not (a.html_dir or a.url_list):
        for u in a.kategori_url or [config.DEFAULT_CATEGORY_URL]:
            c.seed_listing(u, max_pages=a.maks_halaman, per_year=a.per_tahun)
    c.run(limit=a.limit)
    print(f"Selesai: {len(c.rows)} putusan, {len(c.edges)} tautan terkait, {s.requests_made} permintaan HTTP. "
          f"Hasil di {a.out}")


def cmd_pdf_text(a):
    from .pdftext import cached_text

    out = Path(a.out_dir)
    for p in _pdf_items(Path(a.pdf_dir), a.files):
        text = cached_text(p, config.TEXT_CACHE_DIR)
        (out / f"{p.stem}.txt").parent.mkdir(parents=True, exist_ok=True)
        (out / f"{p.stem}.txt").write_text(text, encoding="utf-8")
    print(f"Teks ditulis ke {out}")


def build_candidates(pdf_dir: Path, files: list[str] | None = None) -> pd.DataFrame:
    from .extract import extract_all
    from .pdftext import cached_text

    rows = []
    for p in _pdf_items(pdf_dir, files):
        try:
            r = extract_all(cached_text(p, config.TEXT_CACHE_DIR))
        except Exception as e:  # PDF rusak: catat dan lanjut
            r = {"galat": str(e)}
        r["file_pdf"] = f"pdf/{p.name}"
        rows.append(r)
    df = pd.DataFrame(rows)
    return df[["file_pdf"] + [c for c in df.columns if c != "file_pdf"]]


def _load_or_build_candidates(out_dir: Path, pdf_dir: Path, rebuild: bool = False) -> pd.DataFrame:
    path = out_dir / "kandidat_ekstraksi_pdf.csv"
    if path.exists() and not rebuild:
        return pd.read_csv(path)
    print(f"Mengekstrak kandidat dari PDF di {pdf_dir} ...")
    cand = build_candidates(pdf_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    cand.to_csv(path, index=False, encoding="utf-8-sig")
    return cand


def cmd_candidates(a):
    df = build_candidates(Path(a.pdf_dir), a.files)
    Path(a.out).parent.mkdir(parents=True, exist_ok=True)
    df.to_csv(a.out, index=False, encoding="utf-8-sig")
    print(f"{len(df)} PDF -> {a.out}")


def cmd_validate(a):
    from .validate import issues_frame, load_rekap, summary_counts, validate_rekap

    df = load_rekap(a.rekap)
    excluded = pd.read_csv(a.dikeluarkan) if Path(a.dikeluarkan).exists() else None
    cand = None
    if not a.tanpa_pdf:
        cand = _load_or_build_candidates(Path(a.out_dir), Path(a.rekap).parent / "pdf", rebuild=a.ulang_pdf)
    issues = issues_frame(validate_rekap(df, Path(a.rekap).parent, excluded, cand))
    out = Path(a.out_dir)
    out.mkdir(parents=True, exist_ok=True)
    issues.to_csv(out / "laporan_validasi.csv", index=False, encoding="utf-8-sig")
    stats = summary_counts(df)
    (out / "statistik_rekap.json").write_text(json.dumps(stats, indent=1, ensure_ascii=False), encoding="utf-8")
    counts = issues["tingkat"].value_counts().to_dict() if not issues.empty else {}
    lines = ["# Laporan validasi rekap", "",
             "Dibuat otomatis oleh `python -m kriminal_bbm validate`. Tingkat: galat (perlu diperbaiki), "
             "peringatan (perlu dibaca ulang), info (catatan).", "",
             f"Ringkasan: {counts.get('galat', 0)} galat, {counts.get('peringatan', 0)} peringatan, {counts.get('info', 0)} info.", ""]
    for tingkat in ("galat", "peringatan", "info"):
        sub = issues[issues["tingkat"] == tingkat]
        if sub.empty:
            continue
        lines += [f"## {tingkat.capitalize()} ({len(sub)})", "", "| no | nomor_putusan | kolom | pesan |", "|---|---|---|---|"]
        for _, r in sub.iterrows():
            no = "" if pd.isna(r["no"]) else int(r["no"])
            nomor = "" if pd.isna(r["nomor_putusan"]) else r["nomor_putusan"]
            lines.append(f"| {no} | {nomor} | {r['kolom']} | {str(r['pesan']).replace('|', '/')} |")
        lines.append("")
    (out / "laporan_validasi.md").write_text("\n".join(lines), encoding="utf-8")
    print("\n".join(lines[:6]))
    print(f"Laporan: {out / 'laporan_validasi.md'}")
    return 1 if counts.get("galat") else 0


def cmd_analyze(a):
    from .analysis import write_outputs
    from .validate import load_rekap

    # Kandidat teks PDF dipakai untuk provinsi perkara yang hanya punya putusan MA.
    cand = _load_or_build_candidates(Path(a.out_dir), Path(a.rekap).parent / "pdf")
    res = write_outputs(load_rekap(a.rekap), a.out_dir, cand)
    print(f"{len(res['decisions'])} putusan unik, {len(res['cases'])} perkara. Hasil di {a.out_dir}")


def cmd_curate(a):
    from .curate import apply_review, evidence_table, online_check, read_raw, write_raw
    from .validate import load_rekap

    out = Path(a.out_dir)
    out.mkdir(parents=True, exist_ok=True)
    rekap = load_rekap(a.rekap)
    ev = evidence_table(rekap, Path(a.rekap).parent, config.TEXT_CACHE_DIR)
    if a.online:
        from .web import PoliteSession
        s = PoliteSession(config.HTML_CACHE_DIR, delay=a.jeda)
        on = online_check(rekap, s, config.RAW_DIR / "pdf_kurasi", config.TEXT_CACHE_DIR)
        ev = ev.merge(on, on=["no", "nomor_putusan"], how="left")
    ev.to_csv(out / "kurasi_kata_kunci_bukti.csv", index=False, encoding="utf-8-sig")
    print(ev["dasar_bukti_kata_kunci"].value_counts().to_string())
    print(f"Tanpa kata kunci di sumber mana pun: {(ev['dasar_bukti_kata_kunci'] == 'tidak ada').sum()} baris")

    if not Path(a.tinjauan).exists():
        print(f"Berkas tinjauan {a.tinjauan} tidak ada; hanya bukti kata kunci yang ditulis.")
        return 0
    review = pd.read_csv(a.tinjauan)
    rv = review[review["dataset"] == "rekap"]
    print(f"Tinjauan: {rv['final'].value_counts().to_dict()} (rekap); "
          f"kandidat pemulihan dari daftar dikeluarkan: {int((review['final'].eq('yes') & review['dataset'].eq('dikeluarkan')).sum())}")
    if not a.terapkan:
        print("Gunakan --terapkan untuk mengeluarkan baris final=no dari rekap.")
        return 0
    kept, excluded_new, removed = apply_review(read_raw(a.rekap), read_raw(a.dikeluarkan), rv, a.tanggal)
    if removed.empty:
        print("Tidak ada baris yang dikeluarkan; berkas rekap tidak diubah.")
        return 0
    write_raw(kept, a.rekap)
    write_raw(excluded_new, a.dikeluarkan)
    print(f"{len(removed)} baris dikeluarkan: {', '.join(removed['nomor_putusan'])}. Rekap kini {len(kept)} baris.")
    return 0


def cmd_llm_code(a):
    try:
        import anthropic
    except ImportError:
        print("Paket anthropic belum terpasang: pip install anthropic", file=sys.stderr)
        return 2
    from .llm import code_files, to_rekap_frame
    from .pdftext import cached_text

    paths = _pdf_items(Path(a.pdf_dir), a.files)
    if a.limit:
        paths = paths[: a.limit]
    items = [(f"pdf/{p.name}", cached_text(p, config.TEXT_CACHE_DIR)) for p in paths]
    total_chars = sum(len(t) for _, t in items)
    print(f"{len(items)} dokumen, ~{total_chars // 3:,} token masukan per lintasan (perkiraan kasar). "
          f"Model {a.model}, effort {a.effort}{', dengan verifikasi' if a.verifikasi else ''}.")
    client = anthropic.Anthropic(max_retries=5)
    recs = code_files(client, items, a.out, model=a.model, effort=a.effort, verify=a.verifikasi)
    csv = Path(a.out).with_suffix(".csv")
    to_rekap_frame(recs).to_csv(csv, index=False, encoding="utf-8-sig")
    print(f"Hasil: {a.out} dan {csv} (tinjau sebelum digabung ke rekap)")


# ----------------------------------------------------------------------------- parser

def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="python -m kriminal_bbm", description="Pipeline data kriminalitas BBM (Direktori Putusan MA)")
    sub = p.add_subparsers(dest="cmd", required=True)

    s = sub.add_parser("check-site", help="uji cepat parser terhadap situs (1 halaman daftar + 1 overview)")
    s.add_argument("--kategori-url", default=config.DEFAULT_CATEGORY_URL)
    s.add_argument("--jeda", type=float, default=3.0)
    s.set_defaults(func=cmd_check_site)

    s = sub.add_parser("crawl", help="telusuri direktori: daftar -> overview -> rantai perkara -> PDF")
    s.add_argument("--kategori-url", action="append", help="URL daftar klasifikasi (boleh berulang)")
    s.add_argument("--html-dir", help="folder HTML hasil pencarian yang disimpan dari peramban")
    s.add_argument("--url-list", help="berkas teks berisi URL overview putusan, satu per baris")
    s.add_argument("--tahun-awal", type=int, default=config.TAHUN_AWAL)
    s.add_argument("--tahun-akhir", type=int, default=config.TAHUN_AKHIR)
    s.add_argument("--per-tahun", action="store_true", help="pakai filter tahun putus situs (lebih sedikit halaman)")
    s.add_argument("--maks-halaman", type=int, help="batasi jumlah halaman daftar (uji coba)")
    s.add_argument("--limit", type=int, help="berhenti setelah N overview (uji coba)")
    s.add_argument("--tanpa-terkait", action="store_true", help="jangan ikuti tautan Putusan Terkait")
    s.add_argument("--tanpa-pdf", action="store_true", help="jangan unduh PDF")
    s.add_argument("--jeda", type=float, default=3.0, help="detik antarpermintaan (default 3)")
    s.add_argument("--abaikan-robots", action="store_true", help=argparse.SUPPRESS)
    s.add_argument("--out", default=str(config.RAW_DIR))
    s.add_argument("--pdf-dir", default=str(config.RAW_DIR / "pdf"))
    s.set_defaults(func=cmd_crawl)

    s = sub.add_parser("pdf-text", help="ekstrak teks bersih dari PDF putusan")
    s.add_argument("files", nargs="*")
    s.add_argument("--pdf-dir", default=str(config.PDF_DIR))
    s.add_argument("--out-dir", default=str(config.CACHE_DIR / "teks_bersih"))
    s.set_defaults(func=cmd_pdf_text)

    s = sub.add_parser("candidates", help="kandidat nilai kolom dari teks PDF (regex)")
    s.add_argument("files", nargs="*")
    s.add_argument("--pdf-dir", default=str(config.PDF_DIR))
    s.add_argument("--out", default=str(config.OUTPUT_DIR / "kandidat_ekstraksi_pdf.csv"))
    s.set_defaults(func=cmd_candidates)

    s = sub.add_parser("validate", help="periksa konsistensi rekap (+ cocokkan dengan teks PDF)")
    s.add_argument("--rekap", default=str(config.REKAP_CSV))
    s.add_argument("--dikeluarkan", default=str(config.EXCLUDED_CSV))
    s.add_argument("--out-dir", default=str(config.OUTPUT_DIR))
    s.add_argument("--tanpa-pdf", action="store_true", help="lewati pencocokan dengan teks PDF")
    s.add_argument("--ulang-pdf", action="store_true", help="hitung ulang kandidat PDF walau sudah ada")
    s.set_defaults(func=cmd_validate)

    s = sub.add_parser("analyze", help="dataset tingkat perkara + tabel ringkasan")
    s.add_argument("--rekap", default=str(config.REKAP_CSV))
    s.add_argument("--out-dir", default=str(config.OUTPUT_DIR))
    s.set_defaults(func=cmd_analyze)

    s = sub.add_parser("curate", help="kurasi kata kunci BBM/solar/biosolar/minyak tanah/pertalite")
    s.add_argument("--rekap", default=str(config.REKAP_CSV))
    s.add_argument("--dikeluarkan", default=str(config.EXCLUDED_CSV))
    s.add_argument("--tinjauan", default=str(config.DATA_DIR / "kurasi_kata_kunci_tinjauan.csv"),
                   help="berkas keputusan tinjauan (kolom dataset, no, final, alasan)")
    s.add_argument("--online", action="store_true", help="cek ulang overview + PDF di situs MA lewat url_putusan")
    s.add_argument("--jeda", type=float, default=3.0)
    s.add_argument("--terapkan", action="store_true", help="keluarkan baris final=no dari rekap")
    s.add_argument("--tanggal", default="7 Oktober 2026", help="tanggal kurasi untuk kolom alasan")
    s.add_argument("--out-dir", default=str(config.OUTPUT_DIR))
    s.set_defaults(func=cmd_curate)

    s = sub.add_parser("llm-code", help="(opsional) kodekan tujuh kolom dengan Claude API")
    s.add_argument("files", nargs="*")
    s.add_argument("--pdf-dir", default=str(config.RAW_DIR / "pdf"))
    s.add_argument("--model", default="claude-opus-5-5")
    s.add_argument("--effort", default="high", choices=["low", "medium", "high", "xhigh", "max"])
    s.add_argument("--verifikasi", action="store_true", help="lintasan kedua oleh verifikator independen")
    s.add_argument("--limit", type=int)
    s.add_argument("--out", default=str(config.RAW_DIR / "hasil_llm.jsonl"))
    s.set_defaults(func=cmd_llm_code)
    return p


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    return int(args.func(args) or 0)
