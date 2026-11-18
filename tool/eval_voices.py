"""Whisper listens to every Arabic clip of a voice and scores it against its line.

    python tool/eval_voices.py ziad yasmine        (any clip folders in assets/voice/ar_eg)

Writes tool/try/eval/<voice>.csv (clip, line, what Whisper heard, score 0-1, CER) and prints
the clips to listen to (lowest scores) plus the average per voice. Free, runs on the CPU.
Whisper itself mishears some Egyptian words (ضهرك -> دهرك), so a low score means "listen to
this one", not "this one is wrong".
"""

import csv
import difflib
import os
import re
import sys

ASSET_DIR = os.path.join("assets", "voice", "ar_eg")
OUT = os.path.join("tool", "try", "eval")
TASHKEEL = re.compile(r"[ً-ْٰ]")

UNITS = ["", "واحد", "اتنين", "تلاته", "اربعه", "خمسه", "سته", "سبعه", "تمانيه", "تسعه"]
TEENS = ["عشره", "حداشر", "اتناشر", "تلتاشر", "اربعتاشر", "خمستاشر", "ستاشر", "سبعتاشر", "تمنتاشر", "تسعتاشر"]
TENS = ["", "", "عشرين", "تلاتين", "اربعين", "خمسين", "ستين", "سبعين", "تمانين", "تسعين"]


def number_words(m):
    """Whisper writes numbers as digits ("33"): spell them the Egyptian way to compare"""
    n = int(m.group())
    if 100 <= n < 1000 and n % 10 == 0 and n // 100 > 0:  # "840" = Whisper's "8 40" (تمانية وأربعين)
        return UNITS[n // 100] + "و" + TENS[(n % 100) // 10]
    if n >= 100:
        return m.group()
    if n < 10:
        return UNITS[n] or "صفر"
    if n < 20:
        return TEENS[n - 10]
    return (UNITS[n % 10] + "و" if n % 10 else "") + TENS[n // 10]


def norm(t):
    """compare loosely: no tashkeel or punctuation; common spelling variants and ق/ء equal"""
    t = re.sub(r"\d+", number_words, TASHKEEL.sub("", t))
    for a, b in (("أ", "ا"), ("إ", "ا"), ("آ", "ا"), ("ى", "ي"), ("ة", "ه"), ("ؤ", "و"), ("ئ", "ي"),
                 ("ث", "ت"), ("ق", "ء"), ("ظ", "ض"), ("ذ", "د")):
        t = t.replace(a, b)
    return re.sub(r"[^ء-ي]", "", t)


def cer(heard, line):
    """character error rate (edit distance / length of the line)"""
    a, b = norm(line), norm(heard)
    d = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        prev, d[0] = d[0], i
        for j, cb in enumerate(b, 1):
            prev, d[j] = d[j], min(d[j] + 1, d[j - 1] + 1, prev + (ca != cb))
    return d[len(b)] / max(1, len(a))


def spoken_lines(voice):
    """what each clip was ASKED to say (the corrected wording, e.g. عدات, براحة اهدا), when known"""
    import json

    for name in ("recorded_elevenlabs.json", "recorded_gemini.json", "recorded_namaa.json", "recorded.json"):
        path = os.path.join(ASSET_DIR, name)
        if os.path.exists(path):
            data = json.load(open(path, encoding="utf-8")).get(voice)
            if data:
                return data
    return {}


def rescore(voice):
    """score again from the saved transcripts (no Whisper run)"""
    path = os.path.join(OUT, voice + ".csv")
    asked = spoken_lines(voice)
    rows = []
    for r in csv.DictReader(open(path, encoding="utf-8-sig")):
        ref = asked.get(r["clip"]) or r["line"]
        heard = r["whisper heard"]
        rows.append((r["clip"], ref, heard, round(difflib.SequenceMatcher(None, norm(heard), norm(ref)).ratio(), 3),
                     round(cer(heard, ref), 3)))
    write(voice, rows)


def write(voice, rows):
    with open(os.path.join(OUT, voice + ".csv"), "w", encoding="utf-8-sig", newline="") as f:
        w = csv.writer(f)
        w.writerow(["clip", "line", "whisper heard", "score", "CER"])
        w.writerows(sorted(rows, key=lambda r: r[3]))
    avg = sum(r[3] for r in rows) / max(1, len(rows))
    avg_cer = sum(r[4] for r in rows) / max(1, len(rows))
    low = [r for r in rows if r[3] < 0.7]
    print(f"{voice}: {len(rows)} clips, average score {avg:.2f}, average CER {avg_cer:.2f}, "
          f"{len(low)} to listen to (score < 0.7)", flush=True)


def main():
    voices = [a for a in sys.argv[1:] if not a.startswith("--")] or ["ziad", "yasmine"]
    if "--rescore" in sys.argv:
        for v in voices:
            rescore(v)
        return
    from faster_whisper import WhisperModel

    # all cores (the default used few and Windows slowed the job down in the background)
    model = WhisperModel("small", device="cpu", compute_type="int8", cpu_threads=os.cpu_count() or 4)
    pieces = {}
    with open(os.path.join(ASSET_DIR, "pieces.txt"), encoding="utf-8") as f:
        for line in f:
            if "\t" in line:
                k, t = line.rstrip("\r\n").split("\t", 1)
                pieces[k] = t
    os.makedirs(OUT, exist_ok=True)
    for voice in voices:
        rows = []
        asked = spoken_lines(voice)
        for n, (k, line) in enumerate(pieces.items(), 1):
            line = asked.get(k) or line
            path = os.path.join(ASSET_DIR, voice, k + ".mp3")
            if not os.path.exists(path):
                continue
            segs, _ = model.transcribe(path, language="ar", beam_size=2)
            heard = " ".join(s.text for s in segs).strip()
            score = difflib.SequenceMatcher(None, norm(heard), norm(line)).ratio()
            rows.append((k, line, heard, round(score, 3), round(cer(heard, line), 3)))
            if n % 25 == 0:
                print(f"  {voice}: {n}/{len(pieces)}", flush=True)
        write(voice, rows)


if __name__ == "__main__":
    main()
