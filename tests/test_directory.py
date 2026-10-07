from kriminal_bbm.directory import (
    max_page, page_url, parse_listing, parse_overview, putusan_id, year_filter_url,
)

LIST_URL = "https://putusan3.mahkamahagung.go.id/direktori/index/kategori/migas-1.html"
PN_URL = "https://putusan3.mahkamahagung.go.id/direktori/putusan/1102e1cfc840bf73da0c2c1af05872e7.html"


def test_putusan_id():
    assert putusan_id(PN_URL) == "1102e1cfc840bf73da0c2c1af05872e7"
    assert putusan_id("/direktori/putusan/zaee19ae19bbffd2a715323133303034.html") == "zaee19ae19bbffd2a715323133303034"
    assert putusan_id("/direktori/index/kategori/migas-1.html") is None


def test_parse_listing(fixture_html):
    items = parse_listing(fixture_html("daftar_migas.html"), LIST_URL)
    ids = [i["id"] for i in items]
    assert "1102e1cfc840bf73da0c2c1af05872e7" in ids
    assert "zaee19ae19bbffd2a715323133303034" in ids
    pn = next(i for i in items if i["id"] == "1102e1cfc840bf73da0c2c1af05872e7")
    assert pn["url"] == PN_URL  # tautan relatif dijadikan absolut
    assert pn["tanggal_putus"] == "07-09-2020"
    assert pn["tanggal_register"] == "16-07-2020"
    assert pn["nomor"] == "249/Pid.Sus/2020/PN Spt"


def test_pagination_urls(fixture_html):
    assert page_url(LIST_URL, 1) == LIST_URL
    assert page_url(LIST_URL, 3).endswith("/kategori/migas-1/page/3.html")
    assert page_url(page_url(LIST_URL, 3), 4).endswith("/migas-1/page/4.html")
    assert year_filter_url(LIST_URL, 2021).endswith("/migas-1/tahunjenis/putus/tahun/2021.html")
    # halaman 99 milik kategori lain diabaikan
    assert max_page(fixture_html("daftar_migas.html"), LIST_URL) == 12


def test_parse_overview(fixture_html):
    d = parse_overview(fixture_html("overview_pn.html"), PN_URL)
    assert d["nomor"] == "249/Pid.Sus/2020/PN Spt"
    assert d["tingkat_proses"] == "Pertama"
    assert d["klasifikasi"] == "Pidana Khusus Migas"
    assert d["lembaga_peradilan"] == "PN SAMPIT"
    assert d["tanggal_dibacakan"] == "7 September 2020"
    assert d["url_pdf"].endswith("/pdf/1102e1cfc840bf73da0c2c1af05872e7")
    assert d["lampiran_pdf"] == "Ada"
    rel = {r["id"]: r for r in d["terkait"]}
    # hanya tautan di bagian Putusan Terkait, tanpa diri sendiri dan tanpa "Putusan Terbaru"
    assert set(rel) == {"c" * 32, "d" * 32}
    assert rel["c" * 32]["label"] == "Pengadilan Tinggi"
