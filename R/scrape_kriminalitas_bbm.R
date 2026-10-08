#!/usr/bin/env Rscript
# =============================================================================
#  Scraper data kriminalitas BBM - Direktori Putusan Mahkamah Agung RI
#  (https://putusan3.mahkamahagung.go.id)          Kajian UGM - PT SICPA
# =============================================================================
#
#  ALUR
#   1. Kumpulkan URL putusan dari:
#        a. pencarian kata kunci di situs (BBM, biosolar, solar, pertalite, minyak tanah, ...),
#           per tahun putus 2020-2026;
#        b. daftar klasifikasi direktori (default: Pidana Khusus > Migas), per tahun;
#        c. halaman hasil pencarian yang disimpan dari peramban (bila situs meminta CAPTCHA);
#        d. daftar URL putusan (berkas teks) atau satu URL lewat --url=.
#   2. Buka halaman overview tiap putusan (mis. .../direktori/putusan/1b6b7ad93106cdda7a17bcacf6917d0c.html),
#      baca metadata, lalu unduh PDF di bagian "Lampiran" bila ada.
#   3. Ambil teks PDF (watermark diagonal dibuang); bila tidak ada PDF, pakai teks overview
#      (Catatan Amar, Kata Kunci, Abstrak).
#   4. Isi kolom rekap dengan aturan teks (regex):
#        1 tahun_putusan        5 lokasi_kejadian
#        2 tahun_kejadian       6 barang_bbm
#        3 tingkat_persidangan  7 nilai_kerugian_uang + mata_uang
#        4 hasil_putusan        8 nilai_kerugian_volume + satuan_volume
#      Nilai yang tidak ditemukan ditulis NA. Kolom dasar_* menyimpan alasan/potongan teks
#      sebagai jejak audit: hasil otomatis WAJIB diperiksa ulang sebelum dipakai untuk analisis.
#   5. Tulis CSV (UTF-8, bisa dibuka di Excel):
#        <keluaran>/rekap_kriminalitas_BBM_MA_2020_2026.csv   putusan relevan BBM, 2020-2026
#        <keluaran>/semua_putusan_diperiksa.csv              semua putusan yang dibuka (audit)
#        <keluaran>/daftar_url.csv, log_gagal.csv, pdf/, cache_html/
#
#  CARA MENJALANKAN (dari folder repositori)
#   Rscript R/scrape_kriminalitas_bbm.R                         # pencarian + kategori Migas, 2020-2026
#   Rscript R/scrape_kriminalitas_bbm.R --mode=cek              # uji cepat: 1 halaman + 1 putusan
#   Rscript R/scrape_kriminalitas_bbm.R --mode=kategori --tahun=2023:2024      # juga 2023-2024 atau 2021,2023
#   Rscript R/scrape_kriminalitas_bbm.R --mode=html --html-dir=hasil_pencarian_tersimpan
#   Rscript R/scrape_kriminalitas_bbm.R --mode=url --url=https://putusan3.mahkamahagung.go.id/direktori/putusan/1b6b7ad93106cdda7a17bcacf6917d0c.html
#   Rscript R/scrape_kriminalitas_bbm.R --mode=pdf-lokal --pdf-dir="Data Kriminal BBM/pdf"
#   Rscript R/scrape_kriminalitas_bbm.R --mode=url --url-list=daftar_url.txt     # satu URL per baris
#  Di RStudio: source("R/scrape_kriminalitas_bbm.R") lalu main(c("--mode=cek")) dst.
#  Bila dihentikan (CAPTCHA/blokir), jalankan ulang perintah yang sama: putusan yang sudah diperiksa dilewati
#  dan antrean_tersisa.txt dilanjutkan.
#  Opsi lain: --keluaran=folder  --jeda=3  --maks-halaman=5  --tanpa-terkait  --kata-kunci="solar,pertalite"
#
#  ETIKA DAN BATASAN
#   - Jeda default 3 detik (+acak) antarpermintaan, cache HTML di disk (bisa dilanjutkan), robots.txt dipatuhi.
#   - Bila situs menampilkan CAPTCHA ("Saya bukan robot"), skrip BERHENTI pada jalur itu; CAPTCHA tidak
#     dicoba ditembus. Untuk pencarian kata kunci, buka situs di peramban, selesaikan CAPTCHA, simpan tiap
#     halaman hasil (Ctrl+S, "Web page, HTML only") ke satu folder, lalu jalankan --mode=html.
#   - Nama terdakwa tidak ditulis ke CSV.
#
#  PAKET: httr, rvest, xml2, pdftools, stringr, dplyr, readr, purrr
#   install.packages(c("httr","rvest","xml2","pdftools","stringr","dplyr","readr","purrr"))
# =============================================================================

suppressPackageStartupMessages({
  library(httr)
  library(rvest)
  library(xml2)
  library(pdftools)
  library(stringr)
  library(dplyr)
  library(readr)
  library(purrr)
})

# -----------------------------------------------------------------------------
# 0. KONFIGURASI (ubah di sini atau lewat argumen baris perintah)
# -----------------------------------------------------------------------------
KONFIG <- list(
  base_url = "https://putusan3.mahkamahagung.go.id",
  # Kata kunci pencarian. Tanda kutip membuat situs mencari frasa utuh.
  kata_kunci = c("BBM", "biosolar", "\"bio solar\"", "solar", "pertalite", "\"minyak tanah\"",
                 "\"bahan bakar minyak\"", "premium", "pertamax", "dexlite"),
  tahun = 2020:2026,
  # Pola URL pencarian situs; {q} = kata kunci, {tahun} = tahun putus, {page} = halaman.
  # Bila situs mengubah parameternya, salin URL hasil pencarian dari peramban dan sesuaikan.
  url_pencarian = "https://putusan3.mahkamahagung.go.id/search.html?q={q}&t_put={tahun}&page={page}",
  # Daftar klasifikasi direktori yang ditelusuri (difilter per tahun putus).
  kategori = c("https://putusan3.mahkamahagung.go.id/direktori/index/kategori/migas-1.html"),
  ikuti_terkait = TRUE,   # ikuti tautan "Putusan Terkait" (PN -> PT -> MA)
  maks_halaman = Inf,     # batas halaman per daftar/pencarian (Inf = semua)
  jeda_detik = 3,
  maks_coba = 4,
  cache_daftar_jam = 24,  # umur cache halaman daftar/pencarian (jam); halaman putusan di-cache permanen
  folder_keluaran = "hasil_scrape_R",
  user_agent = "Mozilla/5.0 (compatible; KajianBBM-UGM/0.1; riset akademik; +https://github.com/yudistirapermana/Kriminal-BBM)"
)

# Pola kata kunci jenis BBM (untuk relevansi dan kolom barang_bbm). Urutan = prioritas penamaan.
POLA_BBM <- c(
  "Biosolar"       = "bio\\s*-?\\s*solar",
  "Solar"          = "(?<!bio)(?<!bio )(?<!bio-)\\bsolar\\b|\\bhsd\\b|high speed diesel",
  "Pertalite"      = "pertalit",
  "Premium"        = "\\bpremium\\b",
  "Pertamax"       = "pertamax",
  "Dexlite"        = "dexlite",
  "Pertamina Dex"  = "pertamina\\s+dex\\b",
  "Minyak tanah"   = "minyak\\s+tanah|kerosin",
  "Avtur"          = "\\bavtur\\b",
  "Minyak bakar/MFO" = "\\bmfo\\b|marine fuel oil|minyak bakar",
  "Bensin (jenis tidak disebut)" = "\\bbensin\\b"
)
POLA_BBM_UMUM <- "\\bB\\.?B\\.?M\\b|bahan\\s+bakar\\s+minyak"
POLA_NON_BBM <- c("LPG/gas" = "\\blpg\\b|elpiji|tabung\\s+gas", "Minyak mentah" = "minyak\\s+mentah|crude\\s+oil|kondensat")

BULAN <- c(januari = 1, jan = 1, februari = 2, pebruari = 2, feb = 2, peb = 2, maret = 3, mar = 3,
           april = 4, apr = 4, mei = 5, juni = 6, jun = 6, juli = 7, jul = 7, agustus = 8, agt = 8,
           agu = 8, ags = 8, agust = 8, september = 9, sep = 9, sept = 9, oktober = 10, okt = 10,
           november = 11, nopember = 11, nov = 11, nop = 11, desember = 12, des = 12)
NAMA_BULAN <- c("Januari", "Februari", "Maret", "April", "Mei", "Juni", "Juli", "Agustus",
                "September", "Oktober", "November", "Desember")
POLA_BULAN <- paste(names(BULAN)[order(-nchar(names(BULAN)))], collapse = "|")
POLA_TANGGAL <- paste0("\\b(\\d{1,2})\\s*[- ]\\s*(", POLA_BULAN, ")\\.?\\s*[- ]\\s*(\\d{4})\\b")

