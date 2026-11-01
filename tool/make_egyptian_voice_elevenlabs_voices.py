"""The Egyptian Arabic voices of the voice coach, made with ElevenLabs (paid API, a few minutes).

Voices (from the ElevenLabs Voice Library, added to "My voices"):
  yasmine  female  L10lEremDiJfPicq5CPh
  ziad     male    5REPlS2Ja1VZ7zNA0ykn

Setup: create an API key in ElevenLabs (Developers > API keys) and put it in the environment
variable ELEVENLABS_API_KEY (never in a file in the project). Needs openpyxl for the list.

Use (from the project folder):
    dart run tool/make_egyptian_voice.dart --list                 (the lines the app says)
    python tool/make_egyptian_voice_elevenlabs_voices.py --list          (every line -> tool/elevenlabs_say_as.xlsx)
    python tool/make_egyptian_voice_elevenlabs_voices.py --sample        (a few lines per voice and model -> tool/try/elevenlabs/)
    python tool/make_egyptian_voice_elevenlabs_voices.py --record        (every line, both voices)
    python tool/make_egyptian_voice_elevenlabs_voices.py --record ziad
Re-running only makes new or changed lines; a voice appears in the app (manifest.json) when
all its lines are made. Every line costs its length in characters from the ElevenLabs quota.

How a line is said: write it in the yellow "Voice says" column of tool/elevenlabs_say_as.xlsx
(empty = the app's text without tashkeel, after the SAY_AS wording fixes below).
"""

import json
import os
import re
import sys
import time
import urllib.error
import urllib.request

ASSET_DIR = os.path.join("assets", "voice", "ar_eg")
PIECES = os.path.join(ASSET_DIR, "pieces.txt")
MANIFEST = os.path.join(ASSET_DIR, "manifest.json")
RECORDED = os.path.join(ASSET_DIR, "recorded_elevenlabs.json")
SAY_AS_FILE = os.path.join("tool", "elevenlabs_say_as.xlsx")
TRY_DIR = os.path.join("tool", "try", "elevenlabs")

VOICES = {"yasmine": "L10lEremDiJfPicq5CPh", "ziad": "5REPlS2Ja1VZ7zNA0ykn"}
MODEL = "eleven_multilingual_v2"
SAMPLE_MODELS = ["eleven_multilingual_v2"]  # v3 said j for ج and sounded like formal Arabic
FORMAT = "mp3_44100_64"
SEED = 1

# The wording the user asked for (the app's text and the clip names stay the same)
SAY_AS = [
    ("دي كانِت سْكوات مِش ديدْليفْت، اِتْني مِن وِسْطَك", "دي كانِت سْكوات مِش ديدْليفْت، اِتْني وِسْطَك"),
    ("البار مايِل، اِدْفَع بِإيدَيْك الاِتْنَيْن زَيّ بَعْض", "البار مِش مَظْبوط، خَلّي إيدَك الاِتْنين مَفْرودين زَيّ بَعْض"),
    ("قول يَلّا، أَو وَقْت زِيادَة", "قول جاهِز. وَلّا عايِز وَقْت زِيادَة؟"),  # جاهز is a voice command too
    ("قول يَلّا", "قول جاهِز"),
    ("بِهُدوء، مَتِسْتَعْجِلْش في الحَرَكَة", "بِرّاحَة، اِهْدى"),
    ("تَكْرارات", "عَدّات"),
    ("تَكْرارْتين", "عَدّتين"),
    ("تَكْرارَة", "عَدّة"),
    ("نِزْلَة", "نَزْلَة"),
]
TASHKEEL = re.compile(r"[ً-ْٰ]")
# after the tashkeel is removed: whole words the voices said wrong, picked by ear
PLAIN_FIX = [
    ("عد([ةه])", r"عَدّ\1"),  # 3adda, not 3edda
    ("عدات", "عَدّات"),
    ("عدتين", "عَدّتين"),
    ("ركبتك", "رُكبتك"),  # rokbetak
    ("ضم كوعك لجوه شوي[ةه]", "ضم كوعك شوية"),  # no voice said legowa right here: without it
    ("لجوه", "لجُوَّه"),  # legowa (with ا it said legowae, with a kasra legowah)
    ("جديد", "جِديد"),  # gedeed
    ("بايسبس كيرل", "biceps curl"),
    ("قول", "ءُول"),  # 2ool, not awwal
    ("قلتلك", "ءُلتِلَك"),  # 2oltelak
    ("(?<!legowwa )شوية", "شُوَيّة"),
    ("رقم قياسي", "رَقَم قِياسي"),  # rakam keyasy (said with ق)
    ("متميلش بجسمك", "متمِلش بجِسمك"),  # matmelsh bgesmak
    ("كمل الحرك[ةه] للآخر", "كَمِّل الحَرَكَة لِلْءاخِر"),  # kamel el 7araka ll 2a5er
    ("الحرك[ةه]", "الحَرَكَة"),
    ("ظبط", "ظَبَّط"),  # zabbat
    ("وقفتك", "وَءْفِتَك"),  # zabbat wa2fetak
    ("بدأت تتعب", "بَدَأْت تِتْعَب"),  # bada2t tet3ab
    ("خد نفسك وخليك مركز", "خُد نَفَسَك"),  # you asked to drop وخليك مركز
    ("خد نفسك", "خُد نَفَسَك"),  # 5od nafasak
    ("لقدام", "لِءُدّام"),  # l2odam
    ("نزل[ةه]", "نَزْلة"),  # nazla, not nazala
    ("هسكت دلوقتي", "هَسْكُت دِلْوَءتي"),  # haskot delwa2ty
    ("متلفش", "متلِفِّش"),  # leff
    ("لف", "لِفّ"),
]
# the number clips: your spelling (1-20), the tens with the same care; a short word said without
# tashkeel lost its end (arba3ee, 5amsee)
UNITS = {"واحد": "وَاحِد", "اتنين": "اِتْنِين", "تلاتة": "تَلَاتَة", "أربعة": "أَرْبَعَة", "خمسة": "خَمْسَة",
         "ستة": "سِتَّة", "سبعة": "سَبْعَة", "تمانية": "تَمَانْيَة", "تسعة": "تِسْعَة"}
