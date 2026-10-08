"""Parser HTML Direktori Putusan Mahkamah Agung (putusan3.mahkamahagung.go.id).

Parser sengaja tidak bergantung pada nama kelas CSS tertentu:
- tautan putusan dikenali dari pola URL /direktori/putusan/<id>.html;
- metadata overview dibaca dari baris tabel dua kolom (label | nilai);
- "Putusan Terkait" dicari dari judul bagiannya lalu tautan di dalam wadahnya;
- tautan unduhan dikenali dari pola /direktori/download_file/.../pdf/...
Dengan begitu perubahan tampilan kecil di situs tidak langsung merusak penelusuran.
Jalankan `python -m kriminal_bbm check-site` untuk memastikan parser masih cocok.
"""

from __future__ import annotations

import re
from urllib.parse import urljoin

from bs4 import BeautifulSoup, Tag

from .config import BASE_URL

PUTUSAN_LINK_RE = re.compile(r"/direktori/putusan/([0-9a-z]{16,64})\.html", re.IGNORECASE)
DOWNLOAD_RE = re.compile(r"/direktori/download_file/[^\"'\s]+", re.IGNORECASE)

LABEL_MAP = {
    "nomor": "nomor",
    "tingkat proses": "tingkat_proses",
    "klasifikasi": "klasifikasi",
    "kata kunci": "kata_kunci",
    "tahun": "tahun",
    "tanggal register": "tanggal_register",
    "lembaga peradilan": "lembaga_peradilan",
    "jenis lembaga peradilan": "jenis_lembaga_peradilan",
    "hakim ketua": "hakim_ketua",
    "hakim anggota": "hakim_anggota",
    "panitera": "panitera",
    "amar": "amar",
    "amar lainnya": "amar_lainnya",
    "catatan amar": "catatan_amar",
    "tanggal musyawarah": "tanggal_musyawarah",
    "tanggal dibacakan": "tanggal_dibacakan",
    "kaidah": "kaidah",
    "abstrak": "abstrak",
    "status": "status",
}


def _text(node) -> str:
    return re.sub(r"\s+", " ", node.get_text(" ", strip=True)).strip() if node is not None else ""


def _slug(label: str) -> str:
    label = re.sub(r"\s+", " ", label.strip().strip(":").lower())
    return LABEL_MAP.get(label, re.sub(r"[^a-z0-9]+", "_", label).strip("_"))


def putusan_id(url: str) -> str | None:
    m = PUTUSAN_LINK_RE.search(url or "")
    return m.group(1).lower() if m else None


def canonical_url(href: str, base: str = BASE_URL) -> str:
    pid = putusan_id(href)
    return f"{BASE_URL}/direktori/putusan/{pid}.html" if pid else urljoin(base, href)


# ----------------------------------------------------------------------------- halaman daftar

_LIST_META = {
    "register": re.compile(r"Register\s*:\s*([0-9]{1,2}[-/ ][0-9A-Za-z]{1,9}[-/ ][0-9]{4})", re.IGNORECASE),
    "putus": re.compile(r"Putus\s*:\s*([0-9]{1,2}[-/ ][0-9A-Za-z]{1,9}[-/ ][0-9]{4})", re.IGNORECASE),
    "upload": re.compile(r"Upload\s*:\s*([0-9]{1,2}[-/ ][0-9A-Za-z]{1,9}[-/ ][0-9]{4})", re.IGNORECASE),
}


def _entry_block(a: Tag) -> Tag:
    """Wadah satu entri hasil: div ber-kelas 'spost'/'entry' terdekat, atau dua tingkat di atas tautan."""
    for parent in a.parents:
        if not isinstance(parent, Tag):
            continue
        cls = " ".join(parent.get("class", []))
        if re.search(r"spost|entry|result|item", cls):
            return parent
        if parent.name in {"li", "tr", "article"}:
            return parent
    return a.parent.parent if a.parent is not None and a.parent.parent is not None else a


def parse_listing(html: str, page_url: str = BASE_URL) -> list[dict]:
    """Entri putusan pada halaman daftar klasifikasi atau hasil pencarian."""
    soup = BeautifulSoup(html, "lxml")
    seen: dict[str, dict] = {}
    for a in soup.find_all("a", href=True):
        pid = putusan_id(a["href"])
        if not pid:
            continue
        title = _text(a)
        if pid in seen:
            if len(title) > len(seen[pid]["judul"]):
                seen[pid]["judul"] = title
            continue
        block_text = _text(_entry_block(a))
        item = {"id": pid, "url": canonical_url(a["href"], page_url), "judul": title, "teks_entri": block_text[:500]}
        for k, rx in _LIST_META.items():
            m = rx.search(block_text)
            item[f"tanggal_{k}"] = m.group(1) if m else None
        m = re.search(r"Nomor\s+([0-9][^\s]*(?:\s+[^\s]+){0,3}?)(?:\s+Tanggal|\s*$)", title)
        item["nomor"] = m.group(1) if m else None
        seen[pid] = item
    return list(seen.values())


