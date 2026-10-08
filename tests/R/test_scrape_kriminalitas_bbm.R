# Uji skrip R scraper. Jalankan dari akar repositori:
#   Rscript -e 'testthat::test_file("tests/R/test_scrape_kriminalitas_bbm.R")'
library(testthat)
# testthat menjalankan uji dari folder berkas uji; cari akar repositori ke atas.
AKAR <- normalizePath(".")
while (!file.exists(file.path(AKAR, "R", "scrape_kriminalitas_bbm.R")) && dirname(AKAR) != AKAR) AKAR <- dirname(AKAR)
source(file.path(AKAR, "R", "scrape_kriminalitas_bbm.R"))

FIX <- file.path(AKAR, "tests", "fixtures")
DATA <- file.path(AKAR, "Data Kriminal BBM")

test_that("angka, tanggal dan nomor perkara", {
  expect_equal(angka_id(c("5.353", "19.930.365,00", "1.234,5", "92", "3,5")), c(5353, 19930365, 1234.5, 92, 3.5))
  expect_equal(parse_tanggal("pada hari Rabu, tanggal 5 Pebruari 2020 oleh"), as.Date("2020-02-05"))
  expect_equal(parse_tanggal("tanggal 12 Nopember 2021"), as.Date("2021-11-12"))
  expect_true(is.na(parse_tanggal("tanpa tanggal")))
  expect_equal(tingkat_dari_nomor(c("266/Pid.Sus/2019/PN.Pli", "11/PID.SUS-LH/2021/PTJMB", "4922 K/Pid.Sus/2022",
                                    "580 PK/Pid.Sus/2023", "43-K/PM.II-11/AD/IX/2025")),
               c("PN", "PT", "MA", "MA", "Pengadilan Militer"))
})

test_that("hasil putusan dari amar", {
  h <- function(x) hasil_putusan(x)[1]
  expect_equal(h("MENGADILI: Menyatakan Terdakwa telah terbukti secara sah dan meyakinkan bersalah; pidana penjara selama 6 bulan"), "Bersalah")
  expect_equal(h("MENGADILI: Menyatakan Terdakwa tidak terbukti secara sah dan meyakinkan bersalah; Membebaskan Terdakwa oleh karena itu dari semua dakwaan"), "Tidak bersalah")
  expect_equal(h("MENGADILI: Melepaskan Terdakwa oleh karena itu dari segala tuntutan hukum"), "Tidak bersalah")
  expect_equal(h("Membebaskan terdakwa dari dakwaan Primair; Menyatakan terdakwa terbukti secara sah dan menyakinkan bersalah"), "Bersalah")
  expect_equal(h("M E N G A D I L I: Menolak permohonan kasasi dari Pemohon Kasasi/Terdakwa tersebut"), "Bersalah")
  expect_true(is.na(h("M E N G A D I L I: Menolak permohonan kasasi dari Pemohon Kasasi/Penuntut Umum tersebut")))
  expect_equal(h("Membatalkan putusan PN yang membebaskan Terdakwa dari dakwaan; MENGADILI SENDIRI: Menyatakan Terdakwa terbukti secara sah dan meyakinkan bersalah"), "Bersalah")
})

test_that("volume, nominal uang dan barang BBM", {
  t <- paste("barang bukti BBM solar sebanyak 5.353 (lima ribu tiga ratus lima puluh tiga) liter dalam drum",
             "kapasitas 200 (dua ratus) liter; dan 2 KL solar; hasil lelang sebesar Rp19.930.365,00;",
             "dibeli Rp5.150/liter dan dijual Rp8.000 per liter dengan keuntungan Rp2.850 per liter; denda sebesar Rp1.000.000,00")
  v <- volume_bbm(t)
  expect_setequal(v$nilai, c(5353, 2000))          # kapasitas wadah tidak dihitung
  u <- nominal_uang(t)
  expect_equal(u$jenis[u$nilai == 19930365], "hasil_lelang")
  expect_equal(u$jenis[u$nilai == 5150], "harga_per_liter")
  expect_equal(u$jenis[u$nilai == 2850], "keuntungan_per_liter")
  expect_equal(u$jenis[u$nilai == 1000000], "denda")
  expect_equal(nilai_kerugian(t, list(nilai = 7353, satuan = "liter"))$nilai, 19930365)   # lelang didahulukan
  expect_equal(nilai_kerugian("membeli solar Rp5.150 per liter", list(nilai = 100, satuan = "liter"))$nilai, 515000)
  expect_equal(barang_bbm(NA, "BBM jenis Bio Solar bersubsidi; solar"), "Solar/Biosolar (subsidi)")
  expect_equal(relevansi_bbm("tabung LPG 3 kg"), "Tidak (LPG/gas)")
  expect_equal(relevansi_bbm("BBM jenis pertalite", amar = "barang bukti 20 liter pertalite"), "Ya")
  expect_equal(relevansi_bbm("nosel Pertalite"), "Perlu dicek (sebutan BBM sedikit)")   # sebutan sekilas
  expect_equal(relevansi_bbm("menjual bahan bakar minyak mentah hasil sumur; bahan bakar minyak mentah"), "Sebagian (minyak mentah)")
})

test_that("lokasi, provinsi dan penyamaran nama", {
  l <- lokasi_kejadian("Bahwa terdakwa pada hari Senin bertempat di Desa Pulau Sari Kecamatan Tambang Ulang Kabupaten Tanah Laut atau setidak-tidaknya di tempat lain")
  expect_equal(l$lokasi, "Desa Pulau Sari Kecamatan Tambang Ulang Kabupaten Tanah Laut")
  expect_equal(l$kab_kota, "Kabupaten Tanah Laut")
  expect_equal(provinsi_pengadilan("PN PALANGKA RAYA"), "Kalimantan Tengah")
  expect_equal(provinsi_pengadilan("PN KOTOBARU"), "Sumatera Barat")
  expect_equal(provinsi_pengadilan("PN KOTABARU"), "Kalimantan Selatan")
  expect_true(is.na(provinsi_pengadilan("MAHKAMAH AGUNG")))
  expect_equal(samarkan_nama("disalin oleh saksi Gusma Deri dan Terdakwa tersebut"), "disalin oleh saksi [nama] dan Terdakwa tersebut")
})

test_that("parser halaman daftar dan overview", {
  daftar <- read_file(file.path(FIX, "daftar_migas.html"))
  u <- "https://putusan3.mahkamahagung.go.id/direktori/index/kategori/migas-1.html"
  d <- parse_daftar(daftar, u)
  expect_true(all(c("1102e1cfc840bf73da0c2c1af05872e7", "zaee19ae19bbffd2a715323133303034") %in% d$id))
  expect_equal(d$tanggal_putus[d$id == "1102e1cfc840bf73da0c2c1af05872e7"], "07-09-2020")
  expect_equal(d$nomor[d$id == "1102e1cfc840bf73da0c2c1af05872e7"], "249/Pid.Sus/2020/PN Spt")
  expect_equal(halaman_terakhir(daftar, u), 12)
  expect_equal(url_filter_tahun(u, 2021), "https://putusan3.mahkamahagung.go.id/direktori/index/kategori/migas-1/tahunjenis/putus/tahun/2021.html")
  expect_equal(url_halaman_direktori(url_filter_tahun(u, 2021), 3), "https://putusan3.mahkamahagung.go.id/direktori/index/kategori/migas-1/tahunjenis/putus/tahun/2021/page/3.html")
  expect_equal(url_pencarian("\"minyak tanah\"", 2022, 2), "https://putusan3.mahkamahagung.go.id/search.html?q=%22minyak%20tanah%22&t_put=2022&page=2")

  url <- "https://putusan3.mahkamahagung.go.id/direktori/putusan/1102e1cfc840bf73da0c2c1af05872e7.html"
  ov <- parse_overview(read_file(file.path(FIX, "overview_pn.html")), url)
  expect_equal(ov$nomor, "249/Pid.Sus/2020/PN Spt")
  expect_equal(ov$klasifikasi, "Pidana Khusus Migas")
  expect_equal(ov$lembaga_peradilan, "PN SAMPIT")
  expect_equal(ov$tanggal_dibacakan, "7 September 2020")
  expect_match(ov$url_pdf, "/pdf/1102e1cfc840bf73da0c2c1af05872e7$")
  expect_setequal(id_putusan(ov$terkait), c(strrep("c", 32), strrep("d", 32)))   # tanpa diri sendiri & "Putusan Terbaru"

  r <- rekap_putusan(ov)   # tanpa PDF: rekap dari overview
  expect_equal(r$tahun_putusan, 2020L)
  expect_equal(r$tingkat_persidangan, "PN")
  expect_equal(r$hasil_putusan, "Bersalah")
  expect_equal(r$lokasi_kejadian, "Wilayah hukum PN SAMPIT")
  expect_equal(r$provinsi, "Kalimantan Tengah")
  expect_equal(r$sumber_data, "Overview direktori")
  expect_true(mirip_captcha(read_file(file.path(FIX, "captcha.html"))))
  expect_false(mirip_captcha(read_file(file.path(FIX, "overview_pn.html"))))
})