TEENS = {"عشرة": "عَشَرَة", "حداشر": "حِدَاشَر", "اتناشر": "اِطْنَاشَر", "تلاتطاشر": "طلَطَّاشَر",
         "أربعطاشر": "أَرْبَعْطَاشَر", "خمسطاشر": "خَمَسْطَاشَر", "ستاشر": "سِطَّاشَر", "سبعطاشر": "سَبْعَطَاشَر",
         "تمانطاشر": "تَمَنْطَاشَر", "تسعطاشر": "تِسْعَطَاشَر"}
TENS = {"عشرين": "عِشْرِين", "تلاتين": "تَلَاتِين", "أربعين": "إرْبِعين", "خمسين": "خَمسين",
        "ستين": "سِتِّين", "سبعين": "سَبْعِين", "تمانين": "تَمَانِين", "تسعين": "تِسْعِين", "مية": "مِيَّة"}


def number_say(text, voice):
    """a number clip (تلاتة, سبعطاشر, خمسة وخمسين) as the voice says it, else None"""
    t = text.strip(" .!،")
    one = {**UNITS, **TEENS, **TENS}
    if t in one:
        return one[t]
    m = re.fullmatch(r"(\S+) و(\S+)", t)
    if m and m.group(1) in UNITS and m.group(2) in TENS:
        unit, ten = UNITS[m.group(1)], TENS[m.group(2)]
        if unit.endswith("ة"):  # talata w talateen without a gap: what each voice said right
            return unit[:-1] + ("ة و" if voice == "ziad" else "ا و") + ten  # sab3a w5amseen
        return f"{unit} وِ{ten}"
    return None
# per voice, before PLAIN_FIX: legowwa in English letters gives the hard g; dom, not dum
VOICE_FIX = {
    "ziad": [("ضم كوعك لجوه شوي[ةه]", "dom كوعك legowwa شوية"),
             ("متميلش بجسمك", "مَتْمِلْش بجسمَك"),  # matmelsh gesmak (with a kasra on ج: jesmak)
             ("نزل[ةه] ممتاز[ةه]", "نَزْلة مُمْتازَة"),  # nazla momtaza
             ("افتكر، براحة، اهدى", "إفتِكِر، بِرَّاحَة. اهدى"),  # efteker
             ("قلتلك، براحة", "قلتلك، بِرَّاحَة"),  # berra7a, not bra7a (this one was good)
             ("براحة، اهدى", "بِرَّاحَة. اهدى")],  # alone: with the stop it said berra7a
    "yasmine": [("ضم كوعك لجوه شوي[ةه]", "ضُم كوعك legowwa شوية"),
                ("سكوات", "squats"),  # she said sakawat
                ("متلفش", "مَتْلِفِّش"),  # matlefesh, not motlefesh
                ("وريني", "يلا نبدأ"),  # her وريني sounded bad
                ("براحة، اهدى", "بِرَّاحَة، اِهدا")],  # berra7a, ehda (not bra7a, ehdan)
}
KEEP_Q = ("مستقيم", "قِياسي", "رَقَم")  # said with ق; in the other words ق is said ء, the Egyptian way

