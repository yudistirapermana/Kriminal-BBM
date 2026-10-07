# Ringkasan statistik kriminalitas BBM (Direktori Putusan MA)

Dibuat otomatis oleh `python -m kriminal_bbm analyze` dari `rekap_putusan_kriminalitas_BBM_2020-2026.csv`. Jangan disunting manual; jalankan ulang perintahnya.

- Baris rekap: 166; entri direktori ganda yang dibuang: 2 (baris no 60, 46).
- Putusan unik: 164; perkara unik (rantai): 107.
- Perkara dengan volume dalam liter: 99; total 590.628 liter (median 720 liter).
- Kelompok kejadian yang kemungkinan sama (berkas terpisah/splitsing): 5 kelompok mencakup 12 rantai. Bila tiap kelompok dihitung sekali, total volume menjadi 418.827 liter.

Catatan tafsir:

1. Dataset adalah SAMPEL (klasifikasi Migas + rantai perkaranya + tabulasi tim), bukan populasi putusan BBM.
   Perubahan jumlah antartahun mencerminkan jalur penemuan, bukan tren kriminalitas.
   Khususnya, hampir semua putusan 2026 berasal dari tabulasi tim (`sumber_daftar`), bukan dari klasifikasi Migas.
2. Volume diambil dari putusan tingkat pertama bila ada; satu perkara dihitung sekali.
3. `nilai_uang_rp` umumnya nilai BBM barang bukti, bukan kerugian negara; baca `dasar_nilai_uang`.
4. Hasil akhir = status terdakwa menurut putusan paling akhir di dataset; perkara yang upaya hukumnya
   di luar 2020-2026 atau tidak ditemukan berhenti pada tingkat yang tersedia.

## Putusan per tahun putusan dan tingkat (setelah entri ganda dibuang)

| tahun_putusan | MA | PN | PT | Pengadilan Militer | Total |
|---|---|---|---|---|---|
| 2020 | 13 | 19 | 12 | 0 | 44 |
| 2021 | 5 | 10 | 4 | 0 | 19 |
| 2022 | 12 | 2 | 0 | 0 | 14 |
| 2023 | 14 | 11 | 10 | 0 | 35 |
| 2024 | 3 | 2 | 0 | 0 | 5 |
| 2025 | 0 | 0 | 0 | 1 | 1 |
| 2026 | 0 | 46 | 0 | 0 | 46 |
| Total | 47 | 90 | 26 | 1 | 164 |

## Perkara per tahun putusan paling awal di dataset dan hasil akhir

| tahun_putusan_awal | Bersalah | NA | Tidak bersalah | Total |
|---|---|---|---|---|
| 2020 | 31 | 0 | 0 | 31 |
| 2021 | 9 | 1 | 0 | 10 |
| 2022 | 1 | 0 | 1 | 2 |
| 2023 | 14 | 0 | 1 | 15 |
| 2024 | 2 | 0 | 0 | 2 |
| 2025 | 1 | 0 | 0 | 1 |
| 2026 | 46 | 0 | 0 | 46 |
| Total | 104 | 1 | 2 | 107 |

## Volume BBM (liter) per perkara menurut tahun putusan awal

| tahun_putusan_awal | perkara | perkara_dengan_volume | total_liter | median_liter | rata2_liter | p90_liter | maks_liter |
|---|---|---|---|---|---|---|---|
| 2020 | 31 | 29 | 196.445 | 1.000 | 6.774 | 22.197 | 46.000 |
| 2021 | 10 | 10 | 46.257 | 1.950 | 4.626 | 14.920 | 14.920 |
| 2022 | 2 | 2 | 2.507 | 1.254 | 1.254 | 2.099 | 2.310 |
| 2023 | 15 | 14 | 281.366 | 10.028 | 20.098 | 60.000 | 60.000 |
| 2024 | 2 | 2 | 1.078 | 539 | 539 | 922 | 1.018 |
| 2025 | 1 | 1 | 363 | 363 | 363 | 363 | 363 |
| 2026 | 46 | 41 | 62.612 | 400 | 1.527 | 2.520 | 16.000 |

## Perkara per jenis BBM (volume hanya untuk perkara satu jenis BBM)

| jenis_bbm | perkara_menyebut | perkara_satu_jenis | total_liter_satu_jenis | median_liter_satu_jenis |
|---|---|---|---|---|
| solar | 65 | 56 | 468.089 | 1.845 |
| pertalite | 35 | 27 | 6.268 | 150 |
| premium | 13 | 10 | 4.799 | 156 |
| pertamax | 1 | 0 | 0 |  |
| dexlite | 1 | 0 | 0 |  |
| minyak_tanah | 4 | 1 | 600 | 600 |
| minyak_mentah_olahan | 4 | 0 | 0 |  |
| tidak_disebut | 1 | 1 | 0 |  |

## Perkara menurut status subsidi BBM objek perkara

| status_subsidi | perkara | perkara_dengan_volume | total_liter | median_liter | rata2_liter | p90_liter | maks_liter |
|---|---|---|---|---|---|---|---|
| non-subsidi | 5 | 5 | 13.207 | 1.007 | 2.641 | 5.600 | 6.000 |
| penugasan (JBKP) | 42 | 39 | 34.066 | 180 | 873 | 1.608 | 16.000 |
| subsidi | 48 | 44 | 334.065 | 1.256 | 7.592 | 21.620 | 60.000 |
| tidak disebut | 12 | 11 | 209.289 | 14.920 | 19.026 | 46.000 | 60.000 |

