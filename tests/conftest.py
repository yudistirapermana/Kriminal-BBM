from pathlib import Path

import pytest

FIXTURES = Path(__file__).parent / "fixtures"
REPO = Path(__file__).resolve().parent.parent
DATA = REPO / "Data Kriminal BBM"


@pytest.fixture
def fixture_html():
    def _read(name: str) -> str:
        return (FIXTURES / name).read_text(encoding="utf-8")
    return _read