test_that("PDF asli: teks bersih dan kolom rekap", {
  f <- file.path(DATA, "pdf", "266_Pid.Sus_2019_PN Pli.pdf")
  skip_if_not(file.exists(f))
  tx <- teks_pdf(f)
  expect_false(grepl("Disclaimer", tx))
  expect_true(grepl("Nomor 266/Pid.Sus/2019/PN.Pli", tx, fixed = TRUE))
  r <- rekap_putusan(list(), tx, "pdf/266_Pid.Sus_2019_PN Pli.pdf")
  expect_equal(r$tahun_putusan, 2020L)
  expect_equal(r$tahun_kejadian, "2019")
  expect_equal(r$tingkat_persidangan, "PN")
  expect_equal(r$hasil_putusan, "Bersalah")
  expect_equal(r$pengadilan, "PN PELAIHARI")
  expect_equal(r$provinsi, "Kalimantan Selatan")
  expect_match(r$barang_bbm, "^Solar")
  expect_equal(r$nilai_kerugian_volume, 92)
  expect_equal(r$satuan_volume, "liter")
})

test_that("tolok ukur: hasil otomatis vs rekap manual (PDF yang dirujuk rekap)", {
  rk <- file.path(DATA, "rekap_putusan_kriminalitas_BBM_2020-2026.csv")
  skip_if_not(file.exists(rk))
  manual <- read_csv(rk, show_col_types = FALSE, col_types = cols(.default = "c")) |>
    filter(!is.na(file_pdf), file_pdf != "NA") |> distinct(file_pdf, .keep_all = TRUE)
  otomatis <- bind_rows(lapply(manual$file_pdf, function(fp) rekap_putusan(list(), teks_pdf(file.path(DATA, fp)), fp)))
  b <- bind_cols(manual |> select(file_pdf, m_tahun = tahun_putusan, m_tingkat = tingkat_persidangan, m_hasil = hasil_putusan,
                                  m_barang = barang_bbm, m_vol = nilai_kerugian_volume, m_kej = tahun_kejadian, m_uang = nilai_kerugian_uang),
                 otomatis |> select(tahun_putusan, tingkat_persidangan, hasil_putusan, barang_bbm, nilai_kerugian_volume, tahun_kejadian,
                                    provinsi, relevan_bbm, nilai_kerugian_uang))
  num <- function(x) suppressWarnings(as.numeric(x))
  setuju <- function(x) mean(x, na.rm = TRUE)
  ringkas <- tibble(
    kolom = c("tahun_putusan", "tingkat_persidangan", "hasil_putusan (keduanya terisi)", "barang_bbm (jenis utama sama)",
              "nilai_kerugian_volume (sama +/-1%)", "tahun_kejadian (keduanya terisi)", "provinsi terisi",
              "relevan_bbm = Ya", "nilai_kerugian_uang (sama +/-1%)"),
    cakupan = c(sum(!is.na(b$tahun_putusan)), sum(!is.na(b$tingkat_persidangan)), sum(!is.na(b$hasil_putusan) & b$m_hasil != "NA"),
                sum(!is.na(b$barang_bbm)), sum(!is.na(b$nilai_kerugian_volume) & b$m_vol != "NA"),
                sum(!is.na(b$tahun_kejadian) & b$m_kej != "NA"), sum(!is.na(b$provinsi)),
                nrow(b), sum(!is.na(b$nilai_kerugian_uang) & !is.na(num(b$m_uang)))),
    setuju = c(setuju(as.character(b$tahun_putusan) == b$m_tahun),
               setuju(b$tingkat_persidangan == b$m_tingkat),
               setuju(ifelse(is.na(b$hasil_putusan) | b$m_hasil == "NA", NA, b$hasil_putusan == b$m_hasil)),
               setuju(ifelse(is.na(b$barang_bbm), NA, str_extract(str_to_lower(b$barang_bbm), "solar|pertalite|premium|minyak tanah|pertamax|bbm") ==
                               str_extract(str_to_lower(b$m_barang), "solar|pertalite|premium|minyak tanah|pertamax|bbm"))),
               setuju(ifelse(is.na(b$nilai_kerugian_volume) | b$m_vol == "NA", NA,
                             abs(b$nilai_kerugian_volume - suppressWarnings(as.numeric(b$m_vol))) <= 0.01 * suppressWarnings(as.numeric(b$m_vol)))),
               setuju(ifelse(is.na(b$tahun_kejadian) | b$m_kej == "NA", NA, b$tahun_kejadian == b$m_kej)),
               mean(!is.na(b$provinsi)),
               mean(b$relevan_bbm == "Ya"),
               setuju(ifelse(is.na(b$nilai_kerugian_uang) | is.na(num(b$m_uang)), NA,
                             abs(b$nilai_kerugian_uang - num(b$m_uang)) <= 0.01 * num(b$m_uang))))
  )
  ringkas$n <- nrow(b)
  print(ringkas)
  write_csv(ringkas, file.path(tempdir(), "tolok_ukur.csv"))
  expect_gte(ringkas$setuju[1], 0.95)
  expect_gte(ringkas$setuju[2], 0.95)
  expect_gte(ringkas$setuju[3], 0.90)
  expect_gte(ringkas$setuju[4], 0.80)
  expect_gte(ringkas$setuju[8], 0.95)   # semua PDF di rekap manual dinilai relevan BBM
})

