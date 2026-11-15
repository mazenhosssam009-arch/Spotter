"""Makes the 8 sample coach lines on this PC (CPU, no CUDA needed) with the open-source
VoiceTut model, to judge it by ear. Run with the Python of tool/.venv:

    tool\\.venv\\Scripts\\python tool/try_local_voices.py voicetut            (Yasmin and Tareq)
    tool\\.venv\\Scripts\\python tool/try_local_voices.py voicetut Karim Sarah
    tool\\.venv\\Scripts\\python tool/try_local_voices.py clone              (Zephyr, Kore, Leda)

"clone" copies the voice of a Gemini female sample in tool/try/gemini (no training).
--ref=4-5 picks which lines of the sample are copied (default 6-8):
    tool\\.venv\\Scripts\\python tool/try_local_voices.py clone Zephyr --ref=2-8
    tool\\.venv\\Scripts\\python tool/try_local_voices.py page     (tool/try/local/compare.html)

Writes tool/try/local/<model>_<voice>/01.wav ... and lines.txt (what each number says,
and how long each line took to make).
"""

import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "try", "local")

# the same lines as tool/make_egyptian_voice_namaa.py --sample
LINES = [
    "اِرْفَع صِدْرَك، يَلّا يا بَطَل!",
    "مَتِخَلّيش رُكْبِتَك تِدْخُل لِجُوَّه",
    "تَلاتَة ريبْس",
    "اِرْجَع لِوَرا شُوَيَّة، عايِز أَشوفَك مِن راسَك لِرِجْلَك",
    "الراحَة خِلْصِت، جاهِز لِلسِّت اللي جاي؟",
    "سكوات، يَلّا نِبْدَأ",
    "بنش بريس، يَلّا نِبْدَأ",
    "سومو ديدليفت، يَلّا نِبْدَأ",
]


def write_list(folder, spoken, seconds):
    with open(os.path.join(folder, "lines.txt"), "w", encoding="utf-8") as f:
        for i, (line, s) in enumerate(zip(spoken, seconds), 1):
            f.write(f"{i:02d}  {s:5.1f} s  {line}\n")


def voicetut(speakers):
    import torch

    sys.path.insert(0, os.path.join(HERE, "voicetut"))
    from server import STYLE, say_as  # the spellings checked by ear for VoiceTut
    from voicetut_tts import VoiceTutTTS

    t = time.time()
    tts = VoiceTutTTS.from_pretrained("mohammedaly22/VoiceTut-TTS", device="cpu", dtype="float32")
    print(f"model loaded in {time.time() - t:.0f} s", flush=True)
    for speaker in speakers:
        folder = os.path.join(OUT, f"voicetut_{speaker.lower()}")
        os.makedirs(folder, exist_ok=True)
        spoken, seconds = [], []
        for i, line in enumerate(LINES, 1):
            text = say_as(line)
            t = time.time()
            with torch.inference_mode():
                torch.manual_seed(0)
                tts.synthesize(text, speaker=speaker, output=os.path.join(folder, f"{i:02d}.wav"), **STYLE)
            spoken.append(text)
            seconds.append(time.time() - t)
            print(f"  {speaker} {i:02d}  {seconds[-1]:.1f} s", flush=True)
        write_list(folder, spoken, seconds)
        print(folder)


GEMINI = os.path.join(HERE, "try", "gemini")
# what tool/try/gemini/<Voice>_female.wav says, line by line (see lines.txt there)
GEMINI_LINES = [
    "ارفع صدرك", "متخليش ركبتك تدخل لجوه", "تلاتة ريبس",
    "ارجع لورا شوية، عايز اشوفك من راسك لرجلك", "الراحة خلصت، جاهز للسِت اللي جاي؟",
    "فاضل اتنين! يلا!", "دي متحسبتش، انزل اكتر", "عاش! كمل كده!",
]
# the sample lines used as the voice to copy (1 = first line); 6-8 = none is a test LINE.
# Line 1 of each sample has ~15 s of extra speech before it, so it is never used.
REF_LINES = "6-8"


