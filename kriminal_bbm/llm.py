"""(Opsional) Pengodean tujuh kolom utama dengan Claude API.

Mereplikasi langkah metodologi rekap: satu "pengode" membaca seluruh teks putusan dan
mengisi kolom menurut protokol, lalu (opsi --verifikasi) "verifikator" independen
memeriksa ulang setiap nilai terhadap teks. Kutipan bukti dicek otomatis apakah benar
ada di teks. Hasil tetap harus ditinjau manusia sebelum digabung ke rekap.

Membutuhkan paket `anthropic` dan kredensial (ANTHROPIC_API_KEY atau `ant auth login`).
"""

from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path

PROMPT_VERSION = "2026-10-07"
DEFAULT_MODEL = "claude-opus-5-5"

PROTOKOL = """Anda adalah asisten riset hukum-ekonomi untuk kajian kriminalitas bahan bakar minyak (BBM)
di Indonesia. Anda menerima teks lengkap SATU putusan pengadilan dari Direktori Putusan Mahkamah Agung
dan mengisi variabel berikut sesuai protokol. Isi hanya dari teks putusan; jangan menebak.
Bila nilai tidak ditemukan, tulis null (atau "NA" untuk kolom kategori).

DEFINISI VARIABEL
1. tahun_putusan: tahun putusan INI dibacakan (bukan putusan tingkat sebelumnya).
2. tahun_kejadian: tahun perbuatan pidana menurut dakwaan/fakta hukum; "2020-2021" bila lintas tahun.
3. tingkat_persidangan: PN (tingkat pertama), PT (banding), MA (kasasi/PK), atau Pengadilan Militer.
4. hasil_putusan: status terdakwa SETELAH putusan ini: "Bersalah" atau "Tidak bersalah" (bebas/lepas).
   - Pada MA: kasasi terdakwa ditolak = Bersalah (pemidanaan tetap berlaku). Kasasi penuntut umum ditolak
     atas putusan bebas/lepas = Tidak bersalah. Bila putusan sebelumnya tidak diketahui dari teks, tulis "NA".
   - Pada PT: "menguatkan" mengikuti putusan PN yang dikuatkan (lihat teks); "membatalkan ... mengadili
     sendiri" mengikuti amar baru.
   - Bebas dari dakwaan primair tetapi terbukti dakwaan subsidair/alternatif = Bersalah.
   Bila ada beberapa terdakwa dengan hasil berbeda, jelaskan di rincian_amar dan pilih hasil mayoritas.
5. barang_bbm: jenis bahan bakar objek perkara dan status subsidinya, mis. "Solar/Biosolar (subsidi)",
   "Pertalite", "Premium", "Minyak tanah (subsidi)", "Solar (non-subsidi/industri)",
   "Solar (status subsidi tidak disebut)". Pisahkan beberapa jenis dengan "; ".
   relevan_bbm: "Ya" = objek BBM; "Sebagian" = minyak mentah/kondensat/pengeboran atau penyulingan ilegal;
   "Tidak" = LPG/gas atau bukan BBM; "NA" = tidak jelas.
6. nilai_kerugian_uang (angka rupiah tanpa pemisah ribuan) dengan urutan prioritas dasar_kode:
   (a) kerugian negara yang disebut putusan;
   (b) selisih harga subsidi x volume bila kedua harga disebut putusan;
   (c) nilai BBM yang disebut putusan (mis. hasil lelang barang bukti, nilai transaksi);
   (d) volume x harga per liter yang disebut putusan (hitung sendiri, tunjukkan rumusnya);
   (e) tidak ada -> null.
   Denda dan biaya perkara BUKAN kerugian. dasar_nilai_uang menjelaskan dasar dan rumusnya.
7. nilai_kerugian_volume: total volume BBM objek perkara (angka) + satuan_volume ("liter", "ton",
   atau "kiloliter") + keterangan_volume (rincian penjumlahan; kapasitas wadah kosong tidak dihitung;
   tandai angka "sekitar/±").

KOLOM PENDUKUNG
- nomor_putusan, pengadilan (mis. "PN PELAIHARI", "PT BANJARMASIN", "MAHKAMAH AGUNG"),
  tingkat_proses ("Pertama", "Banding", "Kasasi", "Peninjauan Kembali"), tanggal_putusan ("5 Februari 2020").
- rincian_amar: ringkasan amar 1-3 kalimat (delik yang terbukti, pidana penjara/denda, barang bukti BBM).
- pasal_uu_migas: pasal UU 22/2001 yang menjadi dasar (mis. "55", "53 huruf b"), termasuk perubahan
  UU 6/2023 bila disebut.
- bukti_kutipan: 2-6 kutipan PERSIS dari teks (salin kata demi kata, boleh dipotong dengan " ... ")
  yang mendukung tahun kejadian, jenis BBM, volume, nilai uang, dan hasil putusan.
- catatan: modus operandi singkat dan hal yang perlu dicek manusia.
JANGAN mencantumkan nama terdakwa, saksi, atau data pribadi lain di kolom mana pun (gunakan "terdakwa")."""