test_that("penelusuran online dengan jaringan tiruan: overview -> PDF -> CSV, berhenti rapi saat CAPTCHA", {
  pdf_contoh <- file.path(DATA, "pdf", "266_Pid.Sus_2019_PN Pli.pdf")
  skip_if_not(file.exists(pdf_contoh))
  ov_html <- read_file(file.path(FIX, "overview_pn.html"))
  id_pn <- "1102e1cfc840bf73da0c2c1af05872e7"
  asli <- list(ambil_html = ambil_html, unduh_pdf = unduh_pdf)
  on.exit(for (n in names(asli)) assign(n, asli[[n]], envir = globalenv()), add = TRUE)
  assign("unduh_pdf", function(url, tujuan, cfg) {
    dir.create(dirname(tujuan), recursive = TRUE, showWarnings = FALSE); file.copy(pdf_contoh, tujuan); tujuan
  }, envir = globalenv())

  # 1) Putusan terkait tidak ada (404): dicatat di log_gagal, penelusuran tetap selesai.
  assign("ambil_html", function(url, cfg, folder_cache, pakai_cache = TRUE, ...) {
    if (identical(id_putusan(url), id_pn)) ov_html else stop("HTTP 404")
  }, envir = globalenv())
  keluaran <- tempfile("hasil_")
  main(c("--mode=url", paste0("--url=https://putusan3.mahkamahagung.go.id/direktori/putusan/", id_pn, ".html"),
         paste0("--keluaran=", keluaran), "--jeda=0"))
  r <- read_csv(file.path(keluaran, "rekap_kriminalitas_BBM_MA_2020_2026.csv"), show_col_types = FALSE)
  expect_equal(nrow(r), 1)
  expect_equal(names(r)[2:11], KOLOM_REKAP[1:10])
  expect_equal(r$nomor_putusan, "249/Pid.Sus/2020/PN Spt")
  expect_equal(r$sumber_data, "PDF putusan")
  expect_equal(r$file_pdf, "pdf/249_Pid.Sus_2020_PN_Spt.pdf")
  expect_true(file.exists(file.path(keluaran, "pdf", "249_Pid.Sus_2020_PN_Spt.pdf")))
  expect_equal(nrow(read_csv(file.path(keluaran, "log_gagal.csv"), show_col_types = FALSE)), 2)

  # 2) Putusan terkait meminta CAPTCHA: berhenti, yang sudah terekap tetap tertulis.
  assign("ambil_html", function(url, cfg, folder_cache, pakai_cache = TRUE, ...) {
    if (identical(id_putusan(url), id_pn)) ov_html else stop(kondisi_captcha(url))
  }, envir = globalenv())
  keluaran2 <- tempfile("hasil_")
  expect_message(main(c("--mode=url", paste0("--url=https://putusan3.mahkamahagung.go.id/direktori/putusan/", id_pn, ".html"),
                        paste0("--keluaran=", keluaran2), "--jeda=0")), "DIHENTIKAN")
  r2 <- read_csv(file.path(keluaran2, "rekap_kriminalitas_BBM_MA_2020_2026.csv"), show_col_types = FALSE)
  expect_equal(nrow(r2), 1)
})

test_that("CAPTCHA saat mengunduh PDF juga menghentikan penelusuran", {
  ov_html <- read_file(file.path(FIX, "overview_pn.html"))
  asli <- list(ambil_html = ambil_html, unduh_pdf = unduh_pdf)
  on.exit(for (n in names(asli)) assign(n, asli[[n]], envir = globalenv()), add = TRUE)
  assign("ambil_html", function(url, cfg, folder_cache, pakai_cache = TRUE, ...) ov_html, envir = globalenv())
  assign("unduh_pdf", function(url, tujuan, cfg) stop(kondisi_captcha(url)), envir = globalenv())
  keluaran <- tempfile("hasil_")
  expect_message(main(c("--mode=url", "--url=https://putusan3.mahkamahagung.go.id/direktori/putusan/1102e1cfc840bf73da0c2c1af05872e7.html",
                        paste0("--keluaran=", keluaran), "--jeda=0", "--tanpa-terkait")), "DIHENTIKAN")
  expect_true(file.exists(file.path(keluaran, "antrean_tersisa.csv")))
})


test_that("perbaikan hasil tinjauan: argumen, robots, nama, uang, tahun, overview", {
  # --url-list tidak lagi tertukar dengan --url (pencocokan nama sebagian pada list)
  o <- baca_argumen(c("--mode=url", "--url-list=daftar.txt"))
  expect_null(o[["url"]]); expect_equal(o[["url-list"]], "daftar.txt")
  expect_equal(baca_argumen(c("--keluaran", "folder saya"))[["keluaran"]], "folder saya")
  expect_error(baca_argumen(c("--tahunn=2020")), "opsi tidak dikenal")
  expect_equal(parse_tahun("2020-2026"), 2020:2026); expect_equal(parse_tahun("2021,2023"), c(2021L, 2023L))
  expect_error(parse_tahun("2020-26"))

  a <- aturan_robots("User-agent: *\nUser-agent: Googlebot\nDisallow: /search.html # cari\nAllow: /search.html?ok", "KajianBBM-UGM")
  expect_false(robots_mengizinkan(a, "/search.html?q=solar"))
  expect_true(robots_mengizinkan(a, "/search.html?ok=1"))
  expect_true(robots_mengizinkan(a, "/direktori/putusan/x.html"))
  expect_false(robots_mengizinkan(aturan_robots("User-agent: *\nDisallow: /*?q=", "x"), "/search.html?q=1"))

  expect_equal(samarkan_nama("rumah Terdakwa II Andi Wijaya di Desa X"), "rumah Terdakwa II [nama] di Desa X")
  expect_equal(samarkan_nama("di Rumah Terdakwa Jorong Simpang Ampek"), "di Rumah Terdakwa Jorong Simpang Ampek")
  expect_equal(samarkan_nama("milik PT Garam"), "milik PT Garam")
  expect_false(grepl("SIGIT|AMBON", samarkan_nama("pesanan dari Saksi SIGIT SUTRIYONO alias AMBON")))

  u <- nominal_uang("sehingga keuntungan yang\ndiperoleh kisaran Rp1.000,00 (seribu rupiah) perliter; dijual Rp200.000 per jerigen; kerugian negara sebesar USD 25.000")
  expect_equal(u$jenis[u$nilai == 1000], "keuntungan_per_liter")
  expect_equal(u$jenis[u$nilai == 2e5], "harga_per_wadah")
  expect_equal(u$nilai[u$mata_uang == "USD"], 25000)

  expect_equal(tahun_kejadian("dalam bulan Januari tahun 2000 dua puluh empat sampai bulan April tahun 2000 dua puluh empat", 2025), "2024")
  expect_equal(pengadilan_dari_teks("Hakim Pengadilan Negeri Perpanjangan Oleh Ketua Pengadilan Negeri Jambi sejak"), "PN JAMBI")
  expect_match(lokasi_kejadian("bertempat disebuah warung di Desa Alur Kabupaten Tanah Laut atau setidak-tidaknya")$lokasi, "^sebuah warung")

  v <- volume_butir("Menetapkan barang bukti berupa:\n- 27 (dua puluh tujuh) jerigen masing-masing berisi 30 liter BBM jenis solar;\n- 1 (satu) lembar surat pesanan solar 5.000 liter;\n- 1 drum berisi 200 liter solar")
  expect_equal(sum(v$nilai), 27 * 30 + 200)   # dokumen tidak dihitung, "berisi" bukan kapasitas

  # Overview tanpa PDF dari klasifikasi Migas tanpa nama BBM -> tetap masuk rekap untuk dicek; kolom Amar dipakai.
  ov <- list(nomor = "100 K/Pid.Sus/2021", klasifikasi = "Pidana Khusus Migas", amar = "PIDANA PENJARA WAKTU TERTENTU",
             catatan_amar = "Menolak permohonan kasasi dari Pemohon Kasasi/Penuntut Umum tersebut", tanggal_dibacakan = "3 Maret 2021",
             lembaga_peradilan = "MAHKAMAH AGUNG", url = "https://putusan3.mahkamahagung.go.id/direktori/putusan/abcdefabcdefabcdef.html")
  r <- rekap_putusan(ov, sumber_daftar = "direktori migas-1")
  expect_equal(r$relevan_bbm, "Perlu dicek (tanpa PDF)")
  expect_equal(r$hasil_putusan, "Bersalah")

  # Kotak Putusan Terkait yang hanya berisi diri sendiri tidak mengambil tautan sidebar "Putusan Terbaru".
  x <- gsub("<tr><td>Pengadilan Tinggi</td>.*?</tr>|<tr><td>Kasasi</td>.*?</tr>", "", read_file(file.path(FIX, "overview_pn.html")), perl = TRUE)
  expect_length(parse_overview(x, "https://putusan3.mahkamahagung.go.id/direktori/putusan/1102e1cfc840bf73da0c2c1af05872e7.html")$terkait, 0)
  # Label "Nomor :" dan &nbsp; tetap terbaca.
  y <- gsub("<td>Nomor</td>", "<td>Nomor&nbsp;:</td>", read_file(file.path(FIX, "overview_pn.html")))
  expect_equal(parse_overview(y, "https://putusan3.mahkamahagung.go.id/direktori/putusan/1102e1cfc840bf73da0c2c1af05872e7.html")$nomor, "249/Pid.Sus/2020/PN Spt")
  # Paginasi pencarian dengan urutan/pengodean parameter berbeda.
  h <- "<a href='search.html?q=%22minyak+tanah%22&t_put=2022&page=7'>7</a><a href='/search.html?page=9&q=%22minyak%20tanah%22&t_put=2022'>9</a><a href='search.html?q=solar&t_put=2022&page=50'>x</a>"
  expect_equal(halaman_terakhir(h, url_pencarian("\"minyak tanah\"", 2022, 1)), 9)
  # Tautan sidebar di halaman daftar diabaikan.
  expect_false("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" %in% parse_daftar(read_file(file.path(FIX, "daftar_migas.html")))$id)
})