# Pengadilan -> provinsi (dipakai bila lokasi kejadian tidak terbaca dari teks).
PROVINSI_PENGADILAN <- list(
  "Aceh" = c("BANDA ACEH", "TAKENGON", "LHOKSUKON", "BIREUEN", "LHOKSEUMAWE", "LANGSA", "IDI", "KUALA SIMPANG",
             "MEULABOH", "SIGLI", "CALANG", "TAPAKTUAN", "SINGKIL", "BLANGKEJEREN", "KUTACANE", "SINABANG", "SABANG",
             "JANTHO", "SIMPANG TIGA REDELONG", "MEUREUDU", "SUKA MAKMUE"),
  "Sumatera Utara" = c("MEDAN", "SIBOLGA", "RANTAU PRAPAT", "KISARAN", "TANJUNG BALAI", "LUBUK PAKAM", "BINJAI",
                       "STABAT", "TEBING TINGGI", "PEMATANG SIANTAR", "SIMALUNGUN", "PADANG SIDEMPUAN", "TARUTUNG",
                       "BALIGE", "KABANJAHE", "GUNUNG SITOLI", "PANYABUNGAN", "LABUHAN DELI", "SIDIKALANG"),
  "Sumatera Barat" = c("PADANG", "KOTO BARU", "PAYAKUMBUH", "PARIAMAN", "SAWAHLUNTO", "SOLOK", "BUKITTINGGI",
                       "BATUSANGKAR", "LUBUK SIKAPING", "MUARO", "PAINAN", "PADANG PANJANG", "LUBUK BASUNG",
                       "TANJUNG PATI", "PASAMAN BARAT", "MUARA LABUH"),
  "Riau" = c("PEKANBARU", "DUMAI", "PELALAWAN", "BENGKALIS", "BANGKINANG", "RENGAT", "TEMBILAHAN",
             "SIAK SRI INDRAPURA", "SIAK", "ROKAN HILIR", "PASIR PANGARAIAN", "TELUK KUANTAN"),
  "Kepulauan Riau" = c("BATAM", "TANJUNG PINANG", "KEPULAUAN RIAU", "TANJUNG BALAI KARIMUN", "KARIMUN", "NATUNA",
                       "RANAI", "DABO SINGKEP", "BINTAN"),
  "Jambi" = c("JAMBI", "MUARA BUNGO", "TANJUNG JABUNG TIMUR", "MUARA SABAK", "KUALA TUNGKAL", "SAROLANGUN",
              "MUARA BULIAN", "SENGETI", "BANGKO", "MUARA TEBO", "SUNGAI PENUH"),
  "Sumatera Selatan" = c("PALEMBANG", "LUBUK LINGGAU", "PANGKALAN BALAI", "SEKAYU", "KAYU AGUNG", "BATURAJA",
                         "LAHAT", "MUARA ENIM", "PRABUMULIH", "PAGAR ALAM", "MUARA BELITI"),
  "Kepulauan Bangka Belitung" = c("PANGKAL PINANG", "BANGKA BELITUNG", "KOBA", "SUNGAILIAT", "MUNTOK",
                                  "TANJUNG PANDAN", "SIMPANG RIMBA"),
  "Bengkulu" = c("BENGKULU", "ARGA MAKMUR", "CURUP", "MANNA", "TAIS"),
  "Lampung" = c("TANJUNG KARANG", "GEDONG TATAAN", "KOTABUMI", "METRO", "KALIANDA", "MENGGALA", "SUKADANA",
                "GUNUNG SUGIH", "KOTA AGUNG", "LIWA", "BLAMBANGAN UMPU", "BANDAR LAMPUNG"),
  "DKI Jakarta" = c("JAKARTA PUSAT", "JAKARTA UTARA", "JAKARTA BARAT", "JAKARTA SELATAN", "JAKARTA TIMUR",
                    "DKI JAKARTA", "JAKARTA"),
  "Banten" = c("SERANG", "CILEGON", "TANGERANG", "RANGKASBITUNG", "PANDEGLANG", "BANTEN"),
  "Jawa Barat" = c("BANDUNG", "CIANJUR", "BEKASI", "CIKARANG", "KARAWANG", "CIREBON", "SUMBER", "INDRAMAYU",
                   "SUBANG", "PURWAKARTA", "BOGOR", "CIBINONG", "DEPOK", "SUKABUMI", "CIBADAK", "GARUT",
                   "TASIKMALAYA", "CIAMIS", "KUNINGAN", "MAJALENGKA", "SUMEDANG", "BALE BANDUNG", "BANJAR"),
  "Jawa Tengah" = c("SEMARANG", "KAB SEMARANG", "UNGARAN", "PATI", "REMBANG", "BLORA", "PURWOREJO", "KEBUMEN",
                    "KUDUS", "JEPARA", "DEMAK", "TEGAL", "SLAWI", "BREBES", "CILACAP", "SURAKARTA", "BOYOLALI",
                    "KLATEN", "SRAGEN", "SUKOHARJO", "KARANGANYAR", "WONOGIRI", "PURBALINGGA", "PURWOKERTO",
                    "BANJARNEGARA", "WONOSOBO", "TEMANGGUNG", "MAGELANG", "MUNGKID", "KENDAL", "BATANG",
                    "PEKALONGAN", "KAJEN", "PEMALANG", "GROBOGAN", "PURWODADI", "SALATIGA"),
  "DI Yogyakarta" = c("YOGYAKARTA", "WONOSARI", "SLEMAN", "BANTUL", "WATES"),
  "Jawa Timur" = c("SURABAYA", "BANYUWANGI", "KABUPATEN KEDIRI", "KEDIRI", "KEPANJEN", "MALANG", "KRAKSAAN",
                   "PROBOLINGGO", "SITUBONDO", "SUMENEP", "TUBAN", "TULUNGAGUNG", "SIDOARJO", "GRESIK", "LAMONGAN",
                   "BOJONEGORO", "PASURUAN", "BANGIL", "JEMBER", "LUMAJANG", "BONDOWOSO", "BANGKALAN", "SAMPANG",
                   "PAMEKASAN", "MOJOKERTO", "JOMBANG", "NGANJUK", "MADIUN", "NGAWI", "MAGETAN", "PONOROGO",
                   "PACITAN", "TRENGGALEK", "BLITAR", "BATU"),
  "Bali" = c("DENPASAR", "SEMARAPURA", "SINGARAJA", "GIANYAR", "TABANAN", "NEGARA", "AMLAPURA", "BANGLI"),
  "Nusa Tenggara Barat" = c("MATARAM", "PRAYA", "SELONG", "SUMBAWA BESAR", "DOMPU", "BIMA"),
  "Nusa Tenggara Timur" = c("KUPANG", "RUTENG", "ENDE", "MAUMERE", "LARANTUKA", "ATAMBUA", "KEFAMENANU", "SOE",
                            "WAINGAPU", "WAIKABUBAK", "BAJAWA", "KALABAHI", "LABUAN BAJO", "OELAMASI"),
  "Kalimantan Barat" = c("PONTIANAK", "KETAPANG", "MEMPAWAH", "BENGKAYANG", "SANGGAU", "SINTANG", "PUTUSSIBAU",
                         "SAMBAS", "SINGKAWANG", "NGABANG", "SEKADAU", "NANGA PINOH"),
  "Kalimantan Tengah" = c("PALANGKA RAYA", "PALANGKARAYA", "SAMPIT", "PANGKALAN BUN", "NANGA BULIK", "KUALA KAPUAS",
                          "MUARA TEWEH", "BUNTOK", "TAMIANG LAYANG", "KUALA KURUN", "KASONGAN", "KUALA PEMBUANG",
                          "SUKAMARA", "PULANG PISAU"),
  "Kalimantan Selatan" = c("BANJARMASIN", "PELAIHARI", "MARTAPURA", "KOTABARU", "TANJUNG", "MARABAHAN",
                           "BANJARBARU", "BATULICIN", "AMUNTAI", "BARABAI", "KANDANGAN", "RANTAU", "PARINGIN"),
  "Kalimantan Timur" = c("SAMARINDA", "BALIKPAPAN", "TENGGARONG", "SANGATTA", "KUTAI BARAT", "SENDAWAR",
                         "TANAH GROGOT", "TANJUNG REDEB", "BONTANG", "PENAJAM"),
  "Kalimantan Utara" = c("TARAKAN", "NUNUKAN", "TANJUNG SELOR", "MALINAU"),
  "Sulawesi Utara" = c("MANADO", "BITUNG", "KOTAMOBAGU", "TONDANO", "AIRMADIDI", "AMURANG", "TAHUNA", "MELONGUANE"),
  "Gorontalo" = c("GORONTALO", "LIMBOTO", "TILAMUTA", "MARISA"),
  "Sulawesi Tengah" = c("PALU", "DONGGALA", "TOLITOLI", "LUWUK", "POSO", "BUOL", "PARIGI", "BANGGAI", "KOLONODALE"),
  "Sulawesi Barat" = c("MAMUJU", "POLEWALI", "PASANGKAYU", "MAJENE", "SULAWESI BARAT"),
  "Sulawesi Selatan" = c("MAKASSAR", "PALOPO", "WATANSOPPENG", "TAKALAR", "MAROS", "PANGKAJENE", "BARRU",
                         "PAREPARE", "PINRANG", "SIDENRENG RAPPANG", "SIDRAP", "ENREKANG", "MAKALE", "MASAMBA",
                         "MALILI", "SENGKANG", "WATAMPONE", "SINJAI", "BULUKUMBA", "BANTAENG", "JENEPONTO",
                         "SUNGGUMINASA", "SELAYAR", "BELOPA"),
  "Sulawesi Tenggara" = c("KENDARI", "BAU BAU", "BAUBAU", "KOLAKA", "RAHA", "UNAAHA", "ANDOOLO", "PASARWAJO"),
  "Maluku" = c("AMBON", "MASOHI", "TUAL", "SAUMLAKI", "DOBO", "NAMLEA"),
  "Maluku Utara" = c("TERNATE", "MALUKU UTARA", "TOBELO", "SOASIO", "LABUHA", "SANANA"),
  "Papua Barat" = c("FAKFAK", "MANOKWARI", "KAIMANA", "TELUK BINTUNI", "PAPUA BARAT"),
  "Papua Barat Daya" = c("SORONG"),
  "Papua" = c("JAYAPURA", "BIAK", "SERUI", "NABIRE", "SENTANI", "KEEROM"),
  "Papua Selatan" = c("MERAUKE"),
  "Papua Tengah" = c("TIMIKA", "MIMIKA"),
  "Papua Pegunungan" = c("WAMENA")
)

# -----------------------------------------------------------------------------
# 1. UTILITAS
# -----------------------------------------------------------------------------
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0 || (length(a) == 1 && is.na(a))) b else a

pesan <- function(...) message(format(Sys.time(), "%H:%M:%S"), "  ", paste0(...))

rapikan <- function(x) str_squish(str_replace_all(x %||% "", "\u00a0", " "))

kunci_tempat <- function(nama) {
  n <- toupper(nama %||% "")
  n <- str_replace_all(n, "\\.", " ")
  n <- str_replace(str_trim(n), "^(PN|PT|PENGADILAN\\s+NEGERI|PENGADILAN\\s+TINGGI|DILMIL|PENGADILAN\\s+MILITER(\\s+TINGGI)?)\\b", "")
  n <- str_replace_all(n, "\\bKELAS\\s+[I1]+\\s*[AB]?\\b", " ")
  n <- str_replace_all(n, "\\b[IVX]+\\s*-?\\s*\\d+\\b", " ")
  str_replace_all(n, "[^A-Z]", "")
}
.TABEL_PROVINSI <- local({
  v <- unlist(lapply(names(PROVINSI_PENGADILAN), function(p) setNames(rep(p, length(PROVINSI_PENGADILAN[[p]])),
                                                                       vapply(PROVINSI_PENGADILAN[[p]], kunci_tempat, ""))))
  v[!duplicated(names(v))]
})

provinsi_pengadilan <- function(nama) {
  if (is.null(nama) || is.na(nama) || nama == "" || str_detect(toupper(nama), "MAHKAMAH AGUNG")) return(NA_character_)
  unname(.TABEL_PROVINSI[kunci_tempat(nama)]) %||% NA_character_
}

# -----------------------------------------------------------------------------
# 2. HTTP: jeda, retry, cache, robots.txt, deteksi CAPTCHA
# -----------------------------------------------------------------------------
.robots_cache <- new.env()

kondisi_captcha <- function(url, alasan = "Situs meminta CAPTCHA") {
  # Kelas "captcha_error" dipakai untuk semua tanda pemblokiran (CAPTCHA, tantangan anti-bot, HTTP 403/429):
  # penelusuran dihentikan, bukan dilanjutkan ke URL berikutnya.
  structure(class = c("captcha_error", "error", "condition"),
            list(message = paste0(alasan, ": ", url,
                                  "\nBuka situs di peramban; untuk pencarian, simpan halaman hasil lalu jalankan --mode=html.",
                                  "\nPenelusuran bisa dilanjutkan nanti dengan perintah yang sama (antrean tersimpan)."),
                 call = NULL))
}

mirip_captcha <- function(html) {
  if (is.null(html) || length(html) == 0 || is.na(html)) return(FALSE)
  isTRUE(str_detect(str_to_lower(substr(html, 1, 200000)),
                    "g-recaptcha|recaptcha/api|h-captcha|hcaptcha\\.com|cf-turnstile|saya bukan robot|i'm not a robot|cf-chl-|challenge-platform|just a moment\\.\\.\\.|ddos-guard|<input[^>]+name=[\"']?captcha"))
}

izin_robots <- function(url, cfg = KONFIG) {
  # robots.txt menurut RFC 9309: grup User-agent berurutan, Allow/Disallow, '*' dan '$', aturan terpanjang menang.
  akar <- str_extract(url, "^https?://[^/]+")
  if (is.null(.robots_cache[[akar]])) {
    teks <- tryCatch({
      r <- GET(paste0(akar, "/robots.txt"), user_agent(cfg$user_agent), timeout(30))
      if (status_code(r) == 200) content(r, as = "text", encoding = "UTF-8") else ""
    }, error = function(e) "")
    .robots_cache[[akar]] <- aturan_robots(teks %||% "", "KajianBBM-UGM")
  }
  robots_mengizinkan(.robots_cache[[akar]], str_remove(url, "^https?://[^/]+"))
}

aturan_robots <- function(teks, nama_bot) {
  baris <- str_trim(str_remove(str_split(teks, "\r?\n")[[1]], "#.*$"))
  grup <- list(); agen <- character(0); aturan <- list(); baru_agen <- TRUE
  tutup <- function() if (length(agen)) grup[[length(grup) + 1]] <<- list(agen = agen, aturan = aturan)
  for (b in baris[nzchar(baris)]) {
    kv <- str_match(b, "^([A-Za-z-]+)\\s*:\\s*(.*)$")
    if (is.na(kv[1, 1])) next
    k <- str_to_lower(kv[1, 2]); v <- str_trim(kv[1, 3])
    if (k == "user-agent") {
      if (!baru_agen) { tutup(); agen <- character(0); aturan <- list() }
      agen <- c(agen, str_to_lower(v)); baru_agen <- TRUE
    } else if (k %in% c("allow", "disallow")) {
      baru_agen <- FALSE
      if (nzchar(v)) aturan[[length(aturan) + 1]] <- list(izin = k == "allow", pola = v)
    }
  }
  tutup()
  cocok <- Filter(function(g) any(str_detect(str_to_lower(nama_bot), fixed(g$agen[g$agen != "*"]))), grup)
  if (!length(cocok)) cocok <- Filter(function(g) "*" %in% g$agen, grup)
  unlist(lapply(cocok, `[[`, "aturan"), recursive = FALSE)
}

robots_mengizinkan <- function(aturan, jalur) {
  if (!length(aturan)) return(TRUE)
  ke_regex <- function(p) {
    akhir <- endsWith(p, "$")
    p <- str_remove(p, "\\$$")
    paste0("^", str_replace_all(str_replace_all(p, "([.+?^(){}|\\[\\]\\\\])", "\\\\\\1"), "\\*", ".*"), if (akhir) "$" else "")
  }
  cocok <- Filter(function(a) str_detect(jalur, ke_regex(a$pola)), aturan)
  if (!length(cocok)) return(TRUE)
  panjang <- vapply(cocok, function(a) nchar(a$pola), 0)
  terbaik <- cocok[panjang == max(panjang)]
  any(vapply(terbaik, `[[`, TRUE, "izin"))   # seri: Allow menang
}

.terakhir_minta <- new.env()
tunggu_giliran <- function(cfg) {
  jeda <- cfg$jeda_detik + runif(1, 0, 1.5)
  t0 <- .terakhir_minta$t %||% 0
  sisa <- jeda - (as.numeric(Sys.time()) - t0)
  if (sisa > 0) Sys.sleep(sisa)
  .terakhir_minta$t <- as.numeric(Sys.time())
}

minta <- function(url, cfg, simpan_ke = NULL) {
  if (!izin_robots(url, cfg)) stop("robots.txt melarang: ", url)
  galat <- NULL
  for (i in seq_len(cfg$maks_coba)) {
    tunggu_giliran(cfg)
    r <- tryCatch(
      if (is.null(simpan_ke)) GET(url, user_agent(cfg$user_agent), timeout(90), add_headers(`Accept-Language` = "id-ID,id;q=0.9"))
      else GET(url, user_agent(cfg$user_agent), timeout(180), write_disk(simpan_ke, overwrite = TRUE)),
      error = function(e) e)
    if (inherits(r, "response") && status_code(r) == 200) return(r)
    if (inherits(r, "response")) {
      kode <- status_code(r)
      isi <- tryCatch(if (is.null(simpan_ke)) teks_respons(r) else read_file(simpan_ke), error = function(e) "")
      if (!is.null(simpan_ke)) unlink(simpan_ke)
      # Halaman tantangan anti-bot sering dikirim dengan 403/429/503: hentikan, jangan diulang terus.
      if (mirip_captcha(isi) || !is.null(headers(r)[["cf-mitigated"]])) stop(kondisi_captcha(url))
      if (kode == 403) stop(kondisi_captcha(url, "Situs menolak akses (HTTP 403)"))
      galat <- paste("HTTP", kode)
      if (!kode %in% c(429, 500, 502, 503, 504)) break
      tunda <- suppressWarnings(as.numeric(headers(r)[["retry-after"]]))
      if (is.na(tunda)) tunda <- cfg$jeda_detik * 2^i
    } else {
      galat <- conditionMessage(r)
      tunda <- cfg$jeda_detik * 2^i
    }
    if (i < cfg$maks_coba) {
      pesan("  gagal (", galat, "), coba lagi dalam ", round(min(tunda, 300)), " detik")
      Sys.sleep(min(tunda, 300))
    }
  }
  if (identical(galat, "HTTP 429")) stop(kondisi_captcha(url, "Situs membatasi permintaan (HTTP 429) berulang kali"))
  stop("gagal mengambil ", url, ": ", galat)
}