SAMPLE_LINES = [
    "ضُمّ كوعَك لِجُوَّه شُوَيَّة",
    "افتكر، ضم كوعك لجوه شوية",
    "تسعة وتسعين",
]


def load_json(path):
    if os.path.exists(path):
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    return {}


def save_json(path, data, **kw):
    tmp = path + ".part"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, **kw)
    os.replace(tmp, path)


def load_pieces():
    if not os.path.exists("pubspec.yaml"):
        sys.exit("Run this from the project folder (the one with pubspec.yaml).")
    if not os.path.exists(PIECES):
        sys.exit("pieces.txt is missing. First run:  dart run tool/make_egyptian_voice.dart --list")
    pieces = {}
    with open(PIECES, encoding="utf-8") as f:
        for line in f:
            line = line.rstrip("\r\n")
            if "\t" in line:
                k, t = line.split("\t", 1)
                if k and t.strip():
                    pieces[k] = t
    return pieces


_own = None


def own_say_as():
    """app text -> what the voice says, from the yellow column you filled in"""
    global _own
    if _own is None:
        _own = {}
        if os.path.exists(SAY_AS_FILE):
            from openpyxl import load_workbook

            for row in load_workbook(SAY_AS_FILE, read_only=True).active.iter_rows(min_row=2, values_only=True):
                if len(row) >= 4 and row[1] and row[3] and str(row[3]).strip():
                    _own[str(row[1])] = str(row[3]).strip()
    return _own


def default_spoken(text, voice=None, tashkeel=False):
    for a, b in SAY_AS:
        text = text.replace(a, b)
    if tashkeel:
        return text
    text = TASHKEEL.sub("", text)
    # the user does not want "يلا يا بطل" said
    text = re.sub(r"،\s*يلا يا بطل!", "!", text)
    text = re.sub(r"يلا يا بطل،\s*", "", text).strip() or "يلا"
    num = number_say(text, voice)
    if num:
        return num
    # ة before another word is read with a stop: ه runs on
    text = re.sub(r"ة(?=\s)", "ه", text)
    for a, b in VOICE_FIX.get(voice, []) + PLAIN_FIX:
        text = re.sub(rf"(?<![ء-ي]){a}(?![ء-ي])", b, text)
    return " ".join(w if any(k in w for k in KEEP_Q) else w.replace("ق", "ء") for w in text.split(" "))


def spoken(text, voice=None, tashkeel=False):
    """what the voice reads for [text]: your own text, else the wording fixes in plain letters
    (with tashkeel and ء the voice sounded worse than plain text on the website)"""
    return own_say_as().get(text) or default_spoken(text, voice, tashkeel)


def api_key():
    key = os.environ.get("ELEVENLABS_API_KEY")
    if not key:
        sys.exit("Set the environment variable ELEVENLABS_API_KEY to your ElevenLabs API key first.")
    return key


def say(text, voice_id, model=MODEL):
    """MP3 bytes of [text] in the voice [voice_id]; waits and tries again when busy"""
    url = f"https://api.elevenlabs.io/v1/text-to-speech/{voice_id}?output_format={FORMAT}"
    # a fixed seed: the full recording says a line the way its approved sample did (best effort)
    body = json.dumps({"text": text, "model_id": model, "seed": SEED}).encode("utf-8")
    for attempt in range(5):
        req = urllib.request.Request(url, data=body, method="POST", headers={
            "xi-api-key": api_key(), "Content-Type": "application/json", "Accept": "audio/mpeg"})
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                return r.read()
        except urllib.error.HTTPError as e:
            msg = e.read().decode("utf-8", "replace")[:300]
            if e.code in (429, 500, 502, 503) and attempt < 4:
                time.sleep(3 * (attempt + 1))
                continue
            sys.exit(f"ElevenLabs said {e.code}: {msg}")
        except urllib.error.URLError as e:
            if attempt < 4:
                time.sleep(3 * (attempt + 1))
                continue
            sys.exit(f"No connection to ElevenLabs: {e.reason}")


def voices_from_args(flag):
    names = [a for a in sys.argv[sys.argv.index(flag) + 1:] if not a.startswith("--")]
    for n in names:
        if n not in VOICES:
            sys.exit(f"Unknown voice {n}. Voices: {', '.join(VOICES)}")
    return names or list(VOICES)