test_that("--url-list dan lanjutan antrean setelah CAPTCHA", {
  ov_html <- read_file(file.path(FIX, "overview_pn.html"))
  id_pn <- "1102e1cfc840bf73da0c2c1af05872e7"
  asli <- list(ambil_html = ambil_html, unduh_pdf = unduh_pdf)
  on.exit(for (n in names(asli)) assign(n, asli[[n]], envir = globalenv()), add = TRUE)
  diminta <- character(0)
  assign("unduh_pdf", function(url, tujuan, cfg) stop("tidak ada PDF di uji ini"), envir = globalenv())
  keluaran <- tempfile("hasil_"); dir.create(keluaran)
  daftar <- file.path(keluaran, "daftar.txt")
  writeLines(c(paste0("https://putusan3.mahkamahagung.go.id/direktori/putusan/", id_pn, ".html"), ""), daftar)
  # Putaran 1: putusan terkait meminta CAPTCHA -> antrean tersimpan.
  assign("ambil_html", function(url, cfg, folder_cache, pakai_cache = TRUE, ...) {
    if (identical(id_putusan(url), id_pn)) ov_html else stop(kondisi_captcha(url))
  }, envir = globalenv())
  suppressMessages(main(c("--mode=url", paste0("--url-list=", daftar), paste0("--keluaran=", keluaran), "--jeda=0")))
  expect_true(file.exists(file.path(keluaran, "antrean_tersisa.csv")))
  # Putaran 2: CAPTCHA hilang -> antrean dilanjutkan, berkas antrean dihapus.
  assign("ambil_html", function(url, cfg, folder_cache, pakai_cache = TRUE, ...) {
    diminta <<- c(diminta, id_putusan(url)); ov_html
  }, envir = globalenv())
  suppressMessages(main(c("--mode=url", paste0("--url-list=", daftar), paste0("--keluaran=", keluaran), "--jeda=0")))
  expect_true(all(c(strrep("c", 32), strrep("d", 32)) %in% diminta))
  expect_false(file.exists(file.path(keluaran, "antrean_tersisa.csv")))
})

test_that("penyamaran nama tidak menghapus kata amar dan menangkap pola nama lain", {
  amar <- "MENGADILI: 1. MENYATAKAN TERDAKWA TIDAK TERBUKTI SECARA SAH DAN MEYAKINKAN BERSALAH; 2. MEMBEBASKAN TERDAKWA OLEH KARENA ITU DARI SEMUA DAKWAAN PENUNTUT UMUM;"
  expect_equal(samarkan_nama(amar), amar)
  ov <- list(nomor = "1/Pid.Sus/2021/PN X", catatan_amar = sub("TERDAKWA TIDAK", "TERDAKWA AHMAD TIDAK", amar), tanggal_dibacakan = "3 Maret 2021")
  expect_equal(rekap_putusan(ov)$hasil_putusan, "Tidak bersalah")
  expect_equal(rekap_putusan(list(catatan_amar = "MELEPASKAN TERDAKWA OLEH KARENA ITU DARI SEGALA TUNTUTAN HUKUM"))$hasil_putusan, "Tidak bersalah")
  expect_equal(samarkan_nama("Menyatakan Terdakwa AHMAD ZAILANI Bin (Alm) SUWARTO SUDARSO tersebut"), "Menyatakan Terdakwa [nama] tersebut")
  expect_false(grepl("SUWARTO", samarkan_nama("dimintai tolong oleh Saksi SIGIT SUTRIYONO Bin (Alm)\nSUWARTO SUDARSO untuk")))
  expect_equal(samarkan_nama("membeli solar dari Pandoli seharga Rp6.000"), "membeli solar dari [nama] seharga Rp6.000")
  expect_equal(samarkan_nama("Nama lengkap : Syarif Syahrial; Tempat lahir : Padang"), "Nama lengkap : [nama]; Tempat lahir : Padang")
  expect_false(grepl("ARIS|WADI|SUGIYARTO", samarkan_nama("ARIS WADI Als RIS dan Saksi\nSUGIYARTO Bin SUPARNO tersebut")))
  expect_match(samarkan_nama("oleh Terdakwa\nM E N G A D I L I"), "M E N G A D I L I", fixed = TRUE)
  expect_equal(samarkan_nama("dari Januari 2020 sampai Maret 2021 oleh Penuntut Umum"), "dari Januari 2020 sampai Maret 2021 oleh Penuntut Umum")
  expect_equal(samarkan_nama("dibeli dari Sdr.Wongso dan dijual kepada Bapak Budi Santoso di Desa X"), "dibeli dari Sdr. [nama] dan dijual kepada Bapak [nama] di Desa X")
})

test_that("hasil dari amar yang dikutip, label subsidi", {
  t <- paste("Membaca Putusan Pengadilan Negeri Jambi Nomor 512/Pid.Sus/", "LH/2022/PN Jmb tanggal 9 Januari 2023 sebagai berikut:",
             "1. Menyatakan Terdakwa terbukti secara sah dan meyakinkan bersalah melakukan tindak pidana;", "Menimbang, bahwa banding",
             "M E N G A D I L I", "Menguatkan putusan Pengadilan Negeri Jambi tersebut;", "Demikian diputuskan", sep = "\n")
  expect_equal(hasil_dari_kutipan(t)[1], "Bersalah")
  campur <- paste("membeli sebanyak 10.000 liter BBM jenis Solar non subsidi dari PT X sedangkan sisanya 2.000 liter solar subsidi;",
                  "melakukan penyalahgunaan BBM yang disubsidi Pemerintah; menjual solar subsidi seolah-olah solar non subsidi")
  expect_equal(barang_bbm(NA, campur), "Solar (subsidi)")
  expect_equal(barang_bbm(NA, "minyak solar yang dibeli Terdakwa bukanlah minyak solar yang bersubsidi"), "Solar (non-subsidi)")
  expect_equal(barang_bbm(NA, "Terdakwa bukan konsumen yang berhak atas BBM subsidi jenis solar"), "Solar (subsidi)")
})