teks_respons <- function(r) {
  # Dekode UTF-8 dengan aman: byte tidak sah (mis. tanda kutip Windows-1252) tidak membuat halaman menjadi NA.
  mentah <- content(r, as = "raw")
  if (!length(mentah)) return("")
  t <- rawToChar(mentah[mentah != as.raw(0)])
  t2 <- iconv(t, "UTF-8", "UTF-8", sub = "byte")
  if (is.na(t2)) iconv(t, "latin1", "UTF-8") else t2
}

halaman_dikenali <- function(html, jenis) {
  # Halaman galat (mis. "A Database Error Occurred") atau pemblokiran jenis lain tidak boleh di-cache.
  if (jenis == "overview") return(str_detect(html, regex(">\\s*(Nomor|Tingkat Proses|Klasifikasi|Lembaga Peradilan)\\s*(&nbsp;|\\s)*:?\\s*<", ignore_case = TRUE)))
  if (jenis == "daftar") return(str_detect(html, regex(POLA_URL_PUTUSAN, ignore_case = TRUE)) ||
                                  (str_detect(html, regex("Direktori Putusan|putusan3\\.mahkamahagung", ignore_case = TRUE)) &&
                                   !str_detect(html, regex("Database Error|Fatal error|Exception|Service Unavailable", ignore_case = TRUE))))
  TRUE
}

nama_cache <- function(url) {
  n <- str_replace_all(str_remove(url, "^https?://[^/]+/"), "[^A-Za-z0-9]+", "_")
  if (nchar(n) > 180) n <- paste0(substr(n, 1, 100), "__", substr(n, nchar(n) - 79, nchar(n)))
  paste0(n, ".html")
}

ambil_html <- function(url, cfg, folder_cache, pakai_cache = TRUE, jenis = "overview") {
  # jenis = "overview" (halaman putusan; cache permanen) atau "daftar" (daftar/pencarian; cache kedaluwarsa
  # setelah cfg$cache_daftar_jam agar putusan baru, mis. tahun berjalan, tetap terambil).
  dir.create(folder_cache, showWarnings = FALSE, recursive = TRUE)
  f <- file.path(folder_cache, nama_cache(url))
  if (pakai_cache && file.exists(f)) {
    umur <- as.numeric(difftime(Sys.time(), file.mtime(f), units = "hours"))
    if (jenis != "daftar" || umur < (cfg$cache_daftar_jam %||% 24)) return(read_file(f))
  }
  r <- minta(url, cfg)
  html <- teks_respons(r)
  if (mirip_captcha(html)) stop(kondisi_captcha(url))
  if (!halaman_dikenali(html, jenis)) stop("halaman tidak dikenali sebagai ", jenis, " (galat situs/blokir?), tidak di-cache: ", url)
  write_file(html, f)
  html
}

unduh_pdf <- function(url, tujuan, cfg) {
  if (file.exists(tujuan) && file.size(tujuan) > 0) return(tujuan)
  dir.create(dirname(tujuan), showWarnings = FALSE, recursive = TRUE)
  sementara <- paste0(tujuan, ".part")
  r <- minta(url, cfg, simpan_ke = sementara)
  awal <- readBin(sementara, "raw", 5)
  if (!identical(rawToChar(awal[awal != as.raw(0)]), "%PDF-")) {
    isi <- read_file(sementara)
    unlink(sementara)
    if (mirip_captcha(isi)) stop(kondisi_captcha(url))
    stop("berkas unduhan bukan PDF: ", url)
  }
  file.rename(sementara, tujuan)
  tujuan
}

# -----------------------------------------------------------------------------
# 3. PARSER HTML DIREKTORI PUTUSAN
#    Tidak bergantung pada kelas CSS: tautan putusan dikenali dari pola URL, metadata dari
#    baris tabel label | nilai, lampiran dari pola /download_file/.../pdf/...
# -----------------------------------------------------------------------------
POLA_URL_PUTUSAN <- "/direktori/putusan/([0-9a-z]{16,64})\\.html"

id_putusan <- function(url) {
  if (!length(url)) return(character(0))
  str_to_lower(str_match(ifelse(is.na(url), "", url), regex(POLA_URL_PUTUSAN, ignore_case = TRUE))[, 2])
}

url_kanonik <- function(href, cfg = KONFIG) {
  if (!length(href)) return(character(0))
  id <- id_putusan(href)
  ifelse(is.na(id), href, paste0(cfg$base_url, "/direktori/putusan/", id, ".html"))
}

parse_daftar <- function(html, url_halaman = KONFIG$base_url) {
  doc <- read_html(html)
  a <- html_elements(doc, "a[href]")
  href <- html_attr(a, "href")
  ok <- !is.na(id_putusan(href))
  kosong <- tibble(id = character(), url = character(), nomor = character(), tanggal_putus = character())
  if (!any(ok)) return(kosong)
  a <- a[ok]; href <- href[ok]
  blok <- lapply(a, function(x) xml_find_first(x, "ancestor::*[contains(@class,'spost') or contains(@class,'entry')][1]"))
  dalam_entri <- !vapply(blok, inherits, TRUE, "xml_missing")
  # Bila halaman punya entri hasil (div.spost/.entry), tautan di luar entri (sidebar "Terpopuler/Terbaru") diabaikan.
  if (any(dalam_entri)) { a <- a[dalam_entri]; href <- href[dalam_entri]; blok <- blok[dalam_entri] }
  teks_blok <- map_chr(seq_along(a), function(i) {
    b <- blok[[i]]
    if (inherits(b, "xml_missing")) b <- xml_find_first(a[[i]], "ancestor::*[self::li or self::tr][1]")
    if (inherits(b, "xml_missing")) return(NA_character_)
    # Tanggal hanya dipakai bila blok memuat satu putusan saja (bukan wadah beberapa entri).
    ids <- unique(id_putusan(html_attr(html_elements(b, "a[href]"), "href")))
    if (sum(!is.na(ids)) > 1) NA_character_ else rapikan(html_text2(b))
  })
  judul <- rapikan(html_text2(a))
  tibble(
    id = id_putusan(href),
    url = url_kanonik(url_absolute(href, url_halaman)),
    nomor = str_match(judul, "Nomor\\s+(\\S+(?:\\s+\\S+){0,3}?)(?:\\s+Tanggal|$)")[, 2],
    tanggal_putus = str_match(teks_blok, regex("Putus\\s*:\\s*(\\d{1,2}[-/ ][0-9A-Za-z]{1,9}[-/ ]\\d{4})", ignore_case = TRUE))[, 2]
  ) |>
    group_by(id) |> slice(1) |> ungroup()
}

halaman_terakhir <- function(html, url_daftar) {
  doc <- read_html(html)
  href <- url_absolute(html_attr(html_elements(doc, "a[href]"), "href"), url_daftar)
  # Pola direktori: .../migas-1/tahunjenis/putus/tahun/2021/page/3.html
  awalan <- str_remove(str_replace(url_daftar, "/page/\\d+\\.html$", ".html"), "\\.html$")
  n1 <- as.integer(str_match(href[startsWith(href, paste0(awalan, "/page/"))], "/page/(\\d+)\\.html")[, 2])
  # Pola pencarian: search.html?q=...&t_put=...&page=3 (urutan parameter dan pengodean bebas)
  acuan <- parse_url(url_daftar)
  dekode <- function(x) if (is.null(x)) NA_character_ else str_squish(URLdecode(chartr("+", " ", x)))
  n2 <- vapply(href[str_detect(href, "[?&]page=\\d+")], function(h) {
    u <- parse_url(h)
    sama <- identical(str_remove(u$path %||% "", "^/"), str_remove(acuan$path %||% "", "^/")) &&
      identical(dekode(u$query$q), dekode(acuan$query$q)) &&
      identical(u$query$t_put %||% "", acuan$query$t_put %||% "")
    if (sama) as.integer(u$query$page) else NA_integer_
  }, 0L)
  max(c(1L, n1, n2), na.rm = TRUE)
}

url_halaman_direktori <- function(url_daftar, n) {
  dasar <- str_replace(url_daftar, "/page/\\d+\\.html$", ".html")
  if (n <= 1) dasar else str_replace(dasar, "\\.html$", paste0("/page/", n, ".html"))
}

url_filter_tahun <- function(url_daftar, tahun) {
  dasar <- str_replace(url_daftar, "/page/\\d+\\.html$", ".html")
  dasar <- str_replace(dasar, "/tahunjenis/[^/]+/tahun/\\d{4}\\.html$", ".html")
  str_replace(dasar, "\\.html$", paste0("/tahunjenis/putus/tahun/", tahun, ".html"))
}

url_pencarian <- function(q, tahun, page, cfg = KONFIG) {
  u <- str_replace(cfg$url_pencarian, fixed("{q}"), URLencode(q, reserved = TRUE))
  u <- str_replace(u, fixed("{tahun}"), as.character(tahun))
  str_replace(u, fixed("{page}"), as.character(page))
}

LABEL_OVERVIEW <- c(
  "nomor" = "nomor", "tingkat proses" = "tingkat_proses", "klasifikasi" = "klasifikasi",
  "kata kunci" = "kata_kunci", "tahun" = "tahun", "tanggal register" = "tanggal_register",
  "lembaga peradilan" = "lembaga_peradilan", "jenis lembaga peradilan" = "jenis_lembaga_peradilan",
  "amar" = "amar", "amar lainnya" = "amar_lainnya", "catatan amar" = "catatan_amar",
  "tanggal musyawarah" = "tanggal_musyawarah", "tanggal dibacakan" = "tanggal_dibacakan",
  "kaidah" = "kaidah", "abstrak" = "abstrak", "status" = "status"
)

parse_overview <- function(html, url) {
  doc <- read_html(html)
  hasil <- list(id = id_putusan(url), url = url_kanonik(url))
  for (tr in html_elements(doc, "tr")) {
    sel <- html_elements(tr, xpath = "./td|./th")
    if (length(sel) < 2) next
    # "Nomor :", "Nomor&nbsp;:", "Nomor" -> "nomor"
    label <- str_to_lower(str_squish(str_replace_all(html_text2(sel[[1]]), " ", " ")))
    label <- str_squish(str_remove(label, "\\s*:\\s*$"))
    kunci <- LABEL_OVERVIEW[label]
    if (is.na(kunci) || !is.null(hasil[[kunci]])) next
    hasil[[kunci]] <- rapikan(html_text2(sel[[length(sel)]]))
  }
  href <- url_absolute(html_attr(html_elements(doc, "a[href]"), "href"), url)
  unduh <- href[str_detect(href, regex("/direktori/download_file/", ignore_case = TRUE))]
  hasil$url_pdf <- unduh[str_detect(unduh, regex("/pdf/", ignore_case = TRUE))][1] %||% NA_character_
  hasil$lampiran_pdf <- if (is.na(hasil$url_pdf)) "Tidak ada" else "Ada"

  # Putusan Terkait: naik dari judul bagian sampai wadah pertama yang memuat tautan putusan apa pun
  # (termasuk diri sendiri). Bila isinya hanya diri sendiri, berarti tidak ada putusan terkait; jangan naik
  # lebih jauh ke sidebar "Putusan Terbaru".
  terkait <- character(0)
  judul <- xml_find_first(doc, "//*[contains(translate(normalize-space(text()),'PUTSANERKI','putsanerki'),'putusan terkait')]")
  if (!inherits(judul, "xml_missing")) {
    wadah <- judul
    for (i in 1:6) {
      wadah <- xml_parent(wadah)
      if (inherits(wadah, "xml_missing")) break
      t <- url_absolute(html_attr(html_elements(wadah, "a[href]"), "href"), url)
      t <- t[!is.na(id_putusan(t))]
      if (length(t)) {
        terkait <- unique(url_kanonik(t[id_putusan(t) != hasil$id]))
        break
      }
    }
  }
  hasil$terkait <- terkait
  hasil
}

# -----------------------------------------------------------------------------
# 4. TEKS PDF (tanpa watermark diagonal, kop, nomor halaman dan disclaimer)
# -----------------------------------------------------------------------------
POLA_BOILERPLATE <- paste(c(
  "^Mahkamah Agung Republik Indonesia$", "^Direktori Putusan Mahkamah Agung Republik Indonesia$",
  "^putusan\\.mahkamahagung\\.go\\.id$", "^Disclaimer$",
  "^Kepaniteraan Mahkamah Agung Republik Indonesia berusaha", "^pelaksanaan fungsi peradilan\\. Namun",
  "^Dalam hal Anda menemukan inakurasi", "^Email\\s*:\\s*kepaniteraan@", "^Hal(aman|\\.)?\\s*\\d+\\s*(dari|dr\\.?)\\s*\\d+",
  "^Halaman\\s*\\d+\\s*$"), collapse = "|")

teks_pdf <- function(path) {
  halaman <- tryCatch(pdf_data(path), error = function(e) NULL)
  if (is.null(halaman)) return(NA_character_)
  baris_semua <- character(0)
  for (d in halaman) {
    if (!nrow(d)) next
    # Watermark "Mahkamah Agung Republik Indonesia" berupa huruf besar miring (tinggi >= 19 px);
    # isi putusan ~9 px, kop ~13 px, disclaimer ~4 px.
    d <- d[d$height >= 5 & d$height < 17, ]
    if (!nrow(d)) next
    d <- d[order(d$y, d$x), ]
    no_baris <- cumsum(c(TRUE, diff(d$y) > 3))
    baris <- tapply(d$text, no_baris, paste, collapse = " ")
    baris_semua <- c(baris_semua, unname(baris))
  }
  baris_semua <- rapikan_baris(baris_semua)
  paste(baris_semua[!str_detect(baris_semua, regex(POLA_BOILERPLATE, ignore_case = TRUE))], collapse = "\n")
}

