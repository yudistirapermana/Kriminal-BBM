# Laporan kurasi kata kunci: BBM / solar / biosolar / minyak tanah / pertalite

Tanggal: 7 Oktober 2026. Berkas: `rekap_putusan_kriminalitas_BBM_2020-2026.csv` (166 putusan) dan
`putusan_dikeluarkan_tidak_relevan.csv` (35 putusan). Rincian per putusan: `kurasi_kata_kunci_tinjauan.csv`.

## Ringkasan hasil

| | Jumlah |
|---|---|
| Putusan di rekap yang diperiksa | 166 |
| Berhubungan dengan kata kunci, **dipertahankan** | **166** |
| Tidak berhubungan, **dikeluarkan** | **0** |
| Putusan yang sebelumnya dikeluarkan dan diperiksa ulang | 35 |
| Tetap dikeluarkan (bukan BBM kata kunci) | 31 |
| Tetap dikeluarkan karena tidak dapat dinilai (tanpa teks) | 4 |
| Kandidat untuk dipulihkan ke rekap | 0 |

Tidak ada baris yang perlu dihapus: setiap putusan di rekap memuat kata kunci dan BBM adalah objek perkaranya.
Putusan non-BBM (LPG, minyak mentah, tambang, narkotika yang salah taut) sudah dikeluarkan pada kurasi sebelumnya,
dan pemeriksaan ulang membenarkan semuanya:

| Putusan yang tetap dikeluarkan | Jumlah |
|---|---|
| LPG 3 kg / LPG (termasuk 231/PID.SUS/2019/PT PDG yang menyebut LPG sebagai "bahan bakar minyak yang disubsidi") | 9 |
| Pertambangan (emas, timah, batubara, minerba; "solar" hanya bahan bakar alat) | 9 |
| Minyak mentah tanpa BBM olahan (pengeboran/pengangkutan minyak mentah) | 7 |
| Narkotika yang tertaut ke rantai perkara karena salah ketik nomor | 6 |
| Tidak dapat dinilai: 863 K/Pid.Sus/2020, 109 K/Pid.Sus/2022, 3640 K/Pid.Sus/2022, 209/PID.SUS/2021/PT PBR | 4 |

## Keterbatasan: situs MA tidak dapat diakses dari lingkungan kerja ini

Lingkungan cloud tempat kurasi ini dijalankan memblokir `putusan3.mahkamahagung.go.id` (proxy menolak koneksi, 403).
Pencarian kata kunci di situs itu juga memerlukan CAPTCHA. Karena itu kata kunci diuji pada dokumen putusan yang sama
yang sebelumnya diunduh dari situs, dengan urutan sumber:

1. teks PDF putusan itu sendiri (67 putusan), atau PDF bernomor sama yang tersimpan di berkas lain (3);
2. kutipan verbatim dari putusan di kolom `bukti_kutipan` (28);
3. teks PDF putusan lain dalam rantai perkara yang sama (PN/PT/MA berbagi fakta perkara) (22);
4. isian tabulasi tim (46 baris 2026 dari `tabulasi kebocoran bbm subsidi_v3.xlsx`, tanpa URL dan PDF).

52 baris ditandai `perlu_cek_situs = True` di berkas tinjauan:

- **46 baris tabulasi tim.** Kolom `bukti_kutipan` baris ini berisi sel spreadsheet tim, bukan kutipan teks putusan.
  Relevansinya konsisten (dipidana menurut Pasal 55 UU 22/2001, barang bukti pertalite/solar/minyak tanah), tetapi belum
  dicocokkan dengan teks putusan di situs.
- **6 baris yang hanya memuat frasa lengkap "bahan bakar minyak"** (kepanjangan BBM). Di sumber yang tersedia tidak ada
  token literal "BBM", "solar", dll. Pencarian literal "BBM" di situs mungkin tidak menemukan putusan ini, walaupun
  objeknya jelas BBM (Premium):
  87/Pid.Sus/2020/PNKbm, 25 K/PID.SUS-LH/2020, 139/Pid.Sus/2020/PN Pyh, 4116 K/Pid.Sus/2021,
  249 K/Pid.Sus-LH/2022 (dicek pada PDF-nya sendiri) dan 4533 K/PID.SUS/2022.