test_that("volume: wadah x isi, kapasitas, total, satuan di dalam kurung, skor konteks", {
  vb <- function(x) sum(volume_butir(x)$nilai)
  expect_equal(vb("10 jerigen kapasitas masing-masing 35 liter berisi solar sebanyak 200 liter"), 200)
  expect_equal(vb("1.200 (seribu dua ratus) botol masing-masing berisi 1 liter pertalite"), 1200)
  expect_equal(vb("10 jeriken @ 30 liter solar"), 300)
  expect_equal(vb("26 (dua puluh enam) jerigen berisi setiap 1 (satu) jerigen berisi 30 liter solar"), 780)
  expect_equal(vb("3 (tiga) buah jerigen kapasitas isi 25 liter masing-  masing berisi solar sebanyak 25 liter"), 75)
  expect_equal(vb(paste("± 4.500 liter BBM jenis Solar dimuat dalam 20 buah drum kapasitas 220 liter, yang masing-masing drum diisi",
                        "sebanyak ± 220 liter BBM jenis Solar dan 1 buah drum yang dimuat sebanyak ± 100 liter")), 4500)
  expect_equal(vb("10 (sepuluh) buah jerigen plastik kapasitas 20 liter yang berisi bahan bakar minyak jenis Pertalite"), 200)
  expect_equal(vb("27 (dua puluh tujuh) jerigen ukuran 30 liter minyak jenis bio solar"), 810)
  expect_equal(nrow(volume_butir("6 (enam) buah jerigen kosong isi 35 liter bekas solar")), 0)
  expect_equal(vb("5 buah jerigen isi 35 liter yang berisikan premium sebanyak 155,585 liter"), 155.585)
  expect_equal(vb("Sebanyak 560 liter Bio Solar, telah dilelang bersama-sama dengan perkara lain dengan total 695 (enam ratus sembilan puluh lima liter) solar"), 560)
  expect_true(810 %in% volume_bbm("sebanyak 27 (dua puluh tujuh) Jerigen atau 810 (delapan ratus sepuluh liter) solar")$nilai)
  nv <- function(x) nilai_volume(NA, x)$nilai
  expect_equal(nv("solar sebanyak 16.000 liter disimpan dalam 4 (empat) kempu kapasitas masing-masing 1.000 liter"), 16000)
  expect_equal(nv("membeli sebanyak 10.000 liter BBM jenis Solar non subsidi dari PT X sedangkan sisanya sebanyak 2.000 liter Terdakwa beli BBM jenis Solar Subsidi"), 2000)
  expect_equal(nv(paste("4 (empat) Buah drum berisi 60 liter BBM jenis premium; Dirampas untuk dimusnahkan. Bahwa pada saat ditangkap",
                        "terdakwa memproduksi total keseluruhan 1.210 liter BBM jenis premium")), 1210)
  expect_equal(nv("Terdakwa memesan solar sebanyak 700 liter. Kemudian ditemukan solar sebanyak 200 liter di dalam jerigen"), 200)
})

test_that("nilai uang: harga per wadah, uang yang diserahkan, penjualan langsung, harga beli", {
  j <- function(x) nominal_uang(x)$jenis[1]
  expect_equal(j("BBM jenis Bio Solar dengan harga pergalon isi 30 liter seharga Rp420.000"), "harga_per_wadah")
  expect_equal(j("Bio Solar oleh saksi satu jerigen isi 30 liter adalah seharga Rp200.000"), "harga_per_wadah")
  expect_equal(j("untuk membeli dan mengangkut BBM. Yang mengangkut BBM tersebut adalah Terdakwa dengan memberikan uang sejumlah Rp10.000.000"), "lain")
  expect_equal(j("solar 60.000 liter yang telah dilakukan penjualan langsung senilai Rp360.000.000"), "hasil_lelang")
  expect_equal(j("telah dilakukan lelang secara bersama-sama dengan perkara lain dengan total hasil lelang Rp4.726.000"), "lelang_gabungan")
  expect_equal(j("Print Out Bukti transfer pembelian BBM Solar senilai Rp25.000.000"), "lain")
  t <- paste("solar yang terdakwa beli dari [nama] penyalur di Kecamatan Juwana Kabupaten Pati Provinsi Jawa Tengah dengan harga Rp6.300 per liter;",
             "solar dijual kembali Rp6.500 per liter; dijual Rp6.500 per liter")
  expect_equal(nilai_kerugian(t, list(nilai = 6000, satuan = "liter"))$nilai, 37800000)
})

test_that("overview tanpa PDF: relevansi, rantai perkara, judul Putusan Terkait", {
  ov <- list(nomor = "25 K/PID.SUS-LH/2020", klasifikasi = "Pidana Khusus", kata_kunci = "Penyalahgunaan Pengangkutan Solar Bersubsidi",
             catatan_amar = "Menolak permohonan kasasi dari Pemohon Kasasi/Penuntut Umum tersebut", tanggal_dibacakan = "3 Maret 2020",
             url = "https://putusan3.mahkamahagung.go.id/direktori/putusan/abcdefabcdefabcdef.html")
  expect_equal(rekap_putusan(ov, sumber_daftar = "putusan terkait")$relevan_bbm, "Ya")

  pn <- rekap_putusan(list(), teks_pdf(file.path(DATA, "pdf", "266_Pid.Sus_2019_PN Pli.pdf")), "pdf/266.pdf")
  skip_if(is.na(pn$nomor_putusan))
  pn$url_putusan <- "https://putusan3.mahkamahagung.go.id/direktori/putusan/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.html"
  pn$id_terkait <- "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
  pt <- rekap_putusan(list(nomor = "10/PID.SUS/2020/PT BJM", klasifikasi = "Pidana Khusus Lain-lain", jenis_lembaga_peradilan = "PT",
                           lembaga_peradilan = "PT BANJARMASIN", catatan_amar = "Menguatkan putusan Pengadilan Negeri Pelaihari tersebut",
                           tanggal_dibacakan = "5 Mei 2020", lampiran_pdf = "Tidak ada",
                           url = "https://putusan3.mahkamahagung.go.id/direktori/putusan/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb.html"),
                      sumber_daftar = "putusan terkait")
  expect_equal(pt$relevan_bbm, "Tidak")
  s <- lengkapi_rantai(bind_rows(pn, pt))
  expect_equal(s$relevan_bbm[2], "Perlu dicek (putusan terkait BBM)")
  expect_equal(s$hasil_putusan[2], "Bersalah")
  expect_equal(s$barang_bbm[2], pn$barang_bbm)
  expect_equal(s$nilai_kerugian_volume[2], "92")
  expect_match(s$dasar_volume[2], "dari putusan terkait")
  expect_equal(s$lokasi_kejadian[2], pn$lokasi_kejadian)

  x <- read_file(file.path(FIX, "overview_pn.html")); u <- "https://putusan3.mahkamahagung.go.id/direktori/putusan/1102e1cfc840bf73da0c2c1af05872e7.html"
  terkait <- function(h) id_putusan(parse_overview(h, u)$terkait)
  cd <- c(strrep("c", 32), strrep("d", 32))
  expect_setequal(terkait(sub("<h4>Putusan Terkait</h4>", "<h4>\n  <i class=\"icon\"></i> Putusan Terkait</h4>", x, fixed = TRUE)), cd)
  expect_setequal(terkait(sub("<h4>Putusan Terkait</h4>", "<h4><span>Putusan</span> Terkait</h4>", x, fixed = TRUE)), cd)
  expect_length(terkait(gsub('(?s)<div class="card-body">.*?</div>', '<div class="card-body"><p>Tidak ada putusan terkait</p></div>', x, perl = TRUE)), 0)
})