VERIFIKASI = """Anda adalah VERIFIKATOR independen. Di bawah ini ada teks putusan dan hasil pengodean pihak lain.
Periksa setiap nilai terhadap teks dan protokol. Perbaiki yang salah, lengkapi yang kosong bila teks
mendukung, dan tulis setiap perubahan di daftar koreksi_verifikator (kolom: nilai lama -> nilai baru, alasan).
Bila semua benar, kembalikan nilai yang sama dengan koreksi_verifikator kosong."""


def _nullable(t: dict) -> dict:
    return {"anyOf": [t, {"type": "null"}]}


SCHEMA: dict = {
    "type": "object",
    "properties": {
        "nomor_putusan": {"type": "string"},
        "pengadilan": {"type": "string"},
        "tingkat_persidangan": {"type": "string", "enum": ["PN", "PT", "MA", "Pengadilan Militer"]},
        "tingkat_proses": {"type": "string", "enum": ["Pertama", "Banding", "Kasasi", "Peninjauan Kembali"]},
        "tanggal_putusan": {"type": "string"},
        "tahun_putusan": {"type": "integer"},
        "tahun_kejadian": _nullable({"type": "string"}),
        "hasil_putusan": {"type": "string", "enum": ["Bersalah", "Tidak bersalah", "NA"]},
        "rincian_amar": {"type": "string"},
        "barang_bbm": {"type": "string"},
        "relevan_bbm": {"type": "string", "enum": ["Ya", "Sebagian", "Tidak", "NA"]},
        "nilai_kerugian_uang": _nullable({"type": "number"}),
        "dasar_kode": {"type": "string", "enum": ["a", "b", "c", "d", "e"]},
        "dasar_nilai_uang": _nullable({"type": "string"}),
        "nilai_kerugian_volume": _nullable({"type": "number"}),
        "satuan_volume": _nullable({"type": "string", "enum": ["liter", "ton", "kiloliter"]}),
        "keterangan_volume": _nullable({"type": "string"}),
        "pasal_uu_migas": {"type": "array", "items": {"type": "string"}},
        "bukti_kutipan": {"type": "array", "items": {"type": "string"}},
        "catatan": {"type": "string"},
    },
    "required": [
        "nomor_putusan", "pengadilan", "tingkat_persidangan", "tingkat_proses", "tanggal_putusan",
        "tahun_putusan", "tahun_kejadian", "hasil_putusan", "rincian_amar", "barang_bbm", "relevan_bbm",
        "nilai_kerugian_uang", "dasar_kode", "dasar_nilai_uang", "nilai_kerugian_volume", "satuan_volume",
        "keterangan_volume", "pasal_uu_migas", "bukti_kutipan", "catatan",
    ],
    "additionalProperties": False,
}

SCHEMA_VERIFIKASI: dict = {
    **SCHEMA,
    "properties": {**SCHEMA["properties"], "koreksi_verifikator": {"type": "array", "items": {"type": "string"}}},
    "required": [*SCHEMA["required"], "koreksi_verifikator"],
}


class CodingError(RuntimeError):
    pass


def _squash(s: str) -> str:
    return re.sub(r"\W+", "", s.lower())


def check_quotes(quotes: list[str], text: str) -> list[str]:
    """Kutipan yang TIDAK ditemukan di teks (spasi/tanda baca diabaikan; ' ... ' memisah potongan)."""
    hay = _squash(text)
    missing = []
    for q in quotes:
        parts = [p for p in re.split(r"\.\.\.|…|\|", q) if len(_squash(p)) >= 12]
        if parts and not all(_squash(p) in hay for p in parts):
            missing.append(q)
    return missing


def _api_errors() -> tuple[type[BaseException], ...]:
    try:
        import anthropic
    except ImportError:
        return ()
    return (anthropic.APIError,)


def _call(client, model: str, effort: str, system: str, user: str, schema: dict) -> tuple[dict, dict]:
    try:
        resp = client.beta.messages.create(
            model=model,
            max_tokens=16000,
            system=[{"type": "text", "text": system, "cache_control": {"type": "ephemeral"}}],
            messages=[{"role": "user", "content": user}],
            output_config={"effort": effort, "format": {"type": "json_schema", "schema": schema}},
            # Bila model utama menolak (safety classifier), API mengulang di model cadangan yang direkomendasikan.
            betas=["server-side-fallback-2026-07-01"],
            fallbacks="default",
        )
    except _api_errors() as e:
        # SDK sudah mengulang 429/5xx/koneksi (max_retries); yang sampai ke sini dicatat lalu dilewati.
        raise CodingError(f"{type(e).__name__}: {getattr(e, 'message', e)}") from e

    if resp.stop_reason == "refusal":
        details = getattr(resp, "stop_details", None)
        raise CodingError(f"model menolak permintaan ({getattr(details, 'category', None)})")
    if resp.stop_reason == "max_tokens":
        raise CodingError("keluaran terpotong (max_tokens)")
    text = next((b.text for b in resp.content if getattr(b, "type", None) == "text"), None)
    if not text:
        raise CodingError("respons tanpa teks")
    usage = getattr(resp, "usage", None)
    meta = {
        "model_dipakai": getattr(resp, "model", model),
        "input_tokens": getattr(usage, "input_tokens", None),
        "output_tokens": getattr(usage, "output_tokens", None),
        "cache_read_input_tokens": getattr(usage, "cache_read_input_tokens", None),
    }
    return json.loads(text), meta


