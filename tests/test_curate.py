import pandas as pd
import pytest

from conftest import DATA
from kriminal_bbm.config import TEXT_CACHE_DIR
from kriminal_bbm.curate import apply_review, evidence_table, keyword_hits, read_raw, write_raw
from kriminal_bbm.validate import load_rekap

REKAP = DATA / "rekap_putusan_kriminalitas_BBM_2020-2026.csv"


def test_keyword_hits():
    h = keyword_hits("BBM jenis Bio Solar dan solar industri, minyak tanah, Pertalite; bahan bakar minyak")
    assert h == {"BBM": 1, "bahan bakar minyak": 1, "solar": 1, "biosolar": 1, "minyak tanah": 1, "pertalite": 1}
    assert keyword_hits("tabung LPG 3 kg") == {}
    assert "solar" not in keyword_hits("biosolar")  # biosolar tidak dihitung ganda sebagai solar


def _raw():
    rekap = pd.DataFrame({
        "no": ["1", "2", "3"], "nomor_putusan": ["1/Pid.Sus/2020/PN A", "2/Pid.Sus/2020/PN A", "3 K/Pid.Sus/2021"],
        "pengadilan": ["PN A"] * 2 + ["MAHKAMAH AGUNG"], "tingkat_persidangan": ["PN", "PN", "MA"],
        "tahun_putusan": ["2020", "2020", "2021"], "barang_bbm": ["Solar", "LPG 3 kg", "Pertalite"],
        "klasifikasi": ["x"] * 3, "url_putusan": ["NA"] * 3, "nilai_kerugian_uang": ["19930365", "NA", "NA"],
    })
    excluded = pd.DataFrame(columns=["nomor_putusan", "pengadilan", "tingkat_persidangan", "tahun_putusan",
                                     "barang_bbm", "klasifikasi", "url_putusan", "alasan_dikeluarkan"])
    return rekap, excluded


def test_apply_review_removes_only_final_no(tmp_path):
    rekap, excluded = _raw()
    review = pd.DataFrame({"dataset": ["rekap"] * 3, "no": [1, 2, 3], "final": ["yes", "no", "uncertain"],
                           "alasan": ["", "objek LPG", ""]})
    kept, excl, removed = apply_review(rekap, excluded, review, "7 Oktober 2026")
    assert list(removed["nomor_putusan"]) == ["2/Pid.Sus/2020/PN A"]
    assert list(kept["no"]) == ["1", "2"]                      # diurutkan ulang
    assert list(kept["nilai_kerugian_uang"]) == ["19930365", "NA"]  # sel lain tidak berubah format
    assert "objek LPG" in excl.loc[0, "alasan_dikeluarkan"]
    write_raw(kept, tmp_path / "r.csv")
    assert read_raw(tmp_path / "r.csv").equals(kept.reset_index(drop=True))


@pytest.mark.skipif(not REKAP.exists(), reason="rekap tidak tersedia")
def test_every_rekap_row_has_keyword_evidence():
    ev = evidence_table(load_rekap(REKAP), DATA, TEXT_CACHE_DIR)
    assert len(ev) == 166
    assert (ev["dasar_bukti_kata_kunci"] != "tidak ada").all()
    tab = load_rekap(REKAP)["sumber_daftar"].str.startswith("Tabulasi")
    assert (ev.loc[tab.values, "dasar_bukti_kata_kunci"] == "tabulasi tim (bukan teks putusan)").all()
