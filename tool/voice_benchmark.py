"""Benchmark report of every Egyptian voice: tool/try/eval/voice_benchmark.xlsx

    python tool/eval_voices.py ziad yasmine puck male female namaa_female namaa_male   (Whisper, slow)
    python tool/voice_benchmark.py                                                       (this report, fast)

Sheets: Benchmark (one row per voice), Dataset (the test set), Numbers (accuracy of 1-20 and
0-100 per voice), Confusion <voice> (true number vs the number Whisper heard), Clips <voice>.
Whisper (faster-whisper "small") is the listener: score = how close its transcript is to the
line (0-1), CER = character error rate. Whisper itself mishears some Egyptian words, so the
numbers compare voices fairly but are not absolute pronunciation accuracy.
"""

import csv
import difflib
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from eval_voices import ASSET_DIR, OUT, TENS, TEENS, UNITS, norm  # noqa: E402

VOICES = [  # folder, name, provider, kind, how it was made, human review (the user's listening)
    ("ziad", "Ziad (male)", "ElevenLabs multilingual v2", "commercial, paid",
     "text to speech, spellings fixed by ear over 7 rounds; numbers said in counting context",
     "every line reviewed; fixed lines re-recorded until approved"),
    ("yasmine", "Yasmine (female)", "ElevenLabs multilingual v2 / v3", "commercial, paid",
     "same as Ziad; 11, 13, 16 from v3", "every line reviewed; fixed lines re-recorded until approved"),
    ("puck", "Puck (male)", "Google Gemini TTS", "commercial, free tier",
     "Yahia's script, several lines per request, checked by Gemini", "liked best by the user"),
    ("male", "Shakir (male)", "Microsoft Edge neural TTS (ar-EG)", "free",
     "edge-tts, app text as written", "the first voice; sounds less natural"),
    ("female", "Salma (female)", "Microsoft Edge neural TTS (ar-EG)", "free",
     "edge-tts, app text as written", "the first voice; sounds less natural"),
    ("namaa_female", "NAMAA female", "NAMAA-Egyptian-TTS (open source, Chatterbox)", "open source, local CPU",
     "voice cloning from a reference clip, about 10 h on a CPU", "rejected: robotic / unclear lines"),
    ("namaa_male", "NAMAA male", "NAMAA-Egyptian-TTS (open source, Chatterbox)", "open source, local CPU",
     "voice cloning from a reference clip", "rejected: stuttering"),
]


