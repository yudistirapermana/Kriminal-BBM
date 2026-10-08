# Kriminalitas BBM: data putusan Mahkamah Agung 2020–2026

Data dan kode untuk kajian kriminalitas bahan bakar minyak (BBM) dari
[Direktori Putusan Mahkamah Agung](https://putusan3.mahkamahagung.go.id) (Kajian UGM – PT SICPA).
Satu baris rekap = satu putusan (PN, PT, MA, atau Pengadilan Militer) beserta tujuh variabel utama:
tahun putusan, tahun kejadian, tingkat persidangan, hasil putusan, jenis BBM, nilai kerugian (uang) dan volume BBM.

## Isi repositori

```
Data Kriminal BBM/
  rekap_putusan_kriminalitas_BBM_2020-2026.csv   rekap utama (166 putusan, 107 rantai perkara)
  putusan_dikeluarkan_tidak_relevan.csv          35 putusan yang dikeluarkan (bukan BBM) + alasannya
  kurasi_kata_kunci_tinjauan.csv                  hasil kurasi kata kunci per putusan (lihat laporan_kurasi_kata_kunci.md)
  BACA_SAYA_metodologi.txt                        cakupan, definisi kolom, keterbatasan
  pdf/                                            87 PDF putusan
  hasil_olahan/                                   keluaran kode (dibuat ulang otomatis, jangan disunting)
    rekap_perkara_unik.csv                        1 baris = 1 perkara (rantai PN→PT→MA), siap dianalisis
    putusan_bersih_dengan_variabel.csv            rekap tanpa entri ganda + provinsi, pasal, dummy BBM
    ringkasan_statistik.md, ringkasan_*.csv       tabel ringkasan
    laporan_validasi.md / .csv                    hasil pemeriksaan konsistensi rekap
    kandidat_ekstraksi_pdf.csv                    nilai kandidat dari teks PDF (regex) untuk pengecekan
kriminal_bbm/                                     paket Python (penelusuran, ekstraksi, validasi, analisis)
tests/                                            uji otomatis (pytest)
```

## Skrip R: scraping langsung dari situs MA

`R/scrape_kriminalitas_bbm.R` adalah skrip R mandiri (satu berkas) untuk mencari putusan BBM di
https://putusan3.mahkamahagung.go.id. Alurnya:

1. kumpulkan URL putusan dari pencarian kata kunci (BBM, biosolar, solar, pertalite, minyak tanah, premium, ...) per
   tahun 2020–2026, dari daftar klasifikasi Migas, dari halaman hasil pencarian yang disimpan, atau dari daftar URL;
2. buka halaman overview tiap putusan;
3. unduh PDF di bagian Lampiran bila ada, dan bila tidak ada pakai teks overview;
4. tulis CSV.

```r
install.packages(c("httr", "rvest", "xml2", "pdftools", "stringr", "dplyr", "readr", "purrr"))
```

```bash
Rscript R/scrape_kriminalitas_bbm.R --mode=cek            # uji cepat parser terhadap situs
Rscript R/scrape_kriminalitas_bbm.R                       # pencarian kata kunci + klasifikasi Migas, 2020-2026
Rscript R/scrape_kriminalitas_bbm.R --mode=url --url=https://putusan3.mahkamahagung.go.id/direktori/putusan/1b6b7ad93106cdda7a17bcacf6917d0c.html
Rscript R/scrape_kriminalitas_bbm.R --mode=html --html-dir=hasil_pencarian_tersimpan   # bila pencarian meminta CAPTCHA
Rscript R/scrape_kriminalitas_bbm.R --mode=pdf-lokal --pdf-dir="Data Kriminal BBM/pdf"  # dari PDF yang sudah ada
```

**Keluaran** ada di `hasil_scrape_R/`:

- `rekap_kriminalitas_BBM_MA_2020_2026.csv`, berisi putusan relevan BBM dengan kolom:
  1. `tahun_putusan`
  2. `tahun_kejadian`
  3. `tingkat_persidangan` (PN/PT/MA)
  4. `hasil_putusan` (Bersalah/Tidak bersalah)
  5. `lokasi_kejadian` (dari teks dakwaan; bila tidak ada, "Wilayah hukum PN ...")
  6. `barang_bbm`
  7. `nilai_kerugian_uang` + `mata_uang`
  8. `nilai_kerugian_volume` + `satuan_volume`

  Kolom pendukung: nomor, pengadilan, provinsi, dan kolom `dasar_*` yang berisi potongan teks sebagai jejak audit. Nilai
  yang tidak ditemukan ditulis `NA`.
- `semua_putusan_diperiksa.csv`, `daftar_url.csv`, `log_gagal.csv`, folder `pdf/` dan `cache_html/` (penelusuran bisa
  dilanjutkan).

Sopan terhadap situs: jeda 3 detik, retry, cache, dan robots.txt dipatuhi. Bila situs meminta CAPTCHA, skrip berhenti
(tidak menembusnya) dan menyimpan antrean yang tersisa. Uji: `Rscript -e 'testthat::test_file("tests/R/test_scrape_kriminalitas_bbm.R")'`.

**Tolok ukur ekstraksi otomatis** dibandingkan dengan rekap manual, pada 68 PDF yang dirujuk rekap
(`tests/R/test_scrape_kriminalitas_bbm.R`):

| Kolom | Terisi | Sama dengan rekap manual |
|---|---|---|
| tahun_putusan | 68/68 | 100% |
| tingkat_persidangan | 67/68 | 100% |
| hasil_putusan | 66/68 | 100% |
| barang_bbm (jenis utama) | 68/68 | 98,5% |
| tahun_kejadian | 46/68 | 91,3% |
| nilai_kerugian_volume (±1%) | 61/68 | 70,5% |

Volume dan nilai uang paling sering berbeda dari pengodean manual: barang bukti sering ditulis sebagai jumlah wadah ×
ukuran, atau ada beberapa angka (dipesan vs. disita). Periksa kolom `dasar_volume` dan `dasar_nilai_uang` sebelum
memakai angka itu untuk analisis.

## Instalasi

Python 3.10 atau lebih baru.

```bash
pip install -r requirements.txt
pip install anthropic        # hanya bila memakai perintah llm-code
```

## Perintah

Semua perintah dijalankan dari akar repositori: `python -m kriminal_bbm <perintah> --help` untuk opsi lengkap.

| Perintah | Fungsi |
|---|---|
| `validate` | Memeriksa rekap: format dan konsistensi kolom, tahun vs tanggal, nilai/satuan, berkas PDF, duplikat, urutan tanggal dalam rantai, lalu mencocokkan isi rekap dengan teks PDF (nomor, tahun, hasil, jenis BBM, volume). Keluaran: `hasil_olahan/laporan_validasi.md`. Kode keluar 1 bila ada galat. |
| `analyze` | Membuat dataset tingkat perkara dan tabel ringkasan di `hasil_olahan/`. |
| `candidates` | Mengekstrak kandidat nilai kolom dari teks PDF (tanggal, amar, hasil, jenis BBM, volume, rupiah, pasal, pengadilan asal). |
| `pdf-text` | Menulis teks bersih PDF (tanpa watermark, kop dan disclaimer) ke `cache/teks_bersih/`. |
| `check-site` | Uji cepat parser terhadap situs MA: 1 halaman daftar + 1 halaman overview. Jalankan ini sebelum `crawl`. |
| `crawl` | Menelusuri direktori: daftar klasifikasi → overview → "Putusan Terkait" → unduh PDF. |
| `curate` | Kurasi kata kunci BBM/solar/biosolar/minyak tanah/pertalite: bukti kata kunci per putusan dari teks PDF, kutipan verbatim, PDF rantai, atau isian tim (`--online` mengecek ulang ke situs MA). `--terapkan` memindahkan baris berstatus `final = no` di `kurasi_kata_kunci_tinjauan.csv` ke daftar dikeluarkan. Hasil kurasi 7 Oktober 2026: 166/166 dipertahankan, lihat `Data Kriminal BBM/laporan_kurasi_kata_kunci.md`. |
| `llm-code` | (Opsional) Mengodekan tujuh kolom dari PDF baru dengan Claude API, memakai protokol yang sama dengan rekap. |

### Memperbarui hasil olahan setelah rekap disunting

```bash
python -m kriminal_bbm validate      # periksa dulu; perbaiki galat/peringatan yang relevan
python -m kriminal_bbm analyze
```

### Menambah data baru dari situs MA

```bash
python -m kriminal_bbm check-site
python -m kriminal_bbm crawl --per-tahun                     # klasifikasi Migas 2020–2026 + rantai perkaranya
python -m kriminal_bbm crawl --kategori-url <URL daftar>     # klasifikasi lain, mis. Pidana Khusus Lain-lain
python -m kriminal_bbm crawl --html-dir hasil_pencarian/     # halaman hasil pencarian yang disimpan dari peramban
python -m kriminal_bbm crawl --url-list daftar_url.txt       # URL overview tertentu
```

Hasil penelusuran ada di `data_mentah/` (tidak masuk git karena bisa memuat nama terdakwa):
`putusan_overview.csv` (metadata semua putusan yang dibuka), `putusan_terkait.csv` (tautan antarputusan),
`draf_rekap_untuk_dikoding.csv` (format kolom rekap, tujuh kolom utama masih kosong) dan `pdf/`.
Tujuh kolom lalu diisi manual atau dengan:

```bash
python -m kriminal_bbm llm-code --pdf-dir data_mentah/pdf --verifikasi --limit 5   # uji 5 berkas dulu
```

`llm-code` memakai `claude-opus-5-5` (ubah dengan `--model`), keluaran JSON terstruktur, kutipan bukti
dicek otomatis ke teks, dan dapat dilanjutkan bila terputus. Kredensial dibaca dari `ANTHROPIC_API_KEY` atau
`ant auth login`. Permintaan memakai fallback sisi server (`fallbacks="default"`): bila model utama menolak,
API mengulang di model cadangan yang direkomendasikan. Hasilnya (`data_mentah/hasil_llm.csv`) harus ditinjau manusia
sebelum digabung ke rekap.

## Catatan pemakaian data

- **Sampel, bukan populasi.** Rekap dibangun dari klasifikasi Migas + rantai perkaranya + tabulasi tim. Sebagian besar
  perkara BBM di situs MA diklasifikasikan di luar Migas, dan pencarian kata kunci memerlukan CAPTCHA.
  Perbedaan jumlah antartahun mencerminkan jalur penemuan (hampir semua putusan 2026 berasal dari tabulasi tim).
- **Unit analisis.** Satu perkara bisa muncul sebagai PN, PT dan MA. Gunakan `rekap_perkara_unik.csv` untuk
  menghitung perkara atau menjumlah volume.
- **Berkas terpisah (splitsing).** Beberapa rantai berasal dari satu kejadian dengan terdakwa berbeda (mis. kapal
  KM Cahaya Budi Makmur di PN Sibolga, tiga rantai × 60.000 liter). Kolom `kelompok_kejadian` menandainya secara
  heuristik. Untuk total volume pakai `volume_liter_kelompok` (418.827 liter), bukan `volume_liter` (590.628 liter).
- **Nilai uang** umumnya nilai BBM barang bukti, bukan kerugian negara; baca `dasar_nilai_uang`.

## Etika dan teknis penelusuran

- Jeda default 3 detik (+ acak) antarpermintaan, retry dengan backoff, dan cache HTML di `cache/`
  sehingga penelusuran bisa dilanjutkan tanpa membebani situs.
- `robots.txt` dipatuhi. Bila situs meminta CAPTCHA, penelusuran berhenti dengan pesan; CAPTCHA tidak dicoba
  ditembus. Untuk pencarian kata kunci, buka situs di peramban, simpan halaman hasil (Ctrl+S), lalu pakai `--html-dir`.
- Parser tidak bergantung pada kelas CSS tertentu (tautan dikenali dari pola URL, metadata dari tabel label–nilai).
  Bila tata letak situs berubah, `check-site` akan memberi tahu kolom mana yang tidak terbaca.

## Pengujian

```bash
python -m pytest
```

Uji mencakup parser HTML (dengan contoh halaman di `tests/fixtures/`), penelusuran rantai perkara dengan sesi tiruan,
deteksi CAPTCHA, ekstraksi teks PDF asli, aturan kandidat (hasil putusan, volume, rupiah, pasal), validasi rekap,
dataset tingkat perkara, dan modul LLM dengan klien tiruan.
