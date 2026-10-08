"""Pemetaan nama pengadilan (PN/PT/Dilmil) ke provinsi.

Kunci pencarian adalah nama tempat tanpa awalan PN/PT dan tanpa spasi/tanda baca,
sehingga "PN PALANGKA RAYA", "PT PALANGKARAYA" dan "Pengadilan Negeri Palangkaraya"
dipetakan ke kunci yang sama. Daftar mencakup pengadilan yang muncul di dataset ini
ditambah pengadilan umum lain di daerah rawan penyalahgunaan BBM; tambahkan bila perlu.
"""

from __future__ import annotations

import re

PROVINSI: dict[str, list[str]] = {
    "Aceh": ["BANDA ACEH", "TAKENGON", "LHOKSUKON", "BIREUEN", "LHOKSEUMAWE", "LANGSA", "IDI",
             "KUALA SIMPANG", "MEULABOH", "SIGLI", "CALANG", "TAPAKTUAN", "SINGKIL", "BLANGKEJEREN",
             "KUTACANE", "SINABANG", "SABANG", "JANTHO", "SIMPANG TIGA REDELONG", "MEUREUDU", "SUKA MAKMUE"],
    "Sumatera Utara": ["MEDAN", "SIBOLGA", "RANTAU PRAPAT", "KISARAN", "TANJUNG BALAI", "LUBUK PAKAM",
                       "BINJAI", "STABAT", "TEBING TINGGI", "PEMATANG SIANTAR", "SIMALUNGUN",
                       "PADANG SIDEMPUAN", "TARUTUNG", "BALIGE", "KABANJAHE", "GUNUNG SITOLI",
                       "PANYABUNGAN", "LABUHAN DELI", "SIDIKALANG"],
    "Sumatera Barat": ["PADANG", "KOTO BARU", "PAYAKUMBUH", "PARIAMAN", "SAWAHLUNTO", "SOLOK",
                       "BUKITTINGGI", "BATUSANGKAR", "LUBUK SIKAPING", "MUARO", "PAINAN",
                       "PADANG PANJANG", "LUBUK BASUNG", "TANJUNG PATI", "PASAMAN BARAT", "MUARA LABUH"],
    "Riau": ["PEKANBARU", "DUMAI", "PELALAWAN", "BENGKALIS", "BANGKINANG", "RENGAT", "TEMBILAHAN",
             "SIAK SRI INDRAPURA", "SIAK", "ROKAN HILIR", "PASIR PANGARAIAN", "TELUK KUANTAN"],
    "Kepulauan Riau": ["BATAM", "TANJUNG PINANG", "KEPULAUAN RIAU", "TANJUNG BALAI KARIMUN",
                       "KARIMUN", "NATUNA", "RANAI", "DABO SINGKEP", "BINTAN"],
    "Jambi": ["JAMBI", "MUARA BUNGO", "TANJUNG JABUNG TIMUR", "MUARA SABAK", "KUALA TUNGKAL",
              "SAROLANGUN", "MUARA BULIAN", "SENGETI", "BANGKO", "MUARA TEBO", "SUNGAI PENUH"],
    "Sumatera Selatan": ["PALEMBANG", "LUBUK LINGGAU", "PANGKALAN BALAI", "SEKAYU", "KAYU AGUNG",
                         "BATURAJA", "LAHAT", "MUARA ENIM", "PRABUMULIH", "PAGAR ALAM",
                         "MUARA BELITI"],
    "Kepulauan Bangka Belitung": ["PANGKAL PINANG", "BANGKA BELITUNG", "KOBA", "SUNGAILIAT",
                                  "MUNTOK", "TANJUNG PANDAN", "SIMPANG RIMBA"],
    "Bengkulu": ["BENGKULU", "ARGA MAKMUR", "CURUP", "MANNA", "TAIS"],
    "Lampung": ["TANJUNG KARANG", "GEDONG TATAAN", "KOTABUMI", "METRO", "KALIANDA", "MENGGALA",
                "SUKADANA", "GUNUNG SUGIH", "KOTA AGUNG", "LIWA", "BLAMBANGAN UMPU", "BANDAR LAMPUNG"],
    "DKI Jakarta": ["JAKARTA PUSAT", "JAKARTA UTARA", "JAKARTA BARAT", "JAKARTA SELATAN",
                    "JAKARTA TIMUR", "DKI JAKARTA", "JAKARTA"],
    "Banten": ["SERANG", "CILEGON", "TANGERANG", "RANGKASBITUNG", "PANDEGLANG", "BANTEN"],
    "Jawa Barat": ["BANDUNG", "CIANJUR", "BEKASI", "CIKARANG", "KARAWANG", "CIREBON", "SUMBER",
                   "INDRAMAYU", "SUBANG", "PURWAKARTA", "BOGOR", "CIBINONG", "DEPOK", "SUKABUMI",
                   "CIBADAK", "GARUT", "TASIKMALAYA", "CIAMIS", "KUNINGAN", "MAJALENGKA",
                   "SUMEDANG", "BALE BANDUNG", "BANJAR"],
    "Jawa Tengah": ["SEMARANG", "KAB SEMARANG", "UNGARAN", "PATI", "REMBANG", "BLORA", "PURWOREJO",
                    "KEBUMEN", "KUDUS", "JEPARA", "DEMAK", "TEGAL", "SLAWI", "BREBES", "CILACAP",
                    "SURAKARTA", "BOYOLALI", "KLATEN", "SRAGEN", "SUKOHARJO", "KARANGANYAR",
                    "WONOGIRI", "PURBALINGGA", "PURWOKERTO", "BANJARNEGARA", "WONOSOBO",
                    "TEMANGGUNG", "MAGELANG", "MUNGKID", "KENDAL", "BATANG", "PEKALONGAN",
                    "KAJEN", "PEMALANG", "GROBOGAN", "PURWODADI", "SALATIGA"],
    "DI Yogyakarta": ["YOGYAKARTA", "WONOSARI", "SLEMAN", "BANTUL", "WATES"],
    "Jawa Timur": ["SURABAYA", "BANYUWANGI", "KABUPATEN KEDIRI", "KEDIRI", "KEPANJEN", "MALANG",
                   "KRAKSAAN", "PROBOLINGGO", "SITUBONDO", "SUMENEP", "TUBAN", "TULUNGAGUNG",
                   "SIDOARJO", "GRESIK", "LAMONGAN", "BOJONEGORO", "PASURUAN", "BANGIL", "JEMBER",
                   "LUMAJANG", "BONDOWOSO", "BANGKALAN", "SAMPANG", "PAMEKASAN", "MOJOKERTO",
                   "JOMBANG", "NGANJUK", "MADIUN", "NGAWI", "MAGETAN", "PONOROGO", "PACITAN",
                   "TRENGGALEK", "BLITAR", "BATU"],
    "Bali": ["DENPASAR", "SEMARAPURA", "SINGARAJA", "GIANYAR", "TABANAN", "NEGARA", "AMLAPURA", "BANGLI"],
    "Nusa Tenggara Barat": ["MATARAM", "PRAYA", "SELONG", "SUMBAWA BESAR", "DOMPU", "BIMA"],
    "Nusa Tenggara Timur": ["KUPANG", "RUTENG", "ENDE", "MAUMERE", "LARANTUKA", "ATAMBUA",
                            "KEFAMENANU", "SOE", "WAINGAPU", "WAIKABUBAK", "BAJAWA", "KALABAHI",
                            "LABUAN BAJO", "OELAMASI"],
    "Kalimantan Barat": ["PONTIANAK", "KETAPANG", "MEMPAWAH", "BENGKAYANG", "SANGGAU", "SINTANG",
                         "PUTUSSIBAU", "SAMBAS", "SINGKAWANG", "NGABANG", "SEKADAU", "NANGA PINOH",
                         "SUKADANA KAYONG"],
    "Kalimantan Tengah": ["PALANGKA RAYA", "PALANGKARAYA", "SAMPIT", "PANGKALAN BUN", "NANGA BULIK",
                          "KUALA KAPUAS", "MUARA TEWEH", "BUNTOK", "TAMIANG LAYANG", "KUALA KURUN",
                          "KASONGAN", "KUALA PEMBUANG", "SUKAMARA", "PULANG PISAU"],
    "Kalimantan Selatan": ["BANJARMASIN", "PELAIHARI", "MARTAPURA", "KOTABARU", "TANJUNG",
                           "MARABAHAN", "BANJARBARU", "BATULICIN", "AMUNTAI", "BARABAI", "KANDANGAN",
                           "RANTAU", "PARINGIN"],
    "Kalimantan Timur": ["SAMARINDA", "BALIKPAPAN", "TENGGARONG", "SANGATTA", "KUTAI BARAT",
                         "SENDAWAR", "TANAH GROGOT", "TANJUNG REDEB", "BONTANG", "PENAJAM"],
    "Kalimantan Utara": ["TARAKAN", "NUNUKAN", "TANJUNG SELOR", "MALINAU"],
    "Sulawesi Utara": ["MANADO", "BITUNG", "KOTAMOBAGU", "TONDANO", "AIRMADIDI", "AMURANG", "TAHUNA", "MELONGUANE"],
    "Gorontalo": ["GORONTALO", "LIMBOTO", "TILAMUTA", "MARISA"],
    "Sulawesi Tengah": ["PALU", "DONGGALA", "TOLITOLI", "LUWUK", "POSO", "BUOL", "PARIGI", "BANGGAI", "KOLONODALE"],
    "Sulawesi Barat": ["MAMUJU", "POLEWALI", "PASANGKAYU", "MAJENE", "SULAWESI BARAT"],
    "Sulawesi Selatan": ["MAKASSAR", "PALOPO", "WATANSOPPENG", "TAKALAR", "MAROS", "PANGKAJENE",
                         "BARRU", "PAREPARE", "PINRANG", "SIDENRENG RAPPANG", "SIDRAP", "ENREKANG",
                         "MAKALE", "MASAMBA", "MALILI", "SENGKANG", "WATAMPONE", "SINJAI",
                         "BULUKUMBA", "BANTAENG", "JENEPONTO", "SUNGGUMINASA", "SELAYAR", "BELOPA"],
    "Sulawesi Tenggara": ["KENDARI", "BAU BAU", "BAUBAU", "KOLAKA", "RAHA", "UNAAHA", "ANDOOLO", "PASARWAJO"],
    "Maluku": ["AMBON", "MASOHI", "TUAL", "SAUMLAKI", "DOBO", "NAMLEA"],
    "Maluku Utara": ["TERNATE", "MALUKU UTARA", "TOBELO", "SOASIO", "LABUHA", "SANANA"],
    "Papua Barat": ["FAKFAK", "MANOKWARI", "KAIMANA", "TELUK BINTUNI", "PAPUA BARAT"],
    "Papua Barat Daya": ["SORONG"],
    "Papua": ["JAYAPURA", "BIAK", "SERUI", "NABIRE", "SENTANI", "KEEROM"],
    "Papua Selatan": ["MERAUKE"],
    "Papua Tengah": ["TIMIKA", "MIMIKA"],
    "Papua Pegunungan": ["WAMENA"],
}

_PREFIX_RE = re.compile(
    r"^(PN|PT|PENGADILAN\s+NEGERI|PENGADILAN\s+TINGGI|DILMIL|PENGADILAN\s+MILITER(\s+TINGGI)?)\b",
)


def _key(name: str) -> str:
    n = name.upper().replace(".", " ")
    n = _PREFIX_RE.sub("", n.strip())
    n = re.sub(r"\bKELAS\s+[I1]+\s*[AB]?\b", " ", n)
    n = re.sub(r"\b[IVX]+\s*-?\s*\d+\b", " ", n)  # kode Dilmil "II 11"
    return re.sub(r"[^A-Z]", "", n)


_LOOKUP = {_key(place): prov for prov, places in PROVINSI.items() for place in places}


def provinsi(pengadilan: str | None) -> str | None:
    """Provinsi untuk nama pengadilan; None bila tidak dikenal atau Mahkamah Agung."""
    if not pengadilan or not isinstance(pengadilan, str):
        return None
    if "MAHKAMAH AGUNG" in pengadilan.upper():
        return None
    return _LOOKUP.get(_key(pengadilan))