rapikan_baris <- function(x) {
  x <- str_squish(str_replace_all(x, "[\u00a0\u00ac]", " "))
  # "T erdakwa" -> "Terdakwa" (kerning di sebagian PDF)
  str_replace_all(x, "\\b([TWYPF]) (?=[a-z]{2,})", "\\1")
}

# -----------------------------------------------------------------------------
# 5. EKSTRAKSI KOLOM DARI TEKS PUTUSAN
# -----------------------------------------------------------------------------
parse_tanggal <- function(s) {
  m <- str_match(s %||% "", regex(POLA_TANGGAL, ignore_case = TRUE))
  if (is.na(m[1, 1])) return(as.Date(NA))
  tryCatch(as.Date(sprintf("%s-%02d-%02d", m[1, 4], BULAN[[str_to_lower(m[1, 3])]], as.integer(m[1, 2]))),
           error = function(e) as.Date(NA))
}
format_tanggal <- function(d) if (is.na(d)) NA_character_ else paste(as.integer(format(d, "%d")), NAMA_BULAN[as.integer(format(d, "%m"))], format(d, "%Y"))

angka_id <- function(s) {
  # Angka gaya Indonesia: "5.353" -> 5353 ; "19.930.365,00" -> 19930365 ; "1.234,5" -> 1234.5 ; "92" -> 92
  vapply(s, function(x) {
    x <- str_remove(str_remove_all(str_trim(x %||% ""), "\\s"), "[.,]+$")
    if (!nzchar(x)) return(NA_real_)
    if (str_detect(x, ",")) {
      bulat <- str_remove_all(str_extract(x, "^[^,]*"), "\\.")
      pecahan <- str_extract(x, "(?<=,)\\d+$") %||% "0"
      return(suppressWarnings(as.numeric(paste0(if (nzchar(bulat)) bulat else "0", ".", pecahan))))
    }
    if (str_detect(x, "^\\d{1,3}(\\.\\d{3})+$")) return(as.numeric(str_remove_all(x, "\\.")))
    suppressWarnings(as.numeric(x))
  }, numeric(1), USE.NAMES = FALSE)
}

nomor_dari_teks <- function(teks) {
  kepala <- paste(head(str_split(teks, "\n")[[1]], 40), collapse = "\n")
  m <- str_match(kepala, regex("^\\s*Nomor\\s*[.:]?\\s*(\\d[^\n]{0,60}/[^\n]{2,60})$", ignore_case = TRUE, multiline = TRUE))
  if (is.na(m[1, 2])) NA_character_ else str_remove(str_squish(m[1, 2]), "[.;,: ]+$")
}

tingkat_dari_nomor <- function(nomor) {
  n <- str_remove_all(toupper(nomor %||% ""), " ")
  case_when(
    str_detect(n, "\\d+PK/") ~ "MA",
    str_detect(n, "\\d+K/") ~ "MA",
    str_detect(n, "/PT\\.?[A-Z]") ~ "PT",
    str_detect(n, "/PN\\.?[A-Z]") ~ "PN",
    str_detect(n, "/PM|DILMIL|/AD/|/AL/|/AU/") ~ "Pengadilan Militer",
    TRUE ~ NA_character_
  )
}

posisi_amar <- function(teks) {
  m <- str_locate_all(teks, regex("^\\s*M\\s*E\\s*N\\s*G\\s*A\\s*D\\s*I\\s*L\\s*I\\b(\\s*S\\s*E\\s*N\\s*D\\s*I\\s*R\\s*I)?", multiline = TRUE))[[1]]
  if (!nrow(m)) return(NULL)
  teks_judul <- str_sub(teks, m[, 1], m[, 2] + 20)
  pilih <- which(!str_detect(teks_judul, "S\\s*E\\s*N\\s*D\\s*I\\s*R\\s*I"))
  if (!length(pilih)) return(NULL)
  awal <- m[max(pilih), 1]
  akhir_rel <- str_locate(str_sub(teks, awal), regex("^\\s*Demikian", ignore_case = TRUE, multiline = TRUE))[1, 1]
  c(awal, if (is.na(akhir_rel)) nchar(teks) else awal + akhir_rel - 2)
}

amar_dari_teks <- function(teks) {
  p <- posisi_amar(teks)
  if (is.null(p)) NA_character_ else str_sub(teks, p[1], p[2])
}

tanggal_putusan_teks <- function(teks) {
  pos <- str_locate_all(teks, regex("Demikian", ignore_case = TRUE))[[1]]
  if (!nrow(pos)) return(as.Date(NA))
  penutup <- str_sub(teks, pos[nrow(pos), 1], pos[nrow(pos), 1] + 2500)
  m <- str_match(penutup, regex("diucapkan(.{0,250})", ignore_case = TRUE, dotall = TRUE))[, 2]
  if (!is.na(m) && !str_detect(str_to_lower(m), "itu juga")) {
    d <- parse_tanggal(m)
    if (!is.na(d)) return(d)
  }
  parse_tanggal(penutup)
}

hasil_putusan <- function(amar) {
  # Mengembalikan c(hasil, dasar). Hasil: "Bersalah" / "Tidak bersalah" / NA.
  if (is.na(amar) || !nzchar(amar)) return(c(NA, "amar tidak ditemukan"))
  a <- str_remove_all(str_to_lower(amar), "\\s+")
  if (str_detect(a, "mengadilisendiri")) a <- tail(str_split(a, "mengadilisendiri")[[1]], 1)
  if (str_detect(a, "(?<!tidak)terbukti(secara)?(sah)?(dan)?(meyakinkan|menyakinkan)?bersalah"))
    return(c("Bersalah", "amar: terdakwa terbukti bersalah"))
  if (str_detect(a, "membebaskan(para)?terdakwa.{0,150}dakwaan") || str_detect(a, "bebasdarisegaladakwaan"))
    return(c("Tidak bersalah", "amar: terdakwa dibebaskan (vrijspraak)"))
  if (str_detect(a, "melepaskan(para)?terdakwa.{0,150}tuntutanhukum"))
    return(c("Tidak bersalah", "amar: terdakwa dilepaskan dari segala tuntutan hukum (onslag)"))
  if (str_detect(a, "menolakpermohonan(kasasi|peninjauankembali)")) {
    if (str_detect(a, "pemohon(kasasi|peninjauankembali)[ivx]*/?(terdakwa|terpidana)"))
      return(c("Bersalah", "kasasi/PK terdakwa ditolak: pemidanaan tetap berlaku"))
    return(c(NA, "kasasi penuntut umum ditolak: ikut putusan sebelumnya"))
  }
  if (str_detect(a, "menguatkanputusan")) return(c(NA, "menguatkan putusan sebelumnya: ikut putusan sebelumnya"))
  if (str_detect(a, "pidanapenjaraselama|pidanadendasebesar|pidanadendasejumlah|menjatuhkanpidana"))
    return(c("Bersalah", "amar: menjatuhkan pidana"))
  c(NA, "pola amar tidak dikenali")
}

hasil_dari_kutipan <- function(teks) {
  # Untuk putusan yang "menguatkan" atau menolak kasasi penuntut umum: status terdakwa mengikuti putusan
  # sebelumnya, yang amarnya biasanya dikutip ("Membaca putusan ... yang amar lengkapnya ...").
  p <- posisi_amar(teks)
  if (is.null(p)) return(c(NA, NA))
  badan <- str_sub(teks, 1, p[1] - 1)
  jangkar <- c("amar\\s+(?:putusan(?:nya)?\\s+)?(?:lengkap|selengkap)nya", "yang\\s+amarnya",
               "amar\\s+putusan(?:nya)?\\s+(?:sebagai|berbunyi)",
               "Membaca\\s+(?:salinan\\s+(?:resmi\\s+)?)?[Pp]utusan\\s+Pengadilan\\s+(?:Negeri|Tinggi)[^\\n]{0,200}?sebagai\\s+berikut")
  pos <- unlist(lapply(jangkar, function(j) str_locate_all(badan, regex(j, ignore_case = TRUE))[[1]][, 1]))
  pos <- c(pos, str_locate_all(badan, "M\\s*E\\s*N\\s*G\\s*A\\s*D\\s*I\\s*L\\s*I")[[1]][, 1])
  for (a in sort(unique(pos), decreasing = TRUE)) {
    seg <- str_sub(badan, a, a + 3500)
    henti <- str_locate(str_sub(seg, 30), regex("\\n\\s*(Menimbang|Membaca|Mengingat)", ignore_case = TRUE))[1, 1]
    if (!is.na(henti)) seg <- str_sub(seg, 1, henti + 29)
    h <- hasil_putusan(seg)
    if (!is.na(h[1])) return(c(h[1], paste0("mengikuti putusan sebelumnya yang dikutip (", h[2], ")")))
  }
  c(NA, NA)
}

hitung_bbm <- function(teks) {
  t <- str_to_lower(teks %||% "")
  n <- vapply(POLA_BBM, function(p) str_count(t, regex(p)), 0)
  n[n > 0][order(-n[n > 0])]
}

relevansi_bbm <- function(teks, amar = NA_character_) {
  # "bahan bakar minyak mentah" dan "minyak mentah" bukan BBM olahan: dibuang sebelum mencari BBM.
  t <- str_replace_all(teks %||% "", regex("(bahan\\s+bakar\\s+)?minyak\\s+mentah", ignore_case = TRUE), " MENTAH ")
  inti <- hitung_bbm(t)
  di_amar <- length(hitung_bbm(amar %||% "")) > 0
  # Sebutan sekilas (mis. "Pertalite" hanya label nosel) tidak cukup: minimal 3 sebutan, atau disebut di amar.
  kuat <- length(inti) && (max(inti) >= 3 || di_amar)
  umum <- str_count(t, regex(POLA_BBM_UMUM, ignore_case = TRUE))
  lpg <- str_detect(t, regex(POLA_NON_BBM[["LPG/gas"]], ignore_case = TRUE))
  mentah <- str_detect(t, "MENTAH") || str_detect(t, regex("crude\\s+oil|kondensat", ignore_case = TRUE))
  if (kuat) return("Ya")
  if (umum >= 2 && !lpg && !mentah) return("Ya")
  if (mentah) return("Sebagian (minyak mentah)")
  if (lpg) return("Tidak (LPG/gas)")
  if (length(inti) || umum) return("Perlu dicek (sebutan BBM sedikit)")
  "Tidak"
}

barang_bbm <- function(amar, teks) {
  # Jenis BBM objek perkara: utamakan yang disebut di amar (barang bukti), lalu seluruh teks.
  sumber <- if (!is.na(amar) && length(hitung_bbm(amar))) amar else teks
  n <- hitung_bbm(sumber)
  if (!length(n)) {
    if (str_detect(sumber %||% "", regex(POLA_BBM_UMUM, ignore_case = TRUE))) return("BBM (jenis tidak disebut)")
    return(NA_character_)
  }
  # Jenis yang hanya disebut sekilas (< 1/4 sebutan jenis utama) dianggap bukan objek perkara.
  n <- n[n >= max(1, n[1] / 4)]
  jenis <- names(n)
  # Biosolar adalah solar (B30/B35): satukan agar tidak tercatat sebagai dua barang.
  if (all(c("Biosolar", "Solar") %in% jenis)) jenis <- setdiff(jenis, "Biosolar")
  # "Premium (bensin)": bensin bukan jenis tersendiri bila jenis bensin tertentu sudah disebut.
  if (any(c("Premium", "Pertalite", "Pertamax") %in% jenis)) jenis <- setdiff(jenis, "Bensin (jenis tidak disebut)")
  t <- str_to_lower(str_squish(sumber))
  label <- vapply(jenis, function(j) {
    pos <- str_locate_all(t, regex(POLA_BBM[[j]]))[[1]]
    sekitar <- str_sub(t, pmax(1, pos[, 1] - 120), pos[, 2] + 120)
    nama <- if (j == "Solar" && "Biosolar" %in% names(n)) "Solar/Biosolar" else j
    # "Perindustrian" bukan "industri"; "bukanlah solar yang bersubsidi" = non-subsidi.
    non <- str_detect(sekitar, "\\bnon[- ]?subsidi|solar\\s+industri|\\bindustri\\b|\\bbukan(lah)?\\b[^.;]{0,50}\\b(ber)?subsidi")
    sub <- str_detect(sekitar, "subsidi")
    if (any(non)) paste0(nama, " (non-subsidi)") else if (any(sub)) paste0(nama, " (subsidi)") else nama
  }, "")
  paste(unname(label), collapse = "; ")
}

POLA_ANGKA <- "(\\d{1,3}(?:\\.\\d{3})+(?:,\\d+)?|\\d+(?:,\\d+)?)"
POLA_VOLUME <- paste0(POLA_ANGKA, "(?:\\s*\\([^()]{0,120}\\))?\\s*(kilo\\s*liter|kiloliter|k\\.?l\\b|liter|ltr\\b|lt\\b|l\\b|ton\\b|m3\\b)")
KATA_BBM_KONTEKS <- paste(c(POLA_BBM, POLA_BBM_UMUM), collapse = "|")

