import json
from types import SimpleNamespace

from kriminal_bbm.llm import SCHEMA, check_quotes, code_files, to_rekap_frame

TEXT = ("P U T U S A N Nomor 1/Pid.Sus/2020/PN Pti. Terdakwa mengangkut BBM jenis solar "
        "sebanyak 500 (lima ratus) liter pada hari Senin tanggal 6 Januari 2020.")

ANSWER = {
    "nomor_putusan": "1/Pid.Sus/2020/PN Pti", "pengadilan": "PN PATI", "tingkat_persidangan": "PN",
    "tingkat_proses": "Pertama", "tanggal_putusan": "1 Juni 2020", "tahun_putusan": 2020,
    "tahun_kejadian": "2020", "hasil_putusan": "Bersalah", "rincian_amar": "Bersalah; penjara 6 bulan.",
    "barang_bbm": "Solar (status subsidi tidak disebut)", "relevan_bbm": "Ya", "nilai_kerugian_uang": None,
    "dasar_kode": "e", "dasar_nilai_uang": None, "nilai_kerugian_volume": 500, "satuan_volume": "liter",
    "keterangan_volume": "500 liter solar", "pasal_uu_migas": ["53 huruf b"],
    "bukti_kutipan": ["mengangkut BBM jenis solar sebanyak 500 (lima ratus) liter", "kutipan karangan yang tidak ada"],
    "catatan": "uji",
}


class FakeMessages:
    def __init__(self):
        self.calls = []

    def create(self, **kw):
        self.calls.append(kw)
        return SimpleNamespace(
            stop_reason="end_turn", model=kw["model"],
            content=[SimpleNamespace(type="thinking", thinking=""), SimpleNamespace(type="text", text=json.dumps(ANSWER))],
            usage=SimpleNamespace(input_tokens=100, output_tokens=50, cache_read_input_tokens=0),
        )


def test_schema_is_strict():
    assert SCHEMA["additionalProperties"] is False
    assert set(SCHEMA["required"]) == set(SCHEMA["properties"])


def test_check_quotes():
    assert check_quotes(["solar sebanyak 500 (lima ratus) liter", "tidak ada di teks sama sekali"], TEXT) == \
        ["tidak ada di teks sama sekali"]


def test_code_files_resumes_and_flags_quotes(tmp_path):
    msgs = FakeMessages()
    client = SimpleNamespace(beta=SimpleNamespace(messages=msgs))
    out = tmp_path / "hasil.jsonl"
    recs = code_files(client, [("pdf/a.pdf", TEXT)], out, log=lambda *_: None)
    assert recs[0]["kutipan_tidak_ditemukan"] == ["kutipan karangan yang tidak ada"]
    call = msgs.calls[0]
    assert call["output_config"]["format"]["type"] == "json_schema"
    assert call["system"][0]["cache_control"] == {"type": "ephemeral"}
    # dijalankan ulang: tidak memanggil API lagi
    code_files(client, [("pdf/a.pdf", TEXT)], out, log=lambda *_: None)
    assert len(msgs.calls) == 1
    df = to_rekap_frame(recs)
    assert df.loc[0, "nilai_kerugian_volume"] == 500
    assert "1 kutipan tidak ditemukan" in df.loc[0, "catatan"]
