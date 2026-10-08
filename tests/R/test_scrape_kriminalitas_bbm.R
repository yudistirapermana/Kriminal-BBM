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
  expect_true(file.exists(file.path(keluaran, "antrean_tersisa.txt")))
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
  expect_true(file.exists(file.path(keluaran, "antrean_tersisa.txt")))
  # Putaran 2: CAPTCHA hilang -> antrean dilanjutkan, berkas antrean dihapus.
  assign("ambil_html", function(url, cfg, folder_cache, pakai_cache = TRUE, ...) {
    diminta <<- c(diminta, id_putusan(url)); ov_html
  }, envir = globalenv())
  suppressMessages(main(c("--mode=url", paste0("--url-list=", daftar), paste0("--keluaran=", keluaran), "--jeda=0")))
  expect_true(all(c(strrep("c", 32), strrep("d", 32)) %in% diminta))
  expect_false(file.exists(file.path(keluaran, "antrean_tersisa.txt")))
})
