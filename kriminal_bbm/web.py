"""Klien HTTP yang sopan untuk Direktori Putusan.

- jeda antarpermintaan (default 3 detik + acak) dan retry dengan backoff untuk 429/5xx;
- cache HTML di disk sehingga penelusuran bisa dilanjutkan tanpa mengulang permintaan;
- mematuhi robots.txt;
- berhenti dengan pesan jelas bila situs meminta CAPTCHA (tidak mencoba menembusnya).
"""

from __future__ import annotations

import hashlib
import random
import re
import time
import urllib.robotparser
from pathlib import Path
from urllib.parse import urljoin, urlparse

import requests

from .config import USER_AGENT


class CaptchaRequired(RuntimeError):
    """Situs meminta verifikasi CAPTCHA; lanjutkan lewat peramban dan impor HTML tersimpan."""


class RobotsDisallowed(RuntimeError):
    pass


_CAPTCHA_MARKERS = [
    "g-recaptcha", "recaptcha/api", "h-captcha", "hcaptcha.com", "saya bukan robot",
    "i'm not a robot", "cf-chl-", "challenge-platform", "just a moment...",
]


def looks_like_captcha(html: str) -> bool:
    low = html[:200_000].lower()
    return any(m in low for m in _CAPTCHA_MARKERS)


class PoliteSession:
    def __init__(
        self,
        cache_dir: str | Path,
        delay: float = 3.0,
        jitter: float = 1.5,
        timeout: float = 60.0,
        max_retries: int = 4,
        respect_robots: bool = True,
        user_agent: str = USER_AGENT,
        log=print,
    ):
        self.cache_dir = Path(cache_dir)
        self.cache_dir.mkdir(parents=True, exist_ok=True)
        self.delay, self.jitter, self.timeout, self.max_retries = delay, jitter, timeout, max_retries
        self.respect_robots = respect_robots
        self.log = log
        self.session = requests.Session()
        self.session.headers.update({
            "User-Agent": user_agent,
            "Accept-Language": "id-ID,id;q=0.9,en;q=0.5",
        })
        self._last = 0.0
        self._robots: dict[str, urllib.robotparser.RobotFileParser | None] = {}
        self.requests_made = 0

    # ------------------------------------------------------------------ util
    def _cache_path(self, url: str, suffix: str = ".html") -> Path:
        return self.cache_dir / (hashlib.sha1(url.encode()).hexdigest()[:20] + suffix)

    def _wait(self):
        gap = self.delay + random.uniform(0, self.jitter)
        elapsed = time.monotonic() - self._last
        if elapsed < gap:
            time.sleep(gap - elapsed)
        self._last = time.monotonic()

    def _allowed(self, url: str) -> bool:
        if not self.respect_robots:
            return True
        parts = urlparse(url)
        root = f"{parts.scheme}://{parts.netloc}"
        if root not in self._robots:
            rp = urllib.robotparser.RobotFileParser()
            try:
                r = self.session.get(urljoin(root, "/robots.txt"), timeout=self.timeout)
                rp.parse(r.text.splitlines() if r.status_code == 200 else [])
                self._robots[root] = rp
            except requests.RequestException:
                self._robots[root] = None  # robots.txt tidak bisa dibaca: lanjut dengan hati-hati
        rp = self._robots[root]
        return True if rp is None else rp.can_fetch(self.session.headers["User-Agent"], url)

    def _request(self, url: str) -> requests.Response:
        if not self._allowed(url):
            raise RobotsDisallowed(f"robots.txt melarang: {url}")
        last_exc: Exception | None = None
        for attempt in range(self.max_retries + 1):
            self._wait()
            try:
                self.requests_made += 1
                r = self.session.get(url, timeout=self.timeout)
            except (requests.ConnectionError, requests.Timeout) as e:
                last_exc = e
            else:
                if r.status_code == 200:
                    return r
                if r.status_code in (429, 500, 502, 503, 504):
                    last_exc = requests.HTTPError(f"HTTP {r.status_code} untuk {url}")
                    retry_after = r.headers.get("Retry-After")
                    if retry_after and retry_after.isdigit():
                        time.sleep(min(int(retry_after), 300))
                else:
                    r.raise_for_status()
            backoff = self.delay * (2 ** attempt)
            self.log(f"  gagal ({last_exc}); coba lagi dalam {backoff:.0f} detik")
            time.sleep(backoff)
        raise RuntimeError(f"gagal mengambil {url}: {last_exc}")

    # ------------------------------------------------------------------ API
    def get_html(self, url: str, use_cache: bool = True) -> str:
        path = self._cache_path(url)
        if use_cache and path.exists():
            return path.read_text(encoding="utf-8")
        r = self._request(url)
        r.encoding = r.encoding or r.apparent_encoding
        html = r.text
        if looks_like_captcha(html):
            raise CaptchaRequired(
                f"Halaman meminta CAPTCHA: {url}\n"
                "Buka halaman di peramban, selesaikan verifikasi, simpan halaman (Ctrl+S) ke satu folder, "
                "lalu jalankan: python -m kriminal_bbm crawl --html-dir <folder>"
            )
        path.write_text(html, encoding="utf-8")
        return html

    def download(self, url: str, dest: str | Path) -> Path:
        """Unduh berkas biner ke `dest` (dilewati bila sudah ada)."""
        dest = Path(dest)
        if dest.exists() and dest.stat().st_size > 0:
            return dest
        dest.parent.mkdir(parents=True, exist_ok=True)
        r = self._request(url)
        ctype = r.headers.get("Content-Type", "")
        if "html" in ctype.lower() and looks_like_captcha(r.text):
            raise CaptchaRequired(f"Unduhan meminta CAPTCHA: {url}")
        tmp = dest.with_suffix(dest.suffix + ".part")
        tmp.write_bytes(r.content)
        tmp.replace(dest)
        return dest


def filename_from_disposition(header: str | None) -> str | None:
    if not header:
        return None
    m = re.search(r"filename\*?=(?:UTF-8'')?\"?([^\";]+)", header)
    return m.group(1) if m else None