_PAGE_RE = re.compile(r"/page/(\d+)\.html", re.IGNORECASE)


def page_url(listing_url: str, n: int) -> str:
    """URL halaman ke-n dari sebuah daftar: .../migas-1.html -> .../migas-1/page/2.html"""
    base = _PAGE_RE.sub(".html", listing_url)
    if n <= 1:
        return base
    return re.sub(r"\.html$", f"/page/{n}.html", base)


def year_filter_url(listing_url: str, year: int, jenis: str = "putus") -> str:
    """.../migas-1.html -> .../migas-1/tahunjenis/putus/tahun/2021.html"""
    base = _PAGE_RE.sub(".html", listing_url)
    base = re.sub(r"/tahunjenis/[^/]+/tahun/\d{4}\.html$", ".html", base)
    return re.sub(r"\.html$", f"/tahunjenis/{jenis}/tahun/{year}.html", base)


def max_page(html: str, listing_url: str) -> int:
    """Nomor halaman terbesar yang ditautkan dari daftar ini (1 bila tidak ada paginasi)."""
    prefix = re.sub(r"\.html$", "", _PAGE_RE.sub(".html", listing_url))
    soup = BeautifulSoup(html, "lxml")
    pages = [1]
    for a in soup.find_all("a", href=True):
        href = urljoin(listing_url, a["href"])
        m = _PAGE_RE.search(href)
        if m and href.startswith(prefix):
            pages.append(int(m.group(1)))
    return max(pages)


# ----------------------------------------------------------------------------- halaman overview

def _label_value_rows(soup: BeautifulSoup) -> dict[str, str]:
    data: dict[str, str] = {}
    for tr in soup.find_all("tr"):
        cells = tr.find_all(["td", "th"], recursive=False)
        if len(cells) < 2:
            continue
        label = _text(cells[0])
        if not label or len(label) > 40:
            continue
        key = _slug(label)
        value = _text(cells[-1])
        if key and key not in data:
            data[key] = value
    return data


def parse_related(soup: BeautifulSoup, self_url: str) -> list[dict]:
    """Tautan di bagian 'Putusan Terkait' (PN/PT/MA/PK dari perkara yang sama)."""
    self_id = putusan_id(self_url)
    heading = soup.find(string=re.compile(r"Putusan\s+Terkait", re.IGNORECASE))
    if heading is None:
        return []
    container = heading.parent
    links: list[Tag] = []
    for _ in range(6):
        if container is None:
            break
        links = [a for a in container.find_all("a", href=True)
                 if putusan_id(a["href"]) and putusan_id(a["href"]) != self_id]
        if links:
            break
        container = container.parent
    out, seen = [], set()
    for a in links:
        pid = putusan_id(a["href"])
        if pid in seen:
            continue
        seen.add(pid)
        row = a.find_parent("tr")
        label = None
        if row is not None:
            cells = row.find_all(["td", "th"])
            if len(cells) >= 2 and a not in cells[0].find_all("a"):
                label = _text(cells[0])
        out.append({"id": pid, "url": canonical_url(a["href"]), "teks": _text(a), "label": label})
    return out


def parse_overview(html: str, url: str) -> dict:
    """Metadata satu putusan + tautan unduhan + putusan terkait."""
    soup = BeautifulSoup(html, "lxml")
    data = _label_value_rows(soup)
    h = soup.find(["h1", "h2"], string=re.compile(r"Putusan|PUTUSAN"))
    if h is None:
        h = soup.find("h2")
    data["judul"] = _text(h)
    data["id"] = putusan_id(url)
    data["url"] = canonical_url(url)

    pdfs, zips = [], []
    for a in soup.find_all("a", href=True):
        href = urljoin(url, a["href"])
        if not DOWNLOAD_RE.search(href):
            continue
        if "/pdf/" in href.lower():
            pdfs.append(href)
        elif "/zip/" in href.lower():
            zips.append(href)
    data["url_pdf"] = pdfs[0] if pdfs else None
    data["url_zip"] = zips[0] if zips else None
    data["lampiran_pdf"] = "Ada" if pdfs else "Tidak ada"
    data["terkait"] = parse_related(soup, url)
    return data