test_that("HTTP: 503 tanpa Retry-After diulang, 403 biasa bukan CAPTCHA, reCAPTCHA v3 bukan CAPTCHA, robots sekali", {
  resp <- function(kode, isi = "", hdr = list()) structure(list(url = "u", status_code = kode, headers = httr:::insensitive(hdr),
                                                                content = charToRaw(isi)), class = "response")
  cfg <- modifyList(KONFIG, list(jeda_detik = 0, maks_coba = 3))
  asli <- list(GET = if (exists("GET", envir = globalenv(), inherits = FALSE)) get("GET", envir = globalenv()) else NULL)
  on.exit({ if (is.null(asli$GET)) rm("GET", envir = globalenv()) else assign("GET", asli$GET, envir = globalenv()) }, add = TRUE)
  rm(list = ls(.robots_cache), envir = .robots_cache)
  n <- c(robots = 0, lain = 0); antre_resp <- list()
  assign("GET", function(url, ...) {
    if (grepl("robots\\.txt$", url)) { n[["robots"]] <<- n[["robots"]] + 1; return(resp(404)) }
    n[["lain"]] <<- n[["lain"]] + 1; r <- antre_resp[[1]]; antre_resp <<- antre_resp[-1]; r
  }, envir = globalenv())
  antre_resp <- list(resp(503), resp(200, "<html>ok</html>"))
  expect_equal(status_code(minta("https://contoh.test/a.html", cfg)), 200)
  expect_equal(n[["lain"]], 2)
  antre_resp <- list(resp(403, "<html>Forbidden</html>"))
  e <- tryCatch(minta("https://contoh.test/b.html", cfg), error = function(e) e)
  expect_false(inherits(e, "captcha_error")); expect_match(conditionMessage(e), "HTTP 403")
  antre_resp <- list(resp(403, "<title>Just a moment...</title><div id='cf-chl-widget'></div>"))
  expect_error(minta("https://contoh.test/c.html", cfg), class = "captcha_error")
  expect_equal(n[["robots"]], 1)
  expect_false(mirip_captcha("<script src='https://www.google.com/recaptcha/api.js?render=abc'></script><td>Nomor</td>"))
  expect_true(mirip_captcha("<div class=\"g-recaptcha\" data-sitekey=\"x\"></div>"))
})

test_that("lanjutan: PDF putusan terkait yang gagal diunduh diulang; sumber daftar asli tetap setelah CAPTCHA", {
  pdf_contoh <- file.path(DATA, "pdf", "266_Pid.Sus_2019_PN Pli.pdf")
  skip_if_not(file.exists(pdf_contoh))
  ov_html <- read_file(file.path(FIX, "overview_pn.html"))
  id_pn <- "1102e1cfc840bf73da0c2c1af05872e7"
  varian <- function(id) if (identical(id, id_pn)) ov_html else gsub("249/Pid.Sus/2020/PN Spt", paste0("1/PID.SUS/2021/PT ", substr(id, 1, 1)), ov_html, fixed = TRUE)
  asli <- list(ambil_html = ambil_html, unduh_pdf = unduh_pdf)
  on.exit(for (k in names(asli)) assign(k, asli[[k]], envir = globalenv()), add = TRUE)
  assign("ambil_html", function(url, cfg, folder_cache, pakai_cache = TRUE, ...) varian(id_putusan(url)), envir = globalenv())
  gagal_c <- TRUE
  # PT tiruan untuk id cccc... bernomor "1/PID.SUS/2021/PT c" -> berkas 1_PID.SUS_2021_PT_c.pdf
  assign("unduh_pdf", function(url, tujuan, cfg) {
    if (gagal_c && grepl("PT_c\\.pdf$", tujuan)) stop("HTTP 500")
    dir.create(dirname(tujuan), recursive = TRUE, showWarnings = FALSE); file.copy(pdf_contoh, tujuan); tujuan
  }, envir = globalenv())
  keluaran <- tempfile("hasil_")
  arg <- c("--mode=url", paste0("--url=https://putusan3.mahkamahagung.go.id/direktori/putusan/", id_pn, ".html"), paste0("--keluaran=", keluaran), "--jeda=0")
  suppressMessages(main(arg))
  s1 <- read_csv(file.path(keluaran, "semua_putusan_diperiksa.csv"), show_col_types = FALSE, col_types = cols(.default = "c"))
  expect_equal(nrow(s1), 3)
  expect_equal(s1$sumber_data[id_putusan(s1$url_putusan) == strrep("c", 32)], "Overview direktori")
  gagal_c <- FALSE
  suppressMessages(main(arg))
  s2 <- read_csv(file.path(keluaran, "semua_putusan_diperiksa.csv"), show_col_types = FALSE, col_types = cols(.default = "c"))
  expect_equal(nrow(s2), 3)
  expect_equal(s2$sumber_data[id_putusan(s2$url_putusan) == strrep("c", 32)], "PDF putusan")
  expect_equal(s2$sumber_daftar[id_putusan(s2$url_putusan) == strrep("c", 32)], "putusan terkait")

  # Sumber daftar "pencarian: solar" tetap tercatat untuk putusan yang dilanjutkan dari antrean.
  tanpa_bbm <- gsub("Pidana Khusus Migas", "Pidana Khusus", gsub("(?s)<a[^>]+download_file[^>]+>.*?</a>", "", ov_html, perl = TRUE))
  tanpa_bbm <- gsub("(?i)solar|bbm|bahan bakar minyak|migas", "barang", tanpa_bbm, perl = TRUE)
  ids <- c(strrep("a", 32), strrep("b", 32))
  daftar <- tibble(id = ids, url = paste0("https://putusan3.mahkamahagung.go.id/direktori/putusan/", ids, ".html"),
                   nomor = NA_character_, tanggal_putus = NA_character_, sumber_daftar = "pencarian: solar")
  cfg <- modifyList(KONFIG, list(jeda_detik = 0, ikuti_terkait = FALSE))
  k2 <- tempfile("hasil_"); dir.create(k2)
  assign("ambil_html", function(url, cfg, folder_cache, pakai_cache = TRUE, ...) {
    if (identical(id_putusan(url), ids[2])) stop(kondisi_captcha(url)) else gsub("249/Pid.Sus/2020/PN Spt", "7/Pid.Sus/2020/PN Spt", tanpa_bbm, fixed = TRUE)
  }, envir = globalenv())
  expect_error(suppressMessages(telusuri(daftar, cfg, k2)), class = "captcha_error")
  expect_equal(read_csv(file.path(k2, "antrean_tersisa.csv"), show_col_types = FALSE)$sumber_daftar, "pencarian: solar")
  assign("ambil_html", function(url, cfg, folder_cache, pakai_cache = TRUE, ...) gsub("249/Pid.Sus/2020/PN Spt", "8/Pid.Sus/2020/PN Spt", tanpa_bbm, fixed = TRUE), envir = globalenv())
  s <- suppressMessages(telusuri(daftar[0, ], cfg, k2))
  expect_equal(s$sumber_daftar, c("pencarian: solar", "pencarian: solar"))
  expect_equal(s$relevan_bbm, c("Perlu dicek (tanpa PDF)", "Perlu dicek (tanpa PDF)"))
  expect_false(file.exists(file.path(k2, "antrean_tersisa.csv")))
})


test_that("tinjauan PR #3: penyamaran nama", {
  tidak_ada <- function(x, pola) expect_false(grepl(pola, samarkan_nama(x)), info = x)
  tetap <- function(x) expect_equal(samarkan_nama(x), x)
  tidak_ada("milik Terdakwa Syarif\nSyahrial, akan Terdakwa jual", "Syahrial")
  expect_equal(samarkan_nama("saksi Gusma Deri\nPanggilan Adek berusaha"), "saksi [nama] berusaha")
  expect_match(samarkan_nama("kepada saksi Budi\nRp 9.000 per liter"), "Rp 9.000", fixed = TRUE)
  expect_match(samarkan_nama("Terdakwa Budi Santoso\nBertempat di Desa X"), "Bertempat di Desa X", fixed = TRUE)
  tidak_ada("1. Saksi Hari Purwanto dibawah sumpah", "Hari|Purwanto")
  tidak_ada("dilakukan oleh Pak Agung dengan", "Agung")
  for (x in c("pada Hari Senin", "oleh Majelis Hakim", "oleh Hakim Ketua", "kepada Mahkamah Agung", "dari Juli 2020 sampai Agustus 2020",
              "Anak Buah Kapal", "Terdakwa Rp500,00", "Perubahan dari K-1610-LN", "terdakwa I dan terdakwa II",
              "Halaman 17 dari 18\nDemikianlah", "dari POM Bensin.")) tetap(x)
  tidak_ada("bertempat di rumah Yayat alias Gapuak (DPO)", "Yayat|Gapuak")
  tidak_ada("Terdakwa 1. Lai Lie Fung als. Afung anak Lai Bujang", "Lai|Afung|Bujang")
  tidak_ada("dibantu oleh sdra IDRIS", "IDRIS")
  tidak_ada("terdakwa SUTIKNO Als.Jek bin\nS.Prapto", "SUTIKNO|Jek|Prapto")
  tidak_ada("STNK An. BARATA AKANG, Nomor", "BARATA")
  expect_equal(samarkan_nama("perkara an. Arige Pandu;"), "perkara an. [nama];")
  tidak_ada("nama pemilik SALIM - 1 unit", "SALIM")
  tidak_ada("Yoseph Anak Dari Bapak\nStepanus Bili", "Stepanus")
  tidak_ada("milik pak Sugiyarto", "Sugiyarto")
  tidak_ada("Terdakwa I. DWI ARMADI bin IDRIS", "DWI|IDRIS")
  tidak_ada("Saksi V. Simanjuntak", "Simanjuntak")
  tidak_ada("Terdakwa II.\nNama : Hardi Isfandiari Panggilan Hardi;", "Hardi")
  tidak_ada("bahwa oleh karena TerdakwaHardi Isfandiari Pgl Hardi\nberada", "Hardi|Isfandiari")
})