def number_word(n):
    if n == 0:
        return "صفر"
    if n == 100:
        return "ميه"
    if n < 10:
        return UNITS[n]
    if n < 20:
        return TEENS[n - 10]
    return (UNITS[n % 10] + "و" if n % 10 else "") + TENS[n // 10]


NUMBER_KEYS = {norm(number_word(n)): n for n in range(0, 101)}


def heard_number(text):
    """the number Whisper heard (0-100), or None when it heard no number"""
    t = norm(text)
    if not t:
        return None
    best, score = None, 0.0
    for k, n in NUMBER_KEYS.items():
        r = difflib.SequenceMatcher(None, t, k).ratio()
        if r > score:
            best, score = n, r
    return best if score >= 0.6 else None


def load(voice):
    path = os.path.join(OUT, voice + ".csv")
    if not os.path.exists(path):
        return None
    return list(csv.DictReader(open(path, encoding="utf-8-sig")))


def main():
    from openpyxl import Workbook
    from openpyxl.chart import BarChart, Reference
    from openpyxl.styles import Alignment, Font, PatternFill
    from openpyxl.utils import get_column_letter

    pieces = {}
    with open(os.path.join(ASSET_DIR, "pieces.txt"), encoding="utf-8") as f:
        for line in f:
            if "\t" in line:
                k, t = line.rstrip("\r\n").split("\t", 1)
                pieces[k] = t
    number_clip = {}  # clip -> the number it says
    for k, t in pieces.items():
        n = NUMBER_KEYS.get(norm(t))
        if n is not None:
            number_clip[k] = n

    font, bold = Font(name="Arial"), Font(name="Arial", bold=True)
    head, fill = Font(name="Arial", bold=True, color="FFFFFF"), PatternFill("solid", fgColor="1F4E78")
    wrap = Alignment(vertical="top", wrap_text=True)
    wb = Workbook()

    def table(ws, header, rows, widths):
        ws.append(header)
        for c in ws[ws.max_row]:
            c.font, c.fill, c.alignment = head, fill, wrap
        for r in rows:
            ws.append(r)
            for c in ws[ws.max_row]:
                c.font, c.alignment = font, wrap
        for i, w in enumerate(widths, 1):
            ws.column_dimensions[get_column_letter(i)].width = w

    # ---- benchmark
    ws = wb.active
    ws.title = "Benchmark"
    rows, summary = [], {}
    for folder, name, provider, kind, how, human in VOICES:
        data = load(folder)
        if not data:
            continue
        sc = [float(r["score"]) for r in data]
        ce = [float(r["CER"]) for r in data]
        nums = [(number_clip[r["clip"]], heard_number(r["whisper heard"])) for r in data if r["clip"] in number_clip]
        n20 = [(t, h) for t, h in nums if 1 <= t <= 20]
        acc20 = sum(t == h for t, h in n20) / max(1, len(n20))
        acc100 = sum(t == h for t, h in nums) / max(1, len(nums))
        size = sum(os.path.getsize(os.path.join(ASSET_DIR, folder, f)) for f in os.listdir(os.path.join(ASSET_DIR, folder))
                   if f.endswith(".mp3")) / 1e6
        summary[folder] = (nums, name)
        rows.append([name, provider, kind, len(data), round(sum(sc) / len(sc), 3), round(sum(ce) / len(ce), 3),
                     round(sum(x >= 0.9 for x in sc) / len(sc), 3), round(sum(x >= 0.7 for x in sc) / len(sc), 3),
                     round(acc20, 3), round(acc100, 3), round(size, 1), how, human])
    table(ws, ["Voice", "Engine", "Type", "Clips tested", "Whisper score (avg, 0-1)", "CER (avg)",
               "Clips with score >= 0.9", "Clips with score >= 0.7", "Numbers 1-20 heard right",
               "Numbers 0-100 heard right", "Size (MB)", "How it was made", "Human review"],
          rows, [18, 28, 18, 9, 11, 9, 11, 11, 11, 11, 8, 40, 34])
    for r in range(2, ws.max_row + 1):
        for col in (5, 6):
            ws.cell(r, col).number_format = "0.00"
        for col in (7, 8, 9, 10):
            ws.cell(r, col).number_format = "0%"
    n = ws.max_row
    ws.append([])
    ws.append(["How to read it: Whisper (speech recognition, faster-whisper 'small', CPU) listened to every clip and "
               "wrote what it heard. Score = similarity of that text to the line the voice was asked to say "
               "(1 = identical). CER = character error rate (lower is better). Whisper also mishears some Egyptian "
               "words, so the values compare the voices with each other; they are not absolute accuracy."])
    ws.cell(ws.max_row, 1).font = font
    chart = BarChart()
    chart.title = "Whisper score per voice (higher = clearer)"
    chart.y_axis.title = "average score"
    chart.add_data(Reference(ws, min_col=5, min_row=1, max_row=n), titles_from_data=True)
    chart.set_categories(Reference(ws, min_col=1, min_row=2, max_row=n))
    chart.roundedCorners = False
    chart.legend = None
    chart.x_axis.delete = False
    chart.y_axis.delete = False
    chart.title.overlay = False
    chart.height, chart.width = 8, 18
    ws.add_chart(chart, f"A{ws.max_row + 2}")
    ws.freeze_panes = "B2"

    # ---- dataset
    ds = wb.create_sheet("Dataset")
    cats = {"numbers 0-100": sum(1 for k in pieces if k in number_clip)}
    cats["other lines (cues, warnings, rep results, praise, rest, setup)"] = len(pieces) - cats["numbers 0-100"]
    table(ds, ["Test set", "Lines"], [[k, v] for k, v in cats.items()] + [["total (assets/voice/ar_eg/pieces.txt)", len(pieces)]],
          [60, 10])
    ds.append([])
    for line in ["Every line is a piece the app plays as one clip (sentences are joined from pieces).",
                 "Reference text = what each voice was asked to say (its corrected spelling), from the voice's record file.",
                 "Listener: faster-whisper 'small', language Arabic, CPU int8.",
                 "Voices tested on the clips they have; new lines added later (talking to a woman) are not recorded yet."]:
        ds.append([line])
        ds.cell(ds.max_row, 1).font = font

    # ---- numbers
    ns = wb.create_sheet("Numbers")
    nrows = []
    for folder, (nums, name) in summary.items():
        n20 = [(t, h) for t, h in nums if 1 <= t <= 20]
        nrows.append([name, len(n20), sum(t == h for t, h in n20), round(sum(t == h for t, h in n20) / max(1, len(n20)), 3),
                      len(nums), sum(t == h for t, h in nums), round(sum(t == h for t, h in nums) / max(1, len(nums)), 3)])
    table(ns, ["Voice", "1-20 clips", "1-20 right", "1-20 accuracy", "0-100 clips", "0-100 right", "0-100 accuracy"],
          nrows, [18, 10, 10, 12, 10, 10, 12])
    for r in range(2, ns.max_row + 1):
        ns.cell(r, 4).number_format = ns.cell(r, 7).number_format = "0%"

    # ---- confusion matrices (1-20)
    for folder, (nums, name) in summary.items():
        cm = wb.create_sheet(f"Confusion {folder}"[:31])
        cm.append([f"{name}: numbers 1-20, rows = said, columns = heard by Whisper ('other' = another number or no number)"])
        cm.cell(1, 1).font = bold
        cols = list(range(1, 21)) + ["other"]
        cm.append(["said \\ heard", *cols])
        for c in cm[2]:
            c.font, c.fill = head, fill
        for t in range(1, 21):
            row = [0] * len(cols)
            for tt, h in nums:
                if tt == t:
                    row[(h - 1) if h is not None and 1 <= h <= 20 else 20] += 1
            cm.append([t, *row])
            for c in cm[cm.max_row]:
                c.font = font
            for i, v in enumerate(row, 2):
                if v:
                    cm.cell(cm.max_row, i).fill = PatternFill("solid", fgColor="C6EFCE" if i - 1 == t else "FFC7CE")
        for i in range(1, 23):
            cm.column_dimensions[get_column_letter(i)].width = 6 if i > 1 else 12

    # ---- clips
    for folder, _ in summary.items():
        cs = wb.create_sheet(f"Clips {folder}"[:31])
        data = load(folder)
        table(cs, ["clip", "line (asked)", "Whisper heard", "score", "CER"],
              [[r["clip"], r["line"], r["whisper heard"], float(r["score"]), float(r["CER"])] for r in data],
              [11, 50, 50, 8, 8])
        cs.freeze_panes = "A2"

    path = os.path.join(OUT, "voice_benchmark.xlsx")
    wb.save(path)
    print(path)
    for r in rows:
        print(f"  {r[0]:18} score {r[4]:.2f}  CER {r[5]:.2f}  >=0.7 {r[7]:.0%}  numbers 1-20 {r[8]:.0%}")


if __name__ == "__main__":
    main()