volume_bbm <- function(teks) {
  # Semua sebutan volume yang berkaitan dengan BBM (bukan kapasitas wadah, bukan angka di dokumen), liter/ton.
  kosong <- tibble(nilai = numeric(), satuan = character(), konteks = character(), skor = numeric())
  if (is.na(teks) || !nzchar(teks)) return(kosong)
  m <- str_locate_all(teks, regex(POLA_VOLUME, ignore_case = TRUE))[[1]]
  if (!nrow(m)) return(kosong)
  g <- str_match(str_sub(teks, m[, 1], m[, 2]), regex(POLA_VOLUME, ignore_case = TRUE))
  nilai <- angka_id(g[, 2])
  satuan <- str_remove_all(str_to_lower(g[, 3]), "\\s")
  nilai <- ifelse(str_detect(satuan, "^k|^m3"), nilai * 1000, nilai)
  satuan <- ifelse(satuan == "ton", "ton", "liter")
  sebelum <- str_to_lower(str_squish(str_sub(teks, pmax(1, m[, 1] - 40), m[, 1] - 1)))
  klausa <- map_chr(str_split(sebelum, "[;,]|\\bdan\\b"), ~ tail(.x, 1))
  # "kapasitas 200 liter", "@ 20 liter", "ukuran 35 liter" = wadah; "berisi 30 liter" = isi (bukan kapasitas).
  kapasitas <- str_detect(klausa, "kapasitas|ukuran|(?<!ber)isi\\s*$|volume\\s*$|@") & !str_detect(klausa, "berisi\\s*(\\S+\\s*){0,4}$")
  dokumen <- str_detect(str_to_lower(str_sub(teks, pmax(1, m[, 1] - 90), m[, 1] - 1)),
                        "lembar|faktur|invoice|delivery|\\bdo\\b|nota\\b|kwitansi|kuitansi|surat jalan|berita acara|\\bpo\\b|purchase|dokumen|laporan|rekening|pesanan|pemesanan|order|struk|rekomendasi|alokasi|sounding")
  konteks <- str_to_lower(str_squish(str_sub(teks, pmax(1, m[, 1] - 150), m[, 2] + 100)))
  terkait <- str_detect(konteks, regex(KATA_BBM_KONTEKS, ignore_case = TRUE))
  # Skor untuk cadangan "angka di uraian perkara": barang yang disita didahulukan, rencana/pesanan dihindari.
  skor <- 2 * str_detect(konteks, "disita|diamankan|barang bukti|ditemukan|dirampas|tertangkap|kedapatan") -
    2 * str_detect(konteks, "pesan|permintaan|order|rencana|alokasi|kuota|menjual .{0,30}sebanyak|dijual sebanyak|setiap bulan|per bulan|per hari|setiap hari")
  tibble(nilai = nilai, satuan = satuan, konteks = str_squish(str_sub(teks, pmax(1, m[, 1] - 60), m[, 2] + 40)),
         kapasitas = kapasitas, terkait = terkait, dokumen = dokumen, skor = skor) |>
    filter(!is.na(nilai), nilai > 0, !kapasitas, !dokumen, terkait) |>
    select(nilai, satuan, konteks, skor)
}

POLA_WADAH <- "(?:jerigen|jeriken|jirigen|derigen|dirigen|drum|galon|tandon|baby\\s*tank|botol|tong|kempu|ember)"
POLA_KALI <- paste0("(\\d+)\\s*(?:\\([^()]{0,40}\\))?\\s*(?:buah\\s+|unit\\s+)?", POLA_WADAH,
                    "[^;\\n]{0,100}?(?:masing-masing|masing masing|setiap|tiap)\\s*(?:", POLA_WADAH, "\\s*)?(?:berisi(?:kan)?|isi)?\\s*",
                    "(?:[a-z ]{0,40}?)(?:sebanyak|kurang lebih|±|\\+/-)?\\s*", POLA_ANGKA, "\\s*(?:\\([^()]{0,60}\\))?\\s*(liter|ltr|lt|l)\\b")
POLA_DOKUMEN_ITEM <- paste0("^\\W*(?:\\d+\\s*(?:\\([^()]{0,30}\\))?\\s*)?(?:buah|lembar|bundel|rangkap|eksemplar|set)?\\s*",
                            "(?:lembar|struk|surat|nota|faktur|invoice|kwitansi|kuitansi|delivery|do\\b|rekomendasi|buku|blangko|",
                            "berita\\s+acara|print\\s*out|sounding|bukti|dokumen|laporan|rekening|fotokopi|foto\\s*copy|copy|salinan|",
                            "daftar|catatan|tiket|karcis|kartu|uang|stnk|bpkb|kunci|handphone|hp\\b|telepon)")

butir_barang_bukti <- function(teks) {
  # Pecah daftar barang bukti per butir: baris diawali "-", "•", "1.", "1)", "a." atau dipisah ";".
  b <- str_split(teks, "(?:\\n\\s*(?:[-•−–]|\\d{1,2}[.)]|[a-z][.)])\\s+)|;")[[1]]
  str_squish(b[nzchar(str_trim(b))])
}

volume_butir <- function(teks) {
  # Satu angka per butir barang bukti: jumlah wadah x isi bila "N jerigen masing-masing berisi X liter",
  # selain itu angka terbesar di butir itu (agar "total X liter (a + b)" tidak terhitung ganda).
  hasil <- list()
  for (b in butir_barang_bukti(teks)) {
    bl <- str_to_lower(b)
    if (str_detect(str_sub(bl, 1, 80), POLA_DOKUMEN_ITEM)) next
    if (!str_detect(bl, regex(KATA_BBM_KONTEKS, ignore_case = TRUE))) next
    k <- str_match(bl, POLA_KALI)
    if (!is.na(k[1, 1])) {
      hasil[[length(hasil) + 1]] <- tibble(nilai = angka_id(k[1, 2]) * angka_id(k[1, 3]), satuan = "liter",
                                           konteks = paste0(k[1, 2], " x ", k[1, 3], " liter: ", str_sub(b, 1, 120)))
      next
    }
    v <- volume_bbm(b)
    if (!nrow(v)) next
    s <- if (any(v$satuan == "liter")) "liter" else "ton"
    x <- unique(v$nilai[v$satuan == s])
    # Beberapa angka dalam satu butir dijumlah (mis. tangki 200 L + tangki 400 L), kecuali satu angka adalah
    # total dari yang lain ("total 1.210 liter (4 drum 860 + 10 jeriken 350)").
    total <- x[vapply(seq_along(x), function(i) length(x) > 1 && abs(x[i] - sum(x[-i])) <= 0.01 * x[i], TRUE)]
    nilai <- if (length(total)) max(total) else sum(x)
    hasil[[length(hasil) + 1]] <- tibble(nilai = nilai, satuan = s, konteks = str_sub(b, 1, 120))
  }
  bind_rows(hasil)
}

angka_teks <- function(x) vapply(x, function(v) format(v, big.mark = ".", decimal.mark = ",", scientific = FALSE, trim = TRUE), "")

nilai_volume <- function(amar, teks) {
  # Prioritas: (1) butir barang bukti BBM di amar; (2) daftar "barang bukti berupa ..." terakhir sebelum amar
  # (putusan PT/MA mengutip amar/tuntutan sebelumnya); (3) angka di uraian perkara dengan konteks penyitaan.
  ringkas <- function(v, dasar) {
    s <- if (any(v$satuan == "liter")) "liter" else "ton"
    v <- v[v$satuan == s, ]
    list(nilai = sum(v$nilai), satuan = s, dasar = paste0(dasar, ": ", paste(angka_teks(v$nilai), collapse = " + "), " ", s))
  }
  v <- volume_butir(amar %||% "")
  if (nrow(v)) return(ringkas(v, "jumlah barang bukti BBM di amar"))
  p <- posisi_amar(teks %||% "")
  badan <- if (is.null(p)) teks else str_sub(teks, 1, p[1])
  bb <- str_locate_all(badan %||% "", regex("barang\\s+bukti\\s+berupa", ignore_case = TRUE))[[1]]
  if (nrow(bb)) {
    awal <- bb[nrow(bb), 2]
    potong <- str_sub(badan, awal, awal + 3000)
    henti <- str_locate(potong, regex("Membebankan|biaya perkara|Menimbang", ignore_case = TRUE))[1, 1]
    if (!is.na(henti)) potong <- str_sub(potong, 1, henti)
    v <- volume_butir(potong)
    if (nrow(v)) return(ringkas(v, "jumlah barang bukti BBM yang dikutip dari putusan/tuntutan sebelumnya"))
  }
  v <- volume_bbm(teks)
  # "27 jerigen masing-masing berisi 30 liter" di uraian perkara juga dihitung (27 x 30).
  kali <- str_match_all(str_to_lower(str_squish(teks %||% "")), POLA_KALI)[[1]]
  if (nrow(kali)) {
    v <- bind_rows(v, tibble(nilai = angka_id(kali[, 2]) * angka_id(kali[, 3]), satuan = "liter",
                             konteks = paste0(kali[, 2], " x ", kali[, 3], " liter: ", str_sub(kali[, 1], 1, 100)), skor = 1))
    v <- v[!is.na(v$nilai) & v$nilai > 0, ]
  }
  if (nrow(v)) {
    s <- if (any(v$satuan == "liter")) "liter" else "ton"
    v <- v[v$satuan == s, ]
    v <- v[v$skor == max(v$skor), ]
    i <- which.max(v$nilai)
    return(list(nilai = v$nilai[i], satuan = s, dasar = paste0("angka di uraian perkara (konteks penyitaan didahulukan): \"", v$konteks[i], "\"")))
  }
  list(nilai = NA_real_, satuan = NA_character_, dasar = NA_character_)
}

POLA_RUPIAH <- "Rp\\.?\\s*(\\d{1,3}(?:\\s?\\.\\s?\\d{3})+(?:,\\d{1,2})?|\\d+(?:,\\d{1,2})?)"
POLA_USD <- "(?:USD|US\\s?\\$|\\$)\\s*(\\d{1,3}(?:[.,]\\d{3})+(?:[.,]\\d{1,2})?|\\d+(?:[.,]\\d{1,2})?)"
KATA_RUPIAH <- c(kerugian_negara = "kerugian\\s+(?:keuangan\\s+)?negara", hasil_lelang = "lelang|hasil\\s+penjualan\\s+(?:barang\\s+bukti|langsung)|penjualan\\s+langsung",
                 biaya_perkara = "biaya\\s+perkara", denda = "denda", keuntungan = "keuntungan|untung|laba|upah|imbalan",
                 nilai_transaksi = "harga|seharga|dijual|menjual|membeli|dibeli|senilai|nilai|total")

jenis_nominal <- function(sebelum, sesudah) {
  # Teks PDF terpotong per baris (~70 karakter): baris baru diperlakukan sebagai spasi agar kata kunci
  # di baris sebelumnya tetap terbaca; klausa dipisah hanya dengan ";".
  b <- str_to_lower(str_squish(sebelum))
  b <- tail(str_split(b, ";")[[1]], 1)
  b <- str_sub(b, -120)
  s <- str_remove(str_to_lower(str_squish(sesudah)), "^[\\s,.\\-]*(\\([^()]{0,60}\\))?")
  fee <- "keuntungan|untung|laba|selisih|upah|imbalan|ongkos|biaya|bayar|bayaran|membayar|titip|sewa|jasa|komisi|fee|insentif|transport"
  per_wadah <- "^\\s*(,-|,00)?\\s*(/\\s*|per\\s*|setiap\\s*|tiap\\s*)(jerigen|jeriken|jirigen|drum|galon|botol|tandon|tong|kempu|ember)"
  per_liter <- "^\\s*(,-|,00)?\\s*(/\\s*(liter|ltr|l\\b)|per\\s*liter|perliter|setiap\\s*liter|tiap\\s*liter)"
  if (str_detect(s, per_wadah)) return("harga_per_wadah")
  # "per liter Rp X" (harga ditulis setelah satuan) juga harga per liter.
  if (str_detect(s, per_liter) || str_detect(str_sub(b, -40), "per\\s*liter(nya)?\\s*(seharga|sebesar|yaitu|adalah|:)?\\s*$")) {
    dekat <- str_sub(b, -70)
    return(if (str_detect(dekat, fee)) "keuntungan_per_liter" else "harga_per_liter")
  }
  posisi <- vapply(KATA_RUPIAH, function(p) { l <- str_locate_all(b, p)[[1]]; if (nrow(l)) max(l[, 1]) else -1 }, 0)
  if (all(posisi < 0)) "lain" else names(which.max(posisi))
}

nominal_uang <- function(teks) {
  kosong <- tibble(nilai = numeric(), mata_uang = character(), jenis = character(), konteks = character())
  if (is.na(teks) || !nzchar(teks)) return(kosong)
  angka_usd <- function(g) vapply(g, function(x) {
    x <- str_remove(str_trim(x), "[.,]+$")
    # Putusan Indonesia memakai titik ribuan juga untuk USD ("USD 25.000" = 25 ribu dolar).
    if (str_detect(x, "^\\d{1,3}(\\.\\d{3})+(,\\d+)?$") || str_detect(x, "^\\d+,\\d{1,2}$")) return(angka_id(x))
    if (str_detect(x, "^\\d{1,3}(,\\d{3})+(\\.\\d+)?$")) return(as.numeric(str_remove_all(x, ",")))
    suppressWarnings(as.numeric(x))
  }, 0, USE.NAMES = FALSE)
  ambil <- function(pola, mu) {
    m <- str_locate_all(teks, regex(pola, ignore_case = mu == "IDR"))[[1]]
    if (!nrow(m)) return(kosong)
    g <- str_match(str_sub(teks, m[, 1], m[, 2]), regex(pola, ignore_case = mu == "IDR"))[, 2]
    nilai <- if (mu == "IDR") angka_id(g) else angka_usd(g)
    tibble(nilai = nilai, mata_uang = mu,
           jenis = map2_chr(str_sub(teks, pmax(1, m[, 1] - 200), m[, 1] - 1), str_sub(teks, m[, 2] + 1, m[, 2] + 80), jenis_nominal),
           konteks = str_squish(str_sub(teks, pmax(1, m[, 1] - 80), m[, 2] + 30)))
  }
  bind_rows(ambil(POLA_RUPIAH, "IDR"), ambil(POLA_USD, "USD")) |> filter(!is.na(nilai), nilai > 0)
}