def code_document(client, text: str, *, model: str = DEFAULT_MODEL, effort: str = "high",
                  verify: bool = False, file_label: str = "") -> dict:
    """Kodekan satu putusan. Mengembalikan dict kolom + metadata pengodean."""
    user = f"Berkas: {file_label}\n\n<teks_putusan>\n{text}\n</teks_putusan>"
    result, meta = _call(client, model, effort, PROTOKOL, user, SCHEMA)
    if verify:
        user_v = (f"{user}\n\n<hasil_pengodean>\n{json.dumps(result, ensure_ascii=False, indent=1)}\n"
                  "</hasil_pengodean>")
        result, meta_v = _call(client, model, effort, PROTOKOL + "\n\n" + VERIFIKASI, user_v, SCHEMA_VERIFIKASI)
        meta = {**meta, **{f"verifikasi_{k}": v for k, v in meta_v.items()}}
    result["kutipan_tidak_ditemukan"] = check_quotes(result.get("bukti_kutipan", []), text)
    result["_meta"] = {**meta, "prompt_version": PROMPT_VERSION, "effort": effort, "verifikasi": verify}
    return result


def doc_key(text: str, model: str, verify: bool) -> str:
    return hashlib.sha1(f"{PROMPT_VERSION}|{model}|{verify}|{text}".encode()).hexdigest()[:16]


def code_files(client, items: list[tuple[str, str]], out_jsonl: str | Path, *, model: str = DEFAULT_MODEL,
               effort: str = "high", verify: bool = False, log=print) -> list[dict]:
    """items: daftar (file_pdf, teks). Hasil ditambahkan ke JSONL; dokumen yang sudah dikodekan dilewati."""
    out_jsonl = Path(out_jsonl)
    done: dict[str, dict] = {}
    if out_jsonl.exists():
        for line in out_jsonl.read_text(encoding="utf-8").splitlines():
            if line.strip():
                rec = json.loads(line)
                done[rec["_key"]] = rec
    results = []
    with open(out_jsonl, "a", encoding="utf-8") as f:
        for file_pdf, text in items:
            key = doc_key(text, model, verify)
            if key in done:
                results.append(done[key])
                continue
            try:
                rec = code_document(client, text, model=model, effort=effort, verify=verify, file_label=file_pdf)
            except CodingError as e:
                log(f"  {file_pdf}: GAGAL - {e}")
                rec = {"_error": str(e)}
            rec["_key"], rec["file_pdf"] = key, file_pdf
            f.write(json.dumps(rec, ensure_ascii=False) + "\n")
            f.flush()
            results.append(rec)
            miss = len(rec.get("kutipan_tidak_ditemukan", []))
            log(f"  {file_pdf}: {rec.get('hasil_putusan', '-')}, {rec.get('barang_bbm', '-')}"
                + (f" [{miss} kutipan tidak ditemukan di teks]" if miss else ""))
    return results


def to_rekap_frame(records: list[dict]):
    """Konversi hasil JSONL ke kolom rekap (untuk ditinjau sebelum digabung)."""
    import pandas as pd

    rows = []
    for r in records:
        if "_error" in r:
            rows.append({"file_pdf": r.get("file_pdf"), "catatan": f"GAGAL dikodekan: {r['_error']}"})
            continue
        row = {k: r.get(k) for k in SCHEMA["properties"] if k not in {"pasal_uu_migas", "bukti_kutipan", "dasar_kode"}}
        row["mata_uang"] = "IDR" if r.get("nilai_kerugian_uang") is not None else None
        if r.get("dasar_nilai_uang"):
            row["dasar_nilai_uang"] = f"({r.get('dasar_kode')}) {r['dasar_nilai_uang']}"
        row["bukti_kutipan"] = " | ".join(r.get("bukti_kutipan", []))
        pasal = ", ".join(r.get("pasal_uu_migas", []))
        extra = [f"Pasal UU 22/2001: {pasal}" if pasal else "",
                 "; ".join(r.get("koreksi_verifikator", []) or []) and "Koreksi verifikator: " + "; ".join(r["koreksi_verifikator"]),
                 f"{len(r['kutipan_tidak_ditemukan'])} kutipan tidak ditemukan di teks" if r.get("kutipan_tidak_ditemukan") else ""]
        row["catatan"] = " ".join(x for x in [r.get("catatan", "")] + extra if x)
        row["file_pdf"] = r.get("file_pdf")
        row["sumber_data"] = f"PDF putusan (koding {r['_meta'].get('model_dipakai')}" + (", diverifikasi)" if r["_meta"].get("verifikasi") else ")")
        rows.append(row)
    return pd.DataFrame(rows)