def write_list():
    """every line the app says -> tool/elevenlabs_say_as.xlsx, keeping what you already wrote"""
    from openpyxl import Workbook
    from openpyxl.styles import Alignment, Font, PatternFill

    pieces = load_pieces()
    mine = own_say_as()
    wb = Workbook()
    ws = wb.active
    ws.title = "Say as"
    ws.append(["Clip", "App text", "Voice says now", "Voice says (write here, empty = as now)"])
    for k, t in pieces.items():
        ws.append([k, t, default_spoken(t), mine.get(t, "")])
    for c in ws[1]:
        c.font = Font(name="Arial", bold=True, color="FFFFFF")
        c.fill = PatternFill("solid", fgColor="1F4E78")
    for row in ws.iter_rows(min_row=2):
        for c in row:
            c.font = Font(name="Arial", size=12)
            if c.column > 1:
                c.alignment = Alignment(horizontal="right", readingOrder=2, wrap_text=True)
        row[3].fill = PatternFill("solid", fgColor="FFF2CC")
    for col, w in zip("ABCD", (11, 50, 50, 50)):
        ws.column_dimensions[col].width = w
    ws.freeze_panes = "A2"
    wb.save(SAY_AS_FILE)
    print(f"{len(pieces)} lines -> {SAY_AS_FILE}  (write in the yellow column, then --record)")


def sample():
    os.makedirs(TRY_DIR, exist_ok=True)
    for name in os.listdir(TRY_DIR):
        if name.endswith(".mp3"):
            os.remove(os.path.join(TRY_DIR, name))
    for folder in voices_from_args("--sample"):
        for model in SAMPLE_MODELS:
            for tashkeel in (False,):
                for i, line in enumerate(SAMPLE_LINES, 1):
                    name = f"{folder}_{model.replace('eleven_', '')}_{'tashkeel' if tashkeel else 'plain'}_{i:02d}.mp3"
                    with open(os.path.join(TRY_DIR, name), "wb") as f:
                        f.write(say(spoken(line, folder, tashkeel), VOICES[folder], model))
                    print("made", name, flush=True)
    with open(os.path.join(TRY_DIR, "lines.txt"), "w", encoding="utf-8") as f:
        f.write("\n".join(f"{i:02d}  {spoken(l, None, True)}" for i, l in enumerate(SAMPLE_LINES, 1)) + "\n")
    print(f"Listen in {TRY_DIR}/ (lines.txt says what each number is).")


def record():
    pieces = load_pieces()
    recorded = load_json(RECORDED)
    manifest = load_json(MANIFEST)
    for folder in voices_from_args("--record"):
        out_dir = os.path.join(ASSET_DIR, folder)
        os.makedirs(out_dir, exist_ok=True)
        state = recorded.setdefault(folder, {})
        # a line is made again when the app text or what the voice says changed
        todo = [(k, t) for k, t in pieces.items()
                if state.get(k) != spoken(t, folder) or not os.path.exists(os.path.join(out_dir, k + ".mp3"))]
        chars = sum(len(spoken(t, folder)) for _, t in todo)
        print(f"{folder}: {len(pieces) - len(todo)} done, {len(todo)} to make (~{chars} characters)")
        for n, (k, t) in enumerate(todo, 1):
            with open(os.path.join(out_dir, k + ".mp3"), "wb") as f:
                f.write(say(spoken(t, folder), VOICES[folder]))
            state[k] = spoken(t, folder)
            if n % 20 == 0 or n == len(todo):
                save_json(RECORDED, recorded, ensure_ascii=False, indent=1)
                print(f"  {folder}: {n}/{len(todo)}", flush=True)
        # clips of lines the app no longer says
        for name in os.listdir(out_dir):
            if name.endswith(".mp3") and name[:-4] not in pieces:
                os.remove(os.path.join(out_dir, name))
        recorded[folder] = {k: v for k, v in state.items() if k in pieces}
        save_json(RECORDED, recorded, ensure_ascii=False, indent=1)
        manifest[folder] = sorted(pieces)
        save_json(MANIFEST, manifest, indent=1)
        print(f"{folder}: complete, now in the app (manifest.json)")
    print("Done. Build the app again to hear the voices.")


if __name__ == "__main__":
    if "--record" in sys.argv:
        record()
    elif "--list" in sys.argv:
        write_list()
    elif "--sample" in sys.argv:
        sample()
    else:
        print(__doc__)