nilai_kerugian <- function(teks, volume) {
  # Urutan prioritas (sama dengan rekap manual):
  #  (a) kerugian negara yang disebut putusan; (b) nilai BBM yang disebut putusan (hasil lelang barang bukti);
  #  (c) volume x harga per liter yang disebut putusan (dihitung; harga beli/SPBU didahulukan);
  #  (d) nilai transaksi BBM yang disebut putusan; (e) NA. Denda, biaya perkara, laba dan upah BUKAN kerugian.
  u <- nominal_uang(teks)
  pilih <- function(j) {
    k <- u[u$jenis == j, ]
    if (nrow(k) && any(k$mata_uang == "IDR") && any(k$mata_uang != "IDR")) k <- k[k$mata_uang == "IDR", ]
    k
  }
  hasil <- function(k, dasar) { i <- which.max(k$nilai); list(nilai = k$nilai[i], mata_uang = k$mata_uang[i], dasar = paste0(dasar, ": \"", k$konteks[i], "\"")) }
  k <- pilih("kerugian_negara")
  if (nrow(k)) return(hasil(k, "kerugian negara disebut putusan"))
  k <- pilih("hasil_lelang")
  if (nrow(k)) return(hasil(k, "hasil lelang/penjualan barang bukti BBM"))
  h <- u[u$jenis == "harga_per_liter" & u$mata_uang == "IDR" & u$nilai >= 1000 & u$nilai <= 50000, ]
  if (nrow(h) && !is.na(volume$nilai) && identical(volume$satuan, "liter")) {
    beli <- h[str_detect(str_to_lower(h$konteks), "beli|membeli|dibeli|spbu|spbn|spdn|het|eceran tertinggi|subsidi"), ]
    if (nrow(beli)) { harga <- min(beli$nilai); asal <- "harga beli" }
    else { frek <- table(h$nilai); harga <- as.numeric(names(frek)[which.max(frek)]); asal <- "harga per liter yang paling sering disebut" }
    return(list(nilai = round(volume$nilai * harga), mata_uang = "IDR",
                dasar = paste0("dihitung: volume ", volume$nilai, " liter x ", asal, " Rp", harga, "/liter (\"", h$konteks[h$nilai == harga][1], "\")")))
  }
  k <- pilih("nilai_transaksi")
  k <- k[str_detect(k$konteks, regex(KATA_BBM_KONTEKS, ignore_case = TRUE)), ]
  if (nrow(k)) return(hasil(k, "nilai transaksi BBM disebut putusan"))
  list(nilai = NA_real_, mata_uang = NA_character_, dasar = NA_character_)
}

tahun_kejadian <- function(teks, tahun_putusan = NA) {
  p <- posisi_amar(teks)
  badan <- if (is.null(p)) teks else str_sub(teks, 1, p[1])
  # Dakwaan oditur militer menulis "tahun 2000 dua puluh empat" (= 2024).
  satuan <- c(satu = 1, dua = 2, tiga = 3, empat = 4, lima = 5, enam = 6, tujuh = 7, delapan = 8, sembilan = 9)
  badan <- str_replace_all(badan, regex("\\b2000\\s+dua\\s+puluh(\\s+(satu|dua|tiga|empat|lima|enam|tujuh|delapan|sembilan))?\\b", ignore_case = TRUE),
                           function(m) as.character(2020 + (satuan[str_to_lower(str_match(m, "puluh\\s+(\\w+)")[, 2])] %||% 0)))
  pola <- c(paste0("pada\\s+hari\\s+\\w+,?\\s+tanggal\\s+\\d{1,2}\\s+(?:", POLA_BULAN, ")\\.?\\s+(\\d{4})"),
            paste0("(?:dalam|pada|sekitar)\\s+bulan\\s+(?:", POLA_BULAN, ")\\s+(?:tahun\\s+)?(\\d{4})"),
            "setidak-tidaknya\\s+(?:pada\\s+)?(?:suatu\\s+)?(?:waktu\\s+)?(?:dalam\\s+)?tahun\\s+(\\d{4})")
  th <- as.integer(unlist(lapply(pola, function(q) str_match_all(badan, regex(q, ignore_case = TRUE))[[1]][, 2])))
  batas <- if (is.na(tahun_putusan)) 2100 else tahun_putusan
  bawah <- if (is.na(tahun_putusan)) 1990 else tahun_putusan - 15
  th <- th[!is.na(th) & th >= bawah & th <= batas]
  if (!length(th)) return(NA_character_)
  frek <- table(th)
  utama <- as.integer(names(frek)[frek >= max(2, max(frek) %/% 3)])
  if (!length(utama)) utama <- as.integer(names(frek)[which.max(frek)])
  if (min(utama) == max(utama)) as.character(min(utama)) else paste0(min(utama), "-", max(utama))
}

pengadilan_dari_teks <- function(teks) {
  # Pengadilan tingkat pertama yang disebut di teks (untuk PT/MA atau PDF tanpa overview). Kandidat hanya
  # diterima bila namanya dikenal di tabel pengadilan (menghindari "PN PERPANJANGAN OLEH KETUA ...").
  t <- str_squish(teks %||% "")
  henti <- c("NOMOR", "NO", "TANGGAL", "REGISTER", "KELAS", "YANG", "KARENA", "DALAM", "PADA", "SEJAK", "DI",
             "DIBAWAH", "TERSEBUT", "DENGAN", "UNTUK", "ATAS", "TELAH", "PERPANJANGAN", "OLEH", "KETUA", "HAKIM",
             "PENGADILAN", "PERTAMA", "KEDUA", "PENAHANAN", "SEBAGAI", "DAN", "ATAU")
  awal <- str_locate_all(t, "Pengadilan Negeri\\s+")[[1]][, 2]
  for (a in awal) {
    cand <- str_match(str_sub(t, a + 1, a + 80), "^((?:[A-Z][A-Za-z.\\-]*\\s?){1,5})")[, 2]
    if (is.na(cand)) next
    kata <- str_split(str_trim(cand), "\\s+")[[1]]
    stop_i <- which(toupper(str_remove_all(kata, "[.,]")) %in% henti)
    if (length(stop_i)) kata <- kata[seq_len(stop_i[1] - 1)]
    if (!length(kata)) next
    nama <- paste("PN", toupper(paste(str_remove_all(kata, "[.,]"), collapse = " ")))
    if (!is.na(provinsi_pengadilan(nama))) return(nama)
  }
  NA_character_
}

lokasi_kejadian <- function(teks) {
  # Tempat perbuatan menurut dakwaan/fakta: frasa "bertempat di ..." / "bertempat disebuah ..." (berhenti di
  # "atau setidak-tidaknya", "atau pada suatu tempat", "yang masih termasuk ...").
  p <- posisi_amar(teks)
  badan <- str_squish(if (is.null(p)) teks else str_sub(teks, 1, p[1]))
  m <- str_match(badan, regex("bertempat\\s*di\\s*(.{5,260}?)(?:,?\\s*atau\\s+(?:setidak|pada\\s+suatu|di\\s+suatu|sekurang)|,?\\s*setidak-tidaknya|\\s*yang\\s+masih\\s+termasuk|\\s*dalam\\s+daerah\\s+hukum)", ignore_case = TRUE))[, 2]
  if (is.na(m)) m <- str_match(badan, regex("bertempat\\s*di\\s*([^.;]{5,200})", ignore_case = TRUE))[, 2]
  if (is.na(m)) return(list(lokasi = NA_character_, kab_kota = NA_character_, provinsi = NA_character_))
  lok <- str_remove(str_squish(m), "[,;. ]+$")
  # Nama bisa terpotong spasi palsu dari PDF ("Tan ah Laut"), jadi kata huruf kecil diterima sampai tanda baca.
  kab <- str_match(lok, "\\b(Kabupaten|Kab\\.?|Kota)\\s+([A-Z][A-Za-z]*(?:\\s+[A-Za-z]+){0,3}?)(?=\\s*(?:[,.;]|Provinsi|Prov\\b|Kecamatan|Desa|$))")[, 2:3]
  prov <- str_match(lok, "\\b(?:Provinsi|Prov\\.?)\\s+([A-Z][A-Za-z]+(?:\\s+[A-Z][A-Za-z]+){0,2})")[, 2]
  kab_kota <- if (is.na(kab[2])) NA_character_ else paste(ifelse(str_detect(kab[1], "^Kota"), "Kota", "Kabupaten"), kab[2])
  list(lokasi = lok, kab_kota = kab_kota, provinsi = prov)
}

LEWATI_NAMA <- c("Tersebut", "Telah", "Tidak", "Dan", "Dengan", "Pada", "Di", "Ke", "Yang", "Untuk", "Oleh", "Juga",
                 "Sebagai", "Penuntut", "Pemohon", "Umum", "Kasasi", "Bersama", "Membeli", "Menjual", "Mengangkut",
                 "Menyimpan", "Melakukan", "Dari", "Dalam", "Atas", "Ini", "Itu", "Lain", "Lainnya", "Para", "Mana",
                 "Ahli", "Verbalisan", "Mahkota", "Negara", "Pertamina", "PT", "CV", "UD", "KUD", "SPBU", "SPBN", "SPDN",
                 "Koperasi", "Desa", "Dusun", "Jorong", "Kelurahan", "Kecamatan", "Kabupaten", "Kota", "Jalan", "Jl",
                 "Gudang", "Toko", "Pasar", "Pelabuhan", "Dermaga", "Perairan", "Kapal", "KM", "Polres", "Polda", "Polsek")
# Kata tempat menghentikan nama: "Rumah Terdakwa Budi Desa X" -> "Rumah Terdakwa [nama] Desa X".
KATA_TEMPAT <- "(?:Desa|Dusun|Jorong|Nagari|Kelurahan|Kel|Kecamatan|Kec|Kabupaten|Kab|Kota|Jalan|Jl|RT|RW|Gampong|Kampung|Provinsi|Prov|Pelabuhan|Dermaga|SPBU|SPBN|SPDN|PT|CV|UD|KUD|Gudang|Toko|Pasar|Perairan|Sungai|Kapal|KM)\\b"
POLA_NAMA <- paste0(
  "\\b((?i:terdakwa|terpidana|tersangka|saksi|sdr\\.?|sdri\\.?|saudara|saudari|atas\\s+nama|a\\.n\\.?|milik|bin|binti|als\\.?|alias))",
  "(\\s+(?:[IVX]{1,4}|\\d{1,2})\\b)?\\s+",
  "((?!", KATA_TEMPAT, ")[A-Z][A-Za-z'.\\-]*(?:\\s+(?!", KATA_TEMPAT, ")(?:[A-Z][A-Za-z'.\\-]*|(?i:bin|binti|als\\.?|alias)))*)")

samarkan_nama <- function(x) {
  # Nama orang setelah terdakwa/terpidana/saksi/Sdr./milik/atas nama/bin/alias (termasuk "Terdakwa I NAMA")
  # diganti [nama]. Dijalankan pada teks lengkap sebelum potongan teks diambil, agar tidak ada nama terpotong.
  if (is.null(x) || length(x) == 0 || is.na(x)) return(x)
  str_replace_all(x, POLA_NAMA, function(m) {
    g <- str_match(m, POLA_NAMA)
    pertama <- str_remove(word(g[, 4], 1), "[.,]$")
    if (pertama %in% LEWATI_NAMA) m else paste0(g[, 2], g[, 3] %|na|% "", " [nama]")
  })
}
`%|na|%` <- function(a, b) ifelse(is.na(a), b, a)

# -----------------------------------------------------------------------------
# 6. REKAP SATU PUTUSAN
# -----------------------------------------------------------------------------
KOLOM_REKAP <- c("tahun_putusan", "tahun_kejadian", "tingkat_persidangan", "hasil_putusan", "lokasi_kejadian",
                 "barang_bbm", "nilai_kerugian_uang", "mata_uang", "nilai_kerugian_volume", "satuan_volume",
                 "nomor_putusan", "pengadilan", "tanggal_putusan", "provinsi", "kabupaten_kota", "dasar_lokasi",
                 "dasar_hasil", "dasar_nilai_uang", "dasar_volume", "relevan_bbm", "jenis_bbm_disebut",
                 "klasifikasi", "sumber_data", "lampiran_pdf", "file_pdf", "url_putusan", "sumber_daftar")

PETA_AMAR <- c("PIDANA PENJARA" = "Bersalah", "PENJARA" = "Bersalah", "DENDA" = "Bersalah", "BERSYARAT" = "Bersalah",
               "PIDANA" = "Bersalah", "BEBAS" = "Tidak bersalah", "LEPAS" = "Tidak bersalah")

hasil_dari_amar_overview <- function(amar) {
  # Kolom terstruktur "Amar" di overview (mis. "PIDANA PENJARA WAKTU TERTENTU", "BEBAS", "LEPAS", "Tolak", "Lain-lain").
  a <- toupper(amar %||% "")
  for (k in names(PETA_AMAR)) if (str_detect(a, fixed(k))) return(c(PETA_AMAR[[k]], paste0("kolom Amar overview: ", amar)))
  c(NA, NA)
}