def gemini_ref(voice, folder, lines=REF_LINES):
    """cuts [lines] ("6-8") out of Gemini's sample of [voice] into ref.wav; (path, its text)"""
    import wave

    sys.path.insert(0, HERE)
    from audio_split import split

    with wave.open(os.path.join(GEMINI, f"{voice}_female.wav")) as w:
        rate, pcm = w.getframerate(), w.readframes(w.getnframes())
    clips = split(pcm, rate, len(GEMINI_LINES))
    if not clips:
        raise SystemExit(f"could not cut {voice}'s sample into {len(GEMINI_LINES)} lines")
    import array

    gap = b"\0\0" * (rate * 3 // 10)  # 0.3 s between the lines
    a = array.array("h")
    first, last = (int(x) for x in lines.split("-"))
    picked = range(first - 1, last)
    a.frombytes(gap.join(clips[i] for i in picked))
    # Gemini's samples are very loud and VoiceTut makes its line as loud as the sample, which
    # clipped (crackle): bring the sample down to RMS 0.05 of full scale
    rms = (sum(x * x for x in a) / len(a)) ** 0.5 / 32768
    a = array.array("h", (int(x * 0.05 / rms) for x in a))
    path = os.path.join(folder, "ref.wav")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(a.tobytes())
    # every line ends in a full stop (or its own ! ?) so the text shows the pauses too
    return path, " ".join(GEMINI_LINES[i] if GEMINI_LINES[i][-1] in "!؟?." else GEMINI_LINES[i] + "."
                          for i in picked)


def clone(voices, lines=REF_LINES):
    """VoiceTut speaking the test lines in the voice of a Gemini female sample (no training)"""
    import torch

    sys.path.insert(0, os.path.join(HERE, "voicetut"))
    from server import STYLE, say_as
    from voicetut_tts import VoiceTutTTS

    t = time.time()
    tts = VoiceTutTTS.from_pretrained("mohammedaly22/VoiceTut-TTS", device="cpu", dtype="float32")
    print(f"model loaded in {time.time() - t:.0f} s", flush=True)
    for voice in voices:
        folder = os.path.join(OUT, f"voicetut_clone_{voice.lower()}"
                              + ("" if lines == REF_LINES else f"_ref{lines}"))
        os.makedirs(folder, exist_ok=True)
        ref, ref_text = gemini_ref(voice, folder, lines)
        spoken, seconds = [], []
        for i, line in enumerate(LINES, 1):
            text = say_as(line)
            t = time.time()
            with torch.inference_mode():
                torch.manual_seed(0)
                tts.synthesize(text, ref_audio=ref, ref_text=ref_text,
                               output=os.path.join(folder, f"{i:02d}.wav"), **STYLE)
            spoken.append(text)
            seconds.append(time.time() - t)
            print(f"  {voice} {i:02d}  {seconds[-1]:.1f} s", flush=True)
        write_list(folder, spoken, seconds)
        print(folder)


def gemini_lines(voice):
    """Gemini's own sample of [voice] cut into tool/try/local/gemini_<voice>/02.wav ... 05.wav: the
    lines that are also test LINES 2-5 (line 1 has extra speech before it, 6-8 are other lines)"""
    import wave

    sys.path.insert(0, HERE)
    from audio_split import split

    src = os.path.join(GEMINI, f"{voice}_female.wav")
    if not os.path.exists(src):
        return
    with wave.open(src) as w:
        rate, pcm = w.getframerate(), w.readframes(w.getnframes())
    clips = split(pcm, rate, len(GEMINI_LINES)) or []
    folder = os.path.join(OUT, f"gemini_{voice.lower()}")
    os.makedirs(folder, exist_ok=True)
    for i in range(1, min(5, len(clips))):
        with wave.open(os.path.join(folder, f"{i + 1:02d}.wav"), "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(rate)
            w.writeframes(clips[i])


# the listening page: per voice, (column title, folder in tool/try/local, lines that copy the sample)
PAGE = [
    ("Zephyr", [("Gemini (the real voice)", "gemini_zephyr", ()),
                ("VoiceTut's own female voice (Yasmin)", "voicetut_yasmin", ()),
                ("VoiceTut copy, sample lines 6-8 (first try)", "voicetut_clone_zephyr", ()),
                ("VoiceTut copy, sample lines 2-8", "voicetut_clone_zephyr_ref2-8", (2, 3, 4, 5)),
                ("VoiceTut copy, sample lines 4-5", "voicetut_clone_zephyr_ref4-5", (4, 5))]),
    ("Kore", [("Gemini (the real voice)", "gemini_kore", ()),
              ("VoiceTut copy, sample lines 4-5", "voicetut_clone_kore_ref4-5", (4, 5))]),
    ("Leda", [("Gemini (the real voice)", "gemini_leda", ()),
              ("VoiceTut copy, sample lines 4-5", "voicetut_clone_leda_ref4-5", (4, 5))]),
]


def page():
    """tool/try/local/compare.html: every version of every test line side by side"""
    import html

    for voice, _ in PAGE:
        gemini_lines(voice)
    parts = []
    for voice, columns in PAGE:
        head = "".join(f"<th>{html.escape(t)}</th>" for t, _, _ in columns)
        rows = []
        for i, line in enumerate(LINES, 1):
            cells = []
            for _, folder, copied in columns:
                f = f"{folder}/{i:02d}.wav"
                if os.path.exists(os.path.join(OUT, f)):
                    note = '<div class="note">said in the sample: sounds closer than it really is</div>' \
                        if i in copied else ""
                    cells.append(f'<td><audio controls preload="none" src="{f}"></audio>{note}</td>')
                else:
                    cells.append('<td class="none">-</td>')
            rows.append(f'<tr><td class="line"><b>{i:02d}</b> <span dir="rtl">{html.escape(line)}</span></td>'
                        + "".join(cells) + "</tr>")
        parts.append(f'<h2>{voice}</h2><div class="wrap"><table><tr><th>Line</th>{head}</tr>'
                     + "".join(rows) + "</table></div>")
    with open(os.path.join(OUT, "compare.html"), "w", encoding="utf-8") as f:
        f.write(PAGE_HTML.replace("{body}", "".join(parts)))
    print(os.path.join(OUT, "compare.html"))


PAGE_HTML = """<!doctype html><html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>Voice Comparison</title>
<style>
:root{--bg:#fff;--fg:#1d1d1f;--muted:#6e6e73;--line:#e3e3e8;--head:#f5f5f7}
@media (prefers-color-scheme:dark){:root{--bg:#161618;--fg:#f2f2f4;--muted:#a1a1a6;--line:#2e2e33;--head:#202024}}
body{background:var(--bg);color:var(--fg);font:15px/1.4 system-ui,sans-serif;margin:0;padding:16px}
h1{font-size:20px;margin:0 0 4px}p{color:var(--muted);margin:0 0 16px}h2{font-size:17px;margin:24px 0 8px}
.wrap{overflow-x:auto}table{border-collapse:collapse}
th,td{border:1px solid var(--line);padding:6px 8px;vertical-align:top}
th{background:var(--head);font-weight:600;font-size:13px;text-align:left;max-width:190px}
td.line{min-width:220px}td.none{color:var(--muted);text-align:center}
audio{width:190px;height:34px}.note{color:var(--muted);font-size:12px;max-width:190px}
</style></head><body><h1>Voice comparison</h1>
<p>Every column except "Gemini" is made by VoiceTut. "-" = that version has no clip for this line.</p>
{body}</body></html>"""


if __name__ == "__main__":
    which = sys.argv[1] if len(sys.argv) > 1 else ""
    if which == "voicetut":
        voicetut(sys.argv[2:] or ["Yasmin", "Tareq"])
    elif which == "clone":
        args = sys.argv[2:]
        ref = next((a.split("=")[1] for a in args if a.startswith("--ref=")), REF_LINES)
        clone([a for a in args if not a.startswith("--")] or ["Zephyr", "Kore", "Leda"], ref)
    elif which == "page":
        page()
    else:
        print(__doc__)