test_that("tinjauan PR #3: volume", {
  vb <- function(x) { v <- volume_butir(x); if (nrow(v)) sum(v$nilai) else NA_real_ }
  expect_equal(vb("- 83 (delapan puluh tiga) gallon berukuran 35 liter berisi BBM jenis solar;"), 2905)
  expect_equal(vb("- 4 (dua) drum isi 215 liter, berisi BBM jenis premium"), 860)
  expect_equal(vb("- 10 (sepuluh) jurigen plastik isi 35 Liter berisi BBM jenis premium"), 350)
  expect_equal(vb(paste("37 (tiga puluh tujuh) buah jerigen berisi Bahan Bakar Minyak (BBM) bersubsidi jenis solar dimana 26 (dua puluh enam)",
                        "jerigen berisi setiap 1 (satu) jerigen berisi 30 liter dan 1 (satu) jerigen berisi 20 liter")), 800)
  expect_true(is.na(vb("- Teko plastik warna putih untuk memindahkan BBM jenis premium ke jurigen Plastik isi 35 liter")))
  expect_equal(vb("20 drum masing-masing berisi ± 200 liter solar dengan jumlah keseluruhan 3.890,224 liter"), 3890.224)
  expect_equal(vb("20 drum masing-masing berisi 200 liter solar dan 5 jerigen solar dengan total 100 liter"), 4100)
  expect_equal(vb("1 (satu) buah drum kapasitas isi 220 liter berisi bahan bakar minyak jenis solar sebanyak 150 liter"), 150)
  expect_equal(vb("1 (satu) buah drum kapasitas isi 220 liter berisi bahan bakar minyak jenis solar"), 220)
  expect_true(is.na(vb("10 jerigen kapasitas 35 liter dalam keadaan kosong bekas tempat solar")))
  expect_equal(vb("3 (tiga) buah baby tank kapasitas 1.000 liter masing-masing berisi 900 liter BBM jenis solar"), 2700)
  v <- nilai_volume("- 5 (lima) ton solar;\n- 200 liter solar", NA)
  expect_equal(v$nilai, 5200); expect_equal(v$satuan, "liter"); expect_match(v$dasar, "5 ton (= 5.000 liter)", fixed = TRUE)
  expect_equal(nilai_volume(NA, "Bahwa terdakwa memesan kepada PT. Maju Jaya solar sebanyak 10.000 liter. Kemudian ditemukan solar sebanyak 2.000 liter")$nilai, 2000)
  expect_equal(nilai_volume(NA, "upah untuk per 1 ( satu ) ton Rp 300.000 dan disita solar sebanyak 600 liter")$nilai, 600)
})

test_that("tinjauan PR #3: nilai uang", {
  j <- function(x) nominal_uang(x)$jenis[1]
  expect_equal(j("BBM dijual di Tempat Pelelangan Ikan (TPI) dengan harga Rp 6.000 per liter"), "harga_per_liter")
  expect_equal(j("barang bukti solar dilelang, serta menjatuhkan pidana denda sebesar Rp5.000.000"), "denda")
  expect_equal(j("barang bukti dalam perkara ini telah dilelang dengan hasil sebesar Rp19.930.365"), "hasil_lelang")
  expect_equal(j("Terdakwa menjual BBM jenis solar tersebut sebanyak 600 liter dan mendapatkan uang sebesar Rp 4.500.000"), "nilai_transaksi")
  expect_equal(j("harga Rp240.000,- (dua ratus empat puluh ribu rupiah) per jiregen isi 35 liter"), "harga_per_wadah")
  t <- paste("Sebanyak kurang lebih 560 (lima ratus enam puluh) liter Bahan bakar Minyak jenis Bio Solar yang disubsidi Pemerintah,",
             "telah dilakukan lelang secara bersama-sama pada saat tahap penyidikan dengan perkara [nama] dan [nama] DKK dengan total",
             "695 (enam ratus sembilan puluh lima liter) bahan bakar minyak jenis bio solar dengan total hasil lelang Rp4.726.000,00")
  expect_equal(nilai_kerugian(t, list(nilai = 560, satuan = "liter"))$nilai, round(4726000 * 560 / 695))
  t2 <- "solar dijual kembali seharga Rp 6.400 per liter; untuk pembelian minyak solar di SPBU seharga Rp 6.400 per liter"
  expect_match(nilai_kerugian(t2, list(nilai = 100, satuan = "liter"))$dasar, "pembelian minyak solar")
})

test_that("tinjauan PR #3: label subsidi dan kata BBM", {
  expect_equal(barang_bbm(NA, "BBM jenis Bensin (Premium) merupakan BBM Khusus Penugasan dan tidak disubsidi oleh Pemerintah; premium"), "Premium (non-subsidi)")
  amar <- "denda Rp 1.000.000 subsidiair 1 bulan kurungan; 3. Menyatakan barang bukti berupa: - BBM jenis solar 20 liter"
  expect_equal(barang_bbm(amar, amar), "Solar")
  expect_equal(barang_bbm("barang bukti 20 liter solar", "pengangkutan solar bersubsidi; solar subsidi; barang bukti 20 liter solar"), "Solar (subsidi)")
  expect_length(hitung_bbm("pencurian lampu jalan solar cell dan beras premium"), 0)
  expect_equal(unname(hitung_bbm("BBM jenis bio\nsolar")), 1)
})

test_that("tinjauan PR #3: HTTP, robots, halaman galat", {
  expect_true(mirip_captcha("<script src='https://www.google.com/recaptcha/api.js?onload=cb&render=explicit'></script><script>grecaptcha.render('kotak')</script>"))
  expect_false(mirip_captcha("<input type='hidden' name='recaptcha_response'><script src='https://www.google.com/recaptcha/api.js?render=abc'></script><td>Nomor</td>"))
  expect_true(mirip_captcha("<img src='captcha.php'><input type='text' name='captcha'>"))
  ov <- read_file(file.path(FIX, "overview_pn.html"))
  expect_true(halaman_dikenali(paste("<h4>A PHP Error was encountered</h4><p>Severity: Notice</p>", ov), "overview"))
  expect_false(halaman_dikenali(paste(ov, "<h4>A PHP Error was encountered</h4><p>Severity: Error</p>"), "overview"))

  resp <- function(kode, isi = "") structure(list(url = "u", status_code = kode, headers = httr:::insensitive(list()),
                                                  content = charToRaw(isi)), class = "response")
  cfg <- modifyList(KONFIG, list(jeda_detik = 0, maks_coba = 2))
  asli <- if (exists("GET", envir = globalenv(), inherits = FALSE)) get("GET", envir = globalenv()) else NULL
  on.exit({ if (is.null(asli)) rm("GET", envir = globalenv()) else assign("GET", asli, envir = globalenv()) }, add = TRUE)
  rm(list = ls(.robots_cache), envir = .robots_cache); .terakhir_minta$n403 <- 0
  kode_robots <- 503
  assign("GET", function(url, ...) if (grepl("robots\\.txt$", url)) resp(kode_robots) else resp(403, "<html>Forbidden</html>"), envir = globalenv())
  expect_error(minta("https://contoh.test/a.html", cfg), class = "robots_error")
  expect_false(exists("https://contoh.test", envir = .robots_cache, inherits = FALSE))
  kode_robots <- 404
  e1 <- tryCatch(minta("https://contoh.test/a.html", cfg), error = function(e) e)
  e2 <- tryCatch(minta("https://contoh.test/b.html", cfg), error = function(e) e)
  expect_false(inherits(e1, "captcha_error")); expect_false(inherits(e2, "captcha_error"))
  expect_error(minta("https://contoh.test/c.html", cfg), class = "captcha_error")   # 403 ketiga berturut-turut
})

