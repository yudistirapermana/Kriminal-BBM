from pathlib import Path

import pandas as pd
import pytest

from kriminal_bbm.crawler import Crawler, assign_chains, safe_filename
from kriminal_bbm.web import CaptchaRequired, PoliteSession, looks_like_captcha

BASE = "https://putusan3.mahkamahagung.go.id/direktori/putusan/"


def _overview(nomor, tanggal, related, pdf=True, catatan="BBM jenis solar"):
    rel_rows = "".join(f'<tr><td>Terkait</td><td><a href="/direktori/putusan/{r}.html">{r}</a></td></tr>' for r in related)
    pdf_link = '<a href="/direktori/download_file/x/pdf/x">PDF</a>' if pdf else ""
    return f"""<html><body><h2>PUTUSAN Nomor {nomor}</h2><table>
    <tr><td>Nomor</td><td>{nomor}</td></tr><tr><td>Tingkat Proses</td><td>Pertama</td></tr>
    <tr><td>Lembaga Peradilan</td><td>PN PATI</td></tr><tr><td>Catatan Amar</td><td>{catatan}</td></tr>
    <tr><td>Tanggal Dibacakan</td><td>{tanggal}</td></tr></table>{pdf_link}
    <div><h4>Putusan Terkait</h4><table>{rel_rows}</table></div></body></html>"""


class FakeSession:
    def __init__(self, pages):
        self.pages = pages
        self.downloads = []
        self.requests_made = 0

    def get_html(self, url, use_cache=True):
        self.requests_made += 1
        return self.pages[url]

    def download(self, url, dest):
        dest = Path(dest)
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(b"%PDF-1.4 fake")
        self.downloads.append(dest)
        return dest


def test_captcha_detection(fixture_html):
    assert looks_like_captcha(fixture_html("captcha.html"))
    assert not looks_like_captcha(fixture_html("overview_pn.html"))


def test_session_raises_on_captcha(tmp_path, fixture_html, monkeypatch):
    s = PoliteSession(tmp_path, delay=0, jitter=0, respect_robots=False)

    class R:
        status_code = 200
        encoding = "utf-8"
        apparent_encoding = "utf-8"
        text = fixture_html("captcha.html")
        headers = {}

    monkeypatch.setattr(s.session, "get", lambda *a, **k: R())
    with pytest.raises(CaptchaRequired):
        s.get_html("https://putusan3.mahkamahagung.go.id/search.html?q=solar")
    assert not list(tmp_path.glob("*.html"))  # halaman CAPTCHA tidak di-cache


def test_session_caches(tmp_path, monkeypatch):
    s = PoliteSession(tmp_path, delay=0, jitter=0, respect_robots=False)
    calls = []

    class R:
        status_code = 200
        encoding = "utf-8"
        apparent_encoding = "utf-8"
        text = "<html>ok</html>"
        headers = {}

    monkeypatch.setattr(s.session, "get", lambda *a, **k: calls.append(1) or R())
    assert s.get_html("https://example.org/a") == "<html>ok</html>"
    assert s.get_html("https://example.org/a") == "<html>ok</html>"
    assert len(calls) == 1


def test_assign_chains():
    ids = ["a", "b", "c", "d"]
    chains = assign_chains(ids, [("a", "b"), ("b", "c")], {"a": 2020, "b": 2021, "c": 2022, "d": 2019})
    assert chains["a"] == chains["b"] == chains["c"]
    assert chains["d"] == "R0001"  # rantai diurutkan menurut tahun paling awal


def test_crawler_follows_related_chain(tmp_path):
    pn, pt, ma, old = "1" * 32, "2" * 32, "3" * 32, "4" * 32
    pages = {
        BASE + pn + ".html": _overview("5/Pid.Sus/2021/PN Pti", "29 April 2021", [pt]),
        BASE + pt + ".html": _overview("50/PID.SUS/2021/PT SMG", "1 Juli 2021", [pn, ma], pdf=False),
        BASE + ma + ".html": _overview("100 K/Pid.Sus/2022", "3 Maret 2022", [pt], pdf=True),
        BASE + old + ".html": _overview("9/Pid.Sus/2018/PN Pti", "3 Maret 2018", [], catatan="LPG 3 kg"),
    }
    sess = FakeSession(pages)
    c = Crawler(sess, tmp_path / "out", tmp_path / "out" / "pdf", tmp_path / "teks", years=(2020, 2026))
    c.seed_urls([BASE + pn + ".html", BASE + old + ".html"])
    c.run()
    ov = pd.read_csv(tmp_path / "out" / "putusan_overview.csv", dtype={"id": str})
    assert len(ov) == 4
    chain = ov.set_index("id")["rantai_perkara"]
    assert chain[pn] == chain[pt] == chain[ma] != chain[old]
    assert not ov.set_index("id").loc[old, "dalam_rentang_tahun"]
    draft = pd.read_csv(tmp_path / "out" / "draf_rekap_untuk_dikoding.csv")
    assert set(draft["nomor_putusan"]) == {"5/Pid.Sus/2021/PN Pti", "50/PID.SUS/2021/PT SMG", "100 K/Pid.Sus/2022"}
    assert set(draft["tingkat_persidangan"]) == {"PN", "PT", "MA"}
    # PDF hanya diunduh untuk putusan dalam rentang tahun yang punya lampiran
    assert sorted(p.name for p in sess.downloads) == ["100_K_Pid.Sus_2022.pdf", "5_Pid.Sus_2021_PN_Pti.pdf"]


def test_safe_filename():
    assert safe_filename("249/Pid.Sus/2020/PN Spt") == "249_Pid.Sus_2020_PN_Spt"


def test_crawler_skips_broken_pages(tmp_path):
    good, missing = "5" * 32, "6" * 32
    pages = {BASE + good + ".html": _overview("7/Pid.Sus/2022/PN Pti", "1 Juni 2022", [missing], pdf=False)}
    c = Crawler(FakeSession(pages), tmp_path / "out", tmp_path / "out" / "pdf", tmp_path / "teks")
    c.seed_urls([BASE + good + ".html"])
    c.run()  # halaman terkait yang tidak ada (KeyError di sesi tiruan) dicatat, tidak menghentikan penelusuran
    assert len(c.rows) == 1 and len(c.failures) == 1
    assert (tmp_path / "out" / "gagal.csv").exists()
