import pandas as pd
import pytest

from conftest import DATA
from kriminal_bbm.analysis import case_level, dedupe, prepare, status_subsidi, write_outputs
from kriminal_bbm.regions import provinsi
from kriminal_bbm.validate import load_rekap, norm_nomor, validate_rekap

REKAP = DATA / "rekap_putusan_kriminalitas_BBM_2020-2026.csv"
needs_data = pytest.mark.skipif(not REKAP.exists(), reason="rekap tidak tersedia")


@pytest.fixture(scope="module")
def rekap():
    return load_rekap(REKAP)


def test_norm_nomor():
    assert norm_nomor("266/Pid.Sus/2019/PN.Pli") == norm_nomor("266/Pid.Sus/2019/PN Pli")


@pytest.mark.parametrize("name,prov", [
    ("PN PALANGKA RAYA", "Kalimantan Tengah"), ("PT PALANGKARAYA", "Kalimantan Tengah"),
    ("PN KOTOBARU", "Sumatera Barat"), ("PN KOTABARU", "Kalimantan Selatan"),
    ("DILMIL II 11 YOGYAKARTA", "DI Yogyakarta"), ("MAHKAMAH AGUNG", None),
])
def test_provinsi(name, prov):
    assert provinsi(name) == prov


def test_status_subsidi():
    assert status_subsidi("Solar/Biosolar (subsidi)") == "subsidi"
    assert status_subsidi("Solar (non-subsidi/industri)") == "non-subsidi"
    assert status_subsidi("Pertalite") == "penugasan (JBKP)"
    assert status_subsidi("Solar (status subsidi tidak disebut)") == "tidak disebut"
    assert status_subsidi("Solar/Biosolar (subsidi); Dexlite") == "subsidi"


@needs_data
def test_current_rekap_has_no_errors(rekap):
    issues = validate_rekap(rekap, DATA)
    assert [i for i in issues if i.tingkat == "galat"] == []


def test_validator_catches_broken_rows(tmp_path):
    df = pd.DataFrame([{
        "no": 1, "nomor_putusan": "1/Pid.Sus/2020/PN Pti", "pengadilan": "PN PATI",
        "tingkat_persidangan": "PN", "tingkat_proses": "Kasasi", "tanggal_putusan": "5 Mei 2021",
        "tahun_putusan": 2020, "tahun_kejadian": "2022", "hasil_putusan": "Bersalah", "rincian_amar": "x",
        "barang_bbm": "Solar", "relevan_bbm": "Ya", "nilai_kerugian_uang": 1000.0, "mata_uang": None,
        "dasar_nilai_uang": None, "nilai_kerugian_volume": 10.0, "satuan_volume": None,
        "keterangan_volume": "x", "sumber_data": "PDF", "lampiran_pdf": "Ada", "file_pdf": "pdf/tidak_ada.pdf",
        "rantai_perkara": "C1", "klasifikasi": "x", "sumber_daftar": "x",
        "url_putusan": "https://putusan3.mahkamahagung.go.id/direktori/putusan/abc.html",
        "bukti_kutipan": "x", "catatan": "x",
    }])
    msgs = {(i.kolom, i.tingkat) for i in validate_rekap(df, tmp_path)}
    assert ("tingkat_proses", "galat") in msgs
    assert ("tahun_putusan", "galat") in msgs        # 2020 vs tanggal 2021
    assert ("tahun_kejadian", "galat") in msgs       # kejadian sesudah putusan
    assert ("mata_uang/dasar_nilai_uang", "galat") in msgs
    assert ("satuan_volume", "galat") in msgs
    assert ("file_pdf", "galat") in msgs


@needs_data
def test_case_level(rekap, tmp_path):
    d = dedupe(rekap)
    assert len(rekap) - len(d) == 2  # dua entri direktori ganda yang sudah ditandai di catatan
    cases = case_level(prepare(d))
    assert len(cases) == rekap["rantai_perkara"].nunique()
    assert cases["rantai_perkara"].is_unique
    # tiga berkas terpisah kapal KM Cahaya Budi Makmur (PN Sibolga) dikenali sebagai satu kejadian
    grp = cases.set_index("rantai_perkara").loc[["C065", "C076", "C077"], "kelompok_kejadian"]
    assert grp.nunique() == 1 and grp.iloc[0].startswith("K")
    # volume kelompok dihitung sekali
    assert cases["volume_liter_kelompok"].sum() < cases["volume_liter"].sum()
    out = write_outputs(rekap, tmp_path)
    assert (tmp_path / "rekap_perkara_unik.csv").exists()
    assert (tmp_path / "ringkasan_statistik.md").read_text(encoding="utf-8").startswith("# Ringkasan")
    assert int(out["tables"]["putusan_tahun_x_tingkat"].loc["Total", "Total"]) == len(d)