test_that("tinjauan PR #3: rantai perkara", {
  baris <- function(id, tingkat, sumber, hasil, dasar_hasil, relevan = "Ya", barang = NA, terkait = NA)
    tibble(url_putusan = paste0("https://putusan3.mahkamahagung.go.id/direktori/putusan/", strrep(id, 32), ".html"),
           nomor_putusan = paste0(id, "/", tingkat), tingkat_persidangan = tingkat, sumber_data = sumber, hasil_putusan = hasil,
           dasar_hasil = dasar_hasil, relevan_bbm = relevan, barang_bbm = barang, jenis_bbm_disebut = NA, tahun_kejadian = NA,
           nilai_kerugian_volume = NA, satuan_volume = NA, dasar_volume = NA, nilai_kerugian_uang = NA, mata_uang = NA,
           dasar_nilai_uang = NA, lokasi_kejadian = NA, provinsi = NA, kabupaten_kota = NA, dasar_lokasi = NA, id_terkait = terkait)
  s <- bind_rows(baris("a", "PN", "PDF putusan", "Bersalah", "amar", barang = "Solar (subsidi)", terkait = paste(strrep("b", 32), strrep("c", 32), sep = ";")),
                 baris("b", "PT", "Overview direktori", "Tidak bersalah", "amar: terdakwa dibebaskan", relevan = "Tidak"),
                 baris("c", "MA", "Overview direktori", NA, "kasasi penuntut umum ditolak: ikut putusan sebelumnya", relevan = "Ya",
                       barang = "BBM (jenis tidak disebut)"),
                 baris("d", NA, "Overview direktori", NA, "kasasi penuntut umum ditolak: ikut putusan sebelumnya", relevan = "Tidak",
                       terkait = strrep("a", 32)))
  h <- lengkapi_rantai(s)
  expect_equal(h$hasil_putusan[3], "Tidak bersalah")        # dari PT yang membebaskan, bukan dari PN
  expect_equal(h$barang_bbm[3], "Solar (subsidi)")
  expect_true(is.na(h$hasil_putusan[4])); expect_false(grepl("NA\\)", h$dasar_hasil[4]))
})

test_that("tinjauan PR #3: lanjutan dari versi lama, putusan terkait yang gagal, PDF rusak", {
  pdf_contoh <- file.path(DATA, "pdf", "266_Pid.Sus_2019_PN Pli.pdf")
  skip_if_not(file.exists(pdf_contoh))
  ov_html <- read_file(file.path(FIX, "overview_pn.html"))
  id_pn <- "1102e1cfc840bf73da0c2c1af05872e7"
  asli <- list(ambil_html = ambil_html, unduh_pdf = unduh_pdf)
  on.exit(for (k in names(asli)) assign(k, asli[[k]], envir = globalenv()), add = TRUE)
  diminta <- character(0); gagal_c <- TRUE
  assign("ambil_html", function(url, cfg, folder_cache, pakai_cache = TRUE, ...) {
    id <- id_putusan(url); diminta <<- c(diminta, id)
    if (identical(id, id_pn)) return(ov_html)
    if (gagal_c && identical(id, strrep("c", 32))) stop("HTTP 500")
    gsub("249/Pid.Sus/2020/PN Spt", paste0("1/PID.SUS/2021/PT ", substr(id, 1, 1)), ov_html, fixed = TRUE)
  }, envir = globalenv())
  assign("unduh_pdf", function(url, tujuan, cfg) {
    dir.create(dirname(tujuan), recursive = TRUE, showWarnings = FALSE); file.copy(pdf_contoh, tujuan, overwrite = TRUE); tujuan
  }, envir = globalenv())
  keluaran <- tempfile("hasil_")
  arg <- c("--mode=url", paste0("--url=https://putusan3.mahkamahagung.go.id/direktori/putusan/", id_pn, ".html"), paste0("--keluaran=", keluaran), "--jeda=0")
  suppressMessages(main(arg))
  s1 <- read_csv(file.path(keluaran, "semua_putusan_diperiksa.csv"), show_col_types = FALSE, col_types = cols(.default = "c"))
  expect_equal(nrow(s1), 2)   # cccc gagal (HTTP 500)
  gagal_c <- FALSE; diminta <- character(0)
  suppressMessages(main(arg))
  s2 <- read_csv(file.path(keluaran, "semua_putusan_diperiksa.csv"), show_col_types = FALSE, col_types = cols(.default = "c"))
  expect_equal(diminta, strrep("c", 32))   # hanya putusan terkait yang belum terekam
  expect_equal(nrow(s2), 3)
  expect_equal(nrow(read_csv(file.path(keluaran, "log_gagal.csv"), show_col_types = FALSE)), 1)

  # Baris dari versi skrip sebelumnya (tanpa versi_ekstraksi, nama tidak tersamar) dihitung ulang dan disamarkan.
  s3 <- s2 |> select(-versi_ekstraksi) |> mutate(dasar_volume = "SUWARTO SUDARSO meminta 16.000 liter", dasar_nilai_uang = "solar dari Pandoli seharga")
  s3$tahun_putusan[3] <- "2015"   # di luar rentang: tidak dihitung ulang, tetapi tetap disamarkan
  write_csv(s3, file.path(keluaran, "semua_putusan_diperiksa.csv"), na = "NA")
  diminta <- character(0)
  suppressMessages(main(arg))
  s4 <- read_csv(file.path(keluaran, "semua_putusan_diperiksa.csv"), show_col_types = FALSE, col_types = cols(.default = "c"))
  expect_setequal(diminta, c(id_pn, strrep("d", 32)))
  expect_true(all(s4$versi_ekstraksi[id_putusan(s4$url_putusan) != strrep("c", 32)] == VERSI_EKSTRAKSI))
  dihitung <- id_putusan(s4$url_putusan) != strrep("c", 32)
  expect_false(any(grepl("SUWARTO|Pandoli", c(s4$dasar_volume[dihitung], s4$dasar_nilai_uang[dihitung]))))
  # Baris di luar rentang tahun tidak dihitung ulang; nama setelah kata pemicu ("dari") tetap disamarkan ulang.
  expect_equal(s4$dasar_nilai_uang[!dihitung], "solar dari [nama] seharga")

  # PDF rusak di disk diunduh ulang.
  f <- tempfile(fileext = ".pdf"); writeLines("%PDF-1.4 rusak", f)
  assign("unduh_pdf", asli$unduh_pdf, envir = globalenv())
  asli_minta <- minta; on.exit(assign("minta", asli_minta, envir = globalenv()), add = TRUE)
  assign("minta", function(url, cfg, simpan_ke = NULL) { file.copy(pdf_contoh, simpan_ke, overwrite = TRUE); TRUE }, envir = globalenv())
  unduh_pdf("https://contoh.test/x.pdf", f, KONFIG)
  expect_true(pdf_terbaca(f))
})