rekap_putusan <- function(ov = list(), teks = NA_character_, file_pdf = NA_character_, sumber_daftar = NA_character_) {
  ada_pdf <- !is.na(teks) && nchar(teks) > 500
  # Nama orang disamarkan di seluruh teks sebelum potongan teks diambil untuk kolom CSV.
  if (ada_pdf) teks <- samarkan_nama(teks)
  for (k in c("catatan_amar", "amar_lainnya", "abstrak")) if (!is.null(ov[[k]])) ov[[k]] <- samarkan_nama(ov[[k]])
  teks_ov <- paste(na.omit(c(ov$catatan_amar, ov$amar_lainnya, ov$abstrak, ov$kata_kunci)), collapse = "\n")
  teks_kerja <- if (ada_pdf) teks else teks_ov
  amar <- if (ada_pdf) amar_dari_teks(teks) else (ov$catatan_amar %||% NA_character_)
  if (ada_pdf && is.na(amar)) amar <- ov$catatan_amar %||% NA_character_

  nomor <- ov$nomor %||% (if (ada_pdf) nomor_dari_teks(teks) else NA_character_)
  tgl <- parse_tanggal(ov$tanggal_dibacakan %||% "")
  if (is.na(tgl) && ada_pdf) tgl <- tanggal_putusan_teks(teks)
  if (is.na(tgl)) tgl <- parse_tanggal(ov$tanggal_musyawarah %||% "")
  tahun_put <- if (!is.na(tgl)) as.integer(format(tgl, "%Y")) else suppressWarnings(as.integer(substr(ov$tahun %||% NA, 1, 4)))

  tingkat <- tingkat_dari_nomor(nomor)
  if (is.na(tingkat)) tingkat <- switch(toupper(ov$jenis_lembaga_peradilan %||% ""), PN = "PN", PT = "PT", MA = "MA", NA_character_)

  pengadilan <- toupper(ov$lembaga_peradilan %||% NA_character_)
  if (is.na(pengadilan) && ada_pdf) {
    if (identical(tingkat, "MA")) {
      pengadilan <- "MAHKAMAH AGUNG"
    } else {
      kepala <- str_squish(substr(teks, 1, 1500))
      p <- str_match(kepala, "(Pengadilan (?:Negeri|Tinggi) [A-Z][A-Za-z ]+?)\\s+(?:yang|Kelas|telah)")[, 2]
      if (!is.na(p)) pengadilan <- str_replace(str_replace(toupper(p), "^PENGADILAN NEGERI", "PN"), "^PENGADILAN TINGGI", "PT")
    }
  }

  h <- hasil_putusan(amar)
  if (is.na(h[1]) && ada_pdf && str_detect(h[2], "ikut putusan sebelumnya")) {
    h2 <- hasil_dari_kutipan(teks)
    if (!is.na(h2[1])) h <- c(h2[1], paste0(h[2], "; ", h2[2]))
  }
  if (is.na(h[1]) && !ada_pdf) {
    h2 <- hasil_dari_amar_overview(ov$amar)
    if (!is.na(h2[1])) h <- h2
  }
  vol <- nilai_volume(amar, teks_kerja)
  uang <- nilai_kerugian(teks_kerja, vol)

  # Lokasi: tempat perbuatan menurut dakwaan/fakta di PDF; bila tidak terbaca, lokasi pengadilan tingkat
  # pertama (untuk PT/MA diambil dari pengadilan asal yang disebut di teks), sesuai permintaan kajian.
  asal <- if (tingkat %in% c("PN", "Pengadilan Militer") || !ada_pdf) pengadilan else (pengadilan_dari_teks(teks) %||% pengadilan)
  if (!is.na(asal) && asal == "MAHKAMAH AGUNG") asal <- NA_character_
  lok <- if (ada_pdf) lokasi_kejadian(teks) else list(lokasi = NA_character_, kab_kota = NA_character_, provinsi = NA_character_)
  dasar_lok <- "teks putusan (bertempat di ...)"
  if (is.na(lok$lokasi)) {
    lok$lokasi <- if (is.na(asal)) NA_character_ else paste("Wilayah hukum", asal)
    dasar_lok <- if (is.na(asal)) NA_character_ else "lokasi pengadilan (tempat kejadian tidak terbaca)"
  }
  if (is.na(lok$provinsi)) lok$provinsi <- provinsi_pengadilan(asal)

  n_bbm <- hitung_bbm(teks_kerja)
  relevan <- relevansi_bbm(teks_kerja, amar)
  # Overview tanpa PDF sering tidak menyebut jenis BBM (mis. "Menolak permohonan kasasi ..."). Bila putusan
  # ditemukan lewat pencarian kata kunci BBM atau klasifikasi Migas, jangan dibuang: tandai untuk dicek.
  if (!ada_pdf && !relevan %in% c("Ya", "Tidak (LPG/gas)", "Sebagian (minyak mentah)") &&
      (str_detect(ov$klasifikasi %||% "", regex("migas", ignore_case = TRUE)) ||
       str_detect(sumber_daftar %||% "", "^pencarian") || str_detect(ov$kata_kunci %||% "", regex(POLA_BBM_UMUM, ignore_case = TRUE))))
    relevan <- "Perlu dicek (tanpa PDF)"
  tibble(
    tahun_putusan = tahun_put,
    tahun_kejadian = if (ada_pdf) tahun_kejadian(teks, tahun_put) else NA_character_,
    tingkat_persidangan = tingkat,
    hasil_putusan = h[1],
    lokasi_kejadian = lok$lokasi,
    barang_bbm = barang_bbm(amar, teks_kerja),
    nilai_kerugian_uang = uang$nilai,
    mata_uang = uang$mata_uang,
    nilai_kerugian_volume = vol$nilai,
    satuan_volume = vol$satuan,
    nomor_putusan = nomor,
    pengadilan = pengadilan,
    tanggal_putusan = format_tanggal(tgl),
    provinsi = lok$provinsi,
    kabupaten_kota = lok$kab_kota,
    dasar_lokasi = dasar_lok,
    dasar_hasil = h[2],
    dasar_nilai_uang = uang$dasar,
    dasar_volume = vol$dasar,
    relevan_bbm = relevan,
    jenis_bbm_disebut = if (length(n_bbm)) paste0(names(n_bbm), " (", n_bbm, ")", collapse = "; ") else NA_character_,
    klasifikasi = ov$klasifikasi %||% NA_character_,
    sumber_data = if (ada_pdf) "PDF putusan" else "Overview direktori",
    lampiran_pdf = ov$lampiran_pdf %||% (if (ada_pdf) "Ada" else NA_character_),
    file_pdf = file_pdf,
    url_putusan = ov$url %||% NA_character_,
    sumber_daftar = sumber_daftar
  )
}

# -----------------------------------------------------------------------------
# 7. PENGUMPULAN URL DAN PENELUSURAN
# -----------------------------------------------------------------------------
kumpulkan_pencarian <- function(cfg, folder_cache) {
  hasil <- list()
  ambil <- function(u) tryCatch(ambil_html(u, cfg, folder_cache, jenis = "daftar"),
                                captcha_error = function(e) e,
                                error = function(e) { pesan("  ", conditionMessage(e)); NULL })
  for (q in cfg$kata_kunci) for (th in cfg$tahun) {
    u1 <- url_pencarian(q, th, 1, cfg)
    html <- ambil(u1)
    if (inherits(html, "captcha_error")) {
      pesan("PENCARIAN DIHENTIKAN: ", conditionMessage(html))
      return(bind_rows(hasil))
    }
    if (is.null(html)) next
    akhir <- min(halaman_terakhir(html, u1), cfg$maks_halaman)
    pesan("pencarian '", q, "' tahun ", th, ": ", akhir, " halaman")
    for (pg in seq_len(akhir)) {
      if (pg > 1) {
        html <- ambil(url_pencarian(q, th, pg, cfg))
        if (inherits(html, "captcha_error")) {
          pesan("PENCARIAN DIHENTIKAN: ", conditionMessage(html))
          return(bind_rows(hasil))
        }
        if (is.null(html)) next
      }
      d <- parse_daftar(html, u1)
      if (nrow(d)) hasil[[length(hasil) + 1]] <- mutate(d, sumber_daftar = paste0("pencarian: ", q))
    }
  }
  bind_rows(hasil)
}

kumpulkan_kategori <- function(cfg, folder_cache) {
  hasil <- list()
  ambil <- function(u) tryCatch(ambil_html(u, cfg, folder_cache, jenis = "daftar"),
                                captcha_error = function(e) e,
                                error = function(e) { pesan("  ", conditionMessage(e)); NULL })
  for (kat in cfg$kategori) for (th in cfg$tahun) {
    u <- url_filter_tahun(kat, th)
    html <- ambil(u)
    if (inherits(html, "captcha_error")) { pesan("DAFTAR KATEGORI DIHENTIKAN: ", conditionMessage(html)); return(bind_rows(hasil)) }
    if (is.null(html)) next
    akhir <- min(halaman_terakhir(html, u), cfg$maks_halaman)
    nama <- str_remove(str_extract(kat, "kategori/[^/]+$"), "\\.html$")
    pesan(nama, " tahun ", th, ": ", akhir, " halaman")
    for (pg in seq_len(akhir)) {
      if (pg > 1) {
        html <- ambil(url_halaman_direktori(u, pg))
        if (inherits(html, "captcha_error")) { pesan("DAFTAR KATEGORI DIHENTIKAN: ", conditionMessage(html)); return(bind_rows(hasil)) }
        if (is.null(html)) next
      }
      d <- parse_daftar(html, u)
      if (nrow(d)) hasil[[length(hasil) + 1]] <- mutate(d, sumber_daftar = paste0("direktori ", nama))
    }
  }
  bind_rows(hasil)
}

kumpulkan_html_tersimpan <- function(folder) {
  f <- list.files(folder, pattern = "\\.html?$", full.names = TRUE, ignore.case = TRUE)
  bind_rows(lapply(f, function(x) mutate(parse_daftar(read_file(x)), sumber_daftar = "pencarian (HTML tersimpan)")))
}

nama_berkas_pdf <- function(nomor, id) {
  dasar <- if (is.na(nomor) || !nzchar(nomor)) id else nomor
  paste0(str_replace_all(str_replace_all(dasar, "[\\\\/:*?\"<>|]+", "_"), "\\s+", "_"), ".pdf")
}

tahun_overview <- function(ov, tanggal_daftar = NA) {
  for (s in c(ov$tanggal_dibacakan, ov$tanggal_musyawarah)) {
    d <- parse_tanggal(s %||% "")
    if (!is.na(d)) return(as.integer(format(d, "%Y")))
  }
  th <- suppressWarnings(as.integer(str_extract(tanggal_daftar %||% NA, "\\d{4}$")))
  if (!is.na(th)) return(th)
  suppressWarnings(as.integer(substr(ov$tahun %||% NA, 1, 4)))
}

telusuri <- function(daftar, cfg, keluaran) {
  folder_cache <- file.path(keluaran, "cache_html")
  folder_pdf <- file.path(keluaran, "pdf")
  berkas_kemajuan <- file.path(keluaran, "semua_putusan_diperiksa.csv")
  berkas_antrean <- file.path(keluaran, "antrean_tersisa.txt")
  selesai <- if (file.exists(berkas_kemajuan)) read_csv(berkas_kemajuan, show_col_types = FALSE, col_types = cols(.default = "c")) else NULL
  if (!is.null(selesai)) {
    # Putusan yang PDF-nya gagal diunduh pada putaran sebelumnya diulang (baris lamanya dibuang).
    ulang <- selesai$lampiran_pdf %in% "Ada" & !selesai$sumber_data %in% "PDF putusan"
    selesai <- selesai[!ulang, ]
  }
  sudah <- if (is.null(selesai)) character(0) else id_putusan(selesai$url_putusan)
  antre <- daftar |> filter(!is.na(id))
  # Lanjutkan antrean yang tersisa saat penelusuran sebelumnya dihentikan (mis. CAPTCHA).
  if (file.exists(berkas_antrean)) {
    sisa <- read_lines(berkas_antrean)
    sisa <- sisa[!is.na(id_putusan(sisa))]
    antre <- bind_rows(tibble(id = id_putusan(sisa), url = url_kanonik(sisa), nomor = NA_character_,
                              tanggal_putus = NA_character_, sumber_daftar = "antrean tersisa"), antre)
    pesan(length(sisa), " URL dari antrean_tersisa.txt dilanjutkan")
  }
  antre <- distinct(antre, id, .keep_all = TRUE)
  # Lewati entri daftar yang tanggal putusnya jelas di luar rentang tahun.
  th_daftar <- suppressWarnings(as.integer(str_extract(antre$tanggal_putus, "\\d{4}$")))
  antre <- antre[is.na(th_daftar) | th_daftar %in% cfg$tahun, ]
  dikunjungi <- sudah
  baris <- list(); gagal <- list(); i <- 0
  # Catatan: stop() di dalam handler captcha_error akan tertangkap handler `error` pada tryCatch yang sama,
  # jadi CAPTCHA dikembalikan sebagai nilai penanda lalu dihentikan di luar tryCatch.
  tandai_captcha <- function(e) structure(list(kondisi = e), class = "penanda_captcha")
  while (nrow(antre)) {
    it <- antre[1, ]; antre <- antre[-1, ]
    if (it$id %in% dikunjungi) next
    dikunjungi <- c(dikunjungi, it$id)
    i <- i + 1
    r <- tryCatch({
      ov <- parse_overview(ambil_html(it$url, cfg, folder_cache, jenis = "overview"), it$url)
      th <- tahun_overview(ov, it$tanggal_putus)
      if (cfg$ikuti_terkait && length(ov$terkait)) {
        baru <- tibble(id = id_putusan(ov$terkait), url = ov$terkait, nomor = NA_character_, tanggal_putus = NA_character_,
                       sumber_daftar = "putusan terkait") |> filter(!id %in% dikunjungi)
        antre <- bind_rows(antre, baru)
      }
      teks <- NA_character_; fpdf <- NA_character_; ok <- NULL
      # PDF diunduh bila tahunnya dalam rentang, atau bila tahun belum diketahui (ditentukan dari PDF).
      if ((is.na(th) || th %in% cfg$tahun) && !is.na(ov$url_pdf)) {
        tujuan <- file.path(folder_pdf, nama_berkas_pdf(ov$nomor %||% NA, it$id))
        ok <- tryCatch({ unduh_pdf(ov$url_pdf, tujuan, cfg); TRUE },
                       captcha_error = tandai_captcha,
                       error = function(e) { gagal[[length(gagal) + 1]] <<- tibble(url = ov$url_pdf, galat = conditionMessage(e)); FALSE })
        if (isTRUE(ok)) { teks <- teks_pdf(tujuan); fpdf <- file.path("pdf", basename(tujuan)) }
      }
      # (return() di sini akan keluar dari telusuri(), jadi penanda CAPTCHA diteruskan sebagai nilai blok.)
      if (inherits(ok, "penanda_captcha")) ok else rekap_putusan(ov, teks, fpdf, it$sumber_daftar)
    }, captcha_error = tandai_captcha,
    error = function(e) { gagal[[length(gagal) + 1]] <<- tibble(url = it$url, galat = conditionMessage(e)); NULL })
    if (inherits(r, "penanda_captcha")) {
      simpan_kemajuan(selesai, baris, berkas_kemajuan)
      if (length(gagal)) write_csv(bind_rows(gagal), file.path(keluaran, "log_gagal.csv"))
      writeLines(c(it$url, antre$url), berkas_antrean)
      stop(r$kondisi)
    }
    if (!is.null(r)) {
      baris[[length(baris) + 1]] <- r
      pesan("[", i, "] ", r$nomor_putusan, " (", r$tahun_putusan, ") ", r$sumber_data, " | relevan: ", r$relevan_bbm, " | antrean ", nrow(antre))
    }
    if (length(baris) && length(baris) %% 25 == 0) simpan_kemajuan(selesai, baris, berkas_kemajuan)
  }
  semua <- simpan_kemajuan(selesai, baris, berkas_kemajuan)
  if (length(gagal)) write_csv(bind_rows(gagal), file.path(keluaran, "log_gagal.csv"))
  if (file.exists(berkas_antrean)) unlink(berkas_antrean)
  semua
}