## Perkara per provinsi (dari pengadilan tingkat pertama/banding)

| provinsi | perkara | perkara_dengan_volume | total_liter | median_liter | rata2_liter | p90_liter | maks_liter |
|---|---|---|---|---|---|---|---|
| Kalimantan Selatan | 12 | 11 | 39.602 | 1.000 | 3.600 | 8.260 | 20.500 |
| Jawa Tengah | 12 | 12 | 142.528 | 13.981 | 11.877 | 23.303 | 28.987 |
| Jawa Timur | 12 | 12 | 7.132 | 490 | 594 | 1.307 | 1.450 |
| Kalimantan Barat | 7 | 7 | 9.018 | 720 | 1.288 | 2.738 | 3.890 |
| Kalimantan Tengah | 6 | 5 | 6.633 | 480 | 1.327 | 3.452 | 5.353 |
| Sumatera Utara | 5 | 5 | 197.500 | 60.000 | 39.500 | 60.000 | 60.000 |
| Jambi | 4 | 4 | 12.325 | 3.100 | 3.081 | 6.000 | 6.000 |
| Bengkulu | 4 | 3 | 2.250 | 200 | 750 | 1.640 | 2.000 |
| Kalimantan Timur | 4 | 4 | 2.035 | 440 | 509 | 960 | 1.080 |
| Sumatera Barat | 4 | 4 | 1.977 | 506 | 494 | 810 | 810 |
| Sumatera Selatan | 4 | 3 | 38.159 | 16.000 | 12.720 | 20.880 | 22.100 |
| Maluku | 3 | 1 | 2.240 | 2.240 | 2.240 | 2.240 | 2.240 |
| Sulawesi Selatan | 3 | 3 | 4.824 | 1.720 | 1.608 | 2.744 | 3.000 |
| Sulawesi Tengah | 3 | 3 | 636 | 66 | 212 | 461 | 560 |
| Kepulauan Riau | 3 | 3 | 2.849 | 1.056 | 950 | 1.091 | 1.100 |
| Lampung | 3 | 3 | 2.857 | 350 | 952 | 1.918 | 2.310 |
| Bali | 2 | 1 | 34 | 34 | 34 | 34 | 34 |
| Aceh | 2 | 2 | 157 | 78 | 78 | 109 | 117 |
| Jawa Barat | 2 | 2 | 1.078 | 539 | 539 | 922 | 1.018 |
| DI Yogyakarta | 2 | 2 | 513 | 256 | 256 | 342 | 363 |
| Tidak diketahui | 2 | 1 | 583 | 583 | 583 | 583 | 583 |
| Riau | 2 | 2 | 46.108 | 23.054 | 23.054 | 41.411 | 46.000 |
| Gorontalo | 1 | 1 | 4.055 | 4.055 | 4.055 | 4.055 | 4.055 |
| DKI Jakarta | 1 | 1 | 27.911 | 27.911 | 27.911 | 27.911 | 27.911 |
| Papua | 1 | 1 | 33.705 | 33.705 | 33.705 | 33.705 | 33.705 |
| Nusa Tenggara Timur | 1 | 1 | 2.520 | 2.520 | 2.520 | 2.520 | 2.520 |
| Maluku Utara | 1 | 1 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 |
| Papua Barat | 1 | 1 | 400 | 400 | 400 | 400 | 400 |

## Perkara per pasal UU 22/2001 yang disebut (satu perkara bisa >1 pasal)

| pasal | uraian | perkara |
|---|---|---|
| 53a | Pengolahan tanpa izin usaha | 1 |
| 53b | Pengangkutan tanpa izin usaha | 11 |
| 53c | Penyimpanan tanpa izin usaha | 5 |
| 53d | Niaga tanpa izin usaha | 21 |
| 54 | Meniru/memalsukan BBM | 2 |
| 55 | Penyalahgunaan pengangkutan/niaga BBM bersubsidi | 51 |
| - | pasal tidak tercatat di rincian_amar/catatan | 25 |

## Rantai perkara yang kemungkinan satu kejadian (heuristik, perlu dicek)

| kelompok_kejadian | rantai | pengadilan | volume_liter_maks | dasar |
|---|---|---|---|---|
| K01 | C003, C004, C007 | PN PATI | 28.987 | menyebut KAPAL MANIS SEJAHTERA, PERUSAHAAN BAYU PATRA ENERGY; menyebut PERUSAHAAN BAYU PATRA ENERGY |
| K02 | C026, C027 | PN PATI | 14.920 | menyebut KAPAL BAROKAH 01, PERUSAHAAN LSS; volume sama 14920 L |
| K03 | C031, C035 |  | 6.000 | volume sama 6000 L |
| K04 | C043, C059 | PN KOTOBARU | 810 | volume sama 810 L |
| K05 | C065, C076, C077 | PN SIBOLGA | 60.000 | menyebut KAPAL CAHAYA BUDI MAKMUR; volume sama 60000 L |

## Perkara menurut jalur penemuan

| sumber_daftar | perkara |
|---|---|
| Tabulasi tim (tabulasi kebocoran bbm subsidi_v3.xlsx) | 46 |
| klasifikasi Migas; putusan terkait (rantai perkara Migas) | 31 |
| klasifikasi Migas | 30 |