Bila akses jaringan ke situs MA dibuka, jalankan `python -m kriminal_bbm curate --online`. Perintah itu mengambil ulang
halaman overview dan PDF setiap putusan yang punya `url_putusan` dan menulis kata kunci yang ditemukan ke
`hasil_olahan/kurasi_kata_kunci_bukti.csv`.

## Aturan yang dipakai

- **Kata kunci**: "BBM" (frasa "bahan bakar minyak" dihitung sebagai BBM, tetapi dicatat terpisah), "solar",
  "biosolar" (termasuk "bio solar"), "minyak tanah", "pertalite". Premium, Pertamax, Dexlite termasuk BBM sehingga
  berhubungan lewat kata kunci BBM.
- **Berhubungan** bila BBM kata kunci adalah objek perbuatan pidana (barang yang diangkut, disimpan, diperjualbelikan,
  disalahgunakan atau diolah; barang bukti BBM) dan kata kunci muncul di teks putusan.
- **Tidak berhubungan** bila tidak ada kata kunci, atau kata kunci hanya insidental: misalnya solar sebagai bahan bakar
  ekskavator di perkara tambang, perkara LPG, perkara narkotika yang salah taut, atau minyak mentah tanpa BBM olahan.
  Perkara penyulingan ilegal yang menghasilkan dan menjual solar tetap berhubungan (rantai Dumai C028).

## Proses

1. **Pemeriksaan otomatis.** Untuk semua 201 putusan dihitung kata kunci di setiap sumber
   (`python -m kriminal_bbm curate`). Hasilnya: tidak ada satu pun baris rekap yang tanpa kata kunci.
2. **Penilaian per putusan.** 31 agen peninjau membaca teks putusan per kelompok rantai perkara dan menilai apakah BBM
   kata kunci adalah objek perkara.
3. **Verifikasi.**
   - Panel tiga verifikator independen (bukti kata kunci, pokok perkara, skeptis): 12 putusan, yaitu 6 baris rekap yang
     hanya memuat frasa lengkap, serta 6 putusan dikeluarkan yang insidental atau tanpa teks. Semua putusan panel
     disepakati 3 dari 3.
   - Cek konsistensi isian: 41 putusan yang buktinya hanya dari isian pengode/tabulasi.
   - Tidak diverifikasi ulang: 148 putusan dengan bukti kuat dari teks sendiri.
4. **Kritik kelengkapan.** Satu agen memeriksa konsistensi antarputusan. Ia tidak menemukan keputusan yang salah,
   tetapi mengoreksi label sumber bukti untuk baris tabulasi tim (sudah diterapkan di berkas tinjauan dan di kode).

Kolom `kutipan_pendukung` di berkas tinjauan adalah kutipan teks putusan. Nama terdakwa dan saksi diganti `[nama]`.

## Catatan lain

- 2/Pid.S/2026/PN Bgl memiliki barang bukti identik dengan 1/Pid.S/2026/PN Bgl, kemungkinan berkas terpisah dari satu
  kejadian. Volumenya sudah NA di rekap agar tidak terhitung ganda; baris dipertahankan.
- Rantai C025 (PN Nanga Bulik) dan C043 (PN Koto Baru) di direktori sempat tertaut ke perkara narkotika. Untuk C043,
  penyebabnya salah ketik nomor "119/Pid.Sus/2020/PN Kbr" di putusan 139/PID.SUS/2020/PT PDG. Perkara narkotika itu
  tetap di daftar dikeluarkan, dan anggota BBM kedua rantai (termasuk 1493 K/PID.SUS/2021) dipertahankan.