simpan_kemajuan <- function(selesai, baris, berkas) {
  baru <- bind_rows(baris)
  semua <- if (is.null(selesai)) baru else bind_rows(mutate(selesai, across(everything(), as.character)), mutate(baru, across(everything(), as.character)))
  write_excel_csv(semua, berkas, na = "NA")
  semua
}

tulis_rekap <- function(semua, cfg, keluaran, nama = "rekap_kriminalitas_BBM_MA_2020_2026.csv") {
  if (is.null(semua) || !nrow(semua)) { pesan("Tidak ada putusan yang terekap."); return(invisible(NULL)) }
  semua <- semua |> mutate(tahun_putusan = suppressWarnings(as.integer(tahun_putusan)),
                           nilai_kerugian_uang = suppressWarnings(as.numeric(nilai_kerugian_uang)),
                           nilai_kerugian_volume = suppressWarnings(as.numeric(nilai_kerugian_volume)))
  # "Perlu dicek (tanpa PDF)": overview tanpa nama BBM, tetapi ditemukan lewat kata kunci BBM / klasifikasi Migas.
  rekap <- semua |>
    filter(relevan_bbm %in% c("Ya", "Perlu dicek (tanpa PDF)"), tahun_putusan %in% cfg$tahun) |>
    arrange(tahun_putusan, tingkat_persidangan, nomor_putusan) |>
    mutate(no = row_number(), .before = 1) |>
    select(no, all_of(KOLOM_REKAP))
  f <- file.path(keluaran, nama)
  write_excel_csv(rekap, f, na = "NA")
  pesan("Rekap: ", nrow(rekap), " putusan relevan BBM (dari ", nrow(semua), " yang diperiksa) -> ", f)
  invisible(rekap)
}

# -----------------------------------------------------------------------------
# 8. PROGRAM UTAMA
# -----------------------------------------------------------------------------
OPSI_NILAI <- c("mode", "tahun", "jeda", "maks-halaman", "keluaran", "kata-kunci", "kategori", "url", "url-list",
                "html-dir", "pdf-dir")
OPSI_BENDERA <- c("tanpa-terkait")

baca_argumen <- function(args = commandArgs(trailingOnly = TRUE)) {
  # Menerima "--opsi=nilai" dan "--opsi nilai". Opsi yang tidak dikenal menghentikan skrip dengan daftar opsi.
  opsi <- list(); i <- 1
  while (i <= length(args)) {
    m <- str_match(args[i], "^--([a-z-]+)(?:=(.*))?$")
    if (is.na(m[1, 1])) stop("argumen tidak dikenal: ", args[i], ". Gunakan --opsi=nilai.")
    kunci <- m[1, 2]; nilai <- m[1, 3]
    if (!kunci %in% c(OPSI_NILAI, OPSI_BENDERA))
      stop("opsi tidak dikenal: --", kunci, ". Opsi: ", paste0("--", c(OPSI_NILAI, OPSI_BENDERA), collapse = ", "))
    if (kunci %in% OPSI_BENDERA) {
      nilai <- TRUE
    } else if (is.na(nilai)) {
      if (i < length(args) && !startsWith(args[i + 1], "--")) { nilai <- args[i + 1]; i <- i + 1 }
      else stop("opsi --", kunci, " memerlukan nilai, mis. --", kunci, "=...")
    }
    opsi[[kunci]] <- nilai
    i <- i + 1
  }
  opsi
}

parse_tahun <- function(x) {
  # "2020:2026", "2020-2026", "2020,2022,2024" atau "2023"
  x <- str_remove_all(x, "\\s")
  th <- if (str_detect(x, "^\\d{4}[:-]\\d{4}$")) {
    b <- as.integer(str_split(x, "[:-]")[[1]]); seq(min(b), max(b))
  } else if (str_detect(x, "^\\d{4}(,\\d{4})*$")) as.integer(str_split(x, ",")[[1]]) else integer(0)
  if (!length(th) || any(th < 1990 | th > 2100)) stop("--tahun tidak sah: ", x, " (contoh: --tahun=2020:2026)")
  th
}

terapkan_opsi <- function(cfg, opsi) {
  # Selalu [[ ]] (bukan $): `$` pada list mencocokkan sebagian nama, mis. opsi$url akan mengambil "url-list".
  if (!is.null(opsi[["tahun"]])) cfg$tahun <- parse_tahun(opsi[["tahun"]])
  if (!is.null(opsi[["jeda"]])) cfg$jeda_detik <- as.numeric(opsi[["jeda"]])
  if (!is.null(opsi[["maks-halaman"]])) cfg$maks_halaman <- as.numeric(opsi[["maks-halaman"]])
  if (!is.null(opsi[["keluaran"]])) cfg$folder_keluaran <- opsi[["keluaran"]]
  if (!is.null(opsi[["tanpa-terkait"]])) cfg$ikuti_terkait <- FALSE
  if (!is.null(opsi[["kata-kunci"]])) cfg$kata_kunci <- str_trim(str_split(opsi[["kata-kunci"]], ",")[[1]])
  if (!is.null(opsi[["kategori"]])) cfg$kategori <- str_trim(str_split(opsi[["kategori"]], ",")[[1]])
  if (is.na(cfg$jeda_detik) || is.na(cfg$maks_halaman)) stop("--jeda dan --maks-halaman harus angka")
  cfg
}

proses_pdf_lokal <- function(folder_pdf, cfg, keluaran) {
  f <- list.files(folder_pdf, pattern = "\\.pdf$", full.names = TRUE, ignore.case = TRUE)
  if (!length(f)) stop("tidak ada berkas PDF di ", folder_pdf)
  pesan(length(f), " PDF di ", folder_pdf)
  semua <- bind_rows(lapply(seq_along(f), function(i) {
    r <- tryCatch(rekap_putusan(list(), teks_pdf(f[i]), file.path("pdf", basename(f[i])), "PDF lokal"),
                  error = function(e) { pesan("  gagal ", basename(f[i]), ": ", conditionMessage(e)); NULL })
    if (!is.null(r)) pesan("[", i, "] ", r$nomor_putusan, " | ", r$hasil_putusan, " | ", r$barang_bbm)
    r
  }))
  # Berkas terpisah dari penelusuran online agar tidak menimpa status lanjutan (semua_putusan_diperiksa.csv).
  write_excel_csv(semua, file.path(keluaran, "semua_putusan_pdf_lokal.csv"), na = "NA")
  semua
}

cek_situs <- function(cfg) {
  folder <- tempfile("cek_ma_")
  u <- url_filter_tahun(cfg$kategori[1], max(cfg$tahun))
  html <- ambil_html(u, cfg, folder, pakai_cache = FALSE, jenis = "daftar")
  d <- parse_daftar(html, u)
  pesan("Daftar ", u, ": ", nrow(d), " entri, halaman terakhir ", halaman_terakhir(html, u))
  if (!nrow(d)) stop("Tidak ada tautan /direktori/putusan/ - URL kategori atau tata letak situs berubah.")
  ov <- parse_overview(ambil_html(d$url[1], cfg, folder, pakai_cache = FALSE), d$url[1])
  for (k in c("nomor", "tingkat_proses", "klasifikasi", "lembaga_peradilan", "tanggal_dibacakan", "url_pdf"))
    pesan(sprintf("  %-20s: %s", k, ov[[k]] %||% "(tidak terbaca)"))
  pesan("  putusan terkait     : ", length(ov$terkait))
  q <- url_pencarian(cfg$kata_kunci[1], max(cfg$tahun), 1, cfg)
  hp <- tryCatch(ambil_html(q, cfg, folder, pakai_cache = FALSE, jenis = "daftar"), error = function(e) e)
  if (inherits(hp, "error")) pesan("Pencarian: ", conditionMessage(hp)) else pesan("Pencarian '", cfg$kata_kunci[1], "': ", nrow(parse_daftar(hp, q)), " entri di halaman 1")
}

main <- function(args = commandArgs(trailingOnly = TRUE)) {
  opsi <- baca_argumen(args)
  cfg <- terapkan_opsi(KONFIG, opsi)
  mode <- opsi[["mode"]] %||% "semua"
  keluaran <- cfg$folder_keluaran
  dir.create(keluaran, showWarnings = FALSE, recursive = TRUE)
  folder_cache <- file.path(keluaran, "cache_html")

  if (mode == "cek") return(invisible(cek_situs(cfg)))
  if (mode == "pdf-lokal") {
    semua <- proses_pdf_lokal(opsi[["pdf-dir"]] %||% "Data Kriminal BBM/pdf", cfg, keluaran)
    return(invisible(tulis_rekap(semua, cfg, keluaran, "rekap_kriminalitas_BBM_pdf_lokal.csv")))
  }
  daftar <- switch(mode,
    "semua" = bind_rows(kumpulkan_pencarian(cfg, folder_cache), kumpulkan_kategori(cfg, folder_cache)),
    "pencarian" = kumpulkan_pencarian(cfg, folder_cache),
    "kategori" = kumpulkan_kategori(cfg, folder_cache),
    "html" = kumpulkan_html_tersimpan(opsi[["html-dir"]] %||% stop("--html-dir wajib untuk --mode=html")),
    "url" = {
      u <- if (!is.null(opsi[["url"]])) opsi[["url"]] else read_lines(opsi[["url-list"]] %||% stop("--url atau --url-list wajib untuk --mode=url"))
      u <- str_trim(u[nzchar(str_trim(u))])
      if (!any(!is.na(id_putusan(u)))) stop("tidak ada URL putusan yang sah (pola .../direktori/putusan/<id>.html)")
      tibble(id = id_putusan(u), url = url_kanonik(u), nomor = NA_character_, tanggal_putus = NA_character_, sumber_daftar = "daftar URL")
    },
    stop("mode tidak dikenal: ", mode, " (semua, pencarian, kategori, html, url, pdf-lokal, cek)"))
  berkas_antrean <- file.path(keluaran, "antrean_tersisa.txt")
  if (is.null(daftar) || (!nrow(daftar) && !file.exists(berkas_antrean))) { pesan("Tidak ada URL putusan yang terkumpul."); return(invisible(NULL)) }
  if (nrow(daftar)) {
    write_excel_csv(distinct(daftar, id, .keep_all = TRUE), file.path(keluaran, "daftar_url.csv"), na = "NA")
    pesan(n_distinct(daftar$id), " URL putusan terkumpul")
  }
  semua <- tryCatch(telusuri(daftar, cfg, keluaran), captcha_error = function(e) {
    pesan("DIHENTIKAN: ", conditionMessage(e))
    f <- file.path(keluaran, "semua_putusan_diperiksa.csv")
    if (file.exists(f)) read_csv(f, show_col_types = FALSE, col_types = cols(.default = "c")) else NULL
  })
  invisible(tulis_rekap(semua, cfg, keluaran))
}

if (sys.nframe() == 0L) {
  main()
} else if (interactive()) {
  message("Skrip dimuat (tombol Source di RStudio). Jalankan misalnya:\n",
          "  main(c(\"--mode=cek\"))\n",
          "  main(c(\"--mode=url\", \"--url=https://putusan3.mahkamahagung.go.id/direktori/putusan/1b6b7ad93106cdda7a17bcacf6917d0c.html\"))\n",
          "  main(c(\"--mode=pdf-lokal\", \"--pdf-dir=Data Kriminal BBM/pdf\"))\n",
          "  main()   # pencarian + kategori Migas 2020-2026")
}
