"""Pipeline data kriminalitas BBM dari Direktori Putusan Mahkamah Agung.

Modul:
- config    : lokasi berkas, URL dasar, daftar kata kunci.
- web       : klien HTTP yang sopan (jeda, retry, cache, cek robots.txt, deteksi CAPTCHA).
- directory : parser HTML halaman Direktori Putusan (daftar, overview, putusan terkait).
- crawler   : penelusuran klasifikasi -> overview -> rantai perkara -> unduh PDF.
- pdftext   : ekstraksi teks PDF putusan tanpa watermark/disclaimer.
- extract   : kandidat nilai kolom (tanggal, amar, hasil, BBM, volume, rupiah) berbasis regex.
- llm       : (opsional) pengodean tujuh kolom dengan Claude API memakai protokol yang sama.
- validate  : pemeriksaan konsistensi berkas rekap.
- analysis  : dataset tingkat perkara (rantai) dan tabel ringkasan.
- regions   : pemetaan pengadilan -> provinsi.
"""

__version__ = "0.1.0"
